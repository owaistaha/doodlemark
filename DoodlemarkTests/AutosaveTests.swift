import PencilKit
import XCTest
@testable import Doodlemark

/// A clock the test moves by hand, standing in for the 1 s debounce timer.
@MainActor
final class ManualClock {
    private(set) var now = 0.0
    private var pending: [(id: Int, at: Double, action: @MainActor () -> Void)] = []
    private var nextID = 0

    var pendingCount: Int { pending.count }

    var scheduler: SaveScheduler {
        { [unowned self] delay, action in
            let id = nextID
            nextID += 1
            let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
            pending.append((id, now + seconds, action))
            return { [weak self] in self?.pending.removeAll { $0.id == id } }
        }
    }

    func advance(by seconds: Double) {
        now += seconds
        let due = pending.filter { $0.at <= now + 1e-9 }
        pending.removeAll { $0.at <= now + 1e-9 }
        for item in due { item.action() }
    }
}

@MainActor
final class AutosaveTests: XCTestCase {
    private var root: URL!
    private var store: ProjectStore!
    private var clock: ManualClock!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "AutosaveTests-\(UUID().uuidString)")
        store = ProjectStore(root: root)
        clock = ManualClock()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func newSession(project: Project = .blank()) -> (CanvasModel, ProjectAutosaver) {
        let model = CanvasModel(project: project)
        let saver = ProjectAutosaver(model: model, store: store, isOnDisk: false, schedule: clock.scheduler)
        return (model, saver)
    }

    /// Observation reports a change before it lands; the autosaver looks on
    /// the next main-actor turn.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private var onDisk: Bool { !store.entries().isEmpty }

    // MARK: Debounce

    func testSavesOneSecondAfterTheLastChange() async throws {
        let (model, saver) = newSession()
        model.select(.shapes)
        model.addShape(.circle)
        await settle()
        XCTAssertEqual(saver.state, .editing)

        clock.advance(by: 0.9)
        XCTAssertEqual(saver.saveCount, 0, "not yet")
        model.addShape(.star)                           // another change restarts the wait
        await settle()
        clock.advance(by: 0.9)
        XCTAssertEqual(saver.saveCount, 0, "still within 1 s of the last change")
        XCTAssertFalse(onDisk)
        clock.advance(by: 0.1)
        XCTAssertEqual(saver.saveCount, 1, "one write for the burst")
        XCTAssertEqual(saver.state, .saved)
        XCTAssertEqual(try store.load(model.project.id).project.shapes.count, 2)
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testEveryKindOfChangeIsSaved() async throws {
        let (model, saver) = newSession()
        let changes: [(String, () -> Void)] = [
            ("ink", { _ = model.inkDidChange(PKDrawing(strokes: [Fixtures.monolineStroke([CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)])])) }),
            ("sketch", { model.sketchDidChange(PKDrawing(strokes: [Fixtures.monolineStroke([CGPoint(x: 5, y: 5), CGPoint(x: 50, y: 9)])])) }),
            ("text", { model.select(.text); model.typeText("Hi"); model.endTyping() }),
            ("palette", { model.tryAnotherPalette() }),
            ("mirror", { model.mirrorOn = true }),
            ("grid", { model.gridOn = true }),
            ("name", { model.rename(to: "Moon Café") }),
        ]
        for (label, change) in changes {
            change()
            await settle()
            XCTAssertEqual(saver.state, .editing, label)
            clock.advance(by: 1)
            XCTAssertEqual(saver.state, .saved, label)
        }
        let loaded = try store.load(model.project.id)
        XCTAssertEqual(loaded.project.name, "Moon Café")
        XCTAssertTrue(loaded.project.symmetryOn)
        XCTAssertTrue(loaded.project.gridOn)
        XCTAssertEqual(loaded.project.text?.string, "Hi")
        XCTAssertEqual(loaded.project.palette, model.project.palette)
        XCTAssertEqual(loaded.ink.strokes.count, 1)
        XCTAssertEqual(loaded.sketch.strokes.count, 1)
        XCTAssertEqual(saver.saveCount, changes.count)
    }

    func testSaveNowWritesRightAwayAndStampsTheEditTime() async throws {
        let (model, saver) = newSession()
        let stamp = Date(timeIntervalSinceReferenceDate: 812_345_678)
        saver.now = { stamp }
        model.select(.shapes)
        model.addShape(.triangle)
        await settle()
        saver.saveNow()                                 // back button / app to background
        XCTAssertEqual(saver.saveCount, 1)
        XCTAssertEqual(clock.pendingCount, 0, "the debounce is dropped")
        let loaded = try store.load(model.project.id)
        XCTAssertEqual(loaded.project.updatedAt, stamp)
        clock.advance(by: 2)
        XCTAssertEqual(saver.saveCount, 1, "nothing left to write")
    }

    func testAnUntouchedNewProjectIsNeverWritten() async {
        let (_, saver) = newSession()
        await settle()
        saver.saveNow()
        clock.advance(by: 5)
        XCTAssertEqual(saver.state, .notSaved)
        XCTAssertFalse(onDisk, "New logo then Back leaves no empty card")
    }

    func testUndoingBackToTheSavedStateWritesNothing() async throws {
        let (model, saver) = newSession()
        model.select(.shapes)
        model.addShape(.circle)
        await settle()
        saver.saveNow()
        model.addShape(.star)
        await settle()
        model.undo()
        await settle()
        XCTAssertEqual(saver.state, .saved)
        clock.advance(by: 2)
        XCTAssertEqual(saver.saveCount, 1)
    }

    func testAFailedSaveSaysSoAndTheNextChangeRetries() async throws {
        let (model, saver) = newSession()
        store.writeTemporaryFile = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        model.select(.shapes)
        model.addShape(.circle)
        await settle()
        clock.advance(by: 1)
        XCTAssertEqual(saver.state, .failed)
        store.writeTemporaryFile = { data, url in try data.write(to: url) }
        model.chooseSlot(.first)
        await settle()
        clock.advance(by: 1)
        XCTAssertEqual(saver.state, .saved)
        XCTAssertEqual(try store.load(model.project.id).project.shapes.first?.fill, .first)
    }

    func testAReopenedProjectStartsSavedAndKeepsItsFolder() async throws {
        let (model, saver) = newSession()
        model.select(.shapes)
        model.addShape(.circle)
        await settle()
        saver.saveNow()
        let loaded = try store.load(model.project.id)
        let reopened = CanvasModel(project: loaded.project, sketch: loaded.sketch, ink: loaded.ink)
        let saver2 = ProjectAutosaver(model: reopened, store: store, isOnDisk: true, schedule: clock.scheduler)
        XCTAssertEqual(saver2.state, .saved)
        reopened.select(.shapes)
        reopened.addShape(.star)
        await settle()
        clock.advance(by: 1)
        XCTAssertEqual(store.entries().count, 1, "same project, same folder")
        XCTAssertEqual(try store.load(model.project.id).project.shapes.count, 2)
    }

    // MARK: Thumbnails

    /// Alpha of the thumbnail pixel at canvas point `p`.
    private func alpha(_ image: UIImage, at p: CGPoint) -> UInt8 {
        let cg = image.cgImage!
        let side = cg.width
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let x = Int(p.x / 1024 * CGFloat(side)), y = Int(p.y / 1024 * CGFloat(side))
        context.draw(cg, in: CGRect(x: -x, y: -(side - 1 - y), width: side, height: side))
        return pixel[3]
    }

    private func sketchLine() -> PKDrawing {
        PKDrawing(strokes: [PKStroke(ink: PKInk(.pencil, color: .gray), path: PKStrokePath(
            controlPoints: GateFixtures.densified([CGPoint(x: 700, y: 700), CGPoint(x: 950, y: 700)]).enumerated().map {
                PKStrokePoint(location: $1, timeOffset: Double($0) * 0.01, size: CGSize(width: 30, height: 30),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date()))])
    }

    func testThumbnailIsShapesInkAndTextWithoutTheSketch() {
        var project = Project.blank()
        project.shapes = [LogoShape(id: UUID(), kind: .circle, center: CGPoint(x: 250, y: 250), size: 300,
                                    rotation: 0, fill: .first)]
        let image = Thumbnail.image(project: project, sketch: sketchLine(), ink: PKDrawing())
        XCTAssertEqual(image.cgImage?.width, 512)
        XCTAssertEqual(alpha(image, at: CGPoint(x: 250, y: 250)), 255, "the shape")
        XCTAssertEqual(alpha(image, at: CGPoint(x: 820, y: 700)), 0, "no sketch, like the export")
        XCTAssertEqual(alpha(image, at: CGPoint(x: 50, y: 900)), 0, "transparent background")
    }

    func testASketchOnlyProjectShowsItsSketchFaded() {
        let image = Thumbnail.image(project: .blank(), sketch: sketchLine(), ink: PKDrawing())
        let a = alpha(image, at: CGPoint(x: 820, y: 700))
        XCTAssertGreaterThan(a, 0, "the card isn't blank")
        XCTAssertLessThan(a, 255, "faded")
    }

    func testTheSavedThumbnailFollowsTheProject() async throws {
        let (model, saver) = newSession()
        model.select(.shapes)
        model.addShape(.roundedSquare)
        await settle()
        saver.saveNow()
        let url = store.folder(for: model.project.id).appending(path: "thumb.png")
        let first = try Data(contentsOf: url)
        model.chooseSlot(.third)                        // refill the picked square
        await settle()
        saver.saveNow()
        XCTAssertNotEqual(try Data(contentsOf: url), first, "regenerated on save")
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: url)))
        XCTAssertEqual(alpha(image, at: CGPoint(x: 512, y: 512)), 255)
    }
}
