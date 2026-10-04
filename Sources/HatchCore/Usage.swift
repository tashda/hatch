import Foundation

/// Tokens used, summed from run records for the Usage page and the daily limits. Tokens only: plans have no
/// per-token price, and the owner chose tokens over money (design-review/reports.html).
public struct UsageSummary: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public var day: Date
        public var key: String
        public var tokens: Int
        public var id: String { "\(day.timeIntervalSince1970)-\(key)" }
    }

    /// Tokens per day and per `key` (provider, or model when one provider is chosen), oldest first. Days without runs
    /// are left out; the chart draws them empty.
    public var days: [Day]
    /// Tokens per task (an `AgentRole` raw value, or "other"), largest first.
    public var byTask: [(key: String, tokens: Int)]
    /// Tokens per model, with its provider, largest first.
    public var byModel: [(model: String, provider: String, tokens: Int)]
    public var total: Int
    public var cache: Int

    public static func == (a: Self, b: Self) -> Bool {
        a.days == b.days && a.total == b.total && a.cache == b.cache
            && a.byTask.map(\.key) == b.byTask.map(\.key) && a.byModel.map(\.model) == b.byModel.map(\.model)
    }

    /// The name shown for runs recorded before providers were.
    public static let unknownProvider = "Not recorded"

    /// Sums `runs`, only those of `provider` when given. Days are split on `calendar`.
    public init(runs: [RunRecord], provider: String? = nil, calendar: Calendar = .current) {
        let runs = provider.map { p in runs.filter { ($0.provider ?? Self.unknownProvider) == p } } ?? runs
        var perDay: [Date: [String: Int]] = [:]
        var task: [String: Int] = [:]
        var model: [String: (provider: String, tokens: Int)] = [:]
        for r in runs {
            let p = r.provider ?? Self.unknownProvider
            let key = provider == nil ? p : (r.model ?? "Default model")
            perDay[calendar.startOfDay(for: r.startedAt), default: [:]][key, default: 0] += r.tokens
            task[Self.task(of: r), default: 0] += r.tokens
            let m = r.model ?? "Default model"
            model[m] = (p, (model[m]?.tokens ?? 0) + r.tokens)
        }
        days = perDay.keys.sorted().flatMap { d in perDay[d]!.sorted { $0.key < $1.key }.map { Day(day: d, key: $0.key, tokens: $0.value) } }
        byTask = task.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        byModel = model.sorted { $0.value.tokens > $1.value.tokens }.map { ($0.key, $0.value.provider, $0.value.tokens) }
        total = runs.reduce(0) { $0 + $1.tokens }
        cache = runs.reduce(0) { $0 + $1.cacheTokens }
    }

    /// The task a run did. Runs recorded before tasks were are told apart by their agent name.
    public static func task(of r: RunRecord) -> String {
        if let role = r.role { return role }
        switch r.agent {
        case "ask": return "ask"
        case "Iris": return "iris"
        default: return "other"
        }
    }
}

/// The daily token limits on Settings › Usage. Zero means off. Hatch only warns or stops starting new work; running
/// agents finish, and plans keep their own limits.
public struct UsageLimits: Equatable, Sendable {
    public static let warnSetting = "usage_warn_daily"
    public static let pauseSetting = "usage_pause_daily"

    public var warnAbove: Int
    public var pauseAbove: Int

    public enum Level: Equatable, Sendable { case fine, warn, pause }

    public init(warnAbove: Int = 0, pauseAbove: Int = 0) { self.warnAbove = warnAbove; self.pauseAbove = pauseAbove }

    public static func load(from store: HatchStore) -> UsageLimits {
        UsageLimits(warnAbove: Int((try? store.setting(warnSetting)) ?? nil ?? "") ?? 0,
                    pauseAbove: Int((try? store.setting(pauseSetting)) ?? nil ?? "") ?? 0)
    }

    public func level(today tokens: Int) -> Level {
        if pauseAbove > 0 && tokens >= pauseAbove { return .pause }
        if warnAbove > 0 && tokens >= warnAbove { return .warn }
        return .fine
    }
}
