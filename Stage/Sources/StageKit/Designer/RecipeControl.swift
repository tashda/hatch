import SwiftUI
import HatchCore

// The recipe engine (decision DS1): any role drawn from its recipe with the real SwiftUI and AppKit controls, in every
// place, light and dark. Switching a setting redraws at once; nothing is generated or compiled, so it costs nothing.

/// Sample content for a drawn control, so hard cases (a long label, disabled) are one switch away.
struct SampleContent: Equatable {
    var title = "Save"
    var symbol = "checkmark"
    var disabled = false
    var longLabel = false
    /// Give buttons their real keys (the live window's sheet and alert); off in tiles, where many would compete.
    var liveKeys = false

    var shownTitle: String { longLabel ? "Save and continue to the next step" : title }
}

/// One control or block drawn from a recipe.
struct RecipeControl: View {
    let element: String
    let recipe: [String: String]
    var system: ComponentSystem?
    var importance: ComponentRole.Importance = .other
    var sample = SampleContent()

    var body: some View {
        content
            .disabled(sample.disabled)
    }

    @ViewBuilder private var content: some View {
        switch element {
        case "button": RecipeButton(recipe: recipe, importance: importance, sample: sample)
        case "menu": RecipeMenu(recipe: recipe, sample: sample)
        case "picker": RecipePicker(recipe: recipe)
        case "toggle": RecipeToggle(recipe: recipe, title: sample.longLabel ? "Sync the whole library in the background" : "Sync")
        case "field": RecipeField(recipe: recipe)
        case "switcher": RecipeSwitcher(recipe: recipe)
        case "row": RecipeRow(recipe: recipe)
        case "card": RecipeCard(recipe: recipe, system: system)
        case "sheet": RecipeSheet(recipe: recipe)
        case "badge": RecipeBadge(recipe: recipe)
        case "toast": RecipeToast(recipe: recipe)
        case "emptyState": RecipeEmptyState(recipe: recipe)
        default: Text(element).foregroundStyle(.secondary)
        }
    }
}

extension ControlSize {
    init(recipe value: String?) {
        switch value {
        case "mini": self = .mini
        case "small": self = .small
        case "large": self = .large
        case "extraLarge": self = .extraLarge
        default: self = .regular
        }
    }
}

extension View {
    /// `.tint` for a recipe's tint: critical red, accent, or a color foundation.
    @ViewBuilder func recipeTint(_ value: String?, system: ComponentSystem? = nil) -> some View {
        switch value {
        case "critical": self.tint(.red)
        case "accent": self.tint(.accentColor)
        case let v? where v.hasPrefix("color."): self.tint(RecipeColor.color(v, system: system))
        default: self
        }
    }

    @ViewBuilder func recipeLabelStyle(_ value: String?) -> some View {
        switch value {
        case "iconOnly": self.labelStyle(.iconOnly)
        case "titleOnly": self.labelStyle(.titleOnly)
        case "titleAndIcon": self.labelStyle(.titleAndIcon)
        default: self
        }
    }

    @ViewBuilder func recipeButtonStyle(_ value: String?) -> some View {
        switch value {
        case "bordered": self.buttonStyle(.bordered)
        case "borderedProminent": self.buttonStyle(.borderedProminent)
        case "borderless": self.buttonStyle(.borderless)
        case "plain": self.buttonStyle(.plain)
        case "link": self.buttonStyle(.link)
        case "glass": self.buttonStyle(.glass)
        case "glassProminent": self.buttonStyle(.glassProminent)
        default: self
        }
    }

    @ViewBuilder func recipeShape(_ value: String?) -> some View {
        switch value {
        case "capsule": self.buttonBorderShape(.capsule)
        case "roundedRectangle": self.buttonBorderShape(.roundedRectangle)
        case "circle": self.buttonBorderShape(.circle)
        default: self
        }
    }
}

