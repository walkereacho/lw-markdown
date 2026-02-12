/// Cache of parsed Markdown tokens, keyed by paragraph index + text validation.
///
/// ## Design
/// - Primary key: paragraph index (O(1) dictionary lookup)
/// - Validation: stored text string compared on hit (fast for typical line lengths)
/// - Thread safety: all call sites run on main thread; no synchronization needed
///
/// ## Invalidation
/// - Single paragraph edit: `invalidate(paragraphAt:)` clears that entry
/// - Insertion/deletion: `invalidateFrom(index:)` clears all shifted entries
/// - Document reload: `invalidateAll()` clears everything
final class MarkdownTokenCache {

    private struct CacheEntry {
        let text: String
        let tokens: [MarkdownToken]
    }

    private var entries: [Int: CacheEntry] = [:]

    /// Look up cached tokens. Returns nil on miss or text mismatch.
    func tokens(forParagraphAt index: Int, text: String) -> [MarkdownToken]? {
        guard let entry = entries[index], entry.text == text else { return nil }
        return entry.tokens
    }

    /// Store parsed tokens for a paragraph.
    func store(tokens: [MarkdownToken], forParagraphAt index: Int, text: String) {
        entries[index] = CacheEntry(text: text, tokens: tokens)
    }

    /// Invalidate a specific paragraph (e.g., in-place edit).
    func invalidate(paragraphAt index: Int) {
        entries.removeValue(forKey: index)
    }

    /// Invalidate all entries at or after an index (for insertions/deletions that shift indices).
    func invalidateFrom(index: Int) {
        entries = entries.filter { $0.key < index }
    }

    /// Clear entire cache (e.g., on document reload).
    func invalidateAll() {
        entries.removeAll()
    }
}
