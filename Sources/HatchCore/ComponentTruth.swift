import Foundation
#if canImport(Vision) && canImport(ImageIO)
import Vision
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Measured checks of the app's real screens (decision CM23): what can be measured is never left to judgement, the
// agent's or a model's. Each finding names the screen, the views and where, from the frames the app wrote beside its
// pictures (`ComponentCaptures`) and, on a Mac, the text Vision reads in them. A problem fails `hatch ready` when it
// touches a view the ticket changed; a note is shown and kept.

public struct TruthFinding: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Two views side by side draw over each other.
        case overlap
        /// A view reaches out of the view it sits in.
        case outside
        /// One view drawn at different heights on different screens.
        case drift
        /// Text cut off with an ellipsis.
        case cutText
        /// The Designer's canvas draws a role unlike macOS draws it in the real container.
        case canvas

        public var title: String {
            switch self {
            case .overlap: "Overlap"
            case .outside: "Outside its container"
            case .drift: "Sizes drift"
            case .cutText: "Text cut off"
            case .canvas: "Canvas differs from macOS"
            }
        }
    }
    public var kind: Kind
    public var screen: String
    public var dark: Bool
    public var views: [String]
    /// Where on the screen, in points.
    public var frame: CaptureRect
    public var words: String
    /// A problem fails the gate; a note does not.
    public var problem: Bool

    public init(kind: Kind, screen: String, dark: Bool, views: [String], frame: CaptureRect, words: String, problem: Bool) {
        self.kind = kind; self.screen = screen; self.dark = dark; self.views = views; self.frame = frame; self.words = words; self.problem = problem
    }
}

public enum ComponentTruth {
    /// What the capture run measured of the Designer's canvas against macOS (CM25), beside the screens.
    public static let canvasFile = "canvas-truth.json"
    /// Every finding of the last capture, written by `hatch components capture` for the Designer to read.
    public static let findingsFile = "truth.json"

    /// The screens that show the app (not the canvas measurements, which are compared, not checked).
    static func isAppScreen(_ s: CapturedScreen) -> Bool { !s.name.contains("canvas-") && !s.name.contains("real-") }

