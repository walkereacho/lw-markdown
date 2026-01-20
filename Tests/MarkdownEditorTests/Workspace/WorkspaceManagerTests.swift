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

    func testSearchFilesMatchingPattern() throws {
        // Create test files with various names
        // Note: searchFiles only returns .md files
        let subdir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "test".write(to: tempDir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try "test".write(to: tempDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "test".write(to: subdir.appendingPathComponent("readme-notes.md"), atomically: true, encoding: .utf8)

        let manager = WorkspaceManager()
        try manager.mountWorkspace(at: tempDir)

        // Search for "readme" - should find readme.md and readme-notes.md
        let results = manager.searchFiles(matching: "readme")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.lastPathComponent.lowercased().contains("readme") })
    }

    func testSearchFilesIsCaseInsensitive() throws {
        try "test".write(to: tempDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let manager = WorkspaceManager()
        try manager.mountWorkspace(at: tempDir)

        let results = manager.searchFiles(matching: "readme")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.lastPathComponent, "README.md")
    }

    func testSearchFilesReturnsEmptyWhenNoWorkspace() {
        let manager = WorkspaceManager()
        let results = manager.searchFiles(matching: "test")
        XCTAssertTrue(results.isEmpty)
    }

    func testMountNonDirectoryThrows() {
        let manager = WorkspaceManager()
        let filePath = tempDir.appendingPathComponent("file.txt")
        try? "test".write(to: filePath, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try manager.mountWorkspace(at: filePath)) { error in
            XCTAssertTrue(error is WorkspaceError)
        }
    }
}
