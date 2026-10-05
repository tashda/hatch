import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HatchCore
import HatchAgent

// Settings, Tools (was Apps; design-review/settings-pages.html). One grouped Form in three parts: what Hatch found on
// this Mac with its version and a check, which apps it opens folders in, and the project apps as rows with their icons.
// The probes run off the main thread each time the page appears.

struct ToolsSettingsPage: View {
    @EnvironmentObject var state: AppState
    @State private var found: ToolsFound?
    /// Bumped after a project app is chosen or cleared, so the rows read the settings again.
    @State private var appsVersion = 0

    var body: some View {
        Form {
            foundSection
            openWithSection
            projectAppsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            let store = state.store
            found = await Task.detached(priority: .userInitiated) { await ToolsFound.probe(store: store) }.value
        }
    }

    // MARK: Found on this Mac

    private var foundSection: some View {
        Section {
            FoundToolRow(title: "Xcode", icon: .symbol("hammer.fill", .blue), status: found?.xcode)
            FoundToolRow(title: "Git", icon: .symbol("arrow.triangle.branch", .orange), status: found?.git)
            FoundToolRow(title: "hatch command", icon: .symbol("terminal.fill", .gray), status: found?.hatch)
            FoundToolRow(title: "Claude Code", icon: .symbol("sparkle", .indigo), status: found?.claude) {
                Button("Set up in Agents") { state.settingsPage = .agents }
                    .buttonStyle(.link).font(.callout)
            }
        } header: {
            Text("Found on this Mac")
        }
    }

    // MARK: Open with

    private var openWithSection: some View {
        Section {
            ForEach(HXOpenWith.allCases, id: \.self) { OpenWithPicker(kind: $0) }
        } header: {
            Text("Open with")
        } footer: {
            Text("Used by Open in Terminal, Open in Editor and Take Over.")
        }
    }

    // MARK: Project apps

