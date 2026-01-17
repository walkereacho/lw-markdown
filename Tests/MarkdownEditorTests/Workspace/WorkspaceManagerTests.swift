import XCTest
@testable import MarkdownEditor

final class WorkspaceManagerTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testMountWorkspace() throws {
        let manager = WorkspaceManager()
        XCTAssertNil(manager.workspaceRoot)

        try manager.mountWorkspace(at: tempDir)
        XCTAssertEqual(manager.workspaceRoot, tempDir)
    }

    func testUnmountWorkspace() throws {
        let manager = WorkspaceManager()
        try manager.mountWorkspace(at: tempDir)

        manager.unmountWorkspace()
        XCTAssertNil(manager.workspaceRoot)
    }

    func testFileTreeEnumeration() throws {
        // Create test files
        let subdir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "test".write(to: tempDir.appendingPathComponent("file1.md"), atomically: true, encoding: .utf8)
        try "test".write(to: subdir.appendingPathComponent("file2.md"), atomically: true, encoding: .utf8)

        let manager = WorkspaceManager()
        try manager.mountWorkspace(at: tempDir)

        guard let tree = manager.fileTree() else {
            XCTFail("Expected file tree")
            return
        }

        XCTAssertEqual(tree.url, tempDir)
        XCTAssertTrue(tree.isDirectory)
        XCTAssertNotNil(tree.children)
        XCTAssertEqual(tree.children?.count, 2)  // file1.md and subdir
    }
}
