import XCTest
@testable import MarkdownEditor

/// Tests character-by-character editing within paragraphs.
/// These exercise willProcessEditing on every keystroke, verifying that
/// paragraph type transitions (body↔heading↔code↔blockquote↔list) keep
/// all three layers consistent after each individual edit.
final class IncrementalEditTests: XCTestCase {

    // MARK: - Body → Heading

    func testTypingHashSpaceConvertsBodyToHeading() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Hello world\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default

        // Baseline: body font
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "before typing")
        harness.assertAllParagraphsConsistent(context: "before typing")

        // Type '#' at start — not a heading yet (no space after)
        harness.insertText("#", atParagraph: 0, offset: 0)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "after '#' only")
        harness.assertAllParagraphsConsistent(context: "after '#' only")

        // Type ' ' after '#' — now it's "# Hello world", a heading
        harness.insertText(" ", atParagraph: 0, offset: 1)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!, context: "after '# '")
        harness.assertAllParagraphsConsistent(context: "after '# '")
    }

    func testTypingSecondHashChangesHeadingLevel() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Heading\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default

        // Baseline: H1
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!, context: "H1")

        // Insert another '#' after the first → "## Heading"
        harness.insertText("#", atParagraph: 0, offset: 1)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[2]!, context: "H2")
        harness.assertAllParagraphsConsistent(context: "after H1 → H2")
    }

    // MARK: - Heading → Body

    func testDeletingHashSpaceConvertsHeadingToBody() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Hello\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!, context: "before delete")

        // Delete the space (character at offset 1) → "#Hello" (no longer a heading)
        harness.replaceText(inParagraph: 0, range: 1..<2, with: "")
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "after delete space")
        harness.assertAllParagraphsConsistent(context: "after heading → body")
    }

    func testBackspacingHashFromHeading() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Hello\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default

        // Delete '#' (character at offset 0) → " Hello" (body text)
        harness.replaceText(inParagraph: 0, range: 0..<1, with: "")
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "after backspace #")
        harness.assertAllParagraphsConsistent(context: "after backspace heading")
    }

    // MARK: - Body → Blockquote

    func testTypingGreaterThanSpaceConvertsToBlockquote() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Some text\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "before")

        // Type '>' at start
        harness.insertText(">", atParagraph: 0, offset: 0)
        harness.forceLayout()
        // ">Some text" — parser may or may not treat this as blockquote without space
        harness.assertAllParagraphsConsistent(context: "after '>' only")

        // Type ' ' after '>'
        harness.insertText(" ", atParagraph: 0, offset: 1)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.italicFont, context: "after '> '")
        harness.assertAllParagraphsConsistent(context: "after '> ' blockquote")
    }

    // MARK: - Body → List

    func testTypingDashSpaceConvertsToUnorderedList() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Item text\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "before")

        // Type '-' at start
        harness.insertText("-", atParagraph: 0, offset: 0)
        harness.forceLayout()
        harness.assertAllParagraphsConsistent(context: "after '-' only")

        // Type ' ' after '-' → "- Item text" (unordered list)
        harness.insertText(" ", atParagraph: 0, offset: 1)
        harness.forceLayout()
        // List items use body font but get paragraph style indent
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "after '- '")
        harness.assertAllParagraphsConsistent(context: "after list conversion")
    }

    func testTypingNumberDotSpaceConvertsToOrderedList() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Item text\n")
        harness.forceLayout()

        // Type "1. " character by character
        harness.insertText("1", atParagraph: 0, offset: 0)
        harness.forceLayout()
        harness.assertAllParagraphsConsistent(context: "after '1'")

        harness.insertText(".", atParagraph: 0, offset: 1)
        harness.forceLayout()
        harness.assertAllParagraphsConsistent(context: "after '1.'")

        harness.insertText(" ", atParagraph: 0, offset: 2)
        harness.forceLayout()
        harness.assertAllParagraphsConsistent(context: "after '1. '")
    }

    // MARK: - Body → Code Block Fence

    func testTypingBackticksCreatesCodeBlockFence() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("hello\nworld\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default

        // Both lines are body text
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont)
        harness.assertStorageFont(paragraph: 1, expected: theme.bodyFont)

        // Type first backtick at start of paragraph 0
        harness.replaceText(inParagraph: 0, range: 0..<5, with: "`")
        harness.forceLayout()
        harness.assertAllParagraphsConsistent(context: "after first backtick")

        // Type second backtick
        harness.insertText("`", atParagraph: 0, offset: 1)
        harness.forceLayout()
        harness.assertAllParagraphsConsistent(context: "after second backtick")

        // Type third backtick → "```" — now it's a fence line
        harness.insertText("`", atParagraph: 0, offset: 2)
        harness.forceLayout()
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false, isFence: true,
            context: "opening fence")
        harness.assertBlockContext(paragraph: 1, isCodeBlock: true,
            context: "world is now code")
        harness.assertStorageFont(paragraph: 0, expected: theme.codeFont, context: "fence font")
        harness.assertStorageFont(paragraph: 1, expected: theme.codeFont, context: "code content font")
        harness.assertAllParagraphsConsistent(context: "after triple backtick")
    }

    // MARK: - Code Block Fence → Body (backspacing)

    func testBackspacingFenceCharacterByCharacter() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\ncode line\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false, isFence: true)
        harness.assertBlockContext(paragraph: 1, isCodeBlock: true)

        // Delete third backtick → "``"
        harness.replaceText(inParagraph: 0, range: 2..<3, with: "")
        harness.forceLayout()
        // No longer a fence — "code line" reverts to body
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)
        harness.assertBlockContext(paragraph: 1, isCodeBlock: false)
        harness.assertStorageFont(paragraph: 1, expected: theme.bodyFont, context: "reverted to body")
        harness.assertAllParagraphsConsistent(context: "after removing third backtick")
    }

    // MARK: - Typing Within Active Paragraph

    func testTypingInsideHeadingMaintainsHeadingFont() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Hello\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!)

        // Type " world" at end of heading content
        harness.insertText(" world", atParagraph: 0, offset: 7)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!,
            context: "heading font after appending")
        harness.assertAllParagraphsConsistent(context: "after typing in heading")
    }

    func testTypingInsideCodeBlockContentMaintainsCodeFont() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\nlet x = 1\n```\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default
        harness.assertStorageFont(paragraph: 1, expected: theme.codeFont)

        // Type more code
        harness.insertText(" + 2", atParagraph: 1, offset: 9)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 1, expected: theme.codeFont,
            context: "code font after editing code")
        harness.assertAllParagraphsConsistent(context: "after typing in code block")
    }

    func testTypingInsideBlockquoteMaintainsItalicFont() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("> Quote text\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default
        harness.assertStorageFont(paragraph: 0, expected: theme.italicFont)

        // Type more quoted text
        harness.insertText(" here", atParagraph: 0, offset: 12)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.italicFont,
            context: "italic font after editing blockquote")
        harness.assertAllParagraphsConsistent(context: "after typing in blockquote")
    }

    // MARK: - Multi-step Type Transitions

    func testBodyToHeadingToHigherLevelAndBack() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Hello\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default

        // body → H1
        harness.insertText("# ", atParagraph: 0, offset: 0)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!, context: "H1")
        harness.assertAllParagraphsConsistent(context: "body → H1")

        // H1 → H2
        harness.insertText("#", atParagraph: 0, offset: 1)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[2]!, context: "H2")
        harness.assertAllParagraphsConsistent(context: "H1 → H2")

        // H2 → H3
        harness.insertText("#", atParagraph: 0, offset: 2)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[3]!, context: "H3")
        harness.assertAllParagraphsConsistent(context: "H2 → H3")

        // H3 → body (delete all "### ")
        harness.replaceText(inParagraph: 0, range: 0..<4, with: "")
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "back to body")
        harness.assertAllParagraphsConsistent(context: "H3 → body")
    }

    func testBodyToBlockquoteToHeading() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Text\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default

        // body → blockquote
        harness.insertText("> ", atParagraph: 0, offset: 0)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.italicFont, context: "blockquote")
        harness.assertAllParagraphsConsistent(context: "body → blockquote")

        // blockquote → body (remove "> ")
        harness.replaceText(inParagraph: 0, range: 0..<2, with: "")
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.bodyFont, context: "body again")
        harness.assertAllParagraphsConsistent(context: "blockquote → body")

        // body → heading
        harness.insertText("# ", atParagraph: 0, offset: 0)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!, context: "heading")
        harness.assertAllParagraphsConsistent(context: "body → heading")
    }

    // MARK: - Adjacent Paragraph Isolation

    func testEditingOneParagraphDoesNotAffectNeighbors() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Heading\nBody text\n```\ncode\n```\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default

        // Verify initial state
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!)
        harness.assertStorageFont(paragraph: 1, expected: theme.bodyFont)
        harness.assertStorageFont(paragraph: 3, expected: theme.codeFont)
        harness.assertAllParagraphsConsistent(context: "initial")

        // Edit body text — heading and code block should be unaffected
        harness.insertText(" extra", atParagraph: 1, offset: 9)
        harness.forceLayout()
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!,
            context: "heading unchanged")
        harness.assertStorageFont(paragraph: 1, expected: theme.bodyFont,
            context: "body after edit")
        harness.assertStorageFont(paragraph: 3, expected: theme.codeFont,
            context: "code unchanged")
        harness.assertAllParagraphsConsistent(context: "after editing body")
    }

    // MARK: - Enter Key (Splitting Paragraphs)

    func testPressingEnterInMiddleOfHeading() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Hello World\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!)

        // Press enter after "Hello" → splits into "# Hello\n" and "World\n"
        harness.insertText("\n", atParagraph: 0, offset: 7)
        harness.forceLayout()

        // First paragraph remains heading
        harness.assertStorageFont(paragraph: 0, expected: theme.headingFonts[1]!,
            context: "first half still heading")
        // Second paragraph becomes body (no # prefix)
        harness.assertStorageFont(paragraph: 1, expected: theme.bodyFont,
            context: "second half is body")
        harness.assertAllParagraphsConsistent(context: "after splitting heading")
    }

    func testPressingEnterInCodeBlockContent() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\nlet x = 1\n```\n")
        harness.forceLayout()

        let theme = SyntaxTheme.default

        // Press enter in middle of code → splits code line
        harness.insertText("\n", atParagraph: 1, offset: 5)
        harness.forceLayout()

        // Both resulting lines should still be code block content
        harness.assertBlockContext(paragraph: 1, isCodeBlock: true, context: "first code line")
        harness.assertBlockContext(paragraph: 2, isCodeBlock: true, context: "second code line")
        harness.assertStorageFont(paragraph: 1, expected: theme.codeFont)
        harness.assertStorageFont(paragraph: 2, expected: theme.codeFont)
        harness.assertAllParagraphsConsistent(context: "after splitting code line")
    }
}
