import AppKit

final class CommentCardView: NSView {
    private(set) var comment: Comment
    var onToggleResolved: ((UUID) -> Void)?
    var onToggleCollapsed: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onClick: ((UUID) -> Void)?

    private var checkbox: NSButton!
    private var anchorLabel: NSTextField!
    private var contentLabel: NSTextField!
    private var disclosureButton: NSButton!
    private var deleteButton: NSButton!

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

        checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleResolved))
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)

        disclosureButton = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Expand")!, target: self, action: #selector(toggleCollapsed))
        disclosureButton.translatesAutoresizingMaskIntoConstraints = false
        disclosureButton.bezelStyle = .inline
        disclosureButton.isBordered = false
        addSubview(disclosureButton)

        anchorLabel = NSTextField(labelWithString: "")
        anchorLabel.translatesAutoresizingMaskIntoConstraints = false
        anchorLabel.lineBreakMode = .byTruncatingTail
        anchorLabel.maximumNumberOfLines = 1
        addSubview(anchorLabel)

        contentLabel = NSTextField(labelWithString: "")
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 0
        contentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(contentLabel)

        deleteButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Delete")!, target: self, action: #selector(deleteComment))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.isHidden = true
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            checkbox.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            disclosureButton.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 4),
            disclosureButton.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
            disclosureButton.widthAnchor.constraint(equalToConstant: 16),
            anchorLabel.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 4),
            anchorLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -4),
            anchorLabel.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 16),
            contentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            contentLabel.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 4),
            contentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
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
        let suffix = needsEllipsis ? "..." : ""
        anchorLabel.stringValue = "\"\(truncated)\(suffix)\""
        contentLabel.stringValue = comment.content
        contentLabel.isHidden = comment.isCollapsed
        checkbox.state = comment.isResolved ? .on : .off
        let iconName = comment.isCollapsed ? "chevron.right" : "chevron.down"
        disclosureButton.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        alphaValue = comment.isResolved ? 0.6 : 1.0
    }

    func applyTheme() {
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current
        layer?.backgroundColor = colors.shellSecondaryBackground.cgColor
        layer?.cornerRadius = theme.radiusSM
        anchorLabel.font = theme.uiFont(size: 11, weight: .medium)
        anchorLabel.textColor = colors.sidebarSecondaryText
        contentLabel.font = theme.uiFont(size: 12, weight: .regular)
        contentLabel.textColor = colors.sidebarText
        deleteButton.contentTintColor = colors.sidebarSecondaryText
        disclosureButton.contentTintColor = colors.sidebarSecondaryText
    }

    @objc private func toggleResolved() { onToggleResolved?(comment.id) }
    @objc private func toggleCollapsed() { onToggleCollapsed?(comment.id) }
    @objc private func deleteComment() { onDelete?(comment.id) }
    @objc private func cardClicked() { onClick?(comment.id) }

    override func mouseEntered(with event: NSEvent) { deleteButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { deleteButton.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hitView = hitTest(location)
        // Only trigger card click if clicking on background, not on controls
        if hitView === self || hitView === anchorLabel || hitView === contentLabel {
            onClick?(comment.id)
        } else {
            super.mouseDown(with: event)
        }
    }
}
