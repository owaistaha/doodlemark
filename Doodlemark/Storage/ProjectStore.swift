import Foundation
import PencilKit

/// `project.json` on disk: the `Project` fields plus `"schemaVersion"` at the
/// top level, so a later format change can migrate old files.
struct ProjectFile: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var project: Project

    init(project: Project) {
        schemaVersion = Self.currentSchemaVersion
        self.project = project
    }

    private enum VersionKey: String, CodingKey { case schemaVersion }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: VersionKey.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw ProjectStore.Failure.newerSchema(schemaVersion)
        }
        // Version 1 is the only one so far. Migrations from older versions go here.
        project = try Project(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try project.encode(to: encoder)
        var container = encoder.container(keyedBy: VersionKey.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }
}

/// A project read back from its folder.
struct LoadedProject {
    var project: Project
    var sketch: PKDrawing
    var ink: PKDrawing
}

/// What the gallery shows for a project that loads.
struct ProjectSummary: Identifiable, Equatable {
    var id: UUID
    var name: String
    var updatedAt: Date
    var thumbnail: URL
}

/// A project folder that couldn't be read. Shown as a "Couldn't open this
/// logo" card with Delete, never dropped silently.
struct BrokenProject: Identifiable, Equatable {
    /// The folder name.
    var id: String
    var folder: URL
    /// When the folder last changed, to sort it among the others.
    var modified: Date
    /// For logs and tests; the card stays friendly.
    var reason: String
}

enum GalleryEntry: Identifiable, Equatable {
    case project(ProjectSummary)
    case broken(BrokenProject)

    var id: String {
        switch self {
        case .project(let summary): summary.id.uuidString
        case .broken(let broken): broken.id
        }
    }

    /// Newest edited first.
    var sortDate: Date {
        switch self {
        case .project(let summary): summary.updatedAt
        case .broken(let broken): broken.modified
        }
    }
}

/// Projects on disk (TECH_SPEC "Data model"):
///
///     Documents/Projects/<uuid>/
///       project.json    ProjectFile (schemaVersion + Project)
///       sketch.drawing  PKDrawing.dataRepresentation()
///       ink.drawing     PKDrawing.dataRepresentation()
///       thumb.png       512 px, Shapes + Ink + Text (the sketch only if that's all there is)
///
/// A save is one folder swap: every file is written into a fresh staging
/// folder (`Projects/.staging/<uuid>-<random>/`, hidden, same volume), and
/// then `FileManager.replaceItemAt` swaps that whole folder in for the
/// project's (`rename(2)` with `RENAME_SWAP` on APFS, atomic). A crash at
/// any point leaves the full old save or the full new one, never a mix:
/// Ink colors are linked to palette slots by exact color, so an ink.drawing
/// from one save next to a project.json from another could break recolor.
@MainActor
final class ProjectStore {
    enum FileName {
        static let project = "project.json"
        static let sketch = "sketch.drawing"
        static let ink = "ink.drawing"
        static let thumbnail = "thumb.png"
        /// Where saves are put together before the swap. Hidden, so the
        /// gallery never lists it.
        static let staging = ".staging"
        /// Step 6 wrote ".<name>.saving-<uuid>" temp files inside a project
        /// folder. Still cleaned up, in case an old build was killed mid-save.
        static let savingMarker = ".saving-"
    }

    /// The points a save passes, in order. Tests stop a save at each one to
    /// stand in for a crash there.
    enum SaveStep: CaseIterable {
        case createdStaging, wroteSketch, wroteInk, wroteThumbnail, wroteProject, swapped
    }

    enum Failure: Error, Equatable {
        case newerSchema(Int)
        case missingFile(String)
        case unreadable(String)
    }

    static var defaultRoot: URL {
        URL.documentsDirectory.appending(path: "Projects", directoryHint: .isDirectory)
    }

    let root: URL
    private let files = FileManager.default

    /// Writes one file into the staging folder. Tests swap it to fail a write.
    var writeTemporaryFile: (Data, URL) throws -> Void = { data, url in try data.write(to: url) }
    /// Called at each `SaveStep`. Tests throw `SaveInterrupted` from it to
    /// leave everything as a crash at that point would.
    var stepHook: ((SaveStep) throws -> Void)?

