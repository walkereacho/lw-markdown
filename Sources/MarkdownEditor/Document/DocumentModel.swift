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

    /// Apply fonts BEFORE TextKit 2 creates layout fragments.
    /// This ensures fragments are created with correct line height metrics.
    ///
    /// Handles: headings (h1-h6), code blocks (fenced with ``` or ~~~)
    ///
    /// Strategy:
    /// - If paragraph TYPE changes (body↔heading↔code), apply font to whole paragraph
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

        // Check if this paragraph is inside a code block
        let codeBlockStatus = detectCodeBlockStatus(at: paragraphRange.location, in: text)

        // Parse to determine current paragraph type (only if not in code block)
        let tokens = MarkdownParser.shared.parse(trimmedText)

        // Extract element types from tokens
        let currentHeadingLevel: Int? = codeBlockStatus == .notInCodeBlock ? tokens.compactMap { token -> Int? in
            if case .heading(let level) = token.element { return level }
            return nil
        }.first : nil

        let blockquoteDepth: Int? = codeBlockStatus == .notInCodeBlock ? tokens.compactMap { token -> Int? in
            if case .blockquote = token.element { return token.nestingDepth }
            return nil
        }.first : nil

        let unorderedListDepth: Int? = codeBlockStatus == .notInCodeBlock ? tokens.compactMap { token -> Int? in
            if case .unorderedListItem = token.element { return token.nestingDepth }
            return nil
        }.first : nil

        let orderedListDepth: Int? = codeBlockStatus == .notInCodeBlock ? tokens.compactMap { token -> Int? in
            if case .orderedListItem = token.element { return token.nestingDepth }
            return nil
        }.first : nil

        // Determine current type and target font
        let currentType: ParagraphType
        let targetFont: NSFont

        if codeBlockStatus != .notInCodeBlock {
            currentType = .codeBlock
            targetFont = theme.codeFont
        } else if let level = currentHeadingLevel {
            currentType = .heading(level)
            targetFont = theme.headingFonts[level] ?? theme.bodyFont
        } else if let depth = blockquoteDepth {
            currentType = .blockquote
            targetFont = theme.italicFont
            _ = depth // Depth used for indentation if needed later
        } else if let depth = unorderedListDepth {
            currentType = .unorderedList(depth: depth)
            targetFont = theme.bodyFont
        } else if let depth = orderedListDepth {
            currentType = .orderedList(depth: depth)
            targetFont = theme.bodyFont
        } else {
            currentType = .body
            targetFont = theme.bodyFont
        }

        // Detect previous paragraph type
        let existingFont = textStorage.attribute(.font, at: paragraphRange.location, effectiveRange: nil) as? NSFont
        let existingStyle = textStorage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
        let previousType = detectPreviousParagraphType(font: existingFont, paragraphStyle: existingStyle, theme: theme)

        // Check if paragraph TYPE changed
        let typeChanged = currentType != previousType

        // Calculate attribute range (excluding trailing newline)
        var attributeRange = paragraphRange
        if paragraphText.hasSuffix("\n") {
            attributeRange.length -= 1
        }
        guard attributeRange.length > 0 else { return }

        // Always apply paragraph style for lists (needed for cursor positioning)
        // Do this before checking typeChanged so it applies on every edit
        if let paragraphStyle = paragraphStyleForType(currentType) {
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: attributeRange)
        } else {
            // Remove paragraph style for non-indented elements
            textStorage.removeAttribute(.paragraphStyle, range: attributeRange)
        }

        // Calculate where cursor SHOULD be after edit completes
        // For insertions: after the inserted text
        // For deletions (length == 0): at the deletion point
        let targetCursorPosition = editedRange.location + editedRange.length

        if typeChanged {
            // Type changed: apply font to entire paragraph
            textStorage.addAttribute(.font, value: targetFont, range: attributeRange)
            cursorRestorePosition = targetCursorPosition
        } else {
            // Type unchanged: only apply font to edited range
            // For deletions (length == 0), we still need to set restore position
            // because other attribute changes may move the cursor
            cursorRestorePosition = targetCursorPosition

            guard editedRange.length > 0, editedRange.location < textStorage.length else { return }
            let safeRange = NSRange(
                location: editedRange.location,
                length: min(editedRange.length, textStorage.length - editedRange.location)
            )
            textStorage.addAttribute(.font, value: targetFont, range: safeRange)
        }

        // For body paragraphs, also apply inline formatting fonts for cursor accuracy
        // This ensures TextKit 2's layout matches our rendering
        if currentType == .body {
            // Applying fonts to token ranges can move cursor; remember position to restore
            cursorRestorePosition = editedRange.location + editedRange.length
            theme.applyInlineFormattingFonts(to: textStorage, tokens: tokens, paragraphOffset: paragraphRange.location)
        }
    }

    /// Total indent for list items - must match MarkdownLayoutFragment.listIndent
    private let listIndent: CGFloat = 20.0

    /// Create paragraph style for indented element types.
    /// For lists, we add the total indent so TextKit 2 cursor positioning matches rendering.
    private func paragraphStyleForType(_ type: ParagraphType) -> NSParagraphStyle? {
        let style = NSMutableParagraphStyle()

        switch type {
        case .unorderedList, .orderedList:
            // Add list indent to match rendering layer
            style.firstLineHeadIndent = listIndent
            style.headIndent = listIndent
            return style

        case .blockquote:
            // Blockquotes have vertical bar + indent
            let barSpacing: CGFloat = 12.0
            let contentIndent: CGFloat = 8.0
            style.headIndent = barSpacing + contentIndent
            style.firstLineHeadIndent = 0
            return style

        default:
            return nil
        }
    }

    // MARK: - Code Block Detection

    private enum CodeBlockStatus {
        case notInCodeBlock
        case openingFence
        case insideCodeBlock
        case closingFence
    }

    private enum ParagraphType: Equatable {
        case body
        case heading(Int)
        case codeBlock
        case blockquote
        case unorderedList(depth: Int)
        case orderedList(depth: Int)
    }

    /// Detect if the given character offset is inside a code block.
    /// Scans from document start to determine fence state.
    private func detectCodeBlockStatus(at offset: Int, in text: String) -> CodeBlockStatus {
        let paragraphs = text.components(separatedBy: "\n")

        // Find which paragraph index contains this offset
        var currentOffset = 0
        var targetParagraphIndex = 0
        for (i, para) in paragraphs.enumerated() {
            let paraLength = para.count + 1 // +1 for newline
            if currentOffset + paraLength > offset {
                targetParagraphIndex = i
                break
            }
            currentOffset += paraLength
        }

        // Scan paragraphs to determine code block state
        var inCodeBlock = false

        for i in 0..<paragraphs.count {
            let trimmed = paragraphs[i].trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")

            if i == targetParagraphIndex {
                // This is the paragraph we're checking
                if isFence {
                    return inCodeBlock ? .closingFence : .openingFence
                } else {
                    return inCodeBlock ? .insideCodeBlock : .notInCodeBlock
                }
            }

            // Update state for next iteration
            if isFence {
                inCodeBlock = !inCodeBlock
            }
        }

        return .notInCodeBlock
    }

    /// Detect previous paragraph type from its font and paragraph style.
    private func detectPreviousParagraphType(font: NSFont?, paragraphStyle: NSParagraphStyle?, theme: SyntaxTheme) -> ParagraphType {
        // Check paragraph style for element detection
        if let style = paragraphStyle, style.headIndent > 0 {
            // Check for list pattern (listIndent = 20)
            if style.headIndent == listIndent && style.firstLineHeadIndent == listIndent {
                // Could be either ordered or unordered - return unordered as default
                // The exact type will be determined by parsing anyway
                return .unorderedList(depth: 1)
            }
            // Check for blockquote pattern (barSpacing + contentIndent = 20)
            // Note: blockquote uses headIndent=20 but firstLineHeadIndent=0, so it won't match list
            if style.headIndent == 20.0 && style.firstLineHeadIndent == 0 {
                return .blockquote
            }
        }

        guard let font = font else { return .body }

        // Check if it's a heading font
        for (level, headingFont) in theme.headingFonts {
            if font == headingFont { return .heading(level) }
        }

        // Check if it's the code font
        if font == theme.codeFont { return .codeBlock }

        // Check if it's italic font (blockquote)
        if font == theme.italicFont { return .blockquote }

        return .body
    }
}
