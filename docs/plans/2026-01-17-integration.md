# Feature Integration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire all independently-built modules (Parser, Tabs, Sidebar, Rendering) into a cohesive Markdown editor application.

**Architecture:** MainWindowController becomes the integration hub, owning TabManager and coordinating between Sidebar, Editor, and document operations. Parser connects to PaneController for live syntax rendering.

**Tech Stack:** Swift 5.9+, AppKit (NSSplitView, NSToolbar)

---

## Prerequisites

All modules must be merged to main:
- ✅ Core Rendering (SyntaxTheme, MarkdownLayoutFragment, MarkdownLayoutManagerDelegate)
- ✅ Parser (MarkdownParser, BlockContext, BlockContextScanner)
- ✅ Sidebar (WorkspaceManager, FileWatcher, SidebarController, QuickOpenController)
- ✅ Tabs (TabManager, TabView, TabBarView)

---

## What You're Building

An integrated editor that:
1. Parses Markdown and renders with hybrid WYSIWYG (active paragraph raw, inactive formatted)
2. Manages multiple documents via tabs
3. Shows file tree sidebar with workspace support
4. Handles document lifecycle (new, open, save, close with dirty prompts)

---

## Project Structure (modifications)

```
Sources/MarkdownEditor/
├── App/
│   └── MainWindowController.swift   ← MODIFY: Integration hub
├── Editor/
│   └── EditorViewController.swift   ← MODIFY: Tab-aware document loading
├── Document/
│   └── PaneController.swift         ← MODIFY: Parser injection
└── Tests/
    └── MarkdownEditorTests/
        └── Integration/
            └── IntegrationTests.swift
```

---

## Task 1: Parser → Rendering Integration

**Files:**
- Modify: `Sources/MarkdownEditor/Document/PaneController.swift:47-76`

**Step 1: Write failing test**

Create: `Tests/MarkdownEditorTests/Integration/ParserIntegrationTests.swift`

```swift
import XCTest
@testable import MarkdownEditor

final class ParserIntegrationTests: XCTestCase {

    func testPaneControllerUsesParser() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "# Hello")

        let pane = PaneController(document: document, frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        // Verify parser is connected
        let tokens = pane.layoutDelegate.tokenProvider.parse("# Hello")
        XCTAssertFalse(tokens.isEmpty, "Parser should return tokens for Markdown")
        XCTAssertEqual(tokens.first?.element, .heading(level: 1))
    }

    func testParserTokensForBold() {
        let document = DocumentModel()
        let pane = PaneController(document: document, frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        let tokens = pane.layoutDelegate.tokenProvider.parse("**bold**")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.element, .bold)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ParserIntegrationTests`
Expected: FAIL - tokens are empty (StubTokenProvider)

**Step 3: Expose layoutDelegate and inject parser**

Modify `PaneController.swift` - make layoutDelegate accessible and inject parser:

```swift
// Change line 35 from:
private let layoutDelegate: MarkdownLayoutManagerDelegate

// To:
private(set) var layoutDelegate: MarkdownLayoutManagerDelegate
```

Then add parser injection in init, after `super.init()` (around line 70):

```swift
super.init()

// Wire up delegate references
layoutDelegate.paneController = self
textView.delegate = self

// Inject parser for live Markdown rendering
layoutDelegate.tokenProvider = MarkdownParser.shared

// Configure text view
configureTextView()
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ParserIntegrationTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/MarkdownEditor/Document/PaneController.swift
git add Tests/MarkdownEditorTests/Integration/ParserIntegrationTests.swift
git commit -m "feat(integration): connect MarkdownParser to PaneController"
```

---

## Task 2: Tab Manager Integration

**Files:**
- Modify: `Sources/MarkdownEditor/App/MainWindowController.swift`

**Step 1: Write failing test**

Create: `Tests/MarkdownEditorTests/Integration/TabIntegrationTests.swift`

```swift
import XCTest
@testable import MarkdownEditor

final class TabIntegrationTests: XCTestCase {

    func testMainWindowControllerHasTabManager() {
        let controller = MainWindowController()
        XCTAssertNotNil(controller.tabManager)
    }

    func testNewDocumentCreatesTab() {
        let controller = MainWindowController()
        controller.newDocument()

        XCTAssertEqual(controller.tabManager.tabs.count, 1)
        XCTAssertNotNil(controller.tabManager.activeDocument)
    }

    func testOpenDocumentCreatesTab() throws {
        let controller = MainWindowController()

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try "# Test".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        try controller.openFile(at: testFile)

        XCTAssertEqual(controller.tabManager.tabs.count, 1)
        XCTAssertEqual(controller.tabManager.tabs.first?.title, testFile.lastPathComponent)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TabIntegrationTests`
