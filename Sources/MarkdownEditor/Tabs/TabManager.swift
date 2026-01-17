import Foundation

/// Manages open documents and tab state.
///
/// Implements `TabManaging` protocol from scaffolding.
/// Owns document instances and tracks which is active.
final class TabManager: TabManaging {

    /// Documents keyed by ID.
    private var documents: [UUID: DocumentModel] = [:]

    /// Tab order (document IDs in display order).
    private var tabOrder: [UUID] = []

    /// Currently active document ID.
    private(set) var activeDocumentId: UUID?

    /// Callback when active tab changes.
    var onActiveTabChanged: ((UUID?) -> Void)?

    /// Callback before closing a dirty document (for save prompts).
    /// Return true to proceed with close, false to cancel.
    var onCloseConfirmation: ((DocumentModel) -> Bool)?

    // MARK: - TabManaging

    var tabs: [TabInfo] {
        return tabOrder.compactMap { id in
            guard let doc = documents[id] else { return nil }
            return TabInfo(
                documentId: doc.id,
                title: doc.filePath?.lastPathComponent ?? "Untitled",
                isDirty: doc.isDirty,
                filePath: doc.filePath
            )
        }
    }

    func openDocument(_ document: DocumentModel) {
        // Check if already open
        if documents[document.id] != nil {
            activateTab(documentId: document.id)
            return
        }

        documents[document.id] = document
        tabOrder.append(document.id)
        activateTab(documentId: document.id)
    }

    func closeTab(documentId: UUID) -> Bool {
        guard let document = documents[documentId] else { return false }

        // Check if dirty and prompt for save
        if document.isDirty {
            if let confirmation = onCloseConfirmation {
                if !confirmation(document) {
                    return false  // User cancelled
                }
            }
        }

        // Remove from data structures
        documents.removeValue(forKey: documentId)
        tabOrder.removeAll { $0 == documentId }

        // Update active tab
        if activeDocumentId == documentId {
            activeDocumentId = tabOrder.last
            onActiveTabChanged?(activeDocumentId)
        }

        return true
    }

    func activateTab(documentId: UUID) {
        guard documents[documentId] != nil else { return }

        activeDocumentId = documentId
        onActiveTabChanged?(documentId)
    }

    // MARK: - Document Access

    /// Get document by ID.
    func document(for id: UUID) -> DocumentModel? {
        return documents[id]
    }

    /// Get the active document.
    var activeDocument: DocumentModel? {
        guard let id = activeDocumentId else { return nil }
        return documents[id]
    }

    // MARK: - File Operations

    /// Open document from file, reusing existing tab if already open.
    func openFile(at url: URL) throws -> DocumentModel {
        // Check if already open
        if let existing = documents.values.first(where: { $0.filePath == url }) {
            activateTab(documentId: existing.id)
            return existing
        }

        let document = try DocumentModel(contentsOf: url)
        openDocument(document)
        return document
    }

    /// Create new untitled document.
    func newDocument() -> DocumentModel {
        let document = DocumentModel()
        openDocument(document)
        return document
    }

    /// Close all tabs, prompting for unsaved changes.
    /// Returns true if all closed, false if user cancelled.
    func closeAll() -> Bool {
        let idsToClose = tabOrder
        for id in idsToClose {
            if !closeTab(documentId: id) {
                return false
            }
        }
        return true
    }
}
