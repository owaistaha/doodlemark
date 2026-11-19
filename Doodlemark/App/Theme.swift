import SwiftUI

/// Design tokens from DESIGN.md. This is the only file that may contain hex
/// values: views use these names, never raw colors, fonts or sizes.
enum Theme {
    // MARK: Colors (DESIGN.md → Color tokens)

    /// App background.
    static let paper = Color(hex: 0xFBF8F2)
    /// Cards, panels, top bar, tool rail.
    static let surface = Color(hex: 0xFFFFFF)
    /// Area around the drawing square.
    static let canvasBackdrop = Color(hex: 0xEFEAE0)
    /// Gallery thumbnail backgrounds, empty tiles.
    static let thumbBackdrop = Color(hex: 0xF3EFE7)
    /// Text, icons, ink strokes.
    static let ink = Color(hex: 0x1C1B22)
    /// Secondary text (passes 4.5:1 on paper and white).
    static let inkMuted = Color(hex: 0x5E5B66)
    /// Borders, dividers.
    static let line = Color(hex: 0xE7E2D8)
    /// Dashed "new" tiles, text field borders.
    static let lineStrong = Color(hex: 0xCFC8BA)
    /// Primary buttons, main action. Text on it is always `ink`.
    static let tangerine = Color(hex: 0xFF5A1F)
    /// Selected tool, toggles that are on, active layer, focus rings.
    static let pencilBlue = Color(hex: 0x2F5BFF)
    /// Background of selected rows/cards (with a 2pt `pencilBlue` border).
    static let blueTint = Color(hex: 0xEEF2FF)
    /// Secondary text on `blueTint`.
    static let blueText = Color(hex: 0x3A4CB8)
    /// Small highlights only (hint dot, logo accents).
    static let butter = Color(hex: 0xFFC93C)
    /// Sketch-layer pencil color (faded look).
    static let sketchStroke = Color(hex: 0xC9C3D3)
    /// `paper` as file data: the PNG export background when "Transparent
    /// background" is off.
    static let paperHex = HexColor(red: 0xFB, green: 0xF8, blue: 0xF2)

    // MARK: Type (DESIGN.md → Type). UI fonts only; logo text uses the logo fonts.

    enum FontName {
        static let display = "BricolageGrotesque-ExtraBold"   // 800
        static let regular = "Inter-Regular"                 // 400
        static let semibold = "Inter-SemiBold"               // 600
        static let bold = "Inter-Bold"                       // 700
    }

    /// Display 44–48 (big screen titles).
    static let display = Font.custom(FontName.display, size: 44)
    /// Title 28.
    static let title = Font.custom(FontName.display, size: 28)
    /// Heading 20–24 (project name in the editor bar).
    static let heading = Font.custom(FontName.display, size: 22)
    /// Body 17.
    static let body = Font.custom(FontName.regular, size: 17)
    /// Buttons and row names: body size, semibold.
    static let bodyStrong = Font.custom(FontName.semibold, size: 17)
    /// Labels 15.
    static let label = Font.custom(FontName.regular, size: 15)
    static let labelStrong = Font.custom(FontName.semibold, size: 15)
    /// Small 13.
    static let small = Font.custom(FontName.regular, size: 13)
    /// The "Doodlemark" wordmark next to the app mark in the gallery.
    static let wordmark = Font.custom(FontName.display, size: 30)
    /// Project name on a gallery card, prompt card titles.
    static let cardTitle = Font.custom(FontName.bold, size: 20)
    /// Section labels: 13 semibold, uppercase, +0.6 tracking (see `sectionLabel()`).
    static let sectionLabel = Font.custom(FontName.semibold, size: 13)
    static let sectionLabelTracking: CGFloat = 0.6

    // MARK: Shape, spacing, touch (DESIGN.md → Shape, spacing, touch)

    enum Radius {
        static let tile: CGFloat = 8        // layer icon tiles, checkboxes
        static let small: CGFloat = 12      // small controls, pills
        static let button: CGFloat = 16     // buttons
        static let card: CGFloat = 20       // cards, tools, layer rows
        static let canvas: CGFloat = 28     // big panels and the canvas
    }

