import SwiftUI
import HatchCore
import HatchComponentKit

// The Components page's sections (decision CP2): Overview, Roles, Rules and Foundations. Health and the sheets are in
// ComponentsHealth.swift. Every control is drawn by HatchComponentKit from the role's recipe, never from the project's
// code (CP1).

/// A change to the system, written by the page (Hatch is the only writer).
typealias ComponentsEdit = (String, (inout ComponentSystem) throws -> Void) -> Void

/// Roles in a place, quiet first and the main action last (the macOS order in a row).
func componentRoles(in place: String, _ system: ComponentSystem) -> [ComponentRole] {
    let order: [ComponentRole.Importance] = [.quiet, .destructive, .other, .main]
    return system.roles.filter { $0.places.contains(place) }
        .sorted { (order.firstIndex(of: $0.importance) ?? 0, $0.element) < (order.firstIndex(of: $1.importance) ?? 0, $1.element) }
}

/// "agreed", "provisional", "in redesign" as a symbol, neutral (colour is for turn and problems).
func componentStatusSymbol(_ s: ComponentRole.Status) -> String {
    switch s { case .agreed: "checkmark.seal"; case .provisional: "circle.dashed"; case .inRedesign: "pencil.and.outline" }
}

/// A role's control, drawn from its recipe with words that suit the place.
struct ComponentRoleSample: View {
    let role: ComponentRole
    let system: ComponentSystem
    var place: String? = nil
    var recipe: [String: String]? = nil

    var body: some View {
        RecipeControl(element: role.element, recipe: recipe ?? role.recipe, system: system, importance: role.importance,
                      sample: SampleWords.content(role.importance, place: place ?? role.places.first ?? "page", base: SampleContent()))
            .fixedSize()
            .hatchMark("ComponentRoleSample")
    }
}

// MARK: - Start

/// No design system yet: start one from the app's own controls or from a template.
struct ComponentsStartCard: View {
    let project: Project
    let loaded: ComponentsView.Loaded
    /// The chosen template, and whether to compare it with the app's own controls.
    let start: (ComponentTemplate, Bool) -> Void
    @EnvironmentObject var state: AppState
    @State private var chosen: String?

    /// Hatch's templates and the owner's (CD47), and the one new projects start from (CD46: the marked one, else Native).
    private var library: ComponentTemplateLibrary { ComponentTemplateLibrary(folder: state.paths.root.appendingPathComponent("templates", isDirectory: true)) }

