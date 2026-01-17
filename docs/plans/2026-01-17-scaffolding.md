# Scaffolding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a working plain-text macOS editor with TextKit 2, defining all protocols for parallel module development.

**Architecture:** AppKit-based editor using TextKit 2's modern layout system. DocumentModel owns `NSTextContentStorage` (raw text only, never rendering attributes). Protocols define contracts for Core Rendering, Parser, Sidebar, Tabs, and Split Panes modules. Each module will be developed in parallel against these protocols.

**Tech Stack:** Swift 5.9+, AppKit, TextKit 2, macOS 13+ (Ventura), Swift Package Manager

---

## Background: Why These Choices Matter

### TextKit 2 vs TextKit 1

TextKit 2 is required for this project. **Do not use TextKit 1 classes.**

| TextKit 2 (Use These) | TextKit 1 (Avoid) |
|----------------------|-------------------|
| `NSTextContentStorage` | `NSTextStorage` |
| `NSTextLayoutManager` | `NSLayoutManager` |
| `NSTextLayoutFragment` | `drawGlyphs(forGlyphRange:at:)` |
| `NSTextRange` / `NSTextLocation` | `NSRange` for text positions |

**Why TextKit 2:**
- Multiple layout managers can share one content storage (essential for split panes)
- Viewport-driven incremental layout (performance for large files)
- `NSTextLayoutFragment` subclassing is the clean way to customize rendering

### Layout-Based Rendering (Critical Concept)

The core insight: **rendering happens at the layout layer, not the storage layer**.

```
WRONG (causes undo corruption, multi-pane bugs):
┌─────────────────┐
│ NSTextContent   │ ← Apply formatting attributes here
│ Storage         │ ← Undo records these changes
└─────────────────┘

RIGHT (what we do):
┌─────────────────┐
│ NSTextContent   │ ← Raw text only, never rendering attrs
│ Storage         │ ← Undo is clean
└────────┬────────┘
         │
┌────────┴────────┐
│ NSTextLayout    │ ← Each pane has its own
│ Manager         │
└────────┬────────┘
         │
┌────────┴────────┐
│ MarkdownLayout  │ ← Rendering decisions happen HERE
│ Fragment        │ ← Custom draw() method
└─────────────────┘
```

This architecture lets us:
- Have different "active paragraph" per pane (cursor in pane 1 at line 5, pane 2 at line 12)
- Keep undo clean (storage only has content edits)
- Reload files without re-applying rendering attributes

---

## Project Structure

```
MarkdownEditor/
├── Package.swift
├── Sources/
│   └── MarkdownEditor/
│       ├── main.swift
│       ├── App/
│       │   ├── AppDelegate.swift
│       │   └── MainWindowController.swift
│       ├── Document/
│       │   ├── DocumentModel.swift
│       │   └── ParagraphIndexCache.swift
│       ├── Editor/
│       │   └── EditorViewController.swift
│       ├── Protocols/
│       │   ├── TokenProviding.swift
│       │   ├── LayoutFragmentProviding.swift
│       │   ├── WorkspaceProviding.swift
│       │   ├── TabManaging.swift
│       │   └── PaneManaging.swift
│       └── Stubs/
│           ├── StubTokenProvider.swift
│           └── StubLayoutFragmentProvider.swift
└── Tests/
    └── MarkdownEditorTests/
        └── DocumentModelTests.swift
```

---

## Task 1: Swift Package Setup

