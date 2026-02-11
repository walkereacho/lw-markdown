import XCTest
@testable import MarkdownEditor

final class HarnessSmokeTests: XCTestCase {

    func testHarnessInitializesWithEmptyDocument() {
        let harness = RenderingCorrectnessHarness()
        XCTAssertNotNil(harness.textView)
        XCTAssertNotNil(harness.documentModel)
        XCTAssertNotNil(harness.paneController)
    }

    func testSetTextPopulatesDocument() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Hello\nWorld\n")
        harness.forceLayout()

        XCTAssertEqual(harness.textStorage.string, "# Hello\nWorld\n")
        XCTAssertGreaterThan(harness.paragraphCount, 0)
    }

    func testForceLayoutCreatesFragments() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Heading\n\nBody text\n")
        harness.forceLayout()

        // Verify fragments were created by checking layout manager has content
        var fragmentCount = 0
        harness.paneController.layoutManager.enumerateTextLayoutFragments(
            from: harness.paneController.layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            fragmentCount += 1
            return true
        }
        XCTAssertGreaterThan(fragmentCount, 0, "TextKit 2 should create layout fragments")
    }

    func testLoadFixture() throws {
        let harness = RenderingCorrectnessHarness()
        try harness.loadFixture("headings")
        harness.forceLayout()

        XCTAssertTrue(harness.textStorage.string.contains("# Heading 1"))
        XCTAssertGreaterThan(harness.paragraphCount, 0)
    }

    // MARK: - Layer 1: BlockContext Assertions

    func testBlockContextAssertionsWithCodeBlocks() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# Title\n```swift\nlet x = 1\n```\nBody\n")
        harness.forceLayout()

        // paragraph 0: "# Title" — normal
        harness.assertBlockContext(paragraph: 0, isCodeBlock: false)
        // paragraph 1: "```swift" — opening fence
        harness.assertBlockContext(paragraph: 1, isCodeBlock: false, isFence: true)
        // paragraph 2: "let x = 1" — code block content
        harness.assertBlockContext(paragraph: 2, isCodeBlock: true)
        // paragraph 3: "```" — closing fence
        harness.assertBlockContext(paragraph: 3, isCodeBlock: false, isFence: true)
        // paragraph 4: "Body" — normal
        harness.assertBlockContext(paragraph: 4, isCodeBlock: false)
    }

    func testBlockContextConsistency() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("```\ncode\n```\ntext\n")
        harness.forceLayout()

        for i in 0..<harness.paragraphCount {
            harness.assertBlockContextConsistent(paragraph: i)
        }
    }

    // MARK: - Layer 2: Font-Storage Consistency

    func testStorageFontConsistencyForHeadings() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("# H1\n## H2\n### H3\nBody\n")
        harness.forceLayout()

        harness.assertStorageFontConsistent(paragraph: 0)  // H1
        harness.assertStorageFontConsistent(paragraph: 1)  // H2
        harness.assertStorageFontConsistent(paragraph: 2)  // H3
        harness.assertStorageFontConsistent(paragraph: 3)  // Body
    }

    func testStorageFontConsistencyForCodeBlocks() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("Text\n```\ncode line\n```\nMore text\n")
        harness.forceLayout()

        for i in 0..<harness.paragraphCount {
            harness.assertStorageFontConsistent(paragraph: i)
        }
    }

    func testInlineFontConsistency() {
        let harness = RenderingCorrectnessHarness()
        harness.setText("This has **bold** and `code` inline.\n")
        harness.forceLayout()

        harness.assertInlineFontsConsistent(paragraph: 0)
    }
}
