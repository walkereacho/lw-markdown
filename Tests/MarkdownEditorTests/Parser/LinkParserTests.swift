import XCTest
@testable import MarkdownEditor

final class LinkParserTests: XCTestCase {

    let parser = MarkdownParser()

    func testSimpleLink() {
        let tokens = parser.parse("Click [here](https://example.com) now")

        let linkTokens = tokens.filter {
            if case .link = $0.element { return true }
            return false
        }
        XCTAssertEqual(linkTokens.count, 1)

        guard case .link(let url) = linkTokens[0].element else {
            XCTFail("Expected link element")
            return
        }
        XCTAssertEqual(url, "https://example.com")
        XCTAssertEqual(linkTokens[0].contentRange, 7..<11)  // "here"
    }

    func testLinkWithSpacesInText() {
        let tokens = parser.parse("[Click here](https://example.com)")

        let linkTokens = tokens.filter {
            if case .link = $0.element { return true }
            return false
        }
        XCTAssertEqual(linkTokens.count, 1)

        guard case .link(let url) = linkTokens[0].element else {
            XCTFail("Expected link element")
            return
        }
        XCTAssertEqual(url, "https://example.com")
    }

    func testMultipleLinks() {
        let tokens = parser.parse("[A](a.com) and [B](b.com)")

        let linkTokens = tokens.filter {
            if case .link = $0.element { return true }
            return false
        }
        XCTAssertEqual(linkTokens.count, 2)
    }

    func testLinkSyntaxRanges() {
        let tokens = parser.parse("[text](url)")

        let linkTokens = tokens.filter {
            if case .link = $0.element { return true }
            return false
        }
        XCTAssertEqual(linkTokens.count, 1)

        // Syntax ranges should be: [, ](, )
        XCTAssertEqual(linkTokens[0].syntaxRanges.count, 3)
        XCTAssertEqual(linkTokens[0].syntaxRanges[0], 0..<1)   // [
        XCTAssertEqual(linkTokens[0].syntaxRanges[1], 5..<7)   // ](
        XCTAssertEqual(linkTokens[0].syntaxRanges[2], 10..<11) // )
    }
}
