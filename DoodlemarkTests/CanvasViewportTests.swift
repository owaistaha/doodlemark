import XCTest
@testable import Doodlemark

final class CanvasViewportTests: XCTestCase {
    private let side: CGFloat = 600
    private let pixel: CGFloat = 0.5

    func testFittedShowsTheWholeCanvas() {
        let v = CanvasViewport.fitted(viewSide: side)
        XCTAssertEqual(v.toView(.zero), .zero)
        XCTAssertEqual(v.toView(CGPoint(x: 1024, y: 1024)), CGPoint(x: side, y: side))
        XCTAssertEqual(v.zoomFactor(viewSide: side), 1)
    }

    func testCanvasAndViewMappingsAreInverse() {
        let v = CanvasViewport(zoom: 1.37, offset: CGPoint(x: 210.5, y: 98))
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 512, y: 300), CGPoint(x: 1024, y: 1024)] {
            let back = v.toCanvas(v.toView(p))
            XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
            XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
        }
    }

    func testPinchKeepsThePointUnderTheFingers() {
        let start = CanvasViewport.fitted(viewSide: side)
        let fingers = CGPoint(x: 400, y: 250)
        let underFingers = start.toCanvas(fingers)
        let zoomed = start.navigated(scale: 2, anchor: fingers, centroid: fingers)
        XCTAssertEqual(zoomed.zoomFactor(viewSide: side), 2, accuracy: 1e-9)
        XCTAssertEqual(zoomed.toView(underFingers).x, fingers.x, accuracy: 1e-9)
        XCTAssertEqual(zoomed.toView(underFingers).y, fingers.y, accuracy: 1e-9)
    }

    func testTwoFingerPanMovesTheCanvasWithTheFingers() {
        let start = CanvasViewport(zoom: 1.2, offset: CGPoint(x: 300, y: 300))
        let moved = start.navigated(scale: 1, anchor: CGPoint(x: 100, y: 100), centroid: CGPoint(x: 160, y: 80))
        XCTAssertEqual(moved.offset.x, 240, accuracy: 1e-9)
        XCTAssertEqual(moved.offset.y, 320, accuracy: 1e-9)
        XCTAssertEqual(moved.zoom, 1.2)
    }

    func testClampKeepsZoomInRangeAndCanvasCoveringTheView() {
        let fit = side / 1024
        let tooFar = CanvasViewport(zoom: fit / 3, offset: CGPoint(x: -50, y: -50)).clamped(viewSide: side, pixel: pixel)
        XCTAssertEqual(tooFar, CanvasViewport.fitted(viewSide: side))

        let tooClose = CanvasViewport(zoom: fit * 10, offset: CGPoint(x: 99_999, y: 99_999)).clamped(viewSide: side, pixel: pixel)
        XCTAssertEqual(tooClose.zoomFactor(viewSide: side), CanvasViewport.maxZoomFactor, accuracy: 1e-9)
        XCTAssertEqual(tooClose.toView(CGPoint(x: 1024, y: 1024)).x, side, accuracy: pixel)
    }

    func testClampSnapsOffsetToDevicePixels() {
        let v = CanvasViewport(zoom: 1.2, offset: CGPoint(x: 100.37, y: 20.8)).clamped(viewSide: side, pixel: pixel)
        XCTAssertEqual(v.offset, CGPoint(x: 100.5, y: 21))
    }
}
