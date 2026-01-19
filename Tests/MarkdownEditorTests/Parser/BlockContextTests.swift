import XCTest
@testable import MarkdownEditor

final class BlockContextTests: XCTestCase {

    func testEmptyDocumentHasNoBlocks() {
        let context = BlockContext()
        XCTAssertEqual(context.fencedCodeBlocks.count, 0)
    }

    func testIsInsideFencedCodeBlock() {
        var context = BlockContext()
        context.fencedCodeBlocks = [(start: 2, end: 5, language: "swift", isClosed: true)]

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
        context.fencedCodeBlocks = [(start: 2, end: 5, language: nil, isClosed: true)]

        XCTAssertTrue(context.isFenceBoundary(paragraphIndex: 2))
        XCTAssertTrue(context.isFenceBoundary(paragraphIndex: 5))
        XCTAssertFalse(context.isFenceBoundary(paragraphIndex: 3))
    }

    func testLanguageExtraction() {
        var context = BlockContext()
        context.fencedCodeBlocks = [(start: 0, end: 3, language: "python", isClosed: true)]

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

    // MARK: - Comparison Tests

    func testParagraphsChangedWhenOpeningNewBlock() {
        // Before: no code blocks
        let oldContext = BlockContext()

        // After: user typed ``` on line 2, unclosed block extends to EOF (line 4)
        var newContext = BlockContext()
        newContext.fencedCodeBlocks = [(start: 2, end: 4, language: nil, isClosed: false)]

        let changed = newContext.paragraphsWithChangedCodeBlockStatus(
            comparedTo: oldContext,
            paragraphCount: 5
        )

        // Lines 2, 3, 4 became part of code block
        XCTAssertEqual(changed, Set([2, 3, 4]))
    }

    func testParagraphsChangedWhenClosingBlock() {
        // Before: unclosed block from line 1 to EOF (line 4)
        var oldContext = BlockContext()
        oldContext.fencedCodeBlocks = [(start: 1, end: 4, language: nil, isClosed: false)]

        // After: user typed closing ``` on line 2
        var newContext = BlockContext()
        newContext.fencedCodeBlocks = [(start: 1, end: 2, language: nil, isClosed: true)]

        let changed = newContext.paragraphsWithChangedCodeBlockStatus(
            comparedTo: oldContext,
            paragraphCount: 5
        )

        // Lines 3 and 4 stopped being code (they were inside before, now outside)
        XCTAssertEqual(changed, Set([3, 4]))
    }

    func testParagraphsChangedWhenBreakingBlock() {
        // Before: closed block from line 1 to line 3
        var oldContext = BlockContext()
        oldContext.fencedCodeBlocks = [(start: 1, end: 3, language: nil, isClosed: true)]

        // After: user deleted closing fence, block now extends to EOF (line 5)
        var newContext = BlockContext()
        newContext.fencedCodeBlocks = [(start: 1, end: 5, language: nil, isClosed: false)]

        let changed = newContext.paragraphsWithChangedCodeBlockStatus(
            comparedTo: oldContext,
            paragraphCount: 6
        )

        // Line 3 stays "in block" (was closing fence, now content)
        // Lines 4 and 5 are newly part of block
        XCTAssertEqual(changed, Set([4, 5]))
    }

    func testNoChangesWhenEditingInsideBlock() {
        // Before: closed code block from line 1 to line 3
        var oldContext = BlockContext()
        oldContext.fencedCodeBlocks = [(start: 1, end: 3, language: nil, isClosed: true)]

        // After: same block (user just edited content inside)
        var newContext = BlockContext()
        newContext.fencedCodeBlocks = [(start: 1, end: 3, language: nil, isClosed: true)]

        let changed = newContext.paragraphsWithChangedCodeBlockStatus(
            comparedTo: oldContext,
            paragraphCount: 5
        )

        // No paragraphs changed status
        XCTAssertEqual(changed, Set())
    }

    func testNoChangesWhenEditingOutsideBlock() {
        // Before: closed code block from line 2 to line 4
        var oldContext = BlockContext()
        oldContext.fencedCodeBlocks = [(start: 2, end: 4, language: nil, isClosed: true)]

        // After: same block (user edited line 0 which is outside)
        var newContext = BlockContext()
        newContext.fencedCodeBlocks = [(start: 2, end: 4, language: nil, isClosed: true)]

        let changed = newContext.paragraphsWithChangedCodeBlockStatus(
            comparedTo: oldContext,
            paragraphCount: 6
        )

        XCTAssertEqual(changed, Set())
    }

    // MARK: - Unclosed Block Tests

    func testUnclosedBlockIncludesEndLine() {
        // Unclosed block: end line is content, not a fence
        var context = BlockContext()
        context.fencedCodeBlocks = [(start: 0, end: 2, language: nil, isClosed: false)]

        // Line 0 is opening fence
        XCTAssertTrue(context.isOpeningFence(paragraphIndex: 0).0)
        XCTAssertFalse(context.isInsideFencedCodeBlock(paragraphIndex: 0).0)

        // Lines 1 and 2 are inside (unclosed includes end line)
        XCTAssertTrue(context.isInsideFencedCodeBlock(paragraphIndex: 1).0)
        XCTAssertTrue(context.isInsideFencedCodeBlock(paragraphIndex: 2).0)

        // Line 2 is NOT a closing fence (block is unclosed)
        XCTAssertFalse(context.isClosingFence(paragraphIndex: 2))
        XCTAssertFalse(context.isFenceBoundary(paragraphIndex: 2))
    }

    func testClosedBlockExcludesEndLine() {
        // Closed block: end line is closing fence
        var context = BlockContext()
        context.fencedCodeBlocks = [(start: 0, end: 2, language: nil, isClosed: true)]

        // Line 0 is opening fence
        XCTAssertTrue(context.isOpeningFence(paragraphIndex: 0).0)

        // Line 1 is inside
        XCTAssertTrue(context.isInsideFencedCodeBlock(paragraphIndex: 1).0)

        // Line 2 is closing fence, not inside
        XCTAssertFalse(context.isInsideFencedCodeBlock(paragraphIndex: 2).0)
        XCTAssertTrue(context.isClosingFence(paragraphIndex: 2))
        XCTAssertTrue(context.isFenceBoundary(paragraphIndex: 2))
    }
}
