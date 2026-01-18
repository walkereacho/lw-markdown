import AppKit

/// View controller for the main editor area.
/// Uses PaneController for TextKit 2 setup and active paragraph tracking.
final class EditorViewController: NSViewController {

    /// Current document being edited.
    private(set) var currentDocument: DocumentModel?

    /// Current pane controller.
    private(set) var paneController: PaneController?

    /// Scroll view containing the text view.
    private var scrollView: NSScrollView!

    // MARK: - Lifecycle

    override func loadView() {
        // Create the main view with an initial frame
        // The frame will be resized by the window, but needs a non-zero starting size
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        containerView.autoresizingMask = [.width, .height]
        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        loadDocument(DocumentModel())
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Make text view first responder once view is in a window
        view.window?.makeFirstResponder(paneController?.textView)
    }

    private func setupScrollView() {
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

    func loadDocument(_ document: DocumentModel) {
        currentDocument = document

        // Create pane controller with rendering infrastructure
        paneController = PaneController(document: document, frame: scrollView.bounds)

        // Set as scroll view's document view
        scrollView.documentView = paneController?.textView

        // Invalidate layout and force full redraw to clear any rendering artifacts
        if let pane = paneController {
            pane.layoutManager.ensureLayout(for: pane.layoutManager.documentRange)
            pane.textView.display()
        }

        // Make text view first responder
        view.window?.makeFirstResponder(paneController?.textView)
    }

    // MARK: - Cursor Positioning (for testing)

    /// Position cursor at the beginning of the specified line (1-indexed).
    func setCursorLine(_ line: Int) {
        guard let textView = paneController?.textView,
              let textStorage = textView.textStorage,
              line >= 1 else { return }

        let text = textStorage.string
        var currentLine = 1
        var position = text.startIndex

        // Find the start of the requested line
        while currentLine < line && position < text.endIndex {
            if text[position] == "\n" {
                currentLine += 1
            }
            position = text.index(after: position)
        }

        // Convert String.Index to Int offset
        let offset = text.distance(from: text.startIndex, to: position)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
    }
}
