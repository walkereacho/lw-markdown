import XCTest
@testable import MarkdownEditor

final class SidebarIntegrationTests: XCTestCase {

    func testMainWindowControllerHasSidebar() {
        let controller = MainWindowController()
        XCTAssertNotNil(controller.sidebarController)
    }

    func testSidebarFileSelectionOpensDocument() throws {
        let controller = MainWindowController()
        // MainWindowController creates an initial tab on init
        let initialCount = controller.tabManager.tabs.count

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

        // File selection adds a new tab
        XCTAssertEqual(controller.tabManager.tabs.count, initialCount + 1)
        // The active document should be the selected file
        XCTAssertEqual(controller.tabManager.activeDocument?.filePath, testFile)
    }

    func testOpenWorkspaceUpdatesFileTree() throws {
        let controller = MainWindowController()

        // Create temp workspace
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "# File 1".write(to: tempDir.appendingPathComponent("file1.md"), atomically: true, encoding: .utf8)
        try "# File 2".write(to: tempDir.appendingPathComponent("file2.md"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        controller.openWorkspace(at: tempDir)

        XCTAssertEqual(controller.workspaceManager.workspaceRoot, tempDir)
        XCTAssertNotNil(controller.workspaceManager.fileTree())
    }
}
