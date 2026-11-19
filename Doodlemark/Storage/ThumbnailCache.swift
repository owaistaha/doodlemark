import UIKit

/// Decoded gallery thumbnails, so the grid scrolls smoothly: files are read
/// and decoded off the main thread once, then kept in memory. The key has
/// the project's "last edited" time in it, so a save (which rewrites
/// thumb.png) shows the new picture.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 120
    }

    static func key(for summary: ProjectSummary) -> String {
        "\(summary.id.uuidString)@\(summary.updatedAt.timeIntervalSinceReferenceDate)"
    }

    func cached(_ summary: ProjectSummary) -> UIImage? {
        cache.object(forKey: Self.key(for: summary) as NSString)
    }

    /// The thumbnail, decoded and ready to draw; nil if the file is missing.
    func image(for summary: ProjectSummary) async -> UIImage? {
        if let hit = cached(summary) { return hit }
        let url = summary.thumbnail
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)?.preparingForDisplay()
        }.value
        if let image { cache.setObject(image, forKey: Self.key(for: summary) as NSString) }
        return image
    }
}
