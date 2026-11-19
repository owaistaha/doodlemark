import Foundation
import Observation
import PencilKit

/// One play of a lesson (TECH_SPEC "Lesson player"). It owns a `CanvasModel`
/// in lesson mode (Ink only, undo off) whose project has the lesson's
/// palette and Mirror, and walks the steps:
///
/// - Ink step: the kid draws a stroke. The RAW stroke (before "Smooth my
///   lines") is scored; the canvas shows the smoothed one if Smooth is on.
///   The result card offers Redo (the stroke goes) or Next (it's kept).
/// - Shape step: "Place it" drops the shape in. 3 stars.
/// - "Skip this step": 0 stars, and the target is drawn in (or the shape
///   placed) so the picture still comes out whole.
///
/// Leaving halfway saves the step, stars and kept strokes; the lesson card
/// then says "Continue · step X of Y" and the next session picks up there.
@MainActor @Observable
final class LessonSession: Identifiable {
    /// A scored stroke waiting for Redo or Next.
    struct Pending: Equatable {
        var score: StrokeScore
    }

    let lesson: Lesson
    let canvas: CanvasModel
    @ObservationIgnored let progress: LearnProgressStore

    /// The step being done (== steps.count once finished).
    private(set) var stepIndex = 0
    /// Stars for each finished step.
    private(set) var stars: [Int] = []
    private(set) var pending: Pending?
    /// The best score saved for this lesson, once finished.
    private(set) var bestAfterFinishing: Int?
    /// The best before this run (nil = never finished).
    let bestBefore: Int?
    /// Ink strokes that belong to finished steps; anything after them is pending.
    @ObservationIgnored private var keptCount = 0

    init(lesson: Lesson, progress: LearnProgressStore, resume: Bool = true, now: Date = Date()) {
        self.lesson = lesson
        self.progress = progress
        bestBefore = progress.progress(for: lesson.id)?.bestStars
        let project = Project(id: UUID(), name: lesson.title, createdAt: now, updatedAt: now,
                              palette: lesson.palette, shapes: [], text: nil,
                              symmetryOn: lesson.mirror, gridOn: false)
        canvas = CanvasModel(project: project)
        canvas.select(.ink)
        canvas.undoEnabled = false

        if resume, let saved = progress.progress(for: lesson.id)?.inProgress, Self.isUsable(saved, for: lesson),
           var ink = try? PKDrawing(data: saved.ink) {
            // A reload reports monoline as .pen (RISKS #11); Ink is monoline only.
            for index in ink.strokes.indices where ink.strokes[index].ink.inkType != .monoline {
                ink.strokes[index].ink = PKInk(.monoline, color: ink.strokes[index].ink.color)
            }
            stepIndex = saved.step
            stars = saved.stars
            canvas.ink = ink
            keptCount = ink.strokes.count
            for step in lesson.steps.prefix(saved.step) where step.kind == .shape {
                if let shape = step.shape { canvas.project.shapes.append(shape.logoShape()) }
            }
        } else if !resume {
            progress.saveResume(lesson, nil)
        }
        canvas.onNewInkStroke = { [weak self] raw in self?.scored(raw) }
        prepareStep()
    }

    private static func isUsable(_ resume: LessonResume, for lesson: Lesson) -> Bool {
        (1..<lesson.steps.count).contains(resume.step) && resume.stars.count == resume.step
            && resume.stars.allSatisfy { (0...3).contains($0) }
    }

    // MARK: Where we are

    var isFinished: Bool { stepIndex >= lesson.steps.count }
    var step: LessonStep? { isFinished ? nil : lesson.steps[stepIndex] }
    var totalStars: Int { stars.reduce(0, +) }

    // MARK: Actions

    /// "Place it" on a shape step: the shape goes in, 3 stars.
    func placeShape() {
        guard let step, step.kind == .shape, let shape = step.shape else { return }
        canvas.project.shapes.append(shape.logoShape())
        finishStep(stars: 3)
    }

