import SwiftUI

/// The four "out in the world" mockups (design/Export.png), all drawn from
/// the real export render (`PNGExporter`): what you see is what you share.
struct MockupGrid: View {
    let model: ExportModel

    var body: some View {
        Grid(horizontalSpacing: Theme.Metrics.cardGap, verticalSpacing: Theme.Metrics.cardGap) {
            GridRow {
                MockupCard(background: Theme.surface) {
                    AppIconMockup(logo: model.logo)
                    Text("App icon").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                }
                .mockupAccessibility("App icon preview", id: "mockupAppIcon")
                MockupCard(background: Theme.pencilBlue) {
                    StickerMockup(logo: model.logo)
                    Text("Sticker").font(Theme.bodyStrong).foregroundStyle(Theme.surface)
                }
                .mockupAccessibility("Round sticker preview", id: "mockupSticker")
            }
            GridRow {
                MockupCard(background: Theme.surface) {
                    HStack(alignment: .center, spacing: 28) {
                        ForEach(model.tiny) { render in
                            Image(uiImage: render.image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: render.points, height: render.points)
                        }
                    }
                    .frame(height: Theme.Mockup.tinySizes.max())
                    VStack(spacing: 2) {
                        Text("Tiny test").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                        Text(Theme.Mockup.tinySizes.map { "\(Int($0))" }.joined(separator: " · ")
                             + " px. Can you still tell what it is?")
                            .font(Theme.label).foregroundStyle(Theme.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .mockupAccessibility("Tiny test at 96, 48, 24 and 16", id: "mockupTiny")
                LightDarkMockup(logo: model.logo)
                    .mockupAccessibility("Light and dark backgrounds", id: "mockupLightDark")
            }
        }
    }
}

/// A mockup card: big rounded panel, contents centered.
private struct MockupCard<Content: View>: View {
    let background: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 16) { content }
            .padding(20)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Mockup.cardHeight)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.canvas))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.canvas)
                .strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
    }
}

/// The logo as a home-screen icon: on paper, in the rounded app-icon shape.
private struct AppIconMockup: View {
    let logo: UIImage

    var body: some View {
        let side = Theme.Mockup.appIcon
        Image(uiImage: logo)
            .resizable()
            .interpolation(.high)
            .background(Theme.paper)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * Theme.Mockup.appIconCornerRatio, style: .continuous))
            .shadow(color: Theme.CanvasShadow.color, radius: Theme.CanvasShadow.radius, y: Theme.CanvasShadow.y)
    }
}

/// The logo as a round die-cut sticker: a white rim around a circle crop.
private struct StickerMockup: View {
    let logo: UIImage

    var body: some View {
        let side = Theme.Mockup.sticker
        ZStack {
            Circle().fill(Theme.surface)
            Image(uiImage: logo)
                .resizable()
                .interpolation(.high)
                .background(Theme.paper)
                .clipShape(Circle())
                .padding(Theme.Mockup.stickerRim)
        }
        .frame(width: side, height: side)
        .shadow(color: Theme.CanvasShadow.color, radius: Theme.CanvasShadow.radius, y: Theme.CanvasShadow.y)
    }
}

/// The transparent logo on paper and on ink, side by side.
private struct LightDarkMockup: View {
    let logo: UIImage

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                half(Theme.paper)
                half(Theme.ink)
            }
            Rectangle().fill(Theme.line).frame(height: Theme.Metrics.hairline)
            Text("Light & dark").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Mockup.captionStrip)
                .background(Theme.surface)
        }
        .frame(height: Theme.Mockup.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.canvas))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.canvas)
            .strokeBorder(Theme.line, lineWidth: Theme.Metrics.hairline))
    }

    private func half(_ color: Color) -> some View {
        color.overlay {
            Image(uiImage: logo)
                .resizable()
                .interpolation(.high)
                .frame(width: Theme.Mockup.lightDarkLogo, height: Theme.Mockup.lightDarkLogo)
        }
    }
}

private extension View {
    func mockupAccessibility(_ label: String, id: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier(id)
    }
}
