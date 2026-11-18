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
        return path(string: text.string, font: font, center: text.center, rotation: text.rotation)
    }

    static func path(string: String, font: CTFont, center: CGPoint, rotation: Double) -> CGPath {
        let line = makeLine(string: string, font: font)
        let box = typographicBox(of: line)

        // Collect the outlines in line space: baseline at y = 0, y pointing up.
        let outlines = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            // A run can use a fallback font for characters the logo font lacks;
            // use the run's own font so the outline matches what's on screen.
            let runFont = Self.runFont(of: run) ?? font

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

    static func makeLine(string: String, font: CTFont) -> CTLine {
        let attributed = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        return CTLineCreateWithAttributedString(attributed)
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
