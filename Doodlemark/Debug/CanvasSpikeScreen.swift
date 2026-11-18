#if DEBUG
import PencilKit
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

// Step 4a spikes (throwaway, DEBUG only). Two questions, answered by
// CanvasSpikeUITests; findings are in RISKS.md #1 and #4.
//
// 1. Mirror + undo: when the mirrored copy is appended programmatically,
//    does one undo remove both strokes? Tried with PencilKit's own undo and
//    with our own undo stack of PKDrawing snapshots.
// 2. Layer touch routing: Sketch canvas, SwiftUI Shapes layer and Ink canvas
//    stacked. Only the active layer gets one-finger touches. Two fingers
//    pan/zoom all three together through one shared viewport.

enum SpikeLayer: String, CaseIterable { case sketch = "Sketch", shapes = "Shapes", ink = "Ink" }
enum SpikeUndoMode: String { case pencilKit, own }

@MainActor @Observable
final class SpikeShapes {
    var square = CGPoint(x: 260, y: 260)
    var moves = 0
}

@MainActor @Observable
final class SpikeModel {
    var activeLayer: SpikeLayer = .ink { didSet { stack?.applyActiveLayer() } }
    var mirror = false
    let undoMode: SpikeUndoMode = UserDefaults.standard.string(forKey: "spikeUndoMode") == "own" ? .own : .pencilKit
    var status = ""
    let shapes = SpikeShapes()
    weak var stack: SpikeStackView?
}

struct CanvasSpikeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = SpikeModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("Close") { dismiss() }.frame(minHeight: 44)
                ForEach(SpikeLayer.allCases, id: \.self) { layer in
                    Button(layer.rawValue) { model.activeLayer = layer }
                        .frame(minWidth: 60, minHeight: 44)
                        .background(model.activeLayer == layer ? Theme.blueTint : .clear)
                        .accessibilityIdentifier("spikeLayer-\(layer.rawValue)")
                }
                Button(model.mirror ? "Mirror: on" : "Mirror: off") { model.mirror.toggle() }
                    .frame(minHeight: 44).accessibilityIdentifier("spikeMirror")
                Text("Undo: \(model.undoMode.rawValue)").foregroundStyle(Theme.inkMuted)
                Spacer()
                Button("Undo") { model.stack?.undo() }.frame(minHeight: 44).accessibilityIdentifier("spikeUndo")
                Button("Redo") { model.stack?.redo() }.frame(minHeight: 44).accessibilityIdentifier("spikeRedo")
                Button("Clear") { model.stack?.clear() }.frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            SpikeStack(model: model)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityIdentifier("spikeStack")
            Text(model.status)
                .font(.footnote.monospaced())
                .foregroundStyle(Theme.inkMuted)
                .accessibilityIdentifier("spikeStatus")
        }
        .onChange(of: model.shapes.moves) { model.stack?.updateStatus() }
        .padding(.vertical, 12)
        .background(Theme.canvasBackdrop.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
    }
}

private struct SpikeStack: UIViewRepresentable {
    let model: SpikeModel
    func makeUIView(context: Context) -> SpikeStackView {
        let view = SpikeStackView(model: model)
        model.stack = view
        return view
    }
    func updateUIView(_ view: SpikeStackView, context: Context) {}
}

/// The Shapes layer as real SwiftUI, in 1024 canvas space. Its UIKit host
/// view gets the viewport transform, so gesture deltas arrive in canvas units.
struct SpikeShapesLayer: View {
    let shapes: SpikeShapes
    @State private var dragStart: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.tangerine)
                .frame(width: 160, height: 160)
                .position(shapes.square)
                .gesture(DragGesture()
                    .onChanged { value in
                        let start = dragStart ?? shapes.square
                        dragStart = start
                        shapes.square = CGPoint(x: start.x + value.translation.width,
                                                y: start.y + value.translation.height)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        shapes.moves += 1
                    })
        }
        .frame(width: SpikeStackView.side, height: SpikeStackView.side)
        .ignoresSafeArea()
    }
}

// MARK: - Viewport

