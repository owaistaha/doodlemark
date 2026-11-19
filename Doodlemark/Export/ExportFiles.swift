import Foundation
import PencilKit

/// What "Export & share" makes: the choices in the export panel.
struct ExportOptions: Equatable {
    var svg = true
    var png = true
    /// PNG only. Off = the paper color (#FBF8F2) behind the logo.
    var transparentBackground = true
    /// As typed; `ExportFiles.fileName(from:fallback:)` cleans it.
    var fileName: String

    /// At least one format has to be picked.
    var hasFormat: Bool { svg || png }
}

/// Writing the export files. No UI here, so it's all unit-tested.
enum ExportFiles {
    static let pngSide = 1024
    /// DESIGN.md `paper`, the PNG background when "Transparent background" is off.
    static let paper = Theme.paperHex

    enum Failure: Error, Equatable {
        /// No Ink, shapes or text: "Draw something first." (CLAUDE.md).
        case nothingToExport
        case noFormat
    }

    /// True when there's nothing that would be exported. The Sketch layer
    /// doesn't count: it's never exported.
    static func isEmpty(project: Project, ink: PKDrawing) -> Bool {
        ink.strokes.isEmpty && project.shapes.isEmpty && (project.text?.string.isEmpty ?? true)
    }

    /// A safe file name: letters (accents folded away), digits, "-" and "_";
    /// spaces and anything else become single dashes; no slashes, dots or
    /// control characters; at most 60 characters. Empty → `fallback`.
    static func fileName(from typed: String, fallback: String = "logo") -> String {
        let folded = typed.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
        var result = ""
        var lastWasDash = true                          // no leading dash
        for scalar in folded.unicodeScalars {
            let ascii = scalar.isASCII
            if ascii, CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        result = String(result.prefix(60))
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? fallback : result
    }

    /// The default file name: the project name in kebab-case ("Moon Café" → "moon-cafe").
    static func defaultFileName(for projectName: String) -> String {
        fileName(from: projectName.lowercased())
    }

    /// The SVG bytes: exactly the gated exporter's output.
    static func svgData(project: Project, ink: PKDrawing) throws -> Data {
        Data(try SVGExporter.svg(project: project, ink: ink).utf8)
    }

    /// The 1024 × 1024 PNG: the thumbnails' renderer (Shapes, Ink, Text; never
    /// the sketch), on transparency or on paper.
    @MainActor
    static func pngData(project: Project, ink: PKDrawing, transparent: Bool) -> Data? {
        PNGExporter.pngData(project: project, ink: ink, pixelSide: pngSide, background: transparent ? nil : paper)
    }

    /// Writes the chosen files into a new folder inside `parent` and returns
    /// them (SVG first). The caller shares them and then calls `cleanUp`.
    @MainActor
    static func write(project: Project, ink: PKDrawing, options: ExportOptions,
                      in parent: URL = FileManager.default.temporaryDirectory) throws -> [URL] {
        guard !isEmpty(project: project, ink: ink) else { throw Failure.nothingToExport }
        guard options.hasFormat else { throw Failure.noFormat }
        let name = fileName(from: options.fileName, fallback: defaultFileName(for: project.name))
        let folder = parent.appending(path: "Export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        do {
            if options.svg {
                let url = folder.appending(path: "\(name).svg")
                try svgData(project: project, ink: ink).write(to: url, options: .atomic)
                urls.append(url)
            }
            if options.png {
                let url = folder.appending(path: "\(name).png")
                guard let data = pngData(project: project, ink: ink, transparent: options.transparentBackground) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
        } catch {
            cleanUp(urls: [folder])
            throw error
        }
        return urls
    }

    /// At launch: export folders a share sheet never got to clean up (the
    /// app was killed while it was open).
    static func removeLeftovers(in parent: URL = FileManager.default.temporaryDirectory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names where name.hasPrefix("Export-") {
            try? FileManager.default.removeItem(at: parent.appending(path: name))
        }
    }

    /// Removes the export folder once the share sheet is done with it.
    static func cleanUp(urls: [URL]) {
        let folders = Set(urls.map { $0.hasDirectoryPath ? $0 : $0.deletingLastPathComponent() })
        for folder in folders where folder.lastPathComponent.hasPrefix("Export-") {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
