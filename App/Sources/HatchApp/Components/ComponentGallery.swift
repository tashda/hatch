// hatch-inventory: samples (this file draws the app's own components for Hatch to capture; they are not new looks)
import SwiftUI
import HatchCore

// The app's own components, drawn by the app itself so Hatch can show them as they are (CM5). The contract any app can
// follow: each item is tagged with the view's type name, and the capture writes `component-gallery.json` beside the
// pictures with every item's frame, so the Components Designer cuts out each view. Hatch groups and judges them; the
// gallery only draws. Captured with `--snapshots <folder> --only component-gallery`, stored by `hatch components capture`.

struct ComponentGallery: View {
    /// Frames of the items in the last drawing, in points from the top left.
    @MainActor static var frames: [String: [CGRect]] = [:]

    var body: some View {
        FlowLayout(spacing: 28) {
            item("HXChip") { HStack(spacing: 6) { HXChip(text: "Your call", turn: .you); HXChip(text: "Building", turn: .agent); HXChip(text: "Merged", turn: .finished) } }
            item("HXProblemChip") { HXProblemChip(text: "2 problems") }
            item("PlainChip") { HStack(spacing: 6) { PlainChip(text: "Connections", systemImage: "folder"); PlainChip(text: "Editor") } }
            item("DecideCountBadge") { DecideCountBadge(count: 3) }
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
            item("HXEmpty") { HXEmpty(symbol: "tray", title: "No tickets", detail: "New tickets you write appear here.").frame(width: 300, height: 150) }
        }
        .padding(24)
        .frame(width: 1100, alignment: .topLeading)
        .coordinateSpace(name: "gallery")
        .onPreferenceChange(GalleryFrames.self) { Self.frames = $0 }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// One view, tagged with its type name; its frame is reported for the capture.
    private func item<C: View>(_ id: String, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .background(GeometryReader { g in Color.clear.preference(key: GalleryFrames.self, value: [id: [g.frame(in: .named("gallery"))]]) })
    }

    /// A window without a title bar, so the picture is the gallery and the frames need no offset.
    @MainActor static func window() -> NSWindow {
        let host = NSHostingView(rootView: ComponentGallery())
        let size = host.fittingSize
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.center()
        w.makeKeyAndOrderFront(nil)
        return w
    }

    /// `component-gallery.json`: the version of the contract, the scale of the pictures and each item's frames in points.
    @MainActor static func writeFrames(into folder: URL, scale: CGFloat) {
        let items = frames.mapValues { $0.map { [$0.minX, $0.minY, $0.width, $0.height] } }
        let json: [String: Any] = ["version": 1, "scale": scale, "items": items]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("component-gallery.json"))
        }
    }
}

private struct GalleryFrames: PreferenceKey {
    static let defaultValue: [String: [CGRect]] = [:]
    static func reduce(value: inout [String: [CGRect]], nextValue: () -> [String: [CGRect]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}
