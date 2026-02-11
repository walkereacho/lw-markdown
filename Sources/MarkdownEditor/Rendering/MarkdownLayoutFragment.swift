import AppKit
import CoreText
import os.signpost
import QuartzCore

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
        /// This paragraph is the opening fence line (```swift, etc.).
        /// Background should extend to connect with content below.
        case openingFence(language: String?)
        /// This paragraph is the closing fence line (```).
        /// Background should NOT extend beyond text to avoid styling next paragraph.
        case closingFence
        /// This paragraph is inside a fenced code block (between fences).
        case content(language: String?)
    }

    /// Parsed Markdown tokens for this paragraph.
    let tokens: [MarkdownToken]

    /// Reference to pane controller for checking active state.
    weak var paneController: PaneController?

    /// Theme for visual styling.
    let theme: SyntaxTheme

    /// Compute paragraph index dynamically at draw time.
    /// This ensures correct index even when paragraphs are inserted/deleted.
    /// Uses the fragment's text location to query the document's paragraph cache.
    private var currentParagraphIndex: Int? {
        guard let location = textElement?.elementRange?.location,
              let document = paneController?.document else {
            return nil
        }
        return document.paragraphIndex(for: location)
    }

    /// Check if this paragraph is currently active (at draw time, not creation time).
    private var isActiveParagraph: Bool {
        guard let index = currentParagraphIndex else { return false }
        return paneController?.isActiveParagraph(at: index) ?? false
    }

    /// Code block information queried at draw time (not creation time).
    /// This allows code block status to update when fences are added/removed.
    private var codeBlockInfo: CodeBlockInfo? {
        guard let index = currentParagraphIndex else { return nil }
        return paneController?.codeBlockInfo(at: index)
    }

    // MARK: - Initialization

    init(
        textElement: NSTextElement,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        paneController: PaneController?,
        theme: SyntaxTheme
    ) {
        self.tokens = tokens
        self.paneController = paneController
        self.theme = theme
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Layout Bounds

    /// Override to provide bounds that accommodate larger fonts (headings), full-width horizontal rules, and code block backgrounds.
    override var renderingSurfaceBounds: CGRect {
        let spid = OSSignpostID(log: Signposts.rendering)
        os_signpost(.begin, log: Signposts.rendering, name: Signposts.renderingSurfaceBounds, signpostID: spid)
        defer { os_signpost(.end, log: Signposts.rendering, name: Signposts.renderingSurfaceBounds, signpostID: spid) }

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
        // For code blocks and horizontal rules, always use calculated width for consistency
        // (empty lines would otherwise have different width than lines with text)
        if needsFullWidth || maxHeight > baseBounds.height {
            // Use consistent origin for code blocks - baseBounds.origin differs between
            // empty lines (0,0) and text lines (-3,-2), causing inconsistent clipping
            let originX = needsFullWidth ? 0.0 : baseBounds.origin.x
            let originY = needsFullWidth ? 0.0 : baseBounds.origin.y
            return CGRect(
                x: originX,
                y: originY,
                width: width,
                height: maxHeight
            )
        }

        return baseBounds
    }

    // MARK: - Drawing

    override func draw(at point: CGPoint, in context: CGContext) {
        let drawStart = CACurrentMediaTime()
        defer { PerfTimer.shared.record("draw", ms: (CACurrentMediaTime() - drawStart) * 1000) }

        let drawSpid = OSSignpostID(log: Signposts.rendering)
        let paraIndex = currentParagraphIndex ?? -1
        let active = isActiveParagraph

        guard let paragraph = textElement as? NSTextParagraph else {
            super.draw(at: point, in: context)
            return
        }

        let text = paragraph.attributedString.string

        // Check if this is part of a fenced code block
        if let codeInfo = codeBlockInfo {
            switch codeInfo {
            case .openingFence(let language):
                os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "fence-open para=%d active=%d", paraIndex, active ? 1 : 0)
                let subSpid = OSSignpostID(log: Signposts.rendering)
                os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawFenceLine, signpostID: subSpid)
                if active {
                    drawActiveFenceLine(text: text, language: language, isOpening: true, at: point, in: context)
                } else {
                    drawInactiveFenceLine(text: text, language: language, isOpening: true, at: point, in: context)
                }
                os_signpost(.end, log: Signposts.rendering, name: Signposts.drawFenceLine, signpostID: subSpid)
                os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
                return
            case .closingFence:
                os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "fence-close para=%d active=%d", paraIndex, active ? 1 : 0)
                let subSpid = OSSignpostID(log: Signposts.rendering)
                os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawFenceLine, signpostID: subSpid)
                if active {
                    drawActiveFenceLine(text: text, language: nil, isOpening: false, at: point, in: context)
                } else {
                    drawInactiveFenceLine(text: text, language: nil, isOpening: false, at: point, in: context)
                }
                os_signpost(.end, log: Signposts.rendering, name: Signposts.drawFenceLine, signpostID: subSpid)
                os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
                return
            case .content(let language):
                os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "code-content para=%d lang=%{public}s", paraIndex, language ?? "none")
                let subSpid = OSSignpostID(log: Signposts.rendering)
                os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawCodeBlockContent, signpostID: subSpid)
                drawCodeBlockContent(text: text, language: language, at: point, in: context)
                os_signpost(.end, log: Signposts.rendering, name: Signposts.drawCodeBlockContent, signpostID: subSpid)
                os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
                return
            }
        }

        // Check if this is a horizontal rule
        let hrToken = tokens.first {
            if case .horizontalRule = $0.element { return true }
            return false
        }

        if let token = hrToken {
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "hr para=%d active=%d", paraIndex, active ? 1 : 0)
            let subSpid = OSSignpostID(log: Signposts.rendering)
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawHorizontalRule, signpostID: subSpid)
            if active {
                drawActiveHorizontalRule(text: text, token: token, at: point, in: context)
            } else {
                drawInactiveHorizontalRule(at: point, in: context)
            }
            os_signpost(.end, log: Signposts.rendering, name: Signposts.drawHorizontalRule, signpostID: subSpid)
            os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
            return
        }

        // Check if this is a heading
        let headingToken = tokens.first {
            if case .heading = $0.element { return true }
            return false
        }

        if let token = headingToken, case .heading(let level) = token.element {
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "heading h%d para=%d active=%d", level, paraIndex, active ? 1 : 0)
            let subSpid = OSSignpostID(log: Signposts.rendering)
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawHeading, signpostID: subSpid)
            if active {
                drawActiveHeading(text: text, level: level, token: token, at: point, in: context)
            } else {
                drawInactiveHeading(text: text, level: level, token: token, at: point, in: context)
            }
            os_signpost(.end, log: Signposts.rendering, name: Signposts.drawHeading, signpostID: subSpid)
            os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
            return
        }

        // Check if this is a blockquote
        let blockquoteToken = tokens.first {
            if case .blockquote = $0.element { return true }
            return false
        }

        if let token = blockquoteToken {
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "blockquote para=%d active=%d", paraIndex, active ? 1 : 0)
            let subSpid = OSSignpostID(log: Signposts.rendering)
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawBlockquote, signpostID: subSpid)
            if active {
                drawActiveBlockquote(text: text, token: token, at: point, in: context)
            } else {
                drawInactiveBlockquote(text: text, token: token, at: point, in: context)
            }
            os_signpost(.end, log: Signposts.rendering, name: Signposts.drawBlockquote, signpostID: subSpid)
            os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
            return
        }

        // Check if this is an unordered list item
        let unorderedListToken = tokens.first {
            if case .unorderedListItem = $0.element { return true }
            return false
        }

        if let token = unorderedListToken {
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "ul para=%d active=%d", paraIndex, active ? 1 : 0)
            let subSpid = OSSignpostID(log: Signposts.rendering)
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawUnorderedList, signpostID: subSpid)
            if active {
                drawActiveUnorderedListItem(text: text, token: token, at: point, in: context)
            } else {
                drawInactiveUnorderedListItem(text: text, token: token, at: point, in: context)
            }
            os_signpost(.end, log: Signposts.rendering, name: Signposts.drawUnorderedList, signpostID: subSpid)
            os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
            return
        }

        // Check if this is an ordered list item
        let orderedListToken = tokens.first {
            if case .orderedListItem = $0.element { return true }
            return false
        }

        if let token = orderedListToken, case .orderedListItem(let number) = token.element {
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "ol para=%d active=%d", paraIndex, active ? 1 : 0)
            let subSpid = OSSignpostID(log: Signposts.rendering)
            os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawOrderedList, signpostID: subSpid)
            if active {
                drawActiveOrderedListItem(text: text, token: token, number: number, at: point, in: context)
            } else {
                drawInactiveOrderedListItem(text: text, token: token, number: number, at: point, in: context)
            }
            os_signpost(.end, log: Signposts.rendering, name: Signposts.drawOrderedList, signpostID: subSpid)
            os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
            return
        }

        // Non-heading/non-blockquote/non-list: draw with wrapping support
        // Use TextKit 2's line fragments for line breaks, but apply our custom formatting
        os_signpost(.begin, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid, "text para=%d active=%d", paraIndex, active ? 1 : 0)
        let subSpid = OSSignpostID(log: Signposts.rendering)
        os_signpost(.begin, log: Signposts.rendering, name: Signposts.drawWrappedText, signpostID: subSpid)
        if active {
            drawRawMarkdownWrapped(text: text, at: point, in: context)
        } else {
            drawFormattedMarkdownWrapped(text: text, at: point, in: context)
        }
        os_signpost(.end, log: Signposts.rendering, name: Signposts.drawWrappedText, signpostID: subSpid)
        os_signpost(.end, log: Signposts.rendering, name: Signposts.draw, signpostID: drawSpid)
    }

    // MARK: - Wrapped Text Drawing

    /// Draw active paragraph with formatting and visible syntax, respecting TextKit 2's line wrapping.
    private func drawRawMarkdownWrapped(text: String, at point: CGPoint, in context: CGContext) {
        // For single-line or simple cases, use existing method
        guard textLineFragments.count > 1 else {
            drawRawMarkdown(text: text, at: point, in: context)
            return
        }

        // Build the full attributed string with formatting
        let baseAttributes = theme.bodyAttributes
        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        // Apply inline formatting to content ranges
        for token in tokens {
            switch token.element {
            case .heading, .blockquote, .unorderedListItem, .orderedListItem,
                 .fencedCodeBlock, .indentedCodeBlock, .horizontalRule, .text:
                continue
            case .inlineCode:
                guard token.contentRange.upperBound <= text.count else { continue }
                let contentNSRange = NSRange(location: token.contentRange.lowerBound, length: token.contentRange.count)
                attributedString.addAttribute(.font, value: theme.codeFont, range: contentNSRange)
                continue
            default:
                break
            }
            guard token.contentRange.upperBound <= text.count else { continue }
            let contentNSRange = NSRange(location: token.contentRange.lowerBound, length: token.contentRange.count)
            let formatAttrs = attributesForElement(token.element)
            attributedString.addAttributes(formatAttrs, range: contentNSRange)
        }

        // Apply muted color to syntax characters
        for token in tokens {
            for syntaxRange in token.syntaxRanges {
                guard syntaxRange.upperBound <= text.count else { continue }
                let nsRange = NSRange(location: syntaxRange.lowerBound, length: syntaxRange.count)
                attributedString.addAttribute(.foregroundColor, value: theme.syntaxCharacterColor, range: nsRange)
            }
        }

        // Draw each line fragment at its correct position
        drawLineFragments(attributedString: attributedString, at: point, in: context)
    }

    /// Draw inactive paragraph with formatting and hidden syntax, with text wrapping.
    /// For plain text (no syntax hiding), uses TextKit 2's line fragments for consistent wrapping.
    /// For text with hidden syntax, recalculates line breaks since display text differs from source.
    private func drawFormattedMarkdownWrapped(text: String, at point: CGPoint, in context: CGContext) {
        // Build the display string with syntax hidden and formatting applied
        let (displayString, _) = buildFormattedDisplayString(text: text)

        // Check if display text length matches source - if so, use TextKit 2's line fragments
        // for consistent line breaks with active mode
        if displayString.length == text.count {
            // No syntax was hidden - use same line fragments as active mode
            drawLineFragments(attributedString: displayString, at: point, in: context)
            return
        }

        // Syntax was hidden, so display text is shorter - need to recalculate line breaks
        // Get available width matching TextKit 2's layout
        let availableWidth: CGFloat
        if let textContainer = paneController?.textContainer {
            // Use the actual line fragment rect width from TextKit 2 for consistency
            if let firstFragment = textLineFragments.first {
                availableWidth = firstFragment.typographicBounds.width
            } else {
                availableWidth = textContainer.size.width - (textContainer.lineFragmentPadding * 2)
            }
        } else {
            availableWidth = 760
        }

        // Use CTFramesetter to calculate line breaks on the display text
        let ctSpid = OSSignpostID(log: Signposts.rendering)
        os_signpost(.begin, log: Signposts.rendering, name: Signposts.ctFramesetter, signpostID: ctSpid)
        let framesetter = CTFramesetterCreateWithAttributedString(displayString)
        let constraints = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: displayString.length),
            nil,
            constraints,
            nil
        )

        let framePath = CGPath(rect: CGRect(x: 0, y: 0, width: availableWidth, height: fitSize.height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: displayString.length), framePath, nil)
        os_signpost(.end, log: Signposts.rendering, name: Signposts.ctFramesetter, signpostID: ctSpid)

        // Draw inline code backgrounds first
        drawInlineCodeBackgroundsForDisplayString(displayString: displayString, frame: frame, at: point, fitHeight: fitSize.height, in: context)

        // Get lines and draw each one
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)

        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        for (index, line) in lines.enumerated() {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            // Calculate y position to match drawAttributedString positioning (point.y + ascent)
            // This ensures active and inactive paragraphs render at the same vertical position.
            // For first line: point.y + ascent
            // For subsequent lines: add line height for each previous line
            let lineHeight = ascent + descent + leading
            let lineY = point.y + ascent + (CGFloat(index) * lineHeight)
            context.textPosition = CGPoint(x: point.x + origins[index].x, y: lineY)
            CTLineDraw(line, context)
        }

        context.restoreGState()
    }

    /// Build display string with syntax hidden and formatting applied.
    /// Returns (attributed string, mapping from display position to source position).
    private func buildFormattedDisplayString(text: String) -> (NSAttributedString, [Int: Int]) {
        var displayText = ""
        var positionMap: [Int: Int] = [:]  // display index -> source index
        var attributes: [(range: Range<Int>, attrs: [NSAttributedString.Key: Any])] = []

        // Sort tokens by position
        let sortedTokens = tokens.sorted { $0.contentRange.lowerBound < $1.contentRange.lowerBound }

        var sourceIndex = 0
        var displayIndex = 0

        for token in sortedTokens {
            // Find syntax ranges before content
            let syntaxBefore = token.syntaxRanges.filter { $0.upperBound <= token.contentRange.lowerBound }
            let syntaxStart = syntaxBefore.map(\.lowerBound).min() ?? token.contentRange.lowerBound

            // Add text between last position and this token's syntax
            if sourceIndex < syntaxStart {
                let plainText = substring(of: text, from: sourceIndex, to: syntaxStart)
                for (i, _) in plainText.enumerated() {
                    positionMap[displayIndex + i] = sourceIndex + i
                }
                displayText += plainText
                displayIndex += plainText.count
                sourceIndex = syntaxStart
            }

            // Skip leading syntax, add content with formatting
            let contentText = substring(of: text, from: token.contentRange.lowerBound, to: token.contentRange.upperBound)
            if !contentText.isEmpty {
                let displayStart = displayIndex
                for (i, _) in contentText.enumerated() {
                    positionMap[displayIndex + i] = token.contentRange.lowerBound + i
                }
                displayText += contentText
                displayIndex += contentText.count

                // Record formatting for this range
                let formatAttrs = attributesForElement(token.element)
                attributes.append((range: displayStart..<displayIndex, attrs: formatAttrs))
            }

            // Skip trailing syntax
            let syntaxAfter = token.syntaxRanges.filter { $0.lowerBound >= token.contentRange.upperBound }
            sourceIndex = syntaxAfter.map(\.upperBound).max() ?? token.contentRange.upperBound
        }

        // Add remaining text after last token
        if sourceIndex < text.count {
            let remainingText = substring(of: text, from: sourceIndex, to: text.count)
            for (i, _) in remainingText.enumerated() {
                positionMap[displayIndex + i] = sourceIndex + i
            }
            displayText += remainingText
        }

        // Build attributed string
        let attrString = NSMutableAttributedString(string: displayText, attributes: theme.bodyAttributes)

        // Apply formatting
        for (range, attrs) in attributes {
            let nsRange = NSRange(location: range.lowerBound, length: range.upperBound - range.lowerBound)
            if nsRange.location + nsRange.length <= attrString.length {
                attrString.addAttributes(attrs, range: nsRange)
            }
        }

        return (attrString, positionMap)
    }

    /// Draw inline code backgrounds for the formatted display string.
    private func drawInlineCodeBackgroundsForDisplayString(displayString: NSAttributedString, frame: CTFrame, at point: CGPoint, fitHeight: CGFloat, in context: CGContext) {
        // Find inline code ranges in the display string by checking for code font
        let codeFont = theme.codeFont
        var codeRanges: [NSRange] = []

        displayString.enumerateAttribute(.font, in: NSRange(location: 0, length: displayString.length)) { value, range, _ in
            if let font = value as? NSFont, font == codeFont {
                codeRanges.append(range)
            }
        }

        guard !codeRanges.isEmpty else { return }

        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)

        let lineHeight = theme.bodyFont.ascender - theme.bodyFont.descender + theme.bodyFont.leading
        let verticalPadding: CGFloat = 2.0
        let horizontalPadding: CGFloat = 2.0
        let cornerRadius: CGFloat = 3.0

        context.saveGState()
        context.setFillColor(theme.codeBackgroundColor.cgColor)

        for codeRange in codeRanges {
            // Find which line(s) this code is on
            for (lineIndex, line) in lines.enumerated() {
                let lineRange = CTLineGetStringRange(line)
                let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)

                // Check if code range intersects this line
                let intersection = NSIntersectionRange(codeRange, lineNSRange)
                if intersection.length > 0 {
                    // Get x positions for start and end of code on this line
                    let relativeStart = intersection.location - lineRange.location
                    let relativeEnd = relativeStart + intersection.length

                    let startX = CTLineGetOffsetForStringIndex(line, lineRange.location + relativeStart, nil)
                    let endX = CTLineGetOffsetForStringIndex(line, lineRange.location + relativeEnd, nil)

                    // Calculate y position to match text drawing (top of line)
                    let lineY = point.y + (CGFloat(lineIndex) * lineHeight)

                    let bgRect = CGRect(
                        x: point.x + startX - horizontalPadding,
                        y: lineY - verticalPadding,
                        width: endX - startX + horizontalPadding * 2,
                        height: lineHeight + verticalPadding * 2
                    )
                    let path = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                    context.addPath(path)
                    context.fillPath()
                }
            }
        }

        context.restoreGState()
    }

    /// Draw attributed string using TextKit 2's line fragment positions.
    private func drawLineFragments(attributedString: NSAttributedString, at point: CGPoint, in context: CGContext) {
        for lineFragment in textLineFragments {
            // Get the character range for this line (NSRange)
            let nsRange = lineFragment.characterRange

            guard nsRange.location >= 0, nsRange.location + nsRange.length <= attributedString.length else {
                continue
            }

            // Extract substring for this line
            let lineAttrString = attributedString.attributedSubstring(from: nsRange)

            // Get position from line fragment
            let origin = lineFragment.typographicBounds.origin
            let linePoint = CGPoint(
                x: point.x + origin.x,
                y: point.y + origin.y
            )

            // Draw this line
            drawAttributedString(lineAttrString, at: linePoint, in: context)
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
        // Draw the entire line with blockquote styling (italic font)
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: theme.blockquoteAttributes
        )

        // Apply muted color to syntax characters (the ">" prefix)
        // IMPORTANT: Only change color, keep the same font to match storage metrics
        for syntaxRange in token.syntaxRanges {
            guard syntaxRange.upperBound <= text.count else { continue }
            let nsRange = NSRange(location: syntaxRange.lowerBound, length: syntaxRange.count)
            attributedString.addAttribute(.foregroundColor, value: theme.syntaxCharacterColor, range: nsRange)
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

        // Use font-based height for bars to avoid extending into trailing newline space.
        // Each blockquote line is independent, so we don't need continuous backgrounds.
        let font = theme.blockquoteAttributes[.font] as? NSFont ?? theme.bodyFont
        let barHeight = font.ascender - font.descender + font.leading

        // Draw vertical bars for each nesting level
        context.saveGState()
        context.setFillColor(theme.blockquoteColor.cgColor)

        for level in 0..<depth {
            let barX = point.x + CGFloat(level) * barSpacing
            let barRect = CGRect(
                x: barX,
                y: point.y,
                width: barWidth,
                height: barHeight
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
                attrs[.foregroundColor] = theme.blockquoteColor
                // Remove background color for inline code - it clashes with blockquote styling
                attrs.removeValue(forKey: .backgroundColor)
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

    // MARK: - List Item Drawing Constants

    /// Total indent for list items - must match DocumentModel.listIndent
    /// Applied via paragraph style in storage for cursor positioning.
    private let listIndent: CGFloat = 20.0

    // MARK: - Unordered List Item Drawing

    /// Draw active unordered list item with syntax visible but muted.
    /// Shows the -, *, or + marker in muted color.
    private func drawActiveUnorderedListItem(text: String, token: MarkdownToken, at point: CGPoint, in context: CGContext) {
        // Draw the entire line with body styling
        // The text includes leading whitespace which provides visual nesting
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: theme.bodyAttributes
        )

        // Apply muted color to syntax characters (the "- " or "* " or "+ " marker)
        // IMPORTANT: Only change color, keep the same font to match storage metrics
        for syntaxRange in token.syntaxRanges {
            guard syntaxRange.upperBound <= text.count else { continue }
            let nsRange = NSRange(location: syntaxRange.lowerBound, length: syntaxRange.count)
            attributedString.addAttribute(.foregroundColor, value: theme.syntaxCharacterColor, range: nsRange)
        }

        // Draw at point - paragraph style handles indent for cursor alignment
        drawAttributedString(attributedString, at: point, in: context)
    }

    /// Draw inactive unordered list item with bullet glyph.
    /// Hides the -, *, + marker and replaces with bullet (•) character.
    /// Handles inline formatting within the list item content.
    /// NOTE: Position bullet and content based on actual text measurements to match active mode.
    private func drawInactiveUnorderedListItem(text: String, token: MarkdownToken, at point: CGPoint, in context: CGContext) {
        let contentStart = token.contentRange.lowerBound

        // Measure where the marker starts (after leading whitespace)
        let markerStart = token.syntaxRanges.first?.lowerBound ?? 0
        let leadingText = substring(of: text, from: 0, to: markerStart)
        let leadingWidth = measureWidth(leadingText, attributes: theme.bodyAttributes)

        // Measure where content starts (after marker)
        let prefixText = substring(of: text, from: 0, to: contentStart)
        let prefixWidth = measureWidth(prefixText, attributes: theme.bodyAttributes)

        // Draw bullet at marker position (where "-" would be in active mode)
        let bulletString = NSAttributedString(string: "•", attributes: theme.bodyAttributes)
        let bulletPoint = CGPoint(x: point.x + leadingWidth, y: point.y)
        drawAttributedString(bulletString, at: bulletPoint, in: context)

        // Get content text (without the marker prefix)
        let contentText = String(text.dropFirst(contentStart))

        // Filter inline tokens that fall within the content range and adjust their ranges
        let inlineTokens = tokens.filter { t in
            if case .unorderedListItem = t.element { return false }
            return t.contentRange.lowerBound >= contentStart
        }

        // Calculate content position to match active mode
        let contentPoint = CGPoint(x: point.x + prefixWidth, y: point.y)

        // If no inline tokens, draw plain text
        if inlineTokens.isEmpty {
            let attrString = NSAttributedString(string: contentText, attributes: theme.bodyAttributes)
            drawAttributedString(attrString, at: contentPoint, in: context)
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
                        attributes: theme.bodyAttributes,
                        xOffset: currentX
                    ))
                    currentX += measureWidth(plainText, attributes: theme.bodyAttributes)
                }
            }

            // Draw content with appropriate styling
            let tokenContentText = substring(of: text, from: inlineToken.contentRange.lowerBound, to: inlineToken.contentRange.upperBound)
            if !tokenContentText.isEmpty {
                let attrs = attributesForElement(inlineToken.element)
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
                    attributes: theme.bodyAttributes,
                    xOffset: currentX
                ))
            }
        }

        // Execute drawing at content position
        for run in runs {
            let runPoint = CGPoint(x: contentPoint.x + run.xOffset, y: contentPoint.y)
            let attrString = NSAttributedString(string: run.text, attributes: run.attributes)
            drawAttributedString(attrString, at: runPoint, in: context)
        }
    }

    // MARK: - Ordered List Item Drawing

    /// Draw active ordered list item with syntax visible but muted.
    /// Shows the 1., 2., etc. marker in muted color.
    private func drawActiveOrderedListItem(text: String, token: MarkdownToken, number: Int, at point: CGPoint, in context: CGContext) {
        // Draw the entire line with body styling
        // The text includes leading whitespace which provides visual nesting
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: theme.bodyAttributes
        )

        // Apply muted color to syntax characters (the "1. " marker)
        // IMPORTANT: Only change color, keep the same font to match storage metrics
        for syntaxRange in token.syntaxRanges {
            guard syntaxRange.upperBound <= text.count else { continue }
            let nsRange = NSRange(location: syntaxRange.lowerBound, length: syntaxRange.count)
            attributedString.addAttribute(.foregroundColor, value: theme.syntaxCharacterColor, range: nsRange)
        }

        // Draw at point - paragraph style handles indent for cursor alignment
        drawAttributedString(attributedString, at: point, in: context)
    }

    /// Draw inactive ordered list item with formatted number.
    /// Hides the "1." syntax and replaces with a cleanly rendered number.
    /// Handles inline formatting within the list item content.
    /// NOTE: Position number and content based on actual text measurements to match active mode.
    private func drawInactiveOrderedListItem(text: String, token: MarkdownToken, number: Int, at point: CGPoint, in context: CGContext) {
        let contentStart = token.contentRange.lowerBound

        // Measure where the marker starts (after leading whitespace)
        let markerStart = token.syntaxRanges.first?.lowerBound ?? 0
        let leadingText = substring(of: text, from: 0, to: markerStart)
        let leadingWidth = measureWidth(leadingText, attributes: theme.bodyAttributes)

        // Measure where content starts (after marker) - matches unordered list approach
        let prefixText = substring(of: text, from: 0, to: contentStart)
        let prefixWidth = measureWidth(prefixText, attributes: theme.bodyAttributes)

        // Draw the number at marker position (where "1." would be in active mode)
        let numberString = "\(number)."
        let numberAttrString = NSAttributedString(string: numberString, attributes: theme.bodyAttributes)
        let numberPoint = CGPoint(x: point.x + leadingWidth, y: point.y)
        drawAttributedString(numberAttrString, at: numberPoint, in: context)

        // Get content text (without the marker prefix)
        let contentText = String(text.dropFirst(contentStart))

        // Filter inline tokens that fall within the content range and adjust their ranges
        let inlineTokens = tokens.filter { t in
            if case .orderedListItem = t.element { return false }
            return t.contentRange.lowerBound >= contentStart
        }

        // Calculate content position to match active mode (same approach as unordered lists)
        let contentPoint = CGPoint(x: point.x + prefixWidth, y: point.y)

        // If no inline tokens, draw plain text
        if inlineTokens.isEmpty {
            let attrString = NSAttributedString(string: contentText, attributes: theme.bodyAttributes)
            drawAttributedString(attrString, at: contentPoint, in: context)
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
                        attributes: theme.bodyAttributes,
                        xOffset: currentX
                    ))
                    currentX += measureWidth(plainText, attributes: theme.bodyAttributes)
                }
            }

            // Draw content with appropriate styling
            let tokenContentText = substring(of: text, from: inlineToken.contentRange.lowerBound, to: inlineToken.contentRange.upperBound)
            if !tokenContentText.isEmpty {
                let attrs = attributesForElement(inlineToken.element)
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
                    attributes: theme.bodyAttributes,
                    xOffset: currentX
                ))
            }
        }

        // Execute drawing at content position
        for run in runs {
            let runPoint = CGPoint(x: contentPoint.x + run.xOffset, y: contentPoint.y)
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
    /// - Parameter isOpening: True for opening fence (extends to content), false for closing fence.
    private func drawActiveFenceLine(text: String, language: String?, isOpening: Bool, at point: CGPoint, in context: CGContext) {
        // Opening fence extends to connect with content; closing fence does not extend
        drawCodeBlockBackground(at: point, in: context, useFullHeight: isOpening)

        // Draw the fence syntax in muted color with monospace font
        let attrString = NSAttributedString(string: text, attributes: theme.syntaxCharacterAttributes)
        drawAttributedString(attrString, at: point, in: context)
    }

    /// Draw fence line when inactive (cursor not present).
    /// Hides the fence syntax entirely - shows nothing or just the language label.
    /// - Parameter isOpening: True for opening fence (extends to content), false for closing fence.
    private func drawInactiveFenceLine(text: String, language: String?, isOpening: Bool, at point: CGPoint, in context: CGContext) {
        // Opening fence extends to connect with content; closing fence does not extend
        drawCodeBlockBackground(at: point, in: context, useFullHeight: isOpening)

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
    /// Always renders the same regardless of active/inactive state - only fence lines change.
    private func drawCodeBlockContent(text: String, language: String?, at point: CGPoint, in context: CGContext) {
        // Content lines use full fragment height for continuous backgrounds
        drawCodeBlockBackground(at: point, in: context, useFullHeight: true)

        // Always apply syntax highlighting (or fallback to plain monospace)
        // Code block content should look consistent regardless of cursor position
        // Ensure SyntaxHighlighter uses the correct theme for current appearance
        let expectedTheme = theme.highlightTheme
        if SyntaxHighlighter.shared.currentThemeName != expectedTheme {
            SyntaxHighlighter.shared.setTheme(expectedTheme)
        }
        let hlSpid = OSSignpostID(log: Signposts.rendering)
        os_signpost(.begin, log: Signposts.rendering, name: Signposts.highlightr, signpostID: hlSpid, "len=%d lang=%{public}s", text.count, language ?? "none")
        let highlighted = PerfTimer.shared.measure("draw.highlightr") {
            SyntaxHighlighter.shared.highlight(code: text, language: language)
        }
        os_signpost(.end, log: Signposts.rendering, name: Signposts.highlightr, signpostID: hlSpid)

        if let highlighted = highlighted {
            // IMPORTANT: Replace Highlightr's font with our codeFont to match storage metrics
            // This ensures cursor positioning is correct while keeping syntax colors
            let mutableHighlighted = NSMutableAttributedString(attributedString: highlighted)
            mutableHighlighted.addAttribute(.font, value: theme.codeFont, range: NSRange(location: 0, length: mutableHighlighted.length))
            drawAttributedString(mutableHighlighted, at: point, in: context)
        } else {
            // Fallback to plain monospace if highlighting fails or no language specified
            // Use the highlighter's base text color for consistency with highlighted blocks
            let attrs: [NSAttributedString.Key: Any] = [
                .font: theme.codeFont,
                .foregroundColor: SyntaxHighlighter.shared.baseTextColor
            ]
            let attrString = NSAttributedString(string: text, attributes: attrs)
            drawAttributedString(attrString, at: point, in: context)
        }
    }

    /// Draw the code block background rectangle.
    /// - Parameters:
    ///   - useFullHeight: If true, uses full fragment height (for opening fences and content lines).
    ///                    If false, uses text content height only (for closing fences).
    private func drawCodeBlockBackground(at point: CGPoint, in context: CGContext, useFullHeight: Bool) {
        let bounds = renderingSurfaceBounds

        // Determine background height:
        // - Opening fence + content: Use full fragment height for continuous backgrounds
        //   (layoutFragmentFrame includes inter-line spacing to connect with next line).
        // - Closing fence: Use text content height only to prevent background from
        //   extending into trailing newline space (which would incorrectly style the next paragraph).
        let bgHeight: CGFloat
        if useFullHeight {
            bgHeight = layoutFragmentFrame.height
        } else {
            let font = theme.codeFont
            bgHeight = font.ascender - font.descender + font.leading
        }

        context.saveGState()
        context.setFillColor(theme.codeBackgroundColor.cgColor)

        let bgRect = CGRect(
            x: point.x,
            y: point.y,
            width: bounds.width,
            height: bgHeight
        )
        context.fill(bgRect)
        context.restoreGState()
    }

    // MARK: - Raw Markdown Drawing (Active Paragraph)

    /// Draw with all syntax characters visible but muted, and inline formatting applied.
    /// Shows live formatting preview while keeping syntax visible.
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

        // Draw inline code backgrounds first (full line height)
        drawInlineCodeBackgrounds(text: text, baseAttributes: baseAttributes, at: point, in: context)

        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes
        )

        // Apply inline formatting to content ranges (bold, italic, etc.)
        for token in tokens {
            // Skip block-level elements - they're handled by base attributes
            switch token.element {
            case .heading, .blockquote, .unorderedListItem, .orderedListItem,
                 .fencedCodeBlock, .indentedCodeBlock, .horizontalRule, .text:
                continue
            case .inlineCode:
                // For inline code, apply font but NOT background (we draw it manually)
                guard token.contentRange.upperBound <= text.count else { continue }
                let contentNSRange = NSRange(location: token.contentRange.lowerBound, length: token.contentRange.count)
                attributedString.addAttribute(.font, value: theme.codeFont, range: contentNSRange)
                continue
            default:
                break
            }

            // Apply formatting to content range
            guard token.contentRange.upperBound <= text.count else { continue }
            let contentNSRange = NSRange(location: token.contentRange.lowerBound, length: token.contentRange.count)
            let formatAttrs = attributesForElement(token.element)
            attributedString.addAttributes(formatAttrs, range: contentNSRange)
        }

        // Apply muted color to syntax characters (keeping their current font)
        for token in tokens {
            for syntaxRange in token.syntaxRanges {
                guard syntaxRange.upperBound <= text.count else { continue }
                let nsRange = NSRange(location: syntaxRange.lowerBound, length: syntaxRange.count)
                // Only change color, keep the font to match storage metrics
                attributedString.addAttribute(.foregroundColor, value: theme.syntaxCharacterColor, range: nsRange)
            }
        }

        drawAttributedString(attributedString, at: point, in: context)
    }

    /// Draw full-height background rectangles for inline code spans.
    private func drawInlineCodeBackgrounds(text: String, baseAttributes: [NSAttributedString.Key: Any], at point: CGPoint, in context: CGContext) {
        let inlineCodeTokens = tokens.filter {
            if case .inlineCode = $0.element { return true }
            return false
        }

        guard !inlineCodeTokens.isEmpty else { return }

        // Get line height from base font
        let baseFont = baseAttributes[.font] as? NSFont ?? theme.bodyFont
        let lineHeight = baseFont.ascender - baseFont.descender + baseFont.leading
        let verticalPadding: CGFloat = 2.0
        let horizontalPadding: CGFloat = 2.0
        let cornerRadius: CGFloat = 3.0

        context.saveGState()
        context.setFillColor(theme.codeBackgroundColor.cgColor)

        for token in inlineCodeTokens {
            // Get full range including backticks
            guard let firstSyntax = token.syntaxRanges.first,
                  let lastSyntax = token.syntaxRanges.last else { continue }
            let fullStart = firstSyntax.lowerBound
            let fullEnd = lastSyntax.upperBound
            guard fullEnd <= text.count else { continue }

            // Measure text width up to the start
            let textBefore = substring(of: text, from: 0, to: fullStart)
            let xOffset = measureWidth(textBefore, attributes: baseAttributes)

            // Measure the inline code span width (including backticks)
            let codeText = substring(of: text, from: fullStart, to: fullEnd)
            // Use mixed attributes: backticks in base font, content in code font
            let codeWidth = measureInlineCodeWidth(codeText, token: token, baseAttributes: baseAttributes)

            // Draw rounded rectangle background
            let bgRect = CGRect(
                x: point.x + xOffset - horizontalPadding,
                y: point.y - verticalPadding,
                width: codeWidth + horizontalPadding * 2,
                height: lineHeight + verticalPadding * 2
            )
            let path = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            context.addPath(path)
            context.fillPath()
        }

        context.restoreGState()
    }

    /// Measure width of inline code span with mixed fonts (backticks in base font, content in code font).
    private func measureInlineCodeWidth(_ text: String, token: MarkdownToken, baseAttributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let attrString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        // Apply code font to content range (adjusted for substring offset)
        let contentStart = token.contentRange.lowerBound - (token.syntaxRanges.first?.lowerBound ?? 0)
        let contentLength = token.contentRange.count
        if contentStart >= 0 && contentStart + contentLength <= text.count {
            let contentRange = NSRange(location: contentStart, length: contentLength)
            attrString.addAttribute(.font, value: theme.codeFont, range: contentRange)
        }

        let line = CTLineCreateWithAttributedString(attrString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
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
                let isInlineCode: Bool
                if case .inlineCode = token.element {
                    isInlineCode = true
                } else {
                    isInlineCode = false
                }
                runs.append(DrawingRun(
                    text: contentText,
                    attributes: attrs,
                    xOffset: currentX,
                    isInlineCode: isInlineCode
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

        // Draw inline code backgrounds first (full line height)
        let baseFont = theme.bodyFont
        let lineHeight = baseFont.ascender - baseFont.descender + baseFont.leading
        let verticalPadding: CGFloat = 2.0
        let horizontalPadding: CGFloat = 2.0
        let cornerRadius: CGFloat = 3.0

        context.saveGState()
        context.setFillColor(theme.codeBackgroundColor.cgColor)

        for run in runs where run.isInlineCode {
            let runWidth = measureWidth(run.text, attributes: run.attributes)
            let bgRect = CGRect(
                x: point.x + run.xOffset - horizontalPadding,
                y: point.y - verticalPadding,
                width: runWidth + horizontalPadding * 2,
                height: lineHeight + verticalPadding * 2
            )
            let path = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            context.addPath(path)
            context.fillPath()
        }

        context.restoreGState()

        // Execute text drawing
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
        let isInlineCode: Bool

        init(text: String, attributes: [NSAttributedString.Key: Any], xOffset: CGFloat, isInlineCode: Bool = false) {
            self.text = text
            self.attributes = attributes
            self.xOffset = xOffset
            self.isInlineCode = isInlineCode
        }
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
        // For inline elements, use theme's canonical font resolution
        if let font = theme.fontForInlineElement(element) {
            var attrs = theme.bodyAttributes
            attrs[.font] = font
            // Add element-specific non-font attributes
            switch element {
            case .link:
                attrs[.foregroundColor] = theme.linkColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            default:
                break
            }
            return attrs
        }

        // Non-inline elements use their dedicated attribute dictionaries
        switch element {
        case .heading(let level):
            return theme.headingAttributes(level: level)
        case .fencedCodeBlock, .indentedCodeBlock:
            return theme.codeBlockAttributes
        case .blockquote:
            return theme.blockquoteAttributes
        default:
            // unorderedListItem, orderedListItem, horizontalRule, text
            return theme.bodyAttributes
        }
    }
}
