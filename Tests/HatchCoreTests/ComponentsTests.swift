import XCTest
@testable import HatchCore

final class ComponentsTests: XCTestCase {
    let tokens = """
        import SwiftUI

        public extension Color {
            static let surface = Color(red: 0.96, green: 0.96, blue: 0.97)
            static let accentSoft = Color(red: 51/255, green: 102/255, blue: 204/255, opacity: 0.5)
            static let brand = Color("Brand", bundle: .module)
            static let link = Color.blue
            static let window = Color(nsColor: .windowBackgroundColor)
            static let hexed = Color(hex: "#FF8800")
        }

        extension Font {
            public static let titleLarge = Font.system(.title2, design: .rounded, weight: .semibold)
            public static let label: Font = .system(size: 13, weight: .medium)
            static let hidden = Font.body  // internal: the app cannot use it from a package
        }

        public enum Spacing {
            public static let s: CGFloat = 8
            public static let m: CGFloat = 12 // medium
            public static let animationDuration: Double = 0.25
            public enum Inner { public static let xl = CGFloat(32) }
        }

        public struct PrimaryButton<Label: View>: View {
            public var body: some View { Text("x") }
        }

        public struct CardStyle: ButtonStyle {
            public func makeBody(configuration: Configuration) -> some View { configuration.label }
        }

        struct InternalView: View { var body: some View { EmptyView() } }

        public extension View {
            func cardBackground() -> some View { self.padding(Spacing.m) }
        }
        """

    func testReaderFindsTokensViewsAndStylesWithTheirValues() {
        var cat = ComponentCatalog()
        ComponentReader.read(tokens, file: "Tokens.swift", requirePublic: true, into: &cat)

        XCTAssertEqual(cat.colors.map(\.name), ["Color.surface", "Color.accentSoft", "Color.brand", "Color.link", "Color.window", "Color.hexed"])
        XCTAssertEqual(cat.colors[0].light?.hex, "#F5F5F7")
        XCTAssertEqual(cat.colors[1].light?.hex, "#3366CC80")
        XCTAssertEqual(cat.colors[2].system, "asset:Brand")
        XCTAssertEqual(cat.colors[3].system, "blue")
        XCTAssertEqual(cat.colors[4].system, "windowBackgroundColor")
        XCTAssertEqual(cat.colors[5].light?.hex, "#FF8800")

        XCTAssertEqual(cat.fonts.map(\.name), ["Font.titleLarge", "Font.label"])
        XCTAssertEqual(cat.fonts[0].summary, "Title2, semibold, rounded")
        XCTAssertEqual(cat.fonts[1].size, 13)
        XCTAssertEqual(cat.fonts[1].weight, "medium")

        XCTAssertEqual(cat.sizes.map(\.name), ["Spacing.s", "Spacing.m", "Spacing.Inner.xl"])
        XCTAssertEqual(cat.sizes.map(\.value), [8, 12, 32])

        XCTAssertEqual(cat.views.map(\.name), ["PrimaryButton", "CardStyle", ".cardBackground()"])
        XCTAssertEqual(cat.views.map(\.kind), [.view, .style, .modifier])
    }

