import AppKit

/// View for a single tab in the tab bar.
///
/// Shows title, dirty indicator, and close button.
final class TabView: NSView {

    /// Tab info for display.
    var tabInfo: TabInfo? {
        didSet {
            updateDisplay()
        }
    }

    /// Whether this tab is active.
    var isActive: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    /// Callback when tab is clicked.
    var onActivate: (() -> Void)?

    /// Callback when close button is clicked.
    var onClose: (() -> Void)?

    private var titleLabel: NSTextField!
    private var dirtyIndicator: NSView!
    private var closeButton: NSButton!

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

        // Title label
        titleLabel = NSTextField(labelWithString: "Untitled")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Dirty indicator (dot)
        dirtyIndicator = NSView()
        dirtyIndicator.translatesAutoresizingMaskIntoConstraints = false
        dirtyIndicator.wantsLayer = true
        dirtyIndicator.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dirtyIndicator.layer?.cornerRadius = 3
        dirtyIndicator.isHidden = true
        addSubview(dirtyIndicator)

        // Close button
        closeButton = NSButton()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        addSubview(closeButton)

        // Constraints
        NSLayoutConstraint.activate([
            dirtyIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dirtyIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyIndicator.widthAnchor.constraint(equalToConstant: 6),
            dirtyIndicator.heightAnchor.constraint(equalToConstant: 6),

            titleLabel.leadingAnchor.constraint(equalTo: dirtyIndicator.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16)
        ])

        // Click gesture for activation
        let click = NSClickGestureRecognizer(target: self, action: #selector(tabClicked))
        addGestureRecognizer(click)

        updateAppearance()
    }

    private func updateDisplay() {
        titleLabel.stringValue = tabInfo?.title ?? "Untitled"
        dirtyIndicator.isHidden = !(tabInfo?.isDirty ?? false)
    }

    private func updateAppearance() {
        if isActive {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    @objc private func tabClicked() {
        onActivate?()
    }

    @objc private func closeButtonClicked() {
        onClose?()
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 150, height: 28)
    }
}
