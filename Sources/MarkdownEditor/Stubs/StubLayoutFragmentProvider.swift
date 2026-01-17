import AppKit

/// Stub layout fragment provider that returns default fragments.
/// Replace with real Core Rendering module implementation.
final class StubLayoutFragmentProvider: LayoutFragmentProviding {
    func createLayoutFragment(
        for paragraph: NSTextParagraph,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        isActive: Bool
    ) -> NSTextLayoutFragment {
        // Stub: return default TextKit 2 fragment
        // Real rendering module will return MarkdownLayoutFragment
        return NSTextLayoutFragment(textElement: paragraph, range: range)
    }
}
