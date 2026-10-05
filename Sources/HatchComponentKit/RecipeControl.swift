// hatch-inventory: samples (this file draws sample controls; they are not the app's own looks)
import SwiftUI
import HatchCore

// The recipe engine (decisions DS1, CP1), shared by the Hatch app and the Stage: any role drawn from its recipe with the real SwiftUI and AppKit controls, in every
// place, light and dark. Switching a setting redraws at once; nothing is generated or compiled, so it costs nothing.

/// Sample content for a drawn control, so hard cases (a long label, disabled) are one switch away.
@available(macOS 26.0, *)
public struct SampleContent: Equatable {
    public init() {}
    public var title = "Save"
    public var symbol = "checkmark"
    public var disabled = false
    public var longLabel = false
    /// Give buttons their real keys (the live window's sheet and alert); off in tiles, where many would compete.
    public var liveKeys = false
    /// The place it is drawn in, when a control looks different by place (a badge on a toolbar item or in a row).
    public var place: String?

    public var shownTitle: String { longLabel ? "Save and continue to the next step" : title }
}

/// One control or block drawn from a recipe.
@available(macOS 26.0, *)
public struct RecipeControl: View {
    let element: String
    let recipe: [String: String]
    var system: ComponentSystem?
    var importance: ComponentRole.Importance = .other
    var sample = SampleContent()

    public init(element: String, recipe: [String: String], system: ComponentSystem? = nil, importance: ComponentRole.Importance = .other,
                sample: SampleContent = SampleContent()) {
        self.element = element; self.recipe = recipe; self.system = system; self.importance = importance; self.sample = sample
    }

    public var body: some View {
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
        case "badge": RecipeBadge(recipe: recipe, place: sample.place)
        case "toast": RecipeToast(recipe: recipe)
        case "emptyState": RecipeEmptyState(recipe: recipe)
        case "table": RecipeTable(recipe: recipe)
        case "form": RecipeForm(recipe: recipe)
        case "datePicker": RecipeDatePicker(recipe: recipe)
        case "progress": RecipeProgress(recipe: recipe)
        case "slider": RecipeSlider(recipe: recipe)
        case "stepper": Stepper("Copies: 2", value: .constant(2)).controlSize(ControlSize(recipe: recipe["size"])).fixedSize()
        case "gauge": RecipeGauge(recipe: recipe)
        case "controlGroup": RecipeControlGroup(recipe: recipe)
        case "textEditor": RecipeTextEditor(recipe: recipe)
        default: Text(element).foregroundStyle(.secondary)
        }
    }
}

@available(macOS 26.0, *)
extension ControlSize {
    public init(recipe value: String?) {
        switch value {
        case "mini": self = .mini
        case "small": self = .small
        case "large": self = .large
        case "extraLarge": self = .extraLarge
        default: self = .regular
        }
    }
}

@available(macOS 26.0, *)
extension View {
    /// `.tint` for a recipe's tint: critical red, accent, or a color foundation.
    @ViewBuilder public func recipeTint(_ value: String?, system: ComponentSystem? = nil) -> some View {
        switch value {
        case "critical": self.tint(.red)
        case "accent": self.tint(.accentColor)
        case let v? where v.hasPrefix("color."): self.tint(RecipeColor.color(v, system: system))
        default: self
        }
    }

    @ViewBuilder public func recipeLabelStyle(_ value: String?) -> some View {
        switch value {
        case "iconOnly": self.labelStyle(.iconOnly)
        case "titleOnly": self.labelStyle(.titleOnly)
        case "titleAndIcon": self.labelStyle(.titleAndIcon)
        default: self
        }
    }

    @ViewBuilder public func recipeButtonStyle(_ value: String?) -> some View {
        switch value {
        case "bordered": self.buttonStyle(.bordered)
        case "borderedProminent": self.buttonStyle(.borderedProminent)
        case "borderless": self.buttonStyle(.borderless)
        case "plain": self.buttonStyle(.plain)
        case "link": self.buttonStyle(.link)
        case "glass": self.buttonStyle(.glass)
        case "glassProminent": self.buttonStyle(.glassProminent)
        case "glassClear": self.buttonStyle(.glass(.clear))
        case "accessoryBar": self.buttonStyle(.accessoryBar)
        case "accessoryBarAction": self.buttonStyle(.accessoryBarAction)
        default: self
        }
    }

