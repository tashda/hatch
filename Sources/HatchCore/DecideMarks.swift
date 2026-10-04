import Foundation

extension DecideRun {
    /// One pill in the session's progress bar.
    public enum Mark: Equatable, Sendable {
        /// On screen now.
        case current
        /// Not reached yet.
        case waiting
        /// Left for later (or opened in a Preview); it comes back at the end of the session.
        case later
        /// Decided. `startsAgent` says whose turn it is now: an agent's, or nobody's (done, recorded).
        case handled(startsAgent: Bool)
    }

    /// One mark per decision, in the order they first came up. Later puts a decision at the end of the queue again; it
    /// keeps its first place here, so the bar never grows or shifts while the owner works through it.
    public var marks: [(id: String, mark: Mark)] {
        var seen = Set<String>()
        let currentId = current?.id
        return items.compactMap { item in
            guard seen.insert(item.id).inserted else { return nil }
            if item.id == currentId { return (item.id, .current) }
            switch records[item.id]?.outcome {
            case .none: return (item.id, .waiting)
            case .later?, .opened?: return (item.id, .later)
            case .chose?, .refined?: return (item.id, .handled(startsAgent: records[item.id]?.startsAgent ?? false))
            }
        }
    }
}
