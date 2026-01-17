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
    private var editorViewController: EditorViewController!

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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown Editor"
        window.center()
        window.minSize = NSSize(width: 600, height: 400)

        // Main split view (sidebar | editor area)
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        self.splitView = split

        // Sidebar
        let sidebar = SidebarController()
        sidebar.workspaceManager = workspaceManager
        sidebar.onFileSelected = { [weak self] url in
            try? self?.openFile(at: url)
        }
        self.sidebarController = sidebar

        let sidebarView = sidebar.view
        sidebarView.setFrameSize(NSSize(width: 220, height: 700))
        split.addArrangedSubview(sidebarView)

        // Editor area (tab bar + editor)
        let editorArea = NSView()
        editorArea.translatesAutoresizingMaskIntoConstraints = false

        // Tab bar
        let tabBar = TabBarView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.tabManager = tabManager
        self.tabBarView = tabBar
        editorArea.addSubview(tabBar)

        // Editor
        editorViewController = EditorViewController()
        let editorView = editorViewController.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorArea.addSubview(editorView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: editorArea.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 32),

            editorView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            editorView.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: editorArea.bottomAnchor)
        ])

        split.addArrangedSubview(editorArea)

        // Set holding priorities so sidebar keeps size when resizing
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        window.contentView = split
        self.window = window
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
        }

        // Handle close confirmation for dirty documents
        tabManager.onCloseConfirmation = { [weak self] document in
            self?.tabBarView?.rebuildTabs()
            return self?.confirmClose(document: document) ?? true
        }
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
        panel.allowsMultipleSelection = false

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self?.openFile(at: url)
            } catch {
                self?.showError(error)
            }
        }
    }

    // MARK: - UI Refresh

    /// Refresh UI elements (title, tabs) to reflect current state.
    func refreshUI() {
        updateWindowTitle()
        tabBarView?.updateTabs()
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