**Files:**
- Create: `Package.swift`
- Create: `Sources/MarkdownEditor/main.swift`

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MarkdownEditor",
            path: "Sources/MarkdownEditor"
        ),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: ["MarkdownEditor"],
            path: "Tests/MarkdownEditorTests"
        )
    ]
)
```

**Step 2: Create main.swift entry point**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

**Step 3: Build to verify setup**

Run: `swift build`
Expected: Build succeeds (with warnings about missing files, which we'll add next)

**Step 4: Commit**

```bash
git init
git add Package.swift Sources/MarkdownEditor/main.swift
git commit -m "chore: initialize Swift package for MarkdownEditor"
```

---

## Task 2: AppDelegate and Window Setup

**Files:**
- Create: `Sources/MarkdownEditor/App/AppDelegate.swift`
- Create: `Sources/MarkdownEditor/App/MainWindowController.swift`

**Step 1: Create AppDelegate**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        openNewWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Window Management

    private func openNewWindow() {
        let windowController = MainWindowController()
        windowController.showWindow(nil)
        mainWindowController = windowController
    }

    // MARK: - Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit MarkdownEditor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New", action: #selector(newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As...", action: #selector(saveDocumentAs(_:)), keyEquivalent: "S")

        // Edit menu (for undo/redo/copy/paste)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc private func newDocument(_ sender: Any?) {
        mainWindowController?.newDocument()
    }

    @objc private func openDocument(_ sender: Any?) {
        mainWindowController?.openDocument()
    }

    @objc private func saveDocument(_ sender: Any?) {
        mainWindowController?.saveDocument()
    }

    @objc private func saveDocumentAs(_ sender: Any?) {
        mainWindowController?.saveDocumentAs()
    }
}
```

**Step 2: Create MainWindowController**

```swift
import AppKit

final class MainWindowController: NSWindowController {

    private var editorViewController: EditorViewController!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Untitled"
        window.center()

        super.init(window: window)

        editorViewController = EditorViewController()
        window.contentViewController = editorViewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Document Operations

    func newDocument() {
        editorViewController.loadDocument(DocumentModel())
        window?.title = "Untitled"
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let document = try DocumentModel(contentsOf: url)
                self?.editorViewController.loadDocument(document)
                self?.window?.title = url.lastPathComponent
            } catch {
                self?.showError(error)
            }
        }
    }

    func saveDocument() {
        guard let document = editorViewController.currentDocument else { return }

        if document.filePath != nil {
            do {
                try document.save()
            } catch {
                showError(error)
            }
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        guard let document = editorViewController.currentDocument else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Untitled.md"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            document.filePath = url
            do {
                try document.save()
                self?.window?.title = url.lastPathComponent
            } catch {
                self?.showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        guard let window = window else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }
}
```

**Step 3: Build (will fail — missing files)**

Run: `swift build`
Expected: Errors about missing `EditorViewController`, `DocumentModel`

**Step 4: Commit work in progress**

```bash
git add Sources/MarkdownEditor/App/
git commit -m "feat: add AppDelegate and MainWindowController with menu setup"
```

---

## Task 3: DocumentModel with TextKit 2

**Files:**
- Create: `Sources/MarkdownEditor/Document/DocumentModel.swift`
- Create: `Sources/MarkdownEditor/Document/ParagraphIndexCache.swift`

**Step 1: Create DocumentModel**

This is the core document class. **CRITICAL:** `NSTextContentStorage` holds raw text only — never rendering attributes.

