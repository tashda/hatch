import Foundation

// Native first (decision NF1): what macOS already decides, so the design system never sets it, and where every default,
// rule and piece of advice comes from in Apple's documentation. Each cites a page that was read, with the date and SDK it
// was checked against; when Xcode's SDK moves past that version, `hatch components refs` lists what to read again. The
// full sourced notes are in `tools/components-corpus/native-facts.json`.

/// One page of Apple's documentation or Human Interface Guidelines.
public struct AppleReference: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// The path on developer.apple.com, such as `/design/human-interface-guidelines/buttons`.
    public var path: String
    /// When it was read, and against which SDK.
    public var checked: String
    public var sdk: String

    public init(_ id: String, _ title: String, _ path: String, checked: String = ComponentNative.checkedOn, sdk: String = ComponentNative.checkedSDK) {
        self.id = id; self.title = title; self.path = path; self.checked = checked; self.sdk = sdk
    }

    public var url: String { "https://developer.apple.com" + path }
}

/// Something wrong-headed in a system: setting what macOS sets anyway, or going against Apple's guidance. Advice, never
/// a problem: the owner may have reasons, and the Designer shows the page that says why.
public struct ComponentAdvice: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// The value is what macOS uses anyway.
        case redundant
        /// The place is styled by the system (a toolbar, a menu, an alert).
        case systemPlace
        /// Liquid Glass in the content layer.
        case glassInContent
        /// A destructive or Cancel button as the default button.
        case wrongDefault
        /// A view switcher drawn as a segmented control in the main area.
        case switcherInContent
    }

    public var kind: Kind
    public var role: String
    public var message: String
    /// The Apple page behind it.
    public var source: String
}

public enum ComponentNative {
    /// When the references below were last read, and the macOS SDK they describe.
    public static let checkedOn = "2026-10-05"
    public static let checkedSDK = "27.0"

    public static func reference(_ id: String) -> AppleReference? { references.first { $0.id == id } }

    /// References read against an older SDK than the one installed: read them again and update what cites them.
    public static func stale(installedSDK: String) -> [AppleReference] {
        func number(_ v: String) -> Double { Double(v.split(separator: ".").prefix(2).joined(separator: ".")) ?? 0 }
        return references.filter { number($0.sdk) < number(installedSDK) }
    }

