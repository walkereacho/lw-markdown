import AppKit

/// Controller for the quick open panel (Cmd+P).
///
/// Shows a search field and filtered list of files.
/// Features borderless window with vibrancy and smooth animations.
final class QuickOpenController: NSWindowController {

    /// Workspace manager for file search.
    var workspaceManager: WorkspaceManager?

    /// Callback when user selects a file.
    var onFileSelected: ((URL) -> Void)?

    private var containerView: NSVisualEffectView!
    private var searchField: NSTextField!
    private var searchIconView: NSImageView!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var searchResults: [URL] = []

    /// Theme observer.
    private var themeObserver: NSObjectProtocol?

    init() {
        // Borderless floating panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.center()

        super.init(window: panel)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let theme = ThemeManager.shared.current
        let colors = ThemeManager.shared.colors

        // Visual effect view for blur/vibrancy
        containerView = NSVisualEffectView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.material = .hudWindow
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = theme.radiusLG
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = colors.shellBorder.cgColor
        contentView.addSubview(containerView)

        // Search container
        let searchContainer = NSView()
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.wantsLayer = true
        searchContainer.layer?.backgroundColor = colors.quickOpenInputBackground.cgColor
        searchContainer.layer?.cornerRadius = theme.radiusMD
        containerView.addSubview(searchContainer)

        // Search icon
        searchIconView = NSImageView()
        searchIconView.translatesAutoresizingMaskIntoConstraints = false
        searchIconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        searchIconView.contentTintColor = colors.sidebarSecondaryText
        searchContainer.addSubview(searchIconView)

        // Search field (custom styled)
        searchField = NSTextField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search files..."
        searchField.font = theme.uiFont(size: 16, weight: .regular)
        searchField.textColor = colors.tabActiveText
        searchField.backgroundColor = .clear
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchContainer.addSubview(searchField)

        // Scroll view with table
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        containerView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.title = "Files"
        tableView.addTableColumn(column)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick(_:))

        scrollView.documentView = tableView

        // Constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            searchContainer.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            searchContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            searchContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            searchContainer.heightAnchor.constraint(equalToConstant: 44),

            searchIconView.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 12),
            searchIconView.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIconView.widthAnchor.constraint(equalToConstant: 18),
            searchIconView.heightAnchor.constraint(equalToConstant: 18),

            searchField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])

        // Observe theme changes
        themeObserver = containerView.observeTheme { [weak self] in
            self?.applyTheme()
        }
    }

    // MARK: - Theming

    private func applyTheme() {
        let theme = ThemeManager.shared.current
        let colors = ThemeManager.shared.colors

        containerView.layer?.cornerRadius = theme.radiusLG
        containerView.layer?.borderColor = colors.shellBorder.cgColor

        searchField.textColor = colors.tabActiveText
        searchField.font = theme.uiFont(size: 16, weight: .regular)

        searchIconView.contentTintColor = colors.sidebarSecondaryText

        // Update search container background
        if let searchContainer = searchField.superview {
            searchContainer.layer?.backgroundColor = colors.quickOpenInputBackground.cgColor
            searchContainer.layer?.cornerRadius = theme.radiusMD
        }

        tableView.reloadData()
    }

    // MARK: - Window Lifecycle

    override func showWindow(_ sender: Any?) {
        guard let panel = window else { return }

        // Reset state
        searchField.stringValue = ""
        searchResults = []
        tableView.reloadData()

        // Position centered above main window
        if let mainWindow = NSApp.mainWindow {
            let mainFrame = mainWindow.frame
            let panelSize = panel.frame.size
            let x = mainFrame.midX - panelSize.width / 2
            let y = mainFrame.midY + 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        // Animate in
        panel.alphaValue = 0
        panel.setFrame(panel.frame.offsetBy(dx: 0, dy: -10), display: false)

        super.showWindow(sender)
        panel.makeFirstResponder(searchField)

        if !ThemeManager.shared.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = ThemeManager.shared.current.animationFast
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: 10), display: true)
            }
        } else {
            panel.alphaValue = 1
        }
    }

    override func close() {
        guard let panel = window else {
            super.close()
            return
        }

        if !ThemeManager.shared.reduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = ThemeManager.shared.current.animationFast * 0.7
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: -5), display: true)
            }, completionHandler: {
                super.close()
                panel.alphaValue = 1
            })
        } else {
            super.close()
        }
    }

    // MARK: - Search

    private func performSearch(_ query: String) {
        if query.isEmpty {
            searchResults = []
        } else {
            searchResults = workspaceManager?.searchFiles(matching: query) ?? []
        }
        tableView.reloadData()

        // Auto-select first result
        if !searchResults.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - Actions

    @objc private func handleDoubleClick(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0, row < searchResults.count else { return }

        let url = searchResults[row]
        onFileSelected?(url)
        close()
    }

    /// Select file at current selection and close
    func confirmSelection() {
        let row = tableView.selectedRow
        guard row >= 0, row < searchResults.count else { return }

        let url = searchResults[row]
        onFileSelected?(url)
        close()
    }

    /// Move selection up
    func selectPrevious() {
        let current = tableView.selectedRow
        if current > 0 {
            tableView.selectRowIndexes(IndexSet(integer: current - 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(current - 1)
        }
    }

    /// Move selection down
    func selectNext() {
        let current = tableView.selectedRow
        if current < searchResults.count - 1 {
            tableView.selectRowIndexes(IndexSet(integer: current + 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(current + 1)
        }
    }
}

// MARK: - NSTextFieldDelegate

extension QuickOpenController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        performSearch(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmSelection()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            close()
            return true
        } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
            selectPrevious()
            return true
        } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
            selectNext()
            return true
        }
        return false
    }
}

// MARK: - NSTableViewDataSource

extension QuickOpenController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return searchResults.count
    }
}

// MARK: - NSTableViewDelegate

extension QuickOpenController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < searchResults.count else { return nil }

        let url = searchResults[row]
        let cellIdentifier = NSUserInterfaceItemIdentifier("QuickOpenResultCell")
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? QuickOpenResultCell

        if cell == nil {
            cell = QuickOpenResultCell()
            cell?.identifier = cellIdentifier
        }

        // Build relative path
        var relativePath = url.path
        if let root = workspaceManager?.workspaceRoot {
            relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
        }

        cell?.configure(url: url, relativePath: relativePath)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowIdentifier = NSUserInterfaceItemIdentifier("QuickOpenRowView")
        var rowView = tableView.makeView(withIdentifier: rowIdentifier, owner: self) as? QuickOpenRowView

        if rowView == nil {
            rowView = QuickOpenRowView()
            rowView?.identifier = rowIdentifier
        }

        return rowView
    }
}

// MARK: - Custom Row View

/// Custom row view for Quick Open results with themed selection.
final class QuickOpenRowView: NSTableRowView {

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current

        let selectionRect = bounds.insetBy(dx: 4, dy: 2)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: theme.radiusSM, yRadius: theme.radiusSM)

        colors.quickOpenResultSelected.setFill()
        path.fill()

        // Accent border
        colors.accentPrimary.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        return .normal
    }
}
