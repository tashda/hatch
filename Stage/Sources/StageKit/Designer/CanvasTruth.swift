// hatch-inventory: samples (this file draws real containers to measure the canvas against; they are not the app's looks)
import SwiftUI
import AppKit
import HatchCore
import HatchComponentKit

// The Designer's canvas measured against macOS (decision CM25). Each place the canvas draws is built again from real
// SwiftUI containers (a real toolbar, List, grouped Form, inspector, GroupBox, empty state) holding the same roles, drawn
// by the same recipe engine with no place hint, so the container decides how they look. Both are captured quietly (the
// windows stay below the desktop picture) with every role marked, and `ComponentTruth.compareCanvas` reports each role
// drawn at another size or with another look. Sheets, popovers, alerts and menus are presented by macOS in windows of
// their own that can't be kept off the owner's screen, so the sheet and popover content is measured in a plain window and
// alerts and menus are not measured: the canvas draws those as macOS's own pictures (CD58).

@MainActor
enum CanvasTruth {
    /// The places measured, and the ones left out with the reason.
    static let measured = ["toolbar", "sheetFooter", "bottomBar", "listRow", "card", "inspector", "popover", "form", "emptyState", "actionRow"]
    static let notMeasured = ["alert": "drawn by macOS in a window of its own", "contextMenu": "an NSMenu, drawn by macOS"]

