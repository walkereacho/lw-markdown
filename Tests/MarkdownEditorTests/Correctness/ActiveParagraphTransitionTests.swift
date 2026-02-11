import XCTest
@testable import MarkdownEditor

/// Tests cursor movement transitions — verifies that when cursor moves
/// between paragraphs, the old one becomes inactive and the new one
/// becomes active, with all three layers staying consistent.
final class ActiveParagraphTransitionTests: XCTestCase {

    // MARK: - Basic Transitions

    func testCursorMoveFromHeadingToBody() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Heading\nBody text\n")
        harness.forceLayout()

        // Start at heading
        harness.moveCursor(toParagraph: 0, offset: 3)
        harness.forceLayout()

        harness.assertFragmentIsActive(paragraph: 0, true)
        harness.assertFragmentIsActive(paragraph: 1, false)
        harness.assertAllParagraphsConsistent(context: "cursor at heading")

        // Move to body
        harness.moveCursor(toParagraph: 1, offset: 2)
        harness.forceLayout()

        harness.assertFragmentIsActive(paragraph: 0, false)
        harness.assertFragmentIsActive(paragraph: 1, true)
        harness.assertAllParagraphsConsistent(context: "cursor at body")
    }

    func testCursorEntersCodeBlock() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Text\n```\ncode\n```\n")
        harness.forceLayout()

        // Start outside code block
        harness.moveCursor(toParagraph: 0, offset: 0)
        harness.forceLayout()
        harness.assertAllParagraphsConsistent(context: "cursor outside code block")

        // Move to opening fence
        harness.moveCursor(toParagraph: 1, offset: 0)
        harness.forceLayout()
        harness.assertFragmentIsActive(paragraph: 1, true)
        harness.assertAllParagraphsConsistent(context: "cursor at opening fence")

        // Move to code content
        harness.moveCursor(toParagraph: 2, offset: 0)
        harness.forceLayout()
        harness.assertFragmentIsActive(paragraph: 2, true)
        harness.assertFragmentIsActive(paragraph: 1, false)
        harness.assertAllParagraphsConsistent(context: "cursor at code content")

        // Move to closing fence
        harness.moveCursor(toParagraph: 3, offset: 0)
        harness.forceLayout()
        harness.assertFragmentIsActive(paragraph: 3, true)
        harness.assertFragmentIsActive(paragraph: 2, false)
        harness.assertAllParagraphsConsistent(context: "cursor at closing fence")
    }

    func testCursorExitsCodeBlock() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\ncode\n```\nBody after\n")
        harness.forceLayout()

        // Start inside code block
        harness.moveCursor(toParagraph: 1, offset: 0)
        harness.forceLayout()
        harness.assertFragmentIsActive(paragraph: 1, true)
        harness.assertAllParagraphsConsistent(context: "cursor inside code")

        // Move out to body text
        harness.moveCursor(toParagraph: 3, offset: 0)
        harness.forceLayout()
        harness.assertFragmentIsActive(paragraph: 1, false)
        harness.assertFragmentIsActive(paragraph: 3, true)
        harness.assertAllParagraphsConsistent(context: "cursor exited code block")
    }

    // MARK: - Sequential Walk

    func testCursorWalkThroughEntireDocument() throws {
        let harness = RenderingCorrectnessHarness()
        try harness.loadFixture("comprehensive")
        harness.forceLayout()

        let count = harness.paragraphCount
        for i in 0..<count {
            guard let text = harness.paragraphText(at: i), !text.isEmpty else { continue }

            harness.moveCursor(toParagraph: i, offset: 0)
            harness.forceLayout()
            harness.assertFragmentIsActive(paragraph: i, true,
                context: "walk step \(i)")
            harness.assertAllParagraphsConsistent(
                context: "cursor at paragraph \(i)")
        }
    }

    func testCursorWalkThroughCodeBlocks() throws {
        let harness = RenderingCorrectnessHarness()
        try harness.loadFixture("code-blocks")
        harness.forceLayout()

        let count = harness.paragraphCount
        for i in 0..<count {
            guard let text = harness.paragraphText(at: i), !text.isEmpty else { continue }

            harness.moveCursor(toParagraph: i, offset: 0)
            harness.forceLayout()
            harness.assertFragmentIsActive(paragraph: i, true,
                context: "code-blocks walk step \(i)")
            harness.assertAllParagraphsConsistent(
                context: "code-blocks cursor at paragraph \(i)")
        }
    }

    // MARK: - Rapid Transitions

    func testRapidCursorMovement() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# H1\n## H2\n**bold**\n`code`\n- list\n")
        harness.forceLayout()

        // Move cursor rapidly through all paragraphs
        for i in 0..<harness.paragraphCount {
            harness.moveCursor(toParagraph: i, offset: 0)
        }
        harness.forceLayout()

        // After all movement, only the last non-empty paragraph should be active
        harness.assertAllParagraphsConsistent(context: "after rapid movement")
    }
}
