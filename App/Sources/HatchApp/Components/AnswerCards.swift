import SwiftUI
import HatchCore

// How a question looks wherever it is answered (decision DR8, picked in the Decide Lab): the asker's mark, name and
// time, the whole message in a grey bubble, then the answers as a list with number keys, a filled Recommended badge and
// a checkmark on the selected one, "Something else…" last. Selecting does nothing; Answer sends.

/// One answer the owner can pick.
struct AnswerOption: Identifiable, Hashable {
    let id: String
    var title: String
    var detail: String? = nil
    var gain: String? = nil
    var cost: String? = nil
    var recommended = false
    /// The text that goes back to the asker.
    var answer: String
    /// A design system answer drawn in its places (Decide's component questions).
    var sample: ComponentOptionSample? = nil

    /// A long answer split into a short bold line and the rest: at the first colon, dash or sentence end within 90
    /// characters; otherwise the whole text is the title.
    static func split(_ text: String) -> (title: String, detail: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in [": ", " — ", " - ", ". "] {
            if let r = t.range(of: sep), t.distance(from: t.startIndex, to: r.lowerBound) <= 90 {
                let head = String(t[..<r.lowerBound]) + (sep == ". " ? "." : "")
                let tail = String(t[r.upperBound...])
                if !tail.isEmpty { return (head, tail.prefix(1).uppercased() + tail.dropFirst()) }
            }
        }
        return (t, nil)
    }

    /// The answers to a question, recommended first: the asker's suggestions, or its own "My recommendation: …" when it
    /// gave none.
    static func replies(for q: Question) -> [AnswerOption] {
        if !q.suggestions.isEmpty {
            return q.suggestions.enumerated().map { i, text in
                let (title, detail) = split(text)
                return AnswerOption(id: "\(i)", title: title, detail: detail, recommended: i == 0, answer: text)
            }
        }
        let digest = QuestionDigest(q.text)
        if let rec = digest.recommendation, let answer = digest.acceptAnswer {
            return [AnswerOption(id: "rec", title: rec, detail: "\(q.askedBy)'s own recommendation.", recommended: true, answer: answer)]
        }
        return []
    }
}

/// The asker's message: the mark on its own, name and time, the whole text in a grey bubble.
struct QuestionMessage: View {
    let asker: String
    var at: Date? = nil
    let text: String

    /// How far the answers under a message are indented, so they line up with the bubble.
    static let indent: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            glyph.frame(width: 18, height: 18).padding(.top, 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(asker).fontWeight(.semibold).foregroundStyle(.primary)
                    if let at { Text("· \(Format.ago(at))") }
                }
                .font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(HX.bubble, in: RoundedRectangle(cornerRadius: HX.bubbleRadius, style: .continuous))
            }
        }
    }

    @ViewBuilder private var glyph: some View {
        if asker.caseInsensitiveCompare("Iris") == .orderedSame { Image("IrisIcon").resizable().scaledToFit() }
        else if asker == "Hatch" { Image(systemName: "square.stack.3d.up").resizable().scaledToFit() }
        else { Image(systemName: "cpu").resizable().scaledToFit() }
    }
}

