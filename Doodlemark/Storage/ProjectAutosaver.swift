import Foundation
import Observation
import PencilKit

/// Runs `action` after `delay` unless the returned cancel is called first.
/// The app uses a real timer; tests use a manual clock.
typealias SaveScheduler = @MainActor (Duration, @escaping @MainActor () -> Void) -> (@MainActor () -> Void)

/// Saves the open project: 1 s after the last change (debounced, so a burst
/// of strokes or a typing session is one write), and right away when asked
/// (leaving the canvas, the app going to the background).
///
/// It watches the model's project and both drawings with Observation, so
/// every kind of change counts: strokes, shapes, text, palette, Mirror/Grid,
/// the name. A new project nobody has touched is never written, so tapping
/// New logo and going back doesn't leave an empty card.
@MainActor @Observable
final class ProjectAutosaver {
    enum State: Equatable {
        /// New and untouched: nothing on disk yet.
        case notSaved
        /// Changed; the save is waiting for the debounce.
        case editing
        case saved
        /// The last save threw (disk full…). The next change tries again.
        case failed
    }

    static let debounce: Duration = .seconds(1)

    static let realScheduler: SaveScheduler = { delay, action in
        let task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }

    private(set) var state: State
    /// The project has a folder in the store (loaded, or saved at least once).
    private(set) var isOnDisk: Bool
    /// Saves written (tests).
    private(set) var saveCount = 0

    @ObservationIgnored let model: CanvasModel
    @ObservationIgnored let store: ProjectStore
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let schedule: SaveScheduler
    @ObservationIgnored private var cancelPending: (@MainActor () -> Void)?
    @ObservationIgnored private var lastSaved: (project: Project, sketch: PKDrawing, ink: PKDrawing)
    @ObservationIgnored var now: () -> Date = Date.init

    /// `isOnDisk`: the project was loaded from the store (or saved before).
    init(model: CanvasModel, store: ProjectStore, isOnDisk: Bool,
         debounce: Duration = ProjectAutosaver.debounce, schedule: @escaping SaveScheduler = ProjectAutosaver.realScheduler) {
        self.model = model
        self.store = store
        self.debounce = debounce
        self.schedule = schedule
        lastSaved = (model.project, model.sketch, model.ink)
        self.isOnDisk = isOnDisk
        state = isOnDisk ? .saved : .notSaved
        observeModel()
    }

    /// True when the model differs from what's on disk (or, for a new
    /// project, from how it started).
    var hasUnsavedChanges: Bool {
        model.project != lastSaved.project || model.sketch != lastSaved.sketch || model.ink != lastSaved.ink
    }

    /// Writes now if anything changed, and drops a pending debounce.
    func saveNow() {
        cancelPending?()
        cancelPending = nil
        guard hasUnsavedChanges else { return settle() }
        let project = model.project, sketch = model.sketch, ink = model.ink
        var stored = project
        stored.updatedAt = now()
        do {
            try store.save(stored, sketch: sketch, ink: ink,
                           thumbnail: Thumbnail.pngData(project: stored, sketch: sketch, ink: ink))
            lastSaved = (project, sketch, ink)
            saveCount += 1
            isOnDisk = true
            state = .saved
        } catch {
            state = .failed
        }
    }

    private func settle() {
        if state == .editing { state = isOnDisk ? .saved : .notSaved }
    }

    // MARK: Watching the model

    private func observeModel() {
        withObservationTracking {
            _ = model.project
            _ = model.sketch
            _ = model.ink
        } onChange: { [weak self] in
            // Called before the change lands; look at it on the next turn.
            Task { @MainActor in self?.modelChanged() }
        }
    }

    private func modelChanged() {
        observeModel()
        guard hasUnsavedChanges else {
            // Undone back to what's saved: nothing to write.
            cancelPending?()
            cancelPending = nil
            return settle()
        }
        state = .editing
        cancelPending?()
        cancelPending = schedule(debounce) { [weak self] in self?.saveNow() }
    }
}
