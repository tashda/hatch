import Foundation
import HatchCore
import HatchGit

// The design system's own commands (decisions DS1 to DS12): start it, answer its questions, agree to roles. The
// system lives in the notebook (`components/system.json`) and only Hatch writes it, through these commands and the app.
extension CoreCommands {
    /// hatch components start --template glass|native   or   --from-app [<app folder>] [--template glass]   [--dry-run] [--replace]
    static func componentStart(_ c: Context) throws {
        let project = try? c.project()
        let name = c.args.option("name") ?? project?.name ?? "This app"
        var system: ComponentSystem
        if c.args.flag("from-app") || c.args.option("from-app") != nil {
            let folder = c.args.pos(2) ?? c.args.option("from-app") ?? project?.config?.repo(.app)?.localPath
            guard let folder else { throw CLIError("Give the app's folder: hatch components start --from-app <folder>.") }
            let template = try c.args.option("template").map { id -> ComponentTemplate in
                guard let t = ComponentTemplates.named(id) else { throw CLIError("No template called \(id).") }
                return t
            } ?? ComponentTemplates.glass
            let inv = ComponentInventoryScanner.scan(appRoot: folder, excluding: [project?.config?.components?.path].compactMap { $0 })
            let minimum = ComponentInventoryScanner.minimumMacOS(appRoot: folder) ?? ComponentSystem.referenceMacOS
            system = ComponentDraft.fromApp(name: name, inventory: inv, template: template, minimumMacOS: minimum)
        } else {
            let id = c.args.option("template") ?? "glass"
            guard let t = ComponentTemplates.named(id) else {
                throw CLIError("No template called \(id). Templates: \(ComponentTemplates.all.map(\.id).joined(separator: ", ")).")
            }
            system = t.system(name: name)
        }
        let problems = system.problems()
        guard problems.isEmpty else { throw CLIError("The draft has problems, so nothing was written:\n" + problems.map { "  - " + $0 }.joined(separator: "\n")) }

        var lines = [summary(system)]
        for r in system.roles { lines.append("  \(r.id)  \(r.places.map { ComponentPlace.title($0) }.joined(separator: ", "))  —  \(r.lookSummary)") }
        if !system.questions.isEmpty {
            lines.append("\n\(system.questions.count) question\(system.questions.count == 1 ? "" : "s") to decide (hatch components questions):")
            for q in system.questions { lines.append("  \(q.title)") }
        }
        if c.args.flag("dry-run") {
            lines.append("\nDry run: nothing written.")
        } else {
            let notebook = try notebookFolder(c)
            if try ComponentSystem.load(notebook: notebook) != nil && !c.args.flag("replace") {
                throw CLIError("\(project?.name ?? "This project") already has a design system. Change it through its questions, or start again with --replace.")
            }
            try save(system, notebook: notebook, message: "Components: start the design system" + (system.template.map { " from the \($0) template" } ?? " from the app"))
            lines.append("\nWritten to the notebook: \(ComponentSystem.notebookPath) and \(ComponentSystem.readmePath).")
        }
        c.out.emit(["roles": .int(system.roles.count), "questions": .int(system.questions.count), "written": .bool(!c.args.flag("dry-run"))],
                   text: lines.joined(separator: "\n"))
    }

