import XCTest
@testable import MarkdownEditor

final class SidebarIntegrationTests: XCTestCase {

    func testMainWindowControllerHasSidebar() {
        let controller = MainWindowController()
        XCTAssertNotNil(controller.sidebarController)
    }

    func testSidebarFileSelectionOpensDocument() throws {
        let controller = MainWindowController()

        // Create temp workspace with file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testFile = tempDir.appendingPathComponent("test.md")
        try "# Test".write(to: testFile, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Mount workspace and select file
        try controller.workspaceManager.mountWorkspace(at: tempDir)
        controller.sidebarController?.onFileSelected?(testFile)

        XCTAssertEqual(controller.tabManager.tabs.count, 1)
        XCTAssertEqual(controller.tabManager.tabs.first?.filePath, testFile)
    }
}
