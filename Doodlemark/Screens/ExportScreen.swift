import PencilKit
import SwiftUI

/// The state of the Preview & export screen: the logo, the panel's choices,
/// and the files while the share sheet has them.
@MainActor @Observable
final class ExportModel: Identifiable {
    let project: Project
    let ink: PKDrawing
    var options: ExportOptions
    /// The real export render (transparent), for the big mockups.
    let logo: UIImage
    /// The tiny test, each rendered at its own size (points × screen scale),
    /// never scaled down from a big render: thin lines look as they will.
    let tiny: [TinyRender]
    /// What the last "Export & share" wrote (kept for the DEBUG probe).
    private(set) var sharedFiles: [URL] = []
    private(set) var isSharing = false
    var failed = false

    struct TinyRender: Identifiable {
        let points: CGFloat
        let image: UIImage
        var id: CGFloat { points }
    }

    init(project: Project, ink: PKDrawing, displayScale: CGFloat) {
        self.project = project
        self.ink = ink
        options = ExportOptions(fileName: ExportFiles.defaultFileName(for: project.name))
        logo = PNGExporter.image(project: project, ink: ink, pixelSide: Theme.Mockup.renderSide)
        tiny = Theme.Mockup.tinySizes.map { points in
            TinyRender(points: points, image: PNGExporter.image(project: project, ink: ink,
                                                                pixelSide: Int((points * displayScale).rounded())))
        }
    }

    /// The cleaned name the files get.
    var fileName: String {
        ExportFiles.fileName(from: options.fileName, fallback: ExportFiles.defaultFileName(for: project.name))
    }

    /// The line under the file name field: shows what the name became.
    var savesAs: String {
        switch (options.svg, options.png) {
        case (true, true): "Saves \(fileName).svg and \(fileName).png"
        case (true, false): "Saves \(fileName).svg"
        case (false, true): "Saves \(fileName).png"
        case (false, false): "Pick SVG, PNG or both."
        }
    }

    var canExport: Bool { options.hasFormat && !isSharing }

    /// Writes the files to a temp folder for the share sheet. Nil (and an
    /// alert) if that fails.
    func makeFiles() -> [URL]? {
        do {
            let urls = try ExportFiles.write(project: project, ink: ink, options: options)
            sharedFiles = urls
            isSharing = true
            return urls
        } catch {
            failed = true
            return nil
        }
    }

    /// The share sheet closed (shared or not): the temp files go.
    func finishSharing() {
        ExportFiles.cleanUp(urls: sharedFiles)
        isSharing = false
    }
}

/// design/Export.png: mockups on the left, the export panel on the right.
struct ExportScreen: View {
    @State var model: ExportModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Button(action: onBack) {
                    Label("Back to drawing", systemImage: "chevron.left")
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 20)
                        .frame(height: Theme.Metrics.bigButton)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
                            .strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backToDrawing")
                Text("Preview & export").font(Theme.heading).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, Theme.Metrics.barPadding)
            .frame(height: Theme.Metrics.topBarHeight + 16)
            .background(Theme.surface)
            Rectangle().fill(Theme.line).frame(height: Theme.Metrics.hairline)

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(model.project.name), out in the world")
                            .font(Theme.display).foregroundStyle(Theme.ink)
                            .lineLimit(2).minimumScaleFactor(0.6)
                            .accessibilityIdentifier("exportTitle")
                        Text("A good logo works big, tiny, light and dark. Check yours here.")
                            .font(Theme.body).foregroundStyle(Theme.inkMuted)
                        MockupGrid(model: model).padding(.top, 16)
                    }
                    .padding(Theme.Mockup.screenPadding)
                }
                .background(Theme.paper)
                Rectangle().fill(Theme.line).frame(width: Theme.Metrics.hairline)
                ExportPanel(model: model)
                    .frame(width: Theme.Metrics.exportPanelWidth)
                    .background(Theme.surface)
            }
        }
        .background(Theme.paper)
        .alert("Couldn't make the files", isPresented: $model.failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Something went wrong while saving them. Try again.")
        }
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            // Invisible probe: the files the share sheet got, and whether
            // they're still on disk (they're removed when it closes).
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(exportProbe)
                .accessibilityIdentifier("debugExport")
        }
        #endif
    }

    #if DEBUG
    private var exportProbe: String {
        let names = model.sharedFiles.map(\.lastPathComponent).joined(separator: ", ")
        let onDisk = model.sharedFiles.contains { FileManager.default.fileExists(atPath: $0.path) }
        return "files \(names.isEmpty ? "none" : names); sharing \(model.isSharing ? "yes" : "no"); on disk \(onDisk ? "yes" : "no")"
    }
    #endif
}

