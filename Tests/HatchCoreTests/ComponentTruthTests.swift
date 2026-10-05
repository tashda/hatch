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
