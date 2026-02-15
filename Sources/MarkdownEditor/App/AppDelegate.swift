import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Required for programmatic AppKit apps to appear in Dock and show windows
        NSApp.setActivationPolicy(.regular)

        // Pre-warm Highlightr's JSContext (~50ms) before any rendering.
        // Without this, the first code block draw during scroll spikes to 52ms.
        _ = SyntaxHighlighter.shared.highlight(code: " ", language: "swift")

        setupMainMenu()
        openNewWindow()

        // Process CLI arguments for testing
        processTestArguments()

        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)

        // Run perf tests if requested (after a delay to let document fully load)
        if CommandLine.arguments.contains("--perf-scroll-test") {
            runScrollPerfTest()
        }
        if CommandLine.arguments.contains("--perf-type-test") {
            runTypingPerfTest()
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

    // MARK: - Typing Performance Test

    /// Automated typing profiling.
    /// Inserts characters one at a time at various cursor positions, measuring per-keystroke cost.
    private func runTypingPerfTest() {
        let args = CommandLine.arguments
        let typeCount: Int
        if let idx = args.firstIndex(of: "--type-count"), idx + 1 < args.count,
           let n = Int(args[idx + 1]) {
            typeCount = n
        } else {
            typeCount = 50
        }

        // Scale wait time with document size
        let docLength = mainWindowController?.tabManager.activeDocument?.fullString().count ?? 0
        let loadDelay = max(2.0, Double(docLength) / 10_000)

        DispatchQueue.main.asyncAfter(deadline: .now() + loadDelay) { [weak self] in
            guard let self,
                  let pane = self.mainWindowController?.editorViewController.currentPane else {
                fputs("[PERF] type test: no pane available\n", stderr)
                return
            }

            let textView = pane.textView
            guard let document = pane.document else {
                fputs("[PERF] type test: no document\n", stderr)
                return
            }

            let text = document.fullString()
            let lineCount = text.components(separatedBy: "\n").count
            let filePath = document.filePath?.lastPathComponent ?? "unknown"

            fputs("[PERF] type test: \(typeCount) chars, \(lineCount) lines, file=\(filePath)\n", stderr)

            // Define test scenarios: (label, target line 1-indexed)
            let scenarios: [(label: String, line: Int)] = [
                ("plain-mid", max(1, lineCount / 2)),
                ("code-content", self.findCodeContentLine(in: text) ?? max(1, lineCount / 3)),
                ("fence-line", self.findFenceLine(in: text) ?? 1),
                ("near-end", max(1, lineCount - 5))
            ]

            self.runTypingScenarios(
                scenarios: scenarios,
                scenarioIndex: 0,
                typeCount: typeCount,
                textView: textView,
                document: document,
                filePath: filePath
            )
        }
    }

    /// Run typing scenarios sequentially.
    private func runTypingScenarios(
        scenarios: [(label: String, line: Int)],
        scenarioIndex: Int,
        typeCount: Int,
        textView: NSTextView,
        document: DocumentModel,
        filePath: String
    ) {
        guard scenarioIndex < scenarios.count else {
            // All scenarios complete — exit
            fputs("[PERF] type test: all scenarios complete\n", stderr)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
            return
        }

        let scenario = scenarios[scenarioIndex]
        fputs("[PERF] type test: starting scenario '\(scenario.label)' at line \(scenario.line)\n", stderr)

        // Position cursor at the target line
        mainWindowController?.editorViewController.setCursorLine(scenario.line)

        // Small delay to let cursor positioning settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }

            PerfTimer.shared.reset()

            // Insert characters one at a time
            self.insertCharactersSequentially(
                remaining: typeCount,
                textView: textView,
                completion: { [weak self] in
                    guard let self else { return }

                    // Dump results for this scenario
                    PerfTimer.shared.printSummary(label: "type-\(scenario.label)-\(filePath)")

                    // Undo all insertions
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self else { return }
                        for _ in 0..<typeCount {
                            document.undoManager.undo()
                        }

                        // Small delay then next scenario
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            self?.runTypingScenarios(
                                scenarios: scenarios,
                                scenarioIndex: scenarioIndex + 1,
                                typeCount: typeCount,
                                textView: textView,
                                document: document,
                                filePath: filePath
                            )
                        }
                    }
                }
            )
        }
    }

    /// Insert characters one at a time with minimal delays to simulate real typing.
    private func insertCharactersSequentially(
        remaining: Int,
        textView: NSTextView,
        completion: @escaping () -> Void
    ) {
        guard remaining > 0 else {
            completion()
            return
        }

        // Insert a single character via textView to trigger full editing pipeline
        textView.insertText("x", replacementRange: textView.selectedRange())

        // Schedule next character on next runloop iteration
        DispatchQueue.main.async { [weak self] in
            self?.insertCharactersSequentially(
                remaining: remaining - 1,
                textView: textView,
                completion: completion
            )
        }
    }

    /// Find a line number (1-indexed) that is inside a code block content.
    private func findCodeContentLine(in text: String) -> Int? {
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inCodeBlock {
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                return i + 1 // 1-indexed
            }
        }
        return nil
    }

    /// Find a line number (1-indexed) that is a fence line (``` or ~~~).
    private func findFenceLine(in text: String) -> Int? {
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                return i + 1 // 1-indexed
            }
        }
        return nil
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
