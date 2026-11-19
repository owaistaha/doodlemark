import XCTest

/// One-finger strokes along any path, for UI tests that have to trace a
/// curve (XCUICoordinate's press-and-drag only does straight lines).
///
/// Uses XCTest's own event records (`XCPointerEventPath`,
/// `XCSynthesizedEventRecord`), the same machinery behind `tap()` and
/// `press(forDuration:thenDragTo:)`, looked up at run time. They're not
/// public API, so this lives in the UI test target only, never in the app,
/// and throws `XCTSkip` rather than crashing if a future Xcode renames them.
enum TouchSynthesis {
    /// A finger down at `points[0]`, through every point over `duration`
    /// seconds, then up. Points are in screen coordinates (the same space as
    /// `XCUIElement.frame`); `app` gives the window size for turning them
    /// into the portrait space the event record works in.
    static func stroke(_ screenPoints: [CGPoint], in app: XCUIApplication, duration: TimeInterval = 1.0) throws {
        let points = portrait(screenPoints, window: app.windows.firstMatch.frame.size)
        guard points.count >= 2,
              let pathClass = NSClassFromString("XCPointerEventPath"),
              let recordClass = NSClassFromString("XCSynthesizedEventRecord") else {
            throw XCTSkip("XCTest's touch synthesis isn't available in this Xcode")
        }
        typealias InitTouch = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Unmanaged<AnyObject>
        typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
        typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
        typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> Unmanaged<AnyObject>
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias Synthesize = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Bool

        func function<F>(_ cls: AnyClass, _ name: String, as: F.Type) throws -> (F, Selector) {
            let selector = NSSelectorFromString(name)
            guard class_respondsToSelector(cls, selector), let imp = class_getMethodImplementation(cls, selector) else {
                throw XCTSkip("XCTest touch synthesis: no \(name)")
            }
            return (unsafeBitCast(imp, to: F.self), selector)
        }
        func allocate(_ cls: AnyClass) -> AnyObject {
            (cls as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        }

        let (initTouch, initTouchSel) = try function(pathClass, "initForTouchAtPoint:offset:", as: InitTouch.self)
        let (move, moveSel) = try function(pathClass, "moveToPoint:atOffset:", as: Move.self)
        let (lift, liftSel) = try function(pathClass, "liftUpAtOffset:", as: Lift.self)
        let (initRecord, initRecordSel) = try function(recordClass, "initWithName:interfaceOrientation:", as: InitRecord.self)
        let (add, addSel) = try function(recordClass, "addPointerEventPath:", as: Add.self)
        let (synthesize, synthesizeSel) = try function(recordClass, "synthesizeWithError:", as: Synthesize.self)

        // A short hold first so the canvas sees a touch, not a flick.
        let hold = 0.05
        let path = initTouch(allocate(pathClass), initTouchSel, points[0], 0).takeRetainedValue()
        for (index, point) in points.enumerated().dropFirst() {
            move(path, moveSel, point, hold + duration * Double(index) / Double(points.count - 1))
        }
        lift(path, liftSel, hold + duration + 0.02)

        let record = initRecord(allocate(recordClass), initRecordSel, "stroke" as NSString,
                                UIInterfaceOrientation.portrait.rawValue).takeRetainedValue()
        add(record, addSel, path)
        guard synthesize(record, synthesizeSel, nil) else {
            throw XCTSkip("XCTest touch synthesis refused the stroke")
        }
    }

    /// The event record reads points in the portrait screen space whatever
    /// the orientation (measured: a square drawn in landscape came out
    /// transposed). `window` is the app window in the current orientation.
    static func portrait(_ points: [CGPoint], window: CGSize) -> [CGPoint] {
        switch XCUIDevice.shared.orientation {
        case .landscapeLeft:                                   // home side on the right
            return points.map { CGPoint(x: window.height - $0.y, y: $0.x) }
        case .landscapeRight:
            return points.map { CGPoint(x: $0.y, y: window.width - $0.x) }
        case .portraitUpsideDown:
            return points.map { CGPoint(x: window.width - $0.x, y: window.height - $0.y) }
        default:
            return points
        }
    }

    /// `points` in the 1024 canvas space → screen points on a canvas whose
    /// on-screen square is `frame` (the canvas at its fitted zoom), with a
    /// point every `spacing` screen points so the finger follows curves.
    static func screenPoints(_ points: [CGPoint], canvasFrame frame: CGRect, spacing: CGFloat = 3) -> [CGPoint] {
        let scale = frame.width / 1024
        let screen = points.map { CGPoint(x: frame.minX + $0.x * scale, y: frame.minY + $0.y * scale) }
        var dense = [screen[0]]
        for (a, b) in zip(screen, screen.dropFirst()) {
            let steps = max(1, Int((hypot(b.x - a.x, b.y - a.y) / spacing).rounded(.up)))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                dense.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return dense
    }

    /// "x,y;x,y;…" (the app's DEBUG `debugLessonTarget`) → points.
    static func parse(_ label: String) -> [CGPoint] {
        label.split(separator: ";").compactMap { pair in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
        }
    }
}
