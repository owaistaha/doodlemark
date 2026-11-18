import Observation
import PencilKit
import SwiftUI

/// The tools in the left rail, top to bottom.
enum CanvasTool: String, CaseIterable, Identifiable {
    case sketch, ink, shapes, text, eraser
    var id: Self { self }

    var title: String {
        switch self {
        case .sketch: "Sketch"
        case .ink: "Ink"
        case .shapes: "Shapes"
        case .text: "Text"
        case .eraser: "Eraser"
        }
    }

    /// SF Symbols, line style (DESIGN.md → Icons).
    var symbol: String {
        switch self {
        case .sketch: "pencil"
        case .ink: "paintbrush.pointed"
        case .shapes: "square.on.circle"
        case .text: "textformat"
        case .eraser: "eraser"
        }
    }
}

/// The four fixed layers, in panel order (top of the stack first).
enum CanvasLayer: String, CaseIterable, Identifiable {
    case text, ink, shapes, sketch
    var id: Self { self }

    var title: String {
        switch self {
        case .text: "Text"
        case .ink: "Ink"
        case .shapes: "Shapes"
        case .sketch: "Sketch"
        }
    }
}

/// Editor state for one project, including the one undo history for all
/// four layers. Saving comes in step 6.
@MainActor @Observable
final class CanvasModel {
    nonisolated static let pencilOnlyKey = "pencilOnly"
    nonisolated static let smoothLinesKey = "smoothLines"

    var project: Project
    var sketch = PKDrawing()
    var ink = PKDrawing()

    private(set) var tool: CanvasTool = .ink
    /// The drawing layer the eraser works on: whichever of Sketch/Ink was used last.
    private(set) var eraserLayer: CanvasLayer = .ink
    /// "Line size": drawn thickness in canvas space. Converted only by `LineSize`.
    var lineSize: CGFloat = LineSize.defaultSize
    /// The selected palette color: the Ink pen draws with it and new shapes
    /// are filled with it. Starts on the second slot, the darkest in every
    /// curated palette.
    private(set) var currentSlot: PaletteSlot = .second
    var hiddenLayers: Set<CanvasLayer> = []
    /// "Pencil only": off by default, remembered across launches (TECH_SPEC → Input).
    var pencilOnly: Bool = UserDefaults.standard.bool(forKey: CanvasModel.pencilOnlyKey) {
        didSet { UserDefaults.standard.set(pencilOnly, forKey: Self.pencilOnlyKey) }
    }
    /// "Smooth my lines": Ink only, on by default, remembered across launches.
    var smoothLines: Bool = UserDefaults.standard.object(forKey: CanvasModel.smoothLinesKey) == nil
        || UserDefaults.standard.bool(forKey: CanvasModel.smoothLinesKey) {
        didSet { UserDefaults.standard.set(smoothLines, forKey: Self.smoothLinesKey) }
    }
    /// Mirror (Ink only) and Grid live in the project so they're saved with it.
    var mirrorOn: Bool {
        get { project.symmetryOn }
        set { project.symmetryOn = newValue }
    }
    var gridOn: Bool {
        get { project.gridOn }
        set { project.gridOn = newValue }
    }
    /// Zoom relative to "whole canvas fits", reported by the canvas (1 = 100%).
    var zoomFactor: CGFloat = 1
    /// Bumped to ask the canvas to zoom back to fit.
    private(set) var fitRequest = 0
    /// Bumped when the model replaced the drawings (undo/redo, a palette
    /// change recoloring Ink lines), so the canvases reload them.
    private(set) var restoreRequest = 0

    private(set) var history = CanvasHistory()
    private var toolInUse = false
    private var recordedThisToolUse = false
    /// Where "Try another" goes next when the palette isn't a curated one
    /// (it was edited): after the last curated palette it showed.
    private var lastCuratedIndex: Int?
    /// A tap-and-hold color change in progress: one undo step, however many
    /// colors the picker goes through.
    private var colorEdit: (slot: PaletteSlot, before: CanvasSnapshot, inkSlots: [PaletteSlot?])?

    /// The shape picked with the Shapes tool (handles, Flip, Delete, fill).
    private(set) var selectedShapeID: LogoShape.ID?
    /// Canvas-centre guides to show while a moved shape is snapped.
    private(set) var snapGuides = SnapGuides()
    /// A move/resize/turn gesture in progress. Nested gestures (one finger
    /// becoming two) share it, so each gesture is exactly one undo step.
    private var shapeEdit: (before: CanvasSnapshot, depth: Int)?

    init(project: Project) {
        self.project = project
    }

    /// The layer one-finger touches go to right now.
    var activeLayer: CanvasLayer {
        switch tool {
        case .sketch: .sketch
        case .ink: .ink
        case .shapes: .shapes
        case .text: .text
        case .eraser: eraserLayer
        }
    }