Expected: FAIL - tabManager property doesn't exist

**Step 3: Add TabManager to MainWindowController**

Read the current MainWindowController first, then modify to add:

```swift
import AppKit

final class MainWindowController: NSWindowController {

    /// Tab manager for document lifecycle.
    let tabManager = TabManager()

    /// Editor view controller.
    private var editorViewController: EditorViewController!

    override init(window: NSWindow?) {
        super.init(window: nil)
        setupWindow()
        setupTabManager()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown Editor"
        window.center()

        editorViewController = EditorViewController()
        window.contentViewController = editorViewController

        self.window = window
    }

    private func setupTabManager() {
        // When active tab changes, update editor
        tabManager.onActiveTabChanged = { [weak self] documentId in
            guard let self = self,
                  let docId = documentId,
                  let document = self.tabManager.document(for: docId) else { return }
            self.editorViewController.loadDocument(document)
            self.updateWindowTitle()
        }

        // Handle close confirmation for dirty documents
        tabManager.onCloseConfirmation = { [weak self] document in
            return self?.confirmClose(document: document) ?? true
        }
    }

    // MARK: - Document Operations

    func newDocument() {
        let document = tabManager.newDocument()
        editorViewController.loadDocument(document)
        updateWindowTitle()
    }

    func openFile(at url: URL) throws {
        let document = try tabManager.openFile(at: url)
        editorViewController.loadDocument(document)
        updateWindowTitle()
    }

    func saveDocument() {
        guard let document = tabManager.activeDocument else { return }
        do {
            if document.filePath == nil {
                saveDocumentAs()
            } else {
                try document.save()
                updateWindowTitle()
            }
        } catch {
            showError(error)
        }
    }

    func saveDocumentAs() {
        guard let document = tabManager.activeDocument else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "Untitled.md"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            document.filePath = url
            do {
                try document.save()
                self?.updateWindowTitle()
            } catch {
                self?.showError(error)
            }
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self?.openFile(at: url)
            } catch {
                self?.showError(error)
            }
        }
    }

    // MARK: - Window Title

    private func updateWindowTitle() {
        guard let tab = tabManager.tabs.first(where: { $0.documentId == tabManager.activeDocumentId }) else {
            window?.title = "Markdown Editor"
            return
        }
        let dirty = tab.isDirty ? " •" : ""
        window?.title = "\(tab.title)\(dirty) — Markdown Editor"
    }

    // MARK: - Alerts

    private func confirmClose(document: DocumentModel) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Save
            do {
                if document.filePath == nil {
                    // Need to show save panel synchronously
                    return false  // Cancel for now, need proper handling
                }
                try document.save()
                return true
            } catch {
                showError(error)
                return false
            }
        case .alertSecondButtonReturn:
            // Don't Save
            return true
        default:
            // Cancel
            return false
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter TabIntegrationTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/MarkdownEditor/App/MainWindowController.swift
git add Tests/MarkdownEditorTests/Integration/TabIntegrationTests.swift
git commit -m "feat(integration): add TabManager to MainWindowController"
```

---

## Task 3: Tab Bar UI Integration

**Files:**
- Modify: `Sources/MarkdownEditor/App/MainWindowController.swift`

**Step 1: Write failing test**

Add to `TabIntegrationTests.swift`:

```swift
func testTabBarViewConnected() {
    let controller = MainWindowController()
    controller.newDocument()
    controller.newDocument()

    // Tab bar should reflect tab count
    XCTAssertEqual(controller.tabBarView?.tabManager?.tabs.count, 2)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TabIntegrationTests.testTabBarViewConnected`
Expected: FAIL - tabBarView property doesn't exist

**Step 3: Add TabBarView to window**

In MainWindowController, add property and modify setupWindow:

```swift
/// Tab bar view.
private(set) var tabBarView: TabBarView?

private func setupWindow() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Markdown Editor"
    window.center()

    // Create container for tab bar + editor
    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false

    // Tab bar
    let tabBar = TabBarView()
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.tabManager = tabManager
    self.tabBarView = tabBar
    containerView.addSubview(tabBar)

    // Editor
    editorViewController = EditorViewController()
    let editorView = editorViewController.view
    editorView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(editorView)

    NSLayoutConstraint.activate([
        tabBar.topAnchor.constraint(equalTo: containerView.topAnchor),
        tabBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
        tabBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        tabBar.heightAnchor.constraint(equalToConstant: 32),

        editorView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
        editorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
        editorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        editorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
    ])

    window.contentView = containerView
    self.window = window
}
```

