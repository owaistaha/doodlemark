import PencilKit
import XCTest
@testable import Doodlemark

/// THE HARD GATE (TECH_SPEC "Hard gate"). Every fixture is drawn natively
/// (PencilKit / Core Graphics / Core Text) and as exported SVG (WebKit), then
/// compared with the thresholds in `GateConfig`. Negative controls must FAIL.
///
/// Images for each case are written to DoodlemarkTests/GateOutput/<case>/:
/// native.png, svg.png, diff.png, export.svg, metrics.txt.
@MainActor
final class SVGExportTests: XCTestCase {
    private static let outputRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("GateOutput")

    // MARK: Harness calibration

    /// Proves the WebKit side is pixel-aligned before trusting any other number:
    /// a 200×200 square at (100, 100) must land on exact pixels, with no margin
    /// or scaling, in a 1024×1024 snapshot taken without resampling.
    func testHarnessRendersSVGAtExactPixels() async throws {
        let renderer = SVGWebRenderer()
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><path fill="black" d="M100 100 L300 100 L300 300 L100 300 Z"/></svg>"#
        let bitmap = try await renderer.render(svg: svg)

        XCTAssertEqual(renderer.lastSnapshotPixelSize, CGSize(width: 1024, height: 1024),
                       "WebKit snapshot must be 1024 px without resampling")
        func isBlack(_ x: Int, _ y: Int) -> Bool { bitmap.rgb(x, y) == (0, 0, 0) }
        func isWhite(_ x: Int, _ y: Int) -> Bool { bitmap.rgb(x, y) == (255, 255, 255) }
        XCTAssertTrue(isWhite(99, 99) && isWhite(300, 300) && isWhite(99, 200) && isWhite(200, 300))
        XCTAssertTrue(isBlack(100, 100) && isBlack(299, 299) && isBlack(100, 299) && isBlack(299, 100))
        XCTAssertTrue(isWhite(1023, 1023) && isWhite(0, 0))
    }

    // MARK: Fixtures (must pass)

    func testGateLine() async throws { try await assertGatePasses("line") }
    func testGateCurve() async throws { try await assertGatePasses("curve") }
    func testGateZigzag() async throws { try await assertGatePasses("zigzag") }
    func testGateWobbly() async throws { try await assertGatePasses("wobbly") }
    func testGateTransformed() async throws { try await assertGatePasses("transformed") }
    func testGateDots() async throws { try await assertGatePasses("dots") }
    func testGateShapes() async throws { try await assertGatePasses("shapes") }
    func testGateText() async throws { try await assertGatePasses("text") }
    func testGateTextRotated() async throws { try await assertGatePasses("text-rotated") }
    func testGateLogo() async throws { try await assertGatePasses("logo") }
    func testGateSmoothedMirrored() async throws { try await assertGatePasses("smoothed-mirrored") }

    // MARK: Negative controls (must fail; if one passes, the gate is broken)

    func testNegativeControlShiftedStrokeFails() async throws {
        try await assertGateFails("neg-shifted-stroke", export: GateFixtures.logoWithShiftedUnderline)
    }

    func testNegativeControlDroppedStrokeFails() async throws {
        try await assertGateFails("neg-dropped-stroke", export: GateFixtures.logoWithDroppedUnderline)
    }

    func testNegativeControlWrongColorFails() async throws {
        try await assertGateFails("neg-wrong-color", export: GateFixtures.logoWithRecoloredUnderline)
    }

    // MARK: Whatever was last drawn on the debug screen

    /// Diffs the last drawing from the DEBUG export screen (finger, trackpad or
    /// Pencil) against the exact SVG file that screen wrote. The test host is
    /// the app, so both files are in this process's temporary folder. Skipped
    /// when nothing has been drawn there yet.
    func testLastDebugExportMatchesNative() async throws {
        let folder = FileManager.default.temporaryDirectory
        let drawingURL = folder.appendingPathComponent("doodlemark-export-test.drawing")
        let svgURL = folder.appendingPathComponent("doodlemark-export-test.svg")
        guard FileManager.default.fileExists(atPath: drawingURL.path) else {
            throw XCTSkip("Nothing drawn on the debug export screen yet.")
        }
        let drawing = try PKDrawing(data: Data(contentsOf: drawingURL))
        try XCTSkipIf(drawing.strokes.isEmpty, "The debug export screen is empty.")
        let savedSVG = try String(contentsOf: svgURL, encoding: .utf8)
        XCTAssertEqual(savedSVG, try SVGExporter.svg(shapes: [], ink: drawing, text: nil),
                       "The saved SVG should be exactly what the exporter makes from the saved strokes")

        for (i, stroke) in drawing.strokes.enumerated() {
            let widths = stroke.path.map(\.size.width)
            print("DEBUGDRAWING| stroke \(i): \(stroke.path.count) points, size.width \(widths.min() ?? 0)…\(widths.max() ?? 0), "
                  + "ink \(stroke.ink.inkType.rawValue), transform \(stroke.transform), bounds \(stroke.renderBounds)")
        }
        let metrics = try await runGate("debug-drawing", native: GateScene(ink: drawing), svg: savedSVG)
        XCTAssertTrue(metrics.passes, "debug-drawing: \(metrics)")
    }

    // MARK: - Helpers

    private func assertGatePasses(_ name: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let scene = try XCTUnwrap(GateFixtures.scenes.first { $0.name == name }?.scene)
        let metrics = try await runGate(name, native: scene, export: scene)
        XCTAssertTrue(metrics.passes, "\(name): \(metrics)", file: file, line: line)
    }

    private func assertGateFails(_ name: String, export: GateScene,
                                 file: StaticString = #filePath, line: UInt = #line) async throws {
        let metrics = try await runGate(name, native: GateFixtures.logo, export: export)
        XCTAssertFalse(metrics.passes, "Negative control \(name) PASSED, so the gate is broken: \(metrics)",
                       file: file, line: line)
    }

    private func runGate(_ name: String, native: GateScene, export: GateScene) async throws -> GateMetrics {
        let svg = try SVGExporter.svg(shapes: export.shapes, ink: export.ink, text: export.text)
        return try await runGate(name, native: native, svg: svg)
    }

    private func runGate(_ name: String, native: GateScene, svg: String) async throws -> GateMetrics {
        let nativeBitmap = try NativeRenderer.render(native)
        let svgBitmap = try await SVGWebRenderer().render(svg: svg)
        let (metrics, diff) = GateComparison.compare(native: nativeBitmap, svg: svgBitmap)

        let folder = Self.outputRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try nativeBitmap.pngData().write(to: folder.appendingPathComponent("native.png"))
        try svgBitmap.pngData().write(to: folder.appendingPathComponent("svg.png"))
        try diff.pngData().write(to: folder.appendingPathComponent("diff.png"))
        try svg.write(to: folder.appendingPathComponent("export.svg"), atomically: true, encoding: .utf8)
        try "\(name): \(metrics)\n".write(to: folder.appendingPathComponent("metrics.txt"), atomically: true, encoding: .utf8)

        print("GATE| \(name): \(metrics)")
        return metrics
    }
}
