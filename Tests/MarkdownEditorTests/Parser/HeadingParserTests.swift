import XCTest
@testable import MarkdownEditor

final class HeadingParserTests: XCTestCase {

    let parser = MarkdownParser()

    func testH1Heading() {
        let tokens = parser.parse("# Hello World")

        XCTAssertEqual(tokens.count, 1)
        guard case .heading(let level) = tokens[0].element else {
            XCTFail("Expected heading element")
            return
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(tokens[0].contentRange, 2..<13)  // "Hello World"
        XCTAssertEqual(tokens[0].syntaxRanges, [0..<1])  // "#"
    }

    func testH2Heading() {
        let tokens = parser.parse("## Section Title")

        XCTAssertEqual(tokens.count, 1)
        guard case .heading(let level) = tokens[0].element else {
            XCTFail("Expected heading element")
            return
        }
        XCTAssertEqual(level, 2)
    }

    func testH6Heading() {
        let tokens = parser.parse("###### Deep")

        XCTAssertEqual(tokens.count, 1)
        guard case .heading(let level) = tokens[0].element else {
            XCTFail("Expected heading element")
            return
        }
        XCTAssertEqual(level, 6)
    }

    func testNotHeadingWithoutSpace() {
        // "#NoSpace" is not a heading - requires space after #
        let tokens = parser.parse("#NoSpace")

        // Should return no heading tokens (just plain text)
        let headingTokens = tokens.filter {
            if case .heading = $0.element { return true }
            return false
        }
        XCTAssertEqual(headingTokens.count, 0)
    }

    func testHeadingMaxLevel() {
        // 7 hashes is not a valid heading
        let tokens = parser.parse("####### Too Many")

        let headingTokens = tokens.filter {
            if case .heading = $0.element { return true }
            return false
        }
        XCTAssertEqual(headingTokens.count, 0)
    }
}
