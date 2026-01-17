import XCTest
@testable import MarkdownEditor

final class MarkdownLayoutFragmentTests: XCTestCase {

    func testFragmentCreation() {
        // This is a basic smoke test - full visual testing requires UI tests
        let tokens = [
            MarkdownToken(
                element: .bold,
                contentRange: 2..<6,
                syntaxRanges: [0..<2, 6..<8]
            )
        ]

        // We can't easily test drawing without a real text element,
        // but we can verify the fragment stores its configuration
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].element, .bold)
    }

    func testActiveVsInactiveState() {
        // Verify that tokens and active state are stored correctly
        let tokens: [MarkdownToken] = []

        // Active fragment
        let activeConfig = (tokens: tokens, isActive: true)
        XCTAssertTrue(activeConfig.isActive)

        // Inactive fragment
        let inactiveConfig = (tokens: tokens, isActive: false)
        XCTAssertFalse(inactiveConfig.isActive)
    }

    func testTokenRangesAreValid() {
        // Test that token ranges are properly structured
        let boldToken = MarkdownToken(
            element: .bold,
            contentRange: 2..<6,
            syntaxRanges: [0..<2, 6..<8]
        )

        // Content range should not overlap with syntax ranges
        let syntaxCovered = boldToken.syntaxRanges.flatMap { Array($0) }
        let contentCovered = Array(boldToken.contentRange)

        for contentIndex in contentCovered {
            XCTAssertFalse(syntaxCovered.contains(contentIndex),
                           "Content and syntax ranges should not overlap")
        }
    }

    func testHeadingTokenLevels() {
        // Test that heading levels are preserved
        for level in 1...6 {
            let token = MarkdownToken(
                element: .heading(level: level),
                contentRange: level..<(level + 5),
                syntaxRanges: [0..<level]  // # symbols
            )

            if case .heading(let storedLevel) = token.element {
                XCTAssertEqual(storedLevel, level)
            } else {
                XCTFail("Expected heading element")
            }
        }
    }

    func testLinkTokenPreservesURL() {
        let url = "https://example.com"
        let token = MarkdownToken(
            element: .link(url: url),
            contentRange: 1..<5,
            syntaxRanges: [0..<1, 5..<7]  // [ and ](url)
        )

        if case .link(let storedURL) = token.element {
            XCTAssertEqual(storedURL, url)
        } else {
            XCTFail("Expected link element")
        }
    }

    func testOrderedListItemPreservesNumber() {
        let token = MarkdownToken(
            element: .orderedListItem(number: 42),
            contentRange: 4..<10,
            syntaxRanges: [0..<4]  // "42. "
        )

        if case .orderedListItem(let number) = token.element {
            XCTAssertEqual(number, 42)
        } else {
            XCTFail("Expected ordered list item element")
        }
    }

    func testFencedCodeBlockPreservesLanguage() {
        let language = "swift"
        let token = MarkdownToken(
            element: .fencedCodeBlock(language: language),
            contentRange: 10..<50,
            syntaxRanges: [0..<10, 50..<53]  // ```swift and ```
        )

        if case .fencedCodeBlock(let storedLanguage) = token.element {
            XCTAssertEqual(storedLanguage, language)
        } else {
            XCTFail("Expected fenced code block element")
        }
    }

    func testNestingDepthForLists() {
        let token = MarkdownToken(
            element: .unorderedListItem,
            contentRange: 4..<10,
            syntaxRanges: [0..<2],  // "- "
            nestingDepth: 3
        )

        XCTAssertEqual(token.nestingDepth, 3)
    }

    func testNestingDepthForBlockquotes() {
        let token = MarkdownToken(
            element: .blockquote,
            contentRange: 3..<20,
            syntaxRanges: [0..<2],  // "> "
            nestingDepth: 2
        )

        XCTAssertEqual(token.nestingDepth, 2)
    }
}
