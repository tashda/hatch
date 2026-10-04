import SwiftUI
import AppKit
import HatchCore

/// Components (decisions CO1 to CO8): the selected project's named colors, type, sizes and shared views, read from the
/// app's code on this Mac, and the values still typed straight into views. Hatch draws the tokens itself; views are
/// listed by name, since Hatch never compiles project code (they are drawn live in a Proposal's Stage).
struct ComponentsView: View {
    @EnvironmentObject var state: AppState
    @State private var loaded: Loaded?
    @State private var loading = false
    @State private var section: Section = .all
    @State private var filter = ""
    @State private var message: String?

    enum Section: Hashable { case all, colors, type, sizes, views }

    /// What one read of the app's clone found.
    struct Loaded {
        var projectId: Int
        var components: ComponentsConfig?
        var label: String?
        var hasClone: Bool
        var folderExists: Bool
        var catalog: ComponentCatalog?
        var scan: ComponentsScan?
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
    }

    // MARK: Header

    private func header(_ project: Project) -> some View {
        HStack(spacing: 12) {
            HXHeader(title: "Components", subtitle: subtitle(project))
            Spacer()
            if loaded?.catalog.map({ !$0.isEmpty }) == true {
                HXDock(items: [.init(id: .all, title: "All"), .init(id: .colors, title: "Colors", count: loaded?.catalog?.colors.count),
                               .init(id: .type, title: "Type", count: loaded?.catalog?.fonts.count),
                               .init(id: .sizes, title: "Sizes", count: loaded?.catalog?.sizes.count),
                               .init(id: .views, title: "Views", count: loaded?.catalog?.views.count)],
                       selection: $section)
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            Button { Task { await load() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .buttonStyle(.glass)
                .disabled(loading)
                .help("Read the app's code again")
        }
        .padding(16)
        .floatingCard()
    }

    private func subtitle(_ project: Project) -> String {
        guard let label = project.config?.componentsLabel else { return "Named colors, type, sizes and shared views for \(project.name)." }
        if let product = project.config?.components?.product { return "\(label), import \(product)" }
        if project.config?.components != nil { return "\(label), a folder in the app (not a package yet)" }
        return label
    }

    // MARK: Content

    @ViewBuilder private func content(_ project: Project) -> some View {
        if let loaded, loaded.projectId == project.id {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4) }
                    if !loaded.hasClone {
                        noClone
                    } else if loaded.label == nil {
                        setupCard(project, loaded)
                    } else if !loaded.folderExists {
                        notMadeYet(project, loaded)
                    } else if let catalog = loaded.catalog {
                        if catalog.isEmpty { emptyCatalog(loaded) } else { sections(catalog) }
                    }
                    if loaded.label != nil { decisionsCard(project) }
                    if loaded.hasClone, let scan = loaded.scan, loaded.label != nil {
                        otherSetsCard(project, loaded, scan)
                        typedCard(project, loaded, scan)
                    }
                }
                .padding(3)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Reading \(project.name)'s code…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .floatingCard()
        }
    }

