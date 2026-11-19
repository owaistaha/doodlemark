import Foundation

/// A starter idea for a logo. Picking one names the new project after it.
struct Prompt: Identifiable, Equatable, Sendable {
    /// The small square on the card. Theme maps it to a color (no hex here).
    enum Accent: Sendable { case tangerine, blue, ink, butter }

    let id: String
    let title: String
    let accent: Accent
}

/// The 10 starter prompts (PRD). The New logo screen shows 9 at a time;
/// the gallery's "Need an idea?" chips are the first three.
enum Prompts {
    static let all: [Prompt] = [
        Prompt(id: "pizza-rocket", title: "A pizza delivery rocket", accent: .tangerine),
        Prompt(id: "clan-badge", title: "Your gaming clan's badge", accent: .blue),
        Prompt(id: "cat-cafe", title: "A café run by cats", accent: .ink),
        Prompt(id: "moon-surf", title: "A surf school on the moon", accent: .butter),
        Prompt(id: "youtube", title: "Your YouTube channel", accent: .tangerine),
        Prompt(id: "robot-repair", title: "A robot repair shop", accent: .blue),
        Prompt(id: "dog-bakery", title: "A bakery just for dogs", accent: .butter),
        Prompt(id: "lemonade", title: "A lemonade stand empire", accent: .ink),
        Prompt(id: "initials", title: "Your own initials", accent: .tangerine),
        Prompt(id: "star-club", title: "A stargazing club", accent: .blue),
    ]

    /// "Need an idea?" in the gallery.
    static var galleryChips: [Prompt] { Array(all.prefix(3)) }
}

/// The 9 prompts the New logo grid shows. Shuffle always brings in the one
/// that was hidden (and hides another), in a new order, so it visibly changes.
struct PromptDeck: Equatable {
    static let shownCount = 9

    private(set) var shown: [Prompt]

    init(prompts: [Prompt] = Prompts.all) {
        shown = Array(prompts.prefix(Self.shownCount))
        all = prompts
    }

    private let all: [Prompt]

    /// The prompt not in the grid right now.
    var hidden: [Prompt] { all.filter { !shown.contains($0) } }

    mutating func shuffle<G: RandomNumberGenerator>(using generator: inout G) {
        let wasHidden = hidden
        var order = all.shuffled(using: &generator)
        // Make sure every hidden prompt comes in: swap it into the shown part.
        for prompt in wasHidden {
            guard let index = order.firstIndex(of: prompt), index >= Self.shownCount else { continue }
            let target = Int.random(in: 0..<Self.shownCount, using: &generator)
            order.swapAt(index, target)
        }
        shown = Array(order.prefix(Self.shownCount))
    }

    mutating func shuffle() {
        var generator = SystemRandomNumberGenerator()
        shuffle(using: &generator)
    }
}
