import Foundation

/// The clean-up rules in Settings › Storage: when workspaces of finished tickets go, and how long agent logs stay.
/// A limit of nil means never.
public struct CleanupRules: Equatable, Sendable {
    public static let workspacesKey = "cleanup_workspaces_days"
    public static let logsKey = "cleanup_logs_days"
    public static let workspaceChoices = [1, 3, 7, 30]
    public static let logChoices = [7, 30, 90]
    public static let defaultWorkspaceDays = 7
    public static let defaultLogDays = 30

    public var workspaceDays: Int?
    public var logDays: Int?

    public init(workspaceDays: Int? = CleanupRules.defaultWorkspaceDays, logDays: Int? = CleanupRules.defaultLogDays) {
        self.workspaceDays = workspaceDays; self.logDays = logDays
    }

    /// Settings store the days as a number, "0" for never; a missing setting is the default.
    public init(workspaces: String?, logs: String?) {
        func days(_ s: String?, _ fallback: Int) -> Int? {
            guard let s, let n = Int(s) else { return fallback }
            return n > 0 ? n : nil
        }
        self.init(workspaceDays: days(workspaces, Self.defaultWorkspaceDays), logDays: days(logs, Self.defaultLogDays))
    }

    public static func load(from store: HatchStore) -> CleanupRules {
        CleanupRules(workspaces: (try? store.setting(workspacesKey)) ?? nil, logs: (try? store.setting(logsKey)) ?? nil)
    }
}

extension HatchStore {
    /// Active workspaces of tickets that are Done or Dropped and have not changed for `days` days. Workspaces of tickets
    /// in `excluding` (an agent is running on them) are never chosen.
    public func finishedWorkspaces(olderThanDays days: Int, excluding: Set<Int> = []) throws -> [Workspace] {
        let cutoff = now().addingTimeInterval(-Double(days) * 86_400)
        var finished: [Int: Bool] = [:]
        return try workspaces().filter { ws in
            guard ws.state == "active", !excluding.contains(ws.ticketId) else { return false }
            if let known = finished[ws.ticketId] { return known }
            let t = try ticket(id: ws.ticketId)
            let old = t.map { $0.status.isTerminal && $0.updatedAt <= cutoff } ?? false
            finished[ws.ticketId] = old
            return old
        }
    }
}

/// Sizes and old files on disk, for Settings › Storage and the daily clean-up.
public enum StorageFiles {
    /// Bytes used by a file or everything under a folder. Symbolic links are not followed; a missing path is 0.
    public static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        func bytes(_ u: URL) -> Int64 {
            guard let v = try? u.resourceValues(forKeys: keys), v.isRegularFile == true else { return 0 }
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard isDir.boolValue else { return bytes(url) }
        var total: Int64 = 0
        let walker = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let u = walker?.nextObject() as? URL { total += bytes(u) }
        return total
    }

    /// Files directly in `folder` last changed at least `days` days before `now`, oldest first. Folders are skipped.
    public static func files(in folder: URL, olderThanDays days: Int, now: Date = Date()) -> [URL] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return items.compactMap { url -> (URL, Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let changed = v.contentModificationDate, changed <= cutoff else { return nil }
            return (url, changed)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }
}
