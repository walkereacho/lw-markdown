import XCTest
@testable import MarkdownEditor

final class BlockContextTests: XCTestCase {

    func testEmptyDocumentHasNoBlocks() {
        let context = BlockContext()
        XCTAssertEqual(context.fencedCodeBlocks.count, 0)
    }

    func testIsInsideFencedCodeBlock() {
        var context = BlockContext()
        context.fencedCodeBlocks = [(start: 2, end: 5, language: "swift")]

        // Paragraphs 3 and 4 are inside (exclusive of boundaries)
        XCTAssertTrue(context.isInsideFencedCodeBlock(paragraphIndex: 3).0)
        XCTAssertTrue(context.isInsideFencedCodeBlock(paragraphIndex: 4).0)

        // Boundaries themselves are not "inside"
        XCTAssertFalse(context.isInsideFencedCodeBlock(paragraphIndex: 2).0)
        XCTAssertFalse(context.isInsideFencedCodeBlock(paragraphIndex: 5).0)

        // Outside
        XCTAssertFalse(context.isInsideFencedCodeBlock(paragraphIndex: 0).0)
        XCTAssertFalse(context.isInsideFencedCodeBlock(paragraphIndex: 10).0)
    }

    func testIsFenceBoundary() {
        var context = BlockContext()
        context.fencedCodeBlocks = [(start: 2, end: 5, language: nil)]

        XCTAssertTrue(context.isFenceBoundary(paragraphIndex: 2))
        XCTAssertTrue(context.isFenceBoundary(paragraphIndex: 5))
        XCTAssertFalse(context.isFenceBoundary(paragraphIndex: 3))
    }

    func testLanguageExtraction() {
        var context = BlockContext()
        context.fencedCodeBlocks = [(start: 0, end: 3, language: "python")]

        let (isInside, language) = context.isInsideFencedCodeBlock(paragraphIndex: 1)
        XCTAssertTrue(isInside)
        XCTAssertEqual(language, "python")
    }

    // MARK: - Scanner Tests

    func testScannerFindsCodeBlock() {
        let paragraphs = [
            "Normal text",
            "```swift",
            "let x = 1",
            "```",
            "More text"
        ]

        let scanner = BlockContextScanner()
        let context = scanner.scan(paragraphs: paragraphs)

        XCTAssertEqual(context.fencedCodeBlocks.count, 1)
        XCTAssertEqual(context.fencedCodeBlocks[0].start, 1)
        XCTAssertEqual(context.fencedCodeBlocks[0].end, 3)
        XCTAssertEqual(context.fencedCodeBlocks[0].language, "swift")
    }

    func testScannerHandlesUnclosedBlock() {
        let paragraphs = [
            "```python",
            "code here",
            "more code"
        ]

        let scanner = BlockContextScanner()
        let context = scanner.scan(paragraphs: paragraphs)

        XCTAssertEqual(context.fencedCodeBlocks.count, 1)
        XCTAssertEqual(context.fencedCodeBlocks[0].start, 0)
        XCTAssertEqual(context.fencedCodeBlocks[0].end, 2)  // Extends to end
    }

    func testScannerFindsMultipleBlocks() {
        let paragraphs = [
            "```",
            "block 1",
            "```",
            "normal",
            "```",
            "block 2",
            "```"
        ]

        let scanner = BlockContextScanner()
        let context = scanner.scan(paragraphs: paragraphs)

        XCTAssertEqual(context.fencedCodeBlocks.count, 2)
    }

    func testScannerTildeFence() {
        let paragraphs = [
            "~~~",
            "code",
            "~~~"
        ]

        let scanner = BlockContextScanner()
        let context = scanner.scan(paragraphs: paragraphs)

        XCTAssertEqual(context.fencedCodeBlocks.count, 1)
    }
}
