# Components Designer, round 2 (proposal, ids CD1 to CD10)

Status: **superseded, 2026-10-05**, by `components-designer-round2.html` (CD1 to CD45, with real captures). Its CD numbers
do not match the page's; answer on the page. Kept for the first findings.

Was: **proposal, 2026-10-05**. Written after the owner's first real session with the Designer on Hatch's own system. Builds on
DS1 to DS12 (`components-designer.md`) and changes only how the Designer works, not the data model. ★ marks the recommendation.

Scope tags: **[D]** Designer only (`Stage/Sources/StageKit/Designer/`). **[K]** the shared renderer (`HatchComponentKit`), so it
also changes Decide's option cards and the Components page. **[S]** worth porting to the Proposal Stage later (SL1). Nothing here
changes the Stage today.

## What the owner said

- Too cluttered; hard to change something and see what it looks like.
- No way to give every button in a place (Sheet footer) one style, or to use a template for all buttons.
- The inspector is crowded. Look can change everything, but it doesn't say what *should* change. Stepping with ‹ › feels broken.
- Should a change apply to every button at once, or should you open one place (Bottom bar) and change only that?
- "Against Apple's guidance" is useful but looks plain.
- Switching to dark and back doesn't return to light.
- The Matrix lists what is decided but gives no overview; it needs previews.
- Today vs Draft belongs inside the editing of one role.
- Picking an option in the bottom bar changes nothing on screen; only the inspector does. There should be one place to decide.
- "Make it a setting" means nothing to a user, and it should say whether it's recommended (for buttons, never).

## What I found on every page (snapshots of Hatch's own system, light and dark)

Bugs, which ship whatever is decided below:

| # | Where | What is wrong | Cause | Scope |
|---|---|---|---|---|
| B1 | Hard cases, Dark | Dark doesn't go back to light | `.preferredColorScheme(model.dark ? .dark : nil)`: on macOS, going back to `nil` doesn't reset the window | D |
| B2 | Inspector, ‹ › | From "–" (unset), › skips the first value and ‹ jumps to the last; you can't get back to unset; the end wraps around without a sign | `step` treats a missing value as index 0 and wraps with `%` | D |
| B3 | Inspector, ‹ › | Every click goes through Hatch, which writes the notebook and **makes a git commit**; that is the lag, and the notebook fills with commits | `run("look")` → `StageServer.changeComponents` → `commitNotebook` | D |
| B4 | Question bar | Choosing an option draws nothing; the canvas shows the role as saved | `choice` is local state, the canvas reads `draft ?? recipe` | D |
| B5 | Rules, Foundations | The In Place / Matrix / Today switch stays (showing "Today vs Draft"), and the inspector shows a role from another element (`emptyState.standard`) | Mode and selected role aren't cleared outside elements | D |
| B6 | List rows | Each sample row draws a whole list inside it; text wraps one letter per line | `RecipeRow` draws a list, and `PlaceFrame` puts it in each row of its own list | K + D |
| B7 | Badges | The badge is drawn as a row-sized box ("Waiting for me 3") in the toolbar and in rows; the toolbar title collapses to "…" | `RecipeBadge` draws a `List` row, and the frames treat it as a small control | K + D |
| B8 | Toggles | The recommended option reads "–" (it is the macOS default, a checkbox) and contradicts the role's own "use when" (a mini switch) | An empty recipe summary; the question recommends the most used look | D + core text |
| B9 | Menus | `menu.toolbar` is the role in List row, Card, Inspector and Form, so the name says the wrong place | The name comes from the first place it was found in | core data |
| B10 | Question bar | The fourth card is clipped, cards 5 and 6 are off screen, and a scroll knob shows in the corner | A fixed 210 pt horizontal strip | D |
| B11 | Live window | "Open a Sheet · Open an Alert · Show…" run under the toast | Both pinned to the bottom | D |
| B12 | Title bar | The subtitle cuts off ("30 provisio…") | Too long for the toolbar | D |

Clutter, page by page:

- **Place cards** repeat role ids in monospace ("button.cancel · button.destructive · button.sh…"), a summary line and a ⋯ menu with a
  single item. Three lines of metadata per card, before the sample.
- **Selection** draws a 2 pt blue box around *every* copy of the role: on Toggles, a dozen boxes at once.
- **Status dots** in the sidebar are all grey (everything is provisional), so they say nothing. The orange count capsule looks
  different from the system badges under Rules and Foundations.
- **Inspector**: role id, code name, places, three Apple sections and three buttons in a row, all at the same weight. Ten look
  rows for Buttons, seven of them "–". Behaviour (Confirm first, Key, Tooltip) is mixed in with look.
- **Rules**: ten cards, each with a pop-up and its own "Make It a Setting" button.
- **Foundations**: a read-only list. Surface and Content are both white boxes; nothing shows them in dark or in use.
- **Hard cases** hide in an icon-only menu, and Dark and Large text apply to the whole window, inspector included.

## The model in one paragraph (answers "all buttons, or only Bottom bar?")

