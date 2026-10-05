import Foundation
import HatchCore
import HatchGit

/// When an agent starts building an accepted design system change (decision CP3), Hatch applies the role's draft:
/// the next baseline version, written and committed in the notebook. The Proposal is then the code and migration work.
/// Both ways of taking a ticket call this (the launcher and `hatch take`), so the agent always builds the agreed look.
public enum ComponentChangeBuild {
    /// Returns a line for the agent when a draft was applied, nil otherwise. Never throws: a notebook that cannot be
    /// written leaves the draft in place, and the brief still names the chosen look.
    @discardableResult
    public static func applyOnTake(store: HatchStore, ticket t: Ticket, kind: AgentTaskKind) -> String? {
        guard kind == .build, t.type == .proposal, let roleId = ComponentsSetup.changedRole(inBody: t.body),
              let project = try? store.project(id: t.projectId), let notebook = project.config?.repo(.notebook)?.localPath,
              var system = (try? ComponentSystem.load(notebook: notebook)) ?? nil,
              (try? system.applyChange(ticketBody: t.body, decision: t.displayNumber)) == true else { return nil }
        do {
            try system.write(notebook: notebook)
            _ = try NotebookWriter.commit("Components: \(roleId) takes its new look (\(t.displayNumber)), baseline v\(system.version)", in: notebook)
        } catch { return nil }
        return "Hatch applied the new look of \(roleId): baseline v\(system.version) of the design system."
    }
}
