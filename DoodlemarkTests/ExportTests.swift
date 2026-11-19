import PencilKit
import XCTest
@testable import Doodlemark

/// Step 7: the files "Export & share" writes. The SVG is the gated
/// exporter's output, the PNG is the thumbnails' renderer at 1024 and
/// matches the native render, the sketch is in neither, and an empty
/// project exports nothing.
@MainActor
final class ExportTests: XCTestCase {
    private var parent: URL!

    override func setUp() async throws {
        parent = FileManager.default.temporaryDirectory.appending(path: "ExportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: parent)
    }

    // MARK: Fixture: a full logo (shape + ink + text)

    /// "Pizza Rocket": a tangerine disc and a butter window (Shapes), an ink
    /// rocket (Ink), the name in Lilita One (Text), starter palette.
    static func pizzaRocket() -> (project: Project, ink: PKDrawing) {
        var project = Project.blank(name: "Pizza Rocket")
        project.palette = Palettes.starter                  // tangerine, ink, butter
        project.shapes = [
            LogoShape(id: UUID(), kind: .circle, center: CGPoint(x: 512, y: 430), size: 560, rotation: 0, fill: .first),
            LogoShape(id: UUID(), kind: .circle, center: CGPoint(x: 512, y: 370), size: 96, rotation: 0, fill: .third),
        ]
        project.text = LogoText(string: "Pizza Rocket", fontName: Fixtures.logoFont, center: CGPoint(x: 512, y: 880),
                                pointSize: 110, rotation: 0, fill: .second)
        let ink = project.palette[1]
        func line(_ points: [CGPoint]) -> PKStroke {
            Fixtures.monolineStroke(GateFixtures.densified(points), width: 16, color: ink)
        }
        let drawing = PKDrawing(strokes: [
            line([CGPoint(x: 512, y: 230), CGPoint(x: 584, y: 330), CGPoint(x: 596, y: 540),
                  CGPoint(x: 428, y: 540), CGPoint(x: 440, y: 330), CGPoint(x: 512, y: 230)]),   // body
            line([CGPoint(x: 440, y: 470), CGPoint(x: 384, y: 590), CGPoint(x: 432, y: 570)]),  // fins
            line([CGPoint(x: 584, y: 470), CGPoint(x: 640, y: 590), CGPoint(x: 592, y: 570)]),
            line([CGPoint(x: 470, y: 570), CGPoint(x: 512, y: 650), CGPoint(x: 554, y: 570)]),  // flame
        ])
        return (project, drawing)
    }

    /// A sketch in a color the logo never uses, where the logo has nothing.
    static func loudSketch() -> PKDrawing {
        PKDrawing(strokes: [PKStroke(ink: PKInk(.pencil, color: UIColor(red: 0, green: 1, blue: 0, alpha: 1)),
                                     path: PKStrokePath(controlPoints: GateFixtures.densified(
                                        [CGPoint(x: 60, y: 60), CGPoint(x: 220, y: 60), CGPoint(x: 220, y: 200)]).enumerated().map {
                                            PKStrokePoint(location: $1, timeOffset: Double($0) * 0.01, size: CGSize(width: 40, height: 40),
                                                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                                        }, creationDate: Date(timeIntervalSince1970: 0)))])
    }

    private func write(_ project: Project, _ ink: PKDrawing, _ change: (inout ExportOptions) -> Void = { _ in }) throws -> [URL] {
        var options = ExportOptions(fileName: ExportFiles.defaultFileName(for: project.name))
        change(&options)
        return try ExportFiles.write(project: project, ink: ink, options: options, in: parent)
    }

    /// Pixel (x, y) of a PNG file, straight (not premultiplied) RGBA.
    private func pixel(_ png: Data, _ x: Int, _ y: Int) throws -> [UInt8] {
        let cg = try XCTUnwrap(UIImage(data: png)?.cgImage)
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return rgba
    }

    // MARK: SVG

    func testTheExportedSVGIsExactlyTheGatedExportersOutput() throws {
        let (project, ink) = Self.pizzaRocket()
        let urls = try write(project, ink)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["pizza-rocket.svg", "pizza-rocket.png"])
        let gated = try SVGExporter.svg(project: project, ink: ink)
        XCTAssertEqual(try Data(contentsOf: urls[0]), Data(gated.utf8), "byte for byte")
        XCTAssertFalse(gated.contains("<text"), "text is outlines")

        // Keep a copy to open in Safari (gitignored, next to the gate images).
        let keep = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "GateOutput/export", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        for url in urls {
            let copy = keep.appending(path: url.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: url, to: copy)
        }
    }

    // MARK: PNG

    func testThePNGIs1024AndMatchesTheNativeRender() throws {
        let (project, ink) = Self.pizzaRocket()
        let urls = try write(project, ink) { $0.svg = false }
        XCTAssertEqual(urls.map(\.lastPathComponent), ["pizza-rocket.png"])
        let png = try Data(contentsOf: urls[0])
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(image.width, 1024)
        XCTAssertEqual(image.height, 1024)

        // The gate's native render (PencilKit, Core Graphics, CTLineDraw) of
        // the same logo, judged with the gate's own thresholds.
        let native = try NativeRenderer.render(GateScene(shapes: project.shapes, ink: ink, text: project.text,
                                                         palette: project.palette))
        let (metrics, _) = GateComparison.compare(native: native, svg: Bitmap(image))
        XCTAssertTrue(metrics.passes, "\(metrics)")
        XCTAssertLessThan(metrics.differingFraction, 0.005, "same renderer for shapes and ink: \(metrics)")

        // Without text both sides draw the very same way: no differing pixels.
        var noText = project
        noText.text = nil
        let plain = try XCTUnwrap(ExportFiles.pngData(project: noText, ink: ink, transparent: true))
        let nativePlain = try NativeRenderer.render(GateScene(shapes: project.shapes, ink: ink, palette: project.palette))
        let (plainMetrics, _) = GateComparison.compare(native: nativePlain, svg: Bitmap(try XCTUnwrap(UIImage(data: plain)?.cgImage)))
        XCTAssertEqual(plainMetrics.differingFraction, 0, "\(plainMetrics)")
    }

    func testTransparentBackgroundOrPaper() throws {
        let (project, ink) = Self.pizzaRocket()
        let clear = try XCTUnwrap(ExportFiles.pngData(project: project, ink: ink, transparent: true))
        let paper = try XCTUnwrap(ExportFiles.pngData(project: project, ink: ink, transparent: false))

        XCTAssertEqual(try pixel(clear, 10, 10)[3], 0, "transparent corner")
        XCTAssertEqual(try pixel(paper, 10, 10), [0xFB, 0xF8, 0xF2, 0xFF], "paper #FBF8F2 corner")
        XCTAssertEqual(ExportFiles.paper.hexString, "#FBF8F2")
        // The logo itself is the same on both: the disc is tangerine.
        XCTAssertEqual(try pixel(clear, 300, 430), [0xFF, 0x5A, 0x1F, 0xFF])
        XCTAssertEqual(try pixel(paper, 300, 430), [0xFF, 0x5A, 0x1F, 0xFF])

        let files = try write(project, ink) { $0.svg = false; $0.transparentBackground = false }
        XCTAssertEqual(try pixel(Data(contentsOf: files[0]), 10, 10), [0xFB, 0xF8, 0xF2, 0xFF], "the option reaches the file")
        let svgOnly = try write(project, ink) { $0.png = false; $0.transparentBackground = false }
        XCTAssertFalse(try String(contentsOf: svgOnly[0], encoding: .utf8).contains("FBF8F2"),
                       "the background option is PNG only: the SVG never gets a paper rectangle")
    }

    // MARK: File names

    func testFileNamesAreSanitized() {
        XCTAssertEqual(ExportFiles.defaultFileName(for: "Pizza Rocket"), "pizza-rocket")
        XCTAssertEqual(ExportFiles.defaultFileName(for: "Moon Café"), "moon-cafe")
        XCTAssertEqual(ExportFiles.defaultFileName(for: "Untitled logo"), "untitled-logo")
        XCTAssertEqual(ExportFiles.defaultFileName(for: "Cat café ☕️ & Co."), "cat-cafe-co")
        XCTAssertEqual(ExportFiles.fileName(from: "../../etc/passwd"), "etc-passwd", "no slashes or dots")
        XCTAssertEqual(ExportFiles.fileName(from: "my/logo\\v2"), "my-logo-v2")
        XCTAssertEqual(ExportFiles.fileName(from: "  My Logo  "), "My-Logo", "typed case is kept")
        XCTAssertEqual(ExportFiles.fileName(from: "logo.svg"), "logo-svg", "no extension tricks")
        XCTAssertEqual(ExportFiles.fileName(from: "a\u{0}b\nc:d*e?f\"g<h>i|j"), "a-b-c-d-e-f-g-h-i-j")
        XCTAssertEqual(ExportFiles.fileName(from: "snake_case-ok"), "snake_case-ok")
        XCTAssertEqual(ExportFiles.fileName(from: "🍕🚀"), "logo", "nothing usable → fallback")
        XCTAssertEqual(ExportFiles.fileName(from: "", fallback: "pizza-rocket"), "pizza-rocket")
        XCTAssertEqual(ExportFiles.fileName(from: "---"), "logo")
        XCTAssertEqual(ExportFiles.fileName(from: String(repeating: "ab ", count: 40)).count, 59, "≤ 60, no trailing dash")
        XCTAssertLessThanOrEqual(ExportFiles.fileName(from: String(repeating: "x", count: 500)).count, 60)
    }

    func testAnEmptyFieldUsesTheProjectName() throws {
        let (project, ink) = Self.pizzaRocket()
        let urls = try write(project, ink) { $0.fileName = "  /// " }
        XCTAssertEqual(urls.map(\.lastPathComponent), ["pizza-rocket.svg", "pizza-rocket.png"])
        XCTAssertTrue(urls.allSatisfy { $0.deletingLastPathComponent().deletingLastPathComponent().path == parent.path },
                      "files stay inside their own export folder")
    }

    // MARK: Refusals

    func testAnEmptyProjectExportsNothing() throws {
        var project = Project.blank()
        XCTAssertTrue(ExportFiles.isEmpty(project: project, ink: PKDrawing()))
        XCTAssertThrowsError(try write(project, PKDrawing())) { XCTAssertEqual($0 as? ExportFiles.Failure, .nothingToExport) }
        project.text = LogoText(string: "", fontName: Fixtures.logoFont, center: CGPoint(x: 512, y: 512),
                                pointSize: 100, rotation: 0, fill: .second)
        XCTAssertTrue(ExportFiles.isEmpty(project: project, ink: PKDrawing()), "an empty text box is nothing")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), [], "no folder, no files")

