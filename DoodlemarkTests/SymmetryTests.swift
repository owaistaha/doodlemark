import PencilKit
import XCTest
@testable import Doodlemark

@MainActor
final class SymmetryTests: XCTestCase {
    func testMirroredStrokeIsReflectedAcrossX512() {
        let stroke = GateFixtures.zigzag
        let mirrored = Symmetry.mirrored(stroke)
        let original = stroke.path.map { $0.location.applying(stroke.transform) }
        let copy = mirrored.path.map { $0.location.applying(mirrored.transform) }
        for (a, b) in zip(original, copy) {
            XCTAssertEqual(b.x, 1024 - a.x, accuracy: 1e-9)
            XCTAssertEqual(b.y, a.y, accuracy: 1e-9)
        }
    }

    func testMirroringTwiceGivesTheOriginal() {
        let stroke = GateFixtures.transformed
        XCTAssertEqual(Symmetry.mirrored(Symmetry.mirrored(stroke)).transform, stroke.transform)
    }

    func testMirroredStrokeExportsAtTheSameWidth() throws {
        let stroke = GateFixtures.diagonal
        let svg = try SVGExporter.svg(shapes: [], ink: PKDrawing(strokes: [Symmetry.mirrored(stroke)]), text: nil)
        let width = SVGExporter.format(SVGExporter.renderedMonolineWidth(pointWidth: 8))
        XCTAssertTrue(svg.contains("stroke-width=\"\(width)\""), svg)
        XCTAssertTrue(svg.contains("M874.00 180.00"), "starts at the mirrored point (1024 − 150): \(svg.prefix(300))")
    }
}