    /// The findings kept beside the captures, if any.
    public static func kept(in folder: URL) -> [TruthFinding] {
        (try? JSONDecoder().decode([TruthFinding].self, from: Data(contentsOf: folder.appendingPathComponent(findingsFile)))) ?? []
    }
    /// Every measured check: the frames, and on a Mac the text, with the app's code read for the views' families and
    /// its own strings. `only`: a ticket's changed views.
    public static func measure(_ captures: ComponentCaptures, appRoot: String?, excluding: [String] = [], only: Set<String>? = nil) -> [TruthFinding] {
        var families: [String: String] = [:], literals = Set<String>()
        if let appRoot {
            let files = ComponentInventoryScanner.appFiles(appRoot: appRoot, excluding: excluding)
            for v in AppViewScanner.scan(files: files).views { if let f = v.family { families[v.id] = f } }
            let re = ComponentReader.re(#""((?:[^"\\\n]|\\.){1,120})""#)
            for f in files {
                for m in re.matches(in: f.text, range: NSRange(f.text.startIndex..., in: f.text)) {
                    if let r = Range(m.range(at: 1), in: f.text) { literals.insert(String(f.text[r])) }
                }
            }
        }
        var out = check(captures, families: families, only: only)
        #if canImport(Vision) && canImport(ImageIO)
        out += cutText(captures, literals: literals, only: only)
        #endif
        if only == nil, let data = try? Data(contentsOf: captures.folder.appendingPathComponent(canvasFile)),
           let canvas = try? JSONDecoder().decode([TruthFinding].self, from: data) {
            out += canvas
        }
        return out
    }

    /// Families whose views keep one height wherever they are drawn; a card or a row grows with what it holds.
    public static let fixedHeightFamilies: Set<String> = ["chip", "badge", "keycap", "glyph", "button"]

    /// The frame checks on every screen, light only (dark draws the same layout). `families`: each view's family, for
    /// the drift check. `only`: report only findings that touch these views (a ticket's changed views).
    public static func check(_ captures: ComponentCaptures, families: [String: String] = [:], only: Set<String>? = nil) -> [TruthFinding] {
        var out: [TruthFinding] = []
        for screen in captures.screens where !screen.dark && !screen.isGallery && isAppScreen(screen) {
            out += frameFindings(screen)
        }
        out += drift(captures, families: families)
        guard let only else { return out }
        return out.filter { !$0.views.allSatisfy { !only.contains($0) } }
    }

    /// Overlap between views side by side, and views reaching out of the one they sit in. Nesting is read from the
    /// frames (a mark is a background beside its view, never around the views inside it): a view sits in the smallest
    /// view that holds it whole. Views the app marks as layered on purpose (a pin, an overlay) are left out.
    static func frameFindings(_ screen: CapturedScreen) -> [TruthFinding] {
        let marks = screen.file.marks
        let frames = marks.indices.map { screen.frame($0) ?? CaptureRect(x: 0, y: 0, width: 0, height: 0) }
        let checked = marks.indices.filter { frames[$0].area > 4 && marks[$0].layered != true && !marks[$0].name.hasPrefix("role:") }
        func holder(_ i: Int) -> Int? {
            checked.filter { $0 != i && frames[$0].area > frames[i].area && frames[$0].contains(frames[i], slack: 1) }.min { frames[$0].area < frames[$1].area }
        }
        let parents = Dictionary(uniqueKeysWithValues: checked.map { ($0, holder($0) ?? -1) })
        var out: [TruthFinding] = [], reached = Set<Int>()
        // Reaching out: the smallest view under its middle is much larger and doesn't hold it whole.
        for i in checked {
            let f = frames[i], mid = CaptureRect(x: f.x + f.width / 2, y: f.y + f.height / 2, width: 0.1, height: 0.1)
            guard let c = checked.filter({ $0 != i && frames[$0].area > 2 * f.area && frames[$0].contains(mid) && marks[$0].scroll == marks[i].scroll })
                    .min(by: { frames[$0].area < frames[$1].area }), !frames[c].contains(f, slack: 2), parents[i] != c else { continue }
            let cf = frames[c]
            let past = max(cf.x - f.x, f.maxX - cf.maxX, cf.y - f.y, f.maxY - cf.maxY)
            guard past > 2, let v = screen.visible(i), abs(v.width - f.width) < 1, abs(v.height - f.height) < 1 else { continue }
            reached.insert(i)
            out.append(TruthFinding(kind: .outside, screen: screen.name, dark: screen.dark, views: [marks[i].name, marks[c].name], frame: f,
                                    words: "\(marks[i].name) reaches \(Int(past.rounded())) pt out of \(marks[c].name) on \(screen.title).", problem: true))
        }
        // Overlap: two views in the same place (same holder, same scroll view) covering part of each other.
        let siblings = Dictionary(grouping: checked.filter { !reached.contains($0) }, by: { parents[$0] ?? -1 })
        for (_, group) in siblings {
            for (a, i) in group.enumerated() {
                for j in group[(a + 1)...] where marks[i].scroll == marks[j].scroll {
                    let fi = frames[i], fj = frames[j]
                    // A view a few points past the edge of one around it sits in it (a chip on a card's edge), not over it.
                    guard !fi.contains(fj, slack: 3), !fj.contains(fi, slack: 3), let both = fi.intersection(fj), both.width > 2, both.height > 2,
                          both.area > 0.15 * min(fi.area, fj.area) else { continue }
                    let names = [marks[i].name, marks[j].name]
                    out.append(TruthFinding(kind: .overlap, screen: screen.name, dark: screen.dark, views: names, frame: both,
                                            words: names[0] == names[1] ? "Two \(names[0]) draw over each other on \(screen.title)."
                                                                        : "\(names[0]) and \(names[1]) draw over each other on \(screen.title).",
                                            problem: true))
                }
            }
        }
        return out
    }

    /// A view of a fixed-height family drawn at different heights on different screens.
    static func drift(_ captures: ComponentCaptures, families: [String: String]) -> [TruthFinding] {
        var out: [TruthFinding] = []
        for id in captures.drawn.sorted() where fixedHeightFamilies.contains(families[id] ?? "") {
            let places = captures.places(of: id, dark: false).filter { $0.whole && !$0.screen.isGallery }
            let heights = Dictionary(grouping: places, by: { ($0.frame.height * 2).rounded() / 2 })
            guard heights.count > 1, let lo = heights.keys.min(), let hi = heights.keys.max(), hi - lo > 1.5 else { continue }
            let words = heights.keys.sorted().map { h in "\(AppViewStyle.n(h)) pt on " + Set(heights[h]!.map(\.screen.title)).sorted().prefix(3).joined(separator: ", ") }
            out.append(TruthFinding(kind: .drift, screen: places[0].screen.name, dark: false, views: [id], frame: places[0].frame,
                                    words: "\(id) is drawn at \(heights.count) heights: " + words.joined(separator: "; ") + ".", problem: false))
        }
        return out
    }

    #if canImport(Vision) && canImport(ImageIO)
    /// Text cut off with an ellipsis, read by Vision on the screens' pictures (light only), inside a marked view. A cut
    /// that leaves a word or less ("D…", "Bui…") is a problem; a long title cut in a list is a note. Text the app writes
    /// with an ellipsis itself ("Draw Them…") is left out: `literals` are the app's strings.
    public static func cutText(_ captures: ComponentCaptures, literals: Set<String>, only: Set<String>? = nil) -> [TruthFinding] {
        var out: [TruthFinding] = []
        // The words before the app's own ellipses ("Draw Them…" → "Draw Them"); a lone "…" says nothing.
        let own = literals.filter { $0.hasSuffix("…") || $0.hasSuffix("...") }
            .map { $0.replacingOccurrences(of: "...", with: "…").dropLast().trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 }
        for screen in captures.screens where !screen.dark && isAppScreen(screen) {
            guard let source = CGImageSourceCreateWithURL(screen.picture as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let size = screen.bounds
            for o in request.results ?? [] {
                guard let text = o.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces) else { continue }
                guard text.hasSuffix("…") || text.hasSuffix("...") else { continue }
                let clean = text.replacingOccurrences(of: "...", with: "…")
                let stem = clean.dropLast().trimmingCharacters(in: .whitespaces)
                if own.contains(where: { stem.hasSuffix($0) }) { continue }
                let b = o.boundingBox
                let rect = CaptureRect(x: b.minX * size.width, y: (1 - b.maxY) * size.height, width: b.width * size.width, height: b.height * size.height)
                // The smallest marked view around it is the one that cut it.
                let around = screen.file.marks.indices.compactMap { i -> (String, CaptureRect)? in
                    guard let f = screen.frame(i), f.contains(rect, slack: 3) else { return nil }
                    return (screen.file.marks[i].name, f)
                }.min { $0.1.area < $1.1.area }
                guard let around else { continue }
                if let only, !only.contains(around.0) { continue }
                let kept = clean.dropLast().trimmingCharacters(in: .whitespaces)
                out.append(TruthFinding(kind: .cutText, screen: screen.name, dark: false, views: [around.0], frame: rect,
                                        words: "“\(clean)” is cut off in \(around.0) on \(screen.title).", problem: kept.count <= 6))
            }
        }
        return out
    }
    #endif
}

public extension ComponentTruth {
    /// The Designer's canvas against macOS (CM25): a place drawn on the canvas and the same roles in the real container
    /// (a real toolbar, List, grouped Form…), both captured with each role marked `role:<id>`. A role drawn at another
    /// size, or looking different, is a problem: the canvas must show what macOS shows. `pixels` compares two cut-outs
    /// (0 the same, 1 opposite); nil leaves the look out.
    /// `centered`: the container draws chrome around the control (a toolbar's glass), so the real view's frame is smaller
    /// than what is seen; sizes are not compared, and the look is compared in a box the canvas control's size centred on
    /// the real one.
    /// `fills`: roles that take their row's width (a toggle in a form), so only their height is compared.
    static func compareCanvas(place: String, canvas: CapturedScreen, real: CapturedScreen, centered: Bool = false, inset: Double = 0, fills: Set<String> = [],
                              pixels: ((CapturedScreen, CaptureRect, CapturedScreen, CaptureRect) -> Double?)? = nil) -> [TruthFinding] {
        func roles(_ s: CapturedScreen) -> [String: CaptureRect] {
            var out: [String: CaptureRect] = [:]
            for (i, m) in s.file.marks.enumerated() where m.name.hasPrefix("role:") && out[m.name] == nil { out[m.name] = s.frame(i) }
            return out
        }
        let c = roles(canvas), r = roles(real)
        var out: [TruthFinding] = []
        for (name, rf) in r.sorted(by: { $0.key < $1.key }) {
            let role = String(name.dropFirst(5))
            guard let cf = c[name] else {
                out.append(TruthFinding(kind: .canvas, screen: real.name, dark: canvas.dark, views: [role], frame: rf,
                                        words: "In the \(place), macOS draws \(role) but the canvas doesn't.", problem: false))
                continue
            }
            // Past the canvas's own edges (its tiles sit `inset` points in from the window's sides): cut off on screen.
            if inset > 0, cf.x < inset - 6 || cf.maxX > canvas.bounds.width - inset + 6 {
                out.append(TruthFinding(kind: .canvas, screen: canvas.name, dark: canvas.dark, views: [role], frame: cf,
                                        words: "In the \(place), the canvas draws \(role) past the edge of its tile, so it is cut off.", problem: true))
                continue
            }
            let w = !fills.contains(role) && abs(cf.width - rf.width) > max(4, 0.15 * rf.width), h = abs(cf.height - rf.height) > max(3, 0.15 * rf.height)
            let seen = centered ? CaptureRect(x: rf.x + rf.width / 2 - cf.width / 2, y: rf.y + rf.height / 2 - cf.height / 2, width: cf.width, height: cf.height) : rf
            if !centered && (w || h) {
                out.append(TruthFinding(kind: .canvas, screen: canvas.name, dark: canvas.dark, views: [role], frame: cf,
                                        words: "In the \(place), the canvas draws \(role) \(Int(cf.width.rounded()))×\(Int(cf.height.rounded())) pt; macOS draws it \(Int(rf.width.rounded()))×\(Int(rf.height.rounded())) pt.",
                                        problem: true))
            } else if !fills.contains(role), let d = pixels?(canvas, cf, real, seen), d > 0.12 {
                out.append(TruthFinding(kind: .canvas, screen: canvas.name, dark: canvas.dark, views: [role], frame: cf,
                                        words: "In the \(place), the canvas draws \(role) the right size but it looks different from macOS (\(Int((d * 100).rounded()))% apart).",
                                        problem: true))
            }
        }
        for (name, cf) in c where r[name] == nil {
            out.append(TruthFinding(kind: .canvas, screen: canvas.name, dark: canvas.dark, views: [String(name.dropFirst(5))], frame: cf,
                                    words: "In the \(place), the canvas draws \(name.dropFirst(5)), which the real \(place) doesn't show.", problem: false))
        }
        return out
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    /// How far apart two cut-outs look: both scaled to the same small size, the mean difference of their colours (0…1).
    static func pictureDistance(_ a: CapturedScreen, _ ar: CaptureRect, _ b: CapturedScreen, _ br: CaptureRect) -> Double? {
        func pixels(_ s: CapturedScreen, _ r: CaptureRect, w: Int, h: Int) -> [UInt8]? {
            guard let src = CGImageSourceCreateWithURL(s.picture as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let k = s.file.scale
            guard let cut = image.cropping(to: CGRect(x: r.x * k, y: r.y * k, width: r.width * k, height: r.height * k)) else { return nil }
            var data = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .medium
            ctx.draw(cut, in: CGRect(x: 0, y: 0, width: w, height: h))
            return data
        }
        let w = 32, h = max(4, min(32, Int((32 * ar.height / max(1, ar.width)).rounded())))
        guard let p = pixels(a, ar, w: w, h: h), let q = pixels(b, br, w: w, h: h) else { return nil }
        var sum = 0.0
        for i in stride(from: 0, to: p.count, by: 4) { for c in 0..<3 { sum += abs(Double(p[i + c]) - Double(q[i + c])) } }
        return sum / Double(w * h * 3) / 255
    }
    #endif
}

/// Evidence before a UI ticket is done (CM24): `hatch ready` draws the ticket's workspace with the app's capture command,
/// and the views the ticket changed must be marked, drawn on a screen, and pass the measured checks there. The agent
/// can't say it looked; Hatch looks. Required once the app follows the marks contract; before that, a note.
public enum ComponentEvidence {
    public struct Step: Equatable, Sendable {
        public var kind: String
        public var ok: Bool
        public var detail: String
    }

    /// The app's own views declared in the files a ticket changed.
    public static func changedViews(_ model: AppViewModel, changedFiles: Set<String>) -> [AppView] {
        model.views.filter { v in [.component, .wrapper, .unknown].contains(v.kind) && changedFiles.contains { $0 == v.file || v.file.hasSuffix("/" + $0) || $0.hasSuffix("/" + v.file) } }
    }

    /// The steps `hatch ready` records, from what it found. `captures` is nil when the run failed or there is no command.
    public static func judge(changed: [AppView], unmarked: Set<String>, optedIn: Bool, captureLog: String?,
                             captures: ComponentCaptures?, findings: [TruthFinding]) -> [Step] {
        guard !changed.isEmpty else { return [] }
        let names = changed.map(\.id)
        guard optedIn else {
            return [Step(kind: "screens", ok: true, detail: "note: \(names.count) view(s) changed, but the app doesn't draw its screens for Hatch yet, so nobody checked them (Components Designer, Draw Them).")]
        }
        var steps: [Step] = []
        let missingMarks = names.filter(unmarked.contains)
        steps.append(Step(kind: "marks", ok: missingMarks.isEmpty, detail: missingMarks.isEmpty ? "the \(names.count) changed view(s) are marked"
                          : "end the body of " + missingMarks.joined(separator: ", ") + " with .hatchMark(\"<its name>\") so Hatch can find it on screen"))
        guard let captures else {
            steps.append(Step(kind: "captures", ok: false, detail: "the app's screens could not be drawn" + (captureLog.map { ":\n\($0)" } ?? ": it has no capture command (hatch-capture.sh).")))
            return steps
        }
        let off = names.filter { !captures.drawn.contains($0) && !missingMarks.contains($0) }
        steps.append(Step(kind: "captures", ok: off.isEmpty, detail: off.isEmpty
                          ? "drawn on " + Set(names.flatMap { captures.screens(of: $0).map(\.name) }).sorted().prefix(8).joined(separator: ", ")
                          : off.joined(separator: ", ") + " is on no screen the snapshot run draws: add the screen to the run, or the view to the gallery"))
        let problems = findings.filter(\.problem)
        steps.append(Step(kind: "screens", ok: problems.isEmpty, detail: problems.isEmpty
                          ? "no overlap, nothing reaching out, no cut words" + (findings.isEmpty ? "" : " (\(findings.count) note(s))")
                          : problems.prefix(8).map(\.words).joined(separator: "\n")))
        return steps
    }
}
