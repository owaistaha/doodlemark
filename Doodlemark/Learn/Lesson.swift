import CoreGraphics
import Foundation

/// A bundled trace lesson (TECH_SPEC "Lesson format"), loaded from
/// `Resources/Lessons/<id>.json`. All coordinates are in the 1024 canvas
/// space, the same as projects; the player maps them through the canvas
/// transform, never by hand.
struct Lesson: Codable, Identifiable, Equatable, Sendable {
    var id: String
    /// "Rocket in 5 strokes".
    var title: String
    /// For the complete screen: "Rocket" → "Rocket done!".
    var shortName: String
    /// What it teaches, for the card: "learn curves and Mirror".
    var teaches: String
    /// For the complete screen: "You learned <learned>."
    var learned: String
    /// 1 = Easy, 2 = Medium. Lessons are listed easy → harder.
    var level: Int
    var palette: [HexColor]
    /// Mirror is on for the whole lesson; targets only cover the left half
    /// (x ≤ 512) and Mirror draws the rest.
    var mirror: Bool
    var steps: [LessonStep]

    var levelName: String { level <= 1 ? "Easy" : "Medium" }

    /// The steps the user traces (the ones that get stars).
    var inkSteps: [LessonStep] { steps.filter { $0.kind == .ink } }

    /// 3 stars for every step: a traced line gets 0–3, a shape step gets 3
    /// when it's placed (0 if skipped). "Rocket in 5 strokes" → 15.
    var maxStars: Int { steps.count * 3 }
}

struct LessonStep: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Traced with the monoline pen and scored.
        case ink
        /// Places a shape; the user taps to confirm it (every step is interactive).
        case shape
    }

    /// Short label: "The fins".
    var name: String
    /// The big line: "Give it fins so it looks like it's flying".
    var tip: String
    /// How to draw it: "Start on the blue dot and follow the dashed line…".
    var how: String
    var kind: Kind
    /// Ink steps: the target polyline, `[[x, y], …]` in canvas space,
    /// starting at the start dot.
    var points: [CGPoint]?
    /// Ink steps: the line size (the line's real thickness on the canvas).
    var width: CGFloat?
    /// Shape steps: the shape to place.
    var shape: LessonShape?
}

/// A shape step's shape, in `LogoShape` terms (fill is a palette slot).
struct LessonShape: Codable, Equatable, Sendable {
    var kind: LogoShape.Kind
    var center: CGPoint
    var size: CGFloat
    var rotation: Double = 0
    var fill: PaletteSlot

    func logoShape(id: UUID = UUID()) -> LogoShape {
        LogoShape(id: id, kind: kind, center: center, size: size, rotation: rotation, fill: fill)
    }
}
