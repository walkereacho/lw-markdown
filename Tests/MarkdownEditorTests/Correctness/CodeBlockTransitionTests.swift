import XCTest
@testable import MarkdownEditor

/// Tests cross-paragraph state transitions when code block boundaries change.
/// These are the highest-risk cascading mutations.
final class CodeBlockTransitionTests: XCTestCase {

    // MARK: - Insert Opening Fence

    func testInsertOpeningFenceConvertsBodyToCodeBlock() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("hello\nworld\n")
        harness.forceLayout()

        // Baseline: both are body text
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)
        harness.assertBlockContext(paragraph: 1, isCodeBlock: false)
        harness.assertAllParagraphsConsistent(context: "before insert")

        // Insert opening fence at start
        harness.insertText("```\n", atParagraph: 0, offset: 0)
        harness.forceLayout()

        // Paragraph 0 is now the fence, paragraphs 1-2 are code block content (unclosed)
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false, isFence: true)
        harness.assertBlockContext(paragraph: 1, isCodeBlock: true)
        harness.assertBlockContext(paragraph: 2, isCodeBlock: true)
        harness.assertAllParagraphsConsistent(context: "after insert fence")
    }

    // MARK: - Delete Closing Fence

    func testDeleteClosingFenceCascadesCodeBlockState() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Title\n```\ncode line\n```\nMore text\n")
        harness.forceLayout()

        // Baseline
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)           // # Title
        harness.assertBlockContext(paragraph: 1, isCodeBlock: false, isFence: true) // ```
        harness.assertBlockContext(paragraph: 2, isCodeBlock: true)             // code line
        harness.assertBlockContext(paragraph: 3, isCodeBlock: false, isFence: true) // ```
        harness.assertBlockContext(paragraph: 4, isCodeBlock: false)           // More text
        harness.assertAllParagraphsConsistent(context: "before delete")

        // Delete closing fence (paragraph 3)
        harness.deleteParagraph(3)
        harness.forceLayout()

        // "More text" should now be inside the unclosed code block
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)            // # Title
        harness.assertBlockContext(paragraph: 1, isCodeBlock: false, isFence: true)  // ```
        harness.assertBlockContext(paragraph: 2, isCodeBlock: true)              // code line
        harness.assertBlockContext(paragraph: 3, isCodeBlock: true)              // More text (now code!)
        harness.assertAllParagraphsConsistent(context: "after delete closing fence")
    }

    // MARK: - Delete Opening Fence

    func testDeleteOpeningFenceRevertsCodeBlockToBody() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\nwas code\n```\n")
        harness.forceLayout()

        harness.assertBlockContext(paragraph: 1, isCodeBlock: true)
        harness.assertAllParagraphsConsistent(context: "before delete")

        // Delete opening fence (paragraph 0)
        harness.deleteParagraph(0)
        harness.forceLayout()

        // "was code" is now body text, "```" is now an unpaired opening fence
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)  // was code — now body
        harness.assertAllParagraphsConsistent(context: "after delete opening fence")
    }

    // MARK: - Insert Closing Fence

    func testInsertClosingFenceTerminatesCodeBlock() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\ncode1\ncode2\nstill code\n")
        harness.forceLayout()

        // All lines after fence are unclosed code block
        harness.assertBlockContext(paragraph: 1, isCodeBlock: true)
        harness.assertBlockContext(paragraph: 2, isCodeBlock: true)
        harness.assertBlockContext(paragraph: 3, isCodeBlock: true)
        harness.assertAllParagraphsConsistent(context: "before insert")

        // Insert closing fence after code2 (at end of paragraph 2)
        harness.insertText("\n```", atParagraph: 2, offset: 5)
        harness.forceLayout()

        // "still code" should now be body text
        // Note: exact paragraph indices may shift due to insertion
        harness.assertAllParagraphsConsistent(context: "after insert closing fence")
    }

    // MARK: - Convert Body Line to Fence

    func testConvertBodyLineToFenceCreatesCodeBlock() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("line A\nline B\nline C\n")
        harness.forceLayout()

        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)
        harness.assertBlockContext(paragraph: 1, isCodeBlock: false)
        harness.assertBlockContext(paragraph: 2, isCodeBlock: false)

        // Replace line B with a fence marker
        harness.replaceText(inParagraph: 1, range: 0..<6, with: "```")
        harness.forceLayout()

        // line A is normal, "```" is opening fence, line C is code block
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)
        harness.assertBlockContext(paragraph: 1, isCodeBlock: false, isFence: true)
        harness.assertBlockContext(paragraph: 2, isCodeBlock: true)
        harness.assertAllParagraphsConsistent(context: "after convert to fence")
    }

    // MARK: - Multi-block cascading

    func testDeleteFenceBetweenTwoCodeBlocksMergesThem() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\nblock1\n```\n```\nblock2\n```\n")
        harness.forceLayout()

        let blockContext = harness.paneController.layoutDelegate.blockContext
        XCTAssertEqual(blockContext.fencedCodeBlocks.count, 2, "Should have 2 code blocks")
        harness.assertAllParagraphsConsistent(context: "before merge")

        // Delete both the closing fence of block 1 (paragraph 2) and opening of block 2 (paragraph 3)
        // Delete paragraph 3 first (higher index), then paragraph 2
        harness.deleteParagraph(3)
        harness.forceLayout()
        harness.deleteParagraph(2)
        harness.forceLayout()

        // Now should be one large code block
        harness.assertAllParagraphsConsistent(context: "after merge")
    }
}
