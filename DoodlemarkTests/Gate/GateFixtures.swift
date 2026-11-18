import PencilKit
import UIKit
@testable import Doodlemark

/// Code-built gate cases. Strokes get dense control points (one every 4 pt),
/// like real finger or Pencil input, so PencilKit's curve follows the
/// polyline closely, sharp corners included.
enum GateFixtures {
    static let pencilBlue = HexColor(red: 0x2F, green: 0x5B, blue: 0xFF)

    // MARK: Strokes

    /// Underline-style short stroke. The negative controls change this one.
    static let underline = stroke([CGPoint(x: 300, y: 960), CGPoint(x: 724, y: 960)], width: 8)

    static let diagonal = stroke([CGPoint(x: 150, y: 180), CGPoint(x: 870, y: 840)], width: 8)

    /// A three-quarter circle ("circle-ish curve").
    static let arc = stroke(
        stride(from: -150.0, through: 120.0, by: 2.0).map { (degrees: Double) -> CGPoint in
            let a: Double = degrees * Double.pi / 180
            return CGPoint(x: 512 + 300 * cos(a), y: 440 + 300 * sin(a))
        },
        width: 12)

    /// Sharp corners: the hardest case for RDP + Catmull-Rom.
    static let zigzag = stroke(
        [CGPoint(x: 120, y: 640), CGPoint(x: 260, y: 300), CGPoint(x: 400, y: 640),
         CGPoint(x: 540, y: 300), CGPoint(x: 680, y: 640), CGPoint(x: 820, y: 300),
         CGPoint(x: 900, y: 520)],
        width: 10)

    /// A spiral with a deterministic ±1.5 pt wobble, like a shaky finger.
    static let wobbly: PKStroke = {
        let points: [CGPoint] = stride(from: 0.0, through: 5.5 * Double.pi, by: 0.02).map { (t: Double) -> CGPoint in
            let jitter: Double = 1.5 * sin(t * 37) + 0.8 * sin(t * 91 + 1)
            let radius: Double = 40 + 22 * t + jitter
            return CGPoint(x: 512 + radius * cos(t), y: 512 + radius * sin(t))
        }
        return stroke(points, width: 8, densify: false)
    }()

    /// A curve with a non-identity transform (rotate + scale 1.5 + move), like
    /// a stroke moved with lasso. The export must apply it, width included.
    static let transformed = stroke(
        stride(from: 0.0, through: 2 * Double.pi, by: 0.05).map { (t: Double) -> CGPoint in
            let x: Double = 100 * cos(t) + 40 * cos(3 * t)
            let y: Double = 100 * sin(t) - 40 * sin(3 * t)
            return CGPoint(x: x, y: y)
        },
        width: 8,
        transform: CGAffineTransform(translationX: 520, y: 500).rotated(by: 0.5).scaledBy(x: 1.5, y: 1.5))

    /// Taps: single-point strokes of different widths, plus a 0.3 pt micro-drag.
    static let dots: [PKStroke] = [
        Fixtures.monolineStroke([CGPoint(x: 200, y: 200)], width: 6),
        Fixtures.monolineStroke([CGPoint(x: 400, y: 300)], width: 12),
        Fixtures.monolineStroke([CGPoint(x: 600, y: 500)], width: 24),
        Fixtures.monolineStroke([CGPoint(x: 800, y: 700)], width: 40),
        Fixtures.monolineStroke([CGPoint(x: 300, y: 800), CGPoint(x: 300.3, y: 800)], width: 16),
    ]

    // MARK: Scenes

    static let scenes: [(name: String, scene: GateScene)] = [
        ("line", GateScene(ink: PKDrawing(strokes: [diagonal]))),
        ("curve", GateScene(ink: PKDrawing(strokes: [arc]))),
        ("zigzag", GateScene(ink: PKDrawing(strokes: [zigzag]))),
        ("wobbly", GateScene(ink: PKDrawing(strokes: [wobbly]))),
        ("transformed", GateScene(ink: PKDrawing(strokes: [transformed]))),
        ("dots", GateScene(ink: PKDrawing(strokes: dots))),
        ("shapes", GateScene(shapes: allShapes, palette: allShapesPalette)),
        ("text", GateScene(text: Fixtures.pizzaText(center: CGPoint(x: 512, y: 512)))),
        ("text-rotated", GateScene(text: Fixtures.pizzaText(center: CGPoint(x: 512, y: 512), rotation: -0.35))),
        ("logo", logo),
        ("smoothed-mirrored", smoothedMirrored),
    ] + fontScenes

