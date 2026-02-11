import AppKit
import os.signpost

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

    /// Theme change observer token.
    private var themeObserver: NSObjectProtocol?

    /// Reentrancy guard for heading font application.
    private var isApplyingHeadingFonts = false

    /// Guard to prevent block context updates during display-only invalidations.
    private var isInvalidatingDisplay = false

    /// Guard to suppress textDidChange/textViewDidChangeSelection during init.
    /// `initializeAfterContentLoad()` handles the full init sequence; delegate callbacks
    /// firing before it runs are redundant and cause O(N) font passes to multiply.
    private var isInitializing = true

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

        // Clear any cursor restore position set during init
        // (willProcessEditing fires during setAttributedString and may set this incorrectly)
        document.cursorRestorePosition = nil
    }

    /// Initialize rendering state after content is loaded.
    /// Sets up block context, fonts, active paragraph, and forces fragment recreation.
    // internal for @testable access — used by test harness setText()
    func initializeAfterContentLoad() {
        let spid = OSSignpostID(log: Signposts.layout)
        os_signpost(.begin, log: Signposts.layout, name: Signposts.initAfterContentLoad, signpostID: spid)
        defer { os_signpost(.end, log: Signposts.layout, name: Signposts.initAfterContentLoad, signpostID: spid) }

        // Update block context FIRST so we know which paragraphs are code blocks
        PerfTimer.shared.measure("init.blockContext") {
            updateBlockContextFull()
        }

        // Apply fonts for all paragraph types so TextKit 2 calculates correct metrics (O(N) on load only)
        PerfTimer.shared.measure("init.applyFonts") {
            applyFontsToAllParagraphs()
        }

        // Set initial active paragraph to 0 (cursor starts at beginning)
        activeParagraphIndex = 0

        // Force layout fragment recreation
        PerfTimer.shared.measure("init.fragmentRecreation") {
            if let textContainer = layoutManager.textContainer {
                layoutManager.textContainer = nil
                layoutManager.textContainer = textContainer
            }
        }

        // Init complete — allow delegate callbacks to proceed normally
        isInitializing = false

        // Print timing summary after init completes (only for file-backed documents)
        if let filePath = document?.filePath {
            let docLabel = filePath.lastPathComponent
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PerfTimer.shared.printSummary(label: docLabel)
            }
        }
    }

    /// Update block context incrementally from the edited paragraph. O(K).
    /// Compares old vs new context and invalidates paragraphs whose code-block status changed.
    private func updateBlockContext() {
        let spid = OSSignpostID(log: Signposts.layout)
        os_signpost(.begin, log: Signposts.layout, name: Signposts.blockContextUpdate, signpostID: spid)
        defer { os_signpost(.end, log: Signposts.layout, name: Signposts.blockContextUpdate, signpostID: spid) }

        guard let text = textView.textStorage?.string else { return }
        let paragraphs = text.components(separatedBy: "\n")

        // Capture old block context before updating
        let oldBlockContext = layoutDelegate.blockContext

        // Get the edited paragraph index from cursor position
        if let location = cursorTextLocation,
           let editedIndex = document?.paragraphIndex(for: location) {
            // Incremental update from edit location
            layoutDelegate.updateBlockContextIncremental(afterEditAt: editedIndex, paragraphs: paragraphs)
        } else {
            // Fallback to full scan if we can't determine edit location
            layoutDelegate.updateBlockContext(paragraphs: paragraphs)
        }

        // Find paragraphs whose code-block status changed.
        // Note: paragraphsWithChangedCodeBlockStatus compares by index position, which is
        // unreliable after insertions/deletions shift paragraph indices. When any code block
        // boundary changes, reapply fonts to all paragraphs to ensure correctness.
        let newBlockContext = layoutDelegate.blockContext
        let affectedParagraphs = newBlockContext.paragraphsWithChangedCodeBlockStatus(
            comparedTo: oldBlockContext,
            paragraphCount: paragraphs.count
        )

        if !affectedParagraphs.isEmpty {
            applyFontsToAllParagraphs()
            invalidateParagraphsDisplay(affectedParagraphs)
        }
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
        // Allow text view to grow vertically, but constrain width for text wrapping
        textView.maxSize = NSSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude)
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
        textView.allowsUndo = true

        // Apply initial theme colors and observe changes
        applyThemeColors()
        themeObserver = ThemeManager.shared.observeChanges { [weak self] in
            self?.applyThemeColors()
        }
    }

    private func applyThemeColors() {
        let colors = ThemeManager.shared.colors
        textView.backgroundColor = colors.shellBackground
    }

    // MARK: - Token Provider

    /// Set the token provider (when Parser module is ready).
    func setTokenProvider(_ provider: TokenProviding) {
        layoutDelegate.tokenProvider = provider
    }

    // MARK: - Font Attribute Styling

    /// Total indent for list items - must match DocumentModel.listIndent and MarkdownLayoutFragment.listIndent
    private let listIndent: CGFloat = 20.0

    /// Apply fonts to ALL paragraphs based on their type. O(N) - only for initialization.
    /// Handles headings, code blocks, blockquotes, and lists.
    private func applyFontsToAllParagraphs() {
        guard !isApplyingHeadingFonts else { return }
        guard document != nil,
              let textStorage = textView.textStorage else { return }

        isApplyingHeadingFonts = true
        defer { isApplyingHeadingFonts = false }

        let text = textStorage.string
        guard !text.isEmpty else { return }

        let theme = SyntaxTheme.default
        let blockContext = layoutDelegate.blockContext

        textStorage.beginEditing()

        // Reset to body font
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttribute(.font, value: theme.bodyFont, range: fullRange)

        // Apply fonts based on paragraph type
        let paragraphs = text.components(separatedBy: "\n")
        var offset = 0

        for (index, para) in paragraphs.enumerated() {
            let range = NSRange(location: offset, length: para.count)
            guard range.location + range.length <= textStorage.length else {
                offset += para.count + 1
                continue
            }

            // Check if this paragraph is part of a code block
            let isCodeBlockContent = blockContext.isInsideFencedCodeBlock(paragraphIndex: index).0
            let isOpeningFence = blockContext.isOpeningFence(paragraphIndex: index).0
            let isClosingFence = blockContext.isClosingFence(paragraphIndex: index)

            if isCodeBlockContent || isOpeningFence || isClosingFence {
                // Code block: apply monospace font
                textStorage.addAttribute(.font, value: theme.codeFont, range: range)
            } else {
                // Parse for other block-level elements
                let tokens = layoutDelegate.tokenProvider.parse(para)

                var isBlockElement = false
                for token in tokens {
                    switch token.element {
                    case .heading(let level):
                        let font = theme.headingFonts[level] ?? theme.bodyFont
                        textStorage.addAttribute(.font, value: font, range: range)
                        isBlockElement = true

                    case .blockquote:
                        textStorage.addAttribute(.font, value: theme.italicFont, range: range)
                        // Apply paragraph style for blockquotes (matches DocumentModel.willProcessEditing)
                        let blockquoteStyle = NSMutableParagraphStyle()
                        blockquoteStyle.headIndent = 20.0  // barSpacing + contentIndent
                        blockquoteStyle.firstLineHeadIndent = 0
                        textStorage.addAttribute(.paragraphStyle, value: blockquoteStyle, range: range)
                        isBlockElement = true

                    case .unorderedListItem, .orderedListItem:
                        // Lists use body font (already set), but apply paragraph style for indent
                        // This must match DocumentModel.willProcessEditing for cursor alignment
                        let listStyle = NSMutableParagraphStyle()
                        listStyle.firstLineHeadIndent = listIndent
                        listStyle.headIndent = listIndent
                        textStorage.addAttribute(.paragraphStyle, value: listStyle, range: range)
                        isBlockElement = false  // Allow inline formatting

                    default:
                        break
                    }

                    if isBlockElement { break }
                }

                // Apply inline formatting fonts for cursor accuracy (body paragraphs and lists)
                if !isBlockElement {
                    theme.applyInlineFormattingFonts(to: textStorage, tokens: tokens, paragraphOffset: offset)
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
        let spid = OSSignpostID(log: Signposts.layout)
        os_signpost(.begin, log: Signposts.layout, name: Signposts.activeParagraphSwitch, signpostID: spid)
        defer { os_signpost(.end, log: Signposts.layout, name: Signposts.activeParagraphSwitch, signpostID: spid) }

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
        let spid = OSSignpostID(log: Signposts.layout)
        os_signpost(.begin, log: Signposts.layout, name: Signposts.invalidateParagraph, signpostID: spid, "para=%d", index ?? -1)
        defer { os_signpost(.end, log: Signposts.layout, name: Signposts.invalidateParagraph, signpostID: spid) }

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
        guard !isInitializing else { return }
        handleSelectionChange()
    }

    func textDidChange(_ notification: Notification) {
        // Skip during init — initializeAfterContentLoad handles the full sequence
        guard !isInitializing else { return }
        // Skip if this is just a display invalidation, not an actual text change
        guard !isInvalidatingDisplay else { return }

        let spid = OSSignpostID(log: Signposts.editing)
        os_signpost(.begin, log: Signposts.editing, name: Signposts.textDidChange, signpostID: spid)

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

        os_signpost(.end, log: Signposts.editing, name: Signposts.textDidChange, signpostID: spid)
    }
}
