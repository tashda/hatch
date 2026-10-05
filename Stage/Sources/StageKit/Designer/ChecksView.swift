import SwiftUI
import HatchCore

// What Hatch measured (CM23, CM25): on the app's own screens (views drawing over each other, reaching out of their
// container, drifting heights, cut text) and on this canvas against macOS. One table, grouped by kind, problems first;
// the selected finding's picture, with the place outlined, in the inspector. Nothing here is a judgement: each line is
// a measurement, and it names where.

struct ChecksView: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        let groups = TruthFinding.Kind.allCases.compactMap { k -> (TruthFinding.Kind, [TruthFinding])? in
            let fs = model.findings.filter { $0.kind == k }
            return fs.isEmpty ? nil : (k, fs)
        }
        VStack(alignment: .leading, spacing: 18) {
            Text("\(model.findings.filter(\.problem).count) problems and \(model.findings.filter { !$0.problem }.count) notes, measured on the app's screens and on this canvas. A problem stops a ticket that touches it at hatch ready.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(groups, id: \.0) { kind, fs in
                VStack(alignment: .leading, spacing: 7) {
                    Text(kind.title).font(.headline).padding(.horizontal, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(fs.enumerated()), id: \.offset) { i, f in
                            if i > 0 { Divider().padding(.leading, 14) }
                            CheckRow(model: model, finding: f)
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
                }
            }
        }
    }
}

private struct CheckRow: View {
    @ObservedObject var model: DesignerModel
    let finding: TruthFinding

    var body: some View {
        let selected = model.checkPick == finding
        VStack(alignment: .leading, spacing: 1) {
            Text(finding.words).fixedSize(horizontal: false, vertical: true)
            Text((finding.problem ? "Problem" : "Note") + " · " + (model.screen(of: finding)?.title ?? finding.screen)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { model.checkPick = finding }
        .hatchMark("CheckRow")
    }
}

struct CheckInspector: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let f = model.checkPick {
                    Text(f.kind.title).font(.title3.weight(.semibold))
                    Text(f.problem ? "Problem: a ticket that touches it can't be done" : "Note").foregroundStyle(.secondary).padding(.top, 2)
                    Text(f.words).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
                    if let screen = model.screen(of: f) {
                        CheckHeading(f.kind == .canvas ? "On the canvas" : "Where")
                        ScreenCut(model: model, screen: screen, frame: f.frame)
                        if let (real, frame) = model.realCounterpart(of: f) {
                            CheckHeading("What macOS draws")
                            ScreenCut(model: model, screen: real, frame: frame)
                        }
                    }
                    if f.kind != .canvas {
                        CheckHeading("Views")
                        Text(f.views.joined(separator: ", ")).font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Checks on Screen").font(.title3.weight(.semibold))
                    Text("Select a line to see where it is.").foregroundStyle(.secondary).padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CheckHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 16).padding(.bottom, 6).hatchMark("CheckHeading") }
}

/// A part of a screen around a rectangle, the rectangle outlined in the accent colour.
struct ScreenCut: View {
    @ObservedObject var model: DesignerModel
    let screen: CapturedScreen
    let frame: CaptureRect
    var height: CGFloat = 140

    var body: some View {
        let f = frame, b = screen.bounds
        let margin = max(24, max(f.width, f.height) * 0.4)
        let x0 = max(b.x, f.x - margin), y0 = max(b.y, f.y - margin)
        let around = CaptureRect(x: x0, y: y0, width: min(b.maxX, f.maxX + margin) - x0, height: min(b.maxY, f.maxY + margin) - y0)
        Group {
        if let image = model.crop(screen, around) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .overlay {
                    GeometryReader { g in
                        let k = g.size.width / max(1, around.width)
                        RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 2)
                            .frame(width: f.width * k + 6, height: f.height * k + 6)
                            .offset(x: (f.x - around.x) * k - 3, y: (f.y - around.y) * k - 3)
                    }
                }
                .frame(maxHeight: height, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
        } else {
            Text("The picture is on the Mac that drew it; Capture Again draws it here.").foregroundStyle(.secondary)
        }
        }
        .hatchMark("ScreenCut")
    }
}