Also update `setupTabManager` to refresh tab bar:

```swift
private func setupTabManager() {
    tabManager.onActiveTabChanged = { [weak self] documentId in
        guard let self = self,
              let docId = documentId,
              let document = self.tabManager.document(for: docId) else { return }
        self.editorViewController.loadDocument(document)
        self.tabBarView?.updateTabs()
        self.updateWindowTitle()
    }

    tabManager.onCloseConfirmation = { [weak self] document in
        self?.tabBarView?.rebuildTabs()
        return self?.confirmClose(document: document) ?? true
    }
}
```

Update `newDocument` and `openFile` to refresh tabs:

```swift
func newDocument() {
    let document = tabManager.newDocument()
    editorViewController.loadDocument(document)
    tabBarView?.rebuildTabs()
    updateWindowTitle()
}

func openFile(at url: URL) throws {
    let document = try tabManager.openFile(at: url)
    editorViewController.loadDocument(document)
    tabBarView?.rebuildTabs()
    updateWindowTitle()
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter TabIntegrationTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/MarkdownEditor/App/MainWindowController.swift
git add Tests/MarkdownEditorTests/Integration/TabIntegrationTests.swift
git commit -m "feat(integration): add TabBarView to main window"
```

---

## Task 4: Sidebar Integration

**Files:**
- Modify: `Sources/MarkdownEditor/App/MainWindowController.swift`

**Step 1: Write failing test**

Create: `Tests/MarkdownEditorTests/Integration/SidebarIntegrationTests.swift`

```swift
import XCTest
@testable import MarkdownEditor

final class SidebarIntegrationTests: XCTestCase {

    func testMainWindowControllerHasSidebar() {
        let controller = MainWindowController()
        XCTAssertNotNil(controller.sidebarController)
    }

    func testSidebarFileSelectionOpensDocument() throws {
        let controller = MainWindowController()

        // Create temp workspace with file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testFile = tempDir.appendingPathComponent("test.md")
        try "# Test".write(to: testFile, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Mount workspace and select file
        controller.workspaceManager.mountWorkspace(at: tempDir)
        controller.sidebarController?.onFileSelected?(testFile)

        XCTAssertEqual(controller.tabManager.tabs.count, 1)
        XCTAssertEqual(controller.tabManager.tabs.first?.filePath, testFile)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SidebarIntegrationTests`
Expected: FAIL - sidebarController property doesn't exist

**Step 3: Add Sidebar to MainWindowController**

Add properties:

```swift
/// Workspace manager for file tree.
let workspaceManager = WorkspaceManager()

/// Sidebar controller.
private(set) var sidebarController: SidebarController?

/// Split view for sidebar + editor.
private var splitView: NSSplitView?
```

Update setupWindow to use NSSplitView:

```swift
private func setupWindow() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Markdown Editor"
    window.center()
    window.minSize = NSSize(width: 600, height: 400)

    // Main split view (sidebar | editor area)
    let split = NSSplitView()
    split.isVertical = true
    split.dividerStyle = .thin
    split.autoresizingMask = [.width, .height]
    self.splitView = split

    // Sidebar
    let sidebar = SidebarController(workspaceManager: workspaceManager)
    sidebar.onFileSelected = { [weak self] url in
        try? self?.openFile(at: url)
    }
    self.sidebarController = sidebar

    let sidebarView = sidebar.view
    sidebarView.setFrameSize(NSSize(width: 220, height: 700))
    split.addArrangedSubview(sidebarView)

    // Editor area (tab bar + editor)
    let editorArea = NSView()
    editorArea.translatesAutoresizingMaskIntoConstraints = false

    // Tab bar
    let tabBar = TabBarView()
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    tabBar.tabManager = tabManager
    self.tabBarView = tabBar
    editorArea.addSubview(tabBar)

    // Editor
    editorViewController = EditorViewController()
    let editorView = editorViewController.view
    editorView.translatesAutoresizingMaskIntoConstraints = false
    editorArea.addSubview(editorView)

    NSLayoutConstraint.activate([
        tabBar.topAnchor.constraint(equalTo: editorArea.topAnchor),
        tabBar.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
        tabBar.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
        tabBar.heightAnchor.constraint(equalToConstant: 32),

        editorView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
        editorView.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
        editorView.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
        editorView.bottomAnchor.constraint(equalTo: editorArea.bottomAnchor)
    ])

    split.addArrangedSubview(editorArea)

    // Set holding priorities so sidebar keeps size when resizing
    split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
    split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

    window.contentView = split
    self.window = window
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SidebarIntegrationTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/MarkdownEditor/App/MainWindowController.swift
git add Tests/MarkdownEditorTests/Integration/SidebarIntegrationTests.swift
git commit -m "feat(integration): add Sidebar to main window with split view"
```

