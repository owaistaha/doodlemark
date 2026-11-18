import Foundation

/// The undo manager the system sees (⌘Z / ⇧⌘Z, the Edit menu and the iPadOS
/// three-finger undo/redo gestures). It forwards to `CanvasModel`'s history.
///
/// Registration is switched off, so PencilKit, which registers its own undo
/// actions with whatever `undoManager` its canvas returns, adds nothing. Its
/// undo can't undo a programmatically appended mirror copy (RISKS.md #1).
@MainActor
final class HistoryUndoManager: UndoManager {
    weak var model: CanvasModel?

    init(model: CanvasModel) {
        self.model = model
        super.init()
        disableUndoRegistration()
    }

    override var canUndo: Bool { model?.canUndo ?? false }
    override var canRedo: Bool { model?.canRedo ?? false }
    override func undo() { model?.undo() }
    override func redo() { model?.redo() }
}
