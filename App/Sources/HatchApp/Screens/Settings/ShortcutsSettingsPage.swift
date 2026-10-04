import SwiftUI
import HatchCore

/// Settings, Shortcuts: every command with its key. Click a key to record a new one; a clash asks before it replaces.
struct ShortcutsSettingsPage: View {
    /// The Settings search field, so a search also narrows the commands.
    var filter = ""
    @ObservedObject private var store = ShortcutStore.shared
    @State private var recording: String?
    @State private var problem: (id: String, text: String)?
    @State private var clash: Clash?
    @State private var hovered: String?

    private struct Clash: Identifiable {
        let command: ShortcutCommand
        let chord: KeyChord
        let owner: ShortcutCommand
        var id: String { command.id }
    }

    var body: some View {
        Form {
            ForEach(ShortcutGroup.allCases, id: \.self) { group in
                let rows = commands(in: group)
                if !rows.isEmpty {
                    Section(group.title) { ForEach(rows) { row($0) } }
                }
            }
            Section {
                HStack {
                    Text("Shortcuts you change are kept on this Mac.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset All") { store.resetAll(); problem = nil }
                        .disabled(store.map.overrides.isEmpty)
                }
            } footer: {
                Text("Menu commands need ⌘ or ⌃, so typing never triggers them. Keys for a list work only while a list has focus.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .confirmationDialog(clashTitle, isPresented: Binding(get: { clash != nil }, set: { if !$0 { clash = nil } }), presenting: clash) { c in
            Button("Replace") {
                store.set(c.chord, for: c.command.id, replacing: true)
                recording = nil
            }
            Button("Cancel", role: .cancel) { recording = nil }
        } message: { c in
            Text("\(c.chord.display) is used by \(c.owner.title). Replacing it leaves that command without a shortcut.")
        }
    }

    private var clashTitle: String { clash.map { "Use \($0.chord.display) for \($0.command.title)?" } ?? "" }

    private func commands(in group: ShortcutGroup) -> [ShortcutCommand] {
        store.map.commands.filter { command in
            command.group == group && (filter.isEmpty
                || command.title.localizedCaseInsensitiveContains(filter)
                || (store.hint(command.id)?.localizedCaseInsensitiveContains(filter) ?? false))
        }
    }

    private func row(_ command: ShortcutCommand) -> some View {
        let isRecording = recording == command.id
        let chord = store.chord(command.id)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                    if command.scope != .app {
                        Text(command.scope.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                if store.map.isChanged(command.id), !isRecording {
                    Button { store.reset(command.id); problem = nil } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .help("Back to \(command.defaultChord?.display ?? "no shortcut")")
                }
                if command.customizable, chord != nil, !isRecording, hovered == command.id {
                    Button { store.set(nil, for: command.id); problem = nil } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove the shortcut")
                }
                keyButton(command, chord: chord, isRecording: isRecording)
            }
            if let problem, problem.id == command.id {
                Text(problem.text).font(.caption).foregroundStyle(.red)
            }
        }
        .onHover { inside in
            if inside { hovered = command.id } else if hovered == command.id { hovered = nil }
        }
        .background(KeyRecorder(active: isRecording,
                                onChord: { record($0, for: command) },
                                onCancel: { if recording == command.id { recording = nil } }))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func keyButton(_ command: ShortcutCommand, chord: KeyChord?, isRecording: Bool) -> some View {
        if !command.customizable {
            ShortcutKeyCaps(symbols: chord?.symbols ?? [], dimmed: true).help("This key is fixed")
        } else {
            Button {
                problem = nil
                recording = isRecording ? nil : command.id
            } label: {
                if isRecording {
                    Text("Type the keys…").foregroundStyle(Color.accentColor)
                } else if let chord {
                    ShortcutKeyCaps(symbols: chord.symbols)
                } else {
                    Text("None").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
            .help(isRecording ? "Press the new keys. Esc cancels." : "Click to change")
        }
    }

    private func record(_ chord: KeyChord, for command: ShortcutCommand) {
        switch store.set(chord, for: command.id) {
        case .ok:
            recording = nil
        case .conflict(let owner):
            clash = Clash(command: command, chord: chord, owner: owner)
        case .reserved:
            problem = (command.id, "\(chord.display) belongs to macOS or to editing.")
        case .needsModifier:
            problem = (command.id, "Add ⌘ or ⌃ to \(chord.display), so it does not fire while you type.")
        case .invalidKey:
            problem = (command.id, "That key cannot be used.")
        }
    }
}
