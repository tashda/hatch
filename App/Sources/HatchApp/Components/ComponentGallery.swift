// hatch-inventory: samples (this file draws the app's own components for Hatch to capture; they are not new looks)
import SwiftUI
import HatchCore

// The app's own views that no snapshot screen shows, drawn by the app itself with sample data so Hatch can show them as
// they are (CM20, CM21). Every view marks itself (`.hatchMark`); each item here is marked too, so its picture is the
// whole sample. Captured with the snapshot run (`--snapshots <folder>`, or `--only component-gallery`) as
// `component-gallery-light.png` / `.json`, kept by `hatch components capture`.

struct ComponentGallery: View {
    static let name = "component-gallery"

    var body: some View {
        FlowLayout(spacing: 28) {
            item("HXChip") { HStack(spacing: 6) { HXChip(text: "Your call", turn: .you); HXChip(text: "Building", turn: .agent); HXChip(text: "Merged", turn: .finished) } }
            item("HXProblemChip") { HXProblemChip(text: "2 problems") }
            item("PlainChip") { HStack(spacing: 6) { PlainChip(text: "Connections", systemImage: "folder"); PlainChip(text: "Editor") } }
            item("DecideCountBadge") { DecideCountBadge(count: 3) }
            item("HXIssueSample") { HXIssueSample(number: 151, title: "Toast spacing feels cramped", labels: ["type:proposal", "status:your-call"]) }
            item("StatusChip") { HStack(spacing: 10) { StatusChip(status: .building); StatusChip(status: .yourCall); StatusChip(status: .merged) } }
            item("TypeBadge") { HStack(spacing: 10) { TypeBadge(type: .bug); TypeBadge(type: .proposal) } }
            item("TurnLabel") { HStack(spacing: 10) { TurnLabel(turn: .you); TurnLabel(turn: .agent) } }
            item("ThreadFilterChip") { HStack(spacing: 6) { ThreadFilterChip(title: "Notes", isOn: .constant(true)); ThreadFilterChip(title: "Agents", isOn: .constant(false)) } }
            item("ThreadKindChip") { HStack(spacing: 6) { ThreadKindChip(title: "All", selected: true) {}; ThreadKindChip(title: "Questions", selected: false) {} } }
            item("SectionCard") { SectionCard("Details") { Text("Status: Building").font(.callout) }.frame(width: 240) }
            item("HXCard") { HXCard { Text("Agents run one ticket each.").font(.callout) }.frame(width: 240) }
            item("HXHeader") { HXHeader(title: "Agents", subtitle: "Who is working on what").frame(width: 260, alignment: .leading) }
            item("HXSetupHeader") { HXSetupHeader(symbol: "folder", tint: .accentColor, title: "Repositories", detail: "Where the app and notebook live").frame(width: 280, alignment: .leading) }
            item("MetaRow") { MetaRow(label: "Area") { Text("Editor") }.frame(width: 220) }
            item("HXSetupRow") { HXSetupRow("Branch") { Text("main") }.frame(width: 220) }
            item("ShortcutKeyCaps") { ShortcutKeyCaps(symbols: ["⌘", "K"]) }
            // Quick capture's own buttons, the footer's hover card, Settings' parts and the menu bar's: in panels and
            // hover cards no snapshot screen shows.
            item("QuietIconButton") { HStack(spacing: 8) { QuietIconButton(symbol: "camera") {}; QuietIconButton(symbol: "paperclip") {} } }
            item("SendButton") { HStack(spacing: 8) { SendButton(enabled: true) {}; SendButton(enabled: false) {} } }
            item("DoneButton") { DoneButton {} }
            item("RemoveBadge") { RemoveBadge {} }
            item("FooterCard") {
                FooterCard(title: "Acme") {
                    CardRow(label: "App", value: "acme/app · main")
                    CardRow(label: "Notebook", value: "Not on this Mac", tint: Theme.critical)
                }
            }
            item("TestStatusGlyph") { HStack(spacing: 8) { TestStatusGlyph(status: .passed); TestStatusGlyph(status: .failed); TestStatusGlyph(status: nil) } }
            item("ChoiceRow") {
                VStack(spacing: 4) {
                    ChoiceRow(selected: true, title: "Claude Code", detail: "Your Claude subscription", symbol: "terminal") {}
                    ChoiceRow(selected: false, title: "API key", detail: "Pay per token", symbol: "key") {}
                }
                .frame(width: 320)
            }
            item("GitHubAvatar") { GitHubAvatar(user: nil, size: 40) }
            item("Subtitle") { Subtitle(text: "Signed in as tashda").frame(width: 220, alignment: .leading) }
            item("RepoName") { HStack(spacing: 12) { RepoName(name: "acme/app", isPrivate: true); RepoName(name: "acme/docs", isPrivate: false) } }
            item("MenuBarActionLabel") { MenuBarActionLabel(title: "New Ticket", symbol: "plus", shortcut: "⌘N").frame(width: 220) }
            item("MenuBarLabel") { HStack(spacing: 10) { MenuBarLabel(waiting: false); MenuBarLabel(waiting: true) } }
            item("HXEmpty") { HXEmpty(symbol: "tray", title: "No tickets", detail: "New tickets you write appear here.").frame(width: 300, height: 150) }
        }
        .padding(24)
        .frame(width: 1100, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// One view's sample, marked with the view's name so the whole sample is its picture.
    private func item<C: View>(_ id: String, @ViewBuilder _ content: () -> C) -> some View {
        content().hatchMark(id)
    }

    /// A window without a title bar, so the picture is the gallery and the frames need no offset.
    @MainActor static func window() -> NSWindow {
        let host = NSHostingView(rootView: ComponentGallery().hatchMarksRoot())
        let size = host.fittingSize
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.center()
        w.makeKeyAndOrderFront(nil)
        return w
    }
}
