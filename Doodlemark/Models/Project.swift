import CoreGraphics
import Foundation

// Data model from TECH_SPEC "Data model". All geometry is in canvas space:
// a 1024×1024 square, origin top-left, y pointing down (same as SVG).

/// A saved logo project. Stored as `project.json`. The Sketch and Ink drawings
/// live next to it as separate `PKDrawing` files.
struct Project: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String            // defaults to the prompt or "Untitled logo"
    var createdAt: Date
    var updatedAt: Date
    var palette: [HexColor]     // exactly 3
    var shapes: [LogoShape]
    var text: LogoText?
    var symmetryOn: Bool
    var gridOn: Bool

    /// The color a palette slot shows right now.
    func color(for slot: PaletteSlot) -> HexColor { slot.color(in: palette) }
}

/// Which of the project's three palette colors a shape or the text uses.
/// Stored as 0/1/2, never as a hex, so changing a palette color recolors
/// everything that uses that slot.
enum PaletteSlot: Int, Codable, CaseIterable, Identifiable, Sendable {
    case first = 0, second = 1, third = 2
    var id: Self { self }

    /// 1-based, for labels ("Color 2").
    var number: Int { rawValue + 1 }

    /// The slot's color in `palette`. A palette is always 3 colors; a broken
    /// one falls back to the starter palette rather than crashing.
    func color(in palette: [HexColor]) -> HexColor {
        palette.indices.contains(rawValue) ? palette[rawValue] : Palettes.starter[rawValue]
    }
}

/// A filled vector shape on the Shapes layer. Its outline comes only from
/// `ShapeGeometry`, which both the screen and the SVG exporter use.
struct LogoShape: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case circle, roundedSquare, triangle, star
    }

    var id: UUID
    var kind: Kind
    var center: CGPoint         // canvas space (0...1024)
    var size: CGFloat           // side of the square the shape fits in when unrotated
    var rotation: Double        // radians, clockwise on screen
    var fill: PaletteSlot
}

/// The logo name. Exported as glyph outlines, never as `<text>`.
struct LogoText: Codable, Equatable, Sendable {
    var string: String
    var fontName: String        // PostScript name of a bundled OFL font, e.g. "LilitaOne"
    var center: CGPoint         // center of the line's typographic box, canvas space
    var pointSize: CGFloat
    var rotation: Double        // radians, clockwise on screen
    var fill: PaletteSlot
}

/// An opaque sRGB color, stored and encoded as `"#RRGGBB"`.
struct HexColor: Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `"#RRGGBB"` (the `#` is optional, case-insensitive).
    init?(_ string: String) {
        let digits = string.hasPrefix("#") ? String(string.dropFirst()) : string
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: UInt8((value >> 16) & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8(value & 0xFF)
        )
    }

    /// `"#RRGGBB"`, uppercase.
    var hexString: String {
        let value = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        let digits = String(value, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    /// Converts any CGColor to sRGB. Returns the color plus its alpha (0...1).
    /// Wide-gamut (Display P3) components are clamped into sRGB.
    static func sRGB(from color: CGColor) -> (color: HexColor, alpha: CGFloat)? {
        guard
            let srgb = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
            let c = converted.components, c.count >= 3
        else { return nil }
        func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        let alpha = c.count >= 4 ? c[3] : 1
        return (HexColor(red: byte(c[0]), green: byte(c[1]), blue: byte(c[2])), alpha)
    }

    /// Opaque CGColor in sRGB, for on-screen and native rendering.
    var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

extension HexColor: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = HexColor(string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected \"#RRGGBB\", got \"\(string)\"")
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

/// The one JSON format for project files. ProjectStore (step 6) uses these too,
/// so the round-trip test covers the real on-disk format.
enum ProjectCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Default date strategy (seconds since reference date as a Double) round-trips exactly.
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
