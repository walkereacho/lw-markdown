import Foundation

/// Token representing a parsed Markdown element.
/// Defined in scaffolding so all modules share the same type.
struct MarkdownToken {
    /// The type of Markdown element.
    let element: MarkdownElement

    /// Range of the content text (e.g., "bold" in "**bold**").
    /// Offset from start of paragraph.
    let contentRange: Range<Int>

    /// Ranges of syntax characters (e.g., "**" markers).
    /// Offsets from start of paragraph.
    let syntaxRanges: [Range<Int>]

    /// Nesting depth for lists and blockquotes.
    let nestingDepth: Int

    init(
        element: MarkdownElement,
        contentRange: Range<Int>,
        syntaxRanges: [Range<Int>] = [],
        nestingDepth: Int = 0
    ) {
        self.element = element
        self.contentRange = contentRange
        self.syntaxRanges = syntaxRanges
        self.nestingDepth = nestingDepth
    }
}

/// Markdown element types supported by the editor.
/// Parser module must handle all of these.
enum MarkdownElement: Equatable {
    case text
    case heading(level: Int)           // # through ######
    case bold                          // **text** or __text__
    case italic                        // *text* or _text_
    case boldItalic                    // ***text***
    case inlineCode                    // `code`
    case fencedCodeBlock(language: String?)
    case indentedCodeBlock
    case unorderedListItem             // - or * or +
    case orderedListItem(number: Int)  // 1. 2. etc
    case blockquote                    // > text
    case link(url: String)             // [text](url)
    case horizontalRule                // --- or *** or ___
}

/// Protocol for token providers (implemented by Parser module).
///
/// The parser takes paragraph text and returns tokens describing
/// the Markdown structure. Tokens include both content ranges
/// (what to display) and syntax ranges (what to hide when formatted).
protocol TokenProviding {
    /// Parse a paragraph and return its tokens.
    /// - Parameter text: The raw paragraph text.
    /// - Returns: Array of tokens describing Markdown elements.
    func parse(_ text: String) -> [MarkdownToken]
}
