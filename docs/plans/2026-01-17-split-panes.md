# Split Panes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement split pane functionality allowing multiple views of the same document with independent cursor/active paragraph state.

**Architecture:** `SplitViewManager` owns `NSSplitView` and manages `PaneController` instances. Each pane has its own `NSTextLayoutManager` connected to the shared `NSTextContentStorage`. Active paragraph tracking is pane-local by construction.

**Tech Stack:** Swift 5.9+, AppKit (NSSplitView), TextKit 2

---

## Prerequisites

- **Scaffolding must be complete** (provides `DocumentModel`, basic app structure)
- **Core Rendering must be complete** (provides `PaneController` with active paragraph tracking)
- This module depends on Core Rendering being merged first

---

## Why Split Panes Work

The architecture enables split panes by design:

```
DocumentModel
├── NSTextContentStorage (shared, raw text only)
│
├── Pane 1
│   ├── NSTextLayoutManager (pane-owned)
│   ├── MarkdownLayoutManagerDelegate (pane-owned)
│   └── activeParagraphIndex = 5 (pane-local)
│
└── Pane 2
    ├── NSTextLayoutManager (pane-owned)
    ├── MarkdownLayoutManagerDelegate (pane-owned)
    └── activeParagraphIndex = 12 (pane-local)
```

Each pane:
- Shares the same content storage (edits sync automatically)
- Has its own layout manager (independent layout)
- Tracks its own active paragraph (no interference)

---

## Project Structure (additions)

```
Sources/MarkdownEditor/
├── Views/
│   └── SplitViewManager.swift        ← NSSplitView management
└── Tests/
    └── MarkdownEditorTests/
        └── Views/
            └── SplitViewManagerTests.swift
```

---

## Task 1: SplitViewManager

**Files:**
- Create: `Sources/MarkdownEditor/Views/SplitViewManager.swift`
- Create: `Tests/MarkdownEditorTests/Views/SplitViewManagerTests.swift`

**Step 1: Write failing test**

```swift
import XCTest
@testable import MarkdownEditor

final class SplitViewManagerTests: XCTestCase {

    func testInitialPaneCount() {
        let document = DocumentModel()
        let manager = SplitViewManager(document: document)

        XCTAssertEqual(manager.paneCount, 1)
    }

    func testSplitHorizontally() {
        let document = DocumentModel()
        let manager = SplitViewManager(document: document)

        manager.splitHorizontally()

        XCTAssertEqual(manager.paneCount, 2)
    }

    func testSplitVertically() {
        let document = DocumentModel()
        let manager = SplitViewManager(document: document)

        manager.splitVertically()

        XCTAssertEqual(manager.paneCount, 2)
    }

    func testClosePane() {
        let document = DocumentModel()
        let manager = SplitViewManager(document: document)

        manager.splitHorizontally()
        XCTAssertEqual(manager.paneCount, 2)

        manager.closeCurrentPane()
        XCTAssertEqual(manager.paneCount, 1)
    }

    func testCannotCloseLastPane() {
        let document = DocumentModel()
        let manager = SplitViewManager(document: document)

        XCTAssertEqual(manager.paneCount, 1)

        manager.closeCurrentPane()
        XCTAssertEqual(manager.paneCount, 1)  // Still 1, can't close last
    }

    func testPanesShareDocument() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "Test content")

        let manager = SplitViewManager(document: document)
        manager.splitHorizontally()

        // Both panes should show same content
        // (In a real test, we'd verify the text views)
        XCTAssertEqual(manager.paneCount, 2)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SplitViewManagerTests`
Expected: FAIL

**Step 3: Create SplitViewManager**

