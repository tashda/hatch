import SwiftUI
import Charts
import HatchCore
import HatchAgent

/// Settings, Usage (design-review/settings-pages.html): tokens per day for 14 days, this week by task and by model,
/// and the daily limits. Tokens only; one provider can be chosen to see its models.
struct UsageSettingsPage: View {
    @EnvironmentObject var state: AppState
    @State private var provider = ""
    @State private var runs: [RunRecord] = []
    @State private var limits = UsageLimits()
    @State private var runBudget = AgentLauncher.defaultTokenBudget

    private var chosen: String? { provider.isEmpty ? nil : provider }
    private var fortnight: UsageSummary { UsageSummary(runs: runs, provider: chosen) }
    private var week: UsageSummary {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return UsageSummary(runs: runs.filter { $0.startedAt >= start }, provider: chosen)
    }
    private var today: Int {
        UsageSummary(runs: runs.filter { Calendar.current.isDateInToday($0.startedAt) }).total
    }
    /// Providers that have runs, and those set up in Agents, so a new provider can be chosen before its first run.
    private var providers: [String] {
        let recorded = Set(runs.map { $0.provider ?? UsageSummary.unknownProvider })
        let configured = AgentSettings.load(from: state.store, detect: false).providers.filter(\.enabled).map(\.name)
        return Array(recorded.union(configured)).sorted()
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $provider) {
                    Text("All providers").tag("")
                    ForEach(providers, id: \.self) { Text($0).tag($0) }
                }
                chart
                LabeledContent("Today", value: "\(hxTokens(today)) tokens")
                LabeledContent("Last 14 days", value: "\(hxTokens(fortnight.total)) tokens")
            } header: {
                Text("Tokens per day")
            } footer: {
                if fortnight.cache > 0 {
                    Text("Another \(hxTokens(fortnight.cache)) were read from the prompt cache, which costs far less.")
                }
            }

            Section("This week by task") {
                if week.byTask.isEmpty { Text("No runs this week.").foregroundStyle(.secondary) }
                ForEach(week.byTask, id: \.key) { item in
                    LabeledContent(taskTitle(item.key), value: hxTokens(item.tokens))
                }
            }

            Section("This week by model") {
                if week.byModel.isEmpty { Text("No runs this week.").foregroundStyle(.secondary) }
                ForEach(week.byModel, id: \.model) { item in
                    LabeledContent {
                        Text(hxTokens(item.tokens))
                    } label: {
                        Text(modelName(item.model, provider: item.provider))
                        if chosen == nil { Text(item.provider) }
                    }
                }
            }

            Section {
                Picker("Warn me above", selection: limitBinding(\.warnAbove, UsageLimits.warnSetting)) {
                    Text("Off").tag(0)
                    Divider()
                    ForEach(Self.amounts, id: \.self) { Text("\(hxTokens($0)) tokens a day").tag($0) }
                }
                Picker("Pause agents above", selection: limitBinding(\.pauseAbove, UsageLimits.pauseSetting)) {
                    Text("Never").tag(0)
                    Divider()
                    ForEach(Self.amounts, id: \.self) { Text("\(hxTokens($0)) tokens a day").tag($0) }
                }
                Picker("Stop one run above", selection: runBudgetBinding) {
                    Text("Never").tag(0)
                    Divider()
                    ForEach(Self.runAmounts, id: \.self) { Text("\(hxTokens($0)) tokens").tag($0) }
                }
            } header: {
                Text("Limits")
            } footer: {
                Text("Usage is counted from what each program reports. Plans have their own limits; Hatch only warns, or stops starting new work until tomorrow. A coding agent that goes past the limit for one run is stopped and its ticket is Blocked; its work stays in the workspace.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear(perform: load)
        .onChange(of: state.agentRuns.count) { load() }
    }

    static let amounts = [500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000, 20_000_000]
    static let runAmounts = [500_000, 1_000_000, 1_500_000, 3_000_000, 5_000_000]

    /// Fourteen bars, today last. Stacked by provider, or by model when one provider is chosen.
    private var chart: some View {
        let start = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: Date()))!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        return Chart(fortnight.days) { d in
            BarMark(x: .value("Day", d.day, unit: .day), y: .value("Tokens", d.tokens))
                .foregroundStyle(by: .value(chosen == nil ? "Provider" : "Model", d.key))
                .cornerRadius(2)
            if limits.warnAbove > 0 {
                RuleMark(y: .value("Warn", limits.warnAbove))
                    .foregroundStyle(.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXScale(domain: start...end)
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text(hxTokens(n)) } } } }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 150)
        .padding(.vertical, 6)
        .overlay {
            if fortnight.days.isEmpty {
                Text("No runs in the last 14 days").font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Tokens per day, last 14 days: \(hxTokens(fortnight.total)) in all")
    }

    /// The model's listed name when its provider is set up here, else its id.
    private func modelName(_ id: String, provider: String) -> String {
        AgentSettings.load(from: state.store, detect: false).providers.first { $0.name == provider }?.model(id)?.name ?? id
    }

    private func taskTitle(_ key: String) -> String {
        AgentRole(rawValue: key)?.taskTitle ?? "Other"
    }

    private var runBudgetBinding: Binding<Int> {
        Binding(get: { runBudget }, set: { value in
            runBudget = value
            state.perform("Save the limit") { try state.store.setSetting(AgentLauncher.tokenBudgetSetting, String(value)) }
        })
    }

    private func limitBinding(_ path: WritableKeyPath<UsageLimits, Int>, _ setting: String) -> Binding<Int> {
        Binding(get: { limits[keyPath: path] }, set: { value in
            limits[keyPath: path] = value
            state.perform("Save the limit") { try state.store.setSetting(setting, String(value)) }
            state.checkUsage()
        })
    }

    private func load() {
        let start = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: Date()))!
        runs = (try? state.store.runRecords(since: start)) ?? []
        limits = UsageLimits.load(from: state.store)
        runBudget = Int((try? state.store.setting(AgentLauncher.tokenBudgetSetting)) ?? nil ?? "") ?? AgentLauncher.defaultTokenBudget
        if !provider.isEmpty && !providers.contains(provider) { provider = "" }
    }
}
