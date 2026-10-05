# Hatch: build status

Updated 2026-10-04 after a local run on the owner's Mac with Xcode 27. "Verified" means it was compiled and its tests were run. This file is the source of truth for what exists.

## Components: the engine end to end (2026-10-05, overnight, decisions DS1 to DS12)

Built on top of step 1 (the system file and templates, below):

- **Inventory** (`ComponentInventory.swift`, `hatch components inventory`): every button, menu, picker, toggle and field with its place, look and how sure the place is. Text only, no compiler: strings, comments and other platforms' `#if` branches masked, brackets matched, enclosing blocks, helpers' call sites, the app's own containers and the views' uses in other files followed; the app's own style wrappers expanded. Tuned and measured on 62 open-source macOS apps and 14 Apple samples (`tools/components-corpus/`): places 68% right on a held-out sample of 172 controls (about 80% where the place comes from structure), looks 98%. About 2 s for Hatch, 5 s for Echo.
- **Start** (`ComponentDraft.swift`, `hatch components start --template | --from-app`): from a template, or from the app, where the template's roles are the skeleton and the app's own most-used looks fill them; one question per role where looks compete, the option nearest the macOS 27 reference named. **Answer** with `hatch components questions / answer / agree`.
- **Check** (`ComponentCheck.swift`, `hatch components check [--diff base]`, and `hatch ready`): mismatches, mechanical swaps, missing roles, roles out of place, more main actions on a screen than allowed (if/else and switch branches never count together). `hatch ready` presses only findings whose place is certain; the rest are a note.
- **Code** (`ComponentCodegen.swift`, `hatch components generate [--package]`): `.buttonRole(.primary)` and the other role modifiers, `Palette`, `Typography`, `Space`, `Radius`; macOS 27 looks as they are, `if #available` fallbacks for older targets. Tests type-check the output against the macOS 27 SDK.
- **Agents**: briefs list the roles (code, purpose, places) in a few hundred tokens; Iris asks once when a ticket contradicts a role or needs a missing one.
- **Versions**: an agreed role's new look is a draft (in redesign); applying drafts starts the next baseline version.
- **Components Designer** (Stage, `--components <project>` through Hatch's local API, `--notebook`, `--components-demo`; `--app` for today's looks): In Place, Matrix, Today vs Draft, the role inspector with previous/next per setting, Agree / Apply / Discard, questions answered by choosing among drawn options; hard cases. Opened from the Components page, which also starts a system and drafts the tickets that put it in place.
- **Verified**: all `swift test` suites, `tools/smoke.sh`, Stage tests and build, Xcode app build; the Designer and the Components card looked at in snapshots (light and dark) on the Glass template and on a draft made from Hatch's own code.
- **Not built / not verified**: component questions inside a Decide session (they are answered in the Designer); DS8's offer to agree a role after 3 tickets; DESIGN.md generated from Hatch's system (DS9) until Hatch has one; the Designer opened from the live app against a real notebook (only snapshot runs and API tests); the app engine that draws the app's own compiled components. Hatch's own system was not started in its real notebook: that is the owner's click (Components page, Start from the App), because agents would follow provisional roles at once.

## Components as roles, step 1 of 6: the data (2026-10-05, decisions DS1 to DS12)

