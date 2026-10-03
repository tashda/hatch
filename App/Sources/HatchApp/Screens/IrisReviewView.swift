import SwiftUI
import HatchCore

/// What Iris suggested, read from her summary note (see `VettingBridge` for the contract).
struct VettingResult {
    struct Duplicate: Identifiable {
        let ticketId: Int
        let reason: String
        var id: Int { ticketId }
    }
    var noteId: Int
    var summary: String
    var rewriteTitle: String?
    var rewriteBody: String?
    var suggestedType: TicketType?
    var typeReason: String?
    var duplicates: [Duplicate] = []

    var hasRewrite: Bool { rewriteTitle != nil || rewriteBody != nil }

    static func latest(store: HatchStore, ticketId: Int) -> VettingResult? {
        let notes: [Note] = (try? store.notes(ticketId: ticketId)) ?? []
        guard let note = notes.last(where: { $0.author == "Iris" && $0.context?["vetting"] != nil }) else { return nil }
        guard let v = note.context?["vetting"] else { return nil }
        var result = VettingResult(noteId: note.id, summary: note.body)
        if let rewrite = v["rewrite"] {
            result.rewriteTitle = rewrite["title"]?.stringValue
            result.rewriteBody = rewrite["body"]?.stringValue
        }
        if let type = v["type"], let raw = type["suggested"]?.stringValue, let t = TicketType(rawValue: raw) {
            result.suggestedType = t
            result.typeReason = type["reason"]?.stringValue
        }
        for item in v["duplicates"]?.arrayValue ?? [] {
            if let id = item["ticket"]?.intValue {
                result.duplicates.append(Duplicate(ticketId: id, reason: item["reason"]?.stringValue ?? ""))
            }
        }
        return result
    }
}

/// Word-level comparison of two texts, drawn with colour, underline and strikethrough (decision E8).
enum WordDiff {
    static func marks(old: String, new: String) -> (removed: Set<Int>, inserted: Set<Int>) {
        let oldWords: [String] = old.components(separatedBy: " ")
        let newWords: [String] = new.components(separatedBy: " ")
        let diff = newWords.difference(from: oldWords)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        return (removed, inserted)
    }

    static func originalText(old: String, new: String) -> Text {
        let m = marks(old: old, new: new)
        let words: [String] = old.components(separatedBy: " ")
        var out = Text("")
        for (i, word) in words.enumerated() {
            let piece: String = i < words.count - 1 ? word + " " : word
            if m.removed.contains(i) {
                out = out + Text(piece).foregroundStyle(Theme.critical).strikethrough()
            } else {
                out = out + Text(piece)
            }
        }
        return out
    }

    static func suggestedText(old: String, new: String) -> Text {
        let m = marks(old: old, new: new)
        let words: [String] = new.components(separatedBy: " ")
        var out = Text("")
        for (i, word) in words.enumerated() {
            let piece: String = i < words.count - 1 ? word + " " : word
            if m.inserted.contains(i) {
                out = out + Text(piece).foregroundStyle(Theme.finished).underline()
            } else {
                out = out + Text(piece)
            }
        }
        return out
    }
}

/// The review after Iris has checked a ticket: answer cards, the rewrite as a diff, the type suggestion, likely duplicates.
/// Used inside the composer after Submit and at the top of a ticket (decisions E4, E6, E8, E9).
struct IrisReviewView: View {
    @EnvironmentObject var state: AppState
    let ticketId: Int
    var showIdleMessage: Bool = false

    @State private var ticket: Ticket?
    @State private var result: VettingResult?
    @State private var resolved: Set<String> = []
    @State private var openQuestionCount = 0
    @State private var editing = false
    @State private var editTitle = ""
    @State private var editBody = ""
    @State private var mergeCandidate: VettingResult.Duplicate?

