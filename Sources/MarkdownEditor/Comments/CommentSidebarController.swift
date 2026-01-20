import AppKit

/// NSTextView subclass for comment input
final class CommentInputTextView: NSTextView {
    var onSubmit: (() -> Void)?
}

/// Flipped clip view to pin content to top of scroll view
final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

final class CommentSidebarController: NSViewController {
    var commentStore: CommentStore = CommentStore() { didSet { rebuildCommentList() } }
    var documentText: String = "" { didSet { rebuildCommentList(); scheduleOrphanCheck() } }
    var onCommentClicked: ((Comment) -> Void)?
    var onCommentStoreChanged: ((CommentStore) -> Void)?
    var onClose: (() -> Void)?

    private var headerView: NSView!
    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var resolvedSection: NSView!
    private var resolvedDisclosure: NSButton!
    private var resolvedStack: NSStackView!
    private var resolvedCollapsedConstraint: NSLayoutConstraint!
    private var resolvedExpandedConstraint: NSLayoutConstraint!
    private var borderView: NSView!
    private var inputTextView: CommentInputTextView?
    private var pendingAnchorText: String?
    private var pendingAnchorRange: Range<String.Index>?
    private var isResolvedExpanded = false
    private var themeObserver: NSObjectProtocol?
    private var orphanCheckWorkItem: DispatchWorkItem?

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeader()
        setupBorder()
        setupScrollView()
        setupResolvedSection()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        themeObserver = ThemeManager.shared.observeChanges { [weak self] in self?.applyTheme() }
        applyTheme()
    }

    private func setupHeader() {
        headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        view.addSubview(headerView)

        // Comment icon
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Comments")
        iconView.contentTintColor = ThemeManager.shared.colors.accentPrimary
        iconView.imageScaling = .scaleProportionallyUpOrDown
        headerView.addSubview(iconView)

        titleLabel = NSTextField(labelWithString: "Comments")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        // Count badge
        let countBadge = NSView()
        countBadge.translatesAutoresizingMaskIntoConstraints = false
        countBadge.wantsLayer = true
        countBadge.identifier = NSUserInterfaceItemIdentifier("countBadge")
        headerView.addSubview(countBadge)

        let countLabel = NSTextField(labelWithString: "0")
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.identifier = NSUserInterfaceItemIdentifier("countLabel")
        countBadge.addSubview(countLabel)

        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closeSidebar))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        headerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            countBadge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countBadge.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            countBadge.heightAnchor.constraint(equalToConstant: 20),
            countBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),

            countLabel.centerXAnchor.constraint(equalTo: countBadge.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: countBadge.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: countBadge.leadingAnchor, constant: 6),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: countBadge.trailingAnchor, constant: -6),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func setupBorder() {
        borderView = NSView()
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        view.addSubview(borderView)
        NSLayoutConstraint.activate([
            borderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            borderView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            borderView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            borderView.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func setupScrollView() {
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        // Use flipped clip view to pin content to top
        let clipView = TopAlignedClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        view.addSubview(scrollView)

        stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12  // Increased spacing for elevated cards
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 16, right: 10)
        // Ensure stack hugs content and stays at top
        stackView.setHuggingPriority(.required, for: .vertical)
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
        ])
    }

    private func setupResolvedSection() {
        resolvedSection = NSView()
        resolvedSection.translatesAutoresizingMaskIntoConstraints = false

        resolvedDisclosure = NSButton(title: "Resolved (0)", target: self, action: #selector(toggleResolvedSection))
        resolvedDisclosure.translatesAutoresizingMaskIntoConstraints = false
        resolvedDisclosure.bezelStyle = .inline
        resolvedDisclosure.isBordered = false
        resolvedDisclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        resolvedDisclosure.imagePosition = .imageLeading
        resolvedSection.addSubview(resolvedDisclosure)

        resolvedStack = NSStackView()
        resolvedStack.translatesAutoresizingMaskIntoConstraints = false
        resolvedStack.orientation = .vertical
        resolvedStack.alignment = .leading
        resolvedStack.spacing = 12
        resolvedStack.isHidden = true
        resolvedSection.addSubview(resolvedStack)

        // Create both constraints but only activate collapsed one initially
        resolvedCollapsedConstraint = resolvedDisclosure.bottomAnchor.constraint(equalTo: resolvedSection.bottomAnchor)
        resolvedExpandedConstraint = resolvedStack.bottomAnchor.constraint(equalTo: resolvedSection.bottomAnchor)

        NSLayoutConstraint.activate([
            resolvedDisclosure.leadingAnchor.constraint(equalTo: resolvedSection.leadingAnchor),
            resolvedDisclosure.topAnchor.constraint(equalTo: resolvedSection.topAnchor),
            resolvedStack.leadingAnchor.constraint(equalTo: resolvedSection.leadingAnchor),
            resolvedStack.trailingAnchor.constraint(equalTo: resolvedSection.trailingAnchor),
            resolvedStack.topAnchor.constraint(equalTo: resolvedDisclosure.bottomAnchor, constant: 8),
            resolvedCollapsedConstraint,  // Start collapsed
        ])
    }

    private func applyTheme() {
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current

        // Main view background
        view.layer?.backgroundColor = colors.sidebarBackground.cgColor

        // Header styling
        headerView.layer?.backgroundColor = colors.sidebarBackground.cgColor

        // Find and style header elements
        if let iconView = headerView.subviews.first(where: { $0 is NSImageView }) as? NSImageView {
            iconView.contentTintColor = colors.accentPrimary
        }

        titleLabel.font = theme.uiFont(size: 14, weight: .semibold)
        titleLabel.textColor = colors.sidebarText

        // Style count badge
        if let countBadge = headerView.subviews.first(where: { $0.identifier?.rawValue == "countBadge" }) {
            countBadge.layer?.backgroundColor = colors.accentPrimary.withAlphaComponent(0.15).cgColor
            countBadge.layer?.cornerRadius = 10

            if let countLabel = countBadge.subviews.first(where: { $0.identifier?.rawValue == "countLabel" }) as? NSTextField {
                countLabel.font = theme.uiFont(size: 11, weight: .semibold)
                countLabel.textColor = colors.accentPrimary
            }
        }

        closeButton.contentTintColor = colors.sidebarSecondaryText

        // Border
        borderView.layer?.backgroundColor = colors.shellBorder.cgColor

        // Resolved section styling
        resolvedDisclosure.font = theme.uiFont(size: 12, weight: .medium)
        resolvedDisclosure.contentTintColor = colors.sidebarSecondaryText
        (resolvedDisclosure.cell as? NSButtonCell)?.backgroundColor = .clear

        // Apply theme to all cards
        for case let card as CommentCardView in stackView.arrangedSubviews { card.applyTheme() }
        for case let card as CommentCardView in resolvedStack.arrangedSubviews { card.applyTheme() }
    }

    private func rebuildCommentList() {
        guard isViewLoaded, stackView != nil, resolvedStack != nil else { return }
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        resolvedStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let unresolved = commentStore.unresolvedComments(sortedBy: documentText)
        let resolved = commentStore.resolvedComments()

        // Update count badge
        if let countBadge = headerView?.subviews.first(where: { $0.identifier?.rawValue == "countBadge" }),
           let countLabel = countBadge.subviews.first(where: { $0.identifier?.rawValue == "countLabel" }) as? NSTextField {
            let count = commentStore.comments.count
            countLabel.stringValue = "\(count)"
            countBadge.isHidden = count == 0
        }

        for comment in unresolved {
            let card = createCommentCard(for: comment)
            stackView.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
        }
        if !resolved.isEmpty {
            resolvedDisclosure.title = "  Resolved (\(resolved.count))"
            stackView.addArrangedSubview(resolvedSection)
            for comment in resolved {
                let card = createCommentCard(for: comment)
                resolvedStack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: resolvedStack.widthAnchor).isActive = true
            }
        }
    }

    private func createCommentCard(for comment: Comment) -> CommentCardView {
        let card = CommentCardView(comment: comment)
        card.onToggleResolved = { [weak self] id in self?.toggleResolved(commentId: id) }
        card.onToggleCollapsed = { [weak self] id in self?.toggleCollapsed(commentId: id) }
        card.onDelete = { [weak self] id in self?.deleteComment(commentId: id) }
        card.onClick = { [weak self] id in
            guard let comment = self?.commentStore.comments.first(where: { $0.id == id }) else { return }
            self?.onCommentClicked?(comment)
        }
        return card
    }

    @objc private func closeSidebar() { onClose?() }

    @objc private func toggleResolvedSection() {
        isResolvedExpanded.toggle()
        resolvedStack.isHidden = !isResolvedExpanded
        let iconName = isResolvedExpanded ? "chevron.down" : "chevron.right"
        resolvedDisclosure.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)

        // Swap constraints for proper height
        if isResolvedExpanded {
            resolvedCollapsedConstraint.isActive = false
            resolvedExpandedConstraint.isActive = true
        } else {
            resolvedExpandedConstraint.isActive = false
            resolvedCollapsedConstraint.isActive = true
        }
    }

    private func toggleResolved(commentId: UUID) {
        guard let index = commentStore.comments.firstIndex(where: { $0.id == commentId }) else { return }
        commentStore.comments[index].isResolved.toggle()
        onCommentStoreChanged?(commentStore)
        rebuildCommentList()
    }

    private func toggleCollapsed(commentId: UUID) {
        guard let index = commentStore.comments.firstIndex(where: { $0.id == commentId }) else { return }
        commentStore.comments[index].isCollapsed.toggle()
        onCommentStoreChanged?(commentStore)
        rebuildCommentList()
    }

    private func deleteComment(commentId: UUID) {
        commentStore.comments.removeAll { $0.id == commentId }
        onCommentStoreChanged?(commentStore)
        rebuildCommentList()
    }

    func beginAddingComment(anchorText: String, anchorRange: Range<String.Index>? = nil) {
        pendingAnchorText = anchorText
        // Store the range - if not provided, find first occurrence
        pendingAnchorRange = anchorRange ?? documentText.range(of: anchorText)
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current

        // Outer container for shadow (shadows get clipped by masksToBounds)
        let inputCard = NSView()
        inputCard.translatesAutoresizingMaskIntoConstraints = false
        inputCard.wantsLayer = true
        inputCard.identifier = NSUserInterfaceItemIdentifier("inputCard")

        // Inner card container
        let cardContainer = NSView()
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.wantsLayer = true
        cardContainer.layer?.backgroundColor = colors.shellBackground.cgColor
        cardContainer.layer?.cornerRadius = theme.radiusSM
        cardContainer.layer?.borderWidth = 1
        cardContainer.layer?.borderColor = colors.accentPrimary.withAlphaComponent(0.4).cgColor
        cardContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.08).cgColor
        cardContainer.layer?.shadowOffset = CGSize(width: 0, height: 1)
        cardContainer.layer?.shadowRadius = 3
        cardContainer.layer?.shadowOpacity = 1.0
        cardContainer.layer?.masksToBounds = false
        inputCard.addSubview(cardContainer)

        // Accent bar
        let accentBar = NSView()
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = colors.accentPrimary.cgColor
        accentBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        accentBar.layer?.cornerRadius = theme.radiusSM
        cardContainer.addSubview(accentBar)

        // Header with "New Comment" label
        let headerLabel = NSTextField(labelWithString: "New Comment")
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = theme.uiFont(size: 11, weight: .bold)
        headerLabel.textColor = colors.accentPrimary
        cardContainer.addSubview(headerLabel)

        // Anchor text preview
        let firstLine = anchorText.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? anchorText
        let truncated = String(firstLine.prefix(30))
        let needsEllipsis = firstLine.count > 30 || anchorText.contains("\n")
        let anchorLabel = NSTextField(labelWithString: "\"\(truncated)\(needsEllipsis ? "…" : "")\"")
        anchorLabel.translatesAutoresizingMaskIntoConstraints = false
        anchorLabel.font = theme.uiFont(size: 12, weight: .semibold)
        anchorLabel.textColor = colors.sidebarText
        anchorLabel.lineBreakMode = .byTruncatingTail
        cardContainer.addSubview(anchorLabel)

        // Scroll view for multi-line text input
        let inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.hasVerticalScroller = true
        inputScroll.hasHorizontalScroller = false
        inputScroll.autohidesScrollers = true
        inputScroll.borderType = .noBorder
        inputScroll.drawsBackground = false

        // Create text view with proper frame - will be resized by autoresizing mask
        let contentSize = inputScroll.contentSize
        let input = CommentInputTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
        input.onSubmit = { [weak self] in self?.finishAddingComment() }
        input.minSize = NSSize(width: 0, height: 20)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        input.textContainer?.widthTracksTextView = true
        input.isRichText = false
        input.font = theme.uiFont(size: 13, weight: .regular)
        input.textColor = colors.sidebarText
        input.backgroundColor = .clear
        input.delegate = self
        input.insertionPointColor = colors.accentPrimary
        inputScroll.documentView = input
        cardContainer.addSubview(inputScroll)
        self.inputTextView = input

        // Hint label
        let hintLabel = NSTextField(labelWithString: "Press Enter to save • Esc to cancel")
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = theme.uiFont(size: 10, weight: .regular)
        hintLabel.textColor = colors.sidebarSecondaryText.withAlphaComponent(0.6)
        cardContainer.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            // Card container inside outer view
            cardContainer.topAnchor.constraint(equalTo: inputCard.topAnchor, constant: 2),
            cardContainer.leadingAnchor.constraint(equalTo: inputCard.leadingAnchor, constant: 2),
            cardContainer.trailingAnchor.constraint(equalTo: inputCard.trailingAnchor, constant: -2),
            cardContainer.bottomAnchor.constraint(equalTo: inputCard.bottomAnchor, constant: -2),

            // Accent bar
            accentBar.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 3),

            // Header
            headerLabel.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            headerLabel.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 12),

            // Anchor label
            anchorLabel.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            anchorLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            anchorLabel.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),

            // Input scroll
            inputScroll.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            inputScroll.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),
            inputScroll.topAnchor.constraint(equalTo: anchorLabel.bottomAnchor, constant: 8),
            inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            inputScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 100),

            // Hint label
            hintLabel.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            hintLabel.topAnchor.constraint(equalTo: inputScroll.bottomAnchor, constant: 6),
            hintLabel.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -10),
        ])

        // Calculate correct insertion position based on anchor text position in document
        let insertionIndex = calculateInsertionIndex(for: anchorText)
        stackView.insertArrangedSubview(inputCard, at: insertionIndex)
        inputCard.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
        view.window?.makeFirstResponder(input)

        // Fix text view size after layout
        DispatchQueue.main.async {
            let scrollContentSize = inputScroll.contentSize
            input.frame = NSRect(x: 0, y: 0, width: scrollContentSize.width, height: scrollContentSize.height)
            input.textContainer?.containerSize = NSSize(width: scrollContentSize.width, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    /// Calculate where to insert a new comment card based on document position
    private func calculateInsertionIndex(for anchorText: String) -> Int {
        // Use the pending range if available (for correct occurrence), otherwise find first occurrence
        guard let newPosition = (pendingAnchorRange ?? documentText.range(of: anchorText))?.lowerBound else {
            return 0 // If anchor not found, insert at top
        }

        let unresolvedComments = commentStore.unresolvedComments(sortedBy: documentText)
        for (index, comment) in unresolvedComments.enumerated() {
            if let existingPosition = commentStore.findAnchorRange(for: comment, in: documentText)?.lowerBound {
                if newPosition < existingPosition {
                    return index
                }
            }
        }
        return unresolvedComments.count // Insert at end if it comes after all existing
    }

    private func finishAddingComment() {
        guard let anchorText = pendingAnchorText,
              let content = inputTextView?.string.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            cancelAddingComment()
            return
        }

        // Calculate occurrence index and capture context
        var occurrenceIndex = 1
        var context: AnchorContext? = nil
        if let range = pendingAnchorRange {
            occurrenceIndex = CommentStore.occurrenceIndex(of: anchorText, at: range, in: documentText)
            context = CommentStore.captureContext(for: range, in: documentText)
        }

        let comment = Comment(
            anchorText: anchorText,
            content: content,
            anchorOccurrence: occurrenceIndex,
            anchorContext: context
        )
        commentStore.comments.append(comment)
        pendingAnchorText = nil
        pendingAnchorRange = nil
        inputTextView = nil
        onCommentStoreChanged?(commentStore)
        rebuildCommentList()
    }

    private func cancelAddingComment() {
        pendingAnchorText = nil
        pendingAnchorRange = nil
        inputTextView = nil
        rebuildCommentList()
    }

    private func scheduleOrphanCheck() {
        orphanCheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.checkForOrphans() }
        orphanCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    func checkForOrphans() {
        var orphanedIds: [UUID] = []
        var needsSave = false

        for (index, comment) in commentStore.comments.enumerated() {
            if let match = commentStore.findAnchorMatch(for: comment, in: documentText) {
                // Self-healing: if anchor found at different occurrence, update silently
                if match.occurrenceIndex != comment.anchorOccurrence {
                    commentStore.comments[index].anchorOccurrence = match.occurrenceIndex
                    // Also update context to current position
                    commentStore.comments[index].anchorContext = CommentStore.captureContext(
                        for: match.range,
                        in: documentText
                    )
                    needsSave = true
                }
            } else {
                orphanedIds.append(comment.id)
            }
        }

        for id in orphanedIds {
            if let comment = commentStore.comments.first(where: { $0.id == id }) {
                showOrphanToast(anchorText: comment.anchorText)
            }
            commentStore.comments.removeAll { $0.id == id }
        }

        if !orphanedIds.isEmpty || needsSave {
            onCommentStoreChanged?(commentStore)
            rebuildCommentList()
        }
    }

    private func showOrphanToast(anchorText: String) {
        let truncated = String(anchorText.prefix(20))
        let message = "Comment removed: \"\(truncated)\" was deleted"
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Comment Removed"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            if let window = self.view.window {
                alert.beginSheetModal(for: window) { _ in }
            }
        }
    }
}

extension CommentSidebarController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Enter to submit, Shift+Enter for newline
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
                // Shift+Enter: allow default newline behavior
                return false
            }
            // Plain Enter: submit
            finishAddingComment()
            return true
        }
        // Escape to cancel
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelAddingComment()
            return true
        }
        return false
    }
}