- **Core** (`HatchCore/ComponentSystem.swift`, `ComponentTemplates.swift`): the system file (`components/system.json` in the notebook) with foundations, the 11 standard places plus a system's own, roles (use when, not when, places, importance, at most per screen, recipe, custom view, variants, status, decision) and the role table lookup (element × place × importance). `problems()` checks it (unknown elements, places or settings, values a setting does not take, missing foundations, two roles on one cell, bad colors). `readme()` writes `components/README.md` for agents. Templates as data: macOS Native (20 roles) and Glass (21, from LK1 to LK11 and DR8), all provisional. Both templates add two places the standard list lacks, Page and Action row, as data (DS5). Element catalog with the settings each recipe may use (12 elements).
- **CLI**: `hatch components templates`; `hatch components roles [--template glass] [--element button] [--matrix] [--readme]` (read-only; reads the project's notebook, or a template).
- **Verified**: `swift test` (0 failures, 10 new in `ComponentSystemTests`), `tools/smoke.sh`, Xcode app build. **Not built yet**: anything that writes the system (setup, step 4), the inventory by place (step 2), the Designer (step 3), roles in Iris, briefs and `hatch ready` (step 5), code generation for `.buttonRole(...)`.

## Local verification (macOS, 2026-10-05): Decide in the look picked in the Lab (DR8)

- **Decide** (`DecideCard`): grey panel, white card 820 wide a third down, airy; eyebrow with the kind (and "1 of 2"), large title, token row; `QuestionMessage` (mark only, whole text) and `AnswerList` (keys, full text, filled Recommended badge, checkmark, "Something else…"); one question at a time; a pinned bottom bar (Later, Note, Refine or Open the Stage when they apply, then the prominent button). 1–4 and ↑ ↓ select, ↵ acts; the last question's answer goes through the undo window. Pick and plan cards use the same list (plan: Approve or Send back, Hatch's area check as the reason).
- **Ticket page and composer** (`AnswerCard`): the same message and list with an Answer button under it.
- **Progress pills** (DR9, `DecideRun.marks` in core): one per decision in its first place, coloured by outcome (amber now, teal an agent goes on, green done, outline later, faint not reached), tooltips and a legend in the ? popover. Verified: `DecideRunTests` (3, with the new marks test) and a live run (Later, then two drafts submitted: outline, teal, teal, amber; the bar keeps 11 pills).
- **Verified**: Xcode build (in a copy of the tree with `DeskView.swift` and `DeskBriefPane.swift` at HEAD, because another session's unfinished edits there do not compile); a live `--demo` run: an Iris question, two questions answered in a row with ↓ and ↵ (the second replaces the first, then the undo toast and the next card), an agent's long question, a plan, a pick with gains and costs. **Not verified**: dark mode; the ticket page's new answer card; design pictures (the Stage does not export them yet).

## Local verification (macOS, 2026-10-05): Decide Lab (DR7)

- **Decide Lab** (Go › Decide Lab, `DecideLab.swift`, its own window): the Decide card drawn with the app's controls, 31 parts with 2 to 8 options each (layout, column, position, surface, spacing, title size, header, facts, turn, question style, picture, line above, long message, answer style, recommended, selected, long answers, keys, own answer, two or more questions, how a design is shown, picture size, choosing a design, where the actions are, main button, size, Later and Note, order, hint, key, progress). Content: the real queue or seven hard cases (long answers, two questions, a design with four drawn specimens, gains and costs, an agent's long question, a plan, two short answers). The combination is kept (`lab.decide.style`) and copied with Copy for Claude. Nothing in it decides anything.
- **Verified**: Xcode build; a live `--demo` run of eight combinations (Focus, Inbox, Spotlight, Stack, Split; list, accordion, cards, tiles; gallery, large-and-filmstrip; conversation for two questions). **Not verified**: every combination (there are millions); dark mode.

## Local verification (macOS, 2026-10-04): Decide redesign (DR1 to DR6)

- **Questions as messages** (`AnswerCard`): asker's mark, grey bubble with the ask, the recommendation and the folded full text (`QuestionDigest` in core); replies as capsules, recommended first and prominent; a rounded answer field. Used in Decide, the ticket and the composer.
- **Filed by Iris** is a token row (`FiledByIrisTokens`), under the title in Decide and in Iris's review on the ticket.
- **Decide**: one white panel; the window footer stays visible; no card box; shortcuts in a ? popover (button and ? key); Later among the replies on question cards; ↵ also sends an agent's own "My recommendation: …".
- **Verified**: `QuestionDigestTests` (4), Xcode app build, a live `--demo` run (Iris question, the long agent question with tokens, the ? popover, Space to Later). The demo data has the long agent question (`--snapshots … --only decide-iris`). **Not verified**: dark mode in a live run (snapshot capture leaves out Liquid Glass), and the ticket page's look with the new answer cards.

## Local verification (macOS, 2026-10-04): leaner coding agents and build output

