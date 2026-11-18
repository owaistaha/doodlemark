import PencilKit
import SwiftUI

/// What the layer stack needs from the editor, as one value so SwiftUI hands
/// over every change through `updateUIView`.
struct CanvasStackConfig: Equatable {
    var tool: CanvasTool
    var activeLayer: CanvasLayer
    var inkToolWidth: CGFloat
    var inkColor: HexColor
    var hiddenLayers: Set<CanvasLayer>
    var pencilOnly: Bool
    var gridOn: Bool
    var mirrorOn: Bool
    var fitRequest: Int
    var restoreRequest: Int
}

extension CanvasModel {
    var stackConfig: CanvasStackConfig {
        CanvasStackConfig(tool: tool, activeLayer: activeLayer,
                          inkToolWidth: LineSize.toolWidth(forSize: lineSize), inkColor: penColor,
                          hiddenLayers: hiddenLayers, pencilOnly: pencilOnly, gridOn: gridOn,
                          mirrorOn: mirrorOn, fitRequest: fitRequest, restoreRequest: restoreRequest)
    }
}

/// The square canvas: Sketch, Shapes, Ink and Text layers stacked in 1024
/// canvas space. Structure proven by the step 4a spike (RISKS.md #4).
struct PencilCanvas: UIViewRepresentable {
    let model: CanvasModel
    let config: CanvasStackConfig

    func makeUIView(context: Context) -> CanvasStackView {
        let view = CanvasStackView(model: model)
        view.apply(config)
        return view
    }

    func updateUIView(_ view: CanvasStackView, context: Context) {
        view.apply(config)
    }
}

/// A PKCanvasView that hands PencilKit our undo manager, whose registration
/// is off, so PencilKit keeps no undo history of its own (RISKS.md #1).
final class HistoryCanvasView: PKCanvasView {
    var historyUndoManager: UndoManager?
    override var undoManager: UndoManager? { historyUndoManager }
}