/// Canvas (1024 space) ↔ stack view points. Same mapping as a UIScrollView:
/// view = canvas × zoom − offset.
struct SpikeViewport: Equatable {
    var zoom: CGFloat
    var offset: CGPoint

    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom - offset.x, y: p.y * zoom - offset.y) }
    func toCanvas(_ v: CGPoint) -> CGPoint { CGPoint(x: (v.x + offset.x) / zoom, y: (v.y + offset.y) / zoom) }

    /// Keeps zoom in [fit, fit × maxFactor] and the canvas covering the view.
    func clamped(fit: CGFloat, maxFactor: CGFloat, viewSide: CGFloat) -> SpikeViewport {
        let z = min(max(zoom, fit), fit * maxFactor)
        let maxOffset = max(0, SpikeStackView.side * z - viewSide)
        return SpikeViewport(zoom: z, offset: CGPoint(x: min(max(offset.x, 0), maxOffset),
                                                      y: min(max(offset.y, 0), maxOffset)))
    }
}

/// Records where a one-finger touch went down without taking part in gestures.
private final class TouchProbe: UIGestureRecognizer {
    var onBegan: ((CGPoint) -> Void)?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, event.allTouches?.count == 1 { onBegan?(touch.location(in: view)) }
        state = .failed
    }
}

/// A PKCanvasView whose undo manager can be swapped for a disabled one, so
/// PencilKit registers nothing while our own stack is in charge.
final class SpikeInkCanvas: PKCanvasView {
    var undoOverride: UndoManager?
    override var undoManager: UndoManager? { undoOverride ?? super.undoManager }
}

// MARK: - Layer stack

