import Foundation

// A look in plain words (decision CP1's follow-up: decisions are judged by eye, then by words). A recipe such as
// `style plain, label iconOnly` reads "Icon only, no border"; settings left out are macOS's default and are said that
// way, so every option names the whole control, not just what differs.

public enum ComponentWords {
    /// The whole look of a control, in the words a person uses.
    public static func look(element: String, recipe: [String: String]) -> String {
        var parts: [String]
        switch element {
        case "button": parts = button(recipe)
        case "menu": parts = menu(recipe)
        case "picker":
            parts = [["menu": "Pop-up menu", "segmented": "Segmented control", "inline": "Inline list", "radioGroup": "Radio buttons",
                      "palette": "Palette"][recipe["style"] ?? ""] ?? "Standard picker (a pop-up menu)"]
            if recipe["label"] == "hidden" { parts.append("no label") }
        case "toggle":
            parts = [["switch": "Switch", "checkbox": "Checkbox", "button": "Toggle button"][recipe["style"] ?? ""] ?? "Standard toggle (a checkbox)"]
        case "field":
            parts = [["roundedBorder": "Rounded field", "plain": "Plain field, no border", "squareBorder": "Square field"][recipe["style"] ?? ""] ?? "Standard text field"]
        case "switcher":
            parts = [["segmented": "Segmented control", "menu": "Pop-up menu", "tabs": "Tabs", "dock": "Text dock"][recipe["style"] ?? ""] ?? "Segmented control"]
        case "card":
            parts = [["groupBox": "Group box", "formSection": "Form section", "custom": "Own surface"][recipe["container"] ?? ""] ?? "Group box"]
            if let s = recipe["surface"], s != "none" { parts.append(s == "glass" ? "glass" : s) }
            if recipe["border"] == "hairline" { parts.append("hairline border") }
            if recipe["shadow"] == "soft" { parts.append("soft shadow") }
        case "row":
            parts = ["List row"]
            if recipe["separators"] == "hidden" { parts.append("no separators") }
            if let a = recipe["accessory"], a != "none" { parts.append(a == "chevron" ? "chevron" : "badge") }
        case "badge":
            parts = [["capsule": "Capsule badge", "plain": "Plain count"][recipe["style"] ?? ""] ?? "System badge"]
        case "toast":
            parts = [(recipe["surface"].map { ["glass": "Glass", "material": "Material", "solid": "Solid"][$0] ?? $0 } ?? "Glass") + " toast"]
            if let p = recipe["position"] { parts.append("at the \(p)") }
        case "sheet":
            parts = [["form": "Form-sized sheet", "page": "Page-sized sheet", "fitted": "Sheet fitted to its content"][recipe["sizing"] ?? ""] ?? "Standard sheet"]
        case "emptyState":
            parts = [["prominent": "Empty state with a button", "link": "Empty state with a link", "none": "Empty state, no next step"][recipe["action"] ?? ""] ?? "Empty state"]
        default:
            // Any other element: its settings in plain words, or "Standard" when it follows macOS.
            let named = recipe.sorted { $0.key < $1.key }.map { value(element: element, parameter: $0.key, value: $0.value) }
            parts = named.isEmpty ? ["Standard " + (ComponentElement.named(element)?.title.lowercased() ?? element)] : named
        }
        if let size = recipe["size"], size != "regular" { parts.append(size == "extraLarge" ? "extra large" : size) }
        if let tint = recipe["tint"], tint != "none" { parts.append(tint == "accent" ? "accent color" : tint == "critical" ? "red" : "\(tint) color") }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func button(_ r: [String: String]) -> [String] {
        let label = r["label"]
        let style = r["style"] ?? "automatic"
        var parts: [String]
        switch style {
        case "bordered": parts = ["Bordered button"]
        case "borderedProminent": parts = ["Filled button"]
        case "borderless": parts = ["Borderless button"]
        case "plain": parts = [label == "iconOnly" ? "Icon" : "Text", "no border"]
        case "link": parts = ["Link"]
        case "glass": parts = ["Glass button"]
        case "glassProminent": parts = ["Filled glass button"]
        default: parts = ["Standard button"]
        }
        switch label {
        case "iconOnly" where style != "plain": parts.append("icon only")
        case "titleOnly" where style != "plain" && style != "link": parts.append("text only")
        case "titleAndIcon": parts.append("icon and text")
        default: break
        }
        if let shape = r["shape"], shape != "automatic" { parts.append(["capsule": "capsule", "roundedRectangle": "rounded corners", "circle": "round"][shape] ?? shape) }
        return parts
    }

    private static func menu(_ r: [String: String]) -> [String] {
        var parts = [["button": "Menu button", "borderlessButton": "Borderless menu", "borderedButton": "Bordered menu"][r["style"] ?? ""] ?? "Standard menu"]
        if let look = r["look"], look != "automatic" { parts.append(look == "glass" ? "glass" : look) }
        if r["indicator"] == "hidden" { parts.append("no arrow") }
        switch r["label"] {
        case "iconOnly": parts.append("icon only")
        case "titleOnly": parts.append("text only")
        default: break
        }
        return parts
    }

    /// One setting's value in plain words (CD20): `borderedProminent` reads "Filled". macOS's default says so, with what
    /// it draws when that is the same everywhere ("macOS default (pop-up)"). The code value stays in tooltips.
    public static func value(element: String, parameter: String, value: String) -> String {
        if let v = values["\(element).\(parameter)"]?[value] ?? values[parameter]?[value] { return v }
        if value.contains(".") { return value }  // a foundation, such as radius.card
        return value
    }

    /// What a behaviour setting does, one line (CD22): it can't be judged by looking.
    public static func help(element: String, parameter: String) -> String? {
        helps["\(element).\(parameter)"] ?? helps[parameter]
    }

    /// Whether to offer "Let people choose in Settings" for an element (CD36), and why. Rule 3: a recommendation each time.
    public static func settingAdvice(element: String) -> (offer: Bool, reason: String) {
        switch element {
        case "row": return (true, "Dense or roomy lists are a common choice in pro apps, as in Mail and Finder.")
        case "badge": return (true, "Some people find counts stressful; Mail and the Dock let them turn badges off.")
        case "toast": return (true, "Slower readers need toasts to stay longer.")
        case "button", "menu", "picker", "toggle", "field":
            return (false, "People expect these to look like macOS; a setting doubles what has to be tested and nobody asks for it.")
        default: return (false, "It is structure, not taste: changing it per person breaks layouts.")
        }
    }

    private static let values: [String: [String: String]] = [
        "button.style": ["automatic": "macOS default", "bordered": "Bordered", "borderedProminent": "Filled", "borderless": "Borderless",
                         "plain": "Plain", "link": "Link", "accessoryBar": "Accessory bar", "accessoryBarAction": "Accessory bar action",
                         "glass": "Glass", "glassProminent": "Glass, filled", "glassClear": "Clear glass"],
        "button.sizing": ["automatic": "macOS default", "fitted": "Fits its title", "flexible": "Fills the width"],
        "size": ["mini": "Mini", "small": "Small", "regular": "Regular", "large": "Large", "extraLarge": "Extra large"],
        "label": ["titleAndIcon": "Icon and title", "titleOnly": "Title", "iconOnly": "Icon only"],
        "button.shape": ["automatic": "macOS default", "capsule": "Capsule", "roundedRectangle": "Rounded rectangle", "circle": "Circle"],
        "tint": ["none": "None", "accent": "Accent colour", "critical": "Red (critical)"],
        "button.show": ["always": "Always", "onHover": "On hover"],
        "button.confirm": ["no": "No", "yes": "Ask first"],
        "button.key": ["none": "None", "defaultAction": "Return (default button)", "cancelAction": "Escape (cancel button)"],
        "button.tooltip": ["none": "None", "title": "Title", "shortcut": "Title and shortcut"],
        "menu.style": ["automatic": "macOS default (pull-down)", "button": "Button", "borderlessButton": "Borderless (old)", "borderedButton": "Bordered (old)"],
        "menu.look": ["automatic": "macOS default", "bordered": "Bordered", "borderedProminent": "Filled", "borderless": "Borderless",
                      "plain": "Plain", "link": "Link", "accessoryBar": "Accessory bar", "glass": "Glass", "glassProminent": "Glass, filled"],
        "menu.shape": ["automatic": "macOS default", "capsule": "Capsule", "roundedRectangle": "Rounded rectangle", "circle": "Circle"],
        "menu.order": ["automatic": "macOS default", "fixed": "As written"],
        "menu.indicator": ["visible": "Shown", "hidden": "Hidden"],
        "picker.style": ["automatic": "macOS default (pop-up)", "menu": "Pop-up", "segmented": "Segmented", "tabs": "Tab switcher",
                         "inline": "Inline list", "radioGroup": "Radio buttons", "palette": "Palette"],
        "picker.look": ["automatic": "macOS default", "bordered": "Bordered", "borderless": "Borderless", "plain": "Plain", "accessoryBar": "Accessory bar",
                        "glass": "Glass", "glassProminent": "Glass, filled"],
        "picker.layout": ["vertical": "Stacked", "horizontal": "In a row"],
        "picker.label": ["visible": "Shown", "hidden": "Hidden"],
        "toggle.style": ["automatic": "macOS default (checkbox)", "switch": "Switch", "checkbox": "Checkbox", "button": "Button"],
        "toggle.look": ["automatic": "macOS default", "bordered": "Bordered", "borderedProminent": "Filled", "borderless": "Borderless",
                        "plain": "Plain", "accessoryBar": "Accessory bar", "glass": "Glass", "glassProminent": "Glass, filled"],
        "field.style": ["automatic": "macOS default", "plain": "No border", "bordered": "Bordered",
                        "roundedBorder": "Rounded border (old)", "squareBorder": "Square border (old)"],
        "field.shape": ["automatic": "macOS default", "capsule": "Capsule", "roundedRectangle": "Rounded rectangle"],
        "switcher.style": ["segmented": "Segmented", "tabSegments": "Tab switcher", "menu": "Pop-up", "tabs": "Tab view",
                           "tabBar": "Tab bar", "groupedTabs": "Grouped tab bar", "sidebarTabs": "Sidebar tabs", "dock": "Dock (drawn by Hatch)"],
        "row.list": ["automatic": "macOS default", "plain": "Plain", "inset": "Inset", "bordered": "Bordered", "sidebar": "Sidebar"],
        "row.height": ["automatic": "macOS default", "compact": "Compact", "roomy": "Roomy"],
        "alternating": ["off": "Off", "on": "Alternating"],
        "table.style": ["automatic": "macOS default (inset)", "inset": "Inset", "bordered": "Bordered with grid"],
        "table.headers": ["visible": "Shown", "hidden": "Hidden"],
        "form.style": ["automatic": "macOS default", "columns": "Columns", "grouped": "Grouped (like Settings)"],
        "badge.prominence": ["standard": "Standard", "increased": "More prominent", "decreased": "Less prominent"],
        "datePicker.style": ["automatic": "macOS default", "compact": "Compact", "field": "Field", "stepperField": "Field with stepper",
                             "graphical": "Calendar"],
        "progress.style": ["automatic": "macOS default", "linear": "Bar", "circular": "Spinner"],
        "slider.thumb": ["visible": "Shown", "hidden": "Hidden (a level)"],
        "gauge.style": ["automatic": "macOS default", "linearCapacity": "Filling bar", "accessoryLinear": "Bar with a marker",
                        "accessoryLinearCapacity": "Small filling bar", "accessoryCircular": "Ring with a marker",
                        "accessoryCircularCapacity": "Filling ring"],
        "controlGroup.style": ["automatic": "macOS default (joined)", "navigation": "Navigation (back, forward)", "palette": "Palette",
                               "menu": "Menu", "compactMenu": "Compact menu"],
        "textEditor.style": ["automatic": "macOS default", "plain": "Plain"],
        "row.separators": ["visible": "Shown", "hidden": "Hidden"],
        "row.accessory": ["none": "None", "chevron": "Chevron", "badge": "Count"],
        "row.actions": ["none": "None", "onHover": "On hover", "always": "Always"],
        "card.container": ["groupBox": "Group box", "formSection": "Form section", "custom": "Custom"],
        "card.surface": ["none": "None", "grouped": "Grouped fill", "bordered": "Bordered", "material": "Material", "glass": "Glass", "glassClear": "Clear glass"],
        "card.radius": ["none": "macOS default", "concentric": "Concentric with the window"],
        "card.padding": ["system": "macOS default"],
        "card.border": ["none": "None", "hairline": "Hairline"],
        "card.shadow": ["none": "None", "soft": "Soft"],
        "sheet.sizing": ["automatic": "macOS default", "form": "Form", "page": "Page", "fitted": "Fit the content"],
        "sheet.title": ["inline": "In the sheet", "large": "Large", "none": "None"],
        "badge.style": ["system": "macOS default", "capsule": "Capsule", "plain": "Plain number"],
        "toast.surface": ["glass": "Glass", "glassClear": "Clear glass", "material": "Material", "solid": "Solid"],
        "toast.position": ["top": "Top", "bottom": "Bottom"],
        "toast.duration": ["short": "Short", "long": "Long"],
        "emptyState.action": ["none": "None", "prominent": "Filled button", "glassProminent": "Glass, filled button", "link": "Link"],
    ]

    private static let helps: [String: String] = [
        "button.show": "When the button appears: always, or only when the pointer is over its row or card.",
        "button.confirm": "Ask before doing it, for actions that can't be undone.",
        "button.key": "Return makes it the default button of a sheet or alert (macOS draws it in the accent colour); Escape makes it the cancel button.",
        "button.tooltip": "What the tooltip says when the pointer rests on it.",
        "row.actions": "When a row's own buttons appear.",
        "toast.duration": "How long the toast stays before it goes.",
        "menu.order": "Whether macOS may reorder the items (putting the first nearest the pointer), or keeps them as written.",
    ]

    /// The question for a role whose looks compete: "How should main action buttons look?"
    public static func lookQuestion(_ role: ComponentRole) -> String {
        var title = role.title.lowercased()
        guard let element = ComponentElement.named(role.element) else { return "How should \(title) look?" }
        // "Menu button in a row" → "menu buttons in rows": the plural goes on the noun, before where it sits.
        var qualifier = ""
        for (one, many) in [(" in a row", " in rows"), (" in the toolbar", " in the toolbar"), (" in a menu", " in menus"), (", floating", " that float")]
        where title.hasSuffix(one) {
            title.removeLast(one.count); qualifier = many; break
        }
        let nouns: Set<String> = ["button", "toggle", "picker", "menu", "field", "form", "table", "card", "badge", "slider", "stepper", "gauge",
                                  "row", "editor", "switcher", "sheet", "toast", "state", "group", "layout"]
        let last = title.split(separator: " ").last.map(String.init) ?? ""
        let noun: String
        if last.hasSuffix("s") && nouns.contains(String(last.dropLast())) { noun = title }  // "radio buttons"
        else if last == "progress" { noun = title + " indicators" }
        else if nouns.contains(last) { noun = title + "s" }
        else { noun = "\(title) \(element.plural.lowercased())" }
        return "How should \(noun)\(qualifier) look?"
    }
}