- **Coding agents** (`AgentLauncher.claudeArguments`): Claude Code now gets `--tools` with only the tools the agent may use, `--strict-mcp-config`, `--disable-slash-commands` and `--exclude-dynamic-system-prompt-sections`. In dontAsk mode every other tool was refused anyway; its description was still sent on every turn. Measured: about 7.7k input tokens per turn instead of about 41.6k. A real two-file edit and commit took 31.5k input tokens instead of 169.6k ($0.023 against $0.112 at API prices), with the same result.
- **Build output** (`HatchAgent/BuildLog.swift`): errors and warnings with file and line (paths shortened, duplicates and colour codes removed, compiler command lines dropped), failing XCTest and Swift Testing tests, and one test total across bundles; a failure with nothing recognised falls back to the last 30 lines. A clean xcodebuild of Hatch: 358,087 characters to 827; a passing `swift test`: 92,136 to about 120; real compile and test failures keep every error. `hatch ready` reports with it instead of the last 25 lines (which for xcodebuild are commands, not the error).
- **`hatch check`**: `hatch check #N [--build | --tests]` runs the project's commands in the ticket's workspaces and prints the digest without moving the ticket; `<command> 2>&1 | hatch check -` and `--file` digest any log. The Build and Fix briefs tell agents to compile and test through it.
- **Verified**: `swift test` (498 tests, 0 failures), `tools/smoke.sh`, Xcode app build; the digest on four real logs; the trimmed launcher arguments on a real Claude Code run (edit and commit). **Not verified**: a full Build run started by the launcher with these arguments, and whether agents follow the brief's `hatch check` lines instead of running raw build commands (those stay allowed).

## Local verification (macOS, 2026-10-04): screenshots in the tickets repository (M3)

- **Upload** (`SyncEngine.uploadAttachments`, schema 5: `remote_path`, `uploaded_sha`, `upload_error` on `attachment`): after each push, the app's sync and `hatch sync` commit the project's new screenshots to `attachments/<issue>/` on the tickets repository's branch, once the ticket has an issue. The first upload queues an issue comment in Hatch's format with the image (`![caption](https://github.com/<repo>/blob/<branch>/<path>?raw=true)`), pushed right after; a marked-up file (new checksum) replaces the file under the same name without a second comment. A failure stays on the screenshot and is logged once; the next sync tries again.
- **Where it shows**: a badge on each screenshot (uploaded, waiting, or a red failure with the error); the Log ("Screenshot uploaded to the tickets repository", paired with its comment); agents' briefs list the screenshots as files on this Mac.
- **Verified**: `swift test` (0 failures; the upload, re-upload, no second comment, failure-once test against the in-memory GitHub), `tools/smoke.sh`, Xcode app build; snapshot of a ticket with one uploaded and one waiting screenshot.
- **Not verified**: a real upload to GitHub, and whether the issue comment shows the image for people with access to the private repository.

## Local verification (macOS, 2026-10-04): screenshots, paste anywhere and mark-up (E3)

- **⌘V anywhere**: one app-wide watcher (`ScreenshotPasteCenter`). With an image on the clipboard and no text, ⌘V hands it to the newest view that takes screenshots in that window: the composer (adds a thumbnail), a ticket page or ticket window, including while typing in the Thread (attaches to the ticket), and a Decide card (attaches to its ticket and opens the note). Text on the clipboard, or a window nobody registered for, pastes as usual. Image files copied in Finder count too.
- **Mark-up** (`ScreenshotMarkupSheet`): Box, Arrow, Note, Undo; Save draws the marks into a PNG at the image's own size. Click a thumbnail in the composer, or the pencil on (or right-click) an attached screenshot, which then replaces its file and checksum (`setAttachmentSha`).
- **Verified**: Xcode app build; snapshot of the mark-up sheet with one mark of each kind; the saved file at full size (1280 × 800) with the marks in it; clipboard reading on a private pasteboard (image, image file, text only, empty).
- **Not verified**: the ⌘V watcher in the live app (it needs a real key press); dragging marks with the mouse. Screenshots still stay in the Hatch folder: uploading them to the tickets repository (M3, `SyncEngine.commitAttachment`) is not wired.

