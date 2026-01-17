import AppKit

final class MainWindowController: NSWindowController {

    /// Tab manager for document lifecycle.
    let tabManager = TabManager()

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
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown Editor"
        window.center()

        editorViewController = EditorViewController()
        window.contentViewController = editorViewController

        self.window = window
    }

    private func setupTabManager() {
        // When active tab changes, update editor
        tabManager.onActiveTabChanged = { [weak self] documentId in
            guard let self = self,
                  let docId = documentId,
                  let document = self.tabManager.document(for: docId) else { return }
            self.editorViewController.loadDocument(document)
            self.updateWindowTitle()
        }

        // Handle close confirmation for dirty documents
        tabManager.onCloseConfirmation = { [weak self] document in
            return self?.confirmClose(document: document) ?? true
        }
    }

    // MARK: - Document Operations

    func newDocument() {
        let document = tabManager.newDocument()
        editorViewController.loadDocument(document)
        updateWindowTitle()
    }

    func openFile(at url: URL) throws {
        let document = try tabManager.openFile(at: url)
        editorViewController.loadDocument(document)
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
