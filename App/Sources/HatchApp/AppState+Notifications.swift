import SwiftUI
import Combine
import UserNotifications
import HatchCore

/// Posts macOS notifications for what Settings › Notifications asks for (decision B6): a ticket that waits for you, an
/// agent handing in, an agent that stops or asks, sync or a notebook failing, and, if you want them, every status
/// change. It reads new events after every change (and every few seconds, since agents write through the hatch
/// command), so each event is told once. Your own moves are never notified. Start it once with
/// `NotificationCenterBridge.shared.start(state:)`.
@MainActor
final class NotificationCenterBridge: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterBridge()

    private var cancellables: Set<AnyCancellable> = []
    private var timer: Timer?
    private weak var state: AppState?
    /// The newest event already looked at; nil until the first scan, which only takes the position.
    private var lastEventId: Int?
    private var lastSyncProblem: String?
    private var lastNotebookProblem: String?

    /// Notifications need a real app bundle; a bare `swift run` binary has none and would crash.
    static var canNotify: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    func start(state: AppState) {
        if !cancellables.isEmpty { return }
        self.state = state
        if Self.canNotify {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        scan()
        state.$revision
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.scan() } }
            .store(in: &cancellables)
        state.$syncSummary.map(\.message).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in MainActor.assumeIsolated { self?.syncChanged(message) } }
            .store(in: &cancellables)
        state.$notebookProblem.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] problem in MainActor.assumeIsolated { self?.notebookChanged(problem) } }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    // MARK: What to tell

    /// The kinds of notification, each with its switch in Settings. `needsYou` decides the sound under "Only for
    /// things that need me".
    enum Kind {
        case waiting, handIn, agentStopped, statusChange, syncFailed, test

        var setting: String? {
            switch self {
            case .waiting: Preference.notifyWaiting
            case .handIn: Preference.notifyHandIn
            case .agentStopped: Preference.notifyAgentStops
            case .statusChange: Preference.notifyEveryStatus
            case .syncFailed: Preference.notifySync
            case .test: nil
            }
        }
    }

    /// One notification, before the settings decide whether and how it is shown.
    struct Message {
        var kind: Kind
        var title: String
        var body: String
        var needsYou: Bool
        var ticket: Ticket?
    }

    /// Turns the new events of one ticket into at most one message: an agent stopping beats a hand-in, a hand-in beats
    /// "waits for you", and that beats a plain status change. A kind that is switched off lets the next one speak.
    static func message(for events: [Event], ticket: Ticket, enabled: (Kind) -> Bool) -> Message? {
        let others = events.filter { $0.actor != Actor.owner.rawValue }
        var candidates: [Message] = []
        let n = ticket.displayNumber
        let movedToAnswers = others.contains { $0.kind == "status" && $0.payload["to"]?.stringValue == Status.needsAnswers.rawValue }
        for e in others.reversed() {
            switch e.kind {
            case "release" where e.payload["reason"]?.stringValue != "stopped by the owner":
                candidates.append(Message(kind: .agentStopped, title: "Agent stopped: \(n)",
                                          body: "\(ticket.title) · \(e.payload["reason"]?.stringValue ?? "it stopped before handing in")",
                                          needsYou: true, ticket: ticket))
            case "question" where !movedToAnswers:
                // A question that moved the ticket to Needs answers is a ticket waiting for you; one asked while an
                // agent works means the agent needs you.
                candidates.append(Message(kind: .agentStopped, title: "\(e.actor) asks about \(n)",
                                          body: e.payload["text"]?.stringValue ?? ticket.title, needsYou: true, ticket: ticket))
            case "status":
                guard let to = e.payload["to"]?.stringValue.flatMap(Status.init(rawValue:)) else { continue }
                let from = e.payload["from"]?.stringValue.flatMap(Status.init(rawValue:))
                // Handing in ends real work (preparing, revising, building, fixing). Iris finishing her check does not;
                // the ticket's next state speaks for itself.
                if e.actor == Actor.agent.rawValue, let from, from.turn == .agent, from != .checking, to.turn != .agent {
                    candidates.append(Message(kind: .handIn, title: "Handed in: \(n)", body: "\(ticket.title) · \(to.displayName)",
                                              needsYou: to.turn == .you, ticket: ticket))
                }
                if to.turn == .you, to != .draft {
                    candidates.append(Message(kind: .waiting, title: "\(to.displayName): \(n)", body: ticket.title,
                                              needsYou: true, ticket: ticket))
                }
                candidates.append(Message(kind: .statusChange, title: "\(n) moved to \(to.displayName)", body: ticket.title,
                                          needsYou: false, ticket: ticket))
            default:
                continue
            }
        }
        let order: [Kind] = [.agentStopped, .handIn, .waiting, .statusChange]
        for kind in order where enabled(kind) {
            if let m = candidates.first(where: { $0.kind == kind }) { return m }
        }
        return nil
    }

    // MARK: Watching

    private func scan() {
        guard let state else { return }
        let recent = (try? state.store.recentEvents(kinds: ["status", "release", "question"], limit: 60)) ?? []
        let newest = recent.map(\.event.id).max() ?? 0
        guard let last = lastEventId else { lastEventId = newest; return }
        let fresh = recent.filter { $0.event.id > last }.sorted { $0.event.id < $1.event.id }
        lastEventId = max(last, newest)
        guard !fresh.isEmpty else { return }
        var byTicket: [Int: (ticket: Ticket, events: [Event])] = [:]
        for item in fresh { byTicket[item.ticket.id, default: (item.ticket, [])].events.append(item.event) }
        for (_, item) in byTicket.sorted(by: { $0.key < $1.key }) {
            // The ticket as it is now, so the notification names its current title.
            let ticket = (try? state.store.ticket(id: item.ticket.id)) ?? item.ticket
            if let m = Self.message(for: item.events, ticket: ticket, enabled: { kind in kind.setting.map(state.flag) ?? true }) {
                post(m)
            }
        }
    }

    private func syncChanged(_ message: String?) {
        defer { lastSyncProblem = message }
        guard let message, !message.isEmpty, message != lastSyncProblem, let state, state.flag(Preference.notifySync) else { return }
        post(Message(kind: .syncFailed, title: "GitHub sync failed", body: message, needsYou: true, ticket: nil))
    }

    private func notebookChanged(_ problem: String?) {
        defer { lastNotebookProblem = problem }
        guard let problem, problem != lastNotebookProblem, let state, state.flag(Preference.notifySync) else { return }
        post(Message(kind: .syncFailed, title: "The notebook was not saved", body: problem, needsYou: true, ticket: nil))
    }

    // MARK: Posting

    /// Settings › Notifications › Send a Test: one notification, shown with the current sound and grouping.
    func sendTest() {
        post(Message(kind: .test, title: "Hatch notifications work",
                     body: "This is how Hatch tells you that a ticket waits for you.", needsYou: true, ticket: nil))
    }

    private func post(_ m: Message) {
        guard Self.canNotify, let state else { return }
        let content = UNMutableNotificationContent()
        content.title = m.title
        content.body = m.body
        switch NotificationSound(rawValue: state.hxSetting(Preference.notifySound) ?? "") ?? .needsMe {
        case .always: content.sound = .default
        case .needsMe: content.sound = m.needsYou ? .default : nil
        case .never: content.sound = nil
        }
        if state.flag(Preference.notifyGroup), let t = m.ticket, let project = state.project(id: t.projectId) {
            content.threadIdentifier = "project-\(project.key)"
            content.subtitle = state.projects.count > 1 ? project.name : ""
        }
        if let t = m.ticket { content.userInfo = ["ticketId": t.id] }
        if case .test = m.kind { content.userInfo = ["test": true] }
        let request = UNNotificationRequest(identifier: "hatch-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: Clicking a notification opens the ticket

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["ticketId"] as? Int
        Task { @MainActor in
            NSApp.activate()
            if let id, let state = NotificationCenterBridge.shared.state, let ticket = try? state.store.ticket(id: id) {
                state.open(ticket)
            }
        }
        completionHandler()
    }

    /// While Hatch is in front its own screens show what changed, so notifications go quietly to Notification Center.
    /// The test is the exception: it is sent from Settings, so it must show.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let test = notification.request.content.userInfo["test"] as? Bool == true
        completionHandler(test ? [.banner, .list, .sound] : [.list])
    }
}

extension AppState {
    /// Starts the notification bridge for this state (safe to call many times).
    func startNotifications() {
        NotificationCenterBridge.shared.start(state: self)
    }
}

private struct HXNotificationHook: ViewModifier {
    let state: AppState

    func body(content: Content) -> some View {
        content.onAppear { state.startNotifications() }
    }
}

extension View {
    /// Add to an always-present view (for example the window content) to start Dock-style notifications.
    func hatchNotifications(_ state: AppState) -> some View {
        modifier(HXNotificationHook(state: state))
    }
}
