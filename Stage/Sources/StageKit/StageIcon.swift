import SwiftUI
import AppKit

/// The app icons of the family, all built on Hatch's sunrise (decisions AI4, AI5): Hatch itself (the sun half risen over the
/// sea, its reflection as dashes), the Stage (a loupe with the sunrise in its lens) and the Components Designer (a switch whose
/// track is the sky and sea and whose knob is the sun). Each has a light and a dark colouring.
///
/// One drawing serves two uses. `--render-icon … --full` writes full-bleed artwork for an Icon Composer file (macOS masks it and
/// adds the depth), which `tools/build-stage.sh` and `tools/render-app-icons.sh` turn into the bundles' icons. The tile form, with
/// its own rounded square and shadow, is what a running app sets as `NSApp.applicationIconImage`: the Stage's carries its ticket
/// number in the lens (drawn locally, no model call, no asset per ticket).
enum AppIconKind: String {
    case hatch
    case stage
    case designer
}

/// Drawn in an 824 pt square, the macOS icon tile. The tile form centres it on a 1024 pt canvas; the full form scales it to 1024.
struct StageIconView: View {
    var kind: AppIconKind = .stage
    /// Digits for the Stage's lens; `nil` shows the sunrise.
    var number: String?
    var dark = false
    /// Full-bleed artwork for an Icon Composer layer: no tile, no shadow, no border.
    var full = false

