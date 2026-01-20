import AppKit

/// Custom cell view for sidebar file tree items.
///
/// Features themed styling, hover states, and custom icons.
final class SidebarFileCell: NSTableCellView {

    /// Whether this cell represents a directory.
    var isDirectory: Bool = false {
        didSet {
            updateIcon()
        }
    }

    /// Whether this cell is currently hovered.
    private var isHovered: Bool = false {
        didSet {
            updateAppearance(animated: true)
        }
    }

    /// Background view for hover/selection states.
    private var backgroundView: NSView!

    /// Chevron indicator for folders.
    private var chevronView: NSImageView?

    /// Tracking area for hover detection.
    private var trackingArea: NSTrackingArea?

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

        // Background view for hover/selection
        backgroundView = NSView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = ThemeManager.shared.current.radiusSM
        addSubview(backgroundView, positioned: .below, relativeTo: nil)

        // Icon
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        self.imageView = icon

        // Label
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.font = ThemeManager.shared.current.uiFont(size: 13, weight: .regular)
        addSubview(label)
        self.textField = label

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applyTheme()
    }

    // MARK: - Lifecycle

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil {
            themeObserver = observeTheme { [weak self] in
                self?.applyTheme()
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
        isDirectory = false
        backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
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
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    // MARK: - Configuration

    func configure(with node: FileTreeNode) {
        textField?.stringValue = node.name
        isDirectory = node.isDirectory
        updateIcon()
    }

    private func updateIcon() {
        let colors = ThemeManager.shared.colors

        if isDirectory {
            // Folder icon with accent tint
            let folderImage = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
            imageView?.image = folderImage
            imageView?.contentTintColor = colors.accentPrimary
        } else {
            // File icon - use special icon for markdown
            let fileName = textField?.stringValue ?? ""
            if fileName.hasSuffix(".md") || fileName.hasSuffix(".markdown") {
                let mdImage = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: "Markdown file")
                imageView?.image = mdImage
                imageView?.contentTintColor = colors.sidebarIcon
            } else {
                let fileImage = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: "File")
                imageView?.image = fileImage
                imageView?.contentTintColor = colors.sidebarIcon
            }
        }
    }

    // MARK: - Theming

    func applyTheme() {
        let theme = ThemeManager.shared.current
        let colors = ThemeManager.shared.colors

        textField?.font = theme.uiFont(size: 13, weight: .regular)
        textField?.textColor = colors.sidebarText

        backgroundView.layer?.cornerRadius = theme.radiusSM

        updateIcon()
        updateAppearance(animated: false)
    }

    private func updateAppearance(animated: Bool) {
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current

        let bgColor: NSColor = isHovered ? colors.sidebarItemHover : .clear

        if ThemeManager.shared.reduceMotion || !animated {
            backgroundView.layer?.backgroundColor = bgColor.cgColor
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = theme.animationFast
                context.allowsImplicitAnimation = true
                self.backgroundView.layer?.backgroundColor = bgColor.cgColor
            }
        }
    }
}
