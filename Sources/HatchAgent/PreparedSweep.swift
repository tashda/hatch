import Foundation
import HatchCore

/// A Sweep that Hatch prepared itself (no agent, no model call): the items are what a code check found, the options come from
/// a manifest Hatch built, and it arrives already waiting for the owner's call, under a parent Goal if there is one. The
/// Components setup uses it for one Sweep per role whose looks compete (decision SW11).
public struct PreparedSweep: Sendable {
    public var title: String
    /// What the owner would have asked, in plain words.
    public var body: String
    public var area: String?
    /// The Goal this Sweep belongs under.
    public var parentId: Int?
    public var manifest: ProposalManifest
    /// Why Hatch made it, one short paragraph, shown as the first note.
    public var note: String

    public init(title: String, body: String, area: String? = nil, parentId: Int? = nil, manifest: ProposalManifest, note: String = "") {
        self.title = title; self.body = body; self.area = area; self.parentId = parentId; self.manifest = manifest; self.note = note
    }
}

public enum PreparedSweepResult: Equatable, Sendable {
    case created(Ticket)
    /// The gate found errors, so nothing was made.
    case rejected([GateIssue])

    public var ticket: Ticket? { if case .created(let t) = self { return t }; return nil }
}

public struct PreparedSweepService {
    public let store: HatchStore
    public var by: String

    public init(store: HatchStore, by: String = "hatch") { self.store = store; self.by = by }

    /// Runs the same gate as a hand-in (the items, the kinds, the specimens) and the code check when `appRoot` is given, then
    /// makes the ticket and puts it at Your call. A Sweep that fails the gate is never made, so the owner never meets a half-finished one.
    public func create(projectId: Int, _ sweep: PreparedSweep, appRoot: String?, system: ComponentSystem? = nil) throws -> PreparedSweepResult {
        var issues = ProposalValidator.validate(sweep.manifest, isSweep: true)
        if let appRoot { issues += SweepItemCheck.problems(sweep.manifest.items, appRoot: appRoot) }
        if let role = sweep.manifest.role, let system { issues += RoleDesignCheck.problems(role, system: system) }
        if issues.hasErrors { return .rejected(issues) }
        let json = try sweep.manifest.jsonString()
        let ticket = try store.db.transaction { () -> Ticket in
            let t = try store.createTicket(projectId: projectId, type: .sweep, title: sweep.title, body: sweep.body, area: sweep.area,
                                           parentId: sweep.parentId, status: .draft, actor: .hatch)
            try store.file(t.id, Filing(path: .sweep), by: by)
            try store.saveProposal(ticketId: t.id, manifestJSON: json)
            try store.saveSweepItems(ticketId: t.id, items: sweep.manifest.items.map(\.input))
            if !sweep.note.isEmpty { _ = try store.addNote(t.id, kind: .system, author: by, body: sweep.note) }
            try store.move(t.id, to: .checking, actor: .hatch, reason: "prepared by Hatch")
            try store.move(t.id, to: .ready, actor: .hatch, reason: "prepared by Hatch")
            try store.move(t.id, to: .preparing, actor: .hatch, reason: "prepared by Hatch")
            try store.record(t.id, actor: by, kind: "offer", payload: ["revision": .int(sweep.manifest.revision), "warnings": .int(issues.count), "prepared": .bool(true)])
            return try store.move(t.id, to: .yourCall, actor: .hatch, reason: "prepared by Hatch")
        }
        return .created(ticket)
    }
}
