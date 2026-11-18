#if DEBUG
import SwiftUI

/// DEBUG-only links to the test screens, at the bottom of the canvas's right
/// panel. Release builds have no trace of them. Launch with
/// `-debugOpenExportTest YES` or `-debugOpenCanvasSpike YES` to open one directly.
struct DebugLinks: View {
    @State private var showingExport = UserDefaults.standard.bool(forKey: "debugOpenExportTest")
    @State private var showingSpike = UserDefaults.standard.bool(forKey: "debugOpenCanvasSpike")

    var body: some View {
        HStack(spacing: 16) {
            Button("Export test") { showingExport = true }
                .frame(minHeight: Theme.Metrics.minTarget)
            Button("Canvas spike") { showingSpike = true }
                .frame(minHeight: Theme.Metrics.minTarget)
        }
        .font(Theme.small)
        .foregroundStyle(Theme.inkMuted)
        .fullScreenCover(isPresented: $showingExport) { ExportDebugScreen() }
        .fullScreenCover(isPresented: $showingSpike) { CanvasSpikeScreen() }
    }
}
#endif
