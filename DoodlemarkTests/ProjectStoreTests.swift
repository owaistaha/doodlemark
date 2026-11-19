import PencilKit
import XCTest
@testable import Doodlemark

/// Step 6 storage: the on-disk format, atomic writes, loading, the gallery's
/// list/rename/duplicate/delete and broken projects. Each test gets its own
/// empty folder.
@MainActor
final class ProjectStoreTests: XCTestCase {
    private var root: URL!
    private var store: ProjectStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ProjectStoreTests-\(UUID().uuidString)")
        store = ProjectStore(root: root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Fixtures

    /// Every part of a project: a custom palette, all shape kinds, text with
    /// tracking and caps, Mirror and Grid on, sketch and ink strokes.
    static func fullProject(name: String = "Pizza Rocket") -> LoadedProject {
        var project = Project.blank(name: name, now: Date(timeIntervalSinceReferenceDate: 800_000_000.123))
        project.palette = [HexColor(red: 0xFF, green: 0x5D, blue: 0x1F), Fixtures.ink, HexColor("#4DD0E1")!]
        project.shapes = LogoShape.Kind.allCases.enumerated().map { index, kind in
            LogoShape(id: UUID(), kind: kind, center: CGPoint(x: 200 + 180 * CGFloat(index), y: 300 + 0.25),
                      size: 150 + CGFloat(index) * 10.5, rotation: 0.3 * Double(index), fill: PaletteSlot(rawValue: index % 3)!)
        }
        project.text = LogoText(string: "Pizza Rocket", fontName: "Pacifico-Regular", center: CGPoint(x: 512, y: 820),
                                pointSize: 96, rotation: -0.2, fill: .third, tracking: 80, allCaps: true)
        project.symmetryOn = true
        project.gridOn = true
        let sketch = PKDrawing(strokes: [
            PKStroke(ink: PKInk(.pencil, color: .gray),
                     path: PKStrokePath(controlPoints: (0..<20).map {
                         PKStrokePoint(location: CGPoint(x: 100 + 30 * Double($0), y: 600 + 5 * Double($0)),
                                       timeOffset: Double($0) * 0.01, size: CGSize(width: 6, height: 6),
                                       opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                     }, creationDate: Date(timeIntervalSince1970: 0))),
        ])
        let ink = PKDrawing(strokes: [
            Fixtures.monolineStroke(GateFixtures.densified([CGPoint(x: 120, y: 120), CGPoint(x: 400, y: 200)]), width: 12,
                                    color: project.palette[1]),
            Fixtures.monolineStroke(GateFixtures.densified([CGPoint(x: 600, y: 120), CGPoint(x: 900, y: 400)]), width: 20,
                                    color: project.palette[0]),
        ])
        return LoadedProject(project: project, sketch: sketch, ink: ink)
    }

    /// The color as the exporter sees it (UIColor instances differ after a reload).
    static func hex(_ color: UIColor) -> String? {
        HexColor.sRGB(from: color.cgColor)?.color.hexString
    }

    private func save(_ loaded: LoadedProject) throws {
        try store.save(loaded.project, sketch: loaded.sketch, ink: loaded.ink,
                       thumbnail: Thumbnail.pngData(project: loaded.project, sketch: loaded.sketch, ink: loaded.ink))
    }

    private func assertSame(_ a: PKDrawing, _ b: PKDrawing, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.strokes.count, b.strokes.count, file: file, line: line)
        for (x, y) in zip(a.strokes, b.strokes) {
            XCTAssertEqual(x.path.map(\.location), y.path.map(\.location), file: file, line: line)
            XCTAssertEqual(x.path.map(\.size), y.path.map(\.size), file: file, line: line)
            XCTAssertEqual(x.transform, y.transform, file: file, line: line)
            XCTAssertEqual(Self.hex(x.ink.color), Self.hex(y.ink.color), file: file, line: line)
        }
    }

    // MARK: Round trip

    func testFullProjectRoundTrips() throws {
        let original = Self.fullProject()
        try save(original)
        let folder = store.folder(for: original.project.id)
        for name in ["project.json", "sketch.drawing", "ink.drawing", "thumb.png"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: name).path), name)
        }

        let loaded = try store.load(original.project.id)
        XCTAssertEqual(loaded.project, original.project, "palette, shapes, text, Mirror, Grid, name, dates")
        XCTAssertTrue(loaded.project.symmetryOn)
        XCTAssertTrue(loaded.project.gridOn)
        assertSame(loaded.sketch, original.sketch)
        assertSame(loaded.ink, original.ink)
        XCTAssertEqual(loaded.sketch.strokes.first?.ink.inkType, .pencil)
        XCTAssertEqual(try SVGExporter.svg(project: loaded.project, ink: loaded.ink),
                       try SVGExporter.svg(project: original.project, ink: original.ink), "exports the same")
    }

    func testProjectJSONStartsAtSchemaVersion1() throws {
        let original = Self.fullProject()
        try save(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: store.folder(for: original.project.id).appending(path: "project.json"))) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["name"] as? String, "Pizza Rocket", "the project's fields sit next to it, not nested")
    }

    func testANewerSchemaIsNotOpenedButShownAsBroken() throws {
        let original = Self.fullProject()
        try save(original)
        let url = store.folder(for: original.project.id).appending(path: "project.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertThrowsError(try store.load(original.project.id)) { error in
            XCTAssertEqual(error as? ProjectStore.Failure, .newerSchema(2))
        }
        guard case .broken? = store.entries().first else { return XCTFail("shown as a broken card") }
    }

    func testInkComesBackMonoline() throws {
        let original = Self.fullProject()
        try save(original)
        // What PencilKit itself gives back (RISKS #11): .pen.
        let raw = try PKDrawing(data: Data(contentsOf: store.folder(for: original.project.id).appending(path: "ink.drawing")))
        XCTAssertEqual(raw.strokes.first?.ink.inkType, .pen)
        let loaded = try store.load(original.project.id)
        XCTAssertEqual(Set(loaded.ink.strokes.map(\.ink.inkType)), [.monoline])
        XCTAssertEqual(loaded.ink.strokes.map { Self.hex($0.ink.color) }, original.ink.strokes.map { Self.hex($0.ink.color) })
    }

    // MARK: Atomic writes

    private struct SimulatedCrash: Error {}

    /// A crash part-way through writing any file of a save never corrupts
    /// the project: every file is a whole one (the old version or the new),
    /// project.json is the last good one, and it opens.
    func testACrashMidSaveKeepsTheLastGoodSave() throws {
        let good = Self.fullProject()
        try save(good)
        var newer = good
        newer.project.name = "Newer"
        newer.project.shapes.removeAll()
        newer.ink.strokes.append(newer.ink.strokes[0])

        for crashAt in 1...4 {                               // sketch, ink, thumbnail, project.json
            var writes = 0
            store.writeTemporaryFile = { data, url in
                writes += 1
                if writes == crashAt {
                    try data.prefix(data.count / 2).write(to: url)    // half written…
                    throw SimulatedCrash()                            // …then the app dies
                }
                try data.write(to: url)
            }
            XCTAssertThrowsError(try save(newer), "crash at write \(crashAt)")
            let loaded = try store.load(good.project.id)
            XCTAssertEqual(loaded.project, good.project, "crash at write \(crashAt): project.json is the old one")
            XCTAssertEqual(loaded.sketch.strokes.count, good.sketch.strokes.count)
            let inkLines = loaded.ink.strokes.count
            XCTAssertTrue(inkLines == good.ink.strokes.count || inkLines == newer.ink.strokes.count,
                          "crash at write \(crashAt): ink.drawing is a whole old or new file, never half")
            XCTAssertEqual(store.entries().count, 1)
            guard case .project? = store.entries().first else { return XCTFail("never the error card") }
        }
        store.writeTemporaryFile = { data, url in try data.write(to: url) }
    }

    /// Leftover temp files from a killed save are never read, and the next
    /// save clears them.
    func testLeftoverTempFilesAreIgnoredAndCleanedUp() throws {
        let good = Self.fullProject()
        try save(good)
        let folder = store.folder(for: good.project.id)
        let leftover = folder.appending(path: ".project.json.saving-\(UUID().uuidString)")
        try Data("{ half a fi".utf8).write(to: leftover)

        XCTAssertEqual(try store.load(good.project.id).project, good.project)
        guard case .project? = store.entries().first else { return XCTFail("still a normal card") }
        XCTAssertEqual(store.entries().count, 1)
        try save(good)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    }

    func testAtomicWriteReplacesTheWholeFile() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "file.txt")
        try store.writeAtomically(Data(repeating: 1, count: 1000), to: url)
        try store.writeAtomically(Data(repeating: 2, count: 10), to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data(repeating: 2, count: 10))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["file.txt"], "no temp left")
    }

    // MARK: Gallery

    func testEntriesAreNewestEditedFirst() throws {
        for (name, age) in [("Old", 30.0), ("New", 0.0), ("Middle", 10.0)] {
            var loaded = Self.fullProject(name: name)
            loaded.project.updatedAt = Date(timeIntervalSinceNow: -age * 86_400)
            try save(loaded)
        }
        let names = store.entries().compactMap { entry -> String? in
            if case .project(let summary) = entry { return summary.name } else { return nil }
        }
        XCTAssertEqual(names, ["New", "Middle", "Old"])
    }

    func testRenameChangesOnlyTheName() throws {
        let original = Self.fullProject()
        try save(original)
        try store.rename(original.project.id, to: "Rocket Pizza")
        let loaded = try store.load(original.project.id)
        XCTAssertEqual(loaded.project.name, "Rocket Pizza")
        XCTAssertEqual(loaded.project.updatedAt, original.project.updatedAt, "not an edit: the card stays where it is")
        XCTAssertEqual(loaded.project.shapes, original.project.shapes)
    }

    func testNamesAreCleaned() {
        XCTAssertEqual(ProjectNames.cleaned("  Moon Café  ", fallback: "x"), "Moon Café")
        XCTAssertEqual(ProjectNames.cleaned("   ", fallback: "Pizza"), "Pizza", "empty keeps the old name")
        XCTAssertEqual(ProjectNames.cleaned("Two\nlines", fallback: "x"), "Two lines")
        XCTAssertEqual(ProjectNames.cleaned(String(repeating: "a", count: 60), fallback: "x").count, 40)
        XCTAssertEqual(ProjectNames.copyName(of: "Star Club"), "Star Club copy")
        XCTAssertLessThanOrEqual(ProjectNames.copyName(of: String(repeating: "a", count: 40)).count, 40)
    }

    func testDuplicateIsADeepCopy() throws {
        let original = Self.fullProject()
        try save(original)
        let now = Date()
        let copy = try store.duplicate(original.project.id, now: now)
        XCTAssertNotEqual(copy.id, original.project.id)
        XCTAssertEqual(copy.name, "Pizza Rocket copy")
        XCTAssertEqual(copy.updatedAt, now, "shows first in the gallery")

        let loadedCopy = try store.load(copy.id)
        XCTAssertEqual(loadedCopy.project.shapes, original.project.shapes)
        XCTAssertEqual(loadedCopy.project.text, original.project.text)
        XCTAssertEqual(loadedCopy.project.palette, original.project.palette)
        assertSame(loadedCopy.ink, original.ink)
        assertSame(loadedCopy.sketch, original.sketch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.folder(for: copy.id).appending(path: "thumb.png").path))

        // Changing (or deleting) the original leaves the copy alone.
        var changed = original
        changed.project.shapes.removeAll()
        changed.project.palette[0] = HexColor("#00FF00")!
        changed.ink.strokes.removeAll()
        try save(changed)
        let again = try store.load(copy.id)
        XCTAssertEqual(again.project.shapes, original.project.shapes)
        XCTAssertEqual(again.project.palette, original.project.palette)
        XCTAssertEqual(again.ink.strokes.count, 2)
        try store.delete(original.project.id)
        XCTAssertNoThrow(try store.load(copy.id))
    }

    func testDeleteRemovesTheFolder() throws {
        let original = Self.fullProject()
        try save(original)
        let folder = store.folder(for: original.project.id)
        try store.delete(original.project.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(store.entries().isEmpty)
        try store.delete(folderNamed: "../")                     // never leaves the Projects folder
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().path))
    }

    // MARK: Broken projects

    func testUnreadableFoldersShowAsBrokenNotDropped() throws {
        let good = Self.fullProject()
        try save(good)
        let garbage = store.folder(for: UUID())
        try FileManager.default.createDirectory(at: garbage, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: garbage.appending(path: "project.json"))
        let noJSON = store.folder(for: UUID())                   // killed before its first project.json
        try FileManager.default.createDirectory(at: noJSON, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "not-a-uuid"), withIntermediateDirectories: true)

        let entries = store.entries()
        XCTAssertEqual(entries.count, 4)
        let broken = entries.compactMap { entry -> String? in
            if case .broken(let b) = entry { return b.id } else { return nil }
        }
        XCTAssertEqual(Set(broken), [garbage.lastPathComponent, noJSON.lastPathComponent, "not-a-uuid"])

        let gallery = GalleryModel(store: store)
        for entry in gallery.entries where entry.id != good.project.id.uuidString { gallery.delete(entry) }
        XCTAssertEqual(gallery.entries.map(\.id), [good.project.id.uuidString], "Delete on the error card works")
        XCTAssertFalse(FileManager.default.fileExists(atPath: garbage.path))
    }

    /// project.json is fine but a drawing is damaged: the card turns into the
    /// error card when it's opened, instead of crashing or opening empty.
    func testAProjectThatFailsToOpenBecomesTheErrorCard() throws {
        let damaged = Self.fullProject()
        try save(damaged)
        try Data("garbage".utf8).write(to: store.folder(for: damaged.project.id).appending(path: "ink.drawing"))
        let gallery = GalleryModel(store: store)
        guard case .project? = gallery.entries.first else { return XCTFail("looks fine until opened") }
        XCTAssertNil(gallery.open(damaged.project.id))
        guard case .broken? = gallery.entries.first else { return XCTFail("now the error card") }
        gallery.reload()
        guard case .broken? = gallery.entries.first else { return XCTFail("and it stays one") }
    }

    func testGalleryRenameDuplicateDelete() throws {
        let original = Self.fullProject()
        try save(original)
        let gallery = GalleryModel(store: store)
        gallery.rename(original.project.id, to: "  Rocket  ")
        guard case .project(let renamed)? = gallery.entries.first else { return XCTFail() }
        XCTAssertEqual(renamed.name, "Rocket")
        gallery.duplicate(original.project.id)
        XCTAssertEqual(gallery.entries.count, 2)
        guard case .project(let copy)? = gallery.entries.first else { return XCTFail() }
        XCTAssertEqual(copy.name, "Rocket copy", "the copy is newest")
        gallery.delete(.project(copy))
        XCTAssertEqual(gallery.entries.count, 1)
    }

    // MARK: Gallery labels and prompts

    func testEditedLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
        func ago(days: Int, hour: Int = 9) -> Date {
            calendar.date(byAdding: .day, value: -days, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!)!
        }
        XCTAssertEqual(EditedLabel.text(for: ago(days: 0), now: now, calendar: calendar), "Edited today")
        XCTAssertEqual(EditedLabel.text(for: ago(days: 1, hour: 23), now: now, calendar: calendar), "Edited yesterday")
        XCTAssertEqual(EditedLabel.text(for: ago(days: 3), now: now, calendar: calendar), "Edited 3 days ago")
        XCTAssertEqual(EditedLabel.text(for: ago(days: 8), now: now, calendar: calendar), "Edited last week")
        XCTAssertEqual(EditedLabel.text(for: ago(days: 15), now: now, calendar: calendar), "Edited 2 weeks ago")
        XCTAssertTrue(EditedLabel.text(for: ago(days: 90), now: now, calendar: calendar).hasPrefix("Edited "))
    }

    func testTenPromptsNineShownAndShuffleBringsTheHiddenOneIn() {
        XCTAssertEqual(Prompts.all.count, 10)
        XCTAssertEqual(Set(Prompts.all.map(\.id)).count, 10)
        XCTAssertEqual(Prompts.galleryChips.count, 3)
        var deck = PromptDeck()
        XCTAssertEqual(deck.shown.count, 9)
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<50 {
            let hidden = deck.hidden
            XCTAssertEqual(hidden.count, 1)
            deck.shuffle(using: &generator)
            XCTAssertEqual(Set(deck.shown.map(\.id)).count, 9)
            XCTAssertTrue(deck.shown.contains(hidden[0]), "Shuffle always changes what's shown")
        }
    }
}

/// A repeatable random generator for tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
