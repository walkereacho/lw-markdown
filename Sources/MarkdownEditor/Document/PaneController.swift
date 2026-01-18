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

        // Apply pending content now that layout infrastructure is ready
        document.applyPendingContent()

        // Initialize rendering state after content is loaded
        initializeAfterContentLoad()
    }

    /// Initialize rendering state after content is loaded.
    /// Sets up heading fonts and active paragraph for correct initial display.
    private func initializeAfterContentLoad() {
        // Apply heading fonts so TextKit 2 calculates correct metrics
        applyHeadingFontsToStorage()

        // Set initial active paragraph to 0 (cursor starts at beginning)
        activeParagraphIndex = 0

        // Force layout fragment recreation
        if let textContainer = layoutManager.textContainer {
            layoutManager.textContainer = nil
            layoutManager.textContainer = textContainer
        }
    }

    deinit {
        document?.contentStorage.removeTextLayoutManager(layoutManager)
    }

    private func configureTextView() {
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
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

    /// Apply heading fonts to storage so TextKit 2 calculates correct cursor metrics.
    /// Uses reentrancy guard to prevent infinite loops.
    private func applyHeadingFontsToStorage() {
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

        activeParagraphIndex = newIndex

        // TextKit 2 caches layout fragments. Force fragment recreation by
        // detaching and reattaching the text container.
        if let textContainer = layoutManager.textContainer {
            layoutManager.textContainer = nil
            layoutManager.textContainer = textContainer
        }

        // Force immediate redraw
        textView.display()
    }

}

// MARK: - NSTextViewDelegate

extension PaneController: NSTextViewDelegate {

    func textViewDidChangeSelection(_ notification: Notification) {
        handleSelectionChange()
    }

    func textDidChange(_ notification: Notification) {
        // Notify document of content change for cache invalidation
        let range = document?.contentStorage.documentRange ?? layoutManager.documentRange
        document?.contentDidChange(in: range, changeInLength: 0)

        // Apply heading fonts for correct cursor metrics
        applyHeadingFontsToStorage()
    }
}
