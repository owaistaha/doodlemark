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
    static let pencilOnlyKey = "pencilOnly"
    static let smoothLinesKey = "smoothLines"

    var project: Project
    var sketch = PKDrawing()
    var ink = PKDrawing()

    private(set) var tool: CanvasTool = .ink
    /// The drawing layer the eraser works on: whichever of Sketch/Ink was used last.
    private(set) var eraserLayer: CanvasLayer = .ink
    /// "Line size": drawn thickness in canvas space. Converted only by `LineSize`.
    var lineSize: CGFloat = LineSize.defaultSize
    /// Index into `project.palette` used by the Ink pen.
    var penColorIndex = 1
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
    /// Bumped when undo/redo replaced the drawings, so the canvases reload them.
    private(set) var restoreRequest = 0

    private(set) var history = CanvasHistory()
    private var toolInUse = false
    private var recordedThisToolUse = false

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

    var penColor: HexColor {
        project.palette.indices.contains(penColorIndex) ? project.palette[penColorIndex] : project.palette[0]
    }

    func select(_ newTool: CanvasTool) {
        switch newTool {
        case .sketch: eraserLayer = .sketch
        case .ink: eraserLayer = .ink
        default: break
        }
        tool = newTool
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

    // MARK: Changes and undo

    var snapshot: CanvasSnapshot {
        CanvasSnapshot(sketch: sketch, ink: ink, shapes: project.shapes, text: project.text)
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
        restoreRequest += 1
    }
}
