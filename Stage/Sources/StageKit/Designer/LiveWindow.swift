// hatch-inventory: samples (this file draws sample controls; they are not the app's own looks)
import SwiftUI
import HatchCore
import HatchComponentKit

// The live window (decision NF2): the app's own shell (split view, stack or tabs; toolbar, inspector, search), opened
// for real, with the roles in their places. Sidebars, toolbars, glass, sheets, alerts, menus and popovers are SwiftUI's
// own, so what macOS decides looks exactly as it will in the app. Controls are drawn from the recipes the same way the
// generated role code draws them; the app's own custom views are not compiled here.

/// What the live window shows now, so the Designer (and the snapshot run) can open its sheet, alert or empty state.
@MainActor
final class LiveState: ObservableObject {
    @Published var sheet = false
    @Published var alert = false
    @Published var popover = false
    @Published var empty = false
    @Published var inspector = true
    @Published var selection: String? = "Desk"
    @Published var search = ""
}

struct LiveWindowView: View {
    @ObservedObject var model: DesignerModel
    @ObservedObject var live: LiveState

    private var shell: ComponentShell { model.system.shell ?? ComponentShell(navigation: .splitView, inspector: true, toolbar: true, search: true) }

    var body: some View {
        navigation
            .modifier(LiveChrome(model: model, live: live, shell: shell))
            .preferredColorScheme(model.liveScheme)
            .dynamicTypeSize(model.largeText ? .xxLarge : .large)
    }

    @ViewBuilder private var navigation: some View {
        switch shell.navigation {
        case .splitView:
            NavigationSplitView { LiveSidebar(model: model, live: live) } detail: { LivePage(model: model, live: live) }
        case .splitView3:
            NavigationSplitView { LiveSidebar(model: model, live: live) } content: { LiveList(model: model) } detail: { LivePage(model: model, live: live) }
        case .stack:
            NavigationStack { LivePage(model: model, live: live) }
        case .tabs:
            TabView {
                LivePage(model: model, live: live).tabItem { Label("Overview", systemImage: "square.grid.2x2") }
                LiveList(model: model).tabItem { Label("Tickets", systemImage: "list.bullet") }
            }
        case .plain:
            LivePage(model: model, live: live)
        }
    }
}

/// A role's control, drawn from its recipe, or nothing when the system has no role for the cell.
struct LiveRole: View {
    @ObservedObject var model: DesignerModel
    let element: String
    let place: String
    let importance: ComponentRole.Importance
    var title: String? = nil
    var symbol: String? = nil

    var body: some View {
        if let role = model.system.role(element: element, place: place, importance: importance) {
            RecipeControl(element: element, recipe: model.look(of: role), system: model.system, importance: importance, sample: sample)
                .help("\(role.id): \(role.use)")
        }
    }

    private var sample: SampleContent {
        var s = SampleWords.content(importance, place: place, base: model.sample)
        s.liveKeys = true
        if let title { s.title = title }
        if let symbol { s.symbol = symbol }
        return s
    }
}

private struct LiveChrome: ViewModifier {
    @ObservedObject var model: DesignerModel
    @ObservedObject var live: LiveState
    let shell: ComponentShell

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $live.sheet) { LiveSheet(model: model, live: live) }
            .alert("Drop this ticket?", isPresented: $live.alert) {
                LiveRole(model: model, element: "button", place: "alert", importance: .destructive, title: "Drop Ticket")
                LiveRole(model: model, element: "button", place: "alert", importance: .quiet, title: "Cancel")
            } message: {
                Text("It leaves the queue and its branch is deleted.")
            }
    }
}

/// The detail column's own toolbar, search and inspector, as an app attaches them (to the column, not the split view).
struct LivePageChrome: ViewModifier {
    @ObservedObject var model: DesignerModel
    @ObservedObject var live: LiveState
    let shell: ComponentShell

