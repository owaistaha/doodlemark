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
/// DEBUG-only way into the export test screen. Release builds have no trace of it.
/// Launch with `-debugOpenExportTest YES` to open it directly (handy for automation).
private struct DebugEntryButton: View {
    @State private var showing = UserDefaults.standard.bool(forKey: "debugOpenExportTest")

    var body: some View {
        Button("Export test") { showing = true }
            .font(.footnote)
            .foregroundStyle(Theme.inkMuted)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 20)
            .fullScreenCover(isPresented: $showing) { ExportDebugScreen() }
    }
}
#endif
