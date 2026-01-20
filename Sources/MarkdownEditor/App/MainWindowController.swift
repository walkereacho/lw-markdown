import AppKit

final class MainWindowController: NSWindowController {

    /// Tab manager for document lifecycle.
    let tabManager = TabManager()

    /// Workspace manager for file tree.
    let workspaceManager = WorkspaceManager()

    /// Sidebar controller.
    private(set) var sidebarController: SidebarController?

    /// Split view for sidebar + editor.
    private var splitView: NSSplitView?

    /// Tab bar view.
    private(set) var tabBarView: TabBarView?

    /// Editor view controller.
    private(set) var editorViewController: EditorViewController!

    /// Comment sidebar controller.
    private(set) var commentSidebarController: CommentSidebarController?

    /// Inner split view for editor + comment sidebar.
    private var editorSplitView: NSSplitView?

    /// Whether comment sidebar is visible.
    private(set) var isCommentSidebarVisible = false

    /// Theme observer.
    private var themeObserver: NSObjectProtocol?

    override init(window: NSWindow?) {
        super.init(window: nil)
        setupWindow()
        setupTabManager()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown Editor"
        window.center()
        window.minSize = NSSize(width: 600, height: 400)

        // Transparent titlebar for modern look
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Window background from theme
        window.backgroundColor = ThemeManager.shared.colors.shellBackground

        // Main split view (sidebar | editor area)
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        split.wantsLayer = true
        self.splitView = split

        // Sidebar
        let sidebar = SidebarController()
        sidebar.workspaceManager = workspaceManager
        sidebar.onFileSelected = { [weak self] url in
            try? self?.openFile(at: url)
        }
        self.sidebarController = sidebar

        // Refresh sidebar when files change externally
        workspaceManager.onFileChanged = { [weak self] _ in
            self?.sidebarController?.refresh()
        }

        let sidebarView = sidebar.view
        sidebarView.setFrameSize(NSSize(width: 220, height: 700))
        split.addArrangedSubview(sidebarView)

        // Editor area (tab bar + inner split for editor/comments)
        let editorArea = NSView()
        editorArea.autoresizingMask = [.width, .height]
        editorArea.wantsLayer = true

        // Tab bar
        let tabBar = TabBarView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.tabManager = tabManager
        self.tabBarView = tabBar
        editorArea.addSubview(tabBar)

        // Inner split view for editor + comment sidebar
        let innerSplit = NSSplitView()
        innerSplit.isVertical = true
        innerSplit.dividerStyle = .thin
        innerSplit.translatesAutoresizingMaskIntoConstraints = false
        innerSplit.delegate = self
        self.editorSplitView = innerSplit
        editorArea.addSubview(innerSplit)

        // Editor
        editorViewController = EditorViewController()
        let editorView = editorViewController.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        innerSplit.addArrangedSubview(editorView)

        // Comment sidebar controller (not added to split yet)
        let commentSidebar = CommentSidebarController()
        commentSidebar.onCommentStoreChanged = { [weak self] store in
            self?.saveCommentStore(store)
        }
        commentSidebar.onCommentClicked = { [weak self] comment in
            self?.scrollToComment(comment)
        }
        commentSidebar.onClose = { [weak self] in
            self?.hideCommentSidebar()
        }
        self.commentSidebarController = commentSidebar

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: editorArea.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 36),