## Local verification (macOS, 2026-10-04): gate findings, Spec before To verify, CI on merged tickets

- **H19**: each offer keeps the quality gate's findings (severity, code, message) in its event; `gateResults` reads them; the Work tab shows the last result and how many offers were rejected before it.
- **L5**: `HatchStore.move` refuses To verify for built work in a project with a notebook until a passing `spec` step was recorded since the work or the fix began (`hatch ready` records it). Projects without a notebook are not checked.
- **I6**: sync reads the integration branch's check runs while a ticket is Merged (`SyncEngine.checkCI`), keeps the result per project (setting `ci.<project>`), logs a `ci` event on merged tickets when it changes; the merged banner says "CI is passing / running / failing: …", the Board card shows a red "CI failing".
- **N2**: `activityLog` merges every event with the GitHub operation that carried it (same ticket and kind, queued at or after the action; one comment per note); pulls and unpaired operations are rows of their own; Failed only keeps rows whose sync failed. The Log page shows it for the project in the title, with plain words for the newer events (plan, CI, gate, Decide, `hatch ready` steps).
- **Decide**: the session bookkeeping is `DecideRun` in core (tested); the Desk says "Choose one of N options" for Questions with options.
- **Verified**: `swift test` (0 failures, 5 new tests), `tools/smoke.sh`, `ShortcutsTests`, Xcode app build after the merge of `keyboard-and-ticket-window`; Board snapshot with the CI chip on demo data.
- **Not verified**: CI against real GitHub check runs; the Work tab's gate section with a real Proposal offer.

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

## Local verification (macOS, 2026-10-04): ticket windows and keyboard shortcuts (branch `keyboard-and-ticket-window`)

Built and tested: `swift test --filter "PageHistoryTests|ShortcutsTests"` (18 tests: history, clash rules, saved changes) and `xcodebuild -scheme Hatch build`. Run on demo data (`--demo`) and checked by driving the menus: the Go and Ticket menus list the pages and commands; Command-2 and Command-1 switch pages; Shift-Command-O opens a ticket window (ticket page only, own Back and Forward); Back and Forward in the main window.

Not checked in the running app: the key recorder on Settings › Shortcuts (the logic is tested, the keypress capture is not), Option-Return in the palette and lists, the ticket-page keys and the send-back sheet, a second ticket window for the same ticket, the Keyboard Shortcuts sheet. Command-[ and Command-] could not be tested on the Danish keyboard layout (the key equivalent for "[" shows as another character there); check them on the owner's Mac. The "Publishing changes from within view updates" warning was not reproduced; the sidebar selection now defers its change by one turn, which may or may not be the cause.

## Settings pages and Usage (2026-10-04)

Settings has three groups: Hatch (General, Notifications, Agents, Shortcuts), Connections (GitHub), This Mac (Tools, Storage, Usage), per design-review/settings-pages.html.
- **General**: appearance, open at login, the page and project on opening, the Dock badge (decisions waiting), the menu bar item (on by default, `MenuBarIcon` asset with a waiting dot), how tickets are dropped and their type, and the Decide feedback.
- **Notifications**: six "Tell me when" switches, sound, grouping, and Send a Test. The bridge reads new events, never your own moves.
- **GitHub**: the account, the app's permissions, sync with its interval (`sync_interval`), tickets repositories (default, label repair, Add), and project repositories with CI.
- **Tools**: Xcode, Git, hatch and Claude Code found on this Mac, and Open with (terminal, editor, git client) plus project apps.
- **Storage**: sizes, clean-up rules for workspaces and logs, and a daily database backup (`VACUUM INTO`, checked hourly).
- **Usage**: each run records its provider, model, task and cache reads (migration 4). The page shows tokens per day for 14 days by provider (or by model for one), this week by task and by model, and the daily limits. Above the warning the footer turns orange; above the pause limit no new agent starts until tomorrow.

