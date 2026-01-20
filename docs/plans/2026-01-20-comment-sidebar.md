# Comment Sidebar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a right-hand sidebar for review comments that anchor to selected text, with persistence to sidecar JSON files.

**Architecture:** Comments are stored in a `CommentStore` alongside the document. The sidebar uses `NSScrollView` with custom comment card views. Comments anchor to exact text strings and auto-delete when anchor text is removed.

**Tech Stack:** Swift, AppKit, NSScrollView, Codable for JSON persistence

---

## Task 1: Comment Data Model

**Files:**
- Create: `Sources/MarkdownEditor/Comments/Comment.swift`

**Step 1: Create the Comments directory**

```bash
mkdir -p Sources/MarkdownEditor/Comments
```

**Step 2: Write the Comment model**

```swift
import Foundation

/// A single comment anchored to text in the document.
struct Comment: Codable, Identifiable {
    /// Unique identifier.
    let id: UUID

    /// The exact text this comment is anchored to.
    var anchorText: String

    /// The comment content.
    var content: String

    /// Whether this comment has been resolved.
    var isResolved: Bool

    /// Whether this comment is collapsed in the UI.
    var isCollapsed: Bool

    /// When the comment was created.
    let createdAt: Date

    init(anchorText: String, content: String) {
        self.id = UUID()
        self.anchorText = anchorText
        self.content = content
        self.isResolved = false
        self.isCollapsed = false
        self.createdAt = Date()
    }
}

/// Container for all comments on a document.
struct CommentStore: Codable {
    var comments: [Comment]
    var version: Int = 1

    init() {
        self.comments = []
    }

    /// Find the character range where anchor text appears in document.
    /// Returns nil if anchor text is not found (orphaned).
    func findAnchorRange(for comment: Comment, in documentText: String) -> Range<String.Index>? {
        return documentText.range(of: comment.anchorText)
    }

    /// Get unresolved comments sorted by position in document.
    func unresolvedComments(sortedBy documentText: String) -> [Comment] {
        return comments
            .filter { !$0.isResolved }
            .sorted { lhs, rhs in
                let lhsRange = findAnchorRange(for: lhs, in: documentText)
                let rhsRange = findAnchorRange(for: rhs, in: documentText)
                guard let lhsStart = lhsRange?.lowerBound,
                      let rhsStart = rhsRange?.lowerBound else {
                    return false
                }
                return lhsStart < rhsStart
            }
    }

    /// Get resolved comments.
    func resolvedComments() -> [Comment] {
        return comments.filter { $0.isResolved }
    }
}
```

**Step 3: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -20
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/MarkdownEditor/Comments/Comment.swift
git commit -m "feat(comments): add Comment and CommentStore data models"
```

---

## Task 2: Comment Persistence Manager

**Files:**
- Create: `Sources/MarkdownEditor/Comments/CommentPersistence.swift`

**Step 1: Write the persistence manager**

```swift
import Foundation

/// Handles loading and saving comments to sidecar JSON files.
final class CommentPersistence {

    /// Get the comments file URL for a document.
    /// e.g., /path/to/doc.md -> /path/to/doc.comments.json
    static func commentsFileURL(for documentURL: URL) -> URL {
        let baseName = documentURL.deletingPathExtension().lastPathComponent
        let directory = documentURL.deletingLastPathComponent()
        return directory.appendingPathComponent("\(baseName).comments.json")
    }

