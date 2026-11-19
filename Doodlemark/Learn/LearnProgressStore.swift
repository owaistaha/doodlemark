import Foundation
import Observation

/// One lesson's saved progress.
struct LessonProgress: Codable, Equatable, Sendable {
    /// The best finished score. Only ever goes up.
    var bestStars: Int?
    var maxStars: Int
    /// When the best score was set.
    var completedAt: Date?
    /// A lesson left halfway, to pick up again ("Continue · step 3 of 5").
    var inProgress: LessonResume?
}

/// Where a lesson was left: the next step, the stars so far and the kept
/// strokes (the Ink drawing, mirrored copies included). Shapes aren't
/// saved: every shape step before `step` was placed, so they're rebuilt.
struct LessonResume: Codable, Equatable, Sendable {
    /// Index of the step to do next.
    var step: Int
    /// Stars for steps `0..<step`.
    var stars: [Int]
    /// `PKDrawing.dataRepresentation()` of the kept strokes.
    var ink: Data
}

/// Learn progress in `Documents/learn.json` (TECH_SPEC "Progress"):
/// `{ "<lessonId>": { "bestStars": 12, "maxStars": 15, "completedAt": "…", "inProgress": … } }`.
/// Written atomically, like projects. A missing or unreadable file is an
/// empty start, never a crash.
@MainActor @Observable
final class LearnProgressStore {
    static var defaultURL: URL { URL.documentsDirectory.appending(path: "learn.json") }

    @ObservationIgnored let url: URL
    private(set) var lessons: [String: LessonProgress]

    init(url: URL = LearnProgressStore.defaultURL) {
        self.url = url
        lessons = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode([String: LessonProgress].self, from: $0) } ?? [:]
    }

    func progress(for id: String) -> LessonProgress? { lessons[id] }

    /// Every lesson's best, added up (the header's "25 stars").
    var totalStars: Int { lessons.values.reduce(0) { $0 + ($1.bestStars ?? 0) } }

    /// A finished run. The best score is kept if this one is lower; the
    /// halfway save is cleared either way. Returns the best after this run.
    @discardableResult
    func recordFinished(_ lesson: Lesson, stars: Int, at date: Date = Date()) -> Int {
        var entry = lessons[lesson.id] ?? LessonProgress(maxStars: lesson.maxStars)
        entry.maxStars = lesson.maxStars
        entry.inProgress = nil
        if stars > (entry.bestStars ?? -1) {
            entry.bestStars = stars
            entry.completedAt = date
        }
        lessons[lesson.id] = entry
        write()
        return entry.bestStars ?? stars
    }

    /// Remembers where a lesson was left (nil = nothing to resume).
    func saveResume(_ lesson: Lesson, _ resume: LessonResume?) {
        var entry = lessons[lesson.id] ?? LessonProgress(maxStars: lesson.maxStars)
        guard entry.inProgress != resume else { return }
        entry.inProgress = resume
        lessons[lesson.id] = entry.bestStars == nil && resume == nil ? nil : entry
        write()
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(lessons).write(to: url, options: .atomic)
        } catch {
            // Disk full or similar: progress stays in memory for this run.
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
