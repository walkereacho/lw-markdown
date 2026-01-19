import AppKit

/// Controller for a single editor pane.
///
/// ## Responsibilities
/// - Owns TextKit 2 layout infrastructure for this pane
/// - Tracks PANE-LOCAL active paragraph (cursor position)
/// - Triggers layout invalidation when active paragraph changes
///
/// ## Multi-Pane Architecture
/// Each pane has its own:
/// - `NSTextLayoutManager`
/// - `MarkdownLayoutManagerDelegate`
/// - `activeParagraphIndex`
///
/// All panes share the same `NSTextContentStorage` from `DocumentModel`.
final class PaneController: NSObject {

    /// Unique identifier for this pane.
    let id: UUID

    /// Document being edited (shared with other panes).
    weak var document: DocumentModel?

    /// The text view for this pane.
    let textView: NSTextView

    /// Layout manager (one per pane).
    let layoutManager: NSTextLayoutManager

    /// Text container defining geometry.
    let textContainer: NSTextContainer

    /// Layout delegate providing custom fragments.
    private(set) var layoutDelegate: MarkdownLayoutManagerDelegate

    /// PANE-LOCAL active paragraph index.
    /// Different panes can have cursor in different paragraphs.
    private(set) var activeParagraphIndex: Int?

    /// Debounce timer for cursor movement.
    private var cursorDebounceTimer: DispatchWorkItem?
    private let cursorDebounceInterval: TimeInterval = 0.016  // ~1 frame at 60fps

    /// Reentrancy guard for heading font application.
    private var isApplyingHeadingFonts = false

    /// Guard to prevent block context updates during display-only invalidations.
    private var isInvalidatingDisplay = false

    // MARK: - Initialization

    init(document: DocumentModel, frame: NSRect) {
        self.id = UUID()
        self.document = document

        // Create layout infrastructure
        self.layoutManager = NSTextLayoutManager()
        // Text container needs unlimited height for scrolling to work
        let containerSize = NSSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude)
        self.textContainer = NSTextContainer(size: containerSize)
        self.layoutDelegate = MarkdownLayoutManagerDelegate()

        // Configure
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.textContainer = textContainer
        layoutManager.delegate = layoutDelegate

        // Connect to document's content storage
        document.contentStorage.addTextLayoutManager(layoutManager)

        // Create text view
        self.textView = NSTextView(frame: frame, textContainer: textContainer)

        super.init()

        // Wire up delegate references
        layoutDelegate.paneController = self
        textView.delegate = self

        // Inject parser for live Markdown rendering
        layoutDelegate.tokenProvider = MarkdownParser.shared

        // Configure text view
        configureTextView()

        // Apply pending content now that layout infrastructure is ready
        document.applyPendingContent()

