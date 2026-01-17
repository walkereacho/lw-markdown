import AppKit

/// Errors that can occur during document operations.
enum DocumentError: LocalizedError {
    case noFilePath
    case encodingError

    var errorDescription: String? {
        switch self {
        case .noFilePath:
            return "Document has no file path. Use Save As."
        case .encodingError:
            return "Could not encode document as UTF-8."
        }
    }
}

/// Document model — owns content and provides text access.
///
/// ## Critical Architecture Rule
/// `contentStorage` contains RAW TEXT ONLY. Never add rendering attributes
/// (colors, fonts for formatting) to the content storage. Rendering happens
/// at the layout layer via `NSTextLayoutFragment` subclasses.
///
/// This design enables:
/// - Clean undo (only content changes recorded)
/// - Multiple panes with different "active paragraph" states
/// - Safe external file reload
final class DocumentModel {

    /// Unique identifier for this document.
    let id: UUID

    /// File path, if saved.
    var filePath: URL?

    /// Source of truth for document text.
    /// Contains raw Markdown — NEVER rendering attributes.
    let contentStorage: NSTextContentStorage

    /// Undo manager for content changes.
    let undoManager: UndoManager

    /// Paragraph index cache for O(log N) lookups.
    private(set) lazy var paragraphCache: ParagraphIndexCache = {
        ParagraphIndexCache(contentStorage: contentStorage)
    }()

    /// Document revision counter — incremented on every edit.
    private(set) var revision: UInt64 = 0

    /// Whether document has unsaved changes.
    var isDirty: Bool = false

    /// Last save timestamp.
    var lastSavedAt: Date?

    // MARK: - Initialization

    /// Create a new empty document.
    init() {
        self.id = UUID()
        self.contentStorage = NSTextContentStorage()
        self.undoManager = UndoManager()
    }

    /// Load document from file.
    init(contentsOf url: URL) throws {
        self.id = UUID()
        self.filePath = url
        self.contentStorage = NSTextContentStorage()
        self.undoManager = UndoManager()

        let text = try String(contentsOf: url, encoding: .utf8)

        // Set text as plain attributed string — no formatting attributes
        contentStorage.attributedString = NSAttributedString(string: text)

        // Build paragraph cache
        paragraphCache.rebuildFull()
    }

    // MARK: - Text Access

    /// Full document as plain string.
    /// Use sparingly — prefer paragraph access for performance.
    func fullString() -> String {
        guard let attrString = contentStorage.attributedString else { return "" }
        return attrString.string
    }

    /// Number of paragraphs in document.
    var paragraphCount: Int {
        paragraphCache.count
    }

    /// Get text of a specific paragraph.
    func paragraph(at index: Int) -> String? {
        guard let range = paragraphCache.paragraphRange(at: index) else { return nil }
        return substringForRange(range)
    }

    /// Get the text range for a paragraph.
    func paragraphRange(at index: Int) -> NSTextRange? {
        paragraphCache.paragraphRange(at: index)
    }

    /// Get paragraph index for a text location.
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        paragraphCache.paragraphIndex(for: location)
    }

    // MARK: - Save

    /// Save document to its file path.
    func save() throws {
        guard let url = filePath else {
            throw DocumentError.noFilePath
        }
        let content = fullString()
        try content.write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
        lastSavedAt = Date()
    }

    // MARK: - Edit Notifications

    /// Called when content changes. Updates caches.
    func contentDidChange(in editedRange: NSTextRange, changeInLength delta: Int) {
        revision += 1
        isDirty = true
        paragraphCache.didProcessEditing(in: editedRange, changeInLength: delta)
    }

    // MARK: - Private Helpers

    private func substringForRange(_ range: NSTextRange) -> String? {
        guard let storage = contentStorage.attributedString else { return nil }

        let start = contentStorage.offset(from: contentStorage.documentRange.location, to: range.location)
        let end = contentStorage.offset(from: contentStorage.documentRange.location, to: range.endLocation)

        guard start >= 0, end <= storage.length, start < end else { return nil }

        let nsRange = NSRange(location: start, length: end - start)
        return storage.attributedSubstring(from: nsRange).string
    }
}
