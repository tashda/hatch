// hatch-inventory: samples (this file draws sample controls; they are not the app's own looks)
import SwiftUI
import HatchCore

// A look judged where it lives (decision DS1): one place drawn small, with the role's neighbours in it, and the role
// drawn with the look being judged. Used by Decide's options and the Components page; the Designer has its larger frames.

/// One place, drawn as a small sample of a real screen, with `role` drawn as `recipe` among its neighbours.
@available(macOS 26.0, *)
public struct RecipePlaceSample: View {
    let place: String
    let role: ComponentRole
    let recipe: [String: String]?
    let system: ComponentSystem

    /// `recipe` nil draws the role as it is.
    public init(place: String, role: ComponentRole, recipe: [String: String]?, system: ComponentSystem) {
        self.place = place; self.role = role; self.recipe = recipe; self.system = system
    }

    /// The roles of the same element in this place, quiet first and the main action last (the macOS order in a row).
    /// The judged role is always among them.
    private var cells: [ComponentRole] {
        let order: [ComponentRole.Importance] = [.quiet, .destructive, .other, .main]
        var list = system.roles.filter { $0.element == role.element && $0.places.contains(place) && $0.id != role.id }
        list = Array(list.prefix(2)) + [role]
        return list.sorted { (order.firstIndex(of: $0.importance) ?? 0) < (order.firstIndex(of: $1.importance) ?? 0) }
    }

    private func control(_ r: ComponentRole) -> some View {
        RecipeControl(element: r.element, recipe: r.id == role.id ? (recipe ?? r.recipe) : (r.draft ?? r.recipe), system: system,
                      importance: r.importance, sample: SampleWords.content(r.importance, place: place, base: SampleContent()))
            .fixedSize()
    }

    @ViewBuilder private var controls: some View {
        if role.element == "badge" && place == "toolbar" {
            // A toolbar badge sits on a toolbar item, as the system draws it.
            Image(systemName: "tray").font(.title3).foregroundStyle(.secondary)
                .overlay(alignment: .topTrailing) { control(role).offset(x: 7, y: -6) }
                .padding(.trailing, 6)
        } else {
            HStack(spacing: 8) { ForEach(cells) { control($0) } }
        }
    }

    /// A toast's position decides where it floats (CD21: a setting that is only visible in its place).
    private var floatingAlignment: Alignment {
        role.element == "toast" && (recipe ?? role.recipe)["position"] == "top" ? .top : .bottom
    }

    public var body: some View {
        mock
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var mock: some View {
        switch place {
        case "toolbar":
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) { ForEach(0..<3, id: \.self) { _ in Circle().fill(.quaternary).frame(width: 9) } }
                    Text("Library").font(.headline).padding(.leading, 6)
                    Spacer(minLength: 12)
                    controls
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.bar)
                Divider()
                Color.clear.frame(height: 18)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        case "sheetFooter":
            VStack(alignment: .leading, spacing: 8) {
                Text("Rename Area").font(.headline)
                Text("The new name shows on every ticket in this area.").font(.callout).foregroundStyle(.secondary)
                HStack { Spacer(minLength: 0); controls }
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        case "alert":
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.yellow)
                Text("Drop this ticket?").font(.headline)
                VStack(spacing: 6) { ForEach(cells.reversed()) { control($0).frame(maxWidth: .infinity) } }
            }
            .padding(14)
            .frame(width: 230)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        case "bottomBar":
            VStack(spacing: 0) {
                Color.clear.frame(height: 22)
                Divider()
                HStack {
                    ForEach(cells.filter { $0.importance != .main }) { control($0) }
                    Spacer(minLength: 12)
                    ForEach(cells.filter { $0.importance == .main }) { control($0) }
                }
                .padding(8)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        case "listRow" where role.element == "row":
            // A row draws its own list, once (B6).
            control(role).padding(4).background(.background, in: RoundedRectangle(cornerRadius: 8))
        case "listRow":
            VStack(spacing: 0) {
                ForEach(["Fix the login sheet", "Toast feels cramped"], id: \.self) { title in
                    HStack {
                        Text(title)
                        Spacer(minLength: 12)
                        controls
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    Divider()
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        case "card", "inspector", "popover":
            VStack(alignment: .leading, spacing: 6) {
                Text(place == "inspector" ? "Ticket #142" : "Details").font(.headline)
                LabeledContent("Status", value: "Building")
                controls
            }
            .padding(12)
            .frame(width: 240, alignment: .leading)
            .background(place == "popover" ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.background), in: RoundedRectangle(cornerRadius: 10))
        case "form":
            VStack(alignment: .leading, spacing: 6) {
                ForEach(cells) { r in LabeledContent(r.title) { control(r) } }
            }
            .padding(12)
            .frame(width: 300)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
        case "emptyState":
            VStack(spacing: 6) {
                Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                Text("No tickets").font(.headline)
                controls
            }
            .padding(14)
        case "contextMenu", "menu":
            VStack(alignment: .leading, spacing: 2) {
                ForEach(cells) { r in
                    Text(SampleWords.content(r.importance, place: place, base: SampleContent()).shownTitle)
                        .foregroundStyle(r.importance == .destructive ? .red : .primary)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                }
            }
            .padding(.vertical, 6)
            .frame(width: 200, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        case "floating" where role.element == "toast":
            // A toast is its own floating surface: no bar around it (no glass on glass).
            control(role)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: floatingAlignment)
                .background(LinearGradient(colors: [.teal.opacity(0.25), .indigo.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 8))
        case "floating":
            HStack(spacing: 6) { ForEach(cells) { control($0) } }
                .padding(6)
                .glassEffect(.regular, in: .capsule)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [.teal.opacity(0.25), .indigo.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 8))
        case "actionRow":
            VStack(alignment: .leading, spacing: 8) {
                Text("Toast feels cramped").font(.title3.bold())
                controls
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Toast feels cramped").font(.headline)
                Text("The toast's text wraps early.").font(.callout).foregroundStyle(.secondary)
                controls
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
