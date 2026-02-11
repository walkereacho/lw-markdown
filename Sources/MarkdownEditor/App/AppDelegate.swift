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

        // Run scroll perf test if requested (after a delay to let document fully load)
        if CommandLine.arguments.contains("--perf-scroll-test") {
            runScrollPerfTest()
        }
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

    // MARK: - Scroll Performance Test

    /// Automated scroll-to-bottom profiling.
    /// Waits for document load, resets PerfTimer, scrolls in page-sized steps, then dumps results.
    private func runScrollPerfTest() {
        // Scale wait time with document size — large docs take longer to load
        let docLength = mainWindowController?.tabManager.activeDocument?.fullString().count ?? 0
        let loadDelay = max(2.0, Double(docLength) / 10_000)  // ~1s per 10K chars, minimum 2s

        DispatchQueue.main.asyncAfter(deadline: .now() + loadDelay) { [weak self] in
            guard let self,
                  let pane = self.mainWindowController?.editorViewController.currentPane else {
                fputs("[PERF] scroll test: no pane available\n", stderr)
                return
            }

            let textView = pane.textView
            guard let scrollView = textView.enclosingScrollView else {
                fputs("[PERF] scroll test: no scroll view\n", stderr)
                return
            }

            // Reset timer to isolate scroll metrics
            PerfTimer.shared.reset()

            let clipView = scrollView.contentView
            let contentHeight = textView.frame.height
            let visibleHeight = clipView.bounds.height
            let pageStep = visibleHeight * 0.9  // 90% of visible area per step

            // Calculate how many steps to scroll to bottom
            let maxY = max(0, contentHeight - visibleHeight)
            let steps = Int(ceil(maxY / pageStep))

            fputs("[PERF] scroll test: \(steps) page-down steps, contentHeight=\(Int(contentHeight)), visibleHeight=\(Int(visibleHeight))\n", stderr)

            // Schedule page-down scrolls with small delays to simulate real scrolling
            for i in 0...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                    let targetY = min(Double(i) * pageStep, maxY)
                    let newOrigin = NSPoint(x: 0, y: targetY)
                    clipView.scroll(to: newOrigin)
                    scrollView.reflectScrolledClipView(clipView)
                }
            }

            // After scrolling completes, dump results and exit
            let finishDelay = Double(steps + 1) * 0.05 + 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + finishDelay) { [weak self] in
                let filePath = self?.mainWindowController?.tabManager.activeDocument?.filePath?.lastPathComponent ?? "unknown"
                PerfTimer.shared.printSummary(label: "scroll-\(filePath)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            }
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
        editMenu.addItem(NSMenuItem.separator())
        let addCommentItem = NSMenuItem(title: "Add Comment", action: #selector(addComment(_:)), keyEquivalent: "m")
        addCommentItem.keyEquivalentModifierMask = [.option, .command]
        editMenu.addItem(addCommentItem)
        editMenu.addItem(withTitle: "Toggle Comment Sidebar", action: #selector(toggleCommentSidebar(_:)), keyEquivalent: "")

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

    @objc func openWorkspaceAction(_ sender: Any?) {
        mainWindowController?.openWorkspace()
    }

    @objc func addComment(_ sender: Any?) {
        mainWindowController?.addComment()
    }

    @objc private func toggleCommentSidebar(_ sender: Any?) {
        mainWindowController?.toggleCommentSidebar()
    }
}