    /// Load comments for a document. Returns empty store if file doesn't exist.
    static func load(for documentURL: URL) -> CommentStore {
        let fileURL = commentsFileURL(for: documentURL)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CommentStore()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CommentStore.self, from: data)
        } catch {
            print("Failed to load comments: \(error)")
            return CommentStore()
        }
    }

    /// Save comments for a document. Deletes file if no comments remain.
    static func save(_ store: CommentStore, for documentURL: URL) {
        let fileURL = commentsFileURL(for: documentURL)

        // Delete file if no comments
        if store.comments.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save comments: \(error)")
        }
    }

    /// Check if a document has comments.
    static func hasComments(for documentURL: URL) -> Bool {
        let fileURL = commentsFileURL(for: documentURL)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
```

**Step 2: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -20
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/MarkdownEditor/Comments/CommentPersistence.swift
git commit -m "feat(comments): add CommentPersistence for sidecar JSON files"
```

---

## Task 3: Comment Card View

**Files:**
- Create: `Sources/MarkdownEditor/Comments/CommentCardView.swift`

**Step 1: Write the comment card view**

```swift
import AppKit

/// Visual representation of a single comment in the sidebar.
final class CommentCardView: NSView {

    /// The comment being displayed.
    private(set) var comment: Comment

    /// Callbacks
    var onToggleResolved: ((UUID) -> Void)?
    var onToggleCollapsed: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onClick: ((UUID) -> Void)?

    // UI Elements
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // Checkbox for resolved state
        checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleResolved))
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)

        // Disclosure button for collapse
        disclosureButton = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Expand")!, target: self, action: #selector(toggleCollapsed))
        disclosureButton.translatesAutoresizingMaskIntoConstraints = false
        disclosureButton.bezelStyle = .inline
        disclosureButton.isBordered = false
        addSubview(disclosureButton)

        // Anchor text label (truncated)
        anchorLabel = NSTextField(labelWithString: "")
        anchorLabel.translatesAutoresizingMaskIntoConstraints = false
        anchorLabel.lineBreakMode = .byTruncatingTail
        anchorLabel.maximumNumberOfLines = 1
        addSubview(anchorLabel)

        // Comment content label
        contentLabel = NSTextField(labelWithString: "")
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 0
        contentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(contentLabel)

        // Delete button (shows on hover)
        deleteButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Delete")!, target: self, action: #selector(deleteComment))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.isHidden = true
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            // Checkbox
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            checkbox.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            // Disclosure
            disclosureButton.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 4),
            disclosureButton.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
            disclosureButton.widthAnchor.constraint(equalToConstant: 16),

            // Anchor label
            anchorLabel.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 4),
            anchorLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -4),
            anchorLabel.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),

            // Delete button
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 16),

            // Content label
            contentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            contentLabel.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 4),
            contentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        // Click gesture for the whole card
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(cardClicked))
        addGestureRecognizer(clickGesture)

        // Track mouse for hover
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    func update(with comment: Comment) {
        self.comment = comment

        // Truncate anchor text for display
        let displayAnchor = comment.anchorText.prefix(30)
        let suffix = comment.anchorText.count > 30 ? "..." : ""
        anchorLabel.stringValue = "\"\(displayAnchor)\(suffix)\""

        contentLabel.stringValue = comment.content
        contentLabel.isHidden = comment.isCollapsed

        checkbox.state = comment.isResolved ? .on : .off

        // Update disclosure icon
        let iconName = comment.isCollapsed ? "chevron.right" : "chevron.down"
        disclosureButton.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)

        // Dim resolved comments
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

    // MARK: - Actions

    @objc private func toggleResolved() {
        onToggleResolved?(comment.id)
    }

    @objc private func toggleCollapsed() {
        onToggleCollapsed?(comment.id)
    }

    @objc private func deleteComment() {
        onDelete?(comment.id)
    }

    @objc private func cardClicked() {
        onClick?(comment.id)
    }

    // MARK: - Mouse Tracking

    override func mouseEntered(with event: NSEvent) {
        deleteButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        deleteButton.isHidden = true
    }
}
```

**Step 2: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -20
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/MarkdownEditor/Comments/CommentCardView.swift
git commit -m "feat(comments): add CommentCardView for sidebar display"
```

---

## Task 4: Comment Sidebar Controller

**Files:**
- Create: `Sources/MarkdownEditor/Comments/CommentSidebarController.swift`

**Step 1: Write the sidebar controller**

```swift
import AppKit

/// Controller for the right-hand comment sidebar.
final class CommentSidebarController: NSViewController {

    /// The comment store being displayed.
    var commentStore: CommentStore = CommentStore() {
        didSet { rebuildCommentList() }
    }

    /// Current document text for anchor matching.
    var documentText: String = "" {
        didSet { rebuildCommentList() }
    }

    /// Callbacks
    var onCommentClicked: ((Comment) -> Void)?
    var onCommentStoreChanged: ((CommentStore) -> Void)?
    var onClose: (() -> Void)?

    // UI Elements
    private var headerView: NSView!
    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var resolvedSection: NSView!
    private var resolvedDisclosure: NSButton!
    private var resolvedStack: NSStackView!
    private var borderView: NSView!

    /// Input field for new comment (shown when adding)
    private var inputField: NSTextField?
    private var pendingAnchorText: String?

    /// Whether resolved section is expanded.
    private var isResolvedExpanded = false

    /// Theme observer.
    private var themeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

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
        themeObserver = view.observeTheme { [weak self] in
            self?.applyTheme()
        }
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

    // MARK: - Theme

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

        // Update all comment cards
        for case let card as CommentCardView in stackView.arrangedSubviews {
            card.applyTheme()
        }
        for case let card as CommentCardView in resolvedStack.arrangedSubviews {
            card.applyTheme()
        }
    }

    // MARK: - Comment List

    private func rebuildCommentList() {
        // Clear existing views
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        resolvedStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let unresolved = commentStore.unresolvedComments(sortedBy: documentText)
        let resolved = commentStore.resolvedComments()

        // Update title
        titleLabel.stringValue = "Comments (\(commentStore.comments.count))"

        // Add unresolved comments
        for comment in unresolved {
            let card = createCommentCard(for: comment)
            stackView.addArrangedSubview(card)

            // Make card fill width
            card.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
        }

        // Add resolved section if there are resolved comments
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

        card.onToggleResolved = { [weak self] id in
            self?.toggleResolved(commentId: id)
        }

        card.onToggleCollapsed = { [weak self] id in
            self?.toggleCollapsed(commentId: id)
        }

        card.onDelete = { [weak self] id in
            self?.deleteComment(commentId: id)
        }

        card.onClick = { [weak self] id in
            guard let comment = self?.commentStore.comments.first(where: { $0.id == id }) else { return }
            self?.onCommentClicked?(comment)
        }

        return card
    }

    // MARK: - Actions

    @objc private func closeSidebar() {
        onClose?()
    }

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

    // MARK: - Adding Comments

    /// Begin adding a new comment for the given anchor text.
    func beginAddingComment(anchorText: String) {
        pendingAnchorText = anchorText

        // Create input card
        let inputCard = NSView()
        inputCard.translatesAutoresizingMaskIntoConstraints = false
        inputCard.wantsLayer = true

        let colors = ThemeManager.shared.colors
        let theme = ThemeManager.shared.current
        inputCard.layer?.backgroundColor = colors.shellSecondaryBackground.cgColor
        inputCard.layer?.cornerRadius = theme.radiusSM
        inputCard.layer?.borderWidth = 1
        inputCard.layer?.borderColor = colors.accentPrimary.cgColor

        // Anchor label
        let anchorLabel = NSTextField(labelWithString: "\"\(anchorText.prefix(30))\"")
        anchorLabel.translatesAutoresizingMaskIntoConstraints = false
        anchorLabel.font = theme.uiFont(size: 11, weight: .medium)
        anchorLabel.textColor = colors.sidebarSecondaryText
        inputCard.addSubview(anchorLabel)

        // Input field
        let input = NSTextField()
        input.translatesAutoresizingMaskIntoConstraints = false
        input.placeholderString = "Add your comment..."
        input.font = theme.uiFont(size: 12, weight: .regular)
        input.isBordered = false
        input.focusRingType = .none
        input.backgroundColor = .clear
        input.delegate = self
        inputCard.addSubview(input)
        self.inputField = input

        NSLayoutConstraint.activate([
            anchorLabel.leadingAnchor.constraint(equalTo: inputCard.leadingAnchor, constant: 8),
            anchorLabel.topAnchor.constraint(equalTo: inputCard.topAnchor, constant: 8),
            anchorLabel.trailingAnchor.constraint(lessThanOrEqualTo: inputCard.trailingAnchor, constant: -8),

            input.leadingAnchor.constraint(equalTo: inputCard.leadingAnchor, constant: 8),
            input.trailingAnchor.constraint(equalTo: inputCard.trailingAnchor, constant: -8),
            input.topAnchor.constraint(equalTo: anchorLabel.bottomAnchor, constant: 4),
            input.bottomAnchor.constraint(equalTo: inputCard.bottomAnchor, constant: -8),
        ])

        // Insert at top of stack
        stackView.insertArrangedSubview(inputCard, at: 0)
        inputCard.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true

        // Focus the input
        view.window?.makeFirstResponder(input)
    }

    /// Finish adding comment (called on Enter).
    private func finishAddingComment() {
        guard let anchorText = pendingAnchorText,
              let content = inputField?.stringValue,
              !content.isEmpty else {
            cancelAddingComment()
            return
        }

        let comment = Comment(anchorText: anchorText, content: content)
        commentStore.comments.append(comment)

        pendingAnchorText = nil
        inputField = nil

        onCommentStoreChanged?(commentStore)
        rebuildCommentList()
    }

    /// Cancel adding comment (called on Escape or empty submit).
    private func cancelAddingComment() {
        pendingAnchorText = nil
        inputField = nil
        rebuildCommentList()
    }
}