Built and tested: `swift test` (0 failures), the Xcode build, and one snapshot per page in light and dark (`--only settings-<page>`, `--only menu-bar`). Not tried live: the menu bar item in the real menu bar, real notifications, the login item, GitHub against a real account (permissions, label repair, Add, Disconnect), Clean Up Now and the daily backup on real data, and the limits pausing a real agent.

## Reports (2026-10-04)

A page under Machine (⌃⌘R), tokens only, per design-review/reports.html. It has a period of 7, 14, 30 or 90 days, follows the project in the title, and can be filtered by provider; clicking a model filters by model.
- **Figures**: tokens with the change against the period before, tokens per finished ticket, runs and cache reads, and waste.
- **Chart**: tokens per day by provider (or by model for one provider); hovering a bar gives that day's numbers.
- **Breakdowns**: model, task, area and ticket, each row with a share bar. A ticket opens on click; its retries are runs that ended without handing in.
- **Waste**: stopped or retried runs, and Prepare runs whose options were sent back (every Prepare on a ticket before its latest).
- **Model against outcome**: per model, the tickets whose first handed-in Build needed no Fix.
- **Iris value**: tokens per check, tickets checked, Iris's questions answered, duplicates linked.
- **Export CSV…** saves the filtered runs, one row each.

The numbers come from `RunReport` and `reportOutcomes` in `HatchCore/Reports.swift` (tested in `ReportsTests`). Checked with demo data in light and dark snapshots (`--only reports`). Not tried: Export CSV's save panel, hovering in the live app, and real runs, which are recorded only from 2026-10-04.

## Local verification (macOS, 2026-10-04): agent providers and models per task

