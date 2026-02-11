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
        paneController.applyFontsToAllParagraphs()
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

    // MARK: - Layer 1: DocumentModel Assertions

    /// Assert paragraph count matches expected value.
    func assertParagraphCount(
        _ expected: Int,
        context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let actual = paragraphCount
        XCTAssertEqual(actual, expected,
            "Paragraph count mismatch\(context.isEmpty ? "" : " (\(context))"): expected \(expected), got \(actual)",
            file: file, line: line)
    }

    /// Assert a specific paragraph's code block status.
    func assertBlockContext(
        paragraph index: Int,
        isCodeBlock: Bool,
        isFence: Bool = false,
        context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let blockContext = paneController.layoutDelegate.blockContext
        let (isInside, _) = blockContext.isInsideFencedCodeBlock(paragraphIndex: index)
        let isOpenFence = blockContext.isOpeningFence(paragraphIndex: index).0
        let isCloseFence = blockContext.isClosingFence(paragraphIndex: index)
        let actualIsCodeBlock = isInside
        let actualIsFence = isOpenFence || isCloseFence

        let prefix = "Paragraph \(index)\(context.isEmpty ? "" : " (\(context))")"

        if isCodeBlock {
            XCTAssertTrue(actualIsCodeBlock,
                "\(prefix): expected code block content, but was not",
                file: file, line: line)
        } else if isFence {
            XCTAssertTrue(actualIsFence,
                "\(prefix): expected fence line, but was not",
                file: file, line: line)
        } else {
            XCTAssertFalse(actualIsCodeBlock || actualIsFence,
                "\(prefix): expected normal text, but was code block (inside=\(actualIsCodeBlock), fence=\(actualIsFence))",
                file: file, line: line)
        }
    }

    /// Re-derive block context from raw text and compare against stored context.
    /// Catches stale BlockContext after edits.
    func assertBlockContextConsistent(
        paragraph index: Int,
        context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let text = textStorage.string
        let paragraphs = text.components(separatedBy: "\n")
        let freshContext = BlockContextScanner().scan(paragraphs: paragraphs)
        let storedContext = paneController.layoutDelegate.blockContext

        let prefix = "Paragraph \(index)\(context.isEmpty ? "" : " (\(context))")"

        let (freshInside, _) = freshContext.isInsideFencedCodeBlock(paragraphIndex: index)
        let (storedInside, _) = storedContext.isInsideFencedCodeBlock(paragraphIndex: index)
        XCTAssertEqual(freshInside, storedInside,
            "\(prefix): BlockContext stale — fresh scan says isInside=\(freshInside), stored says \(storedInside)",
            file: file, line: line)

        let freshIsOpenFence = freshContext.isOpeningFence(paragraphIndex: index).0
        let storedIsOpenFence = storedContext.isOpeningFence(paragraphIndex: index).0
        XCTAssertEqual(freshIsOpenFence, storedIsOpenFence,
            "\(prefix): BlockContext stale — fresh scan says isOpeningFence=\(freshIsOpenFence), stored says \(storedIsOpenFence)",
            file: file, line: line)

        let freshIsCloseFence = freshContext.isClosingFence(paragraphIndex: index)
        let storedIsCloseFence = storedContext.isClosingFence(paragraphIndex: index)
        XCTAssertEqual(freshIsCloseFence, storedIsCloseFence,
            "\(prefix): BlockContext stale — fresh scan says isClosingFence=\(freshIsCloseFence), stored says \(storedIsCloseFence)",
            file: file, line: line)
    }

    // MARK: - Layer 2: Font-Storage Consistency Assertions

    /// Assert a paragraph's dominant storage font matches expected.
    func assertStorageFont(
        paragraph index: Int,
        expected: NSFont,
        context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let range = paragraphNSRange(at: index),
              range.length > 0 else {
            // Empty paragraph — skip font check
            return
        }

        let actualFont = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        let prefix = "Paragraph \(index)\(context.isEmpty ? "" : " (\(context))")"

        XCTAssertEqual(actualFont, expected,
            "\(prefix): storage font mismatch — expected \(expected.fontName) \(expected.pointSize)pt, got \(actualFont?.fontName ?? "nil") \(actualFont?.pointSize ?? 0)pt",
            file: file, line: line)
    }

    /// Derive expected font from document state and assert storage matches.
    /// This is the key invariant check — it re-derives independently from scratch.
    func assertStorageFontConsistent(
        paragraph index: Int,
        context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let text = paragraphText(at: index) else { return }
        if text.isEmpty { return }  // Skip empty paragraphs

        let blockContext = paneController.layoutDelegate.blockContext

        // 1. Code block content/fence overrides everything
        let (isInside, _) = blockContext.isInsideFencedCodeBlock(paragraphIndex: index)
        if isInside {
            assertStorageFont(paragraph: index, expected: theme.codeFont,
                context: "\(context) [code block content]", file: file, line: line)
            return
        }
        let isOpenFence = blockContext.isOpeningFence(paragraphIndex: index).0
        let isCloseFence = blockContext.isClosingFence(paragraphIndex: index)
        if isOpenFence || isCloseFence {
            assertStorageFont(paragraph: index, expected: theme.codeFont,
                context: "\(context) [fence line]", file: file, line: line)
            return
        }

        // 2. Parse tokens to determine paragraph type
        let tokens = parser.parse(text)

        for token in tokens {
            switch token.element {
            case .heading(let level):
                let expectedFont = theme.headingFonts[level] ?? theme.bodyFont
                assertStorageFont(paragraph: index, expected: expectedFont,
                    context: "\(context) [heading \(level)]", file: file, line: line)
                return
            case .blockquote:
                assertStorageFont(paragraph: index, expected: theme.italicFont,
                    context: "\(context) [blockquote]", file: file, line: line)
                return
            default:
                break
            }
        }

        // 3. Default: body font
        assertStorageFont(paragraph: index, expected: theme.bodyFont,
            context: "\(context) [body]", file: file, line: line)
    }

    /// Assert inline formatting fonts are correct within a paragraph.
    /// Checks that bold, italic, code spans have the right font in storage.
    func assertInlineFontsConsistent(
        paragraph index: Int,
        context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let text = paragraphText(at: index) else { return }
        if text.isEmpty { return }

        let blockContext = paneController.layoutDelegate.blockContext
        // Skip font checks for code blocks — they use monospace throughout
        let (isInside, _) = blockContext.isInsideFencedCodeBlock(paragraphIndex: index)
        if isInside || blockContext.isOpeningFence(paragraphIndex: index).0 ||
           blockContext.isClosingFence(paragraphIndex: index) {
            return
        }

        // Skip heading and blockquote paragraphs (they use block-level fonts)
        let tokens = parser.parse(text)
        for token in tokens {
            if case .heading = token.element { return }
            if case .blockquote = token.element { return }
        }

        guard let nsRange = paragraphNSRange(at: index) else { return }
        let paragraphOffset = nsRange.location
        let prefix = "Paragraph \(index)\(context.isEmpty ? "" : " (\(context))")"

        for token in tokens {
            guard let expectedFont = theme.fontForInlineElement(token.element) else { continue }

            let start = paragraphOffset + token.contentRange.lowerBound
            let length = token.contentRange.count
            guard start >= 0, start + length <= textStorage.length, length > 0 else { continue }

            let actualFont = textStorage.attribute(.font, at: start, effectiveRange: nil) as? NSFont

            XCTAssertEqual(actualFont, expectedFont,
                "\(prefix): inline \(token.element) font mismatch at content offset \(token.contentRange) — expected \(expectedFont.fontName), got \(actualFont?.fontName ?? "nil")",
                file: file, line: line)
        }
    }

    // MARK: - Layer 3: Fragment Rendering Assertions

    /// Get the layout fragment for a specific paragraph.
    func fragment(at paragraphIndex: Int) -> NSTextLayoutFragment? {
        guard let range = documentModel.paragraphRange(at: paragraphIndex) else { return nil }
        var result: NSTextLayoutFragment?
        paneController.layoutManager.enumerateTextLayoutFragments(
            from: range.location,
            options: [.ensuresLayout]
        ) { fragment in
            result = fragment
            return false  // Stop after first
        }
        return result
    }

    /// Assert the fragment at a paragraph index is a MarkdownLayoutFragment with expected tokens.
    func assertFragmentTokensMatchParse(
        paragraph index: Int,
        context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let text = paragraphText(at: index) else { return }
        if text.isEmpty { return }

        let prefix = "Paragraph \(index)\(context.isEmpty ? "" : " (\(context))")"

        guard let frag = fragment(at: index) else {
            XCTFail("\(prefix): no layout fragment found", file: file, line: line)
            return
        }

        guard let mdFragment = frag as? MarkdownLayoutFragment else {
            // Non-markdown fragment is acceptable for empty lines
            return
        }

        // Re-parse and compare
        let expectedTokens = parser.parse(text)

        XCTAssertEqual(mdFragment.tokens.count, expectedTokens.count,
            "\(prefix): token count mismatch — fragment has \(mdFragment.tokens.count), fresh parse has \(expectedTokens.count)",
            file: file, line: line)

        for (i, (actual, expected)) in zip(mdFragment.tokens, expectedTokens).enumerated() {
            XCTAssertEqual(actual.element, expected.element,
                "\(prefix): token[\(i)] element mismatch — fragment has \(actual.element), expected \(expected.element)",
                file: file, line: line)
            XCTAssertEqual(actual.contentRange, expected.contentRange,
                "\(prefix): token[\(i)] contentRange mismatch — fragment has \(actual.contentRange), expected \(expected.contentRange)",
                file: file, line: line)
        }
    }

    /// Assert a paragraph's active/inactive state.
    func assertFragmentIsActive(
        paragraph index: Int,
        _ expectedActive: Bool,
        context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let prefix = "Paragraph \(index)\(context.isEmpty ? "" : " (\(context))")"
        let actual = paneController.isActiveParagraph(at: index)
        XCTAssertEqual(actual, expectedActive,
            "\(prefix): expected active=\(expectedActive), got \(actual)",
            file: file, line: line)
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