/// UIKit owner of the layer stack.
///
/// - Each PencilKit canvas zooms itself (`zoomScale`/`contentOffset`), so ink
///   stays sharp at any zoom. Their own scrolling and pinch are off.
/// - The SwiftUI Shapes/Text layers are 1024×1024 views with a zoom/offset
///   transform, so their gestures work in canvas units.
/// - Only the active layer takes touches. Touches fall through hidden or
///   inactive layers above it.
/// - Two fingers pan/zoom everything through one `CanvasViewport`.
/// - Two-finger tap = undo, three-finger tap = redo; ⌘Z, ⇧⌘Z and the system
///   undo gestures reach the same history through `HistoryUndoManager`.
final class CanvasStackView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    /// Sketch pencil width (PencilKit pencil ink; not exported, so no law needed).
    static let sketchPencilWidth: CGFloat = 12

    private let model: CanvasModel
    private let history: HistoryUndoManager
    private let gridView = GridOverlayView()
    private let sketchCanvas = HistoryCanvasView()
    private let inkCanvas = HistoryCanvasView()
    private let shapesHost: UIHostingController<ShapesLayer>
    private let textHost: UIHostingController<TextLayer>
    private let mirrorGuide = MirrorGuideView()
    private let pan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private let undoTap = UITapGestureRecognizer()
    private let redoTap = UITapGestureRecognizer()

    private var config: CanvasStackConfig?
    private var viewport = CanvasViewport(zoom: 1, offset: .zero)
    private var side: CGFloat = 0
    private var anchor: (viewport: CanvasViewport, centroid: CGPoint, scale: CGFloat)?
    /// True while we set a canvas's drawing ourselves, so the delegate ignores it.
    private var applying = false

    init(model: CanvasModel) {
        self.model = model
        history = HistoryUndoManager(model: model)
        shapesHost = UIHostingController(rootView: ShapesLayer(model: model))
        textHost = UIHostingController(rootView: TextLayer(model: model))
        super.init(frame: .zero)
        backgroundColor = UIColor(Theme.surface)
        clipsToBounds = true

        for canvas in [sketchCanvas, inkCanvas] {
            canvas.historyUndoManager = history
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.overrideUserInterfaceStyle = .light      // no dark-mode ink inversion
            canvas.isScrollEnabled = false                  // the stack pans and zooms
            canvas.pinchGestureRecognizer?.isEnabled = false
            canvas.showsVerticalScrollIndicator = false
            canvas.showsHorizontalScrollIndicator = false
            canvas.bouncesZoom = false
            canvas.contentInsetAdjustmentBehavior = .never
            canvas.delegate = self
        }
        sketchCanvas.drawing = model.sketch
        inkCanvas.drawing = model.ink

        for host in [shapesHost.view!, textHost.view!] {
            host.backgroundColor = .clear
            host.layer.anchorPoint = .zero
            host.bounds = CGRect(x: 0, y: 0, width: CanvasViewport.canvasSide, height: CanvasViewport.canvasSide)
        }
        shapesHost.safeAreaRegions = []
        textHost.safeAreaRegions = []
        gridView.isUserInteractionEnabled = false
        mirrorGuide.isUserInteractionEnabled = false

        // Bottom to top: grid, Sketch, Shapes, Ink, Text (PRD layer order), mirror guide.
        addSubview(gridView)
        addSubview(sketchCanvas)
        addSubview(shapesHost.view)
        addSubview(inkCanvas)
        addSubview(textHost.view)
        addSubview(mirrorGuide)

        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for recognizer in [pan, pinch] as [UIGestureRecognizer] {
            recognizer.addTarget(self, action: #selector(navigate(_:)))
            recognizer.delegate = self
            recognizer.allowedTouchTypes = fingers
            addGestureRecognizer(recognizer)
        }
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2

        // Taps wait for pan and pinch to fail, so a pinch never undoes. A tap
        // also fails as soon as a finger moves, so a stroke in progress
        // (one finger already moving) can't turn into a tap.
        undoTap.numberOfTouchesRequired = 2
        redoTap.numberOfTouchesRequired = 3
        undoTap.addTarget(self, action: #selector(undoTapped))
        redoTap.addTarget(self, action: #selector(redoTapped))
        for tap in [undoTap, redoTap] {
            tap.allowedTouchTypes = fingers
            tap.require(toFail: pan)
            tap.require(toFail: pinch)
            addGestureRecognizer(tap)
        }

        isAccessibilityElement = true
        accessibilityIdentifier = "canvasStack"
        accessibilityLabel = "Canvas"
        accessibilityTraits = .allowsDirectInteraction
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Undo for the system (⌘Z, Edit menu, three-finger gestures)

    override var undoManager: UndoManager? { history }
    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    @objc private func undoTapped() { model.undo() }
    @objc private func redoTapped() { model.redo() }

    // MARK: Config from SwiftUI

    func apply(_ new: CanvasStackConfig) {
        let old = config
        config = new

        let policy: PKCanvasViewDrawingPolicy = new.pencilOnly ? .pencilOnly : .anyInput
        sketchCanvas.drawingPolicy = policy
        inkCanvas.drawingPolicy = policy

        sketchCanvas.tool = new.tool == .eraser
            ? PKEraserTool(.vector)
            : PKInkingTool(.pencil, color: UIColor(Theme.sketchStroke), width: Self.sketchPencilWidth)
        // Ink: monoline pen and vector eraser only (CLAUDE.md hard rule).
        inkCanvas.tool = new.tool == .eraser
            ? PKEraserTool(.vector)
            : PKInkingTool(.monoline, color: UIColor(cgColor: new.inkColor.cgColor), width: new.inkToolWidth)

        sketchCanvas.isHidden = new.hiddenLayers.contains(.sketch)
        shapesHost.view.isHidden = new.hiddenLayers.contains(.shapes)
        inkCanvas.isHidden = new.hiddenLayers.contains(.ink)
        textHost.view.isHidden = new.hiddenLayers.contains(.text)
        gridView.isHidden = !new.gridOn
        mirrorGuide.isHidden = !new.mirrorOn

        // One-finger touches go to the active layer only. Shapes and Text get
        // their gestures in step 5; until then they take no touches.
        sketchCanvas.isUserInteractionEnabled = new.activeLayer == .sketch && !sketchCanvas.isHidden
        inkCanvas.isUserInteractionEnabled = new.activeLayer == .ink && !inkCanvas.isHidden
        shapesHost.view.isUserInteractionEnabled = false
        textHost.view.isUserInteractionEnabled = false

        if let old, old.restoreRequest != new.restoreRequest {
            set(sketchCanvas, to: model.sketch)
            set(inkCanvas, to: model.ink)
            updateAccessibilityValue()
        }
        if let old, old.fitRequest != new.fitRequest, side > 0 {
            viewport = .fitted(viewSide: side)
            applyViewport()
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        for view in [gridView, sketchCanvas, inkCanvas, mirrorGuide] as [UIView] { view.frame = bounds }
        if abs(bounds.width - side) > 0.001 {
            // Keep the same zoom factor and centre when the square resizes (rotation).
            let factor = side > 0 ? viewport.zoomFactor(viewSide: side) : 1
            let centre = side > 0 ? viewport.toCanvas(CGPoint(x: side / 2, y: side / 2))
                                  : CGPoint(x: CanvasViewport.canvasSide / 2, y: CanvasViewport.canvasSide / 2)
            side = bounds.width
            let fit = side / CanvasViewport.canvasSide
            for canvas in [sketchCanvas, inkCanvas] {
                canvas.minimumZoomScale = fit
                canvas.maximumZoomScale = fit * CanvasViewport.maxZoomFactor
            }
            let zoom = fit * factor
            viewport = CanvasViewport(zoom: zoom, offset: CGPoint(x: centre.x * zoom - side / 2,
                                                                  y: centre.y * zoom - side / 2))
        }
        applyViewport()
    }

    // MARK: Two-finger pan / zoom

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pan and pinch run alongside each other and alongside PencilKit's
        // drawing recognizer (which starts on the first finger; navigating then
        // cancels the stroke). The taps aren't delegates: they wait for pan and
        // pinch to fail instead.
        g === pan || g === pinch
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
            viewport = anchor.viewport.navigated(scale: scale, anchor: anchor.centroid, centroid: centroid)
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
        for canvas in [sketchCanvas, inkCanvas] where canvas.drawingGestureRecognizer.state != .possible {
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true
        }
    }

    private func applyViewport() {
        guard side > 0 else { return }
        viewport = viewport.clamped(viewSide: side, pixel: 1 / traitCollection.displayScale)
        for canvas in [sketchCanvas, inkCanvas] {
            canvas.zoomScale = viewport.zoom
            canvas.contentSize = CGSize(width: CanvasViewport.canvasSide * viewport.zoom,
                                        height: CanvasViewport.canvasSide * viewport.zoom)
            canvas.contentOffset = viewport.offset
        }
        // Give the other layers exactly what PencilKit applied.
        let applied = CanvasViewport(zoom: inkCanvas.zoomScale, offset: inkCanvas.contentOffset)
        let transform = CGAffineTransform(a: applied.zoom, b: 0, c: 0, d: applied.zoom,
                                          tx: -applied.offset.x, ty: -applied.offset.y)
        for host in [shapesHost.view!, textHost.view!] {
            host.layer.position = .zero
            host.transform = transform
        }
        gridView.viewport = applied
        mirrorGuide.viewport = applied
        // Report the zoom after the current SwiftUI update, never during it.
        let factor = applied.zoomFactor(viewSide: side)
        if abs(model.zoomFactor - factor) > 0.001 {
            DispatchQueue.main.async { [model] in model.zoomFactor = factor }
        }
    }

    // MARK: Drawing

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        model.beginToolUse()
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        model.endToolUse()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !applying else { return }
        if canvasView === sketchCanvas {
            model.sketchDidChange(canvasView.drawing)
        } else if canvasView === inkCanvas {
            // Smoothing and Mirror happen in the model; show its result.
            let shown = model.inkDidChange(canvasView.drawing)
            if shown != canvasView.drawing { set(inkCanvas, to: shown) }
        }
        updateAccessibilityValue()
    }

    private func set(_ canvas: PKCanvasView, to drawing: PKDrawing) {
        guard canvas.drawing != drawing else { return }
        applying = true
        canvas.drawing = drawing
        applying = false
    }

    private func updateAccessibilityValue() {
        func lines(_ n: Int) -> String { n == 1 ? "1 line" : "\(n) lines" }
        accessibilityValue = "Sketch: \(lines(sketchCanvas.drawing.strokes.count)). Ink: \(lines(inkCanvas.drawing.strokes.count))."
    }
}

// MARK: - Guides (on screen only, never exported)

/// The Grid: a 10 × 10 grid over the 1024 canvas (one line falls on the
/// mirror axis). Drawn in view space so lines stay 1 pt at any zoom.
final class GridOverlayView: UIView {
    static let divisions = 10

    var viewport = CanvasViewport(zoom: 1, offset: .zero) { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setStrokeColor(UIColor(Theme.line).cgColor)
        cg.setLineWidth(Theme.Metrics.hairline)
        let step = CanvasViewport.canvasSide / CGFloat(Self.divisions)
        for i in 1..<Self.divisions {
            let c = CGFloat(i) * step
            let v = viewport.toView(CGPoint(x: c, y: c))
            let start = viewport.toView(.zero)
            let end = viewport.toView(CGPoint(x: CanvasViewport.canvasSide, y: CanvasViewport.canvasSide))
            cg.move(to: CGPoint(x: v.x, y: start.y)); cg.addLine(to: CGPoint(x: v.x, y: end.y))
            cg.move(to: CGPoint(x: start.x, y: v.y)); cg.addLine(to: CGPoint(x: end.x, y: v.y))
        }
        cg.strokePath()
    }
}

/// Mirror's axis: a dashed pencil-blue line at x = 512.
final class MirrorGuideView: UIView {
    static let lineWidth: CGFloat = 2
    static let dash: [CGFloat] = [8, 6]

    var viewport = CanvasViewport(zoom: 1, offset: .zero) { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let top = viewport.toView(CGPoint(x: Symmetry.axisX, y: 0))
        let bottom = viewport.toView(CGPoint(x: Symmetry.axisX, y: CanvasViewport.canvasSide))
        cg.setStrokeColor(UIColor(Theme.pencilBlue).cgColor)
        cg.setLineWidth(Self.lineWidth)
        cg.setLineDash(phase: 0, lengths: Self.dash)
        cg.move(to: top)
        cg.addLine(to: bottom)
        cg.strokePath()
    }
}
