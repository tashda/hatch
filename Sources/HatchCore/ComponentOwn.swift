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
    /// The one view the code ends up with (`StatusChip`), named when the owner decides.
    public var codeName: String?
    /// The view whose look the component keeps, when its views are drawn differently.
    public var look: String?
    /// The ticket that makes the views one in the code, once decided.
    public var ticket: String?

    public init(id: String, title: String, family: String, variants: [Variant], native: String? = nil, redesign: String? = nil,
                status: ComponentRole.Status = .provisional, codeName: String? = nil) {
        self.id = id; self.title = title; self.family = family; self.variants = variants; self.native = native; self.redesign = redesign
        self.status = status; self.codeName = codeName
    }

    public var views: [String] { variants.flatMap(\.views) }
}

/// What a change to the app's own components asks for, from the API's body or the CLI.
public enum OwnChange: Equatable, Sendable {
    /// Take Hatch's proposal as it is: one component, its proposed sizes as variants.
    case accept(AppComponentProposal)
    /// Move views into a variant of a component (created when new): consolidating sizes.
    case move(views: [String], component: String, variant: String)
    /// Take views out into a component of their own (New Component…).
    case split(views: [String], from: String, title: String)
    /// Every view of one component moves into another; the first goes.
    case merge(from: String, into: String)
    /// The views are different on purpose: each becomes a component of its own, decided, and Hatch stops grouping them.
    case apart(component: String)
    /// These views are not components (a sample, a one-off): out of the system, and Hatch stops proposing them.
    case notComponent(views: [String])
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
            let variants = p.sizes.count > 1 ? p.sizes.map { OwnComponent.Variant(name: $0.name, views: $0.members) }
                : [OwnComponent.Variant(name: "standard", views: p.members)]
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
            // New views in a decided component: decided again.
            own[j].status = .provisional; own[j].ticket = nil
        case .split(let views, let from, let title):
            guard !views.isEmpty else { throw OwnChangeError(description: "Choose at least one view.") }
            let source = try own[index(from)]
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw OwnChangeError(description: "Give the new component a name.") }
            var id = source.family + "." + trimmed.lowercased().replacingOccurrences(of: " ", with: "-")
            while own(id) != nil { id += "-2" }
            takeOut(Set(views))
            // A component made from views of another is listed on its own, under its own name.
            own.append(OwnComponent(id: id, title: trimmed, family: trimmed.lowercased(), variants: [.init(name: "standard", views: views)]))
        case .merge(let from, let into):
            guard from != into else { throw OwnChangeError(description: "A component can't merge into itself.") }
            let views = try own[index(from)].views
            _ = try index(into)
            own.remove(at: try index(from))
            let j = try index(into)
            if own[j].variants.isEmpty { own[j].variants = [.init(name: "standard", views: views)] } else { own[j].variants[0].views += views }
            // A merged component has new views: decided again.
            own[j].status = .provisional; own[j].ticket = nil
        case .apart(let component):
            let c = try own[index(component)]
            own.remove(at: try index(component))
            for v in c.views {
                var id = c.family + "." + v
                while own(id) != nil { id += "-2" }
                own.append(OwnComponent(id: id, title: AppViewScanner.plainName(v), family: c.family, variants: [.init(name: "standard", views: [v])],
                                        status: .agreed, codeName: v))
            }
        case .notComponent(let views):
            guard !views.isEmpty else { throw OwnChangeError(description: "Choose at least one view.") }
            takeOut(Set(views))
            for v in views where !ownExcluded.contains(v) { ownExcluded.append(v) }
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

    /// The owner decides a component (CM17): its name, the view it becomes in the code, and whose look it keeps when
    /// its views are drawn differently. With more than one view, the draft of the ticket that makes them one.
    mutating func decideOwn(component: String, title: String, codeName: String, look: String?) throws -> ComponentsSetup.Draft? {
        guard let i = own.firstIndex(where: { $0.id == component }) else { throw OwnChangeError(description: "No component \(component).") }
        let name = title.trimmingCharacters(in: .whitespaces), code = codeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw OwnChangeError(description: "A component needs a name.") }
        guard code.first?.isUppercase == true, code.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw OwnChangeError(description: "\(code.isEmpty ? "The code name" : code) must be a Swift type name, such as StatusChip.")
        }
        let views = own[i].views
        if let look, !views.contains(look) { throw OwnChangeError(description: "\(look) is not one of \(name)'s views.") }
        own[i].title = name; own[i].codeName = code; own[i].look = look; own[i].status = .agreed
        // One view already named so: nothing changes in the code.
        if views == [code] { own[i].ticket = nil; return nil }
        let keep = look.map { "Keep the look of `\($0)`" + ($0 == code ? "" : " for `\(code)`") + "." } ?? "The views are drawn alike; keep that look."
        let draft = ComponentsSetup.Draft(type: .tweak, title: views.count > 1 ? "Make \(views.joined(separator: " and ")) one \(code)" : "Rename \(views[0]) to \(code)",
            body: """
            The owner decided the component \(name) (`\(own[i].id)`) in the Components Designer.

            Today: \(views.map { "`\($0)`" }.joined(separator: ", ")). After: one view, `\(code)`. \(keep) Move every use of the others to it, keep what each use shows, and remove the views that are left over. Nothing else changes.
            """)
        own[i].ticket = draft.title
        return draft
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
        // Without a variant, into the component's first (a component is one look unless it really has sizes).
        case "move": return .move(views: views(), component: try s("component"), variant: body["variant"]?.stringValue ?? "standard")
        case "split": return .split(views: views(), from: try s("component"), title: try s("title"))
        case "native": return .native(component: try s("component"), element: body["element"]?.stringValue)
        case "use": return .use(component: try s("component"), variant: try s("variant"), text: body["text"]?.stringValue ?? "")
        case "rename": return .rename(component: try s("component"), title: try s("title"))
        case "agree": return .agree(component: try s("component"))
        case "remove": return .remove(component: try s("component"))
        case "merge": return .merge(from: try s("component"), into: try s("into"))
        case "apart": return .apart(component: try s("component"))
        case "notComponent": return .notComponent(views: views())
        case let op: throw OwnChangeError(description: "Unknown op \(op).")
        }
    }
}
