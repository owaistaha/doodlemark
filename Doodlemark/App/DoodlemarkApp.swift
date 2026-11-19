import PencilKit
import SwiftUI

@main
struct DoodlemarkApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands { CanvasCommands() }
    }
}

/// One open project: the editor state and what saves it.
@MainActor
final class CanvasSession: Identifiable {
    let model: CanvasModel
    let autosaver: ProjectAutosaver

    init(model: CanvasModel, store: ProjectStore, isOnDisk: Bool) {
        self.model = model
        autosaver = ProjectAutosaver(model: model, store: store, isOnDisk: isOnDisk)
    }
}

/// Which screen is up, and moving between them. The app opens to the
/// gallery (no splash, no onboarding).
@MainActor @Observable
final class AppModel {
    enum Screen {
        case gallery
        case newLogo
        case canvas(CanvasSession)
    }

    enum GalleryTab: Hashable { case myLogos, learn }

    var screen: Screen = .gallery
    var tab: GalleryTab = .myLogos
    @ObservationIgnored let store: ProjectStore
    let gallery: GalleryModel

    init(store: ProjectStore) {
        self.store = store
        gallery = GalleryModel(store: store)
    }

    func showNewLogo() { screen = .newLogo }

    func showGallery() {
        gallery.reload()
        screen = .gallery
    }

    /// A new project: named after the prompt, or "Untitled logo". It's
    /// written on its first change.
    func startNewProject(prompt: Prompt?) {
        let project = Project.blank(name: prompt?.title ?? ProjectNames.untitled)
        screen = .canvas(CanvasSession(model: CanvasModel(project: project), store: store, isOnDisk: false))
    }

    func open(_ id: UUID) {
        guard let loaded = gallery.open(id) else { return }     // the card turns into the error card
        let model = CanvasModel(project: loaded.project, sketch: loaded.sketch, ink: loaded.ink)
        screen = .canvas(CanvasSession(model: model, store: store, isOnDisk: true))
    }

    /// Back from the canvas: save first, then the gallery shows the new thumbnail.
    func closeCanvas() {
        saveNow()
        showGallery()
    }

    /// Leaving the canvas or the app: write what's pending right away.
    func saveNow() {
        if case .canvas(let session) = screen {
            session.model.endTyping()
            session.autosaver.saveNow()
        }
    }
}

extension AppModel {
    /// The one app model, made on first use. SwiftUI may build `RootView`
    /// more than once, so nothing with side effects goes in its init.
    static let shared: AppModel = {
        let store = ProjectStore()
        #if DEBUG
        DebugLaunch.prepare(store)
        #endif
        let app = AppModel(store: store)
        #if DEBUG
        if DebugLaunch.opensNewLogo { app.startNewProject(prompt: nil) }
        #endif
        return app
    }()
}

struct RootView: View {
    @State private var app = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch app.screen {
            case .gallery:
                GalleryScreen(app: app)
            case .newLogo:
                NewLogoSheet(onBack: { app.showGallery() }, onStart: { app.startNewProject(prompt: $0) })
            case .canvas(let session):
                CanvasScreen(model: session.model, autosaver: session.autosaver, onBack: { app.closeCanvas() })
                    .id(session.id)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Inactive comes first on the way to the app switcher (and a
            // force-quit), so save there already.
            if phase != .active { app.saveNow() }
        }
    }
}
