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
}
