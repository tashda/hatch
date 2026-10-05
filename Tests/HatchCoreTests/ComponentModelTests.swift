import XCTest
@testable import HatchCore

/// Every view an app declares gets an answer with a reason; views that draw alike become one component (CM1 to CM4).
/// The fixtures are Hatch's own chips, checked against its code and the component gallery.
final class ComponentModelTests: XCTestCase {
    let chips = """
    struct HXChip: View {
        let text: String
        let turn: Turn
        var body: some View {
            Text(text)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(Theme.color(for: turn))
                .background(Theme.background(for: turn), in: Capsule())
        }
    }
    struct HXProblemChip: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(Theme.critical)
                .background(Theme.criticalBackground, in: Capsule())
        }
    }
    struct PlainChip: View {
        let text: String
        var systemImage: String?
        var body: some View {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.caption2) }
                Text(text).font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }
    struct StatusChip: View {
        let status: Status
        var body: some View {
            Label { Text(status.displayName).font(.callout) } icon: { Image(systemName: "circle") }
        }
    }
    struct HXStatusChip: View {
        let status: Status
        var body: some View {
            StatusChip(status: status)
        }
    }
    struct SettingsSheet: View {
        var body: some View {
            VStack { HXChip(text: "a", turn: .you); PlainChip(text: "b") }
                .padding(20)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    """

    func testEveryViewIsAnsweredWithAReason() {
        let model = AppViewScanner.scan(files: [("Chips.swift", chips)])
        func kind(_ id: String) -> AppView.Kind? { model.views.first { $0.id == id }?.kind }
        XCTAssertEqual(kind("HXChip"), .component)
        XCTAssertEqual(kind("PlainChip"), .component)
        XCTAssertEqual(kind("HXStatusChip"), .wrapper, "a body that is one call to another view")
        XCTAssertEqual(model.views.first { $0.id == "HXStatusChip" }?.wraps, "StatusChip")
        XCTAssertEqual(kind("StatusChip"), .unknown, "named a chip but draws none: asked, not guessed")
        XCTAssertEqual(kind("SettingsSheet"), .screen, "the name decides before the rounded panel")
        XCTAssertTrue(model.views.allSatisfy { !$0.reason.isEmpty })
        XCTAssertLessThan(model.covered, 1, "an unknown keeps the system from being complete")
    }

    func testTheLookIsReadFromTheTextNotItsIcon() {
        let model = AppViewScanner.scan(files: [("Chips.swift", chips)])
        let plain = model.views.first { $0.id == "PlainChip" }!.style
        XCTAssertEqual(plain.font, "caption", "the Text's font, not the icon's caption2")
        XCTAssertEqual(plain.paddingH, 7)
        XCTAssertEqual(plain.shape, "capsule")
        let hx = model.views.first { $0.id == "HXChip" }!.style
        XCTAssertEqual(hx.font, "caption")
        XCTAssertEqual(hx.weight, "medium")
    }

    func testChipsThatDifferInColourAreOneComponentWithTones() {
        let model = AppViewScanner.scan(files: [("Chips.swift", chips)])
        let chip = model.proposals.first { $0.family == "chip" }!
        XCTAssertEqual(Set(chip.members), ["HXChip", "HXProblemChip", "PlainChip"])
        let hx = chip.variants.first { $0.members.contains("HXChip") }!
        XCTAssertEqual(Set(hx.members), ["HXChip", "HXProblemChip"], "same form, two colours")
        XCTAssertTrue(hx.name.contains("critical") && hx.name.contains("by turn"))
        // PlainChip differs only in weight: proposed as the same size, with the weight to pick.
        XCTAssertTrue(chip.why.contains("weights differ"), chip.why)
    }

    func testSizesAreProposedWhereTheyJumpNotByThirds() {
        func view(_ id: String, pad: Double, font: String) -> AppView {
            AppView(id: id, file: "f", line: 1, kind: .component, reason: "r", family: "card",
                    style: AppViewStyle(font: font, paddingH: pad, paddingV: pad, shape: "rounded 8"), interactive: false, uses: 1, usedIn: [], bodyLines: 5)
        }
        let sizes = AppViewScanner.sizeProposal([view("A", pad: 10, font: "callout"), view("B", pad: 10.5, font: "callout"), view("C", pad: 12, font: "callout"),
                                                 view("D", pad: 24, font: "headline"), view("E", pad: 32, font: "title2")])
        XCTAssertEqual(sizes.map(\.name), ["small", "medium", "large"])
        XCTAssertEqual(sizes[0].members.sorted(), ["A", "B", "C"], "10, 10.5 and 12 are one size")
    }
}