```swift
import AppKit

/// Errors that can occur during document operations.
enum DocumentError: LocalizedError {
    case noFilePath
    case encodingError

    var errorDescription: String? {
        switch self {
        case .noFilePath:
            return "Document has no file path. Use Save As."
        case .encodingError:
            return "Could not encode document as UTF-8."
        }
    }
}

/// Document model — owns content and provides text access.
///
/// ## Critical Architecture Rule
/// `contentStorage` contains RAW TEXT ONLY. Never add rendering attributes
/// (colors, fonts for formatting) to the content storage. Rendering happens
/// at the layout layer via `NSTextLayoutFragment` subclasses.
///
/// This design enables:
/// - Clean undo (only content changes recorded)
/// - Multiple panes with different "active paragraph" states
/// - Safe external file reload
final class DocumentModel {

    /// Unique identifier for this document.
    let id: UUID

    /// File path, if saved.
    var filePath: URL?

    /// Source of truth for document text.
    /// Contains raw Markdown — NEVER rendering attributes.
    let contentStorage: NSTextContentStorage

    /// Undo manager for content changes.
    let undoManager: UndoManager

    /// Paragraph index cache for O(log N) lookups.
    private(set) lazy var paragraphCache: ParagraphIndexCache = {
        ParagraphIndexCache(contentStorage: contentStorage)
    }()

    /// Document revision counter — incremented on every edit.
    private(set) var revision: UInt64 = 0

    /// Whether document has unsaved changes.
    var isDirty: Bool = false

    /// Last save timestamp.
    var lastSavedAt: Date?

    // MARK: - Initialization

    /// Create a new empty document.
    init() {
        self.id = UUID()
        self.contentStorage = NSTextContentStorage()
        self.undoManager = UndoManager()

        contentStorage.undoManager = undoManager
    }

    /// Load document from file.
    init(contentsOf url: URL) throws {
        self.id = UUID()
        self.filePath = url
        self.contentStorage = NSTextContentStorage()
        self.undoManager = UndoManager()

        let text = try String(contentsOf: url, encoding: .utf8)

        // Set text as plain attributed string — no formatting attributes
        contentStorage.attributedString = NSAttributedString(string: text)
        contentStorage.undoManager = undoManager

        // Build paragraph cache
        paragraphCache.rebuildFull()
    }

    // MARK: - Text Access

    /// Full document as plain string.
    /// Use sparingly — prefer paragraph access for performance.
    func fullString() -> String {
        guard let attrString = contentStorage.attributedString else { return "" }
        return attrString.string
    }

    /// Number of paragraphs in document.
    var paragraphCount: Int {
        paragraphCache.count
    }

    /// Get text of a specific paragraph.
    func paragraph(at index: Int) -> String? {
        guard let range = paragraphCache.paragraphRange(at: index) else { return nil }
        return substringForRange(range)
    }

    /// Get the text range for a paragraph.
    func paragraphRange(at index: Int) -> NSTextRange? {
        paragraphCache.paragraphRange(at: index)
    }

    /// Get paragraph index for a text location.
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        paragraphCache.paragraphIndex(for: location)
    }

    // MARK: - Save

    /// Save document to its file path.
    func save() throws {
        guard let url = filePath else {
            throw DocumentError.noFilePath
        }
        let content = fullString()
        try content.write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
        lastSavedAt = Date()
    }

    // MARK: - Edit Notifications

    /// Called when content changes. Updates caches.
    func contentDidChange(in editedRange: NSTextRange, changeInLength delta: Int) {
        revision += 1
        isDirty = true
        paragraphCache.didProcessEditing(in: editedRange, changeInLength: delta)
    }

    // MARK: - Private Helpers

    private func substringForRange(_ range: NSTextRange) -> String? {
        guard let storage = contentStorage.attributedString else { return nil }

        let start = contentStorage.offset(from: contentStorage.documentRange.location, to: range.location)
        let end = contentStorage.offset(from: contentStorage.documentRange.location, to: range.endLocation)

        guard start >= 0, end <= storage.length, start < end else { return nil }

        let nsRange = NSRange(location: start, length: end - start)
        return storage.attributedSubstring(from: nsRange).string
    }
}
```

**Step 2: Create ParagraphIndexCache**

```swift
import AppKit

/// Maintains paragraph range mappings for O(log N) lookups.
///
/// TextKit 2 uses `NSTextRange`/`NSTextLocation` instead of `NSRange`.
/// This cache maps paragraph indices to their text ranges.
final class ParagraphIndexCache {

    private var paragraphRanges: [(range: NSTextRange, index: Int)] = []
    private var documentVersion: Int = 0

    private weak var contentStorage: NSTextContentStorage?

    init(contentStorage: NSTextContentStorage) {
        self.contentStorage = contentStorage
    }

    /// Number of cached paragraphs.
    var count: Int {
        paragraphRanges.count
    }

    // MARK: - Lookup (O(log N) via binary search)

    /// Find paragraph index for a text location.
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        guard let storage = contentStorage else { return nil }

        // Binary search
        var low = 0
        var high = paragraphRanges.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let entry = paragraphRanges[mid]

            if entry.range.contains(location) {
                return entry.index
            }

            let targetOffset = storage.offset(from: storage.documentRange.location, to: location)
            let entryOffset = storage.offset(from: storage.documentRange.location, to: entry.range.location)

            if targetOffset < entryOffset {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }

        return nil
    }

    /// Get text range for a paragraph index.
    func paragraphRange(at index: Int) -> NSTextRange? {
        guard index >= 0 && index < paragraphRanges.count else { return nil }
        return paragraphRanges[index].range
    }

    // MARK: - Cache Updates

    /// Handle document edit by rebuilding cache.
    /// A production implementation would do incremental updates,
    /// but full rebuild is correct and simpler for scaffolding.
    func didProcessEditing(in editedRange: NSTextRange, changeInLength delta: Int) {
        rebuildFull()
    }

    /// Rebuild entire cache by enumerating paragraphs.
    func rebuildFull() {
        guard let storage = contentStorage else { return }

        paragraphRanges.removeAll()
        var index = 0

        storage.enumerateTextElements(from: storage.documentRange.location) { element in
            if let paragraph = element as? NSTextParagraph,
               let range = paragraph.elementRange {
                self.paragraphRanges.append((range: range, index: index))
                index += 1
            }
            return true  // Continue enumeration
        }

        documentVersion += 1
    }
}
```

