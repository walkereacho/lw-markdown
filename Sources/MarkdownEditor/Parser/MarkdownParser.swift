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
        if let headingToken = parseHeading(text) {
            tokens.append(headingToken)
            return tokens
        }

        if let blockquoteToken = parseBlockquote(text) {
            tokens.append(blockquoteToken)
            return tokens
        }

        if let listToken = parseListItem(text) {
            tokens.append(listToken)
            return tokens
        }

        if let hrToken = parseHorizontalRule(text) {
            tokens.append(hrToken)
            return tokens
        }

        // TODO: Parse inline elements

        return tokens
    }

    // MARK: - Block-Level Parsing

    private func parseHeading(_ text: String) -> MarkdownToken? {
        // Pattern: 1-6 # characters, followed by space, then content
        // ^(#{1,6})\s+(.+)$
        let pattern = #/^(#{1,6})\s+(.+)$/#

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
        guard text.hasPrefix("> ") else { return nil }

        return MarkdownToken(
            element: .blockquote,
            contentRange: 2..<text.count,
            syntaxRanges: [0..<2]
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
}
