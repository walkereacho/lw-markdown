import Foundation

/// Identifies regions where paragraph-independence doesn't hold.
///
/// Some Markdown constructs span multiple paragraphs (fenced code blocks).
/// This structure tracks their boundaries so the parser can handle them correctly.
struct BlockContext {

    /// Ranges of fenced code blocks (paragraph indices).
    /// `start` is the opening fence, `end` is the closing fence (or last content line if unclosed).
    /// `isClosed` indicates whether the block has an actual closing fence.
    var fencedCodeBlocks: [(start: Int, end: Int, language: String?, isClosed: Bool)] = []

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
    ///
    /// - Parameters:
    ///   - other: The previous block context to compare against.
    ///   - paragraphCount: Total number of paragraphs in the document.
    /// - Returns: Set of paragraph indices where code-block status changed.
    func paragraphsWithChangedCodeBlockStatus(
        comparedTo other: BlockContext,
        paragraphCount: Int
    ) -> Set<Int> {
        var changed = Set<Int>()
        for i in 0..<paragraphCount {
            let wasInBlock = other.isInsideFencedCodeBlock(paragraphIndex: i).0 ||
                             other.isFenceBoundary(paragraphIndex: i)
            let isInBlock = self.isInsideFencedCodeBlock(paragraphIndex: i).0 ||
                            self.isFenceBoundary(paragraphIndex: i)
            if wasInBlock != isInBlock {
                changed.insert(i)
            }
        }
        return changed
    }
}