A **place** is where a control sits (Bottom bar, Sheet footer). A **role** is one job a control does (the main action, a quiet
action). A look belongs to a role, and a role can sit in many places: `button.primary` is the main action in Bottom bar, Empty state,
Page, Action row and Floating. So changing the main action changes it in all five, which is the point of a design system. To make
it different **only** in Bottom bar, you make a **variant** (`button.primary.bottomBar`) with a reason. "Role" is the right word;
the UI should show its plain name ("Main action") first and the id only where code is concerned.

## The new layout

Two levels: the **element** (all buttons, read to get the picture) and the **role** (one job, edited in every place it sits).

```
Element level: Buttons                                              no role selected: inspector shows the element
┌──────────────┬───────────────────────────────────────────────────┬───────────────────────┐
│ Elements     │ Buttons         [In Place | Matrix]   Glass ▾  ⋯  │ Buttons               │
│ ● Buttons 12 │ ┌ Light · Dark · Both ┐ Long label  Disabled  Aa+ │ 19 uses · 4 roles     │
│   Menus    2 │ ┌ Toolbar ─────────┐ ┌ Sheet footer ─────────────┐ │ 12 to decide          │
│   …          │ │ Desk    [Refresh]│ │ Rename Area  Cancel (Save)│ │                       │
│ Rules        │ └──────────────────┘ └───────────────────────────┘ │ Start from            │
│ Foundations  │ ┌ Bottom bar ●2 ───┐ ┌ List row ─────────────────┐ │  ◉ Today's app (most  │
│              │ │ Share     (Save) │ │ Fix the login …  Open Save│ │    used look, ★)      │
│              │ └──────────────────┘ └───────────────────────────┘ │  ○ macOS Native       │
│              │  hover dims the rest; click a control → its role  │  ○ Glass              │
└──────────────┴───────────────────────────────────────────────────┴───────────────────────┘

Role level: Buttons › Main action                                  the inspector edits; the canvas previews
┌──────────────┬───────────────────────────────────────────────────┬───────────────────────┐
│              │ ‹ Buttons   Main action · in 5 places  [Compare]  │ Main action  Provisional│
│              │ Bottom bar     Today [✓ Save]   Draft [Save]       │ The one main action…  │
│              │ Empty state    Today [✓ Save]   Draft [Save]       │                       │
│              │ Page           …                                  │ To decide             │
│              │ Action row     …                                  │  ◉ [✓ Save] ★ 6 uses  │
│              │ Floating       …                                  │  ○ [Save]     2 uses  │
│              │                                                   │  ○ Follow macOS       │
│              │ Also in the app today: [Save] 2 · [Save] 1 · …    │ ▸ Fine-tune           │
│              │                                                   │ ⚠ Apple: glass in     │
│              │                                                   │   content [Use plain] │
│              │                                                   │ (Answer)            ⋯ │
└──────────────┴───────────────────────────────────────────────────┴───────────────────────┘
```

## Questions for the owner

### CD1. Where do you decide a look? [D]

- ★ **A · In the inspector only.** The bottom bar goes. A role's open question becomes the top section of its inspector: the
  options as a vertical list of drawn controls, recommended first with its reason. **Choosing an option previews it at once on
  the canvas** in every place (not saved); Answer saves. A "12 to decide" button in the toolbar (⌘]) jumps to the next role with
  a question, across elements.
- **B · In the bottom bar only.** The inspector becomes read-only (use when, Apple, code) and the bar previews on selection.
- **C · Both, kept in step.** Choosing in either one previews.

**My recommendation and reason:** A. Deciding and fine-tuning are the same act (picking a look), so they belong in one place.
It also gives the canvas back the 200 pt the bar takes, and the inspector is already tied to the selected role.

### CD2. How is a look changed? [D]

- ★ **A · Picks first, fine-tune second.** The Look section shows three to five drawn candidates you click: Apple's default,
  the template's, the most used in the app, and the current one. Under them, **Fine-tune** (folded) has native pop-up menus
  instead of ‹ ›: each lists every value, marks Apple's default and the recommended one, and says "Default (macOS: automatic)"
  instead of "–". Behaviour (Confirm first, Key, Tooltip) moves to its own folded section. Changes preview at once and are
  **saved once** with Keep / Discard, so one commit per decision, not per click (fixes B2, B3).
- **B · Keep ‹ ›, fix the bugs**, and add "Apple's default" and "recommended" marks.

**My recommendation and reason:** A. "What should I change" is answered by showing real candidates, not ten parameters;
parameters stay for whoever wants them. Pop-ups show where you are in the list, so nothing feels broken.

### CD3. Element and role levels [D]

- ★ **A · Two levels.** The element view is read to get the picture: places drawn compactly, no boxes; hovering a control
  dims the rest; clicking one opens its **role view** ("Buttons › Main action"), which draws the role in every place it sits,
  with **Compare** showing Today beside the Draft per place (Today vs Draft folds in here). Each place row has **Only here…**,
  which makes a variant with a reason.
- **B · One level**, as today, with the role highlighted.

**My recommendation and reason:** A. It answers "all buttons or only Bottom bar" in the layout itself: a change is made on a
role and you see every place it reaches before you keep it; a place-only change is an explicit variant.

