import SwiftUI

@main
struct DoodlemarkApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Bootstrap: a blank paper screen. The gallery replaces this in step 6.
private struct RootView: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.paper
                .ignoresSafeArea()
            #if DEBUG
            DebugEntryButton()
            #endif
        }
    }
}

#if DEBUG
/// DEBUG-only way into the test screens. Release builds have no trace of them.
/// Launch with `-debugOpenExportTest YES` or `-debugOpenCanvasSpike YES` to
/// open one directly (handy for automation).
private struct DebugEntryButton: View {
    @State private var showingExport = UserDefaults.standard.bool(forKey: "debugOpenExportTest")
    @State private var showingSpike = UserDefaults.standard.bool(forKey: "debugOpenCanvasSpike")

    var body: some View {
        HStack(spacing: 0) {
            Button("Canvas spike") { showingSpike = true }
                .frame(minWidth: 44, minHeight: 44)
            Button("Export test") { showingExport = true }
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 20)
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkMuted)
        .fullScreenCover(isPresented: $showingExport) { ExportDebugScreen() }
        .fullScreenCover(isPresented: $showingSpike) { CanvasSpikeScreen() }
    }
}
#endif
