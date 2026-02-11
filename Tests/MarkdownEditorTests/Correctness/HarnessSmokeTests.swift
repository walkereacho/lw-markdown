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
}