    var body: some View {
        HXCard {
            VStack(alignment: .leading, spacing: 12) {
                if loaded.notebook == nil {
                    Label("No notebook on this Mac", systemImage: "book.closed").font(.headline)
                    Text("The design system lives in the project's notebook. Choose its folder in Project settings.").foregroundStyle(.secondary)
                    Button("Project Settings") { state.navigate(to: .projects) }.buttonStyle(.glass)
                } else {
                    let lib = library
                    let templates = lib.all
                    let recommended = lib.recommended.id
                    let selected = chosen ?? recommended
                    Label("Choose a starting point", systemImage: "square.grid.3x3.square").font(.headline)
                    Text(loaded.hasClone
                         ? "Hatch compares \(project.name)'s own controls with the template: where they match, they are used; where they differ, Hatch asks, recommending Apple's guidance first, then the template."
                         : "Every role starts from the template, as a guess you can change in the Components Designer.")
                        .foregroundStyle(.secondary)
                    // A drawn gallery (CD3): each starting point in three places, so it is chosen by seeing it.
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(templates) { t in tile(t, selected: selected == t.id, recommended: recommended == t.id) }
                        }
                        .padding(2)
                    }
                    HStack {
                        Spacer()
                        let name = templates.first { $0.id == selected }?.title ?? "macOS Native"
                        Button {
                            if let t = lib.named(selected) { start(t, loaded.hasClone) }
                        } label: { Label(loaded.hasClone ? "Start from \(name), Compared with the App" : "Start from \(name)", systemImage: "wand.and.stars") }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                    }
                }
            }
        }
        .hatchMark("ComponentsStartCard")
    }

    private func tile(_ t: ComponentTemplate, selected: Bool, recommended: Bool) -> some View {
        let system = t.system(name: project.name)
        let samples: [(String, String)] = [("bottomBar", "button"), ("listRow", "button"), ("inspector", "toggle")]
        return Button { chosen = t.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(t.title).font(.headline)
                    if recommended { Text("Recommended").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary)
                }
                ForEach(samples, id: \.0) { place, element in
                    if let role = ComponentRole.Importance.allCases.lazy.compactMap({ system.role(element: element, place: place, importance: $0) }).first {
                        RecipePlaceSample(place: place, role: role, recipe: nil, system: system)
                    }
                }
                Text(t.isShipped ? t.summary : "Yours. " + t.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            .padding(10)
            .frame(width: 290, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview

/// How the app looks (CP4): where the system stands, the window shell, and one card per place with its roles drawn.
struct ComponentsOverview: View {
    let project: Project
    let loaded: ComponentsView.Loaded
    let system: ComponentSystem
    let select: (String) -> Void
    let edit: ComponentsEdit
    let addTickets: () -> Void
    @EnvironmentObject var state: AppState

    private var places: [ComponentPlace] {
        system.allPlaces.filter { p in system.roles.contains { $0.places.contains(p.id) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            standing
            if let shell = system.shell { shellCard(shell) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(places) { ComponentPlaceCard(place: $0, system: system, uses: loaded.usesByRole, select: select) }
            }
        }
    }

    /// The state line: baseline, roles by status, what waits for the owner, and coverage.
    private var standing: some View {
        let c = system.counts
        let drafts = system.roles.filter { $0.draft != nil }
        let settings = system.roles.filter(\.configurable).count + system.rules.filter(\.configurable).count
        return HXCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 28) {
                    figure("\(c.agreed)", "Agreed")
                    figure("\(c.provisional)", "Provisional")
                    figure("\(c.inRedesign)", "In redesign")
                    figure("\(system.questions.count)", "To decide", turn: system.questions.isEmpty ? nil : .you)
                    if settings > 0 { figure("\(settings)", "Settings to build") }
                    Spacer(minLength: 0)
                }
                if let cov = loaded.coverage, cov.total > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(cov.usingRole), total: Double(cov.total))
                        Text("\(cov.usingRole) of \(cov.total) controls use a role; \(cov.matching) more already have their role's look and only need the swap.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                FlowLayout(spacing: 8) {
                    if !system.questions.isEmpty {
                        Button { state.openDecide(area: ComponentsSetup.area) } label: { Label("Decide \(system.questions.count)", systemImage: "checklist") }
                            .help("Answer the open questions one by one")
                    }
                    if !drafts.isEmpty {
                        Button { edit("apply the drafts of " + drafts.map(\.id).joined(separator: ", ")) { try $0.applyDrafts() } } label: {
                            Label("Apply \(drafts.count == 1 ? "the Draft" : "\(drafts.count) Drafts")", systemImage: "arrow.up.circle")
                        }
                        .help("Make the drafts the roles' looks: baseline v\(system.version + 1). " + drafts.map(\.title).joined(separator: ", "))
                    }
                    if let cov = loaded.coverage, cov.usingRole < cov.total {
                        Button(action: addTickets) { Label("Add Tickets to Put It in Place", systemImage: "plus") }
                            .help("Draft tickets: generate the role code, then move the screens onto the roles")
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func figure(_ value: String, _ title: String, turn: Turn? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                .foregroundStyle(turn.map { Theme.color(for: $0) } ?? .primary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func shellCard(_ shell: ComponentShell) -> some View {
        HXCard {
            HStack(spacing: 12) {
                Image(systemName: shell.navigation == .tabs ? "rectangle.split.3x1" : "sidebar.left").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Window").font(.headline)
                    Text(shell.summary).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { StageLauncher.shared.openDesigner(project: project, state: state) } label: { Label("Open Live Window", systemImage: "macwindow") }
                    .buttonStyle(.glass)
                    .help("The app's own window shell with the roles in it, in the Components Designer")
            }
        }
    }
}

/// One place with its roles drawn the way a screen shows them. A click on a control opens its role.
struct ComponentPlaceCard: View {
    let place: ComponentPlace
    let system: ComponentSystem
    let uses: [String: Int]
    let select: (String) -> Void

    private var roles: [ComponentRole] { componentRoles(in: place.id, system) }

    var body: some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(place.title).font(.headline)
                    Spacer()
                    let count = roles.reduce(0) { $0 + (uses[$1.id] ?? 0) }
                    if count > 0 { Text("\(count) in the app").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                }
                Text(place.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                surface
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .padding(10)
                    .clipped()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(roles.map { $0.title + ($0.followsMacOS ? " (macOS)" : "") + ($0.draft != nil ? " (draft waiting)" : "") }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .hatchMark("ComponentPlaceCard")
    }

    @ViewBuilder private var surface: some View {
        switch place.id {
        case "contextMenu", "menu":
            VStack(alignment: .leading, spacing: 3) {
                ForEach(roles) { r in
                    Text(SampleWords.content(r.importance, place: place.id, base: SampleContent()).shownTitle)
                        .foregroundStyle(r.importance == .destructive ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { select(r.id) }
                }
            }
        case "form", "inspector":
            VStack(alignment: .leading, spacing: 6) {
                ForEach(roles) { r in
                    LabeledContent(r.title) { tappable(r) }
                }
            }
        case let id where (id == "sheetFooter" || id == "alert") && roles.count <= 3:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(roles) { tappable($0) }
            }
        default:
            FlowLayout(spacing: 8) { ForEach(roles) { tappable($0) } }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The control as a picture: a click selects its role instead of pressing it.
    private func tappable(_ r: ComponentRole) -> some View {
        ComponentRoleSample(role: r, system: system, place: place.id)
            .allowsHitTesting(false)
            .overlay { Color.clear.contentShape(Rectangle()).onTapGesture { select(r.id) } }
            .help("\(r.title) (\(r.id)): \(r.use)")
    }
}

// MARK: - Roles

/// Every role, sortable (DESIGN: many records are a native table). Selecting one opens the inspector.
struct ComponentsRolesTable: View {
    let system: ComponentSystem
    let usesByRole: [String: Int]
    let filter: String
    @Binding var selection: String?
    @State private var sortOrder = [KeyPathComparator(\Row.order)]

    struct Row: Identifiable {
        let id: String
        let title: String
        let element: String
        let places: String
        let look: String
        let status: ComponentRole.Status
        let statusTitle: String
        let uses: Int
        let order: Int
    }

    private var rows: [Row] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        return system.roles.enumerated().compactMap { i, r in
            guard f.isEmpty || r.id.localizedCaseInsensitiveContains(f) || r.title.localizedCaseInsensitiveContains(f) || r.use.localizedCaseInsensitiveContains(f) else { return nil }
            return Row(id: r.id, title: r.title, element: ComponentElement.named(r.element)?.title ?? r.element,
                       places: r.places.map { ComponentPlace.title($0) }.joined(separator: ", "),
                       look: r.followsMacOS ? "Follows macOS" : r.lookSummary + (r.draft != nil ? " → draft" : ""),
                       status: r.status, statusTitle: r.status.title, uses: usesByRole[r.id] ?? 0, order: i)
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Role", value: \.title) { r in
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.title)
                    Text(r.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .width(min: 160, ideal: 220)
            TableColumn("Element", value: \.element) { r in Text(r.element).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 90, max: 130)
            TableColumn("Places", value: \.places) { r in Text(r.places).lineLimit(2).foregroundStyle(.secondary) }
                .width(min: 120, ideal: 200)
            TableColumn("Look", value: \.look) { r in Text(r.look).lineLimit(2) }
                .width(min: 140, ideal: 240)
            TableColumn("Status", value: \.statusTitle) { r in
                Label(r.statusTitle, systemImage: componentStatusSymbol(r.status)).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110, max: 130)
            TableColumn("Uses", value: \.uses) { r in Text(r.uses == 0 ? "–" : "\(r.uses)").monospacedDigit().foregroundStyle(.secondary) }
                .width(min: 40, ideal: 50, max: 70)
        }
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .hatchMark("ComponentsRolesTable")
    }
}

/// One role in the inspector: drawn today (and its draft), what it is for, its look with macOS's defaults, Apple's
/// pages, Hatch's native advice, the code that differs, and the actions on it.
struct ComponentRoleInspector: View {
    let role: ComponentRole
    let system: ComponentSystem
    let uses: Int
    let findings: [ComponentFinding]
    let edit: ComponentsEdit
    let change: () -> Void
    let makeSetting: (String) -> Void
    let openDesigner: () -> Void

    private var element: ComponentElement? { ComponentElement.named(role.element) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(role.title).font(.title3.weight(.semibold))
                    Text(role.codeName).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Label(role.status.title + (role.followsMacOS ? ", follows macOS" : ""), systemImage: componentStatusSymbol(role.status))
                        .font(.caption).foregroundStyle(.secondary)
                }
                preview
                actions
                VStack(alignment: .leading, spacing: 4) {
                    Text(role.use)
                    if !role.avoid.isEmpty { Text("Not for: \(role.avoid)").foregroundStyle(.secondary) }
                }
                .font(.callout)
                facts
                look
                if !role.variants.isEmpty { variants }
                advice
                sources
                if !findings.isEmpty { code }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 12) {
            sample("Today", role.recipe)
            if let draft = role.draft { sample("Draft", draft) }
        }
    }

    private func sample(_ title: String, _ recipe: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ComponentRoleSample(role: role, system: system, recipe: recipe)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// Change… goes through a Proposal (CP3); agreeing, applying, following macOS and settings are one click.
    private var actions: some View {
        FlowLayout(spacing: 6) {
            Button("Change…", action: change)
                .help("Ask for a new look: an agent offers two to four, you choose")
            if role.status == .provisional {
                Button("Agree") { edit("agree \(role.id)") { try $0.agree(role.id) } }
                    .help("Keep this look as it is; agents may rely on it")
            }
            if role.draft != nil {
                Button("Apply Draft") { edit("apply the draft of \(role.id)") { try $0.applyDrafts(role.id) } }
                    .help("Make the draft the role's look: baseline v\(system.version + 1)")
                Button("Discard Draft") { edit("keep \(role.id) as it is") { try $0.discardDraft(role.id) } }
            }
            Menu("More") {
                if !role.followsMacOS {
                    Button("Follow macOS") { edit("\(role.id) follows macOS") { try $0.followMacOS(role: role.id) } }
                }
                if !role.configurable { Button("Make It a Setting") { makeSetting(role.id) } }
                Button("Open in the Designer", action: openDesigner)
            }
            .menuStyle(.button).menuIndicator(.hidden).fixedSize()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledContent("Places", value: role.places.map { ComponentPlace.title($0) }.joined(separator: ", "))
            LabeledContent("Importance", value: role.importance.title)
            if let n = role.perScreen { LabeledContent("Per screen", value: "at most \(n)") }
            LabeledContent("In the app", value: uses == 0 ? "not used yet" : "\(uses) controls")
            if let d = role.decision { LabeledContent("Decided in", value: d) }
            if role.configurable { LabeledContent("Setting", value: "a ticket builds it") }
        }
        .font(.callout)
    }

    @ViewBuilder private var look: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(role.draft != nil ? "Look (draft)" : "Look").font(.headline)
            if role.followsMacOS {
                Text("Follows macOS: SwiftUI draws it as the system does in each version. The code sets only behaviour.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(element?.parameters ?? [], id: \.id) { p in
                if let value = (role.draft ?? role.recipe)[p.id] {
                    LabeledContent(p.title) {
                        Text(value + (p.systemDefault == value ? " (macOS default)" : p.systemDefault.map { ", macOS: \($0)" } ?? ""))
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var variants: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Variants").font(.headline)
            ForEach(role.variants) { v in
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.id).font(.callout.monospaced())
                    Text(v.use + " · " + ComponentRole.summary(v.recipe)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var advice: some View {
        let items = system.advice().filter { $0.role == role.id }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Native first").font(.headline)
                ForEach(items, id: \.message) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.message).font(.callout)
                        if let ref = ComponentNative.reference(a.source), let url = URL(string: ref.url) {
                            Link(ref.title, destination: url).font(.caption)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var sources: some View {
        let ids = role.sources + [element?.source].compactMap { $0 } + (element?.parameters.compactMap(\.source) ?? [])
        let refs = Array(NSOrderedSet(array: ids)).compactMap { ($0 as? String).flatMap(ComponentNative.reference) }
        if !refs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Why, from Apple").font(.headline)
                ForEach(refs) { ref in
                    if let url = URL(string: ref.url) { Link(ref.title, destination: url).font(.callout) }
                }
                Text("Checked \(ComponentNative.checkedOn) against the macOS \(ComponentNative.checkedSDK) SDK.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var code: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("In the code").font(.headline)
            Text("\(findings.count) to look at").font(.callout).foregroundStyle(.secondary)
            ForEach(Array(findings.prefix(6).enumerated()), id: \.offset) { _, f in
                Text("\(f.kind.title): \(f.location)").font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Rules

/// The rules (NF4), each with Apple's choice and its pages, and how often the code breaks it. Changing a rule is one
/// click: rules are words, not looks.
struct ComponentsRulesView: View {
    let system: ComponentSystem
    let findings: [ComponentFinding]
    let edit: ComponentsEdit
    let makeSetting: (String) -> Void
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HXCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ComponentRuleKind.catalog.enumerated()), id: \.element.id) { i, kind in
                        if i > 0 { Divider().padding(.vertical, 10) }
                        row(kind)
                    }
                }
            }
            notes
        }
    }

    private func row(_ kind: ComponentRuleKind) -> some View {
        let rule = system.rules.first { $0.kind == kind.id }
        let broken = findings.filter { $0.kind == .rule && $0.role == kind.id }.count
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(kind.title).font(.body.weight(.semibold))
                    if rule?.status == .provisional { Text("Provisional").font(.caption).foregroundStyle(.secondary) }
                    if rule?.configurable == true { Text("A setting").font(.caption).foregroundStyle(.secondary) }
                    if broken > 0 { Text("\(broken) in the code").font(.caption).foregroundStyle(Theme.critical) }
                }
                Text(rule?.text ?? "No rule yet.").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text(kind.appleDefault.map { rule?.value == $0 ? "Apple's choice." : "Apple: " + kind.says($0) } ?? "Apple leaves it to the app on macOS.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(kind.sources, id: \.self) { id in
                        if let ref = ComponentNative.reference(id), let url = URL(string: ref.url) { Link(ref.title, destination: url).font(.caption) }
                    }
                }
                if let caveat = kind.caveat { Text(caveat).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Picker(kind.title, selection: Binding(get: { rule?.value ?? "" }, set: { set(kind, $0) })) {
                if rule == nil { Text("No rule").tag("") }
                ForEach(kind.values, id: \.id) { v in
                    Text(pretty(v.id) + (kind.appleDefault == v.id ? " (Apple)" : "")).tag(v.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            if let rule {
                Menu {
                    if rule.status == .provisional {
                        Button("Agree") { edit("agree rule \(rule.id)") { s in if let i = s.rules.firstIndex(where: { $0.id == rule.id }) { s.rules[i].status = .agreed } } }
                    }
                    if !rule.configurable { Button("Make It a Setting") { makeSetting(rule.id) } }
                    Button("Remove the Rule", role: .destructive) { edit("remove rule \(rule.id)") { $0.rules.removeAll { $0.id == rule.id } } }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                    .help("More for this rule")
            }
        }
    }

    private func set(_ kind: ComponentRuleKind, _ value: String) {
        guard !value.isEmpty else { return }
        edit("rule \(kind.title.lowercased())") { s in
            s.rules.removeAll { $0.kind == kind.id }
            s.rules.append(ComponentRule(id: kind.id, kind: kind.id, value: value, text: kind.says(value), status: .agreed))
        }
    }

    /// Rules in the owner's own words: agents read them, Hatch does not check them.
    private var notes: some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your own rules").font(.headline)
                Text("In your words. Agents read them in every brief; Hatch cannot check them in code.").font(.caption).foregroundStyle(.secondary)
                ForEach(system.rules.filter { $0.kind == "note" }) { r in
                    HStack {
                        Text(r.text)
                        Spacer()
                        Button("Remove") { edit("remove rule \(r.id)") { $0.rules.removeAll { $0.id == r.id } } }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                HStack {
                    TextField("For example: never more than one glass bar per window", text: $note).textFieldStyle(.roundedBorder)
                        .onSubmit(addNote)
                    Button("Add", action: addNote).buttonStyle(.bordered).controlSize(.small)
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addNote() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        edit("add a rule") { s in
            let n = (s.rules.compactMap { r in r.kind == "note" ? Int(r.id.dropFirst(5)) : nil }.max() ?? 0) + 1
            s.rules.append(ComponentRule(id: "note-\(n)", kind: "note", value: "text", text: text, status: .agreed))
        }
        note = ""
    }

    /// "allOrNoneInGroup" reads "All or none in group".
    private func pretty(_ id: String) -> String {
        var out = ""
        for ch in id {
            if ch.isUppercase { out += " " + ch.lowercased() } else { out.append(ch) }
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}

// MARK: - Foundations

/// The named values (DS3): colors light beside dark, type in its own font, spacing and radii as bars.
struct ComponentsFoundationsView: View {
    let system: ComponentSystem
    let filter: String

    private func items(_ kind: ComponentFoundation.Kind) -> [ComponentFoundation] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        return system.foundations.filter { $0.kind == kind && (f.isEmpty || $0.id.localizedCaseInsensitiveContains(f) || $0.use.localizedCaseInsensitiveContains(f)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if system.foundations.isEmpty {
                HXCard {
                    Text("No named values yet. The system uses macOS's own colors, type and spacing; add one when the app needs its own.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(ComponentFoundation.Kind.allCases, id: \.self) { kind in
                let list = items(kind)
                if !list.isEmpty {
                    HXCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Text(kind.title).font(.headline)
                                Text("\(list.count)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            }
                            content(kind, list)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func content(_ kind: ComponentFoundation.Kind, _ list: [ComponentFoundation]) -> some View {
        switch kind {
        case .color:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(list) { f in
                    let c = ComponentRender.colors(f)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 0) {
                            Rectangle().fill(c.light)
                            if let dark = c.dark { Rectangle().fill(dark) }
                        }
                        .frame(height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                        Text(f.id).font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
                        Text(f.valueSummary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .help(f.use)
                }
            }
        case .text:
            ForEach(list) { f in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(f.use.isEmpty ? "The quick brown fox" : f.use).font(ComponentRender.font(f)).lineLimit(1)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(f.id).font(.caption.monospaced()).textSelection(.enabled)
                        Text(f.valueSummary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        case .space, .radius:
            let largest = max(1, list.compactMap(\.value).max() ?? 1)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(list) { f in
                    GridRow {
                        Text(f.id).font(.caption.monospaced()).textSelection(.enabled)
                        Text(f.valueSummary).font(.caption).monospacedDigit().foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        if kind == .radius {
                            RoundedRectangle(cornerRadius: CGFloat(f.value ?? 0)).strokeBorder(.secondary, lineWidth: 1).frame(width: 44, height: 28)
                        } else {
                            Capsule().fill(.quaternary).frame(width: max(2, 220 * CGFloat(min(f.value ?? 0, largest) / largest)), height: 6)
                        }
                        Text(f.use).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        case .material:
            ForEach(list) { f in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8).fill(.regularMaterial).frame(width: 44, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
                    Text(f.id).font(.caption.monospaced())
                    Text(f.valueSummary + " · " + f.use).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
