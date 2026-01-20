import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Required for programmatic AppKit apps to appear in Dock and show windows
        NSApp.setActivationPolicy(.regular)

        setupMainMenu()
        openNewWindow()

        // Process CLI arguments for testing
        processTestArguments()

        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - CLI Test Arguments

    private func processTestArguments() {
        let args = CommandLine.arguments

        // --window-size WxH (e.g., "1200x800")
        if let sizeIndex = args.firstIndex(of: "--window-size"),
           sizeIndex + 1 < args.count {
            let sizeStr = args[sizeIndex + 1]
            let parts = sizeStr.split(separator: "x")
            if parts.count == 2,
               let width = Int(parts[0]),
               let height = Int(parts[1]) {
                mainWindowController?.window?.setContentSize(NSSize(width: width, height: height))
                mainWindowController?.window?.center()
            }
        }

        // --test-file <path>
        if let fileIndex = args.firstIndex(of: "--test-file"),
           fileIndex + 1 < args.count {
            let filePath = args[fileIndex + 1]
            let url = URL(fileURLWithPath: filePath)
            do {
                try mainWindowController?.openFile(at: url)
            } catch {
                print("Error opening test file: \(error)")
            }
        }

        // --cursor-line <N>
        if let lineIndex = args.firstIndex(of: "--cursor-line"),
           lineIndex + 1 < args.count,
           let line = Int(args[lineIndex + 1]) {
            mainWindowController?.setCursorLine(line)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Window Management

    private func openNewWindow() {
        let windowController = MainWindowController()
        windowController.showWindow(nil)
        mainWindowController = windowController
    }

    // MARK: - Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit MarkdownEditor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New", action: #selector(newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Quick Open...", action: #selector(showQuickOpen(_:)), keyEquivalent: "p")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As...", action: #selector(saveDocumentAs(_:)), keyEquivalent: "S")

        // Edit menu (for undo/redo/copy/paste)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc private func newDocument(_ sender: Any?) {
        mainWindowController?.newDocument()
    }

    @objc private func openDocument(_ sender: Any?) {
        mainWindowController?.openDocument()
    }

    @objc private func saveDocument(_ sender: Any?) {
        mainWindowController?.saveDocument()
    }

    @objc private func saveDocumentAs(_ sender: Any?) {
        mainWindowController?.saveDocumentAs()
    }

    @objc private func showQuickOpen(_ sender: Any?) {
        mainWindowController?.showQuickOpen()
    }

    @objc func openWorkspaceAction(_ sender: Any?) {
        mainWindowController?.openWorkspace()
    }
}
