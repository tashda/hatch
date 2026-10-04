import SwiftUI
import HatchCore

/// One card per open question, with suggested answers as buttons and a free text field (decision E4).
/// Answering the last open question moves the ticket on (back to the work, to Iris, or to Ready); the store does that.
struct AnswerCardsView: View {
    @EnvironmentObject var state: AppState
    let ticketId: Int
    @State private var questions: [Question] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

struct AnswerCard: View {
    @EnvironmentObject var state: AppState
    let question: Question
    @State private var text: String = ""
    @State private var primed = false

    /// Questions Hatch acts on (an area, a path, a duplicate, a split) are answered by one of their choices; the others
    /// also take free text. Iris's guess comes first and is picked (decision WF-T3).
    private var choicesOnly: Bool { QuestionPurpose.isActedOn(question.purpose) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble")
                    .foregroundStyle(Theme.you)
                Text("\(question.askedBy) asks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let about = question.payload?["about"]?.stringValue {
                    Text("· about \(about)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.ago(question.at))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(question.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if question.purpose == QuestionPurpose.split, let parts = question.payload?["children"]?.arrayValue {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        Text("\u{2022} " + (part["title"]?.stringValue ?? "")).font(.callout)
                    }
                }
            }
            if !question.suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(question.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        // One click answers; the first is Iris's guess.
                        if index == 0 {
                            Button { answer(suggestion) } label: { Label(suggestion, systemImage: "sparkle") }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.you)
                                .controlSize(.small)
                                .help("Iris's guess. Click to answer with it.")
                        } else {
                            Button(suggestion) { answer(suggestion) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
            if !choicesOnly {
                HStack(spacing: 8) {
                    TextField("Or write your own answer", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }
                    Button("Answer") { send() }
                        .buttonStyle(.glass)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .background(Theme.youBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.you.opacity(0.35)))
    }

    private func send() { answer(text) }

    private func answer(_ raw: String) {
        let answer = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        let id = question.id
        _ = state.perform("Could not save the answer") { try state.store.answer(questionId: id, text: answer) }
        state.refresh()
    }
}
