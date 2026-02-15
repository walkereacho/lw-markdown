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

    /// Paragraph count at last block context update, for detecting insertions/deletions.
    private var lastBlockContextParagraphCount = 0

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
        defer { isInitializing = false }

        // Update block context FIRST so we know which paragraphs are code blocks
        var paragraphs: [String] = []
        PerfTimer.shared.measure("init.blockContext") {
            paragraphs = updateBlockContextFull()
        }
        // Sync block context to document for O(1) lookups in willProcessEditing
        document?.blockContext = layoutDelegate.blockContext
        lastBlockContextParagraphCount = document?.paragraphCount ?? 0

        // Apply fonts for all paragraph types so TextKit 2 calculates correct metrics (O(N) on load only)
        PerfTimer.shared.measure("init.applyFonts") {
            applyFontsToAllParagraphs(paragraphs: paragraphs)
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
    ///
    /// Fast path: if the edited paragraph is not a fence and wasn't a fence before,
    /// skip the entire function (no code block boundaries can change). O(1).
    private func updateBlockContext() {
        let spid = OSSignpostID(log: Signposts.layout)
        os_signpost(.begin, log: Signposts.layout, name: Signposts.blockContextUpdate, signpostID: spid)
        defer { os_signpost(.end, log: Signposts.layout, name: Signposts.blockContextUpdate, signpostID: spid) }

        guard let text = textView.textStorage?.string else { return }

        // Early exit for non-fence edits — O(1) check avoids O(N) string split.
        // Conditions that require a full update:
        // 1. Paragraph count changed (newline insert/delete shifts all code block indices)
        // 2. Current or adjacent paragraph is/was a fence boundary
        // Check if paragraph count changed (O(1) — paragraph cache is already rebuilt)
        let currentParagraphCount = document?.paragraphCount ?? 0
        let paragraphCountChanged = currentParagraphCount != lastBlockContextParagraphCount

        if !paragraphCountChanged,
           let location = cursorTextLocation,
           let editedIndex = document?.paragraphIndex(for: location) {
            let nsText = text as NSString
            let blockContext = layoutDelegate.blockContext

            // Check current paragraph text for fence markers
            let cursorOffset = document?.contentStorage.offset(
                from: document!.contentStorage.documentRange.location,
                to: location
            ) ?? 0
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: cursorOffset, length: 0))
            let paragraphText = nsText.substring(with: paragraphRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isFenceNow = paragraphText.hasPrefix("```") || paragraphText.hasPrefix("~~~")

            // Also check previous paragraph (handles Enter after typing ```)
            var prevIsFence = false
            if editedIndex > 0, paragraphRange.location > 0 {
                let prevRange = nsText.paragraphRange(for: NSRange(location: paragraphRange.location - 1, length: 0))
                let prevText = nsText.substring(with: prevRange).trimmingCharacters(in: .whitespacesAndNewlines)
                prevIsFence = prevText.hasPrefix("```") || prevText.hasPrefix("~~~")
            }

            // Check if any of the involved paragraphs were fence boundaries before
            let wasFenceBefore = blockContext.isFenceBoundary(paragraphIndex: editedIndex) ||
                (editedIndex > 0 && blockContext.isFenceBoundary(paragraphIndex: editedIndex - 1))

            if !isFenceNow && !prevIsFence && !wasFenceBefore {
                // No fence involvement — block context cannot change
                return
            }
        }

        let paragraphs = PerfTimer.shared.measure("bc.split") {
            text.components(separatedBy: "\n")
        }

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
        let affectedParagraphs = PerfTimer.shared.measure("bc.diffStatus") {
            newBlockContext.paragraphsWithChangedCodeBlockStatus(
                comparedTo: oldBlockContext,
                paragraphCount: paragraphs.count
            )
        }

        // Sync block context to document for O(1) lookups in willProcessEditing
        document?.blockContext = layoutDelegate.blockContext
        lastBlockContextParagraphCount = document?.paragraphCount ?? 0

        if !affectedParagraphs.isEmpty {
            PerfTimer.shared.measure("bc.applyFonts") {
                if paragraphCountChanged {
                    // Paragraph insertion/deletion shifts indices — targeted update would
                    // miss paragraphs where text changed but status appears the same.
                    applyFontsToAllParagraphs()
                } else {
                    applyFontsToSpecificParagraphs(affectedParagraphs)
                }
            }
            invalidateParagraphsDisplay(affectedParagraphs)
        }
    }


    /// Update block context by scanning all paragraphs. O(N) - for initialization only.
    /// Returns the paragraphs array so callers can reuse it (avoids redundant splitting).
    @discardableResult
    private func updateBlockContextFull() -> [String] {
        guard let text = textView.textStorage?.string else { return [] }
        let paragraphs = text.components(separatedBy: "\n")
        layoutDelegate.updateBlockContext(paragraphs: paragraphs)
        return paragraphs
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
    /// - Parameter paragraphs: Pre-split paragraph array. If nil, splits the text storage string.
    private func applyFontsToAllParagraphs(paragraphs providedParagraphs: [String]? = nil) {
        guard !isApplyingHeadingFonts else { return }
        guard let document = document,
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

        // Reuse provided paragraphs or split text
        let paragraphs = providedParagraphs ?? text.components(separatedBy: "\n")
        var offset = 0

        for (index, para) in paragraphs.enumerated() {
            let range = NSRange(location: offset, length: para.count)
            guard range.location + range.length <= textStorage.length else {
                offset += para.count + 1
                continue
            }

            // O(1) lookup: check if this paragraph is part of a code block
            if let status = blockContext.codeBlockStatus(paragraphIndex: index) {
                // Code block paragraph (content, opening fence, or closing fence): apply monospace font
                _ = status  // All statuses get the same font treatment
                textStorage.addAttribute(.font, value: theme.codeFont, range: range)
            } else {
                // Parse for other block-level elements (cached)
                let tokens = document.tokensForParagraph(text: para, at: index)

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

    /// Apply fonts to specific paragraphs based on their type. O(K) where K = indices.count.
    /// Used when code block boundaries change to avoid re-processing every paragraph.
    private func applyFontsToSpecificParagraphs(_ indices: Set<Int>) {
        guard !isApplyingHeadingFonts else { return }
        guard let document = document,
              let textStorage = textView.textStorage else { return }

        isApplyingHeadingFonts = true
        defer { isApplyingHeadingFonts = false }

        let text = textStorage.string
        guard !text.isEmpty else { return }

        let theme = SyntaxTheme.default
        let blockContext = layoutDelegate.blockContext

        // Build offset map for requested indices only
        let nsText = text as NSString
        var paragraphOffsets: [(index: Int, offset: Int, length: Int)] = []
        var offset = 0
        var paragraphIndex = 0

        // Walk through paragraphs, only collecting offsets for requested indices
        while offset < nsText.length {
            let paraRange = nsText.paragraphRange(for: NSRange(location: offset, length: 0))
            // Paragraph text length without trailing newline
            let textLength = paraRange.length - (offset + paraRange.length <= nsText.length &&
                paraRange.length > 0 &&
                nsText.character(at: offset + paraRange.length - 1) == 0x0A ? 1 : 0)

            if indices.contains(paragraphIndex) {
                paragraphOffsets.append((index: paragraphIndex, offset: offset, length: textLength))
            }

            offset += paraRange.length
            paragraphIndex += 1

            // Early exit once we've found all requested paragraphs
            if paragraphOffsets.count == indices.count { break }
        }

        textStorage.beginEditing()

        for entry in paragraphOffsets {
            let range = NSRange(location: entry.offset, length: entry.length)
            guard range.location + range.length <= textStorage.length, range.length > 0 else { continue }

            let para = nsText.substring(with: NSRange(location: entry.offset, length: entry.length))

            if let status = blockContext.codeBlockStatus(paragraphIndex: entry.index) {
                _ = status
                textStorage.addAttribute(.font, value: theme.codeFont, range: range)
            } else {
                // Reset to body font first
                textStorage.addAttribute(.font, value: theme.bodyFont, range: range)

                let tokens = document.tokensForParagraph(text: para, at: entry.index)
                var isBlockElement = false

                for token in tokens {
                    switch token.element {
                    case .heading(let level):
                        let font = theme.headingFonts[level] ?? theme.bodyFont
                        textStorage.addAttribute(.font, value: font, range: range)
                        isBlockElement = true

                    case .blockquote:
                        textStorage.addAttribute(.font, value: theme.italicFont, range: range)
                        let blockquoteStyle = NSMutableParagraphStyle()
                        blockquoteStyle.headIndent = 20.0
                        blockquoteStyle.firstLineHeadIndent = 0
                        textStorage.addAttribute(.paragraphStyle, value: blockquoteStyle, range: range)
                        isBlockElement = true

                    case .unorderedListItem, .orderedListItem:
                        let listStyle = NSMutableParagraphStyle()
                        listStyle.firstLineHeadIndent = listIndent
                        listStyle.headIndent = listIndent
                        textStorage.addAttribute(.paragraphStyle, value: listStyle, range: range)
                        isBlockElement = false

                    default:
                        break
                    }
                    if isBlockElement { break }
                }

                if !isBlockElement {
                    theme.applyInlineFormattingFonts(to: textStorage, tokens: tokens, paragraphOffset: entry.offset)
                }
            }
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
        PerfTimer.shared.measure("tdc.contentDidChange") {
            document?.contentDidChange(in: range, changeInLength: 0)
        }

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
