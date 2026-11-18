import CoreText
import SwiftUI
import UIKit
import XCTest
@testable import Doodlemark

/// Guards Theme.swift against typos: every color token must match DESIGN.md exactly.
@MainActor
final class ThemeTests: XCTestCase {
    func testColorTokensMatchDesignDoc() {
        let expected: [(name: String, color: Color, hex: UInt32)] = [
            ("paper", Theme.paper, 0xFBF8F2),
            ("surface", Theme.surface, 0xFFFFFF),
            ("canvasBackdrop", Theme.canvasBackdrop, 0xEFEAE0),
            ("thumbBackdrop", Theme.thumbBackdrop, 0xF3EFE7),
            ("ink", Theme.ink, 0x1C1B22),
            ("inkMuted", Theme.inkMuted, 0x5E5B66),
            ("line", Theme.line, 0xE7E2D8),
            ("lineStrong", Theme.lineStrong, 0xCFC8BA),
            ("tangerine", Theme.tangerine, 0xFF5A1F),
            ("pencilBlue", Theme.pencilBlue, 0x2F5BFF),
            ("blueTint", Theme.blueTint, 0xEEF2FF),
            ("blueText", Theme.blueText, 0x3A4CB8),
            ("butter", Theme.butter, 0xFFC93C),
            ("sketchStroke", Theme.sketchStroke, 0xC9C3D3),
        ]

        for token in expected {
            XCTAssertEqual(rgbHex(of: token.color), token.hex, "Theme.\(token.name)")
        }
    }

    /// Resolves a SwiftUI color to a 0xRRGGBB value in sRGB.
    private func rgbHex(of color: Color) -> UInt32? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((value * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}

/// The UI fonts from DESIGN.md are bundled, registered and static.
final class ThemeFontTests: XCTestCase {
    func testUIFontsAreRegisteredStaticInstances() {
        for name in [Theme.FontName.display, Theme.FontName.regular, Theme.FontName.semibold, Theme.FontName.bold] {
            guard let font = UIFont(name: name, size: 17) else { return XCTFail("\(name) is not registered") }
            XCTAssertEqual(font.fontName, name)
            let axes = CTFontCopyVariationAxes(font as CTFont) as? [Any]
            XCTAssertTrue(axes?.isEmpty ?? true, "\(name) must be a static instance, not a variable font")
        }
    }
}
