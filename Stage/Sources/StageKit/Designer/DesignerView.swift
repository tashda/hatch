import SwiftUI
import HatchCore
import HatchComponentKit

// The Components Designer's window (decision DS1): the system on the left, the selected element drawn in its places in
// the middle, the selected role on the right, and the open questions in a bar at the bottom. Native controls only.

struct DesignerView: View {
    @ObservedObject var model: DesignerModel
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            DesignerSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if let notice = model.notice {
                    Label(notice, systemImage: "exclamationmark.triangle").font(.callout)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.15))
                }
                ScrollView { main.padding(20) }
                if let element = model.selectedElement, !model.questions(for: element).isEmpty {
                    Divider()
                    QuestionBar(model: model, element: element)
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .inspector(isPresented: $showInspector) {
                RoleInspector(model: model)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
            }
        }
        .preferredColorScheme(model.dark ? .dark : nil)
        .dynamicTypeSize(model.largeText ? .xxLarge : .large)
    }

    private var title: String {
        switch model.selection {
        case .element(let e)?: ComponentElement.named(e)?.plural ?? e
        case .foundations(let kind)?: kind.title
        case .rules?: "Rules"
        case nil: model.appName
        }
    }

    private var subtitle: String {
        let c = model.system.counts
        return "\(model.appName) · baseline v\(model.system.version) · \(c.agreed) agreed, \(c.provisional) provisional"
            + (c.inRedesign > 0 ? ", \(c.inRedesign) in redesign" : "") + (model.source.isLocal ? " · not saved (no Hatch)" : "")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $model.mode) {
                ForEach(DesignerMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.selectedElement == nil)
        }
        ToolbarItem {
            Menu {
                Toggle("Long label", isOn: $model.sample.longLabel)
                Toggle("Disabled", isOn: $model.sample.disabled)
                Toggle("Dark", isOn: $model.dark)
                Toggle("Large text", isOn: $model.largeText)
            } label: {
                Label("Hard Cases", systemImage: "slider.horizontal.3")
            }
            .help("Draw every place with a long label, disabled, dark or with large text")
        }
        ToolbarItem {
            Button { model.openLiveWindow?() } label: { Label("Live Window", systemImage: "macwindow") }
                .help("Open \(model.appName)'s own window shell with the roles in it, drawn by SwiftUI itself")
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                .help("Show or hide the role (⌥⌘I)")
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    @ViewBuilder private var main: some View {
        switch model.selection {
        case .foundations(let kind)?:
            FoundationsView(model: model, kind: kind)
        case .rules?:
            RulesView(model: model)
        case .element(let e)?:
            switch model.mode {
            case .inPlace: RoleInPlaceView(model: model, element: e)
            case .matrix: RoleMatrixView(model: model, element: e)
            case .today: RoleTodayView(model: model)
            }
        case nil:
            ContentUnavailableView("Choose an element", systemImage: "square.grid.2x2", description: Text("Pick an element on the left to see its roles in their places."))
        }
    }
}

// MARK: - Sidebar

struct DesignerSidebar: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Elements") {
                ForEach(model.system.elementsUsed, id: \.self) { e in
                    HStack {
                        StatusDot(status: model.state(of: e))
                        Text(ComponentElement.named(e)?.plural ?? e)
                        Spacer()
                        let open = model.openCount(e)
                        if open > 0 {
                            Text("\(open)").font(.caption.weight(.semibold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .help("\(open) to decide")
                        }
                    }
                    .tag(DesignerSelection.element(e))
                }
            }
            Section("Rules") {
                Label("Rules", systemImage: "checklist").badge(model.system.rules.filter { !$0.isOff }.count).tag(DesignerSelection.rules)
            }
            Section("Foundations") {
                ForEach(ComponentFoundation.Kind.allCases, id: \.self) { kind in
                    let count = model.system.foundations.filter { $0.kind == kind }.count
                    if count > 0 {
                        Label(kind.title, systemImage: Self.symbol(kind)).badge(count).tag(DesignerSelection.foundations(kind))
                    }
                }
            }
        }
        .onChange(of: model.selection) { _, new in
            if case .element(let e)? = new, model.role?.element != e { model.selectedRole = model.system.roles(of: e).first?.id }
        }
    }

    static func symbol(_ kind: ComponentFoundation.Kind) -> String {
        switch kind {
        case .color: "paintpalette"
        case .text: "textformat"
        case .space: "arrow.left.and.right"
        case .radius: "square.on.square"
        case .material: "square.stack.3d.down.forward"
        }
    }
}

/// Agreed green, provisional grey, in redesign amber.
struct StatusDot: View {
    let status: ComponentRole.Status?
    var body: some View {
        Circle()
            .fill(status == .agreed ? Color.green : status == .inRedesign ? Color.orange : Color.secondary.opacity(0.5))
            .frame(width: 7, height: 7)
            .help(status?.title ?? "No roles")
    }
}

