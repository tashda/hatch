// hatch-inventory: samples (this file draws sample controls; they are not the app's own looks)
import SwiftUI
import HatchCore
import HatchComponentKit

// "In place" (decision DS1): an element is never judged floating alone. Each place is drawn as a small mock of the
// real thing (a toolbar, a sheet's footer, a list, a form) with the roles that hold its cells, so a button is seen as the
// main action of a sheet or as a row action, beside its neighbours.

/// One place drawn with the element's roles in it. Clicking a control opens its role (CD8). On a role's own level the
/// other roles in the place are dimmed, so the role is judged among its neighbours.
struct PlaceFrame: View {
    let place: ComponentPlace
    let element: String
    @ObservedObject var model: DesignerModel
    /// The role judged on its own level; the place's other roles are dimmed.
    var focus: String? = nil
    /// Draw the roles as saved, without the preview (the Today column, CD14).
    var today = false
    /// Title above a frame (the element's level); the role's level puts the place's name in its own column.
    var framed = true
    /// What the title says, when not the place's name (a place's overview names the element).
    var title: String? = nil
    /// The place's name and dots above the tile; off on a role's page, which names the place beside it.
    var header = true
    @State private var hovered: String?

    /// The roles in this place, quiet first and the main action last (macOS order).
    private var cells: [ComponentRole] {
        // Every role here, a cell holding one per kind of control (CD51), quiet first and the main action last.
        let order: [ComponentRole.Importance] = [.quiet, .destructive, .other, .main]
        return model.system.roles.filter { $0.element == element && $0.places.contains(place.id) }
            .sorted { (order.firstIndex(of: $0.importance) ?? 0, $0.kind) < (order.firstIndex(of: $1.importance) ?? 0, $1.kind) }
    }