// MARK: - Export panel

private struct ExportPanel: View {
    @Bindable var model: ExportModel
    @State private var anchor = ShareAnchor.Holder()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export").font(Theme.title).foregroundStyle(Theme.ink)

            FormatCard(title: "SVG", badge: "Vector",
                       detail: "Sharp at any size. For websites, Figma and printing.",
                       isOn: $model.options.svg)
                .accessibilityIdentifier("formatSVG")
            FormatCard(title: "PNG · 1024 × 1024", badge: nil,
                       detail: "For profile pictures, stickers and messages.",
                       isOn: $model.options.png)
                .accessibilityIdentifier("formatPNG")

            Button {
                model.options.transparentBackground.toggle()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transparent background").font(Theme.bodyStrong)
                        Text(model.options.transparentBackground ? "PNG only. No background behind the logo."
                                                                  : "PNG only. The logo sits on paper.")
                            .font(Theme.small).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    Checkbox(isOn: model.options.transparentBackground)
                }
                .foregroundStyle(Theme.ink)
                .frame(minHeight: Theme.Metrics.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.options.png)
            .opacity(model.options.png ? 1 : 0.45)
            .accessibilityIdentifier("transparentBackground")
            .accessibilityValue(model.options.transparentBackground ? "on" : "off")

            VStack(alignment: .leading, spacing: 8) {
                Text("File name").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                TextField("logo", text: $model.options.fileName)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .frame(height: Theme.Metrics.bigButton)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .strokeBorder(Theme.lineStrong, lineWidth: Theme.Metrics.hairline))
                    .accessibilityIdentifier("fileName")
                Text(model.savesAs)
                    .font(Theme.small).foregroundStyle(Theme.inkMuted)
                    .accessibilityIdentifier("savesAs")
            }

            Spacer(minLength: 0)

            PrimaryButton(title: "Export & share", symbol: "square.and.arrow.up", height: Theme.Metrics.bigButton) {
                guard let urls = model.makeFiles(), let view = anchor.view else { return }
                SharePresenter.present(urls, from: view) { model.finishSharing() }
            }
            .frame(maxWidth: .infinity)
            .background(ShareAnchor(holder: anchor))
            .disabled(!model.canExport)
            .accessibilityIdentifier("exportAndShare")

            Text("Your sketch layer stays private. It's never exported.")
                .font(Theme.small).foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(Theme.Metrics.barPadding + 12)
    }
}

/// A format choice: checkbox, name, optional badge and a line on what it's for.
/// On = `blueTint` + 2 pt `pencilBlue` border, like every selected card.
private struct FormatCard: View {
    let title: String
    let badge: String?
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 14) {
                Checkbox(isOn: isOn)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(Theme.cardTitle)
                        if let badge {
                            Text(badge)
                                .font(Theme.labelStrong)
                                .foregroundStyle(Theme.surface)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Theme.pencilBlue, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
                        }
                    }
                    Text(detail).font(Theme.label).foregroundStyle(isOn ? Theme.blueText : Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Theme.blueTint : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(isOn ? Theme.pencilBlue : Theme.line,
                              lineWidth: isOn ? Theme.Metrics.selectedBorder : Theme.Metrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Blue filled square with a tick, or an empty bordered one.
private struct Checkbox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.tile)
            .fill(isOn ? Theme.pencilBlue : Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .strokeBorder(isOn ? Theme.pencilBlue : Theme.lineStrong, lineWidth: Theme.Metrics.selectedBorder))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.surface)
                }
            }
            .frame(width: Theme.Metrics.checkbox, height: Theme.Metrics.checkbox)
            .accessibilityHidden(true)
    }
}

// MARK: - Share sheet

/// The UIKit view the share popover points at (iPad needs a source).
private struct ShareAnchor: UIViewRepresentable {
    @MainActor final class Holder { weak var view: UIView? }
    let holder: Holder

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        holder.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { holder.view = view }
}

/// The system share sheet with the export files: AirDrop, Save to Files,
/// Save Image, Messages… `done` runs once it closes, shared or not.
@MainActor
enum SharePresenter {
    static func present(_ urls: [URL], from anchor: UIView, done: @escaping @MainActor () -> Void) {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = anchor
        controller.popoverPresentationController?.sourceRect = anchor.bounds
        controller.popoverPresentationController?.permittedArrowDirections = [.down]
        controller.completionWithItemsHandler = { _, _, _, _ in
            MainActor.assumeIsolated { done() }
        }
        var top = anchor.window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        guard let top else { return done() }
        top.present(controller, animated: true)
    }
}
