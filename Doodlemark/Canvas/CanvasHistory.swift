import PencilKit

/// Everything undo can bring back: all four layers and the palette.
struct CanvasSnapshot: Equatable {
    var sketch: PKDrawing
    var ink: PKDrawing
    var shapes: [LogoShape]
    var text: LogoText?
    var palette: [HexColor]
}

/// One undo history for the whole canvas (all four layers). Each user change
/// records the snapshot from *before* it, so a stroke plus its smoothing and
/// mirror copy is a single step. PencilKit's own undo is switched off on both
/// canvases (RISKS.md #1).
struct CanvasHistory {
    /// About 100 steps; the oldest are dropped. See the report / TECH_SPEC for memory.
    static let limit = 100

    private(set) var undoStack: [CanvasSnapshot] = []
    private(set) var redoStack: [CanvasSnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// A new change happened; `before` is the state it replaced.
    mutating func record(_ before: CanvasSnapshot) {
        undoStack.append(before)
        if undoStack.count > Self.limit { undoStack.removeFirst(undoStack.count - Self.limit) }
        redoStack.removeAll()
    }

    /// Returns the state to show, or nil if there's nothing to undo.
    mutating func undo(current: CanvasSnapshot) -> CanvasSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: CanvasSnapshot) -> CanvasSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
