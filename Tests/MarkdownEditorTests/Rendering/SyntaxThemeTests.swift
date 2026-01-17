import XCTest
@testable import MarkdownEditor

final class SyntaxThemeTests: XCTestCase {

    func testDefaultThemeExists() {
        let theme = SyntaxTheme.default
        XCTAssertNotNil(theme.bodyFont)
        XCTAssertNotNil(theme.boldFont)
        XCTAssertNotNil(theme.italicFont)
    }

    func testHeadingFontsExist() {
        let theme = SyntaxTheme.default
        for level in 1...6 {
            XCTAssertNotNil(theme.headingFonts[level], "Missing heading font for level \(level)")
        }
    }

    func testBodyAttributesContainRequiredKeys() {
        let attrs = SyntaxTheme.default.bodyAttributes
        XCTAssertNotNil(attrs[.font])
        XCTAssertNotNil(attrs[.foregroundColor])
    }

    func testHeadingAttributesByLevel() {
        let theme = SyntaxTheme.default
        let h1Attrs = theme.headingAttributes(level: 1)
        let h6Attrs = theme.headingAttributes(level: 6)

        // H1 should be larger than H6
        let h1Font = h1Attrs[.font] as? NSFont
        let h6Font = h6Attrs[.font] as? NSFont

        XCTAssertNotNil(h1Font)
        XCTAssertNotNil(h6Font)
        XCTAssertGreaterThan(h1Font!.pointSize, h6Font!.pointSize)
    }

    func testInlineCodeAttributesHaveBackgroundColor() {
        let attrs = SyntaxTheme.default.inlineCodeAttributes
        XCTAssertNotNil(attrs[.backgroundColor])
    }

    func testLinkAttributesHaveUnderline() {
        let attrs = SyntaxTheme.default.linkAttributes
        XCTAssertNotNil(attrs[.underlineStyle])
    }

    func testSyntaxCharacterAttributesHaveMutedColor() {
        let theme = SyntaxTheme.default
        let syntaxColor = theme.syntaxCharacterAttributes[.foregroundColor] as? NSColor
        let bodyColor = theme.bodyAttributes[.foregroundColor] as? NSColor

        XCTAssertNotNil(syntaxColor)
        XCTAssertNotNil(bodyColor)
        // Syntax characters should have a different color than body text
        XCTAssertNotEqual(syntaxColor, bodyColor)
    }

    func testHeadingFontSizeProgression() {
        let theme = SyntaxTheme.default

        // Heading sizes should decrease from H1 to H6
        var previousSize: CGFloat = .greatestFiniteMagnitude
        for level in 1...6 {
            let font = theme.headingFonts[level]
            XCTAssertNotNil(font)
            XCTAssertLessThanOrEqual(font!.pointSize, previousSize)
            previousSize = font!.pointSize
        }
    }

    func testCodeFontIsMonospaced() {
        let theme = SyntaxTheme.default
        let codeFont = theme.codeFont

        // Check if the font is monospaced by comparing character widths
        let narrowChar = NSAttributedString(string: "i", attributes: [.font: codeFont])
        let wideChar = NSAttributedString(string: "m", attributes: [.font: codeFont])

        let narrowWidth = narrowChar.size().width
        let wideWidth = wideChar.size().width

        // In a monospaced font, all characters have the same width
        XCTAssertEqual(narrowWidth, wideWidth, accuracy: 0.1)
    }
}
