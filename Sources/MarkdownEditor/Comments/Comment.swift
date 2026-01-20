import Foundation

/// Surrounding text context for anchor recovery when occurrences shift.
struct AnchorContext: Codable, Equatable {
    /// ~30 characters before the anchor text.
    let textBefore: String
    /// ~30 characters after the anchor text.
    let textAfter: String
}

/// A single comment anchored to text in the document.
struct Comment: Codable, Identifiable {
    /// Unique identifier.
    let id: UUID

    /// The exact text this comment is anchored to.
    var anchorText: String

    /// 1-based occurrence index (1st, 2nd, 3rd occurrence of anchorText).
    var anchorOccurrence: Int

    /// Surrounding text context for recovery when occurrences shift.
    var anchorContext: AnchorContext?

    /// The comment content.
    var content: String

    /// Whether this comment has been resolved.
    var isResolved: Bool

    /// Whether this comment is collapsed in the UI.
    var isCollapsed: Bool

    /// When the comment was created.
    let createdAt: Date

    init(anchorText: String, content: String, anchorOccurrence: Int = 1, anchorContext: AnchorContext? = nil) {
        self.id = UUID()
        self.anchorText = anchorText
        self.anchorOccurrence = anchorOccurrence
        self.anchorContext = anchorContext
        self.content = content
        self.isResolved = false
        self.isCollapsed = false
        self.createdAt = Date()
    }

    // Custom decoding to support migration from v1 (without anchorOccurrence/anchorContext)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        anchorText = try container.decode(String.self, forKey: .anchorText)
        anchorOccurrence = try container.decodeIfPresent(Int.self, forKey: .anchorOccurrence) ?? 1
        anchorContext = try container.decodeIfPresent(AnchorContext.self, forKey: .anchorContext)
        content = try container.decode(String.self, forKey: .content)
        isResolved = try container.decode(Bool.self, forKey: .isResolved)
        isCollapsed = try container.decode(Bool.self, forKey: .isCollapsed)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

/// Result of anchor matching with occurrence info and confidence score.
struct AnchorMatch {
    let range: Range<String.Index>
    let occurrenceIndex: Int  // 1-based
    let score: Double         // 0.0-1.0 context similarity
}

/// Container for all comments on a document.
struct CommentStore: Codable {
    var comments: [Comment]
    var version: Int = 2

    init() {
        self.comments = []
    }

    // MARK: - Anchor Finding with Smart Recovery

    /// Find the character range where anchor text appears in document.
    /// Uses occurrence index and context matching for disambiguation.
    /// Returns nil if anchor text is not found (orphaned).
    func findAnchorRange(for comment: Comment, in documentText: String) -> Range<String.Index>? {
        return findAnchorMatch(for: comment, in: documentText)?.range
    }

    /// Find anchor match with full details including occurrence index and confidence score.
    func findAnchorMatch(for comment: Comment, in documentText: String) -> AnchorMatch? {
        let allOccurrences = findAllOccurrences(of: comment.anchorText, in: documentText)
        guard !allOccurrences.isEmpty else { return nil }

        // Score all occurrences by context similarity
        var matches: [AnchorMatch] = []
        for (index, range) in allOccurrences.enumerated() {
            let score: Double
            if let context = comment.anchorContext {
                score = contextMatchScore(range, context: context, in: documentText)
            } else {
                // No context stored - give bonus to stored occurrence index
                score = (index + 1 == comment.anchorOccurrence) ? 1.0 : 0.5
            }
            matches.append(AnchorMatch(range: range, occurrenceIndex: index + 1, score: score))
        }

        // 1. Prefer stored occurrence if context score >= 0.5
        if comment.anchorOccurrence <= matches.count {
            let storedMatch = matches[comment.anchorOccurrence - 1]
            if storedMatch.score >= 0.5 {
                return storedMatch
            }
        }

        // 2. Fall back to best context match >= 0.5
        if let bestMatch = matches.filter({ $0.score >= 0.5 }).max(by: { $0.score < $1.score }) {
            return bestMatch
        }

        // 3. No good match - orphaned
        return nil
    }

    /// Find all occurrences of a substring in the document.
    private func findAllOccurrences(of substring: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: substring, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    /// Calculate context match score using LCS similarity.
    private func contextMatchScore(_ range: Range<String.Index>, context: AnchorContext, in text: String) -> Double {
        let contextLength = 30

        // Extract actual context around this occurrence
        let beforeStart = text.index(range.lowerBound, offsetBy: -contextLength, limitedBy: text.startIndex) ?? text.startIndex
        let afterEnd = text.index(range.upperBound, offsetBy: contextLength, limitedBy: text.endIndex) ?? text.endIndex

        let actualBefore = String(text[beforeStart..<range.lowerBound])
        let actualAfter = String(text[range.upperBound..<afterEnd])

        let beforeScore = lcsRatio(context.textBefore, actualBefore)
        let afterScore = lcsRatio(context.textAfter, actualAfter)

        return (beforeScore + afterScore) / 2.0
    }

    /// Calculate LCS similarity ratio between two strings.
    private func lcsRatio(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty && !b.isEmpty else {
            return a.isEmpty && b.isEmpty ? 1.0 : 0.0
        }
        let lcsLength = longestCommonSubsequence(a, b)
        return Double(lcsLength) / Double(max(a.count, b.count))
    }

    /// Standard LCS algorithm - returns length of longest common subsequence.
    private func longestCommonSubsequence(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var dp = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                if aChars[i - 1] == bChars[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        return dp[a.count][b.count]
    }

    // MARK: - Comment Queries

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

    // MARK: - Context Capture Helpers

    /// Capture context around a range for anchor recovery.
    static func captureContext(for range: Range<String.Index>, in text: String) -> AnchorContext {
        let contextLength = 30
        let beforeStart = text.index(range.lowerBound, offsetBy: -contextLength, limitedBy: text.startIndex) ?? text.startIndex
        let afterEnd = text.index(range.upperBound, offsetBy: contextLength, limitedBy: text.endIndex) ?? text.endIndex

        return AnchorContext(
            textBefore: String(text[beforeStart..<range.lowerBound]),
            textAfter: String(text[range.upperBound..<afterEnd])
        )
    }

    /// Find which occurrence index a given range represents.
    static func occurrenceIndex(of anchorText: String, at range: Range<String.Index>, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let foundRange = text.range(of: anchorText, range: searchStart..<text.endIndex) {
            count += 1
            if foundRange.lowerBound == range.lowerBound {
                return count
            }
            searchStart = foundRange.upperBound
        }
        return 1  // Default to first occurrence if not found
    }
}