---

## Task 5: Menu Actions Wiring

**Files:**
- Verify: `Sources/MarkdownEditor/App/AppDelegate.swift`
- Verify: `Sources/MarkdownEditor/App/MainWindowController.swift`

**Step 1: Write failing test**

Add to `TabIntegrationTests.swift`:

```swift
func testSaveDocumentUpdatesDirtyState() throws {
    let controller = MainWindowController()
    controller.newDocument()

    guard let document = controller.tabManager.activeDocument else {
        XCTFail("No active document")
        return
    }

    // Create temp file for saving
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("save-test-\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: testFile) }

    document.filePath = testFile
    document.contentStorage.attributedString = NSAttributedString(string: "# Test")
    document.isDirty = true

    controller.saveDocument()

    XCTAssertFalse(document.isDirty)
}
```

**Step 2: Run test to verify it passes**

Run: `swift test --filter TabIntegrationTests.testSaveDocumentUpdatesDirtyState`
Expected: PASS (already implemented in Task 2)

**Step 3: Verify menu integration**

Read AppDelegate to verify menu actions route to MainWindowController:
- `newDocument()` → `mainWindowController?.newDocument()`
- `openDocument()` → `mainWindowController?.openDocument()`
- `saveDocument()` → `mainWindowController?.saveDocument()`
- `saveDocumentAs()` → `mainWindowController?.saveDocumentAs()`

If not connected, update AppDelegate menu action handlers.

**Step 4: Commit (if changes needed)**

```bash
git add Sources/MarkdownEditor/App/AppDelegate.swift
git commit -m "fix(integration): ensure menu actions route to MainWindowController"
```

---

## Task 6: Dirty State UI Updates

**Files:**
- Modify: `Sources/MarkdownEditor/App/MainWindowController.swift`
- Modify: `Sources/MarkdownEditor/Document/DocumentModel.swift` (if needed)

**Step 1: Write failing test**

Add to `TabIntegrationTests.swift`:

```swift
func testDirtyStateUpdatesWindowTitle() {
    let controller = MainWindowController()
    controller.newDocument()

    guard let document = controller.tabManager.activeDocument else {
        XCTFail("No active document")
        return
    }

    // Simulate edit
    document.isDirty = true

    // Force title update
    controller.refreshUI()

    XCTAssertTrue(controller.window?.title.contains("•") ?? false)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TabIntegrationTests.testDirtyStateUpdatesWindowTitle`
Expected: FAIL - refreshUI doesn't exist

**Step 3: Add refreshUI method**

Add to MainWindowController:

```swift
/// Refresh UI elements (title, tabs) to reflect current state.
func refreshUI() {
    updateWindowTitle()
    tabBarView?.updateTabs()
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter TabIntegrationTests.testDirtyStateUpdatesWindowTitle`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/MarkdownEditor/App/MainWindowController.swift
git add Tests/MarkdownEditorTests/Integration/TabIntegrationTests.swift
git commit -m "feat(integration): add refreshUI for dirty state updates"
```

---

## Task 7: Open Workspace Action

**Files:**
- Modify: `Sources/MarkdownEditor/App/AppDelegate.swift`
- Modify: `Sources/MarkdownEditor/App/MainWindowController.swift`

**Step 1: Write failing test**

Add to `SidebarIntegrationTests.swift`:

```swift
func testOpenWorkspaceUpdatesFileTree() throws {
    let controller = MainWindowController()

    // Create temp workspace
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-workspace-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    try "# File 1".write(to: tempDir.appendingPathComponent("file1.md"), atomically: true, encoding: .utf8)
    try "# File 2".write(to: tempDir.appendingPathComponent("file2.md"), atomically: true, encoding: .utf8)

    defer { try? FileManager.default.removeItem(at: tempDir) }

    controller.openWorkspace(at: tempDir)

    XCTAssertEqual(controller.workspaceManager.workspaceRoot, tempDir)
    XCTAssertNotNil(controller.workspaceManager.fileTree())
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SidebarIntegrationTests.testOpenWorkspaceUpdatesFileTree`
Expected: FAIL - openWorkspace method doesn't exist

**Step 3: Add openWorkspace method**

Add to MainWindowController:

```swift
func openWorkspace(at url: URL) {
    workspaceManager.mountWorkspace(at: url)
    sidebarController?.refresh()
    window?.title = "\(url.lastPathComponent) — Markdown Editor"
}

func openWorkspace() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Choose a folder to open as workspace"

    panel.beginSheetModal(for: window!) { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        self?.openWorkspace(at: url)
    }
}
```

Add menu item in AppDelegate (in File menu, after Open):

```swift
let openWorkspaceItem = NSMenuItem(
    title: "Open Workspace...",
    action: #selector(openWorkspace(_:)),
    keyEquivalent: "O"  // Cmd+Shift+O
)
openWorkspaceItem.keyEquivalentModifierMask = [.command, .shift]
fileMenu.addItem(openWorkspaceItem)

