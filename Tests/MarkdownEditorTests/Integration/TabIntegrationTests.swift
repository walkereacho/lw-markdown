import XCTest
@testable import MarkdownEditor

final class TabIntegrationTests: XCTestCase {

    func testMainWindowControllerHasTabManager() {
        let controller = MainWindowController()
        XCTAssertNotNil(controller.tabManager)
    }

    func testNewDocumentCreatesTab() {
        let controller = MainWindowController()
        // MainWindowController creates an initial tab on init
        let initialCount = controller.tabManager.tabs.count
        XCTAssertEqual(initialCount, 1)

        controller.newDocument()

        // After newDocument(), we should have one more tab
        XCTAssertEqual(controller.tabManager.tabs.count, initialCount + 1)
        XCTAssertNotNil(controller.tabManager.activeDocument)
    }

    func testOpenDocumentCreatesTab() throws {
        let controller = MainWindowController()
        // MainWindowController creates an initial tab on init
        let initialCount = controller.tabManager.tabs.count

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try "# Test".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        try controller.openFile(at: testFile)

        // Opening a file adds a new tab
        XCTAssertEqual(controller.tabManager.tabs.count, initialCount + 1)
        // The active tab should be the opened file
        XCTAssertEqual(controller.tabManager.activeDocument?.filePath, testFile)
    }

    func testTabBarViewConnected() {
        let controller = MainWindowController()
        // MainWindowController creates an initial tab on init (1 tab)
        controller.newDocument()  // 2 tabs
        controller.newDocument()  // 3 tabs

        // Tab bar should reflect tab count (initial + 2 new)
        XCTAssertEqual(controller.tabBarView?.tabManager?.tabs.count, 3)
    }

    func testSaveDocumentUpdatesDirtyState() throws {
        let controller = MainWindowController()
        controller.newDocument()

        guard let document = controller.tabManager.activeDocument else {
            XCTFail("No active document")
            return
        }

        // Create temp file for saving
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("save-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: testFile) }

        document.filePath = testFile
        document.contentStorage.attributedString = NSAttributedString(string: "# Test")
        document.isDirty = true

        controller.saveDocument()

        XCTAssertFalse(document.isDirty)
    }

    func testDirtyStateUpdatesWindowTitle() {
        let controller = MainWindowController()
        controller.newDocument()

        guard let document = controller.tabManager.activeDocument else {
            XCTFail("No active document")
            return
        }

        // Simulate edit
        document.isDirty = true

        // Force title update
        controller.refreshUI()

        XCTAssertTrue(controller.window?.title.contains("•") ?? false)
    }
}
