import AppKit
import CoreText

/// Custom layout fragment that implements hybrid WYSIWYG rendering.
///
/// ## How It Works
/// - Active paragraph (cursor present): draws raw Markdown with syntax visible
/// - Inactive paragraph: draws formatted text with syntax hidden
///
/// ## Critical Architecture Rules
/// - NEVER modify NSTextContentStorage
/// - All rendering is visual-only via draw()
/// - isActiveParagraph is PANE-LOCAL (different panes can have different active paragraphs)
final class MarkdownLayoutFragment: NSTextLayoutFragment {

    /// Information about code block context for this paragraph.
    enum CodeBlockInfo {
        /// This paragraph is the opening or closing fence line.
        case fence(language: String?)
        /// This paragraph is inside a fenced code block (between fences).
        case content(language: String?)
    }

    /// Parsed Markdown tokens for this paragraph.
    let tokens: [MarkdownToken]

    /// Paragraph index for checking active state at draw time.
    let paragraphIndex: Int

    /// Reference to pane controller for checking active state.
    weak var paneController: PaneController?

    /// Theme for visual styling.
    let theme: SyntaxTheme

    /// Code block information (nil if not part of a fenced code block).
    let codeBlockInfo: CodeBlockInfo?

    /// Check if this paragraph is currently active (at draw time, not creation time).
    private var isActiveParagraph: Bool {
        paneController?.isActiveParagraph(at: paragraphIndex) ?? false
    }

    // MARK: - Initialization

    init(
        textElement: NSTextElement,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        paragraphIndex: Int,
        paneController: PaneController?,
        theme: SyntaxTheme,
        codeBlockInfo: CodeBlockInfo? = nil
    ) {
        self.tokens = tokens
        self.paragraphIndex = paragraphIndex
        self.paneController = paneController
        self.theme = theme
        self.codeBlockInfo = codeBlockInfo
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Layout Bounds

    /// Override to provide bounds that accommodate larger fonts (headings), full-width horizontal rules, and code block backgrounds.
    override var renderingSurfaceBounds: CGRect {
        let baseBounds = super.renderingSurfaceBounds

        // Find the maximum line height needed based on tokens
        var maxHeight: CGFloat = baseBounds.height
        var needsFullWidth = false

        for token in tokens {
            if case .heading(let level) = token.element {
                let font = theme.headingFonts[level] ?? theme.bodyFont
                let lineHeight = font.ascender - font.descender + font.leading
                maxHeight = max(maxHeight, lineHeight + 8)  // Add padding
            }
            if case .horizontalRule = token.element {
                needsFullWidth = true
                // Ensure minimum height for horizontal rule
                maxHeight = max(maxHeight, theme.bodyFont.pointSize + 8)
            }
        }

        // Code blocks need full width for background
        if codeBlockInfo != nil {
            needsFullWidth = true
        }

        // Get the content width for horizontal rules and code blocks
        var width = baseBounds.width
        if needsFullWidth {
            if let layoutManager = textLayoutManager,
               let textContainer = layoutManager.textContainer {
                width = textContainer.size.width - 40  // Account for insets
            } else {
                width = max(width, 800)  // Fallback
            }
        }

        // Return expanded bounds if needed
        if maxHeight > baseBounds.height || width > baseBounds.width {
            return CGRect(
                x: baseBounds.origin.x,
                y: baseBounds.origin.y,
                width: width,
                height: maxHeight
            )
        }

        return baseBounds
    }

    // MARK: - Drawing

    override func draw(at point: CGPoint, in context: CGContext) {
        guard let paragraph = textElement as? NSTextParagraph else {
            super.draw(at: point, in: context)
            return
        }

        let text = paragraph.attributedString.string

        // Check if this is part of a fenced code block
        if let codeInfo = codeBlockInfo {
            switch codeInfo {
            case .fence(let language):
                if isActiveParagraph {
                    drawActiveFenceLine(text: text, language: language, at: point, in: context)
                } else {
                    drawInactiveFenceLine(text: text, language: language, at: point, in: context)
                }
                return
            case .content(let language):
                drawCodeBlockContent(text: text, language: language, at: point, in: context)
                return
            }
        }

        // Check if this is a horizontal rule
        let hrToken = tokens.first {
            if case .horizontalRule = $0.element { return true }
            return false
        }

        if let token = hrToken {
            if isActiveParagraph {
                drawActiveHorizontalRule(text: text, token: token, at: point, in: context)
            } else {
                drawInactiveHorizontalRule(at: point, in: context)
            }
            return
        }

        // Check if this is a heading
        let headingToken = tokens.first {
            if case .heading = $0.element { return true }
            return false
        }

        if let token = headingToken, case .heading(let level) = token.element {
            if isActiveParagraph {
                // Active: draw with syntax visible (muted color)
                drawActiveHeading(text: text, level: level, token: token, at: point, in: context)
            } else {
                // Inactive: draw without syntax (content only)
                drawInactiveHeading(text: text, level: level, token: token, at: point, in: context)
            }
            return
        }

        // Check if this is a blockquote
        let blockquoteToken = tokens.first {
            if case .blockquote = $0.element { return true }
            return false
        }

        if let token = blockquoteToken {
            if isActiveParagraph {
                drawActiveBlockquote(text: text, token: token, at: point, in: context)
            } else {
                drawInactiveBlockquote(text: text, token: token, at: point, in: context)
            }
            return
        }

        // Non-heading/non-blockquote: use existing logic
        if isActiveParagraph {
            drawRawMarkdown(text: text, at: point, in: context)
        } else {
            drawFormattedMarkdown(text: text, at: point, in: context)
        }
    }

    // MARK: - Heading Drawing

    /// Draw active heading with syntax visible but muted.
    /// Storage has heading font, so TextKit 2 calculates correct metrics.
    private func drawActiveHeading(text: String, level: Int, token: MarkdownToken, at point: CGPoint, in context: CGContext) {
        // Use existing drawRawMarkdown which handles muted syntax colors correctly
        drawRawMarkdown(text: text, at: point, in: context)
    }

    /// Draw inactive heading with syntax hidden.
    /// Draws only the content portion at the original point.
    private func drawInactiveHeading(text: String, level: Int, token: MarkdownToken, at point: CGPoint, in context: CGContext) {
        // Draw content only (without the "# " prefix)
        let contentText = String(text.dropFirst(token.contentRange.lowerBound))
        let attrString = NSAttributedString(string: contentText, attributes: theme.headingAttributes(level: level))
        drawAttributedString(attrString, at: point, in: context)
    }

    // MARK: - Blockquote Drawing

    /// Draw active blockquote with syntax visible but muted.
    /// Shows the '>' prefix characters in muted color.
    private func drawActiveBlockquote(text: String, token: MarkdownToken, at point: CGPoint, in context: CGContext) {
        // Draw the entire line with body styling
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: theme.blockquoteAttributes
        )

        // Apply muted color to syntax characters (the ">" prefix)
        for syntaxRange in token.syntaxRanges {
            guard syntaxRange.upperBound <= text.count else { continue }
            let nsRange = NSRange(location: syntaxRange.lowerBound, length: syntaxRange.count)
            attributedString.addAttributes(theme.syntaxCharacterAttributes, range: nsRange)
        }

        drawAttributedString(attributedString, at: point, in: context)
    }

