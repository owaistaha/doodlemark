import Darwin
import PencilKit
import XCTest
@testable import Doodlemark

/// How much memory a full undo history (100 snapshots) of a busy drawing
/// costs. Reported, not asserted tightly: it documents the 100-step cap.
@MainActor
final class HistoryMemoryTests: XCTestCase {
    private func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// A busy logo: 400 ink strokes of 150 points each, plus 100 sketch strokes.
    private func busyStroke(_ i: Int, points: Int = 150) -> PKStroke {
        let y = CGFloat(i % 100) * 10 + 5
        let polyline = (0..<points).map { k in
            CGPoint(x: 20 + CGFloat(k) * 6, y: y + 3 * sin(CGFloat(k + i) * 0.4))
        }
        return Fixtures.monolineStroke(polyline, width: 10)
    }

    func testMemoryOfAFullHistoryOfABusyDrawing() throws {
        let model = CanvasModel(project: .blank())
        let saved = UserDefaults.standard.object(forKey: CanvasModel.smoothLinesKey)
        defer { UserDefaults.standard.set(saved, forKey: CanvasModel.smoothLinesKey) }   // runs inside the app
        model.smoothLines = false
        var ink = PKDrawing(strokes: (0..<400).map { busyStroke($0) })
        let sketch = PKDrawing(strokes: (0..<100).map { busyStroke($0 + 1000) })
        model.sketch = sketch
        model.ink = ink
        let drawingBytes = ink.dataRepresentation().count + sketch.dataRepresentation().count

        let before = footprint()
        for step in 0..<CanvasHistory.limit {
            ink.strokes.append(busyStroke(5000 + step))
            _ = model.inkDidChange(ink)
        }
        let after = footprint()
        XCTAssertEqual(model.history.undoStack.count, CanvasHistory.limit)

        let delta = Double(after - before) / 1_048_576
        let naive = Double(drawingBytes * CanvasHistory.limit) / 1_048_576
        print(String(format: "HISTORYMEM| busy drawing %.2f MB serialized (500 strokes, 75,000 points); "
                     + "100 snapshots: footprint +%.1f MB; if every snapshot were a full copy: %.0f MB",
                     Double(drawingBytes) / 1_048_576, delta, naive))
        XCTAssertLessThan(delta, 200, "100 snapshots of a busy drawing should stay well under 200 MB")
    }
}
