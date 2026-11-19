import SwiftUI

/// A lesson on screen: the player, then the complete screen.
struct LessonScreen: View {
    let session: LessonSession
    let app: AppModel

    var body: some View {
        Group {
            if session.isFinished {
                LessonCompleteScreen(session: session, app: app)
            } else {
                LessonPlayer(session: session, onClose: { app.closeLesson() })
            }
        }
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
    }
}

/// The lesson player (design/Lesson.png): the canvas in lesson mode (Ink
/// only, the ghost, the start dot and arrow, Mirror on for Mirror lessons)
/// on the left; the step, its tip and "how", the result card and Redo /
/// Next on the right.
struct LessonPlayer: View {
    let session: LessonSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LessonTopBar(session: session, onClose: onClose)
            Rectangle().fill(Theme.line).frame(height: Theme.Metrics.hairline)
            HStack(spacing: 0) {
                LessonCanvasArea(session: session)
                Rectangle().fill(Theme.line).frame(width: Theme.Metrics.hairline)
                LessonPanel(session: session)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
    }
}

// MARK: - Top bar

private struct LessonTopBar: View {
    let session: LessonSession
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                BarIconButton(symbol: "xmark", label: "Leave the lesson. Your place is saved.", action: onClose)
                    .accessibilityIdentifier("closeLesson")
                Text(session.lesson.title).font(Theme.heading).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StepProgress(current: session.stepIndex, count: session.lesson.steps.count)

            SecondaryButton(title: "Skip this step") { session.skip() }
                .fixedSize()
                .accessibilityHint("No stars for this step. The line is drawn in for you.")
                .accessibilityIdentifier("skipStep")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Metrics.barPadding)
        .frame(height: Theme.Metrics.topBarHeight)
        .background(Theme.surface)
    }
}

/// One bar per step (done = ink, now = pencil blue, to come = line) and
/// "Step 3 of 5". Done and current differ in color and in being filled
/// vs. the light "to come" bars.
private struct StepProgress: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index < current ? Theme.ink : index == current ? Theme.pencilBlue : Theme.line)
                        .frame(width: Theme.Learn.progressBar.width, height: Theme.Learn.progressBar.height)
                }
            }
            Text("Step \(min(current + 1, count)) of \(count)").font(Theme.bodyStrong).monospacedDigit()
                .lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(min(current + 1, count)) of \(count)")
        .accessibilityIdentifier("stepProgress")
    }
}

// MARK: - Canvas

private struct LessonCanvasArea: View {
    let session: LessonSession
    private let verticalInset: CGFloat = 80
    private let horizontalInset: CGFloat = 40

    var body: some View {
        let canvas = session.canvas
        GeometryReader { geo in
            let side = max(0, min(geo.size.width - 2 * horizontalInset, geo.size.height - 2 * verticalInset))
            ZStack {
                Theme.canvasBackdrop
                PencilCanvas(model: canvas, config: canvas.stackConfig)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.canvas))
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.canvas)
                            .fill(Theme.surface)
                            .shadow(color: Theme.CanvasShadow.color, radius: Theme.CanvasShadow.radius,
                                    y: Theme.CanvasShadow.y))
            }
            .overlay(alignment: .bottom) {
                HintPill(text: hint)
                    .padding(.bottom, (verticalInset - Theme.Metrics.minTarget) / 2)
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                // Invisible; lets the UI test trace the current target.
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(debugTarget)
                    .accessibilityIdentifier("debugLessonTarget")
            }
            #endif
        }
    }

    private var hint: String {
        if session.step?.kind == .shape { return "Tap Place it to put the shape in" }
        if session.lesson.mirror { return "Mirror is on: the other side draws itself" }
        return "Start on the blue dot and follow the dashed line"
    }

    #if DEBUG
    /// "x,y;x,y;…" in canvas space, the current ink step's target.
    private var debugTarget: String {
        (session.step?.points ?? []).map { "\(Double($0.x)),\(Double($0.y))" }.joined(separator: ";")
    }
    #endif
}

// MARK: - Right panel

private struct LessonPanel: View {
    let session: LessonSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let step = session.step {
                        Text("Step \(session.stepIndex + 1) · \(step.name)").sectionLabelStyle()
                        Text(step.tip).font(Theme.title)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("stepTip")
                        Text(Self.how(step.how)).font(Theme.body).foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let pending = session.pending {
                        ResultCard(score: pending.score)
                            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
            }
            actions
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
        .frame(width: Theme.Learn.panelWidth)
        .background(Theme.surface)
        .animation(.easeOut(duration: 0.2), value: session.pending)
    }

    @ViewBuilder private var actions: some View {
        if session.pending != nil {
            HStack(spacing: 16) {
                SecondaryButton(title: "Redo", symbol: "arrow.counterclockwise", height: Theme.Metrics.bigButton) {
                    session.redo()
                }
                .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHint("Takes the line away so you can draw it again")
                    .accessibilityIdentifier("redoStroke")
                PrimaryButton(title: isLastStep ? "Finish" : "Next step", symbol: isLastStep ? "checkmark" : "arrow.right",
                              height: Theme.Metrics.bigButton, symbolTrailing: true, fullWidth: true) { session.next() }
                    .accessibilityIdentifier("nextStep")
            }
        } else if session.step?.kind == .shape {
            PrimaryButton(title: "Place it", symbol: "plus.circle", height: Theme.Metrics.bigButton, fullWidth: true) {
                session.placeShape()
            }
            .accessibilityIdentifier("placeShape")
        } else {
            Text("Your turn: draw on the canvas.").font(Theme.label).foregroundStyle(Theme.inkMuted)
                .frame(minHeight: Theme.Metrics.bigButton)
        }
    }

    private var isLastStep: Bool { session.stepIndex == session.lesson.steps.count - 1 }

    /// The "how" line with "blue dot" picked out in pencil blue.
    static func how(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: "blue dot") {
            attributed[range].foregroundColor = Theme.pencilBlue
            attributed[range].font = Theme.bodyStrong
        }
        return attributed
    }
}

/// After a stroke: the stars and the fixed feedback copy.
private struct ResultCard: View {
    let score: StrokeScore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StarsView(stars: score.stars, size: Theme.Learn.resultStar)
                .accessibilityIdentifier("resultStars")
            Text(score.feedback.title).font(Theme.heading)
                .accessibilityIdentifier("resultTitle")
            Text(score.feedback.tip).font(Theme.body).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.canvas))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.canvas).strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("resultCard")
    }
}
