import SwiftUI
import AppKit
import HatchCore
import HatchGit
import HatchComponentKit

/// Components (decisions AE, CP1 to CP5): the hub for the project's design system. How the app looks, place by place,
/// drawn with the real controls (Overview); every role (Roles, a table with an inspector); the rules and the named
/// values; and how much of the code follows them (Health). Changing a role starts here, with Change…, and goes through a
/// Proposal (CP3). Hatch never builds the project's code: it draws the roles with its own renderer (HatchComponentKit).
struct ComponentsView: View {
    @EnvironmentObject var state: AppState
    @State private var loaded: Loaded?
    @State private var loading = false
    @State private var section: Section = .overview
    @State private var filter = ""
    @State private var message: String?
    @State private var selectedRole: String?
    @State private var sheet: ComponentsSheet?

    enum Section: Hashable { case overview, roles, rules, foundations, health }

    /// What one read of the notebook and the app's clone found.
    struct Loaded {
        var projectId: Int
        var components: ComponentsConfig?
        var label: String?
        var hasClone: Bool
        var folderExists: Bool
        var catalog: ComponentCatalog?
        var scan: ComponentsScan?
        /// The design system in the notebook (decisions DS1 to DS12), where it is on this Mac.
        var system: ComponentSystem?
        var notebook: String?
        /// How much of the app already follows it.
        var coverage: (usingRole: Int, matching: Int, total: Int)?
        var findings: [ComponentFinding] = []
        /// How many controls in the app use or fall under each role.
        var usesByRole: [String: Int] = [:]
        /// The components setting points at the app itself (CP5): offered for repair.
        var componentsIsApp = false
    }