    public static let references: [AppleReference] = [
        AppleReference("hig-buttons", "HIG: Buttons", "/design/human-interface-guidelines/buttons"),
        AppleReference("hig-menus", "HIG: Menus", "/design/human-interface-guidelines/menus"),
        AppleReference("hig-context-menus", "HIG: Context menus", "/design/human-interface-guidelines/context-menus"),
        AppleReference("hig-menu-bar", "HIG: The menu bar", "/design/human-interface-guidelines/the-menu-bar"),
        AppleReference("hig-toolbars", "HIG: Toolbars", "/design/human-interface-guidelines/toolbars"),
        AppleReference("hig-alerts", "HIG: Alerts", "/design/human-interface-guidelines/alerts"),
        AppleReference("hig-sheets", "HIG: Sheets", "/design/human-interface-guidelines/sheets"),
        AppleReference("hig-materials", "HIG: Materials (Liquid Glass)", "/design/human-interface-guidelines/materials"),
        AppleReference("hig-lists", "HIG: Lists and tables", "/design/human-interface-guidelines/lists-and-tables"),
        AppleReference("hig-sidebars", "HIG: Sidebars", "/design/human-interface-guidelines/sidebars"),
        AppleReference("hig-toggles", "HIG: Toggles", "/design/human-interface-guidelines/toggles"),
        AppleReference("hig-segmented", "HIG: Segmented controls", "/design/human-interface-guidelines/segmented-controls"),
        AppleReference("hig-text-fields", "HIG: Text fields", "/design/human-interface-guidelines/text-fields"),
        AppleReference("hig-boxes", "HIG: Boxes", "/design/human-interface-guidelines/boxes"),
        AppleReference("hig-color", "HIG: Color", "/design/human-interface-guidelines/color"),
        AppleReference("hig-layout", "HIG: Layout", "/design/human-interface-guidelines/layout"),
        AppleReference("liquid-glass", "Adopting Liquid Glass", "/documentation/technologyoverviews/adopting-liquid-glass"),
        AppleReference("swiftui-glass", "SwiftUI: Applying Liquid Glass to custom views", "/documentation/swiftui/applying-liquid-glass-to-custom-views"),
        AppleReference("swiftui-button", "SwiftUI: Button", "/documentation/swiftui/button"),
        AppleReference("swiftui-buttonstyle-automatic", "SwiftUI: PrimitiveButtonStyle.automatic", "/documentation/swiftui/primitivebuttonstyle/automatic"),
        AppleReference("swiftui-controlsize", "SwiftUI: ControlSize", "/documentation/swiftui/controlsize"),
        AppleReference("swiftui-defaultaction", "SwiftUI: KeyboardShortcut.defaultAction", "/documentation/swiftui/keyboardshortcut/defaultaction"),
        AppleReference("swiftui-cancelaction", "SwiftUI: KeyboardShortcut.cancelAction", "/documentation/swiftui/keyboardshortcut/cancelaction"),
        AppleReference("swiftui-confirmationdialog", "SwiftUI: confirmationDialog", "/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:)"),
        AppleReference("swiftui-pickerstyle-automatic", "SwiftUI: PickerStyle.automatic", "/documentation/swiftui/pickerstyle/automatic"),
        AppleReference("swiftui-togglestyle-automatic", "SwiftUI: ToggleStyle.automatic", "/documentation/swiftui/togglestyle/automatic"),
        AppleReference("swiftui-textfieldstyle-automatic", "SwiftUI: TextFieldStyle.automatic", "/documentation/swiftui/textfieldstyle/automatic"),
        AppleReference("swiftui-form", "SwiftUI: Form", "/documentation/swiftui/form"),
        AppleReference("swiftui-toolbarlabelstyle", "SwiftUI: windowToolbarLabelStyle(_:)", "/documentation/swiftui/scene/windowtoolbarlabelstyle(_:)"),
        AppleReference("swiftui-toolbarspacer", "SwiftUI: ToolbarSpacer", "/documentation/swiftui/toolbarspacer"),
        AppleReference("swiftui-presentationsizing", "SwiftUI: PresentationSizing.automatic", "/documentation/swiftui/presentationsizing/automatic"),
        AppleReference("swiftui-contentunavailable", "SwiftUI: ContentUnavailableView", "/documentation/swiftui/contentunavailableview"),
        AppleReference("swiftui-badge", "SwiftUI: badge(_:)", "/documentation/swiftui/view/badge(_:)"),
        AppleReference("swiftui-listrowseparator", "SwiftUI: listRowSeparator(_:edges:)", "/documentation/swiftui/view/listrowseparator(_:edges:)"),
        AppleReference("swiftui-scrollcontentbackground", "SwiftUI: scrollContentBackground(_:)", "/documentation/swiftui/view/scrollcontentbackground(_:)"),
        AppleReference("swiftui-inspector", "SwiftUI: inspector(isPresented:content:)", "/documentation/swiftui/view/inspector(ispresented:content:)"),
        AppleReference("swiftui-padding", "SwiftUI: padding(_:_:)", "/documentation/swiftui/view/padding(_:_:)"),
        // Added with the macOS 27 catalog check (CD52).
        AppleReference("hig-pickers", "HIG: Pickers", "/design/human-interface-guidelines/pickers"),
        AppleReference("swiftui-buttonsizing", "SwiftUI: buttonSizing(_:)", "/documentation/swiftui/view/buttonsizing(_:)"),
        AppleReference("swiftui-textinputbordershape", "SwiftUI: textInputBorderShape(_:)", "/documentation/swiftui/view/textinputbordershape(_:)"),
        AppleReference("swiftui-liststyle", "SwiftUI: ListStyle", "/documentation/swiftui/liststyle"),
        AppleReference("swiftui-tablestyle", "SwiftUI: TableStyle", "/documentation/swiftui/tablestyle"),
        AppleReference("swiftui-formstyle", "SwiftUI: FormStyle", "/documentation/swiftui/formstyle"),
        AppleReference("swiftui-badgeprominence", "SwiftUI: BadgeProminence", "/documentation/swiftui/badgeprominence"),
        AppleReference("swiftui-datepickerstyle", "SwiftUI: DatePickerStyle", "/documentation/swiftui/datepickerstyle"),
        AppleReference("swiftui-progressviewstyle", "SwiftUI: ProgressViewStyle", "/documentation/swiftui/progressviewstyle"),
        AppleReference("swiftui-slider", "SwiftUI: Slider", "/documentation/swiftui/slider"),
        AppleReference("swiftui-gaugestyle", "SwiftUI: GaugeStyle", "/documentation/swiftui/gaugestyle"),
        AppleReference("swiftui-controlgroupstyle", "SwiftUI: ControlGroupStyle", "/documentation/swiftui/controlgroupstyle"),
        AppleReference("swiftui-texteditorstyle", "SwiftUI: TextEditorStyle", "/documentation/swiftui/texteditorstyle"),
        AppleReference("hig-progress-indicators", "HIG: Progress indicators", "/design/human-interface-guidelines/progress-indicators"),
        AppleReference("hig-sliders", "HIG: Sliders", "/design/human-interface-guidelines/sliders"),
        AppleReference("hig-steppers", "HIG: Steppers", "/design/human-interface-guidelines/steppers"),
        AppleReference("hig-gauges", "HIG: Gauges", "/design/human-interface-guidelines/gauges"),
        AppleReference("hig-text-views", "HIG: Text views", "/design/human-interface-guidelines/text-views"),
    ]

