import XCTest
@testable import MarkdownEditor

/// Tests that paragraph index shifts after insertions/deletions
/// correctly propagate through BlockContext, ParagraphIndexCache,
/// and layout fragment state.
final class ParagraphIndexShiftTests: XCTestCase {

    // MARK: - Insertion

    func testInsertParagraphAtTopShiftsAllIndices() throws {
        let harness = RenderingCorrectnessHarness()
        try harness.loadFixture("comprehensive")
        harness.forceLayout()

        let originalCount = harness.paragraphCount
        harness.assertAllParagraphsConsistent(context: "before insert")

        // Insert a new line at the very top
        harness.insertText("New first line\n", atParagraph: 0, offset: 0)
        harness.forceLayout()

        harness.assertParagraphCount(originalCount + 1)
        harness.assertAllParagraphsConsistent(context: "after insert at top")
    }

    func testInsertParagraphInMiddle() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Heading\nBody\n## Another\n")
        harness.forceLayout()

        let originalCount = harness.paragraphCount
        harness.assertAllParagraphsConsistent(context: "before insert")

        // Insert between Body and ## Another
        harness.insertText("Inserted line\n", atParagraph: 2, offset: 0)
        harness.forceLayout()

        harness.assertParagraphCount(originalCount + 1)
        harness.assertAllParagraphsConsistent(context: "after insert in middle")
    }

    // MARK: - Deletion

    func testDeleteHeadingParagraph() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Heading\nBody text\n## Sub\n")
        harness.forceLayout()

        let originalCount = harness.paragraphCount
        harness.assertAllParagraphsConsistent(context: "before delete")

        // Delete the heading
        harness.deleteParagraph(0)
        harness.forceLayout()

        harness.assertParagraphCount(originalCount - 1)
        harness.assertAllParagraphsConsistent(context: "after delete heading")
    }

    func testDeleteFenceLineShiftsAndCascades() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Text\n```\ncode\n```\nMore\n")
        harness.forceLayout()

        harness.assertBlockContext(paragraph: 2, isCodeBlock: true)
        harness.assertBlockContext(paragraph: 4, isCodeBlock: false)
        harness.assertAllParagraphsConsistent(context: "before delete")

        // Delete opening fence
        harness.deleteParagraph(1)
        harness.forceLayout()

        // Index shift + code block boundary change
        harness.assertAllParagraphsConsistent(context: "after delete fence")
    }

    // MARK: - Bulk Operations

    func testBulkInsertMultipleLines() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Title\nBody\n")
        harness.forceLayout()

        let originalCount = harness.paragraphCount
        harness.assertAllParagraphsConsistent(context: "before bulk insert")

        // Simulate pasting multiple lines (body text only — multi-paragraph paste
        // applies font to the first paragraph only, so block-level elements like
        // blockquotes would get the wrong font; that's a separate willProcessEditing issue)
        let pastedText = "Line 1\nLine 2\nLine 3\n- List item\nMore text\n"
        harness.insertText(pastedText, atParagraph: 1, offset: 0)
        harness.forceLayout()

        XCTAssertGreaterThan(harness.paragraphCount, originalCount)
        harness.assertAllParagraphsConsistent(context: "after bulk insert")
    }

    func testInsertParagraphBeforeCodeBlock() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\ncode\n```\n")
        harness.forceLayout()

        harness.assertBlockContext(paragraph: 0, isCodeBlock: false, isFence: true)
        harness.assertBlockContext(paragraph: 1, isCodeBlock: true)
        harness.assertBlockContext(paragraph: 2, isCodeBlock: false, isFence: true)
        harness.assertAllParagraphsConsistent(context: "before insert")

        // Insert a line before the code block
        harness.insertText("New line\n", atParagraph: 0, offset: 0)
        harness.forceLayout()

        // Code block should shift by 1 but remain valid
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)  // New line
        harness.assertBlockContext(paragraph: 1, isCodeBlock: false, isFence: true)  // ```
        harness.assertBlockContext(paragraph: 2, isCodeBlock: true)   // code
        harness.assertBlockContext(paragraph: 3, isCodeBlock: false, isFence: true)  // ```
        harness.assertAllParagraphsConsistent(context: "after insert before code block")
    }
}
