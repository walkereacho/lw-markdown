import Foundation

/// Represents a document tab.
struct TabInfo {
    let documentId: UUID
    let title: String
    let isDirty: Bool
    let filePath: URL?
}

/// Protocol for tab managers (implemented by Tabs module).
///
/// The tabs module manages:
/// - Multiple open documents
/// - Tab bar UI
/// - Document lifecycle (open, close, save prompts)
/// - Dirty state tracking
protocol TabManaging {
    /// Currently active tab's document ID.
    var activeDocumentId: UUID? { get }

    /// All open tabs.
    var tabs: [TabInfo] { get }

    /// Open a document in a new tab.
    func openDocument(_ document: DocumentModel)

    /// Close a tab, prompting to save if dirty.
    /// - Returns: true if closed, false if user cancelled.
    func closeTab(documentId: UUID) -> Bool

    /// Switch to a tab.
    func activateTab(documentId: UUID)

    /// Callback when active tab changes.
    var onActiveTabChanged: ((UUID?) -> Void)? { get set }
}