    /// Draw inactive blockquote with vertical bar indicator.
    /// Hides the '>' syntax and draws a vertical bar on the left.
    /// Handles inline formatting within the blockquote content.
    private func drawInactiveBlockquote(text: String, token: MarkdownToken, at point: CGPoint, in context: CGContext) {
        let depth = token.nestingDepth
        let contentStart = token.contentRange.lowerBound

        // Configuration for vertical bars
        let barWidth: CGFloat = 3.0
        let barSpacing: CGFloat = 12.0  // Space between bars for nested quotes
        let contentIndent: CGFloat = 8.0  // Space between last bar and content
        let totalIndent = CGFloat(depth) * barSpacing + contentIndent

        // Get line height for proper bar height
        let font = theme.blockquoteAttributes[.font] as? NSFont ?? theme.bodyFont
        let lineHeight = font.ascender - font.descender + font.leading

        // Draw vertical bars for each nesting level
        context.saveGState()
        context.setFillColor(theme.blockquoteColor.cgColor)

        for level in 0..<depth {
            let barX = point.x + CGFloat(level) * barSpacing
            let barRect = CGRect(
                x: barX,
                y: point.y,
                width: barWidth,
                height: lineHeight
            )
            context.fill(barRect)
        }
        context.restoreGState()

        // Get content text (without the ">" prefix)
        let contentText = String(text.dropFirst(contentStart))

        // Filter inline tokens that fall within the content range and adjust their ranges
        let inlineTokens = tokens.filter { t in
            if case .blockquote = t.element { return false }
            return t.contentRange.lowerBound >= contentStart
        }

        // If no inline tokens, draw plain text with blockquote styling
        if inlineTokens.isEmpty {
            let attrString = NSAttributedString(string: contentText, attributes: theme.blockquoteAttributes)
            let indentedPoint = CGPoint(x: point.x + totalIndent, y: point.y)
            drawAttributedString(attrString, at: indentedPoint, in: context)
            return
        }

        // Build drawing runs for content with inline formatting
        var runs: [DrawingRun] = []
        var currentX: CGFloat = 0
        var processedEnd = contentStart  // Track position in original text

        // Sort tokens by content start position
        let sortedTokens = inlineTokens.sorted { $0.contentRange.lowerBound < $1.contentRange.lowerBound }

        for inlineToken in sortedTokens {
            // Find the earliest syntax range before content
            let syntaxBefore = inlineToken.syntaxRanges.filter { $0.upperBound <= inlineToken.contentRange.lowerBound }
            let syntaxStart = syntaxBefore.map(\.lowerBound).min() ?? inlineToken.contentRange.lowerBound

            // Draw any plain text between last processed position and this token's syntax start
            if processedEnd < syntaxStart {
                let plainText = substring(of: text, from: processedEnd, to: syntaxStart)
                if !plainText.isEmpty {
                    runs.append(DrawingRun(
                        text: plainText,
                        attributes: theme.blockquoteAttributes,
                        xOffset: currentX
                    ))
                    currentX += measureWidth(plainText, attributes: theme.blockquoteAttributes)
                }
            }

            // Draw content with appropriate styling (merge with blockquote base style)
            let tokenContentText = substring(of: text, from: inlineToken.contentRange.lowerBound, to: inlineToken.contentRange.upperBound)
            if !tokenContentText.isEmpty {
                var attrs = attributesForElement(inlineToken.element)
                // Apply blockquote color to inline elements
                if let _ = attrs[.foregroundColor] {
                    attrs[.foregroundColor] = theme.blockquoteColor
                }
                runs.append(DrawingRun(
                    text: tokenContentText,
                    attributes: attrs,
                    xOffset: currentX
                ))
                currentX += measureWidth(tokenContentText, attributes: attrs)
            }

            // Track where we've processed to (including trailing syntax)
            let syntaxAfter = inlineToken.syntaxRanges.filter { $0.lowerBound >= inlineToken.contentRange.upperBound }
            let endOfToken = syntaxAfter.map(\.upperBound).max() ?? inlineToken.contentRange.upperBound
            processedEnd = max(processedEnd, endOfToken)
        }

        // Draw any remaining text after last token
        if processedEnd < text.count {
            let remainingText = substring(of: text, from: processedEnd, to: text.count)
            if !remainingText.isEmpty {
                runs.append(DrawingRun(
                    text: remainingText,
                    attributes: theme.blockquoteAttributes,
                    xOffset: currentX
                ))
            }
        }

        // Execute drawing at indented position
        let indentedPoint = CGPoint(x: point.x + totalIndent, y: point.y)
        for run in runs {
            let runPoint = CGPoint(x: indentedPoint.x + run.xOffset, y: indentedPoint.y)
            let attrString = NSAttributedString(string: run.text, attributes: run.attributes)
            drawAttributedString(attrString, at: runPoint, in: context)
        }
    }