**Step 3: Commit**

```bash
git add Sources/MarkdownEditor/Document/
git commit -m "feat: add DocumentModel and ParagraphIndexCache with TextKit 2"
```

---

## Task 4: EditorViewController with TextKit 2

**Files:**
- Create: `Sources/MarkdownEditor/Editor/EditorViewController.swift`

**Step 1: Create EditorViewController**

This sets up the TextKit 2 stack: `NSTextContentStorage` → `NSTextLayoutManager` → `NSTextContainer` → `NSTextView`.

```swift
import AppKit

/// View controller for the main editor area.
/// Sets up TextKit 2 infrastructure for a single editing pane.
final class EditorViewController: NSViewController {

    /// Current document being edited.
    private(set) var currentDocument: DocumentModel?

    /// The text view for editing.
    private var textView: NSTextView!

    /// Scroll view containing the text view.
    private var scrollView: NSScrollView!

    /// Layout manager for this pane.
    private var layoutManager: NSTextLayoutManager!

    /// Text container defining the geometry.
    private var textContainer: NSTextContainer!

    // MARK: - Lifecycle

    override func loadView() {
        // Create the main view
        let containerView = NSView()
        containerView.autoresizingMask = [.width, .height]
        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTextView()
        loadDocument(DocumentModel())  // Start with empty document
    }

    // MARK: - Setup

    private func setupTextView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Document Loading

    /// Load a document into the editor.
    ///
    /// This sets up the full TextKit 2 stack:
    /// ```
    /// DocumentModel.contentStorage (NSTextContentStorage)
    ///         │
    ///         ▼
    ///   NSTextLayoutManager (one per pane)
    ///         │
    ///         ▼
    ///    NSTextContainer
    ///         │
    ///         ▼
    ///      NSTextView
    /// ```
    func loadDocument(_ document: DocumentModel) {
        // Clean up previous document
        if let previousLayout = layoutManager {
            currentDocument?.contentStorage.removeTextLayoutManager(previousLayout)
        }

        currentDocument = document

        // Create TextKit 2 layout infrastructure
        layoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer()

        // Configure text container
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false

        // Connect layout manager to container
        layoutManager.textContainer = textContainer

        // Connect layout manager to document's content storage
        // This is the key TextKit 2 pattern — content storage can have multiple layout managers
        document.contentStorage.addTextLayoutManager(layoutManager)

        // Create text view using TextKit 2 initializer
        // IMPORTANT: Use the initializer that takes NSTextLayoutManager, not the legacy one
        textView = NSTextView(frame: scrollView.bounds, textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 20, height: 20)

        // Configure editor behavior
        textView.isRichText = false  // Plain text editing
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor

        // Wire up undo manager
        textView.allowsUndo = true

        // Set as scroll view's document view
        scrollView.documentView = textView

        // Make text view first responder
        view.window?.makeFirstResponder(textView)
    }
}
```

**Step 2: Build and run**

Run: `swift build && swift run`
Expected: Window opens with empty text editor. You can type, use Cmd+Z for undo.

**Step 3: Test File → Open and Save**

1. Type some text
2. File → Save As → save as test.txt
3. File → Open → open the file
4. Verify text appears

**Step 4: Commit**

```bash
git add Sources/MarkdownEditor/Editor/
git commit -m "feat: add EditorViewController with TextKit 2 layout stack"
```

---

## Task 5: Module Protocols

**Files:**
- Create: `Sources/MarkdownEditor/Protocols/TokenProviding.swift`
- Create: `Sources/MarkdownEditor/Protocols/LayoutFragmentProviding.swift`
- Create: `Sources/MarkdownEditor/Protocols/WorkspaceProviding.swift`
- Create: `Sources/MarkdownEditor/Protocols/TabManaging.swift`
- Create: `Sources/MarkdownEditor/Protocols/PaneManaging.swift`

These protocols define the contracts that parallel modules implement.

**Step 1: Create TokenProviding (Parser module implements this)**

```swift
import Foundation

