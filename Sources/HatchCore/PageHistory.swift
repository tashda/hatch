import Foundation

/// Back and Forward for one window. Each window (main, Settings, a ticket window) owns its own, so going back in
/// one never moves another. It is a plain value; the app wraps it in an observable object.
public struct PageHistory<Page: Hashable & Sendable>: Sendable {
    public private(set) var current: Page
    public private(set) var backStack: [Page] = []
    public private(set) var forwardStack: [Page] = []

    /// The oldest entries fall off so a long session does not grow without bound.
    public static var limit: Int { 100 }

    public init(start: Page) { current = start }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    public var backPage: Page? { backStack.last }
    public var forwardPage: Page? { forwardStack.last }

    /// Goes to a page. Visiting the page you are already on changes nothing, and a new visit clears Forward.
    @discardableResult
    public mutating func visit(_ page: Page) -> Bool {
        guard page != current else { return false }
        backStack.append(current)
        if backStack.count > Self.limit { backStack.removeFirst(backStack.count - Self.limit) }
        forwardStack.removeAll()
        current = page
        return true
    }

    @discardableResult
    public mutating func goBack() -> Page? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return previous
    }

    @discardableResult
    public mutating func goForward() -> Page? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return next
    }

    /// Swaps the current page without adding history (a page that was removed, a ticket that moved).
    public mutating func replaceCurrent(with page: Page) { current = page }
}
