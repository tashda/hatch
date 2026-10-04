import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings, Tools (was Apps; design-review/settings-pages.html). To be redesigned.
struct ToolsSettingsPage: View {
    var body: some View {
        SettingsPageForm(section: "Applications", footer: "Choose the applications Hatch opens for project work.") {
            HXPathRow(title: "Preview app copy", key: "preview_app_path", placeholder: "Path to Echo (Preview).app", chooseApp: true)
            HXPathRow(title: "Hatch Stage", key: "stage_executable", placeholder: "Path to the Stage executable", chooseApp: false)
            HXPathRow(title: "Spec app", key: "spec_app_path", placeholder: "Optional: the project's Spec app", chooseApp: true)
        }
    }
}

/// One path setting with a text field and a Choose button.
struct HXPathRow: View {
    @EnvironmentObject var state: AppState
    let title: String
    let key: String
    let placeholder: String
    let chooseApp: Bool

    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            Button("Choose…") { choose() }
        }
        .onAppear {
            if !loaded { text = state.hxSetting(key) ?? ""; loaded = true }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard loaded else { return }
        if text != (state.hxSetting(key) ?? "") { state.hxSaveSetting(key, text) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = chooseApp
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { text = url.path; commit() }
    }
}
