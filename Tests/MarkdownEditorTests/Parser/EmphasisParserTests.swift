import XCTest
@testable import MarkdownEditor

final class EmphasisParserTests: XCTestCase {

    let parser = MarkdownParser()

    // MARK: - Bold

    func testBoldAsterisks() {
        let tokens = parser.parse("This is **bold** text")

        let boldTokens = tokens.filter {
            if case .bold = $0.element { return true }
            return false
        }
        XCTAssertEqual(boldTokens.count, 1)
        XCTAssertEqual(boldTokens[0].contentRange, 10..<14)  // "bold"
        XCTAssertEqual(boldTokens[0].syntaxRanges.count, 2)
        XCTAssertEqual(boldTokens[0].syntaxRanges[0], 8..<10)   // **
        XCTAssertEqual(boldTokens[0].syntaxRanges[1], 14..<16)  // **
    }

    func testBoldUnderscores() {
        let tokens = parser.parse("This is __bold__ text")

        let boldTokens = tokens.filter {
            if case .bold = $0.element { return true }
            return false
        }
        XCTAssertEqual(boldTokens.count, 1)
    }

    // MARK: - Italic

    func testItalicAsterisk() {
        let tokens = parser.parse("This is *italic* text")

        let italicTokens = tokens.filter {
            if case .italic = $0.element { return true }
            return false
        }
        XCTAssertEqual(italicTokens.count, 1)
        XCTAssertEqual(italicTokens[0].contentRange, 9..<15)  // "italic"
        XCTAssertEqual(italicTokens[0].syntaxRanges[0], 8..<9)   // *
        XCTAssertEqual(italicTokens[0].syntaxRanges[1], 15..<16)  // *
    }

    func testItalicUnderscore() {
        let tokens = parser.parse("This is _italic_ text")

        let italicTokens = tokens.filter {
            if case .italic = $0.element { return true }
            return false
        }
        XCTAssertEqual(italicTokens.count, 1)
    }

    // MARK: - Bold + Italic

    func testBoldItalic() {
        let tokens = parser.parse("This is ***both*** text")

        let boldItalicTokens = tokens.filter {
            if case .boldItalic = $0.element { return true }
            return false
        }
        XCTAssertEqual(boldItalicTokens.count, 1)
        XCTAssertEqual(boldItalicTokens[0].contentRange, 11..<15)  // "both"
    }

    // MARK: - Multiple Emphasis

    func testMultipleEmphasis() {
        let tokens = parser.parse("**bold** and *italic*")

        let boldTokens = tokens.filter {
            if case .bold = $0.element { return true }
            return false
        }
        let italicTokens = tokens.filter {
            if case .italic = $0.element { return true }
            return false
        }

        XCTAssertEqual(boldTokens.count, 1)
        XCTAssertEqual(italicTokens.count, 1)
    }

    // MARK: - Inline Code

    func testInlineCode() {
        let tokens = parser.parse("Use `let x = 1` here")

        let codeTokens = tokens.filter {
            if case .inlineCode = $0.element { return true }
            return false
        }
        XCTAssertEqual(codeTokens.count, 1)
        XCTAssertEqual(codeTokens[0].contentRange, 5..<14)  // "let x = 1"
        XCTAssertEqual(codeTokens[0].syntaxRanges[0], 4..<5)   // `
        XCTAssertEqual(codeTokens[0].syntaxRanges[1], 14..<15)  // `
    }

    func testInlineCodeDoesNotParseEmphasis() {
        // Asterisks inside code should not be parsed as emphasis
        let tokens = parser.parse("`**not bold**`")

        let boldTokens = tokens.filter {
            if case .bold = $0.element { return true }
            return false
        }
        let codeTokens = tokens.filter {
            if case .inlineCode = $0.element { return true }
            return false
        }

        XCTAssertEqual(boldTokens.count, 0)
        XCTAssertEqual(codeTokens.count, 1)
    }
}
