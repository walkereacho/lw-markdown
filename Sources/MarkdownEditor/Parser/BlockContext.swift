import Foundation

/// Classifies a paragraph's role within a fenced code block for O(1) lookup.
enum ParagraphCodeBlockStatus {
    case openingFence(language: String?)
    case closingFence
    case inside(language: String?)
}

/// Identifies regions where paragraph-independence doesn't hold.
///
/// Some Markdown constructs span multiple paragraphs (fenced code blocks).
/// This structure tracks their boundaries so the parser can handle them correctly.
struct BlockContext {

    /// Ranges of fenced code blocks (paragraph indices).
    /// `start` is the opening fence, `end` is the closing fence (or last content line if unclosed).
    /// `isClosed` indicates whether the block has an actual closing fence.
    var fencedCodeBlocks: [(start: Int, end: Int, language: String?, isClosed: Bool)] = []

    /// Pre-computed dictionary for O(1) paragraph code-block status lookup.
    private(set) var paragraphStatusLookup: [Int: ParagraphCodeBlockStatus] = [:]

    /// Build the O(1) lookup dictionary from the current `fencedCodeBlocks` array.
    /// Must be called after any mutation of `fencedCodeBlocks`.
    mutating func buildLookup() {
        paragraphStatusLookup.removeAll()
        for block in fencedCodeBlocks {
            paragraphStatusLookup[block.start] = .openingFence(language: block.language)
            if block.isClosed {
                paragraphStatusLookup[block.end] = .closingFence
            }
            let contentEnd = block.isClosed ? block.end : block.end + 1
            for i in (block.start + 1)..<contentEnd {
                paragraphStatusLookup[i] = .inside(language: block.language)
            }
        }
    }

    /// O(1) lookup for a paragraph's code-block status.
    /// Returns nil if the paragraph is not part of any code block.
    func codeBlockStatus(paragraphIndex: Int) -> ParagraphCodeBlockStatus? {
        return paragraphStatusLookup[paragraphIndex]
    }

    /// Collect all paragraph indices that are part of any code block (fences + content).
    /// Used as fallback when paragraphStatusLookup hasn't been built.
    private func allCodeBlockParagraphIndices() -> Set<Int> {
        var indices = Set<Int>()
        for block in fencedCodeBlocks {
            let end = block.isClosed ? block.end : block.end
            for i in block.start...end {
                indices.insert(i)
            }
        }
        return indices
    }

    /// Check if a paragraph is inside a fenced code block (not on boundary).
    func isInsideFencedCodeBlock(paragraphIndex: Int) -> (Bool, String?) {
        for block in fencedCodeBlocks {
            // Inside means between start and end, exclusive of boundaries
            // For unclosed blocks, the end line is content (not a fence), so include it
            if block.isClosed {
                // Closed block: inside is strictly between fences
                if paragraphIndex > block.start && paragraphIndex < block.end {
                    return (true, block.language)
                }
            } else {
                // Unclosed block: inside includes up to and including end (which is content, not fence)
                if paragraphIndex > block.start && paragraphIndex <= block.end {
                    return (true, block.language)
                }
            }
        }
        return (false, nil)
    }

    /// Check if a paragraph is a fence boundary (opening or closing).
    /// For unclosed blocks, only the opening fence is a boundary.
    func isFenceBoundary(paragraphIndex: Int) -> Bool {
        for block in fencedCodeBlocks {
            if paragraphIndex == block.start {
                return true
            }
            // End is only a boundary if block is actually closed
            if block.isClosed && paragraphIndex == block.end {
                return true
            }
        }
        return false
    }

    /// Check if a paragraph is the opening fence of a code block.
    func isOpeningFence(paragraphIndex: Int) -> (Bool, String?) {
        for block in fencedCodeBlocks {
            if paragraphIndex == block.start {
                return (true, block.language)
            }
        }
        return (false, nil)
    }

    /// Check if a paragraph is the closing fence of a code block.
    /// Only returns true for blocks that actually have a closing fence.
    func isClosingFence(paragraphIndex: Int) -> Bool {
        for block in fencedCodeBlocks {
            // Only closed blocks have actual closing fences
            if block.isClosed && paragraphIndex == block.end {
                return true
            }
        }
        return false
    }

    /// Identifies paragraphs whose code-block status changed between two contexts.
    /// O(K) where K = number of paragraphs in code blocks (not total paragraph count).
    ///
    /// Fast path: if fencedCodeBlocks arrays are identical, returns empty set in O(B).
    /// Slow path: iterates union of paragraphStatusLookup keys from both contexts.
    ///
    /// - Parameters:
    ///   - other: The previous block context to compare against.
    ///   - paragraphCount: Total number of paragraphs in the document (unused in fast path).
    /// - Returns: Set of paragraph indices where code-block status changed.
    func paragraphsWithChangedCodeBlockStatus(
        comparedTo other: BlockContext,
        paragraphCount: Int
    ) -> Set<Int> {
        // Fast path: compare fencedCodeBlocks arrays directly
        if fencedCodeBlocks.count == other.fencedCodeBlocks.count {
            var identical = true
            for (a, b) in zip(fencedCodeBlocks, other.fencedCodeBlocks) {
                if a.start != b.start || a.end != b.end || a.isClosed != b.isClosed {
                    identical = false
                    break
                }
            }
            if identical { return [] }
        }

        // Slow path: iterate union of all code-block paragraph indices
        // Use lookups if available, otherwise build sets from fencedCodeBlocks directly
        let selfIndices: Set<Int>
        let otherIndices: Set<Int>

        if !self.paragraphStatusLookup.isEmpty || self.fencedCodeBlocks.isEmpty {
            selfIndices = Set(self.paragraphStatusLookup.keys)
        } else {
            selfIndices = self.allCodeBlockParagraphIndices()
        }

        if !other.paragraphStatusLookup.isEmpty || other.fencedCodeBlocks.isEmpty {
            otherIndices = Set(other.paragraphStatusLookup.keys)
        } else {
            otherIndices = other.allCodeBlockParagraphIndices()
        }

        return selfIndices.symmetricDifference(otherIndices)
    }
}
