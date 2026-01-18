import AppKit

/// Delegate that provides custom layout fragments for Markdown rendering.
///
/// ## Role in TextKit 2
/// When TextKit 2 needs to layout a paragraph, it asks its delegate for a layout fragment.
/// We return `MarkdownLayoutFragment` instead of the default, enabling custom rendering.
///
/// ## Integration
/// - Owned by `PaneController` (one per pane)
/// - Has weak reference back to pane for active paragraph state
/// - Uses token provider to get parsed Markdown
final class MarkdownLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {

    /// Reference to owning pane (for active paragraph state).
    weak var paneController: PaneController?

    /// Token provider for parsing Markdown.
    var tokenProvider: TokenProviding = StubTokenProvider()

    /// Theme for rendering.
    var theme: SyntaxTheme = .default

    /// Scanner for multi-paragraph constructs (fenced code blocks).
    private let blockContextScanner = BlockContextScanner()

    /// Current block context (updated on document change).
    private(set) var blockContext = BlockContext()

    /// Update block context by scanning all paragraphs.
    func updateBlockContext(paragraphs: [String]) {
        blockContext = blockContextScanner.scan(paragraphs: paragraphs)
    }

    // MARK: - NSTextLayoutManagerDelegate

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {

        guard let paragraph = textElement as? NSTextParagraph,
              let pane = paneController,
              let document = pane.document else {
            // Fallback to default fragment
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        // Get paragraph index
        guard let paragraphIndex = document.paragraphIndex(for: location) else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        // Parse tokens for this paragraph
        // Note: NSTextParagraph includes trailing newline; strip it for parsing
        let rawText = paragraph.attributedString.string
        let text = rawText.trimmingCharacters(in: .newlines)

        // Check if this paragraph is part of a fenced code block
        let (isInsideCodeBlock, language) = blockContext.isInsideFencedCodeBlock(paragraphIndex: paragraphIndex)
        let isFenceLine = blockContext.isFenceBoundary(paragraphIndex: paragraphIndex)

        // Determine code block info for this paragraph
        var codeBlockInfo: MarkdownLayoutFragment.CodeBlockInfo? = nil
        if isInsideCodeBlock {
            codeBlockInfo = .content(language: language)
        } else if isFenceLine {
            // Extract language from opening fence if this is one
            let fenceLanguage = extractFenceLanguage(from: text)
            codeBlockInfo = .fence(language: fenceLanguage)
        }

        let tokens = tokenProvider.parse(text)

        // Return custom fragment (checks active state at draw time, not creation time)
        return MarkdownLayoutFragment(
            textElement: paragraph,
            range: paragraph.elementRange,
            tokens: tokens,
            paragraphIndex: paragraphIndex,
            paneController: pane,
            theme: theme,
            codeBlockInfo: codeBlockInfo
        )
    }

    // MARK: - Private Helpers

    /// Extract language hint from a fence line (e.g., "```swift" -> "swift").
    private func extractFenceLanguage(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }
        let afterFence = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return afterFence.isEmpty ? nil : afterFence
    }
}
