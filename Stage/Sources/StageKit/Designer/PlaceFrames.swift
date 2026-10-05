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
    @State private var hovered: String?

    /// The roles in this place, quiet first and the main action last (macOS order).
    private var cells: [ComponentRole] {
        // Every role here, a cell holding one per kind of control (CD51), quiet first and the main action last.
        let order: [ComponentRole.Importance] = [.quiet, .destructive, .other, .main]
        return model.system.roles.filter { $0.element == element && $0.places.contains(place.id) }
            .sorted { (order.firstIndex(of: $0.importance) ?? 0, $0.kind) < (order.firstIndex(of: $1.importance) ?? 0, $1.kind) }
    }

    var body: some View {
        if framed {
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
            }
            .contextMenu {
                ForEach(cells, id: \.id) { r in Button("Open \(r.title)") { model.open(r.id) } }
                Divider()
                BatchMenuItems(model: model, element: element, place: place.id)
            }
        } else {
            sample
        }
    }

    /// Places that are a surface of their own (a sheet, a popover, an alert, a menu, a floating bar) are drawn as they
    /// are; the rest sit on one window surface. Never a box inside a box of the same colour.
    private static let ownSurface: Set<String> = ["sheetFooter", "popover", "alert", "contextMenu", "floating"]

    @ViewBuilder private var sample: some View {
        if Self.ownSurface.contains(place.id) {
            mock
                .frame(maxWidth: .infinity, minHeight: framed ? 110 : 60)
                .padding(.vertical, 10)
        } else {
            mock
                .frame(maxWidth: .infinity, minHeight: framed ? 110 : 60, alignment: .leading)
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        }
    }

    /// The look a role is drawn with here.
    private func recipe(_ role: ComponentRole) -> [String: String] {
        today ? (role.draft ?? role.recipe) : model.look(of: role)
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
    @ViewBuilder func control(_ role: ComponentRole) -> some View {
        RecipeControl(element: element, recipe: recipe(role), system: model.system, importance: role.importance,
                      sample: SampleWords.content(role.importance, place: place.id, base: model.sample))
            .allowsHitTesting(false)
            .padding(3)
            .opacity(emphasis(role))
            .overlay {
                if hovered == role.id {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1.5)
                } else if changed(role) {
                    // What a preview changes is marked where it is, so a change is seen at a glance.
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange, lineWidth: 2)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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

    @ViewBuilder private var controls: some View {
        if element == "badge" && place.id == "toolbar", let role = cells.first {
            // A toolbar badge sits on a toolbar item (B7).
            Image(systemName: "tray").font(.title3).foregroundStyle(.secondary)
                .overlay(alignment: .topTrailing) { control(role).offset(x: 9, y: -8) }
                .padding(.trailing, 8)
        } else {
            HStack(spacing: 8) { ForEach(cells, id: \.id) { control($0) } }
        }
    }

    @ViewBuilder private var mock: some View {
        switch place.id {
        case "toolbar":
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Circle().fill(.red.opacity(0.8)).frame(width: 10)
                    Circle().fill(.yellow.opacity(0.8)).frame(width: 10)
                    Circle().fill(.green.opacity(0.8)).frame(width: 10)
                    Text("Desk").font(.headline).padding(.leading, 8)
                    Spacer()
                    controls
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.bar)
                Divider()
                Color.clear.frame(height: 50)
            }
        case "sheetFooter":
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename Area").font(.headline)
                Text("The new name shows on every ticket in this area.").font(.callout).foregroundStyle(.secondary)
                HStack { Spacer(); controls }
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        case "bottomBar":
            VStack(spacing: 0) {
                Text("Iris asks: which look should the toast have?").frame(maxWidth: .infinity, minHeight: 60)
                Divider()
                HStack {
                    ForEach(cells.filter { $0.importance != .main }, id: \.id) { control($0) }
                    Spacer()
                    ForEach(cells.filter { $0.importance == .main }, id: \.id) { control($0) }
                }
                .padding(8)
            }
        case "listRow" where element == "row":
            // A row is drawn by its own list, once (B6).
            HStack(spacing: 8) { ForEach(cells, id: \.id) { control($0) } }
        case "listRow":
            VStack(spacing: 0) {
                ForEach(["Fix the login sheet", "Toast feels cramped", "Sync stalls after sleep"], id: \.self) { title in
                    HStack {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(.teal)
                        Text(title)
                        Spacer()
                        controls
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        case "card", "inspector", "popover":
            VStack(alignment: .leading, spacing: 8) {
                Text(place.id == "inspector" ? "Ticket #142" : "Details").font(.headline)
                LabeledContent("Status", value: "Building")
                LabeledContent("Area", value: "Desk")
                controls
            }
            .padding(12)
            .frame(width: place.id == "inspector" ? 220 : 260, alignment: .leading)
            .background(place.id == "popover" ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.background.secondary),
                        in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(place.id == "popover" ? 0.15 : 0), radius: 8, y: 3)
        case "form":
            Form {
                ForEach(cells, id: \.id) { role in
                    LabeledContent(role.title) { control(role) }
                }
            }
            .formStyle(.grouped)
            .frame(height: CGFloat(max(1, cells.count)) * 44 + 30)
            .scrollDisabled(true)
        case "emptyState":
            ContentUnavailableView {
                Label("No tickets", systemImage: "tray")
            } description: {
                Text("New tickets you write appear here.")
            } actions: {
                controls
            }
        case "contextMenu":
            VStack(alignment: .leading, spacing: 2) {
                ForEach(cells, id: \.id) { role in
                    HStack {
                        Text(SampleWords.content(role.importance, place: "contextMenu", base: model.sample).shownTitle)
                            .foregroundStyle(role.importance == .destructive ? .red : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .opacity(emphasis(role))
                    .onTapGesture { model.open(role.id) }
                }
                Text("Menu items are drawn by the system; a role here sets order and wording, not a look.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 4)
            }
            .padding(.vertical, 6)
            .frame(width: 240, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        case "alert":
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.yellow)
                Text("Drop this ticket?").font(.headline)
                Text("It leaves the queue and its branch is deleted.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                VStack(spacing: 6) { ForEach(cells.reversed(), id: \.id) { control($0).frame(maxWidth: .infinity) } }
            }
            .padding(16)
            .frame(width: 260)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        case "actionRow":
            VStack(alignment: .leading, spacing: 8) {
                Text("Toast feels cramped").font(.title2.bold())
                controls
            }
        case "floating" where element == "toast":
            // A toast is its own floating surface (no glass on glass), at the top or bottom its look says (CD21).
            ZStack(alignment: cells.first.map { recipe($0)["position"] == "top" ? .top : .bottom } ?? .bottom) {
                LinearGradient(colors: [.teal.opacity(0.3), .indigo.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 6) { ForEach(cells, id: \.id) { control($0) } }
                    .padding(10)
            }
        case "floating":
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.teal.opacity(0.3), .indigo.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 6) { ForEach(cells, id: \.id) { control($0) } }
                    .padding(6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 10)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Toast feels cramped").font(.headline)
                Text("The toast's text wraps early and the action sits too close.").font(.callout).foregroundStyle(.secondary)
                controls
            }
        }
    }
}