    func body(content: Content) -> some View {
        content
            .toolbar {
                if shell.toolbar {
                    if model.system.role(element: "picker", place: "toolbar", importance: .other) != nil {
                        ToolbarItem(placement: .principal) { LiveRole(model: model, element: "picker", place: "toolbar", importance: .other) }
                    }
                    ToolbarItem(placement: .primaryAction) { LiveRole(model: model, element: "button", place: "toolbar", importance: .other, title: "Refresh", symbol: "arrow.clockwise") }
                    ToolbarItem(placement: .primaryAction) { LiveRole(model: model, element: "button", place: "toolbar", importance: .other, title: "New Ticket", symbol: "plus") }
                    if model.system.role(element: "button", place: "toolbar", importance: .main) != nil {
                        ToolbarItem(placement: .primaryAction) {
                            LiveRole(model: model, element: "button", place: "toolbar", importance: .main, title: "Done", symbol: "checkmark")
                        }
                    }
                    if shell.inspector {
                        ToolbarItem {
                            Button { live.inspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                        }
                    }
                }
            }
            .modifier(LiveSearch(on: shell.search, text: $live.search))
            .modifier(LiveInspector(on: shell.inspector, model: model, live: live))
    }
}

private struct LiveSearch: ViewModifier {
    let on: Bool
    @Binding var text: String
    func body(content: Content) -> some View {
        if on { content.searchable(text: $text, placement: .toolbar) } else { content }
    }
}

private struct LiveInspector: ViewModifier {
    let on: Bool
    @ObservedObject var model: DesignerModel
    @ObservedObject var live: LiveState
    func body(content: Content) -> some View {
        if on {
            content.inspector(isPresented: $live.inspector) {
                Form {
                    Section("Ticket #142") {
                        LabeledContent("Status", value: "Building")
                        LabeledContent("Area", value: "Desk")
                        LiveRole(model: model, element: "toggle", place: "inspector", importance: .other)
                        LiveRole(model: model, element: "picker", place: "inspector", importance: .other)
                    }
                    Section {
                        HStack {
                            LiveRole(model: model, element: "button", place: "inspector", importance: .other, title: "Open", symbol: "arrow.up.forward")
                            LiveRole(model: model, element: "button", place: "inspector", importance: .quiet, title: "Show All")
                        }
                    }
                }
                .formStyle(.grouped)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
            }
        } else {
            content
        }
    }
}

private struct LiveSidebar: View {
    @ObservedObject var model: DesignerModel
    @ObservedObject var live: LiveState

