# Hatch: build status

Updated 2026-10-03 after a local run on the owner's Mac with Xcode 27. "Verified" means it was compiled and its tests were run. This file is the source of truth for what exists.

## Local verification (macOS, 2026-10-03)

- `swift test` at the repo root passed. The Echo-checkout tests skipped because `HATCH_ECHO_CHECKOUT` is not set. The run emitted two harmless unnecessary-`try` warnings and one unhandled fixture warning.
- `tools/smoke.sh` passed (`smoke ok`). Its first attempt was started before the root build had produced `.build/debug/hatch`; rerunning after `swift test` passed.
- `cd Stage && swift test` passed: 73 StageCore tests.
- `cd Stage && swift build` passed, including StageKit and the toast round executable.
- `Stage/.build/debug/HatchStageToast --check` passed: 15 specimens checked, no failures.
- `xcodebuild -project Hatch.xcodeproj -scheme Hatch -destination 'platform=macOS' build` passed on Apple silicon with local ad-hoc signing. After the Ask inspector-layout and snapshot fixture changes, the app build passed again; both light/dark populated snapshot captures completed.
- The follow-up GitHub account refresh fix in `GitHubAccount.swift` and `ProjectView.swift` also passed the Xcode app build.
- Launched the app and inspected the live Desk, Tickets, Board, Previews, Specs, Decisions, Agents, Log, Project settings, and new-ticket views in light and dark appearance. Used the app's in-memory snapshot mode for populated ticket and board views. The black sidebar and banner in bitmap snapshots are capture artifacts: the live selected row is a gray native selection, and the live app displays the glass controls correctly.
- GitHub was tested with the owner's existing `gh` credential. Settings listed repositories; the picker showed `tashda/hatch-tickets` as private (lock icon), and it was selected in a disposable test database. App sync logged successful pulls at startup and after the 60-second interval, with zero waiting or failed operations. The test database was not the owner's working data.
- Fixed a stale GitHub account model in Project settings: it refreshes when the view appears and when the account changes in Settings. The app rebuilt successfully after this change.
- Created `tashda/hatch-demo-project` at the owner's request and verified it is private.
- Added a browser-based GitHub App device authorization flow to Settings. It stores the resulting credential and any refresh credential in the macOS Keychain, and refreshes expiring authorizations before API calls. Xcode app build passes with the flow present.
- Replaced the toolbar project selector's custom button/popover with a native SwiftUI menu, keeping the project name and tile in the toolbar. The app builds with the native menu.
- Added `DESIGN_REVIEW.md` and captured 24 populated Hatch views in both appearances (48 screenshots) using only an in-memory demo project. `--demo` and snapshot mode do not read the Hatch database or probe GitHub/Claude credentials. Bitmap screenshots still render the sidebar black; use the live app for Liquid Glass and sidebar appearance.
- Not visually reviewed yet: destructive and editing sheets, confirmation dialogs, and the separate Stage window. The review document names each one and gives a next step. Ask is a resizable `HSplitView` inspector column with a View-menu toggle; `.inspector(isPresented:content:)` reproduced an AppKit constraint-cycle crash and was not shipped. The latest screenshot set includes the Ask pane, the real ticket overview with Iris review data, project-add, and private-repository creation. Stage also has an in-memory `--snapshots` mode that captured 13 states per appearance; its center captures work, but the bitmap method leaves side panels partly clipped/black and attached sheets black, so those areas still need a live-window review.
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
- Echo-side changes that need the owner's agreement: a `hatch` trigger in `ci-light.yml`, a DEBUG "Preview" banner, extracting EchoDesignSystem into `tashda/echo-design-system`, the "Echo today" views into `tashda/echo-specimens`, splitting Echo Lab Tools, the Echo Labs rebuild-flake fix.
- Importing the real Echo Labs rounds into the owner's database and choosing whether to push them to GitHub (`hatch import-labs --enqueue`).
