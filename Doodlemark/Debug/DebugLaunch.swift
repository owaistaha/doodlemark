#if DEBUG
import PencilKit
import SwiftUI

/// DEBUG-only launch flags for UI tests and screenshots (release builds have
/// no trace of them):
/// - `-resetProjects YES`: start with no saved projects.
/// - `-seedSampleProjects YES`: add a few sample logos (edited over the last
///   weeks, one sketch-only) so the gallery has something to show.
/// - `-seedBrokenProject YES`: add a project folder whose project.json is garbage.
/// - `-openNewLogo YES`: open straight onto a new blank logo (the canvas UI tests).
enum DebugLaunch {
    private static var defaults: UserDefaults { .standard }

    static var opensNewLogo: Bool { defaults.bool(forKey: "openNewLogo") }

    @MainActor
    static func prepare(_ store: ProjectStore) {
        if defaults.bool(forKey: "resetProjects") {
            try? FileManager.default.removeItem(at: store.root)
        }
        if defaults.bool(forKey: "seedSampleProjects") { SampleProjects.seed(into: store) }
        if defaults.bool(forKey: "seedBrokenProject") { SampleProjects.seedBroken(into: store) }
    }
}

/// Sample logos built in code: shapes, text, Ink lines and one sketch-only
/// project, all through the real store (so thumbnails are the real ones).
enum SampleProjects {
    @MainActor
    static func seed(into store: ProjectStore, now: Date = Date()) {
        let day: TimeInterval = 24 * 60 * 60
        func project(_ name: String, palette: Int, daysAgo: Double, shapes: [LogoShape],
                     text: LogoText? = nil, ink: [PKStroke] = [], sketch: [PKStroke] = []) {
            var p = Project.blank(name: name, now: now.addingTimeInterval(-daysAgo * day))
            p.palette = Palettes.curated[palette].colors
            p.shapes = shapes
            p.text = text
            let inkDrawing = PKDrawing(strokes: ink), sketchDrawing = PKDrawing(strokes: sketch)
            try? store.save(p, sketch: sketchDrawing, ink: inkDrawing,
                            thumbnail: Thumbnail.pngData(project: p, sketch: sketchDrawing, ink: inkDrawing))
        }
        func shape(_ kind: LogoShape.Kind, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
                   _ fill: PaletteSlot, rotation: Double = 0) -> LogoShape {
            LogoShape(id: UUID(), kind: kind, center: CGPoint(x: x, y: y), size: size, rotation: rotation, fill: fill)
        }
        func line(_ points: [CGPoint], width: CGFloat = 36, palette: Int, slot: PaletteSlot) -> PKStroke {
            stroke(points, ink: PKInk(.monoline, color: UIColor(cgColor: Palettes.curated[palette].colors[slot.rawValue].cgColor)),
                   width: width)
        }

        project("Pizza Rocket", palette: 0, daysAgo: 0,
                shapes: [shape(.circle, 512, 512, 760, .first), shape(.triangle, 512, 470, 330, .second),
                         shape(.circle, 512, 450, 90, .third)])
        project("Moon Café", palette: 9, daysAgo: 1,
                shapes: [shape(.roundedSquare, 512, 512, 760, .second), shape(.circle, 470, 470, 380, .third),
                         shape(.circle, 580, 400, 300, .second)])
        project("Team Bolt", palette: 1, daysAgo: 3,
                shapes: [shape(.triangle, 512, 560, 820, .first, rotation: .pi), shape(.star, 512, 470, 300, .third)])
        project("Star Club", palette: 0, daysAgo: 8,
                shapes: [shape(.circle, 512, 512, 800, .second), shape(.circle, 512, 512, 680, .third),
                         shape(.star, 512, 530, 520, .first)],
                text: LogoText(string: "STAR CLUB", fontName: "Bungee-Regular", center: CGPoint(x: 512, y: 900),
                               pointSize: 90, rotation: 0, fill: .second))
        project("Wave Surf School", palette: 1, daysAgo: 15,
                shapes: [shape(.roundedSquare, 512, 512, 780, .first), shape(.circle, 700, 330, 170, .third)],
                ink: [line(wave(), width: 56, palette: 1, slot: .third)])
        project("Leafy Market", palette: 2, daysAgo: 16, shapes: [],
                sketch: [stroke(leaf(), ink: PKInk(.pencil, color: UIColor(Theme.sketchStroke)), width: 10)])
    }

    @MainActor
    static func seedBroken(into store: ProjectStore) {
        let folder = store.folder(for: UUID())
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data("{ this is not a project".utf8).write(to: folder.appending(path: ProjectStore.FileName.project))
    }

    private static func stroke(_ points: [CGPoint], ink: PKInk, width: CGFloat) -> PKStroke {
        let controlPoints = points.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index) * 0.01,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
    }

    private static func wave() -> [CGPoint] {
        stride(from: 0.0, through: 1, by: 0.02).map { t in
            CGPoint(x: 230 + 560 * t, y: 600 - 90 * sin(t * 2 * .pi))
        }
    }

    private static func leaf() -> [CGPoint] {
        let outline = stride(from: 0.0, through: 1, by: 0.02).map { t -> CGPoint in
            let a = t * 2 * .pi
            return CGPoint(x: 512 + 300 * cos(a) * 0.9, y: 512 + 170 * sin(a) * (cos(a) > 0 ? 1 : 0.9))
        }
        return outline + [CGPoint(x: 260, y: 640), CGPoint(x: 780, y: 400)]
    }
}
#endif
