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
/// Every file is written to a temp file in the same folder and then renamed
/// over the old one (`rename(2)` is atomic), so a crash mid-save leaves the
/// old file or the new one, never half of one. `project.json` is written
/// last: a folder always has a complete set of files from some save.
@MainActor
final class ProjectStore {
    enum FileName {
        static let project = "project.json"
        static let sketch = "sketch.drawing"
        static let ink = "ink.drawing"
        static let thumbnail = "thumb.png"
        /// Temp files are ".<name>.saving-<uuid>": hidden, and never read.
        static let savingMarker = ".saving-"
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

    /// Writes the temp file. Tests swap it to simulate a crash part-way through.
    var writeTemporaryFile: (Data, URL) throws -> Void = { data, url in try data.write(to: url) }

    init(root: URL = ProjectStore.defaultRoot) {
        self.root = root
    }

    func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    // MARK: Save

    /// Writes the whole project. `project.updatedAt` is saved as given.
    func save(_ project: Project, sketch: PKDrawing, ink: PKDrawing, thumbnail: Data?) throws {
        let folder = folder(for: project.id)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        removeTemporaryFiles(in: folder)
        try writeAtomically(sketch.dataRepresentation(), to: folder.appending(path: FileName.sketch))
        try writeAtomically(ink.dataRepresentation(), to: folder.appending(path: FileName.ink))
        if let thumbnail {
            try writeAtomically(thumbnail, to: folder.appending(path: FileName.thumbnail))
        }
        try writeProjectFile(project, in: folder)
    }

    private func writeProjectFile(_ project: Project, in folder: URL) throws {
        let data = try ProjectCoding.makeEncoder().encode(ProjectFile(project: project))
        try writeAtomically(data, to: folder.appending(path: FileName.project))
    }

    /// Temp file, then rename over the destination.
    func writeAtomically(_ data: Data, to destination: URL) throws {
        let temp = destination.deletingLastPathComponent()
            .appending(path: "." + destination.lastPathComponent + FileName.savingMarker + UUID().uuidString)
        do {
            try writeTemporaryFile(data, temp)
        } catch {
            try? files.removeItem(at: temp)
            throw error
        }
        guard Darwin.rename(temp.path, destination.path) == 0 else {
            let code = errno
            try? files.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)])
        }
    }

    /// Leftovers of a save that never finished (the app was killed).
    private func removeTemporaryFiles(in folder: URL) {
        let names = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.contains(FileName.savingMarker) {
            try? files.removeItem(at: folder.appending(path: name))
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

    /// Changes only the name (and not "last edited").
    func rename(_ id: UUID, to name: String) throws {
        let folder = folder(for: id)
        var project = try readProjectFile(in: folder)
        project.name = name
        try writeProjectFile(project, in: folder)
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
