# The workflow, step by step

From a typed prompt to merged work: every step, who does it, and what happens in each "if". Read this before changing the
workflow, then follow "When you change it" at the end. Decision numbers (WF-…, IR…, AG…) point to `DECISIONS.md` for the
reason. Where this file and the code disagree, the code is right: fix this file in the same change.

Code: `Sources/HatchCore/Workflow.swift` (the transition table), `Sources/HatchCore/AgentQueue.swift` (who works on what),
`Sources/HatchAgent/` (`Iris*`, `VettingService`, `AgentLauncher`, `BriefBuilder`), `Sources/HatchGit/WorkspaceManager.swift`.

## The rules that never bend

1. A status changes only through `HatchStore.move`, which checks `Workflow` (type, from, to, actor), logs an event, indexes
   the ticket and queues the GitHub sync in one transaction. Agents never set a status; they run `hatch` commands.
2. Iris never moves a ticket to another project, never sets High or Urgent priority, and asks the owner at most one question per
   check (two rounds at most).
3. The owner's own words always stay as the ticket's original; Iris's reading is a labelled section after them.
4. A source clone is never touched. Agents work in worktrees (`<root>/<ticket>/<repo>` on branch `ticket/<n>-<slug>`).

## Statuses (16, in 5 phases) and whose turn it is

| Phase | Status | Turn |
|---|---|---|
| Intake | Draft · Checking · Needs answers · Ready | you · agent (Iris) · you · Hatch |
| Exploring | Preparing · Your call · Revising | agent · you · agent |
| Building | Accepted · Building · To verify · Fixing | Hatch · agent · you · agent |
| Landed | Merged · Done | Hatch · finished |
| Off | Blocked · Parked · Dropped | Hatch · paused · paused |

Types: Question, Sketch, Proposal, Tweak, Bug, Theme (shown as Goal), Sweep. Tweak and Bug are *build first*; Question, Sketch,
Proposal and Sweep are *explore first* (a Question or Sketch ends at Your call, then Done).

## 1. Intake: a prompt becomes a ticket

