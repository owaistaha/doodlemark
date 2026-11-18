import PencilKit
import XCTest
@testable import Doodlemark

/// Structure, determinism and the snapshot. Visual faithfulness is the step 3 gate.
final class SVGExporterTests: XCTestCase {

    // MARK: Snapshot

    /// One known shape + one stroke, compared byte-for-byte with a committed file.
    /// To re-record after an intended change, run tests with
    /// `TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test ...`, review the diff, commit it.
    func testShapeAndStrokeMatchesSnapshot() throws {
        let shape = LogoShape(
            id: UUID(), kind: .circle, center: CGPoint(x: 512, y: 400),
            size: 300, rotation: 0, fill: Fixtures.tangerine)
        // A straight stroke, moved down 50pt by its transform: the output must show y = 750.
        let stroke = Fixtures.monolineStroke(
            [CGPoint(x: 200, y: 700), CGPoint(x: 500, y: 700), CGPoint(x: 800, y: 700)],
            transform: CGAffineTransform(translationX: 0, y: 50))

        let actual = try SVGExporter.svg(shapes: [shape], ink: PKDrawing(strokes: [stroke]), text: nil)
        try assertSnapshot(actual, named: "shape-and-stroke")
    }

    // MARK: Structure

    func testLayerOrderIsShapesInkText() throws {
        let svg = try SVGExporter.svg(
            shapes: [LogoShape(id: UUID(), kind: .star, center: CGPoint(x: 512, y: 512),
                               size: 200, rotation: 0, fill: Fixtures.butter)],
            ink: PKDrawing(strokes: [Fixtures.monolineStroke([CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 900)])]),
            text: Fixtures.pizzaText())
        let shapes = try XCTUnwrap(svg.range(of: #"<g id="shapes">"#)).lowerBound
        let ink = try XCTUnwrap(svg.range(of: #"<g id="ink""#)).lowerBound
        let text = try XCTUnwrap(svg.range(of: #"<g id="text">"#)).lowerBound
        XCTAssertLessThan(shapes, ink)
        XCTAssertLessThan(ink, text)
        XCTAssertTrue(svg.contains(#"viewBox="0 0 1024.00 1024.00""#))
    }

    func testTextIsExportedAsOutlinesNeverAsTextElement() throws {
        let svg = try SVGExporter.svg(shapes: [], ink: PKDrawing(), text: Fixtures.pizzaText())
        XCTAssertFalse(svg.contains("<text"))
        XCTAssertFalse(svg.contains("LilitaOne"))
        XCTAssertTrue(svg.contains(##"<path fill="#1C1B22" d="M"##))
    }

    func testMissingFontThrowsInsteadOfDroppingText() {
        var text = Fixtures.pizzaText()
        text.fontName = "Helvetica-Nope"
        XCTAssertThrowsError(try SVGExporter.svg(shapes: [], ink: PKDrawing(), text: text))
    }

    func testEmptyInputHasNoLayerGroups() throws {
        let svg = try SVGExporter.svg(shapes: [], ink: PKDrawing(), text: nil)
        XCTAssertFalse(svg.contains("<g"))
    }

    func testOutputIsDeterministic() throws {
        let project = Fixtures.fullProject()
        let drawing = PKDrawing(strokes: [
            Fixtures.monolineStroke([CGPoint(x: 100, y: 500), CGPoint(x: 300, y: 300),
                                     CGPoint(x: 500, y: 600), CGPoint(x: 700, y: 350)])
        ])
        XCTAssertEqual(try SVGExporter.svg(project: project, ink: drawing),
                       try SVGExporter.svg(project: project, ink: drawing))
    }

    // MARK: Strokes

    func testTapExportsAsZeroLengthRoundCapSegment() throws {
        let dot = Fixtures.monolineStroke([CGPoint(x: 300, y: 300)], width: 12)
        let element = try XCTUnwrap(SVGExporter.strokeElement(for: dot))
        XCTAssertTrue(element.contains(#"d="M300.00 300.00 L300.00 300.00""#), element)
        XCTAssertTrue(element.contains(#"stroke-width="12.00""#), element)
    }

    func testScaledTransformScalesWidthAndPoints() throws {
        let stroke = Fixtures.monolineStroke(
            [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10)], width: 8,
            transform: CGAffineTransform(scaleX: 2, y: 2))
        let element = try XCTUnwrap(SVGExporter.strokeElement(for: stroke))
        XCTAssertTrue(element.contains(#"stroke-width="16.00""#), element)
        XCTAssertTrue(element.contains("M20.00 20.00"), element)
        XCTAssertTrue(element.contains("220.00 20.00"), element)
    }

    func testTranslucentInkGetsStrokeOpacity() throws {
        var stroke = Fixtures.monolineStroke([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)])
        stroke.ink = PKInk(.monoline, color: UIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let element = try XCTUnwrap(SVGExporter.strokeElement(for: stroke))
        XCTAssertTrue(element.contains(##"stroke="#FF0000""##), element)
        XCTAssertTrue(element.contains(#"stroke-opacity="0.50""#), element)
    }

    func testDarkModeInkVariantIsNeverExported() throws {
        let dynamic = UIColor { $0.userInterfaceStyle == .dark ? .white : .black }
        XCTAssertEqual(SVGExporter.inkColor(dynamic).color, HexColor(red: 0, green: 0, blue: 0))
    }

    func testDisplayP3ColorIsConvertedToSRGB() throws {
        let p3Red = UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        let (color, alpha) = SVGExporter.inkColor(p3Red)
        XCTAssertEqual(color, HexColor(red: 255, green: 0, blue: 0))   // clamped into sRGB
        XCTAssertEqual(alpha, 1, accuracy: 0.001)
    }

    // MARK: Simplification

    func testSimplifyKeepsCornersAndDropsCollinearPoints() {
        let line = (0...50).map { CGPoint(x: CGFloat($0) * 2, y: 0) }
        XCTAssertEqual(SVGExporter.simplify(line, tolerance: 0.5), [line.first!, line.last!])

        let corner = (0...20).map { CGPoint(x: CGFloat($0) * 5, y: 0) }
            + (1...20).map { CGPoint(x: 100, y: CGFloat($0) * 5) }
        XCTAssertEqual(SVGExporter.simplify(corner, tolerance: 0.5),
                       [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
    }

    // MARK: Number formatting

    func testNumbersUseFixedTwoDecimals() {
        XCTAssertEqual(SVGExporter.format(0), "0.00")
        XCTAssertEqual(SVGExporter.format(1024), "1024.00")
        XCTAssertEqual(SVGExporter.format(3.14159), "3.14")
        XCTAssertEqual(SVGExporter.format(7.126), "7.13")
        XCTAssertEqual(SVGExporter.format(-12.5), "-12.50")
        XCTAssertEqual(SVGExporter.format(0.05), "0.05")
        XCTAssertEqual(SVGExporter.format(-0.004), "0.00")     // never "-0.00"
        XCTAssertEqual(SVGExporter.format(.nan), "0.00")
    }

    // MARK: - Snapshot helper

    private func assertSnapshot(_ actual: String, named name: String,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let sourceURL = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("Snapshots/\(name).svg")

        if ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" {
            try actual.write(to: sourceURL, atomically: true, encoding: .utf8)
            XCTFail("Recorded snapshot \(name).svg. Review it, then run again without RECORD_SNAPSHOTS.",
                    file: file, line: line)
            return
        }

        let bundleURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "svg"),
            "Missing snapshot \(name).svg. Record it with TEST_RUNNER_RECORD_SNAPSHOTS=1.",
            file: file, line: line)
        let expected = try String(contentsOf: bundleURL, encoding: .utf8)
        if actual != expected {
            let attachment = XCTAttachment(string: actual)
            attachment.name = "\(name)-actual.svg"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(actual, expected, "SVG differs from Snapshots/\(name).svg", file: file, line: line)
    }
}
