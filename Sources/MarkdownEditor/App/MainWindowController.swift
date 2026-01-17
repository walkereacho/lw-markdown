import AppKit

final class MainWindowController: NSWindowController {

    private var editorViewController: EditorViewController!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Untitled"
        window.center()

        super.init(window: window)

        editorViewController = EditorViewController()
        window.contentViewController = editorViewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Document Operations

    func newDocument() {
        editorViewController.loadDocument(DocumentModel())
        window?.title = "Untitled"
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let document = try DocumentModel(contentsOf: url)
                self?.editorViewController.loadDocument(document)
                self?.window?.title = url.lastPathComponent
            } catch {
                self?.showError(error)
            }
        }
    }

    func saveDocument() {
        guard let document = editorViewController.currentDocument else { return }

        if document.filePath != nil {
            do {
                try document.save()
            } catch {
                showError(error)
            }
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        guard let document = editorViewController.currentDocument else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Untitled.md"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            document.filePath = url
            do {
                try document.save()
                self?.window?.title = url.lastPathComponent
            } catch {
                self?.showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        guard let window = window else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }
}