/// Token representing a parsed Markdown element.
/// Defined in scaffolding so all modules share the same type.
struct MarkdownToken {
    /// The type of Markdown element.
    let element: MarkdownElement

    /// Range of the content text (e.g., "bold" in "**bold**").
    /// Offset from start of paragraph.
    let contentRange: Range<Int>

    /// Ranges of syntax characters (e.g., "**" markers).
    /// Offsets from start of paragraph.
    let syntaxRanges: [Range<Int>]

    /// Nesting depth for lists and blockquotes.
    let nestingDepth: Int

    init(
        element: MarkdownElement,
        contentRange: Range<Int>,
        syntaxRanges: [Range<Int>] = [],
        nestingDepth: Int = 0
    ) {
        self.element = element
        self.contentRange = contentRange
        self.syntaxRanges = syntaxRanges
        self.nestingDepth = nestingDepth
    }
}

/// Markdown element types supported by the editor.
/// Parser module must handle all of these.
enum MarkdownElement {
    case text
    case heading(level: Int)           // # through ######
    case bold                          // **text** or __text__
    case italic                        // *text* or _text_
    case boldItalic                    // ***text***
    case inlineCode                    // `code`
    case fencedCodeBlock(language: String?)
    case indentedCodeBlock
    case unorderedListItem             // - or * or +
    case orderedListItem(number: Int)  // 1. 2. etc
    case blockquote                    // > text
    case link(url: String)             // [text](url)
    case horizontalRule                // --- or *** or ___
}

/// Protocol for token providers (implemented by Parser module).
///
/// The parser takes paragraph text and returns tokens describing
/// the Markdown structure. Tokens include both content ranges
/// (what to display) and syntax ranges (what to hide when formatted).
protocol TokenProviding {
    /// Parse a paragraph and return its tokens.
    /// - Parameter text: The raw paragraph text.
    /// - Returns: Array of tokens describing Markdown elements.
    func parse(_ text: String) -> [MarkdownToken]
}
```

**Step 2: Create LayoutFragmentProviding (Core Rendering module implements this)**

```swift
import AppKit

/// Protocol for layout fragment providers (implemented by Core Rendering module).
///
/// The rendering module creates custom `NSTextLayoutFragment` subclasses
/// that implement hybrid WYSIWYG:
/// - Active paragraph: show raw Markdown (syntax visible)
/// - Inactive paragraphs: show formatted text (syntax hidden)
protocol LayoutFragmentProviding {
    /// Create a layout fragment for a paragraph.
    /// - Parameters:
    ///   - paragraph: The text paragraph element.
    ///   - range: The text range of the paragraph.
    ///   - tokens: Parsed Markdown tokens for this paragraph.
    ///   - isActive: Whether cursor is in this paragraph.
    /// - Returns: Custom layout fragment for rendering.
    func createLayoutFragment(
        for paragraph: NSTextParagraph,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        isActive: Bool
    ) -> NSTextLayoutFragment
}
```

**Step 3: Create WorkspaceProviding (Sidebar module implements this)**

```swift
import Foundation

/// Represents a file or folder in the workspace.
struct FileTreeNode {
    let url: URL
    let isDirectory: Bool
    let children: [FileTreeNode]?

    var name: String {
        url.lastPathComponent
    }
}

/// Protocol for workspace providers (implemented by Sidebar module).
///
/// The sidebar module manages:
/// - Mounted workspace directories
/// - File tree enumeration
/// - File watching for external changes
/// - Quick open (Cmd+P) functionality
protocol WorkspaceProviding {
    /// Currently mounted workspace root, if any.
    var workspaceRoot: URL? { get }