    @ViewBuilder public func recipeSizing(_ value: String?) -> some View {
        switch value {
        case "fitted": self.buttonSizing(.fitted)
        case "flexible": self.buttonSizing(.flexible)
        default: self
        }
    }

    @ViewBuilder public func recipeShape(_ value: String?, system: ComponentSystem? = nil) -> some View {
        switch value {
        case "capsule": self.buttonBorderShape(.capsule)
        case "roundedRectangle": self.buttonBorderShape(.roundedRectangle)
        case "circle": self.buttonBorderShape(.circle)
        case let v? where v.hasPrefix("radius."): self.buttonBorderShape(.roundedRectangle(radius: RecipeColor.points(v, system: system, fallback: 8)))
        default: self
        }
    }
}

@available(macOS 26.0, *)
public enum RecipeColor {
    /// A color foundation's value, or the system color it names.
    public static func color(_ id: String, system: ComponentSystem?) -> Color {
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
    public static func points(_ id: String?, system: ComponentSystem?, fallback: CGFloat) -> CGFloat {
        guard let id, let v = system?.foundation(id)?.value else { return fallback }
        return CGFloat(v)
    }
}

@available(macOS 26.0, *)
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
        .recipeButtonStyle(recipe["style"].flatMap { $0 == "automatic" ? nil : $0 } ?? (looksDefault ? "borderedProminent" : nil))
        .controlSize(ControlSize(recipe: recipe["size"]))
        .recipeShape(recipe["shape"])
        .recipeSizing(recipe["sizing"])
        .recipeTint(recipe["tint"])
        .help(recipe["tooltip"] == "shortcut" ? "\(sample.shownTitle) (⌘S)" : sample.shownTitle)
        .modifier(RecipeKey(key: sample.liveKeys ? recipe["key"] : nil))
    }

    /// A button with the Return key and no style of its own is drawn as macOS draws a default button (accent filled),
    /// without the key itself: many samples in one window can't all answer Return.
    private var looksDefault: Bool { recipe["key"] == "defaultAction" && !sample.liveKeys }
}

/// The real default and Cancel keys: on macOS the default key is what makes a sheet's button the default button.
@available(macOS 26.0, *)
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

@available(macOS 26.0, *)
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
        case "button": base.menuStyle(.button).recipeButtonStyle(recipe["look"]).recipeShape(recipe["shape"])
        case "borderlessButton": base.menuStyle(.button).buttonStyle(.borderless)
        default: base
        }
    }
}

@available(macOS 26.0, *)
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
            case "menu": picker.pickerStyle(.menu).recipeButtonStyle(recipe["look"])
            case "segmented": picker.pickerStyle(.segmented)
            case "tabs": picker.modifier(TabsPickerStyle())
            case "inline": picker.pickerStyle(.inline)
            case "radioGroup":
                if recipe["layout"] == "horizontal" { picker.pickerStyle(.radioGroup).horizontalRadioGroupLayout() } else { picker.pickerStyle(.radioGroup) }
            case "palette": picker.pickerStyle(.palette)
            default: picker
            }
        }
        .modifier(LabelsHidden(hidden: recipe["label"] == "hidden"))
        .controlSize(ControlSize(recipe: recipe["size"]))
        .fixedSize()
    }
}

@available(macOS 26.0, *)
private struct LabelsHidden: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        if hidden { content.labelsHidden() } else { content }
    }
}

@available(macOS 26.0, *)
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
            case "button": toggle.toggleStyle(.button).recipeButtonStyle(recipe["look"])
            default: toggle
            }
        }
        .controlSize(ControlSize(recipe: recipe["size"]))
        .recipeTint(recipe["tint"])
        .fixedSize()
    }
}