    var body: some View {
        if framed && !header {
            sample
        } else if framed {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title ?? place.title).font(.headline)
                    // Something to decide here (CD10): an orange dot, nothing more.
                    if cells.contains(where: { model.question(for: $0) != nil }) {
                        Circle().fill(.orange).frame(width: 7, height: 7).help("A look to decide here")
                    }
                    if cells.contains(where: { model.isPreviewing($0) }) { Text("Preview").font(.caption).foregroundStyle(.orange) }
                }
                .help(place.summary)
                Appearances(model: model) { sample }
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            // A tile is its column's width. A Form's ideal width is infinite (measured), so the tile states its own ideal:
            // a grid that sizes columns by ideal width would otherwise make the column as wide as it can.
            .frame(minWidth: 0, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contextMenu {
                ForEach(cells, id: \.id) { r in Button("Open \(r.title)") { model.open(r.id) } }
                Divider()
                BatchMenuItems(model: model, element: element, place: place.id)
            }
        } else {
            sample
        }
    }

    /// Every place is the same tile: one frame, one height on a page, a hairline edge, and a slice of a real window
    /// inside it (the top of a window under its toolbar, a sheet over a dimmed window), so the eye compares the controls,
    /// not the boxes. The window's own surface is never a box inside a box of the same colour.
    @ViewBuilder private var sample: some View {
        mock
            .frame(minWidth: 0, idealWidth: 380, maxWidth: .infinity, minHeight: framed ? Self.tileHeight : 76, maxHeight: framed ? .infinity : nil,
                   alignment: .topLeading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    static let tileHeight: CGFloat = 176

    /// The look a role is drawn with here.
    private func recipe(_ role: ComponentRole) -> [String: String] {
        model.onCanvas(role, today ? (role.draft ?? role.recipe) : model.look(of: role))
    }

    /// Drawn with a look that is being tried and differs from today's.
    private func changed(_ role: ComponentRole) -> Bool {
        !today && model.isChanged(role)
    }

    /// How strongly a role shows: the focused role (or the one under the pointer) in full, the rest dimmed.
    private func emphasis(_ role: ComponentRole) -> Double {
        if let focus { return role.id == focus ? 1 : 0.35 }
        if let hovered { return role.id == hovered ? 1 : 0.4 }
        return 1
    }

    /// A role's control; a click opens its role. The control itself takes no clicks (a menu would open, a toggle flip),
    /// so every control on the canvas can be chosen the same way; under the pointer it is outlined and named, which shows
    /// what can be edited.
    @ViewBuilder func control(_ role: ComponentRole, padded: Bool = true) -> some View {
        RecipeControl(element: element, recipe: recipe(role), system: model.system, importance: role.importance,
                      sample: SampleWords.content(role.importance, place: place.id, base: model.sample))
            .allowsHitTesting(false)
            .padding(padded ? 3 : 0)
            .opacity(emphasis(role))
            .overlay {
                if hovered == role.id {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1.5)
                } else if changed(role) {
                    // What a preview changes is outlined where it is, so a change is seen at a glance; no fill, which
                    // would tint the control and read as an error on a large block.
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if changed(role) && hovered != role.id {
                    Text("Changed").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.orange, in: Capsule())
                        .offset(x: 6, y: -8).fixedSize()
                }
            }
            .overlay(alignment: .bottom) {
                if hovered == role.id {
                    Text("Edit \(role.title)").font(.caption2.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .offset(y: 16).fixedSize()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.open(role.id) }
            .onHover { hovered = $0 ? role.id : (hovered == role.id ? nil : hovered) }
            .zIndex(hovered == role.id ? 1 : 0)
            .help("\(role.title): \(role.use)")
    }

    /// The place's controls, wrapping onto a new line rather than ever cutting a label short.
    @ViewBuilder private func controls(trailing: Bool = false) -> some View {
        if element == "badge" && place.id == "toolbar", let role = cells.first {
            // A toolbar badge sits on a toolbar item (B7).
            Image(systemName: "tray").font(.title3).foregroundStyle(.secondary)
                .overlay(alignment: .topTrailing) { control(role).offset(x: 9, y: -8) }
                .padding(.trailing, 8)
        } else {
            FlowRow(trailing: trailing) { ForEach(cells, id: \.id) { control($0) } }
        }
    }

    /// Grey lines where the window's own content would be: `lines` of them always, and as many more as the tile's row
    /// leaves room for. The extra lines never make a tile taller; they only fill what its row gives it.
    @ViewBuilder private func content(_ lines: Int = 3) -> some View {
        if framed {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: CGFloat(lines) * 17 + 24, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<16, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.6))
                                .frame(maxWidth: [180, 240, 140, 200][i % 4]).frame(height: 7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .clipped()
        }
    }

    /// A window's title bar, for places that sit in or over a window.
    private func titleBar<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 11)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 11)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 11)
                }
                Text("Desk").font(.headline).padding(.leading, 8).fixedSize()
                Spacer(minLength: 12)
                trailing()
            }
            // A macOS 26 toolbar has no bar or line of its own: its items float in glass over the window.
            .padding(.horizontal, 12).frame(minHeight: 52)
        }
    }

    /// A window behind a sheet, alert or menu: its title bar and content, dimmed as macOS dims it.
    private var dimmedWindow: some View {
        VStack(spacing: 0) { titleBar { EmptyView() }; content(4); Spacer(minLength: 0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(Self.dimColor)
            .allowsHitTesting(false)
    }

    /// A surface over the window (sheet, popover, alert, menu), lifted by its shadow and edge. In dark it is lighter
    /// than the window, as macOS 27 draws it (measured: a sheet at 45,44,43 over a window at 31,30,30).
    static let raisedColor = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 45 / 255, green: 44 / 255, blue: 43 / 255, alpha: 1) : .white
    })
    /// How much macOS dims the window behind a sheet or alert: more in dark, where the window is already dark.
    static let dimColor = Color(nsColor: NSColor(name: nil) { a in
        NSColor.black.withAlphaComponent(a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.32 : 0.07)
    })

    private func raised<C: View>(radius: CGFloat = 12, @ViewBuilder _ c: () -> C) -> some View {
        c().background(Self.raisedColor, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }

    /// A row of a form: a control that carries its own label (a toggle, a field, a picker) goes in as itself, as an
    /// app writes it; a button gets the role's name beside it.
    @ViewBuilder private func formRow(_ role: ComponentRole) -> some View {
        if ["card", "table", "textEditor", "gauge", "row"].contains(role.element) {
            // A block takes the row's whole width under its name, not the trailing slot of a label.
            VStack(alignment: .leading, spacing: 6) {
                Text(role.title).foregroundStyle(.secondary)
                control(role, padded: false).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if ["toggle", "field", "datePicker", "slider", "stepper"].contains(role.element) || (role.element == "picker" && recipe(role)["label"] != "hidden") {
            control(role, padded: false)
        } else {
            LabeledContent(role.title) { control(role, padded: false) }
        }
    }

    /// A system alert's button: full width, a capsule, red for destructive, accent for the default, grey otherwise.
    private func alertButton(_ role: ComponentRole) -> some View {
        let title = SampleWords.content(role.importance, place: "alert", base: model.sample).shownTitle
        let fill: AnyShapeStyle = role.importance == .destructive ? AnyShapeStyle(Color.red.opacity(0.18))
            : role.importance == .main ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)
        return Text(title).font(.system(size: 13))
            .foregroundStyle(role.importance == .destructive ? Color.red : role.importance == .main ? .white : .primary)
            .frame(maxWidth: .infinity).frame(height: 28)
            .background(fill, in: Capsule())
            .opacity(emphasis(role))
            .overlay { if hovered == role.id { Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5) } }
            .contentShape(Capsule())
            .onTapGesture { model.open(role.id) }
            .onHover { hovered = $0 ? role.id : (hovered == role.id ? nil : hovered) }
    }

    /// A role's lines in a context menu, as NSMenu draws them: a toggle with its checkmark, a choice as checked items
    /// after a separator, a submenu with its chevron.
    @ViewBuilder private func menuLines(_ role: ComponentRole) -> some View {
        let lines: [(check: Bool, title: String, sub: Bool, red: Bool)] = {
            switch role.element {
            case "toggle": return [(true, "Show Done", false, false)]
            case "picker":
                // Each choice role gets its own words, so two pickers don't read as one list twice.
                let i = cells.filter { $0.element == "picker" }.firstIndex { $0.id == role.id } ?? 0
                let pairs = [("By Date", "By Area"), ("Small", "Large"), ("List", "Board")]
                let p = pairs[i % pairs.count]
                return [(true, p.0, false, false), (false, p.1, false, false)]
            case "menu": return [(false, "Move To", true, false)]
            default:
                let t = SampleWords.content(role.importance, place: "contextMenu", base: model.sample).shownTitle
                // A real NSMenu draws a destructive item like any other (captured on macOS 27).
                return [(false, role.importance == .destructive ? t + "…" : t, false, false)]
            }
        }()
        if role.element == "picker" { Divider().padding(.vertical, 4).padding(.horizontal, 8) }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).opacity(l.check ? 1 : 0).frame(width: 14)
                    Text(l.title).foregroundStyle(l.red ? .red : .primary)
                    Spacer(minLength: 8)
                    if l.sub { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 6).frame(height: 22)
            }
        }
        .background(hovered == role.id ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .opacity(emphasis(role))
        .onTapGesture { model.open(role.id) }
        .onHover { hovered = $0 ? role.id : (hovered == role.id ? nil : hovered) }
        .help("\(role.title): \(role.use)")
    }

    @ViewBuilder private var mock: some View {
        switch place.id {
        case _ where element == "emptyState":
            // The empty state is the place: drawn once, not inside another one.
            HStack(spacing: 12) { ForEach(cells, id: \.id) { control($0, padded: false) } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
        case _ where element == "sheet":
            // A sheet over its dimmed window, as it is seen.
            ZStack {
                if framed { dimmedWindow }
                HStack(spacing: 12) { ForEach(cells, id: \.id) { control($0, padded: false) } }
                    .padding(.top, framed ? 52 : 10).padding(.bottom, framed ? 20 : 10)
            }
        case "inspector" where element == "form" || element == "card", "card" where element == "form", "form" where element == "form" || element == "card", "page" where element == "form":
            // A form layout or a card here is the panel's own content, drawn once, not a box inside a form.
            VStack(spacing: 0) {
                ForEach(cells, id: \.id) { control($0, padded: false).frame(maxWidth: .infinity, alignment: .topLeading) }
            }
            .padding(8)
            .frame(maxHeight: .infinity, alignment: .top)
        case "toolbar":
            VStack(spacing: 0) {
                titleBar {
                    if element == "badge" { controls(trailing: true) } else {
                        ToolbarGlassRow(cells.map { (id: $0.id, glass: ToolbarGlass.of(element: element, recipe: recipe($0))) }) { id in
                            if let role = cells.first(where: { $0.id == id }) { control(role, padded: false) }
                        }
                    }
                }
                content()
            }
        case "bottomBar":
            VStack(spacing: 0) {
                content()
                Spacer(minLength: 0)
                Divider()
                HStack {
                    FlowRow { ForEach(cells.filter { $0.importance != .main }, id: \.id) { control($0) } }
                    Spacer(minLength: 12)
                    FlowRow(trailing: true) { ForEach(cells.filter { $0.importance == .main }, id: \.id) { control($0) } }.fixedSize()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.bar)
            }
            .frame(minHeight: framed ? Self.tileHeight : 76)
        case "sheetFooter":
            // A macOS 27 sheet: centred over the dimmed window, the destructive action apart on the leading side.
            ZStack {
                if framed { dimmedWindow }
                raised(radius: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rename Area").font(.headline)
                        Text("The new name shows on every ticket in this area.").font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        // Bottom-aligned: when the buttons wrap, the destructive one stays on the last line, beside Save.
                        HStack(alignment: .bottom, spacing: 8) {
                            HStack(spacing: 8) { ForEach(cells.filter { $0.importance == .destructive }, id: \.id) { control($0) } }.fixedSize()
                            Spacer(minLength: 12)
                            // Wraps onto a second line when the labels are long, never past the sheet's edge.
                            FlowRow(trailing: true) { ForEach(cells.filter { $0.importance != .destructive }, id: \.id) { control($0) } }
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                    .frame(maxWidth: 440, alignment: .leading)
                }
                .padding(.horizontal, 24).padding(.top, framed ? 60 : 10).padding(.bottom, framed ? 24 : 10)
            }
        case "alert":
            // A macOS 27 alert is drawn by the system: title and message on the leading side, every button full width,
            // stacked, destructive in red and Cancel last. The app's button styles don't reach it; a role here sets
            // the wording and order.
            ZStack {
                if framed { dimmedWindow }
                raised(radius: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Drop this ticket?").font(.system(size: 13, weight: .bold))
                        Text("It leaves the queue and its branch is deleted.").font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                        if element != "button" {
                            // A field or other control in an alert sits above its buttons (an accessory view).
                            VStack(alignment: .leading, spacing: 6) { ForEach(cells, id: \.id) { control($0, padded: false) } }
                                .padding(.top, 6)
                        }
                        VStack(spacing: 6) {
                            let order: [ComponentRole.Importance] = [.destructive, .main, .other, .quiet]
                            if element == "button" {
                                ForEach(cells.sorted { (order.firstIndex(of: $0.importance) ?? 0) < (order.firstIndex(of: $1.importance) ?? 0) }, id: \.id) { role in
                                    alertButton(role)
                                }
                            } else {
                                ForEach(["Rename", "Cancel"], id: \.self) { t in
                                    Text(t).font(.system(size: 13)).foregroundStyle(t == "Rename" ? .white : .primary)
                                        .frame(maxWidth: .infinity).frame(height: 28)
                                        .background(t == "Rename" ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(14).frame(width: 240, alignment: .leading)
                }
                .padding(.top, framed ? 60 : 10).padding(.bottom, framed ? 22 : 10)
            }
            .help("Alert buttons are drawn by macOS: a role here sets wording and order, not a look.")
        case "popover":
            ZStack(alignment: .topTrailing) {
                if framed {
                    VStack(spacing: 0) {
                        titleBar {
                            Image(systemName: "info.circle").font(.system(size: 15)).frame(width: 36, height: 36)
                                .glassEffect(.regular, in: .circle)
                        }
                        content(4)
                    }
                }
                VStack(alignment: .trailing, spacing: 0) {
                    // The arrow points at the toolbar item that opened it.
                    PopoverArrow().fill(Self.raisedColor).frame(width: 18, height: 9)
                        .overlay { PopoverArrow().stroke(.separator, lineWidth: 0.5) }
                        .offset(y: 0.5).zIndex(1)
                        .padding(.trailing, 21)
                    raised {
                        if element == "form" || element == "card" {
                            // A form or card is the popover's content, sized to it within the tile.
                            VStack(alignment: .leading, spacing: 0) { ForEach(cells, id: \.id) { control($0, padded: false) } }
                                .padding(6).frame(maxWidth: 340, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ticket #142").font(.headline)
                                LabeledContent("Status", value: "Building")
                                controls().padding(.top, 2)
                            }
                            .padding(14).frame(width: 250, alignment: .leading)
                        }
                    }
                }
                .padding(.top, framed ? 46 : 10).padding(.trailing, 12).padding(.bottom, 14).padding(.leading, framed ? 0 : 12)
            }
        case "contextMenu":
            ZStack(alignment: .topLeading) {
                if framed { dimmedWindow }
                raised(radius: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(cells, id: \.id) { role in menuLines(role) }
                    }
                    // A menu is as wide as its longest item (at least 200 points), as NSMenu draws it.
                    .padding(5).frame(minWidth: 200, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                }
                .padding(.top, framed ? 56 : 10).padding(.leading, framed ? 60 : 12).padding(.bottom, 14)
            }
            .help("Menu items are drawn by macOS: a role here sets wording and order, not a look.")
        case "listRow" where element == "row":
            // A row is drawn by its own list, once (B6).
            FlowRow { ForEach(cells, id: \.id) { control($0) } }.padding(14)
        case "listRow":
            // An inset list as macOS draws it: compact rows, one control in each (a row holds one action, not every
            // role at once), separators from the text's leading edge.
            let titles = ["Fix the login sheet", "Toast feels cramped", "Sync stalls after sleep", "Rename areas", "Iris asks twice"]
            let rows = framed ? cells : Array(cells.prefix(1))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, role in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(.teal)
                        Text(titles[i % titles.count]).lineLimit(1)
                        Spacer(minLength: 12)
                        control(role, padded: false).fixedSize()
                    }
                    .padding(.horizontal, 10).frame(minHeight: 32)
                    if i < rows.count - 1 || framed { Divider().padding(.leading, 34).padding(.trailing, 10) }
                }
                if framed {
                    // The rest of the list, without controls: it fills what the row leaves, and adds no height.
                    Color.clear.frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .overlay(alignment: .top) {
                            VStack(spacing: 0) {
                                ForEach(rows.count..<rows.count + 10, id: \.self) { i in
                                    HStack(spacing: 8) {
                                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(.teal.opacity(0.5))
                                        Text(titles[i % titles.count]).foregroundStyle(.secondary).lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10).frame(minHeight: 32)
                                    Divider().padding(.leading, 34).padding(.trailing, 10)
                                }
                            }
                        }
                        .clipped()
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        case "card":
            // SwiftUI's own GroupBox, so the card is exactly what macOS draws; the page goes on under it.
            VStack(spacing: 0) {
                GroupBox("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Status", value: "Building")
                        LabeledContent("Area", value: "Desk")
                        controls().padding(.top, 4)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding([.horizontal, .top], 16)
                content(1)
            }
        case "inspector":
            // The inspector column: a grouped form on its own background beside the window's content. In a narrow
            // tile the content side goes, never the inspector's values.
            let form = Form {
                Section("Ticket #142") {
                    LabeledContent("Status", value: "Building")
                    ForEach(cells, id: \.id) { role in formRow(role) }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(minWidth: 0, maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            // A grouped form will not draw narrower than its own minimum, so the inspector takes the tile and the
            // window shows as a strip on its left, never the other way round.
            HStack(alignment: .top, spacing: 0) {
                // The strip only on a page's tile: a compare column is narrow, and the form needs all of it.
                if framed && header { content(5).frame(width: 64); Divider() }
                form.frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        case "form":
            Form {
                ForEach(cells, id: \.id) { role in formRow(role) }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(minWidth: 0, maxWidth: .infinity)
            // The form's own height, so no row is ever cut off.
            .fixedSize(horizontal: false, vertical: true)
        case "emptyState":
            ContentUnavailableView {
                Label("No tickets", systemImage: "tray")
            } description: {
                Text("New tickets you write appear here.")
            } actions: {
                controls()
            }
            .frame(maxWidth: .infinity, minHeight: framed ? Self.tileHeight : 76)
        case "actionRow":
            VStack(alignment: .leading, spacing: 10) {
                Text("Toast feels cramped").font(.title2.bold())
                Text("Desk · Building").font(.callout).foregroundStyle(.secondary)
                controls()
                if framed { content(2).padding(.horizontal, -16) }
            }
            .padding(16)
        case "floating":
            // Floating controls sit over the content (a toast is its own surface; no glass on glass), where their look says.
            let top = element == "toast" && cells.first.map { recipe($0)["position"] == "top" } == true
            ZStack(alignment: top ? .top : .bottom) {
                LinearGradient(colors: [.teal.opacity(0.35), .indigo.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if element == "toast" {
                    FlowRow { ForEach(cells, id: \.id) { control($0) } }.fixedSize().padding(12)
                } else {
                    HStack(spacing: 6) { ForEach(cells, id: \.id) { control($0) } }
                        .padding(6)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 14)
                }
            }
            .frame(minHeight: framed ? Self.tileHeight : 96)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Toast feels cramped").font(.headline)
                Text("The toast's text wraps early and the action sits too close.").font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                controls().padding(.top, 4)
            }
            .padding(16)
        }
    }
}

/// Controls in a row that wraps onto the next line when the row is full; each keeps its full size, so no label is ever
/// cut short. `trailing` puts the lines against the right edge (a sheet's buttons, a toolbar's items).
struct FlowRow: Layout {
    var trailing = false
    var spacing: CGFloat = 8
    /// Items aligned to the top of their line (cells with captions), not centred (controls in a bar).
    var top = false

    private func lines(_ width: CGFloat, _ subviews: Subviews) -> [(items: [(Int, CGSize)], width: CGFloat, height: CGFloat)] {
        var out: [(items: [(Int, CGSize)], width: CGFloat, height: CGFloat)] = []
        var current: [(Int, CGSize)] = [], w: CGFloat = 0, h: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            if !current.isEmpty, w + spacing + size.width > width {
                out.append((current, w, h)); current = []; w = 0; h = 0
            }
            w += (current.isEmpty ? 0 : spacing) + size.width
            h = max(h, size.height)
            current.append((i, size))
        }
        if !current.isEmpty { out.append((current, w, h)) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ls = lines(proposal.width ?? .infinity, subviews)
        let height = ls.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, ls.count - 1))
        let widest = ls.map(\.width).max() ?? 0
        return CGSize(width: trailing ? max(widest, min(proposal.width ?? widest, .greatestFiniteMagnitude)) : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(bounds.width, subviews) {
            var x = trailing ? bounds.maxX - line.width : bounds.minX
            for (i, size) in line.items {
                subviews[i].place(at: CGPoint(x: x, y: y + (top ? 0 : (line.height - size.height) / 2)), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }
}

/// The small arrow under a popover's edge.
struct PopoverArrow: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath() }
    }
}

/// Place tiles in equal columns, each tile exactly its column's width (it can never spill into its neighbour) and as
/// tall as the tallest tile in its row, so a page reads as one even grid. The column count comes from the width alone:
/// a page with one place shows one tile of the usual size, not one stretched across the page.
struct TileGrid: Layout {
    var minWidth: CGFloat = 340
    var spacing: CGFloat = 24
    var rowSpacing: CGFloat = 28

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (column: CGFloat, rows: [(range: Range<Int>, height: CGFloat)]) {
        // An unbounded width (an ideal-size pass) lays out two columns.
        let width = width.isFinite ? width : minWidth * 2 + spacing
        let count = max(1, Int((width + spacing) / (minWidth + spacing)))
        let column = max(minWidth, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        var rows: [(range: Range<Int>, height: CGFloat)] = [], i = 0
        while i < subviews.count {
            let r = i..<min(i + count, subviews.count)
            let h = r.map { subviews[$0].sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
            rows.append((r, h)); i = r.upperBound
        }
        return (column, rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? (minWidth * 2 + spacing)
        let a = arrange(width, subviews)
        return CGSize(width: width, height: a.rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(0, a.rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let a = arrange(bounds.width, subviews)
        var y = bounds.minY
        for row in a.rows {
            for (k, i) in row.range.enumerated() {
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(k) * (a.column + spacing), y: y),
                                  proposal: ProposedViewSize(width: a.column, height: row.height))
            }
            y += row.height + rowSpacing
        }
    }
}

/// A control in a place macOS draws itself (a context menu's items, an alert's buttons): drawn as macOS draws it there,
/// whatever the role's look says, because the look doesn't reach it.
struct SystemDrawnSample: View {
    let role: ComponentRole
    let place: String
    var sample = SampleContent()

    static func applies(_ role: ComponentRole, _ place: String) -> Bool {
        place == "contextMenu" || (place == "alert" && role.element == "button")
    }

    var body: some View {
        let title = SampleWords.content(role.importance, place: place, base: sample).shownTitle
        if place == "alert" {
            Text(title).font(.system(size: 13))
                .foregroundStyle(role.importance == .destructive ? Color.red : role.importance == .main ? .white : .primary)
                .frame(width: 150, height: 28)
                .background(role.importance == .destructive ? AnyShapeStyle(Color.red.opacity(0.18))
                            : role.importance == .main ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
        } else {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).opacity(role.element == "toggle" || role.element == "picker" ? 1 : 0)
                Text(role.element == "toggle" ? "Show Done" : role.element == "picker" ? "By Date" : role.element == "menu" ? "Move To" : title)
                Spacer(minLength: 8)
                if role.element == "menu" { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 6).frame(width: 150, height: 24)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
        }
    }
}
