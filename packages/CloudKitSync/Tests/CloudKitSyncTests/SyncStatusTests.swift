import XCTest
@testable import CloudKitSync

final class SyncStatusTests: XCTestCase {

    func testSyncStatusDisplayText() {
        XCTAssertEqual(SyncStatus.idle.displayText, "")
        XCTAssertEqual(SyncStatus.syncing.displayText, "Syncing...")
        XCTAssertEqual(SyncStatus.synced.displayText, "iCloud Drive")
        XCTAssertEqual(SyncStatus.offline.displayText, "Offline")
        XCTAssertEqual(SyncStatus.error("test").displayText, "Error: test")
    }

    func testSyncStatusAvailability() {
        XCTAssertTrue(SyncStatus.idle.isAvailable)
        XCTAssertTrue(SyncStatus.syncing.isAvailable)
        XCTAssertTrue(SyncStatus.synced.isAvailable)
        XCTAssertFalse(SyncStatus.offline.isAvailable)
        XCTAssertFalse(SyncStatus.error("test").isAvailable)
    }

    func testStorageLocation() {
        XCTAssertEqual(StorageLocation(rawValue: "local"), .local)
        XCTAssertEqual(StorageLocation(rawValue: "icloud"), .icloud)
        XCTAssertNil(StorageLocation(rawValue: "invalid"))
    }
}
