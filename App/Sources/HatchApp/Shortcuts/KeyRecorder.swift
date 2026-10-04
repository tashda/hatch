import SwiftUI
import AppKit
import HatchCore

/// Listens for the next key combination while a row in Settings is recording. It sits behind the row, takes the
/// keyboard when `active` turns on, and swallows the keys (⌘ combinations included) so the menu bar does not run them.
struct KeyRecorder: NSViewRepresentable {
    var active: Bool
    var onChord: (KeyChord) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView { RecorderView() }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onChord = onChord
        view.onCancel = onCancel
        view.setActive(active)
    }

    final class RecorderView: NSView {
        var onChord: ((KeyChord) -> Void)?
        var onCancel: (() -> Void)?
        private var active = false

        override var acceptsFirstResponder: Bool { active }

        func setActive(_ on: Bool) {
            guard on != active else { return }
            active = on
            if on { DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) } }
            else if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }

        override func resignFirstResponder() -> Bool {
            if active { active = false; DispatchQueue.main.async { [weak self] in self?.onCancel?() } }
            return super.resignFirstResponder()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard active, window?.firstResponder === self else { return false }
            handle(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard active else { return super.keyDown(with: event) }
            handle(event)
        }

        private func handle(_ event: NSEvent) {
            if event.keyCode == 53, Self.modifiers(event).isEmpty { onCancel?(); return }
            guard let chord = Self.chord(from: event) else { NSSound.beep(); return }
            onChord?(chord)
        }

        static func modifiers(_ event: NSEvent) -> KeyModifiers {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var out: KeyModifiers = []
            if flags.contains(.control) { out.insert(.control) }
            if flags.contains(.option) { out.insert(.option) }
            if flags.contains(.shift) { out.insert(.shift) }
            if flags.contains(.command) { out.insert(.command) }
            return out
        }

        static func chord(from event: NSEvent) -> KeyChord? {
            let mods = modifiers(event)
            switch event.keyCode {
            case 36, 76: return KeyChord("return", mods)
            case 51: return KeyChord("delete", mods)
            case 48: return KeyChord("tab", mods)
            case 49: return KeyChord("space", mods)
            case 123: return KeyChord("leftArrow", mods)
            case 124: return KeyChord("rightArrow", mods)
            case 125: return KeyChord("downArrow", mods)
            case 126: return KeyChord("upArrow", mods)
            default:
                guard let text = event.charactersIgnoringModifiers?.lowercased(), text.count == 1,
                      let scalar = text.unicodeScalars.first, scalar.value >= 0x20, !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
                return KeyChord(text, mods)
            }
        }
    }
}

/// Keys drawn as small caps, as the palette does.
struct ShortcutKeyCaps: View {
    let symbols: [String]
    var dimmed = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(dimmed ? 0.4 : 0.75))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            }
        }
    }
}
