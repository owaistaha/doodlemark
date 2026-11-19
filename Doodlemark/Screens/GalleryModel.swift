import Foundation
import Observation

/// The gallery's state and actions. Views only call these.
@MainActor @Observable
final class GalleryModel {
    @ObservationIgnored let store: ProjectStore
    private(set) var entries: [GalleryEntry] = []
    /// Projects whose folder looked fine but whose drawings didn't load when
    /// opened: shown as broken from then on.
    private var failedToOpen: [UUID: String] = [:]

    init(store: ProjectStore) {
        self.store = store
        reload()
    }

    var isEmpty: Bool { entries.isEmpty }

    func reload() {
        entries = store.entries().map { entry in
            guard case .project(let summary) = entry, let reason = failedToOpen[summary.id] else { return entry }
            return .broken(BrokenProject(id: summary.id.uuidString, folder: store.folder(for: summary.id),
                                         modified: summary.updatedAt, reason: reason))
        }
    }

    /// Loads a project to open it. If it can't be read, its card turns into
    /// "Couldn't open this logo" and nil comes back (no crash, no alert).
    func open(_ id: UUID) -> LoadedProject? {
        do {
            return try store.load(id)
        } catch {
            failedToOpen[id] = "\(error)"
            reload()
            return nil
        }
    }

    func rename(_ id: UUID, to typed: String) {
        guard case .project(let summary)? = entries.first(where: { $0.id == id.uuidString }) else { return }
        let name = ProjectNames.cleaned(typed, fallback: summary.name)
        guard name != summary.name else { return }
        try? store.rename(id, to: name)
        reload()
    }

    func duplicate(_ id: UUID) {
        _ = try? store.duplicate(id)
        reload()
    }

    /// Deletes a project or a broken folder (after the card's confirmation).
    func delete(_ entry: GalleryEntry) {
        try? store.delete(folderNamed: entry.id)
        if let id = UUID(uuidString: entry.id) { failedToOpen[id] = nil }
        reload()
    }
}

/// "Edited today", "Edited yesterday", "Edited 3 days ago", "Edited last
/// week", "Edited 2 weeks ago", then the date.
enum EditedLabel {
    static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Edited today"
        case 1: return "Edited yesterday"
        case 2...6: return "Edited \(days) days ago"
        case 7...13: return "Edited last week"
        case 14...41: return "Edited \(days / 7) weeks ago"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
            let format = sameYear ? style.month(.abbreviated).day() : style
            return "Edited \(date.formatted(format))"
        }
    }
}
