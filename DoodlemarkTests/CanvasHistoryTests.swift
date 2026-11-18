import PencilKit
import XCTest
@testable import Doodlemark

final class CanvasHistoryTests: XCTestCase {
    private func state(_ n: Int) -> CanvasSnapshot {
        let strokes = (0..<n).map { i in
            Fixtures.monolineStroke([CGPoint(x: 10, y: CGFloat(i) * 10 + 10), CGPoint(x: 100, y: CGFloat(i) * 10 + 10)], width: 8)
        }
        return CanvasSnapshot(sketch: PKDrawing(), ink: PKDrawing(strokes: strokes), shapes: [], text: nil,
                              palette: Palettes.starter)
    }

    /// `PKDrawing` equality is identity (each drawing has its own UUID), so
    /// compare what matters: how many strokes each snapshot holds.
    private func inkCount(_ snapshot: CanvasSnapshot?) -> Int? { snapshot?.ink.strokes.count }

    func testUndoRedoWalkBothWays() {
        var history = CanvasHistory()
        history.record(state(0))
        history.record(state(1))
        XCTAssertEqual(inkCount(history.undo(current: state(2))), 1)
        XCTAssertEqual(inkCount(history.undo(current: state(1))), 0)
        XCTAssertNil(history.undo(current: state(0)))
        XCTAssertEqual(inkCount(history.redo(current: state(0))), 1)
        XCTAssertEqual(inkCount(history.redo(current: state(1))), 2)
        XCTAssertNil(history.redo(current: state(2)))
    }

    func testANewChangeClearsRedo() {
        var history = CanvasHistory()
        history.record(state(0))
        _ = history.undo(current: state(1))
        XCTAssertTrue(history.canRedo)
        history.record(state(0))
        XCTAssertFalse(history.canRedo)
    }

    func testHistoryIsCappedAtTheLimit() {
        var history = CanvasHistory()
        for i in 0..<(CanvasHistory.limit + 25) { history.record(state(i % 3)) }
        XCTAssertEqual(history.undoStack.count, CanvasHistory.limit)
    }
}