    var body: some View {
        if full {
            Canvas { context, _ in
                context.scaleBy(x: 1024 / 824, y: 1024 / 824)
                draw(&context)
            }
            .frame(width: 1024, height: 1024)
        } else {
            let tile = RoundedRectangle(cornerRadius: 185, style: .continuous)
            ZStack {
                Canvas { context, _ in
                    context.clip(to: tile.path(in: CGRect(x: 0, y: 0, width: 824, height: 824)))
                    draw(&context)
                }
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.32), radius: 14, y: 14)
                tile.strokeBorder(borderColor, lineWidth: 2)
                    .frame(width: 824, height: 824)
            }
            .frame(width: 1024, height: 1024)
        }
    }

    private var borderColor: Color {
        dark || kind == .stage ? Color.white.opacity(0.12) : Self.rgb(0x14285a).opacity(0.16)
    }

    private func draw(_ context: inout GraphicsContext) {
        switch kind {
        case .hatch: drawHatch(&context)
        case .stage: drawStage(&context)
        case .designer: drawDesigner(&context)
        }
    }

    // MARK: The sunrise

    private struct Palette {
        var sky: [Color]
        var sea: [Color]
        var glow: Color?
    }

    private static let lightPalette = Palette(sky: [rgb(0xffffff), rgb(0xe8edf7)], sea: [rgb(0x4180f0), rgb(0x1f49aa)], glow: nil)
    private static let darkPalette = Palette(sky: [rgb(0x18234a), rgb(0xf6b48a)], sea: [rgb(0x24408f), rgb(0x0d1a45)], glow: rgb(0xffb347))
    private var palette: Palette { dark ? Self.darkPalette : Self.lightPalette }
    private static let sun = [rgb(0xffd27a), rgb(0xffa01c)]

    /// Hatch's sunrise in a box: sky, glow (dark only), the sun, the sea over the sun's lower half, and the reflection.
    /// `dashes` are (width, opacity, line width, depth from the horizon as a share of the sea).
    private func sunrise(_ context: inout GraphicsContext, box: CGRect, horizon: CGFloat, sunX: CGFloat, radius: CGFloat,
                         palette: Palette, dashes: [(CGFloat, Double, CGFloat, CGFloat)]) {
        context.fill(Path(box), with: Self.vertical(palette.sky, from: box.minY, to: horizon))
        if let glow = palette.glow {
            let r = radius * 2.1
            context.fill(Path(ellipseIn: CGRect(x: sunX - r, y: horizon - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(stops: [.init(color: glow.opacity(0.75), location: 0),
                                                                .init(color: glow.opacity(0.28), location: 0.45),
                                                                .init(color: glow.opacity(0), location: 1)]),
                                               center: CGPoint(x: sunX, y: horizon), startRadius: 0, endRadius: r))
        }
        context.fill(Path(ellipseIn: CGRect(x: sunX - radius, y: horizon - radius, width: radius * 2, height: radius * 2)),
                     with: Self.vertical(Self.sun, from: horizon - radius, to: horizon))
        context.fill(Path(CGRect(x: box.minX, y: horizon, width: box.width, height: box.maxY - horizon)),
                     with: Self.vertical(palette.sea, from: horizon, to: box.maxY))
        let depth = box.maxY - horizon
        for (width, opacity, line, share) in dashes {
            var dash = Path()
            let y = horizon + depth * share
            dash.move(to: CGPoint(x: sunX - width / 2, y: y))
            dash.addLine(to: CGPoint(x: sunX + width / 2, y: y))
            context.stroke(dash, with: Self.vertical(Self.sun.map { $0.opacity(opacity) }, from: y - line, to: y + line),
                           style: StrokeStyle(lineWidth: line, lineCap: .round))
        }
    }

    // MARK: Hatch: the sunrise, its reflection shortening towards you (AI4)

    private func drawHatch(_ context: inout GraphicsContext) {
        sunrise(&context, box: CGRect(x: 0, y: 0, width: 824, height: 824), horizon: 490, sunX: 412, radius: 200, palette: palette,
                dashes: [(300, 0.95, 30, 0.17), (210, 0.75, 26, 0.34), (132, 0.55, 22, 0.51), (72, 0.40, 18, 0.68)])
    }

    // MARK: Stage: a loupe with the sunrise in its lens (AI1, AI5)

    private func drawStage(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 824, height: 824)), with: Self.vertical([Self.rgb(0x1f2b4f), Self.rgb(0x0d1530)], from: 0, to: 824))
        let lens = CGPoint(x: 370, y: 370), r: CGFloat = 220
        var handle = Path()
        handle.move(to: CGPoint(x: lens.x + 150, y: lens.y + 150))
        handle.addLine(to: CGPoint(x: 670, y: 670))
        context.stroke(handle, with: Self.vertical([Self.rgb(0xffc65a), Self.rgb(0xff9a10)], from: 520, to: 670),
                       style: StrokeStyle(lineWidth: 92, lineCap: .round))

        let box = CGRect(x: lens.x - r, y: lens.y - r, width: r * 2, height: r * 2)
        let glass = Path(ellipseIn: box)
        context.drawLayer { inside in
            inside.clip(to: glass)
            if let number, !number.isEmpty {
                // The number in the sky of the lens, the sea kept below it. Sized for three digits; seven still fit.
                inside.fill(Path(box), with: .color(Self.rgb(0xeef3fb)))
                inside.fill(Path(CGRect(x: box.minX, y: lens.y + 120, width: box.width, height: r)),
                            with: Self.vertical(Self.lightPalette.sea, from: lens.y + 120, to: box.maxY))
                let size: CGFloat = [1: 300, 2: 260, 3: 200, 4: 150][number.count] ?? max(70, 600 / CGFloat(number.count))
                inside.draw(Text(number).font(.system(size: size, weight: .heavy)).tracking(-8).foregroundStyle(Self.rgb(0x1f49aa)),
                            at: CGPoint(x: lens.x, y: lens.y + 70 - size * 0.36))
            } else {
                sunrise(&inside, box: box, horizon: lens.y + 60, sunX: lens.x, radius: 110, palette: palette,
                        dashes: [(165, 0.95, 16.5, 0.2), (115.5, 0.75, 14.3, 0.4), (72.6, 0.55, 12.1, 0.6)])
            }
        }
        context.stroke(glass, with: .color(Self.rgb(0xc9d6f0)), lineWidth: 34)
    }

    // MARK: Components Designer: a switch, the track the sky and sea, the knob the sun (AI5)

    private func drawDesigner(_ context: inout GraphicsContext) {
        let tileColors = dark ? [Self.rgb(0x1f2b4f), Self.rgb(0x0d1530)] : [Self.rgb(0xffffff), Self.rgb(0xe8edf7)]
        context.fill(Path(CGRect(x: 0, y: 0, width: 824, height: 824)), with: Self.vertical(tileColors, from: 0, to: 824))
        let track = CGRect(x: 70, y: 242, width: 684, height: 340)
        let shape = Path(roundedRect: track, cornerRadius: 170)
        var colors = palette
        if !dark { colors.sky = [Self.rgb(0xd5e1f7), Self.rgb(0xbccdef)] }
        context.drawLayer { inside in
            inside.clip(to: shape)
            sunrise(&inside, box: track, horizon: 442, sunX: 584, radius: 130, palette: colors, dashes: [])
            for (i, (x, w)) in [(CGFloat(150), CGFloat(260)), (200, 160)].enumerated() {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 492 + CGFloat(i) * 44))
                line.addLine(to: CGPoint(x: x + w, y: 492 + CGFloat(i) * 44))
                inside.stroke(line, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 18, lineCap: .round))
            }
        }
        context.stroke(shape, with: .color((dark ? Color.white : Self.rgb(0x1f49aa)).opacity(0.30)), lineWidth: 8)
        let knob = Path(ellipseIn: CGRect(x: 584 - 140, y: 412 - 140, width: 280, height: 280))
        context.fill(knob, with: Self.vertical(Self.sun, from: 272, to: 552))
        context.stroke(knob, with: .color(.white), lineWidth: 16)
    }

    // MARK: Shared pieces

    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    private static func vertical(_ colors: [Color], from top: CGFloat, to bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }
}

enum StageIcon {
    /// The digits of a ticket reference ("151" from "151"); a draft reference such as "new-7" has no number to show.
    static func digits(from reference: String?) -> String? {
        guard let reference, !reference.isEmpty, reference.allSatisfy(\.isNumber) else { return nil }
        return reference
    }

    /// The tile form for `NSApp.applicationIconImage`, in the colouring of the app's current appearance.
    @MainActor static func image(_ kind: AppIconKind = .stage, number: String? = nil, dark: Bool? = nil, full: Bool = false) -> NSImage? {
        let isDark = dark ?? (NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let renderer = ImageRenderer(content: StageIconView(kind: kind, number: number, dark: isDark, full: full))
        renderer.scale = 1
        return renderer.nsImage
    }

    /// Writes a 1024 px PNG; `--render-icon`.
    @MainActor static func writePNG(to url: URL, kind: AppIconKind = .stage, number: String? = nil, dark: Bool = false, full: Bool = false) -> Bool {
        _ = NSApplication.shared
        guard let image = image(kind, number: number, dark: dark, full: full), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: url); return true } catch { return false }
    }
}
