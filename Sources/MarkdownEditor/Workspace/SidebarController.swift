import AppKit

/// Controller for the file tree sidebar.
///
/// Uses `NSOutlineView` to display the workspace file structure.
/// Handles user interaction for opening files.
final class SidebarController: NSViewController {

    /// Workspace manager providing file tree data.
    var workspaceManager: WorkspaceManager? {
        didSet {
            outlineView?.reloadData()
        }
    }

    /// Callback when user selects a file to open.
    var onFileSelected: ((URL) -> Void)?

    /// The outline view displaying the file tree.
    private var outlineView: NSOutlineView!

    /// Scroll view containing the outline view.
    private var scrollView: NSScrollView!

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOutlineView()
    }

    private func setupOutlineView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)

        // Create outline view
        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = true

        // Add column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.title = "Files"
        column.minWidth = 100
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        // Wire up data source and delegate
        outlineView.dataSource = self
        outlineView.delegate = self

        // Enable double-click to open
        outlineView.target = self
        outlineView.doubleAction = #selector(handleDoubleClick(_:))

        scrollView.documentView = outlineView

        // Constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func handleDoubleClick(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FileTreeNode,
              !node.isDirectory else { return }

        onFileSelected?(node.url)
    }

    // MARK: - Refresh

    func refresh() {
        outlineView?.reloadData()
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // Root level
            return workspaceManager?.fileTree()?.children?.count ?? 0
        }

        if let node = item as? FileTreeNode {
            return node.children?.count ?? 0
        }

        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            // Root level
            return workspaceManager?.fileTree()?.children?[index] ?? FileTreeNode(url: URL(fileURLWithPath: "/"), isDirectory: false, children: nil)
        }

        if let node = item as? FileTreeNode {
            return node.children?[index] ?? FileTreeNode(url: URL(fileURLWithPath: "/"), isDirectory: false, children: nil)
        }

        return FileTreeNode(url: URL(fileURLWithPath: "/"), isDirectory: false, children: nil)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? FileTreeNode {
            return node.isDirectory && (node.children?.isEmpty == false)
        }
        return false
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileTreeNode else { return nil }

        let cellIdentifier = NSUserInterfaceItemIdentifier("FileCell")
        var cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellIdentifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell?.addSubview(imageView)
            cell?.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell?.addSubview(textField)
            cell?.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }

        cell?.textField?.stringValue = node.name
        cell?.imageView?.image = NSWorkspace.shared.icon(forFile: node.url.path)

        return cell
    }
}
