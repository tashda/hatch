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
                BatchBanner(model: model)
                if model.showsCanvas {
                    HardCasesBar(model: model)
                    Divider()
                }
                ScrollView { main.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                    .modifier(CanvasLook(model: model))
                    // A toned backdrop, as in Xcode's canvas: the samples are the white surfaces on it.
                    .background(model.showsCanvas ? Color(nsColor: .underPageBackgroundColor) : Color.clear)
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
        .sheet(item: $model.request) { BatchSheet(model: model, request: $0) }
        // Dark is the whole Designer, like the system setting (CD48; replaces CD15's canvas only). Always an explicit
        // scheme, because macOS doesn't go back from a forced dark one to none (B1).
        .preferredColorScheme(model.appearance == .both ? model.systemScheme : model.liveScheme)
    }

    @ViewBuilder private var inspector: some View {
        if model.focused, model.showsCanvas, let role = model.role {
            RoleInspector(model: model, role: role)
        } else {
            selectionInspector
        }
    }

    @ViewBuilder private var selectionInspector: some View {
        switch model.selection {
        case .element(let e)?:
            ElementInspector(model: model, element: e)
        case .place(let p)?:
            PlaceInspector(model: model, place: p)
        case .all?:
            AllInspector(model: model)
        case .templates?:
            TemplatesInspector(model: model)
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
        case .place(let p)?: model.system.place(p)?.title ?? p
        case .all?: "All Elements"
        case .templates?: "Templates"
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
        if (model.selectedElement != nil || model.selectedPlace != nil) && !model.focused {
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
            Button("Keep") { model.keep() }.keyboardShortcut(.defaultAction).disabled(model.previews.isEmpty)
            Button("Back") { if !model.previews.isEmpty { model.discard() } else { model.back() } }.keyboardShortcut(.cancelAction)
            Button("Undo") { model.undo() }.keyboardShortcut("z", modifiers: .command).disabled(model.undoStack.isEmpty)
            Button("Next Question") { model.nextQuestion() }.keyboardShortcut("]", modifiers: .command)
            Button("Previous Question") { model.nextQuestion(forward: false) }.keyboardShortcut("[", modifiers: .command)
            Button("In Place") { model.back(); model.mode = .inPlace }.keyboardShortcut("1", modifiers: .command)
            Button("Matrix") { model.back(); model.mode = .matrix }.keyboardShortcut("2", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    @ViewBuilder private var main: some View {
        if model.focused, model.showsCanvas, let role = model.role {
            RoleView(model: model, role: role)
        } else {
            canvas
        }
    }

    @ViewBuilder private var canvas: some View {
        switch model.selection {
        case .foundations(let kind)?:
            FoundationsView(model: model, kind: kind)
        case .rules?:
            RulesView(model: model)
        case .all?:
            SystemMatrixView(model: model)
        case .templates?:
            TemplatesView(model: model)
        case .place(let p)?:
            switch model.mode {
            case .inPlace: PlaceOverview(model: model, place: p)
            case .matrix: SystemMatrixView(model: model, only: p)
            }
        case .element(let e)?:
            switch model.mode {
            case .inPlace: RoleInPlaceView(model: model, element: e)
            case .matrix: RoleMatrixView(model: model, element: e)
            }
        case nil:
            ContentUnavailableView("Choose an element", systemImage: "square.grid.2x2", description: Text("Pick an element on the left to see its roles in their places."))
        }
    }
}

// MARK: - Hard cases (CD15)

/// Light, dark or both for the whole Designer (CD48); long label, disabled, larger text and an inactive window for the canvas.
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

/// The canvas's hard cases: its text size and window state (the appearance is the whole window's, CD48).
struct CanvasLook: ViewModifier {
    @ObservedObject var model: DesignerModel
    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(model.largeText ? .xxLarge : .large)
            .environment(\.controlActiveState, model.inactive ? .inactive : .key)
    }
}

/// A place drawn once, or in light and dark side by side when the canvas shows Both.
struct Appearances<Content: View>: View {
    @ObservedObject var model: DesignerModel
    @ViewBuilder var content: () -> Content
    var body: some View {
        if model.appearance == .both {
            HStack(alignment: .top, spacing: 10) {
                content().padding(10).environment(\.colorScheme, .light)
                    .background(Color(white: 0.86), in: RoundedRectangle(cornerRadius: 12))
                content().padding(10).environment(\.colorScheme, .dark)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12))
            }
        } else {
            content()
        }
    }
}