@available(macOS 26.0, *)
private struct RecipeField: View {
    let recipe: [String: String]
    @State private var text = ""

    var body: some View {
        let field = TextField("Name", text: $text)
        Group {
            switch recipe["style"] {
            case "bordered": field.modifier(BorderedField(shape: recipe["shape"]))
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

@available(macOS 26.0, *)
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
        case "tabSegments":
            // macOS 27's tab switcher: a segmented control drawn for moving between sections.
            Picker("Section", selection: $section) { Text("Overview").tag(0); Text("Work").tag(1); Text("Files").tag(2) }
                .modifier(TabsPickerStyle()).labelsHidden().fixedSize()
                .controlSize(ControlSize(recipe: recipe["size"]))
        case "tabBar", "groupedTabs", "sidebarTabs":
            tabView(recipe["style"]!)
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

@available(macOS 26.0, *)
extension RecipeSwitcher {
    /// A real tab view in one of its styles, with three sections.
    @ViewBuilder func tabView(_ style: String) -> some View {
        let view = TabView {
            Tab("Overview", systemImage: "square.grid.2x2") { Text("Overview").frame(maxWidth: .infinity, maxHeight: .infinity) }
            Tab("Work", systemImage: "hammer") { Text("Work") }
            Tab("Files", systemImage: "folder") { Text("Files") }
        }
        Group {
            switch style {
            case "tabBar": view.tabViewStyle(.tabBarOnly)
            case "groupedTabs": view.tabViewStyle(.grouped)
            default: view.tabViewStyle(.sidebarAdaptable)
            }
        }
        .frame(width: 320, height: 150)
    }
}

@available(macOS 26.0, *)
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
        .modifier(ListLook(style: recipe["list"], alternating: recipe["alternating"] == "on"))
        .environment(\.defaultMinListRowHeight, recipe["height"] == "compact" ? 22 : recipe["height"] == "roomy" ? 40 : 28)
        .frame(width: 300, height: recipe["height"] == "roomy" ? 150 : 110)
        .scrollDisabled(true)
    }
}

/// macOS 27's tab switcher; on macOS 26 its fallback, a segmented control.
@available(macOS 26.0, *)
struct TabsPickerStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 27.0, *) { content.pickerStyle(.tabs) } else { content.pickerStyle(.segmented) }
    }
}

/// macOS 27's bordered text field with its border shape; on macOS 26 its fallback, the rounded border.
@available(macOS 26.0, *)
struct BorderedField: ViewModifier {
    let shape: String?
    func body(content: Content) -> some View {
        if #available(macOS 27.0, *) {
            switch shape {
            case "capsule": content.textFieldStyle(.bordered).textInputBorderShape(.capsule)
            case "roundedRectangle": content.textFieldStyle(.bordered).textInputBorderShape(.roundedRectangle)
            default: content.textFieldStyle(.bordered)
            }
        } else {
            content.textFieldStyle(.roundedBorder)
        }
    }
}

/// A list's style and zebra rows.
@available(macOS 26.0, *)
struct ListLook: ViewModifier {
    let style: String?
    let alternating: Bool
    func body(content: Content) -> some View {
        Group {
            switch style {
            case "plain": content.listStyle(.plain)
            case "inset": content.listStyle(.inset)
            case "bordered": content.listStyle(.bordered)
            case "sidebar": content.listStyle(.sidebar)
            default: content
            }
        }
        .alternatingRowBackgrounds(alternating ? .enabled : .automatic)
    }
}

@available(macOS 26.0, *)
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
            GroupBox("Details") { content }.frame(maxWidth: 240)
        case "formSection":
            Form { Section("Details") { content } }.formStyle(.grouped).frame(maxWidth: 240).frame(height: 130).scrollDisabled(true)
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
        .frame(maxWidth: 240, alignment: .leading)
        .background {
            switch recipe["surface"] {
            case "grouped": shape.fill(Color.secondary.opacity(0.14))
            case "material": shape.fill(.regularMaterial)
            case "bordered": shape.strokeBorder(.separator)
            default: EmptyView()
            }
        }
        .modifier(GlassIf(on: recipe["surface"] == "glass", clear: false, shape: shape))
        .modifier(GlassIf(on: recipe["surface"] == "glassClear", clear: true, shape: shape))
        .overlay { if recipe["border"] == "hairline" { shape.strokeBorder(.separator, lineWidth: 0.5) } }
        .background {
            // A soft shadow needs a surface to fall from; without one it would be invisible.
            if recipe["shadow"] == "soft" { shape.fill(.background).shadow(color: .black.opacity(0.14), radius: 8, y: 3) }
        }
    }
}

