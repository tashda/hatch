import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings organized as a native navigation split view, with focused grouped forms.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: SettingsPage? = .general
    @State private var searchText = ""
    /// Back and Forward for this window only: switching pages is navigation, as in the main window.
    @State private var history = PageHistory<SettingsPage>(start: .general)
    @ObservedObject private var keys = ShortcutStore.shared

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search Settings", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                // Grouped like System Settings: how Hatch behaves, the services it connects to, and this Mac.
                List(selection: $selection) {
                    ForEach(SettingsPage.Group.allCases, id: \.self) { group in
                        let pages = SettingsPage.allCases.filter { $0.group == group && matches($0) }
                        if !pages.isEmpty {
                            Section(group.title) { ForEach(pages, id: \.self) { settingsLink($0) } }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: GeneralSettingsPage()
                case .notifications: NotificationsSettingsPage()
                case .agents: AgentSettingsPage()
                case .github: GitHubSettingsPage()
                case .tools: ToolsSettingsPage()
                case .storage: StorageSettingsPage()
                case .usage: UsageSettingsPage()
                case .shortcuts: ShortcutsSettingsPage(filter: searchText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 480)
        .onAppear(perform: showRequestedPage)
        .onChange(of: state.settingsPage) { _, _ in showRequestedPage() }
        .onChange(of: selection) { _, page in
            if let page { history.visit(page) }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button { go(history.goBack()) } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(!history.canGoBack)
                        .help(keys.help(history.backPage.map { "Back to \($0.title)" } ?? "Go Back", "back"))
                    Button { go(history.goForward()) } label: { Label("Forward", systemImage: "chevron.right") }
                        .disabled(!history.canGoForward)
                        .help(keys.help("Go Forward", "forward"))
                }
                .controlGroupStyle(.navigation)
            }
        }
        .windowNavigation(WindowNavigation(
            canGoBack: history.canGoBack, canGoForward: history.canGoForward,
            goBack: { go(history.goBack()) }, goForward: { go(history.goForward()) }))
    }

    /// Shows the page Back or Forward landed on. The selection change that follows is already the current page, so it adds no history.
    private func go(_ page: SettingsPage?) {
        if let page { selection = page }
    }

    /// Another screen (Cmd-K's Connect GitHub) can ask for a page; the window may already be open.
    private func showRequestedPage() {
        guard let page = state.settingsPage else { return }
        selection = page
        state.settingsPage = nil
    }

    private func settingsLink(_ page: SettingsPage) -> some View {
        NavigationLink(value: page) {
            Label(page.title, systemImage: page.symbol)
        }
    }

    private func matches(_ page: SettingsPage) -> Bool {
        searchText.isEmpty || page.title.localizedCaseInsensitiveContains(searchText)
            || (page == .shortcuts && ShortcutCatalog.all.contains { $0.title.localizedCaseInsensitiveContains(searchText) })
    }
}

enum SettingsPage: Hashable, CaseIterable {
    case general, notifications, agents, github, tools, storage, usage, shortcuts

    enum Group: CaseIterable {
        case hatch, connections, thisMac
        var title: String {
            switch self {
            case .hatch: "Hatch"
            case .connections: "Connections"
            case .thisMac: "This Mac"
            }
        }
    }

    var group: Group {
        switch self {
        case .general, .notifications, .agents, .shortcuts: .hatch
        case .github: .connections
        case .tools, .storage, .usage: .thisMac
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .notifications: "Notifications"
        case .agents: "Agents"
        case .github: "GitHub"
        case .tools: "Tools"
        case .storage: "Storage"
        case .usage: "Usage"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell.badge"
        case .agents: "cpu"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .tools: "hammer"
        case .storage: "internaldrive"
        case .usage: "chart.bar"
        case .shortcuts: "keyboard"
        }
    }
}

struct SettingsPageForm<Content: View>: View {
    let section: String
    let footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                content
            } header: {
                Text(section)
            } footer: {
                if let footer { Text(footer) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

