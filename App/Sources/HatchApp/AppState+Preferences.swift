import SwiftUI
import AppKit
import HatchCore

/// The settings of Settings › General and Notifications. Each is a row in the store's settings table, so the app, the
/// snapshot runs (in-memory store) and a fresh install all start from the same defaults written here.
enum Preference {
    // General
    static let appearance = "appearance"            // AppearanceChoice
    static let openTo = "open_to"                   // "desk" or "last"
    static let openProject = "open_project"         // "last" or "all"
    static let lastRoute = "last_route"             // Route.storageKey, kept as you move
    static let lastProject = "last_project"         // a project key; empty for All projects
    static let dockBadge = "dock_badge"             // "waiting" (decisions waiting) or "off"
    static let menuBar = "menu_bar"                 // on by default
    static let menuBarScope = "menu_bar_scope"      // "all" (default) or "selected": which projects the menu bar counts
    static let confirmDrop = "confirm_drop"         // on by default
    static let newTicketType = "new_ticket_type"    // empty asks; otherwise a TicketType raw value

    // Notifications
    static let notifyWaiting = "notify_waiting"
    static let notifyHandIn = "notify_hand_in"
    static let notifyAgentStops = "notify_agent_stops"
    static let notifyCI = "notify_ci"
    static let notifySync = "notify_sync"
    static let notifyEveryStatus = "notify_every_status"
    static let notifySound = "notify_sound"         // NotificationSound
    static let notifyGroup = "notify_group"

    /// Switches and their defaults: only things that need you or went wrong are on; every status change is off.
    static let flagDefaults: [String: Bool] = [
        menuBar: true, confirmDrop: true,
        notifyWaiting: true, notifyHandIn: true, notifyAgentStops: true, notifyCI: true, notifySync: true,
        notifyEveryStatus: false, notifyGroup: true,
    ]
}

/// System, Light or Dark for the whole app.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// When a notification plays a sound.
enum NotificationSound: String, CaseIterable, Identifiable {
    case needsMe = "needs", always, never
    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsMe: "Only for things that need me"
        case .always: "Always"
        case .never: "Never"
        }
    }
}

extension AppState {
    // MARK: Reading and writing

    func flag(_ key: String) -> Bool {
        guard let raw = hxSetting(key) else { return Preference.flagDefaults[key] ?? false }
        return raw == "1"
    }

    func setFlag(_ key: String, _ on: Bool) { setPreference(key, on ? "1" : "0") }

    /// Saves a setting and applies what it changes right away.
    func setPreference(_ key: String, _ value: String) {
        hxSaveSetting(key, value)
        switch key {
        case Preference.appearance: applyAppearance()
        case Preference.menuBar: showMenuBarItem = flag(Preference.menuBar)
        case Preference.menuBarScope: refreshMenuBarQueue()
        case Preference.dockBadge:
            dockBadgeShown = value != "off"
            refreshDecisionCount()
        default: break
        }
    }

    /// A switch in Settings, saved as it changes.
    func flagBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { self.flag(key) }, set: { self.setFlag(key, $0) })
    }

    /// A choice in Settings, saved as it changes; `fallback` is the default.
    func preferenceBinding(_ key: String, default fallback: String) -> Binding<String> {
        Binding(get: { self.hxSetting(key) ?? fallback }, set: { self.setPreference(key, $0) })
    }

    var appearanceChoice: AppearanceChoice { AppearanceChoice(rawValue: hxSetting(Preference.appearance) ?? "") ?? .system }

    /// The type New ticket starts with; nil asks.
    var newTicketType: TicketType? { hxSetting(Preference.newTicketType).flatMap(TicketType.init(rawValue:)) }

    // MARK: Applying

    /// Snapshot and demo runs choose their own appearance per picture, so they are left alone.
    func applyAppearance() {
        guard !Snapshots.demoMode else { return }
        NSApplication.shared.appearance = appearanceChoice.appearance
    }

    /// At launch (live app only): the appearance, the menu bar item, the Dock badge, then the project and page to open.
    func applyLaunchPreferences() {
        applyAppearance()
        showMenuBarItem = flag(Preference.menuBar)
        dockBadgeShown = hxSetting(Preference.dockBadge) != "off"
        let lastProject = hxSetting(Preference.lastProject)
        let lastRoute = hxSetting(Preference.lastRoute)
        if hxSetting(Preference.openProject) != "all", let key = lastProject, projects.contains(where: { $0.key == key }) {
            selectedProjectKey = key
        }
        if hxSetting(Preference.openTo) == "last", let saved = lastRoute, let destination = Route(storageKey: saved) {
            if case .ticket(let id) = destination {
                // A ticket that no longer exists opens the Desk instead.
                if (try? store.ticket(id: id)) != nil { selectedTicketId = id; route = destination }
            } else {
                route = destination
            }
        }
        updateWaitingCount()
    }

    /// Keeps the page you are on, quietly (no refresh), so the next launch can return to it.
    func rememberPlace() {
        try? store.setSetting(Preference.lastRoute, route.storageKey)
    }

    func rememberProject() {
        try? store.setSetting(Preference.lastProject, selectedProjectKey ?? "")
    }

    // MARK: Windows

    /// Brings Hatch forward with its main window, opening one if it was closed. Used by the menu bar item.
    func showMainWindow(_ openWindow: OpenWindowAction) {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(Self.mainWindowId) == true }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: Self.mainWindowId)
        }
    }

    static let mainWindowId = "main"
}
