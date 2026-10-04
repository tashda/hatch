import SwiftUI
import HatchCore

/// The keyboard shortcuts at a glance (⌘/). Read-only; Customize… opens the Settings page where they change.
struct ShortcutCheatSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var keys = ShortcutStore.shared

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 28, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(ShortcutGroup.allCases, id: \.self) { group in
                        let rows = keys.map.commands.filter { $0.group == group && keys.chord($0.id) != nil }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title).font(.headline)
                                ForEach(rows) { command in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(command.title)
                                            if command.scope != .app {
                                                Text(command.scope.title).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        ShortcutKeyCaps(symbols: keys.chord(command.id)?.symbols ?? [])
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("Every shortcut can be changed in Settings.").foregroundStyle(.secondary)
                Spacer()
                Button("Customize…") {
                    state.settingsPage = .shortcuts
                    openWindow(id: "settings")
                }
            }
            .padding(12)
        }
        .frame(minWidth: 680, minHeight: 480)
    }
}
