import XCTest
@testable import Doodlemark

/// Step 8: the first-canvas tips are shown once, in order, skippable, and
/// the Settings switch brings them back once.
@MainActor
final class CanvasTipsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "CanvasTipsTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testThreeTipsInOrderThenNeverAgain() {
        let tips = CanvasTipsModel(defaults: defaults)
        tips.startIfNeeded()
        XCTAssertEqual(tips.current, .sketch)
        tips.next()
        XCTAssertEqual(tips.current, .ink)
        tips.next()
        XCTAssertEqual(tips.current, .export)
        tips.next()
        XCTAssertNil(tips.current)

        let nextCanvas = CanvasTipsModel(defaults: defaults)
        nextCanvas.startIfNeeded()
        XCTAssertNil(nextCanvas.current, "shown once")
    }

    func testSkipEndsThemForGood() {
        let tips = CanvasTipsModel(defaults: defaults)
        tips.startIfNeeded()
        tips.next()
        tips.finish()                                   // "Skip tips" on tip 2
        XCTAssertNil(tips.current)
        let nextCanvas = CanvasTipsModel(defaults: defaults)
        nextCanvas.startIfNeeded()
        XCTAssertNil(nextCanvas.current)
    }

    func testLeavingMidwayShowsThemAgainNextTime() {
        let tips = CanvasTipsModel(defaults: defaults)
        tips.startIfNeeded()
        tips.next()                                     // the app is closed on tip 2
        let nextCanvas = CanvasTipsModel(defaults: defaults)
        nextCanvas.startIfNeeded()
        XCTAssertEqual(nextCanvas.current, .sketch, "not seen until they're finished or skipped")
    }

    func testTheSettingsSwitchBringsThemBackOnce() {
        let tips = CanvasTipsModel(defaults: defaults)
        tips.startIfNeeded()
        tips.finish()
        defaults.set(true, forKey: CanvasTipsModel.showAgainKey)   // Settings → Doodlemark
        let again = CanvasTipsModel(defaults: defaults)
        again.startIfNeeded()
        XCTAssertEqual(again.current, .sketch)
        XCTAssertFalse(defaults.bool(forKey: CanvasTipsModel.showAgainKey), "the switch turns itself off")
        again.finish()
        let after = CanvasTipsModel(defaults: defaults)
        after.startIfNeeded()
        XCTAssertNil(after.current)
    }

    func testStartingTwiceDoesntRestart() {
        let tips = CanvasTipsModel(defaults: defaults)
        tips.startIfNeeded()
        tips.next()
        tips.startIfNeeded()                            // onAppear again (e.g. back from Preview & export)
        XCTAssertEqual(tips.current, .ink)
    }

    func testTheWordsAreShortAndKind() {
        for tip in CanvasTip.allCases {
            XCTAssertLessThanOrEqual(tip.title.count, 24, tip.title)
            XCTAssertLessThanOrEqual(tip.body.count, 90, tip.body)
            XCTAssertFalse((tip.title + tip.body).contains("!"), "no exclamation-mark spam")
            XCTAssertFalse((tip.title + tip.body).unicodeScalars.contains { $0.properties.isEmojiPresentation }, "no emoji")
        }
    }
}