- **Providers** (`HatchAgent/Providers.swift`, `ProviderRunners.swift`, `AgentFactory.swift`, `ModelCatalog.swift`): Claude Code (Claude account, Anthropic key, or an Anthropic-compatible endpoint such as Z.ai's GLM Coding Plan), Codex, Gemini CLI, opencode, the Anthropic API, and any OpenAI-compatible API (OpenAI, OpenRouter, Z.ai, Gemini, Ollama, LM Studio). Presets for each in Settings, Agents. Providers can be switched on and off; a task set to a switched-off or removed provider fails with a message that says so, never a silent fallback.
- **Per task** (Iris, Ask): provider, model, effort (when the model has levels) and, for Claude Code models without levels, thinking on or off. Stored as the `agent_settings` setting, read by the app and the CLI. The old `claude_path` setting becomes the Claude Code provider's path. Default: Iris on Claude Code with `haiku` and thinking off, Ask on Claude Code's default model.
- **Model lists** are fetched from the provider: Claude Code's own account catalog (`~/.claude/cache/model-catalog`), Codex's `models_cache.json`, `opencode models`, `GET /v1/models` or `/models` for APIs. Aliases `opus`, `sonnet`, `haiku` are always offered and say which model they currently mean. Lists refresh when a provider is added or turned on, daily when Settings opens, and with the Refresh button; a failed refresh keeps the old list and shows the error.
- **Subscriptions**: a Claude Pro or Max plan is used by running `claude` with the account sign-in (Hatch removes `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL` from its environment). Hatch never reads a program's login. Codex uses whatever `codex login` set up (ChatGPT here).
- **Cost**: text-only calls run Claude Code without tools, MCP servers, slash commands or a saved session, in Hatch's own empty `agent-work` folder: about 3k to 7k input tokens instead of about 39k. Codex runs read-only without MCP servers, with its tool features switched off (only those `codex features list` reports, since Codex stops on an unknown name; it retries without them if refused) and without the permissions and environment sections: about 8.4k input tokens instead of about 15k. The rest is Codex's own system prompt and core tools; `base_instructions` does not replace it when signed in with ChatGPT. Iris on Codex (gpt-6-luna, effort low) gave valid answers on two real tickets at about 8.8k in and under 60 out. Measured on five real tickets, Iris on Haiku with thinking off took about 6 s and 250 to 475 output tokens per check, against 35 to 60 s and 3.4k to 6k with thinking on, with comparable questions.
- **Iris parser**: a wholly blank `rewrite` or `typeSuggestion` (the prompt's shape echoed back) now means "none" instead of rejecting the answer (seen once in six real Haiku runs with thinking on). An unusable answer keeps its first 2000 characters in the `vetting-failed` event.
- **CLI**: `hatch agents` (tasks and providers with sign-in status), `hatch agents test [iris|ask|<provider>] [--model m]`, `hatch agents models <provider>`. `hatch vet` uses the Iris choice. The CLI reads keys from the app's Keychain item (release builds) or the provider's environment variable; it never changes the settings.
- **Verified**: `swift test` (all bundles, 0 failures), `tools/smoke.sh`, Stage tests and build, Xcode app build. Real calls on the owner's accounts: Claude Code (Max) with Haiku, Sonnet and the default model; Codex (ChatGPT) with GPT-6-Luna; `hatch vet` end to end on a disposable database (11 checks). opencode verified against a local mock OpenAI-compatible server (event format, stdin, errors, `--title` skipping the extra naming call). The live Settings page was checked in light appearance: provider status, model fetch on switching Codex on, Iris and Codex Test buttons, choosing Codex and GPT-6-Luna for Ask (saved and read back by `hatch agents`), the GLM preset sheet.
- **Not verified**: Gemini CLI (not installed; parser written from its source types), the direct Anthropic and OpenAI-compatible APIs against real servers (tested with a fake transport only), Ollama and LM Studio, the GLM endpoint, Keychain storage in a release build (debug builds keep keys in UserDefaults, as the GitHub token does), the Ask panel itself with a non-Claude provider, dark appearance of the new page. Build agents are not started by Hatch yet, so there is no task to choose a model for them.

## Local verification (macOS, 2026-10-04): project setup and the notebook

Decisions PS1 to PS16 (DECISIONS.md section R). All compiled; `swift test` passes in every bundle; checked visually in snapshots with sample data.

- **Setup assistant** replaces the Add project sheet: GitHub, Project (repository first, its clone found or cloned, name and key suggested), Tickets (shared, a default), Components, Notebook, Branches (pull request by default), Agents (defaults or custom; build command suggested from the clone), Review. First run shows a welcome page and a native "Set up a project" toolbar button.
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

## Local verification (macOS, 2026-10-04): Components step as a verdict

The owner found the Components step confusing (a folder menu of App and Stage, four radios, "Use what is in the app" recommended for four sizes and a view). Changes: an unnamed package counts as components only with at least 6 named values including 2 colors or type styles (a package named like components needs less); the step shows one verdict ("Found X" or "No components yet") with a plain plan, and the other choices sit under "Other options"; when nothing exists and typed-in values hold near duplicates, setup adds one prepared Question ("Which close values become one?") before the tickets that act on it. **Verified**: `swift test --filter ComponentsTests` (14, 0 failures, 2 new), Xcode app build with no warnings, `hatch components scan .` no longer lists `Stage`. **Not verified**: the new step looked at on screen, and the Review page does not yet list the consolidation Question.

## Stage as its own app in the Dock

The Stage is now `Stage.app`: its own name, icon and Dock tile, separate from Hatch. The icon is a proscenium tunnel of stepped blue arches (an echo of Hatch's arch) with the number in white at the end; a running Stage draws its ticket number into its Dock icon (`StageIcon.swift`, `NSApp.applicationIconImage`, drawn locally, no model call, gone on quit). `tools/build-stage.sh` builds the bundle (the icon comes from `--render-icon`, no separate art file); Hatch's Xcode build runs it and puts the result in `Hatch.app/Contents/Helpers/Stage.app`, and `StageLauncher` uses it unless a path is set in Settings › Tools. Window title and menu say "Stage".
- **Verified**: Stage built and launched with `--demo --ticket 151`: own Dock tile with the 151 icon beside Hatch; Xcode app build succeeds, `Stage.app` is inside `Hatch.app` and `codesign --verify --deep --strict` passes; Stage tests (73) pass.
- **Not verified**: opening a Stage from the Hatch UI (Open on a Proposal) end to end; release signing and notarization of the nested app; only the toast round is bundled (a real agent-made round would be bundled with `--round`).
