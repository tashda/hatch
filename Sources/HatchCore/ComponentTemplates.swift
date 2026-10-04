import Foundation

/// A complete starting system shipped with Hatch (DS6): foundations, the places it adds, and roles for the common
/// elements, all provisional. Templates are data, so starting from one costs no tokens.
public struct ComponentTemplate: Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    let make: @Sendable (String) -> ComponentSystem

    /// The template as a system for an app with this name.
    public func system(name: String) -> ComponentSystem { make(name) }
}

public enum ComponentTemplates {
    public static let all: [ComponentTemplate] = [native, glass]

    public static func named(_ id: String) -> ComponentTemplate? { all.first { $0.id == id.lowercased() } }

    // Both templates need two places the standard list lacks: a page's own content area (where cards, sheets and toasts
    // sit) and the row of actions under a page or ticket title. Added as data, as DS5 allows.
    static let page = ComponentPlace.page
    static let actionRow = ComponentPlace.actionRow

    /// Values every template shares: the system's own colors and text styles, named by meaning.
    static func baseFoundations(cardRadius: Double, floating: String) -> [ComponentFoundation] {
        [
            ComponentFoundation("color.accent", .color, use: "The app's accent: selection, links, the main action.", system: "accentColor"),
            ComponentFoundation("color.critical", .color, use: "A real problem or a destructive action. Nothing else.", system: "systemRed"),
            ComponentFoundation("color.surface", .color, use: "The window behind content.", system: "windowBackgroundColor"),
            ComponentFoundation("color.content", .color, use: "Cards and content panels.", system: "controlBackgroundColor"),
            ComponentFoundation("color.separator", .color, use: "Hairlines between groups.", system: "separatorColor"),
            ComponentFoundation("text.pageTitle", .text, use: "The title of a page or ticket.", system: "title2", weight: "semibold"),
            ComponentFoundation("text.cardTitle", .text, use: "The title of a card, group or row.", system: "headline"),
            ComponentFoundation("text.body", .text, use: "Running text.", system: "body"),
            ComponentFoundation("text.caption", .text, use: "Captions, recommendations and their reasons.", system: "caption"),
            ComponentFoundation("text.code", .text, use: "Numbers and code only.", system: "body", design: "monospaced"),
            ComponentFoundation("space.inline", .space, use: "Between an icon and its label, or a value and its unit.", value: 4),
            ComponentFoundation("space.related", .space, use: "Between related controls in a row or stack.", value: 8),
            ComponentFoundation("space.group", .space, use: "Between groups, and inside a card.", value: 16),
            ComponentFoundation("space.section", .space, use: "Between sections of a page.", value: 24),
            ComponentFoundation("radius.control", .radius, use: "Small controls drawn by hand.", value: 6),
            ComponentFoundation("radius.card", .radius, use: "Cards and grouped boxes.", value: cardRadius),
            ComponentFoundation("material.floating", .material, use: "Floating controls: toasts, docks, panels. Never content.", system: floating),
        ]
    }

    // MARK: macOS Native

