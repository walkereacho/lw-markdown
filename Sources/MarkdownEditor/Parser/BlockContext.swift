import Foundation

/// Identifies regions where paragraph-independence doesn't hold.
///
/// Some Markdown constructs span multiple paragraphs (fenced code blocks).
/// This structure tracks their boundaries so the parser can handle them correctly.
struct BlockContext {

    /// Ranges of fenced code blocks (paragraph indices).
    /// `start` is the opening fence, `end` is the closing fence.
    var fencedCodeBlocks: [(start: Int, end: Int, language: String?)] = []

    /// Check if a paragraph is inside a fenced code block (not on boundary).
    func isInsideFencedCodeBlock(paragraphIndex: Int) -> (Bool, String?) {
        for block in fencedCodeBlocks {
            // Inside means between start and end, exclusive
            if paragraphIndex > block.start && paragraphIndex < block.end {
                return (true, block.language)
            }
        }
        return (false, nil)
    }

    /// Check if a paragraph is a fence boundary (opening or closing).
    func isFenceBoundary(paragraphIndex: Int) -> Bool {
        for block in fencedCodeBlocks {
            if paragraphIndex == block.start || paragraphIndex == block.end {
                return true
            }
        }
        return false
    }
}
