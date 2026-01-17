import XCTest
@testable import MarkdownEditor

final class TabIntegrationTests: XCTestCase {

    func testMainWindowControllerHasTabManager() {
        let controller = MainWindowController()
        XCTAssertNotNil(controller.tabManager)
    }

    func testNewDocumentCreatesTab() {
        let controller = MainWindowController()
        controller.newDocument()

        XCTAssertEqual(controller.tabManager.tabs.count, 1)
        XCTAssertNotNil(controller.tabManager.activeDocument)
    }

    func testOpenDocumentCreatesTab() throws {
        let controller = MainWindowController()

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try "# Test".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        try controller.openFile(at: testFile)

        XCTAssertEqual(controller.tabManager.tabs.count, 1)
        XCTAssertEqual(controller.tabManager.tabs.first?.title, testFile.lastPathComponent)
    }

    func testTabBarViewConnected() {
        let controller = MainWindowController()
        controller.newDocument()
        controller.newDocument()

        // Tab bar should reflect tab count
        XCTAssertEqual(controller.tabBarView?.tabManager?.tabs.count, 2)
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
}
