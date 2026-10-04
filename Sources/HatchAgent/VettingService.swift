import Foundation
import HatchCore

public enum VettingOutcome: Equatable, Sendable {
    /// Iris answered and her result was applied.
    case vetted(IrisOutcome)
    /// The run failed or the answer was unusable. The ticket stays in Checking and an event says why.
    case failed(String)
}

/// Runs the whole check for one ticket: request, prompt, model, parse, apply, and token accounting (decision K5).
public struct VettingService {
    public let store: HatchStore
    public let runner: AgentRunner
    public var options: AgentOptions
    /// Provider and model, such as "Claude Code · haiku", recorded with the run so the Agents screen shows what ran.
    public var label: String?

    /// The provider and model behind `runner`, recorded with each run for Usage and Reports.
    public var provider: String?
    public var model: String?
    public init(store: HatchStore, runner: AgentRunner, options: AgentOptions = AgentOptions(), label: String? = nil,
                provider: String? = nil, model: String? = nil) {
        self.store = store; self.runner = runner; self.options = options; self.label = label
        self.provider = provider; self.model = model
    }

    @discardableResult
    public func vet(ticketId: Int) throws -> VettingOutcome {
        guard let t = try store.ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
        guard t.status == .checking else {
            throw StoreError.invalid("\(t.displayNumber) is \(t.status.displayName); only a Checking ticket is vetted.")
        }
        let request = try VettingRequest.build(store: store, ticketId: ticketId)
        let prompt = IrisPrompt.make(request)
        var options = self.options
        options.images = (request.screenshots ?? []).map { URL(fileURLWithPath: $0) }
        let runId = try store.startRun(ticketId: ticketId, agent: IrisApplier.name, step: label.map { "vet with \($0)" } ?? "vet",
                                       provider: provider, model: model, role: AgentRole.iris.rawValue)

        let output: AgentOutput
        do { output = try runner.run(prompt: prompt, options: options) }
        catch {
            return try fail(ticketId, runId, tokensIn: 0, tokensOut: 0, outcome: "failed", reason: "\(error)")
        }
        do {
            let result = try IrisResult.parse(output.text)
            try store.endRun(runId, tokensIn: output.tokensIn, tokensOut: output.tokensOut, outcome: "ok")
            // Only tickets she was shown can be linked or closed onto (decision IR8), and what she said is kept (IR5).
            let shown = request.similar.compactMap { try? store.resolve($0.number).id }
            var anchors: SourceAnchors?
            if let root = try store.repo(projectId: t.projectId, role: .app)?.localPath { anchors = SourceAnchors(appRoot: root) }
            let applied = try IrisApplier.apply(result, to: ticketId, store: store, candidates: shown, anchors: anchors,
                                                reply: keepReply(output.text, ticketId: ticketId))
            return .vetted(applied)
        } catch {
            // The tokens were spent even though the answer was unusable, so they are still counted.
            return try fail(ticketId, runId, tokensIn: output.tokensIn, tokensOut: output.tokensOut, outcome: "unusable", reason: "\(error)",
                            answer: Text.clip(output.text, 2000))
        }
    }

    /// Keeps her raw reply next to the database so what she said can be compared with what Hatch applied. Nil without a folder.
    private func keepReply(_ text: String, ticketId: Int) -> String? {
        guard let root = store.attachmentsRoot?.appendingPathComponent("iris-replies", isDirectory: true) else { return nil }
        let file = root.appendingPathComponent("\(ticketId)-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        } catch { return nil }
    }

    /// `answer` keeps the start of an unusable reply, so the owner can see what the model sent.
    private func fail(_ ticketId: Int, _ runId: Int, tokensIn: Int, tokensOut: Int, outcome: String, reason: String, answer: String? = nil) throws -> VettingOutcome {
        try store.endRun(runId, tokensIn: tokensIn, tokensOut: tokensOut, outcome: outcome)
        var payload: JSONValue = ["reason": .string(reason)]
        if let answer { payload = ["reason": .string(reason), "answer": .string(answer)] }
        try store.record(ticketId, actor: IrisApplier.name, kind: "vetting-failed", payload: payload)
        return .failed(reason)
    }
}
