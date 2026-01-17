import AppKit

/// View containing all tabs in a horizontal bar.
///
/// Uses NSStackView for horizontal layout of tabs.
final class TabBarView: NSView {

    /// Tab manager providing tab state.
    weak var tabManager: TabManager? {
        didSet {
            rebuildTabs()
        }
    }

    /// Stack view containing tabs.
    private var stackView: NSStackView!

    /// Tab views keyed by document ID.
    private var tabViews: [UUID: TabView] = [:]

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
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.alignment = .centerY
        stackView.distribution = .fill
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }
}
