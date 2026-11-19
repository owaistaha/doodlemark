#if DEBUG
import PencilKit
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import os

/// DEBUG-only launch flags for UI tests and screenshots (release builds have
/// no trace of them):
/// - `-resetProjects YES`: start with no saved projects.
/// - `-seedSampleProjects YES`: add a few sample logos (edited over the last
///   weeks, one sketch-only) so the gallery has something to show.
/// - `-seedBrokenProject YES`: add a project folder whose project.json is garbage.
/// - `-openNewLogo YES`: open straight onto a new blank logo (the canvas UI tests).
/// - `-traceTouches YES`: log every touch and tool change (see `TouchTrace`).
/// - `-resetCanvasTips YES`: show the first-canvas tips again.
/// - `-hideCanvasTips YES`: mark them seen (UI tests that aren't about tips).
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
        if defaults.bool(forKey: "resetCanvasTips") { defaults.removeObject(forKey: CanvasTipsModel.seenKey) }
        if defaults.bool(forKey: "hideCanvasTips") { defaults.set(true, forKey: CanvasTipsModel.seenKey) }
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

#if DEBUG
/// With `-traceTouches YES`, every touch phase in the window (where it
/// landed, which view, the recognizers' states) and every tool change go to
/// the unified log, category "touchtrace". No UI, so it re-renders nothing.
/// Read it with `xcrun simctl spawn <device> log show --predicate
/// 'category == "touchtrace"'`. Made for the step 6 lost-first-tap hunt.
@MainActor
enum TouchTrace {
    static let log = Logger(subsystem: "com.owaistaha.doodlemark", category: "touchtrace")
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "traceTouches") }
    private static let start = Date()

    static func note(_ message: String) {
        guard enabled else { return }
        let t = String(format: "%.2f", Date().timeIntervalSince(start))
        log.notice("TRACE t\(t, privacy: .public) \(message, privacy: .public)")
    }

    static func install() {
        guard enabled else { return }
        note("start")
        Task { @MainActor in
            for _ in 0..<400 {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
                    window.addGestureRecognizer(TouchLogger())
                    note("installed on key window \(window.bounds.size)")
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}

/// Sees every touch in a window without taking part.
private final class TouchLogger: UIGestureRecognizer {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }
    private func note(_ phase: String, _ touches: Set<UITouch>) {
        guard let touch = touches.first, let view else { return }
        let p = touch.location(in: view)
        let hit = view.hitTest(p, with: nil).map { String(describing: type(of: $0)) } ?? "nil"
        let others = (touch.gestureRecognizers ?? []).filter { $0 !== self }
            .map { "\(type(of: $0)):\($0.state.rawValue)" }.joined(separator: ",")
        TouchTrace.note("\(phase) @\(Int(p.x)),\(Int(p.y)) hit \(hit) recognizers [\(others)]")
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { note("began", touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { note("ended", touches); state = .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { note("cancelled", touches); state = .failed }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
#endif
