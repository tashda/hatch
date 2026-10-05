import Foundation
import HatchCore

/// Checks a survey against the code (decision SW5), so a listed card cannot be invented: every item's file must exist inside
/// the app and hold the item's name. Only Hatch's own look at the files counts; the agent's word does not.
public enum SweepItemCheck {
    public static func problems(_ items: [ManifestItem], appRoot: String) -> [GateIssue] {
        let root = URL(fileURLWithPath: appRoot).standardizedFileURL
        var out: [GateIssue] = []
        for item in items {
            let relative = item.file.trimmingCharacters(in: .whitespaces)
            guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
                out.append(.error("items.file-outside", "Item '\(item.id)' names a file outside the app: \(item.file).", "Give the path relative to the app, such as App/Sources/Views/DecideCard.swift."))
                continue
            }
            let url = root.appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                out.append(.error("items.file-missing", "Item '\(item.id)': there is no file \(item.file) in the app.", "Check the path with ls or Glob, and list only what exists."))
                continue
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                out.append(.error("items.file-unreadable", "Item '\(item.id)': \(item.file) cannot be read as text.", "List a source file."))
                continue
            }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: item.name) + "\\b"
            if text.range(of: pattern, options: .regularExpression) == nil {
                out.append(.error("items.name-not-in-file", "Item '\(item.id)': \(item.file) does not contain \(item.name).",
                                  "name is the type or view as the code spells it. Open the file and copy the name, or drop the item."))
            }
        }
        return out
    }
}

/// Checks a Sweep's role design against the design system (decision SW14), with the check the system itself offers for a change
/// Proposal: only the element's own settings, only their values, and the whole system still valid.
public enum RoleDesignCheck {
    public static func problems(_ role: ManifestRole, system: ComponentSystem) -> [GateIssue] {
        role.looks.sorted(by: { $0.key < $1.key }).flatMap { option, look in
            system.problems(look: look, forRole: role.id, label: "Option '\(option)'").map { GateIssue.error($0.code, $0.message, $0.fix) }
        }
    }
}
