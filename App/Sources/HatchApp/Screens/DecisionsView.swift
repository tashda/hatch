import SwiftUI
import HatchCore

/// Decisions: frozen results, each linked to its ticket (decisions N1, PS9, PS15). Read from the database, which keeps
/// them in full and searches them for free; each one is also a file in the project's notebook.
struct DecisionsView: View {
    @EnvironmentObject var state: AppState
    @State private var filter = ""
    @State private var kind: DecisionKind?

    private var rows: [DecisionRecord] {
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        var list: [DecisionRecord]
        if f.isEmpty {
            list = (try? state.store.decisionRecords(projectId: state.projectFilterId)) ?? []
        } else if let pid = state.projectFilterId ?? (state.projects.count == 1 ? state.projects.first?.id : nil) {
            // Full-text search, best match first, over title, summary, reason and area.
            list = (try? state.store.searchDecisions(projectId: pid, query: f, limit: 100)) ?? []
        } else {
            list = ((try? state.store.decisionRecords()) ?? []).filter {
                ($0.title + " " + $0.summary + " " + ($0.reason ?? "")).localizedCaseInsensitiveContains(f)
            }
        }
        if let kind { list = list.filter { $0.kind == kind } }
        return list
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                HXHeader(title: "Decisions", subtitle: "What was decided and why. Each one is also a file in the project's notebook.")
                Spacer()
                Picker("Kind", selection: $kind) {
                    Text("All").tag(DecisionKind?.none)
                    ForEach(DecisionKind.allCases, id: \.self) { Text($0.displayName).tag(DecisionKind?.some($0)) }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                TextField("Search", text: $filter).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            .padding(16)
            .floatingCard()
            let list = rows
            if list.isEmpty {
                ContentUnavailableView(filter.isEmpty ? "No decisions yet" : "No matching decisions", systemImage: "flag",
                                       description: Text("A decision is recorded when you accept a Proposal or choose an option on a Question."))
                    .floatingCard()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(list, id: \.id) { card($0) }
                    }
                    .padding(3)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollClipDisabled()
            }
        }
        .environment(\.hxCardOnGray, true)
    }

    private func card(_ d: DecisionRecord) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(DecisionKind.allCases, id: \.self) { k in
                            Button(k.displayName) { setKind(d, k) }.disabled(k == d.kind)
                        }
                    } label: {
                        Text(d.kind.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                    .help("Change the kind")
                    Button { open(d) } label: { Text("\(d.ticketNumber) \(d.title.isEmpty ? d.summary : d.title)").lineLimit(1) }
                        .buttonStyle(.link)
                    Spacer()
                    Text(d.at.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                }
                Text(d.summary).textSelection(.enabled)
                if let why = d.reason, !why.isEmpty {
                    Text("Why: \(why)").foregroundStyle(.secondary).textSelection(.enabled)
                }
                if !d.options.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(d.options, id: \.key) { o in
                            let chosen = d.choice == o.key || (d.choice?.contains("\(o.key) = ") ?? false)
                            HStack(spacing: 6) {
                                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen ? Theme.finished : .secondary).font(.caption)
                                Text("\(o.key): \(o.title)").font(.callout)
                                if o.key == d.recommended { Text("recommended").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    ForEach(d.specCodes, id: \.self) { code in
                        Text(code).font(.caption.monospaced()).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Text(d.filePath ?? "Not in the notebook yet").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func open(_ d: DecisionRecord) {
        if let t = try? state.store.ticket(id: d.ticketId) { state.open(t) }
    }

    /// The kind is the one part of a decision that can change; the notebook file is rewritten on the next export.
    private func setKind(_ d: DecisionRecord, _ kind: DecisionKind) {
        state.perform("Could not change the kind") {
            try state.store.setDecisionKind(d.id, kind: kind)
        }
        state.notebookChanged(projectId: d.projectId)
    }
}