    private var noClone: some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("No clone of the app on this Mac", systemImage: "folder.badge.questionmark").font(.headline)
                Text("Hatch reads the components from the app's code. Choose its folder in Project settings.").foregroundStyle(.secondary)
                Button("Project Settings") { state.navigate(to: .projects) }.buttonStyle(.glass)
            }
        }
    }

    /// No components yet: use one Hatch found, or start them with draft tickets.
    private func setupCard(_ project: Project, _ loaded: Loaded) -> some View {
        let candidates = loaded.scan?.candidates ?? []
        let start = ComponentsConfig.suggested(appName: project.name)
        return HXCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No components yet").font(.headline)
                    Text("Named colors, type, sizes and shared views that every screen uses. With them, a Proposal shows \(project.name)'s real look, and agents reuse them instead of copying values from other views.")
                        .foregroundStyle(.secondary)
                }
                if !candidates.isEmpty {
                    Text("Found in the code").font(.subheadline.weight(.semibold))
                    ForEach(Array(candidates.prefix(4).enumerated()), id: \.element.path) { index, c in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.path).font(.callout.monospaced())
                                Text(c.summary + (c.isPackage ? "" : " · a folder in the app, not a package")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index == 0 {
                                Button("Use These") { use(project, c.config) }.buttonStyle(.glassProminent)
                            } else {
                                Button("Use") { use(project, c.config) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    Divider()
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start them in \(Text(start.path).font(.callout.monospaced()))")
                        Text(startDetail(loaded.scan)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if candidates.isEmpty {
                        Button("Start Components") { begin(project, start, scan: loaded.scan) }.buttonStyle(.glassProminent)
                    } else {
                        Button("Start") { begin(project, start, scan: loaded.scan) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }

    private func startDetail(_ scan: ComponentsScan?) -> String {
        guard let scan else { return "Hatch adds a draft ticket for an agent to make a small local package." }
        guard let typed = scan.typedSummary, !scan.isSmall else {
            return "Adds one draft ticket: an agent makes a small local package with Apple's defaults given names. You submit it from the Desk."
        }
        return "The app types \(typed) into views. Adds draft tickets: one starts the package, then one per kind moves the values over. You submit them from the Desk."
    }

    private func notMadeYet(_ project: Project, _ loaded: Loaded) -> some View {
        let ticket = ((try? state.store.tickets(TicketFilter(projectId: project.id))) ?? [])
            .first { $0.title == ComponentsSetup.startTitle && $0.status != .done && $0.status != .dropped }
        return HXCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(loaded.label ?? "") is not made yet", systemImage: "hammer").font(.headline)
                Text(ticket == nil ? "The folder is not in the app's clone. Pull the latest code, or choose another folder in Project settings."
                                   : "\(ticket!.displayNumber) \(ticket!.title) makes it. It is \(ticket!.status.displayName).")
                    .foregroundStyle(.secondary)
                HStack {
                    if let ticket { Button("Open \(ticket.displayNumber)") { state.open(ticket) }.buttonStyle(.glass) }
                    Button("Project Settings") { state.navigate(to: .projects) }.buttonStyle(.glass)
                }
            }
        }
    }

    private func emptyCatalog(_ loaded: Loaded) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Nothing in \(loaded.label ?? "the components") yet", systemImage: "tray").font(.headline)
                Text("Hatch looks for `static let` colors, fonts and sizes, public views and styles, and color sets in asset catalogs.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sections

    private func matches(_ name: String) -> Bool {
        let f = filter.trimmingCharacters(in: .whitespaces)
        return f.isEmpty || name.localizedCaseInsensitiveContains(f)
    }

    @ViewBuilder private func sections(_ c: ComponentCatalog) -> some View {
        let colors = c.colors.filter { matches($0.name) }, fonts = c.fonts.filter { matches($0.name) }
        let sizes = c.sizes.filter { matches($0.name) }, views = c.views.filter { matches($0.name) }
        if (section == .all || section == .colors) && !colors.isEmpty { colorsCard(colors) }
        if (section == .all || section == .type) && !fonts.isEmpty { typeCard(fonts) }
        if (section == .all || section == .sizes) && !sizes.isEmpty { sizesCard(sizes) }
        if (section == .all || section == .views) && !views.isEmpty { viewsCard(views) }
    }

    private func sectionTitle(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.headline)
            Text("\(count)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func colorsCard(_ colors: [ColorToken]) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Colors", colors.count)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(colors, id: \.name) { ComponentSwatch(token: $0) }
                }
            }
        }
    }

    private func typeCard(_ fonts: [FontToken]) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Type", fonts.count)
                ForEach(fonts, id: \.name) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("The quick brown fox").font(ComponentRender.font(f)).lineLimit(1)
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(f.name).font(.caption.monospaced()).textSelection(.enabled)
                            Text(f.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .help(f.file)
                }
            }
        }
    }

    private func sizesCard(_ sizes: [SizeToken]) -> some View {
        let largest = max(1, sizes.map(\.value).max() ?? 1)
        return HXCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Sizes", sizes.count)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(sizes, id: \.name) { s in
                        GridRow {
                            Text(s.name).font(.caption.monospaced()).textSelection(.enabled)
                            Text(ComponentRender.number(s.value)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Capsule().fill(.quaternary)
                                .frame(width: max(2, 220 * CGFloat(min(s.value, largest) / largest)), height: 6)
                        }
                        .help(s.file)
                    }
                }
            }
        }
    }

    private func viewsCard(_ views: [ViewEntry]) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Views and styles", views.count)
                Text("Listed by name. Hatch never builds the app's code; a Proposal's Stage draws them live.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], alignment: .leading, spacing: 6) {
                    ForEach(views, id: \.name) { v in
                        HStack(spacing: 6) {
                            Image(systemName: v.kind == .view ? "square.on.square" : v.kind == .style ? "paintbrush" : "wand.and.rays")
                                .foregroundStyle(.secondary).frame(width: 16)
                            Text(v.name).font(.callout.monospaced()).lineLimit(1).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .help("\(v.kind.rawValue.capitalized) in \(v.file)")
                    }
                }
            }
        }
    }

    /// Decisions about the components that wait for the owner, and a Decide session with only those (DC9).
    @ViewBuilder private func decisionsCard(_ project: Project) -> some View {
        let waiting = (try? state.store.pendingDecisions(projectId: project.id, area: ComponentsSetup.area)) ?? []
        if !waiting.isEmpty {
            HXCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(waiting.count) decision\(waiting.count == 1 ? "" : "s") about components wait for you").font(.headline)
                        Text(waiting.prefix(3).map(\.ticket.title).joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { state.openDecide(area: ComponentsSetup.area) } label: { Label("Decide", systemImage: "checklist") }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    /// Other sets of components in the app besides the one in use (CO9, CO13): a rescan offers the tickets, never
    /// opens them by itself.
    @ViewBuilder private func otherSetsCard(_ project: Project, _ loaded: Loaded, _ scan: ComponentsScan) -> some View {
        let path = loaded.components?.path
        let others = scan.candidates.filter { $0.path != path }
        let chosen = scan.candidates.first { $0.path == path }
        let open = Set(((try? state.store.tickets(TicketFilter(projectId: project.id))) ?? [])
            .filter { $0.status != .done && $0.status != .dropped }.map(\.title))
        if let chosen, !others.isEmpty {
            let clashes = ComponentConflicts.clashes(chosen: chosen, others: others)
            let merges = others.map { ComponentsSetup.mergeDraft(into: chosen, from: $0) }.filter { !open.contains($0.title) }
            let question = ComponentsSetup.clashQuestion(clashes, chosen: chosen, usage: [:]).flatMap { open.contains($0.title) ? nil : $0 }
            if !merges.isEmpty || question != nil {
                HXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Other components in the app").font(.headline)
                        ForEach(others, id: \.path) { o in
                            Text("\(Text(o.path).font(.callout.monospaced())) · \(o.summary)").font(.callout).foregroundStyle(.secondary)
                        }
                        Text(clashes.isEmpty ? "Merging them into \(chosen.path) keeps one place for every color, font and size."
                                             : "\(clashes.count) name\(clashes.count == 1 ? " has" : "s have") two values. Hatch adds a Question for you to choose, then a ticket to merge.")
                            .foregroundStyle(.secondary)
                        Button("Add Tickets") { addConflictTickets(project, chosen: chosen, others: others, clashes: clashes, merges: merges, question: question != nil) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }

    private func addConflictTickets(_ project: Project, chosen: ComponentsCandidate, others: [ComponentsCandidate], clashes: [NameClash],
                                    merges: [ComponentsSetup.Draft], question: Bool) {
        let app = project.config?.repo(.app)?.localPath
        Task {
            let usage = await Task.detached { app.map { ComponentConflicts.usage(of: clashes.map(\.name), appRoot: $0) } ?? [:] }.value
            let q = question ? ComponentsSetup.clashQuestion(clashes, chosen: chosen, usage: usage) : nil
            guard let count = state.addComponentTickets(projectId: project.id, drafts: [q].compactMap { $0 } + merges) else { return }
            message = "Added \(count) draft ticket\(count == 1 ? "" : "s")" + (q != nil ? ". The Question waits in Decide." : ". Read and submit them from the Desk.")
        }
    }

    /// How many values views still type in, where, and a way to move them.
    private func typedCard(_ project: Project, _ loaded: Loaded, _ scan: ComponentsScan) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Typed into views").font(.headline)
                if let summary = scan.typedSummary {
                    Text("\(summary) are written straight into views instead of taken from the components. Agents get a note about new ones on every ready; the rest move when a ticket touches them, or all at once with the tickets below.")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(scan.typedFiles, id: \.path) { f in
                            HStack(spacing: 8) {
                                Text("\(f.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                                Text(f.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    if let components = loaded.components, loaded.folderExists {
                        Button("Add Tickets to Move Them") { addMoves(project, components, scan) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    Text("None. Every view takes its colors, type and sizes from the components.").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Actions

    private func load() async {
        guard let project else { return }
        if Snapshots.demoMode { loaded = Self.demo(project); return }
        loading = true
        let config = project.config
        let result = await Task.detached { () -> Loaded in
            let app = config?.repo(.app)?.localPath.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            var l = Loaded(projectId: project.id, components: config?.components, label: config?.componentsLabel,
                           hasClone: app != nil, folderExists: false, catalog: nil, scan: nil)
            if let app { l.scan = ComponentsScanner.scan(appRoot: app, excluding: config?.components?.path) }
            if let folder = config?.componentsFolder, FileManager.default.fileExists(atPath: folder) {
                l.folderExists = true
                l.catalog = ComponentsScanner.catalog(at: folder, isPackage: config?.components.map { $0.product != nil } ?? true)
            }
            return l
        }.value
        guard self.project?.id == project.id else { return }
        loaded = result
        loading = false
    }

    private func use(_ project: Project, _ components: ComponentsConfig) {
        var config = project.config ?? ProjectConfig(name: project.name, ticketsRepo: "")
        config.components = components
        guard state.saveProject(key: project.key, name: project.name, config: config, label: "Use components") != nil else { return }
        message = "\(components.path) are \(project.name)'s components now."
        Task { await load() }
    }

    private func begin(_ project: Project, _ components: ComponentsConfig, scan: ComponentsScan?) {
        var config = project.config ?? ProjectConfig(name: project.name, ticketsRepo: "")
        config.components = components
        guard state.saveProject(key: project.key, name: project.name, config: config, label: "Start components") != nil,
              let count = state.addComponentTickets(projectId: project.id,
                                                    drafts: ComponentsSetup.drafts(appName: project.name, config: components, scan: scan,
                                                                                   existing: scan?.candidates.map(\.path) ?? [])) else { return }
        message = "Added \(count) draft ticket\(count == 1 ? "" : "s"). Read and submit them from the Desk."
        Task { await load() }
    }

    private func addMoves(_ project: Project, _ components: ComponentsConfig, _ scan: ComponentsScan) {
        guard let count = state.addComponentTickets(projectId: project.id, drafts: ComponentsSetup.moveDrafts(config: components, scan: scan, catalog: loaded?.catalog)) else { return }
        message = "Added \(count) draft ticket\(count == 1 ? "" : "s"). Read and submit them from the Desk."
    }

    /// Sample components for snapshot runs, read with the real reader from a small made-up package.
    static func demo(_ project: Project) -> Loaded {
        var catalog = ComponentCatalog()
        ComponentReader.read("""
            public extension Color {
                static let surface = Color(red: 0.97, green: 0.97, blue: 0.98)
                static let surfaceRaised = Color(white: 1)
                static let accent = Color(red: 0.17, green: 0.35, blue: 0.76)
                static let accentSoft = Color(red: 0.17, green: 0.35, blue: 0.76, opacity: 0.16)
                static let textSecondary = Color.secondary
                static let separator = Color(nsColor: .separatorColor)
                static let warning = Color(red: 0.70, green: 0.33, blue: 0.04)
            }
            public extension Font {
                static let pageTitle = Font.system(.title2, weight: .semibold)
                static let sectionTitle = Font.headline
                static let rowTitle = Font.body
                static let detail = Font.callout
                static let badge = Font.system(size: 11, weight: .semibold, design: .rounded)
            }
            public enum Spacing { public static let xs: CGFloat = 4
            }
            public extension Spacing { static let s: CGFloat = 8; }
            public enum Radius { public static let card: CGFloat = 10 }
            public struct PrimaryButton: View { public var body: some View { EmptyView() } }
            public struct Card<Content: View>: View { public var body: some View { EmptyView() } }
            public struct StatusBadge: View { public var body: some View { EmptyView() } }
            public struct QuietButtonStyle: ButtonStyle { }
            public extension View { func cardBackground() -> some View { self } }
            """, file: "Tokens.swift", requirePublic: true, into: &catalog)
        catalog.sizes += [SizeToken(name: "Spacing.m", value: 12, file: "Tokens.swift"), SizeToken(name: "Spacing.l", value: 20, file: "Tokens.swift")]
        let scan = ComponentsScan(candidates: [], typed: [.color: 3, .size: 41], typedFiles: [(path: "Sources/Editor/EditorToolbar.swift", count: 14),
                                                                                       (path: "Sources/Connections/ConnectionRow.swift", count: 9)], swiftFiles: 412)
        return Loaded(projectId: project.id, components: project.config?.components, label: project.config?.componentsLabel,
                      hasClone: true, folderExists: true, catalog: catalog, scan: scan)
    }
}

/// One color: its light value, and its dark one beside it when it has one.
private struct ComponentSwatch: View {
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
