import XCTest
@testable import MarkdownEditor

final class TabManagerTests: XCTestCase {

    func testOpenDocument() {
        let manager = TabManager()
        let document = DocumentModel()

        manager.openDocument(document)

        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.activeDocumentId, document.id)
    }

    func testOpenMultipleDocuments() {
        let manager = TabManager()
        let doc1 = DocumentModel()
        let doc2 = DocumentModel()

        manager.openDocument(doc1)
        manager.openDocument(doc2)

        XCTAssertEqual(manager.tabs.count, 2)
        XCTAssertEqual(manager.activeDocumentId, doc2.id)  // Most recent is active
    }

    func testCloseTab() {
        let manager = TabManager()
        let document = DocumentModel()

        manager.openDocument(document)
        let closed = manager.closeTab(documentId: document.id)

        XCTAssertTrue(closed)
        // TabManager auto-creates a new document when closing the last tab
        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertNotNil(manager.activeDocumentId)
        // The active document should be a new one, not the closed one
        XCTAssertNotEqual(manager.activeDocumentId, document.id)
    }

    func testActivateTab() {
        let manager = TabManager()
        let doc1 = DocumentModel()
        let doc2 = DocumentModel()

        manager.openDocument(doc1)
        manager.openDocument(doc2)

        manager.activateTab(documentId: doc1.id)

        XCTAssertEqual(manager.activeDocumentId, doc1.id)
    }

    func testTabInfo() {
        let manager = TabManager()
        let document = DocumentModel()
        document.filePath = URL(fileURLWithPath: "/path/to/file.md")

        manager.openDocument(document)

        let tab = manager.tabs.first
        XCTAssertNotNil(tab)
        XCTAssertEqual(tab?.title, "file.md")
        XCTAssertFalse(tab?.isDirty ?? true)
    }

    func testDirtyState() {
        let manager = TabManager()
        let document = DocumentModel()

        manager.openDocument(document)
        document.isDirty = true

        let tab = manager.tabs.first
        XCTAssertTrue(tab?.isDirty ?? false)
    }
}
