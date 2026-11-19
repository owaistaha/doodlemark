import SwiftUI

/// The home screen (design/Gallery.png): "My logos" with the cards grid,
/// newest edited first, and the Learn tab (step 8b; a placeholder for now).
struct GalleryScreen: View {
    @Bindable var app: AppModel
    @State private var renaming: ProjectSummary?
    @State private var draftName = ""
    @State private var deleting: GalleryEntry?

    private var gallery: GalleryModel { app.gallery }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                GalleryHeader(tab: $app.tab, onNewLogo: { app.showNewLogo() })
                switch app.tab {
                case .myLogos: myLogos
                case .learn: LearnComingSoon()
                }
                #if DEBUG
                DebugLinks()
                #endif
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
        .renameAlert(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                     name: $draftName) {
            if let renaming { gallery.rename(renaming.id, to: draftName) }
        }
        .alert(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { entry in
            Button("Delete", role: .destructive) { gallery.delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's gone for good. This can't be undone.")
        }
    }

    @ViewBuilder private var myLogos: some View {
        TitleAndIdeas { prompt in app.startNewProject(prompt: prompt) }
        if gallery.isEmpty {
            EmptyGallery { app.showNewLogo() }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: Theme.Metrics.cardGap)],
                      spacing: Theme.Metrics.cardGap) {
                NewLogoTile { app.showNewLogo() }
                ForEach(gallery.entries) { entry in
                    switch entry {
                    case .project(let summary):
                        ProjectCard(summary: summary) { app.open(summary.id) }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") {
                                    draftName = summary.name
                                    renaming = summary
                                }
                                Button("Duplicate", systemImage: "plus.square.on.square") { gallery.duplicate(summary.id) }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
                            }
                    case .broken:
                        BrokenCard { deleting = entry }
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
                            }
                    }
                }
            }
        }
    }

    private var deleteTitle: String {
        switch deleting {
        case .project(let summary)?: "Delete \u{201C}\(summary.name)\u{201D}?"
        default: "Delete this logo?"
        }
    }
}

// MARK: - Header

private struct GalleryHeader: View {
    @Binding var tab: AppModel.GalleryTab
    let onNewLogo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 14) {
                AppMark(side: 52)
                Text("Doodlemark").font(Theme.wordmark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            TabSwitch(tab: $tab)

            PrimaryButton(title: "New logo", symbol: "plus", height: Theme.Metrics.bigButton, action: onNewLogo)
                .accessibilityIdentifier("newLogo")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The app's mark: an ink tile with a tangerine squiggle.
struct AppMark: View {
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.24)
            .fill(Theme.ink)
            .frame(width: side, height: side)
            .overlay {
                Path { p in
                    let s = side
                    p.move(to: CGPoint(x: 0.2 * s, y: 0.64 * s))
                    p.addCurve(to: CGPoint(x: 0.5 * s, y: 0.5 * s),
                               control1: CGPoint(x: 0.26 * s, y: 0.22 * s), control2: CGPoint(x: 0.44 * s, y: 0.26 * s))
                    p.addCurve(to: CGPoint(x: 0.8 * s, y: 0.36 * s),
                               control1: CGPoint(x: 0.56 * s, y: 0.74 * s), control2: CGPoint(x: 0.74 * s, y: 0.78 * s))
                }
                .stroke(Theme.tangerine, style: StrokeStyle(lineWidth: side * 0.11, lineCap: .round, lineJoin: .round))
            }
            .accessibilityHidden(true)
    }
}

/// "My logos | Learn". Selected = pencil blue with white bold text (fill and
/// weight change, not color alone).
private struct TabSwitch: View {
    @Binding var tab: AppModel.GalleryTab

