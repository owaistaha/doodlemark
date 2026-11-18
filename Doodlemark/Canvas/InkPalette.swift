import PencilKit
import UIKit

/// Ink lines and the palette.
///
/// A PencilKit stroke stores a color, not a palette slot, so a stroke belongs
/// to the slot whose color it has (the pen only ever draws palette colors).
/// When a slot's color changes, its strokes get the new color; strokes of
/// other slots, and strokes in a color that isn't in the palette, are left
/// alone. Only `stroke.ink.color` changes: ink type, points, widths and
/// transform stay the same.
enum InkPalette {
    /// Colors this close (per sRGB channel) count as the same, so a color that
    /// went through PencilKit's storage and a conversion still matches.
    static let matchTolerance = 1

    /// The slot each stroke belongs to, in stroke order (`nil` = not a palette
    /// color). Slots never share a color (`keepingApart`); for a palette from
    /// elsewhere that does, `preferring` wins (the slot being edited), then the first.
    static func slots(of drawing: PKDrawing, palette: [HexColor],
                      preferring preferred: PaletteSlot? = nil) -> [PaletteSlot?] {
        drawing.strokes.map { stroke in
            let color = SVGExporter.inkColor(stroke.ink.color).color
            if let preferred, matches(color, preferred.color(in: palette)) { return preferred }
            return PaletteSlot.allCases.first { matches(color, $0.color(in: palette)) }
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

    /// Ink lines only know their color, so two slots with the same color
    /// couldn't be told apart again. A color picked for a slot that matches
    /// another slot is nudged by 3 in green: invisible, but the lines stay apart.
    static func keepingApart(_ color: HexColor, from others: [HexColor]) -> HexColor {
        var result = color
        let step = color.green <= 127 ? 3 : -3
        for _ in 0..<4 where others.contains(where: { matches(result, $0) }) {
            result.green = UInt8(Int(result.green) + step)
        }
        return result
    }

    static func matches(_ a: HexColor, _ b: HexColor) -> Bool {
        abs(Int(a.red) - Int(b.red)) <= matchTolerance
            && abs(Int(a.green) - Int(b.green)) <= matchTolerance
            && abs(Int(a.blue) - Int(b.blue)) <= matchTolerance
    }
}
