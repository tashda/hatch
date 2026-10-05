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
        /// Parked or dropped instead of decided.
        case setAside
    }

    /// One mark per decision, in the order they first came up. Later puts a decision at the end of the queue again and
    /// going to one moves it forward; it keeps its first place here, so the bar never grows or shifts.
    public var marks: [(id: String, mark: Mark)] {
        let currentId = current?.id
        return firstOrder.map { id in
            if id == currentId { return (id, .current) }
            switch records[id]?.outcome {
            case .none: return (id, .waiting)
            case .later?, .opened?: return (id, .later)
            case .setAside?: return (id, .setAside)
            case .chose?, .refined?: return (id, .handled(startsAgent: records[id]?.startsAgent ?? false))
            }
        }
    }
}
