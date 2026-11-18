import SwiftUI

@main
struct DoodlemarkApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Until the gallery exists (step 6), the app opens straight to a blank canvas.
private struct RootView: View {
    @State private var model = CanvasModel(project: .blank())

    var body: some View {
        CanvasScreen(model: model)
    }
}
