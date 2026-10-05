import Foundation
#if canImport(Vision) && canImport(ImageIO)
import Vision
import ImageIO
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

        public var title: String {
            switch self {
            case .overlap: "Overlap"
            case .outside: "Outside its container"
            case .drift: "Sizes drift"
            case .cutText: "Text cut off"
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
        return out
    }

    /// Families whose views keep one height wherever they are drawn; a card or a row grows with what it holds.
    public static let fixedHeightFamilies: Set<String> = ["chip", "badge", "keycap", "glyph", "button"]

    /// The frame checks on every screen, light only (dark draws the same layout). `families`: each view's family, for
    /// the drift check. `only`: report only findings that touch these views (a ticket's changed views).
    public static func check(_ captures: ComponentCaptures, families: [String: String] = [:], only: Set<String>? = nil) -> [TruthFinding] {
        var out: [TruthFinding] = []
        for screen in captures.screens where !screen.dark && !screen.isGallery {
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
        let checked = marks.indices.filter { frames[$0].area > 4 && marks[$0].layered != true }
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
                    guard !fi.contains(fj), !fj.contains(fi), let both = fi.intersection(fj), both.width > 2, both.height > 2,
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
        for screen in captures.screens where !screen.dark {
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