final class SpikeStackView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    nonisolated static let side: CGFloat = 1024
    static let maxZoomFactor: CGFloat = 4

    private let model: SpikeModel
    private let sketch = PKCanvasView()
    private let ink = SpikeInkCanvas()
    private let shapesHost: UIHostingController<SpikeShapesLayer>
    private let pan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()

    private var viewport = SpikeViewport(zoom: 1, offset: .zero)
    private var fit: CGFloat = 1
    private var anchor: (viewport: SpikeViewport, centroid: CGPoint, scale: CGFloat)?

    // Mirror + undo bookkeeping
    private var applying = false
    private var lastInk = PKDrawing()
    private var history: [PKDrawing] = []
    private var future: [PKDrawing] = []
    private var mirrorAppends = 0
    private var cancelledStrokes = 0

    // Touch → stroke alignment
    private var lastTouch: CGPoint?
    private var touchToStroke: CGFloat = -1

    init(model: SpikeModel) {
        self.model = model
        shapesHost = UIHostingController(rootView: SpikeShapesLayer(shapes: model.shapes))
        super.init(frame: .zero)
        backgroundColor = .white

        for canvas in [sketch, ink as PKCanvasView] {
            canvas.drawingPolicy = .anyInput
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.overrideUserInterfaceStyle = .light
            canvas.isScrollEnabled = false            // the stack pans and zooms, not the canvas
            canvas.pinchGestureRecognizer?.isEnabled = false
            canvas.showsVerticalScrollIndicator = false
            canvas.showsHorizontalScrollIndicator = false
            canvas.bouncesZoom = false
            canvas.delegate = self
        }
        sketch.tool = PKInkingTool(.pencil, color: UIColor(Theme.sketchStroke), width: 4)
        ink.tool = PKInkingTool(.monoline, color: UIColor(Theme.ink),
                                width: LineSize.toolWidth(forSize: LineSize.defaultSize))
        if model.undoMode == .own {
            let disabled = UndoManager()
            disabled.disableUndoRegistration()
            ink.undoOverride = disabled
        }

        let host = shapesHost.view!
        host.backgroundColor = .clear
        host.layer.anchorPoint = .zero
        host.bounds = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        shapesHost.safeAreaRegions = []

        addSubview(sketch)       // bottom
        addSubview(host)         // middle
        addSubview(ink)          // top

        for recognizer in [pan, pinch] as [UIGestureRecognizer] {
            recognizer.addTarget(self, action: #selector(navigate(_:)))
            recognizer.delegate = self
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            addGestureRecognizer(recognizer)
        }
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2

        let probe = TouchProbe()
        probe.cancelsTouchesInView = false
        probe.delaysTouchesBegan = false
        probe.delaysTouchesEnded = false
        probe.onBegan = { [weak self] point in self?.lastTouch = point }
        addGestureRecognizer(probe)

        applyActiveLayer()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        sketch.frame = bounds
        ink.frame = bounds
        let newFit = bounds.width / Self.side
        if abs(newFit - fit) > 0.0001 {
            fit = newFit
            for canvas in [sketch, ink as PKCanvasView] {
                canvas.minimumZoomScale = fit
                canvas.maximumZoomScale = fit * Self.maxZoomFactor
            }
            viewport = SpikeViewport(zoom: fit, offset: .zero)
        }
        applyViewport()
    }

    func applyActiveLayer() {
        sketch.isUserInteractionEnabled = model.activeLayer == .sketch
        shapesHost.view.isUserInteractionEnabled = model.activeLayer == .shapes
        ink.isUserInteractionEnabled = model.activeLayer == .ink
        updateStatus()
    }

    // MARK: Two-finger pan / zoom

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private var pinchActive: Bool { pinch.state == .began || pinch.state == .changed }
    private var panActive: Bool { pan.state == .began || pan.state == .changed }
    private var centroid: CGPoint { panActive ? pan.location(in: self) : pinch.location(in: self) }

    @objc private func navigate(_ g: UIGestureRecognizer) {
        switch g.state {
        case .began:
            cancelStrokesInProgress()
            reanchor()
        case .changed:
            guard let anchor else { return }
            let scale = (pinchActive ? pinch.scale : 1) / anchor.scale
            let zoom = anchor.viewport.zoom * scale
            let pinned = anchor.viewport.toCanvas(anchor.centroid)   // canvas point under the fingers
            let now = centroid
            viewport = SpikeViewport(zoom: zoom, offset: CGPoint(x: pinned.x * zoom - now.x, y: pinned.y * zoom - now.y))
                .clamped(fit: fit, maxFactor: Self.maxZoomFactor, viewSide: bounds.width)
            applyViewport()
        default:
            if pinchActive || panActive { reanchor() } else { anchor = nil }
        }
    }

    private func reanchor() {
        anchor = (viewport, centroid, pinchActive ? pinch.scale : 1)
    }

    /// A second finger means navigate, not draw: drop the half-drawn stroke.
    private func cancelStrokesInProgress() {
        for canvas in [sketch, ink as PKCanvasView] where canvas.drawingGestureRecognizer.state != .possible {
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true
            cancelledStrokes += 1
        }
    }

    private func applyViewport() {
        // UIScrollView snaps contentOffset to device pixels. Snap first, then
        // read back what the canvas really applied and give the SwiftUI layer
        // exactly that, so all three layers share one value.
        let pixel = 1 / traitCollection.displayScale
        viewport.offset = CGPoint(x: (viewport.offset.x / pixel).rounded() * pixel,
                                  y: (viewport.offset.y / pixel).rounded() * pixel)
        for canvas in [sketch, ink as PKCanvasView] {
            canvas.zoomScale = viewport.zoom
            canvas.contentSize = CGSize(width: Self.side * viewport.zoom, height: Self.side * viewport.zoom)
            canvas.contentOffset = viewport.offset
        }
        viewport = SpikeViewport(zoom: ink.zoomScale, offset: ink.contentOffset)
        shapesHost.view.layer.position = .zero
        shapesHost.view.transform = CGAffineTransform(a: viewport.zoom, b: 0, c: 0, d: viewport.zoom,
                                                      tx: -viewport.offset.x, ty: -viewport.offset.y)
        updateStatus()
    }

    /// Largest disagreement, in view points, between where the three layers
    /// actually put the same canvas points (read back from the live views).
    private func alignmentError() -> CGFloat {
        let probes = [CGPoint(x: 0, y: 0), CGPoint(x: 512, y: 512), CGPoint(x: 100, y: 900), CGPoint(x: 1024, y: 1024)]
        var worst: CGFloat = 0
        for p in probes {
            let viaShapes = shapesHost.view.convert(p, to: self)
            for canvas in [sketch, ink as PKCanvasView] {
                let v = CGPoint(x: p.x * canvas.zoomScale - canvas.contentOffset.x + canvas.frame.minX,
                                y: p.y * canvas.zoomScale - canvas.contentOffset.y + canvas.frame.minY)
                worst = max(worst, hypot(v.x - viaShapes.x, v.y - viaShapes.y))
            }
        }
        return worst
    }

    // MARK: Drawing, mirror, undo

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        if canvasView === ink, !applying { inkChangedByUser() }
        updateStatus()
    }

    private func inkChangedByUser() {
        let before = lastInk
        var drawing = ink.drawing
        let added = drawing.strokes.count == lastInk.strokes.count + 1
        if added, let stroke = drawing.strokes.last, let touch = lastTouch, let first = stroke.path.first {
            let canvasPoint = first.location.applying(stroke.transform)
            let view = shapesHost.view.convert(canvasPoint, to: self)
            touchToStroke = hypot(view.x - touch.x, view.y - touch.y)
        }
        if model.mirror, added, let stroke = drawing.strokes.last {
            drawing.strokes.append(Self.mirrored(stroke))
            set(drawing)
            mirrorAppends += 1
        }
        if model.undoMode == .own {
            history.append(before)   // one entry for the stroke and its mirror
            future.removeAll()
        }
        lastInk = ink.drawing
    }

    /// Flip around x = 512, kept as a transform so points and widths are untouched.
    static func mirrored(_ stroke: PKStroke) -> PKStroke {
        var copy = stroke
        copy.transform = stroke.transform.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: side, ty: 0))
        return copy
    }

    private func set(_ drawing: PKDrawing) {
        applying = true
        ink.drawing = drawing
        applying = false
        lastInk = drawing
    }

    func undo() {
        switch model.undoMode {
        case .pencilKit:
            ink.undoManager?.undo()
        case .own:
            guard let previous = history.popLast() else { return }
            future.append(ink.drawing)
            set(previous)
        }
        updateStatus()
    }

    func redo() {
        switch model.undoMode {
        case .pencilKit:
            ink.undoManager?.redo()
        case .own:
            guard let next = future.popLast() else { return }
            history.append(ink.drawing)
            set(next)
        }
        updateStatus()
    }

    func clear() {
        set(PKDrawing())
        sketch.drawing = PKDrawing()
        history.removeAll()
        future.removeAll()
        mirrorAppends = 0
        model.shapes.square = CGPoint(x: 260, y: 260)
        model.shapes.moves = 0
        updateStatus()
    }

    // MARK: Status (parsed by CanvasSpikeUITests)

    func updateStatus() {
        let stored = ink.drawing.strokes.last?.path.first?.size.width ?? 0
        let pkUndo = super.undoManager ?? window?.undoManager
        model.status = [
            "layer=\(model.activeLayer.rawValue)",
            "sketch=\(sketch.drawing.strokes.count)",
            "ink=\(ink.drawing.strokes.count)",
            "mirrorAppends=\(mirrorAppends)",
            "history=\(history.count)",
            "pkCanUndo=\(pkUndo?.canUndo == true ? 1 : 0)",
            String(format: "square=%.0f,%.0f", model.shapes.square.x, model.shapes.square.y),
            "squareMoves=\(model.shapes.moves)",
            String(format: "zoomx=%.2f", viewport.zoom / fit),
            String(format: "canvasZoom=%.3f", ink.zoomScale),
            String(format: "offset=%.0f,%.0f", viewport.offset.x, viewport.offset.y),
            String(format: "align=%.3f", alignmentError()),
            String(format: "touch=%.2f", touchToStroke),
            String(format: "stored=%.2f", stored),
            "cancelled=\(cancelledStrokes)",
        ].joined(separator: " ")
    }
}
#endif
