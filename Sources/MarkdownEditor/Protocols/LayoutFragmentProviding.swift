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
    /// - Returns: Custom layout fragment for rendering.
    /// - Note: Paragraph index and code block info are computed at fragment creation time
    ///   and stored as properties. Invalidation happens via fragment recreation (TextKit 2
    ///   creates new fragments when layout is invalidated).
    func createLayoutFragment(
        for paragraph: NSTextParagraph,
        range: NSTextRange?,
        tokens: [MarkdownToken]
    ) -> NSTextLayoutFragment
}