/// The answers as one grouped list: the key that picks each (1–4), the title, all of its explanation, gain and cost, a
/// filled Recommended badge, the selected row tinted with a checkmark; "Something else…" opens a field.
struct AnswerList: View {
    let options: [AnswerOption]
    @Binding var selection: String
    /// Nil when the question is answered only by its choices.
    var own: Binding<String>? = nil
    var ownFocus: FocusState<Bool>.Binding? = nil
    var showKeys = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { i, o in
                if i > 0 { Divider().padding(.leading, 14) }
                row(o, index: i)
            }
            if let own {
                if !options.isEmpty { Divider().padding(.leading, 14) }
                ownRow(own)
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ o: AnswerOption, index i: Int) -> some View {
        let on = selection == o.id
        return Button { selection = o.id } label: {
            HStack(alignment: .top, spacing: 10) {
                if showKeys { key(i < 4 ? "\(i + 1)" : " ") }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(o.title).fontWeight(.medium).multilineTextAlignment(.leading)
                        if o.recommended {
                            Text("Recommended").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.accentColor, in: Capsule())
                        }
                    }
                    if let s = o.sample { ComponentOptionPreview(sample: s) }
                    if let d = o.detail {
                        Text(d).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    if let g = o.gain { line("plus", g, primary: true) }
                    if let c = o.cost { line("minus", c, primary: false) }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentColor).opacity(on ? 1 : 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color.accentColor.opacity(0.1) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func ownRow(_ own: Binding<String>) -> some View {
        let on = selection == "own"
        return VStack(alignment: .leading, spacing: 10) {
            Button { selection = "own" } label: {
                HStack(spacing: 10) {
                    if showKeys { key(" ") }
                    Text("Something else…").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentColor).opacity(on ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            if on {
                if let ownFocus {
                    TextField("Write your own answer", text: own, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5).focused(ownFocus)
                } else {
                    TextField("Write your own answer", text: own, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(on ? Color.accentColor.opacity(0.1) : .clear)
    }

    private func key(_ k: String) -> some View {
        Text(k).font(.caption.monospaced()).foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .background(k == " " ? Color.clear : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }

    private func line(_ symbol: String, _ text: String, primary: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(width: 10)
            Text(text).font(.callout).foregroundStyle(primary ? Color.primary : Color.secondary).multilineTextAlignment(.leading)
        }
    }
}

/// Every open question on a ticket, one after another, each with its own Answer (the ticket page and the composer).
/// Answering the last open question moves the ticket on (back to the work, to Iris, or to Ready); the store does that.
struct AnswerCardsView: View {
    @EnvironmentObject var state: AppState
    let ticketId: Int
    @State private var questions: [Question] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(questions) { question in
                AnswerCard(question: question)
            }
        }
        .autoReload(every: 4) { load() }
    }

    private func load() {
        let open: [Question] = (try? state.store.questions(ticketId: ticketId, openOnly: true)) ?? []
        if open != questions { questions = open }
    }
}

/// One question outside Decide: the message, the answer list and an Answer button under it.
struct AnswerCard: View {
    @EnvironmentObject var state: AppState
    let question: Question
    @State private var selected: String?
    @State private var own = ""

    /// Questions Hatch acts on (an area, a path, a duplicate, a split) are answered by one of their choices; the others
    /// also take free text (decision WF-T3).
    private var choicesOnly: Bool { QuestionPurpose.isActedOn(question.purpose) }
    private var options: [AnswerOption] { AnswerOption.replies(for: question) }
    private var selection: String { selected ?? options.first?.id ?? "own" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuestionMessage(asker: question.askedBy, at: question.at, text: question.text)
            if question.purpose == QuestionPurpose.split, let parts = question.payload?["children"]?.arrayValue {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        Text("\u{2022} " + (part["title"]?.stringValue ?? "")).font(.callout)
                    }
                }
                .padding(.leading, QuestionMessage.indent)
            }
            VStack(alignment: .trailing, spacing: 12) {
                AnswerList(options: options, selection: Binding(get: { selection }, set: { selected = $0 }),
                           own: choicesOnly ? nil : $own, showKeys: false)
                Button("Answer") { send() }
                    .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .disabled(answerText == nil)
            }
            .padding(.leading, QuestionMessage.indent)
        }
    }

    private var answerText: String? {
        if selection == "own" {
            let t = own.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return options.first { $0.id == selection }?.answer
    }

    private func send() {
        guard let answer = answerText else { return }
        let id = question.id
        _ = state.perform("Could not save the answer") { try state.store.answer(questionId: id, text: answer) }
        state.refresh()
    }
}

/// The title, then the icon: "Open ticket ↗".
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.title; configuration.icon.imageScale(.small) }
    }
}
