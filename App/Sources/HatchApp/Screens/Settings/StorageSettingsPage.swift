import SwiftUI
import AppKit
import HatchCore
import HatchGit

// Settings, Storage (was Local data; design-review/settings-pages.html). What takes space on this Mac, the clean-up
// rules that keep workspaces and logs from piling up, and what is safe elsewhere. Sizes are measured off the main thread
// each time the page appears; the same clean-up and the database backup also run once a day in the background.

struct StorageSettingsPage: View {
    @EnvironmentObject var state: AppState
    @State private var report: StorageReport?
    @State private var workspaceDays = CleanupRules.defaultWorkspaceDays
    @State private var logDays = CleanupRules.defaultLogDays
    @State private var backup = BackupPolicy.default
    @State private var loaded = false
    @State private var planning = false
    @State private var cleaning = false
    @State private var plan: CleanupPlan?
    @State private var confirming = false
    /// What the last Clean Up Now did, or why there was nothing to do.
    @State private var outcome: (text: String, problem: Bool)?

    var body: some View {
        Form {
            onThisMacSection
            cleanUpSection
            safetySection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear(perform: load)
        .task { await measure() }
        .confirmationDialog(plan.map(confirmTitle) ?? "", isPresented: $confirming, titleVisibility: .visible, presenting: plan) { plan in
            Button("Remove", role: .destructive) { clean(plan) }
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text(confirmMessage(plan))
        }
    }

    // MARK: On this Mac

    private var onThisMacSection: some View {
        Section {
            // A long path is shortened in the middle rather than pushed under the label.
            HStack {
                Text("Hatch folder")
                Spacer(minLength: 16)
                Text(hxAbbreviated(state.paths.root.path)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(state.paths.root.path).textSelection(.enabled)
            }
            LabeledContent("Database") {
                value(report.map { "\(bytes($0.databaseBytes)) · \($0.tickets.formatted()) \($0.tickets == 1 ? "ticket" : "tickets")" })
            }
            LabeledContent("Agent workspaces") {
                value(report.map { "\($0.workspaces.formatted()) · \(bytes($0.workspaceBytes))" })
            }
            LabeledContent("Agent logs") { value(report.map { bytes($0.logBytes) }) }
            if let attachments = report?.attachmentsBytes {
                LabeledContent("Attachments cache") { value(bytes(attachments)) }
            }
        } header: {
            HStack {
                Text("On this Mac")
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([state.paths.root]) }
                    .buttonStyle(.link)
            }
        }
    }

    // MARK: Clean up

    private var cleanUpSection: some View {
        Section {
            Picker("Remove workspaces of finished tickets", selection: $workspaceDays) {
                ForEach(CleanupRules.workspaceChoices, id: \.self) { n in
                    Text("After \(n) \(n == 1 ? "day" : "days")").tag(n)
                }
                Divider()
                Text("Never").tag(0)
            }
            .onChange(of: workspaceDays) { _, n in save(CleanupRules.workspacesKey, n) }
            Picker("Keep agent logs", selection: $logDays) {
                ForEach(CleanupRules.logChoices, id: \.self) { n in Text("\(n) days").tag(n) }
                Divider()
                Text("Forever").tag(0)
            }
            .onChange(of: logDays) { _, n in save(CleanupRules.logsKey, n) }
        } header: {
            HStack {
                Text("Clean up")
                Spacer()
                if planning || cleaning { ProgressView().controlSize(.small) }
                Button("Clean Up Now…", action: startCleanUp)
                    .buttonStyle(.link)
                    .disabled(planning || cleaning || Snapshots.demoMode)
            }
        } footer: {
            if let outcome {
                Text(outcome.text).foregroundStyle(outcome.problem ? Theme.critical : .secondary)
            } else {
                Text("Finished means Done or Dropped; a workspace with uncommitted changes is always kept.")
            }
        }
    }

    // MARK: Safety

    private var safetySection: some View {
        Section {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Everything that matters is in git and on GitHub")
                    Text("Tickets in GitHub issues, decisions and the Spec in each notebook")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Theme.finished)
                    .accessibilityLabel("Safe")
            }
            .accessibilityElement(children: .combine)
            Picker("Back up the database", selection: $backup) {
                Text("Daily, keep 7").tag(BackupPolicy.daily)
                Text("Weekly, keep 4").tag(BackupPolicy.weekly)
                Divider()
                Text("Off").tag(BackupPolicy.off)
            }
            .onChange(of: backup) { _, policy in
                guard loaded else { return }
                state.hxSaveSetting(BackupPolicy.settingKey, policy.rawValue)
                backUpIfDue(policy)
            }
        } header: {
            Text("Safety")
        } footer: {
            Text(backupFooter)
        }
    }

    private var backupFooter: String {
        let place = "Copies go to the backups folder in the Hatch folder"
        guard let latest = report?.latestBackup else { return place + "." }
        return place + "; the newest is from \(latest.formatted(date: .abbreviated, time: .omitted))."
    }

    // MARK: Values

    @ViewBuilder private func value(_ text: String?) -> some View {
        if let text { Text(text).foregroundStyle(.secondary) } else { ProgressView().controlSize(.small) }
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    private func confirmTitle(_ plan: CleanupPlan) -> String { "Remove \(bytes(plan.bytes)) from this Mac?" }

    /// Exactly what goes: how many workspaces and log files, and their size.
    private func confirmMessage(_ plan: CleanupPlan) -> String {
        var parts: [String] = []
        if !plan.workspaces.isEmpty {
            parts.append("\(count(plan.workspaces.count, "workspace", "workspaces")) of finished tickets (\(bytes(plan.workspaceBytes)))")
        }
        if !plan.logs.isEmpty {
            parts.append("\(count(plan.logs.count, "agent log file", "agent log files")) (\(bytes(plan.logBytes)))")
        }
        let kept = plan.workspaces.isEmpty ? "" : " A workspace with uncommitted changes is kept."
        return "Hatch removes " + parts.joined(separator: " and ") + "." + kept
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    // MARK: Loading and work

    private func load() {
        guard !loaded else { return }
        let rules = CleanupRules(workspaces: state.hxSetting(CleanupRules.workspacesKey), logs: state.hxSetting(CleanupRules.logsKey))
        workspaceDays = rules.workspaceDays ?? 0
        logDays = rules.logDays ?? 0
        backup = BackupPolicy(setting: state.hxSetting(BackupPolicy.settingKey))
        // The pickers' onChange runs after this pass; saving starts once these values are in place.
        DispatchQueue.main.async { loaded = true }
    }

    private func save(_ key: String, _ days: Int) {
        guard loaded else { return }
        state.hxSaveSetting(key, String(days))
        outcome = nil
    }

    private func measure() async {
        let store = state.store, paths = state.paths
        report = await Task.detached(priority: .utility) { StorageReport.measure(store: store, paths: paths) }.value
    }

    /// Switching backups on makes the first copy now rather than at the next daily run.
    private func backUpIfDue(_ policy: BackupPolicy) {
        guard !Snapshots.demoMode else { return }
        let store = state.store, folder = state.paths.backups
        Task {
            let made = await Task.detached(priority: .utility) { (try? store.backUpIfDue(policy, into: folder)) ?? nil }.value
            if made != nil { await measure() }
        }
    }

    private var rules: CleanupRules {
        CleanupRules(workspaceDays: workspaceDays > 0 ? workspaceDays : nil, logDays: logDays > 0 ? logDays : nil)
    }

    private func startCleanUp() {
        guard !planning, !cleaning else { return }
        planning = true
        outcome = nil
        let store = state.store, logs = state.paths.runs, rules = rules
        let running = Set(state.agentRuns.map(\.ticketId))
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                StorageCleanup.plan(store: store, rules: rules, logsFolder: logs, excludingTickets: running)
            }.value
            planning = false
            if plan.isEmpty {
                outcome = ("Nothing to clean up with these rules.", false)
            } else {
                self.plan = plan
                confirming = true
            }
        }
    }

    private func clean(_ plan: CleanupPlan) {
        cleaning = true
        let store = state.store
        Task {
            let result = await Task.detached(priority: .userInitiated) { StorageCleanup.run(plan, store: store) }.value
            cleaning = false
            self.plan = nil
            outcome = Self.describe(result)
            state.refresh()
            await measure()
        }
    }

    /// One plain sentence about a clean-up, naming the workspaces it kept.
    static func describe(_ r: CleanupResult) -> (text: String, problem: Bool) {
        var parts: [String] = []
        if r.removedWorkspaces > 0 { parts.append("\(r.removedWorkspaces) \(r.removedWorkspaces == 1 ? "workspace" : "workspaces")") }
        if r.removedLogs > 0 { parts.append("\(r.removedLogs) log \(r.removedLogs == 1 ? "file" : "files")") }
        var text = parts.isEmpty ? "Nothing was removed." :
            "Removed \(parts.joined(separator: " and ")), \(ByteCountFormatter.string(fromByteCount: r.freedBytes, countStyle: .file)) freed."
        if !r.keptDirty.isEmpty {
            let names = r.keptDirty.map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: ", ")
            text += " Kept \(names): uncommitted changes."
        }
        if let first = r.problems.first { text += " Could not remove \(first)" }
        return (text, !r.problems.isEmpty)
    }
}