// MARK: - NSTextFieldDelegate

extension CommentSidebarController: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishAddingComment()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelAddingComment()
            return true
        }
        return false
    }
}
```

**Step 2: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -30
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/MarkdownEditor/Comments/CommentSidebarController.swift
git commit -m "feat(comments): add CommentSidebarController for right sidebar"
```

---

## Task 5: Integrate Comment Sidebar into MainWindowController

**Files:**
- Modify: `Sources/MarkdownEditor/App/MainWindowController.swift`

**Step 1: Add comment sidebar properties and setup**

Add after line 21 (after `editorViewController` declaration):

```swift
/// Comment sidebar controller.
private(set) var commentSidebarController: CommentSidebarController?

/// Inner split view for editor + comment sidebar.
private var editorSplitView: NSSplitView?

/// Whether comment sidebar is visible.
private(set) var isCommentSidebarVisible = false
```

**Step 2: Modify setupWindow to use nested split view**

Replace the editor area setup (around lines 79-109) with a nested split view:

Find this section starting at line 79:
```swift
// Editor area (tab bar + editor)
let editorArea = NSView()
```

Replace through line 109 with:

```swift
// Editor area (tab bar + editor split)
let editorArea = NSView()
editorArea.autoresizingMask = [.width, .height]
editorArea.wantsLayer = true

// Tab bar
let tabBar = TabBarView()
tabBar.translatesAutoresizingMaskIntoConstraints = false
tabBar.tabManager = tabManager
self.tabBarView = tabBar
editorArea.addSubview(tabBar)

// Inner split view for editor + comment sidebar
let innerSplit = NSSplitView()
innerSplit.translatesAutoresizingMaskIntoConstraints = false
innerSplit.isVertical = true
innerSplit.dividerStyle = .thin
innerSplit.delegate = self
self.editorSplitView = innerSplit
editorArea.addSubview(innerSplit)

// Editor
editorViewController = EditorViewController()
let editorView = editorViewController.view
innerSplit.addArrangedSubview(editorView)

// Comment sidebar (initially hidden)
let commentSidebar = CommentSidebarController()
commentSidebar.onClose = { [weak self] in
    self?.hideCommentSidebar()
}
commentSidebar.onCommentClicked = { [weak self] comment in
    self?.scrollToComment(comment)
}
commentSidebar.onCommentStoreChanged = { [weak self] store in
    self?.saveCommentStore(store)
}
self.commentSidebarController = commentSidebar
// Don't add to split yet - added when shown

NSLayoutConstraint.activate([
    tabBar.topAnchor.constraint(equalTo: editorArea.topAnchor),
    tabBar.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
    tabBar.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
    tabBar.heightAnchor.constraint(equalToConstant: 36),

    innerSplit.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
    innerSplit.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
    innerSplit.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
    innerSplit.bottomAnchor.constraint(equalTo: editorArea.bottomAnchor),
])
```

