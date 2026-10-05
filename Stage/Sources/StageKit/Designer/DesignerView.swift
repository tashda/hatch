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
        content.onAppear(perform: Self.sizeForReview)
    }

    /// `HATCH_DESIGNER_SIZE=1600x2600`: a window that shows whole pages, for reviewing snapshot runs.
    static func sizeForReview() {
        guard let v = ProcessInfo.processInfo.environment["HATCH_DESIGNER_SIZE"], case let parts = v.split(separator: "x").compactMap({ Double($0) }),
              parts.count == 2 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let w = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
            w.setFrame(NSRect(x: 0, y: 0, width: parts[0], height: parts[1]), display: true)
        }
    }

    @ViewBuilder private var content: some View {
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
        case .decide?:
            AllInspector(model: model)
        case .rules?:
            ContentUnavailableView("Rules", systemImage: "checklist", description: Text("Choose a value beside a rule; Hatch checks the ones marked."))
        case .own(let id)?:
            OwnInspector(model: model, proposal: model.ownProposal(id))
        case .ownQuestions?:
            OwnInspector(model: model, proposal: nil)
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
        case .decide?: "To Decide"
        case .foundations(let kind)?: kind.title
        case .rules?: "Rules"
        case .own(let id)?: model.ownProposal(id)?.title ?? id
        case .ownQuestions?: "Not Sure Yet"
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
            Button { model.selection = .decide } label: { Label("\(n) to Decide", systemImage: "questionmark.bubble") }
                .labelStyle(.titleAndIcon)
                .disabled(n == 0)
                .help("Everything waiting for a decision (⌘] goes to the next one)")
        }
        // Its own glass group, apart from the window's tools.
        ToolbarSpacer(.fixed)
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
        case .own(let id)?:
            if let p = model.ownProposal(id) { OwnComponentView(model: model, proposal: p) }
        case .ownQuestions?:
            OwnQuestionsView(model: model)
        case .all?:
            SystemMatrixView(model: model)
        case .templates?:
            TemplatesView(model: model)
        case .decide?:
            DecideList(model: model)
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
            Toggle("macOS \(model.oldestMacOSTitle)", isOn: $model.oldestMacOS)
                .disabled(model.system.minimumMacOSNumber >= 27)
                .help(model.system.minimumMacOSNumber >= 27
                      ? "\(model.appName) runs only on the newest macOS, so nothing falls back."
                      : "Draw every look as \(model.appName)'s oldest macOS (\(model.oldestMacOSTitle)) will: newer styles become their fallbacks.")
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
            // Each side is its own tile in its own appearance; no band around them (a box around a box).
            HStack(alignment: .top, spacing: 12) {
                content().environment(\.colorScheme, .light)
                content().environment(\.colorScheme, .dark)
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

    /// A symbol for each place, so the list can be scanned (every one checked to exist on macOS 27).
    static func placeSymbol(_ place: String) -> String {
        ["toolbar": "menubar.rectangle", "sheetFooter": "rectangle.bottomthird.inset.filled", "bottomBar": "dock.rectangle",
         "listRow": "list.bullet.rectangle", "card": "square.text.square", "inspector": "sidebar.right", "popover": "bubble.middle.top",
         "form": "checklist", "emptyState": "tray", "contextMenu": "contextualmenu.and.cursorarrow", "alert": "exclamationmark.bubble",
         "page": "doc.text", "actionRow": "button.horizontal", "floating": "capsule.portrait"][place] ?? "rectangle.dashed"
    }

    /// Elements by kind (CD11), so the list stays readable as the catalog grows.
    static let groups: [(title: String, elements: [String])] = [
        ("Actions", ["button", "menu", "controlGroup"]), ("Choices", ["picker", "toggle", "datePicker", "slider", "stepper"]),
        ("Text", ["field", "textEditor"]), ("Lists and Containers", ["row", "table", "card", "form", "sheet"]),
        ("Feedback", ["badge", "progress", "gauge", "toast", "emptyState"]),
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
            if !model.system.questions.isEmpty {
                Label("To Decide", systemImage: "questionmark.bubble").badge(model.system.questions.count).tag(DesignerSelection.decide)
            }
            Label("All Elements", systemImage: "square.grid.3x3").tag(DesignerSelection.all)
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
            // The app's own components, as much part of the system as SwiftUI's (CM9).
            let own = model.ownProposals.filter { shown($0.title) }
            if !own.isEmpty || !model.ownQuestions.isEmpty {
                Section("Your Own Components") {
                    ForEach(own) { p in
                        Label(p.title, systemImage: "square.on.square.dashed")
                            .badge(p.members.count).tag(DesignerSelection.own(p.id))
                            .help(p.why)
                    }
                    if !model.ownQuestions.isEmpty {
                        Label("Not Sure Yet", systemImage: "questionmark.circle")
                            .badge(model.ownQuestions.count).tag(DesignerSelection.ownQuestions)
                            .help("Views Hatch can't place from their code: questions, never guesses")
                    }
                }
            }
            let places = model.placesUsed.filter { shown($0.title) }
            if !places.isEmpty {
                Section("By Place") {
                    ForEach(places) { p in
                        // Not more elements: the same roles grouped by where they sit, so they read differently.
                        Label(p.title, systemImage: Self.placeSymbol(p.id)).foregroundStyle(.secondary)
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
                TileGrid(minWidth: model.appearance == .both ? 620 : 360) {
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
    /// The place row under the pointer: its "Only Here…" shows there, not on every row.
    @State private var hoveredPlace: String?

    /// Where Esc goes back to: the element, the place or All it was opened from.
    private var backTitle: String {
        switch model.selection {
        case .place(let p)?: model.system.place(p)?.title ?? p
        case .all?: "All Elements"
        case .templates?: "Templates"
        case .decide?: "To Decide"
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
                Text("Choose a look in the inspector; it is drawn here beside today's, in every place.").font(.callout).foregroundStyle(.secondary)
            } else if model.isPreviewing(role) && !model.isChanged(role) {
                // Said in words, so two identical columns don't look like a broken preview.
                Label(model.preview?.follow == true
                      ? "Draws the same as today. What changes: macOS decides this look from now on, so it follows macOS in later versions."
                      : "Draws the same as today in every place.", systemImage: "equal.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 20) {
                // Always two columns, so the page keeps its shape when a look is tried and no tile is page-wide.
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ThenNowLabel(now: false, title: "Today", detail: "as the app looks now")
                    Text("")
                    if comparing {
                        ThenNowLabel(now: true, title: model.isPreviewing(role) ? "Preview" : "Draft",
                                     detail: model.isPreviewing(role) ? model.preview?.label ?? "" : "saved, not applied yet")
                    } else {
                        ThenNowLabel(now: true, title: "Preview", detail: "choose a look").opacity(0.5)
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
                                    .opacity(hoveredPlace == id ? 1 : 0)
                            }
                        }
                        .frame(width: 140, alignment: .leading).help(place.summary)
                        .onHover { if $0 { hoveredPlace = id } }
                        // The same tiles as the element's page, window and all, without their headings.
                        ThenNow(now: false, comparing: true) {
                            Appearances(model: model) { PlaceFrame(place: place, element: role.element, model: model, focus: role.id, today: true, header: false) }
                        }
                        .onHover { if $0 { hoveredPlace = id } }
                        if !comparing {
                            Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.quaternary)
                                .frame(maxHeight: .infinity)
                            // Where the preview will be: quiet, the same size as today's tile.
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.tertiary)
                                .overlay { if id == role.places.first { Text("A look you choose is drawn here").font(.callout).foregroundStyle(.tertiary) } }
                                .frame(minWidth: 0, idealWidth: 380, maxWidth: .infinity, minHeight: PlaceFrame.tileHeight, maxHeight: .infinity)
                        }
                        if comparing {
                            Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.tertiary)
                                .frame(maxHeight: .infinity)
                            ThenNow(now: true, comparing: true) {
                                Appearances(model: model) { PlaceFrame(place: place, element: role.element, model: model, focus: role.id, header: false) }
                            }
                            .onHover { if $0 { hoveredPlace = id } }
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

// MARK: - Actions (only the ones that change something)

/// A change offered in an inspector or a context menu: what it is, what it changes, and the sheet it opens.
struct DesignerAction: Identifiable {
    var title: String
    var detail: String
    var symbol: String
    var request: DesignerModel.BatchRequest
    var id: String { request.id }
}

/// One action as a row: an icon in a tinted square, the title, what it changes, and a chevron (like System Settings).
struct ActionRow: View {
    let title: String
    let detail: String
    let symbol: String
    var tint: Color = .accentColor
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5).padding(.horizontal, 6)
            .background(hovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct ActionRows: View {
    @ObservedObject var model: DesignerModel
    let actions: [DesignerAction]
    var body: some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
            if i > 0 { Divider().padding(.leading, 40) }
            ActionRow(title: a.title, detail: a.detail, symbol: a.symbol) { model.request = a.request }
        }
    }
}

// MARK: - To decide

/// Everything waiting for a decision, grouped by control: what each role is for, where it is, and its options drawn.
/// Clicking an option opens the role with that option previewed in every place.
struct DecideList: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        let groups = model.system.elementsUsed.map { e in (e, model.questions(for: e)) }.filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: 24) {
            Text("\(model.system.questions.count) looks to decide. Each shows the looks the app uses today and the template's; click one to see it in every place, then Keep.")
                .foregroundStyle(.secondary)
            ForEach(groups, id: \.0) { element, questions in
                VStack(alignment: .leading, spacing: 10) {
                    Text(ComponentElement.named(element)?.plural ?? element).font(.title3.weight(.semibold))
                    ForEach(questions, id: \.id) { q in card(q) }
                }
            }
        }
    }

    @ViewBuilder private func card(_ q: ComponentQuestion) -> some View {
        if let id = q.role, let role = model.system.role(id) {
            let screens = model.screens(of: role)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(role.title).font(.headline)
                    Text(role.places.map { ComponentPlace.title($0) }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open") { model.open(role.id) }
                }
                Text(role.use).font(.callout).foregroundStyle(.secondary)
                if !screens.isEmpty {
                    Text("Used on " + screens.prefix(4).map(\.screen).joined(separator: ", ") + (screens.count > 4 ? " and \(screens.count - 4) more screens" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                // The options wrap within the card: nothing on this page scrolls sideways.
                FlowRow(spacing: 10, top: true) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                        Button {
                            model.open(role.id)
                            model.tryLook(RoleInspectorPreview.make(role, q, i))
                        } label: { option(role, q, i, o) }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        }
    }

    private func option(_ role: ComponentRole, _ q: ComponentQuestion, _ i: Int, _ o: ComponentQuestion.Option) -> some View {
        let recommended = i == q.recommended
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if let r = o.recipe {
                    RecipeControl(element: role.element, recipe: r, system: model.system, importance: role.importance,
                                  sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: SampleContent()))
                        .allowsHitTesting(false)
                        .fitted(0.85, maxHeight: 40)
                } else {
                    Image(systemName: o.follow == true ? "apple.logo" : "questionmark.circle").font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                }
            }
            .frame(width: 150, alignment: .leading)
            Text(o.recipe.map { ComponentWords.look(element: role.element, recipe: ComponentElement.named(role.element)?.look($0) ?? $0) } ?? o.title)
                .font(.caption).lineLimit(2)
            if let j = model.drawsLikeEarlier(role, q, i) {
                Text(sameNote(role, q, j)).font(.caption2).foregroundStyle(.orange).lineLimit(3)
            }
            HStack(spacing: 4) {
                if recommended { Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                if o.count > 0 { Text("\(o.count) use\(o.count == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(10)
        .frame(width: 170, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(recommended ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}

// MARK: - Then and now

/// The column heading: Today is the past (a clock, grey), the preview is what it becomes (a sparkle, the accent).
struct ThenNowLabel: View {
    let now: Bool
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: now ? "sparkles" : "clock.arrow.circlepath")
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased()).font(.caption.weight(.bold))
                Text(detail).font(.caption2).lineLimit(1)
            }
        }
        .foregroundStyle(now ? Color.accentColor : .secondary)
    }
}

/// Today on a neutral band, the preview on a tinted band outlined in the accent colour, so the two never read as
/// duplicates. Both are drawn exactly as they look: fading today would bias the comparison.
struct ThenNow<Content: View>: View {
    let now: Bool
    let comparing: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if !comparing {
            content()
        } else if now {
            content()
                .padding(8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2))
        } else {
            content()
                .padding(8)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Group {
                    if SystemDrawnSample.applies(role, place) {
                        SystemDrawnSample(role: role, place: place, sample: model.sample)
                            .help("\(role.title): drawn by macOS here; the role sets its wording and order, not its look")
                    } else {
                        RecipeControl(element: role.element, recipe: model.onCanvas(role, model.look(of: role)), system: model.system, importance: role.importance,
                                      sample: SampleWords.content(role.importance, place: place, base: model.sample))
                    }
                }
                .allowsHitTesting(false)
                // Every cell the same size: a large control (a form, a list) is drawn smaller, never over its neighbours.
                .fitted(1, maxHeight: 54)
                HStack(spacing: 4) {
                    if model.question(for: role) != nil { Circle().fill(.orange).frame(width: 6, height: 6) }
                    Text(role.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(8)
            // One width for every cell: a column, never the page (a stepper is not 1,600 points wide).
            .frame(minWidth: 180, maxWidth: 240, minHeight: 64)
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
            .frame(minWidth: 180, maxWidth: 240, minHeight: 64)
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

    /// One row per place (or per importance, for one place): only the elements that are there, as cells that wrap
    /// within the page, each named. No empty cells to read past, nothing off the edge of the window.
    var body: some View {
        let rows: [(id: String, title: String, help: String, cells: [(element: String, role: ComponentRole)], place: (String) -> String)] = {
            if let only {
                return ComponentRole.Importance.allCases.compactMap { i in
                    let cells = elements.compactMap { e in model.system.role(element: e, place: only, importance: i).map { (e, $0) } }
                    return cells.isEmpty ? nil : (i.rawValue, i.title, "", cells, { _ in only })
                }
            }
            return model.placesUsed.compactMap { place in
                let cells = elements.compactMap { e in main(e, place.id).map { (e, $0) } }
                return cells.isEmpty ? nil : (place.id, place.title, place.summary, cells, { _ in place.id })
            }
        }()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.id) { row in
                HStack(alignment: .top, spacing: 18) {
                    Text(row.title).font(.headline).frame(width: 120, alignment: .leading).padding(.top, 10).help(row.help)
                    FlowRow(spacing: 10, top: true) {
                        ForEach(row.cells, id: \.role.id) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ComponentElement.named(c.element)?.plural ?? c.element)
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                                MatrixCell(model: model, role: c.role, place: row.place(c.element), hovered: $hovered)
                            }
                            .frame(width: 190, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
                Divider()
            }
        }
    }

    /// The element's role in a place that matters most: the main action before the others.
    private func main(_ element: String, _ place: String) -> ComponentRole? {
        ComponentRole.Importance.allCases.lazy.compactMap { model.system.role(element: element, place: place, importance: $0) }.first
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
            TileGrid(minWidth: model.appearance == .both ? 620 : 360) {
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
            let actions = model.actions(element: nil, place: place)
            if !actions.isEmpty {
                InspectorSection(title: "For the Whole Place", footer: "Each shows every role it changes first; a role that also sits elsewhere can change everywhere or only here.") {
                    ActionRows(model: model, actions: actions)
                }
            }
            InspectorSection(title: "One Look Here") {
                // One action, the element chosen in its menu: not a row per element saying the same thing.
                Menu {
                    ForEach(elements, id: \.self) { e in
                        Button(ComponentElement.named(e)?.plural ?? e) { model.request = .setting(element: e, place: place) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("One Look for Every…").font(.callout)
                            Text("Choose an element, then a setting and its value").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
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
            if model.selection == .all {
                Text("Each cell is an element's most important role in a place. Read across a row to see if a place holds together; point at a cell to see where else its role sits.")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
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
                if let element, element.needs(model.look(of: role), newerThan: model.system.minimumMacOSNumber) != nil {
                    OlderMacOSSection(model: model, role: role, element: element)
                }
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
                    if let j = model.drawsLikeEarlier(role, question, i) {
                        Text(sameNote(role, question, j)).font(.caption2).foregroundStyle(.orange)
                    }
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
    /// Wide enough that the sample is drawn near its real size, so options can be told apart.
    static func width(_ element: String) -> CGFloat {
        ["picker": 150, "switcher": 160, "row": 220, "card": 220, "sheet": 220, "toast": 180, "emptyState": 220, "field": 150, "textEditor": 200,
         "table": 220, "datePicker": 150, "slider": 150, "progress": 150, "gauge": 150, "stepper": 110, "controlGroup": 120, "menu": 100,
         "toggle": 96][element] ?? 84
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

    /// "Also draws like: Glass, Bordered" for a value with twins.
    private func twinsNote(_ p: ComponentParameter, _ value: String?) -> String {
        let twins = p.twins(of: value ?? p.systemDefault ?? "")
        return twins.isEmpty ? "" : "\nOn macOS 27 these draw the same: " + twins.map { ComponentWords.value(element: element.id, parameter: p.id, value: $0) }.joined(separator: ", ") + "."
    }

    /// One value of a setting, drawn on the role.
    private func chip(_ p: ComponentParameter, _ value: String?, _ recipe: [String: String]) -> some View {
        var tried = recipe
        if let value, value != p.systemDefault { tried[p.id] = value } else { tried[p.id] = nil }
        let current = (recipe[p.id] ?? p.systemDefault) == (value ?? p.systemDefault)
        let name = value.map { ComponentWords.value(element: element.id, parameter: p.id, value: $0) } ?? "macOS default"
        let need = value.flatMap { p.needs($0) }.flatMap { $0 > model.system.minimumMacOSNumber ? $0 : nil }
        let fallback = value.flatMap { p.fallback[$0] }.map { ComponentWords.value(element: element.id, parameter: p.id, value: $0) } ?? "macOS default"
        return Button { model.tryValue(p, value) } label: {
            VStack(spacing: 4) {
                RecipeControl(element: element.id, recipe: tried, system: model.system, importance: role.importance,
                              sample: SampleWords.content(role.importance, place: role.places.first ?? "page", base: SampleContent()))
                    .allowsHitTesting(false)
                    .fitted()
                Text(name).font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(current ? .primary : .secondary)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .background(current ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(current ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: current ? 1.5 : 0.5))
            .overlay(alignment: .topTrailing) {
                if let need {
                    // Newer than the app's oldest macOS: it falls back there.
                    Text("\(Int(need))+").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.purple, in: Capsule()).offset(x: 4, y: -5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help((value ?? "macOS default") + twinsNote(p, value) + (need.map { "\nmacOS \(Int($0)) and later. On macOS \(model.oldestMacOSTitle): \(fallback)." } ?? ""))
    }
}

/// What the role draws on the app's oldest macOS, for each setting that needs a newer one: the nearest look by default,
/// or the owner's own choice.
struct OlderMacOSSection: View {
    @ObservedObject var model: DesignerModel
    let role: ComponentRole
    let element: ComponentElement

    var body: some View {
        let recipe = model.look(of: role)
        let min = model.system.minimumMacOSNumber
        let newer = element.parameters.filter { p in recipe[p.id].flatMap { p.needs($0) }.map { $0 > min } ?? false }
        InspectorSection(title: "On macOS \(model.oldestMacOSTitle)", footer: "\(model.appName) still runs on macOS \(model.oldestMacOSTitle), which doesn't have these. Turn on macOS \(model.oldestMacOSTitle) above the canvas to see it.") {
            ForEach(newer, id: \.id) { p in
                let v = recipe[p.id]!
                let nearest = p.fallback[v].map { ComponentWords.value(element: element.id, parameter: p.id, value: $0) } ?? "macOS default"
                let options = p.values.filter { o in (p.needs(o) ?? 0) <= min && !p.deprecated.contains(o) }
                Picker("\(p.title): \(ComponentWords.value(element: element.id, parameter: p.id, value: v))", selection: Binding(
                    get: { role.fallbacks[p.id] ?? "" },
                    set: { model.setFallback(role, parameter: p.id, value: $0.isEmpty ? nil : $0) })) {
                    Text("Nearest: \(nearest)").tag("")
                    Divider()
                    ForEach(options, id: \.self) { o in Text(ComponentWords.value(element: element.id, parameter: p.id, value: o)).tag(o) }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

/// The same key choices for every role of an element at once (CD50): "Capsule for every button" in one click,
/// previewed on the canvas under a banner, kept as one change. Roles where a value doesn't apply are left as they are.
struct ElementChoices: View {
    @ObservedObject var model: DesignerModel
    let element: ComponentElement

    var body: some View {
        InspectorSection(title: "Look for All \(element.plural)", footer: "Applies to every \(element.title.lowercased()) where it fits; menus and alerts that macOS draws are left alone. Previewed first.") {
            // Only settings some role can use (a toggle's "button look" needs a toggle drawn as a button), each drawn on
            // a role where it applies, so no option is drawn identical to the next.
            let roles = model.system.roles(of: element.id)
            ForEach(element.keyParameters.filter { p in roles.contains { p.applies(to: model.look(of: $0)) } }, id: \.id) { p in
                // Only what the setting needs from a role (a toggle's style for its button look), never the role's own
                // key or style, so "macOS default" is drawn as macOS draws it.
                let needs = Set(p.requires.keys)
                let base = (roles.map { model.look(of: $0) }.first { p.applies(to: $0) } ?? [:]).filter { needs.contains($0.key) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.title).font(.callout.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: ChoiceTile.width(element.id)), spacing: 6, alignment: .top)], alignment: .leading, spacing: 6) {
                        ForEach(model.choices(of: p), id: \.self) { value in
                            Button { model.tryBatch(model.batchSetting(p, value, element: element.id, place: nil)) } label: {
                                VStack(spacing: 4) {
                                    RecipeControl(element: element.id, recipe: base.merging([p.id: value ?? p.systemDefault ?? ""]) { $1 }.filter { !$0.value.isEmpty },
                                                  system: model.system, importance: .other,
                                                  sample: SampleWords.content(.other, place: "page", base: SampleContent()))
                                        .allowsHitTesting(false).fitted()
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
            let actions = model.actions(element: element, place: nil)
            let clear = model.clearQuestions(element)
            if !actions.isEmpty || !clear.isEmpty {
                InspectorSection(title: "For All \(ComponentElement.named(element)?.plural ?? element)",
                                 footer: "Each shows every role it changes before anything is saved.") {
                    if !clear.isEmpty {
                        ActionRow(title: "Accept the clear ones", detail: clear.compactMap { $0.role.flatMap { model.system.role($0)?.title } }.joined(separator: ", "),
                                  symbol: "checkmark.circle", tint: .green) { model.acceptClear(element) }
                    }
                    ActionRows(model: model, actions: actions)
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
                // An edge, so a white or window-coloured swatch is seen on the page.
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
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
    /// The rule under the pointer: its "Make It a Setting" shows there, not on every rule.
    @State private var hovered: String?

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
                                .opacity(hovered == kind.id ? 1 : 0)
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
                .onHover { if $0 { hovered = kind.id } else if hovered == kind.id { hovered = nil } }
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

/// A sample drawn whole: at most `maxScale`, smaller when it is wider than its tile (or taller than `maxHeight`),
/// never cropped and never spilling over its neighbours.
struct FittedPreview<C: View>: View {
    var maxScale: CGFloat = 0.8
    var maxHeight: CGFloat? = nil
    @ViewBuilder var content: () -> C
    @State private var natural = CGSize(width: 1, height: 30)
    @State private var available: CGFloat = 80

    var body: some View {
        let scale = min(maxScale, available / max(natural.width, 1), maxHeight.map { $0 / max(natural.height, 1) } ?? .infinity)
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: maxHeight ?? max(34, natural.height * scale))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
            .overlay {
                content().fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
                    .scaleEffect(scale)
            }
    }
}

extension View {
    func fitted(_ maxScale: CGFloat = 0.8, maxHeight: CGFloat? = nil) -> some View { FittedPreview(maxScale: maxScale, maxHeight: maxHeight) { self } }
}

/// Why two options draw alike: "Looks the same as “Standard button, icon and text” in the toolbar, which draws a
/// button as its icon only."
func sameNote(_ role: ComponentRole, _ q: ComponentQuestion, _ j: Int) -> String {
    let other = q.options[j].recipe.map { ComponentWords.look(element: role.element, recipe: ComponentElement.named(role.element)?.look($0) ?? $0) } ?? q.options[j].title
    if role.element == "button", role.places.allSatisfy({ $0 == "toolbar" }) {
        // Measured on a real macOS 27 toolbar: a button shows its icon only, whatever its label style.
        return "Looks the same as “\(other)” in the toolbar, which draws a button as its icon only."
    }
    return "Draws the same as “\(other)” here."
}
