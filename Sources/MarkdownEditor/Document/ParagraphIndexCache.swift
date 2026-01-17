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

    /// Find paragraph index for a text location.
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        guard let storage = contentStorage else { return nil }

        // Binary search
        var low = 0
        var high = paragraphRanges.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let entry = paragraphRanges[mid]

            if entry.range.contains(location) {
                return entry.index
            }

            let targetOffset = storage.offset(from: storage.documentRange.location, to: location)
            let entryOffset = storage.offset(from: storage.documentRange.location, to: entry.range.location)

            if targetOffset < entryOffset {
                high = mid - 1
            } else {
                low = mid + 1
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
