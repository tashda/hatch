import SwiftUI
import HatchCore

/// Plain-words descriptions of the events in a ticket's log (Thread and History tabs).
enum EventText {
    static func statusName(_ raw: String?) -> String {
        guard let raw, let s = Status(rawValue: raw) else { return raw ?? "?" }
        return s.displayName
    }

    static func describe(_ e: Event) -> String {
        let p = e.payload
        switch e.kind {
        case "created":
            return "Created as \(p["type"]?.stringValue ?? "ticket")"
        case "status":
            var text = "\(statusName(p["from"]?.stringValue)) to \(statusName(p["to"]?.stringValue))"
            if let reason = p["reason"]?.stringValue, !reason.isEmpty { text += " (\(reason))" }
            return text
        case "type":
            return "Type changed from \(p["from"]?.stringValue ?? "?") to \(p["to"]?.stringValue ?? "?")"
        case "edit":
            return "Text edited"
        case "note":
            switch p["kind"]?.stringValue {
            case "agent": return "The agent wrote a note"
            case "instruction": return "Sent an instruction"
            case "ask": return "Asked the agent"
            case "comment": return "Comment from GitHub"
            default: return "Added a note"
            }
        case "question":
            return "Asked: \(p["text"]?.stringValue ?? "")"
        case "answer":
            return "Answered a question"
        case "link":
            return "Linked (\(p["kind"]?.stringValue ?? "related"))"
        case "attachment":
            return "Added a screenshot"
        case "pick":
            return "Picked \(p["choice"]?.stringValue ?? "") for \(p["topic"]?.stringValue ?? "")"
        case "verdict":
            return "\(p["verdict"]?.stringValue ?? "") on \(p["option"]?.stringValue ?? "") (\(p["topic"]?.stringValue ?? ""))"
        case "revision":
            return "Revision \(p["n"]?.intValue ?? 0): \(p["summary"]?.stringValue ?? "")"
        case "claim":
            let n = p["paths"]?.arrayValue?.count ?? 0
            return "Claimed \(Format.count(n, "path")) (\(p["state"]?.stringValue ?? ""))"
        case "claim-granted":
            return "Files are free, claims granted"
        case "stack":
            return "Stacked on another ticket"
        case "take":
            return "Taken for \(p["task"]?.stringValue ?? "work")"
        case "release":
            return "Released: \(p["reason"]?.stringValue ?? "")"
        case "attachment-uploaded":
            return "Screenshot uploaded to the tickets repository"
        case "attachment-upload-failed":
            return "Screenshot upload failed: \(p["error"]?.stringValue ?? "")"
        case "ci":
            return "CI on \(p["ref"]?.stringValue ?? "the integration branch"): \(p["state"]?.stringValue == "passed" ? "passing" : p["state"]?.stringValue == "failed" ? "failing" : "running")"
        case "plan-waiting":
            return "Plan waits for the owner (\(p["reason"]?.stringValue ?? ""))"
        case "plan-approved":
            return "Plan approved"
        case "plan-sent-back":
            return "Plan sent back"
        case "decided":
            return "Decided in Decide" + (p["agreed"]?.boolValue == true ? ", as recommended" : ", own call")
        case "offer":
            return "Offered revision \(p["revision"]?.intValue ?? 1); the quality gate passed"
        case "offer-rejected":
            return "Offer sent back by the quality gate"
        case "typed-values":
            return "\(p["count"]?.intValue ?? 0) values typed into views"
        case "spec", "build", "tests", "match-check", "merge-base", "commit":
            return "\(e.kind.prefix(1).uppercased() + e.kind.dropFirst()): \(p["ok"]?.boolValue == false ? "failed" : "passed")"
        case "vetting":
            return "Iris checked the ticket"
        case "vetting-review":
            return "Review of Iris's suggestion: \(p["part"]?.stringValue ?? "") \(p["outcome"]?.stringValue ?? "")"
        default:
            return e.kind
        }
    }

    static func symbol(_ e: Event) -> String {
        switch e.kind {
        case "status": return "arrow.right.circle"
        case "note": return "text.bubble"
        case "question", "answer": return "questionmark.bubble"
        case "link": return "link"
        case "attachment": return "photo"
        case "pick", "verdict": return "checkmark.circle"
        case "revision": return "arrow.triangle.2.circlepath"
        case "claim", "claim-granted", "stack": return "lock"
        case "take", "release": return "cpu"
        case "edit", "type": return "pencil"
        default: return "circle"
        }
    }
}

/// Words for a link kind, depending on which end of the link this ticket is.
enum LinkText {
    static func label(kind: LinkKind, outgoing: Bool) -> String {
        switch kind {
        case .related: return "Related"
        case .parent: return outgoing ? "Theme" : "Child"
        case .blocks: return outgoing ? "Blocks" : "Blocked by"
        case .duplicates: return outgoing ? "Duplicates" : "Duplicated by"
        case .supersedes: return outgoing ? "Supersedes" : "Superseded by"
        }
    }

    static func name(_ kind: LinkKind) -> String {
        switch kind {
        case .related: return "Related"
        case .parent: return "Parent (Theme)"
        case .blocks: return "Blocks"
        case .duplicates: return "Duplicates"
        case .supersedes: return "Supersedes"
        }
    }
}
