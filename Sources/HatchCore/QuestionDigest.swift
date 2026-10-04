import Foundation

/// A question split into what the owner needs first: the ask itself, the asker's own recommendation, and an opening line.
/// Agents often send one long paragraph; the owner should read the question in a glance and open the rest only when
/// needed. Free and local: plain text rules, no model call (rule 4).
public struct QuestionDigest: Equatable, Sendable {
    /// The opening statement before the ask ("I can't prepare #5 yet."), shown only for a long question.
    public let lead: String?
    /// The question sentences, or the whole text when it holds no question mark.
    public let ask: String
    /// What the asker recommends, from "My recommendation: …" or "I recommend …", with its first letter capitalised.
    public let recommendation: String?
    /// Whether the full text says more than the digest, so it is worth a "full message" disclosure.
    public let isLong: Bool

    /// Shorter than this, the text is shown as it is.
    public static let longAfter = 240

    public init(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = Self.sentences(text)
        let recIndex = sentences.firstIndex { Self.recommendation(in: $0) != nil }
        recommendation = recIndex.flatMap { Self.recommendation(in: sentences[$0]) }

        guard text.count > Self.longAfter else {
            lead = nil
            ask = text
            isLong = false
            return
        }
        let questions = sentences.filter { $0.hasSuffix("?") }
        ask = questions.isEmpty ? (sentences.first ?? text) : questions.joined(separator: " ")
        if let first = sentences.first, !first.hasSuffix("?"), recIndex != 0, first != ask {
            lead = first
        } else {
            lead = nil
        }
        isLong = true
    }

    /// The answer to send when the owner goes with the asker's recommendation.
    public var acceptAnswer: String? {
        recommendation.map { "Go with your recommendation: \($0.prefix(1).lowercased() + $0.dropFirst())." }
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            guard c == "." || c == "?" || c == "!" else { continue }
            // A sentence ends at the mark when whitespace and then a capital, a digit or a quote follow.
            var j = i + 1
            var sawSpace = false
            while j < chars.count, chars[j].isWhitespace { sawSpace = true; j += 1 }
            if j == chars.count || (sawSpace && (chars[j].isUppercase || chars[j].isNumber || "\"'‘“#".contains(chars[j]))) {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    static func recommendation(in sentence: String) -> String? {
        let lower = sentence.lowercased()
        var body: Substring?
        for marker in ["my recommendation:", "recommendation:", "i recommend:"] {
            if let r = lower.range(of: marker) {
                body = sentence[r.upperBound...]
                break
            }
        }
        if body == nil, lower.hasPrefix("i recommend ") {
            body = sentence.dropFirst("i recommend ".count)
        }
        guard var rec = body.map({ String($0).trimmingCharacters(in: .whitespaces) }), !rec.isEmpty else { return nil }
        while let last = rec.last, ".!".contains(last) { rec.removeLast() }
        guard !rec.isEmpty else { return nil }
        return rec.prefix(1).uppercased() + rec.dropFirst()
    }
}
