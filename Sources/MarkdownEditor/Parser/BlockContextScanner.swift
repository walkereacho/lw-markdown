import Foundation

/// Scans documents for multi-paragraph constructs.
///
/// Runs on document load (full scan) and incrementally on edits.
final class BlockContextScanner {

    /// Scan entire document for block constructs.
    /// O(N) where N = paragraph count.
    func scan(paragraphs: [String]) -> BlockContext {
        var context = BlockContext()
        var openFence: (index: Int, language: String?)? = nil

        for (i, text) in paragraphs.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for fence (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let open = openFence {
                    // Closing fence
                    context.fencedCodeBlocks.append((
                        start: open.index,
                        end: i,
                        language: open.language
                    ))
                    openFence = nil
                } else {
                    // Opening fence - extract language
                    let afterFence = String(trimmed.dropFirst(3))
                        .trimmingCharacters(in: .whitespaces)
                    let language = afterFence.isEmpty ? nil : afterFence
                    openFence = (index: i, language: language)
                }
            }
        }

        // Handle unclosed fence (extends to end of document)
        if let open = openFence {
            context.fencedCodeBlocks.append((
                start: open.index,
                end: paragraphs.count - 1,
                language: open.language
            ))
        }

        return context
    }

    /// Incremental update after an edit.
    /// Re-scans from affected paragraph to next stable point.
    func update(
        context: inout BlockContext,
        afterEditAt paragraphIndex: Int,
        paragraphs: [String]
    ) {
        // Remove blocks that start at or after the edit point
        context.fencedCodeBlocks.removeAll { block in
            block.start >= paragraphIndex || block.end >= paragraphIndex
        }

        // Re-scan from the edit point
        var openFence: (index: Int, language: String?)? = nil

        // Check if we're resuming inside an existing block
        for block in context.fencedCodeBlocks {
            if paragraphIndex > block.start && paragraphIndex <= block.end {
                // Edit is inside this block - remove it and rescan from its start
                context.fencedCodeBlocks.removeAll { $0.start == block.start }
                openFence = nil
                break
            }
        }

        let startIndex = context.fencedCodeBlocks.last.map { $0.end + 1 } ?? 0
        let scanStart = max(startIndex, paragraphIndex > 0 ? paragraphIndex - 1 : 0)

        for i in scanStart..<paragraphs.count {
            let text = paragraphs[i]
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let open = openFence {
                    context.fencedCodeBlocks.append((
                        start: open.index,
                        end: i,
                        language: open.language
                    ))
                    openFence = nil
                } else {
                    let afterFence = String(trimmed.dropFirst(3))
                        .trimmingCharacters(in: .whitespaces)
                    openFence = (index: i, language: afterFence.isEmpty ? nil : afterFence)
                }
            }
        }

        // Handle unclosed fence
        if let open = openFence {
            context.fencedCodeBlocks.append((
                start: open.index,
                end: paragraphs.count - 1,
                language: open.language
            ))
        }

        // Sort by start index
        context.fencedCodeBlocks.sort { $0.start < $1.start }
    }
}