    /// "Pizza Rocket" in every bundled logo font, turned and letter-spaced;
    /// every other font in ALL CAPS.
    static var fontScenes: [(name: String, scene: GateScene)] {
        LogoFonts.all.enumerated().map { index, font in
            ("text-\(font.postScriptName)",
             GateScene(text: LogoText(string: "Pizza Rocket", fontName: font.postScriptName,
                                      center: CGPoint(x: 512, y: 512), pointSize: 90, rotation: -0.3,
                                      fill: .second, tracking: 60, allCaps: index.isMultiple(of: 2) == false)))
        }
    }

    /// "Smooth my lines" + Mirror: the smoothed wobbly spiral and its mirror
    /// copy (a flip in `transform`, determinant −1). Both must export exactly.
    static var smoothedMirrored: GateScene {
        let smoothed = StrokeSmoother.smoothed(wobbly)
        return GateScene(ink: PKDrawing(strokes: [smoothed, Symmetry.mirrored(smoothed)]))
    }

    /// Three slots for four shapes: the square and the star share blue.
    static let allShapesPalette = [Fixtures.tangerine, pencilBlue, Fixtures.butter]

    static var allShapes: [LogoShape] {
        [
            LogoShape(id: UUID(), kind: .circle, center: CGPoint(x: 280, y: 280), size: 300, rotation: 0, fill: .first),
            LogoShape(id: UUID(), kind: .roundedSquare, center: CGPoint(x: 740, y: 280), size: 280, rotation: 0.3, fill: .second),
            LogoShape(id: UUID(), kind: .triangle, center: CGPoint(x: 280, y: 740), size: 300, rotation: -0.2, fill: .third),
            LogoShape(id: UUID(), kind: .star, center: CGPoint(x: 740, y: 740), size: 320, rotation: 0.15, fill: .second),
        ]
    }

    /// The TECH_SPEC gate logo: a line, a circle-ish curve, a zig-zag, a circle
    /// shape and "Pizza", plus the short underline the negative controls change.
    static var logo: GateScene {
        GateScene(
            shapes: [LogoShape(id: UUID(), kind: .circle, center: CGPoint(x: 512, y: 440),
                               size: 520, rotation: 0, fill: .first)],
            ink: PKDrawing(strokes: [arc, zigzag, diagonal, underline]),
            text: Fixtures.pizzaText(center: CGPoint(x: 512, y: 880)))
    }

    // MARK: Negative controls (applied to the exported side only)

    static var logoWithShiftedUnderline: GateScene {
        var scene = logo
        let shift = GateConfig.negativeControlShift
        scene.ink.strokes[3].transform = scene.ink.strokes[3].transform.translatedBy(x: 0, y: shift)
        return scene
    }

    static var logoWithDroppedUnderline: GateScene {
        var scene = logo
        scene.ink.strokes.remove(at: 3)
        return scene
    }

    static var logoWithRecoloredUnderline: GateScene {
        var scene = logo
        scene.ink.strokes[3].ink = PKInk(.monoline, color: UIColor(cgColor: Fixtures.tangerine.cgColor))
        return scene
    }

    // MARK: Helpers

    static func stroke(
        _ polyline: [CGPoint], width: CGFloat,
        transform: CGAffineTransform = .identity, densify: Bool = true
    ) -> PKStroke {
        Fixtures.monolineStroke(densify ? densified(polyline) : polyline,
                                width: width, color: Fixtures.ink, transform: transform)
    }

    /// Inserts points so no two neighbours are more than `spacing` apart.
    static func densified(_ polyline: [CGPoint], spacing: CGFloat = 4) -> [CGPoint] {
        guard var previous = polyline.first else { return [] }
        var result = [previous]
        for point in polyline.dropFirst() {
            let steps = max(1, Int((hypot(point.x - previous.x, point.y - previous.y) / spacing).rounded(.up)))
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                result.append(CGPoint(x: previous.x + (point.x - previous.x) * t,
                                      y: previous.y + (point.y - previous.y) * t))
            }
            previous = point
        }
        return result
    }
}
