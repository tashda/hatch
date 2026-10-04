import Foundation
import HatchCore
import HatchAgent

/// `hatch agents`: which provider and model each task uses, as chosen in the app's Settings. Read-only on purpose:
/// an agent running `hatch` must not change which model checks its own work.
enum AgentSetupCommands {
    static let all: [String: Handler] = ["agents": agents]

    /// Keys from the Keychain item the app saves (release builds), else the provider's environment variable.
    struct CLISecrets: AgentSecrets {
        func storedKey(providerId: String) -> String? {
            #if os(macOS)
            guard let r = try? AgentProcess.spawn("/usr/bin/security", ["find-generic-password", "-s", "app.hatch.agents", "-a", providerId, "-w"],
                                                  stdin: nil, directory: nil, environment: nil, timeout: 20), r.status == 0 else { return nil }
            let key = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : key
            #else
            return nil
            #endif
        }
    }

    static func context() -> AgentContext {
        let dir = URL(fileURLWithPath: Home.directory).appendingPathComponent("agent-work", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AgentContext(secrets: CLISecrets(), workingDirectory: dir)
    }

    static func provider(_ c: Context, _ settings: AgentSettings, _ ref: String) throws -> AgentProvider {
        let lower = ref.lowercased()
        if let p = settings.providers.first(where: { $0.id == ref || $0.name.lowercased() == lower }) { return p }
        let prefixed = settings.providers.filter { $0.name.lowercased().hasPrefix(lower) || $0.id.hasPrefix(lower) }
        if prefixed.count == 1 { return prefixed[0] }
        throw CLIError("No provider '\(ref)'. Known: \(settings.providers.map(\.name).joined(separator: ", ")).")
    }

    // hatch agents                      -> each task's provider and model, and every provider with its status
    // hatch agents test [iris|ask|<provider>] [--model m]   -> one tiny real call (costs a few tokens)
    // hatch agents models <provider>    -> the provider's current model list, fetched now
    static func agents(_ c: Context) throws {
        let settings = AgentSettings.load(from: c.store)
        let ctx = context()
        switch c.args.pos(1) {
        case nil, "list":
            var lines = ["Tasks:"]
            var tasks: [JSONValue] = []
            for role in AgentRole.allCases {
                let choice = settings.choice(role)
                let p = choice.flatMap { settings.provider($0.providerId) }
                let model = choice?.model ?? p?.defaultModel
                let state = p == nil ? "not set" : (p!.enabled ? "" : "  (provider is off)")
                let extras = (choice?.effort.map { " · effort \($0)" } ?? "") + (choice?.thinking == false ? " · no thinking" : "")
                lines.append("  \(role.title.padding(toLength: 16, withPad: " ", startingAt: 0)) \(p?.name ?? "-") · \(model ?? "program default")\(extras)\(state)")
                tasks.append(["role": .string(role.rawValue), "provider": p.map { .string($0.name) } ?? .null,
                              "model": model.map { .string($0) } ?? .null, "effort": choice?.effort.map { .string($0) } ?? .null,
                              "thinking": choice?.thinking.map { .bool($0) } ?? .null, "enabled": .bool(p?.enabled ?? false)])
            }
            lines.append("Providers:")
            var providers: [JSONValue] = []
            for p in settings.providers {
                let status = ProviderCheck.status(p, context: ctx)
                lines.append("  \(p.enabled ? "on " : "off") \(p.name) (\(p.kind.displayName)): \(status.summary) \(p.models.count) model(s) listed.")
                providers.append(["id": .string(p.id), "name": .string(p.name), "kind": .string(p.kind.rawValue), "enabled": .bool(p.enabled),
                                  "ready": .bool(status.ready), "status": .string(status.summary), "models": .int(p.models.count)])
            }
            c.out.emit(["tasks": .array(tasks), "providers": .array(providers)], text: lines.joined(separator: "\n"))
        case "test":
            let ref = c.args.pos(2) ?? AgentRole.iris.rawValue
            let started = Date()
            let out: AgentOutput, label: String
            if let role = AgentRole(rawValue: ref) {
                var resolved = try AgentFactory.resolve(role, settings: settings, context: ctx)
                if let m = c.args.option("model") {
                    resolved = try AgentFactory.make(resolved.provider, model: m, effort: resolved.effort, thinking: resolved.thinking, context: ctx, timeout: 120)
                }
                out = try resolved.runner.run(prompt: "Reply with exactly: OK", options: AgentOptions())
                label = "\(role.title) (\(resolved.label))"
            } else {
                let p = try provider(c, settings, ref)
                let r = try ProviderCheck.test(p, model: c.args.option("model"), context: ctx)
                out = AgentOutput(text: r.text, tokensIn: r.tokensIn, tokensOut: r.tokensOut)
                label = r.model.map { "\(p.name) · \($0)" } ?? p.name
            }
            let seconds = Date().timeIntervalSince(started)
            c.out.emit(["answer": .string(out.text), "tokensIn": .int(out.tokensIn), "tokensOut": .int(out.tokensOut), "seconds": .int(Int(seconds.rounded()))],
                       text: "\(label) answered \"\(out.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))\" in \(String(format: "%.1f", seconds)) s, \(out.tokensIn) tokens in, \(out.tokensOut) out.")
        case "models":
            guard let ref = c.args.pos(2) else { throw CLIError("Usage: hatch agents models <provider>") }
            let p = try provider(c, settings, ref)
            let models = try ModelCatalog.fetch(p, context: ctx)
            let text = models.map { m in
                var line = "  \(m.id)"
                if let n = m.name, n != m.id { line += "  \(n)" }
                if !m.efforts.isEmpty { line += "  effort: \(m.efforts.joined(separator: ", "))" }
                if let note = m.note { line += "  (\(note))" }
                return line
            }.joined(separator: "\n")
            c.out.emit(.array(models.map { .string($0.id) }), text: "\(p.name): \(models.count) model(s)\n" + text)
        default:
            throw CLIError("Usage: hatch agents [list] | hatch agents test [iris|ask|<provider>] [--model m] | hatch agents models <provider>")
        }
    }
}
