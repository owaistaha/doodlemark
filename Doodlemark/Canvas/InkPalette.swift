import PencilKit
import UIKit

/// Ink lines and the palette (TECH_SPEC "Palette → How Ink lines follow a slot").
///
/// A PencilKit stroke can't carry a palette slot (no custom data, no stable
/// ID), only a color. So a stroke belongs to the slot whose color it has,
/// **exactly**: the pen only ever draws palette colors, and PencilKit gives
/// the color back unchanged (finger strokes: UI test; save and reload:
/// `DrawingPersistenceTests`). When a slot's color changes, its strokes get
/// the new color; strokes of other slots, and strokes in a color that isn't
/// in the palette, are left alone. Only `stroke.ink.color` changes.
///
/// That only works while the three slots have three different colors, so a
/// slot is never given another slot's color: it's nudged by 3/255 instead
/// (`keepingApart`).
enum InkPalette {
    /// The nudge, out of 255, in one channel.
    static let nudge = 3

    /// The slot each stroke belongs to, in stroke order (`nil` = not a palette
    /// color). Slots never share a color (`keepingApart`); for a palette from
    /// elsewhere that does, `preferring` wins (the slot being edited), then the first.
    static func slots(of drawing: PKDrawing, palette: [HexColor],
                      preferring preferred: PaletteSlot? = nil) -> [PaletteSlot?] {
        drawing.strokes.map { stroke in
            let color = SVGExporter.inkColor(stroke.ink.color).color
            if let preferred, color == preferred.color(in: palette) { return preferred }
            return PaletteSlot.allCases.first { color == $0.color(in: palette) }
        }
    }

    /// `drawing` with every stroke that has a slot in `slots` set to that
    /// slot's color in `palette`.
    static func recolored(_ drawing: PKDrawing, slots: [PaletteSlot?], palette: [HexColor]) -> PKDrawing {
        var result = drawing
        for (index, slot) in zip(result.strokes.indices, slots) {
            guard let slot else { continue }
            let target = slot.color(in: palette)
            let stroke = result.strokes[index]
            guard SVGExporter.inkColor(stroke.ink.color).color != target else { continue }
            result.strokes[index].ink = PKInk(stroke.ink.inkType, color: UIColor(cgColor: target.cgColor))
        }
        return result
    }

    /// `color`, or if another slot already has it, the same color nudged by
    /// 3/255 in one channel: green first (+3, or −3 near the top), then red,
    /// then blue. Invisible, and it keeps the slots' lines apart.
    ///
    /// Always succeeds within one 3/255 step: of the six nudges at least three
    /// stay in 0…255 (one per channel), and the two other slots can block at
    /// most two of them.
    static func keepingApart(_ color: HexColor, from others: [HexColor]) -> HexColor {
        guard others.contains(color) else { return color }
        for candidate in nudges(of: color) where !others.contains(candidate) {
            return candidate
        }
        return color   // unreachable (see above)
    }

    private static func nudges(of c: HexColor) -> [HexColor] {
        func step(_ v: UInt8) -> [UInt8] {
            let up = Int(v) + nudge, down = Int(v) - nudge
            return [up <= 255 ? UInt8(up) : nil, down >= 0 ? UInt8(down) : nil].compactMap { $0 }
        }
        return step(c.green).map { HexColor(red: c.red, green: $0, blue: c.blue) }
            + step(c.red).map { HexColor(red: $0, green: c.green, blue: c.blue) }
            + step(c.blue).map { HexColor(red: c.red, green: c.green, blue: $0) }
    }
}
