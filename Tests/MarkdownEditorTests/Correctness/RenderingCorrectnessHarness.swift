import XCTest
@testable import MarkdownEditor

/// Full-stack TextKit 2 test harness for rendering correctness.
/// Wires up real DocumentModel + PaneController with an offscreen NSTextView.
/// All assertions inspect real production state — no mocks.
final class RenderingCorrectnessHarness {

    let documentModel: DocumentModel
    let paneController: PaneController
    let theme = SyntaxTheme.default
    let parser = MarkdownParser.shared

    /// Text view (offscreen — never displayed, but TextKit 2 runs the full layout pipeline).
    var textView: NSTextView { paneController.textView }

    /// Text storage shortcut.
    var textStorage: NSTextStorage { documentModel.textStorage }

    // MARK: - Initialization

    /// Create harness with empty document.
    init() {
        documentModel = DocumentModel()
        paneController = PaneController(
            document: documentModel,
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
    }

    /// Load a test fixture by name (without extension).
    /// Looks in Tests/Fixtures/<name>.md
    func loadFixture(_ name: String, file: StaticString = #file, line: UInt = #line) throws {
        let testDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Correctness/
            .deletingLastPathComponent()  // MarkdownEditorTests/
        let fixturesDir = testDir
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
        let url = fixturesDir.appendingPathComponent("\(name).md")
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Fixture not found: \(url.path)", file: file, line: line)
            return
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        setText(content)
    }

    /// Set document content directly.
    func setText(_ markdown: String) {
        textStorage.beginEditing()
        textStorage.replaceCharacters(
            in: NSRange(location: 0, length: textStorage.length),
            with: markdown
        )
        textStorage.endEditing()
        // Rebuild paragraph cache after full replacement
        documentModel.paragraphCache.rebuildFull()
        // Update block context
        let paragraphs = textStorage.string.components(separatedBy: "\n")
        paneController.layoutDelegate.updateBlockContext(paragraphs: paragraphs)
        // Apply fonts to all paragraphs (matches PaneController.initializeAfterContentLoad)
        forceLayout()
    }

    // MARK: - Mutations

    /// Insert text at a specific paragraph and character offset within that paragraph.
    func insertText(_ text: String, atParagraph paragraphIndex: Int, offset: Int) {
        let storageOffset = storageOffset(forParagraph: paragraphIndex, charOffset: offset)
        textView.setSelectedRange(NSRange(location: storageOffset, length: 0))
        textView.insertText(text, replacementRange: NSRange(location: storageOffset, length: 0))
    }

    /// Delete an entire paragraph (including its trailing newline if present).
    func deleteParagraph(_ paragraphIndex: Int) {
        let text = textStorage.string
        let paragraphs = text.components(separatedBy: "\n")
        guard paragraphIndex < paragraphs.count else { return }

        var offset = 0
        for i in 0..<paragraphIndex {
            offset += paragraphs[i].count + 1  // +1 for newline
        }
        var length = paragraphs[paragraphIndex].count
        // Include trailing newline if not last paragraph
        if offset + length < text.count {
            length += 1
        }
        textView.setSelectedRange(NSRange(location: offset, length: length))
        textView.delete(nil)
    }

    /// Replace text within a paragraph.
    func replaceText(inParagraph paragraphIndex: Int, range: Range<Int>, with replacement: String) {
        let baseOffset = storageOffset(forParagraph: paragraphIndex, charOffset: range.lowerBound)
        let nsRange = NSRange(location: baseOffset, length: range.count)
        textView.setSelectedRange(nsRange)
        textView.insertText(replacement, replacementRange: nsRange)
    }

    /// Move cursor to a specific paragraph and offset.
    func moveCursor(toParagraph paragraphIndex: Int, offset: Int = 0) {
        let storagePos = storageOffset(forParagraph: paragraphIndex, charOffset: offset)
        textView.setSelectedRange(NSRange(location: storagePos, length: 0))
        // Trigger selection change handling synchronously
        paneController.handleSelectionChange()
        // Process the debounced timer immediately
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    /// Force TextKit 2 to lay out all content so fragments exist for assertions.
    func forceLayout() {
        paneController.layoutManager.ensureLayout(
            for: paneController.layoutManager.documentRange
        )
    }

    // MARK: - Paragraph Introspection

    /// Number of paragraphs in the document.
    var paragraphCount: Int {
        documentModel.paragraphCount
    }

    /// Get the text of a specific paragraph (without trailing newline).
    func paragraphText(at index: Int) -> String? {
        let text = textStorage.string
        let paragraphs = text.components(separatedBy: "\n")
        guard index < paragraphs.count else { return nil }
        return paragraphs[index]
    }

    /// Get the NSRange in storage for a specific paragraph.
    func paragraphNSRange(at index: Int) -> NSRange? {
        let text = textStorage.string
        let paragraphs = text.components(separatedBy: "\n")
        guard index < paragraphs.count else { return nil }

        var offset = 0
        for i in 0..<index {
            offset += paragraphs[i].count + 1
        }
        return NSRange(location: offset, length: paragraphs[index].count)
    }

    // MARK: - Private Helpers

    /// Convert paragraph index + char offset to absolute storage offset.
    private func storageOffset(forParagraph paragraphIndex: Int, charOffset: Int) -> Int {
        let text = textStorage.string
        let paragraphs = text.components(separatedBy: "\n")
        var offset = 0
        for i in 0..<min(paragraphIndex, paragraphs.count) {
            offset += paragraphs[i].count + 1
        }
        return offset + charOffset
    }
}
