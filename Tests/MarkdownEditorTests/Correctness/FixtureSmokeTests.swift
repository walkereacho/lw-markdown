import XCTest
@testable import MarkdownEditor

/// Loads every test fixture, forces layout, and asserts full consistency.
/// No mutations — just verifies the initial render is correct.
/// Any new fixture added to Tests/Fixtures/ should be added to the list.
final class FixtureSmokeTests: XCTestCase {

    static let fixtures = [
        "headings",
        "inline-formatting",
        "blockquotes",
        "code-blocks",
        "lists-unordered",
        "lists-ordered",
        "lists-mixed",
        "comprehensive",
        "edge-empty",
        "edge-long-lines",
        "edge-deep-nesting",
    ]

    func testAllFixturesRenderConsistently() throws {
        for fixture in Self.fixtures {
            let harness = RenderingCorrectnessHarness()
            try harness.loadFixture(fixture)
            harness.forceLayout()
            harness.assertAllParagraphsConsistent(context: "fixture: \(fixture)")
        }
    }

    func testComprehensiveFixtureParsesParagraphCount() throws {
        let harness = RenderingCorrectnessHarness()
        try harness.loadFixture("comprehensive")
        harness.forceLayout()

        // comprehensive.md has 56 lines (including trailing newline)
        // Verify we have a reasonable paragraph count
        XCTAssertGreaterThan(harness.paragraphCount, 40,
            "comprehensive.md should have many paragraphs")
    }

    func testCodeBlocksFixtureBlockContext() throws {
        let harness = RenderingCorrectnessHarness()
        try harness.loadFixture("code-blocks")
        harness.forceLayout()

        // Verify code blocks are detected correctly
        // code-blocks.md has 4 code blocks: swift, plain, javascript, python
        let blockContext = harness.paneController.layoutDelegate.blockContext
        XCTAssertEqual(blockContext.fencedCodeBlocks.count, 4,
            "code-blocks.md should have 4 fenced code blocks")
    }
}
