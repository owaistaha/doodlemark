import PencilKit
import XCTest
@testable import Doodlemark

/// What survives `PKDrawing.dataRepresentation()` → `PKDrawing(data:)`.
/// Projects are saved this way (step 6), so the exporter must still get the
/// same strokes after a reload.
///
/// Measured on the iPadOS 26.5 simulator: the reload reports monoline strokes
/// as `.pen` (`requiredContentVersion` 2). Points, widths, the native render and
/// the exported SVG are all identical. Step 6 re-applies monoline ink to every
/// Ink-layer stroke after a load (RISKS.md #11).
@MainActor
final class DrawingPersistenceTests: XCTestCase {
    private let stroke = Fixtures.monolineStroke(
        GateFixtures.densified([CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 140), CGPoint(x: 420, y: 60)]),
        width: 10)

    func testReloadKeepsGeometryRenderAndExport() throws {
        let original = PKDrawing(strokes: [stroke])
        let reloaded = try PKDrawing(data: original.dataRepresentation())
        let back = try XCTUnwrap(reloaded.strokes.first)
        print("PERSIST| ink before \(stroke.ink.inkType.rawValue), after reload \(back.ink.inkType.rawValue)")

        XCTAssertEqual(back.path.map(\.location), stroke.path.map(\.location))
        XCTAssertEqual(back.path.map(\.size.width), stroke.path.map(\.size.width))
        XCTAssertEqual(try SVGExporter.svg(shapes: [], ink: reloaded, text: nil),
                       try SVGExporter.svg(shapes: [], ink: original, text: nil))
        XCTAssertEqual(try render(reloaded), try render(original), "PencilKit should draw the reloaded strokes identically")
    }

    /// Documents the ink-type downgrade. If a future iOS keeps `.monoline`
    /// through a reload, this fails: then the step 6 re-stamp can go.
    func testReloadReportsMonolineAsPen() throws {
        let reloaded = try PKDrawing(data: PKDrawing(strokes: [stroke]).dataRepresentation())
        XCTAssertEqual(reloaded.strokes.first?.ink.inkType, .pen)
    }

    func testReapplyingMonolineAfterReloadRestoresTheType() throws {
        var reloaded = try PKDrawing(data: PKDrawing(strokes: [stroke]).dataRepresentation())
        for i in reloaded.strokes.indices {
            reloaded.strokes[i].ink = PKInk(.monoline, color: reloaded.strokes[i].ink.color)
        }
        XCTAssertEqual(reloaded.strokes.first?.ink.inkType, .monoline)
        XCTAssertEqual(try render(reloaded), try render(PKDrawing(strokes: [stroke])))
    }

    private func render(_ drawing: PKDrawing) throws -> Data {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(x: 0, y: 0, width: 512, height: 256), scale: 2)
        }
        return try XCTUnwrap(image.pngData())
    }
}
