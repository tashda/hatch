import SwiftUI
import HatchCore
import HatchComponentKit

// The Components Designer's window (decisions DS1, CD7): the system on the left, the selected element drawn in its places
// in the middle, the selected role on the right. Questions are answered in the role's inspector (CD27), a look is tried
// everywhere before it is kept (CD13), and an element opens into one role drawn in every place it sits (CD8).

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
                if model.selectedElement != nil {
                    HardCasesBar(model: model)
                    Divider()
                }
                ScrollView { main.padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                    .modifier(CanvasLook(model: model))
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .inspector(isPresented: $showInspector) {
                inspector
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
            }
        }
        .background { keys }
    }

    @ViewBuilder private var inspector: some View {
        switch model.selection {
        case .element(let e)?:
            if model.focused, let role = model.role { RoleInspector(model: model, role: role) } else { ElementInspector(model: model, element: e) }
        case .rules?:
            ContentUnavailableView("Rules", systemImage: "checklist", description: Text("Choose a value beside a rule; Hatch checks the ones marked."))
        case .foundations(let kind)?:
            ContentUnavailableView(kind.title, systemImage: DesignerSidebar.symbol(kind), description: Text("Named values the roles use."))
        case nil:
            EmptyView()
        }
    }

    private var title: String {
        switch model.selection {
        case .element(let e)?: ComponentElement.named(e)?.plural ?? e
        case .foundations(let kind)?: kind.title
        case .rules?: "Rules"
        case nil: model.appName
        }
    }

    /// Short, so it is never cut off (B12): what waits, what is still a guess.
    private var subtitle: String {
        let c = model.system.counts
        var parts: [String] = []
        if !model.system.questions.isEmpty { parts.append("\(model.system.questions.count) to decide") }
        parts.append("\(c.provisional) provisional")
        if c.inRedesign > 0 { parts.append("\(c.inRedesign) in redesign") }
        if model.source.isLocal { parts.append("not saved") }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // The view switch only where it means something (B5, CD10): an element, not a role, rules or foundations.
        if model.selectedElement != nil && !model.focused {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.mode) {
                    ForEach(DesignerMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        ToolbarItem {
            let n = model.system.questions.count
            Button { model.nextQuestion() } label: { Label("\(n) to Decide", systemImage: "questionmark.bubble") }
                .labelStyle(.titleAndIcon)
                .disabled(n == 0)
                .help("Go to the next question, in any element (⌘])")
        }
        ToolbarItem {
            Button { model.openLiveWindow?() } label: { Label("Live Window", systemImage: "macwindow") }
                .help("Open \(model.appName)'s own window shell with the roles in it, drawn by SwiftUI itself")
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                .help("Show or hide the inspector (⌥⌘I)")
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    /// The keyboard (CD39): Return keeps, Esc discards or goes back, ⌘Z undoes, ⌘] and ⌘[ walk the questions, ⌘1 and ⌘2 the views.
    private var keys: some View {
        Group {
            Button("Keep") { model.keep() }.keyboardShortcut(.defaultAction).disabled(model.preview == nil)
            Button("Back") { if model.preview != nil { model.discard() } else { model.back() } }.keyboardShortcut(.cancelAction)
            Button("Undo") { model.undo() }.keyboardShortcut("z", modifiers: .command).disabled(model.undoStack.isEmpty)
            Button("Next Question") { model.nextQuestion() }.keyboardShortcut("]", modifiers: .command)
            Button("Previous Question") { model.nextQuestion(forward: false) }.keyboardShortcut("[", modifiers: .command)
            Button("In Place") { model.back(); model.mode = .inPlace }.keyboardShortcut("1", modifiers: .command)
            Button("Matrix") { model.back(); model.mode = .matrix }.keyboardShortcut("2", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    @ViewBuilder private var main: some View {
        switch model.selection {
        case .foundations(let kind)?:
            FoundationsView(model: model, kind: kind)
        case .rules?:
            RulesView(model: model)
        case .element(let e)?:
            if model.focused, let role = model.role, role.element == e {
                RoleView(model: model, role: role)
            } else {
                switch model.mode {
                case .inPlace: RoleInPlaceView(model: model, element: e)
                case .matrix: RoleMatrixView(model: model, element: e)
                }
            }
        case nil:
            ContentUnavailableView("Choose an element", systemImage: "square.grid.2x2", description: Text("Pick an element on the left to see its roles in their places."))
        }
    }
}

// MARK: - Hard cases (CD15)

/// Light, dark or both, long label, disabled, larger text and an inactive window, for the canvas only.
struct HardCasesBar: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        HStack(spacing: 14) {
            Picker("Appearance", selection: $model.appearance) {
                ForEach(DesignerAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Toggle("Long Label", isOn: $model.sample.longLabel)
            Toggle("Disabled", isOn: $model.sample.disabled)
            Toggle("Larger Text", isOn: $model.largeText)
            Toggle("Inactive Window", isOn: $model.inactive)
            Spacer()
            if let label = model.undoLabel {
                Button("Undo \(label)") { model.undo() }.buttonStyle(.link).lineLimit(1)
                    .help("⌘Z")
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 7)
    }
}

/// The canvas's hard cases: its appearance, text size and window state, never the inspector's.
struct CanvasLook: ViewModifier {
    @ObservedObject var model: DesignerModel
    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, model.appearance == .dark ? .dark : model.appearance == .light ? .light : model.systemScheme)
            .dynamicTypeSize(model.largeText ? .xxLarge : .large)
            .environment(\.controlActiveState, model.inactive ? .inactive : .key)
            .background(model.appearance == .dark ? Color.black.opacity(0.85) : model.appearance == .light ? Color.white : Color.clear)
    }
}

/// A place drawn once, or in light and dark side by side when the canvas shows Both.
struct Appearances<Content: View>: View {
    @ObservedObject var model: DesignerModel
    @ViewBuilder var content: () -> Content
    var body: some View {
        if model.appearance == .both {
            HStack(alignment: .top, spacing: 10) {
                content().padding(8).environment(\.colorScheme, .light).background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                content().padding(8).environment(\.colorScheme, .dark).background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            }
        } else {
            content()
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
                    let open = model.openCount(e)
                    HStack {
                        Text(ComponentElement.named(e)?.plural ?? e)
                        Spacer()
                        // Only what differs is marked (CD41): a check when every role is agreed.
                        if open == 0 && model.state(of: e) == .agreed { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary) }
                    }
                    .badge(open)
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
            model.back()
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

// MARK: - In place (the element's level)

struct RoleInPlaceView: View {
    @ObservedObject var model: DesignerModel
    let element: String

    var body: some View {
        let places = model.system.allPlaces.filter { p in model.system.roles(of: element).contains { $0.places.contains(p.id) } }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: model.appearance == .both ? 560 : 340), spacing: 24, alignment: .top)], alignment: .leading, spacing: 28) {
            ForEach(places) { place in
                PlaceFrame(place: place, element: element, model: model)
            }
        }
    }
}

// MARK: - A role, in every place it sits (CD8, CD14)

struct RoleView: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Button { model.back() } label: { Label(ComponentElement.named(role.element)?.plural ?? role.element, systemImage: "chevron.left") }
                    .buttonStyle(.link)
                    .help("Back to every place (Esc)")
                Text(role.title).font(.title3.weight(.semibold))
                Text("in \(role.places.count) place\(role.places.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                if let p = model.preview, p.role == role.id {
                    Text("Preview: \(p.label)").font(.callout).foregroundStyle(.orange)
                    Button("Discard") { model.discard() }
                    Button("Keep") { model.keep() }.buttonStyle(.borderedProminent)
                }
            }
            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 20) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(model.isPreviewing(role) ? "Preview" : role.draft != nil ? "Draft" : "Draft (as today)")
                        .font(.caption.weight(.semibold)).foregroundStyle(model.isPreviewing(role) ? .orange : .secondary)
                }
                ForEach(role.places, id: \.self) { id in
                    let place = model.system.place(id) ?? ComponentPlace(id, id, "")
                    GridRow {
                        Text(place.title).font(.headline).frame(width: 110, alignment: .leading).help(place.summary)
                        Appearances(model: model) { PlaceFrame(place: place, element: role.element, model: model, focus: role.id, today: true, framed: false) }
                        Appearances(model: model) { PlaceFrame(place: place, element: role.element, model: model, focus: role.id, framed: false) }
                    }
                }
            }
            let looks = model.looksToday(role)
            if looks.count > 1 {
                Divider()
                Text("Also in the app today").font(.headline)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(looks.prefix(8).enumerated()), id: \.offset) { _, look in
                            VStack(alignment: .leading, spacing: 4) {
                                RecipeControl(element: role.element, recipe: look.look, system: model.system, importance: role.importance,
                                              sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: model.sample))
                                    .allowsHitTesting(false)
                                Text("\(look.count) use\(look.count == 1 ? "" : "s")").font(.caption.weight(.medium))
                                Text(look.examples.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(width: 170, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { model.tryLook(DesignerPreview(role: role.id, recipe: look.look, label: "\(look.count) uses today")) }
                            .help("Try this look everywhere")
                        }
                    }
                }
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
                                Button { model.open(role.id) } label: {
                                    VStack(spacing: 4) {
                                        RecipeControl(element: role.element, recipe: model.look(of: role), system: model.system, importance: role.importance,
                                                      sample: SampleWords.content(role.importance, place: place.id, base: model.sample))
                                            .allowsHitTesting(false)
                                        Text(role.title).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Open \(role.title)")
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

// MARK: - The role (CD17: decide first, detail folded)

/// A grouped box like a Form section, but not a Form: a Form restyles the controls drawn in it (a toggle becomes a switch),
/// and the inspector draws looks as they are in their places.
struct InspectorSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4) }
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4) }
        }
    }
}

