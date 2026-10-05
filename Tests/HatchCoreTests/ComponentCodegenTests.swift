import XCTest
@testable import HatchCore

final class ComponentCodegenTests: XCTestCase {
    func testRolesReadLikeTheSystem() {
        let s = ComponentTemplates.glass.system(name: "Acme")
        let code = ComponentCodegen.roles(s)
        XCTAssertTrue(code.hasPrefix(ComponentCodegen.header))
        XCTAssertTrue(code.contains("public enum Button: String, CaseIterable, Sendable"))
        XCTAssertTrue(code.contains("case primaryStop"), "variants are cases too")
        XCTAssertTrue(code.contains("@ViewBuilder func buttonRole(_ role: Roles.Button) -> some View"))
        XCTAssertTrue(code.contains("self.buttonStyle(.glassProminent).controlSize(.large).labelStyle(.titleAndIcon).keyboardShortcut(.defaultAction)"))
        XCTAssertTrue(code.contains("case .sheetDefault:\n            // Follows macOS: the system draws it.\n            self.keyboardShortcut(.defaultAction)"),
                      "the default button is only its key; macOS draws it")
        XCTAssertTrue(code.contains("Section { self }"), "a details card is a native Form section")
        XCTAssertFalse(code.contains("if #available"), "macOS 27 needs no fallback")
        XCTAssertTrue(code.contains("// - emptyState.standard: ContentUnavailableView") == false, "a custom role with a recipe is still generated")
        let foundations = ComponentCodegen.foundations(s)
        XCTAssertTrue(foundations.contains("public static let group: CGFloat = 16"))
        XCTAssertFalse(ComponentCodegen.foundations(ComponentTemplates.native.system(name: "Acme")).contains("enum Space"),
                       "macOS Native has no spacing numbers: macOS gives none")
        XCTAssertTrue(foundations.contains("public static let surface = Color(nsColor: .windowBackgroundColor)"))
    }

    func testOlderMacOSFallsBack() {
        var s = ComponentTemplates.glass.system(name: "Acme")
        s.minimumMacOS = "14.0"
        let code = ComponentCodegen.roles(s)
        XCTAssertTrue(code.contains("if #available(macOS 26.0, *)"))
        XCTAssertTrue(code.contains("self.buttonStyle(.borderedProminent)"))
    }

    func testFilesForAPackage() {
        let files = ComponentCodegen.files(ComponentTemplates.native.system(name: "Acme"), product: "AcmeComponents", makePackage: true)
        XCTAssertEqual(Set(files.keys), ["Package.swift", "Sources/AcmeComponents/Roles.swift", "Sources/AcmeComponents/Foundations.swift"])
        XCTAssertTrue(files["Package.swift"]!.contains(#"platforms: [.macOS("27.0")]"#))
    }

    /// The generated code compiles against the real SDK, for macOS 27 and for an app that supports macOS 14.
    func testGeneratedCodeTypechecks() throws {
        #if os(macOS)
        guard let sdk = shell(["xcrun", "--show-sdk-path", "--sdk", "macosx"]).out?.trimmingCharacters(in: .whitespacesAndNewlines), !sdk.isEmpty else {
            throw XCTSkip("No macOS SDK")
        }
        let usage = """
            import SwiftUI
            struct UsesRoles: View {
                var body: some View {
                    VStack(spacing: 12) {
                        Button("Save") {}.buttonRole(.primary)
                        Button("Stop") {}.buttonRole(.primaryStop)
                        Menu("More") { Button("Drop") {}.buttonRole(.destructive) }.menuRole(.more)
                        Toggle("Sync", isOn: .constant(true)).toggleRole(.setting)
                        Text("Card").font(Typography.cardTitle).cardRole(.details)
                        Button("Done") {}.buttonRole(.sheetDefault)
                    }
                    .padding(Space.group)
                }
            }
            """
        for template in ComponentTemplates.all {
            for minimum in ["27.0", "14.0"] {
                var s = template.system(name: "Acme")
                s.minimumMacOS = minimum
                // A color of its own exercises the light and dark helper.
                s.foundations.append(ComponentFoundation("color.brand", .color, use: "Brand.", light: "#3366CC", dark: "#88AAFF"))
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: dir) }
                var paths: [String] = []
                for (name, text) in ComponentCodegen.files(s, product: nil) {
                    let url = dir.appendingPathComponent(name)
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    paths.append(url.path)
                }
                if template.id == "glass" {
                    let url = dir.appendingPathComponent("Usage.swift")
                    try usage.write(to: url, atomically: true, encoding: .utf8)
                    paths.append(url.path)
                }
                let r = shell(["xcrun", "swiftc", "-typecheck", "-target", "arm64-apple-macos\(minimum)", "-sdk", sdk] + paths)
                XCTAssertEqual(r.status, 0, "\(template.id) for macOS \(minimum):\n\(r.err ?? "")")
            }
        }
        #else
        throw XCTSkip("macOS only")
        #endif
    }

    /// Every value of every setting in the catalog compiles against the SDK (NF1): a value Apple removes or renames fails here.
    func testEveryCatalogValueCompiles() throws {
        #if os(macOS)
        guard let sdk = shell(["xcrun", "--show-sdk-path", "--sdk", "macosx"]).out?.trimmingCharacters(in: .whitespacesAndNewlines), !sdk.isEmpty else {
            throw XCTSkip("No macOS SDK")
        }
        var s = ComponentSystem(name: "All", foundations: ComponentTemplates.glass.system(name: "x").foundations + [
            ComponentFoundation("radius.card", .radius, use: "x", value: 12)])
        for element in ComponentElement.catalog {
            for p in element.parameters {
                for (i, v) in (p.values + (p.foundation.map { k in s.foundations.filter { $0.kind == k }.map(\.id).prefix(1).map { $0 } } ?? [])).enumerated() {
                    var recipe = [p.id: v]
                    if element.id == "card", p.id != "container" { recipe["container"] = "custom" }
                    s.roles.append(ComponentRole("\(element.id).\(p.id)\(i)", "x", use: "x", places: ["page"], importance: .other, recipe: recipe))
                }
            }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var paths: [String] = []
        for (name, text) in ComponentCodegen.files(s, product: nil) {
            let url = dir.appendingPathComponent(name); try text.write(to: url, atomically: true, encoding: .utf8); paths.append(url.path)
        }
        let r = shell(["xcrun", "swiftc", "-typecheck", "-target", "arm64-apple-macos27.0", "-sdk", sdk] + paths)
        XCTAssertEqual(r.status, 0, r.err ?? "")
        #else
        throw XCTSkip("macOS only")
        #endif
    }

    func shell(_ args: [String]) -> (status: Int32, out: String?, err: String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        guard (try? p.run()) != nil else { return (-1, nil, nil) }
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }
}
