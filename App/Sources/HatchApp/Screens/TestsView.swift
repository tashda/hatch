import SwiftUI
import HatchCore

/// Tests (section Y): the Xcode tests a project has, grouped by bundle and suite with each one's last result, the runs
/// agents and people made, and the run in progress. Everything is read from Hatch's own records (written by
/// `hatch check`), so opening the page costs nothing; "Read Test Sources" re-reads the repository's test files.
struct TestsView: View {
    @EnvironmentObject var state: AppState

    enum Section: Hashable { case runs, tests }
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", failing = "Failing", neverRun = "Never run"
        var id: String { rawValue }
    }

    @State private var section: Section = .runs
    @State private var runs: [TestRun] = []
    @State private var overview: [TestOverviewRow] = []
    @State private var selectedRun: Int?
    @State private var filter: Filter = .all
    @State private var agentFilter: String?
    @State private var search = ""
    @State private var scanning = false
    @State private var scanError: String?

    var body: some View {
        Group {
            if let project = state.hxProject { content(project) }
            else { ContentUnavailableView("No project yet", systemImage: "checkmark.diamond", description: Text("Set up a project to see its tests.")).floatingCard() }
        }
        .environment(\.hxCardOnGray, true)
        .autoReload(every: 3) { reload() }
        .searchable(text: $search, prompt: "Search tests")
    }

    // MARK: Data

    private func reload() {
        guard let project = state.hxProject else { return }
        try? state.store.closeAbandonedTestRuns { pid in kill(pid_t(pid), 0) == 0 }
        let r = (try? state.store.testRuns(projectId: project.id, limit: 100)) ?? []
        let o = (try? state.store.testOverview(projectId: project.id)) ?? []
        if r != runs { runs = r }
        if o != overview { overview = o }
        if selectedRun == nil || !runs.contains(where: { $0.id == selectedRun }) { selectedRun = runs.first?.id }
        if overview.isEmpty, !scanning, scanError == nil { scan(project) }
    }

    private func scan(_ project: Project) {
        guard let repo = ((try? state.store.repos(projectId: project.id)) ?? []).first(where: { $0.role == .app }), let path = repo.localPath else {
            scanError = "The app repository has no local path. Set it in Project settings."
            return
        }
        scanning = true; scanError = nil
        let store = state.store
        Task.detached {
            let found = TestScanner.scan(root: URL(fileURLWithPath: path))
            try? store.syncTestCatalog(projectId: project.id, repoId: repo.id, cases: found)
            await MainActor.run { scanning = false; if found.isEmpty { scanError = "No tests found under \(path)." }; reload() }
        }
    }

    private var running: [TestRun] { runs.filter { $0.state == .running } }
    private var agents: [String] { Array(Set(overview.compactMap(\.lastAgent))).sorted() }

    private var summary: String {
        let bundles = Set(overview.map(\.info.bundle)).count
        var parts = ["\(Format.count(overview.count, "test")) in \(Format.count(bundles, "bundle"))"]
        if let last = runs.first(where: \.finished) {
            parts.append("last run \(Format.ago(last.endedAt ?? last.startedAt))" + (last.agent.map { " by \($0)" } ?? ""))
        }
        return parts.joined(separator: ", ") + "."
    }

    // MARK: Body

    private func content(_ project: Project) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                HXHeader(title: "Tests", subtitle: summary)
                Spacer()
                if scanning { ProgressView().controlSize(.small) }
                Button("Read Test Sources", systemImage: "arrow.clockwise") { scan(project) }
                    .help("Read the repository's test files again")
                    .disabled(scanning)
            }
            .padding(16)
            .floatingCard()
            if let scanError { Text(scanError).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(running) { runningCard($0) }
                    HStack { HXDock(items: [.init(id: Section.runs, title: "Runs", count: runs.count),
                                            .init(id: Section.tests, title: "Tests", count: overview.count)], selection: $section); Spacer()
                        if section == .tests { testFilters } }
                    switch section {
                    case .runs: runsSection
                    case .tests: testsSection
                    }
                }
                .padding(3)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Running

    private func runningCard(_ run: TestRun) -> some View {
        let expected = (try? state.store.expectedTestTotal(for: run)) ?? nil
        return HXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Running tests").font(.headline)
                    Text(who(run)).foregroundStyle(.secondary)
                    Spacer()
                    Text("started \(Format.ago(run.startedAt))").font(.callout).foregroundStyle(.secondary)
                }
                if let expected, expected > 0 {
                    ProgressView(value: Double(min(run.done, expected)), total: Double(expected))
                    Text("\(run.done) of about \(expected) tests" + (run.failed > 0 ? ", \(run.failed) failed" : "")).font(.callout).foregroundStyle(run.failed > 0 ? .red : .secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                    Text("\(run.done) tests done" + (run.failed > 0 ? ", \(run.failed) failed" : "")).font(.callout).foregroundStyle(run.failed > 0 ? .red : .secondary)
                }
                if let name = run.runningName { Text(name).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                if let scope = run.scope { Text(scope).font(.caption).foregroundStyle(.tertiary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Runs

    private var runsSection: some View {
        Group {
            if runs.isEmpty {
                HXCard { HXEmpty(symbol: "checkmark.diamond", title: "No test runs yet",
                                 detail: "An agent's `hatch check` records its test run here, with who ran it and what failed.") }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    HXCard {
                        VStack(spacing: 0) {
                            ForEach(runs) { run in
                                Button { selectedRun = run.id } label: { runRow(run) }
                                    .buttonStyle(.plain)
                                    .background(selectedRun == run.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                if run.id != runs.last?.id { Divider() }
                            }
                        }
                    }
                    .frame(width: 360)
                    if let id = selectedRun, let run = runs.first(where: { $0.id == id }) { RunDetail(run: run) }
                }
            }
        }
    }

    private func runRow(_ run: TestRun) -> some View {
        HStack(alignment: .top, spacing: 8) {
            stateGlyph(run).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(who(run)).font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text(Format.relative(run.startedAt)).font(.caption).foregroundStyle(.secondary)
                }
                Text(counts(run)).font(.callout).foregroundStyle(run.failed > 0 ? Color.red : .secondary)
                if let scope = run.scope { Text(scope).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func who(_ run: TestRun) -> String {
        let agent = run.agent ?? "Manual run"
        guard let id = run.ticketId, let t = try? state.store.ticket(id: id) else { return agent }
        return "\(agent) on \(Format.number(t))"
    }

    private func counts(_ run: TestRun) -> String {
        switch run.state {
        case .running: "\(run.done) done, \(run.failed) failed"
        case .interrupted: "Interrupted after \(run.done) tests"
        default: "\(run.passed) passed, \(run.failed) failed" + (run.skipped > 0 ? ", \(run.skipped) skipped" : "") + (run.duration.map { String(format: " · %.0f s", $0) } ?? "")
        }
    }

    @ViewBuilder private func stateGlyph(_ run: TestRun) -> some View {
        switch run.state {
        case .running: ProgressView().controlSize(.mini)
        case .passed: Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .interrupted: Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
        }
    }

    // MARK: Tests

    private var testFilters: some View {
        HStack(spacing: 8) {
            Picker("Show", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            if !agents.isEmpty {
                Picker("Agent", selection: $agentFilter) {
                    Text("Any agent").tag(String?.none)
                    ForEach(agents, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
            }
        }
    }

    private var filtered: [TestOverviewRow] {
        overview.filter { row in
            switch filter {
            case .all: true
            case .failing: row.lastStatus == .failed
            case .neverRun: row.lastStatus == nil
            }
        }
        .filter { agentFilter == nil || $0.lastAgent == agentFilter }
        .filter { search.isEmpty || $0.info.id.localizedCaseInsensitiveContains(search) || ($0.lastMessage ?? "").localizedCaseInsensitiveContains(search) }
    }

    private var testsSection: some View {
        let rows = filtered
        let bundles = Dictionary(grouping: rows, by: \.info.bundle).keys.sorted()
        return VStack(alignment: .leading, spacing: 10) {
            if overview.isEmpty {
                HXCard { HXEmpty(symbol: "checkmark.diamond", title: scanning ? "Reading the test files" : "No tests found",
                                 detail: "Hatch reads the app repository's test files. Press Read Test Sources after adding a test target.") }
            } else if rows.isEmpty {
                HXCard { HXEmpty(symbol: "line.3.horizontal.decrease", title: "Nothing matches", detail: "Change the filter or the search.") }
            }
            ForEach(bundles, id: \.self) { bundle in
                BundleCard(bundle: bundle, rows: rows.filter { $0.info.bundle == bundle }, projectId: state.hxProject?.id ?? 0,
                           onOpenRun: { id in selectedRun = id; section = .runs }, onOpenTicket: { state.navigate(to: .ticket($0)) })
            }
        }
    }
}

// MARK: - Run detail

private struct RunDetail: View {
    @EnvironmentObject var state: AppState
    let run: TestRun
    @State private var all = false
    @State private var results: [TestResult] = []

    var body: some View {
        HXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Run \(run.id)").font(.headline)
                    Spacer()
                    if let id = run.ticketId, let t = try? state.store.ticket(id: id) {
                        Button(Format.number(t), systemImage: "ticket") { state.navigate(to: .ticket(id)) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Form {
                    LabeledContent("Who", value: run.agent ?? "Manual run")
                    LabeledContent("Result", value: run.state.rawValue.capitalized)
                    LabeledContent("Tests", value: "\(run.passed) passed, \(run.failed) failed, \(run.skipped) skipped")
                    LabeledContent("Started", value: Format.clock(run.startedAt))
                    if let d = run.duration { LabeledContent("Took", value: String(format: "%.0f s", d)) }
                    if let b = run.branch { LabeledContent("Branch", value: b + (run.commit.map { " @ \($0)" } ?? "")) }
                    if let s = run.scope { LabeledContent("Scope", value: s) }
                    if let c = run.command { LabeledContent("Command") { Text(c).font(.system(.callout, design: .monospaced)).textSelection(.enabled) } }
                }
                .formStyle(.columns)
                if let e = run.error { Text(e).foregroundStyle(.red).font(.callout) }
                Picker("Results", selection: $all) { Text("Problems").tag(false); Text("All tests").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                if results.isEmpty { Text(all ? "No results recorded." : "No failing tests.").foregroundStyle(.secondary).font(.callout) }
                ForEach(results) { r in resultRow(r) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
        .onChange(of: all) { load() }
        .onChange(of: run) { load() }
    }

    private func load() { results = (try? state.store.testResults(runId: run.id, problemsOnly: !all)) ?? [] }

    private func resultRow(_ r: TestResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                TestStatusGlyph(status: r.status)
                Text("\(r.suite).\(r.name)").font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let d = r.duration { Text(String(format: "%.2f s", d)).font(.caption).foregroundStyle(.tertiary) }
            }
            if let m = r.message, r.status != .passed {
                Text(m).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).padding(.leading, 22)
                if let f = r.file, let l = r.line { Text("\((f as NSString).lastPathComponent):\(l)").font(.caption).foregroundStyle(.tertiary).padding(.leading, 22) }
            }
        }
    }
}

// MARK: - Tests by bundle

private struct BundleCard: View {
    @EnvironmentObject var state: AppState
    let bundle: String
    let rows: [TestOverviewRow]
    let projectId: Int
    let onOpenRun: (Int) -> Void
    let onOpenTicket: (Int) -> Void
    @State private var expanded: String?

    private var suites: [String] { Array(Set(rows.map(\.info.suite))).sorted() }

    var body: some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(bundle).font(.headline)
                    Spacer()
                    Text(tally).font(.callout).foregroundStyle(rows.contains { $0.lastStatus == .failed } ? Color.red : .secondary)
                }
                ForEach(suites, id: \.self) { suite in
                    DisclosureGroup {
                        ForEach(rows.filter { $0.info.suite == suite }) { row in testRow(row) }
                    } label: {
                        HStack {
                            Text(suite).font(.body.weight(.medium))
                            Spacer()
                            Text(Format.count(rows.filter { $0.info.suite == suite }.count, "test")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hatchMark("BundleCard")
    }

    private var tally: String {
        let failed = rows.filter { $0.lastStatus == .failed }.count, never = rows.filter { $0.lastStatus == nil }.count
        var parts = [Format.count(rows.count, "test")]
        if failed > 0 { parts.append("\(failed) failing") }
        if never > 0 { parts.append("\(never) never run") }
        return parts.joined(separator: ", ")
    }

    private func testRow(_ row: TestOverviewRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded = expanded == row.id ? nil : row.id } label: {
                HStack(spacing: 6) {
                    TestStatusGlyph(status: row.lastStatus)
                    Text(row.info.name).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    if row.info.kind == "swift-testing" { Text("Swift Testing").font(.caption2).foregroundStyle(.tertiary) }
                    Spacer()
                    if let at = row.lastAt {
                        Text((row.lastAgent.map { "\($0), " } ?? "") + Format.ago(at)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("never run").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded == row.id { history(row) }
        }
        .padding(.leading, 4)
    }

    private func history(_ row: TestOverviewRow) -> some View {
        let past = (try? state.store.testHistory(projectId: projectId, bundle: row.info.bundle, suite: row.info.suite, name: row.info.name, limit: 8)) ?? []
        return VStack(alignment: .leading, spacing: 4) {
            if let f = row.info.file { Text("\(f)" + (row.info.line.map { ":\($0)" } ?? "")).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled) }
            if past.isEmpty { Text("No run has included this test yet.").font(.callout).foregroundStyle(.secondary) }
            ForEach(past, id: \.result.id) { item in
                HStack(spacing: 6) {
                    TestStatusGlyph(status: item.result.status)
                    Button("Run \(item.run.id)") { onOpenRun(item.run.id) }.buttonStyle(.link)
                    Text(item.run.agent ?? "Manual run").foregroundStyle(.secondary)
                    if let t = item.run.ticketId { Button("ticket") { onOpenTicket(t) }.buttonStyle(.link) }
                    Spacer()
                    Text(Format.ago(item.run.startedAt)).font(.caption).foregroundStyle(.tertiary)
                }
                .font(.callout)
                if let m = item.result.message, item.result.status == .failed { Text(m).font(.caption).foregroundStyle(.secondary).padding(.leading, 22).textSelection(.enabled) }
            }
        }
        .padding(.leading, 22).padding(.vertical, 4)
    }
}

/// Failed is the one coloured state (a real problem, LK5); the rest are neutral glyphs.
struct TestStatusGlyph: View {
    let status: TestStatus?

    var body: some View {
        Group {
            switch status {
            case .passed?: Image(systemName: "checkmark.circle").foregroundStyle(.secondary).frame(width: 16)
            case .failed?: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 16)
            case .skipped?: Image(systemName: "minus.circle").foregroundStyle(.secondary).frame(width: 16)
            case .running?: ProgressView().controlSize(.mini).frame(width: 16)
            case nil: Image(systemName: "circle.dashed").foregroundStyle(.tertiary).frame(width: 16)
            }
        }
        .hatchMark("TestStatusGlyph")
    }
}