enum RecipeColor {
    /// A color foundation's value, or the system color it names.
    static func color(_ id: String, system: ComponentSystem?) -> Color {
        guard let f = system?.foundation(id) else { return .accentColor }
        if let light = f.light, let rgb = rgb(light) { return Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
        switch f.system {
        case "accentColor": return .accentColor
        case "systemRed": return .red
        case let name?: return Color(nsColor: NSColor(named: name) ?? (NSColor.value(forKey: name) as? NSColor) ?? .controlAccentColor)
        default: return .accentColor
        }
    }

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        let d = hex.dropFirst()
        guard d.count >= 6, let v = UInt32(d.prefix(6), radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// Points for a radius or spacing foundation (`radius.card`), or a fallback.
    static func points(_ id: String?, system: ComponentSystem?, fallback: CGFloat) -> CGFloat {
        guard let id, let v = system?.foundation(id)?.value else { return fallback }
        return CGFloat(v)
    }
}

private struct RecipeButton: View {
    let recipe: [String: String]
    let importance: ComponentRole.Importance
    let sample: SampleContent

    var body: some View {
        Button(role: importance == .destructive ? .destructive : (importance == .quiet && recipe["key"] == "cancelAction" ? .cancel : nil)) {} label: {
            switch recipe["label"] {
            case "iconOnly": Label(sample.shownTitle, systemImage: sample.symbol).labelStyle(.iconOnly)
            case "titleAndIcon": Label(sample.shownTitle, systemImage: sample.symbol)
            default: Text(sample.shownTitle)  // what Button("Save") draws when the role says nothing
            }
        }
        .recipeButtonStyle(recipe["style"])
        .controlSize(ControlSize(recipe: recipe["size"]))
        .recipeShape(recipe["shape"])
        .recipeTint(recipe["tint"])
        .help(recipe["tooltip"] == "shortcut" ? "\(sample.shownTitle) (⌘S)" : sample.shownTitle)
        .modifier(RecipeKey(key: sample.liveKeys ? recipe["key"] : nil))
    }
}

/// The real default and Cancel keys: on macOS the default key is what makes a sheet's button the default button.
private struct RecipeKey: ViewModifier {
    let key: String?
    func body(content: Content) -> some View {
        switch key {
        case "defaultAction": content.keyboardShortcut(.defaultAction)
        case "cancelAction": content.keyboardShortcut(.cancelAction)
        default: content
        }
    }
}

private struct RecipeMenu: View {
    let recipe: [String: String]
    let sample: SampleContent

    var body: some View {
        menu
            .menuIndicator(recipe["indicator"] == "hidden" ? .hidden : .automatic)
            .controlSize(ControlSize(recipe: recipe["size"]))
            .fixedSize()
    }

    @ViewBuilder private var menu: some View {
        let base = Menu {
            Button("Rename…") {}
            Button("Duplicate") {}
            Divider()
            Button("Delete", role: .destructive) {}
        } label: {
            switch recipe["label"] {
            case "iconOnly": Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
            case "titleOnly": Text("More")
            default: Label("More", systemImage: "ellipsis")
            }
        }
        switch recipe["style"] {
        case "button": base.menuStyle(.button).recipeButtonStyle(recipe["look"])
        case "borderlessButton": base.menuStyle(.button).buttonStyle(.borderless)
        default: base
        }
    }
}

private struct RecipePicker: View {
    let recipe: [String: String]
    @State private var choice = 0

    var body: some View {
        let picker = Picker("View", selection: $choice) {
            Text("List").tag(0)
            Text("Board").tag(1)
            Text("Grid").tag(2)
        }
        Group {
            switch recipe["style"] {
            case "menu": picker.pickerStyle(.menu)
            case "segmented": picker.pickerStyle(.segmented)
            case "inline": picker.pickerStyle(.inline)
            case "radioGroup": picker.pickerStyle(.radioGroup)
            case "palette": picker.pickerStyle(.palette)
            default: picker
            }
        }
        .modifier(LabelsHidden(hidden: recipe["label"] == "hidden"))
        .controlSize(ControlSize(recipe: recipe["size"]))
        .fixedSize()
    }
}

private struct LabelsHidden: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        if hidden { content.labelsHidden() } else { content }
    }
}

private struct RecipeToggle: View {
    let recipe: [String: String]
    let title: String
    @State private var on = true

    var body: some View {
        let toggle = Toggle(title, isOn: $on)
        Group {
            switch recipe["style"] {
            case "switch": toggle.toggleStyle(.switch)
            case "checkbox": toggle.toggleStyle(.checkbox)
            case "button": toggle.toggleStyle(.button)
            default: toggle
            }
        }
        .controlSize(ControlSize(recipe: recipe["size"]))
        .fixedSize()
    }
}

private struct RecipeField: View {
    let recipe: [String: String]
    @State private var text = ""

    var body: some View {
        let field = TextField("Name", text: $text)
        Group {
            switch recipe["style"] {
            case "roundedBorder": field.textFieldStyle(.roundedBorder)
            case "plain": field.textFieldStyle(.plain)
            case "squareBorder": field.textFieldStyle(.squareBorder)
            default: field
            }
        }
        .controlSize(ControlSize(recipe: recipe["size"]))
        .frame(width: 180)
    }
}

private struct RecipeSwitcher: View {
    let recipe: [String: String]
    @State private var section = 0