    // MARK: - Horizontal Rule Drawing

    /// Draw active horizontal rule with syntax visible but muted.
    /// Shows the ---, ***, ___, or spaced variants in muted color.
    private func drawActiveHorizontalRule(text: String, token: MarkdownToken, at point: CGPoint, in context: CGContext) {
        // Show syntax characters in muted color
        let attrString = NSAttributedString(string: text, attributes: theme.syntaxCharacterAttributes)
        drawAttributedString(attrString, at: point, in: context)
    }

    /// Draw inactive horizontal rule as a visual line.
    /// Draws a thin horizontal line spanning most of the content width.
    private func drawInactiveHorizontalRule(at point: CGPoint, in context: CGContext) {
        let bounds = renderingSurfaceBounds

        // Line configuration
        let lineThickness: CGFloat = 1.0
        let verticalCenter = point.y + bounds.height / 2

        // Draw the horizontal line using the full width from renderingSurfaceBounds
        context.saveGState()
        context.setStrokeColor(theme.syntaxCharacterColor.cgColor)
        context.setLineWidth(lineThickness)

        // Line spans the full content width (bounds already expanded in renderingSurfaceBounds)
        let lineStartX = point.x
        let lineEndX = point.x + bounds.width

        context.move(to: CGPoint(x: lineStartX, y: verticalCenter))
        context.addLine(to: CGPoint(x: lineEndX, y: verticalCenter))
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Code Block Drawing

    /// Draw fence line when active (cursor present).
    /// Shows ``` or ~~~ with language hint in muted color.
    private func drawActiveFenceLine(text: String, language: String?, at point: CGPoint, in context: CGContext) {
        // Draw background first
        drawCodeBlockBackground(at: point, in: context)

        // Draw the fence syntax in muted color with monospace font
        let attrString = NSAttributedString(string: text, attributes: theme.syntaxCharacterAttributes)
        drawAttributedString(attrString, at: point, in: context)
    }

    /// Draw fence line when inactive (cursor not present).
    /// Hides the fence syntax entirely - shows nothing or just the language label.
    private func drawInactiveFenceLine(text: String, language: String?, at point: CGPoint, in context: CGContext) {
        // Draw background
        drawCodeBlockBackground(at: point, in: context)

        // For inactive fence lines, we hide the ``` syntax entirely
        // Optionally show language label if this is opening fence
        if let lang = language, !lang.isEmpty {
            // Show language label in small muted text at top-right (like Obsidian)
            var labelAttrs = theme.syntaxCharacterAttributes
            labelAttrs[.font] = NSFont.systemFont(ofSize: 10, weight: .medium)
            let labelString = NSAttributedString(string: lang, attributes: labelAttrs)

            // Position label at the right side
            let labelWidth = measureWidth(lang, attributes: labelAttrs)
            let bounds = renderingSurfaceBounds
            let labelPoint = CGPoint(x: point.x + bounds.width - labelWidth - 8, y: point.y)
            drawAttributedString(labelString, at: labelPoint, in: context)
        }
        // If no language or closing fence, draw nothing (just background)
    }

    /// Draw code block content (lines between fences).
    /// Uses monospace font with background, regardless of active state.
    private func drawCodeBlockContent(text: String, language: String?, at point: CGPoint, in context: CGContext) {
        // Draw background first
        drawCodeBlockBackground(at: point, in: context)

        // Draw content with monospace font
        let attrString = NSAttributedString(string: text, attributes: theme.codeBlockAttributes)
        drawAttributedString(attrString, at: point, in: context)
    }

    /// Draw the code block background rectangle.
    private func drawCodeBlockBackground(at point: CGPoint, in context: CGContext) {
        let bounds = renderingSurfaceBounds

        // Get line height for proper background height
        let font = theme.codeFont
        let lineHeight = font.ascender - font.descender + font.leading

        context.saveGState()
        context.setFillColor(theme.codeBackgroundColor.cgColor)

        let bgRect = CGRect(
            x: point.x,
            y: point.y,
            width: bounds.width,
            height: max(lineHeight, bounds.height)
        )
        context.fill(bgRect)
        context.restoreGState()
    }

    // MARK: - Raw Markdown Drawing (Active Paragraph)

    /// Draw with all syntax characters visible but muted.
    /// Headings still render at heading size for visual consistency.
    private func drawRawMarkdown(text: String, at point: CGPoint, in context: CGContext) {
        // Check if this is a heading line
        let headingToken = tokens.first { token in
            if case .heading = token.element { return true }
            return false
        }

        let baseAttributes: [NSAttributedString.Key: Any]
        if let token = headingToken, case .heading(let level) = token.element {
            // Use heading font for heading lines
            baseAttributes = theme.headingAttributes(level: level)
        } else {
            baseAttributes = theme.bodyAttributes
        }

        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes
        )

        // Apply muted color to syntax characters (keeping heading font size)
        for token in tokens {
            for syntaxRange in token.syntaxRanges {
                guard syntaxRange.upperBound <= text.count else { continue }
                let nsRange = NSRange(location: syntaxRange.lowerBound, length: syntaxRange.count)
                // Merge syntax styling with current font
                var syntaxAttrs = theme.syntaxCharacterAttributes
                if let font = baseAttributes[.font] as? NSFont {
                    syntaxAttrs[.font] = font
                }
                attributedString.addAttributes(syntaxAttrs, range: nsRange)
            }
        }

        drawAttributedString(attributedString, at: point, in: context)
    }

