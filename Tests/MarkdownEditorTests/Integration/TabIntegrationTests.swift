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
}