1. The owner types a prompt (app composer, `hatch new`). Hatch makes a ticket, Draft → **Checking** (owner or Hatch).
2. **Iris checks it** (`VettingService.vet`, only for a Checking ticket). Hatch gathers, for free, up to 8 similar tickets, 8 Spec
   items, 5 decisions, the project's areas and components; Iris is asked once. The answer is parsed (any dress-up: plain, fenced,
   with prose around, snake_case keys) and applied by `IrisApplier.apply` in one transaction:
   - **Unusable answer or runner failure** → ticket stays Checking, a `vetting-failed` event keeps the first 2000 characters,
     tokens spent are still counted.
   - **A sure duplicate** (she names it, says `duplicateSure` and a `duplicateWhy`, *and* Hatch can see the same file or screen
     named or nearly the same words) → ticket is closed as a repeat (Dropped) and linked. **Not corroborated** → filed as it is, with
     a Related link when Hatch can say why. No question.
   - **Several unrelated things** (`path: split`, two or more parts, up to 12, one for each thing the owner asked for; a prompt
     with more is cut at 12) → parts are made at once (each Ready if it has a path, otherwise
     Checking, same project and area, linked "split from the same prompt"), the prompt's ticket is Dropped. *Undo split* puts it
     back as one ticket, Iris told not to split again; refused once a part has started.
   - **Otherwise she files**: path (→ type), area (the area that contains the screen, by name or by its Spec code; dropped if the project has no such area), verify kind, spec touches, related links
     (at most two, found by Hatch from the owner's words, never taken on her word alone), blocks/parent (only tickets she was shown).
     A long body is sent as its start and its end, cut in the middle, because the ask is often last.
     Where the owner's rules do not pick one path (IR1: a vague line gets her best reading, no question), "add 4pt" is small
     (an exactly stated change), "show me options" or "how should X look" is visual, "how should it work" is approaches, and
     question is for an answer or an explanation.
     Path → type: question→Question · visual, approaches→Proposal · bug, investigate→Bug · small, chore→Tweak · sweep→Sweep.
     An unsure path or area (`confidence` under the threshold) is filed as a guess and marked, not asked.
   - **A question** (first one only; none after two rounds) → Checking → **Needs answers**. *Low stakes* with suggestions: carries
     her first suggestion as a default and is answered with it when the wait lapses (`answerLapsedAssumptions`). *High stakes* and
     every clash with a decision or component: the ticket waits for the owner, never answered for them.
   - **A clash with an earlier decision** (WF-T6) is always asked, with two fixed answers that Hatch writes itself: *Keep the decision* →
     the ticket is closed (Dropped) with a note, and nobody builds it; *Replace the decision* → it goes ahead (Ready) with a note that it
     supersedes the decision. A free-text answer goes ahead, and the agent reads it in its brief.
   - **No question** → **Ready**.
3. **The owner answers** → the ticket leaves Needs answers when no question is open: back to **Checking** if the answer could change
   the kind of work (`rerun`), else **Ready**. A second check sees the answers and a third round asks nothing.
   An agent's question (below) returns the ticket to the status it came from.

Priority: Iris may only lower it to Normal or less. Everything she filed is shown in the "Filed by Iris" box and is the owner's to change.

## 2. Ready: which agent task waits (`HatchStore.taskKind`)

| Status | Type | Task |
|---|---|---|
| Ready | Tweak, Bug | **build** |
| Ready | Question, Sketch, Proposal, Sweep | **prepare** |
| Preparing / Accepted / Building / Revising / Fixing | any | prepare / build / build / revise / fix (work that lost its agent resumes) |
| Checking | any | vet (Iris; needs no slot) |

A ticket is picked up only when: not paused, a slot is free (`maxAgents` per project), it is not taken, and for a build no open
blocker ticket. Order: priority, then oldest update.

## 3. Starting an agent (`AgentLauncher.start`)

1. Needs the `hatch` command and a Claude Code provider for the role (Build/Fix/Prepare/Revise/Rescue are chosen in Settings, Agents;
   a non-Claude provider for coding → `notForCoding` error, nothing taken).
2. `take`: Ready → Preparing (explore) or Building (build-first); sets `taken_by`; records the task.
3. **Workspaces** (`AgentWorkspaces.make`), only for the ticket's own project and only repos with a local clone:
   - prepare, revise: specimens, notebook, app, design system
   - build, fix: app, design system, notebook
   - Where the program starts: app → design system → notebook → specimens, first one that exists (the app's CLAUDE.md loads from there).
     A project without an app clone (docs) starts in the notebook. No clone at all → `noWorkspace`, the ticket is released.
   - Each worktree starts from the repo's base-branch tip (fetched when a remote exists), on `ticket/<n>-<slug>`, with the push guard installed.
4. **Brief** (`BriefBuilder`, compact; about 700 to 1100 tokens for a quiet ticket, capped for a busy one: the latest 8 of the owner's answers, the latest notes, 3 decisions): ticket, project, owner's answers, open questions, links, related tickets, Spec lines, three
   related decisions, area rules, component roles, repos with build/test commands and workspace paths, docs, the rules for the task, the
   `hatch` commands to run next.
5. **Program arguments**: only the tools the work needs, no MCP, no slash commands, build and test commands from the repos plus
   `hatch *` and a few read-only programs; the brief goes in on stdin.
6. **Preparing a design-system change** (a role's look changed) uses its own rules: looks as recipes, no code.

## 4. While and after the agent runs

- **Hands in** (`hatch offer` for a Proposal/Sketch/Sweep, `hatch ready` for a build): Hatch moves the status, never the agent.
  - Preparing → **Your call**, after `ProposalValidator` passes (every suggestion carries one recommendation and its reason).
    A rejected hand-in changes nothing and tells the agent why.
  - Building/Fixing → **To verify**, only when `hatch ready` passes: build, the area's tests (never the whole suite), the match
    check, component roles in the diff, and the screens (CM24): when the app follows the marks contract, Hatch draws the
    workspace with its capture command and every view the ticket changed must be marked, on a captured screen, and free of
    measured problems (overlap, reaching out, cut words). The pictures stay in `evidence/<n>` and the ticket's history.
- **Needs the owner** (`hatch ask`, one `--suggest` per answer, recommendation first) → **Needs answers**; the answer returns the
  ticket to where it was (Preparing, Revising, Building, Fixing).
- **Stops without handing in**: started once more; a second stop runs once on the "Second try" model; every run failing →
  released and **Blocked** with the log tail in the thread. *Resume* starts it again. This is never put to the owner as a question.
- **Owner stops it** → released, **Blocked**.
- **Hatch stops it at a limit** → a run that has used more than the token budget, or has run past the role's time limit (3 hours for
  coding agents), is interrupted, released and **Blocked** with the reason and the log tail in the thread. It is not retried by itself;
  its work stays in the workspace and *Resume* starts it again. This is the ceiling on what a runaway Claude agent can spend. The
  budget is 1.5M by default (Settings › Usage › "Stop one run above", 0 for none) in input-token equivalents (`RunMeter`): fresh input
  and cache writes count 1, re-read context a tenth, output five times, once per model message (Claude Code writes a message's usage
  in every one of its events). A real 34-turn build is about 164k of that, so the default is about nine times a real build.

## 5. The owner's turn, and landing

- **Your call**: Accept (Proposal/Sweep → **Accepted** → Building by an agent), Send back with a note (→ **Revising**), or for a
  Question/Sketch close it as answered (→ Done).
- **To verify**: the owner checks the Preview; "needs a fix" → **Fixing** (agent, then back to To verify); Hatch merges from the
  Preview into the integration branch → **Merged**; when the integration branch reaches the base branch on green CI, Hatch moves every
  Merged ticket of the project → **Done** (`finishLanded`, WF-L3).
- **Park** (owner, from any open status) · **Drop** (owner; Hatch only while still in intake, for a sure duplicate or a split) ·
  **Block** (Hatch). A Done or Dropped ticket can be reopened by the owner to Draft; an undone split goes back to Checking.

## What each branch is covered by

| Branch | Test |
|---|---|
| Every allowed and refused move, by actor and type | `WorkflowTests` |
| Parsing every shape of Iris's answer | `IrisTests` (parse), `testASnakeCaseRepeatKeepsItsReasonSoItCanBeClosed` |
| One question, rounds, low and high stakes, defaults that lapse | `IrisTests` (`testOneQuestionAtMostGoesToTheOwner`, `testALowStakesQuestion…`, `testAHighStakesQuestion…`, `testASecondCheckSees…`) |
| Duplicates (sure, unsure, uncorroborated), splits and undo, related links | `IrisTests` |
| Clash with a decision or component | `IrisTests` (`testAClashWith…`) |
| Hand-ins and the gate | `ServiceTests`, `ValidatorTests`, `ManifestTests` |
| Screens before To verify: marked, drawn, measured | `ComponentEvidenceTests`, `ComponentTruthTests` |
| Launch, retry, stop, blocked, paused, no `hatch` command | `AgentLauncherTests` |
| Which workspaces per kind of work, branch and base, main checkout untouched | `AgentWorkspaces` in `LauncherTests`, `WorkspaceTests` |
| A stand-in agent drives the **real `hatch` command through the real launcher**: build and hand in, uncommitted work refused, an agent cannot move its own ticket, ask and resume with the answer in the next brief, a question needs a suggestion, crash then retry then Blocked, two agents in separate worktrees | `AgentLoopTests` (`Tests/HatchWorkflowTests`) |
| A Proposal end to end: gate refusal, fix, offer, send back, revise (only adding options), accept, build | `ProposalLoopTests` |
| Token budget and time limit, unlimited with 0, resume after a limit | `AgentLimitTests` |
| Every `hatch` command in every brief exists, every program in it is allowed, a brief never tells an agent to change a status, size budgets | `BriefCommandsTests`, `BriefSizeTests` |
| The whole transition table (golden file), an agent's allowed moves, a random walk over `move`, each ticket kind start to finish, the doc names every status and type | `WorkflowLifecycleTests` |
| Corrupted and extreme Iris answers never crash and never break a rule (12,000 of each, several seeds) | `IrisFuzzTests` |
| **Prompt to planned agent, 98 written prompts** (all paths, outcomes, three projects, odd inputs, other languages, text that tries to steer Iris, near-miss and closed-ticket repeats, a decision nearby but not contradicted, seven things in one prompt) | `IrisPipelineTests.testTheCorpusOfWrittenPrompts` |
| **Prompt to planned agent, random prompts** from a seed | `IrisPipelineTests.testRandomPromptsFromASeed` |
| **Iris's real judgment** on the same prompts | `tools/iris-eval.sh` (live model, costs tokens, builds nothing) |

### The pipeline bench (`IrisEval`, `Tests/HatchAgentTests/IrisPipelineTests.swift`, `tools/iris-eval/corpus.json`)

Each prompt is a ticket in a throwaway world with real git repos: `echo` (app, design system, notebook, specimens), `web` (app,
notebook), `docs` (notebook only). Iris's answer is scripted from the case's gold answer (free) or comes from the real model.
For every case it checks **invariants** (must hold for any answer; a failure is a Hatch bug) and **gold** (what a careful reader
would file; a failure is Iris being wrong or the gold arguable):

- Invariants: ticket leaves Checking; at most one question; priority never above Normal; stays in its project; owner's words kept;
  area is one the project has; exactly one agent task when Ready; a worktree for each repo the work needs and for no other
  project's; every worktree on the ticket's branch from the base tip and outside its source clone; the agent starts in the app (or
  the notebook when there is no app); the brief names ticket, project, task, repos, rules, `hatch` commands and the build command;
  sources never change.
- Gold: outcome (ready, asks, split, duplicate), kind of work, area, next task.

Gold where the owner's rules do not pick one answer lists `alsoPaths` (accepted alternatives). A vague prompt is *not* a question
case (IR1); the real asks are a ticket that undoes an earlier decision.

Run: `swift test --filter IrisPipelineTests` (about 4 minutes; each case makes real worktrees). More random prompts:
`HATCH_EVAL_SEED=123 HATCH_EVAL_COUNT=300 swift test --filter IrisPipelineTests/testRandomPromptsFromASeed`. A failing random run
prints its seed. Live: `tools/iris-eval.sh [--only id,id] [--limit n] [--random n --seed s [--random-only]] [--model m] [--min 0.9] [--verbose]`
(`--verbose` prints her raw reply for every miss; a full run is 98 prompts, about 17 minutes and 9k input tokens a prompt on Codex).

## When you change the workflow

0. If a status move changes, `WorkflowLifecycleTests.testTheTransitionTableMatchesTheGoldenFile` fails and lists the difference: that is
   your list of what this document must say differently. Regenerate the golden file only after this document is updated.
1. Change `Workflow.swift` (or the applier, queue or launcher) and its tests.
2. Find the step above that changed; update it and the "covered by" row in the same commit.
3. Add or change a corpus case in `tools/iris-eval/corpus.json` for the new branch (gold answer = what a careful reader would
   file) and run `IrisPipelineTests`. If the scripted answer shape changes, update `IrisEval.scriptedReply`.
4. If Iris's prompt changed, run `tools/iris-eval.sh` before and after; do not ship a lower gold score without a reason in `DECISIONS.md`.
5. Record the decision in `DECISIONS.md` and the verification in `STATUS.md`.
