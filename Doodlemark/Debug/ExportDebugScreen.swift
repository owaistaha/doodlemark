#if DEBUG
import PencilKit
import SwiftUI
import WebKit

/// DEBUG-only export check (bootstrap step 3). A bare Ink canvas next to a
/// WebKit render of the exported SVG, plus "Export SVG" through the share sheet,
/// so a human can draw with a finger or Pencil and open the file in Safari.
///
/// Not product UI: system fonts and plain layout are fine here. Colors still
/// come from Theme.
struct ExportDebugScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var erasing = false
    @State private var svg = ""
    @State private var exportURL: URL?
    @State private var message = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(alignment: .top, spacing: 20) {
                panel("Ink canvas (PencilKit)") {
                    DebugInkCanvas(drawing: $drawing, erasing: erasing)
                }
                panel("Exported SVG (WebKit)") {
                    SVGPreview(svg: svg)
                }
            }
            .padding(20)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(Theme.inkMuted)
                .padding(.bottom, 20)
            Spacer(minLength: 0)
        }
        .background(Theme.canvasBackdrop.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onChange(of: drawing) { _, newDrawing in export(newDrawing) }
        .onAppear {
            if UserDefaults.standard.bool(forKey: "debugLoadSample") { loadSample() }
            export(drawing)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Button("Close") { dismiss() }
                .frame(minHeight: 44)
            Text("Export test").font(.headline)
            Spacer()
            Picker("Tool", selection: $erasing) {
                Text("Pen").tag(false)
                Text("Eraser").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            Button("Sample") { loadSample() }
                .frame(minHeight: 44)
            Button("Clear", role: .destructive) { drawing = PKDrawing() }
                .frame(minHeight: 44)
            if let exportURL, !drawing.strokes.isEmpty {
                ShareLink("Export SVG", item: exportURL)
                    .frame(minHeight: 44)
            } else {
                Text("Draw something first.").foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .background(Theme.surface)
        .foregroundStyle(Theme.ink)
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkMuted)
            content()
                .aspectRatio(1, contentMode: .fit)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private func export(_ drawing: PKDrawing) {
        do {
            svg = try SVGExporter.svg(shapes: [], ink: drawing, text: nil)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("doodlemark-export-test.svg")
            try svg.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            let b = drawing.bounds
            // What PencilKit stored for the last stroke, and what the exporter turns it into.
            // Pen is set to width 8; check this on device (RISKS.md #9).
            var lastStroke = ""
            if let last = drawing.strokes.last, let point = last.path.first {
                let w = point.size.width
                lastStroke = String(format: " · last stroke size.width %.2f → stroke-width %.2f",
                                    w, SVGExporter.renderedMonolineWidth(pointWidth: w))
            }
            message = drawing.strokes.isEmpty
                ? "No strokes. Canvas space is 0–1024."
                : "\(drawing.strokes.count) strokes · bounds x \(Int(b.minX))–\(Int(b.maxX)), y \(Int(b.minY))–\(Int(b.maxY)) (canvas space 0–1024) · \(svg.utf8.count) bytes" + lastStroke
        } catch {
            message = "Export failed: \(error)"
        }
    }

    /// A few code-built strokes, so the screen can be checked without drawing.
    private func loadSample() {
        let ink = UIColor(Theme.ink)
        func stroke(_ points: [CGPoint], width: CGFloat) -> PKStroke {
            let strokePoints = points.enumerated().map { i, p in
                PKStrokePoint(location: p, timeOffset: Double(i) * 0.01, size: CGSize(width: width, height: width),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.monoline, color: ink),
                            path: PKStrokePath(controlPoints: strokePoints, creationDate: Date()))
        }
        let spiral: [CGPoint] = stride(from: 0.0, through: 5 * Double.pi, by: 0.05).map { (t: Double) -> CGPoint in
            let radius: Double = 30 + 20 * t
            return CGPoint(x: 512 + radius * cos(t), y: 420 + radius * sin(t))
        }
        let zigzag = [CGPoint(x: 140, y: 900), CGPoint(x: 300, y: 760), CGPoint(x: 460, y: 900),
                      CGPoint(x: 620, y: 760), CGPoint(x: 780, y: 900), CGPoint(x: 900, y: 800)]
        drawing = PKDrawing(strokes: [
            stroke(spiral, width: 8),
            stroke(zigzag, width: 10),
            stroke([CGPoint(x: 120, y: 120)], width: 24),
        ])
    }
}

// MARK: - Ink canvas

/// A bare Ink-layer PKCanvasView: monoline pen, vector eraser, any input,
/// and a 1024×1024 canvas space scaled to fit the view.
private struct DebugInkCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var erasing: Bool

    func makeUIView(context: Context) -> FittedCanvasView {
        let view = FittedCanvasView()
        view.canvas.delegate = context.coordinator
        view.canvas.drawing = drawing
        return view
    }

    func updateUIView(_ view: FittedCanvasView, context: Context) {
        let canvas = view.canvas
        canvas.tool = erasing
            ? PKEraserTool(.vector)
            : PKInkingTool(.monoline, color: UIColor(Theme.ink), width: 8)
        if canvas.drawing != drawing {
            context.coordinator.isUpdatingFromSwiftUI = true
            canvas.drawing = drawing
            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        var isUpdatingFromSwiftUI = false

        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingFromSwiftUI else { return }
            drawing.wrappedValue = canvasView.drawing
        }
    }
}

/// Holds a PKCanvasView whose content is the 1024×1024 canvas space, zoomed to
/// fit the view (Apple's PencilKit sample pattern). Stroke coordinates stay in
/// canvas space at any view size.
final class FittedCanvasView: UIView {
    static let canvasSide: CGFloat = 1024
    let canvas = PKCanvasView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        canvas.drawingPolicy = .anyInput        // finger, any stylus, Pencil
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.overrideUserInterfaceStyle = .light   // no dark-mode ink inversion
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.bouncesZoom = false
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        guard bounds.width > 0 else { return }
        let fit = bounds.width / Self.canvasSide
        canvas.minimumZoomScale = fit
        canvas.maximumZoomScale = fit
        canvas.zoomScale = fit
        canvas.contentSize = CGSize(width: Self.canvasSide * fit, height: Self.canvasSide * fit)
    }
}

// MARK: - SVG preview

/// Renders the SVG string with WebKit, scaled to the view. Local HTML only, no network.
private struct SVGPreview: UIViewRepresentable {
    var svg: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loaded != svg else { return }
        context.coordinator.loaded = svg
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:white}svg{display:block;width:100%;height:auto}</style>
        </head><body>\(svg)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var loaded: String? }
}
#endif
