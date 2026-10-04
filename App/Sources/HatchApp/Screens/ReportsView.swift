import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers
import HatchCore
import HatchAgent

/// Reports (design-review/reports.html): where model work went, in tokens only. By provider and model, task, area and
/// ticket, then waste, model against outcome and what Iris's vetting gives back. Read from the run records on this
/// Mac, so opening it costs nothing; Export CSV writes the runs behind what the filters show.
struct ReportsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("hatch.reports.days") private var days = 14
    @State private var provider = ""
    @State private var model = ""
    @State private var report: RunReport?
    @State private var providers: [String] = []
    @State private var hoverDay: Date?

    static let periods = [7, 14, 30, 90]

    var body: some View {
        VStack(spacing: 8) {
            header
                .padding(16)
                .floatingCard()
            if let report, !report.runs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        summary(report)
                        chartCard(report)
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            GridRow {
                                modelsCard(report)
                                tasksCard(report)
                            }
                            GridRow {
                                areasCard(report)
                                ticketsCard(report)
                            }
                        }
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            GridRow(alignment: .top) {
                                wasteCard(report)
                                outcomeCard(report)
                                irisCard(report)
                            }
                        }
                    }
                    .padding(3)
                    .frame(maxWidth: 1100, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollClipDisabled()
            } else {
                ContentUnavailableView("No model work in this period", systemImage: "chart.bar.xaxis",
                                       description: Text("Every run of Iris, Ask and the agents is counted here from the tokens its program reports."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .floatingCard()
            }
        }
        .environment(\.hxCardOnGray, true)
        .onAppear(perform: load)
        .onChange(of: days) { load() }
        .onChange(of: provider) { model = ""; load() }
        .onChange(of: model) { load() }
        .onChange(of: state.projectFilterId) { load() }
        .onChange(of: state.agentRuns.count) { load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            HXHeader(title: "Reports", subtitle: "Where model work went, in tokens. Read from this Mac; nothing is fetched.")
            Spacer()
            if !model.isEmpty {
                Button { model = "" } label: { Label(model, systemImage: "xmark.circle.fill") }
                    .help("Show every model again")
            }
            Picker("Period", selection: $days) {
                ForEach(Self.periods, id: \.self) { Text("Last \($0) days").tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Provider", selection: $provider) {
                Text("All providers").tag("")
                Divider()
                ForEach(providers, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Button("Export CSV…", systemImage: "square.and.arrow.up") { export() }
                .disabled(report?.runs.isEmpty ?? true)
                .help("Save the runs these filters show, one row each, for a spreadsheet")
        }
    }

    // MARK: Summary and chart

    private func summary(_ r: RunReport) -> some View {
        HXCard {
            HStack(alignment: .top, spacing: 0) {
                figure("Tokens", hxTokens(r.total), detail: r.change.map(changeText) ?? "Nothing in the \(days) days before")
                Divider().padding(.horizontal, 16)
                figure("Per finished ticket", r.perFinishedTicket.map(hxTokens) ?? "–",
                       detail: r.finishedTickets == 1 ? "1 ticket done" : "\(r.finishedTickets) tickets done")
                Divider().padding(.horizontal, 16)
                figure("Runs", "\(r.runs.count)", detail: r.usage.cache > 0 ? "\(hxTokens(r.usage.cache)) more read from the cache" : "No cache reads")
                Divider().padding(.horizontal, 16)
                figure("Waste", r.total > 0 ? percent(Double(r.waste.total) / Double(r.total)) : "–",
                       detail: "\(hxTokens(r.waste.total)) on stopped runs and sent-back options")
            }
        }
    }

    private func figure(_ title: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartCard(_ r: RunReport) -> some View {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date()))!
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let hovered = hoverDay.map { d in r.usage.days.filter { cal.isDate($0.day, inSameDayAs: d) } } ?? []
        return HXCard {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle(provider.isEmpty ? "Tokens per day, by provider" : "Tokens per day, by \(provider) model",
                          detail: hovered.isEmpty ? "Hover a bar for that day." : dayText(hovered))
                Chart {
                    ForEach(r.usage.days) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("Tokens", d.tokens))
                            .foregroundStyle(by: .value(provider.isEmpty ? "Provider" : "Model", d.key))
                            .cornerRadius(2)
                            .opacity(hoverDay == nil || cal.isDate(d.day, inSameDayAs: hoverDay!) ? 1 : 0.45)
                    }
                }
                .chartXScale(domain: start...end)
                .chartXSelection(value: $hoverDay)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text(hxTokens(n)) } } } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 200)
            }
        }
    }

    private func dayText(_ day: [UsageSummary.Day]) -> String {
        let total = day.reduce(0) { $0 + $1.tokens }
        let parts = day.sorted { $0.tokens > $1.tokens }.map { "\($0.key) \(hxTokens($0.tokens))" }.joined(separator: " · ")
        return "\(day[0].day.formatted(.dateTime.weekday(.wide).day().month(.wide))): \(hxTokens(total)), \(parts)"
    }

    // MARK: Breakdowns

    private func modelsCard(_ r: RunReport) -> some View {
        table("Model", columns: ["Tokens", "Runs"], detail: "Click a model to show only its work.", rows: r.byModel.prefix(8).map { m in
            BreakdownRow(id: m.id, title: modelName(m.model, provider: m.provider), subtitle: provider.isEmpty ? m.provider : nil,
                         values: [hxTokens(m.tokens), "\(m.runs)"], share: share(m.tokens, r)) { model = m.model }
        })
    }

    private func tasksCard(_ r: RunReport) -> some View {
        table("Task", columns: ["Tokens", "Runs"], detail: "What the work was for.", rows: r.byTask.map { t in
            BreakdownRow(id: t.id, title: AgentRole(rawValue: t.task)?.taskTitle ?? "Other", subtitle: nil,
                         values: [hxTokens(t.tokens), "\(t.runs)"], share: share(t.tokens, r), action: nil)
        })
    }

    private func areasCard(_ r: RunReport) -> some View {
        table("Area", columns: ["Tokens", "Tickets"], detail: "Where in the app the work went.", rows: r.byArea.prefix(8).map { a in
            BreakdownRow(id: a.id, title: a.area, subtitle: nil, values: [hxTokens(a.tokens), "\(a.tickets)"], share: share(a.tokens, r), action: nil)
        })
    }

    private func ticketsCard(_ r: RunReport) -> some View {
        table("Ticket", columns: ["Tokens", "Retries"], detail: "The most expensive tickets. Click one to open it.", rows: r.byTicket.prefix(8).map { t in
            BreakdownRow(id: "\(t.ticketId)", title: t.title, number: t.number, subtitle: nil,
                         values: [hxTokens(t.tokens), "\(t.retries)"], share: share(t.tokens, r)) {
                if let ticket = try? state.store.ticket(id: t.ticketId) { state.open(ticket) }
            }
        })
    }

    private func table(_ title: String, columns: [String], detail: String, rows: [BreakdownRow]) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle(title, detail: detail)
                if rows.isEmpty {
                    Text("Nothing in this period.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        GridRow {
                            Text("").gridColumnAlignment(.leading)
                            ForEach(columns, id: \.self) { Text($0).gridColumnAlignment(.trailing) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach(rows) { row in
                            Divider().gridCellUnsizedAxes(.horizontal)
                            row.view
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Extras

    private func wasteCard(_ r: RunReport) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle("Waste", detail: "Work that did not lead anywhere. A clearer ticket or another model may help.")
                fact("Stopped or retried runs", hxTokens(r.waste.stopped))
                fact("Options you sent back", hxTokens(r.waste.sentBack))
                fact("Share of all tokens", r.total > 0 ? percent(Double(r.waste.total) / Double(r.total)) : "–")
            }
            .monospacedDigit()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func outcomeCard(_ r: RunReport) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle("Model against outcome", detail: "How often a model's build needed no fix after your review.")
                if r.modelOutcomes.isEmpty {
                    Text("No builds handed in yet.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(r.modelOutcomes) { o in
                    fact(modelName(o.model, provider: o.provider),
                         "\(o.firstTime) of \(o.builds) · \(percent(Double(o.firstTime) / Double(max(o.builds, 1))))")
                }
            }
            .monospacedDigit()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func irisCard(_ r: RunReport) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle("Iris value", detail: "What vetting cost, and what it caught before work started.")
                fact("Tokens", r.iris.checks > 0 ? "\(hxTokens(r.iris.tokens)) · \(hxTokens(r.iris.tokens / r.iris.checks)) a check" : hxTokens(r.iris.tokens))
                fact("Tickets checked", "\(r.iris.checks)")
                fact("Questions answered", "\(r.iris.answered) of \(r.iris.questions)")
                fact("Duplicates linked", "\(r.iris.duplicates)")
            }
            .monospacedDigit()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Helpers

    private func cardTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }

    /// A label and its value on one line, the value at the trailing edge.
    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit()
        }
    }

    private func share(_ tokens: Int, _ r: RunReport) -> Double { r.total > 0 ? Double(tokens) / Double(r.total) : 0 }
    private func percent(_ x: Double) -> String { x.formatted(.percent.precision(.fractionLength(0))) }
    private func changeText(_ c: Double) -> String {
        "\(c >= 0 ? "+" : "−")\(percent(abs(c))) on the \(days) days before"
    }

    /// The model's listed name when its provider is set up here, else its id.
    private func modelName(_ id: String, provider: String) -> String {
        AgentSettings.load(from: state.store, detect: false).providers.first { $0.name == provider }?.model(id)?.name ?? id
    }

    private var range: (start: Date, end: Date) {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        return (cal.date(byAdding: .day, value: -days, to: end)!, end)
    }

    private func load() {
        let (start, end) = range
        let before = Calendar.current.date(byAdding: .day, value: -days, to: start)!
        let project = state.projectFilterId
        let runs = (try? state.store.runRecords(since: start, until: end, projectId: project)) ?? []
        let previous = (try? state.store.runRecords(since: before, until: start, projectId: project)) ?? []
        let outcomes = (try? state.store.reportOutcomes(since: start, until: end, projectId: project)) ?? ReportOutcomes()
        providers = Array(Set(runs.map { $0.provider ?? UsageSummary.unknownProvider })).sorted()
        report = RunReport(runs: runs, previous: previous, outcomes: outcomes,
                           provider: provider.isEmpty ? nil : provider, model: model.isEmpty ? nil : model)
    }

    private func export() {
        guard let runs = report?.runs else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Hatch runs \(Date().formatted(.iso8601.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.perform("Export the runs") { try RunReport.csv(runs).write(to: url, atomically: true, encoding: .utf8) }
    }
}

/// One row of a breakdown: a name, its numbers, and a thin bar for its share of all tokens. Clickable when it leads
/// somewhere (a model filters the page, a ticket opens).
private struct BreakdownRow: Identifiable {
    let id: String
    let title: String
    var number: String? = nil
    let subtitle: String?
    let values: [String]
    let share: Double
    let action: (() -> Void)?

    var view: some View {
        GridRow {
            if let action {
                Button(action: action) { label.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                label
            }
            ForEach(Array(values.enumerated()), id: \.offset) { Text($0.element).monospacedDigit() }
        }
    }

    private var label: some View {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let number { Text(number).monospacedDigit().foregroundStyle(.secondary) }
                        Text(title).lineLimit(1).truncationMode(.tail)
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    GeometryReader { g in
                        Capsule().fill(.tertiary).frame(width: max(2, g.size.width * share), height: 3)
                    }
                    .frame(height: 3)
                }
    }
}
