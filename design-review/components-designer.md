# Components: roles, a baseline and the Components Designer (proposal, ids DS1 to DS12)

Status: **answered 2026-10-05: every recommendation**, recorded in `DECISIONS.md` section AC. Written after the owner's feedback below. Where it
conflicts with CO1 to CO13 or SC1 to SC5, this wins. ★ marks the recommendation, and the chosen option.

## What the owner asked for

- Hatch builds and keeps a real design system for an app. It is one of Hatch's key features, so it must be done by
  Hatch's own process, also for Hatch itself (no hand-written rules that skip the feature).
- A button is not just a button. Rules need context: which button, in which place, for what.
- Three ways in: from scratch with templates (such as macOS native), during setup of an existing app, or later.
- When new features are built they respect the components, and Hatch asks when a prompt and the components disagree.
- Redesign must still be possible while using the app's components.
- A dedicated Components Designer, structured enough for many elements. The Decide Lab works better than the Stage
  today but will not scale; the Stage is ugly and confusing.
- It must not burn tokens.

## What goes wrong today (found in the code)

- The scanner (`HatchCore/Components.swift`) finds **what exists**: colors, fonts, sizes, views and styles by name. It
  knows nothing about **when** to use them. Briefs and Iris get a list of names (CO5, WF-T8).
- Hatch's own components are mostly colors (`Theme.swift`, `HX` in `DesignSystem.swift`). The rules for buttons live
  only as prose in `DESIGN.md`. In code, 240 places pick a button style inline across 7 styles, and about 540 lines type
  in a padding, font size or radius.
- So "Use what is in the app" adopted the app as it is, inconsistencies included. There is no agreed baseline, which
  means nothing can be called a mismatch, which means Hatch cannot ask about one. Agents copy the nearest screen.

## The model: elements, places, roles

A design system in Hatch is four layers. Every entry says **when to use it and when not to**.

| Layer | What it is | Examples |
|---|---|---|
| Foundations | Values named by meaning, not by number | `color.surface`, `color.turn.you`, `text.cardTitle`, `space.rowInset`, `radius.card`, `material.floating` |
| Elements | The kinds of control or block | Button, Menu, Text field, Toggle, List row, Card, Sheet, Badge, Empty state |
| Places | Where an element can sit; a fixed, shared list for macOS apps | Toolbar, Sheet footer, Bottom bar, List row, Card, Inspector, Popover, Form, Empty state, Context menu, Alert |
| Roles | One element in a place, for one purpose: the unit the rules are made of | `button.primary` "the one main action of a screen or sheet"; `button.inRow` "actions inside a row, card or toast, shown on hover or selection" |

A role holds:

- **Purpose** ("use when") and **avoid** ("not when"), one line each.
- **Places** it is allowed in, and how many per screen (`button.primary`: at most one).
- **Recipe**: the look as parameters of native controls (style, size, label shape, material, tint, shape). A role whose
  look cannot be said in parameters is **custom** and points at its view in the components package.
- **Variants** with a reason each (`button.primary.compact` for popovers).
- **Code name**: how code uses it, for example `.buttonStyle(.role(.primary))` or `AppButton(.primary)`.
- **Status**: provisional, agreed, or in redesign. Plus the decision that set it.

The **role table** is the lookup the whole feature runs on: element × place × importance → role. "A delete button in a
row" resolves to `button.inRow` with the destructive rule. An empty cell means "not decided yet". A usage that contradicts
a cell is a mismatch. This is what turns "a button is not just a button" into something Hatch can check for free.

## Where the truth lives

- **The rules** live in the notebook as data: `components/system.json` (foundations, roles, places, status, version)
  and a generated, readable `components/README.md`, so any agent can use them without Hatch (PS9). Hatch is the only
  writer (rule 2). Agents propose changes with `hatch components propose`, which becomes a question for the owner.
- **The look** lives in the app's components package as code. For recipe roles Hatch **generates** the code from the
  recipe with templates: no model call. Custom roles are written by an agent on a normal ticket.
- The scanner checks the two stay in step: every role has code, and the code still matches its recipe.
- For Hatch, `DESIGN.md`'s component map and button table become generated from the system file, so they can no longer
  drift from the code.

## Where it is done: the Components Designer

One place for everything about the design system. It replaces the Decide Lab once it can do what the Lab does, and
the Stage moves onto the same layout later (SL1), so there is one way of judging looks.

### Two drawing engines, so it costs no tokens

| Engine | What it draws | Cost |
|---|---|---|
| Recipe engine (prebuilt in StageKit) | Any recipe role with real SwiftUI and AppKit controls, in every place, light and dark, on sample screens and hard cases | Free and instant: switching a candidate changes parameters, nothing is generated or compiled |
| App engine (compiled once per base commit, cached, about 2 s incremental) | The app's real components package: "today", custom roles, and a check that generated code looks like its recipe | Build time only, no tokens |

