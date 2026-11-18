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
    var fitRequest: Int
}

extension CanvasModel {
    var stackConfig: CanvasStackConfig {
        CanvasStackConfig(tool: tool, activeLayer: activeLayer,
                          inkToolWidth: LineSize.toolWidth(forSize: lineSize), inkColor: penColor,
                          hiddenLayers: hiddenLayers, pencilOnly: pencilOnly, fitRequest: fitRequest)
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

/// UIKit owner of the layer stack.
///
/// - Each PencilKit canvas zooms itself (`zoomScale`/`contentOffset`), so ink
///   stays sharp at any zoom. Their own scrolling and pinch are off.
/// - The SwiftUI Shapes/Text layers are 1024×1024 views with a zoom/offset
///   transform, so their gestures work in canvas units.
/// - Only the active layer takes touches. Touches fall through hidden or
///   inactive layers above it.
/// - Two fingers pan/zoom everything through one `CanvasViewport`.
final class CanvasStackView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    /// Sketch pencil width (PencilKit pencil ink; not exported, so no law needed).
    static let sketchPencilWidth: CGFloat = 12

    private let model: CanvasModel
    private let sketchCanvas = PKCanvasView()
    private let inkCanvas = PKCanvasView()
    private let shapesHost: UIHostingController<ShapesLayer>
    private let textHost: UIHostingController<TextLayer>
    private let pan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()

    private var config: CanvasStackConfig?
    private var viewport = CanvasViewport(zoom: 1, offset: .zero)
    private var side: CGFloat = 0
    private var anchor: (viewport: CanvasViewport, centroid: CGPoint, scale: CGFloat)?

    init(model: CanvasModel) {
        self.model = model
        shapesHost = UIHostingController(rootView: ShapesLayer(model: model))
        textHost = UIHostingController(rootView: TextLayer(model: model))
        super.init(frame: .zero)
        backgroundColor = UIColor(Theme.surface)
        clipsToBounds = true

        for canvas in [sketchCanvas, inkCanvas] {
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

        // Bottom to top: Sketch, Shapes, Ink, Text (PRD layer order).
        addSubview(sketchCanvas)
        addSubview(shapesHost.view)
        addSubview(inkCanvas)
        addSubview(textHost.view)

        for recognizer in [pan, pinch] as [UIGestureRecognizer] {
            recognizer.addTarget(self, action: #selector(navigate(_:)))
            recognizer.delegate = self
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            addGestureRecognizer(recognizer)
        }
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2

        isAccessibilityElement = true
        accessibilityIdentifier = "canvasStack"
        accessibilityLabel = "Canvas"
        accessibilityTraits = .allowsDirectInteraction
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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

        // One-finger touches go to the active layer only. Shapes and Text get
        // their gestures in step 5; until then they take no touches.
        sketchCanvas.isUserInteractionEnabled = new.activeLayer == .sketch && !sketchCanvas.isHidden
        inkCanvas.isUserInteractionEnabled = new.activeLayer == .ink && !inkCanvas.isHidden
        shapesHost.view.isUserInteractionEnabled = false
        textHost.view.isUserInteractionEnabled = false

        if let old, old.fitRequest != new.fitRequest, side > 0 {
            viewport = .fitted(viewSide: side)
            applyViewport()
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        sketchCanvas.frame = bounds
        inkCanvas.frame = bounds
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
        // Give the SwiftUI layers exactly what PencilKit applied.
        let applied = CanvasViewport(zoom: inkCanvas.zoomScale, offset: inkCanvas.contentOffset)
        let transform = CGAffineTransform(a: applied.zoom, b: 0, c: 0, d: applied.zoom,
                                          tx: -applied.offset.x, ty: -applied.offset.y)
        for host in [shapesHost.view!, textHost.view!] {
            host.layer.position = .zero
            host.transform = transform
        }
        // Report the zoom after the current SwiftUI update, never during it.
        let factor = applied.zoomFactor(viewSide: side)
        if abs(model.zoomFactor - factor) > 0.001 {
            DispatchQueue.main.async { [model] in model.zoomFactor = factor }
        }
    }

    // MARK: Drawing

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        if canvasView === sketchCanvas { model.sketch = canvasView.drawing }
        if canvasView === inkCanvas { model.ink = canvasView.drawing }
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        func lines(_ n: Int) -> String { n == 1 ? "1 line" : "\(n) lines" }
        accessibilityValue = "Sketch: \(lines(sketchCanvas.drawing.strokes.count)). Ink: \(lines(inkCanvas.drawing.strokes.count))."
    }
}