    /// Thrown by test hooks: the "app died" here, so nothing is cleaned up.
    struct SaveInterrupted: Error {}

    init(root: URL = ProjectStore.defaultRoot) {
        self.root = root
    }

    func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private var stagingRoot: URL {
        root.appending(path: FileName.staging, directoryHint: .isDirectory)
    }

    // MARK: Save

    /// Writes the whole project. `project.updatedAt` is saved as given.
    /// With no thumbnail the save has none (the card shows a blank tile)
    /// rather than an older one that no longer matches.
    func save(_ project: Project, sketch: PKDrawing, ink: PKDrawing, thumbnail: Data?) throws {
        let json = try ProjectCoding.makeEncoder().encode(ProjectFile(project: project))
        var contents: [(String, Data, SaveStep)] = [
            (FileName.sketch, sketch.dataRepresentation(), .wroteSketch),
            (FileName.ink, ink.dataRepresentation(), .wroteInk),
        ]
        if let thumbnail { contents.append((FileName.thumbnail, thumbnail, .wroteThumbnail)) }
        contents.append((FileName.project, json, .wroteProject))
        try commit(contents, to: project.id)
    }

    /// Stages the files and swaps the folder in.
    private func commit(_ contents: [(name: String, data: Data, step: SaveStep)], to id: UUID) throws {
        removeStaging(for: id)
        let destination = folder(for: id)
        let staging = stagingRoot.appending(path: "\(id.uuidString)-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
            try stepHook?(.createdStaging)
            for (name, data, step) in contents {
                try writeTemporaryFile(data, staging.appending(path: name))
                try stepHook?(step)
            }
            if files.fileExists(atPath: destination.path) {
                _ = try files.replaceItemAt(destination, withItemAt: staging)
            } else {
                try files.createDirectory(at: root, withIntermediateDirectories: true)
                try files.moveItem(at: staging, to: destination)
            }
            try stepHook?(.swapped)
        } catch let crash as SaveInterrupted {
            throw crash                                     // a crash cleans nothing up
        } catch {
            try? files.removeItem(at: staging)
            throw error
        }
    }

    /// A project's staging folders left by a save that never finished.
    private func removeStaging(for id: UUID) {
        let names = (try? files.contentsOfDirectory(atPath: stagingRoot.path)) ?? []
        for name in names where name.hasPrefix(id.uuidString) {
            try? files.removeItem(at: stagingRoot.appending(path: name))
        }
    }

    /// At launch: drop every unfinished save (staging folders and step 6's
    /// temp files). They're never read, so this is only tidying.
    func removeLeftovers() {
        try? files.removeItem(at: stagingRoot)
        let folders = (try? files.contentsOfDirectory(atPath: root.path)) ?? []
        for folder in folders where !folder.hasPrefix(".") {
            let url = root.appending(path: folder, directoryHint: .isDirectory)
            for name in (try? files.contentsOfDirectory(atPath: url.path)) ?? [] where name.contains(FileName.savingMarker) {
                try? files.removeItem(at: url.appending(path: name))
            }
        }
    }

    // MARK: Load

    func load(_ id: UUID) throws -> LoadedProject {
        let folder = folder(for: id)
        var project = try readProjectFile(in: folder)
        project.id = id                                   // the folder is the identity
        let sketch = try readDrawing(FileName.sketch, in: folder)
        var ink = try readDrawing(FileName.ink, in: folder)
        // A reload reports monoline strokes as .pen (RISKS #11). Ink is
        // monoline only, so put the type back; pixels and export are unchanged.
        for index in ink.strokes.indices where ink.strokes[index].ink.inkType != .monoline {
            ink.strokes[index].ink = PKInk(.monoline, color: ink.strokes[index].ink.color)
        }
        return LoadedProject(project: project, sketch: sketch, ink: ink)
    }

