import XCTest
@testable import MarkdownEditor

final class ParserRenderingIntegrationTests: XCTestCase {

    func testPaneControllerUsesParser() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "# Hello")

        let pane = PaneController(document: document, frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        // Verify parser is connected
        let tokens = pane.layoutDelegate.tokenProvider.parse("# Hello")
        XCTAssertFalse(tokens.isEmpty, "Parser should return tokens for Markdown")
        XCTAssertEqual(tokens.first?.element, .heading(level: 1))
    }

    func testParserTokensForBold() {
        let document = DocumentModel()
        let pane = PaneController(document: document, frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        let tokens = pane.layoutDelegate.tokenProvider.parse("**bold**")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.element, .bold)
    }
}
