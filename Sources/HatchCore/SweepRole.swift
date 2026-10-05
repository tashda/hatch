import Foundation

/// The design an accepted Sweep saves as a role in the design system (decision SW6, SW14): the role, the look the owner chose
/// (one recipe of the element's own settings), and where it applies.
public struct AcceptedRoleDesign: Equatable, Sendable {
    public var role: String
    /// The option the owner chose, a specimen id of the Proposal.
    public var option: String
    public var look: [String: String]
    public var place: String?
    public var area: String?
    /// One line for a variant ("Cards in the inspector"); the Sweep's title for the role's own look.
    public var use: String
}

public extension HatchStore {
    /// The role design an accepted Sweep carries, from its stored manifest and the owner's picks. The chosen option is the pick on
    /// the specimen topic, or Hatch's recommendation when the owner accepted without picking. Nil when the Sweep names no role or
    /// the chosen option has no look.
    func acceptedRoleDesign(for t: Ticket) throws -> AcceptedRoleDesign? {
        guard t.type == .sweep, let json = try proposalManifest(ticketId: t.id) else { return nil }
        let manifest = JSONValue.parse(json)
        guard let role = manifest["role"], let roleId = role["id"]?.stringValue, !roleId.isEmpty else { return nil }
        let topic = manifest["exhibitTopic"]
        let topicId = topic?["id"]?.stringValue ?? "exhibit"
        let picked = try picks(ticketId: t.id).first { $0.topic == topicId }?.choice
        guard let option = picked ?? topic?["recommended"]?.stringValue,
              let recipe = role["looks"]?[option]?.objectValue else { return nil }
        let look = recipe.compactMapValues { $0.stringValue }
        guard !look.isEmpty else { return nil }
        func text(_ key: String) -> String? { role[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
        return AcceptedRoleDesign(role: roleId, option: option, look: look, place: text("place"), area: text("area"), use: text("use") ?? t.title)
    }

    /// Called after a Sweep is accepted: if it names a role, the chosen look becomes the role's draft (or a variant for one place
    /// or area) in the notebook, and `commit` writes it to git. A look that no longer passes (the system changed since the offer)
    /// is not saved, and a note on the ticket says so, so the owner is never left thinking it was. Never throws.
    func saveRoleDesign(of t: Ticket, commit: (_ notebook: String, _ message: String) throws -> Void) {
        do {
            guard let design = try acceptedRoleDesign(for: t) else { return }
            guard let notebook = try project(id: t.projectId)?.config?.repo(.notebook)?.localPath,
                  var system = try ComponentSystem.load(notebook: notebook) else {
                _ = try addNote(t.id, kind: .system, author: "hatch", body: "The accepted look for \(design.role) was not saved: the project has no design system in its notebook yet.")
                return
            }
            try system.acceptDesign(role: design.role, look: design.look, place: design.place, area: design.area, use: design.use, decision: t.displayNumber)
            try system.write(notebook: notebook)
            try commit(notebook, "Components: \(design.role) from \(t.displayNumber) (option \(design.option))")
            try record(t.id, actor: "hatch", kind: "role-design", payload: ["role": .string(design.role), "option": .string(design.option)])
        } catch {
            _ = try? addNote(t.id, kind: .system, author: "hatch", body: "The accepted look could not be saved as a role design: \(error) Set it on the Components page.")
            try? record(t.id, actor: "hatch", kind: "role-design-failed", payload: ["error": .string("\(error)")])
        }
    }
}