    private func readProjectFile(in folder: URL) throws -> Project {
        let url = folder.appending(path: FileName.project)
        guard files.fileExists(atPath: url.path) else { throw Failure.missingFile(FileName.project) }
        do {
            return try ProjectCoding.makeDecoder().decode(ProjectFile.self, from: Data(contentsOf: url)).project
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.unreadable("\(FileName.project): \(error)")
        }
    }

    private func readDrawing(_ name: String, in folder: URL) throws -> PKDrawing {
        let url = folder.appending(path: name)
        guard files.fileExists(atPath: url.path) else { throw Failure.missingFile(name) }
        do {
            return try PKDrawing(data: Data(contentsOf: url))
        } catch {
            throw Failure.unreadable("\(name): \(error)")
        }
    }

    // MARK: Gallery

    /// Every project folder, newest edited first. A folder whose
    /// `project.json` can't be read is a `.broken` entry.
    func entries() -> [GalleryEntry] {
        let folders = (try? files.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        var entries: [GalleryEntry] = []
        for folder in folders {
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { continue }
            let name = folder.lastPathComponent
            do {
                guard let id = UUID(uuidString: name) else { throw Failure.unreadable("folder name \(name)") }
                let project = try readProjectFile(in: folder)
                entries.append(.project(ProjectSummary(id: id, name: project.name, updatedAt: project.updatedAt,
                                                       thumbnail: folder.appending(path: FileName.thumbnail))))
            } catch {
                entries.append(.broken(BrokenProject(id: name, folder: folder,
                                                     modified: values?.contentModificationDate ?? .distantPast,
                                                     reason: "\(error)")))
            }
        }
        return entries.sorted { $0.sortDate != $1.sortDate ? $0.sortDate > $1.sortDate : $0.id < $1.id }
    }

    /// Changes only the name (and not "last edited"). Still a whole-folder
    /// save: the other files are carried over byte for byte.
    func rename(_ id: UUID, to name: String) throws {
        let folder = folder(for: id)
        var project = try readProjectFile(in: folder)
        project.name = name
        var contents: [(String, Data, SaveStep)] = []
        for (file, step) in [(FileName.sketch, SaveStep.wroteSketch), (FileName.ink, .wroteInk), (FileName.thumbnail, .wroteThumbnail)] {
            let url = folder.appending(path: file)
            guard files.fileExists(atPath: url.path) else { continue }
            contents.append((file, try Data(contentsOf: url), step))
        }
        contents.append((FileName.project, try ProjectCoding.makeEncoder().encode(ProjectFile(project: project)), .wroteProject))
        try commit(contents, to: id)
    }

    /// A deep copy in a new folder: new id, "<name> copy", edited now, so it
    /// shows first. Nothing is shared with the original.
    @discardableResult
    func duplicate(_ id: UUID, now: Date = Date()) throws -> Project {
        let original = try load(id)
        var copy = original.project
        copy.id = UUID()
        copy.name = ProjectNames.copyName(of: original.project.name)
        copy.createdAt = now
        copy.updatedAt = now
        let thumbnail = try? Data(contentsOf: folder(for: id).appending(path: FileName.thumbnail))
        try save(copy, sketch: original.sketch, ink: original.ink, thumbnail: thumbnail)
        return copy
    }

    /// Removes the project's folder, broken or not.
    func delete(folderNamed name: String) throws {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        // Only ever a folder directly inside Projects/ (paths, not URLs: URL
        // equality cares about a trailing slash).
        guard !name.isEmpty, !name.contains("/"), name != "..", name != ".",
              folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else { return }
        if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
    }

    func delete(_ id: UUID) throws {
        try delete(folderNamed: id.uuidString)
    }
}

/// Project names: what's typed in Rename, and copies.
enum ProjectNames {
    static let untitled = "Untitled logo"
    static let maxLength = 40

    /// Trimmed and at most 40 characters; empty keeps `fallback`.
    static func cleaned(_ typed: String, fallback: String) -> String {
        let trimmed = typed.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    static func copyName(of name: String) -> String {
        String(name.prefix(maxLength - 5)) + " copy"
    }
}
