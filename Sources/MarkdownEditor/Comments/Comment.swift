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

    /// Get unresolved comments sorted by position in document (top to bottom).
    func unresolvedComments(sortedBy documentText: String) -> [Comment] {
        return comments
            .filter { !$0.isResolved }
            .sorted { lhs, rhs in
                let lhsRange = findAnchorRange(for: lhs, in: documentText)
                let rhsRange = findAnchorRange(for: rhs, in: documentText)
                switch (lhsRange?.lowerBound, rhsRange?.lowerBound) {
                case let (lhsStart?, rhsStart?):
                    return lhsStart < rhsStart
                case (_?, nil):
                    return true  // lhs found, rhs not - lhs comes first
                case (nil, _?):
                    return false // rhs found, lhs not - rhs comes first
                case (nil, nil):
                    return lhs.createdAt < rhs.createdAt  // neither found, sort by creation
                }
            }
    }

    /// Get resolved comments.
    func resolvedComments() -> [Comment] {
        return comments.filter { $0.isResolved }
    }
}
