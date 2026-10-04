import SwiftUI
import HatchCore

/// The live shortcuts: the defaults from `ShortcutCatalog` plus the user's changes, saved per user. The menu bar,
/// tooltips, palette hints and the Settings page all read this, so a change shows everywhere at once.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var map: ShortcutMap
    private let defaults: UserDefaults
    private let defaultsKey = "hatch.shortcuts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        map = defaults.data(forKey: "hatch.shortcuts").map { ShortcutMap.decoded($0) } ?? ShortcutMap()
    }

    func chord(_ id: String) -> KeyChord? { map.chord(for: id) }

    /// The key as text ("⇧⌘O"), or nil when the command has none.
    func hint(_ id: String) -> String? { chord(id)?.display }

    /// A tooltip: "Back (⌘[)".
    func help(_ title: String, _ id: String) -> String {
        hint(id).map { "\(title) (\($0))" } ?? title
    }

    func shortcut(_ id: String) -> KeyboardShortcut? { chord(id)?.keyboardShortcut }

    @discardableResult
    func set(_ chord: KeyChord?, for id: String, replacing: Bool = false) -> ShortcutCheck {
        var next = map
        let result = next.set(chord, for: id, replacing: replacing)
        if result == .ok { commit(next) }
        return result
    }

    func reset(_ id: String) {
        var next = map
        next.reset(id)
        commit(next)
    }

    func resetAll() { commit(ShortcutMap()) }

    private func commit(_ next: ShortcutMap) {
        map = next
        if next.overrides.isEmpty { defaults.removeObject(forKey: defaultsKey) } else { defaults.set(next.encoded(), forKey: defaultsKey) }
    }
}

extension KeyChord {
    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "return": .return
        case "escape": .escape
        case "delete": .delete
        case "tab": .tab
        case "space": .space
        case "upArrow": .upArrow
        case "downArrow": .downArrow
        case "leftArrow": .leftArrow
        case "rightArrow": .rightArrow
        default: key.count == 1 ? KeyEquivalent(Character(key)) : nil
        }
    }

    var eventModifiers: EventModifiers {
        var out: EventModifiers = []
        if modifiers.contains(.control) { out.insert(.control) }
        if modifiers.contains(.option) { out.insert(.option) }
        if modifiers.contains(.shift) { out.insert(.shift) }
        if modifiers.contains(.command) { out.insert(.command) }
        return out
    }

    var keyboardShortcut: KeyboardShortcut? {
        keyEquivalent.map { KeyboardShortcut($0, modifiers: eventModifiers) }
    }
}

extension View {
    /// Gives the view the shortcut the user has for a command (none when it was cleared).
    func shortcut(_ id: String, _ store: ShortcutStore) -> some View {
        keyboardShortcut(store.shortcut(id))
    }
}
