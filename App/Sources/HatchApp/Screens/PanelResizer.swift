import SwiftUI
import AppKit

/// A drag handle that sits in the gutter between two panels and resizes one of them.
/// Attach it as an overlay on the panel's edge; `growsLeft` is true for a panel on the right of the handle.
struct PanelResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    var growsLeft = false
    @State private var startWidth: Double?
    @State private var hovering = false

    var body: some View {
        Color.clear
            .frame(width: 14)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Color.accentColor.opacity(hovering || startWidth != nil ? 0.55 : 0))
                    .frame(width: 3, height: 44)
                    .animation(.easeOut(duration: 0.15), value: hovering)
            }
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        if startWidth == nil { startWidth = width }
                        let delta = growsLeft ? -drag.translation.width : drag.translation.width
                        width = min(max((startWidth ?? width) + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .help("Drag to resize")
    }
}
