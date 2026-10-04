import Foundation

// The keyboard shortcuts of the app, as data. One table says what every command is called, where it applies and
// which key it has by default. The menu bar, the palette hints, the tooltips, the cheat sheet and the Settings
// page all read it, and the tests check it for clashes. The SwiftUI side only turns a `KeyChord` into a key.

public struct KeyModifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = KeyModifiers(rawValue: 1)
    public static let option = KeyModifiers(rawValue: 2)
    public static let shift = KeyModifiers(rawValue: 4)
    public static let command = KeyModifiers(rawValue: 8)
}

/// One key with its modifiers. `key` is a single lowercase character ("k", "1", "[") or one of the names in
/// `KeyChord.namedKeys` ("return", "escape", "delete", "tab", "space", the arrows).
public struct KeyChord: Hashable, Codable, Sendable {
    public var key: String
    public var modifiers: KeyModifiers

    public init(_ key: String, _ modifiers: KeyModifiers = []) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    public static let namedKeys: Set<String> = ["return", "escape", "delete", "tab", "space", "upArrow", "downArrow", "leftArrow", "rightArrow"]

    public var isNamed: Bool { Self.namedKeys.contains(key) }
    public var isValidKey: Bool { isNamed || key.count == 1 }

    /// The way it is written on a keycap, in the order macOS uses: control, option, shift, command, then the key.
    public var symbols: [String] {
        var out: [String] = []
        if modifiers.contains(.control) { out.append("⌃") }
        if modifiers.contains(.option) { out.append("⌥") }
        if modifiers.contains(.shift) { out.append("⇧") }
        if modifiers.contains(.command) { out.append("⌘") }
        out.append(Self.glyph(for: key))
        return out
    }

    public var display: String { symbols.joined() }

    static func glyph(for key: String) -> String {
        switch key {
        case "return": "↩"
        case "escape": "⎋"
        case "delete": "⌫"
        case "tab": "⇥"
        case "space": "Space"
        case "upArrow": "↑"
        case "downArrow": "↓"
        case "leftArrow": "←"
        case "rightArrow": "→"
        default: key.uppercased()
        }
    }
}

/// Where a command is live. Commands in different places never clash with each other; `app` is a menu command
/// and clashes with everything, because the menu bar sees the key first.
public enum ShortcutScope: String, Codable, CaseIterable, Sendable {
    /// A menu command, valid in any window.
    case app
    /// Single keys on a focused list (Desk, Tickets, Board). They never fire while a text field has focus.
    case list
    /// Inside the open command palette.
    case palette
    /// From any app on the Mac, even when Hatch is in the background (decision WF-C2). It takes the key before any
    /// app sees it, so it clashes with Hatch's menu commands too.
    case system
    /// While writing a ticket: in Quick Capture and on the New Ticket page.
    case compose

    func overlaps(_ other: ShortcutScope) -> Bool {
        if self == .system || other == .system { return self == other || self == .app || other == .app }
        return self == .app || other == .app || self == other
    }

    public var title: String {
        switch self {
        case .app: "Anywhere"
        case .list: "In a list"
        case .palette: "In the command palette"
        case .system: "From any app"
        case .compose: "While writing a ticket"
        }
    }
}

public enum ShortcutGroup: String, CaseIterable, Sendable {
    case pages, tickets, windows, palette, lists, general

    public var title: String {
        switch self {
        case .pages: "Go to"
        case .tickets: "Ticket"
        case .windows: "Windows"
        case .palette: "Command palette"
        case .lists: "Lists"
        case .general: "General"
        }
    }
}

public struct ShortcutCommand: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let group: ShortcutGroup
    public let scope: ShortcutScope
    public let defaultChord: KeyChord?
    /// Fixed keys (↵, Esc and the arrows inside the palette) are listed but cannot be changed.
    public let customizable: Bool

    public init(_ id: String, _ title: String, _ group: ShortcutGroup, _ scope: ShortcutScope = .app,
                _ defaultChord: KeyChord? = nil, customizable: Bool = true) {
        self.id = id
        self.title = title
        self.group = group
        self.scope = scope
        self.defaultChord = defaultChord
        self.customizable = customizable
    }
}

public enum ShortcutCatalog {
    private static let cmd: KeyModifiers = .command