    /// Captures each place on the canvas and in its real container into `folder` (`designer-canvas-<place>-light`,
    /// `designer-real-<place>-light`) and returns what differs.
    static func run(model: DesignerModel, into folder: URL) async -> [TruthFinding] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var findings: [TruthFinding] = []
        let system = model.system
        for place in measured {
            let roles = Self.roles(system, place)
            guard !roles.isEmpty, let p = system.place(place) else { continue }
            let elements = Array(Set(roles.map(\.element))).sorted()
            // Each tile at its own height, nothing squeezed or cut, so every role is where it is drawn.
            await shoot(AnyView(Canvas(model: model, place: p, elements: elements)), name: "designer-canvas-\(place)-light",
                        size: NSSize(width: 460, height: CGFloat(elements.count) * 340 + 40), into: folder)
            // At the tile's width where the place is a column (a form, a card, a popover): what doesn't fit shows on both sides.
            let narrow = ["form", "card", "popover", "sheetFooter"].contains(place)
            await shoot(AnyView(real(place, system)), name: "designer-real-\(place)-light", size: NSSize(width: narrow ? 460 : 980, height: 460), into: folder)
            // Controls that are their own form row take the row's width, which is the column's, not theirs.
            let fills = Set(roles.filter { ["form", "inspector", "card", "popover"].contains(place) && ["toggle", "field", "datePicker", "slider", "stepper"].contains($0.element) }.map(\.id))
            guard let captures = ComponentCaptures.load(from: folder),
                  let canvas = captures.screens.first(where: { $0.name == "designer-canvas-\(place)" }),
                  let real = captures.screens.first(where: { $0.name == "designer-real-\(place)" }) else { continue }
            #if canImport(CoreGraphics)
            findings += ComponentTruth.compareCanvas(place: p.title.lowercased(), canvas: canvas, real: real, centered: place == "toolbar", inset: 20, fills: fills,
                                                     pixels: ComponentTruth.pictureDistance)
            #else
            findings += ComponentTruth.compareCanvas(place: p.title.lowercased(), canvas: canvas, real: real, centered: place == "toolbar", inset: 20, fills: fills)
            #endif
        }
        if let data = try? JSONEncoder().encode(findings) { try? data.write(to: folder.appendingPathComponent("canvas-truth.json")) }
        return findings
    }

    /// The roles in a place, quiet first and the main action last, as macOS orders them.
    static func roles(_ system: ComponentSystem, _ place: String, _ elements: [String]? = nil) -> [ComponentRole] {
        let order: [ComponentRole.Importance] = [.quiet, .destructive, .other, .main]
        return system.roles.filter { $0.places.contains(place) && (elements?.contains($0.element) ?? true) && !["form", "row"].contains($0.element) }
            .sorted { (order.firstIndex(of: $0.importance) ?? 0) < (order.firstIndex(of: $1.importance) ?? 0) }
    }

    /// A hidden window with the view, captured with its marks, then closed.
    private static func shoot(_ view: AnyView, name: String, size: NSSize, into folder: URL) async {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.level = HatchMarks.hiddenLevel
        w.toolbarStyle = .unified
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = NSHostingView(rootView: view.hatchMarksRoot().frame(minWidth: size.width, minHeight: size.height))
        w.orderBack(nil)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        HatchMarks.capture(w, as: name, into: folder)
        w.orderOut(nil)
        w.close()
    }

    /// The place as the canvas draws it: one tile per element with roles there.
    private struct Canvas: View {
        @ObservedObject var model: DesignerModel
        let place: ComponentPlace
        let elements: [String]
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(elements, id: \.self) { e in
                    PlaceFrame(place: place, element: e, model: model, today: true, framed: false).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: The real containers

    private static func control(_ r: ComponentRole, _ place: String, _ system: ComponentSystem, inForm: Bool = false) -> some View {
        var s = SampleWords.content(r.importance, place: place, base: SampleContent())
        s.place = nil
        s.inForm = inForm
        return RecipeControl(element: r.element, recipe: r.draft ?? r.recipe, system: system, importance: r.importance, sample: s)
            .hatchMark("role:" + r.id)
    }

    /// A row as an app writes it in a form, the way the canvas does: a control with its own label (toggle, field, date
    /// picker, slider, stepper, a labelled picker) is the row; a block goes under its name; anything else is labelled.
    @ViewBuilder private static func row(_ r: ComponentRole, _ place: String, _ system: ComponentSystem) -> some View {
        if ["card", "table", "textEditor", "gauge", "row"].contains(r.element) {
            VStack(alignment: .leading, spacing: 6) {
                Text(r.title).foregroundStyle(.secondary)
                control(r, place, system).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if ["toggle", "field", "datePicker", "slider", "stepper"].contains(r.element) || (r.element == "picker" && (r.draft ?? r.recipe)["label"] != "hidden") {
            control(r, place, system, inForm: true)
        } else {
            LabeledContent(r.title) { control(r, place, system) }
        }
    }

    private struct Lines: View {
        var body: some View { List(["Fix the login sheet", "Toast feels cramped", "Sync stalls after sleep", "Rename areas"], id: \.self) { Text($0) } }
    }

    @ViewBuilder static func real(_ place: String, _ system: ComponentSystem) -> some View {
        let rs = roles(system, place)
        switch place {
        case "toolbar":
            NavigationStack {
                Lines().navigationTitle("Desk").toolbar {
                    ForEach(rs.filter { !["field", "badge"].contains($0.element) }) { r in ToolbarItem { control(r, place, system) } }
                }
            }
        case "bottomBar":
            VStack(spacing: 0) {
                Lines()
                HStack {
                    ForEach(rs.filter { $0.importance != .main }) { control($0, place, system) }
                    Spacer()
                    ForEach(rs.filter { $0.importance == .main }) { control($0, place, system) }
                }
                .padding(10).background(.bar)
            }
        case "listRow":
            List(rs) { r in
                HStack { Image(systemName: "circle.lefthalf.filled").foregroundStyle(.teal); Text(r.title); Spacer(); control(r, place, system) }
            }
        case "card":
            ScrollView {
                GroupBox("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Status", value: "Building")
                        ForEach(rs) { r in row(r, place, system) }
                    }
                    .padding(6)
                }
                .padding(20)
            }
        case "inspector":
            Lines().inspector(isPresented: .constant(true)) {
                Form { Section("Ticket #142") { ForEach(rs.filter { $0.element != "card" }) { r in row(r, place, system) } } }.formStyle(.grouped)
                    .inspectorColumnWidth(340)
            }
        case "form":
            Form { ForEach(rs) { r in row(r, place, system) } }.formStyle(.grouped)
        case "emptyState":
            ContentUnavailableView {
                Label("No tickets", systemImage: "tray")
            } description: { Text("New tickets you write appear here.") } actions: {
                HStack { ForEach(rs.filter { $0.element == "button" }) { control($0, place, system) } }
            }
        case "sheetFooter":
            // A sheet's content and size, in a plain window (a presented sheet can't be kept hidden).
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Area").font(.headline)
                Text("The new name shows on every ticket in this area.").foregroundStyle(.secondary)
                ForEach(rs.filter { ["field", "progress"].contains($0.element) }) { control($0, place, system) }
                HStack {
                    ForEach(rs.filter { $0.element == "button" && $0.importance == .destructive }) { control($0, place, system) }
                    Spacer()
                    ForEach(rs.filter { $0.element == "button" && $0.importance != .destructive }) { control($0, place, system) }
                }
            }
            .padding(20).frame(width: 460)
        case "popover":
            VStack(alignment: .leading, spacing: 8) {
                Text("Ticket #142").font(.headline)
                ForEach(rs) { r in row(r, place, system) }
            }
            .padding(16).frame(width: 340)
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text("Toast feels cramped").font(.title2.bold())
                HStack { ForEach(rs) { control($0, place, system) } }
                Spacer()
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
