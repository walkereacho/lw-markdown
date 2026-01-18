import Foundation

/// Parser that converts Markdown text to tokens.
///
/// ## Design Principles
/// - Pure function: text in, tokens out
/// - No side effects, no storage interaction
/// - Stateless — block context provided externally
/// - Tokens describe structure; rendering is separate concern
final class MarkdownParser: TokenProviding {

    static let shared = MarkdownParser()

    // MARK: - TokenProviding

    func parse(_ text: String) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []

        // Check block-level elements first (mutually exclusive)
        // Horizontal rules have no content, so return immediately
        if let hrToken = parseHorizontalRule(text) {
            tokens.append(hrToken)
            return tokens
        }

        // Other block-level elements may contain inline elements
        if let headingToken = parseHeading(text) {
            tokens.append(headingToken)
            // Continue to parse inline elements within the heading content
        }

        if let blockquoteToken = parseBlockquote(text) {
            tokens.append(blockquoteToken)
            // Continue to parse inline elements within the blockquote content
        }

        if let listToken = parseListItem(text) {
            tokens.append(listToken)
            // Continue to parse inline elements within the list item content
        }

        // Parse inline elements
        tokens.append(contentsOf: parseInlineElements(text))

        return tokens
    }

    // MARK: - Block-Level Parsing

    private func parseHeading(_ text: String) -> MarkdownToken? {
        // Pattern: 1-6 # characters, followed by space, then optional content
        // Using (.*)$ allows heading to be recognized as soon as "# " is typed
        let pattern = #/^(#{1,6})\s+(.*)$/#

        guard let match = text.wholeMatch(of: pattern) else { return nil }

        let hashes = String(match.1)
        let level = hashes.count
        let contentStart = level + 1  // hashes + space
        let contentEnd = text.count

        return MarkdownToken(
            element: .heading(level: level),
            contentRange: contentStart..<contentEnd,
            syntaxRanges: [0..<level]
        )
    }

    private func parseBlockquote(_ text: String) -> MarkdownToken? {
        // Match one or more '>' characters, each optionally followed by ' '
        // Examples: "> text", "> > text", ">> text", "> > > text"
        var depth = 0
        var syntaxEnd = 0
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char == ">" {
                depth += 1
                syntaxEnd = text.distance(from: text.startIndex, to: index) + 1
                index = text.index(after: index)
                // Skip optional space after each '>'
                if index < text.endIndex && text[index] == " " {
                    syntaxEnd = text.distance(from: text.startIndex, to: index) + 1
                    index = text.index(after: index)
                }
            } else if char == " " {
                // Allow space between '>' characters (like "> > text")
                index = text.index(after: index)
            } else {
                break
            }
        }

        guard depth > 0 else { return nil }

        return MarkdownToken(
            element: .blockquote,
            contentRange: syntaxEnd..<text.count,
            syntaxRanges: [0..<syntaxEnd],
            nestingDepth: depth
        )
    }

    private func parseListItem(_ text: String) -> MarkdownToken? {
        // Unordered: - item, * item, + item
        let unorderedPattern = #/^([-*+])\s+(.+)$/#

        if text.wholeMatch(of: unorderedPattern) != nil {
            let markerLength = 1  // -, *, or +
            let syntaxLength = markerLength + 1  // marker + space
            return MarkdownToken(
                element: .unorderedListItem,
                contentRange: syntaxLength..<text.count,
                syntaxRanges: [0..<syntaxLength]
            )
        }

        // Ordered: 1. item, 2. item, etc.
        let orderedPattern = #/^(\d+)\.\s+(.+)$/#

        if let match = text.wholeMatch(of: orderedPattern) {
            let numberStr = String(match.1)
            let number = Int(numberStr) ?? 1
            let syntaxLength = numberStr.count + 2  // number + ". "
            return MarkdownToken(
                element: .orderedListItem(number: number),
                contentRange: syntaxLength..<text.count,
                syntaxRanges: [0..<syntaxLength]
            )
        }

        return nil
    }

    private func parseHorizontalRule(_ text: String) -> MarkdownToken? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Must be at least 3 of the same character
        guard trimmed.count >= 3 else { return nil }

        let patterns: [(prefix: String, char: Character)] = [
            ("---", "-"),
            ("***", "*"),
            ("___", "_")
        ]

        for (prefix, char) in patterns {
            // Check if line starts with the pattern and only contains that character (and spaces)
            if trimmed.hasPrefix(prefix) &&
               trimmed.allSatisfy({ $0 == char || $0 == " " }) {
                return MarkdownToken(
                    element: .horizontalRule,
                    contentRange: 0..<0,  // No content
                    syntaxRanges: [0..<text.count]
                )
            }
        }

        return nil
    }

    // MARK: - Inline Parsing

    private func parseInlineElements(_ text: String) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        var excludedRanges: [Range<Int>] = []

        // Parse inline code first (contents should not be parsed for emphasis)
        let codeRanges = parseInlineCode(text)
        tokens.append(contentsOf: codeRanges.map { $0.token })
        excludedRanges.append(contentsOf: codeRanges.map { $0.fullRange })

        // Links [text](url) - parse before emphasis so emphasis inside links works
        let linkTokens = parseLinks(in: text, excluding: excludedRanges)
        tokens.append(contentsOf: linkTokens)
        excludedRanges.append(contentsOf: linkTokens.map { rangeFromToken($0) })

        // Bold italic first (***text***) - must be parsed before bold/italic
        let boldItalicTokens = parseEmphasis(
            in: text,
            pattern: #/\*\*\*(.+?)\*\*\*/#,
            element: .boldItalic,
            syntaxLength: 3,
            excluding: excludedRanges
        )
        tokens.append(contentsOf: boldItalicTokens)
        excludedRanges.append(contentsOf: boldItalicTokens.map { rangeFromToken($0) })

        // Bold (**text** or __text__)
        let boldAsteriskTokens = parseEmphasis(
            in: text,
            pattern: #/\*\*(.+?)\*\*/#,
            element: .bold,
            syntaxLength: 2,
            excluding: excludedRanges
        )
        tokens.append(contentsOf: boldAsteriskTokens)
        excludedRanges.append(contentsOf: boldAsteriskTokens.map { rangeFromToken($0) })

        let boldUnderscoreTokens = parseEmphasis(
            in: text,
            pattern: #/__(.+?)__/#,
            element: .bold,
            syntaxLength: 2,
            excluding: excludedRanges
        )
        tokens.append(contentsOf: boldUnderscoreTokens)
        excludedRanges.append(contentsOf: boldUnderscoreTokens.map { rangeFromToken($0) })

        // Italic (*text* or _text_) - use manual parsing to handle adjacent bold markers
        let italicAsteriskTokens = parseItalicManually(
            in: text,
            marker: "*",
            excluding: excludedRanges
        )
        tokens.append(contentsOf: italicAsteriskTokens)
        excludedRanges.append(contentsOf: italicAsteriskTokens.map { rangeFromToken($0) })

        let italicUnderscoreTokens = parseItalicManually(
            in: text,
            marker: "_",
            excluding: excludedRanges
        )
        tokens.append(contentsOf: italicUnderscoreTokens)

        return tokens
    }

    private func rangeFromToken(_ token: MarkdownToken) -> Range<Int> {
        // Get full range from syntax ranges (opening to closing)
        guard let first = token.syntaxRanges.first,
              let last = token.syntaxRanges.last else {
            return token.contentRange
        }
        return first.lowerBound..<last.upperBound
    }

    private struct InlineCodeMatch {
        let token: MarkdownToken
        let fullRange: Range<Int>
    }

    private func parseInlineCode(_ text: String) -> [InlineCodeMatch] {
        var matches: [InlineCodeMatch] = []

        let pattern = #/`([^`]+)`/#

        for match in text.matches(of: pattern) {
            let start = text.distance(from: text.startIndex, to: match.range.lowerBound)
            let end = text.distance(from: text.startIndex, to: match.range.upperBound)

            let contentStart = start + 1
            let contentEnd = end - 1

            let token = MarkdownToken(
                element: .inlineCode,
                contentRange: contentStart..<contentEnd,
                syntaxRanges: [start..<(start + 1), (end - 1)..<end]
            )

            matches.append(InlineCodeMatch(token: token, fullRange: start..<end))
        }

        return matches
    }

    private func parseEmphasis<Output>(
        in text: String,
        pattern: Regex<Output>,
        element: MarkdownElement,
        syntaxLength: Int,
        excluding: [Range<Int>]
    ) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []

        for match in text.matches(of: pattern) {
            let start = text.distance(from: text.startIndex, to: match.range.lowerBound)
            let end = text.distance(from: text.startIndex, to: match.range.upperBound)

            // Skip if this range overlaps with excluded ranges (e.g., code)
            let overlapsExcluded = excluding.contains { excluded in
                start < excluded.upperBound && end > excluded.lowerBound
            }
            if overlapsExcluded { continue }

            let contentStart = start + syntaxLength
            let contentEnd = end - syntaxLength

            tokens.append(MarkdownToken(
                element: element,
                contentRange: contentStart..<contentEnd,
                syntaxRanges: [
                    start..<(start + syntaxLength),
                    (end - syntaxLength)..<end
                ]
            ))
        }

        return tokens
    }

    /// Parse italic matches using a character-by-character approach to handle
    /// cases where regex fails due to asterisk consumption.
    private func parseItalicManually(
        in text: String,
        marker: Character,
        excluding: [Range<Int>]
    ) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        var i = 0
        let chars = Array(text)
        let n = chars.count

        while i < n {
            // Skip if inside excluded range
            if excluding.contains(where: { i >= $0.lowerBound && i < $0.upperBound }) {
                i += 1
                continue
            }

            // Look for single marker (not double)
            if chars[i] == marker {
                // Check it's not part of double/triple marker
                let prevIsMarker = (i > 0 && chars[i - 1] == marker)
                let nextIsMarker = (i + 1 < n && chars[i + 1] == marker)

                if !prevIsMarker && !nextIsMarker {
                    // Found opening marker, look for closing
                    let openPos = i
                    var j = i + 1

                    // Find content (must be non-empty, no markers)
                    while j < n && chars[j] != marker {
                        // Stop if we hit an excluded range
                        if excluding.contains(where: { j >= $0.lowerBound && j < $0.upperBound }) {
                            break
                        }
                        j += 1
                    }

                    // Check for valid closing marker
                    if j < n && chars[j] == marker && j > openPos + 1 {
                        let prevIsMarkerClose = (j > 0 && chars[j - 1] == marker)
                        let nextIsMarkerClose = (j + 1 < n && chars[j + 1] == marker)

                        if !prevIsMarkerClose && !nextIsMarkerClose {
                            // Valid italic match
                            let closePos = j
                            tokens.append(MarkdownToken(
                                element: .italic,
                                contentRange: (openPos + 1)..<closePos,
                                syntaxRanges: [
                                    openPos..<(openPos + 1),
                                    closePos..<(closePos + 1)
                                ]
                            ))
                            i = closePos + 1
                            continue
                        }
                    }
                }
            }
            i += 1
        }

        return tokens
    }

    private func parseLinks(in text: String, excluding: [Range<Int>]) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []

        // Pattern: [text](url)
        let pattern = #/\[([^\]]+)\]\(([^)]+)\)/#

        for match in text.matches(of: pattern) {
            let start = text.distance(from: text.startIndex, to: match.range.lowerBound)
            let end = text.distance(from: text.startIndex, to: match.range.upperBound)

            // Skip if overlaps with excluded ranges
            let overlapsExcluded = excluding.contains { excluded in
                start < excluded.upperBound && end > excluded.lowerBound
            }
            if overlapsExcluded { continue }

            // Extract URL
            let url = String(match.2)

            // Find the bracket positions
            let fullText = String(text[match.range])
            guard let closeBracketIndex = fullText.firstIndex(of: "]") else { continue }

            let bracketOffset = fullText.distance(from: fullText.startIndex, to: closeBracketIndex)

            let contentStart = start + 1  // After [
            let contentEnd = start + bracketOffset  // Before ]
            let urlEnd = end - 1  // Before )

            tokens.append(MarkdownToken(
                element: .link(url: url),
                contentRange: contentStart..<contentEnd,
                syntaxRanges: [
                    start..<(start + 1),           // [
                    contentEnd..<(contentEnd + 2),  // ](
                    urlEnd..<end                    // )
                ]
            ))
        }

        return tokens
    }
}
