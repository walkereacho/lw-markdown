import XCTest
@testable import MarkdownEditor

final class DocumentModelTests: XCTestCase {

    // MARK: - Initialization

    func testNewDocumentIsEmpty() {
        let document = DocumentModel()
        XCTAssertEqual(document.fullString(), "")
        XCTAssertEqual(document.paragraphCount, 0)
        XCTAssertFalse(document.isDirty)
    }

    func testNewDocumentHasUniqueId() {
        let doc1 = DocumentModel()
        let doc2 = DocumentModel()
        XCTAssertNotEqual(doc1.id, doc2.id)
    }

    // MARK: - File Loading

    func testLoadFromFile() throws {
        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        let content = "# Hello\n\nWorld"
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: testFile) }

        // Load document
        let document = try DocumentModel(contentsOf: testFile)
        XCTAssertEqual(document.fullString(), content)
        XCTAssertEqual(document.filePath, testFile)
        XCTAssertFalse(document.isDirty)
    }

    // MARK: - Saving

    func testSaveDocument() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("save-test-\(UUID().uuidString).md")

        defer { try? FileManager.default.removeItem(at: testFile) }

        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "Test content")
        document.filePath = testFile

        try document.save()

        let saved = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(saved, "Test content")
        XCTAssertFalse(document.isDirty)
        XCTAssertNotNil(document.lastSavedAt)
    }

    func testSaveWithoutPathThrows() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "Test")

        XCTAssertThrowsError(try document.save()) { error in
            XCTAssertTrue(error is DocumentError)
        }
    }

    // MARK: - Paragraph Access

    func testParagraphCount() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "Line 1\nLine 2\nLine 3")
        document.paragraphCache.rebuildFull()

        XCTAssertEqual(document.paragraphCount, 3)
    }

    func testParagraphAccess() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "First\nSecond\nThird")
        document.paragraphCache.rebuildFull()

        // Note: paragraphs include trailing newline
        XCTAssertEqual(document.paragraph(at: 0), "First\n")
        XCTAssertEqual(document.paragraph(at: 1), "Second\n")
        XCTAssertEqual(document.paragraph(at: 2), "Third")  // Last paragraph has no trailing newline
    }

    // MARK: - Revision Tracking

    func testRevisionIncrementsOnEdit() {
        let document = DocumentModel()
        let initialRevision = document.revision

        // Simulate edit notification
        let range = document.contentStorage.documentRange
        document.contentDidChange(in: range, changeInLength: 5)

        XCTAssertEqual(document.revision, initialRevision + 1)
        XCTAssertTrue(document.isDirty)
    }
}
