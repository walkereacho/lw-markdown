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
        let tokens = tokenProvider.parse(text)

        // Return custom fragment (checks active state at draw time, not creation time)
        return MarkdownLayoutFragment(
            textElement: paragraph,
            range: paragraph.elementRange,
            tokens: tokens,
            paragraphIndex: paragraphIndex,
            paneController: pane,
            theme: theme
        )
    }
}
