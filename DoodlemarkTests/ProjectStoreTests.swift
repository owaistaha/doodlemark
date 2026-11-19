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

    // MARK: Atomic saves (one folder swap)

    /// Every file in a project folder, byte for byte.
    private func folderContents(_ id: UUID) -> [String: Data] {
        let folder = store.folder(for: id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Dictionary(uniqueKeysWithValues: names.map { ($0, (try? Data(contentsOf: folder.appending(path: $0))) ?? Data()) })
    }

    /// A second save that changes every file: new name, a shape gone, an
    /// extra ink line in a recolored palette (ink colors follow the palette
    /// by exact color, so a mix of saves would break recolor).
    private static func newerSave(of good: LoadedProject) -> LoadedProject {
        var newer = good
        newer.project.name = "Newer"
        newer.project.shapes.removeAll()
        newer.project.palette[1] = HexColor("#1E88E5")!
        newer.project.updatedAt = good.project.updatedAt.addingTimeInterval(60)
        newer.ink.strokes = newer.ink.strokes.map { stroke in
            var stroke = stroke
            if Self.hex(stroke.ink.color) == good.project.palette[1].hexString {
                stroke.ink = PKInk(.monoline, color: UIColor(cgColor: newer.project.palette[1].cgColor))
            }
            return stroke
        }
        newer.ink.strokes.append(newer.ink.strokes[0])
        newer.sketch.strokes.removeAll()
        return newer
    }

    /// Where a save can be cut off: after each step, or half-way through
    /// writing each file.
    private enum CrashPoint: CustomStringConvertible {
        case after(ProjectStore.SaveStep)
        case tornWrite(String)

        static var all: [CrashPoint] {
            ProjectStore.SaveStep.allCases.map { .after($0) }
                + [ProjectStore.FileName.sketch, ProjectStore.FileName.ink, ProjectStore.FileName.thumbnail,
                   ProjectStore.FileName.project].map { .tornWrite($0) }
        }

        /// Only a crash after the swap has the new save.
        var keepsNewSave: Bool {
            if case .after(.swapped) = self { true } else { false }
        }

        var description: String {
            switch self {
            case .after(let step): "after \(step)"
            case .tornWrite(let name): "half-way through \(name)"
            }
        }
    }

    /// Arms the store to "die" at `point`. Real writes are recorded so the
    /// test knows the exact bytes of the new save.
    private func arm(_ point: CrashPoint, recording written: @escaping (String, Data) -> Void) {
        store.stepHook = { step in
            if case .after(let at) = point, at == step { throw ProjectStore.SaveInterrupted() }
        }
        store.writeTemporaryFile = { data, url in
            written(url.lastPathComponent, data)
            if case .tornWrite(let name) = point, name == url.lastPathComponent {
                try data.prefix(data.count / 2).write(to: url)
                throw ProjectStore.SaveInterrupted()
            }
            try data.write(to: url)
        }
    }

    /// "Relaunch": a fresh store on the same folder, tidied like at launch.
    private func relaunch() {
        store = ProjectStore(root: root)
        store.removeLeftovers()
    }

    /// The user's ask: a crash at any point of a save leaves the full old
    /// save or the full new save, every file byte for byte, never a mix.
    func testACrashAnywhereInASaveLeavesTheFullOldOrTheFullNewSave() throws {
        let good = Self.fullProject()
        let newer = Self.newerSave(of: good)
        let id = good.project.id
        for point in CrashPoint.all {
            store = ProjectStore(root: root)
            try save(good)
            let old = folderContents(id)
            XCTAssertEqual(Set(old.keys), ["project.json", "sketch.drawing", "ink.drawing", "thumb.png"])
            var new: [String: Data] = [:]
            arm(point) { name, data in new[name] = data }

            XCTAssertThrowsError(try save(newer), "\(point)")
            relaunch()

            let after = folderContents(id)
            if point.keepsNewSave {
                XCTAssertEqual(after, new, "\(point): the full new save")
                XCTAssertEqual(try store.load(id).project, newer.project, "\(point)")
            } else {
                XCTAssertEqual(after, old, "\(point): the full old save, every file")
                XCTAssertEqual(try store.load(id).project, good.project, "\(point)")
            }
            XCTAssertNotEqual(old, new, "the two saves differ in every way that matters")
            let loaded = try store.load(id)
            let palette = Set(loaded.project.palette.map(\.hexString))
            for stroke in loaded.ink.strokes {
                XCTAssertTrue(palette.contains(Self.hex(stroke.ink.color) ?? "?"),
                              "\(point): every ink line still matches a palette slot")
            }
            XCTAssertEqual(store.entries().count, 1, "\(point)")
            guard case .project? = store.entries().first else { return XCTFail("\(point): never the error card") }
            try store.delete(id)
        }
    }

    /// A brand-new project that dies mid-save leaves nothing (no empty or
    /// error card), or the whole project once the swap is done.
    func testACrashInTheFirstSaveLeavesNoProjectOrTheWholeOne() throws {
        let fresh = Self.fullProject()
        for point in CrashPoint.all {
            store = ProjectStore(root: root)
            var new: [String: Data] = [:]
            arm(point) { name, data in new[name] = data }
            XCTAssertThrowsError(try save(fresh), "\(point)")
            relaunch()
            if point.keepsNewSave {
                XCTAssertEqual(folderContents(fresh.project.id), new, "\(point)")
                XCTAssertEqual(store.entries().count, 1, "\(point)")
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(for: fresh.project.id).path), "\(point)")
                XCTAssertEqual(store.entries(), [], "\(point): no card at all")
            }
            try store.delete(fresh.project.id)
        }
    }

    /// Rename is a whole-folder save too.
    func testACrashMidRenameLeavesTheOldOrTheNewName() throws {
        let good = Self.fullProject()
        for point in CrashPoint.all where !{ if case .tornWrite(ProjectStore.FileName.thumbnail) = point { true } else { false } }() {
            store = ProjectStore(root: root)
            try save(good)
            let old = folderContents(good.project.id)
            arm(point) { _, _ in }
            XCTAssertThrowsError(try store.rename(good.project.id, to: "Rocket Pizza"), "\(point)")
            relaunch()
            let after = folderContents(good.project.id)
            if point.keepsNewSave {
                XCTAssertEqual(try store.load(good.project.id).project.name, "Rocket Pizza", "\(point)")
                XCTAssertEqual(after.filter { $0.key != "project.json" }, old.filter { $0.key != "project.json" },
                               "\(point): the other files carried over byte for byte")
            } else {
                XCTAssertEqual(after, old, "\(point)")
            }
            try store.delete(good.project.id)
        }
    }

    /// Leftovers of a killed save (staging folders, step 6 temp files) are
    /// never read or listed, and launch and the next save clear them.
    func testLeftoversAreIgnoredAndCleanedUp() throws {
        let good = Self.fullProject()
        try save(good)
        arm(.after(.wroteProject)) { _, _ in }
        XCTAssertThrowsError(try save(Self.newerSave(of: good)))
        let staging = root.appending(path: ".staging")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path).count, 1, "a crash left its staging folder")
        let folder = store.folder(for: good.project.id)
        let oldTemp = folder.appending(path: ".project.json.saving-\(UUID().uuidString)")
        try Data("{ half a fi".utf8).write(to: oldTemp)

        store = ProjectStore(root: root)
        XCTAssertEqual(try store.load(good.project.id).project, good.project)
        XCTAssertEqual(store.entries().count, 1, "staging is never a card")
        guard case .project? = store.entries().first else { return XCTFail("still a normal card") }

        try save(good)                                      // the next save of that project tidies its own
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
        store.removeLeftovers()                             // launch tidies everything
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldTemp.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [good.project.id.uuidString])
    }

    /// An ordinary failure (disk full) cleans up its staging folder and
    /// keeps the old save.
    func testAFailedWriteKeepsTheOldSaveAndLeavesNoStaging() throws {
        let good = Self.fullProject()
        try save(good)
        let old = folderContents(good.project.id)
        store.writeTemporaryFile = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try save(Self.newerSave(of: good)))
        XCTAssertEqual(folderContents(good.project.id), old)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: ".staging").path)) ?? [], [])
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
