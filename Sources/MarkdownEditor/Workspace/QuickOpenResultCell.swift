import AppKit

/// Custom cell view for Quick Open search results.
///
/// Shows file icon, filename (bold), and path (muted).
final class QuickOpenResultCell: NSTableCellView {

    /// File URL this cell represents.
    private var fileURL: URL?

    /// Filename label (bold).
    private var filenameLabel: NSTextField!

    /// Path label (muted, smaller).
    private var pathLabel: NSTextField!

    /// File icon.
    private var iconView: NSImageView!

    /// Background view for hover/selection.
    private var backgroundView: NSView!

    /// Whether this cell is hovered.
    private var isHovered: Bool = false {
        didSet {
            updateAppearance(animated: true)
        }
    }

    /// Tracking area for hover.
    private var trackingArea: NSTrackingArea?

    /// Theme observer.
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

        // Background
        backgroundView = NSView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = ThemeManager.shared.current.radiusSM
        addSubview(backgroundView, positioned: .below, relativeTo: nil)

        // Icon
        iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        // Filename (bold)
        filenameLabel = NSTextField(labelWithString: "")
        filenameLabel.translatesAutoresizingMaskIntoConstraints = false
        filenameLabel.font = ThemeManager.shared.current.uiFont(size: 13, weight: .semibold)
        filenameLabel.lineBreakMode = .byTruncatingTail
        addSubview(filenameLabel)

        // Path (muted)
        pathLabel = NSTextField(labelWithString: "")
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = ThemeManager.shared.current.uiFont(size: 11, weight: .regular)
        pathLabel.lineBreakMode = .byTruncatingHead
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            filenameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            filenameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            filenameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            pathLabel.leadingAnchor.constraint(equalTo: filenameLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: filenameLabel.bottomAnchor, constant: 2),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
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
        fileURL = nil
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

    func configure(url: URL, relativePath: String) {
        fileURL = url
        filenameLabel.stringValue = url.lastPathComponent
        pathLabel.stringValue = relativePath

        // Icon
        let colors = ThemeManager.shared.colors
        if url.lastPathComponent.hasSuffix(".md") || url.lastPathComponent.hasSuffix(".markdown") {
            iconView.image = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: "Markdown")
            iconView.contentTintColor = colors.accentPrimary
        } else {
            iconView.image = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: "File")
            iconView.contentTintColor = colors.sidebarIcon
        }
    }

    // MARK: - Theming

    func applyTheme() {
        let theme = ThemeManager.shared.current
        let colors = ThemeManager.shared.colors

        filenameLabel.font = theme.uiFont(size: 13, weight: .semibold)
        filenameLabel.textColor = colors.tabActiveText

        pathLabel.font = theme.uiFont(size: 11, weight: .regular)
        pathLabel.textColor = colors.sidebarSecondaryText

        backgroundView.layer?.cornerRadius = theme.radiusSM

        updateAppearance(animated: false)
    }

    private func updateAppearance(animated: Bool) {
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current

        let bgColor: NSColor = isHovered ? colors.quickOpenResultHover : .clear

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
