import CoreGraphics
import Foundation

/// The five bundled lessons, easy → harder (PRD: any lesson can be opened).
enum LessonLibrary {
    /// File names in `Resources/Lessons/`, in list order.
    static let ids = ["rocket", "bolt-shield", "star-club", "cat-badge", "moon-cafe"]

    enum Failure: Error, Equatable {
        case missing(String)
        case unreadable(String, String)
        case invalid(String, String)
    }

    /// Every lesson, in order. A lesson that fails to load is left out (and
    /// `LessonLoaderTests` fails), so a bad file never takes the tab down.
    static func all(bundle: Bundle = .main) -> [Lesson] {
        ids.compactMap { try? load($0, bundle: bundle) }
    }

    static func load(_ id: String, bundle: Bundle = .main) throws -> Lesson {
        guard let url = bundle.url(forResource: id, withExtension: "json") else { throw Failure.missing(id) }
        let lesson: Lesson
        do {
            lesson = try JSONDecoder().decode(Lesson.self, from: Data(contentsOf: url))
        } catch {
            throw Failure.unreadable(id, "\(error)")
        }
        try validate(lesson)
        return lesson
    }

    /// The rules a lesson file must follow.
    static func validate(_ lesson: Lesson) throws {
        func fail(_ why: String) throws -> Never { throw Failure.invalid(lesson.id, why) }
        let canvas = 0...CanvasViewport.canvasSide
        if lesson.palette.count != 3 { try fail("palette needs 3 colors") }
        if lesson.shortName.isEmpty || lesson.learned.isEmpty { try fail("needs a short name and what it teaches") }
        if !(4...8).contains(lesson.steps.count) { try fail("\(lesson.steps.count) steps, PRD wants 4–8") }
        for (index, step) in lesson.steps.enumerated() {
            let label = "step \(index + 1)"
            if step.name.isEmpty || step.tip.isEmpty || step.how.isEmpty { try fail("\(label) needs a name, tip and how") }
            switch step.kind {
            case .ink:
                guard let points = step.points, points.count >= 2 else { try fail("\(label): ink needs 2+ points") }
                guard let width = step.width, width > 0 else { try fail("\(label): ink needs a width") }
                for p in points where !canvas.contains(p.x) || !canvas.contains(p.y) {
                    try fail("\(label): \(p) is outside the canvas")
                }
                if lesson.mirror, points.contains(where: { $0.x > Symmetry.axisX + 0.5 }) {
                    try fail("\(label): a Mirror lesson only draws the left half")
                }
                if StrokeScorer.length(of: points) < 40 { try fail("\(label): too short to trace") }
            case .shape:
                guard let shape = step.shape else { try fail("\(label): shape step needs a shape") }
                if !canvas.contains(shape.center.x) || !canvas.contains(shape.center.y) || shape.size <= 0 {
                    try fail("\(label): shape outside the canvas")
                }
            }
        }
        if lesson.inkSteps.isEmpty { try fail("nothing to trace") }
    }
}