**Step 3: Add comment sidebar methods**

Add before `// MARK: - Window Title`:

```swift
// MARK: - Comment Sidebar

/// Show the comment sidebar.
func showCommentSidebar() {
    guard !isCommentSidebarVisible,
          let sidebar = commentSidebarController,
          let split = editorSplitView else { return }

    sidebar.view.setFrameSize(NSSize(width: 280, height: split.bounds.height))
    split.addArrangedSubview(sidebar.view)
    isCommentSidebarVisible = true

    // Load comments for current document
    loadCommentsForActiveDocument()
}

/// Hide the comment sidebar.
func hideCommentSidebar() {
    guard isCommentSidebarVisible,
          let sidebar = commentSidebarController else { return }

    sidebar.view.removeFromSuperview()
    isCommentSidebarVisible = false
}

/// Toggle comment sidebar visibility.
func toggleCommentSidebar() {
    if isCommentSidebarVisible {
        hideCommentSidebar()
    } else {
        showCommentSidebar()
    }
}

/// Add a comment for the current selection.
func addComment() {
    guard let pane = editorViewController.currentPane,
          let textView = pane.textView as NSTextView?,
          textView.selectedRange().length > 0 else {
        // No selection - toggle sidebar instead
        toggleCommentSidebar()
        return
    }

    // Get selected text
    let range = textView.selectedRange()
    let selectedText = (textView.string as NSString).substring(with: range)

    // Show sidebar if hidden
    if !isCommentSidebarVisible {
        showCommentSidebar()
    }

    // Begin adding comment
    commentSidebarController?.beginAddingComment(anchorText: selectedText)
}

/// Load comments for the active document.
private func loadCommentsForActiveDocument() {
    guard let document = tabManager.activeDocument,
          let url = document.filePath else {
        commentSidebarController?.commentStore = CommentStore()
        return
    }

    let store = CommentPersistence.load(for: url)
    commentSidebarController?.commentStore = store
    commentSidebarController?.documentText = document.fullString()

    // Auto-show if document has comments
    if !store.comments.isEmpty && !isCommentSidebarVisible {
        showCommentSidebar()
    }
}

/// Save the comment store for the active document.
private func saveCommentStore(_ store: CommentStore) {
    guard let document = tabManager.activeDocument,
          let url = document.filePath else { return }

    CommentPersistence.save(store, for: url)

    // Hide sidebar if no comments remain
    if store.comments.isEmpty && isCommentSidebarVisible {
        hideCommentSidebar()
    }
}

/// Scroll editor to show the comment's anchor text.
private func scrollToComment(_ comment: Comment) {
    guard let pane = editorViewController.currentPane,
          let textView = pane.textView as NSTextView?,
          let range = textView.string.range(of: comment.anchorText) else { return }

    let nsRange = NSRange(range, in: textView.string)
    textView.scrollRangeToVisible(nsRange)
    textView.showFindIndicator(for: nsRange)
}
```