    enum Metrics {
        static let grid: CGFloat = 8
        static let barPadding: CGFloat = 20        // editor bars
        static let minTarget: CGFloat = 44
        static let topBarHeight: CGFloat = 72
        static let barButton: CGFloat = 48         // square top-bar buttons
        static let toolRailWidth: CGFloat = 100
        static let toolButton: CGFloat = 76
        static let rightPanelWidth: CGFloat = 300
        static let layerRowHeight: CGFloat = 56
        static let iconTile: CGFloat = 32
        static let swatch: CGFloat = 60
        static let hairline: CGFloat = 1
        static let selectedBorder: CGFloat = 2     // selected rows and cards
        static let screenPadding: CGFloat = 48     // gallery and New logo
        static let bigButton: CGFloat = 56         // gallery/New logo primary buttons
        static let dashedBorder: CGFloat = 2       // "Start a new logo" tile, blank canvas
        static let cardGap: CGFloat = 24
        static let thumbnailHeight: CGFloat = 168  // gallery card picture area
        static let promptAccent: CGFloat = 56      // colored square on a prompt card
        static let exportPanelWidth: CGFloat = 400 // Preview & export right panel
        static let checkbox: CGFloat = 28
    }

    /// First-canvas tips.
    enum Tips {
        static let cardWidth: CGFloat = 380
        /// Space around the control inside its ring.
        static let holePadding: CGFloat = 6
        static let ring: CGFloat = 3
        /// The triangle from the card to the control.
        static let arrow: CGFloat = 12
        static let gap: CGFloat = 6
        /// Card top to its arrow, for cards beside a rail tool.
        static let arrowInset: CGFloat = 44
        static let scrim = Theme.ink.opacity(0.35)
    }

    /// Preview & export mockups (design/Export.png).
    enum Mockup {
        /// Pixel size of the logo render the big mockups use.
        static let renderSide = 512
        /// Padding around the mockups (smaller than the gallery's 48 so all
        /// four fit on a landscape screen).
        static let screenPadding: CGFloat = 32
        static let cardHeight: CGFloat = 262
        static let appIcon: CGFloat = 150
        /// The app-icon corner as a share of its side (the home-screen look).
        static let appIconCornerRatio: CGFloat = 0.225
        static let sticker: CGFloat = 170
        static let stickerRim: CGFloat = 12
        /// The tiny test, in points (each drawn at its own size).
        static let tinySizes: [CGFloat] = [96, 48, 24, 16]
        static let lightDarkLogo: CGFloat = 112
        static let captionStrip: CGFloat = 52
    }

    /// Learn: lesson cards, the lesson player, the complete screen.
    enum Learn {
        static let cardMinWidth: CGFloat = 300
        /// Card: the picture, then title, "Easy · …" and the stars line.
        static let cardHeight: CGFloat = Metrics.thumbnailHeight + 132
        /// Lesson card picture: the drawing's line art fits this square.
        static let previewSide: CGFloat = 136
        static let previewLine: CGFloat = 4
        static let previewDash: [CGFloat] = [5, 5]
        static let cardStar: CGFloat = 20
        static let resultStar: CGFloat = 34
        static let totalStar: CGFloat = 44
        static let doneBadge: CGFloat = 88
        static let panelWidth: CGFloat = 400
        static let progressBar = CGSize(width: 52, height: 8)
        /// Body text on the ink "Logo tip" card.
        static let onInkMuted = Theme.surface.opacity(0.82)
    }

    /// The small square on a prompt card.
    static func accent(_ accent: Prompt.Accent) -> Color {
        switch accent {
        case .tangerine: tangerine
        case .blue: pencilBlue
        case .ink: ink
        case .butter: butter
        }
    }

    /// The only shadow: canvas square and mockups, `0 12 40 ink@10%`.
    enum CanvasShadow {
        static let color = Theme.ink.opacity(0.10)
        static let radius: CGFloat = 20            // SwiftUI radius ≈ CSS blur / 2
        static let y: CGFloat = 12
    }
}

extension View {
    /// DESIGN.md section label: 13 semibold, uppercase, +0.6 tracking, muted.
    func sectionLabelStyle() -> some View {
        font(Theme.sectionLabel)
            .tracking(Theme.sectionLabelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkMuted)
    }
}

// `fileprivate` so only Theme can turn a hex literal into a color.
fileprivate extension Color {
    /// sRGB color from a `0xRRGGBB` literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