### CD4. Doing something for a whole element or a whole place [D]

- ★ **A · Right-click menus, plus "Start from" in the element inspector.** Right-click Buttons in the sidebar: *Use a template
  for all buttons ▸ macOS Native / Glass*, *Follow macOS for all buttons*, *Agree to all buttons*. Right-click a place on the
  canvas: *One look for every button here…* (picks a style and sets it on each role in that place, then lists the other places
  those roles reach, with *only here* as a variant), *Follow macOS here*. With no role selected, the inspector shows the
  element: uses, roles, open questions and a **Start from** choice (today's app ★, or a template), previewed before applying.
- **B · Only the sidebar menu.**

**My recommendation and reason:** A. Both requests ("same style for all of Sheet footer", "template for all buttons") are
batch changes, and the canvas and sidebar are where you look when you think of them. The ⋯ menu on each place goes.

### CD5. The Matrix [D, S]

- ★ **A · A matrix of drawn controls.** Places down, Main / Other / Quiet / Destructive across; each cell draws the role's control
  with its name small under it. Hovering a cell lights up every cell of the same role; a column with more than two different
  looks gets a mark ("Main: 3 looks"). **Today** overlays the app's current look per cell with a dot where it differs. Empty
  cells say "Decide…" and file the question.
- **B · Keep the table**, add a hover preview.

**My recommendation and reason:** A. The table already says *what* is decided; drawing it shows whether the system holds
together, which is what the Matrix is for. Same idea fits the Stage's Matrix later.

### CD6. Apple's guidance [D]

- ★ **A · One "Apple" section with a callout.** When a role goes against Apple, a callout at the top of the inspector: a symbol,
  one sentence, a **Use Apple's choice** button when there is a clear fix (plain material instead of glass in content), and
  the page link. Sources become one row of links ("HIG: Buttons · Adopting Liquid Glass"); the read date goes in the tooltip.
  On the canvas, the affected places get a small mark.
- **B · Keep two sections**, styled better.

**My recommendation and reason:** A. Today the warning and the sources look the same and sit below ten look rows. A callout
with a fix turns advice into a one-click answer.

### CD7. "Make it a setting" [D, core]

- ★ **A · Rename to "Let people choose in Settings"**, explain it in the help ("Keeps this look as the default and drafts a
  ticket for a setting in your app"), and give **each element a recommendation**: never for Buttons, Menus, Sheets, Alerts,
  Context menus ("people expect these to look like macOS; a setting doubles what has to be tested"); worth offering for accent
  colour, density, toast position and duration, row separators. Not recommended → it lives in the ⋯ menu; recommended → a
  checkbox under Answer with the reason.
- **B · Rename only.**

**My recommendation and reason:** A. Rule 3 asks for a recommendation on every suggestion, and the owner already knows the answer
for buttons.

### CD8. Hard cases [D, S]

- ★ **A · A visible bar above the canvas**: Light · Dark · Both (side by side), Long label, Disabled, Larger text. They apply
  **to the canvas only**, not the window, so the inspector stays as it is (fixes B1).
- **B · Keep the menu**, fix the dark bug.

**My recommendation and reason:** A. Hard cases are the Lab's best part (DS12) and are hidden today. "Both" lets dark be judged
without flipping back and forth.

### CD9. Rules and Foundations [D]

- ★ **A · Grouped forms, and foundations in use.** Rules become a grouped form (Menus, Context menus, Text) with one pop-up per
  row, Apple's choice marked, and a tiny example of what the rule does ("Open Recent" / "Open recent"); the setting choice goes
  in the row's ⋯ menu. Foundations show each value in light and dark, with a sample in use (the surface behind a card, a radius
  on a card), and can be changed with the same pick-and-preview as roles. The view switcher and role inspector are hidden here
  (fixes B5); the inspector shows the selected rule or foundation.
- **B · Fix B5 only.**

**My recommendation and reason:** A. The foundations are what templates and roles stand on; seeing only names and swatches
can't tell anyone if Surface and Content are right.

### CD10. Canvas tidy-up [D]

- ★ **A · All of these:** place cards show the title only (summary and role ids in the tooltip); selection is a soft halo on the
  selected role with the rest dimmed, not boxes; places with an open question get an orange dot; sidebar uses system badges and
  shows a check only when an element is fully agreed (no grey dots); the subtitle becomes "12 to decide · 30 provisional", with
  the baseline version in a toolbar menu (fixes B12).

**My recommendation and reason:** A. Each line of metadata taken off a card is room for the sample, which is the thing being
judged.

## Order

1. Bugs B1 to B12 (small, no decisions needed beyond this list).
2. CD1 and CD2 together (one place to decide, pick and preview, one commit per decision): they fix the "feels broken" part.
3. CD3 and CD10 (two levels, quieter canvas), then CD4 (batch changes).
4. CD5 (drawn Matrix), CD6, CD7, CD8, CD9.

Every step: `swift test` at the root and in `Stage/`, Designer snapshots (`--snapshots`) in light and dark, and run on Hatch's
own notebook.
