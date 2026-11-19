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
/// four layers. `ProjectAutosaver` watches it and saves.
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
    /// A move/resize/turn gesture (or a text slider drag) in progress. Nested
    /// gestures (one finger becoming two) share it, so each is one undo step.
    private var itemEdit: (before: CanvasSnapshot, depth: Int)?

    /// A friendly note under the text field ("This font can't draw “😀”."), or nil.
    private(set) var textMessage: String?
    /// The font new text starts in (the picker works before anything's typed).
    private(set) var newTextFont = LogoFonts.defaultFont.postScriptName
    /// A typing session in progress: everything typed until the field loses
    /// focus, or another change starts, is one undo step.
    private var typing: CanvasSnapshot?
    /// Bumped when the text string changed other than by typing (undo, redo,
    /// Delete text), so the field takes the model's string. Typing itself is
    /// never echoed back: a keystroke landing between two SwiftUI updates
    /// would otherwise be overwritten by the string from before it.
    private(set) var textReplaced = 0

    // MARK: Lesson mode (the lesson player drives these)

    /// Called with each new Ink stroke exactly as drawn, before "Smooth my
    /// lines" and Mirror: Learn scores the RAW stroke.
    @ObservationIgnored var onNewInkStroke: ((PKStroke) -> Void)?
    /// No drawing on Ink right now (a result card is up, or a shape step).
    var inkLocked = false
    /// The dashed targets on the canvas (lesson mode only).
    var lessonGhost: LessonGhost?
    /// Off in lesson mode: the player's Redo is the undo there.
    var undoEnabled = true

    /// A project with its drawings (a loaded one, or a new blank one).
    init(project: Project, sketch: PKDrawing = PKDrawing(), ink: PKDrawing = PKDrawing()) {
        self.project = project
        self.sketch = sketch
        self.ink = ink
    }

    /// The name, from the canvas title (tap to rename). Not an undo step.
    func rename(to typed: String) {
        let name = ProjectNames.cleaned(typed, fallback: project.name)
        if name != project.name { project.name = name }
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
        #if DEBUG
        TouchTrace.note("select \(newTool)")
        #endif
        switch newTool {
        case .sketch: eraserLayer = .sketch
        case .ink: eraserLayer = .ink
        default: break
        }
        endTyping()
        tool = newTool
        if newTool != .shapes { selectedShapeID = nil }
        textMessage = nil
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

    /// Tap on a swatch: that color becomes the current one, and the picked
    /// shape, or the text with the Text tool, is filled with it (one undo step).
    func chooseSlot(_ slot: PaletteSlot) {
        currentSlot = slot
        endTyping()
        if tool == .text {
            changeText { $0.fill = slot }
            return
        }
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

    /// The shape or text the gestures work on: the picked shape with the
    /// Shapes tool, the logo text (once it has letters) with the Text tool.
    var pickedItem: PickedItem? {
        switch tool {
        case .shapes:
            return selectedShape.map(PickedItem.shape)
        case .text:
            guard let text = project.text, !text.string.isEmpty else { return nil }
            return .text(text)
        default:
            return nil
        }
    }

    /// A move, resize or turn gesture (or a text slider drag) started.
    func beginEdit() {
        endTyping()
        if let edit = itemEdit {
            itemEdit = (edit.before, edit.depth + 1)
        } else {
            itemEdit = (snapshot, 1)
        }
    }

    /// The gesture's current result (live, not an undo step yet).
    func updateItem(_ item: PickedItem, guides: SnapGuides = SnapGuides()) {
        switch item {
        case .shape(let shape):
            updateShape(shape, guides: guides)
        case .text(let text):
            if project.text != text { project.text = text }
            if snapGuides != guides { snapGuides = guides }
        }
    }

    /// The gesture's current result for one shape (live, not an undo step yet).
    func updateShape(_ shape: LogoShape, guides: SnapGuides = SnapGuides()) {
        guard let index = project.shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        if project.shapes[index] != shape { project.shapes[index] = shape }
        if snapGuides != guides { snapGuides = guides }
    }

    /// The gesture ended: one undo step if anything changed.
    func endEdit() {
        guard let edit = itemEdit else { return }
        if edit.depth > 1 {
            itemEdit = (edit.before, edit.depth - 1)
            return
        }
        itemEdit = nil
        snapGuides = SnapGuides()
        if project.shapes != edit.before.shapes || project.text != edit.before.text { record(edit.before) }
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

    // MARK: Text (one logo name per project)

    /// What the text field shows: the typed string ("" when there's no text).
    var textString: String { project.text?.string ?? "" }
    /// The font the picker shows as chosen.
    var textFont: String { project.text?.fontName ?? newTextFont }

    /// The text field changed. Keeps what the rules allow (characters the font
    /// can draw, at most 24 of them) and returns it, so the field shows exactly
    /// what's on the canvas. The first letter creates the text, centred, in
    /// the current color.
    @discardableResult
    func typeText(_ typed: String) -> String {
        // The field writing back what was accepted: nothing new, and the note
        // about what was refused stays up.
        guard typed != textString else { return typed }
        let fontName = textFont
        let allCaps = project.text?.allCaps ?? false
        var blocked: [Character] = []
        var accepted = String(typed.precomposedStringWithCanonicalMapping.filter { character in
            let shown = allCaps ? String(character).uppercased() : String(character)
            guard LogoFonts.missingCharacters(in: shown, fontName: fontName).isEmpty else {
                if !blocked.contains(character) { blocked.append(character) }
                return false
            }
            return true
        })
        var message: String?
        if !blocked.isEmpty { message = "This font can't draw \(Self.quoted(blocked))." }
        if accepted.count > LogoText.maxLength {
            accepted = String(accepted.prefix(LogoText.maxLength))
            message = message ?? "Up to \(LogoText.maxLength) letters and spaces."
        }
        textMessage = message
        guard accepted != textString else { return accepted }

        if typing == nil { typing = snapshot }
        if project.text == nil {
            project.text = LogoText(string: accepted, fontName: fontName, center: ShapeEditing.canvasCenter,
                                    pointSize: Self.newTextSize, rotation: 0, fill: currentSlot)
            hiddenLayers.remove(.text)
        } else {
            project.text?.string = accepted
        }
        return accepted
    }

    /// New text: big enough to read, small enough for a long name to fit.
    static let newTextSize: CGFloat = 120

    /// The text field lost focus (or something else started): everything typed
    /// since it got focus is one undo step. Emptied text is removed.
    func endTyping() {
        guard let before = typing else { return }
        typing = nil
        if project.text?.string.isEmpty == true { project.text = nil }
        if project.text != before.text { record(before) }
    }

    /// Picks a font. Refused, with a note, if it can't draw the text.
    func setTextFont(_ font: LogoFont) {
        endTyping()
        if let text = project.text {
            let missing = LogoFonts.missingCharacters(in: text.displayString, fontName: font.postScriptName)
            guard missing.isEmpty else {
                textMessage = "\(font.displayName) can't draw \(Self.quoted(missing)). Change the text first."
                return
            }
        }
        textMessage = nil
        newTextFont = font.postScriptName
        changeText { $0.fontName = font.postScriptName }
    }

    /// ALL CAPS. Refused, with a note, if the font has no capital for a letter.
    func setTextAllCaps(_ on: Bool) {
        endTyping()
        guard let text = project.text else { return }
        if on {
            let missing = LogoFonts.missingCharacters(in: text.string.uppercased(), fontName: text.fontName)
            guard missing.isEmpty else {
                textMessage = "This font can't draw \(Self.quoted(missing)) in capitals."
                return
            }
        }
        textMessage = nil
        changeText { $0.allCaps = on }
    }

    func setTextSize(_ size: CGFloat) {
        changeText { $0.pointSize = min(max(size, LogoText.scaleRange.lowerBound), LogoText.scaleRange.upperBound) }
    }

    func setTextTracking(_ tracking: CGFloat) {
        changeText { $0.tracking = min(max(tracking, LogoText.trackingRange.lowerBound), LogoText.trackingRange.upperBound) }
    }

    func deleteText() {
        endTyping()
        guard project.text != nil else { return }
        let before = snapshot
        project.text = nil
        textReplaced += 1
        textMessage = nil
        record(before)
    }

    /// One change to the text: live during a slider drag (`beginEdit`/`endEdit`),
    /// otherwise its own undo step.
    private func changeText(_ change: (inout LogoText) -> Void) {
        endTyping()                                    // what was typed is its own step
        guard var text = project.text else { return }
        change(&text)
        guard text != project.text else { return }
        if itemEdit != nil {
            project.text = text
            return
        }
        let before = snapshot
        project.text = text
        record(before)
    }

    /// “a”, “b” and “c”
    private static func quoted(_ characters: [Character]) -> String {
        let items = characters.map { "\u{201C}\($0)\u{201D}" }
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    // MARK: Changes and undo

    var snapshot: CanvasSnapshot {
        CanvasSnapshot(sketch: sketch, ink: ink, shapes: project.shapes, text: project.text,
                       palette: project.palette)
    }

    /// Typing that isn't recorded yet counts: Undo takes back the session.
    var canUndo: Bool { undoEnabled && (history.canUndo || typedSomething) }
    /// Undo would record the typing first, which clears the redo steps.
    var canRedo: Bool { undoEnabled && history.canRedo && !typedSomething }
    private var typedSomething: Bool { typing.map { $0.text != project.text } ?? false }

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
        if drawing.strokes.count == before.ink.strokes.count + 1, let raw = drawing.strokes.last {
            onNewInkStroke?(raw)
        }
        return result
    }

    /// Lesson mode: puts in a whole new Ink drawing (Redo, Skip, resume).
    /// Not an undo step; undo is off in lesson mode.
    func replaceInk(_ drawing: PKDrawing) {
        ink = drawing
        restoreRequest += 1
    }

    func undo() {
        guard undoEnabled else { return }
        endTyping()
        guard let previous = history.undo(current: snapshot) else { return }
        restore(previous)
    }

    func redo() {
        guard undoEnabled else { return }
        endTyping()
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
        if project.text?.string != state.text?.string { textReplaced += 1 }
        project.text = state.text
        project.palette = state.palette
        if selectedShapeIndex == nil { selectedShapeID = nil }
        textMessage = nil
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

    /// "svg 1A2B…(4123); sketch 1 lines 57 points; mirror off grid on; Pizza
    /// Rocket": the exported SVG's FNV-1a hash (stable across launches,
    /// unlike `hashValue`) and the sketch, so a UI test can check a reopened
    /// project is identical (`debugDocument`).
    var debugDocumentFingerprint: String {
        let svg = (try? SVGExporter.svg(project: project, ink: ink)) ?? "export failed"
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in svg.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        let points = sketch.strokes.reduce(0) { $0 + $1.path.count }
        return "svg \(String(hash, radix: 16, uppercase: true))(\(svg.utf8.count)); sketch \(sketch.strokes.count) lines"
            + " \(points) points; mirror \(mirrorOn ? "on" : "off") grid \(gridOn ? "on" : "off"); \(project.name)"
    }

    /// "text Pizza Rocket; LilitaOne 120 0° fill 2 tracking 0 caps off; at 512 512",
    /// for UI tests (`debugText`).
    var debugTextSummary: String {
        guard let t = project.text else { return "no text" }
        let degrees = Int((t.rotation * 180 / .pi).rounded())
        return "text \(t.string); \(t.fontName) \(Int(t.pointSize.rounded())) \(degrees)° fill \(t.fill.number)"
            + " tracking \(Int(t.tracking.rounded())) caps \(t.allCaps ? "on" : "off");"
            + " at \(Int(t.center.x.rounded())) \(Int(t.center.y.rounded()))"
    }
}
#endif