    var penColor: HexColor { project.color(for: currentSlot) }

    func select(_ newTool: CanvasTool) {
        switch newTool {
        case .sketch: eraserLayer = .sketch
        case .ink: eraserLayer = .ink
        default: break
        }
        tool = newTool
        if newTool != .shapes { selectedShapeID = nil }
    }

    /// Tapping a layer row picks that layer's tool. The eraser stays the eraser
    /// but moves to Sketch or Ink.
    func activate(_ layer: CanvasLayer) {
        switch layer {
        case .sketch, .ink:
            if tool == .eraser { eraserLayer = layer } else { select(layer == .sketch ? .sketch : .ink) }
        case .shapes: select(.shapes)
        case .text: select(.text)
        }
    }

    func toggleVisibility(_ layer: CanvasLayer) {
        if hiddenLayers.contains(layer) { hiddenLayers.remove(layer) } else { hiddenLayers.insert(layer) }
    }

    func zoomToFit() { fitRequest += 1 }

    // MARK: Palette

    /// Tap on a swatch: that color becomes the current one, and the selected
    /// shape (if any) is filled with it, as one undo step.
    func chooseSlot(_ slot: PaletteSlot) {
        currentSlot = slot
        guard let index = selectedShapeIndex, project.shapes[index].fill != slot else { return }
        let before = snapshot
        project.shapes[index].fill = slot
        record(before)
    }

    /// "Try another": the next curated palette. Everything that uses a slot
    /// takes that slot's new color, Ink lines included. One undo step.
    func tryAnotherPalette() {
        let index = Palettes.indexAfter(Palettes.curatedIndex(of: project.palette) ?? lastCuratedIndex)
        lastCuratedIndex = index
        let new = Palettes.curated[index].colors
        guard new != project.palette else { return }
        let before = snapshot
        ink = InkPalette.recolored(ink, slots: InkPalette.slots(of: ink, palette: project.palette), palette: new)
        project.palette = new
        record(before)
        restoreRequest += 1
    }

    /// The slot whose color is being changed (tap and hold), if any.
    var editingSlot: PaletteSlot? { colorEdit?.slot }

    /// Tap and hold on a swatch opened the color picker for `slot`.
    func beginColorEdit(_ slot: PaletteSlot) {
        endColorEdit()
        colorEdit = (slot, snapshot, InkPalette.slots(of: ink, palette: project.palette, preferring: slot))
    }

    /// The picker shows a new color. Shapes and text follow through their
    /// slot; the slot's Ink lines are recolored from the drawing as it was
    /// when the edit began, so passing through another slot's color on the
    /// way never merges two slots' lines.
    func previewColor(_ color: HexColor) {
        guard let edit = colorEdit else { return }
        var palette = edit.before.palette
        let others = PaletteSlot.allCases.filter { $0 != edit.slot }.map { $0.color(in: palette) }
        palette[edit.slot.rawValue] = InkPalette.keepingApart(color, from: others)
        guard palette != project.palette else { return }
        let slots = edit.inkSlots.map { $0 == edit.slot ? $0 : nil }
        ink = InkPalette.recolored(edit.before.ink, slots: slots, palette: palette)
        project.palette = palette
        restoreRequest += 1
    }

    /// The picker closed. The whole change is one undo step (none if the
    /// color ended up the same).
    func endColorEdit() {
        guard let edit = colorEdit else { return }
        colorEdit = nil
        if project.palette != edit.before.palette { record(edit.before) }
    }

    // MARK: Shapes

    var selectedShape: LogoShape? { selectedShapeIndex.map { project.shapes[$0] } }
    private var selectedShapeIndex: Int? {
        selectedShapeID.flatMap { id in project.shapes.firstIndex { $0.id == id } }
    }

    /// Adds a shape at the canvas centre in the current color and selects it.
    func addShape(_ kind: LogoShape.Kind) {
        let before = snapshot
        let shape = LogoShape(id: UUID(), kind: kind, center: ShapeEditing.canvasCenter,
                              size: ShapeEditing.newShapeSize, rotation: 0, fill: currentSlot)
        project.shapes.append(shape)
        selectedShapeID = shape.id
        hiddenLayers.remove(.shapes)
        record(before)
    }

    /// Picks a shape (`nil` = nothing picked).
    func selectShape(_ id: LogoShape.ID?) {
        selectedShapeID = id.flatMap { id in project.shapes.contains { $0.id == id } ? id : nil }
    }

    /// A move, resize or turn gesture started.
    func beginShapeEdit() {
        if let edit = shapeEdit {
            shapeEdit = (edit.before, edit.depth + 1)
        } else {
            shapeEdit = (snapshot, 1)
        }
    }

    /// The gesture's current result for one shape (live, not an undo step yet).
    func updateShape(_ shape: LogoShape, guides: SnapGuides = SnapGuides()) {
        guard let index = project.shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        if project.shapes[index] != shape { project.shapes[index] = shape }
        if snapGuides != guides { snapGuides = guides }
    }

