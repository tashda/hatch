import Foundation

// The app's own components in the design system (decisions CM16 to CM18): kept beside SwiftUI's, each with a few
// variants, the app's views that belong to each, and where each variant is used. Hatch proposes the grouping
// (`AppViewScanner`); the owner accepts it, moves views between sizes, splits views out, takes the native option,
// makes a variant a setting, or asks for a redesign. Every change goes through these functions, so the API, the CLI and
// the Designer's local mode do the same thing.

/// One of the app's own components, as agreed.
public struct OwnComponent: Codable, Equatable, Identifiable, Sendable {
    public struct Variant: Codable, Equatable, Sendable {
        /// small, medium, large, or the owner's own word.
        public var name: String
        /// The app's views that are this variant today (type names).
        public var views: [String]
        /// Where it is used, in a sentence: the usage rule agents follow ("a status in a row").
        public var use: String
        /// The app offers this choice to its users (a setting), with the ticket that builds it.
        public var setting: String?

        public init(name: String, views: [String], use: String = "", setting: String? = nil) {
            self.name = name; self.views = views; self.use = use; self.setting = setting
        }
    }

    public var id: String
    public var title: String
    /// chip, card, row…, from the scan.
    public var family: String
    public var variants: [Variant]
    /// The native element this is replaced by, when the owner chose SwiftUI's own (`card` for GroupBox).
    public var native: String?
    /// The Proposal ticket that redesigns it, while one is open.
    public var redesign: String?
    public var status: ComponentRole.Status

    public init(id: String, title: String, family: String, variants: [Variant], native: String? = nil, redesign: String? = nil,
                status: ComponentRole.Status = .provisional) {
        self.id = id; self.title = title; self.family = family; self.variants = variants; self.native = native; self.redesign = redesign
        self.status = status
    }

    public var views: [String] { variants.flatMap(\.views) }
}

/// What a change to the app's own components asks for, from the API's body or the CLI.
public enum OwnChange: Equatable, Sendable {
    /// Take Hatch's proposal as it is: one component, its proposed sizes as variants.
    case accept(AppComponentProposal)
    /// Move views into a variant of a component (created when new): consolidating sizes.
    case move(views: [String], component: String, variant: String)
    /// Take views out into a component of their own.
    case split(views: [String], from: String, title: String)
    /// Use SwiftUI's own element instead of the app's views.
    case native(component: String, element: String?)
    /// Where a variant is used: the rule agents follow.
    case use(component: String, variant: String, text: String)
    /// Rename a component.
    case rename(component: String, title: String)
    /// Agree the component as it stands.
    case agree(component: String)
    /// Remove a component (its views go back to Hatch's proposals).
    case remove(component: String)
}

public struct OwnChangeError: Error, CustomStringConvertible {
    public var description: String
}

public extension ComponentSystem {
    func own(_ id: String) -> OwnComponent? { own.first { $0.id == id } }

    /// The component a view belongs to, if it has been agreed into one.
    func ownComponent(containing view: String) -> OwnComponent? { own.first { $0.views.contains(view) } }

