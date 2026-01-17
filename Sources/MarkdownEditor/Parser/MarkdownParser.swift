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

        // TODO: Add more block-level parsers

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
}
