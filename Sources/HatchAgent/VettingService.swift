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
    /// The stronger model for tickets Iris is unsure about (decision WF-T7): run once more before the owner is asked.
    public var unsure: Escalation?

    public struct Escalation: Sendable {
        public var runner: AgentRunner
        public var label: String?
        public var provider: String?
        public var model: String?
        public init(runner: AgentRunner, label: String?, provider: String?, model: String?) {
            self.runner = runner; self.label = label; self.provider = provider; self.model = model
        }
    }

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
            var result = try IrisResult.parse(output.text)
            try store.endRun(runId, tokensIn: output.tokensIn, tokensOut: output.tokensOut, outcome: "ok")
            if !result.isSure("path"), let unsure, let better = try escalate(ticketId, prompt: prompt, options: options, with: unsure) {
                result = better
            }
            let applied = try IrisApplier.apply(result, to: ticketId, store: store)
            return .vetted(applied)
        } catch {
            // The tokens were spent even though the answer was unusable, so they are still counted.
            return try fail(ticketId, runId, tokensIn: output.tokensIn, tokensOut: output.tokensOut, outcome: "unusable", reason: "\(error)",
                            answer: Text.clip(output.text, 2000))
        }
    }

    /// Runs the same check on the stronger model. Its answer is used when it parses; otherwise the first one stands.
    private func escalate(_ ticketId: Int, prompt: String, options: AgentOptions, with e: Escalation) throws -> VettingResult? {
        let runId = try store.startRun(ticketId: ticketId, agent: IrisApplier.name, step: "unsure, vet again" + (e.label.map { " with \($0)" } ?? ""),
                                       provider: e.provider, model: e.model, role: AgentRole.irisUnsure.rawValue)
        guard let output = try? e.runner.run(prompt: prompt, options: options) else {
            try store.endRun(runId, tokensIn: 0, tokensOut: 0, outcome: "failed")
            return nil
        }
        let result = try? IrisResult.parse(output.text)
        try store.endRun(runId, tokensIn: output.tokensIn, tokensOut: output.tokensOut, outcome: result == nil ? "unusable" : "ok")
        return result
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
