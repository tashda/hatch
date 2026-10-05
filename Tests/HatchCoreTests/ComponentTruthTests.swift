import XCTest
@testable import HatchCore

/// The measured checks on real screens (CM23). The cases are the ones the owner caught by eye on 2026-10-05: tiles
/// drawn over each other, a control reaching out of its card, and the cases that must not count: a badge placed on a
/// card, content scrolling under a bar, a pin layered over a specimen.
final class ComponentTruthTests: XCTestCase {
    private func screen(_ marks: [CaptureFile.Mark], name: String = "desk") -> CapturedScreen {
        CapturedScreen(name: name, dark: false, picture: URL(fileURLWithPath: "/dev/null"), file: CaptureFile(scale: 2, size: [1000, 800], marks: marks))
    }

    func testTilesDrawnOverEachOtherAreAProblem() {
        let found = ComponentTruth.frameFindings(screen([
            .init(name: "Page", frame: [0, 0, 1000, 800]),
            .init(name: "Tile", frame: [20, 20, 300, 200]),
            .init(name: "Tile", frame: [250, 20, 300, 200]),
            .init(name: "Tile", frame: [600, 20, 300, 200]),
        ]))
        XCTAssertEqual(found.map(\.kind), [.overlap])
        XCTAssertEqual(found.first?.views, ["Tile", "Tile"])
        XCTAssertEqual(found.first?.frame, CaptureRect(x: 250, y: 20, width: 70, height: 200))
        XCTAssertTrue(found.allSatisfy(\.problem))
    }

    func testAControlReachingOutOfItsCard() {
        let found = ComponentTruth.frameFindings(screen([
            .init(name: "SectionCard", frame: [20, 20, 300, 120]),
            .init(name: "WideButton", frame: [40, 60, 340, 28]),
        ]))
        XCTAssertEqual(found.map(\.kind), [.outside])
        XCTAssertTrue(found[0].words.contains("WideButton reaches 60 pt out of SectionCard"), found[0].words)
    }

    func testWhatIsPutThereOnPurposeIsNotAFinding() {
        let found = ComponentTruth.frameFindings(screen([
            // A count badge on a card's corner, wholly inside it.
            .init(name: "Card", frame: [20, 20, 300, 120]),
            .init(name: "CountBadge", frame: [300, 24, 16, 16]),
            // Rows scrolling under a footer bar that floats over them.
            .init(name: "Row", frame: [0, 760, 1000, 40], scroll: 1),
            .init(name: "Footer", frame: [0, 770, 1000, 30]),
            // A pin layered over a specimen.
            .init(name: "Specimen", frame: [400, 200, 200, 100]),
            .init(name: "PinBadge", frame: [580, 190, 30, 30], layered: true),
        ]))
        XCTAssertEqual(found, [], found.map(\.words).joined(separator: "; "))
    }

    func testAChipDrawnAtDifferentHeightsIsANote() {
        let a = screen([.init(name: "HXChip", frame: [10, 10, 60, 18])], name: "desk")
        let b = screen([.init(name: "HXChip", frame: [10, 10, 60, 24])], name: "board")
        let captures = ComponentCaptures(folder: URL(fileURLWithPath: "/tmp"), screens: [a, b])
        let found = ComponentTruth.check(captures, families: ["HXChip": "chip"])
        XCTAssertEqual(found.map(\.kind), [.drift])
        XCTAssertFalse(found[0].problem)
        XCTAssertTrue(found[0].words.contains("18 pt on Desk") && found[0].words.contains("24 pt on Board"), found[0].words)
        XCTAssertEqual(ComponentTruth.check(captures, families: ["HXChip": "card"]), [], "a card grows with what it holds")
    }

    /// The canvas against macOS (CM25): a role drawn at another size is a problem; one side only is a note; a toolbar's
    /// sizes are not compared (its glass is drawn outside the control) and its look is compared in the canvas item's box.
    func testTheCanvasIsMeasuredAgainstTheRealContainer() {
        let canvas = screen([.init(name: "role:button.primary", frame: [10, 10, 80, 22]), .init(name: "role:field.search", frame: [100, 10, 120, 22])],
                            name: "designer-canvas-form")
        let real = screen([.init(name: "role:button.primary", frame: [400, 50, 64, 28]), .init(name: "role:toggle.setting", frame: [400, 90, 40, 20])],
                          name: "designer-real-form")
        let found = ComponentTruth.compareCanvas(place: "form", canvas: canvas, real: real)
        XCTAssertEqual(found.filter(\.problem).map(\.views), [["button.primary"]])
        XCTAssertTrue(found.first { $0.problem }!.words.contains("80×22 pt; macOS draws it 64×28 pt"), found.map(\.words).joined(separator: "; "))
        XCTAssertEqual(Set(found.filter { !$0.problem }.flatMap(\.views)), ["field.search", "toggle.setting"])
        var asked: CaptureRect?
        let toolbar = ComponentTruth.compareCanvas(place: "toolbar", canvas: canvas, real: real, centered: true) { _, _, _, r in asked = r; return 0.02 }
        XCTAssertTrue(toolbar.allSatisfy { !$0.problem }, "no size check in a toolbar")
        XCTAssertEqual(asked, CaptureRect(x: 392, y: 53, width: 80, height: 22), "the canvas item's box, centred on the real one")
    }

