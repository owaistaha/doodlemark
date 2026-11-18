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

/// Editor state for one project. Undo history, Mirror and Grid come in step 4c,
/// saving in step 6.
@MainActor @Observable
final class CanvasModel {
    static let pencilOnlyKey = "pencilOnly"

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
    /// Zoom relative to "whole canvas fits", reported by the canvas (1 = 100%).
    var zoomFactor: CGFloat = 1
    /// Bumped to ask the canvas to zoom back to fit.
    private(set) var fitRequest = 0

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
}