    private var projectAppsSection: some View {
        Section {
            ForEach(ProjectApp.allCases, id: \.self) { app in
                ProjectAppRow(app: app, path: path(app), onChoose: { choose(app) }, onClear: { set(app, nil) })
            }
        } header: {
            HStack {
                Text("Project apps")
                Spacer()
                // Drawn like the link buttons in the other section headers.
                Menu {
                    ForEach(ProjectApp.allCases, id: \.self) { app in Button(app.menuTitle) { choose(app) } }
                } label: {
                    Text("Choose…").fontWeight(.regular).foregroundStyle(Color.accentColor)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } footer: {
            Text("The apps Hatch opens for a project's Previews, Proposals and Spec.")
        }
    }

    private func path(_ app: ProjectApp) -> String? {
        _ = appsVersion
        return state.hxSetting(app.settingKey)
    }

    private func set(_ app: ProjectApp, _ path: String?) {
        state.hxSaveSetting(app.settingKey, path ?? "")
        appsVersion += 1
    }

    private func choose(_ app: ProjectApp) {
        let panel = NSOpenPanel()
        panel.title = app.menuTitle.replacingOccurrences(of: "…", with: "")
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = app.contentTypes
        if let current = path(app) { panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent() }
        else { panel.directoryURL = URL(fileURLWithPath: "/Applications") }
        if panel.runModal() == .OK, let url = panel.url { set(app, url.path) }
    }
}

// MARK: Probes

/// One tool as the page shows it: the value on the right, whether it works, and an optional line under the name.
struct ToolStatus: Equatable, Sendable {
    var value: String
    var ok: Bool
    var subtitle: String? = nil
    /// An app or file whose Finder icon stands for the tool.
    var iconPath: String? = nil
    /// Where it was found, or what went wrong, for the tooltip.
    var help: String? = nil
}

struct ToolsFound: Sendable {
    var xcode: ToolStatus
    var git: ToolStatus
    var hatch: ToolStatus
    var claude: ToolStatus

    /// Runs the four probes side by side; each one gives up after a few seconds.
    static func probe(store: HatchStore) async -> ToolsFound {
        async let x = Task.detached { xcodeStatus() }.value
        async let g = Task.detached { gitStatus() }.value
        async let h = Task.detached { hatchStatus(store: store) }.value
        async let c = Task.detached { claudeStatus() }.value
        return await ToolsFound(xcode: x, git: g, hatch: h, claude: c)
    }

    /// Output of a program that ran and exited 0, trimmed; nil otherwise.
    static func output(_ program: String, _ args: [String]) -> String? {
        guard let r = try? AgentProcess.spawn(program, args, stdin: nil, directory: nil,
                                              environment: AgentProcess.environment(), timeout: 10),
              r.status == 0 else { return nil }
        let text = (r.stdout.isEmpty ? r.stderr : r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The first thing that looks like a version number: "git version 2.51.0 (Apple Git-155)" gives 2.51.0.
    static func version(in text: String) -> String? {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "(" })
            .first { $0.first?.isNumber == true && $0.contains(".") }
            .map(String.init)
    }

    /// The .app that contains a path, such as the Xcode a developer directory belongs to.
    static func enclosingApp(_ path: String) -> String? {
        guard let range = path.range(of: ".app", options: .backwards) else { return nil }
        let end = path[range.upperBound...]
        guard end.isEmpty || end.hasPrefix("/") else { return nil }
        return String(path[..<range.upperBound])
    }

    /// Xcode as xcodebuild sees it: the version of the one xcode-select points at, and a line when that is not the
    /// Xcode macOS opens by default (or only the Command Line Tools).
    static func xcodeStatus() -> ToolStatus {
        let developer = output("/usr/bin/xcode-select", ["-p"])
        let selected = developer.flatMap(enclosingApp)
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode")?.path
        let version = output("/usr/bin/xcodebuild", ["-version"]).flatMap { $0.split(separator: "\n").first.map(String.init) }.flatMap(version(in:))
        var status = ToolStatus(value: version ?? "", ok: version != nil, iconPath: selected ?? installed, help: developer)
        if let selected, let installed, URL(fileURLWithPath: selected).standardizedFileURL != URL(fileURLWithPath: installed).standardizedFileURL {
            status.subtitle = "xcode-select points to \(URL(fileURLWithPath: selected).lastPathComponent)"
        }
        if version == nil {
            if installed == nil && selected == nil {
                status.value = "Not installed"
            } else if selected == nil {
                status.value = "Not selected"
                status.subtitle = "xcode-select points to the Command Line Tools"
            } else {
                status.value = "xcodebuild failed"
            }
        }
        return status
    }

    static func gitStatus() -> ToolStatus {
        guard let git = AgentProcess.locate("git") else { return ToolStatus(value: "Not found", ok: false) }
        guard let text = output(git, ["--version"]) else {
            return ToolStatus(value: "Not working", ok: false, help: "\(git) --version failed. Install the Command Line Tools with xcode-select --install.")
        }
        return ToolStatus(value: version(in: text) ?? text, ok: true, help: git)
    }

    /// The hatch agents use, and whether Terminal finds the same one.
    static func hatchStatus(store: HatchStore) -> ToolStatus {
        guard let path = AppState.hatchCommand(store: store) else { return ToolStatus(value: "Not found", ok: false) }
        let app = Bundle.main.bundlePath
        if path == AppState.builtInHatch {
            return ToolStatus(value: AppState.hatchInPath ? "Built in · in PATH" : "Built in · not in PATH", ok: true,
                              iconPath: app, help: path)
        }
        return ToolStatus(value: hxAbbreviated(path), ok: true, iconPath: app, help: path)
    }

    static func claudeStatus() -> ToolStatus {
        guard let claude = AgentProcess.locate("claude") else { return ToolStatus(value: "Not installed", ok: false) }
        guard let text = output(claude, ["--version"]) else { return ToolStatus(value: "Not working", ok: false, help: "\(claude) --version failed.") }
        return ToolStatus(value: version(in: text) ?? text, ok: true, help: claude)
    }
}

// MARK: Rows

/// A tool's icon: the app's own where there is one, otherwise a symbol in a small tile as System Settings shows panes.
enum ToolIcon {
    case symbol(String, Color)

    @ViewBuilder func view(path: String?) -> some View {
        if let path, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().interpolation(.high)
                .frame(width: 26, height: 26)
        } else if case .symbol(let name, let tint) = self {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: 26, height: 26)
        }
    }
}

/// One tool: icon, name (and a line under it), the version on the right and a check, or what is wrong in red.
private struct FoundToolRow<Subtitle: View>: View {
    let title: String
    let icon: ToolIcon
    let status: ToolStatus?
    @ViewBuilder var extra: Subtitle

    init(title: String, icon: ToolIcon, status: ToolStatus?, @ViewBuilder extra: () -> Subtitle = { EmptyView() }) {
        self.title = title; self.icon = icon; self.status = status; self.extra = extra()
    }

    var body: some View {
        HStack(spacing: 10) {
            icon.view(path: status?.iconPath)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle = status?.subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                } else {
                    extra
                }
            }
            Spacer()
            if let status {
                Text(status.value).foregroundStyle(status.ok ? Color.secondary : Theme.critical)
                    .lineLimit(1).truncationMode(.middle)
                    .help(status.help ?? "")
                    .textSelection(.enabled)
                if status.ok {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Theme.finished)
                        .accessibilityLabel("Works")
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .hatchMark("FoundToolRow")
    }
}

// MARK: Open with

/// The apps Hatch can open a folder in, by bundle id. Only installed ones are offered; the choice is a setting.
enum HXOpenWith: CaseIterable {
    case terminal, editor, gitClient