            innerSplit.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            innerSplit.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            innerSplit.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            innerSplit.bottomAnchor.constraint(equalTo: editorArea.bottomAnchor)
        ])

        split.addArrangedSubview(editorArea)

        // Set holding priorities so editor grows when resizing (sidebar stays fixed)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)  // Sidebar holds its size
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)   // Editor absorbs resize
        split.delegate = self

        window.contentView = split
        self.window = window

        // Observe theme changes for window background
        themeObserver = ThemeManager.shared.observeChanges { [weak self] in
            self?.applyTheme()
        }
    }

    private func applyTheme() {
        let colors = ThemeManager.shared.colors
        window?.backgroundColor = colors.shellBackground

        // Update split view divider
        splitView?.setValue(colors.shellDivider, forKey: "dividerColor")
    }

    private func setupTabManager() {
        // When active tab changes, update editor
        tabManager.onActiveTabChanged = { [weak self] documentId in
            guard let self = self,
                  let docId = documentId,
                  let document = self.tabManager.document(for: docId) else { return }
            self.editorViewController.loadDocument(document)
            self.tabBarView?.updateTabs()
            self.updateWindowTitle()
            self.loadCommentsForActiveDocument()
        }

        // Handle close confirmation for dirty documents
        tabManager.onCloseConfirmation = { [weak self] document in
            self?.tabBarView?.rebuildTabs()
            return self?.confirmClose(document: document) ?? true
        }

        // Observe text changes to update comment sidebar
        NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let textView = notification.object as? NSTextView,
                  textView === self?.editorViewController.currentPane?.textView else { return }
            self?.commentSidebarController?.documentText = textView.string
        }

        // Create initial empty document so tabs are never empty
        newDocument()
    }

    // MARK: - Document Operations

    func newDocument() {
        let document = tabManager.newDocument()
        editorViewController.loadDocument(document)
        tabBarView?.rebuildTabs()
        updateWindowTitle()
    }

    func openFile(at url: URL) throws {
        let document = try tabManager.openFile(at: url)
        editorViewController.loadDocument(document)
        tabBarView?.rebuildTabs()
        updateWindowTitle()
    }

    func saveDocument() {
        guard let document = tabManager.activeDocument else { return }
        do {
            if document.filePath == nil {
                saveDocumentAs()
            } else {
                try document.save()
                updateWindowTitle()
            }
        } catch {
            showError(error)
        }
    }

    func saveDocumentAs() {
        guard let document = tabManager.activeDocument else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "Untitled.md"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            document.filePath = url
            do {
                try document.save()
                self?.updateWindowTitle()
            } catch {
                self?.showError(error)
            }
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            if url.hasDirectoryPath {
                self?.openWorkspace(at: url)
            } else {
                do {
                    try self?.openFile(at: url)
                } catch {
                    self?.showError(error)
                }
            }
        }
    }

    // MARK: - Workspace Operations

    func openWorkspace(at url: URL) {
        do {
            try workspaceManager.mountWorkspace(at: url)
            sidebarController?.refresh()
            window?.title = "\(url.lastPathComponent) — Markdown Editor"
        } catch {
            showError(error)
        }
    }

    func openWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open as workspace"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openWorkspace(at: url)
        }
    }

    // MARK: - UI Refresh

    /// Refresh UI elements (title, tabs) to reflect current state.
    func refreshUI() {
        updateWindowTitle()
        tabBarView?.updateTabs()
    }

    // MARK: - Cursor Positioning (for testing)

    /// Position cursor at the beginning of the specified line (1-indexed).
    func setCursorLine(_ line: Int) {
        editorViewController.setCursorLine(line)
    }

    // MARK: - Comment Sidebar

    func showCommentSidebar() {
        guard !isCommentSidebarVisible, let sidebar = commentSidebarController, let split = editorSplitView else { return }
        sidebar.view.setFrameSize(NSSize(width: 280, height: split.bounds.height))
        split.addArrangedSubview(sidebar.view)
        isCommentSidebarVisible = true
        loadCommentsForActiveDocument()
    }

    func hideCommentSidebar() {
        guard isCommentSidebarVisible, let sidebar = commentSidebarController else { return }
        sidebar.view.removeFromSuperview()
        isCommentSidebarVisible = false
    }

    func toggleCommentSidebar() {
        if isCommentSidebarVisible { hideCommentSidebar() } else { showCommentSidebar() }
    }

    func addComment() {
        guard let pane = editorViewController.currentPane,
              pane.textView.selectedRange().length > 0 else {
            toggleCommentSidebar()
            return
        }
        let range = pane.textView.selectedRange()
        let selectedText = (pane.textView.string as NSString).substring(with: range)
        if !isCommentSidebarVisible { showCommentSidebar() }
        commentSidebarController?.beginAddingComment(anchorText: selectedText)
    }

    private func loadCommentsForActiveDocument() {
        guard let document = tabManager.activeDocument, let url = document.filePath else {
            commentSidebarController?.commentStore = CommentStore()
            return
        }
        let store = CommentPersistence.load(for: url)
        commentSidebarController?.commentStore = store
        commentSidebarController?.documentText = document.fullString()
        if !store.comments.isEmpty && !isCommentSidebarVisible { showCommentSidebar() }
    }

    private func saveCommentStore(_ store: CommentStore) {
        guard let document = tabManager.activeDocument, let url = document.filePath else { return }
        CommentPersistence.save(store, for: url)
        if store.comments.isEmpty && isCommentSidebarVisible { hideCommentSidebar() }
    }

    private func scrollToComment(_ comment: Comment) {
        guard let pane = editorViewController.currentPane,
              let range = pane.textView.string.range(of: comment.anchorText) else { return }
        let nsRange = NSRange(range, in: pane.textView.string)

        // Set selection to make paragraph active (shows raw markdown)
        pane.textView.setSelectedRange(nsRange)
        pane.textView.scrollRangeToVisible(nsRange)
    }

    // MARK: - Window Title

    private func updateWindowTitle() {
        guard let tab = tabManager.tabs.first(where: { $0.documentId == tabManager.activeDocumentId }) else {
            window?.title = "Markdown Editor"
            return
        }
        let dirty = tab.isDirty ? " \u{2022}" : ""
        window?.title = "\(tab.title)\(dirty) — Markdown Editor"
    }

    // MARK: - Alerts

    private func confirmClose(document: DocumentModel) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Save
            do {
                if document.filePath == nil {
                    return false  // Cancel for now
                }
                try document.save()
                return true
            } catch {
                showError(error)
                return false
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

// MARK: - NSSplitViewDelegate

extension MainWindowController: NSSplitViewDelegate {

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === self.splitView {
            // Main split: minimum file sidebar width
            return 150
        } else if splitView === editorSplitView {
            // Editor split: minimum editor width
            return 300
        }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === self.splitView {
            // Main split: maximum file sidebar width (leave at least 400px for editor area)
            return splitView.bounds.width - 400
        } else if splitView === editorSplitView {
            // Editor split: maximum editor width (leave at least 200px for comment sidebar)
            return splitView.bounds.width - 200
        }
        return proposedMaximumPosition
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        if splitView === self.splitView {
            // Main split: file sidebar keeps its width, editor area gets the rest
            guard splitView.subviews.count == 2 else {
                splitView.adjustSubviews()
                return
            }

            let sidebarView = splitView.subviews[0]
            let editorView = splitView.subviews[1]
            let dividerThickness = splitView.dividerThickness

            // Keep sidebar at its current width (or default 220 if too small)
            var sidebarWidth = sidebarView.frame.width
            if sidebarWidth < 150 {
                sidebarWidth = 220
            }

            let newWidth = splitView.bounds.width
            let editorWidth = newWidth - sidebarWidth - dividerThickness

            sidebarView.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: splitView.bounds.height)
            editorView.frame = NSRect(x: sidebarWidth + dividerThickness, y: 0, width: editorWidth, height: splitView.bounds.height)
        } else if splitView === editorSplitView {
            // Editor split: comment sidebar keeps its width, editor gets the rest
            guard splitView.subviews.count >= 1 else {
                splitView.adjustSubviews()
                return
            }

            let editorView = splitView.subviews[0]
            let dividerThickness = splitView.dividerThickness
            let newWidth = splitView.bounds.width
            let height = splitView.bounds.height

            if splitView.subviews.count == 2 {
                let commentView = splitView.subviews[1]
                var commentWidth = commentView.frame.width
                if commentWidth < 200 { commentWidth = 280 }

                let editorWidth = newWidth - commentWidth - dividerThickness
                editorView.frame = NSRect(x: 0, y: 0, width: editorWidth, height: height)
                commentView.frame = NSRect(x: editorWidth + dividerThickness, y: 0, width: commentWidth, height: height)
            } else {
                editorView.frame = NSRect(x: 0, y: 0, width: newWidth, height: height)
            }
        } else {
            splitView.adjustSubviews()
        }
    }
}