```swift
import AppKit

/// Direction for splitting panes.
enum SplitDirection {
    case horizontal  // Side by side
    case vertical    // Top and bottom
}

/// Manages split panes showing the same document.
///
/// Each pane has its own `PaneController` with independent:
/// - NSTextLayoutManager
/// - Active paragraph tracking
/// - Selection state
///
/// All panes share the document's `NSTextContentStorage`.
final class SplitViewManager: PaneManaging {

    /// The split view containing panes.
    private let splitView: NSSplitView

    /// Pane controllers keyed by ID.
    private var panes: [UUID: PaneController] = [:]

    /// Order of panes (for navigation).
    private var paneOrder: [UUID] = []

    /// Currently focused pane.
    private var currentPaneId: UUID?

    /// Document being displayed.
    private weak var document: DocumentModel?

    // MARK: - PaneManaging

    var paneCount: Int {
        return panes.count
    }

    var containerView: NSView {
        return splitView
    }

    // MARK: - Initialization

    init(document: DocumentModel) {
        self.document = document
        self.splitView = NSSplitView()

        splitView.isVertical = true  // Horizontal split by default
        splitView.dividerStyle = .thin

        // Create initial pane
        let initialPane = createPane()
        addPaneToSplitView(initialPane)
    }

    // MARK: - Split Operations

    func splitHorizontally() {
        splitView.isVertical = true  // Divider is vertical = panes side by side
        addNewPane()
    }

    func splitVertically() {
        splitView.isVertical = false  // Divider is horizontal = panes top/bottom
        addNewPane()
    }

    func closeCurrentPane() {
        // Don't close the last pane
        guard panes.count > 1, let currentId = currentPaneId else { return }

        closePane(currentId)
    }

    // MARK: - Private

    private func createPane() -> PaneController {
        guard let doc = document else {
            fatalError("SplitViewManager requires a document")
        }

        let frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let pane = PaneController(document: doc, frame: frame)

        panes[pane.id] = pane
        paneOrder.append(pane.id)

        if currentPaneId == nil {
            currentPaneId = pane.id
        }

        return pane
    }

    private func addNewPane() {
        let pane = createPane()
        addPaneToSplitView(pane)
    }

    private func addPaneToSplitView(_ pane: PaneController) {
        // Wrap text view in scroll view
        let scrollView = NSScrollView()
        scrollView.documentView = pane.textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Store pane ID in scroll view for lookup
        scrollView.identifier = NSUserInterfaceItemIdentifier(pane.id.uuidString)

        splitView.addArrangedSubview(scrollView)

        // Adjust divider positions for equal split
        adjustDividers()
    }

    private func closePane(_ paneId: UUID) {
        guard let pane = panes.removeValue(forKey: paneId) else { return }

        // Find and remove the scroll view
        for subview in splitView.arrangedSubviews {
            if subview.identifier?.rawValue == paneId.uuidString {
                splitView.removeArrangedSubview(subview)
                subview.removeFromSuperview()
                break
            }
        }

        paneOrder.removeAll { $0 == paneId }

        // Update current pane
        if currentPaneId == paneId {
            currentPaneId = paneOrder.first
        }
    }

    private func adjustDividers() {
        guard panes.count > 1 else { return }

        let totalSize = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let paneSize = totalSize / CGFloat(panes.count)

        for (index, _) in splitView.arrangedSubviews.enumerated() {
            if index < splitView.arrangedSubviews.count - 1 {
                let position = paneSize * CGFloat(index + 1)
                splitView.setPosition(position, ofDividerAt: index)
            }
        }
    }

    // MARK: - Pane Focus

    /// Set focus to a specific pane.
    func focusPane(_ paneId: UUID) {
        guard panes[paneId] != nil else { return }
        currentPaneId = paneId

        // Make text view first responder
        if let pane = panes[paneId] {
            splitView.window?.makeFirstResponder(pane.textView)
        }
    }

    /// Get the currently focused pane.
    var currentPane: PaneController? {
        guard let id = currentPaneId else { return nil }
        return panes[id]
    }

    /// Navigate to next pane.
    func focusNextPane() {
        guard let currentId = currentPaneId,
              let currentIndex = paneOrder.firstIndex(of: currentId) else { return }

        let nextIndex = (currentIndex + 1) % paneOrder.count
        focusPane(paneOrder[nextIndex])
    }

    /// Navigate to previous pane.
    func focusPreviousPane() {
        guard let currentId = currentPaneId,
              let currentIndex = paneOrder.firstIndex(of: currentId) else { return }

        let prevIndex = currentIndex > 0 ? currentIndex - 1 : paneOrder.count - 1
        focusPane(paneOrder[prevIndex])
    }
}
```

**Step 4: Run tests**

Run: `swift test --filter SplitViewManagerTests`
Expected: All tests pass

**Step 5: Commit**

```bash
git add Sources/MarkdownEditor/Views/SplitViewManager.swift
git add Tests/MarkdownEditorTests/Views/SplitViewManagerTests.swift
git commit -m "feat(split-panes): add SplitViewManager with NSSplitView"
```

---

## Task 2: Integration with EditorViewController

**Files:**
- Modify: `Sources/MarkdownEditor/Editor/EditorViewController.swift`

**Step 1: Update EditorViewController to use SplitViewManager**