    var body: some View {
        HStack(spacing: 4) {
            item(.myLogos, title: "My logos", symbol: nil)
            item(.learn, title: "Learn", symbol: "graduationcap")
        }
        .padding(6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
    }

    private func item(_ value: AppModel.GalleryTab, title: String, symbol: String?) -> some View {
        let selected = tab == value
        return Button { tab = value } label: {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(selected ? Theme.cardTitle : Theme.bodyStrong)
            .foregroundStyle(selected ? Theme.surface : Theme.ink)
            .padding(.horizontal, 24)
            .frame(height: Theme.Metrics.barButton)
            .background(selected ? Theme.pencilBlue : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(value == .myLogos ? "tab-myLogos" : "tab-learn")
    }
}

/// "Your logos", the tagline, and "Need an idea?" prompt chips.
private struct TitleAndIdeas: View {
    let onPrompt: (Prompt) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) {
                title
                Spacer(minLength: 0)
                ideas
            }
            VStack(alignment: .leading, spacing: 20) {
                title
                ideas
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your logos").font(Theme.display)
                .accessibilityAddTraits(.isHeader)
            Text("Doodle it. Ink it. Export it.").font(Theme.body).foregroundStyle(Theme.inkMuted)
        }
        .fixedSize()
    }

    private var ideas: some View {
        HStack(spacing: 12) {
            Text("Need an idea?").font(Theme.bodyStrong).foregroundStyle(Theme.inkMuted)
            ForEach(Prompts.galleryChips) { prompt in
                Button { onPrompt(prompt) } label: {
                    Text(prompt.title)
                        .font(Theme.bodyStrong)
                        .lineLimit(1)
                        .padding(.horizontal, 18)
                        .frame(minHeight: Theme.Metrics.barButton)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Starts a new logo with this idea")
                .accessibilityIdentifier("chip-\(prompt.id)")
            }
        }
        .fixedSize()
    }
}

// MARK: - Cards

private struct NewLogoTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.tangerine)
                    .frame(width: Theme.Metrics.toolButton, height: Theme.Metrics.toolButton)
                    .overlay(Image(systemName: "plus").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.ink))
                Text("Start a new logo").font(Theme.cardTitle)
            }
            .frame(maxWidth: .infinity, minHeight: galleryCardHeight)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: Theme.Metrics.dashedBorder, dash: [6, 6])))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("startNewLogo")
    }
}

/// White card: the picture on `thumbBackdrop`, then name and "Edited …".
/// Card height: the picture plus the name and "Edited …".
private let galleryCardHeight = Theme.Metrics.thumbnailHeight + 96

private struct GalleryCard<Picture: View, Footer: View>: View {
    @ViewBuilder let picture: Picture
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metrics.thumbnailHeight)
                .background(Theme.thumbBackdrop)
            footer
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
        }
        .frame(height: galleryCardHeight)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

private struct ProjectCard: View {
    let summary: ProjectSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GalleryCard {
                ThumbnailImage(summary: summary)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.name).font(Theme.cardTitle).lineLimit(1)
                    Text(EditedLabel.text(for: summary.updatedAt)).font(Theme.label).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.name), \(EditedLabel.text(for: summary.updatedAt))")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the logo. Touch and hold for Rename, Duplicate and Delete.")
        .accessibilityIdentifier("projectCard")
    }
}

/// A project that couldn't be read: say so kindly and offer Delete.
private struct BrokenCard: View {
    let onDelete: () -> Void

    var body: some View {
        GalleryCard {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Theme.inkMuted)
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't open this logo").font(Theme.cardTitle).lineLimit(1).minimumScaleFactor(0.75)
                HStack(spacing: 12) {
                    Text("Its file is damaged.").font(Theme.label).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 0)
                    SecondaryButton(title: "Delete", compact: true, action: onDelete)
                        .accessibilityIdentifier("deleteBroken")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brokenCard")
    }
}

/// The saved thumbnail, decoded off the main thread and cached.
private struct ThumbnailImage: View {
    let summary: ProjectSummary
    @State private var image: UIImage?

    init(summary: ProjectSummary) {
        self.summary = summary
        _image = State(initialValue: ThumbnailCache.shared.cached(summary))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: ThumbnailCache.key(for: summary)) {
            image = await ThumbnailCache.shared.image(for: summary)
        }
    }
}

// MARK: - Empty and Learn

/// First launch: nothing saved yet.
private struct EmptyGallery: View {
    let onNewLogo: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            AppMark(side: 88)
            Text("No logos yet").font(Theme.title)
            Text("Every logo starts with a doodle. Tap New logo to make your first one.")
                .font(Theme.body).foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "New logo", symbol: "plus", height: Theme.Metrics.bigButton, action: onNewLogo)
                .accessibilityIdentifier("emptyNewLogo")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.canvas))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.canvas)
            .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: Theme.Metrics.dashedBorder, dash: [6, 6])))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emptyGallery")
    }
}

private struct LearnComingSoon: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "graduationcap")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.pencilBlue)
                .frame(width: 88, height: 88)
                .background(Theme.blueTint, in: Circle())
            Text("Lessons are coming soon").font(Theme.title)
            Text("Trace along, stroke by stroke, and learn to draw logos.")
                .font(Theme.body).foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("learnComingSoon")
    }
}