    /// The selected project, or the only one when "All projects" is selected and there is just one.
    private var project: Project? {
        state.selectedProject ?? (state.projects.count == 1 ? state.projects.first : nil)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let project {
                header(project)
                content(project)
            } else {
                ContentUnavailableView("Choose a project", systemImage: "paintpalette",
                                       description: Text("Components belong to one project. Pick it from the title menu in the toolbar."))
                    .floatingCard()
            }
        }
        .environment(\.hxCardOnGray, true)
        .task(id: project?.id) { await load() }
        .inspector(isPresented: inspectorShown) { inspector.inspectorColumnWidth(min: 300, ideal: 340, max: 440) }
        .sheet(item: $sheet) { s in sheetView(s) }
    }

    // MARK: Header

    private var system: ComponentSystem? { loaded?.projectId == project?.id ? loaded?.system : nil }

    /// One row when the window is wide; the dock drops to a second row when it is not (the inspector takes room).
    private func header(_ project: Project) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                HXHeader(title: "Components", subtitle: subtitle(project)).fixedSize()
                Spacer(minLength: 8)
                dock
                Spacer(minLength: 8)
                actions(project)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    HXHeader(title: "Components", subtitle: subtitle(project)).fixedSize()
                    Spacer(minLength: 8)
                    actions(project)
                }
                dock
            }
        }
        .padding(16)
        .floatingCard()
    }

    @ViewBuilder private var dock: some View {
        if let system {
            HXDock(items: [.init(id: .overview, title: "Overview"),
                           .init(id: .roles, title: "Roles", count: system.roles.count),
                           .init(id: .rules, title: "Rules", count: system.rules.count),
                           .init(id: .foundations, title: "Foundations", count: system.foundations.count),
                           .init(id: .health, title: "Health", count: loaded.map { $0.findings.count })],
                   selection: $section)
        }
    }

    @ViewBuilder private func actions(_ project: Project) -> some View {
        HStack(spacing: 8) {
            if let system {
                if section == .roles || section == .foundations {
                    TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 140)
                }
                Button { StageLauncher.shared.openDesigner(project: project, state: state) } label: {
                    Label("Open Designer", systemImage: "paintbrush.pointed")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .fixedSize()
                .help("Judge and decide the roles with the real controls, in their places")
                moreMenu(project, system)
            } else {
                Button { Task { await load() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glass)
                    .disabled(loading)
                    .help("Read the notebook and the app's code again")
            }
        }
    }

    private func subtitle(_ project: Project) -> String {
        guard let system else { return "\(project.name)'s design system: which control to use in which place." }
        return "Baseline v\(system.version) · macOS \(system.minimumMacOS) and later"
    }

    /// Rare actions (LK11): the live window, a rescan, the code and the design document Hatch makes, Apple's pages.
    private func moreMenu(_ project: Project, _ system: ComponentSystem) -> some View {
        Menu {
            Button { StageLauncher.shared.openDesigner(project: project, state: state) } label: { Label("Open Live Window", systemImage: "macwindow") }
            Button { Task { await load() } } label: { Label("Rescan the App", systemImage: "arrow.clockwise") }
            Divider()
            Button { sheet = .code } label: { Label("Generated Code…", systemImage: "chevron.left.forwardslash.chevron.right") }
            Button { sheet = .designDocument } label: { Label("Design Document…", systemImage: "doc.text") }
            Button { sheet = .sources } label: { Label("Apple Sources…", systemImage: "book") }
            if system.counts.provisional > 0 {
                Divider()
                Button { edit("agree every provisional role") { try $0.agree() } } label: { Label("Agree Every Provisional Role", systemImage: "checkmark.seal") }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .controlSize(.large)
        .fixedSize()
        .help("More")
    }

    // MARK: Content

    @ViewBuilder private func content(_ project: Project) -> some View {
        if let loaded, loaded.projectId == project.id, section == .roles, let system = loaded.system {
            // A table scrolls by itself, so the Roles section is not in the page's scroll view.
            VStack(alignment: .leading, spacing: 6) {
                if let message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                ComponentsRolesTable(system: system, usesByRole: loaded.usesByRole, filter: filter, selection: $selectedRole)
            }
            .padding(8)
            .floatingCard()
        } else if let loaded, loaded.projectId == project.id {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let message {
                        Text(message).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4).textSelection(.enabled)
                    }
                    if loaded.componentsIsApp { repairCard(project, loaded) }
                    if let system = loaded.system {
                        section(project, loaded, system)
                    } else {
                        ComponentsStartCard(project: project, loaded: loaded, start: { startSystem(project, template: $0, compare: $1) })
                        ComponentsOldScan(project: project, loaded: loaded, message: $message, reload: { Task { await load() } })
                    }
                }
                .padding(3)
                .frame(maxWidth: 1040, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Reading \(project.name)'s design system…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .floatingCard()
        }
    }

    @ViewBuilder private func section(_ project: Project, _ loaded: Loaded, _ system: ComponentSystem) -> some View {
        switch section {
        case .overview:
            ComponentsOverview(project: project, loaded: loaded, system: system, select: show(role:), edit: edit,
                               addTickets: { addSystemTickets(project, system, loaded) })
        case .roles:
            EmptyView()
        case .rules:
            ComponentsRulesView(system: system, findings: loaded.findings, edit: edit, makeSetting: makeSetting)
        case .foundations:
            ComponentsFoundationsView(system: system, filter: filter)
        case .health:
            ComponentsHealthView(project: project, loaded: loaded, system: system, select: show(role:),
                                 addTickets: { addSystemTickets(project, system, loaded) })
            ComponentsOldScan(project: project, loaded: loaded, message: $message, reload: { Task { await load() } })
        }
    }

    /// A components setting that names the app's own package (CP5): Hatch reads the app's controls by itself, so the
    /// setting only misleads. One click clears it.
    private func repairCard(_ project: Project, _ loaded: Loaded) -> some View {
        HXCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The components folder is the app itself").font(.headline)
                    Text("\(loaded.label ?? "The folder") holds \(project.name)'s own code, not a set of shared components. Hatch reads the app's controls on its own, so this setting only misleads it. Clearing it changes nothing in the code.")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Clear the Setting") { clearComponentsSetting(project) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    // MARK: Inspector

    private var inspectorShown: Binding<Bool> {
        Binding(get: { section == .roles && selectedRole != nil && system?.role(selectedRole ?? "") != nil },
                set: { if !$0 { selectedRole = nil } })
    }

    @ViewBuilder private var inspector: some View {
        if let system, let id = selectedRole, let role = system.role(id), let project {
            ComponentRoleInspector(role: role, system: system, uses: loaded?.usesByRole[id] ?? 0,
                                   findings: loaded?.findings.filter { $0.role == id } ?? [],
                                   edit: edit, change: { sheet = .change(id) }, makeSetting: makeSetting,
                                   openDesigner: { StageLauncher.shared.openDesigner(project: project, state: state) })
        } else {
            Text("Select a role").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func show(role id: String) {
        section = .roles
        selectedRole = id
    }

    // MARK: Sheets

    @ViewBuilder private func sheetView(_ s: ComponentsSheet) -> some View {
        if let project, let system {
            switch s {
            case .change(let id):
                if let role = system.role(id) {
                    ComponentChangeSheet(role: role, system: system, areas: project.config?.areas.map(\.name) ?? []) { what, place, area in
                        fileChange(project, system, role: role, what: what, place: place, area: area)
                    }
                }
            case .code:
                ComponentCodeSheet(title: "Generated code",
                                   detail: "What `hatch components generate` writes into \(loaded?.label ?? "the components folder"). An agent writes it on a ticket; Hatch never edits the app's code.",
                                   files: ComponentCodegen.files(system, product: project.config?.components?.product),
                                   addTitle: "Add a Ticket to Generate It") {
                    let config = project.config?.components ?? ComponentsConfig.suggested(appName: project.name)
                    let drafts = ComponentsSetup.systemDrafts(system, config: config, coverage: nil)
                    if let count = state.addComponentTickets(projectId: project.id, drafts: Array(drafts.prefix(2))) {
                        message = "Added \(count) draft tickets. Submit \"Generate the role code\" from the Desk."
                    }
                }
            case .designDocument:
                ComponentCodeSheet(title: "Design document",
                                   detail: "The section Hatch keeps between its markers in the app's DESIGN.md (`hatch components design-md`). Text outside the markers is never touched.",
                                   files: ["DESIGN.md": system.designDocument(updating: "")], addTitle: nil, add: nil)
            case .sources:
                ComponentSourcesSheet(system: system)
            }
        }
    }

    // MARK: Changing the system

    /// One change to the system: written into the notebook and committed there (Hatch is the only writer, DS2), then
    /// Decide is brought in step. A change that would leave the system with problems is refused with them.
    private func edit(_ label: String, _ change: (inout ComponentSystem) throws -> Void) {
        guard let project, let notebook = loaded?.notebook, var system = loaded?.system else { return }
        do {
            try change(&system)
            let problems = system.problems()
            guard problems.isEmpty else { message = "Not changed: " + problems.joined(separator: " "); return }
            if !Snapshots.demoMode {
                try system.write(notebook: notebook)
                _ = try NotebookWriter.commit("Components: \(label)", in: notebook)
                state.notebookChanged(projectId: project.id)
                state.syncComponentQuestions(project: project, system: system)
            }
            loaded?.system = system
            message = nil
        } catch {
            message = "Could not \(label): \(error)"
        }
    }

    /// "Make it a setting" (NF5): the role or rule is marked, and a draft ticket builds the app setting.
    private func makeSetting(_ id: String) {
        guard let project else { return }
        var draft: ComponentsSetup.Draft?
        edit("make \(id) a setting") { draft = try $0.makeConfigurable(id) }
        guard let draft, !Snapshots.demoMode, let count = state.addComponentTickets(projectId: project.id, drafts: [draft]) else { return }
        message = "Added \(count) draft ticket for the setting. Read and submit it from the Desk."
    }

    /// Change… (CP3): a Proposal an agent answers with looks; it skips Iris, since Hatch wrote it.
    private func fileChange(_ project: Project, _ system: ComponentSystem, role: ComponentRole, what: String, place: String?, area: String?) {
        let draft = ComponentsSetup.changeDraft(role: role, what: what, place: place, area: area, system: system)
        guard let t = state.perform("File the change", { try state.store.fileComponentChange(projectId: project.id, draft) }) else { return }
        message = "Filed \(t.displayNumber). An agent offers two to four looks; you choose in Decide or in the Designer."
    }

    /// Writes a new system into the notebook and commits it there (Hatch is the only writer, DS2).
    /// With `compare`, the app's own controls are read and compared with the template (CD46): its looks are used where
    /// they match, the rest become questions recommended by Apple's guidance, then the template, then use counts.
    private func startSystem(_ project: Project, template: ComponentTemplate, compare: Bool) {
        guard let notebook = loaded?.notebook else { return }
        let config = project.config
        message = "Reading \(project.name)'s controls…"
        Task {
            let result = await Task.detached { () -> Result<ComponentSystem, Error> in
                Result {
                    let system: ComponentSystem
                    if !compare {
                        system = template.system(name: project.name)
                    } else {
                        guard let app = config?.repo(.app)?.localPath else { throw StoreError.invalid("No clone of the app.") }
                        let files = ComponentInventoryScanner.appFiles(appRoot: app, excluding: [config?.components?.path].compactMap { $0 })
                        system = ComponentDraft.fromApp(name: project.name, inventory: ComponentInventoryScanner.inventory(files: files), template: template,
                                                        minimumMacOS: ComponentInventoryScanner.minimumMacOS(appRoot: app) ?? ComponentSystem.referenceMacOS,
                                                        shell: ComponentShell.detect(files: files))
                    }
                    try system.write(notebook: notebook)
                    _ = try NotebookWriter.commit("Components: start the design system from the \(template.title) template" + (compare ? ", compared with the app" : ""), in: notebook)
                    return system
                }
            }.value
            switch result {
            case .success(let system):
                state.notebookChanged(projectId: project.id)
                state.syncComponentQuestions(project: project, system: system)
                message = "Started: \(system.roles.count) roles" + (system.questions.isEmpty ? "." : ", \(system.questions.count) to decide in the Designer or in Decide.")
            case .failure(let error):
                message = "Could not start the design system: \(error)"
            }
            await load()
        }
    }

    private func addSystemTickets(_ project: Project, _ system: ComponentSystem, _ loaded: Loaded) {
        let config = loaded.components ?? ComponentsConfig.suggested(appName: project.name)
        let drafts = ComponentsSetup.systemDrafts(system, config: config, coverage: loaded.coverage)
        guard let count = state.addComponentTickets(projectId: project.id, drafts: drafts) else { return }
        message = "Added \(count) draft tickets. Submit \"Generate the role code\" first."
    }

    private func clearComponentsSetting(_ project: Project) {
        guard var config = project.config else { return }
        config.components = nil
        guard state.saveProject(key: project.key, name: project.name, config: config, label: "Clear the components setting") != nil else { return }
        message = "Cleared. Hatch reads \(project.name)'s controls from the app itself."
        Task { await load() }
    }

    // MARK: Loading

    private func load() async {
        guard let project else { return }
        if Snapshots.demoMode {
            loaded = Self.demo(project)
            // HATCH_COMPONENTS_SECTION=roles draws one section in a snapshot run, with a role selected.
            switch ProcessInfo.processInfo.environment["HATCH_COMPONENTS_SECTION"] {
            case "roles"?: section = .roles; selectedRole = "button.primary"
            case "rules"?: section = .rules
            case "foundations"?: section = .foundations
            case "health"?: section = .health
            // No design system yet: the start gallery (CD3, CD46).
            case "start"?: loaded?.system = nil
            default: break
            }
            return
        }
        loading = true
        let config = project.config
        let result = await Task.detached { () -> Loaded in
            let app = config?.repo(.app)?.localPath.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            var l = Loaded(projectId: project.id, components: config?.components, label: config?.componentsLabel,
                           hasClone: app != nil, folderExists: false, catalog: nil, scan: nil)
            if let app { l.scan = ComponentsScanner.scan(appRoot: app, excluding: config?.components?.path) }
            if let folder = config?.componentsFolder, FileManager.default.fileExists(atPath: folder) {
                l.folderExists = true
                l.componentsIsApp = ComponentsScanner.isAppItself(folder: folder)
                if !l.componentsIsApp {
                    l.catalog = ComponentsScanner.catalog(at: folder, isPackage: config?.components.map { $0.product != nil } ?? true)
                }
            }
            l.notebook = config?.repo(.notebook)?.localPath.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            if let notebook = l.notebook { l.system = try? ComponentSystem.load(notebook: notebook) }
            if let system = l.system, let app {
                // A components setting that is the app itself would hide the whole app from the check.
                let excluded = l.componentsIsApp ? [] : [config?.components?.path].compactMap { $0 }
                let checked = ComponentCheck.all(appRoot: app, excluding: excluded, system: system, areaOf: { config?.area(ofFile: $0) })
                l.coverage = ComponentCheck.coverage(checked.inventory.uses, system: system)
                l.findings = checked.findings
                l.usesByRole = Self.usesByRole(checked.inventory.uses, system: system)
            }
            return l
        }.value
        guard self.project?.id == project.id else { return }
        loaded = result
        loading = false
        if let system = result.system { state.syncComponentQuestions(project: project, system: system) }
    }

    /// Each control counts for the role it uses, or the role its element, place and importance call for.
    nonisolated static func usesByRole(_ uses: [ComponentInventory.Use], system: ComponentSystem) -> [String: Int] {
        var out: [String: Int] = [:]
        for u in uses {
            guard let id = u.role ?? u.place.flatMap({ system.role(element: u.element, place: $0, importance: u.importance, kind: ComponentDraft.kind(u.element, u.recipe))?.id }) else { continue }
            out[id, default: 0] += 1
        }
        return out
    }

    /// A design system for snapshot runs: the Glass template with some roles agreed, a draft, a question and findings.
    static func demo(_ project: Project) -> Loaded {
        var loaded = Loaded(projectId: project.id, components: project.config?.components, label: project.config?.componentsLabel,
                            hasClone: true, folderExists: true, catalog: nil,
                            scan: ComponentsScan(candidates: [], typed: [.color: 3, .size: 41],
                                                 typedFiles: [(path: "Sources/Editor/EditorToolbar.swift", count: 14),
                                                              (path: "Sources/Connections/ConnectionRow.swift", count: 9)], swiftFiles: 412))
        var system = ComponentTemplates.glass.system(name: project.name)
        system.version = 3
        system.minimumMacOS = "15.0"
        system.shell = ComponentShell(navigation: .splitView, scenes: ["window", "settings", "menuBarWindow"], inspector: true, toolbar: true, search: true)
        try? system.agree("button.primary"); try? system.agree("button.cancel"); try? system.agree("button.toolbar")
        try? system.setLook("button.primary", recipe: ["style": "borderedProminent", "size": "large"])
        system.questions = [ComponentQuestion(id: "look.button.inRow", kind: .look, role: "button.inRow", title: "Row action: 3 looks in use",
                                              options: [.init(title: "bordered small", recipe: ["style": "bordered", "size": "small"], count: 29, effect: ""),
                                                        .init(title: "Not sure yet", effect: "")], reason: "Most used.")]
        loaded.system = system
        loaded.notebook = "/tmp/demo-notebook"
        loaded.coverage = (usingRole: 12, matching: 164, total: 412)
        func f(_ kind: ComponentFinding.Kind, _ role: String?, _ file: String, _ line: Int, certain: Bool = true) -> ComponentFinding {
            var x = ComponentFinding(kind: kind, element: "button", place: "listRow", role: role, file: file, line: line, look: "bordered", message: kind.title)
            x.certain = certain
            return x
        }
        loaded.findings = (0..<14).map { f(.couldUseRole, "button.inRow", "Sources/Desk/DeskRow.swift", 20 + $0) }
            + (0..<6).map { f(.mismatch, "button.secondary", "Sources/Editor/EditorToolbar.swift", 40 + $0, certain: $0 < 3) }
            + [f(.noRole, nil, "Sources/Settings/General.swift", 12), f(.rule, "titleCase", "Sources/Menus/Commands.swift", 33),
               f(.rule, "ellipsis", "Sources/Menus/Commands.swift", 51)]
        loaded.usesByRole = ["button.primary": 18, "button.cancel": 15, "button.inRow": 43, "button.toolbar": 27, "button.secondary": 31]
        return loaded
    }
}

/// The sheets the page opens.
enum ComponentsSheet: Identifiable, Hashable {
    case change(String), code, designDocument, sources
    var id: String {
        switch self { case .change(let r): "change-\(r)"; case .code: "code"; case .designDocument: "design"; case .sources: "sources" }
    }
}

/// One color: its light value, and its dark one beside it when it has one.
struct ComponentSwatch: View {
    let token: ColorToken

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                fill(token.light, system: token.system)
                if let dark = token.dark { fill(dark, system: nil) }
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            Text(token.name).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .help(token.file)
    }

    private var caption: String {
        if let l = token.light { return l.hex + (token.dark.map { " / \($0.hex)" } ?? "") }
        if let s = token.system { return "System: \(s)" }
        return "Value not readable"
    }

    @ViewBuilder private func fill(_ value: ComponentRGBA?, system: String?) -> some View {
        if let value {
            Rectangle().fill(ComponentRender.color(value))
        } else if let system, let color = ComponentRender.systemColor(system) {
            Rectangle().fill(color)
        } else {
            Rectangle().fill(.quaternary).overlay(Image(systemName: "questionmark").foregroundStyle(.secondary))
        }
    }
}

/// Turns what the reader found back into SwiftUI values, to draw the project's own tokens.
enum ComponentRender {
    static func color(_ v: ComponentRGBA) -> Color {
        Color(.sRGB, red: v.red, green: v.green, blue: v.blue, opacity: v.alpha)
    }

    static func systemColor(_ name: String) -> Color? {
        let swiftUI: [String: Color] = ["red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "mint": .mint, "teal": .teal,
                                        "cyan": .cyan, "blue": .blue, "indigo": .indigo, "purple": .purple, "pink": .pink, "brown": .brown,
                                        "white": .white, "gray": .gray, "black": .black, "clear": .clear, "primary": .primary,
                                        "secondary": .secondary, "accentColor": .accentColor]
        if let c = swiftUI[name] { return c }
        // NSColor's named colors (`windowBackgroundColor`, `systemBlue`), the same way asset catalogs refer to them.
        for candidate in [name, name + "Color"] {
            let selector = Selector(candidate)
            if NSColor.responds(to: selector), let ns = NSColor.perform(selector)?.takeUnretainedValue() as? NSColor {
                return Color(nsColor: ns)
            }
        }
        return nil
    }

    /// A color foundation's light and dark values, or the system color it names.
    static func colors(_ f: ComponentFoundation) -> (light: Color, dark: Color?) {
        func hex(_ s: String) -> Color? {
            let d = s.dropFirst()
            guard d.count >= 6, let v = UInt32(d.prefix(6), radix: 16) else { return nil }
            let a = d.count >= 8 ? Double(UInt32(d.dropFirst(6).prefix(2), radix: 16) ?? 255) / 255 : 1
            return Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
        }
        if let light = f.light.flatMap(hex) { return (light, f.dark.flatMap(hex)) }
        return (f.system.flatMap(systemColor) ?? .accentColor, nil)
    }

    static func font(_ t: FontToken) -> Font {
        let weight = t.weight.flatMap(fontWeight)
        let design = t.design.flatMap(fontDesign)
        var font: Font
        if let family = t.family {
            font = .custom(family, size: t.size ?? 13)
        } else if let size = t.size {
            font = .system(size: size, weight: weight ?? .regular, design: design ?? .default)
        } else {
            font = .system(t.style.flatMap(textStyle) ?? .body, design: design ?? .default)
            if let weight { font = font.weight(weight) }
        }
        return font
    }

    /// A type foundation drawn in its own font.
    static func font(_ f: ComponentFoundation) -> Font {
        let design = f.design.flatMap(fontDesign) ?? .default
        var font: Font = f.value.map { .system(size: $0, design: design) } ?? .system(f.system.flatMap(textStyle) ?? .body, design: design)
        if let weight = f.weight.flatMap(fontWeight) { font = font.weight(weight) }
        return font
    }

    static func number(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    private static func textStyle(_ s: String) -> Font.TextStyle? {
        ["largeTitle": .largeTitle, "title": .title, "title2": .title2, "title3": .title3, "headline": .headline,
         "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote, "caption": .caption,
         "caption2": .caption2][s]
    }

    private static func fontWeight(_ s: String) -> Font.Weight? {
        ["ultraLight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular, "medium": .medium,
         "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black][s]
    }

    private static func fontDesign(_ s: String) -> Font.Design? {
        ["default": .default, "rounded": .rounded, "serif": .serif, "monospaced": .monospaced][s]
    }
}

extension AppState {
    /// A prepared design system Question, or a change Proposal's look (CP3), answered in Decide or on its ticket: the
    /// answer goes into the system in the notebook and is committed there (Hatch is the only writer, DS2).
    func applyComponentDecision(ticket: Ticket, choice: String) throws {
        let isChange = ticket.type == .proposal && ComponentsSetup.changedRole(inBody: ticket.body) != nil
        guard ticket.area == ComponentsSetup.area, isChange || ComponentsSetup.componentQuestionId(inBody: ticket.body) != nil,
              let project = try store.project(id: ticket.projectId), let notebook = project.config?.repo(.notebook)?.localPath,
              var system = try ComponentSystem.load(notebook: notebook) else { return }
        guard try system.applyDecided(ticketBody: ticket.body, choice: choice, decision: ticket.displayNumber, ticketId: isChange ? ticket.id : nil) else { return }
        try system.write(notebook: notebook)
        _ = try NotebookWriter.commit("Components: \(ticket.title) (decided in \(ticket.displayNumber))", in: notebook)
    }

    /// Brings Decide in step with the design system's open questions.
    func syncComponentQuestions(project: Project, system: ComponentSystem) {
        guard !Snapshots.demoMode,
              let changed = try? store.syncComponentQuestions(projectId: project.id, system: system), changed.added + changed.dropped + changed.updated > 0 else { return }
        refresh()
    }

    /// Adds draft tickets for the components (decision CO3): a leading Theme is the parent of the rest. Drafts,
    /// so nothing starts until the owner reads and submits them. Returns how many were added.
    @discardableResult
    func addComponentTickets(projectId: Int, drafts: [ComponentsSetup.Draft]) -> Int? {
        perform("Add components tickets") {
            var parent: Int?
            for (index, d) in drafts.enumerated() {
                let t = try store.createTicket(projectId: projectId, type: d.type, title: d.title, body: d.body, area: d.area, parentId: parent)
                if index == 0 && d.type == .theme { parent = t.id }
                // A Question Hatch prepared carries its options, so it is answered in Decide without an agent (CO11).
                if !d.options.isEmpty { try store.setQuestionOptions(ticketId: t.id, d.options) }
            }
            return drafts.count
        }
    }
}