    func testOnlyTheTicketsViewsCount() {
        let captures = ComponentCaptures(folder: URL(fileURLWithPath: "/tmp"), screens: [screen([
            .init(name: "Tile", frame: [20, 20, 300, 200]), .init(name: "Tile", frame: [250, 20, 300, 200]),
        ])])
        XCTAssertEqual(ComponentTruth.check(captures, only: ["Tile"]).count, 1)
        XCTAssertEqual(ComponentTruth.check(captures, only: ["HXChip"]), [])
    }

    #if canImport(Vision) && canImport(AppKit)
    /// Text cut to a word or less ("D…", the owner's case) is a problem; the app's own "Draw Them…" is not a cut.
    func testCutTextIsReadFromThePicture() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("truth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Drawn at 2x, as the app's screens are captured.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 400).fill()
        let font = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black]
        ("Bui…" as NSString).draw(at: NSPoint(x: 60, y: 300), withAttributes: font)
        ("Draw Them…" as NSString).draw(at: NSPoint(x: 60, y: 120), withAttributes: font)
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("desk-light.png"))
        try JSONEncoder().encode(CaptureFile(scale: 2, size: [600, 200], marks: [
            .init(name: "StatusChip", frame: [20, 20, 200, 60]), .init(name: "Footer", frame: [20, 110, 300, 60]),
        ])).write(to: dir.appendingPathComponent("desk-light.json"))
        let captures = try XCTUnwrap(ComponentCaptures.load(from: dir))
        let found = ComponentTruth.cutText(captures, literals: ["Draw Them…", "…"])
        XCTAssertEqual(found.map(\.views), [["StatusChip"]], found.map(\.words).joined(separator: "; "))
        XCTAssertTrue(found.first?.problem == true, "a word or less is left")
    }
    #endif
}

/// Evidence before done (CM24): what `hatch ready` decides from the changed views and the screens Hatch drew.
final class ComponentEvidenceTests: XCTestCase {
    private func view(_ id: String, file: String = "App/Chips.swift") -> AppView {
        AppView(id: id, file: file, line: 1, kind: .component, reason: "r", family: "chip", style: AppViewStyle(), interactive: false, uses: 1, usedIn: [], bodyLines: 3)
    }
    private func captures(_ marks: [CaptureFile.Mark]) -> ComponentCaptures {
        ComponentCaptures(folder: URL(fileURLWithPath: "/tmp"), screens: [CapturedScreen(name: "desk", dark: false, picture: URL(fileURLWithPath: "/dev/null"),
                                                                                         file: CaptureFile(scale: 2, size: [800, 600], marks: marks))])
    }

    func testTheChangedViewsAreTheOnesInChangedFiles() {
        let model = AppViewModel(views: [view("HXChip"), view("BoardCard", file: "App/Board.swift")], proposals: [])
        XCTAssertEqual(ComponentEvidence.changedViews(model, changedFiles: ["App/Chips.swift"]).map(\.id), ["HXChip"])
    }

    func testAnAppThatDoesNotDrawItsScreensYetGetsANoteNotAFailure() {
        let steps = ComponentEvidence.judge(changed: [view("HXChip")], unmarked: ["HXChip"], optedIn: false, captureLog: nil, captures: nil, findings: [])
        XCTAssertTrue(steps.allSatisfy(\.ok))
        XCTAssertTrue(steps[0].detail.hasPrefix("note:"))
    }

    func testEveryChangedViewMustBeMarkedDrawnAndMeasured() {
        let drawn = captures([.init(name: "HXChip", frame: [1, 1, 60, 18])])
        let pass = ComponentEvidence.judge(changed: [view("HXChip")], unmarked: [], optedIn: true, captureLog: nil, captures: drawn, findings: [])
        XCTAssertEqual(pass.map(\.kind), ["marks", "captures", "screens"])
        XCTAssertTrue(pass.allSatisfy(\.ok), pass.map(\.detail).joined(separator: "; "))
        XCTAssertTrue(pass[1].detail.contains("desk"))

        let unmarked = ComponentEvidence.judge(changed: [view("NewChip")], unmarked: ["NewChip"], optedIn: true, captureLog: nil, captures: drawn, findings: [])
        XCTAssertFalse(unmarked[0].ok)

        let offScreen = ComponentEvidence.judge(changed: [view("NewChip")], unmarked: [], optedIn: true, captureLog: nil, captures: drawn, findings: [])
        XCTAssertFalse(offScreen[1].ok, "a changed view no screen shows is not checked, so not done")

        let overlap = TruthFinding(kind: .overlap, screen: "desk", dark: false, views: ["HXChip", "HXChip"], frame: .init(x: 0, y: 0, width: 5, height: 5),
                                   words: "Two HXChip draw over each other on Desk.", problem: true)
        let failed = ComponentEvidence.judge(changed: [view("HXChip")], unmarked: [], optedIn: true, captureLog: nil, captures: drawn, findings: [overlap])
        XCTAssertFalse(failed[2].ok)
        XCTAssertTrue(failed[2].detail.contains("draw over each other"))

        let broken = ComponentEvidence.judge(changed: [view("HXChip")], unmarked: [], optedIn: true, captureLog: "xcodebuild failed", captures: nil, findings: [])
        XCTAssertEqual(broken.last?.kind, "captures")
        XCTAssertFalse(broken.last!.ok)
    }
}
