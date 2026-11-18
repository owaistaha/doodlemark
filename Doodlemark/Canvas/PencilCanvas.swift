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
    /// Path bounds of the selected shape while the Shapes tool is on (canvas space).
    var selection: CGRect?
    var snapGuides: SnapGuides
}

extension CanvasModel {
    var stackConfig: CanvasStackConfig {
        CanvasStackConfig(tool: tool, activeLayer: activeLayer,
                          inkToolWidth: LineSize.toolWidth(forSize: lineSize), inkColor: penColor,
                          hiddenLayers: hiddenLayers, pencilOnly: pencilOnly, gridOn: gridOn,
                          mirrorOn: mirrorOn, fitRequest: fitRequest, restoreRequest: restoreRequest,
                          selection: tool == .shapes && !hiddenLayers.contains(.shapes)
                              ? selectedShape.map(ShapeEditing.bounds(of:)) : nil,
                          snapGuides: snapGuides)
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
/// - With the Shapes tool: tap picks a shape, one finger drags it or a corner
///   handle, and two fingers that start on the picked shape move, resize and
///   turn it instead of the canvas. Each gesture is one undo step.
final class CanvasStackView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    /// Sketch pencil width (PencilKit pencil ink; not exported, so no law needed).
    static let sketchPencilWidth: CGFloat = 12
    /// Touch distances in view points, so they feel the same at any zoom.
    /// A corner handle takes touches within this radius (a 64 pt target).
    static let handleHitRadius: CGFloat = 32
    /// Taps this close outside a shape's path bounds still pick it.
    static let shapeSlop: CGFloat = 8
    /// A moved shape's centre snaps to x = 512 / y = 512 within this.
    static let snapDistance: CGFloat = 10
    /// Two fingers whose midpoint is within this of the picked shape's bounds
    /// work on the shape; anywhere else they pan and zoom the canvas.
    static let twoFingerReach: CGFloat = 40

    private let model: CanvasModel
    private let history: HistoryUndoManager
    private let gridView = GridOverlayView()
    private let sketchCanvas = HistoryCanvasView()
    private let inkCanvas = HistoryCanvasView()
    private let shapesHost: UIHostingController<ShapesLayer>
    private let textHost: UIHostingController<TextLayer>
    private let mirrorGuide = MirrorGuideView()
    private let selectionView = ShapeSelectionView()
    private let pan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private let rotation = UIRotationGestureRecognizer()
    private let undoTap = UITapGestureRecognizer()
    private let redoTap = UITapGestureRecognizer()
    private let shapeTap = UITapGestureRecognizer()
    private let shapeDrag = UIPanGestureRecognizer()

    /// What a one-finger drag with the Shapes tool does, decided where it starts.
    private enum ShapeDrag {
        case move(LogoShape)
        case resize(LogoShape, handle: CGPoint)
    }
    private var shapeDragMode: ShapeDrag?
    /// Where the drag's finger came down. Measured from here, not with the
    /// pan's `translation`, which leaves out the ~10 pt it takes to start.
    private var shapeDragStart = CGPoint.zero

    /// What the current two-finger gesture works on, decided when it starts.
    private enum TwoFinger {
        case viewport
        case shape(ShapeSession)
    }
    /// Two fingers on the picked shape, accumulated from the recognizers'
    /// increments so a finger lifting or landing never makes it jump.
    private struct ShapeSession {
        var start: LogoShape
        var lastCentroid: CGPoint
        var translation = CGPoint.zero
        var scale: CGFloat = 1
        var rotation: Double = 0
    }
    private var twoFinger: TwoFinger?

    private var config: CanvasStackConfig?
    private var viewport = CanvasViewport(zoom: 1, offset: .zero)
    /// The viewport PencilKit actually applied (what every layer shows).
    private var shown = CanvasViewport(zoom: 1, offset: .zero)
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
        selectionView.isUserInteractionEnabled = false

        // Bottom to top: grid, Sketch, Shapes, Ink, Text (PRD layer order), mirror guide.
        addSubview(gridView)
        addSubview(sketchCanvas)
        addSubview(shapesHost.view)
        addSubview(inkCanvas)
        addSubview(textHost.view)
        addSubview(mirrorGuide)
        addSubview(selectionView)

        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for recognizer in [pan, pinch, rotation] as [UIGestureRecognizer] {
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
            tap.require(toFail: rotation)
            addGestureRecognizer(tap)
        }

        // Shapes tool: any finger, Pencil or stylus picks and moves shapes.
        shapeTap.addTarget(self, action: #selector(shapeTapped))
        shapeDrag.addTarget(self, action: #selector(dragShape))
        shapeDrag.maximumNumberOfTouches = 1
        for recognizer in [shapeTap, shapeDrag] as [UIGestureRecognizer] {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
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
        selectionView.selection = new.selection
        selectionView.guides = new.snapGuides

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
        for view in [gridView, sketchCanvas, inkCanvas, mirrorGuide, selectionView] as [UIView] { view.frame = bounds }
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
        // Pan, pinch and rotation run alongside each other and alongside
        // PencilKit's drawing recognizer (which starts on the first finger;
        // navigating then cancels the stroke). A shape drag keeps running when
        // a second finger lands; the two-finger gesture then takes over. The
        // taps aren't delegates: they wait for pan, pinch and rotation to fail.
        g === pan || g === pinch || g === rotation || g === shapeDrag
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if g === shapeDrag, g.state == .possible, g.numberOfTouches == 0 {
            shapeDragStart = touch.location(in: self)
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === shapeTap { return shapesEditable }
        if g === shapeDrag { return shapesEditable && prepareShapeDrag() }
        if g === rotation { return shapesEditable && model.selectedShape != nil }
        return super.gestureRecognizerShouldBegin(g)
    }

    private var pinchActive: Bool { pinch.state == .began || pinch.state == .changed }
    private var panActive: Bool { pan.state == .began || pan.state == .changed }
    private var rotationActive: Bool { rotation.state == .began || rotation.state == .changed }
    private var centroid: CGPoint {
        if panActive { return pan.location(in: self) }
        if pinchActive { return pinch.location(in: self) }
        return rotation.location(in: self)
    }

    @objc private func navigate(_ g: UIGestureRecognizer) {
        if g.state == .began, twoFinger == nil { twoFinger = startTwoFinger() }
        guard let mode = twoFinger else { return }

        switch mode {
        case .viewport:
            guard g !== rotation else { break }
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
                if pinchActive || panActive { reanchor() }
            }

        case .shape(var session):
            let now = centroid
            if g.state == .changed {
                session.translation.x += (now.x - session.lastCentroid.x) / shown.zoom
                session.translation.y += (now.y - session.lastCentroid.y) / shown.zoom
            }
            // A finger landing or lifting moves the midpoint: re-base, don't jump.
            session.lastCentroid = now
            if g === pinch, g.state == .began || g.state == .changed {
                session.scale *= pinch.scale
                pinch.scale = 1
            }
            if g === rotation, g.state == .began || g.state == .changed {
                session.rotation += Double(rotation.rotation)
                rotation.rotation = 0
            }
            let result = ShapeEditing.transformed(session.start, translation: session.translation,
                                                  scale: session.scale, rotation: session.rotation,
                                                  snapDistance: Self.snapDistance / shown.zoom)
            model.updateShape(result.shape, guides: result.guides)
            twoFinger = .shape(session)
        }

        if !(panActive || pinchActive || rotationActive) {
            if case .shape = mode { model.endShapeEdit() }
            twoFinger = nil
            anchor = nil
        }
    }

    /// Two fingers came down: on the picked shape they edit it, anywhere else
    /// they pan and zoom. Either way a one-finger shape drag stops here.
    private func startTwoFinger() -> TwoFinger {
        if shapesEditable, let shape = model.selectedShape {
            let reach = Self.twoFingerReach / shown.zoom
            if ShapeEditing.bounds(of: shape).insetBy(dx: -reach, dy: -reach).contains(shown.toCanvas(centroid)) {
                model.beginShapeEdit()          // before the drag ends: one undo step for both
                cancelShapeDrag()
                return .shape(ShapeSession(start: shape, lastCentroid: centroid))
            }
        }
        cancelShapeDrag()
        return .viewport
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
        shown = applied
        gridView.viewport = applied
        mirrorGuide.viewport = applied
        selectionView.viewport = applied
        // Report the zoom after the current SwiftUI update, never during it.
        let factor = applied.zoomFactor(viewSide: side)
        if abs(model.zoomFactor - factor) > 0.001 {
            DispatchQueue.main.async { [model] in model.zoomFactor = factor }
        }
    }

    // MARK: Shapes (one finger)

    private var shapesEditable: Bool {
        guard let config else { return false }
        return config.tool == .shapes && !config.hiddenLayers.contains(.shapes)
    }

    /// Tap: pick the shape under the finger, or nothing. A tap on a handle
    /// of the picked shape keeps it.
    @objc private func shapeTapped(_ g: UITapGestureRecognizer) {
        let point = g.location(in: self)
        if handle(near: point) != nil { return }
        model.selectShape(ShapeEditing.hitTest(shown.toCanvas(point), in: model.project.shapes,
                                               slop: Self.shapeSlop / shown.zoom))
    }

    /// The picked shape's corner handle within reach of `point` (view space).
    private func handle(near point: CGPoint) -> CGPoint? {
        guard let shape = model.selectedShape else { return nil }
        return ShapeEditing.handles(of: shape).first { handle in
            let v = shown.toView(handle)
            return hypot(v.x - point.x, v.y - point.y) <= Self.handleHitRadius
        }
    }

    /// Where a drag starts decides what it does: a corner handle of the picked
    /// shape resizes it, a shape moves it (and picks it), empty canvas does nothing.
    private func prepareShapeDrag() -> Bool {
        let start = shapeDragStart
        if let shape = model.selectedShape, let handle = handle(near: start) {
            shapeDragMode = .resize(shape, handle: handle)
            return true
        }
        guard let id = ShapeEditing.hitTest(shown.toCanvas(start), in: model.project.shapes,
                                            slop: Self.shapeSlop / shown.zoom),
              let shape = model.project.shapes.first(where: { $0.id == id }) else { return false }
        shapeDragMode = .move(shape)
        return true
    }

    @objc private func dragShape(_ g: UIPanGestureRecognizer) {
        guard let mode = shapeDragMode else { return }
        switch g.state {
        case .began, .changed:
            if g.state == .began {
                model.beginShapeEdit()
                if case .move(let shape) = mode { model.selectShape(shape.id) }
            }
            let location = g.location(in: self)
            let delta = CGPoint(x: (location.x - shapeDragStart.x) / shown.zoom,
                                y: (location.y - shapeDragStart.y) / shown.zoom)
            switch mode {
            case .move(let start):
                let result = ShapeEditing.moved(start, by: delta, snapDistance: Self.snapDistance / shown.zoom)
                model.updateShape(result.shape, guides: result.guides)
            case .resize(let start, let handle):
                let finger = CGPoint(x: handle.x + delta.x, y: handle.y + delta.y)
                model.updateShape(ShapeEditing.scaled(start, handle: handle, finger: finger))
            }
        default:
            shapeDragMode = nil
            model.endShapeEdit()
        }
    }

    private func cancelShapeDrag() {
        guard shapeDrag.state == .began || shapeDrag.state == .changed else { return }
        shapeDrag.isEnabled = false
        shapeDrag.isEnabled = true
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

/// The picked shape's path bounds with four corner handles, and the canvas
/// centre lines while a moved shape is snapped to them. Drawn in view space
/// so handles stay the same size at any zoom. On screen only.
final class ShapeSelectionView: UIView {
    static let handleDiameter: CGFloat = 26
    static let lineWidth: CGFloat = 2

    var viewport = CanvasViewport(zoom: 1, offset: .zero) { didSet { setNeedsDisplay() } }
    var selection: CGRect? { didSet { if selection != oldValue { setNeedsDisplay() } } }
    var guides = SnapGuides() { didSet { if guides != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setLineWidth(Self.lineWidth)

        let side = CanvasViewport.canvasSide, mid = side / 2
        cg.setStrokeColor(UIColor(Theme.tangerine).cgColor)
        if guides.vertical {
            cg.move(to: viewport.toView(CGPoint(x: mid, y: 0)))
            cg.addLine(to: viewport.toView(CGPoint(x: mid, y: side)))
        }
        if guides.horizontal {
            cg.move(to: viewport.toView(CGPoint(x: 0, y: mid)))
            cg.addLine(to: viewport.toView(CGPoint(x: side, y: mid)))
        }
        cg.strokePath()

        guard let selection else { return }
        let a = viewport.toView(selection.origin)
        let b = viewport.toView(CGPoint(x: selection.maxX, y: selection.maxY))
        let box = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        cg.setStrokeColor(UIColor(Theme.pencilBlue).cgColor)
        cg.stroke(box)
        let d = Self.handleDiameter
        for corner in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)] {
            let dot = CGRect(x: corner.x - d / 2, y: corner.y - d / 2, width: d, height: d)
                .insetBy(dx: Self.lineWidth / 2, dy: Self.lineWidth / 2)
            cg.setFillColor(UIColor(Theme.surface).cgColor)
            cg.fillEllipse(in: dot)
            cg.strokeEllipse(in: dot)
        }
    }
}