// MARK: - Sidebar

struct DesignerSidebar: View {
    @ObservedObject var model: DesignerModel
    @State private var filter = ""

    /// Elements by kind (CD11), so the list stays readable as the catalog grows.
    static let groups: [(title: String, elements: [String])] = [
        ("Actions", ["button", "menu"]), ("Choices", ["picker", "toggle"]), ("Text", ["field"]),
        ("Lists and Containers", ["row", "card", "sheet"]), ("Feedback", ["badge", "toast", "emptyState"]),
    ]

    var body: some View {
        List(selection: $model.selection) {
            if !filter.isEmpty {
                Section("Roles") {
                    ForEach(matches) { r in
                        Button { model.open(r.id) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title)
                                Text(ComponentElement.named(r.element)?.plural ?? r.element).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Label("All Elements", systemImage: "square.grid.3x3").badge(model.system.questions.count).tag(DesignerSelection.all)
            ForEach(Self.groups, id: \.title) { group in
                let used = group.elements.filter { model.system.elementsUsed.contains($0) && shown(ComponentElement.named($0)?.plural ?? $0) }
                if !used.isEmpty {
                    Section(group.title) {
                        ForEach(used, id: \.self) { e in element(e) }
                    }
                }
            }
            let others = model.system.elementsUsed.filter { e in e != "switcher" && !Self.groups.contains { $0.elements.contains(e) } && shown(e) }
            if !others.isEmpty { Section("Other") { ForEach(others, id: \.self) { e in element(e) } } }
            let places = model.placesUsed.filter { shown($0.title) }
            if !places.isEmpty {
                Section("By Place") {
                    ForEach(places) { p in
                        // Not more elements: the same roles grouped by where they sit, so they read differently.
                        Label(p.title, systemImage: "rectangle.dashed").foregroundStyle(.secondary)
                            .badge(model.questions(inPlace: p.id).count).tag(DesignerSelection.place(p.id))
                            .help("Every control in \(p.title.lowercased()): \(p.summary)")
                            .contextMenu { BatchMenuItems(model: model, element: nil, place: p.id) }
                    }
                }
            }
            Section("System") {
                Label("Templates", systemImage: "square.on.square").tag(DesignerSelection.templates)
                Label("Rules", systemImage: "checklist").badge(model.system.rules.filter { !$0.isOff }.count).tag(DesignerSelection.rules)
                ForEach(ComponentFoundation.Kind.allCases, id: \.self) { kind in
                    let count = model.system.foundations.filter { $0.kind == kind }.count
                    if count > 0 {
                        Label(kind.title, systemImage: Self.symbol(kind)).badge(count).tag(DesignerSelection.foundations(kind))
                    }
                }
            }
        }
        .searchable(text: $filter, placement: .sidebar, prompt: "Filter")
        .onChange(of: model.selection) { _, new in
            // Opening a role in another element changes the selection too; that keeps the role open.
            if case .element(let e)? = new, model.focused, model.role.map({ model.page(of: $0.element) }) == e { return }
            model.back()
            if case .element(let e)? = new, model.role.map({ model.page(of: $0.element) }) != e { model.selectedRole = model.system.roles(of: e).first?.id }
        }
    }

    private func element(_ e: String) -> some View {
        let open = model.openCount(e)
        return HStack {
            Text(ComponentElement.named(e)?.plural ?? e)
            Spacer()
            // Only what differs is marked (CD41): a check when every role is agreed.
            if open == 0 && model.state(of: e) == .agreed { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary) }
        }
        .badge(open)
        .tag(DesignerSelection.element(e))
        .contextMenu {
            BatchMenuItems(model: model, element: e, place: nil)
            Divider()
            Button("Agree to All \(ComponentElement.named(e)?.plural ?? e)") { model.agreeAll(element: e) }
        }
    }

    private func shown(_ name: String) -> Bool { filter.isEmpty || name.localizedCaseInsensitiveContains(filter) }

    /// Roles whose title or id matches the filter (⌘F).
    private var matches: [ComponentRole] {
        model.system.roles.filter { $0.title.localizedCaseInsensitiveContains(filter) || $0.id.localizedCaseInsensitiveContains(filter) }
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
        let members = model.members(of: element)
        VStack(alignment: .leading, spacing: 28) {
            ForEach(members, id: \.self) { e in
                let places = model.system.allPlaces.filter { p in model.system.roles(of: e).contains { $0.places.contains(p.id) } }
                if members.count > 1 {
                    Text(ComponentElement.named(e)?.plural ?? e).font(.title3.weight(.semibold))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: model.appearance == .both ? 560 : 340), spacing: 24, alignment: .top)], alignment: .leading, spacing: 28) {
                    ForEach(places) { place in
                        PlaceFrame(place: place, element: e, model: model)
                    }
                }
            }
        }
    }
}

