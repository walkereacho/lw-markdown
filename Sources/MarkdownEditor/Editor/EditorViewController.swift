import AppKit

/// View controller for the main editor area.
/// Uses PaneController for TextKit 2 setup and active paragraph tracking.
final class EditorViewController: NSViewController {

    /// Current document being edited.
    private(set) var currentDocument: DocumentModel?

    /// Current pane controller.
    private var paneController: PaneController?

    /// Scroll view containing the text view.
    private var scrollView: NSScrollView!

    // MARK: - Lifecycle

    override func loadView() {
        let containerView = NSView()
        containerView.autoresizingMask = [.width, .height]
        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        loadDocument(DocumentModel())
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

        // Make text view first responder
        view.window?.makeFirstResponder(paneController?.textView)
    }
}
