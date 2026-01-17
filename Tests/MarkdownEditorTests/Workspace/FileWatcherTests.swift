import XCTest
@testable import MarkdownEditor

final class FileWatcherTests: XCTestCase {

    func testWatcherCanBeCreated() {
        let watcher = FileWatcher()
        XCTAssertNotNil(watcher)
    }

    func testWatcherCanStartAndStop() {
        let watcher = FileWatcher()
        let tempDir = FileManager.default.temporaryDirectory

        watcher.watchWorkspace(at: tempDir)
        watcher.stopWatchingWorkspace()

        // Should not crash
        XCTAssertTrue(true)
    }

    func testWatcherHandlesMultipleStartStopCycles() {
        let watcher = FileWatcher()
        let tempDir = FileManager.default.temporaryDirectory

        // Multiple start/stop cycles should work without issues
        for _ in 0..<3 {
            watcher.watchWorkspace(at: tempDir)
            watcher.stopWatchingWorkspace()
        }

        XCTAssertTrue(true)
    }

    func testWatcherCallbacksCanBeSet() {
        let watcher = FileWatcher()

        var changedCalled = false
        var deletedCalled = false
        var createdCalled = false

        watcher.onFileChanged = { _ in changedCalled = true }
        watcher.onFileDeleted = { _ in deletedCalled = true }
        watcher.onFileCreated = { _ in createdCalled = true }

        XCTAssertNotNil(watcher.onFileChanged)
        XCTAssertNotNil(watcher.onFileDeleted)
        XCTAssertNotNil(watcher.onFileCreated)

        // Callbacks exist but were not triggered
        XCTAssertFalse(changedCalled)
        XCTAssertFalse(deletedCalled)
        XCTAssertFalse(createdCalled)
    }
}
