import XCTest
@testable import CloudKitSync

final class ConflictResolverTests: XCTestCase {

    func testResolveNoConflictsReturnsNil() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("test.md")
        try "- [ ] Task".write(to: url, atomically: true, encoding: .utf8)

        let resolver = ConflictResolver()
        let result = try resolver.resolveConflicts(at: url)
        XCTAssertNil(result)
    }
}
