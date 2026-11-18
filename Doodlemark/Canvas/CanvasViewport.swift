import CoreGraphics

/// Where the 1024×1024 canvas sits in the on-screen stack. One value drives
/// every layer (both PencilKit canvases and the SwiftUI Shapes/Text layers), so
/// they can't drift apart (RISKS.md #4). Same mapping as a UIScrollView:
/// view point = canvas point × zoom − offset.
struct CanvasViewport: Equatable {
    static let canvasSide: CGFloat = 1024
    /// How far in the user can zoom, relative to "whole canvas fits".
    static let maxZoomFactor: CGFloat = 4

    var zoom: CGFloat
    var offset: CGPoint

    /// The whole canvas exactly filling a square view `side` points wide.
    static func fitted(viewSide side: CGFloat) -> CanvasViewport {
        CanvasViewport(zoom: side / canvasSide, offset: .zero)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * zoom - offset.x, y: p.y * zoom - offset.y)
    }

    func toCanvas(_ v: CGPoint) -> CGPoint {
        CGPoint(x: (v.x + offset.x) / zoom, y: (v.y + offset.y) / zoom)
    }

    /// Zoom relative to the fitted size, e.g. 1.5 = "150%".
    func zoomFactor(viewSide side: CGFloat) -> CGFloat {
        zoom / (side / Self.canvasSide)
    }

    /// The viewport after a two-finger gesture: zoom by `scale` relative to
    /// `self`, keeping the canvas point that was under `anchor` (view points,
    /// at gesture start) under `centroid` (view points, now).
    func navigated(scale: CGFloat, anchor: CGPoint, centroid: CGPoint) -> CanvasViewport {
        let pinned = toCanvas(anchor)
        let newZoom = zoom * scale
        return CanvasViewport(zoom: newZoom, offset: CGPoint(x: pinned.x * newZoom - centroid.x,
                                                             y: pinned.y * newZoom - centroid.y))
    }

    /// Zoom kept between "fits" and `maxZoomFactor`, the canvas always
    /// covering the square view, and the offset snapped to device pixels
    /// (UIScrollView snaps `contentOffset`; snapping first keeps the layers equal).
    func clamped(viewSide side: CGFloat, pixel: CGFloat) -> CanvasViewport {
        let fit = side / Self.canvasSide
        let z = min(max(zoom, fit), fit * Self.maxZoomFactor)
        let maxOffset = max(0, Self.canvasSide * z - side)
        func clamp(_ v: CGFloat) -> CGFloat {
            let snapped = (min(max(v, 0), maxOffset) / pixel).rounded() * pixel
            return min(snapped, maxOffset)
        }
        return CanvasViewport(zoom: z, offset: CGPoint(x: clamp(offset.x), y: clamp(offset.y)))
    }
}
