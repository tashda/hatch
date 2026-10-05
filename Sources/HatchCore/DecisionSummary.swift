import Foundation

public extension PendingDecision {
    /// What waits, in a few words for one line ("3 questions · 1 plan to approve · 9 to verify"), in a fixed order so the
    /// line does not reshuffle as counts change. Used by the menu bar's Decide item.
    static func summary(of kinds: [Kind]) -> String {
        func count(_ match: Set<Kind>) -> Int { kinds.filter(match.contains).count }
        func noun(_ n: Int, _ one: String, _ many: String) -> String? { n == 0 ? nil : "\(n) \(n == 1 ? one : many)" }
        let parts = [
            noun(count([.pick, .answer, .iris]), "question", "questions"),
            noun(count([.plan]), "plan to approve", "plans to approve"),
            noun(count([.submit]), "draft", "drafts"),
            noun(count([.judge]), "to judge", "to judge"),
            noun(count([.verify]), "to verify", "to verify"),
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}