    /// Places macOS styles itself (NF1): what a role may still set there. Toolbars: only the one prominent key action;
    /// menus and alerts: nothing but behaviour (the role, a key, a confirmation).
    public static let systemPlaces: [String: (allowed: Set<String>, why: String, source: String)] = [
        "toolbar": (["style"], "macOS draws toolbar items without a bezel, adds Liquid Glass and lets the window (and the user) choose icon or text; only the one key action may be prominent.", "hig-toolbars"),
        "contextMenu": ([], "Menu items are drawn by the system; a role here can only be destructive, and icons are a rule for the whole group.", "hig-menus"),
        "alert": ([], "Alert buttons are drawn by the system; the default and Cancel come from their keys and roles.", "hig-alerts"),
    ]

    /// Places in the content layer, where Liquid Glass does not belong (it is for controls and navigation).
    public static let contentPlaces: Set<String> = ["listRow", "card", "form", "inspector", "page", "emptyState"]
}

public extension ComponentSystem {
    /// Native advice for every role (NF1), each with the Apple page that says why. The templates have none.
    func advice() -> [ComponentAdvice] {
        var out: [ComponentAdvice] = []
        for r in roles {
            guard let element = ComponentElement.named(r.element) else { continue }
            let recipe = r.draft ?? r.recipe
            // 1. Settings that repeat what macOS does anyway.
            for (key, value) in recipe.sorted(by: { $0.key < $1.key }) {
                guard let p = element.parameter(key), p.systemDefault == value else { continue }
                out.append(ComponentAdvice(kind: .redundant, role: r.id, message: "\(r.id): \(key) \(value) is what macOS does anyway; leave it out.",
                                           source: p.source ?? element.source ?? "hig-buttons"))
            }
            // 2. Places the system styles.
            for place in r.places {
                guard let rule = ComponentNative.systemPlaces[place], !r.followsMacOS else { continue }
                let look = element.withoutDefaults(element.look(recipe)).filter { !rule.allowed.contains($0.key) && $0.key != "label" }
                let prominentOnly = place == "toolbar" && r.importance != .main && recipe["style"].map { $0.hasSuffix("Prominent") } == true
                if !look.isEmpty || prominentOnly {
                    out.append(ComponentAdvice(kind: .systemPlace, role: r.id,
                                               message: "\(r.id) styles a \(ComponentPlace.title(place).lowercased()): \(rule.why)", source: rule.source))
                }
            }
            // 3. Liquid Glass belongs to controls and navigation, not content.
            let glass = ["glass", "glassProminent"].contains(recipe["style"] ?? "") || recipe["surface"] == "glass" || recipe["look"] == "glass"
            let inContent = r.places.filter(ComponentNative.contentPlaces.contains)
            if glass, !inContent.isEmpty {
                out.append(ComponentAdvice(kind: .glassInContent, role: r.id,
                                           message: "\(r.id) puts Liquid Glass in the content layer (\(inContent.map { ComponentPlace.title($0).lowercased() }.joined(separator: ", "))); Apple keeps glass for controls and navigation and uses standard materials for content.",
                                           source: "hig-materials"))
            }
            // 4. A destructive or Cancel button is never the default.
            if recipe["key"] == "defaultAction", r.importance == .destructive || r.importance == .quiet {
                out.append(ComponentAdvice(kind: .wrongDefault, role: r.id,
                                           message: "\(r.id) is \(r.importance == .destructive ? "destructive" : "a Cancel-like action") and the default button; Apple never makes those the default.",
                                           source: r.importance == .destructive ? "hig-buttons" : "hig-alerts"))
            }
            // 5. Switching views in the main area is a tab view on macOS.
            if r.element == "switcher", recipe["style"] == "segmented", r.places.contains("page") {
                out.append(ComponentAdvice(kind: .switcherInContent, role: r.id,
                                           message: "\(r.id) switches views in the main area with a segmented control; on macOS Apple uses a tab view there and segmented controls in toolbars and inspectors.",
                                           source: "hig-segmented"))
            }
        }
        return out
    }
}