/// What Hatch keeps on this Mac, measured for Settings › Storage.
struct StorageReport: Sendable {
    var databaseBytes: Int64
    var tickets: Int
    var workspaces: Int
    var workspaceBytes: Int64
    var logBytes: Int64
    /// Nil when there is no attachments folder.
    var attachmentsBytes: Int64?
    var latestBackup: Date?

    static func measure(store: HatchStore, paths: AppPaths) -> StorageReport {
        let db = paths.database.path
        let databaseBytes = ["", "-wal", "-shm"].reduce(Int64(0)) { $0 + StorageFiles.size(of: URL(fileURLWithPath: db + $1)) }
        let all = (try? store.workspaces(includeRemoved: true)) ?? []
        let active = all.filter { $0.state == "active" }
        let attachments = FileManager.default.fileExists(atPath: paths.attachments.path) ? StorageFiles.size(of: paths.attachments) : nil
        return StorageReport(databaseBytes: databaseBytes, tickets: (try? store.ticketCount()) ?? 0, workspaces: active.count,
                             workspaceBytes: workspaceFolders(all, paths: paths).reduce(0) { $0 + StorageFiles.size(of: $1) },
                             logBytes: StorageFiles.size(of: paths.runs), attachmentsBytes: attachments,
                             latestBackup: DatabaseBackups.latest(in: paths.backups))
    }

