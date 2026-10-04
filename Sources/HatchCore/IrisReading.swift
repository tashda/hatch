import Foundation

/// A ticket's text as Iris leaves it (decision IR2): the owner's words stay the ticket, and her structured reading is a
/// labelled section after them, so nothing she writes can pass as something the owner said.
public enum IrisReading {
    /// Starts the section. Everything after it is Iris's.
    public static let marker = "\n\n---\n**Iris's reading** (her words, not yours)\n\n"

    /// The owner's words for a ticket as captured: the title when the prompt was one short line, the whole prompt when the
    /// title was cut (`workingTitle` keeps the whole text as the body then), otherwise title and body together.
    public static func ownerWords(title: String?, body: String?) -> String {
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return title }
        if title.isEmpty || title.hasSuffix("…") || body.hasPrefix(title) { return body }
        return title + "\n\n" + body
    }

    /// The owner's text and Iris's section, split at the marker. `reading` is nil when there is no section.
    public static func split(_ body: String) -> (words: String, reading: String?) {
        guard let r = body.range(of: marker) else { return (body, nil) }
        return (String(body[..<r.lowerBound]), String(body[r.upperBound...]))
    }

    /// The owner's words, then the labelled section. `assumed` is what she read into the text that the owner did not say.
    public static func compose(words: String, reading: String, assumed: [String]) -> String {
        var section = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = assumed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !notes.isEmpty { section += (section.isEmpty ? "" : "\n\n") + "Assumed: " + notes.joined(separator: "; ") }
        return section.isEmpty ? words : words + marker + section
    }
}
