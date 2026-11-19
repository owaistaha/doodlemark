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
        /// The lesson player, then its complete screen.
        case lesson(LessonSession)
    }

    enum GalleryTab: Hashable { case myLogos, learn }

    var screen: Screen = .gallery
    var tab: GalleryTab = .myLogos
    @ObservationIgnored let store: ProjectStore
    let gallery: GalleryModel
    let learn: LearnProgressStore
    /// The bundled lessons, easy → harder.
    @ObservationIgnored let lessons: [Lesson]

    init(store: ProjectStore, learn: LearnProgressStore = LearnProgressStore(), lessons: [Lesson] = LessonLibrary.all()) {
        self.store = store
        self.learn = learn
        self.lessons = lessons
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

    // MARK: Learn

    /// Opens a lesson where it was left, or from the start (`fresh`: "Try for N stars").
    func openLesson(_ lesson: Lesson, fresh: Bool = false) {
        saveNow()
        screen = .lesson(LessonSession(lesson: lesson, progress: learn, resume: !fresh))
    }

    /// The lesson after `lesson` in the list, if any.
    func lesson(after lesson: Lesson) -> Lesson? {
        lessons.firstIndex { $0.id == lesson.id }.flatMap { lessons.indices.contains($0 + 1) ? lessons[$0 + 1] : nil }
    }

    /// Out of a lesson (✕, or "All lessons"): where the kid got to is saved.
    func closeLesson() {
        saveNow()
        tab = .learn
        showGallery()
    }

    /// "Make it yours": the lesson's drawing becomes a new project, saved
    /// right away (so it's in My logos even if nothing else changes), and
    /// opens in the editor.
    func makeItYours(from lesson: LessonSession) {
        let made = lesson.makeItYours()
        let session = CanvasSession(model: CanvasModel(project: made.project, ink: made.ink), store: store, isOnDisk: false)
        session.autosaver.saveNow(evenIfUnchanged: true)
        tab = .myLogos
        screen = .canvas(session)
    }

    /// Back from the canvas: save first, then the gallery shows the new thumbnail.
    func closeCanvas() {
        saveNow()
        showGallery()
    }

    /// Leaving the canvas or the app: write what's pending right away.
    func saveNow() {
        switch screen {
        case .canvas(let session):
            session.model.endTyping()
            session.autosaver.saveNow()
        case .lesson(let session):
            session.saveForLater()
        default:
            break
        }
    }
}

extension AppModel {
    /// The one app model, made on first use. SwiftUI may build `RootView`
    /// more than once, so nothing with side effects goes in its init.
    static let shared: AppModel = {
        let store = ProjectStore()
        store.removeLeftovers()                         // unfinished saves from a crash
        ExportFiles.removeLeftovers()                   // export files a share sheet never cleaned up
        #if DEBUG
        DebugLaunch.prepare(store)
        #endif
        #if DEBUG
        let learn = DebugLaunch.learnStore()
        #else
        let learn = LearnProgressStore()
        #endif
        let app = AppModel(store: store, learn: learn)
        #if DEBUG
        if DebugLaunch.opensNewLogo { app.startNewProject(prompt: nil) }
        TouchTrace.install()
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
            case .lesson(let session):
                LessonScreen(session: session, app: app)
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
