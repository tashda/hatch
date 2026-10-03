# Hatch design rules (draft)

Status: **proposed**. These are the recommendations on the design page (decisions L1 to L9). They become rules when the owner answers; change this file to match the answers. Agents read this file before they add or change any UI.

## Principles

1. Native first. Use the system control when one exists.
2. Glass is for floating controls (dock, toasts, panels), never for content.
3. No glass on glass. Selection inside a glass control is a fill.
4. Everything through tokens (`HX`): no literal sizes, radii or colours in views.
5. Motion explains change. Reduce Motion, Reduce Transparency and Increase Contrast must look right.
6. Colour means whose turn it is (amber you, teal agent, slate Hatch, green finished, grey paused) or a real problem (red). Types, areas and projects are neutral. The one exception is the project tile colour in the project card.
7. One prominent action per screen.
8. Text: system font and text styles only. Monospaced only for ticket numbers and code.
9. Every suggestion shows one recommendation and its reason.

## Component map

| You need | Use | SwiftUI |
|---|---|---|
| Many records, sortable | Native table | `Table` |
| A queue to work through | Sectioned list and detail pane (Desk) | `List`, `Section` |
| Flow across stages | Lanes with plain cards (Board) | `ScrollView`, `LazyVStack` |
| Switch main areas | Sidebar source list | `NavigationSplitView`, `List` |
| Switch sections of one pane (up to 5) | Text dock | `HXDock` |
| Switch sections (6 or more) | Pull-down | `Picker` `.menu` |
| View mode in the toolbar | System segmented control | `Picker` `.segmented` |
| Status of a ticket | Phase glyph and name | `HXStatus` (`Label` with symbol) |
| Project | Project card at the top of the sidebar | `HXProjectCard` |
| Facts about the selection | Details card | `LabeledContent` in `Form` |
| Settings | Grouped form | `Form` `.formStyle(.grouped)` |
| Main action | One prominent button | `.borderedProminent` |
| Other actions | Bordered buttons, rest in a menu | `.bordered`, `Menu` |
| Destructive action | Menu item then confirmation sheet | `role: .destructive` |
| Filter or search | Search field with tokens, saved views | `.searchable` |
| Nothing to show | Empty state with next step | `ContentUnavailableView` |
| Work in progress | Spinner in the row, text says what | `ProgressView` |
| Short feedback | Toast capsule | `HXToast` |

## When adding something new

1. Look it up in the component map. If it is there, use it as written.
2. If not, pick the nearest native control and add a row to the map in the same change.
3. Take sizes, colours and spacing from the tokens file. If one is missing, add the token first.
4. Colour only for turn or a real problem.
5. Check the CI screenshots (light and dark) before marking the work ready.
