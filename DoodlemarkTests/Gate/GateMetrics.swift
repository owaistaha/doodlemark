import Foundation

/// The numbers the gate judges, for one native-vs-SVG pair.
struct GateMetrics: CustomStringConvertible {
    var differingFraction: Double     // of all pixels
    var paintedIoU: Double            // geometry agreement
    var worstTileMismatch: Double     // worst local mismatch
    var worstTile: (x: Int, y: Int)   // top-left pixel of that tile
    var paintedNative: Int
    var paintedSVG: Int

    var passesDifferingFraction: Bool { differingFraction < GateConfig.maxDifferingFraction }
    var passesIoU: Bool { paintedIoU >= GateConfig.minPaintedIoU }
    var passesTiles: Bool { worstTileMismatch <= GateConfig.maxTileMismatch }
    var passes: Bool { passesDifferingFraction && passesIoU && passesTiles }

    var description: String {
        func pct(_ v: Double) -> String { String(format: "%.3f%%", v * 100) }
        func mark(_ ok: Bool) -> String { ok ? "ok" : "FAIL" }
        return "differing \(pct(differingFraction)) [\(mark(passesDifferingFraction))]"
            + " | IoU \(String(format: "%.4f", paintedIoU)) [\(mark(passesIoU))]"
            + " | worst tile \(pct(worstTileMismatch)) at (\(worstTile.x),\(worstTile.y)) [\(mark(passesTiles))]"
            + " | painted native \(paintedNative) / svg \(paintedSVG)"
            + " → \(passes ? "PASS" : "FAIL")"
    }
}

enum GateComparison {
    /// Compares two renders and builds the diff image:
    /// light grey = painted in both and matching, red = only in native (missing
    /// from SVG), blue = only in SVG (extra), magenta = painted in both but a
    /// different color, white = background in both.
    static func compare(native: Bitmap, svg: Bitmap) -> (GateMetrics, diff: Bitmap) {
        precondition(native.side == svg.side)
        let side = native.side
        let tolerance = Int(GateConfig.pixelTolerance)
        let paintedBar = Int(GateConfig.paintedThreshold)

        func painted(_ c: (UInt8, UInt8, UInt8)) -> Bool {
            255 - Int(min(c.0, c.1, c.2)) > paintedBar
        }
        func differs(_ a: (UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8)) -> Bool {
            abs(Int(a.0) - Int(b.0)) > tolerance
                || abs(Int(a.1) - Int(b.1)) > tolerance
                || abs(Int(a.2) - Int(b.2)) > tolerance
        }

        let tiles = side / GateConfig.tileSide
        var tileUnion = [Int](repeating: 0, count: tiles * tiles)
        var tileMismatch = [Int](repeating: 0, count: tiles * tiles)

        var differing = 0, intersection = 0, union = 0, paintedNative = 0, paintedSVG = 0
        var diff = [UInt8](repeating: 255, count: side * side * 4)

        for y in 0..<side {
            for x in 0..<side {
                let a = native.rgb(x, y), b = svg.rgb(x, y)
                let pa = painted(a), pb = painted(b)
                let isDifferent = differs(a, b)
                if isDifferent { differing += 1 }
                if pa { paintedNative += 1 }
                if pb { paintedSVG += 1 }

                let i = (y * side + x) * 4
                guard pa || pb else { continue }
                union += 1
                if pa && pb { intersection += 1 }

                let tile = (y / GateConfig.tileSide) * tiles + (x / GateConfig.tileSide)
                tileUnion[tile] += 1

                // A mismatch is a painted pixel whose colors really differ. A pixel that
                // only straddles the painted bar with near-identical colors is a match.
                let color: (UInt8, UInt8, UInt8)
                if !isDifferent {
                    color = (210, 210, 210)
                } else {
                    tileMismatch[tile] += 1
                    if pa && !pb { color = (230, 30, 30) }        // missing from SVG
                    else if pb && !pa { color = (30, 90, 230) }   // extra in SVG
                    else { color = (200, 0, 200) }                // both painted, wrong color
                }
                diff[i] = color.0; diff[i + 1] = color.1; diff[i + 2] = color.2
            }
        }

        var worst = 0.0, worstTile = (x: 0, y: 0)
        for t in 0..<(tiles * tiles) where tileUnion[t] >= GateConfig.minTileUnion {
            let ratio = Double(tileMismatch[t]) / Double(tileUnion[t])
            if ratio > worst {
                worst = ratio
                worstTile = ((t % tiles) * GateConfig.tileSide, (t / tiles) * GateConfig.tileSide)
            }
        }

        let metrics = GateMetrics(
            differingFraction: Double(differing) / Double(side * side),
            paintedIoU: union == 0 ? 1 : Double(intersection) / Double(union),
            worstTileMismatch: worst,
            worstTile: worstTile,
            paintedNative: paintedNative,
            paintedSVG: paintedSVG)
        return (metrics, Bitmap(side: side, bytes: diff))
    }
}
