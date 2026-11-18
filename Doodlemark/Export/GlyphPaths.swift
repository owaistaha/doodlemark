import CoreGraphics
import CoreText
import Foundation

/// Turns logo text into glyph outlines in canvas space. The SVG exporter uses
/// these instead of `<text>`, so the file looks right without the font installed.
///
/// Layout goes through `CTLine`, so kerning and ligatures match what Core Text
/// draws on screen. Each glyph is placed at its `CTRun` position.
///
/// Placement: the center of the line's typographic box (advance width ×
/// ascent+descent) sits on `center`, then the outline rotates around it.
enum GlyphPaths {
    enum Failure: Error, Equatable {
        /// The font isn't registered (not bundled or not listed in `UIAppFonts`).
        case fontUnavailable(String)
        /// The font can't draw these characters. Core Text would quietly use a
        /// system font for them, which must never reach a logo (license; RISKS #7).
        case missingGlyphs(String)
    }

    /// Loads a bundled font by PostScript name. Core Text silently substitutes
    /// a system font for unknown names, so this checks for that and refuses.
    /// System fonts must never end up in a logo (license).
    static func font(named postScriptName: String, size: CGFloat) throws(Failure) -> CTFont {
        let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
        guard CTFontCopyPostScriptName(font) as String == postScriptName else {
            throw .fontUnavailable(postScriptName)
        }
        return font
    }

    static func path(for text: LogoText) throws(Failure) -> CGPath {
        let font = try font(named: text.fontName, size: text.pointSize)
        return try path(string: text.displayString, font: font, tracking: text.tracking,
                        center: text.center, rotation: text.rotation)
    }

    /// The characters of `string` that `font` has no glyph for (emoji, other
    /// scripts, missing accents), each listed once, in order. Checked with
    /// `CTFontGetGlyphsForCharacters`, the same lookup Core Text does before it
    /// falls back to another font.
    static func missingCharacters(in string: String, font: CTFont) -> [Character] {
        var missing: [Character] = []
        for character in string where !missing.contains(character) {
            let units = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            let found = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
            if !found || glyphs.contains(0) || character.isNewline { missing.append(character) }
        }
        return missing
    }

    static func path(string: String, font: CTFont, tracking: CGFloat = 0,
                     center: CGPoint, rotation: Double) throws(Failure) -> CGPath {
        let line = makeLine(string: string, font: font, tracking: tracking)
        let box = typographicBox(of: line)
        let fontName = CTFontCopyPostScriptName(font) as String

        // Collect the outlines in line space: baseline at y = 0, y pointing up.
        let outlines = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            // Core Text puts characters the logo font lacks into a run with a
            // fallback (system) font. Refuse: the text tool blocks those
            // characters, so this only guards against a gap in that check.
            let runFont = Self.runFont(of: run) ?? font
            guard CTFontCopyPostScriptName(runFont) as String == fontName else {
                let range = CTRunGetStringRange(run)
                let characters = (string as NSString).substring(with: NSRange(location: range.location, length: range.length))
                throw .missingGlyphs(characters)
            }

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)

            for (glyph, position) in zip(glyphs, positions) {
                guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                outlines.addPath(glyphPath, transform: CGAffineTransform(translationX: position.x, y: position.y))
            }
        }

        // Line space → canvas space: center the box on the origin, flip y, rotate, move.
        var transform = lineToCanvasTransform(box: box, center: center, rotation: rotation)
        return outlines.copy(using: &transform) ?? outlines
    }

    /// The transform from Core Text line space (y up, baseline at 0) to canvas
    /// space. Shared so the native reference renderer can place `CTLineDraw` the same way.
    static func lineToCanvasTransform(box: CGRect, center: CGPoint, rotation: Double) -> CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(rotation))
            .scaledBy(x: 1, y: -1)
            .translatedBy(x: -box.midX, y: -box.midY)
    }

    private static func runFont(of run: CTRun) -> CTFont? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as String] else { return nil }
        let object = value as CFTypeRef
        guard CFGetTypeID(object) == CTFontGetTypeID() else { return nil }
        return (object as! CTFont)
    }

    /// One line of text. `tracking` (1/1000 em) is extra space after every
    /// character but the last, so it never adds a gap at the end that would
    /// push the line off centre.
    static func makeLine(string: String, font: CTFont, tracking: CGFloat = 0) -> CTLine {
        let attributed = NSMutableAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let range = trackedRange(of: string)
        if tracking != 0, range.length > 0 {
            attributed.addAttribute(NSAttributedString.Key(kCTKernAttributeName as String),
                                    value: kern(tracking: tracking, pointSize: CTFontGetSize(font)), range: range)
        }
        return CTLineCreateWithAttributedString(attributed)
    }

    /// Tracking in 1/1000 em → Core Text kern in points.
    static func kern(tracking: CGFloat, pointSize: CGFloat) -> CGFloat {
        tracking / 1000 * pointSize
    }

    /// Every character but the last (UTF-16 range, whole characters).
    static func trackedRange(of string: String) -> NSRange {
        let ns = string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let last = ns.rangeOfComposedCharacterSequence(at: ns.length - 1)
        return NSRange(location: 0, length: last.location)
    }

    /// Advance width × (ascent + descent), in line space (y up, baseline at 0).
    static func typographicBox(of line: CTLine) -> CGRect {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
    }
}
