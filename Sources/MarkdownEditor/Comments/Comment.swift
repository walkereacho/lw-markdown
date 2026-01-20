import Foundation

/// A single comment anchored to text in the document.
struct Comment: Codable, Identifiable {
    /// Unique identifier.
    let id: UUID

    /// The exact text this comment is anchored to.
    var anchorText: String

    /// The comment content.
    var content: String

    /// Whether this comment has been resolved.
    var isResolved: Bool

    /// Whether this comment is collapsed in the UI.
    var isCollapsed: Bool

    /// When the comment was created.
    let createdAt: Date

    init(anchorText: String, content: String) {
        self.id = UUID()
        self.anchorText = anchorText
        self.content = content
        self.isResolved = false
        self.isCollapsed = false
        self.createdAt = Date()
    }
}

/// Container for all comments on a document.
struct CommentStore: Codable {
    var comments: [Comment]
    var version: Int = 1

    init() {
        self.comments = []
    }

    /// Find the character range where anchor text appears in document.
    /// Returns nil if anchor text is not found (orphaned).
    func findAnchorRange(for comment: Comment, in documentText: String) -> Range<String.Index>? {
        return documentText.range(of: comment.anchorText)
    }

    /// Get unresolved comments sorted by position in document.
    func unresolvedComments(sortedBy documentText: String) -> [Comment] {
        return comments
            .filter { !$0.isResolved }
            .sorted { lhs, rhs in
                let lhsRange = findAnchorRange(for: lhs, in: documentText)
                let rhsRange = findAnchorRange(for: rhs, in: documentText)
                guard let lhsStart = lhsRange?.lowerBound,
                      let rhsStart = rhsRange?.lowerBound else {
                    return false
                }
                return lhsStart < rhsStart
            }
    }

    /// Get resolved comments.
    func resolvedComments() -> [Comment] {
        return comments.filter { $0.isResolved }
    }
}