        // Initialize rendering state after content is loaded
        initializeAfterContentLoad()
    }

    /// Initialize rendering state after content is loaded.
    /// Sets up heading fonts and active paragraph for correct initial display.
    private func initializeAfterContentLoad() {
        // Apply heading fonts so TextKit 2 calculates correct metrics (O(N) on load only)
        applyHeadingFontsToAllParagraphs()

        // Update block context for fenced code blocks (O(N) on load only)
        updateBlockContextFull()

        // Set initial active paragraph to 0 (cursor starts at beginning)
        activeParagraphIndex = 0

        // Force layout fragment recreation
        if let textContainer = layoutManager.textContainer {
            layoutManager.textContainer = nil
            layoutManager.textContainer = textContainer
        }
    }

    /// Update block context incrementally from the edited paragraph. O(K).
    /// Compares old vs new context and invalidates paragraphs whose code-block status changed.
    private func updateBlockContext() {
        guard let text = textView.textStorage?.string else { return }
        let paragraphs = text.components(separatedBy: "\n")

        // Capture old block context before updating
        let oldBlockContext = layoutDelegate.blockContext

        // Get the edited paragraph index from cursor position
        guard let location = cursorTextLocation,
              let editedIndex = document?.paragraphIndex(for: location) else {
            // Fallback to full scan if we can't determine edit location
            layoutDelegate.updateBlockContext(paragraphs: paragraphs)
            return
        }

        // Update block context
        layoutDelegate.updateBlockContextIncremental(afterEditAt: editedIndex, paragraphs: paragraphs)

        // Find paragraphs whose code-block status changed
        let newBlockContext = layoutDelegate.blockContext
        var affectedParagraphs = newBlockContext.paragraphsWithChangedCodeBlockStatus(
            comparedTo: oldBlockContext,
            paragraphCount: paragraphs.count
        )

        // Exclude the edited paragraph (TextKit 2 already handles it)
        affectedParagraphs.remove(editedIndex)

        // Invalidate affected paragraphs to force fragment recreation
        invalidateParagraphsDisplay(affectedParagraphs)
    }

    /// Update block context by scanning all paragraphs. O(N) - for initialization only.
    private func updateBlockContextFull() {
        guard let text = textView.textStorage?.string else { return }
        let paragraphs = text.components(separatedBy: "\n")
        layoutDelegate.updateBlockContext(paragraphs: paragraphs)
    }

    deinit {
        document?.contentStorage.removeTextLayoutManager(layoutManager)
    }

    private func configureTextView() {
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // Allow text view to grow to fit content
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.textContainerInset = NSSize(width: 20, height: 20)

        // Explicitly enable editing and selection
        textView.isEditable = true
        textView.isSelectable = true

        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.allowsUndo = true
    }

    // MARK: - Token Provider

    /// Set the token provider (when Parser module is ready).
    func setTokenProvider(_ provider: TokenProviding) {
        layoutDelegate.tokenProvider = provider
    }

    // MARK: - Font Attribute Styling

    /// Apply heading fonts to ALL paragraphs. O(N) - only for initialization.
    private func applyHeadingFontsToAllParagraphs() {
        guard !isApplyingHeadingFonts else { return }
        guard document != nil,
              let textStorage = textView.textStorage else { return }

        isApplyingHeadingFonts = true
        defer { isApplyingHeadingFonts = false }

        let text = textStorage.string
        guard !text.isEmpty else { return }

        let theme = SyntaxTheme.default

        textStorage.beginEditing()

        // Reset to body font
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttribute(.font, value: theme.bodyFont, range: fullRange)

        // Apply heading fonts
        let paragraphs = text.components(separatedBy: "\n")
        var offset = 0

        for para in paragraphs {
            let tokens = layoutDelegate.tokenProvider.parse(para)
            for token in tokens {
                if case .heading(let level) = token.element {
                    let font = theme.headingFonts[level] ?? theme.bodyFont
                    let range = NSRange(location: offset, length: para.count)
                    if range.location + range.length <= textStorage.length {
                        textStorage.addAttribute(.font, value: font, range: range)
                    }
                }
            }
            offset += para.count + 1
        }

        textStorage.endEditing()
    }

    // MARK: - Active Paragraph

    /// Check if a paragraph is active in THIS pane.
    func isActiveParagraph(at index: Int) -> Bool {
        return index == activeParagraphIndex
    }

    // MARK: - Code Block Info (queried at draw time)

    /// Get code block info for a paragraph at draw time.
    /// Returns nil if paragraph is not part of a fenced code block.
    func codeBlockInfo(at paragraphIndex: Int) -> MarkdownLayoutFragment.CodeBlockInfo? {
        let blockContext = layoutDelegate.blockContext

        let (isInside, language) = blockContext.isInsideFencedCodeBlock(paragraphIndex: paragraphIndex)
        if isInside {
            return .content(language: language)
        }

        let (isOpening, openingLanguage) = blockContext.isOpeningFence(paragraphIndex: paragraphIndex)
        if isOpening {
            return .openingFence(language: openingLanguage)
        }

        if blockContext.isClosingFence(paragraphIndex: paragraphIndex) {
            return .closingFence
        }

        return nil
    }

    /// Get current cursor location.
    var cursorTextLocation: NSTextLocation? {
        guard let selection = layoutManager.textSelections.first,
              let range = selection.textRanges.first else { return nil }
        return range.location
    }

    /// Handle selection change — debounce and update active paragraph.
    func handleSelectionChange() {
        cursorDebounceTimer?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateActiveParagraph()
        }
        cursorDebounceTimer = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + cursorDebounceInterval,
            execute: workItem
        )
    }

    private func updateActiveParagraph() {
        guard let document = document,
              let location = cursorTextLocation else { return }

        let newIndex = document.paragraphIndex(for: location)

        // Only update if changed
        guard newIndex != activeParagraphIndex else { return }

        let oldIndex = activeParagraphIndex
        activeParagraphIndex = newIndex

        // Invalidate display for only the affected paragraphs (old and new active)
        invalidateParagraphDisplay(at: oldIndex)
        invalidateParagraphDisplay(at: newIndex)
    }

    /// Invalidate layout for a specific paragraph to force fragment recreation.
    /// Uses content storage notification to trigger delegate callback.
    private func invalidateParagraphDisplay(at index: Int?) {
        guard let index = index,
              let document = document,
              let range = document.paragraphRange(at: index) else { return }

        // Convert NSTextRange to NSRange for the content storage
        let contentStorage = document.contentStorage
        let startOffset = contentStorage.offset(from: contentStorage.documentRange.location, to: range.location)
        let endOffset = contentStorage.offset(from: contentStorage.documentRange.location, to: range.endLocation)
        let nsRange = NSRange(location: startOffset, length: endOffset - startOffset)

        // Trigger layout invalidation by notifying the content storage of a "change"
        // This is a zero-length edit that forces re-layout without modifying content
        isInvalidatingDisplay = true
        defer { isInvalidatingDisplay = false }
        contentStorage.performEditingTransaction {
            contentStorage.textStorage?.edited(.editedAttributes, range: nsRange, changeInLength: 0)
        }
    }

    /// Invalidate layout for multiple paragraphs to force fragment recreation.
    /// Used when code block boundaries change and multiple paragraphs need refreshing.
    private func invalidateParagraphsDisplay(_ indices: Set<Int>) {
        guard !indices.isEmpty,
              let document = document else { return }

        let contentStorage = document.contentStorage

        isInvalidatingDisplay = true
        defer { isInvalidatingDisplay = false }
        contentStorage.performEditingTransaction {
            for index in indices {
                guard let range = document.paragraphRange(at: index) else { continue }

                let startOffset = contentStorage.offset(from: contentStorage.documentRange.location, to: range.location)
                let endOffset = contentStorage.offset(from: contentStorage.documentRange.location, to: range.endLocation)
                let nsRange = NSRange(location: startOffset, length: endOffset - startOffset)

                contentStorage.textStorage?.edited(.editedAttributes, range: nsRange, changeInLength: 0)
            }
        }
    }

}

// MARK: - NSTextViewDelegate

extension PaneController: NSTextViewDelegate {

    func textViewDidChangeSelection(_ notification: Notification) {
        handleSelectionChange()
    }

    func textDidChange(_ notification: Notification) {
        // Skip if this is just a display invalidation, not an actual text change
        guard !isInvalidatingDisplay else { return }

        // Notify document of content change for cache invalidation
        let range = document?.contentStorage.documentRange ?? layoutManager.documentRange
        document?.contentDidChange(in: range, changeInLength: 0)

        // Note: Heading fonts are now applied in DocumentModel.willProcessEditing
        // BEFORE TextKit 2 creates layout fragments, ensuring correct metrics.

        // Restore cursor position if a paragraph type change moved it
        if let restorePosition = document?.cursorRestorePosition {
            document?.cursorRestorePosition = nil  // Clear immediately to avoid loops
            let safePosition = min(restorePosition, textView.string.count)
            textView.setSelectedRange(NSRange(location: safePosition, length: 0))
        }

        // Update block context for fenced code blocks
        updateBlockContext()

        // Scroll to keep cursor visible
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}
