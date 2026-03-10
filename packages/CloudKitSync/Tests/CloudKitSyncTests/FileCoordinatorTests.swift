import XCTest
@testable import CloudKitSync

final class FileCoordinatorTests: XCTestCase {

    let coordinator = FileCoordinator()
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testWriteAndReadFile() throws {
        let url = tempDir.appendingPathComponent("test.md")
        let content = "- [ ] Test task\n"

        try coordinator.writeFile(content, to: url)
        let read = try coordinator.readFile(at: url)

        XCTAssertEqual(read, content)
    }

    func testModificationDate() throws {
        let url = tempDir.appendingPathComponent("test2.md")
        try coordinator.writeFile("content", to: url)

        let date = coordinator.modificationDate(of: url)
        XCTAssertNotNil(date)
    }

    func testReadNonexistentFile() {
        let url = tempDir.appendingPathComponent("nonexistent.md")
        XCTAssertThrowsError(try coordinator.readFile(at: url))
    }
}
