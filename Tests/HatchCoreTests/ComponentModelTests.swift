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

    func testViewsDrawnAlikeAreOneProposalAndColourDoesNotSplitThem() {
        let model = AppViewScanner.scan(files: [("Chips.swift", chips)])
        let chips = model.proposals.filter { $0.family == "chip" }
        // HXChip and HXProblemChip differ only in colour: one group. PlainChip is regular weight, not medium: apart.
        XCTAssertEqual(Set(chips.first { $0.members.contains("HXChip") }!.members), ["HXChip", "HXProblemChip"])
        XCTAssertEqual(chips.first { $0.members.contains("PlainChip") }!.members, ["PlainChip"])
        let same = AppViewScanner.compare(model.views.filter { ["HXChip", "HXProblemChip"].contains($0.id) })
        XCTAssertTrue(same.same); XCTAssertTrue(same.words.contains("Only the colour differs"), same.words)
        let differ = AppViewScanner.compare(model.views.filter { ["HXChip", "PlainChip"].contains($0.id) })
        XCTAssertFalse(differ.same); XCTAssertTrue(differ.words.contains("weight (medium, regular)"), differ.words)
    }

    func testWhatAViewShowsAndWhereItIsUsed() {
        let screen = """
        struct LogView: View {
            var body: some View { VStack { HXChip(text: "Merged cleanly", turn: .finished); HXChip(text: name, turn: .you); PlainChip(text: "Default") } }
        }
        struct RunRow: View { var body: some View { HXChip(text: "Built", turn: .finished) } }
        """
        let model = AppViewScanner.scan(files: [("Chips.swift", chips), ("LogView.swift", screen)])
        let hx = model.views.first { $0.id == "HXChip" }!
        // The fixture's own SettingsSheet shows "a"; a variable (`name`) says nothing.
        XCTAssertEqual(hx.shows, ["a", "Merged cleanly", "Built"], "literal texts, once each")
        XCTAssertEqual(hx.usedOn.map(\.name), ["Log", "Run row", "Settings sheet"], "most used first")
        XCTAssertEqual(hx.usedOn.first?.count, 2)
        XCTAssertEqual(AppViewScanner.plainName("HXProblemChip"), "Problem chip")
        XCTAssertEqual(AppViewScanner.plainName("GitHubSettingsPage", screen: true), "GitHub settings")
    }

    /// Views for the same purpose are one component even when drawn differently; the same look for another purpose is
    /// not (CM22). The cases are Hatch's own: two chips that filter, drawn two ways; a sample drawn like a tag.
    func testViewsAreGroupedByWhatTheyAreFor() {
        let more = """
        struct ThreadFilterChip: View {
            let title: String
            @Binding var isOn: Bool
            var body: some View {
                Button { isOn.toggle() } label: { Text(title).font(.callout).padding(.horizontal, 6).padding(.vertical, 4).background(.quaternary, in: Capsule()) }
            }
        }
        struct ThreadKindChip: View {
            let title: String
            let selected: Bool
            let action: () -> Void
            var body: some View {
                Button(action: action) { Text(title).font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: Capsule()) }
            }
        }
        struct HXIssueSample: View {
            let number: Int
            let title: String
            var body: some View {
                Text(title).font(.caption).padding(.horizontal, 7).padding(.vertical, 2).background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        struct PageHeader: View {
            let title: String
            var body: some View { Text(title).font(.title2.weight(.semibold)).padding(.horizontal, 4) }
        }
        struct SectionHeader: View {
            let title: String
            var body: some View { Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 2) }
        }
        """
        let model = AppViewScanner.scan(files: [("Chips.swift", chips), ("More.swift", more)])
        func purpose(_ id: String) -> String? { model.views.first { $0.id == id }?.purpose }
        XCTAssertEqual(purpose("HXChip"), "state", "given a Turn")
        XCTAssertEqual(purpose("HXProblemChip"), "state", "named for a problem")
        XCTAssertEqual(purpose("PlainChip"), "label", "only text")
        XCTAssertEqual(purpose("ThreadFilterChip"), "choice")
        XCTAssertEqual(purpose("HXIssueSample"), "sample")
        func group(_ id: String) -> AppComponentProposal? { model.proposals.first { $0.members.contains(id) } }
        XCTAssertEqual(Set(group("ThreadFilterChip")!.members), ["ThreadFilterChip", "ThreadKindChip"], "both pick or filter, drawn two ways")
        XCTAssertEqual(group("ThreadFilterChip")?.title, "Filter chip")
        XCTAssertTrue(group("ThreadFilterChip")!.why.contains("drawn 2 ways"), group("ThreadFilterChip")!.why)
        XCTAssertEqual(group("HXChip")?.title, "Status chip")
        XCTAssertEqual(group("HXChip")?.purpose, "show a state")
        XCTAssertEqual(group("HXIssueSample")?.members, ["HXIssueSample"], "drawn like a tag, but a sample of an issue")
        XCTAssertEqual(group("PlainChip")?.title, "Tag")
        XCTAssertNotEqual(group("PageHeader")?.id, group("SectionHeader")?.id, "text names any header: headers go by look")
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
