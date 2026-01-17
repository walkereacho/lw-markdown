import XCTest
@testable import MarkdownEditor

final class ListParserTests: XCTestCase {

    let parser = MarkdownParser()

    // MARK: - Blockquotes

    func testBlockquote() {
        let tokens = parser.parse("> This is quoted")

        XCTAssertEqual(tokens.count, 1)
        guard case .blockquote = tokens[0].element else {
            XCTFail("Expected blockquote element")
            return
        }
        XCTAssertEqual(tokens[0].contentRange, 2..<16)  // "This is quoted"
        XCTAssertEqual(tokens[0].syntaxRanges, [0..<2])  // "> "
    }

    // MARK: - Unordered Lists

    func testUnorderedListDash() {
        let tokens = parser.parse("- List item")

        XCTAssertEqual(tokens.count, 1)
        guard case .unorderedListItem = tokens[0].element else {
            XCTFail("Expected unordered list item")
            return
        }
        XCTAssertEqual(tokens[0].contentRange, 2..<11)
        XCTAssertEqual(tokens[0].syntaxRanges, [0..<2])
    }

    func testUnorderedListAsterisk() {
        let tokens = parser.parse("* Another item")

        XCTAssertEqual(tokens.count, 1)
        guard case .unorderedListItem = tokens[0].element else {
            XCTFail("Expected unordered list item")
            return
        }
    }

    func testUnorderedListPlus() {
        let tokens = parser.parse("+ Plus item")

        XCTAssertEqual(tokens.count, 1)
        guard case .unorderedListItem = tokens[0].element else {
            XCTFail("Expected unordered list item")
            return
        }
    }

    // MARK: - Ordered Lists

    func testOrderedList() {
        let tokens = parser.parse("1. First item")

        XCTAssertEqual(tokens.count, 1)
        guard case .orderedListItem(let number) = tokens[0].element else {
            XCTFail("Expected ordered list item")
            return
        }
        XCTAssertEqual(number, 1)
        XCTAssertEqual(tokens[0].contentRange, 3..<13)  // "First item"
        XCTAssertEqual(tokens[0].syntaxRanges, [0..<3])  // "1. "
    }

    func testOrderedListLargeNumber() {
        let tokens = parser.parse("42. Answer")

        XCTAssertEqual(tokens.count, 1)
        guard case .orderedListItem(let number) = tokens[0].element else {
            XCTFail("Expected ordered list item")
            return
        }
        XCTAssertEqual(number, 42)
    }

    // MARK: - Horizontal Rule

    func testHorizontalRuleDashes() {
        let tokens = parser.parse("---")

        XCTAssertEqual(tokens.count, 1)
        guard case .horizontalRule = tokens[0].element else {
            XCTFail("Expected horizontal rule")
            return
        }
        XCTAssertEqual(tokens[0].syntaxRanges, [0..<3])
    }

    func testHorizontalRuleAsterisks() {
        let tokens = parser.parse("***")

        XCTAssertEqual(tokens.count, 1)
        guard case .horizontalRule = tokens[0].element else {
            XCTFail("Expected horizontal rule")
            return
        }
    }

    func testHorizontalRuleUnderscores() {
        let tokens = parser.parse("___")

        XCTAssertEqual(tokens.count, 1)
        guard case .horizontalRule = tokens[0].element else {
            XCTFail("Expected horizontal rule")
            return
        }
    }
}
