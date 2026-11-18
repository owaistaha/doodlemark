import CoreGraphics

/// Pass thresholds for the SVG export gate (TECH_SPEC "Hard gate").
///
/// These were fixed BEFORE the first gate run and must never be loosened to
/// make a failing case pass. Fix the exporter instead. If a threshold itself
/// looks wrong, stop and discuss it; don't edit it quietly.
///
/// Both renders are 1024×1024 px at 1x on white: the native render
/// (PencilKit + Core Graphics + Core Text) and the SVG render (WebKit).
enum GateConfig {
    /// Side of both renders, in pixels. Canvas space is 1024 points, so 1 px = 1 pt.
    static let renderSide = 1024

    // MARK: Per-pixel definitions

    /// A pixel "differs" when any RGB channel differs by more than this (0–255).
    /// 64 ≈ 25%. Two correct renderers disagree on anti-aliased edge pixels by
    /// a little; a coverage difference this big means the edge moved by roughly
    /// 0.3 px or more, or the color is wrong.
    static let pixelTolerance: UInt8 = 64

    /// A pixel is "painted" when any RGB channel is further than this from
    /// white (0–255). The same 25% bar puts the mask edge at about the middle of
    /// the anti-aliasing ramp for every palette color. Even butter (#FFC93C)
    /// clears it at about a third coverage.
    static let paintedThreshold: UInt8 = 64

    // MARK: Pass criteria (all three must hold)

    /// TECH_SPEC: fewer than 2% of all pixels may differ.
    /// Loose on its own for line art (ink covers a few % of the canvas), which
    /// is why the two checks below exist.
    static let maxDifferingFraction = 0.02

    /// Geometry agreement: |painted ∩| / |painted ∪| over the whole canvas.
    /// A correct export loses a few % to anti-aliasing at stroke edges (8 pt
    /// strokes are ~25% edge pixels). 0.90 still fails a stroke that is 1 pt too
    /// wide or narrow on a stroke-only fixture (8/9 ≈ 0.89).
    static let minPaintedIoU = 0.90

    /// Local check: the canvas is cut into `tileSide × tileSide` tiles. In every
    /// tile with at least `minTileUnion` painted pixels (either render),
    /// mismatching painted pixels / painted union must stay at or below `maxTileMismatch`.
    ///
    /// Why: a single short stroke that is shifted, missing or recolored is a
    /// tiny share of the whole image, so the two global checks can't see it.
    /// Inside a 32 px tile, an 8 pt stroke shifted by 2 pt already gives ~40%
    /// mismatch, while edge noise from a correct export should stay near 10%.
    static let tileSide = 32
    /// Below this many painted pixels a tile is mostly edge, so its ratio is noise.
    static let minTileUnion = 64
    static let maxTileMismatch = 0.25

    // MARK: Negative controls

    /// How far the "shifted stroke" control moves one stroke: half an 8 pt line.
    /// Clearly visible to a person, so the gate must catch it.
    static let negativeControlShift: CGFloat = 4
}
