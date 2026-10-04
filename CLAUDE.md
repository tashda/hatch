# Hatch

Hatch is a macOS app and a `hatch` command-line tool for tickets, AI agents and visual design decisions. It replaces Echo Labs. Read `DESIGN.md` before changing any UI. Read `SUMMARY.md` for what it is, `DECISIONS.md` for every decision (with the reason; section R changes project setup and adds the notebook), `STATUS.md` for what is built and verified, `NEXT.md` for how to continue.

## Layout

- `Package.swift`: the core (no external packages, language mode 5): `HatchCore`, `HatchGit`, `HatchSync`, `HatchAgent`, `HatchAPI`, `HatchImport`, and the `hatch` executable.
- `App/`: the SwiftUI app (macOS only). `Stage/`: `StageCore` (logic), `StageKit` and the round packages (macOS only).
- `design-page/`: source of the interactive design page and the saved answers.
- `examples/`: a sample `project.json` (it now lives in each project's notebook, not in the app). `tools/`: CLI smoke test and helper scripts.

## Rules that must hold in every change

1. **The app does the bookkeeping.** A status changes only through `HatchStore.move`, which validates against `Workflow`, logs an event, indexes the ticket and queues the GitHub sync in one transaction. Never write SQL for state outside `HatchCore`, and never let an agent edit labels, state or the database. Agents use the `hatch` commands.
2. **Hatch is the only writer** to SQLite and GitHub. The Stage app talks to Hatch over the local API (`HatchAPI`).
3. **Every suggestion carries one recommendation and its reason**; the quality gate (`ProposalValidator`) enforces it for Proposals.
4. **Cost matters.** Free local search (FTS) before any model call, compact briefs, no full test suite before merge (CI covers it).
5. iOS is out of scope. EchoSense and server testing are a separate tool.
6. Do not claim code works that has not been compiled and tested. This runs on the owner's Mac with Xcode: build and run it yourself and say what is unverified.

## Working on it

- Local Mac: `swift test` at the root and in `Stage/`; the app with `xcodebuild -project Hatch.xcodeproj -scheme Hatch -destination 'platform=macOS' build`. `tools/smoke.sh` checks the CLI end to end. Run the app and look at it. Ignore the CI mirror (`tools/mirror-to-echo.sh`) until the repo is public.
- Public API gets short comments that say why. Plain, direct style. Tests are XCTest. Commit often with focused messages.
- Model calls go through `AgentFactory.resolve(role, settings:context:)` (`HatchAgent/AgentFactory.swift`), never a runner built by hand. The owner picks a provider and model per task in Settings, Agents; the choice is the `agent_settings` setting (`AgentSettings`), API keys are in the Keychain (`app.hatch.agents`) or an environment variable. A subscription (Claude Max, ChatGPT) is used only by running the vendor's own program, never by reading its login. `hatch agents` shows and tests the setup; it does not change it.
- Names: app Hatch, vetting agent Iris, ticket types Question / Sketch / Proposal / Tweak / Bug / Theme, 16 statuses in 5 phases (see `Workflow.swift`).
