import Foundation

/// Curated 3-color logo palettes. Logo data, not UI tokens: these colors end
/// up in the user's SVG. Step 5 adds the full curated set and "Try another".
enum Palettes {
    /// The default for new projects: tangerine, ink, butter (the Doodlemark look).
    static let starter: [HexColor] = [
        HexColor(red: 0xFF, green: 0x5A, blue: 0x1F),
        HexColor(red: 0x1C, green: 0x1B, blue: 0x22),
        HexColor(red: 0xFF, green: 0xC9, blue: 0x3C),
    ]
}

extension Project {
    /// A new, empty project.
    static func blank(name: String = "Untitled logo", now: Date = Date()) -> Project {
        Project(id: UUID(), name: name, createdAt: now, updatedAt: now, palette: Palettes.starter,
                shapes: [], text: nil, symmetryOn: false, gridOn: false)
    }
}
