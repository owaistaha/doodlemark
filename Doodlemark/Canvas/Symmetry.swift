import PencilKit

/// Mirror for the Ink layer: a vertical axis at x = 512.
///
/// The mirrored copy is the same stroke with a horizontal flip added to its
/// `transform` (proven in the step 4a spike). Points, widths and timing are
/// untouched, and the exporter already applies transforms, so the copy
/// exports exactly as drawn. The pair is one undo step because the whole
/// canvas is snapshotted per change (`CanvasHistory`).
enum Symmetry {
    static let axisX: CGFloat = 512

    /// x ↦ 2·axis − x.
    static let flip = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * axisX, ty: 0)

    static func mirrored(_ stroke: PKStroke) -> PKStroke {
        var copy = stroke
        copy.transform = stroke.transform.concatenating(flip)
        return copy
    }
}