No model call is made while the owner looks, switches or picks. Candidates come from templates, from the app's own
usages, and from the recipe parameters.

### The window

```
┌───────────────┬──────────────────────────────────────────────┬────────────────────┐
│ SYSTEM  v1 ▾  │  Buttons            [In place] [Matrix] [Today vs Draft]      │ button.inRow      │
│               │                                              │                    │
│ Foundations   │  ┌ Toolbar ──────────────────────────────┐   │ Use when           │
│   Color       │  │  [⌘] [⎘] [⋯]                          │   │ Actions inside a   │
│   Type        │  └───────────────────────────────────────┘   │ row, card or toast │
│   Spacing     │  ┌ List row ─────────────────────────────┐   │ Not when           │
│   Radius      │  │  Fix the login bug      (Open) (Park) │ ◀ │ The main action    │
│   Materials   │  └───────────────────────────────────────┘   │                    │
│ Elements      │  ┌ Sheet footer ─────────────────────────┐   │ Look  ‹ bordered › │
│ ● Buttons   3 │  │                     Cancel   (Save)   │   │ Size  ‹ small ›    │
│ ○ Menus       │  └───────────────────────────────────────┘   │ Label ‹ text ›     │
│ ○ Rows        │  ┌ Bottom bar ───────────────────────────┐   │ Show  ‹ on hover › │
│ ○ Cards       │  │  (Later) (Note)          ((Answer))   │   │                    │
│ ○ Sheets      │  └───────────────────────────────────────┘   │ Used 29× today     │
│ Patterns      │                                              │ 3 other looks →    │
│   Settings    │  Hard cases: long label · disabled · busy ·  │ Decision #12       │
│   Decision    │  destructive · dark · large text             │                    │
├───────────────┴──────────────────────────────────────────────┴────────────────────┤
│  3 to decide in Buttons   Rows: 3 looks in use, pick one ›        (Later) ((Decide)) │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

- **Left**: the system as a list. Each element shows its state: agreed, provisional, something to decide (with a
  count), or in redesign. Many elements stay manageable because you work on one element at a time.
- **Centre, In place** (default): the selected element drawn **inside each place it is used**, never floating alone.
  Clicking one selects its role. Hard cases are one click away (the Lab's best part).
- **Centre, Matrix**: places across, importance down, a role in each cell. Empty cells are undecided. This is the role
  table, and it answers "which button where" at a glance.
- **Centre, Today vs Draft**: the app's real components (app engine) beside the draft (recipe engine).
- **Right**: the selected role. Use when, not when, the recipe as parameters stepped with ‹ › like the Lab, variants,
  how often and where it is used today, the decision behind it.
- **Bottom bar**: the questions open for this element, answered in place in the Decide style (one recommendation and
  its reason), or Later. The same questions also appear in Decide sessions.

## The workflows

### A. A new app, from a template

1. Setup, Components step: **Start from a template**. Shipped as data in Hatch, no tokens. First set: macOS Native
   (Apple's defaults and the HIG), Glass (like Hatch: Liquid Glass capsules, one prominent action), Compact (a dense pro
   tool: small controls, tight spacing). Each is a complete system: foundations, about 12 elements, the role table.
2. The Designer opens on the template with sample screens (list and detail, settings form, sheet, empty state). A few
   top-level knobs (accent, density, corner style, glass or plain) cascade into every role.
3. **Use this** makes baseline v1. Every role is provisional. Hatch adds a draft Tweak that creates the components
   package with the generated role code (no agent needed).
4. Missing roles are asked the first time a ticket needs one ("the first slider: which look?"), with two or three
   candidates drawn by the recipe engine. Nothing is decided in the abstract.
5. A provisional role becomes agreed when the owner confirms it, or Hatch offers that in Decide once it has been used on
   a few built tickets without change.

### B. An existing app, during setup

1. **Inventory**, free. The scanner reads foundations as today, and now also every use of an element **with its place**:
   inside `.toolbar {}`, a `.sheet`, a view named `…Row` or inside `List`/`ForEach`, `.safeAreaInset(edge: .bottom)`, a
   `.contextMenu`, an `.alert`. A use whose place cannot be told is listed as unknown. Each use gets a signature (style,
   size, label shape, tint, role), and uses are grouped by place and signature.
2. **Pick a starting point**: match the app as it is (★ for an app that already ships), or a template that the app
   moves towards.
3. **Draft roles**, free. Each place gets the most-used signature as the recommendation; the others become choices.
   When a cluster matches a template role, the template's name and "use when" text are used. Only clusters that
   match nothing need words written: one model call for all of them, with the cluster table as input (a few thousand
   tokens), shown with its cost before it runs, and skippable.
4. **Review in the Designer**, one element at a time. Each question shows today's looks in place with counts: "Rows: 3
   looks in use (bordered small 29, borderless 22, plain 55)". Answers: make it the role (recommended), keep it as a
   variant with a reason, or fold it into the role. The owner can stop at any point; what is left stays provisional.
5. **Result**: baseline v1 as a decision, the system file in the notebook, and a draft Theme "Put the components in
   place": move or create the package (CO8), the generated role code, and one Tweak per area that swaps inline styles
   for roles. Exact matches are swapped without asking because nothing visible changes (CO12); the rest is agent work
   reviewed as usual.
6. The Components page shows **coverage** ("84% of buttons use a role") and what is still open.

### C. Later, any time

The same as B, started from the Components page. A rescan compares with the baseline. Uses added since then that have
no role or contradict one are offered as one batch of questions, never opened by themselves (CO13).

### D. Building features: respect the roles, ask on a mismatch

| When | Who | What happens | Cost |
|---|---|---|---|
| Filing | Iris | She gets the role table in short form and maps the prompt to roles. A mismatch becomes one of her questions (see below). | A few hundred tokens more in her one call |
| Brief | Hatch | The agent gets the roles for the places the ticket touches: code name, use when, not when. Rule: use only these; if none fits, `hatch ask`, never invent a look. | A few hundred tokens |
| Ready | `hatch ready` | Free check of the diff: inline styles or typed-in values instead of roles, a role in a place it is not allowed in, two primaries on one screen, a role's code changed outside a components ticket. The agent fixes them or asks. | Free |
| After the agent | Owner | What the agent could not settle comes to Decide with three answers: fix to match (★ by default), add as a variant with a reason, or allow here only (recorded, so it is not flagged again). | Free |

Kinds of mismatch Iris asks about:

1. **The prompt contradicts a role**: "make the Save button big and blue" where Save in a sheet is `button.primary`.
   Answers: use the role (★), add a variant here, or change the role everywhere (which becomes a redesign, E).
2. **The prompt needs a role that does not exist**: the first slider, the first destructive action in a row. Answers:
   two or three candidates from the template, drawn as pictures by the recipe engine.
3. **The prompt breaks a rule of the table**: a second prominent button on a screen.

Clashes with components always wait for the owner (IR12 stays).

Every answer updates the system file. The baseline grows from the owner's decisions, not from what the last agent did.

### E. Redesign: the baseline has versions

The components are where a redesign **starts**, not a limit on it.

- **Change a role everywhere** ("other actions should not be glass"): the Designer opens a draft v2. Edit the recipe
  and see it in every place at once (recipe engine), beside today (app engine). Accepting makes v2 the baseline and adds
  a ticket that changes the role's code once; every screen follows, because they all use the role.
- **Redesign an area** ("redo Desk"): a Theme marks the area **in redesign**. Inside it, `hatch ready` stops flagging
  mismatches and options may propose new roles or variants (SC2: proposed inside the option, moved on build). On
  accept, Iris asks once per new thing: make it the role everywhere, a variant for this area, or drop it.

## Hatch on Hatch

Hatch is the first app to go through workflow B, with Hatch's own process and no hand-written shortcut:

1. Inventory Hatch. Its components sit in a folder of the app target, so the first ticket moves them into
   `Packages/HatchComponents` (CO8).
2. The Glass template is written from Hatch's accepted rules (LK1 to LK11, DR8), so most clusters match it and the
   owner only decides where Hatch disagrees with itself.
3. The Theme that results updates Hatch's screens. `DESIGN.md`'s component tables become generated from the system file.

## Cost, in one place

| Step | Model calls |
|---|---|
| Templates, inventory, clustering, matrix, drawing candidates, code generation, `hatch ready` checks | None |
| Setup of an existing app | At most one, for clusters that match no template role; shown with its cost first, can be skipped |
| Iris filing | None extra: the role table rides in her existing call |
| Briefs | None extra: a few hundred tokens of roles |
| Custom roles, area migrations, redesign options | Normal ticket and Proposal work, as today |

## Build order

1. **Data**: the system file, places, roles, templates as data; `hatch components roles`. Tests. No UI.
2. **Inventory by place**: usages with place and signature, grouping, coverage; `hatch components inventory`. Run on
   Hatch and Echo to tune the place rules.
3. **Recipe engine and the Designer** in the Stage app (In place, Matrix, inspector, bottom bar).
4. **Setup A, B and C**: baseline, code generation, draft tickets. **Then run B on Hatch.**
5. **Building features**: Iris's role table, briefs, the `hatch ready` role check, Decide questions.
6. **Versions and redesign**, the app engine, then the Stage's Proposal view on the same layout (SL1). Retire the
   Decide Lab.

## Questions for the owner

### DS1. Where does the Components Designer live?

- ★ **A · A mode of the Stage app**, rebuilt with the Lab's way of working. The Stage already compiles app code and
  runs apart from Hatch, so a broken build cannot take Hatch down.
- **B · A window in Hatch**, like the Decide Lab. Quickest, but Hatch never compiles project code (CO4), so it could
  never draw the app's real components.
- **C · A third app.** Clean, but a third look to learn and keep up.

**My recommendation and reason:** A. It is the only place that can draw both recipes and the app's real components, and
it gives the redesign of the confusing Stage a clear target: Proposals move onto the same layout later.

### DS2. What is the source of truth?

- ★ **A · Rules in the notebook, look in the app's package**, with code generated from recipes and a scanner check that
  both agree.
- **B · The code is the truth**; the notebook only mirrors it. Simple, but "use when" and status have no home in code.
- **C · The notebook only**; the app reads it at run time. Unusual for a SwiftUI app and adds a dependency.

**My recommendation and reason:** A. The rules can be read without Hatch or Xcode, the app keeps plain SwiftUI with no
new dependency, and generating code from recipes costs no tokens.

### DS3. How is a role's look described?

- ★ **A · Recipes made of native control parameters, with a custom escape** for looks that need their own view.
- **B · Always code**, written by an agent per role.

**My recommendation and reason:** A. Recipes can be drawn, compared and turned into code for free. Most roles in a
macOS app are native controls with a few settings; only a few need custom views.

### DS4. The default starting point for an existing app

- ★ **A · Match the app as it is**, most-used look per place recommended.
- **B · A template**, and the app moves towards it.

**My recommendation and reason:** A for an app that ships, because it changes the least and every difference is a
question. B stays one click away for an app that is about to be redesigned anyway.

### DS5. Which places ship first?

Proposed: Toolbar, Sheet footer, Bottom bar, List row, Card, Inspector, Popover, Form, Empty state, Context menu,
Alert. More can be added as data.

**My recommendation and reason:** these 11. They cover every place Hatch and Echo use today; a missing place shows up as
"unknown" in the inventory, which tells us what to add.

### DS6. Which templates ship first?

- ★ **A · macOS Native and Glass**, then Compact.
- **B · All three at once.**

**My recommendation and reason:** A. Glass is Hatch's own look and is tested on Hatch; macOS Native is the safe start for
anything new. Compact can wait until an app needs it.

### DS7. A mismatch found at Ready

- ★ **A · The agent fixes it or asks first; only what is left reaches the owner**, with "fix to match" recommended.
- **B · Every mismatch goes to the owner.**
- **C · A note only**, as today.

**My recommendation and reason:** A. Most mismatches are an agent forgetting a role, which it can fix for free. The owner
is asked only about real choices.

### DS8. When does a provisional role become agreed?

- ★ **A · When the owner confirms it**, offered in Decide after it has been used on 3 built tickets without change.
- **B · Only when the owner confirms it**, never offered.
- **C · Automatically after 3 tickets.**

**My recommendation and reason:** A. It never changes by itself, but it does not depend on the owner remembering to look.

### DS9. Hatch's DESIGN.md

- ★ **A · Its component map and button table are generated from the system file**; the principles stay hand-written.
- **B · Left as it is.**

**My recommendation and reason:** A. Two copies of the same rules drift; that is part of what went wrong.

### DS10. The setup model call for unmatched clusters

- ★ **A · Offered with its cost, skippable**; skipping leaves those roles with a plain generated name for the owner to rename.
- **B · Always run.**
- **C · Never; the owner names them.**

**My recommendation and reason:** A. Matching template roles covers most clusters for free; the call only writes words
for the rest, and the owner sees the cost first.

### DS11. The name

- ★ **A · Keep "Components"** for the feature and the page (PS11), and call the window **Components Designer**.
- **B · "Design system"** everywhere.

**My recommendation and reason:** A. It is the word already used in the app, the CLI and the decisions; renaming costs a
migration for no gain.

### DS12. What happens to the Decide Lab?

- ★ **A · Kept until the Designer can do what it does, then retired**; its way of working (parts, ‹ ›, hard cases) is
  what the Designer is built from.
- **B · Retired now.**

**My recommendation and reason:** A. The Lab is the one look-picking tool that works today; it should go only when
something better replaces it.
