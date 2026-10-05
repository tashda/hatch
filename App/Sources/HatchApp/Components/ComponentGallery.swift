// hatch-inventory: samples (this file draws the app's own components side by side for review; they are not new looks)
import SwiftUI
import HatchCore

// The app's own components, drawn by the app itself (proposal CM5): each group is what `hatch components views` proposes
// as one component, with every view that is part of it today, so the owner judges the grouping by eye, not by a
// reading of the code. Captured with `--snapshots <folder> --only component-gallery`.

struct ComponentGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Chip", "Proposed: one Chip. Same capsule and padding today; the colour is a tone, the weight differs (pick one).") {
                item("HXChip · by turn") { HStack(spacing: 6) { HXChip(text: "Your call", turn: .you); HXChip(text: "Building", turn: .agent); HXChip(text: "Merged", turn: .finished) } }
                item("HXProblemChip · critical") { HXProblemChip(text: "2 problems") }
                item("PlainChip · neutral") { HStack(spacing: 6) { PlainChip(text: "Connections", systemImage: "folder"); PlainChip(text: "Editor") } }
                item("DecideCountBadge · small") { DecideCountBadge(count: 3) }
            }
            group("Asked: named chips that draw no chip", "StatusChip and TypeBadge have no capsule or fill: a status label, or chips that lost their shape?") {
                item("StatusChip") { HStack(spacing: 10) { StatusChip(status: .building); StatusChip(status: .yourCall); StatusChip(status: .merged) } }
                item("TypeBadge") { HStack(spacing: 10) { TypeBadge(type: .bug); TypeBadge(type: .proposal) } }
                item("TurnLabel") { HStack(spacing: 10) { TurnLabel(turn: .you); TurnLabel(turn: .agent) } }
            }
            group("Filter chip", "Two views for one job, drawn differently: selected is accent-tinted in one and grey in the other, which also drops the capsule when not selected.") {
                item("ThreadFilterChip") { HStack(spacing: 6) { ThreadFilterChip(title: "Notes", isOn: .constant(true)); ThreadFilterChip(title: "Agents", isOn: .constant(false)) } }
                item("ThreadKindChip") { HStack(spacing: 6) { ThreadKindChip(title: "All", selected: true) {}; ThreadKindChip(title: "Questions", selected: false) {} } }
            }
            group("Card", "Today 12 views in 11 forms; two of them here, and they already disagree: a grey fill against a white bordered panel.") {
                item("SectionCard") { SectionCard("Details") { Text("Status: Building").font(.callout) }.frame(width: 240) }
                item("HXCard") { HXCard { Text("Agents run one ticket each.").font(.callout) }.frame(width: 240) }
            }
            group("Header", "Four views; two here: a large title with a subtitle against an icon tile with a title.") {
                item("HXHeader") { HXHeader(title: "Agents", subtitle: "Who is working on what").frame(width: 260, alignment: .leading) }
                item("HXSetupHeader") { HXSetupHeader(symbol: "folder", tint: .accentColor, title: "Repositories", detail: "Where the app and notebook live").frame(width: 260, alignment: .leading) }
            }
            group("Row", "Today 14 views in 9 forms; two here: a label above its value against a label beside it.") {
                item("MetaRow") { MetaRow(label: "Area") { Text("Editor") }.frame(width: 220) }
                item("HXSetupRow") { HXSetupRow("Branch") { Text("main") }.frame(width: 220) }
            }
            group("Keycap", "Keys are drawn by ShortcutKeyCaps here and by KeyCaps (private to the command palette, not shown) in a slightly smaller form: one Keycap?") {
                item("ShortcutKeyCaps") { ShortcutKeyCaps(symbols: ["⌘", "K"]) }
            }
            group("Empty state", "One view, used five times.") {
                item("HXEmpty") { HXEmpty(symbol: "tray", title: "No tickets", detail: "New tickets you write appear here.").frame(width: 300, height: 150) }
            }
        }
        .padding(24)
        .frame(width: 1180, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func group<C: View>(_ title: String, _ note: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(note).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 18) { content() }
        }
    }

    private func item<C: View>(_ name: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            Text(name).font(.caption.monospaced()).foregroundStyle(.tertiary)
        }
    }

    @MainActor static func window() -> NSWindow {
        let host = NSHostingView(rootView: ComponentGallery())
        let size = host.fittingSize
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.center()
        w.makeKeyAndOrderFront(nil)
        return w
    }
}
