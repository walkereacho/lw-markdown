import AppKit

/// Implementation of LayoutFragmentProviding using MarkdownLayoutFragment.
final class MarkdownLayoutFragmentProvider: LayoutFragmentProviding {

    var theme: SyntaxTheme = .default

    func createLayoutFragment(
        for paragraph: NSTextParagraph,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        isActive: Bool
    ) -> NSTextLayoutFragment {
        return MarkdownLayoutFragment(
            textElement: paragraph,
            range: range,
            tokens: tokens,
            isActiveParagraph: isActive,
            theme: theme
        )
    }
}
