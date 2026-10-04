import SwiftUI
import AppKit

/// The Stage's icon: a proscenium tunnel of stepped blue arches with the ticket number lit at the end of it.
///
/// One drawing makes both icons. The Dock icon of a running Stage carries its ticket number (`NSApp.applicationIconImage`,
/// drawn locally, no model call and no asset per ticket). The icon of `Stage.app` itself has no number (an orange dot, as in
/// Hatch's own icon) and is written by `--render-icon` so `tools/build-stage.sh` never needs a separate design file.
struct StageIconView: View {
    /// Digits to show; `nil` shows the orange dot.
    var number: String?

    var body: some View {
        // The macOS icon grid: an 824 pt tile centred on a 1024 pt canvas, the shadow in the margin.
        let tile = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            tile
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.18, blue: 0.33), Color(red: 0.05, green: 0.08, blue: 0.19)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
            scene
                .frame(width: 824, height: 824)
                .clipShape(tile)
            tile
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 3)
                .frame(width: 824, height: 824)
        }
        .frame(width: 1024, height: 1024)
    }

    private let warm = Color(red: 1.0, green: 0.89, blue: 0.62)

    /// A proscenium tunnel: arches that step back into the dark, the number lit at the end. The arches echo Hatch's own.
    private var scene: some View {
        ZStack {
            Color(red: 0.086, green: 0.192, blue: 0.541)
            ForEach(Array(Self.layers.enumerated()), id: \.offset) { i, color in
                Arch(step: i).fill(color)
            }
            // Light at the end of the tunnel, behind the number.
            RadialGradient(colors: [Color(red: 0.81, green: 0.89, blue: 1.0).opacity(0.50), .clear],
                           center: UnitPoint(x: 0.5, y: 0.58), startRadius: 0, endRadius: 280)
            LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4))
            star
        }
    }

    private static let layers: [Color] = [
        Color(red: 0.416, green: 0.647, blue: 1.0), Color(red: 0.263, green: 0.490, blue: 0.918),
        Color(red: 0.153, green: 0.329, blue: 0.741), Color(red: 0.071, green: 0.145, blue: 0.478),
    ]

    @ViewBuilder private var star: some View {
        if let number, !number.isEmpty {
            // The size is for three digits; fewer digits are bigger, more are smaller (a seven-digit number still fits the tile).
            let size: CGFloat = [1: 540, 2: 420, 3: 360, 4: 250][number.count] ?? max(110, 1140 / CGFloat(number.count))
            Text(number)
                .font(.system(size: size, weight: .heavy))
                .tracking(-size * 0.04)
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.87, green: 0.92, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(red: 0.03, green: 0.08, blue: 0.29).opacity(0.60), radius: 14, x: 0, y: 14)
                .minimumScaleFactor(0.5).lineLimit(1)
                .frame(width: 740)
                .offset(y: 38)
        } else {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.38), Color(red: 0.96, green: 0.58, blue: 0.04)], startPoint: .top, endPoint: .bottom))
                .frame(width: 190, height: 190)
                .shadow(color: Color(red: 1, green: 0.7, blue: 0.2).opacity(0.6), radius: 40)
                .offset(y: 40)
        }
    }

    /// One arch of the tunnel, drawn in a 200 x 200 space; each step is narrower than the one before.
    private struct Arch: Shape {
        var step: Int
        func path(in rect: CGRect) -> Path {
            let k = rect.width / 200
            let inset = CGFloat(step) * 12
            let radius = 88 - inset
            let centerY = 98 + CGFloat(step)
            var p = Path()
            p.move(to: CGPoint(x: (12 + inset) * k, y: 200 * k))
            p.addLine(to: CGPoint(x: (12 + inset) * k, y: centerY * k))
            p.addArc(center: CGPoint(x: 100 * k, y: centerY * k), radius: radius * k, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: (188 - inset) * k, y: 200 * k))
            p.closeSubpath()
            return p
        }
    }
}

enum StageIcon {
    /// The digits of a ticket reference ("151" from "151"); a draft reference such as "new-7" has no number to show.
    static func digits(from reference: String?) -> String? {
        guard let reference, !reference.isEmpty, reference.allSatisfy(\.isNumber) else { return nil }
        return reference
    }

    @MainActor static func image(number: String?) -> NSImage? {
        let renderer = ImageRenderer(content: StageIconView(number: number))
        renderer.scale = 1
        return renderer.nsImage
    }

    /// Writes a 1024 pt PNG; `--render-icon`.
    @MainActor static func writePNG(to url: URL, number: String?) -> Bool {
        _ = NSApplication.shared
        guard let image = image(number: number), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: url); return true } catch { return false }
    }
}
