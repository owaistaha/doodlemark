import SwiftUI

/// Design tokens from DESIGN.md. This is the only file that may contain hex
/// values: views use these names, never raw colors.
///
/// Fonts, spacing and radii are added when their first screen needs them.
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
