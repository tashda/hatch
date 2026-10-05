import XCTest
@testable import HatchCore

/// The app's pictures of its own views (CM21): the marks contract, what a capture run writes, and what Hatch reads.
final class ComponentCapturesTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    /// Hatch's app and its Stage carry the contract file exactly as Hatch writes it.
    func testHatchsOwnCopiesOfTheMarksFileAreCurrent() throws {
        for path in ["App/Sources/HatchApp/Components/HatchMarks.swift", "Stage/Sources/StageKit/HatchMarks.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertEqual(text, ComponentMarks.appFile, "\(path) is out of date: hatch components marks-file --write \(path)")
        }
    }
}

extension ComponentCapturesTests {
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("captures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ file: CaptureFile, _ name: String, in dir: URL) throws {
        try JSONEncoder().encode(file).write(to: dir.appendingPathComponent(name + ".json"))
        try Data([0x89]).write(to: dir.appendingPathComponent(name + ".png"))
    }

    /// A run's screens are read with every use of a view; a view drawn as siblings (one instance) is one frame around them.
    func testScreensAreReadAndAViewsPartsAreJoined() throws {
        let dir = try folder()
        try write(CaptureFile(scale: 2, size: [800, 600], marks: [
            .init(name: "TicketRow", frame: [0, 0, 400, 40]),
            .init(name: "HXChip", frame: [300, 10, 60, 18], parent: 0),
            .init(name: "ToolbarActions", frame: [600, 4, 28, 28], instance: 7),
            .init(name: "ToolbarActions", frame: [632, 4, 28, 28], instance: 7),
            .init(name: "HXChip", frame: [300, 50, 60, 18], visible: [300, 50, 60, 9]),
        ]), "desk-light", in: dir)
        try write(CaptureFile(scale: 2, size: [500, 300], marks: [.init(name: "HXChip", frame: [10, 10, 180, 20])]), "component-gallery-light", in: dir)
        let captures = try XCTUnwrap(ComponentCaptures.load(from: dir))
        XCTAssertEqual(Set(captures.screens.map(\.name)), ["desk", "component-gallery"])
        let desk = try XCTUnwrap(captures.screens.first { $0.name == "desk" })
        XCTAssertEqual(desk.file.marks.count, 4, "the toolbar's two parts are one use")
        XCTAssertEqual(desk.file.marks.first { $0.name == "ToolbarActions" }?.frame, [600, 4, 60, 28])
        XCTAssertEqual(desk.file.marks.last?.parent, nil)
        XCTAssertEqual(captures.places(of: "HXChip", dark: false).map(\.screen.name), ["desk", "desk", "component-gallery"], "screens first")
        XCTAssertEqual(captures.places(of: "HXChip", dark: false).map(\.whole), [true, false, true], "half scrolled away")
        XCTAssertTrue(captures.best(of: "HXChip", dark: false)!.screen.isGallery, "the gallery's sample is drawn on purpose")
        XCTAssertEqual(captures.best(of: "TicketRow", dark: false)?.pixels, CaptureRect(x: 0, y: 0, width: 800, height: 80))
        XCTAssertEqual(captures.screens(of: "HXChip").first?.count, 2)
        XCTAssertEqual(captures.drawn, ["TicketRow", "HXChip", "ToolbarActions"])
    }

    /// Kept in the notebook: the gallery beside the system, screens in their folder with their pictures left out of git.
    func testKeepingACaptureRun() throws {
        let run = try folder(), notebook = try folder()
        try write(CaptureFile(scale: 2, size: [800, 600], marks: [.init(name: "HXChip", frame: [1, 1, 10, 10])]), "desk-dark", in: run)
        try write(CaptureFile(scale: 2, size: [500, 300], marks: []), "component-gallery-light", in: run)
        let kept = try ComponentCaptures.keep(from: run, notebook: notebook.path)
        let target = notebook.appendingPathComponent(ComponentCaptures.notebookPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("component-gallery-light.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("screens/desk-dark.json").path))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("screens/.gitignore"), encoding: .utf8), "*.png\n")
        XCTAssertEqual(kept.drawn, ["HXChip"])
        XCTAssertThrowsError(try ComponentCaptures.keep(from: try folder(), notebook: notebook.path), "an empty run keeps nothing")
    }

    /// What keeps a view out of the pictures, and the ticket that fixes it: an agent marks, draws and runs the capture.
    func testCoverageAndTheTicketToDrawTheRest() throws {
        let app = try folder()
        try """
        struct HXChip: View { let text: String; var body: some View { Text(text).font(.caption).padding(.horizontal, 7).background(.blue, in: Capsule()).hatchMark("HXChip") } }
        struct PlainChip: View { let text: String; var body: some View { Text(text).font(.caption).padding(.horizontal, 7).background(.gray, in: Capsule()).hatchMark("PlainChip", layered: true) } }
        struct BadgeDot: View { var body: some View { Circle().fill(.red).padding(2).background(.white, in: Circle()) } }
        """.write(to: app.appendingPathComponent("Chips.swift"), atomically: true, encoding: .utf8)
        let shots = try folder()
        try write(CaptureFile(scale: 2, size: [800, 600], marks: [.init(name: "HXChip", frame: [1, 1, 10, 10])]), "desk-light", in: shots)
        let model = AppViewScanner.scan(appRoot: app.path)
        let coverage = ComponentMarks.coverage(model, root: app.path, captures: ComponentCaptures.load(from: shots))
        XCTAssertEqual(coverage.drawn, ["HXChip"])
        XCTAssertTrue(coverage.unmarked.contains("BadgeDot"))
        XCTAssertEqual(coverage.offScreen, ["PlainChip"], "marked, but no screen shows it")
        XCTAssertFalse(coverage.complete)
        let draft = ComponentMarks.drawDraft(coverage, hasMarksFile: false, hasCommand: false)
        XCTAssertEqual(draft.type, .tweak)
        XCTAssertTrue(draft.body.contains("hatch components marks-file"))
        XCTAssertTrue(draft.body.contains("- BadgeDot") && draft.body.contains("- PlainChip"))
        XCTAssertTrue(draft.body.contains("hatch-capture.sh"))
        XCTAssertTrue(draft.body.contains("Done when"))
        XCTAssertFalse(ComponentMarks.drawDraft(coverage, hasMarksFile: true, hasCommand: true).body.contains("hatch-capture.sh"))
    }

    func testTheCaptureCommand() throws {
        let app = try folder()
        XCTAssertNil(ComponentCaptures.command(appRoot: app.path, configured: nil))
        XCTAssertEqual(ComponentCaptures.command(appRoot: app.path, configured: "make shots"), "make shots")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("tools"), withIntermediateDirectories: true)
        try "".write(to: app.appendingPathComponent("tools/hatch-capture.sh"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ComponentCaptures.command(appRoot: app.path, configured: nil), "sh tools/hatch-capture.sh")
    }
}
