import AppKit

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
    private var borderView: NSView!
    private var inputTextView: NSTextView?
    private var pendingAnchorText: String?
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

        titleLabel = NSTextField(labelWithString: "Comments (0)")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closeSidebar))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        headerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    private func setupBorder() {
        borderView = NSView()
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        view.addSubview(borderView)
        NSLayoutConstraint.activate([
            borderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            borderView.topAnchor.constraint(equalTo: view.topAnchor, constant: 36),
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
        view.addSubview(scrollView)

        stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
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
        resolvedStack.spacing = 8
        resolvedStack.isHidden = true
        resolvedSection.addSubview(resolvedStack)

        NSLayoutConstraint.activate([
            resolvedDisclosure.leadingAnchor.constraint(equalTo: resolvedSection.leadingAnchor),
            resolvedDisclosure.topAnchor.constraint(equalTo: resolvedSection.topAnchor),
            resolvedStack.leadingAnchor.constraint(equalTo: resolvedSection.leadingAnchor),
            resolvedStack.trailingAnchor.constraint(equalTo: resolvedSection.trailingAnchor),
            resolvedStack.topAnchor.constraint(equalTo: resolvedDisclosure.bottomAnchor, constant: 8),
            resolvedStack.bottomAnchor.constraint(equalTo: resolvedSection.bottomAnchor),
        ])
    }

    private func applyTheme() {
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current
        view.layer?.backgroundColor = colors.sidebarBackground.cgColor
        headerView.layer?.backgroundColor = colors.sidebarBackground.cgColor
        borderView.layer?.backgroundColor = colors.shellBorder.cgColor
        titleLabel.font = theme.uiFont(size: 13, weight: .semibold)
        titleLabel.textColor = colors.sidebarText
        closeButton.contentTintColor = colors.sidebarSecondaryText
        resolvedDisclosure.font = theme.uiFont(size: 12, weight: .medium)
        (resolvedDisclosure.cell as? NSButtonCell)?.backgroundColor = .clear
        for case let card as CommentCardView in stackView.arrangedSubviews { card.applyTheme() }
        for case let card as CommentCardView in resolvedStack.arrangedSubviews { card.applyTheme() }
    }

    private func rebuildCommentList() {
        guard isViewLoaded, stackView != nil, resolvedStack != nil else { return }
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        resolvedStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let unresolved = commentStore.unresolvedComments(sortedBy: documentText)
        let resolved = commentStore.resolvedComments()
        titleLabel?.stringValue = "Comments (\(commentStore.comments.count))"
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

    func beginAddingComment(anchorText: String) {
        pendingAnchorText = anchorText
        let inputCard = NSView()
        inputCard.translatesAutoresizingMaskIntoConstraints = false
        inputCard.wantsLayer = true
        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current
        inputCard.layer?.backgroundColor = colors.shellSecondaryBackground.cgColor
        inputCard.layer?.cornerRadius = theme.radiusSM
        inputCard.layer?.borderWidth = 1
        inputCard.layer?.borderColor = colors.accentPrimary.cgColor

        let firstLine = anchorText.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? anchorText
        let truncated = String(firstLine.prefix(30))
        let needsEllipsis = firstLine.count > 30 || anchorText.contains("\n")
        let anchorLabel = NSTextField(labelWithString: "\"\(truncated)\(needsEllipsis ? "..." : "")\"")
        anchorLabel.translatesAutoresizingMaskIntoConstraints = false
        anchorLabel.font = theme.uiFont(size: 11, weight: .medium)
        anchorLabel.textColor = colors.sidebarSecondaryText
        inputCard.addSubview(anchorLabel)

        // Scroll view for multi-line text input
        let inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.hasVerticalScroller = true
        inputScroll.hasHorizontalScroller = false
        inputScroll.autohidesScrollers = true
        inputScroll.borderType = .noBorder
        inputScroll.drawsBackground = false

        let input = NSTextView()
        input.isRichText = false
        input.font = theme.uiFont(size: 12, weight: .regular)
        input.textColor = colors.sidebarText
        input.backgroundColor = .clear
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        input.textContainer?.widthTracksTextView = true
        input.delegate = self
        inputScroll.documentView = input
        inputCard.addSubview(inputScroll)
        self.inputTextView = input

        // Hint label
        let hintLabel = NSTextField(labelWithString: "⌘+Enter to submit")
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = theme.uiFont(size: 10, weight: .regular)
        hintLabel.textColor = colors.sidebarSecondaryText.withAlphaComponent(0.6)
        inputCard.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            anchorLabel.leadingAnchor.constraint(equalTo: inputCard.leadingAnchor, constant: 8),
            anchorLabel.topAnchor.constraint(equalTo: inputCard.topAnchor, constant: 8),
            anchorLabel.trailingAnchor.constraint(lessThanOrEqualTo: inputCard.trailingAnchor, constant: -8),
            inputScroll.leadingAnchor.constraint(equalTo: inputCard.leadingAnchor, constant: 8),
            inputScroll.trailingAnchor.constraint(equalTo: inputCard.trailingAnchor, constant: -8),
            inputScroll.topAnchor.constraint(equalTo: anchorLabel.bottomAnchor, constant: 4),
            inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            inputScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 100),
            hintLabel.topAnchor.constraint(equalTo: inputScroll.bottomAnchor, constant: 4),
            hintLabel.trailingAnchor.constraint(equalTo: inputCard.trailingAnchor, constant: -8),
            hintLabel.bottomAnchor.constraint(equalTo: inputCard.bottomAnchor, constant: -6),
        ])

        stackView.insertArrangedSubview(inputCard, at: 0)
        inputCard.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
        view.window?.makeFirstResponder(input)
    }

    private func finishAddingComment() {
        guard let anchorText = pendingAnchorText,
              let content = inputTextView?.string.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            cancelAddingComment()
            return
        }
        let comment = Comment(anchorText: anchorText, content: content)
        commentStore.comments.append(comment)
        pendingAnchorText = nil
        inputTextView = nil
        onCommentStoreChanged?(commentStore)
        rebuildCommentList()
    }

    private func cancelAddingComment() {
        pendingAnchorText = nil
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
        for comment in commentStore.comments {
            if commentStore.findAnchorRange(for: comment, in: documentText) == nil {
                orphanedIds.append(comment.id)
            }
        }
        guard !orphanedIds.isEmpty else { return }
        for id in orphanedIds {
            if let comment = commentStore.comments.first(where: { $0.id == id }) {
                showOrphanToast(anchorText: comment.anchorText)
            }
            commentStore.comments.removeAll { $0.id == id }
        }
        onCommentStoreChanged?(commentStore)
        rebuildCommentList()
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
        // Cmd+Enter to submit
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                finishAddingComment()
                return true
            }
            // Allow regular Enter for newlines
            return false
        }
        // Escape to cancel
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelAddingComment()
            return true
        }
        return false
    }
}