**Step 4: Update tab manager callback to reload comments**

Find `tabManager.onActiveTabChanged` in `setupTabManager()` and add comment loading:

After `self.updateWindowTitle()` add:
```swift
self.loadCommentsForActiveDocument()
```

**Step 5: Update split view delegate for inner split**

Update the `splitView(_:constrainMinCoordinate:ofSubviewAt:)` method to handle both splits:

```swift
func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
    if splitView === self.splitView {
        // Left sidebar minimum
        return 150
    } else if splitView === editorSplitView {
        // Editor minimum (leave space for comment sidebar)
        return 300
    }
    return proposedMinimumPosition
}

func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
    if splitView === self.splitView {
        // Left sidebar maximum
        return splitView.bounds.width - 400
    } else if splitView === editorSplitView {
        // Comment sidebar minimum width (editor can't push it smaller than 200)
        return splitView.bounds.width - 200
    }
    return proposedMaximumPosition
}
```

**Step 6: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -30
```

**Step 7: Commit**

```bash
git add Sources/MarkdownEditor/App/MainWindowController.swift
git commit -m "feat(comments): integrate comment sidebar into main window"
```

---

## Task 6: Add EditorViewController Support

**Files:**
- Create: `Sources/MarkdownEditor/Document/EditorViewController.swift`

Note: Based on the codebase exploration, EditorViewController doesn't exist yet. The editor functionality is in PaneController. We need to create a simple wrapper or add the property access directly.

**Step 1: Check if EditorViewController exists and create if needed**

First, let's check what's needed. The MainWindowController references `editorViewController.currentPane`. We need to ensure this exists.

Look at how `editorViewController` is used in MainWindowController and create the missing piece:

```swift
import AppKit