    mutating func change(_ change: OwnChange) throws {
        func index(_ id: String) throws -> Int {
            guard let i = own.firstIndex(where: { $0.id == id }) else { throw OwnChangeError(description: "No component \(id).") }
            return i
        }
        /// A view is in one variant of one component: moving it takes it out of wherever it was.
        func takeOut(_ views: Set<String>) {
            for i in own.indices {
                for v in own[i].variants.indices { own[i].variants[v].views.removeAll { views.contains($0) } }
                own[i].variants.removeAll { $0.views.isEmpty && $0.setting == nil && $0.use.isEmpty }
            }
            own.removeAll { $0.variants.isEmpty }
        }
        switch change {
        case .accept(let p):
            guard own(p.id) == nil else { throw OwnChangeError(description: "\(p.title) is already a component.") }
            takeOut(Set(p.members))
            let variants = p.sizes.isEmpty ? [OwnComponent.Variant(name: "standard", views: p.members)]
                : p.sizes.map { OwnComponent.Variant(name: p.sizes.count == 1 ? "standard" : $0.name, views: $0.members) }
            own.append(OwnComponent(id: p.id, title: p.title, family: p.family, variants: variants))
        case .move(let views, let component, let variant):
            guard !views.isEmpty else { throw OwnChangeError(description: "Choose at least one view.") }
            _ = try index(component)
            takeOut(Set(views))
            // Taking the views out can empty and remove the component itself: then it comes back with them.
            guard let j = own.firstIndex(where: { $0.id == component }) else {
                throw OwnChangeError(description: "Moving every view of \(component) out of it leaves nothing to move them into.")
            }
            if let v = own[j].variants.firstIndex(where: { $0.name == variant }) { own[j].variants[v].views += views }
            else { own[j].variants.append(.init(name: variant, views: views)) }
        case .split(let views, let from, let title):
            guard !views.isEmpty else { throw OwnChangeError(description: "Choose at least one view.") }
            let source = try own[index(from)]
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw OwnChangeError(description: "Give the new component a name.") }
            var id = source.family + "." + trimmed.lowercased().replacingOccurrences(of: " ", with: "-")
            while own(id) != nil { id += "-2" }
            takeOut(Set(views))
            own.append(OwnComponent(id: id, title: trimmed, family: source.family, variants: [.init(name: "standard", views: views)]))
        case .native(let component, let element):
            let i = try index(component)
            own[i].native = element
        case .use(let component, let variant, let text):
            let i = try index(component)
            guard let v = own[i].variants.firstIndex(where: { $0.name == variant }) else { throw OwnChangeError(description: "No variant \(variant).") }
            own[i].variants[v].use = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .rename(let component, let title):
            let i = try index(component)
            let t = title.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { throw OwnChangeError(description: "A component needs a name.") }
            own[i].title = t
        case .agree(let component):
            let i = try index(component)
            own[i].status = .agreed
        case .remove(let component):
            let i = try index(component)
            own.remove(at: i)
        }
    }

    /// A variant becomes a choice the app's users make (a setting): the draft of the ticket that builds it.
    mutating func makeOwnSetting(component: String, variant: String) throws -> ComponentsSetup.Draft {
        guard let i = own.firstIndex(where: { $0.id == component }),
              let v = own[i].variants.firstIndex(where: { $0.name == variant }) else { throw OwnChangeError(description: "No variant \(variant) of \(component).") }
        let c = own[i]
        let others = c.variants.map(\.name).filter { $0 != variant }
        let draft = ComponentsSetup.Draft(type: .proposal, title: "Let people choose the \(c.title.lowercased()) size",
            body: """
            The \(c.title) component (`\(c.id)`) has the variants \(c.variants.map(\.name).joined(separator: ", ")). Make the choice between \(variant)\(others.isEmpty ? "" : " and " + others.joined(separator: ", ")) a setting in the app, with \(variant) as the default.

            Views today: \(c.variants[v].views.joined(separator: ", ")).
            """)
        own[i].variants[v].setting = draft.title
        return draft
    }

    /// The Proposal that redesigns a component (CM18): an agent builds two or three real options of it, and the native
    /// one, as specimens in the Stage; the owner picks; the pick becomes the component.
    mutating func redesignOwn(component: String, what: String) throws -> ComponentsSetup.Draft {
        guard let i = own.firstIndex(where: { $0.id == component }) else { throw OwnChangeError(description: "No component \(component).") }
        let c = own[i]
        let native = AppViewScanner.nativeOption(family: c.family)
        let variants = c.variants.map { "- \($0.name): \($0.views.joined(separator: ", "))" + ($0.use.isEmpty ? "" : " (used for \($0.use))") }
        let draft = ComponentsSetup.Draft(type: .proposal, title: "Redesign the \(c.title.lowercased())", body: """
            \(what.trimmingCharacters(in: .whitespacesAndNewlines))

            The app's own component `\(c.id)` (\(c.title)), with its views today:
            \(variants.joined(separator: "\n"))

            Build two or three options as Swift specimens in the Stage, each drawing the component with real content in light and dark, plus the native option (\(native.words)). Say what each gains and costs, and recommend one. Do not change the app's code on this ticket until it is accepted.
            """)
        own[i].redesign = draft.title
        return draft
    }
}

public extension OwnChange {
    /// The change an API or CLI body asks for: `op` and its fields. `proposal` comes from the scan, which only the
    /// caller has (the app's code is read where it lives).
    static func parse(_ body: [String: JSONValue], proposal: (String) -> AppComponentProposal?) throws -> OwnChange {
        func s(_ k: String) throws -> String {
            guard let v = body[k]?.stringValue, !v.isEmpty else { throw OwnChangeError(description: "\(k) is required.") }
            return v
        }
        func views() -> [String] { body["views"]?.arrayValue?.compactMap(\.stringValue) ?? [] }
        switch try s("op") {
        case "accept":
            let id = try s("component")
            guard let p = proposal(id) else { throw OwnChangeError(description: "Hatch proposes no component \(id) for this app.") }
            return .accept(p)
        case "move": return .move(views: views(), component: try s("component"), variant: try s("variant"))
        case "split": return .split(views: views(), from: try s("component"), title: try s("title"))
        case "native": return .native(component: try s("component"), element: body["element"]?.stringValue)
        case "use": return .use(component: try s("component"), variant: try s("variant"), text: body["text"]?.stringValue ?? "")
        case "rename": return .rename(component: try s("component"), title: try s("title"))
        case "agree": return .agree(component: try s("component"))
        case "remove": return .remove(component: try s("component"))
        case let op: throw OwnChangeError(description: "Unknown op \(op).")
        }
    }
}
