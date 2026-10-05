# Hatch design rules (draft)

Status: **accepted**. These rules reflect the owner's answers on the design page (LK1 to LK11). Agents read this file before they add or change any UI.

## Principles

1. Native first. Use the system control when one exists.
2. Glass is for floating controls (dock, toasts, panels), never for content.
3. No glass on glass. Selection inside a glass control is a fill.
4. Everything through tokens (`HX`): no literal sizes, radii or colours in views.
5. Motion explains change. Reduce Motion, Reduce Transparency and Increase Contrast must look right.
6. Colour means whose turn it is (amber you, teal agent, slate Hatch, green finished, grey paused) or a real problem (red). Types, areas and projects are neutral. Exceptions: the project tile colour in the project card, and the count badge on the Decide toolbar button, which is the system's red badge like the Dock icon's (DC11).
7. One prominent action per screen.
8. Text: system font and text styles only. Monospaced only for ticket numbers and code.
9. Every suggestion shows one recommendation and its reason.
10. Iris's mark is drawn in the label colour (primary or secondary; the accent when her panel is open), never teal. Teal says an agent is working; Iris is the one who files and asks, not a worker.

## Component map

| You need | Use | SwiftUI |
|---|---|---|
| Many records, sortable | Native table | `Table` |
| A queue to work through | Sectioned list and detail pane (Desk) | `List`, `Section` |
| Flow across stages | Lanes with plain cards (Board) | `ScrollView`, `LazyVStack` |
| Switch main areas | Sidebar source list | `NavigationSplitView`, `List` |
| Contextual details or actions | Native trailing inspector on the detail column | `.inspector(isPresented:)`, `.inspectorColumnWidth(min:ideal:max:)` |
| Switch sections of one pane (up to 5) | Text dock | `HXDock` (6 or more: pull-down, automatic) |
| Switch sections (6 or more) | Pull-down | `Picker` `.menu` |
| View mode in the toolbar | System segmented control | `Picker` `.segmented` |
| Status of a ticket | Phase glyph and name | `HXStatus` (`Label` with symbol) |
| Project | Title menu in the toolbar: tile, name, pull-down of projects | `ProjectTitleMenu` |
| Facts about the selection | Details card | `LabeledContent` in `Form` |
| Settings | Navigation sidebar with focused grouped forms | `NavigationSplitView`; detail `Form` `.formStyle(.grouped)` |
| Provider and model per task | One row per task with menu pickers (provider, model, effort), a Test button and the recommendation as a caption; providers as rows with an on/off switch, Refresh, Test and Edit | `Picker` (menu), `Toggle` `.switch`, `.bordered` `.controlSize(.small)` |
| Project settings | One card per part (tile, ⓘ popover, current value, rows edited in place), Save bar | `HXSettingsCard`, `HXSetupRow` |
| Main action | One prominent glass capsule, first in the row | `.glassProminent`, `.controlSize(.large)` |
| Other actions | Quiet glass capsules with icon and label; rare ones in a More menu | `.glass`, `Menu` |
| Destructive action | Menu item then confirmation sheet | `role: .destructive` |
| Filter or search | Search field with tokens, saved views | `.searchable` |
| Search and commands across the app | Floating glass command palette, scoped by prefix or shortcut (CP1 to CP8) | `commandPaletteOverlay()`, `.glassEffect` |
| A project's own colors, type and sizes (Components page) | Swatches (light beside dark), a type sample in its own font, size bars. The one other place colour that is not turn or a problem appears: it is the project's data, not Hatch's look | `ComponentSwatch`, `ComponentRender` |
| Everything that waits for the owner | A Decide session (DR8): a grey panel over the sidebar and page (the footer stays visible), one decision on a white card 820 wide a third of the way down; coloured eyebrow, large title, token row; the asker's message and the answer list; a bottom bar with Later and Note (glass) and one prominent glass button, large; progress pills; keys in a ? popover beside Done; an undo toast before Hatch acts | `DecideSessionView`, `.decideOverlay()` |
| A question from Iris or an agent | The asker's mark on its own, name · time, the whole message in a grey bubble (`HX.bubble`); under it the answers as one grouped list: number keys, full text, a filled Recommended badge, the selected row tinted with a checkmark, "Something else…" last. Selecting does nothing: Answer (the prominent button) sends | `QuestionMessage`, `AnswerList`, `AnswerCard` |
| What Iris set when she filed a ticket | A row of tokens under the title: type, then path, priority, area, verify as small bordered capsule pop-ups; "Your words" in a popover | `FiledByIrisTokens` |
| Choosing how a screen looks | A lab window: the screen drawn with the real controls on real and hard content, one menu per part with ‹ › to step through, a description under each, Copy for Claude | `DecideLabView` (SL1: the Stage later) |
| The way into Decide | A card with the count, time and kinds, one prominent Decide button (Desk top, Iris top); a toolbar button in its own group with the count badge, hidden at zero | `DecideIrisCard`, `DecideToolbarButton` |
| Pointing at something in a screenshot | Mark-up sheet: Box, Arrow and Note in a segmented control, Undo, Save flattens the marks into the image. Marks are one fixed red so they read the same in light, dark and the saved file | `ScreenshotMarkupSheet`, `ShotMarksLayer` |
| Where model work went (Reports) | Figures in one card, a stacked bar per day with hover, breakdown cards with a thin share bar per row, CSV export. Tokens only | `Chart` `BarMark` `.chartXSelection`, `Grid`, `NSSavePanel` |
| Writing a ticket from any app | Quick Capture: one glass bar like Spotlight, Iris's mark, a field that grows, project, capture area and a round send button on the right; screenshots as thumbnails under it. Same glass, 24 pt radius and shadow as the command palette. Return sends, ⌥Return a new line, Esc or a click elsewhere closes | `QuickCaptureView`, `.glassEffect(.regular, in: .rect(cornerRadius: 24))` |
| Nothing to show | Empty state with next step | `ContentUnavailableView` |
| Work in progress | Spinner in the row, text says what | `ProgressView` |
| Short feedback | Toast capsule | `HXToast` |
| Status while Hatch is in the background | A real menu (MB1 to MB7): Decide with the count as a badge and the kinds as a second line; agents only while they work; a problem only when there is one, with Retry; New Ticket, Pause or Resume Agents, Open Hatch, Settings, Quit Hatch. No ellipses. The egg cracks when something waits | `MenuBarMenu` (`NSStatusItem`, `NSMenu`: `subtitle`, `NSMenuItemBadge`, `sectionHeader`) |

