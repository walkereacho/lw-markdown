import XCTest
@testable import MarkdownEditor

final class ParserIntegrationTests: XCTestCase {

    let parser = MarkdownParser()

    func testComplexParagraph() {
        let text = "# Heading with **bold** and *italic*"
        let tokens = parser.parse(text)

        // Should have heading, bold, and italic
        let hasHeading = tokens.contains { if case .heading = $0.element { return true }; return false }
        let hasBold = tokens.contains { if case .bold = $0.element { return true }; return false }
        let hasItalic = tokens.contains { if case .italic = $0.element { return true }; return false }

        XCTAssertTrue(hasHeading)
        XCTAssertTrue(hasBold)
        XCTAssertTrue(hasItalic)
    }

    func testLinkWithEmphasis() {
        let text = "Check [**bold link**](url)"
        let tokens = parser.parse(text)

        let hasLink = tokens.contains { if case .link = $0.element { return true }; return false }
        XCTAssertTrue(hasLink)
    }

    func testPlainText() {
        let text = "Just plain text, nothing special."
        let tokens = parser.parse(text)

        // Should return empty (no special formatting)
        XCTAssertEqual(tokens.count, 0)
    }

    func testEmptyString() {
        let tokens = parser.parse("")
        XCTAssertEqual(tokens.count, 0)
    }

    func testBlockquoteWithEmphasis() {
        let text = "> This is **quoted** text"
        let tokens = parser.parse(text)

        let hasBlockquote = tokens.contains { if case .blockquote = $0.element { return true }; return false }
        let hasBold = tokens.contains { if case .bold = $0.element { return true }; return false }
        XCTAssertTrue(hasBlockquote)
        XCTAssertTrue(hasBold)  // Bold inside blockquote is also parsed
    }

    func testListItemWithEmphasis() {
        let text = "- Item with *emphasis*"
        let tokens = parser.parse(text)

        let hasList = tokens.contains { if case .unorderedListItem = $0.element { return true }; return false }
        XCTAssertTrue(hasList)
    }

    func testMixedInlineElements() {
        let text = "Text with **bold**, *italic*, `code`, and [link](url)"
        let tokens = parser.parse(text)

        let hasBold = tokens.contains { if case .bold = $0.element { return true }; return false }
        let hasItalic = tokens.contains { if case .italic = $0.element { return true }; return false }
        let hasCode = tokens.contains { if case .inlineCode = $0.element { return true }; return false }
        let hasLink = tokens.contains { if case .link = $0.element { return true }; return false }

        XCTAssertTrue(hasBold)
        XCTAssertTrue(hasItalic)
        XCTAssertTrue(hasCode)
        XCTAssertTrue(hasLink)
    }

    func testCodeDoesNotContainEmphasis() {
        let text = "Check `**code not bold**` here"
        let tokens = parser.parse(text)

        let hasBold = tokens.contains { if case .bold = $0.element { return true }; return false }
        let hasCode = tokens.contains { if case .inlineCode = $0.element { return true }; return false }

        XCTAssertFalse(hasBold)  // Bold inside code should not be parsed
        XCTAssertTrue(hasCode)
    }

    func testBoldItalicCombination() {
        let text = "***bold and italic***"
        let tokens = parser.parse(text)

        let hasBoldItalic = tokens.contains { if case .boldItalic = $0.element { return true }; return false }
        XCTAssertTrue(hasBoldItalic)
    }

    func testParserConformsToTokenProviding() {
        // Verify the parser implements TokenProviding
        let tokenProvider: TokenProviding = MarkdownParser()
        let tokens = tokenProvider.parse("**test**")
        XCTAssertGreaterThan(tokens.count, 0)
    }

    func testSharedInstance() {
        // Verify shared instance works
        let tokens = MarkdownParser.shared.parse("# Heading")
        let hasHeading = tokens.contains { if case .heading = $0.element { return true }; return false }
        XCTAssertTrue(hasHeading)
    }
}
