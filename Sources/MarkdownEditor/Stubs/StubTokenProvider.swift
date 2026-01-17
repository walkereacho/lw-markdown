import Foundation

/// Stub token provider that returns no tokens.
/// Replace with real Parser module implementation.
final class StubTokenProvider: TokenProviding {
    func parse(_ text: String) -> [MarkdownToken] {
        // Stub: return empty tokens
        // Real parser will analyze text and return proper tokens
        return []
    }
}
