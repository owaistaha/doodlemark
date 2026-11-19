import SwiftUI

/// The three first-canvas tips (PRD: no onboarding, just "one 3-step tip
/// overlay on the first canvas"). Each points at its control.
enum CanvasTip: Int, CaseIterable, Sendable {
    case sketch, ink, export

    var title: String {
        switch self {
        case .sketch: "Sketch it messy first"
        case .ink: "Then trace it clean"
        case .export: "Show it to the world"
        }
    }

    var body: String {
        switch self {
        case .sketch: "Doodle your idea on the Sketch layer. Wobbly is fine. Nobody else sees it."
        case .ink: "Switch to Ink and draw over your sketch. These lines become your logo."
        case .export: "Tap Preview & export when you're happy. You can save it or send it."
        }
    }
}

/// Which tip is up. Shown once: the first canvas the user ever opens.
/// "Show drawing tips again" in Settings → Doodlemark (Settings.bundle)
/// brings them back once; DEBUG builds also have `-resetCanvasTips YES`
/// and `-hideCanvasTips YES`.
@MainActor @Observable
final class CanvasTipsModel {
    static let seenKey = "canvasTipsSeen"
    /// The Settings.bundle switch. Read once, then switched off again.
    static let showAgainKey = "showCanvasTipsAgain"

    private(set) var current: CanvasTip?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isShowing: Bool { current != nil }

    /// On opening a canvas: the first tip, if the tips haven't been seen
    /// (or Settings asked to see them again).
    func startIfNeeded() {
        if defaults.bool(forKey: Self.showAgainKey) {
            defaults.set(false, forKey: Self.showAgainKey)
            defaults.set(false, forKey: Self.seenKey)
        }
        guard current == nil, !defaults.bool(forKey: Self.seenKey) else { return }
        current = .sketch
    }

    /// "Got it": the next tip, or done after the last.
    func next() {
        guard let current else { return }
        if let following = CanvasTip(rawValue: current.rawValue + 1) {
            self.current = following
        } else {
            finish()
        }
    }

    /// "Skip tips", or the last "Got it". Never shown again.
    func finish() {
        current = nil
        defaults.set(true, forKey: Self.seenKey)
    }
}

// MARK: - Pointing at controls

/// Where each tip's control is, reported by the control itself.
struct CanvasTipAnchors: PreferenceKey {
    static let defaultValue: [CanvasTip: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CanvasTip: Anchor<CGRect>], nextValue: () -> [CanvasTip: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks the control a tip points at.
    func canvasTipAnchor(_ tip: CanvasTip) -> some View {
        anchorPreference(key: CanvasTipAnchors.self, value: .bounds) { [tip: $0] }
    }

    /// The tip overlay for the whole canvas screen.
    func canvasTips(_ tips: CanvasTipsModel) -> some View {
        overlayPreferenceValue(CanvasTipAnchors.self) { anchors in
            GeometryReader { proxy in
                if let tip = tips.current, let anchor = anchors[tip] {
                    CanvasTipLayer(tip: tip, target: proxy[anchor], size: proxy.size, tips: tips)
                }
            }
            .ignoresSafeArea()                          // dim the status bar strip too
        }
    }
}

/// Dims everything but the control, rings it, and shows the tip card next
/// to it. Touches don't reach the canvas while it's up.
private struct CanvasTipLayer: View {
    let tip: CanvasTip
    let target: CGRect
    let size: CGSize
    let tips: CanvasTipsModel

    private var hole: CGRect { target.insetBy(dx: -Theme.Tips.holePadding, dy: -Theme.Tips.holePadding) }

    /// Rail tools (left) get the card to their right; the top-bar button
    /// gets it underneath.
    private var below: Bool { target.midX > size.width / 2 }

    private var cardOrigin: CGPoint {
        let width = Theme.Tips.cardWidth
        if below {
            let x = min(max(Theme.Metrics.barPadding, target.maxX - width), size.width - width - Theme.Metrics.barPadding)
            return CGPoint(x: x, y: hole.maxY + Theme.Tips.arrow + Theme.Tips.gap)
        }
        return CGPoint(x: hole.maxX + Theme.Tips.arrow + Theme.Tips.gap,
                       y: max(Theme.Metrics.barPadding, target.midY - Theme.Tips.arrowInset))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRoundedRect(in: hole, cornerSize: CGSize(width: Theme.Radius.card, height: Theme.Radius.card))
            }
            .fill(Theme.Tips.scrim, style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture {}                                // the canvas waits until the tips are done
            .accessibilityHidden(true)

            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.pencilBlue, lineWidth: Theme.Tips.ring)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            TipCard(tip: tip, below: below, arrowAt: below ? target.midX - cardOrigin.x : target.midY - cardOrigin.y,
                    tips: tips)
                .offset(x: cardOrigin.x, y: cardOrigin.y)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.2), value: tip)
    }
}

private struct TipCard: View {
    let tip: CanvasTip
    /// The arrow is on the top edge (card below the control) or the left edge.
    let below: Bool
    /// Where along that edge the arrow points from, in card coordinates.
    let arrowAt: CGFloat
    let tips: CanvasTipsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tip \(tip.rawValue + 1) of \(CanvasTip.allCases.count)").sectionLabelStyle()
            Text(tip.title).font(Theme.title).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(tip.body).font(Theme.body).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if tip != CanvasTip.allCases.last {
                    Button("Skip tips") { tips.finish() }
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.inkMuted)
                        .frame(minWidth: Theme.Metrics.minTarget, minHeight: Theme.Metrics.bigButton)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tipSkip")
                }
                Spacer(minLength: 0)
                PrimaryButton(title: "Got it", symbol: "checkmark", height: Theme.Metrics.bigButton) { tips.next() }
                    .accessibilityIdentifier("tipGotIt")
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: Theme.Tips.cardWidth, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(alignment: .topLeading) {
            TipArrow(pointsUp: below)
                .fill(Theme.surface)
                .frame(width: below ? Theme.Tips.arrow * 2 : Theme.Tips.arrow,
                       height: below ? Theme.Tips.arrow : Theme.Tips.arrow * 2)
                .offset(x: below ? arrowAt - Theme.Tips.arrow : -Theme.Tips.arrow + 1,
                        y: below ? -Theme.Tips.arrow + 1 : arrowAt - Theme.Tips.arrow)
                .accessibilityHidden(true)
        }
        .shadow(color: Theme.CanvasShadow.color, radius: Theme.CanvasShadow.radius, y: Theme.CanvasShadow.y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tip \(tip.rawValue + 1) of \(CanvasTip.allCases.count). \(tip.title)")
        .accessibilityIdentifier("canvasTip")
        .accessibilityAddTraits(.isModal)
    }
}

/// The little triangle from the card to the control.
private struct TipArrow: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        Path { path in
            if pointsUp {
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            path.closeSubpath()
        }
    }
}
