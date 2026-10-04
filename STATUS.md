# Hatch: build status

Updated 2026-10-04 after a local run on the owner's Mac with Xcode 27. "Verified" means it was compiled and its tests were run. This file is the source of truth for what exists.

## Local verification (macOS, 2026-10-04): Decide and component conflicts

Decisions DC1 to DC12 and CO9 to CO13 (DECISIONS.md sections T and V).

- **Core** (`HatchCore/DecisionQueue.swift`): `pendingDecisions` is everything that is the owner's turn plus plans over the limit, quick ones first, Themes left out; `pendingDecisionCount` is the one number shown everywhere. `plan_review` (schema 3): `hatch plan` holds a Bug or a plan over the file limit for the owner and says so; `hatch plan #n --wait` waits for the answer; approve or send back with a note (the note becomes an instruction). `decidePreparedQuestion` answers a Question Hatch prepared as a draft: each move on its path is validated and logged, then it becomes a decision. Options keep what they gain and cost; `hatch options` and the quality gate (`specimen.gain-cost`) require both.
- **Components** (CO9 to CO12): the scan counts a second set's values as typed in; clashes (a name with two values) become one prepared Question with three options; a merge ticket per other set; move tickets list values equal to a name (replace) and close to one (propose in the plan).
- **App**: the Decide session (full window, one card per decision, keys ↵ 1–4 ← → N R Space Z esc, 10-second undo before Hatch acts, summary with agreement and a streak, trackpad tap and optional sound in Settings, General). Ways in: Desk card, Iris card (Iris's review cards fold into it except the ticket on screen), toolbar button with the count badge in its own group, command palette, Go menu (⇧⌘D), Components page (only component decisions). The Dock badge, the Desk row and the toolbar show the same count, read again every 5 seconds. The ticket page shows a waiting plan (Approve, Send back with a note) and a prepared Question (Choose an option). Setup offers merging other sets and adds the clash Question; Review lists what it adds; Hatch starts them names the existing sets.
- **Verified**: `swift test` (all bundles, 0 failures; 7 new tests), `tools/smoke.sh`, Xcode app build; snapshots of the Decide session (an Iris card and the prepared pick card, light and dark) and the Desk with the Decide card, the Iris card and the toolbar badge, on demo data.
- **Not verified**: the keys, the undo window and the summary in a live session (snapshots do not press keys, and driving the window by script hit the owner's own running Hatch instead, with no effect); a plan review with a real agent running `hatch plan --wait`; the Components page offers with a real app that has two sets; the trackpad tap. The Desk row label for a prepared Question still reads "Finish and submit".

## Local verification (macOS, 2026-10-04): components inside the app

Decisions CO1 to CO8 (DECISIONS.md section T).

- **Core** (`HatchCore/Components.swift`): `components` in `project.json` (folder and library); a reader for colors, fonts, sizes, views, styles and View modifiers in Swift text, and color sets in asset catalogs; a scanner that finds candidate folders in an app's clone and counts values typed into views; the check on a diff's added lines; the draft tickets that start components. No model calls.
- **CLI**: `hatch components` (the project's components as agents see them; `--all`, `--values`) and `hatch components scan <folder>` (any app, no project needed). `hatch ready` notes typed-in values on added lines (a note and a `typed-values` event, never a failure).
- **Briefs** list the components by name for work that draws (CO5).
- **App**: the Components page (Reference section, Go menu, command palette); the setup assistant's Components step (use what is found, Hatch starts them with draft tickets, separate repository, not now); Project settings' Components card (in the app with a folder menu of found candidates, separate repository, none). Hatch no longer creates a components repository.
- **Verified**: `swift test` (all bundles, 0 failures, 10 new tests), Xcode app build, snapshots of the Components page and the setup step in light and dark (sample data). Real scans: Echo (2566 Swift files, about 4 s) finds `Packages/EchoDesignSystem` (135 colors, 38 type styles, 105 sizes, 13 views and styles) and `Echo/Sources/Shared/DesignSystem`; Hatch itself finds `App/Sources/HatchApp/Components` and 556 typed-in values (mostly padding and spacing numbers); EchoSense finds nothing.
- **Not verified**: the Project settings Components card was compiled but not looked at (it sits below the snapshot's fold); Use, Start Components and Add Tickets on the live page with a real project; the setup Add with "Hatch starts them" against GitHub; the typed-values note inside a real `hatch ready`. The Stage does not import components yet.

## Local verification (macOS, 2026-10-04): agent providers and models per task

- **Providers** (`HatchAgent/Providers.swift`, `ProviderRunners.swift`, `AgentFactory.swift`, `ModelCatalog.swift`): Claude Code (Claude account, Anthropic key, or an Anthropic-compatible endpoint such as Z.ai's GLM Coding Plan), Codex, Gemini CLI, opencode, the Anthropic API, and any OpenAI-compatible API (OpenAI, OpenRouter, Z.ai, Gemini, Ollama, LM Studio). Presets for each in Settings, Agents. Providers can be switched on and off; a task set to a switched-off or removed provider fails with a message that says so, never a silent fallback.
- **Per task** (Iris, Ask): provider, model, effort (when the model has levels) and, for Claude Code models without levels, thinking on or off. Stored as the `agent_settings` setting, read by the app and the CLI. The old `claude_path` setting becomes the Claude Code provider's path. Default: Iris on Claude Code with `haiku` and thinking off, Ask on Claude Code's default model.
- **Model lists** are fetched from the provider: Claude Code's own account catalog (`~/.claude/cache/model-catalog`), Codex's `models_cache.json`, `opencode models`, `GET /v1/models` or `/models` for APIs. Aliases `opus`, `sonnet`, `haiku` are always offered and say which model they currently mean. Lists refresh when a provider is added or turned on, daily when Settings opens, and with the Refresh button; a failed refresh keeps the old list and shows the error.
- **Subscriptions**: a Claude Pro or Max plan is used by running `claude` with the account sign-in (Hatch removes `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL` from its environment). Hatch never reads a program's login. Codex uses whatever `codex login` set up (ChatGPT here).
- **Cost**: text-only calls run Claude Code without tools, MCP servers, slash commands or a saved session, in Hatch's own empty `agent-work` folder: about 3k to 7k input tokens instead of about 39k. Codex runs read-only without MCP servers (about 15k input tokens; its own system prompt). Measured on five real tickets, Iris on Haiku with thinking off took about 6 s and 250 to 475 output tokens per check, against 35 to 60 s and 3.4k to 6k with thinking on, with comparable questions.
- **Iris parser**: a wholly blank `rewrite` or `typeSuggestion` (the prompt's shape echoed back) now means "none" instead of rejecting the answer (seen once in six real Haiku runs with thinking on). An unusable answer keeps its first 2000 characters in the `vetting-failed` event.
- **CLI**: `hatch agents` (tasks and providers with sign-in status), `hatch agents test [iris|ask|<provider>] [--model m]`, `hatch agents models <provider>`. `hatch vet` uses the Iris choice. The CLI reads keys from the app's Keychain item (release builds) or the provider's environment variable; it never changes the settings.
- **Verified**: `swift test` (all bundles, 0 failures), `tools/smoke.sh`, Stage tests and build, Xcode app build. Real calls on the owner's accounts: Claude Code (Max) with Haiku, Sonnet and the default model; Codex (ChatGPT) with GPT-6-Luna; `hatch vet` end to end on a disposable database (11 checks). opencode verified against a local mock OpenAI-compatible server (event format, stdin, errors, `--title` skipping the extra naming call). The live Settings page was checked in light appearance: provider status, model fetch on switching Codex on, Iris and Codex Test buttons, choosing Codex and GPT-6-Luna for Ask (saved and read back by `hatch agents`), the GLM preset sheet.
- **Not verified**: Gemini CLI (not installed; parser written from its source types), the direct Anthropic and OpenAI-compatible APIs against real servers (tested with a fake transport only), Ollama and LM Studio, the GLM endpoint, Keychain storage in a release build (debug builds keep keys in UserDefaults, as the GitHub token does), the Ask panel itself with a non-Claude provider, dark appearance of the new page. Build agents are not started by Hatch yet, so there is no task to choose a model for them.

## Local verification (macOS, 2026-10-04): project setup and the notebook

Decisions PS1 to PS16 (DECISIONS.md section R). All compiled; `swift test` passes in every bundle; checked visually in snapshots with sample data.

- **Setup assistant** replaces the Add project sheet: GitHub, Project (repository first, name and key suggested), Tickets (shared, a default), App code (clone found or cloned), Components, Notebook, Branches (pull request by default), Agents (defaults or custom; build command suggested from the clone), Review. First run shows a welcome page and a native "Set up a project" toolbar button.
- **Notebook**: created or reused, cloned next to the app, first files written (README, AGENTS, WORKFLOW, NOW, rules, spec, decisions, specimens, project.json without this Mac's folders), the app's own AGENTS.md imported as its rules, committed and pushed. Nothing is written into the app repository. Rules are placed in the app clone and every agent worktree as AGENTS.md plus CLAUDE.md (`@AGENTS.md`), excluded via `.git/info/exclude`; a committed AGENTS.md or a hand-written file is left alone. Agents get a notebook workspace for Prepare, Build and Fix; the merge plan includes it.
- **SQLite as the working record** (migration 2): decisions keep kind, title, area, options, choice, recommendation, reason and what they replace, with an FTS index; `file_path` is the export queue. Question options (one recommended, with a reason) in `question_option`; `notebook_state` holds NOW.md's hash and the last push or error.
- **Notebook export** (app, at most every few seconds after a change; `hatch notebook export`): imports decision files the database lacks, writes missing decision files (ADR shape), keeps the kind in step, rewrites the decision index and NOW.md (only when changed), one commit, pushes what is ahead. The Spec is indexed from the notebook's `spec/`. No model call.
- **Fewer tokens**: briefs and Iris get the three most related decisions from FTS (title and one line of why), the area's rule file only when it exists, and the notebook rules only when the app commits its own AGENTS.md. Agents offer Question options with `hatch options`; the owner chooses in the ticket's banner, which records an architecture decision.
- **Decisions page**: kinds, FTS search, why, options, the notebook path; the kind can be changed.
- **Other**: debug builds keep the GitHub token in UserDefaults (no Keychain prompts; release builds use the Keychain) and are signed with team JQU2HR44D8; the app uses only the account connected in Hatch (no `gh` or `GITHUB_TOKEN` fallback); the toolbar never draws its hard background; snapshot runs use the live window and never save window state.
- **Not verified**: a real Add against GitHub (needs the Hatch installation to see the repositories and the Contents, Pull requests, Checks and Commit statuses permissions); whether a repository Hatch creates joins a "selected repositories" installation; pushes with the app's token; the Question decision sheet with a real ticket. The Spec-before-Done check across the app and notebook branches is decided (PS13) but not built.

## Local verification (macOS, 2026-10-03)

- `swift test` at the repo root passed. The Echo-checkout tests skipped because `HATCH_ECHO_CHECKOUT` is not set. The run emitted two harmless unnecessary-`try` warnings and one unhandled fixture warning.
- `tools/smoke.sh` passed (`smoke ok`). Its first attempt was started before the root build had produced `.build/debug/hatch`; rerunning after `swift test` passed.
- `cd Stage && swift test` passed: 73 StageCore tests.
- `cd Stage && swift build` passed, including StageKit and the toast round executable.
- `Stage/.build/debug/HatchStageToast --check` passed: 15 specimens checked, no failures.
- `xcodebuild -project Hatch.xcodeproj -scheme Hatch -destination 'platform=macOS' build` passed on Apple silicon with local ad-hoc signing. After the Ask inspector-layout and snapshot fixture changes, the app build passed again; both light/dark populated snapshot captures completed.
- After the Settings navigation update, `swift test` at the root passed (Echo-checkout fixture tests skipped because no checkout is configured), `tools/smoke.sh` passed, `cd Stage && swift test` passed (73 tests), `cd Stage && swift build` passed, and the Xcode Hatch app build passed. The live Settings window was checked in light appearance across Local data, GitHub, Agents, and Apps.
- Settings now uses a native `NavigationSplitView`, grouped by Workspace, Services, Automation, and Applications. Each page has a focused grouped form. The preference pages were visually checked in light appearance; dark appearance screenshots are not yet captured.
- Ask now uses SwiftUI's native `.inspector` on the NavigationSplitView detail column, with `.inspectorColumnWidth(min: 280, ideal: 320, max: 420)`. The Xcode app build passed. Live checks opened/closed the inspector using the toolbar, View menu, and shortcut; resized to both bounds and a midpoint; closed/reopened; and navigated Desk, Tickets, Board, and Previews with it open, without a crash. A snapshot run reproduced the constraint-cycle exception when the inspector modifier remained attached during rapid route changes, even with its binding false. Snapshot mode now omits the native modifier entirely and keeps a split pane just for capture; rerunning it completed all 48 images.
- The follow-up GitHub account refresh fix in `GitHubAccount.swift` and `ProjectView.swift` also passed the Xcode app build.
- Launched the app and inspected the live Desk, Tickets, Board, Previews, Specs, Decisions, Agents, Log, Project settings, and new-ticket views in light and dark appearance. Used the app's in-memory snapshot mode for populated ticket and board views. The black sidebar and banner in bitmap snapshots are capture artifacts: the live selected row is a gray native selection, and the live app displays the glass controls correctly.
- GitHub was tested with the owner's existing `gh` credential. Settings listed repositories; the picker showed `tashda/hatch-tickets` as private (lock icon), and it was selected in a disposable test database. App sync logged successful pulls at startup and after the 60-second interval, with zero waiting or failed operations. The test database was not the owner's working data.
- Fixed a stale GitHub account model in Project settings: it refreshes when the view appears and when the account changes in Settings. The app rebuilt successfully after this change.
- Created `tashda/hatch-demo-project` at the owner's request and verified it is private.
- Added a browser-based GitHub App device authorization flow to Settings. It stores the resulting credential and any refresh credential in the macOS Keychain, and refreshes expiring authorizations before API calls. Xcode app build passes with the flow present.
- Replaced the toolbar project selector's custom button/popover with a native SwiftUI menu, keeping the project name and tile in the toolbar. The app builds with the native menu.
- Added `DESIGN_REVIEW.md` and captured 24 populated Hatch views in both appearances (48 screenshots) using only an in-memory demo project. `--demo` and snapshot mode do not read the Hatch database or probe GitHub/Claude credentials. Bitmap screenshots still render the sidebar black; use the live app for Liquid Glass and sidebar appearance.
- Not visually reviewed yet: destructive and editing sheets, confirmation dialogs, and the separate Stage window. The review document names each one and gives a next step. Old `.inspector` reports omit enough details to identify their exact trigger; the same exception was reproduced and resolved in current snapshot mode, which no longer installs the native inspector. The Ask screenshot in the old snapshot set predates the native live inspector. Stage's bitmap method still leaves side panels partly clipped/black and attached sheets black, so those areas need a live-window review.
- Not verified: registering the GitHub App, installing it only on `hatch-demo-project`, entering the one-time device code in GitHub, authorizing the app, or a Hatch sync using that authorization. `App/Info.plist` still has the `HatchGitHubClientID` placeholder. The owner was asked to confirm registering and authorizing the app with Issues read/write and Metadata read, limited to the demo repo.
- Also not verified: the manual sync shortcut in a confirmed run, public-repo refusal, or end-to-end Stage launch/API flow. The prior `gh`-credential sync against the existing tickets repo does not prove the new app authorization.
- StageKit and its toast round compile, but the app-to-Stage launch and API flow have not been exercised end to end. The new Stage `--snapshots` mode builds and writes 26 images in its isolated in-memory mode.

## Environment facts

- Cloud sessions are Ubuntu 24.04 x86_64 with **no macOS and no SwiftUI/AppKit**. Swift 6.1.3 for Linux is installed with `tools/install-swift-linux.sh` (Docker Hub image layers; download.swift.org is blocked).
- A cloud session can only reach repositories attached to it. This repository is `tashda/hatch`; the others are `tashda/hatch-tickets`, `tashda/echo-specimens`, `tashda/echo-design-system` (all private, the last two still empty) and `tashda/Echo`.
- **GitHub Actions does not start any job in `tashda/hatch`** (checked 2026-10-03: even a one-line `echo` job fails in about two seconds with no runner assigned, no steps and no log). It looks like an account or repository Actions/billing setting. The same workflows run fine in `tashda/Echo` (runner label `xcode-27`). Until the setting is fixed, `tools/mirror-to-echo.sh` copies the tree to `.hatch-ci-mirror/` on the Echo working branch, where `Hatch CI (mirror)` compiles the core, the app and the Stage on macOS. This is temporary; delete `.hatch-ci-mirror/` and `.github/workflows/hatch-ci-mirror.yml` from Echo afterwards.

## Built and verified on Linux (`swift test`, 2026-10-03)

| Module | What | Tests |
|---|---|---|
| HatchCore | SQLite + FTS5, schema v1, 16-status workflow with who-may-move-what, ticket store, events, notes, questions, links, search, sync queue with coalescing and backoff, file claims (queue, stack, wake), agent queue and slots, Proposal state, decisions, agent runs | 32 |
| HatchSync | `IssueTracker`, GitHub REST client (fake transport), in-memory tracker, push/pull engine, status-drift handling, CI status, attachments | 38 |
| HatchGit | worktrees per ticket, pre-push guard, claim drift, preview builder (names the conflicting pair), merge plan and executor, promote only on green CI | 37 |
| HatchAPI | local HTTP API for the Stage with token auth, client with an outbox so picks are never lost, idempotency keys | 42 |
| HatchImport | Echo Labs importer (all 46 real pages import), Spec markdown format, Spec exporter (233 items from the real Swift specs), project bootstrap (25 suggested Echo areas) | 56 |
| HatchAgent | Proposal manifest and quality gate, brief builder, Iris contract and applier, Claude CLI runner, offer and vetting services | 129 |
| `hatch` CLI | `tools/smoke.sh` passes: init, ticket, next, take, plan (claim queue), sync (dry run), status, search, Echo Labs import | smoke |

Total: 334 package tests plus the CLI smoke test, all green.

## Compiled and tested on macOS (Swift 6.4, Xcode 27, via the CI mirror, 2026-10-03)

All core tests (a few Echo-checkout tests skip there) and the CLI smoke test pass on macOS; the macOS run takes about 4 minutes because the git and sync suites are slow there. One real macOS-only bug was found and fixed: the Stage API reset the connection on an oversized body, so the client never saw the 413.

- `App/`: the SwiftUI app (shell, Desk, Tickets, Board, ticket view, composer with Iris review, Previews, Agents, Project, Specs, Decisions, Log, Ask panel, command palette, Sketch board, Stage launcher, settings) **builds**. The local visual review above covers current empty states and in-memory sample views; there are no UI tests.
- `Stage/`: StageCore tests pass, StageKit and the toast round (`HatchStageToast`) **build**.
- Spike (decision S1/O1): a round-only incremental rebuild with StageKit cached took about **2 s** (build log: "Build complete! (1.24 sec)"). Well under the 10-15 s target.

## Design decisions applied in the app (2026-10-03, all answered on the design page)

Status = phase glyph (SF Symbol) coloured by turn plus the name (LK1). Project = title control in the toolbar with a popover (LK2, the owner's pick over the recommended sidebar card). Section switcher = glass text dock, a pull-down from six sections (LK3). Buttons = glass capsules with icon and label, one prominent first, rare actions behind More (LK10, LK11). Rules and component map: `DESIGN.md`; shared components: `App/Sources/HatchApp/Components/DesignSystem.swift`.

Seen in CI screenshots: status glyphs, dock, project control, Board cards. Not judged: Liquid Glass itself (the screenshot method does not capture glass, so buttons and the dock look flat there), and the selected sidebar row shows black in captures (thought to be a capture artifact; please check on a Mac). Still on the old look: Previews, Agents, Sketch, Iris review and Project screens use `glassProminent` now but have not been walked through for the rest of the button rules.

The App starts the Stage API at launch; the Stage can clear a verdict. `hatch-design.html` decision IDs for this round are `LK1` to `LK11`.

## Not started or open

- Wiring `StageKit` to `HatchAPI.StageClient` and launching the Stage from the app end to end.
- Measuring the round-only Stage build time (decision S1/O1).
- Echo-side changes that need the owner's agreement: a `hatch` trigger in `ci-light.yml`, a DEBUG "Preview" banner, the "Echo today" views into `tashda/echo-specimens`, splitting Echo Lab Tools, the Echo Labs rebuild-flake fix.
- Importing the real Echo Labs rounds into the owner's database and choosing whether to push them to GitHub (`hatch import-labs --enqueue`).
