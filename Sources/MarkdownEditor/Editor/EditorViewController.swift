import AppKit

/// View controller for the main editor area.
/// Sets up TextKit 2 infrastructure for a single editing pane.
final class EditorViewController: NSViewController {

    /// Current document being edited.
    private(set) var currentDocument: DocumentModel?

    /// The text view for editing.
    private var textView: NSTextView!

    /// Scroll view containing the text view.
    private var scrollView: NSScrollView!

    /// Layout manager for this pane.
    private var layoutManager: NSTextLayoutManager!

    /// Text container defining the geometry.
    private var textContainer: NSTextContainer!

    // MARK: - Lifecycle

    override func loadView() {
        // Create the main view
        let containerView = NSView()
        containerView.autoresizingMask = [.width, .height]
        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTextView()
        loadDocument(DocumentModel())  // Start with empty document
    }

    // MARK: - Setup

    private func setupTextView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Document Loading

    /// Load a document into the editor.
    ///
    /// This sets up the full TextKit 2 stack:
    /// ```
    /// DocumentModel.contentStorage (NSTextContentStorage)
    ///         │
    ///         ▼
    ///   NSTextLayoutManager (one per pane)
    ///         │
    ///         ▼
    ///    NSTextContainer
    ///         │
    ///         ▼
    ///      NSTextView
    /// ```
    func loadDocument(_ document: DocumentModel) {
        // Clean up previous document
        if let previousLayout = layoutManager {
            currentDocument?.contentStorage.removeTextLayoutManager(previousLayout)
        }

        currentDocument = document

        // Create TextKit 2 layout infrastructure
        layoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer()

        // Configure text container
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false

        // Connect layout manager to container
        layoutManager.textContainer = textContainer

        // Connect layout manager to document's content storage
        // This is the key TextKit 2 pattern — content storage can have multiple layout managers
        document.contentStorage.addTextLayoutManager(layoutManager)

        // Create text view using TextKit 2 initializer
        // IMPORTANT: Use the initializer that takes NSTextLayoutManager, not the legacy one
        textView = NSTextView(frame: scrollView.bounds, textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 20, height: 20)

        // Configure editor behavior
        textView.isRichText = false  // Plain text editing
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor

        // Wire up undo manager
        textView.allowsUndo = true

        // Set as scroll view's document view
        scrollView.documentView = textView

        // Make text view first responder
        view.window?.makeFirstResponder(textView)
    }
}