/// View controller managing the editor area.
/// Wraps PaneController and provides document loading.
final class EditorViewController: NSViewController {

    /// Current pane controller.
    private(set) var currentPane: PaneController?

    /// Scroll view containing the text view.
    private var scrollView: NSScrollView!

    override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]
        view = scrollView
    }

    /// Load a document into the editor.
    func loadDocument(_ document: DocumentModel) {
        // Create new pane for this document
        let pane = PaneController(document: document, frame: scrollView.bounds)

        // Configure text view
        pane.textView.autoresizingMask = [.width]

        // Set as scroll view's document
        scrollView.documentView = pane.textView

        currentPane = pane
    }

    /// Position cursor at the beginning of the specified line (1-indexed).
    func setCursorLine(_ line: Int) {
        guard let pane = currentPane,
              let text = pane.textView.string as NSString? else { return }

        var currentLine = 1
        var offset = 0

        while currentLine < line && offset < text.length {
            let lineRange = text.lineRange(for: NSRange(location: offset, length: 0))
            offset = lineRange.location + lineRange.length
            currentLine += 1
        }

        pane.textView.setSelectedRange(NSRange(location: offset, length: 0))
        pane.textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }
}
```

**Step 2: Verify the file exists and matches what MainWindowController expects**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && ls -la Sources/MarkdownEditor/Document/
```

If EditorViewController.swift doesn't exist, create it. If it does, we may need to add the `currentPane` property.