    /// Apple's defaults and the HIG: bordered controls, a prominent default button, nothing drawn by hand.
    public static let native = ComponentTemplate(
        id: "native", title: "macOS Native",
        summary: "Apple's defaults: bordered buttons, the prominent default button in sheets, GroupBox cards, no custom controls. The safe start for anything new."
    ) { name in
        ComponentSystem(name: name, template: "native",
            foundations: baseFoundations(cardRadius: 8, floating: "regularMaterial"),
            places: [page, actionRow],
            roles: [
                ComponentRole("button.primary", "Main action",
                    use: "The one action a screen, sheet or alert exists for; Return triggers it.",
                    avoid: "A second action on the same screen; anything risky.",
                    places: ["actionRow", "sheetFooter", "alert", "bottomBar", "emptyState"], importance: .main, perScreen: 1,
                    recipe: ["style": "borderedProminent", "size": "regular", "label": "titleOnly", "key": "defaultAction"]),
                ComponentRole("button.secondary", "Other action",
                    use: "Other actions on the same object, beside the main one.",
                    avoid: "Inside a row; rare or risky actions (put them in a menu).",
                    places: ["actionRow", "sheetFooter", "bottomBar", "card", "form"], importance: .other,
                    recipe: ["style": "bordered", "size": "regular", "label": "titleOnly"]),
                ComponentRole("button.cancel", "Cancel",
                    use: "Leaving a sheet or alert without a change; Escape triggers it.",
                    places: ["sheetFooter", "alert"], importance: .quiet,
                    recipe: ["style": "automatic", "label": "titleOnly", "key": "cancelAction"]),
                ComponentRole("button.inRow", "Row action",
                    use: "Actions on one row, card item or inspector line.",
                    avoid: "The main action of the screen.",
                    places: ["listRow", "inspector", "popover"], importance: .other,
                    recipe: ["style": "borderless", "size": "small", "label": "iconOnly", "show": "onHover", "tooltip": "title"]),
                ComponentRole("button.toolbar", "Toolbar item",
                    use: "Commands for the window or the selection.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["style": "automatic", "label": "iconOnly", "tooltip": "title"]),
                ComponentRole("button.destructive", "Destructive action",
                    use: "Deleting or dropping something: a menu item or alert button, confirmed first.",
                    avoid: "A visible button in a row or action row.",
                    places: ["contextMenu", "alert"], importance: .destructive,
                    recipe: ["style": "automatic", "tint": "critical", "confirm": "yes"]),
                ComponentRole("button.link", "Link",
                    use: "A light action inside text or under a group, such as Show All.",
                    places: ["form", "card", "inspector", "emptyState"], importance: .quiet,
                    recipe: ["style": "link", "label": "titleOnly"]),
                ComponentRole("menu.choice", "Action with a choice",
                    use: "An action that needs a choice first, such as Export As.",
                    places: ["actionRow", "toolbar"], importance: .other,
                    recipe: ["style": "automatic", "indicator": "visible", "label": "titleOnly"]),
                ComponentRole("menu.more", "More",
                    use: "Rare actions on the object, the risky ones last.",
                    places: ["actionRow", "toolbar", "listRow"], importance: .quiet,
                    recipe: ["style": "borderlessButton", "indicator": "hidden", "label": "iconOnly"]),
                ComponentRole("picker.viewMode", "View mode",
                    use: "Switching how the same content is shown, such as list or board.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["style": "segmented", "label": "hidden"]),
                ComponentRole("picker.setting", "Setting",
                    use: "Choosing one value of a setting.",
                    places: ["form", "inspector", "popover"], importance: .other,
                    recipe: ["style": "menu", "label": "visible"]),
                ComponentRole("toggle.setting", "On or off",
                    use: "A setting that is on or off and takes effect at once.",
                    places: ["form", "inspector", "popover"], importance: .other,
                    recipe: ["style": "switch", "size": "small"]),
                ComponentRole("field.text", "Text field",
                    use: "Typing a value.",
                    places: ["form", "sheetFooter", "popover", "inspector"], importance: .other,
                    recipe: ["style": "roundedBorder"]),
                ComponentRole("field.search", "Search",
                    use: "Filtering what a pane shows.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["style": "automatic"], custom: ".searchable"),
                ComponentRole("switcher.sections", "Sections",
                    use: "Switching between up to five sections of one pane.",
                    places: ["page", "toolbar"], importance: .other,
                    recipe: ["style": "segmented"],
                    variants: [ComponentVariant("many", use: "Six or more sections: a pull-down.", recipe: ["style": "menu"])]),
                ComponentRole("row.standard", "Row",
                    use: "One record in a list or table.",
                    places: ["listRow"], importance: .other,
                    recipe: ["density": "regular", "selection": "system", "accessory": "none", "actions": "onHover"]),
                ComponentRole("card.group", "Group",
                    use: "Related facts or settings grouped on a page or in the inspector.",
                    places: ["page", "inspector"], importance: .other,
                    recipe: ["surface": "grouped", "radius": "radius.card", "padding": "space.group"]),
                ComponentRole("sheet.standard", "Sheet",
                    use: "A short task that needs the owner's full attention.",
                    places: ["page"], importance: .other,
                    recipe: ["width": "medium", "footer": "trailing", "title": "inline"]),
                ComponentRole("badge.count", "Count",
                    use: "How many things wait for the owner.",
                    places: ["toolbar", "listRow"], importance: .other,
                    recipe: ["style": "count", "tint": "critical"]),
                ComponentRole("emptyState.standard", "Nothing here",
                    use: "A pane with nothing to show: say why and give the next step.",
                    places: ["page", "emptyState"], importance: .other,
                    recipe: ["style": "system", "action": "prominent"], custom: "ContentUnavailableView"),
            ])
    }

    // MARK: Glass

    /// Hatch's own look (LK1 to LK11, DR8): Liquid Glass capsules with icon and label, one prominent action first in the
    /// row, small bordered buttons inside rows, glass only for floating controls.
    public static let glass = ComponentTemplate(
        id: "glass", title: "Glass",
        summary: "Liquid Glass capsules with icon and label, one prominent glass action per screen, small bordered buttons inside rows, glass only for floating controls. Hatch's own look."
    ) { name in
        ComponentSystem(name: name, template: "glass",
            foundations: baseFoundations(cardRadius: 12, floating: "glass") + [
                ComponentFoundation("radius.floating", .radius, use: "Floating glass panels, such as a command bar.", value: 24),
            ],
            places: [page, actionRow],
            roles: [
                ComponentRole("button.primary", "Main action",
                    use: "The one main action of a screen, ticket, sheet or bottom bar, first in its row.",
                    avoid: "A second one on the same screen; actions inside a row or card.",
                    places: ["actionRow", "bottomBar", "sheetFooter", "alert", "emptyState"], importance: .main, perScreen: 1,
                    recipe: ["style": "glassProminent", "size": "large", "label": "titleAndIcon", "shape": "capsule", "key": "defaultAction"],
                    variants: [ComponentVariant("stop", use: "A run that can be stopped: the same button swaps in place and turns red while running.",
                                                recipe: ["tint": "critical"])]),
                ComponentRole("button.secondary", "Other action",
                    use: "Other actions on the same object, in the same row as the main action; the row wraps.",
                    avoid: "Inside a row, card or toast; rare or risky actions (put them in More).",
                    places: ["actionRow", "bottomBar"], importance: .other,
                    recipe: ["style": "glass", "size": "large", "label": "titleAndIcon", "shape": "capsule"]),
                ComponentRole("button.cancel", "Cancel",
                    use: "Leaving a sheet or dialog without a change.",
                    avoid: "Disabling the default button silently: say what is missing instead.",
                    places: ["sheetFooter", "alert"], importance: .quiet,
                    recipe: ["style": "automatic", "label": "titleOnly", "key": "cancelAction"]),
                ComponentRole("button.inRow", "Row action",
                    use: "Actions inside a row, card, inspector line or toast, shown on hover or selection.",
                    avoid: "The main action of the screen; glass inside content.",
                    places: ["listRow", "card", "inspector", "popover"], importance: .other,
                    recipe: ["style": "bordered", "size": "small", "label": "titleOnly", "show": "onHover"]),
                ComponentRole("button.toolbar", "Toolbar item",
                    use: "Commands for the window or the selection; the tooltip shows the shortcut.",
                    avoid: "Text labels; shortcuts in the label.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["style": "automatic", "label": "iconOnly", "tooltip": "shortcut"]),
                ComponentRole("button.destructive", "Destructive action",
                    use: "Rare or risky actions (Drop, Delete): an item in More or a context menu, then a confirmation sheet.",
                    avoid: "A visible button in an action row or row.",
                    places: ["contextMenu", "alert"], importance: .destructive,
                    recipe: ["style": "automatic", "tint": "critical", "confirm": "yes"]),
                ComponentRole("button.link", "Link",
                    use: "A light action inside text or under a group, such as Show All or Open in GitHub.",
                    places: ["form", "inspector", "emptyState"], importance: .quiet,
                    recipe: ["style": "link", "label": "titleOnly"]),
                ComponentRole("menu.choice", "Action with a choice",
                    use: "An action that needs a choice first: a glass button that opens a menu, no arrow.",
                    places: ["actionRow", "bottomBar"], importance: .other,
                    recipe: ["style": "button", "look": "glass", "indicator": "hidden", "label": "titleAndIcon"]),
                ComponentRole("menu.more", "More",
                    use: "Rare actions on the object, the risky ones last and confirmed.",
                    places: ["actionRow", "bottomBar"], importance: .quiet,
                    recipe: ["style": "button", "look": "glass", "indicator": "hidden", "label": "titleAndIcon"]),
                ComponentRole("picker.viewMode", "View mode",
                    use: "Switching how the same content is shown, in the toolbar.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["style": "segmented", "label": "hidden"]),
                ComponentRole("picker.setting", "Setting",
                    use: "Choosing one value of a setting, such as a provider or a model.",
                    places: ["form", "inspector", "popover"], importance: .other,
                    recipe: ["style": "menu", "label": "visible"]),
                ComponentRole("toggle.setting", "On or off",
                    use: "A setting that is on or off and takes effect at once.",
                    places: ["form", "inspector", "popover"], importance: .other,
                    recipe: ["style": "switch", "size": "small"]),
                ComponentRole("field.text", "Text field",
                    use: "Typing a value.",
                    places: ["form", "popover", "inspector"], importance: .other,
                    recipe: ["style": "roundedBorder"]),
                ComponentRole("field.search", "Search",
                    use: "Filtering what a pane shows, with tokens and saved views.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["style": "automatic"], custom: ".searchable"),
                ComponentRole("switcher.sections", "Sections",
                    use: "Switching between up to five sections of one pane: a glass text dock.",
                    places: ["page", "toolbar"], importance: .other,
                    recipe: ["style": "dock", "size": "large"],
                    variants: [ComponentVariant("many", use: "Six or more sections: a pull-down.", recipe: ["style": "menu"])]),
                ComponentRole("row.queue", "Row",
                    use: "One record in a list or queue: status glyph, title, actions on hover.",
                    places: ["listRow"], importance: .other,
                    recipe: ["density": "regular", "selection": "system", "accessory": "none", "actions": "onHover"]),
                ComponentRole("card.details", "Details card",
                    use: "Facts or settings grouped on a page or in the inspector.",
                    avoid: "Glass: glass is for floating controls, never for content.",
                    places: ["page", "inspector"], importance: .other,
                    recipe: ["surface": "grouped", "radius": "radius.card", "padding": "space.group", "border": "none", "shadow": "none"]),
                ComponentRole("sheet.standard", "Sheet",
                    use: "A short task that needs full attention; the default button is the main action.",
                    places: ["page"], importance: .other,
                    recipe: ["width": "medium", "footer": "trailing", "title": "inline"]),
                ComponentRole("badge.count", "Count",
                    use: "How many things wait for the owner, like the Dock badge.",
                    places: ["toolbar", "listRow"], importance: .other,
                    recipe: ["style": "count", "tint": "critical"]),
                ComponentRole("toast.feedback", "Toast",
                    use: "Short feedback after an action, with Undo when it can be undone.",
                    avoid: "Errors that need an answer.",
                    places: ["page"], importance: .other,
                    recipe: ["surface": "glass", "position": "bottom", "duration": "short"]),
                ComponentRole("emptyState.standard", "Nothing here",
                    use: "A pane with nothing to show: say why and give the next step.",
                    places: ["page", "emptyState"], importance: .other,
                    recipe: ["style": "system", "action": "prominent"], custom: "ContentUnavailableView"),
            ])
    }
}
