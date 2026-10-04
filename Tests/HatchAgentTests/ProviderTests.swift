import XCTest
import HatchCore
@testable import HatchAgent
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Records requests and answers with a fixed status and body.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var status = 200
    var body: [String: Any] = [:]
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) throws -> (status: Int, body: Data) {
        requests.append(request)
        return (status, try JSONSerialization.data(withJSONObject: body))
    }
    var lastBody: [String: Any] {
        guard let data = requests.last?.httpBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

struct FixedSecrets: AgentSecrets {
    var keys: [String: String]
    func storedKey(providerId: String) -> String? { keys[providerId] }
}

final class ProviderParsingTests: XCTestCase {
    func testCodexEventsGiveTheLastMessageAndSkipWarnings() throws {
        let out = """
        {"type":"thread.started","thread_id":"t"}
        {"type":"item.completed","item":{"id":"item_0","type":"error","message":"Codex is ignoring 12 unrecognized configuration settings."}}
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"first"}}
        {"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"OK"}}
        {"type":"turn.completed","usage":{"input_tokens":15743,"cached_input_tokens":12672,"output_tokens":5,"reasoning_output_tokens":2}}
        """
        let r = try CodexCLIRunner.parse(out)
        XCTAssertEqual(r.text, "OK")
        XCTAssertEqual(r.tokensIn, 15743, "cached input is already inside input_tokens")
        XCTAssertEqual(r.tokensOut, 7)
    }

    func testCodexFailureShowsTheInnerMessage() {
        let out = #"""
        {"type":"turn.started"}
        {"type":"error","message":"{\"type\":\"error\",\"status\":400,\"error\":{\"type\":\"invalid_request_error\",\"message\":\"The 'x' model is not supported when using Codex with a ChatGPT account.\"}}"}
        {"type":"turn.failed","error":{"message":"{\"type\":\"error\",\"status\":400,\"error\":{\"type\":\"invalid_request_error\",\"message\":\"The 'x' model is not supported when using Codex with a ChatGPT account.\"}}"}}
        """#
        XCTAssertThrowsError(try CodexCLIRunner.parse(out, status: 1)) { e in
            XCTAssertEqual(e as? AgentRunnerError, .failed(code: 1, stderr: "The 'x' model is not supported when using Codex with a ChatGPT account."))
        }
    }

    func testGeminiJSONWithAPreambleLine() throws {
        let out = """
        Loaded cached credentials.
        {"session_id":"s","response":"OK","stats":{"models":{"gemini-x":{"tokens":{"input":9,"prompt":12,"candidates":3,"total":17,"cached":2,"thoughts":2,"tool":0}}}}}
        """
        let r = try GeminiCLIRunner.parse(out)
        XCTAssertEqual(r.text, "OK")
        XCTAssertEqual(r.tokensIn, 12)
        XCTAssertEqual(r.tokensOut, 5)
    }

    func testGeminiError() {
        XCTAssertThrowsError(try GeminiCLIRunner.parse(#"{"error":{"type":"auth","message":"Please sign in"}}"#, status: 1)) { e in
            XCTAssertEqual(e as? AgentRunnerError, .failed(code: 1, stderr: "Please sign in"))
        }
    }

    func testGeminiLargePromptGoesToStdin() {
        let small = GeminiCLIRunner(model: "m").invocation(prompt: "hi", model: "m")
        XCTAssertEqual(small.args, ["--output-format", "json", "--model", "m", "--prompt", "hi"])
        XCTAssertNil(small.stdin)
        let big = GeminiCLIRunner().invocation(prompt: String(repeating: "x", count: 150_000), model: nil)
        XCTAssertFalse(big.args.contains("--prompt"))
        XCTAssertEqual(big.stdin?.count, 150_000)
    }

    /// The event stream recorded from opencode 2.0.20 against a local mock server.
    func testOpenCodeEvents() throws {
        let out = """
        {"type":"step_start","timestamp":1,"sessionID":"s","part":{"id":"p1","type":"step-start"}}
        {"type":"text","timestamp":2,"sessionID":"s","part":{"id":"p2","type":"text","text":"OK from mock"}}
        {"type":"step_finish","timestamp":3,"sessionID":"s","part":{"id":"p3","type":"step-finish","reason":"stop","cost":0,"tokens":{"input":12,"output":3,"reasoning":1,"cache":{"read":4,"write":0}}}}
        """
        let r = try OpenCodeRunner.parse(out)
        XCTAssertEqual(r.text, "OK from mock")
        XCTAssertEqual(r.tokensIn, 16)
        XCTAssertEqual(r.tokensOut, 4)
    }

    func testOpenCodeKeepsTheFinalStepAfterAToolStep() throws {
        let out = """
        {"type":"step_start","part":{}}
        {"type":"text","part":{"text":"Let me look."}}
        {"type":"step_finish","part":{"tokens":{"input":1,"output":1}}}
        {"type":"step_start","part":{}}
        {"type":"text","part":{"text":"Final"}}
        {"type":"step_finish","part":{"tokens":{"input":2,"output":2}}}
        """
        let r = try OpenCodeRunner.parse(out)
        XCTAssertEqual(r.text, "Final")
        XCTAssertEqual(r.tokensIn, 3)
    }

    func testOpenCodeErrorEvent() {
        let out = #"{"type":"error","timestamp":1,"sessionID":"s","error":{"type":"provider.no-route","message":"Model unavailable: mock/nope"}}"#
        XCTAssertThrowsError(try OpenCodeRunner.parse(out, status: 1)) { e in
            XCTAssertEqual(e as? AgentRunnerError, .failed(code: 1, stderr: "Model unavailable: mock/nope"))
        }
    }

    func testAnthropicRequestAndAnswer() throws {
        let t = FakeTransport()
        t.body = ["content": [["type": "text", "text": "OK"]], "stop_reason": "end_turn",
                  "usage": ["input_tokens": 10, "output_tokens": 2, "cache_read_input_tokens": 5]]
        let r = try AnthropicAPIRunner(apiKey: "k", model: "claude-haiku-4-5", effort: "low", transport: t).run(prompt: "hi", options: AgentOptions())
        XCTAssertEqual(r, AgentOutput(text: "OK", tokensIn: 15, tokensOut: 2))
        let req = try XCTUnwrap(t.requests.last)
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(t.lastBody["model"] as? String, "claude-haiku-4-5")
        XCTAssertEqual((t.lastBody["output_config"] as? [String: Any])?["effort"] as? String, "low")
    }

    func testAnthropicRefusalAndAuthErrors() {
        let t = FakeTransport()
        t.body = ["content": [], "stop_reason": "refusal", "stop_details": ["type": "refusal", "explanation": "not allowed"]]
        XCTAssertThrowsError(try AnthropicAPIRunner(apiKey: "k", model: "m", transport: t).run(prompt: "p", options: AgentOptions())) { e in
            XCTAssertTrue("\(e)".contains("not allowed"))
        }
        t.status = 401
        t.body = ["type": "error", "error": ["type": "authentication_error", "message": "invalid x-api-key"]]
        XCTAssertThrowsError(try AnthropicAPIRunner(apiKey: "k", model: "m", transport: t).run(prompt: "p", options: AgentOptions())) { e in
            XCTAssertTrue("\(e)".contains("invalid x-api-key"))
            XCTAssertTrue("\(e)".contains("Check the API key"))
        }
        XCTAssertThrowsError(try AnthropicAPIRunner(apiKey: nil, model: "m", transport: t).run(prompt: "p", options: AgentOptions())) { e in
            XCTAssertTrue("\(e)".contains("No API key"))
        }
    }

    func testOpenAICompatibleRequestAndAnswer() throws {
        let t = FakeTransport()
        t.body = ["choices": [["message": ["role": "assistant", "content": "OK"]]], "usage": ["prompt_tokens": 12, "completion_tokens": 3]]
        let r = try OpenAICompatibleRunner(baseURL: "http://localhost:11434/v1/", apiKey: nil, model: "qwen", transport: t).run(prompt: "hi", options: AgentOptions())
        XCTAssertEqual(r, AgentOutput(text: "OK", tokensIn: 12, tokensOut: 3))
        let req = try XCTUnwrap(t.requests.last)
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"), "a local server gets no key")
        XCTAssertEqual((t.lastBody["messages"] as? [[String: Any]])?.first?["content"] as? String, "hi")

        _ = try OpenAICompatibleRunner(baseURL: "https://api.openai.com/v1", apiKey: "sk", model: "m", transport: t).run(prompt: "hi", options: AgentOptions())
        XCTAssertEqual(t.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer sk")
    }

    func testOpenAIContentPartsAndBadAddress() throws {
        let t = FakeTransport()
        t.body = ["choices": [["message": ["content": [["type": "text", "text": "A"], ["type": "text", "text": "B"]]]]]]
        XCTAssertEqual(try OpenAICompatibleRunner(baseURL: "http://x/v1", apiKey: nil, model: "m", transport: t).run(prompt: "p", options: AgentOptions()).text, "AB")
        XCTAssertThrowsError(try OpenAICompatibleRunner(baseURL: "ftp://x", apiKey: nil, model: "m", transport: t).run(prompt: "p", options: AgentOptions()))
        XCTAssertThrowsError(try OpenAICompatibleRunner(baseURL: "http://x/v1", apiKey: nil, model: nil, transport: t).run(prompt: "p", options: AgentOptions())) { e in
            XCTAssertTrue("\(e)".contains("No model chosen"))
        }
    }
}

final class ProviderProgramTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("providers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func fake(_ name: String, _ body: String) throws -> String {
        let url = dir.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
    var argsFile: String { dir.appendingPathComponent("args.txt").path }
    func args() throws -> [String] { try String(contentsOfFile: argsFile).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init) }

    func testClaudeLeanArgumentsEffortAndEnvironment() throws {
        let exe = try fake("claude", #"""
        printf '%s\n' "$@" > "\#(argsFile)"
        echo "key=${ANTHROPIC_API_KEY:-none}" > "\#(dir.path)/env.txt"
        echo '{"result":"OK","usage":{"input_tokens":1,"output_tokens":1}}'
        """#)
        let env = AgentProcess.environment(removing: AgentFactory.claudeAuthVariables)
        _ = try ClaudeCLIRunner(executable: exe, model: "sonnet", lean: true, effort: "low", environment: env).run(prompt: "hi", options: AgentOptions())
        XCTAssertEqual(try args(), ["-p", "hi", "--output-format", "json", "--model", "sonnet", "--effort", "low",
                                    "--tools", "", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"])
        XCTAssertEqual(try String(contentsOfFile: dir.appendingPathComponent("env.txt").path).trimmingCharacters(in: .whitespacesAndNewlines), "key=none")
    }

    func testClaudeRetriesWithoutLeanFlagsOnAnOlderProgram() throws {
        let exe = try fake("claude", #"""
        for a in "$@"; do if [ "$a" = "--strict-mcp-config" ]; then echo "error: unknown option '--strict-mcp-config'" >&2; exit 1; fi; done
        printf '%s\n' "$@" > "\#(argsFile)"
        echo '{"result":"OK","usage":{}}'
        """#)
        let out = try ClaudeCLIRunner(executable: exe, lean: true).run(prompt: "hi", options: AgentOptions())
        XCTAssertEqual(out.text, "OK")
        XCTAssertFalse(try args().contains("--tools"))
    }

    func testClaudeErrorJSONOnFailureKeepsTheMessage() throws {
        let exe = try fake("claude", #"""
        echo '{"type":"result","is_error":true,"result":"There is an issue with the selected model (x).","usage":{}}'
        exit 1
        """#)
        XCTAssertThrowsError(try ClaudeCLIRunner(executable: exe).run(prompt: "p", options: AgentOptions())) { e in
            XCTAssertEqual(e as? AgentRunnerError, .failed(code: 1, stderr: "There is an issue with the selected model (x)."))
        }
    }

    func testCodexArgumentsAndStdin() throws {
        let exe = try fake("codex", #"""
        printf '%s\n' "$@" > "\#(argsFile)"
        cat > "\#(dir.path)/stdin.txt"
        echo '{"type":"item.completed","item":{"type":"agent_message","text":"OK"}}'
        echo '{"type":"turn.completed","usage":{"input_tokens":3,"output_tokens":1}}'
        """#)
        let out = try CodexCLIRunner(executable: exe, model: "gpt-6-luna", effort: "low").run(prompt: "the prompt", options: AgentOptions())
        XCTAssertEqual(out, AgentOutput(text: "OK", tokensIn: 3, tokensOut: 1))
        XCTAssertEqual(try args(), ["exec", "--json", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "-c", "mcp_servers={}",
                                    "--model", "gpt-6-luna", "-c", "model_reasoning_effort=\"low\"", "-"])
        XCTAssertEqual(try String(contentsOfFile: dir.appendingPathComponent("stdin.txt").path), "the prompt")
    }

    func testCodexFeatureListIsRead() {
        let list = "apps                 stable             true\nartifact             under development  false\nshell_tool  stable  true\n"
        XCTAssertEqual(CodexCLIRunner.parseFeatures(list), ["apps", "shell_tool"])
    }

    /// Lean Codex switches off only the tool features this Codex lists as on, and trims the system prompt.
    func testLeanCodexDisablesOnlyListedFeatures() throws {
        let exe = try fake("codex-lean", #"""
        if [ "$1" = "features" ]; then printf 'apps  stable  true\nshell_tool  stable  true\ngoals  stable  false\nmy_own  stable  true\n'; exit 0; fi
        printf '%s\n' "$@" > "\#(argsFile)"
        cat > /dev/null
        echo '{"type":"item.completed","item":{"type":"agent_message","text":"OK"}}'
        """#)
        _ = try CodexCLIRunner(executable: exe, lean: true).run(prompt: "p", options: AgentOptions())
        let a = try args()
        XCTAssertEqual(a.indices.filter { a[$0] == "--disable" }.map { a[$0 + 1] }, ["apps", "shell_tool"])
        XCTAssertTrue(a.contains("include_environment_context=false"))
        XCTAssertTrue(a.contains("web_search=\"disabled\""))
    }

    func testLeanCodexRetriesWithoutDisablesWhenAFeatureIsRefused() throws {
        let exe = try fake("codex-old", #"""
        if [ "$1" = "features" ]; then printf 'apps  stable  true\n'; exit 0; fi
        for a in "$@"; do if [ "$a" = "--disable" ]; then echo "Error: Unknown feature flag: apps" >&2; exit 1; fi; done
        printf '%s\n' "$@" > "\#(argsFile)"
        cat > /dev/null
        echo '{"type":"item.completed","item":{"type":"agent_message","text":"OK"}}'
        """#)
        XCTAssertEqual(try CodexCLIRunner(executable: exe, lean: true).run(prompt: "p", options: AgentOptions()).text, "OK")
        XCTAssertFalse(try args().contains("--disable"))
    }

    func testOpenCodeArguments() throws {
        let exe = try fake("opencode", #"""
        printf '%s\n' "$@" > "\#(argsFile)"
        cat > /dev/null
        echo '{"type":"text","part":{"text":"OK"}}'
        """#)
        _ = try OpenCodeRunner(executable: exe, model: "mock/small").run(prompt: "p", options: AgentOptions())
        XCTAssertEqual(try args(), ["run", "--format", "json", "--title", "Hatch", "--model", "mock/small"])
    }

    func testLocateFindsAConfiguredPathAndRejectsAMissingOne() throws {
        let exe = try fake("tool", "exit 0")
        XCTAssertEqual(AgentProcess.locate("tool", configured: exe), exe)
        XCTAssertNil(AgentProcess.locate("tool", configured: dir.appendingPathComponent("missing").path))
        XCTAssertNotNil(AgentProcess.locate("sh"))
        XCTAssertTrue(AgentProcess.searchPath().contains("/usr/bin"))
    }
}

final class AgentSettingsTests: XCTestCase {
    func testFirstRunUsesClaudeWithHaikuForIris() {
        let s = AgentSettings.initial(claudePath: "/opt/claude", detect: false)
        XCTAssertEqual(s.providers.count, 1)
        XCTAssertEqual(s.providers[0].kind, .claudeCode)
        XCTAssertEqual(s.providers[0].signIn, .account)
        XCTAssertEqual(s.providers[0].executable, "/opt/claude")
        XCTAssertEqual(s.choice(.iris), RoleChoice(providerId: AgentSettings.claudeProviderId, model: "haiku", thinking: false))
        XCTAssertEqual(s.choice(.ask), RoleChoice(providerId: AgentSettings.claudeProviderId))
    }

    func testSaveLoadAndTheOldClaudePathSetting() throws {
        let store = try HatchStore.inMemory()
        try store.setSetting(AgentSettings.legacyClaudePathKey, "/legacy/claude")
        var s = AgentSettings.load(from: store, detect: false)
        XCTAssertEqual(s.providers.first?.executable, "/legacy/claude")
        var p = ProviderPreset.all.first { $0.id == "ollama" }!.make()
        p.models = [ModelInfo(id: "qwen3", efforts: ["low"])]
        p.modelsFetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        s.update(p)
        s.setChoice(RoleChoice(providerId: p.id, model: "qwen3", effort: "low"), for: .ask)
        try s.save(to: store)
        XCTAssertEqual(AgentSettings.load(from: store, detect: false), s)
    }

    func testOlderJSONWithoutNewFieldsStillLoads() {
        let json = #"{"version":1,"providers":[{"id":"a","name":"A","kind":"codex"}],"roles":{"iris":{"providerId":"a"},"later":{"providerId":"a"}}}"#
        let s = AgentSettings.decode(json)
        XCTAssertEqual(s?.providers.first?.enabled, true)
        XCTAssertEqual(s?.providers.first?.models, [])
        XCTAssertEqual(s?.choice(.iris)?.providerId, "a")
    }

    func testRemovingAProviderClearsTheTasksThatUsedIt() {
        var s = AgentSettings.initial(detect: false)
        s.remove(AgentSettings.claudeProviderId)
        XCTAssertNil(s.choice(.iris))
        XCTAssertTrue(s.providers.isEmpty)
    }

    func testResolveSaysWhatIsWrong() {
        var s = AgentSettings.initial(detect: false)
        s.providers[0].enabled = false
        XCTAssertThrowsError(try AgentFactory.resolve(.iris, settings: s, context: AgentContext())) { e in
            XCTAssertEqual(e as? AgentSetupError, .providerOff(.iris, "Claude Code"))
            XCTAssertTrue("\(e)".contains("turned off"))
        }
        s.setChoice(.off, for: .iris)
        XCTAssertThrowsError(try AgentFactory.resolve(.iris, settings: s, context: AgentContext())) { e in
            XCTAssertEqual(e as? AgentSetupError, .noProvider(.iris))
        }
    }

    func testResolveUsesTheChoiceThenTheDefaultModelAndDropsUnsupportedEffort() throws {
        var s = AgentSettings.initial(detect: false)
        s.providers[0].models = [ModelInfo(id: "haiku", efforts: []), ModelInfo(id: "sonnet", efforts: ["low", "high"])]
        s.providers[0].defaultModel = "sonnet"
        s.setChoice(RoleChoice(providerId: AgentSettings.claudeProviderId, model: "haiku", effort: "high"), for: .iris)
        let iris = try AgentFactory.resolve(.iris, settings: s, context: AgentContext())
        XCTAssertEqual(iris.model, "haiku")
        XCTAssertNil(iris.effort, "Haiku takes no effort level")
        XCTAssertEqual(iris.label, "Claude Code · haiku")
        s.roles[AgentRole.iris.rawValue]?.thinking = false
        XCTAssertEqual(try AgentFactory.resolve(.iris, settings: s, context: AgentContext()).label, "Claude Code · haiku · no thinking")
        XCTAssertEqual((iris.runner as? ClaudeCLIRunner)?.lean, true)

        s.setChoice(RoleChoice(providerId: AgentSettings.claudeProviderId, effort: "high"), for: .ask)
        let ask = try AgentFactory.resolve(.ask, settings: s, context: AgentContext())
        XCTAssertEqual(ask.model, "sonnet")
        XCTAssertEqual(ask.effort, "high")
    }

    func testClaudeSignInDecidesTheEnvironment() throws {
        var p = AgentProvider(name: "C", kind: .claudeCode, signIn: .account)
        let secrets = FixedSecrets(keys: [p.id: "secret"])
        XCTAssertNil(try AgentFactory.claudeEnvironment(p, secrets: secrets)["ANTHROPIC_API_KEY"])
        p.signIn = .apiKey
        XCTAssertEqual(try AgentFactory.claudeEnvironment(p, secrets: secrets)["ANTHROPIC_API_KEY"], "secret")
        p.signIn = .endpoint
        p.baseURL = "https://api.z.ai/api/anthropic"
        let env = try AgentFactory.claudeEnvironment(p, secrets: secrets)
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "https://api.z.ai/api/anthropic")
        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"], "secret")
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertThrowsError(try AgentFactory.claudeEnvironment(p, secrets: FixedSecrets(keys: [:])))
        p.signIn = .account
        XCTAssertEqual(try AgentFactory.claudeEnvironment(p, secrets: secrets, thinking: false)["MAX_THINKING_TOKENS"], "0")
        setenv("MAX_THINKING_TOKENS", "8000", 1)
        defer { unsetenv("MAX_THINKING_TOKENS") }
        XCTAssertEqual(try AgentFactory.claudeEnvironment(p, secrets: secrets)["MAX_THINKING_TOKENS"], "8000", "no choice keeps the user's own setting")
        XCTAssertNil(try AgentFactory.claudeEnvironment(p, secrets: secrets, thinking: true)["MAX_THINKING_TOKENS"])
    }

    func testAPIProvidersNeedAKeyButLocalServersDoNot() throws {
        let local = ProviderPreset.all.first { $0.id == "ollama" }!.make()
        XCTAssertTrue(local.isLocal)
        XCTAssertFalse(local.usesAPIKey)
        XCTAssertNoThrow(try AgentFactory.make(local, model: "m", effort: nil, context: AgentContext(), timeout: 5))
        let openai = ProviderPreset.all.first { $0.id == "openai" }!.make()
        XCTAssertThrowsError(try AgentFactory.make(openai, model: "m", effort: nil, context: AgentContext(secrets: FixedSecrets(keys: [:])), timeout: 5))
        XCTAssertNoThrow(try AgentFactory.make(openai, model: "m", effort: nil, context: AgentContext(secrets: FixedSecrets(keys: [openai.id: "k"])), timeout: 5))
    }

    func testEnvironmentVariableKeyIsUsedWhenNoneIsStored() {
        setenv("HATCH_TEST_PROVIDER_KEY", "from-env", 1)
        defer { unsetenv("HATCH_TEST_PROVIDER_KEY") }
        let p = AgentProvider(name: "X", kind: .openAICompatible, baseURL: "https://x", apiKeyEnv: "HATCH_TEST_PROVIDER_KEY")
        XCTAssertEqual(FixedSecrets(keys: [:]).apiKey(for: p), "from-env")
        XCTAssertEqual(FixedSecrets(keys: [p.id: "stored"]).apiKey(for: p), "stored")
    }
}

final class ModelCatalogTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func write(_ name: String, _ obj: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: obj).write(to: dir.appendingPathComponent(name))
    }

    func testClaudeCodeCatalogUsesTheNewestFile() throws {
        func catalog(_ at: Double, _ models: [[String: Any]]) -> [String: Any] {
            ["version": 2, "fetchedAt": at, "catalog": ["surface": "ccd", "config": ["id": "ccd", "models": models]]]
        }
        try write("old.json", catalog(1, [["id": "claude-old", "section": "main"]]))
        try write("new.json", catalog(2, [
            ["id": "claude-sonnet-5-5", "name": "Sonnet 5.5", "section": "main",
             "thinking": ["type": "effort", "effort_options": [["id": "low"], ["id": "high", "badge": ["message": "Default"]]]]],
            ["id": "claude-haiku-4-5-20251001", "name": "Haiku 4.5", "section": "main"],
            ["id": "claude-fable-5-1", "name": "Fable 5.1", "section": "main", "badge": ["message": "Requires usage credits"]],
            ["id": "claude-opus-4-6", "name": "Opus 4.6", "section": "overflow"],
        ]))
        let list = try XCTUnwrap(ModelCatalog.claudeCodeCatalog(directory: dir))
        XCTAssertEqual(list.map(\.id), ["claude-sonnet-5-5", "claude-haiku-4-5-20251001", "claude-fable-5-1", "claude-opus-4-6"])
        XCTAssertEqual(list[0].efforts, ["low", "high"])
        XCTAssertEqual(list[0].defaultEffort, "high")
        XCTAssertEqual(list[2].note, "Requires usage credits")
        XCTAssertFalse(list[3].featured)

        let aliases = ModelCatalog.aliases(matching: list)
        XCTAssertEqual(aliases.map(\.id), ["opus", "sonnet", "haiku"])
        XCTAssertEqual(aliases[1].efforts, ["low", "high"])
        XCTAssertEqual(aliases[1].note, "Now Sonnet 5.5")
        XCTAssertEqual(aliases[2].efforts, [])
        XCTAssertNil(ModelCatalog.claudeCodeCatalog(directory: dir.appendingPathComponent("missing")))
    }

    func testCodexCatalogKeepsListedModels() throws {
        try write("models_cache.json", ["models": [
            ["slug": "gpt-6.1-sol", "display_name": "GPT-6.1-Sol", "visibility": "list", "default_reasoning_level": "low",
             "supported_reasoning_levels": [["effort": "low"], ["effort": "high"]]],
            ["slug": "gpt-reserve", "visibility": "hide"],
        ]])
        let list = try XCTUnwrap(ModelCatalog.codexCatalog(file: dir.appendingPathComponent("models_cache.json")))
        XCTAssertEqual(list.map(\.id), ["gpt-6.1-sol"])
        XCTAssertEqual(list[0].efforts, ["low", "high"])
        XCTAssertEqual(list[0].defaultEffort, "low")
    }

    func testOpenCodeAndOpenAILists() throws {
        XCTAssertEqual(ModelCatalog.openCodeModels("LiteLLM/qwen3-coder-next\nnot a model line\nmock/small\n").map(\.id), ["LiteLLM/qwen3-coder-next", "mock/small"])
        XCTAssertEqual(ModelCatalog.openAIModels(["data": [["id": "b"], ["id": "a"]]]).map(\.id), ["a", "b"])
    }

    func testFetchFromAnAPIAndRefreshKeepsTheOldListOnFailure() throws {
        let t = FakeTransport()
        t.body = ["object": "list", "data": [["id": "mock-small"], ["id": "mock-large"]]]
        var p = ProviderPreset.all.first { $0.id == "ollama" }!.make()
        let context = AgentContext(transport: t)
        ModelCatalog.refresh(&p, context: context, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(p.models.map(\.id), ["mock-large", "mock-small"])
        XCTAssertEqual(t.requests.last?.url?.absoluteString, "http://localhost:11434/v1/models")
        XCTAssertNil(p.modelsError)
        XCTAssertFalse(ModelCatalog.isStale(p, now: Date(timeIntervalSince1970: 200)))
        XCTAssertTrue(ModelCatalog.isStale(p, now: Date(timeIntervalSince1970: 100 + 25 * 3600)))

        t.status = 500
        t.body = ["error": ["message": "down"]]
        ModelCatalog.refresh(&p, context: context)
        XCTAssertEqual(p.models.count, 2, "a failed refresh keeps the list")
        XCTAssertTrue(p.modelsError?.contains("down") == true)
    }

    func testAnthropicListSendsTheKey() throws {
        let t = FakeTransport()
        t.body = ["data": [["id": "claude-sonnet-5-5", "display_name": "Claude Sonnet 5.5"]]]
        var p = ProviderPreset.all.first { $0.id == "anthropic-api" }!.make()
        let list = try ModelCatalog.fetch(p, context: AgentContext(secrets: FixedSecrets(keys: [p.id: "k"]), transport: t))
        XCTAssertEqual(list.first?.name, "Claude Sonnet 5.5")
        XCTAssertEqual(t.requests.last?.value(forHTTPHeaderField: "x-api-key"), "k")
        p.apiKeyEnv = nil
        XCTAssertThrowsError(try ModelCatalog.fetch(p, context: AgentContext(secrets: FixedSecrets(keys: [:]), transport: t)))
    }
}

final class ModelServiceTests: XCTestCase {
    func testClaudeCodeThroughAServiceIsAnOrdinaryProvider() {
        let zai = ModelService.service("zai")!
        let p = AgentProvider.claudeCode(through: zai)
        XCTAssertEqual(p.name, "Claude Code · Z.ai")
        XCTAssertEqual(p.kind, .claudeCode)
        XCTAssertEqual(p.signIn, .endpoint)
        XCTAssertEqual(p.baseURL, "https://api.z.ai/api/anthropic")
        XCTAssertEqual(p.apiKeyEnv, "ZAI_API_KEY")
        XCTAssertEqual(p.way, .program)
        let anthropic = AgentProvider.claudeCode(through: ModelService.service("anthropic")!)
        XCTAssertEqual(anthropic.signIn, .apiKey)
        XCTAssertNil(anthropic.baseURL)
    }

    func testTheThreeWays() {
        XCTAssertEqual(AgentProvider.program(.codex).way, .program)
        XCTAssertEqual(AgentProvider.api(ModelService.service("openrouter")!).way, .api)
        XCTAssertEqual(AgentProvider.api(ModelService.service("anthropic")!).kind, .anthropicAPI)
        XCTAssertEqual(AgentProvider.server(name: "Ollama", baseURL: "http://localhost:11434/v1").way, .server)
        XCTAssertEqual(AgentProvider.server(name: "Lab box", baseURL: "http://10.0.0.5:8000/v1").way, .server)
    }

    func testOnlyServicesWithAnAnthropicAPICanBackClaudeCode() {
        XCTAssertEqual(Set(ModelService.anthropicCompatible.map(\.id)), ["anthropic", "zai", "deepseek", "moonshot"])
        XCTAssertTrue(ModelService.all.allSatisfy { $0.anthropicURL != nil || $0.openAIURL != nil })
    }

    func testOlderSettingsDecodeWithoutTheNewFields() throws {
        let old = #"{"version":1,"providers":[{"id":"claude-code","name":"Claude Code","kind":"claudeCode"}],"roles":{}}"#
        let s = try XCTUnwrap(AgentSettings.decode(old))
        XCTAssertNil(s.providers[0].serviceId)
        XCTAssertNil(s.codingProviderId)
    }
}

final class TaskDefaultTests: XCTestCase {
    func testTasksFollowTheDefaultUnlessTheyChooseOrAreOff() {
        var s = AgentSettings.initial(detect: false)
        XCTAssertEqual(s.choice(.ask), RoleChoice(providerId: AgentSettings.claudeProviderId), "Ask follows the default")
        XCTAssertEqual(s.choice(.iris)?.model, "haiku", "Iris has its own")
        s.setChoice(.off, for: .ask)
        XCTAssertNil(s.choice(.ask))
        XCTAssertEqual(s.ownChoice(.ask), .off)
        s.setChoice(nil, for: .ask)
        XCTAssertEqual(s.choice(.ask), s.defaultChoice)
    }

    func testOlderSettingsGetADefault() throws {
        let old = #"{"version":1,"providers":[{"id":"claude-code","name":"Claude Code","kind":"claudeCode"}],"roles":{"iris":{"providerId":"claude-code","model":"haiku","thinking":false},"ask":{"providerId":"claude-code"}}}"#
        var s = try XCTUnwrap(AgentSettings.decode(old))
        s.normalize()
        XCTAssertNotNil(s.defaultChoice)
        XCTAssertEqual(s.roles.count, 1, "the task that matched the default now follows it")
    }

    func testAliasesBecomeVersionsAndVersionsMoveUp() {
        var s = AgentSettings.initial(detect: false)
        s.providers[0].models = ModelCatalog.claudeAliases + [
            ModelInfo(id: "claude-haiku-5-0", name: "Haiku 5"), ModelInfo(id: "claude-haiku-4-5", name: "Haiku 4.5"),
            ModelInfo(id: "claude-sonnet-5-5", name: "Sonnet 5.5"),
        ]
        let moved = s.upgradeModels()
        XCTAssertEqual(s.choice(.iris)?.model, "claude-haiku-5-0", "the alias became the newest Haiku")
        XCTAssertEqual(moved.count, 1, "Iris is the only task on an alias now; the second-opinion task is retired")

        s.setChoice(RoleChoice(providerId: AgentSettings.claudeProviderId, model: "claude-haiku-4-5"), for: .ask)
        s.providers[0].autoUpgrade = false
        s.upgradeModels()
        XCTAssertEqual(s.choice(.ask)?.model, "claude-haiku-4-5", "kept when the provider does not move tasks")
        s.providers[0].autoUpgrade = nil
        s.upgradeModels()
        XCTAssertEqual(s.choice(.ask)?.model, "claude-haiku-5-0", "moved to the newer version")
        XCTAssertEqual(AgentSettings.family(of: "claude-sonnet-5-5"), "sonnet")
        XCTAssertNil(AgentSettings.family(of: "gpt-5"))
    }
}