    private var pendingRewrite: Bool { (result?.hasRewrite ?? false) && !resolved.contains("rewrite") }
    private var pendingType: Bool { result?.suggestedType != nil && !resolved.contains("type") }
    private var pendingDuplicates: [VettingResult.Duplicate] {
        (result?.duplicates ?? []).filter { !resolved.contains("duplicate-\($0.ticketId)") }
    }
    private var hasAnything: Bool {
        openQuestionCount > 0 || pendingRewrite || pendingType || !pendingDuplicates.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let ticket {
                content(ticket)
            }
        }
        .autoReload(every: 3) { load() }
        .sheet(isPresented: $editing) { editSheet }
        .confirmationDialog("Merge into the other ticket?", isPresented: Binding(get: { mergeCandidate != nil }, set: { if !$0 { mergeCandidate = nil } })) {
            Button("Mark this as a duplicate and drop it", role: .destructive) { merge() }
            Button("Cancel", role: .cancel) { mergeCandidate = nil }
        } message: {
            Text("This ticket is linked as a duplicate and dropped. Nothing is deleted; you can reopen it later.")
        }
    }

    @ViewBuilder private func content(_ ticket: Ticket) -> some View {
        if ticket.status == .checking {
            checking(ticket)
        } else if hasAnything {
            header
            if !pendingDuplicates.isEmpty { duplicatesCard }
            if pendingType { typeCard(ticket) }
            if openQuestionCount > 0 { AnswerCardsView(ticketId: ticketId) }
            if pendingRewrite { rewriteCard(ticket) }
        } else if showIdleMessage {
            idle(ticket)
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Theme.agent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Iris checked this ticket")
                    .font(.subheadline.weight(.semibold))
                if let summary = result?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func checking(_ ticket: Ticket) -> some View {
        let slow = Date().timeIntervalSince(ticket.updatedAt) > 120
        return HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Iris is checking this ticket")
                    .font(.subheadline.weight(.semibold))
                Text(slow ? "This is taking longer than usual." : "She compares it with other tickets and the Spec, then asks questions before any work starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if slow && VettingBridge.isAvailable {
                Button("Check again") { VettingBridge.start(ticketId: ticket.id, state: state) }
            }
        }
        .padding(12)
        .background(Theme.agentBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private func idle(_ ticket: Ticket) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(Theme.finished)
            Text(ticket.status == .ready ? "Nothing to review. The ticket is Ready." : "Nothing to review.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var duplicatesCard: some View {
        SectionCard("Likely duplicates") {
            ForEach(pendingDuplicates) { dup in
                VStack(alignment: .leading, spacing: 6) {
                    if let other = try? state.store.ticket(id: dup.ticketId) {
                        HStack(spacing: 8) {
                            Button {
                                state.open(other)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(other.displayNumber).foregroundStyle(.secondary)
                                    Text(other.title)
                                }
                            }
                            .buttonStyle(.link)
                            StatusChip(status: other.status)
                        }
                    }
                    if !dup.reason.isEmpty {
                        Text(dup.reason).font(.callout).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Link") { linkDuplicate(dup) }
                        Button("Merge") { mergeCandidate = dup }
                        Button("Keep separate") { resolve("duplicate-\(dup.ticketId)", outcome: "kept") }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func typeCard(_ ticket: Ticket) -> some View {
        let suggested: TicketType = result?.suggestedType ?? ticket.type
        return SectionCard("Type") {
            HStack(spacing: 8) {
                TypeBadge(type: ticket.type)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TypeBadge(type: suggested)
            }
            if let reason = result?.typeReason, !reason.isEmpty {
                Text(reason).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Accept") { acceptType(suggested) }
                    .buttonStyle(.borderedProminent)
                Button("Keep mine") { resolve("type", outcome: "kept") }
            }
            .controlSize(.small)
        }
    }

    private func rewriteCard(_ ticket: Ticket) -> some View {
        let newTitle: String = result?.rewriteTitle ?? ticket.title
        let newBody: String = result?.rewriteBody ?? ticket.body
        return SectionCard("Suggested rewrite") {
            if newTitle != ticket.title {
                diffColumns(old: ticket.title, new: newTitle, bold: true)
            }
            if newBody != ticket.body {
                diffColumns(old: ticket.body, new: newBody, bold: false)
            }
            Text("Removed words are struck through in red; added words are underlined in green. Your original is always kept in the history.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Accept") { acceptRewrite(newTitle: newTitle, newBody: newBody) }
                    .buttonStyle(.borderedProminent)
                Button("Edit") {
                    editTitle = newTitle
                    editBody = newBody
                    editing = true
                }
                Button("Keep mine") { resolve("rewrite", outcome: "kept") }
            }
            .controlSize(.small)
        }
    }

    private func diffColumns(old: String, new: String, bold: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Yours").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                WordDiff.originalText(old: old, new: new)
                    .font(diffFont(bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Iris suggests").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                WordDiff.suggestedText(old: old, new: new)
                    .font(diffFont(bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diffFont(_ bold: Bool) -> Font {
        if bold { return Font.body.weight(.semibold) }
        return Font.body
    }

    private var editSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit the suggestion")
                .font(.title3.weight(.semibold))
            TextField("Title", text: $editTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $editBody)
                .font(.body)
                .frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Cancel") { editing = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    applyText(title: editTitle, body: editBody, outcome: "edited")
                    editing = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    // MARK: Actions

    private func acceptRewrite(newTitle: String, newBody: String) {
        applyText(title: newTitle, body: newBody, outcome: "accepted")
    }

    private func applyText(title: String, body: String, outcome: String) {
        let id = ticketId
        let ok: Ticket? = state.perform("Could not apply the rewrite") { try state.store.update(id, title: title, body: body, actor: .owner) }
        if ok != nil { resolve("rewrite", outcome: outcome) }
    }

    private func acceptType(_ type: TicketType) {
        let id = ticketId
        let reason: String? = result?.typeReason
        let ok: Ticket? = state.perform("Could not change the type") { try state.store.changeType(id, to: type, actor: .owner, reason: reason) }
        if ok != nil { resolve("type", outcome: "accepted") }
    }

    private func linkDuplicate(_ dup: VettingResult.Duplicate) {
        let id = ticketId
        let other = dup.ticketId
        _ = state.perform("Could not link the tickets") { try state.store.link(from: id, to: other, kind: .duplicates) }
        resolve("duplicate-\(dup.ticketId)", outcome: "linked")
    }

    private func merge() {
        guard let dup = mergeCandidate else { return }
        mergeCandidate = nil
        let id = ticketId
        let other = dup.ticketId
        let done: Ticket? = state.perform("Could not merge the tickets") {
            try state.store.link(from: id, to: other, kind: .duplicates)
            return try state.store.move(id, to: .dropped, actor: .owner, reason: "duplicate of \(other)")
        }
        if done != nil { resolve("duplicate-\(dup.ticketId)", outcome: "merged") }
    }

    private func resolve(_ part: String, outcome: String) {
        guard let noteId = result?.noteId else { return }
        let id = ticketId
        _ = state.perform("Could not record the choice") {
            try state.store.record(id, actor: "owner", kind: "vetting-review",
                                   payload: ["note": .int(noteId), "part": .string(part), "outcome": .string(outcome)])
        }
    }

    // MARK: Data

    private func load() {
        ticket = try? state.store.ticket(id: ticketId)
        let latest = VettingResult.latest(store: state.store, ticketId: ticketId)
        result = latest
        var done = Set<String>()
        if let latest {
            let events: [Event] = (try? state.store.events(ticketId: ticketId, kinds: ["vetting-review"])) ?? []
            for e in events where e.payload["note"]?.intValue == latest.noteId {
                if let part = e.payload["part"]?.stringValue { done.insert(part) }
            }
        }
        resolved = done
        openQuestionCount = ((try? state.store.questions(ticketId: ticketId, openOnly: true)) ?? []).count
    }
}
