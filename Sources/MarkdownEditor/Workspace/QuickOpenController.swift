import AppKit

/// Controller for the quick open panel (Cmd+P).
///
/// Shows a search field and filtered list of files.
final class QuickOpenController: NSWindowController {

    /// Workspace manager for file search.
    var workspaceManager: WorkspaceManager?

    /// Callback when user selects a file.
    var onFileSelected: ((URL) -> Void)?

    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var searchResults: [URL] = []

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Open"
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.level = .floating
        window.center()

        super.init(window: window)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Search field
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search files..."
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        contentView.addSubview(searchField)

        // Scroll view with table
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 24

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
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(searchField)
        searchField.stringValue = ""
        searchResults = []
        tableView.reloadData()
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        let query = sender.stringValue
        if query.isEmpty {
            searchResults = []
        } else {
            searchResults = workspaceManager?.searchFiles(matching: query) ?? []
        }
        tableView.reloadData()
    }

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
        let cellIdentifier = NSUserInterfaceItemIdentifier("FileCell")
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellIdentifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell?.addSubview(textField)
            cell?.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }

        // Show relative path from workspace root
        if let root = workspaceManager?.workspaceRoot {
            let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
            cell?.textField?.stringValue = relativePath
        } else {
            cell?.textField?.stringValue = url.lastPathComponent
        }

        return cell
    }
}