// MARK: - In place

struct RoleInPlaceView: View {
    @ObservedObject var model: DesignerModel
    let element: String

    var body: some View {
        let places = model.system.allPlaces.filter { p in model.system.roles(of: element).contains { $0.places.contains(p.id) } }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
            ForEach(places) { place in
                PlaceFrame(place: place, element: element, model: model)
            }
        }
    }
}

// MARK: - Matrix

struct RoleMatrixView: View {
    @ObservedObject var model: DesignerModel
    let element: String

    var body: some View {
        let m = model.system.matrix(element: element)
        VStack(alignment: .leading, spacing: 12) {
            Text("Which role where: places down, importance across. An empty cell is not decided yet; the first ticket that needs it asks.")
                .font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Place").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(m.importances, id: \.self) { Text($0.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                }
                Divider()
                ForEach(Array(m.places.enumerated()), id: \.offset) { row, place in
                    GridRow {
                        Text(place.title)
                        ForEach(Array(m.cells[row].enumerated()), id: \.offset) { _, role in
                            if let role {
                                Button { model.selectedRole = role.id } label: {
                                    HStack(spacing: 6) {
                                        StatusDot(status: role.status)
                                        Text(role.name).font(.callout.monospaced())
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(model.selectedRole == role.id ? .accentColor : nil)
                            } else {
                                Text("not decided").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Today vs draft

struct RoleTodayView: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        if let role = model.role {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("In the app today").font(.headline)
                    let looks = model.looksToday(role)
                    if looks.isEmpty {
                        Text(model.inventory == nil ? "Open the Designer with the app's folder to see what the app uses." : "Not used in the app yet.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(Array(looks.prefix(6).enumerated()), id: \.offset) { _, look in
                        HStack(alignment: .top, spacing: 12) {
                            RecipeControl(element: role.element, recipe: look.look, system: model.system, importance: role.importance,
                                          sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: model.sample))
                                .frame(minWidth: 140, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(look.count) use\(look.count == 1 ? "" : "s")").font(.callout.weight(.medium))
                                Text(ComponentRole.summary(look.look)).font(.caption).foregroundStyle(.secondary)
                                Text(look.examples.joined(separator: ", ")).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text(role.draft == nil ? "The role" : "Now and the draft").font(.headline)
                    lookRow("Now", role.recipe, role)
                    if let draft = role.draft { lookRow("Draft", draft, role) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Choose a role", systemImage: "hand.tap", description: Text("Tap a control in In Place, or a cell in Matrix."))
        }
    }

    private func lookRow(_ title: String, _ recipe: [String: String], _ role: ComponentRole) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RecipeControl(element: role.element, recipe: recipe, system: model.system, importance: role.importance,
                          sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: model.sample))
                .frame(minWidth: 140, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(ComponentRole.summary(recipe)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Foundations

struct FoundationsView: View {
    @ObservedObject var model: DesignerModel
    let kind: ComponentFoundation.Kind

    var body: some View {
        let list = model.system.foundations.filter { $0.kind == kind }
        VStack(alignment: .leading, spacing: 14) {
            ForEach(list) { f in
                HStack(alignment: .center, spacing: 16) {
                    sample(f).frame(width: 120, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.id).font(.callout.monospaced())
                        Text(f.use).font(.caption).foregroundStyle(.secondary)
                        Text(f.valueSummary).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func sample(_ f: ComponentFoundation) -> some View {
        switch f.kind {
        case .color:
            RoundedRectangle(cornerRadius: 6).fill(RecipeColor.color(f.id, system: model.system)).frame(width: 60, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
        case .text:
            Text("Aa Title").font(font(f))
        case .space:
            Capsule().fill(Color.accentColor.opacity(0.6)).frame(width: CGFloat(f.value ?? 0), height: 8)
        case .radius:
            RoundedRectangle(cornerRadius: CGFloat(f.value ?? 0)).strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 60, height: 40)
        case .material:
            Text(f.system ?? "").font(.caption).padding(8).glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }

    private func font(_ f: ComponentFoundation) -> Font {
        let styles: [String: Font.TextStyle] = ["largeTitle": .largeTitle, "title": .title, "title2": .title2, "title3": .title3, "headline": .headline,
                                                 "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote,
                                                 "caption": .caption, "caption2": .caption2]
        let weights: [String: Font.Weight] = ["semibold": .semibold, "bold": .bold, "medium": .medium, "regular": .regular, "light": .light]
        var font = f.system.flatMap { styles[$0] }.map { Font.system($0) } ?? .system(size: CGFloat(f.value ?? 13))
        if let w = f.weight.flatMap({ weights[$0] }) { font = font.weight(w) }
        if f.design == "monospaced" { font = font.monospaced() }
        return font
    }
}

// MARK: - The role

struct RoleInspector: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        if let role = model.role, let element = ComponentElement.named(role.element) {
            Form {
                Section {
                    LabeledContent("Role") { Text(role.id).font(.callout.monospaced()) }
                    LabeledContent("Status") {
                        HStack { StatusDot(status: role.status); Text(role.status.title + (role.followsMacOS ? ", follows macOS" : "")) }
                    }
                    LabeledContent("Code") { Text(role.codeName).font(.caption.monospaced()).textSelection(.enabled) }
                } header: { Text(role.title) }
                Section("Use when") {
                    Text(role.use)
                    if !role.avoid.isEmpty { Text("Not when: \(role.avoid)").foregroundStyle(.secondary) }
                    Text(role.places.map { model.system.place($0)?.title ?? $0 }.joined(separator: ", ")
                         + (role.perScreen.map { "; at most \($0) per screen" } ?? "")).font(.caption).foregroundStyle(.secondary)
                }
                Section(role.draft == nil ? "Look" : "Look (draft)") {
                    let recipe = role.draft ?? role.recipe
                    ForEach(element.parameters, id: \.id) { p in
                        LabeledContent(p.title) {
                            HStack(spacing: 4) {
                                Button { model.step(p, by: -1) } label: { Image(systemName: "chevron.left") }
                                    .buttonStyle(.borderless).help("Previous \(p.title.lowercased())")
                                Text(recipe[p.id] ?? "–").font(.callout.monospaced()).frame(minWidth: 96)
                                    .foregroundStyle(recipe[p.id] == nil ? .tertiary : .primary)
                                Button { model.step(p, by: 1) } label: { Image(systemName: "chevron.right") }
                                    .buttonStyle(.borderless).help("Next \(p.title.lowercased())")
                            }
                        }
                    }
                    if role.status == .agreed { Text("Changing an agreed role makes a draft; it changes every screen only when applied.").font(.caption).foregroundStyle(.secondary) }
                }
                if !role.variants.isEmpty {
                    Section("Variants") {
                        ForEach(role.variants) { v in
                            VStack(alignment: .leading) {
                                Text(v.id).font(.callout.monospaced())
                                Text(v.use).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                let advice = model.advice(for: role)
                if !advice.isEmpty {
                    Section("Against Apple's guidance") {
                        ForEach(Array(advice.enumerated()), id: \.offset) { _, a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.message).font(.callout)
                                if let ref = ComponentNative.reference(a.source), let url = URL(string: ref.url) { Link(ref.title, destination: url).font(.caption) }
                            }
                        }
                    }
                }
                if !role.sources.isEmpty {
                    Section("Why, from Apple") {
                        ForEach(role.sources.compactMap { ComponentNative.reference($0) }) { ref in
                            if let url = URL(string: ref.url) {
                                LabeledContent { Text("read \(ref.checked), macOS \(ref.sdk)").font(.caption).foregroundStyle(.secondary) } label: {
                                    Link(ref.title, destination: url)
                                }
                            }
                        }
                    }
                }
                if model.inventory != nil {
                    Section("In the app today") {
                        let looks = model.looksToday(role)
                        let total = looks.reduce(0) { $0 + $1.count }
                        Text(total == 0 ? "Not used yet." : "\(total) uses, \(looks.count) look\(looks.count == 1 ? "" : "s").")
                        if total > 0 { Button("Compare with Today") { model.mode = .today }.buttonStyle(.link) }
                    }
                }
                Section {
                    actions(role)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No role chosen", systemImage: "hand.tap", description: Text("Tap a control to see its role."))
        }
    }

    /// One prominent action, the rest quiet.
    @ViewBuilder private func actions(_ role: ComponentRole) -> some View {
        HStack {
            if !role.followsMacOS {
                Button("Follow macOS") { model.follow(role) }.buttonStyle(.glass)
                    .help("No look of its own: macOS decides, now and in later versions")
            }
            if !role.configurable {
                Button("Make It a Setting") { model.makeSetting(role.id) }.buttonStyle(.glass)
                    .help("Keep this look as the default and draft a ticket for a setting in the app")
            } else {
                Text("Will become a setting").font(.caption).foregroundStyle(.secondary)
            }
        }
        switch role.status {
        case .provisional:
            Button("Agree to This Role") { model.agree(role) }.buttonStyle(.glassProminent).controlSize(.large)
        case .inRedesign:
            HStack {
                Button("Discard Draft") { model.discard(role) }.buttonStyle(.glass)
                Spacer()
                Button("Apply Draft") { model.apply(role) }.buttonStyle(.glassProminent).controlSize(.large)
            }
        case .agreed:
            Text("Agreed\(role.decision.map { " in \($0)" } ?? ""). Step a setting above to draft a change.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Questions

struct QuestionBar: View {
    @ObservedObject var model: DesignerModel
    let element: String
    @State private var index = 0
    @State private var choice: Int?
    @State private var asSetting = false

    var body: some View {
        let questions = model.questions(for: element)
        let q = questions[min(index, questions.count - 1)]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(questions.count) to decide").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Text(q.title).font(.headline).lineLimit(1)
                Spacer()
                if questions.count > 1 {
                    Button { index = (index + questions.count - 1) % questions.count; choice = nil } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Button { index = (index + 1) % questions.count; choice = nil } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                        OptionCard(model: model, question: q, option: option, index: i, selected: (choice ?? q.recommended) == i)
                            .onTapGesture { choice = i }
                    }
                }
            }
            HStack {
                Text(q.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Toggle("and make it a setting", isOn: $asSetting).toggleStyle(.checkbox)
                    .help("Keep this choice as the default and draft a ticket for a setting in the app")
                Button("Answer") {
                    model.answer(q, option: choice ?? q.recommended, setting: asSetting)
                    choice = nil; index = 0; asSetting = false
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(.background.secondary)
        .onChange(of: q.role) { _, role in if let role { model.selectedRole = role } }
    }
}

struct OptionCard: View {
    @ObservedObject var model: DesignerModel
    let question: ComponentQuestion
    let option: ComponentQuestion.Option
    let index: Int
    let selected: Bool

    var body: some View {
        let role = question.role.flatMap { model.system.role($0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(index + 1)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                if index == question.recommended {
                    Text("Recommended").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
            }
            if let recipe = option.recipe, let role {
                RecipeControl(element: role.element, recipe: recipe, system: model.system, importance: role.importance,
                              sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: model.sample))
                    .allowsHitTesting(false)
                    .frame(height: 36, alignment: .leading)
            } else {
                Text(option.title).font(.callout.weight(.medium)).frame(height: 36, alignment: .leading)
            }
            Text(option.recipe == nil ? option.effect : option.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if option.count > 0 { Text("\(option.count) uses").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(10)
        .frame(width: 210, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Rules

/// The rules beyond roles (NF4): each with Apple's choice marked, its pages, and whether Hatch checks it.
struct RulesView: View {
    @ObservedObject var model: DesignerModel
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What roles cannot say: how menus are grouped, how titles are written, where commands live, which colours and spacing. Hatch checks the ones marked; notes are read by agents and Iris.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(ComponentRuleKind.catalog.filter { $0.id != "note" }) { kind in
                let rule = model.system.rules.first { $0.kind == kind.id }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(kind.title).font(.headline)
                        if kind.checked { Text("checked").font(.caption2).foregroundStyle(.secondary) }
                        if rule?.configurable == true { Text("will become a setting").font(.caption2).foregroundStyle(.orange) }
                        Spacer()
                        Picker(kind.title, selection: Binding(get: { rule?.value ?? "off" }, set: { model.setRule(kind.id, $0) })) {
                            ForEach(kind.values, id: \.id) { v in
                                Text(v.id == kind.appleDefault ? "\(v.id) (Apple)" : v.id).tag(v.id)
                            }
                            if !kind.values.contains(where: { $0.id == "off" }) { Text("off").tag("off") }
                        }
                        .labelsHidden().fixedSize()
                        if rule?.configurable != true, rule.map({ !$0.isOff }) == true {
                            Button("Make It a Setting") { model.makeSetting(kind.id) }.controlSize(.small)
                        }
                    }
                    Text(kind.says(rule?.value ?? kind.appleDefault ?? "off")).font(.callout)
                    if let caveat = kind.caveat { Text(caveat).font(.caption).foregroundStyle(.orange) }
                    HStack(spacing: 10) {
                        ForEach(kind.sources.compactMap { ComponentNative.reference($0) }) { ref in
                            if let url = URL(string: ref.url) { Link(ref.title, destination: url).font(.caption) }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes").font(.headline)
                ForEach(model.system.rules.filter { $0.kind == "note" }) { r in
                    HStack { Text(r.text); Spacer(); Button("Remove") { model.removeRule(r.id) }.controlSize(.small) }
                }
                HStack {
                    TextField("A rule in words, for agents and Iris", text: $note)
                    Button("Add") { model.addNote(note); note = "" }.disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if !model.system.follows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Following macOS").font(.headline)
                    ForEach(model.system.follows) { f in
                        HStack { Text(f.title); Spacer(); Button("Stop Following") { model.unfollow(f) }.controlSize(.small) }
                    }
                }
            }
        }
    }
}
