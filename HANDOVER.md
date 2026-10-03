# Handover

> **If you are running on the owner's Mac, with Xcode:** most of section 2 is not for you. It describes the cloud sandbox the project was built in (no macOS, no Xcode), which is why a CI mirror exists. Build and run locally instead: `xcodebuild -project Hatch.xcodeproj -scheme Hatch -destination 'platform=macOS' build` (or open the project in Xcode), `swift test` at the root and in `Stage/`, `cd App && swift build`. Run the app and look at it yourself; no screenshot job is needed. You can ignore the Actions problem and the mirror until the repo is public. Section 4 step 1 becomes: build everything locally and fix the compile errors, because many SwiftUI edits were made without a compiler.

Written 2026-10-03 for whoever continues (another AI assistant or a person). Read this first, then `CLAUDE.md`, `DESIGN.md`, `STATUS.md`. It says what exists, what is verified, what is not, and what to do next, in order.

## 1. What Hatch is

A macOS app plus a `hatch` command-line tool that replaces "Echo Labs" (the owner's design-lab inside their database client, Echo). Tickets are GitHub issues in a **private** repo, mirrored into local SQLite (FTS5). Agents (Claude Code) work tickets through `hatch` commands. A vetting agent called Iris checks new tickets. Visual decisions: Sketches are HTML; Proposals open a separate Stage app (SwiftUI) that shows options beside "Echo today". Read `SUMMARY.md` (the whole idea) and `DECISIONS.md` (all 99 original decisions plus section Q, look and feel).

Owner: GitHub user `tashda`. Repos: `tashda/hatch` (this repo, private for now), `tashda/hatch-tickets` (private, tickets), `tashda/echo-specimens` and `tashda/echo-design-system` (private, still empty, only for the Echo side), `tashda/Echo` (the owner's app; do not change it without their agreement).

Owner preferences that matter: plain direct language; every suggestion gets one recommendation and its reason; ask before outward-facing or hard-to-undo actions; keep token cost low; iOS is out of scope; EchoSense and server testing are a separate tool.

## 2. Environment facts (important, easy to get wrong)

- **No macOS in the cloud container.** Swift 6.1 for Linux is installed with `tools/install-swift-linux.sh` (`export PATH=/opt/swiftroot/usr/bin:$PATH`). The core package builds and tests there: `swift test --scratch-path /tmp/b` (use a separate scratch path per parallel job). `tools/smoke.sh` checks the CLI end to end. SwiftUI code (`App/`, `Stage/Sources/StageKit`, rounds) can only be compiled on macOS.
- **GitHub Actions does not start jobs in `tashda/hatch`** (checked: even a one-line job fails with no runner). Probably an account, billing or Actions setting; public repositories get free Actions, which may fix it. Workaround in use: `tools/mirror-to-echo.sh` copies the tree to `.hatch-ci-mirror/hatch/` on the Echo branch `claude/echo-labs-features-wmwnbv`, where the workflow `Hatch CI (mirror)` (runner label `xcode-27`, Swift 6.4, Xcode 27) builds and tests everything. Delete the mirror (`.hatch-ci-mirror/`, `.github/workflows/hatch-ci-mirror.yml` in Echo, and the two files in `tools/`) once Actions work in this repo.
- The mirror job also builds the app, takes **screenshots of every screen** on made-up data (`HatchApp --snapshots <dir>`, light and dark) and pushes them to the scratch branch `hatch-screens` in `tashda/Echo` (fetch with git). Limits: Liquid Glass is not captured (glass buttons and the dock look flat), and the selected sidebar row shows as a black bar (believed to be a capture artifact; unconfirmed).
- The job `Xcode project (macOS)` generates `Hatch.xcodeproj` from `project.yml` with XcodeGen, builds it, and pushes the project to the scratch branch `hatch-xcodeproj` in Echo.

## 3. What is built

All in this repo (`main`). Linux tests: 341 core tests (16 skip because they need an Echo checkout) plus the CLI smoke test, all green at commit `3a922ee`. On macOS CI at `3b28ae8` (before the latest changes) everything was green: core tests, app build, Stage tests and build.

- **Core (SwiftPM, no external packages):** `HatchCore` (SQLite, 16-status workflow with who-may-move-what, claims, agent queue, sync queue), `HatchSync` (GitHub client, sync engine, **new:** `GitHubAccount.swift` with current user, list repos, create private repo, `prepareTicketsRepo`), `HatchGit` (worktrees, preview builder, merge plan), `HatchAgent` (briefs, Iris, quality gate, Claude runner), `HatchAPI` (local HTTP API for the Stage; fixed a macOS-only bug where an oversized body reset the connection), `HatchImport` (Echo Labs importer, Specs), `hatch` CLI.
- **App (`App/`, SwiftUI, macOS 26):** all screens (Desk, Tickets, Board, Previews, Specs, Decisions, Agents, Log, Project, ticket view with tabs, composer, Iris review, Ask panel, command palette, Sketch board, Settings). Design rules applied in `Components/DesignSystem.swift` (`HX`, `HXDock`, `HXMenuButton`, `ProjectTile`, `Status.phaseSymbol`) and `DESIGN.md`.
- **Stage (`Stage/`):** `StageCore` (logic, 73 tests), `StageKit` (SwiftUI), toast spike round. Round-only rebuild measured at about 2 seconds.
- **New this session, all unverified on macOS:**
  - GitHub account: Keychain token (`Components/GitHubAccount.swift`), Settings > GitHub section (paste token, link to create one, remove), repo picker menu, "Create private" sheet, Project settings blocks saving a public tickets repo. Core part is tested on Linux with a fake transport (`Tests/HatchSyncTests/GitHubAccountTests.swift`).
  - **The app now syncs with GitHub itself** (`AppState.startSync/syncNow`): every 60 seconds, 4 seconds after a change, and from the menu (Shift-Cmd-R). Before this only the CLI synced. The sidebar footer shows the real state.
  - The page-by-page review by four agents: fixes across all screens against `DECISIONS.md` (see section 5 for the gaps they could not close).
  - Xcode app project: `project.yml`, `App/Resources/Assets.xcassets` (generated icon, accent colour). `Hatch.xcodeproj` itself is NOT in the repo yet (see section 4).
- **Design page** (interactive, for the owner's decisions): https://claude.ai/artifact/STGbCJYZxTST7zHXzntxyN (version 8). Source in `design-page/` (`python3 build.py` rebuilds `hatch-design.html`; it can only be published from a Claude session with the Artifact tool). All decisions are answered, including LK1 to LK11, now also recorded in `DECISIONS.md`. Lesson: decision ids must be unique (an id clash once overwrote the owner's real answers; restored).

## 4. First things to do (in this order)

1. **Read the last CI run** (at the time of writing: the Xcode project job and the app build were green with all changes; the core tests and the Stage job were still running) on `tashda/Echo` (workflow `Hatch CI (mirror)`, run 37121448054 or newer on branch `claude/echo-labs-features-wmwnbv`). It covers everything committed so far. Expect possible compile errors in the app and StageKit edits made without a compiler (the agents only re-read their code). Fix them, re-run `tools/mirror-to-echo.sh`, repeat until the four jobs are green. Do not push to the mirror more than once at a time: a new push cancels the running one.
2. **The Xcode project is in the repo** (`Hatch.xcodeproj`, `App/Info.plist`), generated by XcodeGen from `project.yml` and built successfully on the macOS runner (run 37121448054, job `Xcode project (macOS)`, unsigned Debug build). The owner opens `Hatch.xcodeproj`, scheme **Hatch**, My Mac. It has not been run by a person: check signing (set a team in Xcode to run it locally), the Keychain prompt, and that the icon shows. After changing `project.yml`, regenerate with `xcodegen generate` (the CI job does this and pushes the result to the scratch branch `hatch-xcodeproj`). Reason this exists: until now the only way to run the app was the SwiftPM executable `HatchApp` (open the `App/` folder in Xcode), which has no app bundle, so notifications, the Dock name and the icon do not work. The owner expected a proper app project from the start; do not skip this.
3. **Tell the owner the app should be launched** from `Hatch.xcodeproj`, not from the root package (whose only scheme is the `hatch` command-line tool).
4. **Check the screenshots** (`hatch-screens` branch) for the screens changed by the review agents: Desk, Tickets, Board, ticket, new ticket, Previews, Agents, Specs, Decisions, Log, Project. Look for layout problems, not glass.

## 5. Open work

**From the page-by-page review (gaps the agents could not close):**
- Needs core work: ticket does not show whether the Proposal quality gate passed (H19); plan-approval UI and a stored "plan awaiting approval" (I2); Match check parts table and image comparison (I4); CI results on the ticket (I6, `SyncEngine.ciStatus` exists but nothing stores it); the Log only shows sync operations, not every action (N2); "a ticket cannot reach Done until Spec text is updated" is not enforced (L5); removing a pin in the Stage is local only (H13, no delete in core).
- Needs app work: screenshot annotation (box, arrow, note) in the composer (E3); a global quick-capture shortcut (E1); Hatch-side Stage handling: Focus button, close confirmation, "Stage closed unexpectedly" banner (S5, S7); dock badge and notifications review (B6); some screens still use plain `TextField` search instead of `.searchable`; literal radii and widths where `HX` has no token yet; `HXEmpty` and `HXCard` in `Adapters.swift` use literal sizes; the composer's six ticket types became a pull-down under the "pull-down from six sections" rule (ask the owner if they want them visible).
- Stage: overlay of two revisions cannot be built (old option code is not in the binary, H15); the round executable has a headless `--check` mode (S6) that nothing in Hatch calls yet.
- `STATUS.md` and `NEXT.md` are partly out of date; update them from this file.

**GitHub linking:** there is no OAuth sign-in. The owner pastes a **classic** token with the `repo` scope (fine-grained tokens cannot create repositories under a user account). A device-flow sign-in would need the owner to register a GitHub OAuth app and put its client id in settings. Organisation repos are supported by name (`org/name`).

**Making the repo public (the owner asked):**
- Done: no secrets or tokens in the tree or the history (checked); one anonymous commit author; owner-specific names removed from defaults, tests and the CLI (now `acme/...`, no `tashda` default); `design-page/db/` (the owner's private notes and answers) untracked and git-ignored; generic `examples/project.json`; public `README.md`.
- Still to decide with the owner: **licence** (none chosen; the README says "Not yet chosen"; Apache-2.0 or MIT are the usual picks); whether `reference/` (the owner's Echo Labs guides, 29 and 23 mentions of Echo) and the Echo-derived text in `DECISIONS.md`, `SUMMARY.md`, `NEXT.md`, `STATUS.md` may be public (is Echo itself public?); `NEXT.md` and `STATUS.md` are internal working notes and mention private repos and the CI workaround, so trim or remove them; the git **history** still contains `design-page/db/` (the owner's notes plus an opaque id) and the `Claude-Session:` trailers in commit messages. Removing those needs a history rewrite or a fresh squashed repository: ask first, it is destructive. After the repo is public, delete the CI mirror files, and check whether Actions then work.
- Tests that read real Echo Labs data run only when `HATCH_ECHO_CHECKOUT=/path/to/Echo` is set.

**Echo-side changes that need the owner's agreement (do not do them unasked):** a `hatch` branch trigger in Echo's `ci-light.yml`; a DEBUG-only "Preview" banner in Echo; extracting `EchoDesignSystem` into `tashda/echo-design-system`; moving the "Echo today" views into `tashda/echo-specimens`; splitting EchoSense and server testing into their own tool; the Echo Labs rebuild-flake fix; importing the real Echo Labs rounds with `hatch import-labs` and choosing whether to push them to GitHub (`--enqueue`). Later, remove the temporary mirror files from the Echo branch.

## 6. How to work

- Read `CLAUDE.md` rules: all status changes go through `HatchStore.move`; agents only call `hatch`; Hatch is the only writer to SQLite and GitHub; every suggestion has one recommendation and a reason; do not claim code works that was not compiled and tested, and say what is unverified.
- UI work follows `DESIGN.md` (status = glyph + name; text dock; glass capsule buttons with one prominent first; colour only for turn and problems; shared pieces in `DesignSystem.swift`). Add a row to its component map when you introduce a new kind of element.
- Commit often with focused messages. Push to `main` of `tashda/hatch`. Never rewrite history or make the repository public without the owner saying so.