@objc func openWorkspace(_ sender: Any?) {
    mainWindowController?.openWorkspace()
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SidebarIntegrationTests.testOpenWorkspaceUpdatesFileTree`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/MarkdownEditor/App/AppDelegate.swift
git add Sources/MarkdownEditor/App/MainWindowController.swift
git add Tests/MarkdownEditorTests/Integration/SidebarIntegrationTests.swift
git commit -m "feat(integration): add Open Workspace menu action"
```

---

## Task 8: Final Integration Test

**Step 1: Write comprehensive test**

Add to a new file `Tests/MarkdownEditorTests/Integration/FullIntegrationTests.swift`:

```swift
import XCTest
@testable import MarkdownEditor

final class FullIntegrationTests: XCTestCase {

    func testFullWorkflow() throws {
        let controller = MainWindowController()

        // 1. Create new document
        controller.newDocument()
        XCTAssertEqual(controller.tabManager.tabs.count, 1)

        // 2. Type some Markdown
        guard let document = controller.tabManager.activeDocument else {
            XCTFail("No document")
            return
        }
        document.contentStorage.attributedString = NSAttributedString(string: "# Hello World\n\nThis is **bold** text.")

        // 3. Verify parser is working (tokens exist)
        guard let pane = controller.editorViewController.paneController else {
            XCTFail("No pane controller")
            return
        }
        let tokens = pane.layoutDelegate.tokenProvider.parse("# Hello World")
        XCTAssertFalse(tokens.isEmpty)

        // 4. Open another document
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("integration-\(UUID().uuidString).md")
        try "# Second File".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        try controller.openFile(at: testFile)
        XCTAssertEqual(controller.tabManager.tabs.count, 2)

        // 5. Verify tab switching works
        controller.tabManager.activateTab(documentId: document.id)
        XCTAssertEqual(controller.tabManager.activeDocumentId, document.id)
    }
}
```

**Step 2: Run all integration tests**

Run: `swift test --filter Integration`
Expected: All PASS

**Step 3: Run full test suite**

Run: `swift test`
Expected: All tests pass

**Step 4: Final commit**

```bash
git add Tests/MarkdownEditorTests/Integration/FullIntegrationTests.swift
git commit -m "feat(integration): complete module integration

- Parser connected to PaneController for live syntax rendering
- TabManager wired to MainWindowController
- TabBarView displaying open documents
- Sidebar with file tree and workspace support
- Menu actions routed through TabManager
- Dirty state tracking with UI updates

All modules now work together as a cohesive application."
```

---

## What This Integration Delivers

| Integration | Description |
|-------------|-------------|
| Parser → Rendering | Live Markdown syntax highlighting via MarkdownParser |
| Tabs → Editor | Tab switching loads documents in editor |
| Sidebar → Tabs | File selection opens documents in tabs |
| Menu → TabManager | File operations route through document lifecycle |
| Dirty State → UI | Window title and tabs show unsaved indicator |

## Post-Integration

After completing this plan, the app should:
1. Render Markdown with hybrid WYSIWYG (active paragraph raw, inactive formatted)
2. Support multiple open documents via tabs
3. Show file tree sidebar when workspace is opened
4. Handle save prompts when closing dirty documents
5. Update window title with filename and dirty indicator