    /// Every command with a key. Commands are added here as they are built, so the Settings page never lists one
    /// that does nothing.
    public static let all: [ShortcutCommand] = [
        // Pages. The id after `page.` is the route's name; the app checks that every route has one.
        .init("page.desk", "Desk", .pages, .app, .init("1", cmd)),
        .init("page.tickets", "Tickets", .pages, .app, .init("2", cmd)),
        .init("page.board", "Board", .pages, .app, .init("3", cmd)),
        .init("page.previews", "Previews", .pages, .app, .init("4", cmd)),
        .init("page.specs", "Specs", .pages, .app, .init("5", cmd)),
        .init("page.decisions", "Decisions", .pages, .app, .init("6", cmd)),
        .init("page.agents", "Agents", .pages, .app, .init("7", cmd)),
        .init("page.log", "Log", .pages, .app, .init("8", cmd)),
        .init("page.projects", "Project Settings", .pages, .app, .init("9", cmd)),
        .init("page.components", "Components", .pages, .app, .init("0", cmd)),
        .init("page.tests", "Tests", .pages, .app, .init("t", [.control, .command])),
        .init("page.health", "Health", .pages, .app, .init("h", [.control, .command])),
        .init("page.reports", "Reports", .pages, .app, .init("r", [.control, .command])),
        // A ticket from anywhere on the Mac (WF-C2). ⌃⌥H: H for Hatch, two modifiers no common app or macOS uses, and
        // not ⌃Space or ⌃⌥Space, which switch input sources.
        .init("capture.quick", "Quick Capture", .general, .system, .init("h", [.control, .option])),
        // Drag a rectangle over the screen for a screenshot (WF-C2). ⇧⌘A: A for area, and not a key a capture tool
        // such as Shottr or macOS's own ⇧⌘3 to ⇧⌘5 takes.
        .init("capture.area", "Capture Area", .general, .compose, .init("a", [.shift, .command])),
        // Empties Quick Capture, which otherwise keeps what was typed and pasted until it is sent.
        .init("capture.fresh", "Start Fresh", .general, .compose, .init("delete", [.shift, .command])),
        .init("page.newTicket", "New Ticket", .pages, .app, .init("n", cmd)),
        .init("go.places", "Go to…", .pages, .app, .init("k", [.shift, .command])),
        .init("decide.open", "Decide", .pages, .app, .init("d", [.shift, .command])),
        // The saved views listed under Views in the sidebar, in order.
        .init("view.1", "Saved view 1", .pages, .app, .init("1", [.option, .command])),
        .init("view.2", "Saved view 2", .pages, .app, .init("2", [.option, .command])),
        .init("view.3", "Saved view 3", .pages, .app, .init("3", [.option, .command])),
        .init("view.4", "Saved view 4", .pages, .app, .init("4", [.option, .command])),
        .init("view.5", "Saved view 5", .pages, .app, .init("5", [.option, .command])),
        .init("view.6", "Saved view 6", .pages, .app, .init("6", [.option, .command])),
        .init("view.7", "Saved view 7", .pages, .app, .init("7", [.option, .command])),
        .init("view.8", "Saved view 8", .pages, .app, .init("8", [.option, .command])),
        .init("view.9", "Saved view 9", .pages, .app, .init("9", [.option, .command])),

        // General
        .init("search.tickets", "Search Tickets", .general, .app, .init("k", cmd)),
        .init("search.actions", "Actions…", .general, .app, .init("p", [.shift, .command])),
        .init("search.reference", "Search Spec and Decisions", .general, .app, .init("k", [.option, .command])),
        .init("sync", "Sync with GitHub", .general, .app, .init("r", [.shift, .command])),
        .init("iris.toggle", "Iris", .general, .app, .init("a", [.option, .command])),
        .init("iris.inspector", "Iris Inspector", .general, .app, .init("i", [.control, .command])),
        .init("sidebar", "Sidebar", .general, .app, .init("s", [.control, .command])),
        .init("back", "Back", .general, .app, .init("[", cmd)),
        .init("forward", "Forward", .general, .app, .init("]", cmd)),
        .init("settings", "Settings…", .general, .app, .init(",", cmd), customizable: false),
        .init("help.shortcuts", "Keyboard Shortcuts", .general, .app, .init("/", cmd)),

        // The ticket in front (its page, or the selected row). Tabs are ⌃1 to ⌃5; the rest use ⌥⌘ so typing never triggers them.
        .init("ticket.tab.overview", "Overview", .tickets, .app, .init("1", .control)),
        .init("ticket.tab.options", "Options", .tickets, .app, .init("2", .control)),
        .init("ticket.tab.thread", "Thread", .tickets, .app, .init("3", .control)),
        .init("ticket.tab.work", "Work", .tickets, .app, .init("4", .control)),
        .init("ticket.tab.history", "History", .tickets, .app, .init("5", .control)),
        .init("ticket.primary", "Main Action", .tickets, .app, .init("return", [.shift, .command])),
        .init("ticket.secondary", "Second Action", .tickets, .app, .init("return", [.option, .command])),
        .init("ticket.sendBack", "Send Back with Notes…", .tickets, .app, .init("r", [.option, .command])),
        .init("ticket.park", "Park", .tickets, .app, .init("p", [.option, .command])),
        .init("ticket.resume", "Resume or Reopen", .tickets, .app, .init("z", [.option, .command])),
        .init("ticket.drop", "Drop…", .tickets, .app, .init("delete", [.option, .command])),

        // Windows and the ticket in front
        .init("ticket.openWindow", "Open Ticket in New Window", .windows, .app, .init("o", [.shift, .command])),
        .init("list.openWindow", "Open Selected Ticket in New Window", .windows, .list, .init("return", .option)),
        .init("palette.openWindow", "Open in New Window", .windows, .palette, .init("return", .option)),

        // Command palette
        .init("palette.open", "Open", .palette, .palette, .init("return"), customizable: false),
        .init("palette.newTicket", "New ticket with this title", .palette, .palette, .init("return", cmd)),
        .init("palette.actions", "Show actions for the ticket", .palette, .palette, .init("tab"), customizable: false),
        .init("palette.next", "Next result", .palette, .palette, .init("downArrow"), customizable: false),
        .init("palette.previous", "Previous result", .palette, .palette, .init("upArrow"), customizable: false),
        .init("palette.close", "Close", .palette, .palette, .init("escape"), customizable: false),

        // Lists
        .init("list.next", "Next ticket", .lists, .list, .init("j")),
        .init("list.previous", "Previous ticket", .lists, .list, .init("k")),
        .init("list.open", "Open ticket", .lists, .list, .init("return")),
        .init("list.park", "Park", .lists, .list, .init("p")),
        .init("list.accept", "Accept recommendation", .lists, .list, .init("a")),
    ]

