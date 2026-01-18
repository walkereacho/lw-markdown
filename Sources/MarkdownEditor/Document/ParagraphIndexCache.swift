import AppKit

/// Maintains paragraph range mappings for O(log N) lookups.
///
/// TextKit 2 uses `NSTextRange`/`NSTextLocation` instead of `NSRange`.
/// This cache maps paragraph indices to their text ranges.
final class ParagraphIndexCache {

    private var paragraphRanges: [(range: NSTextRange, index: Int)] = []
    private var documentVersion: Int = 0

    private weak var contentStorage: NSTextContentStorage?

    init(contentStorage: NSTextContentStorage) {
        self.contentStorage = contentStorage
    }

    /// Number of cached paragraphs.
    var count: Int {
        paragraphRanges.count
    }

    // MARK: - Lookup (O(log N) via binary search)

    /// Find paragraph index for a text location using raw text analysis.
    /// Paragraph N = text after the Nth newline (paragraph 0 = text before first newline)
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        guard let storage = contentStorage,
              let text = storage.attributedString?.string else {
            return nil
        }
        let cursorOffset = storage.offset(from: storage.documentRange.location, to: location)

        // Empty document = paragraph 0
        if text.isEmpty {
            return 0
        }

        // Cursor beyond text = on empty new line, no active paragraph
        if cursorOffset >= text.count {
            // Check if last char is newline - if so, we're on empty line after it
            if text.last == "\n" {
                return nil
            }
            // Otherwise cursor is at end of last line (no trailing newline)
            return text.filter { $0 == "\n" }.count
        }

        // Check if char before cursor is newline (we're at start of a line)
        if cursorOffset > 0 {
            let idx = text.index(text.startIndex, offsetBy: cursorOffset - 1)
            if text[idx] == "\n" {
                // We're at position 0 of a new line
                // Paragraph index = number of newlines before cursor
                return text.prefix(cursorOffset).filter { $0 == "\n" }.count
            }
        }

        // Normal case: count newlines before cursor position
        return text.prefix(cursorOffset).filter { $0 == "\n" }.count
    }

    /// Get text range for a paragraph index.
    func paragraphRange(at index: Int) -> NSTextRange? {
        guard index >= 0 && index < paragraphRanges.count else { return nil }
        return paragraphRanges[index].range
    }

    // MARK: - Cache Updates

    /// Handle document edit by rebuilding cache.
    /// A production implementation would do incremental updates,
    /// but full rebuild is correct and simpler for scaffolding.
    func didProcessEditing(in editedRange: NSTextRange, changeInLength delta: Int) {
        rebuildFull()
    }

    /// Rebuild entire cache by enumerating paragraphs.
    func rebuildFull() {
        guard let storage = contentStorage else { return }

        paragraphRanges.removeAll()
        var index = 0

        storage.enumerateTextElements(from: storage.documentRange.location) { element in
            if let paragraph = element as? NSTextParagraph,
               let range = paragraph.elementRange {
                self.paragraphRanges.append((range: range, index: index))
                index += 1
            }
            return true  // Continue enumeration
        }

        documentVersion += 1
    }
}