@available(macOS 26.0, *)
private struct GlassIf<S: Shape>: ViewModifier {
    let on: Bool
    var clear = false
    let shape: S
    func body(content: Content) -> some View {
        if on { content.glassEffect(clear ? .clear : .regular, in: shape) } else { content }
    }
}

@available(macOS 26.0, *)
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

@available(macOS 26.0, *)
private struct RecipeBadge: View {
    let recipe: [String: String]
    let place: String?

    var body: some View {
        let text = Text("3").font(.caption2.weight(.semibold)).monospacedDigit()
        switch recipe["style"] {
        case "plain": text.foregroundStyle(.secondary)
        case "capsule": capsule(text, color: recipe["tint"] == "accent" ? Color.accentColor : Color.red)
        default:
            // The system badge: a red capsule on a toolbar item (like the Dock's), the count in grey at the end of a row.
            // Prominence: more draws it in the label colour and heavier, less in the tertiary colour.
            if place == "toolbar" { capsule(text, color: .red) } else {
                switch recipe["prominence"] {
                case "increased": Text("3").monospacedDigit().fontWeight(.semibold).foregroundStyle(.primary)
                case "decreased": Text("3").monospacedDigit().foregroundStyle(.tertiary)
                default: Text("3").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    private func capsule(_ text: some View, color: Color) -> some View {
        text.foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color, in: Capsule())
    }
}

@available(macOS 26.0, *)
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
        case "glassClear": content.glassEffect(.clear, in: .capsule)
        case "material": content.background(.regularMaterial, in: Capsule())
        default: content.background(.background.secondary, in: Capsule())
        }
    }
}

@available(macOS 26.0, *)
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
            case "glassProminent": Button("New Ticket") {}.buttonStyle(.glassProminent)
            case "link": Button("New Ticket") {}.buttonStyle(.link)
            default: EmptyView()
            }
        }
        .frame(width: 280, height: 190)
    }
}

@available(macOS 26.0, *)
private struct RecipeTable: View {
    let recipe: [String: String]
    struct Item: Identifiable { let id: Int; let name: String; let status: String }
    let items = [Item(id: 1, name: "Fix the login sheet", status: "Building"), Item(id: 2, name: "Toast feels cramped", status: "Ready"),
                 Item(id: 3, name: "Sync stalls after sleep", status: "To verify")]
    var body: some View {
        let table = Table(items) {
            TableColumn("Title", value: \.name)
            TableColumn("Status", value: \.status)
        }
        Group {
            switch recipe["style"] {
            case "inset": table.tableStyle(.inset)
            case "bordered": table.tableStyle(.bordered)
            default: table
            }
        }
        .tableColumnHeaders(recipe["headers"] == "hidden" ? .hidden : .automatic)
        .alternatingRowBackgrounds(recipe["alternating"] == "on" ? .enabled : .automatic)
        .frame(width: 320, height: 120)
        .scrollDisabled(true)
    }
}

@available(macOS 26.0, *)
private struct RecipeForm: View {
    let recipe: [String: String]
    var body: some View {
        let form = Form {
            Toggle("Sync in the background", isOn: .constant(true))
            Picker("Refresh", selection: .constant(1)) { Text("Every hour").tag(1); Text("Daily").tag(2) }
            TextField("Name", text: .constant("Desk"))
        }
        Group {
            switch recipe["style"] {
            case "columns": form.formStyle(.columns)
            case "grouped": form.formStyle(.grouped)
            default: form
            }
        }
        .frame(width: 330, height: 150)
        .scrollDisabled(true)
    }
}

