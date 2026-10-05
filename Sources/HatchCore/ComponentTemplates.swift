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

    /// Every template starts with Apple's rules (NF4).
    static func withAppleRules(_ system: ComponentSystem) -> ComponentSystem {
        var s = system
        s.rules = ComponentRule.appleDefaults
        return s
    }

    /// The system's own colors and text styles, named by meaning (HIG Color: system colors, never hard-coded values).
    static let systemFoundations: [ComponentFoundation] = [
        ComponentFoundation("color.accent", .color, use: "The accent: selection, links, the main action. The user's accent color replaces it.", system: "accentColor"),
        ComponentFoundation("color.critical", .color, use: "A real problem or a destructive action. Nothing else.", system: "systemRed"),
        ComponentFoundation("color.surface", .color, use: "The window behind content.", system: "windowBackgroundColor"),
        ComponentFoundation("color.content", .color, use: "Content panels drawn by the app.", system: "controlBackgroundColor"),
        ComponentFoundation("color.separator", .color, use: "Hairlines between groups.", system: "separatorColor"),
        ComponentFoundation("text.pageTitle", .text, use: "The title of a page or ticket.", system: "title2", weight: "semibold"),
        ComponentFoundation("text.cardTitle", .text, use: "The title of a group or row.", system: "headline"),
        ComponentFoundation("text.body", .text, use: "Running text.", system: "body"),
        ComponentFoundation("text.caption", .text, use: "Captions, recommendations and their reasons.", system: "caption"),
        ComponentFoundation("text.code", .text, use: "Numbers and code only.", system: "body", design: "monospaced"),
    ]

    // MARK: macOS Native

    /// Apple's defaults (NF1, NF3): almost every role follows macOS, so the system decides now and in later versions.
    /// No spacing numbers: macOS gives none and asks for standard spacing.
    public static let native = ComponentTemplate(
        id: "native", title: "macOS Native",
        summary: "Apple's defaults throughout: every control follows macOS, GroupBox for boxes, a tab view to switch views, standard spacing. The safe start for anything new."
    ) { name in
        withAppleRules(ComponentSystem(name: name, template: "native",
            foundations: systemFoundations,
            places: [page, actionRow],
            roles: [
                ComponentRole("button.primary", "Main action",
                    use: "The one action a screen, sheet or alert exists for; Return triggers it and macOS draws it as the default button.",
                    avoid: "A second one on the same screen; anything destructive or Cancel.",
                    places: ["actionRow", "sheetFooter", "alert", "bottomBar", "emptyState"], importance: .main, perScreen: 1,
                    recipe: ["key": "defaultAction"], followsMacOS: true, sources: ["swiftui-defaultaction", "hig-buttons"]),
                ComponentRole("button.secondary", "Other action",
                    use: "Other actions on the same object, beside the main one.",
                    avoid: "Rare or risky actions (put them in a menu).",
                    places: ["actionRow", "sheetFooter", "bottomBar", "card", "form"], importance: .other,
                    followsMacOS: true, sources: ["swiftui-buttonstyle-automatic"]),
                ComponentRole("button.cancel", "Cancel",
                    use: "Leaving a sheet or alert without a change; Escape triggers it. On the leading side of the default button.",
                    places: ["sheetFooter", "alert"], importance: .quiet,
                    recipe: ["key": "cancelAction"], followsMacOS: true, sources: ["swiftui-cancelaction", "hig-alerts"]),
                ComponentRole("button.inRow", "Row action",
                    use: "Actions on one row, item or inspector line; the list or form styles them.",
                    avoid: "The main action of the screen.",
                    places: ["listRow", "inspector", "popover"], importance: .other,
                    recipe: ["show": "onHover", "tooltip": "title"], followsMacOS: true, sources: ["swiftui-buttonstyle-automatic", "swiftui-button"]),
                ComponentRole("button.toolbar", "Toolbar item",
                    use: "Commands for the window or the selection, with a symbol and a title; the window decides icon or text. Every one is also in the menu bar.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["label": "titleAndIcon", "tooltip": "title"], followsMacOS: true, sources: ["hig-toolbars", "swiftui-toolbarlabelstyle"]),
                ComponentRole("button.toolbarPrimary", "Toolbar key action",
                    use: "The one prominent action in a toolbar (Done, Submit), on its trailing side.",
                    avoid: "More than one per toolbar.",
                    places: ["toolbar"], importance: .main, perScreen: 1,
                    recipe: ["style": "borderedProminent", "label": "titleAndIcon"], sources: ["hig-toolbars", "hig-buttons"]),
                ComponentRole("button.destructive", "Destructive action",
                    use: "Deleting or anything that cannot be undone: role destructive (red), confirmed first when it cannot be undone.",
                    avoid: "The default button; an alert for a common action that can be undone.",
                    places: ["contextMenu", "alert"], importance: .destructive,
                    recipe: ["confirm": "yes"], followsMacOS: true, sources: ["hig-buttons", "hig-alerts", "swiftui-confirmationdialog"]),
                ComponentRole("button.menuItem", "Menu item",
                    use: "An item in a menu or a context menu; the system draws it.",
                    places: ["contextMenu"], importance: .other, followsMacOS: true, sources: ["hig-menus", "hig-context-menus"]),
                ComponentRole("button.link", "Link",
                    use: "A light action inside text or under a group, such as Show All.",
                    places: ["form", "card", "inspector", "emptyState"], importance: .quiet,
                    recipe: ["style": "link"], sources: ["swiftui-button"]),
                ComponentRole("menu.choice", "Action with a choice",
                    use: "An action that needs a choice first, such as Export As.",
                    places: ["actionRow", "toolbar"], importance: .other, followsMacOS: true, sources: ["hig-menus"]),
                ComponentRole("picker.viewMode", "View mode",
                    use: "Switching how the same content is shown, in the toolbar.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["style": "segmented"], sources: ["hig-segmented"]),
                ComponentRole("picker.setting", "Setting",
                    use: "Choosing one value of a setting: a pop-up button.",
                    places: ["form", "inspector", "popover"], importance: .other, followsMacOS: true, sources: ["swiftui-pickerstyle-automatic"]),
                ComponentRole("toggle.setting", "On or off",
                    use: "A single setting that is on or off: a checkbox.",
                    avoid: "A switch, except for an emphasized setting that governs a group.",
                    places: ["form", "inspector", "popover"], importance: .other, followsMacOS: true, sources: ["swiftui-togglestyle-automatic", "hig-toggles"]),
                ComponentRole("field.text", "Text field",
                    use: "Typing a short value, sized to what is expected.",
                    places: ["form", "sheetFooter", "popover", "inspector"], importance: .other, followsMacOS: true, sources: ["hig-text-fields"]),
                ComponentRole("field.search", "Search",
                    use: "Filtering what a pane shows.",
                    places: ["toolbar"], importance: .other, custom: ".searchable", followsMacOS: true, sources: ["hig-toolbars"]),
                ComponentRole("switcher.sections", "Sections",
                    use: "Switching between views of one pane: a tab view in the main area.",
                    avoid: "A segmented control in the main area (use it in a toolbar or inspector).",
                    places: ["page"], importance: .other,
                    recipe: ["style": "tabs"], sources: ["hig-segmented"]),
                ComponentRole("row.standard", "Row",
                    use: "One record in a list or table; the list style draws it.",
                    places: ["listRow"], importance: .other, followsMacOS: true, sources: ["hig-lists"]),
                ComponentRole("card.group", "Group",
                    use: "Related facts or settings grouped on a page or in the inspector: a GroupBox, small, never nested.",
                    places: ["page", "inspector"], importance: .other,
                    recipe: ["container": "groupBox"], sources: ["hig-boxes"]),
                ComponentRole("sheet.standard", "Sheet",
                    use: "A short task that needs full attention; macOS sizes it to a form fitted to its content.",
                    places: ["page"], importance: .other, followsMacOS: true, sources: ["hig-sheets", "swiftui-presentationsizing"]),
                ComponentRole("badge.count", "Count",
                    use: "How many things wait, on a list row, a toolbar item or a menu item.",
                    places: ["toolbar", "listRow"], importance: .other, followsMacOS: true, sources: ["swiftui-badge"]),
                ComponentRole("emptyState.standard", "Nothing here",
                    use: "A pane with nothing to show: say why and give the next step, ideally a button.",
                    places: ["page", "emptyState"], importance: .other,
                    recipe: ["action": "prominent"], custom: "ContentUnavailableView", sources: ["swiftui-contentunavailable"]),
            ]))
    }

    // MARK: Glass

    /// Hatch's own look (LK1 to LK11, DR8) where it differs from macOS: Liquid Glass capsules with icon and label for the
    /// actions of a screen, small bordered buttons inside rows, a glass section dock. Everything else follows macOS.
    public static let glass = ComponentTemplate(
        id: "glass", title: "Glass",
        summary: "macOS everywhere it decides, plus Liquid Glass capsules with icon and label for a screen's own actions, one prominent glass action, small bordered buttons in rows and a glass section dock. Hatch's own look."
    ) { name in
        withAppleRules(ComponentSystem(name: name, template: "glass",
            foundations: systemFoundations + [
                ComponentFoundation("space.related", .space, use: "Between related controls in Hatch-drawn views.", value: 8),
                ComponentFoundation("space.group", .space, use: "Between groups, and inside Hatch-drawn panels.", value: 16),
                ComponentFoundation("radius.floating", .radius, use: "Floating glass panels, such as a command bar.", value: 24),
                ComponentFoundation("material.floating", .material, use: "Floating controls: toasts, docks, panels. Never content.", system: "glass"),
            ],
            places: [page, actionRow, ComponentPlace.floating],
            roles: [
                ComponentRole("button.primary", "Main action",
                    use: "The one main action of a screen, ticket or bottom bar, first in its row; in a sheet, the default button.",
                    avoid: "A second one on the same screen; actions inside a row or card.",
                    places: ["actionRow", "bottomBar", "floating"], importance: .main, perScreen: 1,
                    recipe: ["style": "glassProminent", "size": "large", "label": "titleAndIcon", "key": "defaultAction"],
                    variants: [ComponentVariant("stop", use: "A run that can be stopped: the same button swaps in place and turns red while running.",
                                                recipe: ["tint": "critical"])],
                    sources: ["liquid-glass", "hig-buttons"]),
                ComponentRole("button.sheetDefault", "Default button",
                    use: "The button Return triggers in a sheet or alert; macOS draws it as the default.",
                    avoid: "Cancel or a destructive action.",
                    places: ["sheetFooter", "alert"], importance: .main,
                    recipe: ["key": "defaultAction"], followsMacOS: true, sources: ["swiftui-defaultaction", "hig-alerts"]),
                ComponentRole("button.secondary", "Other action",
                    use: "Other actions on the same object, in the same row as the main action; the row wraps.",
                    avoid: "Inside a row, card or toast; rare or risky actions (put them in More).",
                    places: ["actionRow", "bottomBar", "floating"], importance: .other,
                    recipe: ["style": "glass", "size": "large", "label": "titleAndIcon"], sources: ["liquid-glass"]),
                ComponentRole("button.cancel", "Cancel",
                    use: "Leaving a sheet or dialog without a change; on the leading side of the default button.",
                    places: ["sheetFooter", "alert"], importance: .quiet,
                    recipe: ["key": "cancelAction"], followsMacOS: true, sources: ["swiftui-cancelaction", "hig-alerts"]),
                ComponentRole("button.inRow", "Row action",
                    use: "Actions inside a row, card, inspector line or toast, shown on hover or selection.",
                    avoid: "The main action of the screen; glass inside content.",
                    places: ["listRow", "card", "inspector", "popover"], importance: .other,
                    recipe: ["style": "bordered", "size": "small", "label": "titleOnly", "show": "onHover"], sources: ["hig-materials"]),
                ComponentRole("button.toolbar", "Toolbar item",
                    use: "Commands for the window or the selection, with a symbol and a title; the tooltip shows the shortcut. Every one is also in the menu bar.",
                    avoid: "Shortcuts in the label; a toolbar background or tint.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["label": "titleAndIcon", "tooltip": "shortcut"], followsMacOS: true, sources: ["hig-toolbars", "swiftui-toolbarlabelstyle"]),
                ComponentRole("button.destructive", "Destructive action",
                    use: "Rare or risky actions (Drop, Delete): an item in More or a context menu, then a confirmation.",
                    avoid: "A visible button in an action row or row; the default button.",
                    places: ["contextMenu", "alert"], importance: .destructive,
                    recipe: ["confirm": "yes"], followsMacOS: true, sources: ["hig-buttons", "swiftui-confirmationdialog"]),
                ComponentRole("button.menuItem", "Menu item",
                    use: "An item in a menu, a More menu or a context menu; the system draws it.",
                    places: ["contextMenu"], importance: .other, followsMacOS: true, sources: ["hig-menus"]),
                ComponentRole("button.link", "Link",
                    use: "A light action inside text or under a group, such as Show All or Open in GitHub.",
                    places: ["form", "inspector", "emptyState"], importance: .quiet,
                    recipe: ["style": "link"], sources: ["swiftui-button"]),
                ComponentRole("menu.choice", "Action with a choice",
                    use: "An action that needs a choice first: a glass button that opens a menu, no arrow.",
                    places: ["actionRow", "bottomBar"], importance: .other,
                    recipe: ["style": "button", "look": "glass", "indicator": "hidden", "label": "titleAndIcon"], sources: ["liquid-glass"]),
                ComponentRole("menu.more", "More",
                    use: "Rare actions on the object, the risky ones last and confirmed.",
                    places: ["actionRow", "bottomBar"], importance: .quiet,
                    recipe: ["style": "button", "look": "glass", "indicator": "hidden", "label": "titleAndIcon"], sources: ["liquid-glass", "hig-menus"]),
                ComponentRole("picker.viewMode", "View mode",
                    use: "Switching how the same content is shown, in the toolbar.",
                    places: ["toolbar"], importance: .other,
                    recipe: ["style": "segmented", "label": "hidden"], sources: ["hig-segmented"]),
                ComponentRole("picker.setting", "Setting",
                    use: "Choosing one value of a setting, such as a provider or a model: a pop-up button.",
                    places: ["form", "inspector", "popover"], importance: .other, followsMacOS: true, sources: ["swiftui-pickerstyle-automatic"]),
                ComponentRole("toggle.setting", "On or off",
                    use: "A setting that is on or off: a mini switch, so rows in a grouped form keep their height.",
                    places: ["form", "inspector", "popover"], importance: .other,
                    recipe: ["style": "switch", "size": "mini"], sources: ["hig-toggles"]),
                ComponentRole("field.text", "Text field",
                    use: "Typing a short value, sized to what is expected.",
                    places: ["form", "popover", "inspector"], importance: .other, followsMacOS: true, sources: ["hig-text-fields"]),
                ComponentRole("field.search", "Search",
                    use: "Filtering what a pane shows, with tokens and saved views.",
                    places: ["toolbar"], importance: .other, custom: ".searchable", followsMacOS: true, sources: ["hig-toolbars"]),
                ComponentRole("switcher.sections", "Sections",
                    use: "Switching between up to five sections of one pane: a glass text dock floating over it.",
                    places: ["floating"], importance: .other,
                    recipe: ["style": "dock", "size": "large"],
                    variants: [ComponentVariant("many", use: "Six or more sections: a pop-up.", recipe: ["style": "menu"])],
                    sources: ["liquid-glass", "hig-segmented"]),
                ComponentRole("row.queue", "Row",
                    use: "One record in a list or queue: status glyph, title, actions on hover; the list draws the row.",
                    places: ["listRow"], importance: .other,
                    recipe: ["actions": "onHover"], followsMacOS: true, sources: ["hig-lists"]),
                ComponentRole("card.details", "Details",
                    use: "Facts or settings grouped on a page or in the inspector: a grouped Form section.",
                    avoid: "Glass: glass is for floating controls, never for content.",
                    places: ["page", "inspector"], importance: .other,
                    recipe: ["container": "formSection"], sources: ["swiftui-form", "hig-materials"]),
                ComponentRole("sheet.standard", "Sheet",
                    use: "A short task that needs full attention; macOS sizes it.",
                    places: ["page"], importance: .other, followsMacOS: true, sources: ["swiftui-presentationsizing", "hig-sheets"]),
                ComponentRole("badge.count", "Count",
                    use: "How many things wait for the owner, on a toolbar item or a row.",
                    places: ["toolbar", "listRow"], importance: .other, followsMacOS: true, sources: ["swiftui-badge"]),
                ComponentRole("toast.feedback", "Toast",
                    use: "Short feedback after an action, with Undo when it can be undone: a glass capsule floating over the content.",
                    avoid: "Errors that need an answer.",
                    places: ["floating"], importance: .other,
                    recipe: ["surface": "glass", "position": "bottom", "duration": "short"], sources: ["hig-materials", "hig-layout"]),
                ComponentRole("emptyState.standard", "Nothing here",
                    use: "A pane with nothing to show: say why and give the next step.",
                    places: ["page", "emptyState"], importance: .other,
                    recipe: ["action": "prominent"], custom: "ContentUnavailableView", sources: ["swiftui-contentunavailable"]),
            ]))
    }
}