    var body: some View {
        switch recipe["style"] {
        case "dock":
            // The glass text dock: one capsule, the current section a soft accent fill.
            HStack(spacing: 0) {
                ForEach(Array(["Overview", "Work", "Files"].enumerated()), id: \.offset) { i, title in
                    Button { section = i } label: {
                        Text(title)
                            .font(.callout.weight(section == i ? .semibold : .regular))
                            .foregroundStyle(section == i ? Color.accentColor : .secondary)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background { if section == i { Capsule().fill(Color.accentColor.opacity(0.16)) } }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .glassEffect(.regular, in: .capsule)
            .fixedSize()
        case "menu":
            Picker("Section", selection: $section) { Text("Overview").tag(0); Text("Work").tag(1); Text("Files").tag(2) }
                .pickerStyle(.menu).labelsHidden().fixedSize()
        case "tabs":
            // The native view switcher for the main area on macOS: a real tab view.
            TabView(selection: $section) {
                Text("Overview").tabItem { Text("Overview") }.tag(0)
                Text("Work").tabItem { Text("Work") }.tag(1)
                Text("Files").tabItem { Text("Files") }.tag(2)
            }
            .frame(width: 280, height: 110)
        default:
            Picker("Section", selection: $section) { Text("Overview").tag(0); Text("Work").tag(1); Text("Files").tag(2) }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .controlSize(ControlSize(recipe: recipe["size"]))
        }
    }
}

private struct RecipeRow: View {
    let recipe: [String: String]

    var body: some View {
        // A real List draws the rows: their height, padding and selection are the list's, as in the app.
        List {
            ForEach(Array(["Fix the login sheet", "Toast feels cramped", "Sync stalls after sleep"].enumerated()), id: \.offset) { i, title in
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(.teal)
                    Text(title)
                    Spacer()
                    if recipe["actions"] == "always" { Button("Open") {}.controlSize(.small) }
                    if recipe["accessory"] == "chevron" { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                }
                .badge(recipe["accessory"] == "badge" ? 3 - i : 0)
                .listRowSeparator(recipe["separators"] == "hidden" ? .hidden : .automatic)
            }
        }
        .frame(width: 300, height: 110)
        .scrollDisabled(true)
    }
}

private struct RecipeCard: View {
    let recipe: [String: String]
    let system: ComponentSystem?

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Status", value: "Building")
            LabeledContent("Area", value: "Desk")
        }
    }

    var body: some View {
        switch recipe["container"] {
        case "groupBox":
            GroupBox("Details") { content }.frame(width: 240)
        case "formSection":
            Form { Section("Details") { content } }.formStyle(.grouped).frame(width: 260, height: 130).scrollDisabled(true)
        default:
            custom
        }
    }

    /// Only a custom card draws its own surface (NF1: GroupBox and Form sections are native).
    private var custom: some View {
        let radius = RecipeColor.points(recipe["radius"], system: system, fallback: 12)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Details").font(.headline)
            content
        }
        .padding(recipe["padding"].flatMap { $0 == "system" ? nil : RecipeColor.points($0, system: system, fallback: 16) } ?? 16)
        .frame(width: 240, alignment: .leading)
        .background {
            switch recipe["surface"] {
            case "grouped": shape.fill(.background.secondary)
            case "material": shape.fill(.regularMaterial)
            case "bordered": shape.strokeBorder(.separator)
            default: EmptyView()
            }
        }
        .modifier(GlassIf(on: recipe["surface"] == "glass", shape: shape))
        .overlay { if recipe["border"] == "hairline" { shape.strokeBorder(.separator, lineWidth: 0.5) } }
        .shadow(color: .black.opacity(recipe["shadow"] == "soft" ? 0.08 : 0), radius: 4, y: 1)
    }
}

private struct GlassIf<S: Shape>: ViewModifier {
    let on: Bool
    let shape: S
    func body(content: Content) -> some View {
        if on { content.glassEffect(.regular, in: shape) } else { content }
    }
}

private struct RecipeSheet: View {
    let recipe: [String: String]

    var body: some View {
        // macOS sizes sheets (presentationSizing); the live window shows a real one.
        let width: CGFloat = ["page": 360, "fitted": 220][recipe["sizing"] ?? "automatic"] ?? 290
        VStack(alignment: .leading, spacing: 10) {
            if recipe["title"] != "none" { Text("Rename Area").font(recipe["title"] == "large" ? .title2.bold() : .headline) }
            TextField("Name", text: .constant("Desk"))
            HStack { Spacer(); Button("Cancel", role: .cancel) {}; Button("Rename") {}.keyboardShortcut(.defaultAction) }
            Text("Sizing: \(recipe["sizing"] ?? "automatic")").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 8, y: 3))
    }
}

private struct RecipeBadge: View {
    let recipe: [String: String]

    var body: some View {
        let text = Text("3").font(.caption2.weight(.semibold)).monospacedDigit()
        switch recipe["style"] {
        case "plain": text.foregroundStyle(.secondary)
        case "capsule":
            text.foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(recipe["tint"] == "accent" ? Color.accentColor : Color.red, in: Capsule())
        default:
            // The system badge, on a real list row.
            List { Text("Waiting for me").badge(3) }.frame(width: 220, height: 44).scrollDisabled(true)
        }
    }
}

private struct RecipeToast: View {
    let recipe: [String: String]

    var body: some View {
        let content = HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Ticket parked")
            Button("Undo") {}.buttonStyle(.borderless)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        switch recipe["surface"] {
        case "glass": content.glassEffect(.regular, in: .capsule)
        case "material": content.background(.regularMaterial, in: Capsule())
        default: content.background(.background.secondary, in: Capsule())
        }
    }
}

private struct RecipeEmptyState: View {
    let recipe: [String: String]

    var body: some View {
        ContentUnavailableView {
            Label("No tickets", systemImage: "tray")
        } description: {
            Text("New tickets you write appear here.")
        } actions: {
            switch recipe["action"] {
            case "prominent": Button("New Ticket") {}.buttonStyle(.borderedProminent)
            case "link": Button("New Ticket") {}.buttonStyle(.link)
            default: EmptyView()
            }
        }
        .frame(width: 280, height: 190)
    }
}
