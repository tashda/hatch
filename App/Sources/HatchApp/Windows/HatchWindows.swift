import SwiftUI
import AppKit

/// Finds the windows of the app that other windows need to reach.
@MainActor
enum HatchWindows {
    static let mainIdentifier = NSUserInterfaceItemIdentifier("hatch.main")

    /// Brings the main window forward (a ticket window sends you there for Previews and the like).
    static func showMain() {
        guard let window = NSApp.windows.first(where: { $0.identifier == mainIdentifier }) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// Marks the hosting window so `HatchWindows` can find it.
struct WindowTag: NSViewRepresentable {
    let identifier: NSUserInterfaceItemIdentifier

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.identifier = identifier }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window, window.identifier != identifier { window.identifier = identifier }
    }
}
