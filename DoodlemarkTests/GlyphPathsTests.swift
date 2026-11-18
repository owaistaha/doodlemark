import CoreText
import XCTest
@testable import Doodlemark

/// Text → glyph outlines in canvas space, using the bundled Lilita One.
final class GlyphPathsTests: XCTestCase {
    func testBundledLogoFontIsRegistered() throws {
        let font = try GlyphPaths.font(named: Fixtures.logoFont, size: 40)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, Fixtures.logoFont)
    }

    func testPizzaGivesANonEmptyOutline() throws {
        let path = try GlyphPaths.path(for: Fixtures.pizzaText())
        XCTAssertFalse(path.isEmpty)
        let b = path.boundingBoxOfPath
        XCTAssertGreaterThan(b.width, 100)
        XCTAssertGreaterThan(b.height, 40)
    }

    func testOutlineIsCenteredOnTextCenter() throws {
        let text = Fixtures.pizzaText(center: CGPoint(x: 300, y: 450))
        let b = try GlyphPaths.path(for: text).boundingBoxOfPath
        // The typographic box is centered; ink bounds differ by side bearings, so allow a few points.
        XCTAssertEqual(b.midX, 300, accuracy: 8)
        XCTAssertEqual(b.midY, 450, accuracy: 30)
    }

    func testTextIsUprightNotMirrored() throws {
        // "Pizza" has no descenders, so its ink sits on the baseline. With y down,
        // the baseline is at center.y + box.midY. A missing y-flip would put the
        // ink *below* the baseline instead.
        let text = Fixtures.pizzaText()
        let font = try GlyphPaths.font(named: text.fontName, size: text.pointSize)
        let box = GlyphPaths.typographicBox(of: GlyphPaths.makeLine(string: text.string, font: font))
        let baselineY = text.center.y + box.midY
        let b = try GlyphPaths.path(for: text).boundingBoxOfPath
        XCTAssertEqual(b.maxY, baselineY, accuracy: 3)
        XCTAssertLessThan(b.minY, baselineY - 40)
    }

    func testQuarterTurnMakesTheWordTall() throws {
        let flat = try GlyphPaths.path(for: Fixtures.pizzaText()).boundingBoxOfPath
        let turned = try GlyphPaths.path(for: Fixtures.pizzaText(rotation: .pi / 2)).boundingBoxOfPath
        XCTAssertEqual(turned.height, flat.width, accuracy: 1)
        XCTAssertEqual(turned.width, flat.height, accuracy: 1)
    }

    func testUnknownFontIsRefusedInsteadOfFallingBack() {
        var text = Fixtures.pizzaText()
        text.fontName = "NotARealFont-Bold"
        XCTAssertThrowsError(try GlyphPaths.path(for: text)) { error in
            XCTAssertEqual(error as? GlyphPaths.Failure, .fontUnavailable("NotARealFont-Bold"))
        }
    }
}
