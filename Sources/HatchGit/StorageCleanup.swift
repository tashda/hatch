import Foundation
import HatchCore

/// What a clean-up would remove, worked out before anything is touched so the owner can be told exactly.
public struct CleanupPlan: Sendable {
    public var workspaces: [Workspace] = []
    public var workspaceBytes: Int64 = 0
    public var logs: [URL] = []
    public var logBytes: Int64 = 0

    public var isEmpty: Bool { workspaces.isEmpty && logs.isEmpty }
    public var bytes: Int64 { workspaceBytes + logBytes }
}

/// What a clean-up did. Workspaces with uncommitted changes are kept and listed, never forced.
public struct CleanupResult: Sendable {
    public var removedWorkspaces = 0
    public var removedLogs = 0
    public var freedBytes: Int64 = 0
    public var keptDirty: [Workspace] = []
    public var problems: [String] = []
}

/// The clean-up behind Settings › Storage: workspaces of finished tickets through `WorkspaceManager.remove` (the ticket
/// branch is kept), and old agent logs in `<home>/runs`. Used by Clean Up Now and by the daily background run.
public enum StorageCleanup {
    public static func plan(store: HatchStore, rules: CleanupRules, logsFolder: URL, excludingTickets: Set<Int> = [],
                            measure: Bool = true) -> CleanupPlan {
        var plan = CleanupPlan()
        if let days = rules.workspaceDays {
            plan.workspaces = (try? store.finishedWorkspaces(olderThanDays: days, excluding: excludingTickets)) ?? []
            if measure { plan.workspaceBytes = plan.workspaces.reduce(0) { $0 + StorageFiles.size(of: URL(fileURLWithPath: $1.path)) } }
        }
        if let days = rules.logDays {
            plan.logs = StorageFiles.files(in: logsFolder, olderThanDays: days, now: store.now())
            if measure { plan.logBytes = plan.logs.reduce(0) { $0 + StorageFiles.size(of: $1) } }
        }
        return plan
    }

    public static func run(_ plan: CleanupPlan, store: HatchStore, git: GitRunner = ProcessGit()) -> CleanupResult {
        var result = CleanupResult()
        let manager = WorkspaceManager(store: store, git: git)
        let fm = FileManager.default
        for ws in plan.workspaces {
            do {
                if fm.fileExists(atPath: ws.path) {
                    // A dirty worktree may hold work nobody committed: keep it and say so.
                    guard try manager.status(ws).isClean else { result.keptDirty.append(ws); continue }
                }
                let bytes = StorageFiles.size(of: URL(fileURLWithPath: ws.path))
                try manager.remove(ws)
                result.removedWorkspaces += 1
                result.freedBytes += bytes
            } catch {
                result.problems.append("\(ws.path): \(error)")
            }
        }
        for url in plan.logs {
            let bytes = StorageFiles.size(of: url)
            do {
                try fm.removeItem(at: url)
                result.removedLogs += 1
                result.freedBytes += bytes
            } catch {
                result.problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }
}