    /// hatch components refs: the Apple pages behind the defaults, rules and advice, and which to read again because
    /// the installed SDK is newer than the one they were checked against (NF1).
    static func componentRefs(_ c: Context) throws {
        let installed = shellOutput(["xcrun", "--show-sdk-version", "--sdk", "macosx"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let stale = installed.isEmpty ? [] : ComponentNative.stale(installedSDK: installed)
        var lines = ["\(ComponentNative.references.count) Apple pages, read \(ComponentNative.checkedOn) against the macOS \(ComponentNative.checkedSDK) SDK"
                     + (installed.isEmpty ? "." : "; installed SDK \(installed).")]
        if !stale.isEmpty { lines.append("Read again (the SDK moved on): " + stale.map(\.id).joined(separator: ", ")) }
        for r in ComponentNative.references { lines.append("  \(r.id)  \(r.title)  \(r.url)") }
        c.out.emit(["references": .array(ComponentNative.references.map { r in
                        ["id": .string(r.id), "title": .string(r.title), "url": .string(r.url), "checked": .string(r.checked), "sdk": .string(r.sdk)] }),
                    "stale": .array(stale.map { .string($0.id) })], text: lines.joined(separator: "\n"))
    }

    /// hatch components questions
    static func componentQuestions(_ c: Context) throws {
        let (system, _) = try loadSystem(c)
        guard !system.questions.isEmpty else { c.out.emit(["questions": .array([])], text: "Nothing to decide."); return }
        var lines: [String] = []
        for q in system.questions {
            lines.append("\(q.id)\n  \(q.title)")
            for (i, o) in q.options.enumerated() {
                lines.append("   \(i + 1). \(o.title)" + (o.count > 0 ? "  (\(o.count) uses, e.g. \(o.examples.joined(separator: ", ")))" : "") + (i == q.recommended ? "  ★ recommended" : ""))
            }
            lines.append("  Why: \(q.reason)")
        }
        c.out.emit(["questions": .array(system.questions.map { .string($0.id) })], text: lines.joined(separator: "\n"))
    }

    /// hatch components answer <question> <n>
    static func componentAnswer(_ c: Context) throws {
        guard let id = c.args.pos(2), let n = c.args.pos(3).flatMap(Int.init) else { throw CLIError("Usage: hatch components answer <question id> <option number>") }
        var (system, notebook) = try loadSystem(c)
        let question = system.questions.first { $0.id == id }
        try system.answer(id, option: n - 1, decision: c.args.option("decision"))
        try save(system, notebook: notebook, message: "Components: \(question?.title ?? id) — \(question?.options[n - 1].title ?? "")")
        c.out.emit(["answered": .string(id), "left": .int(system.questions.count)], text: "Answered. \(system.questions.count) question\(system.questions.count == 1 ? "" : "s") left.")
    }

    /// hatch components follow (--role R | --element E [--place P] | --area A)   [--stop]
    /// macOS decides there (NF3): no look of its own, hand styling flagged, never asked again.
    static func componentFollow(_ c: Context) throws {
        var (system, notebook) = try loadSystem(c)
        let message: String
        if let role = c.args.option("role") {
            try system.followMacOS(role: role, decision: c.args.option("decision"))
            message = "Components: \(role) follows macOS"
        } else {
            let scope = ComponentFollow(element: c.args.option("element"), place: c.args.option("place"), area: c.args.option("area"),
                                        decision: c.args.option("decision"))
            if c.args.flag("stop") { system.stopFollowing(scope.id); message = "Components: \(scope.title) no longer follow macOS" }
            else { try system.followMacOS(scope); message = "Components: \(scope.title) follow macOS" }
        }
        try save(system, notebook: notebook, message: message)
        c.out.emit(["follows": .array(system.follows.map { .string($0.id) })], text: message.replacingOccurrences(of: "Components: ", with: "") + ".")
    }

    /// hatch components rule <kind> <value>   or   hatch components rule note "text"   [--remove <id>]
    static func componentRule(_ c: Context) throws {
        var (system, notebook) = try loadSystem(c)
        if let id = c.args.option("remove") {
            system.rules.removeAll { $0.id == id }
        } else {
            guard let kind = c.args.pos(2), let info = ComponentRuleKind.named(kind) else {
                throw CLIError("Usage: hatch components rule <kind> <value>. Kinds: " + ComponentRuleKind.catalog.map(\.id).joined(separator: ", "))
            }
            if kind == "note" {
                let text = c.args.rest(from: 3)
                guard !text.isEmpty else { throw CLIError("Usage: hatch components rule note \"the rule in words\"") }
                system.rules.append(ComponentRule(id: "note-\(system.rules.filter { $0.kind == "note" }.count + 1)", kind: "note", value: "text", text: text, status: .agreed))
            } else {
                guard let value = c.args.pos(3), info.values.contains(where: { $0.id == value }) else {
                    throw CLIError("Values for \(kind): " + info.values.map(\.id).joined(separator: ", "))
                }
                system.rules.removeAll { $0.kind == kind }
                system.rules.append(ComponentRule(id: kind, kind: kind, value: value, text: info.says(value), status: .agreed, decision: c.args.option("decision")))
            }
        }
        try save(system, notebook: notebook, message: "Components: rules")
        c.out.emit(["rules": .array(system.rules.map { .string("\($0.kind)=\($0.value)") })],
                   text: system.rules.map { "  \($0.info?.title ?? $0.kind): \($0.text)" }.joined(separator: "\n"))
    }

    /// hatch components agree [<role>]
    static func componentAgree(_ c: Context) throws {
        var (system, notebook) = try loadSystem(c)
        try system.agree(c.args.pos(2), decision: c.args.option("decision"))
        try save(system, notebook: notebook, message: "Components: agree " + (c.args.pos(2) ?? "every provisional role"))
        c.out.emit(["agreed": .string(c.args.pos(2) ?? "all")], text: summary(system))
    }

    // MARK: Helpers

    static func summary(_ s: ComponentSystem) -> String {
        let n = s.counts
        return "\(s.name): baseline v\(s.version)" + (s.template.flatMap { ComponentTemplates.named($0)?.title }.map { ", from the \($0) template" } ?? "")
            + ", macOS \(s.minimumMacOS) and later. \(s.roles.count) roles: \(n.agreed) agreed, \(n.provisional) provisional"
            + (n.inRedesign > 0 ? ", \(n.inRedesign) in redesign" : "") + (s.questions.isEmpty ? "." : "; \(s.questions.count) to decide.")
    }

    static func notebookFolder(_ c: Context) throws -> String {
        if let dir = c.args.option("notebook") { return (dir as NSString).expandingTildeInPath }
        let project = try c.project()
        guard let notebook = project.config?.repo(.notebook)?.localPath else {
            throw CLIError("\(project.name) has no notebook on this Mac. Give one with --notebook <folder>, or use --dry-run.")
        }
        return notebook
    }

    static func loadSystem(_ c: Context) throws -> (ComponentSystem, String) {
        let notebook = try notebookFolder(c)
        guard let system = try ComponentSystem.load(notebook: notebook) else {
            throw CLIError("No design system yet. Start one: hatch components start --template glass, or --from-app.")
        }
        return (system, notebook)
    }

    /// Writes the system and its README into the notebook and commits there. Refuses a system with problems.
    static func save(_ system: ComponentSystem, notebook: String, message: String) throws {
        let problems = system.problems()
        guard problems.isEmpty else { throw CLIError("Not written; the system would have problems:\n" + problems.map { "  - " + $0 }.joined(separator: "\n")) }
        try NotebookWriter.write([ComponentSystem.notebookPath: String(decoding: try system.encoded(), as: UTF8.self),
                                  ComponentSystem.readmePath: system.readme()], in: notebook)
        if FileManager.default.fileExists(atPath: (notebook as NSString).appendingPathComponent(".git")) {
            _ = try NotebookWriter.commit(message, in: notebook)
        }
    }
}

extension CoreCommands {
    /// hatch components check [<app folder>] [--diff <base>] [--all]
    /// Compares the app's controls with the role table. With --diff, only lines added since <base> (what a ticket wrote).
    static func componentCheck(_ c: Context) throws {
        let (system, _) = try loadSystem(c)
        let project = try? c.project()
        guard let folder = c.args.pos(2).map({ ($0 as NSString).expandingTildeInPath }) ?? project?.config?.repo(.app)?.localPath else {
            throw CLIError("Give the app's folder: hatch components check <folder>.")
        }
        var (inv, findings) = ComponentCheck.all(appRoot: folder, excluding: [project?.config?.components?.path].compactMap { $0 }, system: system,
                                                 areaOf: { project?.config?.area(ofFile: $0) })
        if let base = c.args.option("diff") {
            let diff = shellOutput(["git", "-C", folder, "diff", "-U0", "\(base)...HEAD", "--", "*.swift"])
            findings = ComponentCheck.inDiff(findings, diff: diff)
        }
        let cov = ComponentCheck.coverage(inv.uses, system: system)
        var lines = ["\(findings.count) finding\(findings.count == 1 ? "" : "s"). Using a role: \(cov.usingRole) of \(cov.total); already the role's look: \(cov.matching)."]
        let cap = c.args.flag("all") ? Int.max : 12
        for kind in ComponentFinding.Kind.allCases {
            let mine = findings.filter { $0.kind == kind }
            guard !mine.isEmpty else { continue }
            lines.append("\n\(kind.title) (\(mine.count))")
            if kind == .rule {
                // Per rule first: one rule can hold hundreds of lines (spacing typed in).
                let byRule = Dictionary(grouping: mine, by: { $0.role ?? "" }).sorted { $0.value.count > $1.value.count }
                lines.append("  " + byRule.map { "\(ComponentRuleKind.named($0.key)?.title ?? $0.key) \($0.value.count)" }.joined(separator: ", "))
            }
            for f in mine.prefix(cap) { lines.append("  \(f.location)  \(f.message)" + (kind == .rule ? " [\(f.role ?? "")]" : "")) }
            if mine.count > cap { lines.append("  and \(mine.count - cap) more (--all)") }
        }
        c.out.emit(["findings": .array(findings.map { f in
                        ["kind": .string(f.kind.rawValue), "file": .string(f.file), "line": .int(f.line), "role": f.role.map { .string($0) } ?? .null,
                         "message": .string(f.message)] }),
                    "usingRole": .int(cov.usingRole), "matching": .int(cov.matching), "total": .int(cov.total)],
                   text: lines.joined(separator: "\n"))
    }

    static func shellOutput(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

extension CoreCommands {
    /// hatch components generate [--out <folder>] [--product Name] [--package] [--dry-run]
    /// Writes the role modifiers and named values into the components folder (the build ticket runs this). Only the
    /// generated files are touched; custom roles stay the app's own views.
    static func componentGenerate(_ c: Context) throws {
        let (system, _) = try loadSystem(c)
        let project = try? c.project()
        let config = project?.config?.components
        guard let out = c.args.option("out").map({ ($0 as NSString).expandingTildeInPath }) ?? project?.config?.componentsFolder else {
            throw CLIError("Say where: --out <components folder>, or set the project's components folder.")
        }
        let product = c.args.option("product") ?? config?.product
        let makePackage = c.args.flag("package") && !FileManager.default.fileExists(atPath: (out as NSString).appendingPathComponent("Package.swift"))
        let files = ComponentCodegen.files(system, product: product, makePackage: makePackage)
        if c.args.flag("dry-run") {
            c.out.emit(["files": .array(files.keys.sorted().map { .string($0) })], text: files.keys.sorted().map { "would write \($0)" }.joined(separator: "\n"))
            return
        }
        try NotebookWriter.write(files, in: out)
        c.out.emit(["files": .array(files.keys.sorted().map { .string($0) })],
                   text: "Wrote \(files.count) files in \(out): \(files.keys.sorted().joined(separator: ", ")). Views use \(system.roles.first.map { $0.codeName } ?? ".buttonRole(…)") and the named values from here.")
    }
}