struct RoleInspector: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole
    @State private var asking = false
    @State private var what = ""

    private var element: ComponentElement? { ComponentElement.named(role.element) }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            InspectorSection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(role.title).font(.title3.weight(.semibold))
                    Text(statusLine).font(.callout).foregroundStyle(.secondary)
                    Text(role.places.map { model.system.place($0)?.title ?? $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            if let finding {
                InspectorSection { AppleCallout(model: model, role: role, advice: finding) }
            }
            if let q = model.question(for: role) {
                QuestionPicks(model: model, role: role, question: q)
            } else {
                LookPicks(model: model, role: role)
            }
            if let element {
                FineTune(model: model, role: role, element: element)
            }
            InspectorSection(title: "Use When") {
                Text(role.use)
                if !role.avoid.isEmpty { Text("Not when: \(role.avoid)").foregroundStyle(.secondary) }
                if let n = role.perScreen { Text("At most \(n) per screen.").font(.caption).foregroundStyle(.secondary) }
            }
            if !role.variants.isEmpty {
                InspectorSection(title: "Variants") {
                    ForEach(role.variants) { v in
                        VStack(alignment: .leading) {
                            Text(v.id).font(.callout)
                            Text(v.use).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if model.inventory != nil {
                InspectorSection(title: "In the App Today") {
                    let looks = model.looksToday(role)
                    let total = looks.reduce(0) { $0 + $1.count }
                    Text(total == 0 ? "Not used yet." : "\(total) uses, \(looks.count) look\(looks.count == 1 ? "" : "s").")
                }
            }
            InspectorSection {
                sources
                LabeledContent("Code") { Text(role.codeName).font(.caption.monospaced()).textSelection(.enabled) }
                    .help(role.id)
            }
            footer
        }
        .padding(14) }
        .popover(isPresented: $asking) { ask }
    }

    private var statusLine: String {
        var s = role.status.title
        if role.followsMacOS { s += ", follows macOS" }
        if role.configurable { s += ", people choose it in Settings" }
        return s
    }

    /// The first real problem with the look shown now (CD35: settings macOS uses anyway are cleaned up on save, not shown).
    private var finding: ComponentAdvice? {
        var system = model.system
        if let i = system.roles.firstIndex(where: { $0.id == role.id }) {
            system.roles[i].recipe = model.look(of: role)
            system.roles[i].draft = nil
            if model.preview?.follow == true, model.isPreviewing(role) { system.roles[i].followsMacOS = true }
        }
        return system.advice().first { $0.role == role.id && $0.kind != .redundant }
    }

    @ViewBuilder private var sources: some View {
        let refs = role.sources.compactMap { ComponentNative.reference($0) }
        if !refs.isEmpty {
            LabeledContent("Apple") {
                HStack(spacing: 10) {
                    ForEach(refs) { ref in
                        if let url = URL(string: ref.url) { Link(ref.title, destination: url).help("Read \(ref.checked), macOS \(ref.sdk)") }
                    }
                }
                .font(.caption)
            }
        }
    }

    /// One prominent action; the rest in a menu (CD17).
    @ViewBuilder private var footer: some View {
        HStack {
            Menu {
                if !role.followsMacOS {
                    Button("Follow macOS") { model.tryLook(DesignerPreview(role: role.id, recipe: behaviour, follow: true, label: "Follow macOS")) }
                }
                if !model.source.isLocal { Button("Ask an Agent for New Looks…") { asking = true } }
                Divider()
                let advice = ComponentWords.settingAdvice(element: role.element)
                if !role.configurable {
                    Button(advice.offer ? "Let People Choose in Settings… (recommended)" : "Let People Choose in Settings…") { model.makeSetting(role.id) }
                        .help((advice.offer ? "Recommended. " : "Not recommended. ") + advice.reason + " Keeps this look as the default and drafts a ticket for a setting in the app.")
                }
                Button("Copy Code Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(role.codeName, forType: .string)
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).fixedSize()
                .help("More for this role")
            Spacer()
            if model.isPreviewing(role) {
                Button("Discard") { model.discard() }
                Button("Keep") { model.keep() }.buttonStyle(.borderedProminent).help("Save this look (Return)")
            } else if let q = model.question(for: role) {
                Button("Answer") {
                    let i = q.recommended
                    model.tryLook(preview(for: q, option: i))
                    model.keep()
                }
                .buttonStyle(.borderedProminent)
                .help("Answer with the recommendation; choose another option above to try it first")
            } else {
                switch role.status {
                case .provisional: Button("Agree") { model.agree(role) }.buttonStyle(.borderedProminent).help("Make this look the rule")
                case .inRedesign:
                    Button("Discard Draft") { model.discard(role) }
                    Button("Apply Draft") { model.apply(role) }.buttonStyle(.borderedProminent)
                case .agreed: Text("Agreed").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var behaviour: [String: String] { role.recipe.filter { element?.parameter($0.key)?.isLook == false } }

    func preview(for q: ComponentQuestion, option i: Int) -> DesignerPreview {
        let o = q.options[i]
        return DesignerPreview(role: role.id, recipe: o.recipe ?? (o.follow == true ? behaviour : role.recipe), follow: o.follow == true, option: i,
                               label: o.recipe.map { ComponentWords.look(element: role.element, recipe: element?.look($0) ?? $0) } ?? o.title)
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should change?").font(.headline)
            TextField("For example: calmer, without glass", text: $what, axis: .vertical).lineLimit(2...5).frame(width: 300)
            Text("An agent offers two to four looks; they come back here as a question.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("File the Proposal") { model.change(role, what: what); what = ""; asking = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(what.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }
}

/// Apple's guidance as a callout with its fix (CD34).
struct AppleCallout: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole
    let advice: ComponentAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(heading, systemImage: "exclamationmark.triangle.fill").font(.callout.weight(.semibold)).foregroundStyle(.orange)
            Text(advice.message.replacingOccurrences(of: "\(role.id) ", with: "This role ")).font(.callout)
            HStack {
                if let fix { Button(fix.title) { model.tryLook(DesignerPreview(role: role.id, recipe: fix.recipe, follow: fix.follow, label: fix.title)) } }
                if let ref = ComponentNative.reference(advice.source), let url = URL(string: ref.url) { Link(ref.title, destination: url).font(.caption) }
            }
        }
    }

    private var heading: String {
        switch advice.kind {
        case .glassInContent: "Glass in content"
        case .systemPlace: "macOS draws this here"
        case .wrongDefault: "Not a default button"
        case .switcherInContent: "A switcher in the content"
        case .redundant: "Repeats macOS"
        }
    }

    /// The one-click fix, when there is a clear one.
    private var fix: (title: String, recipe: [String: String], follow: Bool)? {
        var r = model.look(of: role)
        switch advice.kind {
        case .glassInContent:
            if r["style"] == "glassProminent" { r["style"] = "borderedProminent"; return ("Use Filled Instead", r, false) }
            if r["style"] == "glass" { r["style"] = "bordered"; return ("Use Bordered Instead", r, false) }
            if r["surface"] == "glass" { r["surface"] = "material"; return ("Use Material Instead", r, false) }
            if r["look"] == "glass" { r["look"] = nil; return ("Use the macOS Default", r, false) }
            return nil
        case .systemPlace:
            return ("Follow macOS", r.filter { ComponentElement.named(role.element)?.parameter($0.key)?.isLook == false }, true)
        case .wrongDefault:
            r["key"] = nil; return ("Remove the Return Key", r, false)
        case .switcherInContent:
            r["style"] = "tabs"; return ("Use Tabs Instead", r, false)
        case .redundant:
            return nil
        }
    }
}

/// The open question as a list of drawn looks, recommended first, Follow macOS and Not sure yet as quiet rows (CD27, CD30).
struct QuestionPicks: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole
    let question: ComponentQuestion

    var body: some View {
        InspectorSection(title: "To Decide", footer: question.reason) {
            ForEach(order, id: \.self) { i in
                let o = question.options[i]
                if o.recipe != nil { row(i, o) }
                Divider()
            }
            ForEach(Array(question.options.enumerated()), id: \.offset) { i, o in
                if o.recipe == nil { quiet(i, o) }
            }
        }
    }

    /// The look in plain words, worked out now so questions written by an older Hatch read the same (CD20).
    private func words(_ o: ComponentQuestion.Option) -> String {
        guard let r = o.recipe, let element = ComponentElement.named(role.element) else { return o.title }
        return ComponentWords.look(element: role.element, recipe: element.look(r)) + (o.custom.map { " (\($0))" } ?? "")
    }

    /// The recommended look first, then the rest as they come (most used first).
    private var order: [Int] {
        let looks = question.options.indices.filter { question.options[$0].recipe != nil }
        return looks.sorted { ($0 == question.recommended ? 0 : 1, $0) < ($1 == question.recommended ? 0 : 1, $1) }
    }

    private func selected(_ i: Int) -> Bool { model.preview?.role == role.id && model.preview?.option == i }

    private func row(_ i: Int, _ o: ComponentQuestion.Option) -> some View {
        Button { model.tryLook(RoleInspectorPreview.make(role, question, i)) } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: selected(i) ? "largecircle.fill.circle" : "circle").foregroundStyle(selected(i) ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    RecipeControl(element: role.element, recipe: o.recipe ?? [:], system: model.system, importance: role.importance,
                                  sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: SampleContent()))
                        .allowsHitTesting(false)
                    HStack(spacing: 6) {
                        Text(words(o)).font(.caption)
                        if i == question.recommended { Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    }
                    Text(o.count > 0 ? "\(o.count) use\(o.count == 1 ? "" : "s") today" : "Not used in the app yet").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(o.effect)
    }

    private func quiet(_ i: Int, _ o: ComponentQuestion.Option) -> some View {
        Button { model.tryLook(RoleInspectorPreview.make(role, question, i)) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected(i) ? "largecircle.fill.circle" : "circle").foregroundStyle(selected(i) ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(o.title).font(.callout)
                        if i == question.recommended { Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    }
                    Text(o.follow == true ? "No look of its own: macOS decides, now and later." : "Keep the most used look for now; decide when a ticket needs it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum RoleInspectorPreview {
    static func make(_ role: ComponentRole, _ q: ComponentQuestion, _ i: Int) -> DesignerPreview {
        let element = ComponentElement.named(role.element)
        let behaviour = role.recipe.filter { element?.parameter($0.key)?.isLook == false }
        let o = q.options[i]
        return DesignerPreview(role: role.id, recipe: o.recipe ?? (o.follow == true ? behaviour : role.recipe), follow: o.follow == true, option: i,
                               label: o.recipe.map { ComponentWords.look(element: role.element, recipe: element?.look($0) ?? $0) } ?? o.title)
    }
}

/// Real looks to try when nothing is asked (CD18): each named by where it comes from.
struct LookPicks: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole

    var body: some View {
        InspectorSection(title: "Look") {
            ForEach(Array(model.picks(for: role).enumerated()), id: \.offset) { _, pick in
                let current = pick.label.hasPrefix("Current")
                let on = model.isPreviewing(role) ? model.preview?.recipe == pick.recipe && model.preview?.follow == pick.follow : current
                Button {
                    if current { model.discard() } else { model.tryLook(DesignerPreview(role: role.id, recipe: pick.recipe, follow: pick.follow, label: pick.label)) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            RecipeControl(element: role.element, recipe: pick.recipe, system: model.system, importance: role.importance,
                                          sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: SampleContent()))
                                .allowsHitTesting(false)
                            Text(pick.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Every setting as a pop-up with plain names (CD19, CD20), behaviour apart (CD22). Settings that need another one show
/// only with it (CD21). Choosing previews; Keep saves.
struct FineTune: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole
    let element: ComponentElement
    @State private var lookOpen = false
    @State private var behaviourOpen = false

    var body: some View {
        let recipe = model.look(of: role)
        let look = element.parameters.filter { $0.isLook && $0.applies(to: recipe) }
        let behaviour = element.parameters.filter { !$0.isLook }
        InspectorSection {
            DisclosureGroup("Fine-Tune", isExpanded: $lookOpen) {
                ForEach(look, id: \.id) { p in row(p, recipe) }
            }
            if !behaviour.isEmpty {
                DisclosureGroup("Behaviour", isExpanded: $behaviourOpen) {
                    ForEach(behaviour, id: \.id) { p in
                        row(p, recipe)
                        if let help = ComponentWords.help(element: element.id, parameter: p.id) { Text(help).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private func row(_ p: ComponentParameter, _ recipe: [String: String]) -> some View {
        let values = model.values(of: p).filter { $0 != p.systemDefault }
        let binding = Binding<String>(
            get: { recipe[p.id] ?? "" },
            set: { model.tryValue(p, $0.isEmpty ? nil : $0) })
        return Picker(p.title, selection: binding) {
            Text(defaultName(p)).tag("")
            Divider()
            ForEach(values, id: \.self) { v in
                Text(ComponentWords.value(element: element.id, parameter: p.id, value: v)).tag(v).help(v)
            }
        }
        .pickerStyle(.menu)
    }

    /// macOS's default, with what it is when the catalog knows (CD20).
    private func defaultName(_ p: ComponentParameter) -> String {
        guard let d = p.systemDefault else { return "macOS default" }
        let name = ComponentWords.value(element: element.id, parameter: p.id, value: d)
        return name.hasPrefix("macOS default") ? name : "macOS default (\(name))"
    }
}

// MARK: - The element (CD8)

struct ElementInspector: View {
    @ObservedObject var model: DesignerModel
    let element: String

    var body: some View {
        let roles = model.system.roles(of: element)
        let open = model.questions(for: element)
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            InspectorSection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ComponentElement.named(element)?.plural ?? element).font(.title3.weight(.semibold))
                    Text("\(roles.count) role\(roles.count == 1 ? "" : "s")" + (open.isEmpty ? "" : " · \(open.count) to decide")).foregroundStyle(.secondary)
                }
            }
            InspectorSection(title: "Roles") {
                ForEach(roles) { r in
                    Button { model.open(r.id) } label: {
                        HStack {
                            Text(r.title)
                            Spacer()
                            if model.question(for: r) != nil { Text("To decide").font(.caption).foregroundStyle(.orange) }
                            else if r.status == .agreed { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                            else if r.followsMacOS { Text("macOS").font(.caption).foregroundStyle(.secondary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            let clear = model.clearQuestions(element)
            if !clear.isEmpty {
                InspectorSection(footer: "Each takes its recommendation: the template's look, or the look 80% of uses already have. The roles stay provisional.") {
                    Text(clear.compactMap { $0.role.flatMap { model.system.role($0)?.title } }.joined(separator: ", ")).font(.callout)
                    Button("Accept the Clear Ones (\(clear.count))") { model.acceptClear(element) }
                }
            }
            Text("Click a control on the canvas, or a role above, to open it in every place it sits.").font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(14) }
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
