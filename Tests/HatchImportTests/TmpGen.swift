import XCTest
import HatchCore
@testable import HatchImport
final class TmpGen: XCTestCase {
    func testGen() throws {
        let areas = ProjectBootstrap.suggestAreas(repoRoot: Paths.echoRepo)
        print("AREAS:" + areas.map { "\($0.name)|\($0.specPrefix!)" }.joined(separator: ";"))
    }
}