    public static func command(_ id: String) -> ShortcutCommand? { all.first { $0.id == id } }
}

public enum ShortcutCheck: Equatable, Sendable {
    case ok
    /// The key belongs to the system or to editing; it cannot be taken.
    case reserved
    /// A menu command needs ⌘ or ⌃, otherwise it would fire while typing.
    case needsModifier
    /// The key is not a character or a named key.
    case invalidKey
    /// Another command already has this key where both apply.
    case conflict(ShortcutCommand)
}

/// The defaults plus the user's changes. A change is a chord, or nil for "no shortcut". Pure value; the app
/// stores `overrides` as JSON.
public struct ShortcutMap: Equatable, Sendable {
    public var commands: [ShortcutCommand]
    /// Keyed by command id. A present key with a nil chord means the user cleared the shortcut.
    public private(set) var overrides: [String: KeyChord?]

    public init(commands: [ShortcutCommand] = ShortcutCatalog.all, overrides: [String: KeyChord?] = [:]) {
        self.commands = commands
        self.overrides = overrides.filter { id, _ in commands.contains { $0.id == id && $0.customizable } }
    }

    public func chord(for id: String) -> KeyChord? {
        if let changed = overrides[id] { return changed }
        return commands.first { $0.id == id }?.defaultChord
    }

    public func isChanged(_ id: String) -> Bool { overrides[id] != nil }

    /// The command that has this chord where `scope` applies, other than `excluding`.
    public func owner(of chord: KeyChord, scope: ShortcutScope, excluding id: String? = nil) -> ShortcutCommand? {
        commands.first { $0.id != id && $0.scope.overlaps(scope) && self.chord(for: $0.id) == chord }
    }

