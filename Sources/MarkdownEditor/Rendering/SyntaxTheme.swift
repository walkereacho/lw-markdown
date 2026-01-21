import AppKit

/// Theme defining visual appearance for Markdown elements.
/// Pure data — no rendering logic. Easily swappable for light/dark mode.
struct SyntaxTheme {
    let bodyFont: NSFont
    let headingFonts: [Int: NSFont]
    let boldFont: NSFont
    let italicFont: NSFont
    let boldItalicFont: NSFont
    let codeFont: NSFont

    let bodyColor: NSColor
    let headingColor: NSColor
    let linkColor: NSColor
    let codeBackgroundColor: NSColor
    let syntaxCharacterColor: NSColor
    let blockquoteColor: NSColor

    /// Highlight.js theme name for light mode (used for syntax highlighting in code blocks).
    let highlightThemeLight: String

    /// Highlight.js theme name for dark mode (used for syntax highlighting in code blocks).
    let highlightThemeDark: String

    // MARK: - Highlight.js Theme Selection

    /// Returns the appropriate highlight.js theme name for the current system appearance.
    var highlightTheme: String {
        let appearance = NSApp.effectiveAppearance
        let isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDarkMode ? highlightThemeDark : highlightThemeLight
    }

    // MARK: - Attribute Dictionaries

    var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: bodyColor]
    }

    var boldAttributes: [NSAttributedString.Key: Any] {
        [.font: boldFont, .foregroundColor: bodyColor]
    }

    var italicAttributes: [NSAttributedString.Key: Any] {
        [.font: italicFont, .foregroundColor: bodyColor]
    }

    var boldItalicAttributes: [NSAttributedString.Key: Any] {
        [.font: boldItalicFont, .foregroundColor: bodyColor]
    }

    var inlineCodeAttributes: [NSAttributedString.Key: Any] {
        // Note: backgroundColor is drawn manually for full line height
        [
            .font: codeFont,
            .foregroundColor: bodyColor
        ]
    }

    var codeBlockAttributes: [NSAttributedString.Key: Any] {
        [.font: codeFont, .foregroundColor: bodyColor]
    }

    var linkAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    var blockquoteAttributes: [NSAttributedString.Key: Any] {
        [.font: italicFont, .foregroundColor: blockquoteColor]
    }

    var syntaxCharacterAttributes: [NSAttributedString.Key: Any] {
        [.font: codeFont, .foregroundColor: syntaxCharacterColor]
    }

    func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        [.font: headingFonts[level] ?? bodyFont, .foregroundColor: headingColor]
    }

    // MARK: - Font Resolution

    /// Resolve font for inline element content (bold, italic, code, etc.).
    /// Returns nil for non-inline elements (headings, blockquotes, lists).
    func fontForInlineElement(_ element: MarkdownElement) -> NSFont? {
        switch element {
        case .bold:
            return boldFont
        case .italic:
            return italicFont
        case .boldItalic:
            return boldItalicFont
        case .inlineCode:
            return codeFont
        case .link:
            return bodyFont  // Links use body font, just different color
        default:
            return nil  // Non-inline elements
        }
    }

    /// Apply inline formatting fonts to text storage for cursor accuracy.
    /// This ensures TextKit 2's layout calculation matches our rendering.
    ///
    /// - Parameters:
    ///   - textStorage: The text storage to modify
    ///   - tokens: Parsed tokens for the paragraph
    ///   - paragraphOffset: Character offset of paragraph start in storage
    func applyInlineFormattingFonts(
        to textStorage: NSTextStorage,
        tokens: [MarkdownToken],
        paragraphOffset: Int
    ) {
        for token in tokens {
            guard let font = fontForInlineElement(token.element) else { continue }

            let start = paragraphOffset + token.contentRange.lowerBound
            let length = token.contentRange.count

            guard start >= 0, start + length <= textStorage.length else { continue }

            textStorage.addAttribute(.font, value: font, range: NSRange(location: start, length: length))
        }
    }

    // MARK: - Default Theme

    static let `default`: SyntaxTheme = {
        let baseSize: CGFloat = 14

        // Create italic font
        let italicFont = NSFontManager.shared.convert(
            .systemFont(ofSize: baseSize),
            toHaveTrait: .italicFontMask
        )

        // Create bold-italic font
        let boldItalicFont = NSFontManager.shared.font(
            withFamily: NSFont.systemFont(ofSize: baseSize).familyName ?? "System",
            traits: [.boldFontMask, .italicFontMask],
            weight: 0,
            size: baseSize
        ) ?? .boldSystemFont(ofSize: baseSize)

        return SyntaxTheme(
            bodyFont: .systemFont(ofSize: baseSize),
            headingFonts: [
                1: .systemFont(ofSize: 28, weight: .bold),
                2: .systemFont(ofSize: 22, weight: .bold),
                3: .systemFont(ofSize: 18, weight: .semibold),
                4: .systemFont(ofSize: 16, weight: .semibold),
                5: .systemFont(ofSize: 14, weight: .semibold),
                6: .systemFont(ofSize: 14, weight: .medium)
            ],
            boldFont: .boldSystemFont(ofSize: baseSize),
            italicFont: italicFont,
            boldItalicFont: boldItalicFont,
            codeFont: .monospacedSystemFont(ofSize: baseSize - 1, weight: .regular),
            bodyColor: .textColor,
            headingColor: .textColor,
            linkColor: .linkColor,
            codeBackgroundColor: NSColor.gray.withAlphaComponent(0.2),
            syntaxCharacterColor: .tertiaryLabelColor,
            blockquoteColor: .secondaryLabelColor,
            highlightThemeLight: "atom-one-light",
            highlightThemeDark: "atom-one-dark"
        )
    }()
}
