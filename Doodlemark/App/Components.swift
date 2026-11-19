import SwiftUI

// Buttons shared by the gallery, the New logo screen and the canvas
// (DESIGN.md style guide). Colors and sizes only from Theme.

/// Tangerine main action. Text on tangerine is always ink (DESIGN.md).
struct PrimaryButton: View {
    let title: String
    let symbol: String
    /// 48 in the editor bar, 56 on the gallery and New logo screens.
    var height: CGFloat = Theme.Metrics.barButton
    /// The symbol after the title ("Start drawing →").
    var symbolTrailing = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if !symbolTrailing { Image(systemName: symbol) }
                Text(title)
                if symbolTrailing { Image(systemName: symbol) }
            }
                .font(height > Theme.Metrics.barButton ? Theme.cardTitle : Theme.bodyStrong)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, height > Theme.Metrics.barButton ? 28 : 20)
                .frame(height: height)
                .background(Theme.tangerine, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

/// "Secondary" from the style guide: white with a border, ink text.
struct SecondaryButton: View {
    let title: String
    var symbol: String?
    var compact = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .font(compact ? Theme.labelStrong : Theme.bodyStrong)
            .foregroundStyle(isEnabled ? Theme.ink : Theme.lineStrong)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 36 : Theme.Metrics.barButton)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small)
                .strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
            .frame(minHeight: Theme.Metrics.minTarget)   // 44 pt target even when it looks compact
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

