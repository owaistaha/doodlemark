import PencilKit
import XCTest
@testable import Doodlemark

/// Learn progress (`Documents/learn.json`) and the lesson player's logic
/// (`LessonSession`), driven the way the canvas drives it: a new stroke
/// lands on Ink through `CanvasModel.inkDidChange`.
@MainActor
final class LearnProgressTests: XCTestCase {
    private var folder: URL!
    private var savedSmooth: Bool!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "LearnTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        savedSmooth = UserDefaults.standard.object(forKey: CanvasModel.smoothLinesKey) as? Bool ?? true
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.set(savedSmooth, forKey: CanvasModel.smoothLinesKey)
    }

    private var url: URL { folder.appending(path: "learn.json") }
    private func lesson(_ id: String) throws -> Lesson { try LessonLibrary.load(id) }

    /// The kid draws `stroke` on Ink.
    private func draw(_ session: LessonSession, _ stroke: PKStroke) {
        var drawing = session.canvas.ink
        drawing.strokes.append(stroke)
        _ = session.canvas.inkDidChange(drawing)
    }

    /// A clean trace of the current step's target.
    private func traceCurrentStep(_ session: LessonSession) {
        let step = session.step!
        draw(session, LessonInk.stroke(along: step.points!, size: step.width!, color: session.canvas.penColor))
    }

    /// Plays every step perfectly (Place it, or a clean trace + Next).
    private func playPerfectly(_ session: LessonSession) {
        while let step = session.step {
            if step.kind == .shape {
                session.placeShape()
            } else {
                traceCurrentStep(session)
                XCTAssertEqual(session.pending?.score.stars, 3, "\(step.name): \(String(describing: session.pending))")
                session.next()
            }
        }
    }

    // MARK: Store

    func testProgressRoundTripsThroughLearnJSON() throws {
        let store = LearnProgressStore(url: url)
        XCTAssertEqual(store.totalStars, 0)
        let rocket = try lesson("rocket"), shield = try lesson("bolt-shield")
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        XCTAssertEqual(store.recordFinished(rocket, stars: 12, at: date), 12)
        let resume = LessonResume(step: 2, stars: [3, 1], ink: PKDrawing().dataRepresentation())
        store.saveResume(shield, resume)

        let again = LearnProgressStore(url: url)
        XCTAssertEqual(again.lessons, store.lessons)
        XCTAssertEqual(again.progress(for: "rocket"), LessonProgress(bestStars: 12, maxStars: 15, completedAt: date))
        XCTAssertEqual(again.progress(for: "bolt-shield")?.inProgress, resume)
        XCTAssertNil(again.progress(for: "bolt-shield")?.bestStars)
        XCTAssertEqual(again.totalStars, 12)

        // The TECH_SPEC file shape.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
        XCTAssertEqual(json["rocket"]?["bestStars"] as? Int, 12)
        XCTAssertEqual(json["rocket"]?["maxStars"] as? Int, 15)
        XCTAssertNotNil(json["rocket"]?["completedAt"] as? String)

        // A damaged file is an empty start, not a crash.
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(LearnProgressStore(url: url).lessons, [:])
    }

    func testTheBestScoreNeverGoesDown() throws {
        let store = LearnProgressStore(url: url)
        let rocket = try lesson("rocket")
        let first = Date(timeIntervalSinceReferenceDate: 1000)
        store.recordFinished(rocket, stars: 12, at: first)
        XCTAssertEqual(store.recordFinished(rocket, stars: 9, at: Date(timeIntervalSinceReferenceDate: 2000)), 12)
        XCTAssertEqual(store.progress(for: "rocket")?.completedAt, first, "a worse run doesn't touch the best")
        XCTAssertEqual(store.recordFinished(rocket, stars: 14), 14)
        XCTAssertEqual(LearnProgressStore(url: url).progress(for: "rocket")?.bestStars, 14)

        // Through the player: skipping everything is 0 stars, and the best stays.
        let session = LessonSession(lesson: rocket, progress: store, resume: false)
        while session.step != nil { session.skip() }
        XCTAssertEqual(session.totalStars, 0)
        XCTAssertEqual(session.bestAfterFinishing, 14)
        XCTAssertEqual(store.progress(for: "rocket")?.bestStars, 14)
    }

    // MARK: Player

    func testAPerfectRocketIsFifteenStars() throws {
        let store = LearnProgressStore(url: url)
        let session = LessonSession(lesson: try lesson("rocket"), progress: store)
        XCTAssertEqual(session.lesson.maxStars, 15, "5 steps × 3")
        XCTAssertTrue(session.canvas.mirrorOn, "Mirror lesson")
        XCTAssertFalse(session.canvas.undoEnabled)
        XCTAssertTrue(session.canvas.inkLocked, "step 1 is a shape: Place it, no drawing")
        playPerfectly(session)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.stars, [3, 3, 3, 3, 3])
        XCTAssertEqual(session.totalStars, 15)
        XCTAssertEqual(store.progress(for: "rocket")?.bestStars, 15)
        XCTAssertNil(store.progress(for: "rocket")?.inProgress)
        XCTAssertNil(session.canvas.lessonGhost)
        XCTAssertEqual(session.canvas.ink.strokes.count, 8, "4 traced steps, each mirrored")
        XCTAssertEqual(session.canvas.project.shapes.count, 1)
    }

    /// Score the RAW stroke; the canvas shows the smoothed one (Smooth on)
    /// plus its mirrored copy. Drawing waits while the result card is up.
    func testTheRawStrokeIsScoredAndTheSmoothedOneShown() throws {
        let session = LessonSession(lesson: try lesson("rocket"), progress: LearnProgressStore(url: url))
        session.canvas.smoothLines = true
        session.placeShape()
        XCTAssertFalse(session.canvas.inkLocked)
        let target = session.step!.points!
        // A finger-like shaky trace along the body (the calibration's finger).
        let raw = Fixtures.monolineStroke(LessonLoaderTests.fingerTrace(target, shake: 2, drift: 4, seed: 3), width: 10)
        draw(session, raw)

        let pending = try XCTUnwrap(session.pending)
        XCTAssertEqual(pending.score, StrokeScorer.score(StrokeScorer.points(of: raw), target: target))
        XCTAssertEqual(session.canvas.ink.strokes.count, 2, "the stroke and its mirrored copy")
        let shown = session.canvas.ink.strokes[0]
        XCTAssertNotEqual(shown.path.map(\.location), raw.path.map(\.location), "smoothed on screen")
        XCTAssertLessThan(StrokeScorer.score(StrokeScorer.points(of: shown), target: target).wobble, pending.score.wobble,
                          "the smoothed line would hide wobble, so it isn't what's scored")
        XCTAssertTrue(session.canvas.inkLocked, "no drawing while the result card is up")
    }

    func testRedoTakesTheStrokeAwayAndSkipDrawsTheTargetIn() throws {
        let store = LearnProgressStore(url: url)
        let session = LessonSession(lesson: try lesson("bolt-shield"), progress: store)
        XCTAssertFalse(session.canvas.mirrorOn)

        // Way off the line: 0 stars, said kindly.
        draw(session, Fixtures.monolineStroke([CGPoint(x: 100, y: 950), CGPoint(x: 400, y: 990)], width: 10))
        XCTAssertEqual(session.pending?.score.stars, 0)
        XCTAssertEqual(session.pending?.score.feedback.title, "Almost! Try once more")
        session.redo()
        XCTAssertNil(session.pending)
        XCTAssertTrue(session.canvas.ink.strokes.isEmpty)
        XCTAssertFalse(session.canvas.inkLocked)
        XCTAssertEqual(session.stepIndex, 0)

        // Skip: 0 stars, the target drawn in, on to step 2.
        session.skip()
        XCTAssertEqual(session.stars, [0])
        XCTAssertEqual(session.stepIndex, 1)
        let drawnIn = try XCTUnwrap(session.canvas.ink.strokes.first)
        let target = session.lesson.steps[0].points!
        XCTAssertEqual(StrokeScorer.score(StrokeScorer.points(of: drawnIn), target: target).stars, 3, "it's the target")
        XCTAssertEqual(LineSize.size(forStoredWidth: drawnIn.path[0].size.width), session.lesson.steps[0].width!, accuracy: 0.01)

        // Skipping with a result card up drops that stroke first.
        traceCurrentStep(session)
        XCTAssertNotNil(session.pending)
        session.skip()
        XCTAssertEqual(session.canvas.ink.strokes.count, 2, "step 1's drawn-in line and step 2's, not the pending one too")
        XCTAssertEqual(session.stars, [0, 0])
    }

    /// Leaving halfway saves the step, stars and kept strokes; the next
    /// session picks up right there (a pending stroke isn't kept).
    func testALessonResumesWhereItWasLeft() throws {
        let store = LearnProgressStore(url: url)
        let rocket = try lesson("rocket")
        let first = LessonSession(lesson: rocket, progress: store)
        first.placeShape()
        traceCurrentStep(first)
        first.next()                                   // body: 3 stars
        traceCurrentStep(first)                        // base: scored, not kept yet
        first.saveForLater()

        let saved = try XCTUnwrap(LearnProgressStore(url: url).progress(for: "rocket")?.inProgress)
        XCTAssertEqual(saved.step, 2)
        XCTAssertEqual(saved.stars, [3, 3])

        let reopened = LearnProgressStore(url: url)            // as after a relaunch
        let again = LessonSession(lesson: rocket, progress: reopened)
        XCTAssertEqual(again.stepIndex, 2)
        XCTAssertEqual(again.stars, [3, 3])
        XCTAssertNil(again.pending)
        XCTAssertEqual(again.canvas.ink.strokes.count, 2, "the body and its mirrored copy")
        XCTAssertEqual(again.canvas.ink.strokes.map(\.ink.inkType), [.monoline, .monoline], "Ink stays monoline (RISKS #11)")
        XCTAssertEqual(again.canvas.project.shapes.count, 1, "the badge is back")
        XCTAssertEqual(again.canvas.lessonGhost, LessonGhost(lesson: rocket, step: 2))
        XCTAssertFalse(again.canvas.inkLocked)
        XCTAssertEqual(again.canvas.lineSize, rocket.steps[2].width)

        playPerfectly(again)
        XCTAssertEqual(again.totalStars, 15)
        XCTAssertNil(reopened.progress(for: "rocket")?.inProgress, "nothing to continue once finished")

        // "Try for 15 stars" starts over and forgets a halfway save.
        reopened.saveResume(rocket, saved)
        let fresh = LessonSession(lesson: rocket, progress: reopened, resume: false)
        XCTAssertEqual(fresh.stepIndex, 0)
        XCTAssertNil(reopened.progress(for: "rocket")?.inProgress)
        XCTAssertEqual(reopened.progress(for: "rocket")?.bestStars, 15)

        // A save that doesn't fit the lesson is ignored, not trusted.
        reopened.saveResume(rocket, LessonResume(step: 9, stars: [3], ink: Data()))
        XCTAssertEqual(LessonSession(lesson: rocket, progress: reopened).stepIndex, 0)
    }

    /// "Make it yours": a new project with the lesson's name, palette and
    /// Mirror, the kept strokes on Ink and the shape steps as shapes. It
    /// saves, loads back the same, and exports SVG + PNG.
    func testMakeItYoursCreatesAProjectThatSavesAndExports() throws {
        let rocket = try lesson("rocket")
        let session = LessonSession(lesson: rocket, progress: LearnProgressStore(url: url))
        playPerfectly(session)
        let made = session.makeItYours()
        XCTAssertEqual(made.project.name, "Rocket in 5 strokes")
        XCTAssertEqual(made.project.palette, rocket.palette)
        XCTAssertTrue(made.project.symmetryOn)
        XCTAssertFalse(made.project.gridOn)
        XCTAssertNil(made.project.text)
        XCTAssertEqual(made.project.shapes.map(\.kind), [.circle])
        XCTAssertEqual(made.project.shapes.first?.size, rocket.steps[0].shape?.size)
        XCTAssertEqual(made.ink.strokes.count, 8)
        XCTAssertNotEqual(made.project.shapes.first?.id, session.canvas.project.shapes.first?.id, "its own shapes")

        let store = ProjectStore(root: folder.appending(path: "Projects"))
        let model = CanvasModel(project: made.project, ink: made.ink)
        let autosaver = ProjectAutosaver(model: model, store: store, isOnDisk: false)
        autosaver.saveNow()
        XCTAssertEqual(autosaver.saveCount, 0, "nothing changed: a normal save writes nothing")
        autosaver.saveNow(evenIfUnchanged: true)
        XCTAssertEqual(autosaver.saveCount, 1, "Make it yours writes it right away")
        let loaded = try store.load(made.project.id)
        XCTAssertEqual(loaded.ink.strokes.map { $0.path.map(\.location) }, made.ink.strokes.map { $0.path.map(\.location) })
        XCTAssertEqual(loaded.ink.strokes.map(\.transform), made.ink.strokes.map(\.transform), "mirrored copies kept")
        XCTAssertEqual(loaded.project.shapes, made.project.shapes)
        XCTAssertEqual(loaded.project.palette, rocket.palette)
        XCTAssertTrue(loaded.project.symmetryOn)

        let svg = try SVGExporter.svg(project: loaded.project, ink: loaded.ink)
        XCTAssertEqual(svg.components(separatedBy: "<path").count - 1, 9, "1 circle + 8 ink lines")
        let files = try ExportFiles.write(project: loaded.project, ink: loaded.ink,
                                          options: ExportOptions(fileName: ""), in: folder)
        XCTAssertEqual(files.map(\.lastPathComponent), ["rocket-in-5-strokes.svg", "rocket-in-5-strokes.png"])
        for file in files { XCTAssertGreaterThan(try Data(contentsOf: file).count, 500) }
    }

    func testTheGhostShowsTheCurrentStepAndWhatsToCome() throws {
        let rocket = try lesson("rocket")
        let ghost = LessonGhost(lesson: rocket, step: 3)            // the fins
        let fins = rocket.steps[3].points!
        XCTAssertEqual(ghost.current, [.line(fins), .line(LessonInk.mirrored(fins))], "Mirror: both fins dashed")
        XCTAssertEqual(ghost.start, fins[0])
        XCTAssertEqual(ghost.upcoming.count, 2, "the window and its mirror")
        let badge = LessonGhost(lesson: rocket, step: 0)
        XCTAssertEqual(badge.current, [.shape(rocket.steps[0].shape!)])
        XCTAssertNil(badge.start, "no start dot on a shape step")
        XCTAssertEqual(LessonInk.mirrored([CGPoint(x: 400, y: 10)]), [CGPoint(x: 624, y: 10)])
    }
}