## When adding something new

1. Look it up in the component map. If it is there, use it as written.
2. If not, pick the nearest native control and add a row to the map in the same change.
3. Take sizes, colours and spacing from the tokens file. If one is missing, add the token first.
4. Colour only for turn or a real problem.
5. Check the CI screenshots (light and dark) before marking the work ready.

## Which buttons where (decisions LK10 and LK11)

The style is the one on Echo's server page and Activity Monitor: Liquid Glass capsules with an icon and a label.

| Place | Button |
|---|---|
| Main action of a screen or ticket | One `.glassProminent` capsule, large, first in the row. Never two. |
| Other actions on the object | `.glass` capsules with icon and label in the same row; the row wraps (`ViewThatFits` and a flow layout). |
| An action that needs a choice | A `Menu` styled as a glass button: `.menuStyle(.button)`, `.menuIndicator(.hidden)`. |
| Rare or risky actions (Drop) | Inside a More menu, then a confirmation sheet (`role: .destructive`). |
| Toolbar | Icon-only system items with a tooltip that shows the shortcut. |
| Inside a row, card or toast | Small bordered buttons (`.bordered`, `.controlSize(.small)`), on hover or selection. |
| Sheets and dialogs | Prominent default button; Cancel quiet. The default is never silently disabled: say what is missing and focus it. |
| A run that can be stopped | One button that swaps in place and turns red while running. |
| Shortcuts | In the tooltip and menus, not in the label. The command palette is a menu, so its rows show them on the right (CP8). |
