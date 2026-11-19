import SwiftUI

/// Lesson complete (design/LessonDone.png): the drawing, the total stars,
/// stars per step, then "Make it yours" (a new project → the editor),
/// "Try for 15 stars" and "Next: <lesson>". The best score is already
/// saved by the session (never lowered by a worse retry).
struct LessonCompleteScreen: View {
    let session: LessonSession
    let app: AppModel
    @State private var picture: UIImage?

    private var lesson: Lesson { session.lesson }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.height - 2 * Theme.Metrics.screenPadding - Theme.Metrics.bigButton, geo.size.width * 0.4)
            HStack(alignment: .center, spacing: 64) {
                drawing(side: max(0, side))
                summary
                    .frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.Metrics.screenPadding)
        }
        .overlay(alignment: .topLeading) {
            BarIconButton(symbol: "xmark", label: "Back to lessons") { app.closeLesson() }
                .padding(Theme.Metrics.barPadding)
                .accessibilityIdentifier("closeLessonDone")
        }
        .background(Theme.paper.ignoresSafeArea())
        .task {
            picture = PNGExporter.image(project: session.canvas.project, ink: session.canvas.ink, pixelSide: 1024)
        }
    }

    private func drawing(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.canvas)
                .fill(Theme.surface)
                .shadow(color: Theme.CanvasShadow.color, radius: Theme.CanvasShadow.radius, y: Theme.CanvasShadow.y)
            if let picture {
                Image(uiImage: picture).resizable().interpolation(.high).scaledToFit()
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: Theme.Learn.doneBadge, height: Theme.Learn.doneBadge)
                .background(Theme.butter, in: Circle())
                .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 6))
                .offset(x: Theme.Learn.doneBadge / 3, y: -Theme.Learn.doneBadge / 3)
                .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel("Your \(lesson.shortName.lowercased()) drawing")
        .accessibilityIdentifier("lessonDrawing")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lesson complete").sectionLabelStyle()
                Text("\(lesson.shortName) done!").font(Theme.display)
                    .accessibilityAddTraits(.isHeader)
            }
            total
            stepChips
            Text("You learned \(lesson.learned). Now make it yours: add colors, your name, and export it.")
                .font(Theme.body).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Make it yours", symbol: "pencil", height: Theme.Metrics.bigButton, fullWidth: true) {
                app.makeItYours(from: session)
            }
            .accessibilityHint("Makes a new logo from this drawing and opens it")
            .accessibilityIdentifier("makeItYours")
            HStack(spacing: 16) {
                SecondaryButton(title: session.totalStars < lesson.maxStars ? "Try for \(lesson.maxStars) stars" : "Play again",
                                height: Theme.Metrics.bigButton) {
                    app.openLesson(lesson, fresh: true)
                }
                .accessibilityIdentifier("tryAgain")
                if let next = app.lesson(after: lesson) {
                    SecondaryButton(title: "Next: \(next.title)", height: Theme.Metrics.bigButton) { app.openLesson(next) }
                        .accessibilityIdentifier("nextLesson")
                } else {
                    SecondaryButton(title: "All lessons", height: Theme.Metrics.bigButton) { app.closeLesson() }
                        .accessibilityIdentifier("allLessons")
                }
            }
        }
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: "star.fill")
                    .font(.system(size: Theme.Learn.totalStar))
                    .foregroundStyle(Theme.butter)
                    .overlay(Image(systemName: "star").font(.system(size: Theme.Learn.totalStar)).foregroundStyle(Theme.ink))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.bottom] - 6 }
                Text("\(session.totalStars)").font(Theme.display)
                Text("of \(lesson.maxStars) stars").font(Theme.title).foregroundStyle(Theme.inkMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(session.totalStars) of \(lesson.maxStars) stars")
            .accessibilityIdentifier("lessonTotal")
            if let note = bestNote {
                Text(note).font(Theme.labelStrong).foregroundStyle(Theme.blueText)
                    .accessibilityIdentifier("bestNote")
            }
        }
    }

    /// A new best, or the best that a lower retry didn't change.
    private var bestNote: String? {
        guard let before = session.bestBefore else { return nil }
        if session.totalStars > before { return "New best. Your last best was \(before)." }
        if session.totalStars < before { return "Your best is still \(before) of \(lesson.maxStars)." }
        return nil
    }

    private var stepChips: some View {
        // One row, however many steps (4–8): equal chips, names on up to two lines.
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(zip(lesson.steps.indices, session.stars)), id: \.0) { index, stars in
                let name = lesson.steps[index].name
                VStack(spacing: 4) {
                    Text(name).font(Theme.small).foregroundStyle(Theme.inkMuted)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    HStack(spacing: 3) {
                        Text("\(stars)").font(Theme.bodyStrong)
                        Image(systemName: "star.fill").font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), \(stars) of 3 stars")
                .accessibilityIdentifier("stepStars-\(index + 1)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)       // equal-height chips
    }
}
