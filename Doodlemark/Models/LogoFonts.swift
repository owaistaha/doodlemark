import CoreText
import Foundation

/// A bundled logo font: a static OFL file from google/fonts, registered in
/// `UIAppFonts`, with its license in `Resources/Fonts/<Name>-OFL.txt`.
struct LogoFont: Identifiable, Equatable, Sendable {
    /// PostScript name: what `LogoText.fontName` stores and Core Text loads.
    let postScriptName: String
    /// Shown in the font picker, written in the font itself.
    let displayName: String
    /// One word for the style, under the name.
    let style: String

    var id: String { postScriptName }
}

/// The only fonts logo text can use. Never SF Pro or any system font: their
/// license doesn't allow them in user logos (CLAUDE.md, TECH_SPEC "Fonts").
enum LogoFonts {
    static let all: [LogoFont] = [
        LogoFont(postScriptName: "LilitaOne", displayName: "Lilita One", style: "Bubbly"),
        LogoFont(postScriptName: "Bungee-Regular", displayName: "Bungee", style: "Blocky"),
        LogoFont(postScriptName: "Sniglet-ExtraBold", displayName: "Sniglet", style: "Rounded"),
        LogoFont(postScriptName: "Pacifico-Regular", displayName: "Pacifico", style: "Script"),
        LogoFont(postScriptName: "Poppins-ExtraBold", displayName: "Poppins", style: "Clean"),
    ]

    /// New text starts in Lilita One (also the export gate's font).
    static var defaultFont: LogoFont { all[0] }

    static func font(named postScriptName: String) -> LogoFont? {
        all.first { $0.postScriptName == postScriptName }
    }

    /// The characters of `string` the font can't draw, or all of them if the
    /// font isn't bundled.
    static func missingCharacters(in string: String, fontName: String) -> [Character] {
        guard font(named: fontName) != nil,
              let ctFont = try? GlyphPaths.font(named: fontName, size: 100) else { return Array(string) }
        return GlyphPaths.missingCharacters(in: string, font: ctFont)
    }
}
