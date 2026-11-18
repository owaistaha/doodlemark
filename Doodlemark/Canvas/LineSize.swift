import CoreGraphics

/// The Ink pen's "Line size": the thickness the user actually sees, in 1024
/// canvas space. This is the only number the UI shows. PencilKit's own widths
/// never leave this file.
///
/// Three different widths are involved (all measured on iPadOS 26.5):
/// - **size**: the drawn thickness, what the slider shows (4–40).
/// - **tool width**: what `PKInkingTool(.monoline, width:)` gets.
/// - **stored width**: what PencilKit writes into every `PKStrokePoint.size.width`
///   for a touch stroke: tool width + 2 (`FingerStrokeUITests`).
///
/// PencilKit then draws a stored width `w` as `2·w − 4` thick
/// (`SVGExporter.renderedMonolineWidth`, `MonolineWidthTests`), so
/// size = 2·(tool + 2) − 4 = 2·tool.
enum LineSize {
    /// Slider range and step. Step 2 keeps tool widths whole numbers.
    static let range: ClosedRange<CGFloat> = 4...40
    static let step: CGFloat = 2
    /// 16 = tool width 8, clean on a finger without looking heavy.
    static let defaultSize: CGFloat = 16

    /// What PencilKit adds to the tool width when it stores a touch stroke.
    static let storedWidthOffset: CGFloat = 2

    /// THE conversion: the PencilKit tool width that draws a line `size` thick.
    /// Out-of-range sizes are clamped to `range`.
    static func toolWidth(forSize size: CGFloat) -> CGFloat {
        let clamped = min(max(size, range.lowerBound), range.upperBound)
        // Invert the render law for the stored width, then remove PencilKit's offset.
        let stored = (clamped - SVGExporter.monolineWidthOffset) / SVGExporter.monolineWidthSlope
        return stored - storedWidthOffset
    }

    /// The `size.width` PencilKit stores for a line `size` thick: (size + 4) / 2.
    static func storedWidth(forSize size: CGFloat) -> CGFloat {
        toolWidth(forSize: size) + storedWidthOffset
    }

    /// The thickness a stored stroke is drawn with, for showing an existing stroke's size.
    static func size(forStoredWidth width: CGFloat) -> CGFloat {
        SVGExporter.renderedMonolineWidth(pointWidth: width)
    }
}
