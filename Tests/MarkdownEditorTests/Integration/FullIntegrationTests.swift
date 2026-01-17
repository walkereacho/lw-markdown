import XCTest
@testable import MarkdownEditor

final class FullIntegrationTests: XCTestCase {

    func testFullWorkflow() throws {
        let controller = MainWindowController()

        // 1. Create new document
        controller.newDocument()
        XCTAssertEqual(controller.tabManager.tabs.count, 1)

        // 2. Type some Markdown
        guard let document = controller.tabManager.activeDocument else {
            XCTFail("No document")
            return
        }
        document.contentStorage.attributedString = NSAttributedString(string: "# Hello World\n\nThis is **bold** text.")

        // 3. Verify parser is working (tokens exist)
        guard let pane = controller.editorViewController.paneController else {
            XCTFail("No pane controller")
            return
        }
        let tokens = pane.layoutDelegate.tokenProvider.parse("# Hello World")
        XCTAssertFalse(tokens.isEmpty)

        // 4. Open another document
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("integration-\(UUID().uuidString).md")
        try "# Second File".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        try controller.openFile(at: testFile)
        XCTAssertEqual(controller.tabManager.tabs.count, 2)

        // 5. Verify tab switching works
        controller.tabManager.activateTab(documentId: document.id)
        XCTAssertEqual(controller.tabManager.activeDocumentId, document.id)
    }

    func testParserIntegrationWithEditor() throws {
        let controller = MainWindowController()
        controller.newDocument()

        guard controller.tabManager.activeDocument != nil,
              let pane = controller.editorViewController.paneController else {
            XCTFail("Setup failed")
            return
        }

        // Test various Markdown patterns
        let testCases: [(input: String, expectedElement: MarkdownElement)] = [
            ("# Heading", .heading(level: 1)),
            ("## Heading 2", .heading(level: 2)),
            ("**bold**", .bold),
            ("*italic*", .italic),
            ("[link](url)", .link(url: "url"))
        ]

        for testCase in testCases {
            let tokens = pane.layoutDelegate.tokenProvider.parse(testCase.input)
            XCTAssertFalse(tokens.isEmpty, "Parser should return tokens for: \(testCase.input)")
            XCTAssertEqual(tokens.first?.element, testCase.expectedElement, "Element mismatch for: \(testCase.input)")
        }
    }

    func testWorkspaceWithTabs() throws {
        let controller = MainWindowController()

        // Create temp workspace with multiple files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("full-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("file1.md")
        let file2 = tempDir.appendingPathComponent("file2.md")
        try "# File 1".write(to: file1, atomically: true, encoding: .utf8)
        try "# File 2".write(to: file2, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Open workspace
        controller.openWorkspace(at: tempDir)
        XCTAssertEqual(controller.workspaceManager.workspaceRoot, tempDir)

        // Simulate selecting files from sidebar
        controller.sidebarController?.onFileSelected?(file1)
        XCTAssertEqual(controller.tabManager.tabs.count, 1)

        controller.sidebarController?.onFileSelected?(file2)
        XCTAssertEqual(controller.tabManager.tabs.count, 2)

        // Verify both tabs exist
        let tabTitles = controller.tabManager.tabs.map { $0.title }
        XCTAssertTrue(tabTitles.contains("file1.md"))
        XCTAssertTrue(tabTitles.contains("file2.md"))
    }

    func testDirtyStateTracking() throws {
        let controller = MainWindowController()
        controller.newDocument()

        guard let document = controller.tabManager.activeDocument else {
            XCTFail("No document")
            return
        }

        // Initially not dirty
        XCTAssertFalse(document.isDirty)

        // Simulate content change
        document.contentStorage.attributedString = NSAttributedString(string: "# Changed")
        let range = document.contentStorage.documentRange
        document.contentDidChange(in: range, changeInLength: 0)

        // Should be dirty now
        XCTAssertTrue(document.isDirty)

        // Tab should reflect dirty state
        let tab = controller.tabManager.tabs.first
        XCTAssertTrue(tab?.isDirty ?? false)
    }

    func testMultipleDocumentsWithParsing() throws {
        let controller = MainWindowController()

        // Create multiple documents with different content
        controller.newDocument()
        guard let doc1 = controller.tabManager.activeDocument else {
            XCTFail("No document 1")
            return
        }
        doc1.contentStorage.attributedString = NSAttributedString(string: "# Document 1\n\n**Bold text**")

        controller.newDocument()
        guard let doc2 = controller.tabManager.activeDocument else {
            XCTFail("No document 2")
            return
        }
        doc2.contentStorage.attributedString = NSAttributedString(string: "## Document 2\n\n*Italic text*")

        // Both documents exist
        XCTAssertEqual(controller.tabManager.tabs.count, 2)

        // Switch between tabs
        controller.tabManager.activateTab(documentId: doc1.id)
        XCTAssertEqual(controller.tabManager.activeDocumentId, doc1.id)

        controller.tabManager.activateTab(documentId: doc2.id)
        XCTAssertEqual(controller.tabManager.activeDocumentId, doc2.id)

        // Parser works for both
        guard let pane = controller.editorViewController.paneController else {
            XCTFail("No pane controller")
            return
        }

        let boldTokens = pane.layoutDelegate.tokenProvider.parse("**Bold text**")
        XCTAssertEqual(boldTokens.first?.element, .bold)

        let italicTokens = pane.layoutDelegate.tokenProvider.parse("*Italic text*")
        XCTAssertEqual(italicTokens.first?.element, .italic)
    }
}