    /// Redo: the scored stroke (and its mirrored copy) goes.
    func redo() {
        guard pending != nil else { return }
        dropPendingStrokes()
        pending = nil
        prepareStep()
    }

    /// Next: the scored stroke stays.
    func next() {
        guard let pending else { return }
        keptCount = canvas.ink.strokes.count
        self.pending = nil
        finishStep(stars: pending.score.stars)
    }

    /// "Skip this step": 0 stars, and the target is drawn in for them.
    func skip() {
        guard let step else { return }
        if pending != nil {
            dropPendingStrokes()
            pending = nil
        }
        switch step.kind {
        case .ink:
            var drawing = canvas.ink
            drawing.strokes += LessonInk.strokes(for: step, in: lesson, color: canvas.penColor)
            canvas.replaceInk(drawing)
            keptCount = drawing.strokes.count
        case .shape:
            if let shape = step.shape { canvas.project.shapes.append(shape.logoShape()) }
        }
        finishStep(stars: 0)
    }

    /// Leaving the player (or the app going to the background): remember
    /// where the kid got to. A finished lesson, or one not started, leaves nothing.
    func saveForLater() {
        guard !isFinished else { return }
        guard stepIndex > 0 else { return progress.saveResume(lesson, nil) }
        let ink = PKDrawing(strokes: Array(canvas.ink.strokes.prefix(keptCount)))
        progress.saveResume(lesson, LessonResume(step: stepIndex, stars: stars, ink: ink.dataRepresentation()))
    }

    // MARK: "Make it yours"

    /// The new project: named after the lesson, the lesson palette, Mirror
    /// on if the lesson used it, the kept strokes on Ink (mirrored copies
    /// included) and the shape steps as shapes. Grid off, no text yet.
    func makeItYours(now: Date = Date()) -> (project: Project, ink: PKDrawing) {
        let project = Project(id: UUID(), name: lesson.title, createdAt: now, updatedAt: now,
                              palette: lesson.palette,
                              shapes: canvas.project.shapes.map { LogoShape(id: UUID(), kind: $0.kind, center: $0.center,
                                                                           size: $0.size, rotation: $0.rotation, fill: $0.fill) },
                              text: nil, symmetryOn: lesson.mirror, gridOn: false)
        return (project, PKDrawing(strokes: Array(canvas.ink.strokes.prefix(keptCount))))
    }

    // MARK: Inside

    /// A new stroke on Ink, as drawn. Mirror lessons score the half that
    /// fits best, so a kid who drew the right side isn't told off.
    private func scored(_ raw: PKStroke) {
        guard let step, step.kind == .ink, let target = step.points, pending == nil else { return }
        var score = StrokeScorer.score(StrokeScorer.points(of: raw), target: target)
        if lesson.mirror {
            let other = StrokeScorer.score(StrokeScorer.points(of: Symmetry.mirrored(raw)), target: target)
            if other.stars > score.stars { score = other }
        }
        pending = Pending(score: score)
        canvas.inkLocked = true
    }

    private func dropPendingStrokes() {
        guard canvas.ink.strokes.count > keptCount else { return }
        canvas.replaceInk(PKDrawing(strokes: Array(canvas.ink.strokes.prefix(keptCount))))
    }

    private func finishStep(stars earned: Int) {
        stars.append(earned)
        stepIndex += 1
        if isFinished {
            bestAfterFinishing = progress.recordFinished(lesson, stars: totalStars)
        } else {
            saveForLater()
        }
        prepareStep()
    }

    /// The canvas for the current step: its line size, the ghost, and
    /// drawing allowed only on an ink step with no result card up.
    private func prepareStep() {
        if let width = step?.width { canvas.lineSize = width }
        canvas.lessonGhost = isFinished ? nil : LessonGhost(lesson: lesson, step: stepIndex)
        canvas.inkLocked = step?.kind != .ink || pending != nil
    }
}
