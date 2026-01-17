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

    // MARK: - Initialization

    init(document: DocumentModel, frame: NSRect) {
        self.id = UUID()
        self.document = document

        // Create layout infrastructure
        self.layoutManager = NSTextLayoutManager()
        self.textContainer = NSTextContainer(size: frame.size)
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
    }

    deinit {
        document?.contentStorage.removeTextLayoutManager(layoutManager)
    }

    private func configureTextView() {
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 20, height: 20)

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

    // MARK: - Active Paragraph

    /// Check if a paragraph is active in THIS pane.
    func isActiveParagraph(at index: Int) -> Bool {
        return index == activeParagraphIndex
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

        let previousIndex = activeParagraphIndex
        activeParagraphIndex = newIndex

        // Invalidate layout for affected paragraphs
        // This triggers redraw with new active state
        if let prevIdx = previousIndex,
           let range = document.paragraphRange(at: prevIdx) {
            layoutManager.invalidateLayout(for: range)
        }

        if let newIdx = newIndex,
           let range = document.paragraphRange(at: newIdx) {
            layoutManager.invalidateLayout(for: range)
        }
    }
}

// MARK: - NSTextViewDelegate

extension PaneController: NSTextViewDelegate {

    func textViewDidChangeSelection(_ notification: Notification) {
        handleSelectionChange()
    }

    func textDidChange(_ notification: Notification) {
        // Notify document of content change for cache invalidation
        // (Full implementation would pass edit range, simplified here)
        let range = document?.contentStorage.documentRange ?? layoutManager.documentRange
        document?.contentDidChange(in: range, changeInLength: 0)
    }
}
