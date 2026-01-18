import AppKit

/// Implementation of LayoutFragmentProviding using MarkdownLayoutFragment.
final class MarkdownLayoutFragmentProvider: LayoutFragmentProviding {

    var theme: SyntaxTheme = .default
    weak var paneController: PaneController?

    func createLayoutFragment(
        for paragraph: NSTextParagraph,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        paragraphIndex: Int
    ) -> NSTextLayoutFragment {
        return MarkdownLayoutFragment(
            textElement: paragraph,
            range: range,
            tokens: tokens,
            paragraphIndex: paragraphIndex,
            paneController: paneController,
            theme: theme
        )
    }
}
