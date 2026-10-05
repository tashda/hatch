import XCTest
import HatchCore
@testable import HatchAgent

/// Prompt to agent, for many prompts, without a model and without a build: each prompt is filed as a ticket, Iris's answer
/// (scripted from the gold answer, in several dress-ups) is applied, and the agent that would start is planned. See WORKFLOW.md.
/// `tools/iris-eval.sh` sends the same corpus to the real model.
final class IrisPipelineTests: XCTestCase {
    static let corpusURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("tools/iris-eval/corpus.json")

    private func runAll(_ cases: [IrisEvalCase], file: StaticString = #filePath, line: UInt = #line) throws {
        let world = try IrisEvalWorld()
        defer { world.tearDown() }
        var results: [IrisEvalResult] = []
        for c in cases {
            results.append(try IrisEval.run(c, in: world) { c, seeds in ScriptedRunner(text: IrisEval.scriptedReply(for: c, seedNumbers: seeds), tokensIn: 900, tokensOut: 120) })
        }
        let summary = IrisEval.summarize(results)
        XCTAssertEqual(summary.casesPassed, summary.cases, "\n" + summary.lines.joined(separator: "\n"), file: file, line: line)
        XCTAssertEqual(world.disturbedSources(), [], "an agent's workspace must never change the clone it came from", file: file, line: line)
    }

    func testTheCorpusOfWrittenPrompts() throws {
        let cases = try IrisEval.loadCorpus(Self.corpusURL)
        XCTAssertGreaterThanOrEqual(cases.count, 50)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        try runAll(cases)
    }

    func testTheCorpusCoversEveryKindOfWorkAndEveryOutcomeAndEveryProject() throws {
        let cases = try IrisEval.loadCorpus(Self.corpusURL)
        XCTAssertEqual(Set(cases.map(\.gold.path)), Set(WorkPath.allCases), "every path Iris can file has a prompt")
        XCTAssertEqual(Set(cases.map(\.gold.outcome)), Set([.ready, .asks, .split, .duplicate]))
        XCTAssertEqual(Set(cases.map(\.project)), ["echo", "web", "docs", "app"])
    }

    /// Made-up prompts from a seed, so every run is a new set of scenarios and a failure can be repeated:
    /// `HATCH_EVAL_SEED=123 HATCH_EVAL_COUNT=300 swift test --filter IrisPipelineTests`.
    func testRandomPromptsFromASeed() throws {
        let env = ProcessInfo.processInfo.environment
        let seed = UInt64(env["HATCH_EVAL_SEED"] ?? "") ?? UInt64(Date().timeIntervalSince1970) / 86_400
        let count = Int(env["HATCH_EVAL_COUNT"] ?? "") ?? 20
        print("Iris pipeline: \(count) random prompts, seed \(seed)")
        try runAll(IrisEval.generate(seed: seed, count: count))
    }

    func testTheSameSeedMakesTheSamePrompts() {
        XCTAssertEqual(IrisEval.generate(seed: 7, count: 20).map(\.title), IrisEval.generate(seed: 7, count: 20).map(\.title))
        XCTAssertNotEqual(IrisEval.generate(seed: 7, count: 20).map(\.title), IrisEval.generate(seed: 8, count: 20).map(\.title))
    }

    func testAnUnusableAnswerLeavesTheTicketCheckingAndIsReported() throws {
        let world = try IrisEvalWorld()
        defer { world.tearDown() }
        let c = IrisEvalCase(id: "x", project: "echo", title: "toast padding", body: "more", gold: .init(path: .small))
        let r = try IrisEval.run(c, in: world) { _, _ in ScriptedRunner(text: "I could not decide.") }
        XCTAssertTrue(r.checks.contains { $0.kind == .gold && !$0.ok }, "Iris being unusable shows as a gold failure")
        XCTAssertTrue(r.invariantFailures.isEmpty, "Hatch itself handled it correctly: \(r.invariantFailures)")
    }

    func testVariantsChangeTheWordsButNotTheGoldAndSkipRepeats() throws {
        let cases = try IrisEval.loadCorpus(Self.corpusURL)
        let v = IrisEval.variants(of: cases, seed: 5)
        XCTAssertGreaterThan(v.count, cases.count / 2)
        let byId = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        for one in v {
            let original = try XCTUnwrap(byId[String(one.id.split(separator: "~")[0])])
            XCTAssertEqual(one.gold.path, original.gold.path)
            XCTAssertEqual(one.gold.outcome, original.gold.outcome)
            XCTAssertNotEqual(one.title + one.body, original.title + original.body, "\(one.id) really changed")
            XCTAssertNil(one.seeds, "a prompt that repeats an earlier ticket is not varied")
        }
        XCTAssertEqual(IrisEval.variants(of: cases, seed: 5).map(\.id), v.map(\.id), "the same seed makes the same variants")
        XCTAssertEqual(Set(IrisEval.variantKinds).count, 7)
    }
}