    /// Mount a directory as the workspace.
    func mountWorkspace(at url: URL) throws

    /// Unmount current workspace.
    func unmountWorkspace()

    /// Get file tree for current workspace.
    func fileTree() -> FileTreeNode?

    /// Callback when a file changes externally.
    var onFileChanged: ((URL) -> Void)? { get set }

    /// Search files by name pattern for quick open.
    func searchFiles(matching pattern: String) -> [URL]
}
```

**Step 4: Create TabManaging (Tabs module implements this)**

```swift
import Foundation

/// Represents a document tab.
struct TabInfo {
    let documentId: UUID
    let title: String
    let isDirty: Bool
    let filePath: URL?
}

/// Protocol for tab managers (implemented by Tabs module).
///
/// The tabs module manages:
/// - Multiple open documents
/// - Tab bar UI
/// - Document lifecycle (open, close, save prompts)
/// - Dirty state tracking
protocol TabManaging {
    /// Currently active tab's document ID.
    var activeDocumentId: UUID? { get }

    /// All open tabs.
    var tabs: [TabInfo] { get }

    /// Open a document in a new tab.
    func openDocument(_ document: DocumentModel)

    /// Close a tab, prompting to save if dirty.
    /// - Returns: true if closed, false if user cancelled.
    func closeTab(documentId: UUID) -> Bool

    /// Switch to a tab.
    func activateTab(documentId: UUID)

    /// Callback when active tab changes.
    var onActiveTabChanged: ((UUID?) -> Void)? { get set }
}
```

**Step 5: Create PaneManaging (Split Panes module implements this)**

```swift
import AppKit

/// Protocol for pane managers (implemented by Split Panes module).
///
/// The split panes module manages:
/// - Multiple panes viewing the same document
/// - Independent active paragraph per pane
/// - Split/unsplit operations
protocol PaneManaging {
    /// Number of panes currently showing.
    var paneCount: Int { get }

    /// Split the current pane horizontally.
    func splitHorizontally()

    /// Split the current pane vertically.
    func splitVertically()

    /// Close the current pane (if more than one).
    func closeCurrentPane()

    /// Get the view for embedding in the window.
    var containerView: NSView { get }
}
```

**Step 6: Commit protocols**

```bash
git add Sources/MarkdownEditor/Protocols/
git commit -m "feat: define module protocols for Parser, Rendering, Workspace, Tabs, Panes"
```

---

## Task 6: Stub Implementations

**Files:**
- Create: `Sources/MarkdownEditor/Stubs/StubTokenProvider.swift`
- Create: `Sources/MarkdownEditor/Stubs/StubLayoutFragmentProvider.swift`

These stubs let the app compile and run while real modules are developed.

**Step 1: Create StubTokenProvider**

```swift
import Foundation

/// Stub token provider that returns no tokens.
/// Replace with real Parser module implementation.
final class StubTokenProvider: TokenProviding {
    func parse(_ text: String) -> [MarkdownToken] {
        // Stub: return empty tokens
        // Real parser will analyze text and return proper tokens
        return []
    }
}
```

**Step 2: Create StubLayoutFragmentProvider**

```swift
import AppKit

/// Stub layout fragment provider that returns default fragments.
/// Replace with real Core Rendering module implementation.
final class StubLayoutFragmentProvider: LayoutFragmentProviding {
    func createLayoutFragment(
        for paragraph: NSTextParagraph,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        isActive: Bool
    ) -> NSTextLayoutFragment {
        // Stub: return default TextKit 2 fragment
        // Real rendering module will return MarkdownLayoutFragment
        return NSTextLayoutFragment(textElement: paragraph, range: range)
    }
}
```

**Step 3: Commit stubs**

```bash
git add Sources/MarkdownEditor/Stubs/
git commit -m "feat: add stub implementations for TokenProviding and LayoutFragmentProviding"
```

---

## Task 7: DocumentModel Tests

**Files:**
- Create: `Tests/MarkdownEditorTests/DocumentModelTests.swift`

**Step 1: Create test file**

```swift
import XCTest
@testable import MarkdownEditor

