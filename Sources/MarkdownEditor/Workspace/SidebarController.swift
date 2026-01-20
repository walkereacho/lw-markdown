import AppKit

/// Controller for the file tree sidebar.
///
/// Uses `NSOutlineView` to display the workspace file structure.
/// Handles user interaction for opening files.
/// Supports theming via ThemeManager.
final class SidebarController: NSViewController {

    /// Workspace manager providing file tree data.
    var workspaceManager: WorkspaceManager? {
        didSet {
            updateEmptyState()
            outlineView?.reloadData()
        }
    }

    /// Callback when user selects a file to open.
    var onFileSelected: ((URL) -> Void)?

    /// The outline view displaying the file tree.
    private var outlineView: NSOutlineView!

    /// Scroll view containing the outline view.
    private var scrollView: NSScrollView!

    /// Right border view.
    private var borderView: NSView!

    /// Empty state view.
    private var emptyStateView: SidebarEmptyStateView!

    /// Theme observer token.
    private var themeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBorder()
        setupEmptyState()
        setupOutlineView()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        themeObserver = view.observeTheme { [weak self] in
            self?.applyTheme()
        }
    }

    private func setupBorder() {
        borderView = NSView()
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        view.addSubview(borderView)

        // Position on right edge, with top inset to clear the tab bar area
        let topInset: CGFloat = 36
        NSLayoutConstraint.activate([
            borderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            borderView.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset),
            borderView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            borderView.widthAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func setupEmptyState() {
        emptyStateView = SidebarEmptyStateView()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.onOpenWorkspace = { [weak self] in
            // Trigger open workspace action via responder chain
            NSApp.sendAction(#selector(AppDelegate.openWorkspaceAction(_:)), to: nil, from: self)
        }
        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            emptyStateView.topAnchor.constraint(equalTo: view.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupOutlineView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        view.addSubview(scrollView)

        // Create outline view
        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.rowHeight = 28
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = true
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.selectionHighlightStyle = .none
        outlineView.backgroundColor = .clear

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
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -1),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        updateEmptyState()
    }

    // MARK: - Empty State

    private func updateEmptyState() {
        let hasWorkspace = workspaceManager?.fileTree() != nil
        emptyStateView?.isHidden = hasWorkspace
        scrollView?.isHidden = !hasWorkspace
    }

    // MARK: - Theming

    private func applyTheme() {
        let colors = ThemeManager.shared.colors

        view.layer?.backgroundColor = colors.sidebarBackground.cgColor
        borderView?.layer?.backgroundColor = colors.shellBorder.cgColor
        outlineView?.backgroundColor = .clear
        emptyStateView?.applyTheme()

        // Reload to update cell styling
        outlineView?.reloadData()
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
        updateEmptyState()
        outlineView?.reloadData()
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return workspaceManager?.fileTree()?.children?.count ?? 0
        }
        if let node = item as? FileTreeNode {
            return node.children?.count ?? 0
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
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

        let cellIdentifier = NSUserInterfaceItemIdentifier("SidebarFileCell")
        var cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? SidebarFileCell

        if cell == nil {
            cell = SidebarFileCell()
            cell?.identifier = cellIdentifier
        }

        cell?.configure(with: node)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rowIdentifier = NSUserInterfaceItemIdentifier("SidebarRowView")
        var rowView = outlineView.makeView(withIdentifier: rowIdentifier, owner: self) as? SidebarRowView

        if rowView == nil {
            rowView = SidebarRowView()
            rowView?.identifier = rowIdentifier
        }
        return rowView
    }
}

// MARK: - Custom Row View

final class SidebarRowView: NSTableRowView {

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current

        let selectionRect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: theme.radiusSM, yRadius: theme.radiusSM)

        colors.sidebarItemSelected.setFill()
        path.fill()

        colors.accentPrimary.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        return .normal
    }
}

// MARK: - Empty State View

/// View shown when no workspace is open.
final class SidebarEmptyStateView: NSView {

    var onOpenWorkspace: (() -> Void)?

    private var iconView: NSImageView!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var openButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true

        // Container for centering
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        // Folder icon
        iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Open folder")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
        container.addSubview(iconView)

        // Title
        titleLabel = NSTextField(labelWithString: "No Workspace")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        container.addSubview(titleLabel)

        // Subtitle
        subtitleLabel = NSTextField(labelWithString: "Open a folder to see\nyour files here")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        container.addSubview(subtitleLabel)

        // Open button
        openButton = NSButton(title: "Open Folder", target: self, action: #selector(openButtonClicked))
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        container.addSubview(openButton)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            container.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),

            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            openButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            openButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            openButton.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        applyTheme()
    }

    func applyTheme() {
        let theme = ThemeManager.shared.current
        let colors = ThemeManager.shared.colors

        iconView.contentTintColor = colors.accentPrimary.withAlphaComponent(0.6)

        titleLabel.font = theme.uiFont(size: 13, weight: .medium)
        titleLabel.textColor = colors.sidebarText

        subtitleLabel.font = theme.uiFont(size: 11, weight: .regular)
        subtitleLabel.textColor = colors.sidebarSecondaryText

        // Style the button with theme font
        openButton.font = theme.uiFont(size: 11, weight: .medium)
    }

    @objc private func openButtonClicked() {
        onOpenWorkspace?()
    }
}