**Step 3: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -30
```

**Step 4: Commit if changes were made**

```bash
git add Sources/MarkdownEditor/Document/EditorViewController.swift
git commit -m "feat(editor): add currentPane access to EditorViewController"
```

---

## Task 7: Add Menu Items and Keyboard Shortcut

**Files:**
- Modify: `Sources/MarkdownEditor/App/AppDelegate.swift`

**Step 1: Add menu items to Edit menu**

Find the Edit menu setup (around line 94-105) and add after `Select All`:

```swift
editMenu.addItem(NSMenuItem.separator())
let addCommentItem = NSMenuItem(title: "Add Comment", action: #selector(addComment(_:)), keyEquivalent: "m")
addCommentItem.keyEquivalentModifierMask = [.option, .command]
editMenu.addItem(addCommentItem)
editMenu.addItem(withTitle: "Toggle Comment Sidebar", action: #selector(toggleCommentSidebar(_:)), keyEquivalent: "")
```

**Step 2: Add action methods**

Add after `openWorkspaceAction`:

```swift
@objc func addComment(_ sender: Any?) {
    mainWindowController?.addComment()
}

@objc private func toggleCommentSidebar(_ sender: Any?) {
    mainWindowController?.toggleCommentSidebar()
}
```

**Step 3: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -20
```

**Step 4: Commit**

```bash
git add Sources/MarkdownEditor/App/AppDelegate.swift
git commit -m "feat(comments): add menu items and ⌥⌘M shortcut for comments"
```

---

## Task 8: Add Orphan Detection

**Files:**
- Modify: `Sources/MarkdownEditor/Comments/CommentSidebarController.swift`

**Step 1: Add orphan detection method**

Add to CommentSidebarController after `rebuildCommentList`:

```swift
/// Check for orphaned comments and remove them with notification.
func checkForOrphans() {
    var orphanedIds: [UUID] = []

    for comment in commentStore.comments {
        if commentStore.findAnchorRange(for: comment, in: documentText) == nil {
            orphanedIds.append(comment.id)
        }
    }

    guard !orphanedIds.isEmpty else { return }

    // Remove orphaned comments
    for id in orphanedIds {
        if let comment = commentStore.comments.first(where: { $0.id == id }) {
            // Show toast notification
            showOrphanToast(anchorText: comment.anchorText)
        }
        commentStore.comments.removeAll { $0.id == id }
    }

    onCommentStoreChanged?(commentStore)
    rebuildCommentList()
}

private func showOrphanToast(anchorText: String) {
    // Create a simple toast notification
    let truncated = String(anchorText.prefix(20))
    let message = "Comment removed: \"\(truncated)\" was deleted"

    // Use NSAlert for simplicity (could be replaced with custom toast)
    DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "Comment Removed"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            alert.window.close()
        }

        if let window = self.view.window {
            alert.beginSheetModal(for: window) { _ in }
        }
    }
}
```

**Step 2: Call orphan check when document text changes**

Add a debounced update mechanism. Add property:

```swift
private var orphanCheckWorkItem: DispatchWorkItem?
```

Update the `documentText` didSet:

```swift
var documentText: String = "" {
    didSet {
        rebuildCommentList()
        scheduleOrphanCheck()
    }
}

private func scheduleOrphanCheck() {
    orphanCheckWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
        self?.checkForOrphans()
    }
    orphanCheckWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
}
```

**Step 3: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -20
```

**Step 4: Commit**

```bash
git add Sources/MarkdownEditor/Comments/CommentSidebarController.swift
git commit -m "feat(comments): add orphan detection with toast notifications"
```

---

## Task 9: Wire Up Document Text Updates

**Files:**
- Modify: `Sources/MarkdownEditor/App/MainWindowController.swift`

**Step 1: Update comment sidebar when document changes**

Add observer for document changes. In `setupTabManager()`, add after the existing callbacks:

```swift
// Update comment sidebar when document text changes
NotificationCenter.default.addObserver(
    forName: NSText.didChangeNotification,
    object: nil,
    queue: .main
) { [weak self] notification in
    guard let textView = notification.object as? NSTextView,
          textView === self?.editorViewController.currentPane?.textView else { return }

    self?.commentSidebarController?.documentText = textView.string
}
```

**Step 2: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -20
```

**Step 3: Commit**

```bash
git add Sources/MarkdownEditor/App/MainWindowController.swift
git commit -m "feat(comments): wire up document text changes to comment sidebar"
```

---

## Task 10: Add NSView Theme Observer Extension

**Files:**
- Check if extension exists, add if needed

**Step 1: Check for existing theme observer**

The code uses `view.observeTheme { }` pattern. This needs to exist.

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && grep -r "observeTheme" Sources/
```

If it doesn't exist, add to `Sources/MarkdownEditor/Theme/ThemeManager.swift`:

```swift
extension NSView {
    /// Observe theme changes and call handler.
    func observeTheme(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        return ThemeManager.shared.observeChanges(handler)
    }
}
```

**Step 2: Verify it compiles**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build 2>&1 | head -20
```

**Step 3: Commit if changes made**

```bash
git add Sources/MarkdownEditor/Theme/ThemeManager.swift
git commit -m "feat(theme): add NSView.observeTheme extension"
```

---

## Task 11: Final Integration Test

**Step 1: Build the app**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift build
```

**Step 2: Run the app**

```bash
cd /Users/walkereacho/Desktop/code/Markdown/.worktrees/comment-sidebar && swift run MarkdownEditor
```

**Step 3: Manual testing checklist**

- [ ] Open a markdown file
- [ ] Select some text
- [ ] Press ⌥⌘M - sidebar should open with input field
- [ ] Type a comment and press Enter
- [ ] Comment should appear in sidebar
- [ ] Click comment - editor should scroll to anchor
- [ ] Check the checkbox - comment should move to Resolved section
- [ ] Delete the anchor text - toast should appear, comment removed
- [ ] Close and reopen app - comments should persist

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix(comments): integration fixes from manual testing"
```

---

## Summary

This plan implements the comment sidebar feature in 11 tasks:

1. **Comment Data Model** - `Comment` and `CommentStore` structs
2. **Persistence Manager** - Load/save to sidecar JSON
3. **Comment Card View** - Individual comment UI
4. **Sidebar Controller** - Right sidebar with comment list
5. **MainWindowController Integration** - Nested split view
6. **EditorViewController Support** - Access to current pane
7. **Menu Items & Shortcut** - ⌥⌘M keyboard shortcut
8. **Orphan Detection** - Auto-remove when anchor deleted
9. **Document Change Wiring** - Update sidebar on edits
10. **Theme Observer Extension** - If needed
11. **Final Integration Test** - Manual verification

Each task is a small, focused unit with clear verification steps.