    func testSampleCodeInsideAMultilineStringIsNotACatalogEntry() {
        let source = #"""
        import SwiftUI
        struct RealView: View { var body: some View { EmptyView() } }
        extension Font { static let real = Font.body }
        func fixture() {
            read("""
                public extension Font { static let badge = Font.system(size: 11) }
                public struct QuietButtonStyle: ButtonStyle { }
                """, file: "Tokens.swift")
        }
        struct AfterView: View { var body: some View { EmptyView() } }
        """#
        var catalog = ComponentCatalog()
        ComponentReader.read(source, file: "A.swift", requirePublic: false, into: &catalog)
        XCTAssertEqual(Set(catalog.views.map(\.name)), ["RealView", "AfterView"], "only code outside the literal is read")
        XCTAssertEqual(catalog.fonts.map(\.name), ["Font.real"])
    }

    func testOneLineDeclarationsAndSemicolonsAreRead() {
        var cat = ComponentCatalog()
        ComponentReader.read("public extension Spacing { static let s: CGFloat = 8; }\npublic extension View { func card() -> some View { self } }\n",
                             file: "T.swift", requirePublic: true, into: &cat)
        XCTAssertEqual(cat.sizes.map(\.value), [8])
        XCTAssertEqual(cat.views.map(\.name), [".card()"])
    }

    func testAFolderInTheAppTargetCountsInternalNames() {
        var cat = ComponentCatalog()
        ComponentReader.read(tokens, file: "Tokens.swift", requirePublic: false, into: &cat)
        XCTAssertTrue(cat.fonts.contains { $0.name == "Font.hidden" })
        XCTAssertTrue(cat.views.contains { $0.name == "InternalView" })
    }

    func testBriefLinesAreShortAndCapped() {
        var cat = ComponentCatalog()
        ComponentReader.read(tokens, file: "Tokens.swift", requirePublic: true, into: &cat)
        let lines = cat.briefLines(cap: 3)
        XCTAssertEqual(lines.first, "- Colors: Color.surface, Color.accentSoft, Color.brand, and 3 more")
        XCTAssertTrue(lines.contains("- Sizes: Spacing.s 8, Spacing.m 12, Spacing.Inner.xl 32"))
        XCTAssertTrue(cat.briefLines(values: true).first!.contains("Color.surface #F5F5F7"))
    }

    func testColorSetsReadBothAppearances() {
        let json = """
            {"colors":[{"color":{"color-space":"srgb","components":{"red":"0x33","green":"0.400","blue":"204","alpha":"1.000"}},"idiom":"universal"},
                       {"appearances":[{"appearance":"luminosity","value":"dark"}],"color":{"color-space":"srgb","components":{"red":"1.000","green":"1.000","blue":"1.000","alpha":"1.000"}},"idiom":"universal"}]}
            """
        let v = ComponentReader.colorSet(Data(json.utf8))
        XCTAssertEqual(v.light?.hex, "#3366CC")
        XCTAssertEqual(v.dark?.hex, "#FFFFFF")
    }

    func testTypedValuesOnlyCountAddedLinesOutsideTheComponents() {
        let diff = """
            diff --git a/App/Views/Card.swift b/App/Views/Card.swift
            +++ b/App/Views/Card.swift
            @@ -10,0 +11,4 @@
            +        .padding(12)
            +        .foregroundStyle(Color(red: 1, green: 0, blue: 0))
            +        .font(.system(size: 14))   // a comment with .padding(4)
            +        .padding(Spacing.m)
            +++ b/Packages/AcmeComponents/Sources/Tokens.swift
            @@ -1,0 +2,1 @@
            +    static let red = Color(red: 1, green: 0, blue: 0)
            +++ b/README.md
            @@ -1,0 +1,1 @@
            +.padding(12)
            """
        let found = TypedValues.inDiff(diff, excluding: "Packages/AcmeComponents")
        XCTAssertEqual(found.map(\.kind), [.size, .color, .font])
        XCTAssertEqual(found.map(\.line), [11, 12, 13])
        XCTAssertEqual(found.first?.file, "App/Views/Card.swift")
        XCTAssertEqual(TypedValues.kinds(in: "  VStack(spacing: 0) { .padding(.horizontal) }"), [])
        XCTAssertEqual(TypedValues.kinds(in: "  VStack(spacing: 6) {"), [.size])
    }

    func testScanFindsAPackageAndCountsTypedValuesElsewhere() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("components-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("Packages/AcmeUI/Package.swift", #"let package = Package(name: "AcmeUI", products: [.library(name: "AcmeUI", targets: ["AcmeUI"])])"#)
        try write("Packages/AcmeUI/Sources/AcmeUI/Tokens.swift", tokens)
        try write("Packages/AcmeUI/Sources/AcmeUI/Colors.xcassets/Brand.colorset/Contents.json",
                  #"{"colors":[{"color":{"components":{"red":"0.1","green":"0.2","blue":"0.3","alpha":"1"}}}]}"#)
        try write("Acme/Views/Home.swift", "Text(\"Hi\").padding(16).foregroundStyle(Color(red: 1, green: 0, blue: 0))\n.font(.system(size: 20))\n")
        try write("Acme/Views/Other.swift", "Text(\"Hi\").padding(8)\n")
        try write("AcmeTests/HomeTests.swift", ".padding(99)\n")

        let scan = ComponentsScanner.scan(appRoot: root.path)
        XCTAssertEqual(scan.candidates.map(\.path), ["Packages/AcmeUI"])
        let c = try XCTUnwrap(scan.candidates.first)
        XCTAssertTrue(c.isPackage)
        XCTAssertEqual(c.product, "AcmeUI")
        XCTAssertEqual(c.catalog.colors.first { $0.name == "Color.brand" }?.light?.hex, "#1A334D", "the token takes the color set's value")
        XCTAssertEqual(scan.typed, [.size: 2, .color: 1, .font: 1])
        XCTAssertEqual(scan.typedFiles.map(\.path), ["Acme/Views/Home.swift", "Acme/Views/Other.swift"])
        XCTAssertTrue(scan.isSmall)
        XCTAssertEqual(scan.typedSummary, "1 colors, 1 font sizes and 2 sizes")
    }

    func testSetupDraftsAreOneTweakForASmallAppAndAThemeForALargeOne() {
        let config = ComponentsConfig.suggested(appName: "acme app")
        XCTAssertEqual(config.path, "Packages/AcmeappComponents")
        let small = ComponentsSetup.drafts(appName: "Acme", config: config, scan: nil)
        XCTAssertEqual(small.map(\.type), [.tweak])
        XCTAssertTrue(small[0].body.contains("`Packages/AcmeappComponents`"))

        let big = ComponentsScan(candidates: [], typed: [.color: 140, .size: 300], typedFiles: [(path: "A.swift", count: 40)], swiftFiles: 900)
        let drafts = ComponentsSetup.drafts(appName: "Acme", config: config, scan: big)
        XCTAssertEqual(drafts.map(\.type), [.theme, .tweak, .tweak, .tweak])
        XCTAssertEqual(drafts.map(\.title).last, "Move typed-in sizes into components")
        XCTAssertTrue(drafts[1].body.contains("140 colors and 300 sizes"))
    }

    func testASmallUnnamedPackageIsNotComponents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hatch-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("Stage/Package.swift", #"let package = Package(name: "Stage", products: [.library(name: "Stage", targets: ["Stage"])])"#)
        try write("Stage/Sources/Stage/Sizes.swift", "public enum Gap { public static let a: CGFloat = 4\n public static let b: CGFloat = 8\n public static let c: CGFloat = 12\n public static let d: CGFloat = 16 }\npublic struct Card: View { public var body: some View { Text(\"x\") } }\n")
        XCTAssertEqual(ComponentsScanner.scan(appRoot: root.path).candidates.map(\.path), [], "four sizes and a view are not a components set")
    }

    func testNearDuplicateTypedValuesBecomeAPreparedQuestion() throws {
        var scan = ComponentsScan(candidates: [], typed: [.color: 60, .size: 80], typedFiles: [], swiftFiles: 100,
                                  colorLiterals: ["#2B59C2": 30, "#2B5AC2": 3], sizeLiterals: [16: 40, 15: 2])
        let q = try XCTUnwrap(ComponentsSetup.consolidationQuestion(scan: scan))
        XCTAssertEqual(q.type, .question)
        XCTAssertEqual(q.options.filter(\.recommended).count, 1)
        let drafts = ComponentsSetup.drafts(appName: "Acme", config: .suggested(appName: "Acme"), scan: scan)
        XCTAssertEqual(drafts.first?.type, .question, "decisions come before the tickets that act on them")
        scan.colorLiterals = ["#2B59C2": 30]; scan.sizeLiterals = [16: 40]
        XCTAssertNil(ComponentsSetup.consolidationQuestion(scan: scan), "nothing close, nothing to decide")
    }

    func testConfigWithoutComponentsStillLoads() throws {
        let old = #"{"name":"A","ticketsRepo":"a/t","repos":[],"areas":[],"docs":[],"maxAgents":3,"integrationBranch":"hatch","planApprovalFileThreshold":8}"#
        let config = try JSONDecoder().decode(ProjectConfig.self, from: Data(old.utf8))
        XCTAssertNil(config.components)
        var withApp = config
        withApp.repos = [RepoConfig(role: .app, remote: "a/app", branch: "main", localPath: "/code/app")]
        withApp.components = ComponentsConfig(path: "Packages/AUI", product: "AUI")
        XCTAssertEqual(withApp.componentsFolder, "/code/app/Packages/AUI")
        XCTAssertEqual(withApp.componentsLabel, "Packages/AUI")
    }

    func testClashesFindNamesWithTwoValuesAcrossSets() {
        var package = ComponentCatalog(), folder = ComponentCatalog()
        ComponentReader.read("public extension Color {\n static let accent = Color(hex: \"#2B59C2\")\n static let surface = Color.secondary\n}\n",
                             file: "Tokens.swift", requirePublic: true, into: &package)
        ComponentReader.read("extension Color {\n static let accent = Color(hex: \"#3366CC\")\n static let surface = Color.secondary\n}\n",
                             file: "Colors.swift", requirePublic: false, into: &folder)
        let chosen = ComponentsCandidate(path: "Packages/UI", isPackage: true, product: "UI", catalog: package)
        let other = ComponentsCandidate(path: "App/DesignSystem", isPackage: false, product: nil, catalog: folder)
        let clashes = ComponentConflicts.clashes(chosen: chosen, others: [other])
        XCTAssertEqual(clashes.map(\.name), ["Color.accent"], "same value is not a clash")
        XCTAssertEqual(clashes.first?.values.map(\.value), ["#2B59C2", "#3366CC"])

        let q = ComponentsSetup.clashQuestion(clashes, chosen: chosen, usage: ["Color.accent": 40])
        XCTAssertEqual(q?.type, .question)
        XCTAssertEqual(q?.area, "Components")
        XCTAssertEqual(q?.options.map(\.key), ["A", "B", "C"])
        XCTAssertEqual(q?.options.filter(\.recommended).map(\.key), ["A"])
        XCTAssertTrue(q?.options.allSatisfy { $0.gain != nil && $0.cost != nil } ?? false)
        XCTAssertTrue(q?.body.contains("used about 40 times") ?? false)
        XCTAssertNil(ComponentsSetup.clashQuestion([], chosen: chosen, usage: [:]))
        XCTAssertTrue(ComponentsSetup.mergeDraft(into: chosen, from: other).title.contains("Merge DesignSystem into UI"))
    }

    func testTypedValuesAreMatchedToNamesExactlyOrNearly() {
        let found = TypedValues.literals(in: ".foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.8))\n.padding(12)\n.padding(11)\nVStack(spacing: 12) {\n")
        XCTAssertEqual(found.colors, ["#3366CC": 1])
        XCTAssertEqual(found.sizes, [12: 2, 11: 1])

        var catalog = ComponentCatalog()
        ComponentReader.read("public extension Color {\n static let accent = Color(hex: \"#3366CC\")\n static let link = Color(hex: \"#0A66D8\")\n}\npublic enum Spacing { public static let m: CGFloat = 12 }\n",
                             file: "T.swift", requirePublic: true, into: &catalog)
        let colors = ComponentConflicts.colorMatches(["#3366CC": 5, "#0B66D8": 2, "#FF0000": 1], catalog: catalog)
        XCTAssertEqual(colors.map(\.literal), ["#3366CC", "#0B66D8"])
        XCTAssertEqual(colors.map(\.exact), [true, false])
        XCTAssertEqual(colors.map(\.name), ["Color.accent", "Color.link"])
        let sizes = ComponentConflicts.sizeMatches([12: 9, 11: 2, 40: 1], catalog: catalog)
        XCTAssertEqual(sizes.map(\.literal), ["12", "11"])
        XCTAssertEqual(sizes.map(\.exact), [true, false])
        // Without names, a rarer value next to a more used one is flagged against it.
        let loose = ComponentConflicts.colorMatches(["#3366CC": 9, "#3367CC": 1], catalog: nil)
        XCTAssertEqual(loose.map(\.literal), ["#3367CC"])
        XCTAssertEqual(loose.first?.nameValue, "#3366CC")

        let scan = ComponentsScan(candidates: [], typed: [.color: 8, .size: 11], typedFiles: [], swiftFiles: 10,
                                  colorLiterals: ["#3366CC": 5, "#0B66D8": 2], sizeLiterals: [12: 9, 11: 2])
        let moves = ComponentsSetup.moveDrafts(config: ComponentsConfig(path: "Packages/UI", product: "UI"), scan: scan, catalog: catalog)
        XCTAssertTrue(moves[0].body.contains("#3366CC → Color.accent (5)"))
        XCTAssertTrue(moves[0].body.contains("#0B66D8 (2) ~ Color.link #0A66D8"))
        XCTAssertTrue(moves[1].body.contains("12 → Spacing.m (9)"))
    }

    func testTheStartTicketNamesComponentsAlreadyInTheApp() {
        let drafts = ComponentsSetup.drafts(appName: "Echo", config: ComponentsConfig(path: "Packages/EchoComponents", product: "EchoComponents"),
                                            scan: nil, existing: ["Echo/Sources/Shared/DesignSystem"])
        XCTAssertTrue(drafts[0].body.contains("`Echo/Sources/Shared/DesignSystem`"))
        XCTAssertEqual(drafts[0].area, "Components")
    }

    func testTheAppItselfIsNeverItsComponents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("App"), ui = root.appendingPathComponent("Packages/AcmeUI")
        for (dir, manifest, code) in [(app, ".executableTarget(name: \"Acme\")", "@main struct AcmeApp: App {}\npublic extension Color { static let a = Color.red; static let b = Color.blue; static let c = Color.green }\npublic enum Spacing { public static let s: CGFloat = 4; public static let m: CGFloat = 8; public static let l: CGFloat = 16 }"),
                                      (ui, ".library(name: \"AcmeUI\")", "public extension Color { static let surface = Color.white; static let ink = Color.black }")] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
            try "let p = Package(\(manifest))".write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            try code.write(to: dir.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(ComponentsScanner.isAppItself(folder: app.path))
        XCTAssertFalse(ComponentsScanner.isAppItself(folder: ui.path))
        XCTAssertEqual(ComponentsScanner.scan(appRoot: root.path).candidates.map(\.path), ["Packages/AcmeUI"])
    }
}