    /// Reserved by macOS or by editing; no command can use these.
    static let reserved: Set<KeyChord> = {
        let c: KeyModifiers = .command
        let keys = ["q", "h", "m", "w", "c", "v", "x", "z", "a", ",", "tab", "`", "space"]
        var set = Set(keys.map { KeyChord($0, c) })
        set.formUnion([KeyChord("h", [.option, .command]), KeyChord("z", [.shift, .command]), KeyChord("q", [.control, .command]),
                       KeyChord("space", .control), KeyChord("f", [.control, .command])])
        return set
    }()

    /// Keys macOS uses system-wide: Spotlight, Finder search and switching input sources.
    static let reservedSystemWide: Set<KeyChord> = [KeyChord("space", .command), KeyChord("space", [.option, .command]),
                                                    KeyChord("space", [.control, .option]), KeyChord("space", .control)]

    public func check(_ chord: KeyChord, for command: ShortcutCommand) -> ShortcutCheck {
        guard chord.isValidKey else { return .invalidKey }
        if Self.reserved.contains(chord) { return .reserved }
        if command.scope == .app || command.scope == .compose, !chord.modifiers.contains(.command), !chord.modifiers.contains(.control) { return .needsModifier }
        // A key taken from every app needs two modifiers, so it never steals an ordinary shortcut like ⌘K.
        if command.scope == .system {
            if Self.reservedSystemWide.contains(chord) { return .reserved }
            if [KeyModifiers.control, .option, .shift, .command].filter({ chord.modifiers.contains($0) }).count < 2 { return .needsModifier }
        }
        if let other = owner(of: chord, scope: command.scope, excluding: command.id) { return .conflict(other) }
        return .ok
    }

    /// Sets the key. `replacing` takes it from the command that has it; without it a clash is refused.
    @discardableResult
    public mutating func set(_ chord: KeyChord?, for id: String, replacing: Bool = false) -> ShortcutCheck {
        guard let command = commands.first(where: { $0.id == id }), command.customizable else { return .reserved }
        if let chord {
            let result = check(chord, for: command)
            switch result {
            case .ok: break
            case .conflict(let other) where replacing && other.customizable:
                overrides[other.id] = .some(nil)
            default: return result
            }
        }
        // Setting the default again is the same as no change.
        if chord == command.defaultChord { overrides[id] = nil } else { overrides[id] = .some(chord) }
        return .ok
    }

    public mutating func reset(_ id: String) { overrides[id] = nil }
    public mutating func resetAll() { overrides = [:] }

    /// Commands that share a key where both apply. The defaults must have none.
    public func clashes() -> [(ShortcutCommand, ShortcutCommand)] {
        var out: [(ShortcutCommand, ShortcutCommand)] = []
        for (i, a) in commands.enumerated() {
            guard let mine = self.chord(for: a.id) else { continue }
            for b in commands[(i + 1)...] where b.scope.overlaps(a.scope) && self.chord(for: b.id) == mine { out.append((a, b)) }
        }
        return out
    }

    // MARK: Saving

    /// A stable text form of the changes: id to "⌃⌘H" style tokens, "" for cleared.
    public func encoded() -> Data {
        let flat: [String: Stored] = overrides.mapValues { chord in
            chord.map { Stored(key: $0.key, modifiers: $0.modifiers.rawValue) } ?? Stored(key: "", modifiers: 0)
        }
        return (try? JSONEncoder().encode(flat)) ?? Data()
    }

    public static func decoded(_ data: Data, commands: [ShortcutCommand] = ShortcutCatalog.all) -> ShortcutMap {
        guard let flat = try? JSONDecoder().decode([String: Stored].self, from: data) else { return ShortcutMap(commands: commands) }
        var map = ShortcutMap(commands: commands)
        for (id, stored) in flat {
            // A stored change that is no longer valid (a key made reserved, a command removed) is dropped.
            let chord: KeyChord? = stored.key.isEmpty ? nil : KeyChord(stored.key, KeyModifiers(rawValue: stored.modifiers))
            if let chord, !chord.isValidKey { continue }
            map.overrides[id] = .some(chord)
        }
        map.overrides = map.overrides.filter { id, _ in commands.contains { $0.id == id && $0.customizable } }
        return map
    }

    private struct Stored: Codable { var key: String; var modifiers: Int }
}
