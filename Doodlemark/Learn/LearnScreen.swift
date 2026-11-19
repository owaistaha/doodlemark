import SwiftUI

/// The Learn tab (design/Learn.png): "Learn to sketch", the five lesson
/// cards easy → harder (any one can be opened), and a logo tip card.
struct LearnTab: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Learn to sketch").font(Theme.display)
                    .accessibilityAddTraits(.isHeader)
                Text("Trace one stroke at a time. Every lesson ends as a logo you can keep.")
                    .font(Theme.body).foregroundStyle(Theme.inkMuted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Learn.cardMinWidth), spacing: Theme.Metrics.cardGap)],
                      spacing: Theme.Metrics.cardGap) {
                ForEach(app.lessons) { lesson in
                    LessonCard(lesson: lesson, progress: app.learn.progress(for: lesson.id)) {
                        app.openLesson(lesson)
                    }
                }
                LogoTipCard()
            }
        }
    }
}

/// "★ 25 stars": every lesson's best, added up. In the header on the Learn tab.
struct StarTotalPill: View {
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill").foregroundStyle(Theme.butter)
                .overlay(Image(systemName: "star").foregroundStyle(Theme.ink))
            Text(total == 1 ? "1 star" : "\(total) stars").font(Theme.bodyStrong)
        }
        .padding(.horizontal, 22)
        .frame(height: Theme.Metrics.bigButton)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button).strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) stars earned in lessons")
        .accessibilityIdentifier("starTotal")
    }
}

/// `stars` filled out of `of`, butter with an ink outline (filled vs. empty
/// is a shape change too, not color alone). VoiceOver: "2 of 3 stars".
struct StarsView: View {
    let stars: Int
    var of: Int = 3
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.22) {
            ForEach(0..<of, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(index < stars ? Theme.butter : Color.clear)
                    .overlay(Image(systemName: "star").font(.system(size: size, weight: .regular)).foregroundStyle(Theme.ink))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) of \(of) stars")
    }
}

/// A lesson card: the line-art picture, title, "Easy · what it teaches",
/// then "Best: 13 of 15" with stars, or "New". A lesson left halfway is
/// tinted, outlined and says "Continue · step 3 of 5".
private struct LessonCard: View {
    let lesson: Lesson
    let progress: LessonProgress?
    let action: () -> Void

    private var resume: LessonResume? { progress?.inProgress }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                LessonPreview(lesson: lesson, doneSteps: resume?.step)
                    .frame(width: Theme.Learn.previewSide, height: Theme.Learn.previewSide)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metrics.thumbnailHeight)
                    .background(resume == nil ? Theme.thumbBackdrop : Theme.blueTint)
                    .overlay(alignment: .topLeading) {
                        if let resume {
                            Text("Continue · step \(resume.step + 1) of \(lesson.steps.count)")
                                .font(Theme.labelStrong)
                                .foregroundStyle(Theme.surface)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.pencilBlue, in: Capsule())
                                .padding(16)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text(lesson.title).font(Theme.cardTitle).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(lesson.levelName) · \(lesson.teaches)").font(Theme.label).foregroundStyle(Theme.inkMuted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    status.padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: Theme.Learn.cardHeight)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(resume == nil ? Theme.line : Theme.pencilBlue,
                              lineWidth: resume == nil ? Theme.Metrics.hairline : Theme.Metrics.selectedBorder))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("lesson-\(lesson.id)")
    }

    @ViewBuilder private var status: some View {
        if let best = progress?.bestStars {
            HStack(spacing: 10) {
                StarsView(stars: Self.cardStars(best: best, max: lesson.maxStars), size: Theme.Learn.cardStar)
                Text("Best: \(best) of \(lesson.maxStars)").font(Theme.bodyStrong)
            }
        } else if resume == nil {
            Text("New").font(Theme.bodyStrong).foregroundStyle(Theme.blueText)
        }
    }

    /// 0–3 card stars for a best score: the share of the maximum, rounded
    /// (13 of 15 → 3, 12 of 15 → 2).
    static func cardStars(best: Int, max: Int) -> Int {
        guard max > 0 else { return 0 }
        return Swift.min(3, Swift.max(0, Int((Double(best) * 3 / Double(max)).rounded())))
    }

    private var accessibilityText: String {
        var parts = [lesson.title, "\(lesson.levelName), \(lesson.teaches)"]
        if let resume { parts.append("Continue, step \(resume.step + 1) of \(lesson.steps.count)") }
        if let best = progress?.bestStars { parts.append("Best: \(best) of \(lesson.maxStars) stars") }
        else if resume == nil { parts.append("New") }
        return parts.joined(separator: ". ")
    }
}

/// A lesson's picture as line art: every step's target in ink (mirrored
/// halves included) and shape steps as outlines. With `doneSteps`, the steps
/// still to do are dashed pencil blue, like the ghost in the player.
struct LessonPreview: View {
    let lesson: Lesson
    var doneSteps: Int?

    var body: some View {
        Canvas { context, size in
            var marks: [(path: CGPath, width: CGFloat, done: Bool)] = []
            for (index, step) in lesson.steps.enumerated() {
                let done = doneSteps.map { index < $0 } ?? true
                for mark in LessonGhost(lesson: lesson, step: index).current {
                    marks.append((LessonGhost.path(mark), step.width ?? 0, done))
                }
            }
            // Fit the drawing (not the whole 1024 canvas) into the square.
            let box = marks.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
            guard !box.isNull, box.width > 0 || box.height > 0 else { return }
            let scale = min(size.width, size.height) / max(box.width, box.height)
            let transform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -box.midX, y: -box.midY)
            for mark in marks {
                let path = Path(mark.path).applying(transform)
                let width = max(Theme.Learn.previewLine, mark.width * scale)
                if mark.done {
                    context.stroke(path, with: .color(Theme.ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                } else {
                    context.stroke(path, with: .color(Theme.pencilBlue),
                                   style: StrokeStyle(lineWidth: Theme.Learn.previewLine * 0.75, lineCap: .round,
                                                      lineJoin: .round, dash: Theme.Learn.previewDash))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The dark "Logo tip" card at the end of the grid.
private struct LogoTipCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logo tip")
                .font(Theme.labelStrong)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.butter, in: Capsule())
            Text("Do the squint test").font(Theme.title).foregroundStyle(Theme.surface)
            Text("Squint at your logo until it's blurry. If you can still tell what it is, it will work as a tiny app icon too.")
                .font(Theme.body).foregroundStyle(Theme.Learn.onInkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Theme.Learn.cardHeight)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("logoTip")
    }
}
