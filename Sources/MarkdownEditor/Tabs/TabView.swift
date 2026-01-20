import AppKit

/// View for a single tab in the tab bar.
///
/// Shows title, dirty indicator, and close button.
/// Supports hover states, animations, and theming.
final class TabView: NSView, NSGestureRecognizerDelegate {

    /// Tab info for display.
    var tabInfo: TabInfo? {
        didSet {
            updateDisplay()
        }
    }

    /// Whether this tab is active.
    var isActive: Bool = false {
        didSet {
            updateAppearance(animated: true)
        }
    }

    /// Callback when tab is clicked.
    var onActivate: (() -> Void)?

    /// Callback when close button is clicked.
    var onClose: (() -> Void)?

    private var titleLabel: NSTextField!
    private var dirtyIndicator: NSView!
    private var closeButton: NSButton!
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false

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
        layer?.cornerRadius = ThemeManager.shared.current.radiusMD
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        // Title label
        titleLabel = NSTextField(labelWithString: "Untitled")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = ThemeManager.shared.current.uiFont(size: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Dirty indicator (dot with glow)
        dirtyIndicator = NSView()
        dirtyIndicator.translatesAutoresizingMaskIntoConstraints = false
        dirtyIndicator.wantsLayer = true
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
        closeButton.alphaValue = 0 // Hidden by default, fade in on hover
        addSubview(closeButton)

        // Constraints
        NSLayoutConstraint.activate([
            dirtyIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dirtyIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyIndicator.widthAnchor.constraint(equalToConstant: 6),
            dirtyIndicator.heightAnchor.constraint(equalToConstant: 6),

            titleLabel.leadingAnchor.constraint(equalTo: dirtyIndicator.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -6),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16)
        ])

        // Click gesture for activation
        let click = NSClickGestureRecognizer(target: self, action: #selector(tabClicked))
        click.delegate = self
        addGestureRecognizer(click)

        applyTheme()
    }

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        themeObserver = observeTheme { [weak self] in
            self?.applyTheme()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance(animated: true)
    }

    // MARK: - Theming

    func applyTheme() {
        let theme = ThemeManager.shared.current
        let colors = ThemeManager.shared.colors

        // Update fonts
        titleLabel.font = theme.uiFont(size: 12, weight: .medium)

        // Update dirty indicator
        dirtyIndicator.layer?.backgroundColor = colors.tabDirtyIndicator.cgColor

        // Add subtle glow to dirty indicator
        if !(dirtyIndicator.isHidden) {
            dirtyIndicator.layer?.shadowColor = colors.tabDirtyIndicator.cgColor
            dirtyIndicator.layer?.shadowOffset = .zero
            dirtyIndicator.layer?.shadowRadius = 4
            dirtyIndicator.layer?.shadowOpacity = 0.6
        }

        // Update close button tint
        closeButton.contentTintColor = colors.tabText

        updateAppearance(animated: false)
    }

    private func updateDisplay() {
        titleLabel.stringValue = tabInfo?.title ?? "Untitled"
        dirtyIndicator.isHidden = !(tabInfo?.isDirty ?? false)

        // Update dirty indicator glow
        if !dirtyIndicator.isHidden {
            let colors = ThemeManager.shared.colors
            dirtyIndicator.layer?.shadowColor = colors.tabDirtyIndicator.cgColor
            dirtyIndicator.layer?.shadowOffset = .zero
            dirtyIndicator.layer?.shadowRadius = 4
            dirtyIndicator.layer?.shadowOpacity = 0.6
        }
    }

    private func updateAppearance(animated: Bool) {
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current
        let duration = animated ? theme.animationFast : 0

        // Determine background color
        let bgColor: NSColor
        if isActive {
            bgColor = colors.tabActiveBackground
        } else if isHovered {
            bgColor = colors.tabHoverBackground
        } else {
            bgColor = .clear
        }

        // Determine text color
        let textColor = isActive ? colors.tabActiveText : colors.tabText

        // Determine close button visibility
        let closeButtonAlpha: CGFloat = (isHovered || isActive) ? 1.0 : 0.0

        // Apply with animation
        if ThemeManager.shared.reduceMotion || !animated {
            layer?.backgroundColor = bgColor.cgColor
            titleLabel.textColor = textColor
            closeButton.alphaValue = closeButtonAlpha
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.allowsImplicitAnimation = true

                self.layer?.backgroundColor = bgColor.cgColor
                self.titleLabel.animator().textColor = textColor
                self.closeButton.animator().alphaValue = closeButtonAlpha
            }
        }

        // Add subtle shadow to active tab
        if isActive {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOffset = NSSize(width: 0, height: -1)
            layer?.shadowRadius = 3
            layer?.shadowOpacity = 0.15
        } else {
            layer?.shadowOpacity = 0
        }
    }

    // MARK: - Actions

    @objc private func tabClicked() {
        onActivate?()
    }

    @objc private func closeButtonClicked() {
        onClose?()
    }

    // MARK: - NSGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        // Don't let the tab click gesture intercept clicks on the close button
        let locationInView = convert(event.locationInWindow, from: nil)
        return !closeButton.frame.contains(locationInView)
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 160, height: 32)
    }
}
