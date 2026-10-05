// hatch-inventory: samples (this file draws sample controls; they are not the app's own looks)
import SwiftUI
import AppKit

// Menu Bar Lab (Go › Menu Bar Lab): the owner picks how the parts of the menu bar menu look by switching between real
// versions in the real menu bar, on their own data or on samples. As in the Decide Lab, the choice is kept and can be
// copied for Claude; nothing here changes a ticket.

struct MenuBarLabView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var look = MenuBarLook.shared
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                row("Menu bar item", \.form)
                row("Content", \.content)
            } footer: {
                Text("The menu bar item changes as you choose. A sample stays in the menu bar until this window closes.")
            }
            Section {
                Button("Show the Menu") { MenuBarMenu.shared.popUpPreview() }
            } header: {
                Text("Preview")
            } footer: {
                Text("The same menu as the egg in the menu bar opens.")
            }
            Section("Choices") {
                row("Symbols", \.symbols)
                row("Decide", \.decide)
                row("Agents", \.agents)
                row("Problem", \.problem)
            }
            Section("Your combination") {
                Text(look.summary).font(.callout).textSelection(.enabled)
                HStack {
                    Button(copied ? "Copied" : "Copy for Claude") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("Menu Bar Lab choice: " + look.summary, forType: .string)
                        copied = true
                    }
                    Button("Reset") { look.reset() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
        .onChange(of: look.summary) { copied = false }
        .onDisappear { look.content = .live }
        .navigationTitle("Menu Bar Lab")
    }

    /// One choice: its name, ‹ › to step through the options, a menu of them, and what the selected one does.
    private func row<E: LabChoice>(_ title: String, _ kp: ReferenceWritableKeyPath<MenuBarLook, E>) -> some View {
        let value = Binding<E>(get: { look[keyPath: kp] }, set: { look[keyPath: kp] = $0 })
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                Spacer(minLength: 8)
                Button { step(kp, -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless).help("Previous option")
                Picker(title, selection: value) {
                    ForEach(E.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Button { step(kp, 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).help("Next option")
            }
            Text(look[keyPath: kp].about).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func step<E: LabChoice>(_ kp: ReferenceWritableKeyPath<MenuBarLook, E>, _ by: Int) {
        let all = Array(E.allCases)
        guard let i = all.firstIndex(of: look[keyPath: kp]) else { return }
        look[keyPath: kp] = all[(i + by + all.count) % all.count]
    }
}
