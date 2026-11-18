import PencilKit
import XCTest
@testable import Doodlemark

final class LineSizeTests: XCTestCase {
    func testToolWidthIsHalfTheSize() {
        XCTAssertEqual(LineSize.toolWidth(forSize: 4), 2)
        XCTAssertEqual(LineSize.toolWidth(forSize: 16), 8)
        XCTAssertEqual(LineSize.toolWidth(forSize: 40), 20)
    }

    func testStoredWidthMatchesTheAgreedFormula() {
        for size in stride(from: LineSize.range.lowerBound, through: LineSize.range.upperBound, by: LineSize.step) {
            XCTAssertEqual(LineSize.storedWidth(forSize: size), (size + 4) / 2)
        }
    }

    func testOutOfRangeSizesAreClamped() {
        XCTAssertEqual(LineSize.toolWidth(forSize: 0), 2)
        XCTAssertEqual(LineSize.toolWidth(forSize: -10), 2)
        XCTAssertEqual(LineSize.toolWidth(forSize: 100), 20)
    }

    /// Every slider position round-trips through the stored width to the same
    /// size, and the exported stroke-width is that size.
    func testEverySliderSizeExportsAtThatThickness() throws {
        for size in stride(from: LineSize.range.lowerBound, through: LineSize.range.upperBound, by: LineSize.step) {
            let stored = LineSize.storedWidth(forSize: size)
            XCTAssertEqual(LineSize.size(forStoredWidth: stored), size)
            XCTAssertEqual(LineSize.toolWidth(forSize: size).rounded(), LineSize.toolWidth(forSize: size),
                           "step 2 keeps tool widths whole")

            let stroke = Fixtures.monolineStroke([CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 100)], width: stored)
            let svg = try SVGExporter.svg(shapes: [], ink: PKDrawing(strokes: [stroke]), text: nil)
            XCTAssertTrue(svg.contains("stroke-width=\"\(SVGExporter.format(size))\""), "size \(size): \(svg)")
        }
    }

    func testDefaultIsInRangeAndOnAStep() {
        XCTAssertTrue(LineSize.range.contains(LineSize.defaultSize))
        XCTAssertEqual((LineSize.defaultSize - LineSize.range.lowerBound).truncatingRemainder(dividingBy: LineSize.step), 0)
    }
}
