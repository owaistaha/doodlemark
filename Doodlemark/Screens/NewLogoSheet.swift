import SwiftUI

/// "What are we making today?" (design/NewLogo.png): a blank canvas, or one
/// of 9 prompts (Shuffle swaps in the 10th), then "Start drawing". The
/// prompt becomes the project's name.
struct NewLogoSheet: View {
    let onBack: () -> Void
    /// nil = blank canvas.
    let onStart: (Prompt?) -> Void

    @State private var deck = PromptDeck()
    @State private var choice: Prompt?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Gallery", systemImage: "chevron.left")
                        .font(Theme.bodyStrong)
                        .padding(.horizontal, 20)
                        .frame(height: Theme.Metrics.bigButton)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
                            .strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backToGallery")
                Spacer()
                Text("Pick a start").font(Theme.label).foregroundStyle(Theme.inkMuted)
            }

            Text("What are we making today?").font(Theme.display)
                .padding(.top, 32)
                .accessibilityAddTraits(.isHeader)
            Text("Start from a blank page, or pick a prompt and let your pencil go wild.")
                .font(Theme.body).foregroundStyle(Theme.inkMuted)
                .padding(.top, 8)

            HStack(alignment: .top, spacing: 32) {
                BlankCanvasCard(selected: choice == nil) { choice = nil }
                    .frame(width: 300)
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Or try a prompt").font(Theme.cardTitle)
                        Spacer()
                        SecondaryButton(title: "Shuffle", symbol: "shuffle", compact: true) {
                            withAnimation(.easeInOut(duration: 0.25)) { deck.shuffle() }
                        }
                        .accessibilityIdentifier("shuffle")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(deck.shown) { prompt in
                            PromptCard(prompt: prompt, selected: choice == prompt) {
                                choice = choice == prompt ? nil : prompt
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        (Text("Selected: ").foregroundStyle(Theme.inkMuted)
                         + Text(choice?.title ?? "Blank canvas").font(Theme.bodyStrong))
                            .font(Theme.body)
                            .lineLimit(2)
                            .accessibilityIdentifier("selectedStart")
                        Spacer(minLength: 0)
                        PrimaryButton(title: "Start drawing", symbol: "arrow.right", height: Theme.Metrics.bigButton,
                                      symbolTrailing: true) { onStart(choice) }
                            .accessibilityIdentifier("startDrawing")
                    }
                }
            }
            .padding(.top, 36)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(Theme.Metrics.screenPadding)
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
    }
}

/// The left card: blank canvas. Selected = blue tint + 2 pt blue border.
private struct BlankCanvasCard: View {
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.thumbBackdrop)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: Theme.Metrics.dashedBorder, dash: [6, 6])))
                    .overlay(Image(systemName: "pencil").font(.system(size: 44, weight: .regular)).foregroundStyle(Theme.inkMuted))
                    .aspectRatio(1, contentMode: .fit)
                Spacer(minLength: 24)
                Text("Blank canvas").font(Theme.title)
                Text("You already have an idea. Go!").font(Theme.label).foregroundStyle(selected ? Theme.blueText : Theme.inkMuted)
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(selected ? Theme.blueTint : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.canvas))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.canvas)
                .strokeBorder(selected ? Theme.pencilBlue : Theme.line,
                              lineWidth: selected ? Theme.Metrics.selectedBorder : Theme.Metrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.canvas))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blank canvas")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("blankCanvas")
    }
}

/// A prompt: colored square + title. Selected = blue tint + 2 pt blue border.
private struct PromptCard: View {
    let prompt: Prompt
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: Theme.Radius.button)
                    .fill(Theme.accent(prompt.accent))
                    .frame(width: Theme.Metrics.promptAccent, height: Theme.Metrics.promptAccent)
                Text(prompt.title)
                    .font(Theme.bodyStrong)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(selected ? Theme.blueTint : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(selected ? Theme.pencilBlue : Theme.line,
                              lineWidth: selected ? Theme.Metrics.selectedBorder : Theme.Metrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prompt.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("prompt-\(prompt.id)")
    }
}
