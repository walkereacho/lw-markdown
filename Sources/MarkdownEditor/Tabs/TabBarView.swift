import AppKit

/// View containing all tabs in a horizontal bar.
///
/// Uses NSStackView for horizontal layout of tabs.
/// Supports theming via ThemeManager.
final class TabBarView: NSView {

    /// Tab manager providing tab state.
    weak var tabManager: TabManager? {
        didSet {
            tabManager?.onTabsChanged = { [weak self] in
                self?.rebuildTabs()
            }
            rebuildTabs()
        }
    }

    /// Stack view containing tabs.
    private var stackView: NSStackView!

    /// Bottom border layer for depth.
    private var borderLayer: CALayer!

    /// Tab views keyed by document ID.
    private var tabViews: [UUID: TabView] = [:]

    /// Theme observer token.
    private var themeObserver: NSObjectProtocol?

    // MARK: - Initialization

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

        // Bottom border for depth
        borderLayer = CALayer()
        borderLayer.zPosition = 1
        layer?.addSublayer(borderLayer)

        stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        themeObserver = observeTheme { [weak self] in
            self?.applyTheme()
        }
    }

    // MARK: - Theming

    private func applyTheme() {
        let colors = ThemeManager.shared.colors
        layer?.backgroundColor = colors.tabBarBackground.cgColor
        borderLayer.backgroundColor = colors.shellBorder.cgColor

        // Update existing tabs
        for tabView in tabViews.values {
            tabView.applyTheme()
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Position border at bottom
        borderLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    override var wantsUpdateLayer: Bool {
        return true
    }

    override func updateLayer() {
        applyTheme()
    }

    // MARK: - Tab Management

    /// Rebuild all tabs from tab manager state.
    func rebuildTabs() {
        // Remove old tabs
        for tabView in tabViews.values {
            tabView.removeFromSuperview()
        }
        tabViews.removeAll()

        // Create new tabs
        guard let manager = tabManager else { return }

        for tabInfo in manager.tabs {
            let tabView = TabView()
            tabView.tabInfo = tabInfo
            tabView.isActive = tabInfo.documentId == manager.activeDocumentId

            tabView.onActivate = { [weak self, weak manager] in
                manager?.activateTab(documentId: tabInfo.documentId)
                self?.updateActiveStates()
            }

            tabView.onClose = { [weak manager] in
                _ = manager?.closeTab(documentId: tabInfo.documentId)
            }

            stackView.addArrangedSubview(tabView)
            tabViews[tabInfo.documentId] = tabView
        }
    }

    /// Update tab info (e.g., after dirty state changes).
    func updateTabs() {
        guard let manager = tabManager else { return }

        for tabInfo in manager.tabs {
            tabViews[tabInfo.documentId]?.tabInfo = tabInfo
        }
        updateActiveStates()
    }

    private func updateActiveStates() {
        guard let manager = tabManager else { return }

        for (id, tabView) in tabViews {
            tabView.isActive = id == manager.activeDocumentId
        }
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 36)
    }
}