@available(macOS 26.0, *)
private struct RecipeDatePicker: View {
    let recipe: [String: String]
    var body: some View {
        let picker = DatePicker("Due", selection: .constant(Date(timeIntervalSinceReferenceDate: 813_000_000)), displayedComponents: .date)
        Group {
            switch recipe["style"] {
            case "compact": picker.datePickerStyle(.compact)
            case "field": picker.datePickerStyle(.field)
            case "stepperField": picker.datePickerStyle(.stepperField)
            case "graphical": picker.datePickerStyle(.graphical).frame(width: 240)
            default: picker
            }
        }
        .controlSize(ControlSize(recipe: recipe["size"]))
        .fixedSize()
    }
}

@available(macOS 26.0, *)
private struct RecipeProgress: View {
    let recipe: [String: String]
    var body: some View {
        let progress = ProgressView(value: 0.6) { Text("Building") }
        Group {
            switch recipe["style"] {
            case "linear": progress.progressViewStyle(.linear)
            case "circular": progress.progressViewStyle(.circular)
            default: progress
            }
        }
        .controlSize(ControlSize(recipe: recipe["size"]))
        .recipeTint(recipe["tint"])
        .frame(width: 200)
    }
}

@available(macOS 26.0, *)
private struct RecipeSlider: View {
    let recipe: [String: String]
    var body: some View {
        Slider(value: .constant(0.4), in: 0...1, step: 0.1) { Text("Volume") }
            .sliderThumbVisibility(recipe["thumb"] == "hidden" ? .hidden : .automatic)
            .controlSize(ControlSize(recipe: recipe["size"]))
            .recipeTint(recipe["tint"])
            .frame(width: 200)
    }
}

@available(macOS 26.0, *)
private struct RecipeGauge: View {
    let recipe: [String: String]
    var body: some View {
        let gauge = Gauge(value: 0.62) { Text("CPU") } currentValueLabel: { Text("62") }
        Group {
            switch recipe["style"] {
            case "linearCapacity": gauge.gaugeStyle(.linearCapacity)
            case "accessoryLinear": gauge.gaugeStyle(.accessoryLinear)
            case "accessoryLinearCapacity": gauge.gaugeStyle(.accessoryLinearCapacity)
            case "accessoryCircular": gauge.gaugeStyle(.accessoryCircular)
            case "accessoryCircularCapacity": gauge.gaugeStyle(.accessoryCircularCapacity)
            default: gauge
            }
        }
        .recipeTint(recipe["tint"])
        .frame(width: 200)
    }
}

@available(macOS 26.0, *)
private struct RecipeControlGroup: View {
    let recipe: [String: String]
    var body: some View {
        let group = ControlGroup {
            Button { } label: { Label("Back", systemImage: "chevron.left") }
            Button { } label: { Label("Forward", systemImage: "chevron.right") }
        } label: { Label("Navigate", systemImage: "arrow.left.arrow.right") }
        Group {
            switch recipe["style"] {
            case "navigation": group.controlGroupStyle(.navigation)
            case "palette": group.controlGroupStyle(.palette)
            case "menu": group.controlGroupStyle(.menu)
            case "compactMenu": group.controlGroupStyle(.compactMenu)
            default: group
            }
        }
        .controlSize(ControlSize(recipe: recipe["size"]))
        .fixedSize()
    }
}

@available(macOS 26.0, *)
private struct RecipeTextEditor: View {
    let recipe: [String: String]
    var body: some View {
        let editor = TextEditor(text: .constant("Notes for the build: the toast wraps early."))
        Group {
            if recipe["style"] == "plain" { editor.textEditorStyle(.plain) } else { editor }
        }
        .frame(width: 240, height: 70)
    }
}

/// Sample words for a control by importance, so a place reads like a real screen.
@available(macOS 26.0, *)
public enum SampleWords {
    public static func content(_ importance: ComponentRole.Importance, place: String, base: SampleContent) -> SampleContent {
        var s = base
        s.place = place
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