    // MARK: - Formatted Markdown Drawing (Inactive Paragraph)

    /// Draw with syntax characters hidden and formatting applied.
    private func drawFormattedMarkdown(text: String, at point: CGPoint, in context: CGContext) {
        // If no tokens, draw as plain text
        if tokens.isEmpty {
            let attrString = NSAttributedString(string: text, attributes: theme.bodyAttributes)
            drawAttributedString(attrString, at: point, in: context)
            return
        }

        // Build drawing runs, skipping syntax characters
        var runs: [DrawingRun] = []
        var currentX: CGFloat = 0
        var processedEnd = 0

        // Sort tokens by content start position
        let sortedTokens = tokens.sorted { $0.contentRange.lowerBound < $1.contentRange.lowerBound }

        for token in sortedTokens {
            // Find the earliest syntax range before content
            let syntaxBefore = token.syntaxRanges.filter { $0.upperBound <= token.contentRange.lowerBound }
            let syntaxStart = syntaxBefore.map(\.lowerBound).min() ?? token.contentRange.lowerBound

            // Draw any text between last token and this one's syntax
            if processedEnd < syntaxStart {
                let plainText = substring(of: text, from: processedEnd, to: syntaxStart)
                if !plainText.isEmpty {
                    runs.append(DrawingRun(
                        text: plainText,
                        attributes: theme.bodyAttributes,
                        xOffset: currentX
                    ))
                    currentX += measureWidth(plainText, attributes: theme.bodyAttributes)
                }
            }

            // Draw content with appropriate styling
            let contentText = substring(of: text, from: token.contentRange.lowerBound, to: token.contentRange.upperBound)
            if !contentText.isEmpty {
                let attrs = attributesForElement(token.element)
                runs.append(DrawingRun(
                    text: contentText,
                    attributes: attrs,
                    xOffset: currentX
                ))
                currentX += measureWidth(contentText, attributes: attrs)
            }

            // Track where we've processed to (including trailing syntax)
            let syntaxAfter = token.syntaxRanges.filter { $0.lowerBound >= token.contentRange.upperBound }
            let endOfToken = syntaxAfter.map(\.upperBound).max() ?? token.contentRange.upperBound
            processedEnd = max(processedEnd, endOfToken)
        }

        // Draw any remaining text after last token
        if processedEnd < text.count {
            let remainingText = substring(of: text, from: processedEnd, to: text.count)
            if !remainingText.isEmpty {
                runs.append(DrawingRun(
                    text: remainingText,
                    attributes: theme.bodyAttributes,
                    xOffset: currentX
                ))
            }
        }

        // Execute drawing
        for run in runs {
            let runPoint = CGPoint(x: point.x + run.xOffset, y: point.y)
            let attrString = NSAttributedString(string: run.text, attributes: run.attributes)
            drawAttributedString(attrString, at: runPoint, in: context)
        }
    }