    var body: some View {
        let badge = model.system.role(element: "badge", place: "listRow", importance: .other)
        List(selection: $live.selection) {
            Section("Work") {
                Label("Desk", systemImage: "tray").badge(badge != nil ? 12 : 0).tag("Desk")
                Label("Tickets", systemImage: "list.bullet").tag("Tickets")
                Label("Board", systemImage: "rectangle.split.3x1").tag("Board")
            }
            Section("Reference") {
                Label("Specs", systemImage: "doc.text").tag("Specs")
                Label("Components", systemImage: "paintpalette").tag("Components")
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

private struct LiveList: View {
    @ObservedObject var model: DesignerModel
    var body: some View {
        List {
            ForEach(["Fix the login sheet", "Toast feels cramped", "Sync stalls after sleep"], id: \.self) { title in
                LiveRow(model: model, title: title)
            }
        }
    }
}

/// A row with its row action and a context menu that follows the menu rules.
private struct LiveRow: View {
    @ObservedObject var model: DesignerModel
    let title: String

    private var icons: Bool { (model.system.rules.first { $0.kind == "menuIcons" }?.value ?? "allOrNoneInGroup") != "never" }

    var body: some View {
        HStack {
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(.teal)
            Text(title)
            Spacer()
            LiveRole(model: model, element: "button", place: "listRow", importance: .other, title: "Open", symbol: "arrow.up.forward")
        }
        .contextMenu {
            item("Open", "arrow.up.forward")
            item("Open in New Window", "macwindow")
            Divider()
            item("Park", "pause")
            item("Rename…", "pencil")
            Divider()
            Button(role: .destructive) {} label: { if icons { Label("Drop", systemImage: "trash") } else { Text("Drop") } }
        }
    }

    @ViewBuilder private func item(_ t: String, _ symbol: String) -> some View {
        Button {} label: { if icons { Label(t, systemImage: symbol) } else { Text(t) } }
    }
}

private struct LivePage: View {
    @ObservedObject var model: DesignerModel
    @ObservedObject var live: LiveState

    private var shell: ComponentShell { model.system.shell ?? ComponentShell(navigation: .splitView, inspector: true, toolbar: true, search: true) }

    var body: some View {
        content.modifier(LivePageChrome(model: model, live: live, shell: shell))
    }

    @ViewBuilder private var content: some View {
        if live.empty {
            ContentUnavailableView {
                Label("No tickets", systemImage: "tray")
            } description: {
                Text("New tickets you write appear here.")
            } actions: {
                LiveRole(model: model, element: "button", place: "emptyState", importance: .main, title: "New Ticket", symbol: "plus")
            }
            .toolbar { ToolbarItem { Button("Show Content") { live.empty = false } } }
        } else {
            page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // The demo's own links sit at the top, clear of the toast and the bottom bar (B11).
                HStack {
                    Button("Open a Sheet") { live.sheet = true }
                    Button("Open an Alert") { live.alert = true }
                    Button("Show a Popover") { live.popover = true }
                        .popover(isPresented: $live.popover) { LivePopover(model: model) }
                    Button("Show the Empty State") { live.empty = true }
                }
                .buttonStyle(.link)
                .font(.caption)
                Text("Toast feels cramped").font(.title2.bold())
                HStack(spacing: 8) {
                    LiveRole(model: model, element: "button", place: "actionRow", importance: .main, title: "Accept", symbol: "checkmark")
                    LiveRole(model: model, element: "button", place: "actionRow", importance: .other, title: "Share", symbol: "square.and.arrow.up")
                    LiveRole(model: model, element: "menu", place: "actionRow", importance: .other)
                    LiveRole(model: model, element: "menu", place: "actionRow", importance: .quiet)
                }
                card
                List {
                    ForEach(["Fix the login sheet", "Toast feels cramped", "Sync stalls after sleep"], id: \.self) { LiveRow(model: model, title: $0) }
                }
                .frame(height: 150)
                Form {
                    Section("Settings") {
                        LiveRole(model: model, element: "toggle", place: "form", importance: .other)
                        LiveRole(model: model, element: "picker", place: "form", importance: .other)
                        LiveRole(model: model, element: "field", place: "form", importance: .other)
                        LiveRole(model: model, element: "button", place: "form", importance: .quiet, title: "Show All")
                    }
                }
                .formStyle(.grouped)
                .frame(height: 220)
                .scrollDisabled(true)
            }
            .padding()
            .frame(maxWidth: 760, alignment: .leading)
        }
        .safeAreaBar(edge: .bottom) {
            if model.system.role(element: "button", place: "bottomBar", importance: .main) != nil {
                HStack {
                    LiveRole(model: model, element: "button", place: "bottomBar", importance: .other, title: "Later", symbol: "clock")
                    Spacer()
                    LiveRole(model: model, element: "button", place: "bottomBar", importance: .main, title: "Answer", symbol: "checkmark")
                }
                .padding()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.system.role(element: "toast", place: "floating", importance: .other) {
                RecipeControl(element: "toast", recipe: model.look(of: toast), system: model.system).padding(.bottom, 70)
            }
        }
    }

    @ViewBuilder private var card: some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Status", value: "Building")
            LabeledContent("Area", value: "Desk")
            LiveRole(model: model, element: "button", place: "card", importance: .other, title: "Open", symbol: "arrow.up.forward")
        }
        if let role = model.system.role(element: "card", place: "page", importance: .other) {
            switch model.look(of: role)["container"] {
            case "groupBox": GroupBox("Details") { content }
            case "formSection": Form { Section("Details") { content } }.formStyle(.grouped).frame(height: 150).scrollDisabled(true)
            default: RecipeControl(element: "card", recipe: model.look(of: role), system: model.system)
            }
        } else {
            GroupBox("Details") { content }
        }
    }
}

private struct LivePopover: View {
    @ObservedObject var model: DesignerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details").font(.headline)
            LabeledContent("Status", value: "Building")
            LiveRole(model: model, element: "picker", place: "popover", importance: .other)
            LiveRole(model: model, element: "button", place: "popover", importance: .other, title: "Open", symbol: "arrow.up.forward")
        }
        .padding()
        .frame(width: 260)
    }
}

private struct LiveSheet: View {
    @ObservedObject var model: DesignerModel
    @ObservedObject var live: LiveState

    var body: some View {
        let sizing = model.system.role(element: "sheet", place: "page", importance: .other).map { model.look(of: $0)["sizing"] ?? "automatic" } ?? "automatic"
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Area").font(.headline)
            Text("The new name shows on every ticket in this area.").foregroundStyle(.secondary)
            TextField("Name", text: .constant("Desk"))
            HStack {
                Spacer()
                LiveRole(model: model, element: "button", place: "sheetFooter", importance: .quiet, title: "Cancel")
                LiveRole(model: model, element: "button", place: "sheetFooter", importance: .main, title: "Rename")
            }
        }
        .padding(20)
        .frame(width: 420)
        .modifier(LiveSizing(sizing: sizing))
        .onSubmit { live.sheet = false }
    }
}

private struct LiveSizing: ViewModifier {
    let sizing: String
    func body(content: Content) -> some View {
        switch sizing {
        case "form": content.presentationSizing(.form)
        case "page": content.presentationSizing(.page)
        case "fitted": content.presentationSizing(.fitted)
        default: content
        }
    }
}