final class DocumentModelTests: XCTestCase {

    // MARK: - Initialization

    func testNewDocumentIsEmpty() {
        let document = DocumentModel()
        XCTAssertEqual(document.fullString(), "")
        XCTAssertEqual(document.paragraphCount, 0)
        XCTAssertFalse(document.isDirty)
    }

    func testNewDocumentHasUniqueId() {
        let doc1 = DocumentModel()
        let doc2 = DocumentModel()
        XCTAssertNotEqual(doc1.id, doc2.id)
    }

    // MARK: - File Loading

    func testLoadFromFile() throws {
        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        let content = "# Hello\n\nWorld"
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: testFile) }

        // Load document
        let document = try DocumentModel(contentsOf: testFile)
        XCTAssertEqual(document.fullString(), content)
        XCTAssertEqual(document.filePath, testFile)
        XCTAssertFalse(document.isDirty)
    }

    // MARK: - Saving

    func testSaveDocument() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("save-test-\(UUID().uuidString).md")

        defer { try? FileManager.default.removeItem(at: testFile) }

        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "Test content")
        document.filePath = testFile

        try document.save()

        let saved = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(saved, "Test content")
        XCTAssertFalse(document.isDirty)
        XCTAssertNotNil(document.lastSavedAt)
    }

    func testSaveWithoutPathThrows() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "Test")

        XCTAssertThrowsError(try document.save()) { error in
            XCTAssertTrue(error is DocumentError)
        }
    }

    // MARK: - Paragraph Access

    func testParagraphCount() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "Line 1\nLine 2\nLine 3")
        document.paragraphCache.rebuildFull()

        XCTAssertEqual(document.paragraphCount, 3)
    }

    func testParagraphAccess() {
        let document = DocumentModel()
        document.contentStorage.attributedString = NSAttributedString(string: "First\nSecond\nThird")
        document.paragraphCache.rebuildFull()

        // Note: paragraphs include trailing newline
        XCTAssertEqual(document.paragraph(at: 0), "First\n")
        XCTAssertEqual(document.paragraph(at: 1), "Second\n")
        XCTAssertEqual(document.paragraph(at: 2), "Third")  // Last paragraph has no trailing newline
    }

    // MARK: - Revision Tracking

    func testRevisionIncrementsOnEdit() {
        let document = DocumentModel()
        let initialRevision = document.revision

        // Simulate edit notification
        let range = document.contentStorage.documentRange
        document.contentDidChange(in: range, changeInLength: 5)

        XCTAssertEqual(document.revision, initialRevision + 1)
        XCTAssertTrue(document.isDirty)
    }
}
```

**Step 2: Run tests**

Run: `swift test`
Expected: All tests pass

**Step 3: Commit tests**

```bash
git add Tests/
git commit -m "test: add DocumentModel tests"
```

---

## Task 8: Final Integration Test

**Step 1: Build and run full app**

Run: `swift build && swift run`

**Step 2: Manual verification checklist**

- [ ] Window opens with empty editor
- [ ] Can type text
- [ ] Cmd+Z undoes typing
- [ ] Cmd+Shift+Z redoes
- [ ] File → Save As works
- [ ] File → Open works
- [ ] File → New clears editor
- [ ] Cmd+Q quits app

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete scaffolding with working plain-text editor

- TextKit 2 layout stack (NSTextContentStorage → NSTextLayoutManager → NSTextView)
- DocumentModel with paragraph cache
- File open/save operations
- Module protocols for parallel development
- Stub implementations for TokenProviding and LayoutFragmentProviding

Ready for parallel module development."
```

---

## What's Next

With scaffolding complete, parallel development can begin:

| Module | Worktree | Implements |
|--------|----------|------------|
| Core Rendering | `feature/core-rendering` | `LayoutFragmentProviding`, `MarkdownLayoutFragment`, active paragraph tracking |
| Parser | `feature/parser` | `TokenProviding`, full Markdown parsing |
| Sidebar | `feature/sidebar` | `WorkspaceProviding`, file tree, file watching |
| Tabs | `feature/tabs` | `TabManaging`, tab bar, document lifecycle |

Each module has its own implementation plan with full technical details.