    // MARK: - Drawing Helpers

    private struct DrawingRun {
        let text: String
        let attributes: [NSAttributedString.Key: Any]
        let xOffset: CGFloat
    }

    private func drawAttributedString(_ string: NSAttributedString, at point: CGPoint, in context: CGContext) {
        let line = CTLineCreateWithAttributedString(string)

        // Get line metrics to properly position text
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        context.saveGState()
        // Core Text uses a flipped coordinate system (y increases upward)
        // NSView/CALayer uses y increasing downward
        // We need to flip and offset by ascent to draw from top-left
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: point.x, y: point.y + ascent)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func measureWidth(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func substring(of text: String, from start: Int, to end: Int) -> String {
        guard start >= 0, end <= text.count, start < end else { return "" }
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        return String(text[startIndex..<endIndex])
    }

    private func attributesForElement(_ element: MarkdownElement) -> [NSAttributedString.Key: Any] {
        switch element {
        case .heading(let level):
            return theme.headingAttributes(level: level)
        case .bold:
            return theme.boldAttributes
        case .italic:
            return theme.italicAttributes
        case .boldItalic:
            return theme.boldItalicAttributes
        case .inlineCode:
            return theme.inlineCodeAttributes
        case .link:
            return theme.linkAttributes
        case .fencedCodeBlock, .indentedCodeBlock:
            return theme.codeBlockAttributes
        case .blockquote:
            return theme.blockquoteAttributes
        case .unorderedListItem, .orderedListItem:
            return theme.bodyAttributes
        case .horizontalRule:
            return theme.bodyAttributes
        case .text:
            return theme.bodyAttributes
        }
    }
}
