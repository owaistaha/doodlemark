import PencilKit
import UIKit
@testable import Doodlemark

/// Shared, deterministic test data. Colors mirror DESIGN.md tokens.
enum Fixtures {
    static let tangerine = HexColor(red: 0xFF, green: 0x5A, blue: 0x1F)
    static let ink = HexColor(red: 0x1C, green: 0x1B, blue: 0x22)
    static let butter = HexColor(red: 0xFF, green: 0xC9, blue: 0x3C)

    /// The one bundled logo font so far (export gate font).
    static let logoFont = "LilitaOne"

    static func pizzaText(center: CGPoint = CGPoint(x: 512, y: 800), rotation: Double = 0) -> LogoText {
        LogoText(string: "Pizza", fontName: logoFont, center: center,
                 pointSize: 120, rotation: rotation, fill: .second)
    }

    static func fullProject() -> Project {
        Project(
            id: UUID(uuidString: "6B0E4C1A-0D2B-4C8F-9E1A-5F3D2C1B0A99")!,
            name: "Pizza Rocket",
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_123.5),
            palette: [tangerine, ink, butter],
            shapes: LogoShape.Kind.allCases.enumerated().map { index, kind in
                LogoShape(
                    id: UUID(), kind: kind,
                    center: CGPoint(x: 200 + 200 * CGFloat(index), y: 300),
                    size: 150, rotation: Double(index) * 0.25, fill: .first)
            },
            text: pizzaText(),
            symmetryOn: true,
            gridOn: false
        )
    }

    /// A monoline stroke through `points` (B-spline control points), built in code.
    static func monolineStroke(
        _ points: [CGPoint],
        width: CGFloat = 8,
        color: HexColor = ink,
        transform: CGAffineTransform = .identity
    ) -> PKStroke {
        let strokePoints = points.enumerated().map { index, location in
            PKStrokePoint(
                location: location, timeOffset: TimeInterval(index) * 0.01,
                size: CGSize(width: width, height: width), opacity: 1,
                force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date(timeIntervalSince1970: 0))
        return PKStroke(
            ink: PKInk(.monoline, color: UIColor(cgColor: color.cgColor)),
            path: path, transform: transform, mask: nil)
    }
}