        // Any one of ink, a shape or text is enough.
        let (full, ink) = Self.pizzaRocket()
        var shapesOnly = Project.blank(); shapesOnly.shapes = full.shapes
        var textOnly = Project.blank(); textOnly.text = full.text
        XCTAssertFalse(ExportFiles.isEmpty(project: .blank(), ink: ink))
        XCTAssertFalse(ExportFiles.isEmpty(project: shapesOnly, ink: PKDrawing()))
        XCTAssertFalse(ExportFiles.isEmpty(project: textOnly, ink: PKDrawing()))
    }

    func testASketchOnlyProjectCountsAsEmpty() throws {
        let model = CanvasModel(project: .blank(), sketch: Self.loudSketch(), ink: PKDrawing())
        XCTAssertTrue(ExportFiles.isEmpty(project: model.project, ink: model.ink), "the sketch is never exported")
    }

    func testAtLeastOneFormat() throws {
        let (project, ink) = Self.pizzaRocket()
        XCTAssertThrowsError(try write(project, ink) { $0.svg = false; $0.png = false }) {
            XCTAssertEqual($0 as? ExportFiles.Failure, .noFormat)
        }
        let model = ExportModel(project: project, ink: ink, displayScale: 2)
        model.options.svg = false
        model.options.png = false
        XCTAssertFalse(model.canExport)
        XCTAssertEqual(model.savesAs, "Pick SVG, PNG or both.")
        model.options.png = true
        XCTAssertEqual(model.savesAs, "Saves pizza-rocket.png")
        model.options.fileName = "Rocket/Pizza!"
        XCTAssertEqual(model.savesAs, "Saves Rocket-Pizza.png", "shows what the typed name became")
    }

    // MARK: The sketch is never exported

    /// The export screen gets its logo from the open canvas, sketch and all:
    /// both files are byte-identical to the same logo without a sketch.
    func testTheSketchIsInNeitherFile() throws {
        let (project, ink) = Self.pizzaRocket()
        let withSketch = CanvasModel(project: project, sketch: Self.loudSketch(), ink: ink)
        let without = CanvasModel(project: project, sketch: PKDrawing(), ink: ink)
        let a = ExportModel(project: withSketch.project, ink: withSketch.ink, displayScale: 2)
        let b = ExportModel(project: without.project, ink: without.ink, displayScale: 2)
        a.options.transparentBackground = false
        b.options.transparentBackground = false
        let filesA = try XCTUnwrap(a.makeFiles())
        let filesB = try XCTUnwrap(b.makeFiles())
        defer { a.finishSharing(); b.finishSharing() }
        XCTAssertEqual(try filesA.map { try Data(contentsOf: $0) }, try filesB.map { try Data(contentsOf: $0) })

        let svg = try String(contentsOf: filesA[0], encoding: .utf8)
        XCTAssertFalse(svg.contains("00FF00"), "no sketch color in the SVG")
        XCTAssertEqual(svg.components(separatedBy: "<path").count - 1,
                       project.shapes.count + ink.strokes.count + 1, "shapes, ink lines and one text outline, nothing else")
        let png = try Data(contentsOf: filesA[1])
        XCTAssertEqual(try pixel(png, 140, 60), [0xFB, 0xF8, 0xF2, 0xFF], "paper where the sketch line is")
    }

    // MARK: Temp files

    func testFilesAreCleanedUpAfterSharing() throws {
        let (project, ink) = Self.pizzaRocket()
        let model = ExportModel(project: project, ink: ink, displayScale: 2)
        let urls = try XCTUnwrap(model.makeFiles())
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertFalse(model.canExport, "one share at a time")
        model.finishSharing()
        XCTAssertFalse(urls.contains { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].deletingLastPathComponent().path), "the folder too")
        XCTAssertTrue(model.canExport)
    }

    func testLeftoverExportFoldersAreRemovedAtLaunch() throws {
        let (project, ink) = Self.pizzaRocket()
        let urls = try write(project, ink)
        let unrelated = parent.appending(path: "keep-me.txt")
        try Data("x".utf8).write(to: unrelated)
        ExportFiles.removeLeftovers(in: parent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path), "only Export- folders")
    }

    // MARK: Mockups

    func testMockupsUseTheRealRender() throws {
        let (project, ink) = Self.pizzaRocket()
        let model = ExportModel(project: project, ink: ink, displayScale: 2)
        XCTAssertEqual(model.logo.pngData(), PNGExporter.image(project: project, ink: ink, pixelSide: Theme.Mockup.renderSide).pngData())
        XCTAssertEqual(model.tiny.map(\.points), [96, 48, 24, 16])
        XCTAssertEqual(model.tiny.map { $0.image.cgImage?.width }, [192, 96, 48, 32], "each drawn at its own size, 2× screen")
    }
}
