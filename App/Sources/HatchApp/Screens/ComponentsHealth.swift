import SwiftUI
import AppKit
import HatchCore
import HatchComponentKit

// Health (decision CP2): how much of the app's code follows the system, what differs, where, and the tickets that put
// it in place. The older folder-based scan (CO1 to CO13) sits under it, folded (CP5). Then the page's sheets.

struct ComponentsHealthView: View {
    let project: Project
    let loaded: ComponentsView.Loaded
    let system: ComponentSystem
    let select: (String) -> Void
    let addTickets: () -> Void

    private var findings: [ComponentFinding] { loaded.findings }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            coverage
            if findings.isEmpty {
                HXCard { Label("Nothing to look at: every control the check can place follows its role and the rules.", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    byKind
                    byRole
                }
                byFile
            }
        }
    }

    private var coverage: some View {
        HXCard {
            VStack(alignment: .leading, spacing: 10) {
                if let c = loaded.coverage, c.total > 0 {
                    HStack(alignment: .top, spacing: 28) {
                        figure(c.usingRole, "use a role")
                        figure(c.matching, "only need the swap")
                        figure(max(0, c.total - c.usingRole - c.matching), "differ or have no role")
                        figure(findings.filter(\.certain).count, "sure findings")
                        Spacer(minLength: 0)
                    }
                    ProgressView(value: Double(c.usingRole + c.matching), total: Double(c.total))
                    Text("Of \(c.total) controls whose place Hatch can tell. Agents are pressed only on sure findings (read from the code's structure); the rest are notes.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(loaded.hasClone ? "The app has no controls Hatch can place yet." : "No clone of the app on this Mac, so Hatch cannot check the code. Choose its folder in Project settings.")
                        .foregroundStyle(.secondary)
                }
                if let c = loaded.coverage, c.usingRole < c.total {
                    Button(action: addTickets) { Label("Add Tickets to Put It in Place", systemImage: "plus") }
                        .buttonStyle(.glass)
                        .help("Draft tickets: generate the role code, then the swaps that change nothing visible, then the controls that differ")
                }
            }
        }
    }

    private func figure(_ value: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var byKind: some View {
        let groups = ComponentFinding.Kind.allCases.compactMap { k -> (ComponentFinding.Kind, Int, Int)? in
            let list = findings.filter { $0.kind == k }
            return list.isEmpty ? nil : (k, list.count, list.filter(\.certain).count)
        }
        let largest = max(1, groups.map(\.1).max() ?? 1)
        return HXCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("By kind").font(.headline)
                ForEach(groups, id: \.0) { k, n, sure in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(k.title)
                            Spacer()
                            Text(sure == n ? "\(n)" : "\(n), \(sure) sure").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        Capsule().fill(.quaternary).frame(width: max(2, 240 * CGFloat(n) / CGFloat(largest)), height: 4)
                    }
                }
                let rules = Dictionary(grouping: findings.filter { $0.kind == .rule }, by: { $0.role ?? "" })
                if !rules.isEmpty {
                    Divider()
                    Text("Rules broken").font(.subheadline.weight(.semibold))
                    ForEach(rules.keys.sorted(), id: \.self) { id in
                        HStack {
                            Text(ComponentRuleKind.named(id)?.title ?? id)
                            Spacer()
                            Text("\(rules[id]?.count ?? 0)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    /// The roles with the most to look at; a click opens the role.
    private var byRole: some View {
        let counts = Dictionary(grouping: findings.filter { $0.kind != .rule && $0.role != nil }, by: { $0.role! }).mapValues(\.count)
        let top = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(8)
        return HXCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("By role").font(.headline)
                if top.isEmpty { Text("No role has findings.").font(.callout).foregroundStyle(.secondary) }
                ForEach(Array(top), id: \.key) { id, n in
                    Button { select(id) } label: {
                        HStack {
                            Text(system.role(id)?.title ?? id)
                            Text(id).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                }
            }
        }
    }

    private var byFile: some View {
        let counts = Dictionary(grouping: findings, by: \.file).mapValues(\.count)
        let top = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(10)
        return HXCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where").font(.headline)
                ForEach(Array(top), id: \.key) { file, n in
                    HStack(spacing: 8) {
                        Text("\(n)").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                        Text(file).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                }
                if counts.count > top.count {
                    Text("and \(counts.count - top.count) more files (`hatch components check`)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - The older scan

/// The folder-based components (CO1 to CO13): colors, type, sizes and views read from a components folder, the values
/// typed into views, and other sets. Folded under Health (CP5): the design system is the source of truth now.
struct ComponentsOldScan: View {
    let project: Project
    let loaded: ComponentsView.Loaded
    @Binding var message: String?
    let reload: () -> Void
    @EnvironmentObject var state: AppState
    @State private var open = false

    var body: some View {
        HXCard {
            DisclosureGroup(isExpanded: $open) {
                VStack(alignment: .leading, spacing: 14) {
                    if !loaded.hasClone {
                        Text("No clone of the app on this Mac. Choose its folder in Project settings.").foregroundStyle(.secondary)
                    } else if loaded.label == nil || loaded.componentsIsApp {
                        setup
                    } else if !loaded.folderExists {
                        Text("\(loaded.label ?? "The folder") is not in the app's clone yet. Pull the latest code, or choose another folder in Project settings.")
                            .foregroundStyle(.secondary)
                    } else if let catalog = loaded.catalog {
                        if catalog.isEmpty { Text("Nothing in \(loaded.label ?? "the folder") yet.").foregroundStyle(.secondary) } else { catalogView(catalog) }
                    }
                    if let scan = loaded.scan, loaded.label != nil, !loaded.componentsIsApp {
                        otherSets(scan)
                        typed(scan)
                    }
                }
                .padding(.top, 10)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Components folder").font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if let label = loaded.label, !loaded.componentsIsApp { parts.append(label + (project.config?.components?.product.map { ", import \($0)" } ?? "")) }
        else { parts.append("Not set; the generated role code needs one") }
        if let c = loaded.catalog, !c.isEmpty { parts.append("\(c.colors.count) colors, \(c.fonts.count) type, \(c.sizes.count) sizes, \(c.views.count) views") }
        if let typed = loaded.scan?.typedSummary { parts.append(typed + " typed into views") }
        return parts.joined(separator: " · ")
    }

    // A components folder for the generated role code: one Hatch found, or a new local package.
    private var setup: some View {
        let candidates = loaded.scan?.candidates ?? []
        let start = ComponentsConfig.suggested(appName: project.name)
        return VStack(alignment: .leading, spacing: 8) {
            Text("The generated role code and the named values live in a small package the app imports. Hatch only offers folders that are not the app itself.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(candidates.prefix(4), id: \.path) { c in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.path).font(.callout.monospaced())
                        Text(c.summary + (c.isPackage ? "" : " · a folder in the app, not a package")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Use") { use(c.config) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            HStack(spacing: 10) {
                Text("Start one in \(Text(start.path).font(.callout.monospaced()))").font(.callout)
                Spacer()
                Button("Start") { begin(start) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func catalogView(_ c: ComponentCatalog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !c.colors.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(c.colors, id: \.name) { ComponentSwatch(token: $0) }
                }
            }
            ForEach(c.fonts, id: \.name) { f in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("The quick brown fox").font(ComponentRender.font(f)).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(f.name).font(.caption.monospaced()).textSelection(.enabled)
                }
                .help(f.file)
            }
            if !c.sizes.isEmpty {
                Text(c.sizes.map { "\($0.name) \(ComponentRender.number($0.value))" }.joined(separator: " · ")).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if !c.views.isEmpty {
                Text("Views and styles: " + c.views.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func otherSets(_ scan: ComponentsScan) -> some View {
        let path = loaded.components?.path
        let others = scan.candidates.filter { $0.path != path }
        if let chosen = scan.candidates.first(where: { $0.path == path }), !others.isEmpty {
            let open = Set(((try? state.store.tickets(TicketFilter(projectId: project.id))) ?? [])
                .filter { $0.status != .done && $0.status != .dropped }.map(\.title))
            let clashes = ComponentConflicts.clashes(chosen: chosen, others: others)
            let merges = others.map { ComponentsSetup.mergeDraft(into: chosen, from: $0) }.filter { !open.contains($0.title) }
            let question = ComponentsSetup.clashQuestion(clashes, chosen: chosen, usage: [:]).flatMap { open.contains($0.title) ? nil : $0 }
            if !merges.isEmpty || question != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Other components in the app").font(.subheadline.weight(.semibold))
                    ForEach(others, id: \.path) { o in
                        Text("\(Text(o.path).font(.callout.monospaced())) · \(o.summary)").font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Add Tickets to Merge Them") { addConflictTickets(chosen: chosen, others: others, clashes: clashes, merges: merges, question: question != nil) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private func typed(_ scan: ComponentsScan) -> some View {
        if let summary = scan.typedSummary {
            VStack(alignment: .leading, spacing: 6) {
                Text("Typed into views").font(.subheadline.weight(.semibold))
                Text("\(summary) are written straight into views instead of taken from the named values.").font(.callout).foregroundStyle(.secondary)
                ForEach(scan.typedFiles.prefix(8), id: \.path) { f in
                    HStack(spacing: 8) {
                        Text("\(f.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                        Text(f.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                }
                if let components = loaded.components, loaded.folderExists {
                    Button("Add Tickets to Move Them") { addMoves(components, scan) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    private func use(_ components: ComponentsConfig) {
        var config = project.config ?? ProjectConfig(name: project.name, ticketsRepo: "")
        config.components = components
        guard state.saveProject(key: project.key, name: project.name, config: config, label: "Use components") != nil else { return }
        message = "\(components.path) holds \(project.name)'s components now."
        reload()
    }

    private func begin(_ components: ComponentsConfig) {
        var config = project.config ?? ProjectConfig(name: project.name, ticketsRepo: "")
        config.components = components
        let scan = loaded.scan
        guard state.saveProject(key: project.key, name: project.name, config: config, label: "Start components") != nil,
              let count = state.addComponentTickets(projectId: project.id,
                                                    drafts: ComponentsSetup.drafts(appName: project.name, config: components, scan: scan,
                                                                                   existing: scan?.candidates.map(\.path) ?? [])) else { return }
        message = "Added \(count) draft ticket\(count == 1 ? "" : "s"). Read and submit them from the Desk."
        reload()
    }

    private func addMoves(_ components: ComponentsConfig, _ scan: ComponentsScan) {
        guard let count = state.addComponentTickets(projectId: project.id, drafts: ComponentsSetup.moveDrafts(config: components, scan: scan, catalog: loaded.catalog)) else { return }
        message = "Added \(count) draft ticket\(count == 1 ? "" : "s"). Read and submit them from the Desk."
    }

    private func addConflictTickets(chosen: ComponentsCandidate, others: [ComponentsCandidate], clashes: [NameClash],
                                    merges: [ComponentsSetup.Draft], question: Bool) {
        let app = project.config?.repo(.app)?.localPath
        let projectId = project.id
        Task {
            let usage = await Task.detached { app.map { ComponentConflicts.usage(of: clashes.map(\.name), appRoot: $0) } ?? [:] }.value
            let q = question ? ComponentsSetup.clashQuestion(clashes, chosen: chosen, usage: usage) : nil
            guard let count = state.addComponentTickets(projectId: projectId, drafts: [q].compactMap { $0 } + merges) else { return }
            message = "Added \(count) draft ticket\(count == 1 ? "" : "s")" + (q != nil ? ". The Question waits in Decide." : ". Read and submit them from the Desk.")
        }
    }
}

// MARK: - Sheets

/// Change… on a role (CP3): what should change and where. Filing makes a Proposal an agent answers with looks.
struct ComponentChangeSheet: View {
    let role: ComponentRole
    let system: ComponentSystem
    let areas: [String]
    let file: (String, String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var what = ""
    @State private var scope = Scope.everywhere
    @State private var place = ""
    @State private var area = ""
    @State private var missing = false
    @FocusState private var focused: Bool

    enum Scope: Hashable { case everywhere, place, area }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Change \(role.title)").font(.title2.weight(.semibold))
                Text(role.use).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                ComponentRoleSample(role: role, system: system)
                    .allowsHitTesting(false)
                    .frame(minWidth: 120, minHeight: 44)
                    .padding(10)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    Text(role.followsMacOS ? "Follows macOS" : role.lookSummary)
                    Text("Baseline v\(system.version)").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("What should change?").font(.headline)
                TextField("For example: calmer, without glass; or larger in sheets", text: $what, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                if missing {
                    Text("Say what should change, so the agent knows which looks to offer.").font(.caption).foregroundStyle(Theme.critical)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Where").font(.headline)
                Picker("Where", selection: $scope) {
                    Text("Everywhere the role is used").tag(Scope.everywhere)
                    if role.places.count > 1 { Text("Only in one place (a variant)").tag(Scope.place) }
                    if !areas.isEmpty { Text("Only in one area (a variant)").tag(Scope.area) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if scope == .place {
                    Picker("Place", selection: $place) {
                        ForEach(role.places, id: \.self) { Text(ComponentPlace.title($0)).tag($0) }
                    }
                    .fixedSize()
                }
                if scope == .area {
                    Picker("Area", selection: $area) {
                        ForEach(areas, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                }
            }
            Text("Hatch files a Proposal. An agent offers two to four looks as recipes (a short file, no build); you choose in Decide or in the Designer, which draws them in place. Building the chosen look starts baseline v\(system.version + 1).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("File the Proposal") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            place = role.places.first ?? ""
            area = areas.first ?? ""
            focused = true
        }
    }

    private func submit() {
        let text = what.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { missing = true; focused = true; return }
        file(text, scope == .place ? place : nil, scope == .area ? area : nil)
        dismiss()
    }
}

/// Text Hatch makes from the system (the generated code, the design document), to read and copy.
struct ComponentCodeSheet: View {
    let title: String
    let detail: String
    let files: [String: String]
    let addTitle: String?
    let add: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var file = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            Text(LocalizedStringKey(detail)).foregroundStyle(.secondary)
            if files.count > 1 {
                Picker("File", selection: $file) {
                    ForEach(files.keys.sorted(), id: \.self) { Text(($0 as NSString).lastPathComponent).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ScrollView {
                Text(files[file] ?? "")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(files[file] ?? "", forType: .string)
                }
                Spacer()
                if let addTitle, let add {
                    Button(addTitle) { add(); dismiss() }
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 720, height: 560)
        .onAppear { file = files.keys.sorted().first ?? "" }
    }
}

/// The Apple pages every default comes from (NF1), with when they were last checked.
struct ComponentSourcesSheet: View {
    let system: ComponentSystem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple sources").font(.title2.weight(.semibold))
            Text("Every default, rule and piece of advice names the Apple page it comes from. Checked \(ComponentNative.checkedOn) against the macOS \(ComponentNative.checkedSDK) SDK; `hatch components refs` says when a newer SDK is installed and they need another look.")
                .foregroundStyle(.secondary)
            List(ComponentNative.references) { ref in
                HStack {
                    if let url = URL(string: ref.url) { Link(ref.title, destination: url) } else { Text(ref.title) }
                    Spacer()
                    Text(ref.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .listStyle(.inset)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
    }
}