// MARK: - A role, in every place it sits (CD8, CD14)

struct RoleView: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole

    /// Where Esc goes back to: the element, the place or All it was opened from.
    private var backTitle: String {
        switch model.selection {
        case .place(let p)?: model.system.place(p)?.title ?? p
        case .all?: "All Elements"
        case .templates?: "Templates"
        default: ComponentElement.named(model.page(of: role.element))?.plural ?? role.element
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Button { model.back() } label: { Label(backTitle, systemImage: "chevron.left") }
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
            let comparing = model.isPreviewing(role) || role.draft != nil
            if !comparing {
                Text("Choose a look on the right to see it here beside today's.").font(.callout).foregroundStyle(.secondary)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 20) {
                if comparing {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(model.isPreviewing(role) ? "Preview" : "Draft")
                            .font(.caption.weight(.semibold)).foregroundStyle(model.isPreviewing(role) ? .orange : .secondary)
                    }
                }
                ForEach(role.places, id: \.self) { id in
                    let place = model.system.place(id) ?? ComponentPlace(id, id, "")
                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.title).font(.headline)
                            let here = model.screens(of: role, place: id)
                            if !here.isEmpty {
                                Text("In " + here.prefix(3).map(\.screen).joined(separator: ", ") + (here.count > 3 ? " and \(here.count - 3) more" : ""))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            if model.isPreviewing(role) && role.places.count > 1 {
                                Button("Only Here…") { model.request = .onlyHere(role: role.id, place: id) }
                                    .buttonStyle(.link).font(.caption)
                                    .help("Keep this look for \(place.title) only: a variant, with a reason (CD26)")
                            }
                        }
                        .frame(width: 140, alignment: .leading).help(place.summary)
                        Appearances(model: model) { PlaceFrame(place: place, element: role.element, model: model, focus: role.id, today: true, framed: false) }
                        if comparing {
                            Appearances(model: model) { PlaceFrame(place: place, element: role.element, model: model, focus: role.id, framed: false) }
                        }
                    }
                }
            }
            let looks = model.looksToday(role)
            if looks.count > 1 {
                Divider().padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("For reference: how the app draws it today").font(.headline)
                    Text("\(looks.reduce(0) { $0 + $1.count }) places in the code use \(looks.count) different looks for this role. Whatever you choose, they move to it when their screens are next changed.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(Array(looks.prefix(8).enumerated()), id: \.offset) { _, look in
                        VStack(alignment: .leading, spacing: 6) {
                            RecipeControl(element: role.element, recipe: look.look, system: model.system, importance: role.importance,
                                          sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: model.sample))
                                .allowsHitTesting(false)
                            Text("\(ComponentWords.look(element: role.element, recipe: look.look)) · \(look.count) use\(look.count == 1 ? "" : "s")")
                                .font(.caption.weight(.medium))
                            Text(look.examples.joined(separator: "\n")).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - Matrix (CD32, CD33)

/// One cell of a drawn matrix: the role's control and its name. Pointing at it lights up every cell of the same role.
struct MatrixCell: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole
    let place: String
    @Binding var hovered: String?

    var body: some View {
        Button { model.open(role.id) } label: {
            VStack(spacing: 5) {
                RecipeControl(element: role.element, recipe: model.look(of: role), system: model.system, importance: role.importance,
                              sample: SampleWords.content(role.importance, place: place, base: model.sample))
                    .allowsHitTesting(false)
                    .frame(minHeight: 28)
                HStack(spacing: 4) {
                    if model.question(for: role) != nil { Circle().fill(.orange).frame(width: 6, height: 6) }
                    Text(role.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(hovered == role.id ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: hovered == role.id ? 2 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? role.id : (hovered == role.id ? nil : hovered) }
        .help("\(role.title): \(role.use)")
    }
}

/// An empty cell: nothing decided yet; the first ticket that needs it asks.
struct EmptyCell: View {
    var body: some View {
        Text("Not decided").font(.caption2).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [4])).foregroundStyle(.tertiary))
            .help("Not decided yet: the first ticket that needs it asks")
    }
}

/// An element's matrix: places down, importance across, each cell drawn. A column with more than two looks is marked.
struct RoleMatrixView: View {
    @ObservedObject var model: DesignerModel
    let element: String

    var body: some View {
        let members = model.members(of: element)
        VStack(alignment: .leading, spacing: 24) {
            ForEach(members, id: \.self) { e in
                if members.count > 1 { Text(ComponentElement.named(e)?.plural ?? e).font(.title3.weight(.semibold)) }
                ElementMatrix(model: model, element: e)
            }
        }
    }
}

struct ElementMatrix: View {
    @ObservedObject var model: DesignerModel
    let element: String
    @State private var hovered: String?

    var body: some View {
        let m = model.system.matrix(element: element)
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("")
                ForEach(m.importances, id: \.self) { i in
                    let looks = Set(model.system.roles(of: element).filter { $0.importance == i }.map { model.look(of: $0) }).count
                    HStack(spacing: 6) {
                        Text(i.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if looks > 2 { Text("\(looks) looks").font(.caption2.weight(.semibold)).foregroundStyle(.orange).help("\(looks) different looks for \(i.title.lowercased()) \((ComponentElement.named(element)?.plural ?? element).lowercased())") }
                    }
                }
            }
            ForEach(Array(m.places.enumerated()), id: \.offset) { row, place in
                GridRow {
                    Text(place.title).font(.callout).frame(width: 110, alignment: .leading)
                    ForEach(Array(m.cells[row].enumerated()), id: \.offset) { _, role in
                        if let role { MatrixCell(model: model, role: role, place: place.id, hovered: $hovered) } else { EmptyCell() }
                    }
                }
            }
        }
    }
}

/// The whole app at a glance (CD33): places down, elements across, each cell the element's most important role there.
/// With `only`, one place: importance down, elements across.
struct SystemMatrixView: View {
    @ObservedObject var model: DesignerModel
    var only: String? = nil
    @State private var hovered: String?

    private var elements: [String] {
        let order = DesignerSidebar.groups.flatMap { $0.elements.flatMap { $0 == "picker" ? ["picker", "switcher"] : [$0] } }
        return model.system.elementsUsed.filter { e in only.map { p in model.system.roles(of: e).contains { $0.places.contains(p) } } ?? true }
            .sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("")
                    ForEach(elements, id: \.self) { e in
                        Text(ComponentElement.named(e)?.plural ?? e).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                if let only {
                    ForEach(ComponentRole.Importance.allCases, id: \.self) { i in
                        if elements.contains(where: { model.system.role(element: $0, place: only, importance: i) != nil }) {
                            GridRow {
                                Text(i.title).font(.callout).frame(width: 100, alignment: .leading)
                                ForEach(elements, id: \.self) { e in cell(model.system.role(element: e, place: only, importance: i), only) }
                            }
                        }
                    }
                } else {
                    ForEach(model.placesUsed) { place in
                        GridRow {
                            Text(place.title).font(.callout).frame(width: 100, alignment: .leading).help(place.summary)
                            ForEach(elements, id: \.self) { e in cell(main(e, place.id), place.id) }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// The element's role in a place that matters most: the main action before the others.
    private func main(_ element: String, _ place: String) -> ComponentRole? {
        ComponentRole.Importance.allCases.lazy.compactMap { model.system.role(element: element, place: place, importance: $0) }.first
    }

    @ViewBuilder private func cell(_ role: ComponentRole?, _ place: String) -> some View {
        if let role { MatrixCell(model: model, role: role, place: place, hovered: $hovered).frame(minWidth: 120) } else { Color.clear.frame(minWidth: 120, minHeight: 64) }
    }
}

// MARK: - A place (CD9)

/// Every element in one place, each drawn as it sits there.
struct PlaceOverview: View {
    @ObservedObject var model: DesignerModel
    let place: String

    var body: some View {
        let p = model.system.place(place) ?? ComponentPlace(place, place, "")
        let elements = DesignerSidebar.groups.flatMap { $0.elements.flatMap { $0 == "picker" ? ["picker", "switcher"] : [$0] } }
            .filter { e in model.system.roles(of: e).contains { $0.places.contains(place) } }
        VStack(alignment: .leading, spacing: 14) {
            Text(p.summary).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: model.appearance == .both ? 560 : 340), spacing: 24, alignment: .top)], alignment: .leading, spacing: 28) {
                ForEach(elements, id: \.self) { e in
                    PlaceFrame(place: p, element: e, model: model, title: ComponentElement.named(e)?.plural ?? e)
                }
            }
        }
    }
}

struct PlaceInspector: View {
    @ObservedObject var model: DesignerModel
    let place: String

    var body: some View {
        let p = model.system.place(place) ?? ComponentPlace(place, place, "")
        let roles = model.system.roles.filter { $0.places.contains(place) }
        let elements = Array(Set(roles.map(\.element))).sorted()
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            InspectorSection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title).font(.title3.weight(.semibold))
                    Text(p.summary).font(.callout).foregroundStyle(.secondary)
                }
            }
            InspectorSection(title: "Roles Here") {
                ForEach(roles) { r in
                    Button { model.open(r.id) } label: {
                        HStack {
                            Text(r.title)
                            Spacer()
                            Text(ComponentElement.named(r.element)?.title ?? r.element).font(.caption).foregroundStyle(.secondary)
                            if model.question(for: r) != nil { Circle().fill(.orange).frame(width: 6, height: 6) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            InspectorSection(title: "For the Whole Place", footer: "Each opens a list of every role it changes; a role that also sits elsewhere can change everywhere or only here.") {
                ForEach(model.templates) { t in
                    Button("Match \(t.title) Here…") { model.request = .template(t.id, element: nil, place: place) }
                }
                Button("Follow macOS Here…") { model.request = .follow(element: nil, place: place) }
                Divider()
                ForEach(elements, id: \.self) { e in
                    Button("One Look for Every \(ComponentElement.named(e)?.title ?? e) Here…") { model.request = .setting(element: e, place: place) }
                }
            }
        }
        .padding(14) }
    }
}

struct AllInspector: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        let c = model.system.counts
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            InspectorSection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.appName).font(.title3.weight(.semibold))
                    Text("Baseline v\(model.system.version) · \(model.system.roles.count) roles").foregroundStyle(.secondary)
                    Text("\(c.agreed) agreed · \(c.provisional) provisional" + (c.inRedesign > 0 ? " · \(c.inRedesign) in redesign" : "")).font(.callout).foregroundStyle(.secondary)
                }
            }
            InspectorSection(title: "To Decide") {
                if model.system.questions.isEmpty { Text("Nothing waits.").foregroundStyle(.secondary) }
                ForEach(model.system.elementsUsed.filter { model.openCount($0) > 0 }, id: \.self) { e in
                    Button { model.selection = .element(e) } label: {
                        HStack { Text(ComponentElement.named(e)?.plural ?? e); Spacer(); Text("\(model.openCount(e))").monospacedDigit().foregroundStyle(.secondary) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !model.system.questions.isEmpty { Button("Start with the First") { model.nextQuestion() } }
            }
            Text("Each cell is an element's most important role in a place. Read across a row to see if a place holds together; point at a cell to see where else its role sits.")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        .padding(14) }
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
    @State private var renaming = false
    @State private var newTitle = ""

    private var element: ComponentElement? { ComponentElement.named(role.element) }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            if let suggestion = model.system.suggestedTitle(role.id) {
                InspectorSection(footer: "Made-up roles were named after their places. A name by its job is easier to read; the code name stays.") {
                    HStack {
                        Text("Rename to “\(suggestion)”?").font(.callout)
                        Spacer()
                        Button("Rename") { model.rename(role, to: suggestion) }
                    }
                }
            }
            InspectorSection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(role.title).font(.title3.weight(.semibold))
                        .onTapGesture(count: 2) { newTitle = role.title; renaming = true }
                        .help("Double-click to rename")
                    Text(statusLine).font(.callout).foregroundStyle(.secondary)
                    Text(role.places.map { model.system.place($0)?.title ?? $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            WhereSection(model: model, role: role)
            if let finding {
                InspectorSection { AppleCallout(model: model, role: role, advice: finding) }
            }
            if role.places.allSatisfy({ ComponentNative.systemPlaces[$0]?.allowed.isEmpty == true }) {
                // Menu items and alerts are drawn by macOS: there is no look to choose, only order and wording (Rules).
                InspectorSection(title: "Look", footer: "Order, wording and icons in menus are set under Rules.") {
                    Text("macOS draws \(role.places.map { ComponentPlace.title($0).lowercased() }.joined(separator: " and ")) itself, so there is no look to choose here.")
                    if !role.followsMacOS { Button("Follow macOS") { model.tryLook(DesignerPreview(role: role.id, recipe: role.recipe.filter { ComponentElement.named(role.element)?.parameter($0.key)?.isLook == false }, follow: true, label: "Follow macOS")) } }
                }
            } else {
                if let q = model.question(for: role) { QuestionPicks(model: model, role: role, question: q) }
                if let element { LookChoices(model: model, role: role, element: element) }
                LookPicks(model: model, role: role)
                if let element { FineTune(model: model, role: role, element: element) }
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
            InspectorSection {
                sources
                LabeledContent("Code") { Text(role.codeName).font(.caption.monospaced()).textSelection(.enabled) }
                    .help(role.id)
            }
            footer
        }
        .padding(14) }
        .popover(isPresented: $asking) { ask }
        .popover(isPresented: $renaming) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rename \(role.title)").font(.headline)
                TextField("Title", text: $newTitle).frame(width: 260)
                Text("The code name \(role.codeName) stays.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Rename") { model.rename(role, to: newTitle); renaming = false }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
        }
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
                Button("Rename…") { newTitle = role.title; renaming = true }
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

/// Where the role is in the app (CD49): the screens that use it, what each control says, and the file and line, so a
/// change is never abstract. A use opens in Xcode.
struct WhereSection: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole
    @State private var open = false

    var body: some View {
        let screens = model.screens(of: role)
        let total = screens.reduce(0) { $0 + $1.uses.count }
        InspectorSection(title: "Where It Is in \(model.appName)",
                         footer: total == 0 ? nil : "Changing this role changes all \(total). New screens that need it use it too.") {
            if model.inventory == nil {
                Text("Open the Designer from Hatch to see where the app uses it.").foregroundStyle(.secondary)
            } else if total == 0 {
                Text("Not used yet: the first screen that needs it will.").foregroundStyle(.secondary)
            } else {
                Text("\(total) control\(total == 1 ? "" : "s") on \(screens.count) screen\(screens.count == 1 ? "" : "s")").font(.callout.weight(.medium))
                ForEach(Array(screens.prefix(open ? 40 : 4).enumerated()), id: \.offset) { _, s in
                    DisclosureGroup {
                        ForEach(Array(s.uses.prefix(12).enumerated()), id: \.offset) { _, u in
                            Button { model.reveal(u) } label: {
                                HStack {
                                    Text(u.title.map { "“\($0)”" } ?? "A control").lineLimit(1)
                                    Spacer()
                                    Text(u.location).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open \(u.location) in Xcode")
                        }
                    } label: {
                        HStack {
                            Text(s.screen)
                            Spacer()
                            Text("\(s.uses.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                if screens.count > 4 {
                    Button(open ? "Show Fewer" : "Show All \(screens.count) Screens") { open.toggle() }.buttonStyle(.link)
                }
            }
        }
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
        InspectorSection(title: "Shortcuts", footer: "A whole look at once: macOS's, a template's, or the one the app uses most.") {
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

/// How wide a choice tile is for an element: wide controls (a segmented picker, a list) need room to be seen whole.
enum ChoiceTile {
    static func width(_ element: String) -> CGFloat {
        ["picker": 150, "switcher": 160, "row": 220, "card": 220, "sheet": 220, "toast": 180, "emptyState": 220][element] ?? 84
    }
}

/// The choices that make the look (CD50): each key setting as a row of drawn options, the role drawn with each value on
/// top of its current look. Clicking one previews it everywhere; Keep saves it (and answers an open question).
struct LookChoices: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole
    let element: ComponentElement

    var body: some View {
        let recipe = model.look(of: role)
        InspectorSection(title: "Look", footer: "Each choice is drawn on this role as it looks now. Keep saves what you try.") {
            ForEach(element.keyParameters.filter { $0.applies(to: recipe) }, id: \.id) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.title).font(.callout.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: ChoiceTile.width(element.id)), spacing: 6, alignment: .top)], alignment: .leading, spacing: 6) {
                        ForEach(model.choices(of: p, for: role), id: \.self) { value in chip(p, value, recipe) }
                    }
                }
            }
        }
    }

    /// One value of a setting, drawn on the role.
    private func chip(_ p: ComponentParameter, _ value: String?, _ recipe: [String: String]) -> some View {
        var tried = recipe
        if let value, value != p.systemDefault { tried[p.id] = value } else { tried[p.id] = nil }
        let current = (recipe[p.id] ?? p.systemDefault) == (value ?? p.systemDefault)
        let name = value.map { ComponentWords.value(element: element.id, parameter: p.id, value: $0) } ?? "macOS default"
        return Button { model.tryValue(p, value) } label: {
            VStack(spacing: 4) {
                RecipeControl(element: element.id, recipe: tried, system: model.system, importance: role.importance,
                              sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: SampleContent()))
                    .allowsHitTesting(false)
                    .fixedSize()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .clipped()
                Text(name).font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(current ? .primary : .secondary)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .background(current ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(current ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: current ? 1.5 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(value ?? "macOS default")
    }
}

/// The same key choices for every role of an element at once (CD50): "Capsule for every button" in one click,
/// previewed on the canvas under a banner, kept as one change. Roles where a value doesn't apply are left as they are.
struct ElementChoices: View {
    @ObservedObject var model: DesignerModel
    let element: ComponentElement

    var body: some View {
        InspectorSection(title: "Look for All \(element.plural)", footer: "Applies to every \(element.title.lowercased()) where it fits; menus and alerts that macOS draws are left alone. Previewed first.") {
            ForEach(element.keyParameters, id: \.id) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.title).font(.callout.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: ChoiceTile.width(element.id)), spacing: 6, alignment: .top)], alignment: .leading, spacing: 6) {
                        ForEach(model.choices(of: p), id: \.self) { value in
                            Button { model.tryBatch(model.batchSetting(p, value, element: element.id, place: nil)) } label: {
                                VStack(spacing: 4) {
                                    RecipeControl(element: element.id, recipe: value.map { [p.id: $0] } ?? [:], system: model.system, importance: .other,
                                                  sample: SampleWords.content(.other, place: "page", base: SampleContent()))
                                        .allowsHitTesting(false).fixedSize().scaleEffect(0.8).frame(maxWidth: .infinity, minHeight: 34).clipped()
                                    Text(value.map { ComponentWords.value(element: element.id, parameter: p.id, value: $0) } ?? "macOS default")
                                        .font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.secondary)
                                }
                                .padding(5).frame(maxWidth: .infinity)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
        let keys = Set(element.keyParameters.map(\.id))
        let look = element.parameters.filter { $0.isLook && $0.applies(to: recipe) && !keys.contains($0.id) }
        let behaviour = element.parameters.filter { !$0.isLook }
        InspectorSection {
            if !look.isEmpty {
                DisclosureGroup("Fine-Tune", isExpanded: $lookOpen) {
                    ForEach(look, id: \.id) { p in row(p, recipe) }
                }
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
        let roles = model.members(of: element).flatMap { model.system.roles(of: $0) }
        let open = model.members(of: element).flatMap { model.questions(for: $0) }
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
            if let el = ComponentElement.named(element), !el.keyParameters.isEmpty { ElementChoices(model: model, element: el) }
            InspectorSection(title: "For All \(ComponentElement.named(element)?.plural ?? element)") {
                if ["button", "menu"].contains(element) {
                    Button("Use Glass Where It Fits…") { model.request = .glass(element: element) }
                        .help("Only the style, only where Liquid Glass belongs: bottom bars, floating bars and action rows")
                }
                ForEach(model.templates) { t in
                    Button("Match \(t.title)…") { model.request = .template(t.id, element: element, place: nil) }
                        .help("Every role takes \(t.title)'s look for it; the list shows each change. " + t.summary)
                }
                Button("Follow macOS…") { model.request = .follow(element: element, place: nil) }
                Button("One Look for All…") { model.request = .setting(element: element, place: nil) }
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
