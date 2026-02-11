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

    /// Find paragraph index for a text location using binary search over cached paragraph ranges.
    /// Falls back to linear scan only when the cache is empty.
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        guard let storage = contentStorage else { return nil }

        let cursorOffset = storage.offset(from: storage.documentRange.location, to: location)

        // Use binary search over paragraphRanges when available (O(log N))
        if !paragraphRanges.isEmpty {
            var lo = 0
            var hi = paragraphRanges.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                let range = paragraphRanges[mid].range
                let rangeStart = storage.offset(from: storage.documentRange.location, to: range.location)
                let rangeEnd = storage.offset(from: storage.documentRange.location, to: range.endLocation)
                if cursorOffset < rangeStart {
                    hi = mid - 1
                } else if cursorOffset >= rangeEnd {
                    lo = mid + 1
                } else {
                    return paragraphRanges[mid].index
                }
            }
            // Cursor is beyond all paragraph ranges (e.g. trailing newline)
            return nil
        }

        // Fallback: linear scan when cache is empty (e.g. before first rebuildFull)
        guard let text = storage.attributedString?.string else { return nil }

        if text.isEmpty { return 0 }

        if cursorOffset >= text.count {
            if text.last == "\n" { return nil }
            return text.filter { $0 == "\n" }.count
        }

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
