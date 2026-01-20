import AppKit

final class CommentCardView: NSView {
    private(set) var comment: Comment
    var onToggleResolved: ((UUID) -> Void)?
    var onToggleCollapsed: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onClick: ((UUID) -> Void)?

    // Card container for elevation effect
    private var cardContainer: NSView!
    private var accentBar: NSView!
    private var headerContainer: NSView!
    private var checkbox: NSButton!
    private var anchorLabel: NSTextField!
    private var timestampLabel: NSTextField!
    private var contentLabel: NSTextField!
    private var disclosureButton: NSButton!
    private var deleteButton: NSButton!
    private var isHovered = false

    init(comment: Comment) {
        self.comment = comment
        super.init(frame: .zero)
        setupViews()
        applyTheme()
        update(with: comment)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // Main card container with shadow
        cardContainer = NSView()
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.wantsLayer = true
        addSubview(cardContainer)

        // Accent bar on left edge
        accentBar = NSView()
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.wantsLayer = true
        cardContainer.addSubview(accentBar)

        // Header row container
        headerContainer = NSView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(headerContainer)

        disclosureButton = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Expand")!, target: self, action: #selector(toggleCollapsed))
        disclosureButton.translatesAutoresizingMaskIntoConstraints = false
        disclosureButton.bezelStyle = .inline
        disclosureButton.isBordered = false
        headerContainer.addSubview(disclosureButton)

        anchorLabel = NSTextField(labelWithString: "")
        anchorLabel.translatesAutoresizingMaskIntoConstraints = false
        anchorLabel.lineBreakMode = .byTruncatingTail
        anchorLabel.maximumNumberOfLines = 1
        headerContainer.addSubview(anchorLabel)

        timestampLabel = NSTextField(labelWithString: "")
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.lineBreakMode = .byClipping
        timestampLabel.maximumNumberOfLines = 1
        timestampLabel.setContentHuggingPriority(.required, for: .horizontal)
        headerContainer.addSubview(timestampLabel)

        deleteButton = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")!, target: self, action: #selector(deleteComment))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.alphaValue = 0
        headerContainer.addSubview(deleteButton)

        contentLabel = NSTextField(labelWithString: "")
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 0
        contentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cardContainer.addSubview(contentLabel)

        // Resolve button at bottom right (checkmark icon like trash)
        checkbox = NSButton(image: NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Mark resolved")!, target: self, action: #selector(toggleResolved))
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.bezelStyle = .inline
        checkbox.isBordered = false
        cardContainer.addSubview(checkbox)

        NSLayoutConstraint.activate([
            // Card container fills view with padding for shadow
            cardContainer.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            cardContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            cardContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            cardContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            // Accent bar on left
            accentBar.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 3),

            // Header container
            headerContainer.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 12),
            headerContainer.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            headerContainer.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),

            // Disclosure at leading edge
            disclosureButton.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            disclosureButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            disclosureButton.widthAnchor.constraint(equalToConstant: 16),
            disclosureButton.heightAnchor.constraint(equalToConstant: 16),

            // Anchor label
            anchorLabel.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 6),
            anchorLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            anchorLabel.trailingAnchor.constraint(lessThanOrEqualTo: timestampLabel.leadingAnchor, constant: -8),

