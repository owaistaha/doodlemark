import Foundation

/// A named 3-color logo palette.
struct CuratedPalette: Equatable, Sendable {
    let name: String
    let colors: [HexColor]

    init(_ name: String, _ first: String, _ second: String, _ third: String) {
        self.name = name
        colors = [first, second, third].map { HexColor($0)! }
    }
}

/// Curated 3-color logo palettes. Logo data, not UI tokens: these colors end
/// up in the user's SVG.
///
/// Every palette follows the same rules (checked by `PaletteTests`):
/// - the **second** color is the darkest, so the default Ink pen draws dark
///   lines whichever palette is picked, and it has at least 3:1 contrast with
///   the other two (WCAG's minimum for graphics), so a line or name in it
///   reads on a shape in either of them;
/// - the three colors are clearly different from each other (CIE76 ΔE ≥ 25);
/// - every color shows up on the white canvas (contrast with white ≥ 1.4).
enum Palettes {
    static let curated: [CuratedPalette] = [
        CuratedPalette("Pizza rocket", "#FF5A1F", "#1C1B22", "#FFC93C"),
        CuratedPalette("Ocean", "#1E88E5", "#0D1B3E", "#4DD0E1"),
        CuratedPalette("Jungle", "#2EAD4B", "#123524", "#B5D93A"),
        CuratedPalette("Bubblegum", "#FF4F9A", "#3A1048", "#FFB3D1"),
        CuratedPalette("Grape soda", "#8A4DFF", "#1A1433", "#FFB547"),
        CuratedPalette("Lava", "#E63946", "#1D1A1F", "#FF9F1C"),
        CuratedPalette("Arcade", "#00BFA6", "#1B1B3A", "#FF4F8B"),
        CuratedPalette("Sunny", "#FFB000", "#3B2416", "#FF6B35"),
        CuratedPalette("Mint chip", "#2BD99F", "#1E2235", "#FF7A59"),
        CuratedPalette("Space", "#3D5AFE", "#0F0F1F", "#FFD23F"),
        CuratedPalette("Berry", "#D81B60", "#2A0E1F", "#F48FB1"),
        CuratedPalette("Racing", "#D62828", "#00203A", "#F77F00"),
    ]

    /// The default for new projects: tangerine, ink, butter (the Doodlemark look).
    static var starter: [HexColor] { curated[0].colors }

    /// The curated palette with exactly these colors, if any.
    static func curatedIndex(of colors: [HexColor]) -> Int? {
        curated.firstIndex { $0.colors == colors }
    }

    /// "Try another": the curated palette after `index`, wrapping around.
    /// `nil` (a custom palette) starts at the first one.
    static func indexAfter(_ index: Int?) -> Int {
        guard let index else { return 0 }
        return (index + 1) % curated.count
    }
}

extension Project {
    /// A new, empty project.
    static func blank(name: String = "Untitled logo", now: Date = Date()) -> Project {
        Project(id: UUID(), name: name, createdAt: now, updatedAt: now, palette: Palettes.starter,
                shapes: [], text: nil, symmetryOn: false, gridOn: false)
    }
}
