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
/// **Exception:** Font attributes ARE applied to storage for heading lines.
/// This is required for TextKit 2 to calculate correct cursor metrics and
/// line heights. These fonts are applied in `willProcessEditing` BEFORE
/// layout fragments are created, ensuring correct metrics from the start.
///
/// This design enables:
/// - Clean undo (only content changes recorded)
/// - Multiple panes with different "active paragraph" states
/// - Safe external file reload
///
/// ## Initialization Order
/// When loading from file, content is NOT applied until `applyPendingContent()`
/// is called. This ensures the layout manager is connected first, which is
/// required for proper TextKit 2 text element enumeration and editing.
final class DocumentModel: NSObject, NSTextStorageDelegate {

    /// Unique identifier for this document.
    let id: UUID

    /// File path, if saved.
    var filePath: URL?

    /// Source of truth for document text.
    /// Contains raw Markdown — NEVER rendering attributes.
    let contentStorage: NSTextContentStorage

    /// Backing text storage for NSTextView editing compatibility.
    /// NSTextContentStorage needs this for NSTextView to properly edit content.
    let textStorage: NSTextStorage

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

    /// Content loaded from file, waiting to be applied after layout is ready.
    private var pendingContent: String?

    /// Cursor position to restore after a paragraph type change.
    /// Set in `willProcessEditing` when type changes, cleared after restoration.
    /// The position is where cursor SHOULD be after the edit completes.
    var cursorRestorePosition: Int?

    // MARK: - Initialization

    /// Create a new empty document.
    override init() {
        self.id = UUID()
        self.textStorage = NSTextStorage()
        self.contentStorage = NSTextContentStorage()
        self.contentStorage.textStorage = textStorage
        self.undoManager = UndoManager()
        super.init()
        self.textStorage.delegate = self
    }

    /// Load document from file.
    /// Note: Content is stored but not applied until `applyPendingContent()` is called.
    /// This ensures proper TextKit 2 initialization order.
    init(contentsOf url: URL) throws {
        // Read file content first (can throw)
        let content = try String(contentsOf: url, encoding: .utf8)

        self.id = UUID()
        self.filePath = url
        self.textStorage = NSTextStorage()
        self.contentStorage = NSTextContentStorage()
        self.contentStorage.textStorage = textStorage
        self.undoManager = UndoManager()
        self.pendingContent = content
        super.init()
        self.textStorage.delegate = self
    }

    /// Apply pending content after layout manager is connected.
    /// Must be called after `contentStorage.addTextLayoutManager()`.
    func applyPendingContent() {
        guard let text = pendingContent else { return }
        pendingContent = nil

        // Set content via textStorage so NSTextView can access it
        textStorage.setAttributedString(NSAttributedString(string: text))

        // Build paragraph cache now that text elements can be enumerated
        paragraphCache.rebuildFull()
    }

    /// Whether there is pending content waiting to be applied.
    var hasPendingContent: Bool {
        pendingContent != nil
    }

    // MARK: - Text Access

    /// Full document as plain string.
    /// Use sparingly — prefer paragraph access for performance.
    func fullString() -> String {
        // If content is pending (not yet applied), return that
        if let pending = pendingContent {
            return pending
        }
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

    // MARK: - NSTextStorageDelegate

    /// Apply heading fonts BEFORE TextKit 2 creates layout fragments.
    /// This ensures fragments are created with correct line height metrics.
    ///
    /// Strategy:
    /// - If paragraph TYPE changes (body↔heading), apply font to whole paragraph
    /// - If type stays same, only apply to edited range (avoids cursor jump)
    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Only process if characters changed (not just attributes)
        guard editedMask.contains(.editedCharacters) else { return }

        let text = textStorage.string
        guard !text.isEmpty else { return }

        let theme = SyntaxTheme.default

        // Get the paragraph range to determine what type of line this is
        let paragraphRange = (text as NSString).paragraphRange(for: editedRange)
        guard paragraphRange.length > 0 else { return }

        // Get paragraph text (without trailing newline for parsing)
        let paragraphText = (text as NSString).substring(with: paragraphRange)
        let trimmedText = paragraphText.trimmingCharacters(in: .newlines)

        // Parse to determine current paragraph type
        let tokens = MarkdownParser.shared.parse(trimmedText)
        let currentHeadingLevel = tokens.compactMap { token -> Int? in
            if case .heading(let level) = token.element { return level }
            return nil
        }.first

        // Determine target font based on current paragraph type
        let targetFont: NSFont
        if let level = currentHeadingLevel {
            targetFont = theme.headingFonts[level] ?? theme.bodyFont
        } else {
            targetFont = theme.bodyFont
        }

        // Detect previous paragraph type by checking existing font at paragraph start
        let existingFont = textStorage.attribute(.font, at: paragraphRange.location, effectiveRange: nil) as? NSFont
        let previousHeadingLevel: Int? = {
            guard let font = existingFont else { return nil }
            for (level, headingFont) in theme.headingFonts {
                if font == headingFont { return level }
            }
            return nil  // Was body text (or unknown font)
        }()

        // Check if paragraph TYPE changed
        let typeChanged = currentHeadingLevel != previousHeadingLevel

        if typeChanged {
            // Type changed: apply font to entire paragraph (excluding trailing newline)
            var attributeRange = paragraphRange
            if paragraphText.hasSuffix("\n") {
                attributeRange.length -= 1
            }
            guard attributeRange.length > 0 else { return }
            textStorage.addAttribute(.font, value: targetFont, range: attributeRange)

            // Remember where cursor SHOULD be after edit completes
            // (addAttribute moves cursor to end of range, so we need to restore it)
            cursorRestorePosition = editedRange.location + editedRange.length
        } else {
            // Type unchanged: only apply to edited range (avoids cursor jump)
            guard editedRange.length > 0, editedRange.location < textStorage.length else { return }
            let safeRange = NSRange(
                location: editedRange.location,
                length: min(editedRange.length, textStorage.length - editedRange.location)
            )
            textStorage.addAttribute(.font, value: targetFont, range: safeRange)
        }
    }
}