    /// The folders that hold workspaces: each repository's `.hatch-workspaces` (so leftovers count too) and Hatch's own
    /// workspaces folder. A workspace somewhere else counts on its own, never its parent.
    static func workspaceFolders(_ workspaces: [Workspace], paths: AppPaths) -> [URL] {
        var folders: [String: URL] = [:]
        func add(_ url: URL) {
            let key = url.standardizedFileURL.path
            if folders[key] == nil, FileManager.default.fileExists(atPath: key) { folders[key] = url }
        }
        add(paths.workspaces)
        for ws in workspaces {
            let url = URL(fileURLWithPath: ws.path)
            let parent = url.deletingLastPathComponent()
            // <root>/<ticket>/<repo> now; <root>/<repo>-<ticket> before.
            let root = parent.deletingLastPathComponent()
            if root.lastPathComponent == ".hatch-workspaces" { add(root) }
            else if parent.lastPathComponent == ".hatch-workspaces" { add(parent) } else if ws.state == "active" { add(url) }
        }
        // A workspace inside a folder already counted is not counted twice.
        let keys = folders.keys.sorted()
        return keys.filter { k in !keys.contains { $0 != k && k.hasPrefix($0 + "/") } }.compactMap { folders[$0] }
    }
}

// MARK: Daily maintenance

extension AppState {
    static let storageMaintainedSetting = "storage_maintained_at"

    /// Once a day, off the main thread: the database backup and the clean-up from Settings › Storage. Runs at launch and
    /// on the sync timer. Never in snapshots or the demo.
    func maintainStorageIfDue() {
        guard Snapshots.folder == nil, !Snapshots.demoMode, !maintainingStorage else { return }
        if storageMaintainedAt == nil, let stamp = hxSetting(Self.storageMaintainedSetting).flatMap(Double.init) {
            storageMaintainedAt = Date(timeIntervalSince1970: stamp)
        }
        if let last = storageMaintainedAt, Date().timeIntervalSince(last) < 86_400 { return }
        maintainingStorage = true
        let store = store, paths = paths, running = Set(agentRuns.map(\.ticketId))
        Task {
            await Task.detached(priority: .background) { Self.maintainStorage(store: store, paths: paths, running: running) }.value
            let now = Date()
            maintainingStorage = false
            storageMaintainedAt = now
            try? store.setSetting(Self.storageMaintainedSetting, String(now.timeIntervalSince1970))
        }
    }

    nonisolated static func maintainStorage(store: HatchStore, paths: AppPaths, running: Set<Int>) {
        let policy = BackupPolicy(setting: (try? store.setting(BackupPolicy.settingKey)) ?? nil)
        do { try store.backUpIfDue(policy, into: paths.backups) } catch { NSLog("Hatch: database backup failed: \(error)") }
        let plan = StorageCleanup.plan(store: store, rules: CleanupRules.load(from: store), logsFolder: paths.runs,
                                       excludingTickets: running, measure: false)
        guard !plan.isEmpty else { return }
        let result = StorageCleanup.run(plan, store: store)
        for problem in result.problems { NSLog("Hatch: clean-up: \(problem)") }
    }
}
