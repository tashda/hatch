import Foundation

/// How often Hatch copies its database, and how many copies it keeps (setting `db_backup`). Everything that matters is
/// also in git and on GitHub; the copy saves rebuilding local state (runs, checks, settings) after a broken disk or a bad
/// migration.
public enum BackupPolicy: String, CaseIterable, Sendable {
    case daily, weekly, off

    public static let settingKey = "db_backup"
    public static let `default`: BackupPolicy = .daily

    /// Copies kept: a week of daily copies, or a month of weekly ones.
    public var keep: Int {
        switch self {
        case .daily: 7
        case .weekly: 4
        case .off: 0
        }
    }

    /// Days between copies.
    public var interval: Int? {
        switch self {
        case .daily: 1
        case .weekly: 7
        case .off: nil
        }
    }

    public init(setting: String?) { self = setting.flatMap(BackupPolicy.init(rawValue:)) ?? .default }

    /// Whether a new copy is due: none yet, or the newest is at least `interval` calendar days old.
    public func isDue(latest: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let interval else { return false }
        guard let latest else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: latest), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= interval
    }
}

/// The copies in `<home>/backups`, named `hatch-YYYY-MM-DD.sqlite` so they sort by date.
public enum DatabaseBackups {
    static let prefix = "hatch-"
    static let suffix = ".sqlite"

    static func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        prefix + formatter(calendar).string(from: date) + suffix
    }

    /// The day a backup file is from, or nil when the name is not one of Hatch's backups.
    public static func date(ofFile name: String, calendar: Calendar = .current) -> Date? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let stamp = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard stamp.count == 10 else { return nil }
        return formatter(calendar).date(from: stamp)
    }

    /// Hatch's backups in a folder, newest first. Other files are never listed, so pruning cannot touch them.
    public static func list(in folder: URL, calendar: Calendar = .current) -> [(url: URL, date: Date)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in date(ofFile: name, calendar: calendar).map { (folder.appendingPathComponent(name), $0) } }
            .sorted { $0.date > $1.date }
    }

    public static func latest(in folder: URL, calendar: Calendar = .current) -> Date? { list(in: folder, calendar: calendar).first?.date }

    /// Deletes all but the newest `keep` backups. Returns what was deleted.
    @discardableResult
    public static func prune(in folder: URL, keep: Int, calendar: Calendar = .current) throws -> [URL] {
        let old = list(in: folder, calendar: calendar).dropFirst(max(keep, 0)).map(\.url)
        for url in old { try FileManager.default.removeItem(at: url) }
        return old
    }
}

extension HatchStore {
    /// Writes a consistent copy of the database to `<folder>/hatch-YYYY-MM-DD.sqlite` with `VACUUM INTO`, which is safe
    /// while the app is using the database. A copy from the same day is replaced. Returns the copy's location.
    @discardableResult
    public func backUp(into folder: URL, calendar: Calendar = .current) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(DatabaseBackups.fileName(for: now(), calendar: calendar))
        // VACUUM INTO refuses an existing file, so write next to it and swap, never leaving a half copy under the real name.
        let partial = folder.appendingPathComponent(target.lastPathComponent + ".partial")
        try? fm.removeItem(at: partial)
        do {
            try db.execute("VACUUM INTO ?", [.text(partial.path)])
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: partial)
        } else {
            try fm.moveItem(at: partial, to: target)
        }
        return target
    }

    /// Makes a copy when the policy says one is due, then keeps only the newest copies. Returns the new copy, if any.
    @discardableResult
    public func backUpIfDue(_ policy: BackupPolicy, into folder: URL, calendar: Calendar = .current) throws -> URL? {
        guard policy.isDue(latest: DatabaseBackups.latest(in: folder, calendar: calendar), now: now(), calendar: calendar) else { return nil }
        let url = try backUp(into: folder, calendar: calendar)
        try DatabaseBackups.prune(in: folder, keep: policy.keep, calendar: calendar)
        return url
    }

    /// Number of tickets in every project, for Settings › Storage.
    public func ticketCount() throws -> Int { try db.scalarInt("SELECT COUNT(*) FROM ticket") }
}
