import SwiftUI
import AppKit

/// The icons of the two apps the Stage binary ships as: Stage (a loupe over Hatch's arch, decision AI1) and the Components
/// Designer (Hatch's arch as a construction drawing on blueprint blue, AI2). Drawn here so `tools/build-stage.sh` needs no art files.
///
/// The Dock icon of a running Stage carries its ticket number in the lens (`NSApp.applicationIconImage`, drawn locally, no model
/// call and no asset per ticket). `--render-icon` writes the icons of the app bundles.
enum AppIconKind {
    case stage
    case designer
}

/// Everything is drawn on the 1024 pt macOS icon canvas: an 824 pt tile centred on it, the shadow in the margin.
struct StageIconView: View {
    var kind: AppIconKind = .stage
    /// Digits to show in the Stage's lens; `nil` shows Hatch's arch and dot.
    var number: String?
    /// For 16 and 32 px: thinner detail (the Designer's fine grid) is left out, so the small icon stays crisp.
    var small = false

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 185, style: .continuous)
        let colors = kind == .stage ? [Self.rgb(0x1f2b4f), Self.rgb(0x0d1530)] : [Self.rgb(0x2a63d8), Self.rgb(0x1a3f9e)]
        ZStack {
            tile
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.32), radius: 14, y: 14)
            Canvas { context, _ in
                context.clip(to: tile.path(in: CGRect(x: 100, y: 100, width: 824, height: 824)))
                switch kind {
                case .stage: drawStage(&context)
                case .designer: drawDesigner(&context)
                }
            }
            .frame(width: 1024, height: 1024)
            tile
                .strokeBorder(Color.white.opacity(kind == .stage ? 0.10 : 0.14), lineWidth: 2)
                .frame(width: 824, height: 824)
        }
        .frame(width: 1024, height: 1024)
    }

    // MARK: Stage: a loupe over Hatch's arch

    private func drawStage(_ context: inout GraphicsContext) {
        let lens = CGPoint(x: 470, y: 470), radius: CGFloat = 220
        var handle = Path()
        handle.move(to: CGPoint(x: 620, y: 620))
        handle.addLine(to: CGPoint(x: 770, y: 770))
        context.stroke(handle, with: Self.vertical(Self.orange, from: 620, to: 770), style: StrokeStyle(lineWidth: 92, lineCap: .round))

        let glass = Path(ellipseIn: CGRect(x: lens.x - radius, y: lens.y - radius, width: radius * 2, height: radius * 2))
        context.fill(glass, with: .color(Self.rgb(0xe9effa)))
        context.drawLayer { inside in
            inside.clip(to: glass)
            if let number, !number.isEmpty {
                // Sized for three digits; fewer are bigger, more are smaller (seven digits still fit the lens).
                let size: CGFloat = [1: 300, 2: 260, 3: 210, 4: 160][number.count] ?? max(70, 620 / CGFloat(number.count))
                let text = Text(number)
                    .font(.system(size: size, weight: .heavy))
                    .tracking(-size * 0.04)
                    .foregroundStyle(Self.rgb(0x1f49aa))
                inside.draw(text, at: CGPoint(x: lens.x, y: lens.y + size * 0.03))
            } else {
                let arch = Self.arch(cx: 470, rc: 115, yc: 480, yb: 725)
                inside.stroke(arch, with: Self.vertical([Self.rgb(0x4180f0), Self.rgb(0x1f49aa)], from: 330, to: 700),
                              style: StrokeStyle(lineWidth: 70, lineCap: .round))
                inside.fill(Path(ellipseIn: CGRect(x: 470 - 58, y: 560 - 58, width: 116, height: 116)),
                            with: Self.vertical(Self.orange, from: 502, to: 618))
            }
        }
        context.stroke(glass, with: .color(Self.rgb(0xc9d6f0)), lineWidth: 34)
    }

    // MARK: Components Designer: Hatch's arch as a blueprint

    private func drawDesigner(_ context: inout GraphicsContext) {
        let white = Color.white
        func grid(every step: CGFloat, from start: CGFloat, opacity: Double, width: CGFloat) {
            var p = Path()
            var v = start
            while v < 924 {
                p.move(to: CGPoint(x: v, y: 100)); p.addLine(to: CGPoint(x: v, y: 924))
                p.move(to: CGPoint(x: 100, y: v)); p.addLine(to: CGPoint(x: 924, y: v))
                v += step
            }
            context.stroke(p, with: .color(white.opacity(opacity)), lineWidth: width)
        }
        if !small { grid(every: 32, from: 132, opacity: 0.08, width: 2) }
        grid(every: 128, from: 228, opacity: small ? 0.22 : 0.16, width: small ? 8 : 3)

        // Hatch's arch as a faint fill, then its outline as a drawing.
        context.stroke(Self.arch(cx: 512, rc: 173, yc: 450, yb: 738), with: .color(white.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 104, lineCap: .round))
        let line: CGFloat = small ? 22 : 10
        context.stroke(Self.arch(cx: 512, rc: 221, yc: 450, yb: 786), with: .color(white), lineWidth: line)
        context.stroke(Self.arch(cx: 512, rc: 117, yc: 450, yb: 786), with: .color(white), lineWidth: line)
        if !small {
            var axis = Path()
            axis.move(to: CGPoint(x: 259, y: 450)); axis.addLine(to: CGPoint(x: 765, y: 450))
            context.stroke(axis, with: .color(white.opacity(0.45)), style: StrokeStyle(lineWidth: 4, dash: [18, 14]))
        }
        var dimension = Path()
        dimension.move(to: CGPoint(x: 287, y: 865)); dimension.addLine(to: CGPoint(x: 737, y: 865))
        for x: CGFloat in [287, 737] {
            dimension.move(to: CGPoint(x: x, y: 845)); dimension.addLine(to: CGPoint(x: x, y: 885))
        }
        context.stroke(dimension, with: .color(white.opacity(0.7)), lineWidth: small ? 14 : 6)
        context.fill(Path(ellipseIn: CGRect(x: 512 - 88, y: 596 - 88, width: 176, height: 176)),
                     with: Self.vertical(Self.orange, from: 508, to: 684))
    }

    // MARK: Shared pieces

    private static let orange = [rgb(0xffc65a), rgb(0xffa01c)]

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    private static func vertical(_ colors: [Color], from top: CGFloat, to bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }

    /// Hatch's arch as a centreline: two legs ending at `yb` and a half circle of radius `rc` centred at (`cx`, `yc`).
    private static func arch(cx: CGFloat, rc: CGFloat, yc: CGFloat, yb: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx - rc, y: yb))
        p.addLine(to: CGPoint(x: cx - rc, y: yc))
        p.addArc(center: CGPoint(x: cx, y: yc), radius: rc, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: cx + rc, y: yb))
        return p
    }
}

enum StageIcon {
    /// The digits of a ticket reference ("151" from "151"); a draft reference such as "new-7" has no number to show.
    static func digits(from reference: String?) -> String? {
        guard let reference, !reference.isEmpty, reference.allSatisfy(\.isNumber) else { return nil }
        return reference
    }

    @MainActor static func image(_ kind: AppIconKind = .stage, number: String? = nil, small: Bool = false) -> NSImage? {
        let renderer = ImageRenderer(content: StageIconView(kind: kind, number: number, small: small))
        renderer.scale = 1
        return renderer.nsImage
    }

    /// Writes a 1024 pt PNG; `--render-icon`.
    @MainActor static func writePNG(to url: URL, kind: AppIconKind = .stage, number: String? = nil, small: Bool = false) -> Bool {
        _ = NSApplication.shared
        guard let image = image(kind, number: number, small: small), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: url); return true } catch { return false }
    }
}