            // Timestamp
            timestampLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            timestampLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            // Delete button
            deleteButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            deleteButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 18),
            deleteButton.heightAnchor.constraint(equalToConstant: 18),

            // Header height
            headerContainer.heightAnchor.constraint(equalToConstant: 20),

            // Content label
            contentLabel.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            contentLabel.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -40),
            contentLabel.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 8),
            contentLabel.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -12),

            // Resolve button at bottom right - matches delete button size and spacing
            checkbox.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),
            checkbox.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -12),
            checkbox.widthAnchor.constraint(equalToConstant: 18),
            checkbox.heightAnchor.constraint(equalToConstant: 18),
        ])

        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    func update(with comment: Comment) {
        self.comment = comment
        // Show only first line, truncated to 30 chars
        let firstLine = comment.anchorText.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? comment.anchorText
        let truncated = String(firstLine.prefix(30))
        let needsEllipsis = firstLine.count > 30 || comment.anchorText.contains("\n")
        let suffix = needsEllipsis ? "…" : ""
        anchorLabel.stringValue = "\"\(truncated)\(suffix)\""
        contentLabel.stringValue = comment.content
        contentLabel.isHidden = comment.isCollapsed
        let resolveIcon = comment.isResolved ? "checkmark.circle.fill" : "checkmark.circle"
        checkbox.image = NSImage(systemSymbolName: resolveIcon, accessibilityDescription: nil)
        let iconName = comment.isCollapsed ? "chevron.right" : "chevron.down"
        disclosureButton.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)

        // Format timestamp
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timestampLabel.stringValue = formatter.localizedString(for: comment.createdAt, relativeTo: Date())

        // Apply resolved state
        applyResolvedState()
    }

    private func applyResolvedState() {
        let colors = ThemeManager.shared.colors
        if comment.isResolved {
            cardContainer.alphaValue = 0.6
            accentBar.layer?.backgroundColor = colors.sidebarSecondaryText.withAlphaComponent(0.3).cgColor
            checkbox.contentTintColor = colors.accentPrimary
        } else {
            cardContainer.alphaValue = 1.0
            accentBar.layer?.backgroundColor = colors.accentPrimary.cgColor
            checkbox.contentTintColor = colors.sidebarSecondaryText
        }
    }

    func applyTheme() {
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current

        // Card styling - clean, subtle appearance
        cardContainer.layer?.backgroundColor = colors.shellBackground.cgColor
        cardContainer.layer?.cornerRadius = theme.radiusSM
        cardContainer.layer?.borderWidth = 1
        cardContainer.layer?.borderColor = colors.shellBorder.withAlphaComponent(0.6).cgColor

        // Apply subtle shadow
        cardContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.06).cgColor
        cardContainer.layer?.shadowOffset = CGSize(width: 0, height: 1)
        cardContainer.layer?.shadowRadius = 2
        cardContainer.layer?.shadowOpacity = 1.0
        cardContainer.layer?.masksToBounds = false

        // Accent bar rounds top-left and bottom-left
        accentBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        accentBar.layer?.cornerRadius = theme.radiusSM
        accentBar.layer?.backgroundColor = colors.accentPrimary.cgColor

        // Typography
        anchorLabel.font = theme.uiFont(size: 12, weight: .semibold)
        anchorLabel.textColor = colors.sidebarText
        timestampLabel.font = theme.uiFont(size: 10, weight: .regular)
        timestampLabel.textColor = colors.sidebarSecondaryText.withAlphaComponent(0.7)
        contentLabel.font = theme.uiFont(size: 13, weight: .regular)
        contentLabel.textColor = colors.sidebarText.withAlphaComponent(0.9)

        // Button styling
        deleteButton.contentTintColor = colors.tabDirtyIndicator.withAlphaComponent(0.8)
        disclosureButton.contentTintColor = colors.sidebarSecondaryText

        applyResolvedState()
        applyHoverState()
    }

    private func applyHoverState() {
        let colors = ThemeManager.shared.colors

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            if isHovered && !comment.isResolved {
                cardContainer.animator().layer?.shadowRadius = 4
                cardContainer.animator().layer?.shadowOffset = CGSize(width: 0, height: 2)
                cardContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.1).cgColor
                cardContainer.layer?.borderColor = colors.accentPrimary.withAlphaComponent(0.25).cgColor
                deleteButton.animator().alphaValue = 1.0
            } else {
                cardContainer.animator().layer?.shadowRadius = 2
                cardContainer.animator().layer?.shadowOffset = CGSize(width: 0, height: 1)
                cardContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.06).cgColor
                cardContainer.layer?.borderColor = colors.shellBorder.withAlphaComponent(0.6).cgColor
                deleteButton.animator().alphaValue = 0
            }
        }
    }

    @objc private func toggleResolved() { onToggleResolved?(comment.id) }
    @objc private func toggleCollapsed() { onToggleCollapsed?(comment.id) }
    @objc private func deleteComment() { onDelete?(comment.id) }
    @objc private func cardClicked() { onClick?(comment.id) }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyHoverState()
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hitView = hitTest(location)
        // Trigger click unless hitting an interactive control
        let isControl = hitView === checkbox || hitView === disclosureButton || hitView === deleteButton
        if !isControl {
            onClick?(comment.id)
        } else {
            super.mouseDown(with: event)
        }
    }
}
