import SwiftUI
import HatchCore

// "In place" (decision DS1): an element is never judged floating alone. Each place is drawn as a small mock of the
// real thing (a toolbar, a sheet's footer, a list, a form) with the roles that hold its cells, so a button is seen as the
// main action of a sheet or as a row action, beside its neighbours.

/// Sample words for a control by importance, so a place reads like a real screen.
enum SampleWords {
    static func content(_ importance: ComponentRole.Importance, place: String, base: SampleContent) -> SampleContent {
        var s = base
        switch (importance, place) {
        case (_, "toolbar"): s.title = "Refresh"; s.symbol = "arrow.clockwise"
        case (.main, _): s.title = base.longLabel ? base.title : "Save"; s.symbol = "checkmark"
        case (.quiet, "sheetFooter"), (.quiet, "alert"): s.title = "Cancel"; s.symbol = "xmark"
        case (.quiet, _): s.title = "Show All"; s.symbol = "chevron.right"
        case (.destructive, _): s.title = "Delete"; s.symbol = "trash"
        case (.other, "listRow"), (.other, "card"), (.other, "inspector"), (.other, "popover"): s.title = "Open"; s.symbol = "arrow.up.forward"
        case (.other, _): s.title = "Share"; s.symbol = "square.and.arrow.up"
        }
        return s
    }
}

/// One place drawn with the element's roles in it. Tapping a control selects its role.
struct PlaceFrame: View {
    let place: ComponentPlace
    let element: String
    @ObservedObject var model: DesignerModel

    /// The roles in this place, quiet first and the main action last (macOS order).
    private var cells: [ComponentRole] {
        let order: [ComponentRole.Importance] = [.quiet, .destructive, .other, .main]
        return order.compactMap { model.system.role(element: element, place: place.id, importance: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(place.title).font(.headline)
                Text(cells.map(\.id).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if cells.allSatisfy(\.followsMacOS) {
                    Text("follows macOS").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Menu {
                        Button("Follow macOS for \((ComponentElement.named(element)?.plural ?? element).lowercased()) here") { model.follow(element: element, place: place.id) }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                    .help("Let macOS decide this place")
                }
            }
            Text(place.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            mock
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        }
    }

    /// A role's control, outlined when selected; a tap selects it.
    @ViewBuilder func control(_ role: ComponentRole) -> some View {
        let recipe = role.draft ?? role.recipe
        RecipeControl(element: element, recipe: recipe, system: model.system, importance: role.importance,
                      sample: SampleWords.content(role.importance, place: place.id, base: model.sample))
            .padding(3)
            .overlay {
                if model.selectedRole == role.id {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { model.selectedRole = role.id })
            .help("\(role.id): \(role.use)")
    }

    private var controls: some View {
        HStack(spacing: 8) { ForEach(cells, id: \.id) { control($0) } }
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
                    .overlay { if model.selectedRole == role.id { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2) } }
                    .onTapGesture { model.selectedRole = role.id }
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