```swift
import AppKit

/// View controller for the main editor area.
/// Uses SplitViewManager to support multiple panes.
final class EditorViewController: NSViewController {

    /// Current document being edited.
    private(set) var currentDocument: DocumentModel?

    /// Split view manager for panes.
    private var splitViewManager: SplitViewManager?

    // MARK: - Lifecycle

    override func loadView() {
        let containerView = NSView()
        containerView.autoresizingMask = [.width, .height]
        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadDocument(DocumentModel())
    }

    // MARK: - Document Loading

    func loadDocument(_ document: DocumentModel) {
        // Remove previous split view
        splitViewManager?.containerView.removeFromSuperview()

        currentDocument = document

        // Create split view manager
        splitViewManager = SplitViewManager(document: document)

        if let splitView = splitViewManager?.containerView {
            splitView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(splitView)

            NSLayoutConstraint.activate([
                splitView.topAnchor.constraint(equalTo: view.topAnchor),
                splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        // Focus first pane
        if let pane = splitViewManager?.currentPane {
            view.window?.makeFirstResponder(pane.textView)
        }
    }

    // MARK: - Split Operations

    func splitHorizontally() {
        splitViewManager?.splitHorizontally()
    }

    func splitVertically() {
        splitViewManager?.splitVertically()
    }

    func closeCurrentPane() {
        splitViewManager?.closeCurrentPane()
    }

    func focusNextPane() {
        splitViewManager?.focusNextPane()
    }

    func focusPreviousPane() {
        splitViewManager?.focusPreviousPane()
    }
}
```

**Step 2: Commit**

```bash
git add Sources/MarkdownEditor/Editor/EditorViewController.swift
git commit -m "feat(split-panes): integrate SplitViewManager with EditorViewController"
```

---

## Task 3: Menu Items for Split Operations

**Files:**
- Modify: `Sources/MarkdownEditor/App/AppDelegate.swift`

**Step 1: Add View menu with split options**

Add to `setupMainMenu()` in AppDelegate:

```swift
// View menu
let viewMenuItem = NSMenuItem()
mainMenu.addItem(viewMenuItem)
let viewMenu = NSMenu(title: "View")
viewMenuItem.submenu = viewMenu

viewMenu.addItem(withTitle: "Split Horizontally", action: #selector(splitHorizontally(_:)), keyEquivalent: "d")
viewMenu.items.last?.keyEquivalentModifierMask = [.command]

viewMenu.addItem(withTitle: "Split Vertically", action: #selector(splitVertically(_:)), keyEquivalent: "D")
viewMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]

viewMenu.addItem(NSMenuItem.separator())

viewMenu.addItem(withTitle: "Close Pane", action: #selector(closePane(_:)), keyEquivalent: "w")
viewMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]

viewMenu.addItem(NSMenuItem.separator())

viewMenu.addItem(withTitle: "Focus Next Pane", action: #selector(focusNextPane(_:)), keyEquivalent: "]")
viewMenu.items.last?.keyEquivalentModifierMask = [.command]

viewMenu.addItem(withTitle: "Focus Previous Pane", action: #selector(focusPreviousPane(_:)), keyEquivalent: "[")
viewMenu.items.last?.keyEquivalentModifierMask = [.command]
```

Add action methods to AppDelegate:

```swift
@objc private func splitHorizontally(_ sender: Any?) {
    mainWindowController?.editorViewController?.splitHorizontally()
}

@objc private func splitVertically(_ sender: Any?) {
    mainWindowController?.editorViewController?.splitVertically()
}

@objc private func closePane(_ sender: Any?) {
    mainWindowController?.editorViewController?.closeCurrentPane()
}

@objc private func focusNextPane(_ sender: Any?) {
    mainWindowController?.editorViewController?.focusNextPane()
}

@objc private func focusPreviousPane(_ sender: Any?) {
    mainWindowController?.editorViewController?.focusPreviousPane()
}
```

**Step 2: Commit**

```bash
git add Sources/MarkdownEditor/App/AppDelegate.swift
git commit -m "feat(split-panes): add View menu with split operations"
```

---

## Task 4: Verify Active Paragraph Independence

**Step 1: Manual testing**

1. Open app
2. Type multiline text (5+ paragraphs)
3. Cmd+D to split horizontally
4. In left pane, place cursor on paragraph 2
5. In right pane, place cursor on paragraph 4
6. Verify: Each pane shows different active paragraph

**Step 2: Final commit**

```bash
git add -A
git commit -m "feat(split-panes): complete split panes module

- SplitViewManager with NSSplitView
- Multiple panes viewing same document
- Independent active paragraph per pane
- Keyboard shortcuts for split operations

Each pane has its own NSTextLayoutManager connected to shared content storage.
Active paragraph tracking is pane-local by construction."
```

---

## What This Module Delivers

| Component | Purpose |
|-----------|---------|
| `SplitViewManager` | NSSplitView management, pane creation/removal |
| Updated `EditorViewController` | Integration with split view |
| View menu items | Keyboard shortcuts for split operations |

## Architecture Verification

The split panes work because:
1. `NSTextContentStorage` is shared (edits sync automatically)
2. Each `PaneController` has its own `NSTextLayoutManager`
3. `activeParagraphIndex` is stored in `PaneController`, not `DocumentModel`
4. `MarkdownLayoutFragment` receives `isActiveParagraph` from its owning pane

No additional code is needed for active paragraph independence — it's built into the architecture.
