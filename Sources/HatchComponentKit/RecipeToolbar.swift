// hatch-inventory: samples (this file draws sample controls; they are not the app's own looks)
import SwiftUI
import HatchCore

// A window's toolbar as macOS 26 and later draw it, matched to a real SwiftUI toolbar captured on macOS 27: icon buttons
// show only their icon and share one Liquid Glass capsule; a text-only button or a menu has a capsule of its own; a
// prominent button is an accent glass circle; bordered and plain styles draw the same as the default there. Items are
// 36 points tall. A control drawn alone with `.buttonStyle(.bordered)` is not what a toolbar shows.

/// The glass a toolbar gives an item.
public enum ToolbarGlass: Equatable, Sendable {
    /// Shares one capsule with the icon buttons beside it.
    case shared
    /// A capsule of its own (a text button, a menu).
    case own
    /// Draws its own surface (a prominent button, a picker, a search field).
    case none

    public static func of(element: String, recipe: [String: String]) -> ToolbarGlass {
        switch element {
        case "button":
            if prominent(recipe) { return .none }
            return recipe["label"] == "titleOnly" ? .own : .shared
        case "menu", "picker", "controlGroup", "field": return .own
        default: return .none
        }
    }

    /// A prominent button: an accent glass circle (or capsule, with a title) of its own.
    public static func prominent(_ recipe: [String: String]) -> Bool {
        ["borderedProminent", "glassProminent"].contains(recipe["style"] ?? "")
    }
}

/// The item's face inside its glass: what `RecipeControl` draws for a button or menu in the toolbar.
@available(macOS 26.0, *)
struct ToolbarFace: View {
    let element: String
    let recipe: [String: String]
    let sample: SampleContent

    static let height: CGFloat = 36

    var body: some View {
        if element == "picker" {
            if ["segmented", "tabs", "palette"].contains(recipe["style"] ?? "") {
                // A segmented picker in a toolbar: the selection is a grey pill in the item's glass, not an accent segment.
                HStack(spacing: 0) {
                    ForEach(Array(["List", "Board", "Grid"].enumerated()), id: \.offset) { i, t in
                        Text(t).font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(i == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Capsule())
                    }
                }
                .padding(.horizontal, 4).frame(height: Self.height)
            } else {
                HStack(spacing: 6) {
                    Text("List").font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 12).frame(height: Self.height)
            }
        } else if element == "controlGroup" {
            HStack(spacing: 0) {
                Image(systemName: "chevron.left").frame(width: Self.height, height: Self.height)
                Rectangle().fill(.separator).frame(width: 1, height: 16)
                Image(systemName: "chevron.right").frame(width: Self.height, height: Self.height)
            }
            .font(.system(size: 15, weight: .medium))
        } else if element == "field" {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("Search").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12).frame(width: 190, height: Self.height)
        } else if element == "menu" {
            HStack(spacing: 5) {
                if recipe["label"] == "titleOnly" { Text("More").font(.system(size: 13, weight: .medium)) }
                else { Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)) }
                if recipe["indicator"] != "hidden" { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
            }
            .padding(.horizontal, 12).frame(height: Self.height)
        } else if ToolbarGlass.prominent(recipe) {
            Group {
                if recipe["label"] == "titleOnly" {
                    Text(sample.shownTitle).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: Self.height)
                } else {
                    Image(systemName: sample.symbol).font(.system(size: 16, weight: .semibold)).frame(width: Self.height, height: Self.height)
                }
            }
            .foregroundStyle(.white)
            .glassEffect(.regular.tint(recipe["tint"] == "critical" ? .red : .accentColor), in: .capsule)
        } else if recipe["label"] == "titleOnly" {
            Text(sample.shownTitle).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(height: Self.height)
                .foregroundStyle(recipe["tint"] == "critical" ? .red : .primary)
        } else {
            Image(systemName: sample.symbol).font(.system(size: 15))
                .frame(width: Self.height, height: Self.height)
                .foregroundStyle(recipe["tint"] == "critical" ? .red : .primary)
        }
    }
}

/// Toolbar items in their glass: consecutive icon buttons in one capsule, the rest each on their own.
@available(macOS 26.0, *)
public struct ToolbarGlassRow<ID: Hashable, Item: View>: View {
    let items: [(id: ID, glass: ToolbarGlass)]
    let item: (ID) -> Item

    public init(_ items: [(id: ID, glass: ToolbarGlass)], @ViewBuilder item: @escaping (ID) -> Item) {
        self.items = items; self.item = item
    }

    private var groups: [(key: Int, glass: ToolbarGlass, ids: [ID])] {
        var out: [(key: Int, glass: ToolbarGlass, ids: [ID])] = []
        for (i, it) in items.enumerated() {
            if it.glass == .shared, let last = out.last, last.glass == .shared { out[out.count - 1].ids.append(it.id) }
            else { out.append((i, it.glass, [it.id])) }
        }
        return out
    }

    public var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(groups, id: \.key) { g in
                    switch g.glass {
                    case .shared:
                        HStack(spacing: 0) { ForEach(g.ids, id: \.self) { item($0) } }
                            .padding(.horizontal, 2)
                            .glassEffect(.regular, in: .capsule)
                    case .own:
                        item(g.ids[0]).glassEffect(.regular, in: .capsule)
                    case .none:
                        item(g.ids[0])
                    }
                }
            }
        }
    }
}