    /// The gesture ended: one undo step if the shapes changed.
    func endShapeEdit() {
        guard let edit = shapeEdit else { return }
        if edit.depth > 1 {
            shapeEdit = (edit.before, edit.depth - 1)
            return
        }
        shapeEdit = nil
        snapGuides = SnapGuides()
        if project.shapes != edit.before.shapes { record(edit.before) }
    }

    /// Whether Flip would visibly change the selected shape (a circle never does).
    func canFlipSelectedShape(sideways: Bool) -> Bool {
        guard let shape = selectedShape else { return false }
        return !ShapeEditing.looksTheSame(shape, ShapeEditing.flipped(shape, sideways: sideways))
    }

    func flipSelectedShape(sideways: Bool) {
        guard canFlipSelectedShape(sideways: sideways), let index = selectedShapeIndex else { return }
        let before = snapshot
        project.shapes[index] = ShapeEditing.flipped(project.shapes[index], sideways: sideways)
        record(before)
    }

    func deleteSelectedShape() {
        guard let index = selectedShapeIndex else { return }
        let before = snapshot
        project.shapes.remove(at: index)
        selectedShapeID = nil
        record(before)
    }

    // MARK: Changes and undo

    var snapshot: CanvasSnapshot {
        CanvasSnapshot(sketch: sketch, ink: ink, shapes: project.shapes, text: project.text,
                       palette: project.palette)
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// A finger or Pencil went down with a tool. Everything until `endToolUse`
    /// (e.g. one eraser drag across several lines) is one undo step.
    func beginToolUse() {
        toolInUse = true
        recordedThisToolUse = false
    }

    func endToolUse() {
        toolInUse = false
    }

    /// The Sketch canvas changed (a stroke or an erase).
    func sketchDidChange(_ drawing: PKDrawing) {
        guard drawing != sketch else { return }
        let before = snapshot
        sketch = drawing
        record(before)
    }

    /// The Ink canvas changed. A new stroke is smoothed first (if "Smooth my
    /// lines" is on), then mirrored (if Mirror is on), and all of it is one
    /// undo step. Returns the drawing the Ink canvas should show.
    func inkDidChange(_ drawing: PKDrawing) -> PKDrawing {
        guard drawing != ink else { return drawing }
        let before = snapshot
        var result = drawing
        if drawing.strokes.count == ink.strokes.count + 1, var stroke = drawing.strokes.last {
            if smoothLines { stroke = StrokeSmoother.smoothed(stroke) }
            result.strokes[result.strokes.count - 1] = stroke
            if mirrorOn { result.strokes.append(Symmetry.mirrored(stroke)) }
        }
        ink = result
        record(before)
        return result
    }

    func undo() {
        guard let previous = history.undo(current: snapshot) else { return }
        restore(previous)
    }

    func redo() {
        guard let next = history.redo(current: snapshot) else { return }
        restore(next)
    }

    private func record(_ before: CanvasSnapshot) {
        if toolInUse, recordedThisToolUse { return }
        history.record(before)
        recordedThisToolUse = toolInUse
    }

    private func restore(_ state: CanvasSnapshot) {
        sketch = state.sketch
        ink = state.ink
        project.shapes = state.shapes
        project.text = state.text
        project.palette = state.palette
        if selectedShapeIndex == nil { selectedShapeID = nil }
        restoreRequest += 1
    }
}

#if DEBUG
extension CanvasModel {
    /// "palette #FF5A1F #1C1B22 #FFC93C; ink #1C1B22": the palette and the
    /// distinct Ink line colors, for UI tests (`debugColors`).
    var debugColorSummary: String {
        let palette = project.palette.map(\.hexString).joined(separator: " ")
        let inkColors = Set(ink.strokes.map { SVGExporter.inkColor($0.ink.color).color.hexString }).sorted()
        return "palette \(palette); ink \(inkColors.joined(separator: " "))"
    }

    /// "2 shapes; selected star 512 512 320 15°; guides x": the shapes and the
    /// selected one (centre, size, rotation in degrees), for UI tests (`debugShapes`).
    var debugShapeSummary: String {
        var text = "\(project.shapes.count) shapes"
        if let shape = selectedShape {
            let degrees = Int((shape.rotation * 180 / .pi).rounded())
            text += "; selected \(shape.kind.rawValue) \(Int(shape.center.x.rounded())) \(Int(shape.center.y.rounded()))"
                + " \(Int(shape.size.rounded())) \(degrees)° fill \(shape.fill.number)"
        }
        if snapGuides.vertical || snapGuides.horizontal {
            text += "; guides" + (snapGuides.vertical ? " x" : "") + (snapGuides.horizontal ? " y" : "")
        }
        return text
    }
}
#endif
