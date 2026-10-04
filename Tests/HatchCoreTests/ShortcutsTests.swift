import XCTest
@testable import HatchCore

final class ShortcutsTests: XCTestCase {
    func testDefaultsHaveNoClashes() {
        let clashes = ShortcutMap().clashes()
        XCTAssertTrue(clashes.isEmpty, clashes.map { "\($0.0.id) and \($0.1.id)" }.joined(separator: ", "))
    }

    func testIdsAreUniqueAndDefaultsAreValid() {
        let ids = ShortcutCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        let map = ShortcutMap()
        for c in ShortcutCatalog.all {
            guard let chord = c.defaultChord else { continue }
            XCTAssertTrue(chord.isValidKey, c.id)
            if c.scope == .app {
                XCTAssertTrue(chord.modifiers.contains(.command) || chord.modifiers.contains(.control), "\(c.id) needs ⌘ or ⌃")
            }
            XCTAssertEqual(map.chord(for: c.id), chord)
        }
    }

    func testDisplayOrderMatchesMacOS() {
        XCTAssertEqual(KeyChord("o", [.command, .shift]).display, "⇧⌘O")
        XCTAssertEqual(KeyChord("h", [.command, .control]).display, "⌃⌘H")
        XCTAssertEqual(KeyChord("return", .option).display, "⌥↩")
        XCTAssertEqual(KeyChord("K").symbols, ["K"])
    }

    func testOverrideWinsAndResetRestores() {
        var map = ShortcutMap()
        XCTAssertEqual(map.set(KeyChord("d", [.control, .command]), for: "page.desk"), .ok)
        XCTAssertEqual(map.chord(for: "page.desk"), KeyChord("d", [.control, .command]))
        XCTAssertTrue(map.isChanged("page.desk"))
        map.reset("page.desk")
        XCTAssertEqual(map.chord(for: "page.desk"), KeyChord("1", .command))
        XCTAssertFalse(map.isChanged("page.desk"))
    }

    func testSettingTheDefaultIsNoChange() {
        var map = ShortcutMap()
        map.set(KeyChord("d", [.control, .command]), for: "page.desk")
        map.set(KeyChord("1", .command), for: "page.desk")
        XCTAssertFalse(map.isChanged("page.desk"))
    }

    func testClearingLeavesNoShortcut() {
        var map = ShortcutMap()
        map.set(nil, for: "page.board")
        XCTAssertNil(map.chord(for: "page.board"))
        XCTAssertTrue(map.isChanged("page.board"))
    }

    func testConflictIsRefusedUnlessReplacing() {
        var map = ShortcutMap()
        // ⌘2 belongs to Tickets.
        if case .conflict(let other) = map.set(KeyChord("2", .command), for: "page.desk") {
            XCTAssertEqual(other.id, "page.tickets")
        } else { XCTFail("expected a conflict") }
        XCTAssertEqual(map.chord(for: "page.desk"), KeyChord("1", .command))

        XCTAssertEqual(map.set(KeyChord("2", .command), for: "page.desk", replacing: true), .ok)
        XCTAssertEqual(map.chord(for: "page.desk"), KeyChord("2", .command))
        XCTAssertNil(map.chord(for: "page.tickets"))
        XCTAssertTrue(map.clashes().isEmpty)
    }

    func testScopesOnlyClashWhereTheyOverlap() {
        let map = ShortcutMap()
        // ⌥↩ is a list key and a palette key: separate places, no clash.
        XCTAssertEqual(map.chord(for: "list.openWindow"), map.chord(for: "palette.openWindow"))
        XCTAssertTrue(map.clashes().isEmpty)
        // A menu command overlaps every scope.
        let owner = map.owner(of: KeyChord("j"), scope: .app)
        XCTAssertEqual(owner?.id, "list.next")
    }

    func testReservedAndModifierRules() {
        var map = ShortcutMap()
        XCTAssertEqual(map.set(KeyChord("q", .command), for: "page.desk"), .reserved)
        XCTAssertEqual(map.set(KeyChord("d"), for: "page.desk"), .needsModifier)
        XCTAssertEqual(map.set(KeyChord("d", .shift), for: "page.desk"), .needsModifier)
        XCTAssertEqual(map.set(KeyChord("zz"), for: "page.desk"), .invalidKey)
        // A list command may use a bare letter.
        XCTAssertEqual(map.set(KeyChord("n"), for: "list.next"), .ok)
        // Fixed keys cannot be changed.
        XCTAssertEqual(map.set(KeyChord("x", .command), for: "palette.open"), .reserved)
        XCTAssertEqual(map.chord(for: "palette.open"), KeyChord("return"))
    }

    func testResetAll() {
        var map = ShortcutMap()
        map.set(KeyChord("d", [.control, .command]), for: "page.desk")
        map.set(nil, for: "page.board")
        map.resetAll()
        XCTAssertEqual(map, ShortcutMap())
    }

    func testSavingRoundTrips() {
        var map = ShortcutMap()
        map.set(KeyChord("d", [.control, .command]), for: "page.desk")
        map.set(nil, for: "page.board")
        let back = ShortcutMap.decoded(map.encoded())
        XCTAssertEqual(back, map)
        XCTAssertNil(back.chord(for: "page.board"))
    }

    func testStaleSavedChangesAreDropped() {
        let data = #"{"gone.command":{"key":"x","modifiers":8},"settings":{"key":"x","modifiers":8},"page.desk":{"key":"zz","modifiers":8}}"#.data(using: .utf8)!
        let map = ShortcutMap.decoded(data)
        XCTAssertEqual(map, ShortcutMap())
        XCTAssertEqual(ShortcutMap.decoded(Data("not json".utf8)), ShortcutMap())
    }
}
