import AppKit

/// Maintains paragraph range mappings for O(log N) lookups.
///
/// TextKit 2 uses `NSTextRange`/`NSTextLocation` instead of `NSRange`.
/// This cache maps paragraph indices to their text ranges, and pre-computes
/// integer offsets for fast binary search without framework calls.
final class ParagraphIndexCache {

    private var paragraphRanges: [(range: NSTextRange, index: Int)] = []
    /// Pre-computed integer offsets for O(log N) binary search without storage.offset() calls.
    private var integerRanges: [(start: Int, end: Int)] = []
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

    /// Find paragraph index for a text location using binary search over pre-computed integer offsets.
    /// Falls back to linear scan only when the cache is empty.
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        guard let storage = contentStorage else { return nil }

        let cursorOffset = storage.offset(from: storage.documentRange.location, to: location)

        // Use binary search over pre-computed integer offsets (O(log N), no framework calls)
        if !integerRanges.isEmpty {
            return paragraphIndex(forCharacterOffset: cursorOffset)
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

    /// Find paragraph index for a character offset using binary search over pre-computed ranges.
    /// Use this from contexts that have NSRange offsets (e.g., willProcessEditing) to avoid
    /// the O(N) newline-counting approach.
    func paragraphIndex(forCharacterOffset offset: Int) -> Int? {
        guard !integerRanges.isEmpty else { return nil }

        var lo = 0
        var hi = integerRanges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let range = integerRanges[mid]
            if offset < range.start {
                hi = mid - 1
            } else if offset >= range.end {
                lo = mid + 1
            } else {
                return mid
            }
        }
        return nil
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
        integerRanges.removeAll()
        var index = 0
        let docStart = storage.documentRange.location

        storage.enumerateTextElements(from: docStart) { element in
            if let paragraph = element as? NSTextParagraph,
               let range = paragraph.elementRange {
                self.paragraphRanges.append((range: range, index: index))
                let start = storage.offset(from: docStart, to: range.location)
                let end = storage.offset(from: docStart, to: range.endLocation)
                self.integerRanges.append((start: start, end: end))
                index += 1
            }
            return true  // Continue enumeration
        }

        documentVersion += 1
    }
}
