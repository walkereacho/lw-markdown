import AppKit

/// Protocol for layout fragment providers (implemented by Core Rendering module).
///
/// The rendering module creates custom `NSTextLayoutFragment` subclasses
/// that implement hybrid WYSIWYG:
/// - Active paragraph: show raw Markdown (syntax visible)
/// - Inactive paragraphs: show formatted text (syntax hidden)
protocol LayoutFragmentProviding {
    /// Create a layout fragment for a paragraph.
    /// - Parameters:
    ///   - paragraph: The text paragraph element.
    ///   - range: The text range of the paragraph.
    ///   - tokens: Parsed Markdown tokens for this paragraph.
    ///   - paragraphIndex: Index of this paragraph for active state lookup.
    /// - Returns: Custom layout fragment for rendering.
    func createLayoutFragment(
        for paragraph: NSTextParagraph,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        paragraphIndex: Int
    ) -> NSTextLayoutFragment
}