    struct App: Hashable {
        let id: String
        let name: String
    }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .editor: "Code editor"
        case .gitClient: "Git client"
        }
    }

    var settingKey: String {
        switch self {
        case .terminal: "open_terminal"
        case .editor: "open_editor"
        case .gitClient: "open_git_client"
        }
    }

    var candidates: [App] {
        switch self {
        case .terminal:
            [App(id: "com.apple.Terminal", name: "Terminal"), App(id: "com.googlecode.iterm2", name: "iTerm"),
             App(id: "com.mitchellh.ghostty", name: "Ghostty"), App(id: "dev.warp.Warp-Stable", name: "Warp")]
        case .editor:
            [App(id: "com.apple.dt.Xcode", name: "Xcode"), App(id: "com.microsoft.VSCode", name: "Visual Studio Code"),
             App(id: "com.todesktop.230313mzl4w4u92", name: "Cursor"), App(id: "dev.zed.Zed", name: "Zed"),
             App(id: "com.panic.Nova", name: "Nova")]
        case .gitClient:
            [App(id: "com.fournova.Tower3", name: "Tower"), App(id: "com.DanPristupov.Fork", name: "Fork"),
             App(id: "com.github.GitHubClient", name: "GitHub Desktop"), App(id: "com.torusknot.SourceTreeNotMAS", name: "Sourcetree")]
        }
    }

    /// A git client is optional; a terminal and an editor always have one when any is installed.
    var allowsNone: Bool { self == .gitClient }

    static func url(_ app: App) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) }

    var installed: [App] { candidates.filter { Self.url($0) != nil } }

    /// The app to use: the chosen one if it is still installed, else the first installed (none for a git client).
    func chosen(setting: String?) -> App? {
        let installed = installed
        if let setting, let app = installed.first(where: { $0.id == setting }) { return app }
        return allowsNone ? nil : installed.first
    }

    func appURL(setting: String?) -> URL? { chosen(setting: setting).flatMap(Self.url) }
}

/// A native picker of the installed apps for one kind, each with its icon.
private struct OpenWithPicker: View {
    @EnvironmentObject var state: AppState
    let kind: HXOpenWith
    @State private var selection = ""
    @State private var apps: [HXOpenWith.App] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if apps.isEmpty && !kind.allowsNone {
                LabeledContent(kind.title) { Text(loaded ? "None installed" : "").foregroundStyle(.secondary) }
            } else {
                Picker(kind.title, selection: $selection) {
                    if kind.allowsNone { Text("None").tag("") }
                    ForEach(apps, id: \.self) { app in
                        Label { Text(app.name) } icon: { Image(nsImage: Self.icon(app)) }.tag(app.id)
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: selection) { _, value in
            if loaded, value != (state.hxSetting(kind.settingKey) ?? "") { state.hxSaveSetting(kind.settingKey, value) }
        }
        .hatchMark("OpenWithPicker")
    }

    private func load() {
        guard !loaded else { return }
        apps = kind.installed
        selection = kind.chosen(setting: state.hxSetting(kind.settingKey))?.id ?? ""
        loaded = true
    }

    /// The app's icon at menu size.
    static func icon(_ app: HXOpenWith.App) -> NSImage {
        let image = (HXOpenWith.url(app).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()).copy() as! NSImage
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

// MARK: Project apps

/// The apps a project uses that Hatch starts itself. Each is a setting holding a path.
enum ProjectApp: CaseIterable {
    case preview, stage, spec

    var title: String {
        switch self {
        case .preview: "Preview copy"
        case .stage: "Stage"
        case .spec: "Spec app"
        }
    }

    var menuTitle: String {
        switch self {
        case .preview: "Choose Preview Copy…"
        case .stage: "Choose Stage…"
        case .spec: "Choose Spec App…"
        }
    }

    var settingKey: String {
        switch self {
        case .preview: "preview_app_path"
        case .stage: "stage_executable"
        case .spec: "spec_app_path"
        }
    }

    /// The Stage may be a built app or a bare executable from `swift build`.
    var contentTypes: [UTType] { self == .stage ? [.application, .unixExecutable] : [.application] }
}

/// A project app: its name and icon on the right, or Not set. Right-click to choose another, show it, or clear it.
private struct ProjectAppRow: View {
    let app: ProjectApp
    let path: String?
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        LabeledContent(app.title) {
            if let path {
                let exists = FileManager.default.fileExists(atPath: path)
                HStack(spacing: 6) {
                    if exists {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().interpolation(.high)
                            .frame(width: 18, height: 18)
                    }
                    Text(exists ? URL(fileURLWithPath: path).lastPathComponent : "Missing: \(URL(fileURLWithPath: path).lastPathComponent)")
                        .foregroundStyle(exists ? Color.secondary : Theme.critical)
                        .lineLimit(1).truncationMode(.middle)
                }
                .help(hxAbbreviated(path))
            } else {
                Text("Not set").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(app.menuTitle, action: onChoose)
            if let path {
                Button("Show in Finder") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                Divider()
                Button("Clear", action: onClear)
            }
        }
        .hatchMark("ProjectAppRow")
    }
}
