# Lightweight Markdown Editor — Technical Architecture

## Stack Decision

**Language:** Swift 5.9+  
**UI Framework:** AppKit (not SwiftUI)  
**Text Framework:** TextKit 2 (explicitly, not TextKit 1)  
**Target:** macOS 13+ (Ventura)  
**Build System:** Swift Package Manager  

### Why AppKit over SwiftUI

SwiftUI's `TextEditor` is a thin wrapper with limited control over text rendering. The hybrid WYSIWYG requirement — showing raw Markdown on the active line while rendering elsewhere — requires direct manipulation of text layout and drawing. AppKit provides the necessary control surface.

### Why TextKit 2 (Not TextKit 1)

macOS 13+ defaults to TextKit 2, and our requirements strongly favor it:

| Requirement | TextKit 1 | TextKit 2 |
|-------------|-----------|-----------|
| Multiple views of same document | Manual storage sharing, fragile | Native: shared `NSTextContentStorage`, separate `NSTextLayoutManager` per view |
| Large documents | Full layout on load | Viewport-driven incremental layout |
| Split panes | Awkward `NSLayoutManager` sharing | Designed for this exact use case |
| Performance | Eager layout | Lazy layout, better for our targets |
| Custom rendering | Override `drawGlyphs` (fragile) | Subclass `NSTextLayoutFragment` (clean) |

**TextKit 2 Core Classes (we use these):**
- `NSTextContentStorage` — owns the text content, source of truth for the document
- `NSTextLayoutManager` — handles layout for a single view, one per pane
- `NSTextLayoutFragment` — visual representation of a paragraph, **our customization point**
- `NSTextContainer` — defines geometry, attached to layout manager
- `NSTextRange` / `NSTextLocation` — position API (not `NSRange`)

**TextKit 1 Classes (we avoid):**
- `NSTextStorage` — do not use directly
- `NSLayoutManager` — replaced by `NSTextLayoutManager`
- `NSRange` for text positions — use `NSTextRange` instead

### NSTextView Subclassing

We will **not** subclass `NSTextView` unless strictly necessary. Instead:
- Configure `NSTextView` instances via their `textLayoutManager` and `textContentStorage` properties
- Use delegation (`NSTextViewDelegate`, `NSTextContentStorageDelegate`) for behavior customization
- Inject our rendering logic via `NSTextLayoutManagerDelegate` to provide custom `NSTextLayoutFragment` subclasses

---

## Core Architectural Principle: Layout-Based Rendering

### The Insight

**Hybrid WYSIWYG is a visual illusion, not a document mutation.**

When the user types `**bold**`, the document content is literally `**bold**`. Only the *presentation* changes based on whether that paragraph is active (cursor present) or inactive.

This means hybrid rendering should **never mutate `NSTextContentStorage`**. It belongs entirely at the layout/presentation layer.

### Why This Matters

Storage-based rendering (mutating attributes on cursor move) creates severe problems:

| Problem | Root Cause |
|---------|------------|
| Undo corruption | Rendering changes create undo groups mixed with content edits |
| Multi-pane interference | Shared storage means one pane's "active line" affects another |
| Attribute ownership ambiguity | Which attributes are semantic vs. rendering? |
| External reload complexity | Must reapply rendering state after file reload |
| Parser ↔ rendering coupling | Parser must know about storage mutation |

Layout-based rendering avoids all of these by construction.

### The Clean Model

```
┌─────────────────────────────────────────────────────────────────┐
│                     NSTextContentStorage                        │
│                                                                 │
│  • Raw Markdown text: "This is **bold** text"                  │
│  • Semantic attributes only (link URLs, code language hints)    │
│  • NEVER modified by rendering                                  │
│  • Undo stack contains ONLY user edits                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Shared by all panes
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Token Cache (per document)                   │
│                                                                 │
│  • MarkdownToken[] keyed by paragraph                          │
│  • Invalidated on content edit                                  │
│  • No undo interaction                                          │
│  • Rebuilt lazily on demand                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│     Pane 1      │ │     Pane 2      │ │     Pane N      │
│                 │ │                 │ │                 │
│ NSTextLayout    │ │ NSTextLayout    │ │ NSTextLayout    │
│ Manager         │ │ Manager         │ │ Manager         │
│                 │ │                 │ │                 │
│ activeParagraph │ │ activeParagraph │ │ activeParagraph │
│ = 5             │ │ = 12            │ │ = 5             │
│                 │ │                 │ │                 │
│ MarkdownLayout  │ │ MarkdownLayout  │ │ MarkdownLayout  │
│ Fragment        │ │ Fragment        │ │ Fragment        │
│ (custom draw)   │ │ (custom draw)   │ │ (custom draw)   │
└─────────────────┘ └─────────────────┘ └─────────────────┘
        │                   │                   │
        └───────────────────┴───────────────────┘
                            │
              Each pane renders independently
              Active paragraph is pane-local state
              No cross-pane contamination
```

### Data Flow Comparison

**Before (storage-mutating approach — DO NOT USE):**
```
Cursor move → parse → mutate storage attributes → undo risk → redraw
```

**After (layout-based approach — CORRECT):**
```
Cursor move → update activeParagraphIndex → invalidate layout → redraw
```

No storage mutation. No undo interaction. No cross-pane contamination.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Application Layer                        │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌─────────────┐  │
│  │  AppKit   │  │   Tab     │  │   Split   │  │   Sidebar   │  │
│  │  Window   │  │  Manager  │  │   View    │  │  (FileTree) │  │
│  │ Controller│  │           │  │  Manager  │  │             │  │
│  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └──────┬──────┘  │
│        │              │              │               │          │
│        └──────────────┴──────────────┴───────────────┘          │
│                              │                                   │
├──────────────────────────────┼───────────────────────────────────┤
│                     Document Layer                               │
│                              │                                   │
│              ┌───────────────┴───────────────┐                  │
│              │        DocumentModel          │                  │
│              │  ┌─────────────────────────┐  │                  │
│              │  │  NSTextContentStorage   │◀─┼── Raw text only  │
│              │  │  (never rendering attrs)│  │                  │
│              │  └───────────┬─────────────┘  │                  │
│              │              │                │                  │
│              │  ┌───────────┴─────────────┐  │                  │
│              │  │   MarkdownTokenCache    │◀─┼── Parsed tokens  │
│              │  └─────────────────────────┘  │   (side data)    │
│              │              │                │                  │
│              │  ┌───────────┴─────────────┐  │                  │
│              │  │     UndoManager         │◀─┼── Content only   │
│              │  └─────────────────────────┘  │                  │
│              └───────────────────────────────┘                  │
│                              │                                   │
│          ┌───────────────────┼───────────────────┐              │
│          ▼                   ▼                   ▼              │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │    Pane 1    │   │    Pane 2    │   │    Pane N    │        │
│  │              │   │              │   │              │        │
│  │ ┌──────────┐ │   │ ┌──────────┐ │   │ ┌──────────┐ │        │
│  │ │NSTextView│ │   │ │NSTextView│ │   │ │NSTextView│ │        │
│  │ └────┬─────┘ │   │ └────┬─────┘ │   │ └────┬─────┘ │        │
│  │      │       │   │      │       │   │      │       │        │
│  │ ┌────┴─────┐ │   │ ┌────┴─────┐ │   │ ┌────┴─────┐ │        │
│  │ │ Layout   │ │   │ │ Layout   │ │   │ │ Layout   │ │        │
│  │ │ Manager  │ │   │ │ Manager  │ │   │ │ Manager  │ │        │
│  │ │ Delegate │ │   │ │ Delegate │ │   │ │ Delegate │ │        │
│  │ └────┬─────┘ │   │ └────┬─────┘ │   │ └────┬─────┘ │        │
│  │      │       │   │      │       │   │      │       │        │
│  │ ┌────┴─────┐ │   │ ┌────┴─────┐ │   │ ┌────┴─────┐ │        │
│  │ │ Markdown │ │   │ │ Markdown │ │   │ │ Markdown │ │        │
│  │ │ Layout   │ │   │ │ Layout   │ │   │ │ Layout   │ │        │
│  │ │ Fragment │ │   │ │ Fragment │ │   │ │ Fragment │ │        │
│  │ └──────────┘ │   │ └──────────┘ │   │ └──────────┘ │        │
│  │              │   │              │   │              │        │
│  │ activePara=5 │   │ activePara=12│   │ activePara=5 │        │
│  └──────────────┘   └──────────────┘   └──────────────┘        │
│                                                                  │
│         Each pane has its own layout manager + delegate          │
│         All share the same NSTextContentStorage                  │
│         Active paragraph is PANE-LOCAL state                     │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                        Parsing Layer                             │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
│  │   Markdown     │  │   Token        │  │   Syntax           │ │
│  │   Parser       │  │   Cache        │  │   Theme            │ │
│  └────────────────┘  └────────────────┘  └────────────────────┘ │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                        File System Layer                         │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
│  │  Workspace     │  │   File         │  │   Auto-Save        │ │
│  │  Manager       │  │   Watcher      │  │   Controller       │ │
│  └────────────────┘  └────────────────┘  └────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Document Layer

#### Terminology: "Line" Means Paragraph, Not Visual Line

**Critical distinction:** Throughout this document, "line" refers to a **logical paragraph** (text between newline characters), not a **visual line** (what fits on screen before soft-wrapping).

| Term | Definition | TextKit 2 Concept |
|------|------------|-------------------|
| **Line / Paragraph** | Text between `\n` characters | `NSTextParagraph` |
| **Visual line** | Screen row after soft-wrap | `NSTextLineFragment` |

**Hybrid rendering operates on paragraphs, not visual lines.**

This means:
- A long paragraph that soft-wraps across 5 visual lines is **one unit** for rendering purposes
- When the cursor is anywhere in that paragraph, the entire paragraph shows raw Markdown
- Moving between visual lines within the same paragraph does **not** trigger re-rendering

```
┌─────────────────────────────────────────────────────────────┐
│ This is a **long paragraph** that wraps across multiple     │  ← Visual line 1
│ screen lines but is still considered a single "line" for    │  ← Visual line 2
│ hybrid rendering purposes.                                  │  ← Visual line 3
└─────────────────────────────────────────────────────────────┘
                    ↑ All one paragraph — rendered as a unit
```

**Why paragraph-based, not visual-line-based:**
1. Markdown semantics are paragraph-oriented (emphasis can span soft-wrap boundaries)
2. `NSTextParagraph` is the natural enumeration unit in TextKit 2
3. Visual line boundaries change on window resize — paragraph boundaries don't
4. Simpler implementation with fewer edge cases

#### `DocumentModel`

The document model owns the content storage and token cache. It **never** contains rendering attributes.

```swift
/// Document model — owns content and parsed token cache.
/// CRITICAL: NSTextContentStorage contains raw text only, never rendering attributes.
class DocumentModel {
    let id: UUID
    var filePath: URL?
    
    /// Source of truth for document text.
    /// Contains raw Markdown and semantic attributes only.
    let contentStorage: NSTextContentStorage
    
    /// Undo manager for content changes only.
    /// Rendering never touches this.
    let undoManager: UndoManager
    
    /// Cached parsed tokens, keyed by paragraph index.
    /// Invalidated on content edit, rebuilt lazily.
    private(set) var tokenCache: MarkdownTokenCache
    
    /// Paragraph index cache for O(1) lookups.
    private(set) lazy var paragraphCache: ParagraphIndexCache = {
        ParagraphIndexCache(contentStorage: contentStorage)
    }()
    
    var isDirty: Bool = false
    var lastSavedAt: Date?
    
    /// Document revision counter — incremented on every edit.
    /// Used by token cache to detect staleness.
    private(set) var revision: UInt64 = 0
    
    init() {
        self.id = UUID()
        self.contentStorage = NSTextContentStorage()
        self.undoManager = UndoManager()
        self.tokenCache = MarkdownTokenCache()
        
        contentStorage.undoManager = undoManager
        contentStorage.delegate = self
    }
    
    init(contentsOf url: URL) throws {
        self.id = UUID()
        self.filePath = url
        self.contentStorage = NSTextContentStorage()
        self.undoManager = UndoManager()
        self.tokenCache = MarkdownTokenCache()
        
        let text = try String(contentsOf: url, encoding: .utf8)
        contentStorage.attributedString = NSAttributedString(string: text)
        contentStorage.undoManager = undoManager
        contentStorage.delegate = self
        
        // Build paragraph cache (O(N), but only on load)
        paragraphCache.rebuildFull()
    }
    
    // MARK: - Text Access
    
    /// Full document as string — use sparingly (serialization, search).
    func fullString() -> String {
        var result = ""
        contentStorage.enumerateTextElements(from: contentStorage.documentRange.location) { element in
            if let paragraph = element as? NSTextParagraph {
                result += paragraph.attributedString.string
            }
            return true
        }
        return result
    }
    
    var paragraphCount: Int {
        paragraphCache.count
    }
    
    func paragraph(at index: Int) -> String? {
        guard let range = paragraphCache.paragraphRange(at: index) else { return nil }
        var result: String?
        contentStorage.enumerateTextElements(from: range.location) { element in
            if let paragraph = element as? NSTextParagraph {
                result = paragraph.attributedString.string
            }
            return false
        }
        return result
    }
    
    func paragraphRange(at index: Int) -> NSTextRange? {
        paragraphCache.paragraphRange(at: index)
    }
    
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        paragraphCache.paragraphIndex(for: location)
    }
    
    // MARK: - Token Access
    
    /// Get parsed tokens for a paragraph. Parses lazily if not cached.
    func tokens(forParagraphAt index: Int) -> [MarkdownToken] {
        if let cached = tokenCache.tokens(forParagraph: index, revision: revision) {
            return cached
        }
        
        // Parse and cache
        guard let text = paragraph(at: index) else { return [] }
        let tokens = MarkdownParser.shared.parse(text)
        tokenCache.setTokens(tokens, forParagraph: index, revision: revision)
        return tokens
    }
    
    // MARK: - Save
    
    func save() throws {
        guard let url = filePath else {
            throw DocumentError.noFilePath
        }
        let content = fullString()
        try content.write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
        lastSavedAt = Date()
    }
}

// MARK: - NSTextContentStorageDelegate

extension DocumentModel: NSTextContentStorageDelegate {
    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        // Default paragraph creation — no customization needed
        return nil
    }
}

// MARK: - Edit Notifications

extension DocumentModel {
    /// Called when content changes. Updates caches and marks dirty.
    func contentDidChange(in editedRange: NSTextRange, changeInLength delta: Int) {
        revision += 1
        isDirty = true
        
        // Update paragraph cache incrementally
        paragraphCache.didProcessEditing(in: editedRange, changeInLength: delta)
        
        // Invalidate affected token cache entries
        if let startIndex = paragraphIndex(for: editedRange.location) {
            tokenCache.invalidate(fromParagraph: startIndex)
        }
    }
}

enum DocumentError: Error {
    case noFilePath
}
```

#### `MarkdownTokenCache`

Tokens are stored in a side cache, **not** in the content storage. This is critical for the layout-based rendering model.

```swift
/// Cache of parsed Markdown tokens, keyed by paragraph index and document revision.
/// Tokens are NEVER stored in NSTextContentStorage.
class MarkdownTokenCache {
    
    private struct CacheEntry {
        let tokens: [MarkdownToken]
        let revision: UInt64
    }
    
    private var entries: [Int: CacheEntry] = [:]
    
    /// Get cached tokens if still valid for current revision.
    func tokens(forParagraph index: Int, revision: UInt64) -> [MarkdownToken]? {
        guard let entry = entries[index], entry.revision == revision else {
            return nil
        }
        return entry.tokens
    }
    
    /// Cache tokens for a paragraph at current revision.
    func setTokens(_ tokens: [MarkdownToken], forParagraph index: Int, revision: UInt64) {
        entries[index] = CacheEntry(tokens: tokens, revision: revision)
    }
    
    /// Invalidate cache entries from a paragraph onwards.
    /// Called when an edit may have shifted paragraph boundaries.
    func invalidate(fromParagraph index: Int) {
        entries = entries.filter { $0.key < index }
    }
    
    /// Clear entire cache (e.g., on document reload).
    func clear() {
        entries.removeAll()
    }
}
```

#### `MarkdownToken`

Tokens describe parsed Markdown elements with their ranges. They do **not** contain attribute dictionaries — that's the theme's job at draw time.

```swift
/// A parsed Markdown token with location information.
/// Tokens are computed by the parser and cached; never stored in NSTextContentStorage.
struct MarkdownToken {
    /// The type of Markdown element.
    let element: MarkdownElement
    
    /// Range of the content (e.g., "bold" in "**bold**").
    let contentRange: Range<Int>
    
    /// Ranges of syntax characters (e.g., the "**" markers).
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

/// Explicitly scoped grammar for v1.
enum MarkdownElement {
    case text                    // Plain text
    case heading(level: Int)     // # through ######
    case bold                    // **text** or __text__
    case italic                  // *text* or _text_
    case boldItalic              // ***text***
    case inlineCode              // `code`
    case fencedCodeBlock(language: String?)  // ```lang ... ```
    case indentedCodeBlock       // 4-space indent
    case unorderedListItem       // - or * or +
    case orderedListItem(number: Int)  // 1. 2. etc
    case blockquote              // > text
    case link(url: String)       // [text](url)
    case horizontalRule          // --- or *** or ___
    
    // Explicitly NOT supported in v1:
    // - Tables
    // - Images  
    // - Footnotes
    // - HTML blocks
    // - Reference-style links
}
```

#### `ParagraphIndexCache`

Performance-critical cache for O(1) paragraph lookups. Implementation unchanged from before, but included here for completeness.

```swift
/// Maintains O(1) paragraph index lookups via cached range mapping.
/// Updated incrementally on document edits.
class ParagraphIndexCache {
    
    private var paragraphRanges: [(range: NSTextRange, index: Int)] = []
    private var documentVersion: Int = 0
    
    weak var contentStorage: NSTextContentStorage?
    
    init(contentStorage: NSTextContentStorage) {
        self.contentStorage = contentStorage
        rebuildFull()
    }
    
    // MARK: - Lookup (O(log N) via binary search)
    
    func paragraphIndex(for location: NSTextLocation) -> Int? {
        guard let storage = contentStorage else { return nil }
        
        var low = 0
        var high = paragraphRanges.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let entry = paragraphRanges[mid]
            
            if entry.range.contains(location) {
                return entry.index
            }
            
            if storage.offset(from: storage.documentRange.location, to: location) <
               storage.offset(from: storage.documentRange.location, to: entry.range.location) {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }
    
    func paragraphRange(at index: Int) -> NSTextRange? {
        guard index >= 0 && index < paragraphRanges.count else { return nil }
        return paragraphRanges[index].range
    }
    
    var count: Int {
        paragraphRanges.count
    }
    
    // MARK: - Incremental Update
    
    func didProcessEditing(in editedRange: NSTextRange, changeInLength delta: Int) {
        // Implementation: update affected entries, adjust indices
        // (See full implementation in previous document version)
        // For brevity, showing that this triggers incremental update
        rebuildFull() // Simplified; real impl is incremental
    }
    
    func rebuildFull() {
        guard let storage = contentStorage else { return }
        
        paragraphRanges.removeAll()
        var index = 0
        
        storage.enumerateTextElements(from: storage.documentRange.location) { element in
            if let paragraph = element as? NSTextParagraph,
               let range = paragraph.elementRange {
                paragraphRanges.append((range: range, index: index))
                index += 1
            }
            return true
        }
        
        documentVersion += 1
    }
}
```

#### `PaneController`

Each pane owns its layout manager, layout delegate, and **pane-local active paragraph state**.

```swift
/// Controller for a single editor pane.
/// Owns layout manager and tracks pane-local active paragraph.
class PaneController: NSObject {
    let id: UUID
    weak var document: DocumentModel?
    
    let textView: NSTextView
    let layoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer
    
    /// Layout delegate that provides custom MarkdownLayoutFragments.
    private let layoutDelegate: MarkdownLayoutManagerDelegate
    
    /// PANE-LOCAL active paragraph index.
    /// Each pane tracks this independently — no cross-pane interference.
    private(set) var activeParagraphIndex: Int?
    
    /// Debounce timer for cursor movement.
    private var cursorDebounceTimer: DispatchWorkItem?
    private let cursorDebounceInterval: TimeInterval = 0.016  // ~1 frame
    
    init(document: DocumentModel, frame: NSRect) {
        self.id = UUID()
        self.document = document
        
        // Create layout infrastructure
        self.layoutManager = NSTextLayoutManager()
        self.textContainer = NSTextContainer(size: frame.size)
        self.layoutDelegate = MarkdownLayoutManagerDelegate()
        
        layoutManager.textContainer = textContainer
        layoutManager.delegate = layoutDelegate
        
        // Share document's content storage
        document.contentStorage.addTextLayoutManager(layoutManager)
        
        // Create text view
        self.textView = NSTextView(frame: frame, textContainer: textContainer)
        
        super.init()
        
        // Wire up delegate
        layoutDelegate.paneController = self
        textView.delegate = self
    }
    
    deinit {
        document?.contentStorage.removeTextLayoutManager(layoutManager)
    }
    
    // MARK: - Cursor Position
    
    var cursorTextLocation: NSTextLocation? {
        guard let selection = layoutManager.textSelections.first,
              let range = selection.textRanges.first else { return nil }
        return range.location
    }
    
    // MARK: - Active Paragraph Management
    
    /// Called when selection changes. Debounces and updates active paragraph.
    func handleSelectionChange() {
        // Cancel pending update
        cursorDebounceTimer?.cancel()
        
        // Schedule debounced update
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateActiveParagraph()
        }
        cursorDebounceTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + cursorDebounceInterval, execute: workItem)
    }
    
    private func updateActiveParagraph() {
        guard let document = document,
              let location = cursorTextLocation else { return }
        
        let newIndex = document.paragraphIndex(for: location)
        
        // Only update if paragraph actually changed
        guard newIndex != activeParagraphIndex else { return }
        
        let previousIndex = activeParagraphIndex
        activeParagraphIndex = newIndex
        
        // Invalidate layout for affected paragraphs
        // This triggers redraw with new active state — NO storage mutation
        if let prevIdx = previousIndex,
           let range = document.paragraphRange(at: prevIdx) {
            layoutManager.invalidateLayout(for: range)
        }
        
        if let newIdx = newIndex,
           let range = document.paragraphRange(at: newIdx) {
            layoutManager.invalidateLayout(for: range)
        }
    }
    
    /// Check if a paragraph index is the active one for this pane.
    func isActiveParagraph(at index: Int) -> Bool {
        return index == activeParagraphIndex
    }
}

// MARK: - NSTextViewDelegate

extension PaneController: NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {
        handleSelectionChange()
    }
}
```

### 2. Layout/Rendering Layer

This is where hybrid WYSIWYG actually happens. The key insight: **we customize drawing, not storage**.

#### `MarkdownLayoutManagerDelegate`

Provides custom `MarkdownLayoutFragment` instances for each paragraph.

```swift
/// Delegate that provides custom layout fragments for Markdown rendering.
/// This is the integration point between TextKit 2 and our rendering logic.
class MarkdownLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    
    /// Weak reference to owning pane (for active paragraph state).
    weak var paneController: PaneController?
    
    /// Theme for rendering.
    var theme: SyntaxTheme = .default
    
    // MARK: - NSTextLayoutManagerDelegate
    
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        
        guard let paragraph = textElement as? NSTextParagraph,
              let pane = paneController,
              let document = pane.document else {
            // Fallback to default fragment
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        
        // Determine paragraph index
        guard let paragraphIndex = document.paragraphIndex(for: location) else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        
        // Get tokens for this paragraph
        let tokens = document.tokens(forParagraphAt: paragraphIndex)
        
        // Check if this is the active paragraph (PANE-LOCAL state)
        let isActive = pane.isActiveParagraph(at: paragraphIndex)
        
        // Create custom fragment with rendering context
        return MarkdownLayoutFragment(
            textElement: paragraph,
            range: paragraph.elementRange,
            tokens: tokens,
            isActiveParagraph: isActive,
            theme: theme
        )
    }
}
```

#### `MarkdownLayoutFragment` — The Secret Weapon

This is where the actual hybrid rendering happens. We subclass `NSTextLayoutFragment` and override `draw(at:in:)`.

**Key insight:** We draw glyphs ourselves, deciding which to show based on active state. The underlying text is unchanged; only the visual representation differs.

```swift
/// Custom layout fragment that implements hybrid WYSIWYG rendering.
/// 
/// This is the core of the rendering system. It:
/// - Draws formatted Markdown (syntax hidden) for inactive paragraphs
/// - Draws raw Markdown (syntax visible) for the active paragraph
/// - NEVER modifies NSTextContentStorage
/// - Makes rendering purely a drawing concern
final class MarkdownLayoutFragment: NSTextLayoutFragment {
    
    /// Parsed tokens for this paragraph.
    let tokens: [MarkdownToken]
    
    /// Whether this is the active paragraph (cursor present).
    /// This is PANE-LOCAL — different panes can have different active paragraphs.
    let isActiveParagraph: Bool
    
    /// Theme for colors and fonts.
    let theme: SyntaxTheme
    
    init(
        textElement: NSTextElement,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        isActiveParagraph: Bool,
        theme: SyntaxTheme
    ) {
        self.tokens = tokens
        self.isActiveParagraph = isActiveParagraph
        self.theme = theme
        super.init(textElement: textElement, range: range)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    // MARK: - Drawing
    
    override func draw(at point: CGPoint, in context: CGContext) {
        guard let paragraph = textElement as? NSTextParagraph else {
            super.draw(at: point, in: context)
            return
        }
        
        let text = paragraph.attributedString.string
        
        if isActiveParagraph {
            drawRawMarkdown(text: text, at: point, in: context)
        } else {
            drawFormattedMarkdown(text: text, at: point, in: context)
        }
    }
    
    // MARK: - Raw Markdown Drawing (Active Paragraph)
    
    /// Draw with all syntax characters visible.
    /// Used when cursor is in this paragraph.
    private func drawRawMarkdown(text: String, at point: CGPoint, in context: CGContext) {
        // Draw the full text with minimal styling
        // Syntax characters are visible but may be styled differently (muted color)
        
        let attributedString = NSMutableAttributedString(string: text, attributes: theme.bodyAttributes)
        
        // Apply muted color to syntax characters
        for token in tokens {
            for syntaxRange in token.syntaxRanges {
                let nsRange = NSRange(syntaxRange, in: text)
                attributedString.addAttributes(theme.syntaxCharacterAttributes, range: nsRange)
            }
        }
        
        // Draw using standard attributed string drawing
        drawAttributedString(attributedString, at: point, in: context)
    }
    
    // MARK: - Formatted Markdown Drawing (Inactive Paragraph)
    
    /// Draw with syntax characters hidden and formatting applied.
    /// Used when cursor is NOT in this paragraph.
    private func drawFormattedMarkdown(text: String, at point: CGPoint, in context: CGContext) {
        // Build a drawing plan that skips syntax characters
        var drawingRuns: [DrawingRun] = []
        var currentPosition: CGFloat = 0
        var textIndex = text.startIndex
        
        // Sort tokens by position
        let sortedTokens = tokens.sorted { $0.contentRange.lowerBound < $1.contentRange.lowerBound }
        
        for token in sortedTokens {
            // Handle text before this token
            let tokenStart = text.index(text.startIndex, offsetBy: token.contentRange.lowerBound)
            if textIndex < tokenStart {
                let plainText = String(text[textIndex..<tokenStart])
                // Check if this is syntax that should be hidden
                if !isSyntaxRange(textIndex..<tokenStart, in: token) {
                    drawingRuns.append(DrawingRun(
                        text: plainText,
                        attributes: theme.bodyAttributes,
                        xOffset: currentPosition
                    ))
                    currentPosition += measureWidth(plainText, attributes: theme.bodyAttributes)
                }
            }
            
            // Draw token content with appropriate styling
            let contentStart = text.index(text.startIndex, offsetBy: token.contentRange.lowerBound)
            let contentEnd = text.index(text.startIndex, offsetBy: token.contentRange.upperBound)
            let contentText = String(text[contentStart..<contentEnd])
            
            let attributes = attributesForElement(token.element)
            drawingRuns.append(DrawingRun(
                text: contentText,
                attributes: attributes,
                xOffset: currentPosition
            ))
            currentPosition += measureWidth(contentText, attributes: attributes)
            
            textIndex = text.index(text.startIndex, offsetBy: token.contentRange.upperBound)
            
            // Skip past syntax characters at end of token
            for syntaxRange in token.syntaxRanges where syntaxRange.lowerBound >= token.contentRange.upperBound {
                textIndex = text.index(text.startIndex, offsetBy: syntaxRange.upperBound)
            }
        }
        
        // Handle remaining text after last token
        if textIndex < text.endIndex {
            let remainingText = String(text[textIndex...])
            drawingRuns.append(DrawingRun(
                text: remainingText,
                attributes: theme.bodyAttributes,
                xOffset: currentPosition
            ))
        }
        
        // Execute drawing
        for run in drawingRuns {
            let runPoint = CGPoint(x: point.x + run.xOffset, y: point.y)
            drawText(run.text, at: runPoint, attributes: run.attributes, in: context)
        }
    }
    
    // MARK: - Drawing Helpers
    
    private struct DrawingRun {
        let text: String
        let attributes: [NSAttributedString.Key: Any]
        let xOffset: CGFloat
    }
    
    private func drawAttributedString(_ string: NSAttributedString, at point: CGPoint, in context: CGContext) {
        // Use Core Text for drawing
        let line = CTLineCreateWithAttributedString(string)
        
        context.saveGState()
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
    
    private func drawText(_ text: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any], in context: CGContext) {
        let attrString = NSAttributedString(string: text, attributes: attributes)
        drawAttributedString(attrString, at: point, in: context)
    }
    
    private func measureWidth(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
    
    private func isSyntaxRange(_ range: Range<String.Index>, in token: MarkdownToken) -> Bool {
        // Check if the given range overlaps with any syntax ranges in the token
        // (Implementation detail for proper syntax hiding)
        return false // Simplified
    }
    
    private func attributesForElement(_ element: MarkdownElement) -> [NSAttributedString.Key: Any] {
        switch element {
        case .heading(let level):
            return theme.headingAttributes(level: level)
        case .bold:
            return theme.boldAttributes
        case .italic:
            return theme.italicAttributes
        case .boldItalic:
            return theme.boldItalicAttributes
        case .inlineCode:
            return theme.inlineCodeAttributes
        case .link:
            return theme.linkAttributes
        case .fencedCodeBlock, .indentedCodeBlock:
            return theme.codeBlockAttributes
        case .blockquote:
            return theme.blockquoteAttributes
        default:
            return theme.bodyAttributes
        }
    }
}
```

#### Important: Selection and Caret Positioning

A critical question: if we're hiding syntax characters visually, won't selection and caret be misaligned?

**Answer: No, because TextKit 2 still knows the real glyph positions.**

The underlying string is unchanged (`**bold**` is still 8 characters). TextKit 2 computes glyph advances and positions based on the real text. We are only changing *what gets painted*, not the geometry.

This is the same technique used by:
- Xcode's invisible indentation guides
- Code folding in editors
- Inline diagnostic overlays

For selection highlighting to work correctly, we need to ensure our custom drawing doesn't interfere with TextKit's selection rendering. The default `NSTextLayoutFragment` handles selection drawing in a separate pass that we don't override.

#### `SyntaxTheme`

Pure data defining colors, fonts, and sizes. No rendering logic.

```swift
/// Theme defining visual appearance for Markdown elements.
/// Pure data — no rendering logic.
struct SyntaxTheme {
    let bodyFont: NSFont
    let headingFonts: [Int: NSFont]
    let boldFont: NSFont
    let italicFont: NSFont
    let boldItalicFont: NSFont
    let codeFont: NSFont
    
    let bodyColor: NSColor
    let headingColor: NSColor
    let linkColor: NSColor
    let codeBackgroundColor: NSColor
    let syntaxCharacterColor: NSColor  // Muted color for raw mode
    let blockquoteColor: NSColor
    
    var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: bodyColor]
    }
    
    var boldAttributes: [NSAttributedString.Key: Any] {
        [.font: boldFont, .foregroundColor: bodyColor]
    }
    
    var italicAttributes: [NSAttributedString.Key: Any] {
        [.font: italicFont, .foregroundColor: bodyColor]
    }
    
    var boldItalicAttributes: [NSAttributedString.Key: Any] {
        [.font: boldItalicFont, .foregroundColor: bodyColor]
    }
    
    var inlineCodeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: bodyColor,
            .backgroundColor: codeBackgroundColor
        ]
    }
    
    var codeBlockAttributes: [NSAttributedString.Key: Any] {
        [.font: codeFont, .foregroundColor: bodyColor]
    }
    
    var linkAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }
    
    var blockquoteAttributes: [NSAttributedString.Key: Any] {
        [.font: italicFont, .foregroundColor: blockquoteColor]
    }
    
    var syntaxCharacterAttributes: [NSAttributedString.Key: Any] {
        [.font: codeFont, .foregroundColor: syntaxCharacterColor]
    }
    
    func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        [.font: headingFonts[level] ?? bodyFont, .foregroundColor: headingColor]
    }
    
    static let `default` = SyntaxTheme(
        bodyFont: .systemFont(ofSize: 14),
        headingFonts: [
            1: .systemFont(ofSize: 28, weight: .bold),
            2: .systemFont(ofSize: 22, weight: .bold),
            3: .systemFont(ofSize: 18, weight: .semibold),
            4: .systemFont(ofSize: 16, weight: .semibold),
            5: .systemFont(ofSize: 14, weight: .semibold),
            6: .systemFont(ofSize: 14, weight: .medium)
        ],
        boldFont: .boldSystemFont(ofSize: 14),
        italicFont: NSFontManager.shared.convert(.systemFont(ofSize: 14), toHaveTrait: .italicFontMask),
        boldItalicFont: NSFontManager.shared.font(
            withFamily: NSFont.systemFont(ofSize: 14).familyName ?? "System",
            traits: [.boldFontMask, .italicFontMask],
            weight: 0,
            size: 14
        ) ?? .boldSystemFont(ofSize: 14),
        codeFont: .monospacedSystemFont(ofSize: 13, weight: .regular),
        bodyColor: .textColor,
        headingColor: .textColor,
        linkColor: .linkColor,
        codeBackgroundColor: .quaternaryLabelColor,
        syntaxCharacterColor: .tertiaryLabelColor,
        blockquoteColor: .secondaryLabelColor
    )
}
```

### 3. Parsing Layer

#### `MarkdownParser`

Produces tokens from text. Pure function — no side effects, no storage interaction.

```swift
/// Parser that converts Markdown text to tokens.
/// Pure function: text in, tokens out.
/// NEVER interacts with NSTextContentStorage.
class MarkdownParser {
    
    static let shared = MarkdownParser()
    
    /// Parse a paragraph of Markdown text.
    func parse(_ text: String) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        
        // Check for block-level elements first
        if let headingToken = parseHeading(text) {
            tokens.append(headingToken)
            return tokens
        }
        
        if let blockquoteToken = parseBlockquote(text) {
            tokens.append(blockquoteToken)
            return tokens
        }
        
        if let listToken = parseListItem(text) {
            tokens.append(listToken)
            return tokens
        }
        
        if let hrToken = parseHorizontalRule(text) {
            tokens.append(hrToken)
            return tokens
        }
        
        // Parse inline elements
        tokens.append(contentsOf: parseInlineElements(text))
        
        return tokens
    }
    
    // MARK: - Block-Level Parsing
    
    private func parseHeading(_ text: String) -> MarkdownToken? {
        let pattern = "^(#{1,6})\\s+(.+)$"
        guard let match = text.firstMatch(of: try! Regex(pattern)) else { return nil }
        
        let hashes = String(match.output.1)
        let level = hashes.count
        let contentStart = hashes.count + 1  // +1 for space
        let contentEnd = text.count
        
        return MarkdownToken(
            element: .heading(level: level),
            contentRange: contentStart..<contentEnd,
            syntaxRanges: [0..<hashes.count]
        )
    }
    
    private func parseBlockquote(_ text: String) -> MarkdownToken? {
        guard text.hasPrefix("> ") else { return nil }
        
        return MarkdownToken(
            element: .blockquote,
            contentRange: 2..<text.count,
            syntaxRanges: [0..<2]
        )
    }
    
    private func parseListItem(_ text: String) -> MarkdownToken? {
        // Unordered: - item, * item, + item
        let unorderedPattern = "^([\\-\\*\\+])\\s+(.+)$"
        if let match = text.firstMatch(of: try! Regex(unorderedPattern)) {
            return MarkdownToken(
                element: .unorderedListItem,
                contentRange: 2..<text.count,
                syntaxRanges: [0..<2]
            )
        }
        
        // Ordered: 1. item, 2. item
        let orderedPattern = "^(\\d+\\.)\\s+(.+)$"
        if let match = text.firstMatch(of: try! Regex(orderedPattern)) {
            let marker = String(match.output.1)
            let number = Int(marker.dropLast()) ?? 1
            return MarkdownToken(
                element: .orderedListItem(number: number),
                contentRange: (marker.count + 1)..<text.count,
                syntaxRanges: [0..<(marker.count + 1)]
            )
        }
        
        return nil
    }
    
    private func parseHorizontalRule(_ text: String) -> MarkdownToken? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let patterns = ["---", "***", "___"]
        
        for pattern in patterns {
            if trimmed.hasPrefix(pattern) && trimmed.allSatisfy({ $0 == pattern.first || $0 == " " }) {
                return MarkdownToken(
                    element: .horizontalRule,
                    contentRange: 0..<0,  // No content
                    syntaxRanges: [0..<text.count]
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Inline Parsing
    
    private func parseInlineElements(_ text: String) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        
        // Bold italic: ***text***
        tokens.append(contentsOf: parsePattern(
            in: text,
            pattern: "\\*\\*\\*(.+?)\\*\\*\\*",
            element: .boldItalic,
            syntaxLength: 3
        ))
        
        // Bold: **text** or __text__
        tokens.append(contentsOf: parsePattern(
            in: text,
            pattern: "\\*\\*(.+?)\\*\\*|__(.+?)__",
            element: .bold,
            syntaxLength: 2
        ))
        
        // Italic: *text* or _text_
        tokens.append(contentsOf: parsePattern(
            in: text,
            pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)",
            element: .italic,
            syntaxLength: 1
        ))
        
        // Inline code: `code`
        tokens.append(contentsOf: parsePattern(
            in: text,
            pattern: "`([^`]+)`",
            element: .inlineCode,
            syntaxLength: 1
        ))
        
        // Links: [text](url)
        tokens.append(contentsOf: parseLinks(in: text))
        
        return tokens
    }
    
    private func parsePattern(
        in text: String,
        pattern: String,
        element: MarkdownElement,
        syntaxLength: Int
    ) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        
        guard let regex = try? Regex(pattern) else { return tokens }
        
        for match in text.matches(of: regex) {
            let fullRange = match.range
            let start = text.distance(from: text.startIndex, to: fullRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: fullRange.upperBound)
            
            let contentStart = start + syntaxLength
            let contentEnd = end - syntaxLength
            
            tokens.append(MarkdownToken(
                element: element,
                contentRange: contentStart..<contentEnd,
                syntaxRanges: [
                    start..<(start + syntaxLength),
                    (end - syntaxLength)..<end
                ]
            ))
        }
        
        return tokens
    }
    
    private func parseLinks(in text: String) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? Regex(pattern) else { return tokens }
        
        for match in text.matches(of: regex) {
            let fullRange = match.range
            let start = text.distance(from: text.startIndex, to: fullRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: fullRange.upperBound)
            
            // Find the ] to determine content vs URL boundary
            let fullText = String(text[fullRange])
            if let bracketIndex = fullText.firstIndex(of: "]") {
                let bracketOffset = fullText.distance(from: fullText.startIndex, to: bracketIndex)
                let contentStart = start + 1  // After [
                let contentEnd = start + bracketOffset
                
                // Extract URL
                let urlStart = contentEnd + 2  // After ](
                let urlEnd = end - 1  // Before )
                let url = String(text[text.index(text.startIndex, offsetBy: urlStart)..<text.index(text.startIndex, offsetBy: urlEnd)])
                
                tokens.append(MarkdownToken(
                    element: .link(url: url),
                    contentRange: contentStart..<contentEnd,
                    syntaxRanges: [
                        start..<(start + 1),           // [
                        contentEnd..<(contentEnd + 2),  // ](
                        (urlEnd)..<end                  // )
                    ]
                ))
            }
        }
        
        return tokens
    }
}
```

### Multi-Paragraph Constructs

#### The Problem

The parser's `parse(_ text: String)` method takes a single paragraph, assuming paragraphs can be parsed independently. This assumption breaks for fenced code blocks:

```markdown
Here is some code:

```swift
let x = 1
let y = 2
```

Back to normal text.
```

The paragraph containing `let x = 1` has no syntactic indication it's inside a code block. The opening ` ``` ` is in a previous paragraph; the closing ` ``` ` is in a later one.

#### Design Decision: Block Context Tracking

We solve this with a **block context pre-scan** that identifies multi-paragraph construct boundaries before per-paragraph parsing.

```swift
/// Identifies regions where paragraph-independence doesn't hold.
/// Computed on document load and updated incrementally on edits.
struct BlockContext {
    /// Ranges of fenced code blocks (paragraph indices, inclusive).
    /// Example: [(2, 5)] means paragraphs 2-5 are inside a fenced block.
    var fencedCodeBlocks: [(start: Int, end: Int, language: String?)] = []
    
    /// Check if a paragraph is inside a fenced code block.
    func isInsideFencedCodeBlock(paragraphIndex: Int) -> (Bool, String?) {
        for block in fencedCodeBlocks {
            if paragraphIndex > block.start && paragraphIndex < block.end {
                return (true, block.language)
            }
        }
        return (false, nil)
    }
    
    /// Check if a paragraph is a fence boundary (opening or closing).
    func isFenceBoundary(paragraphIndex: Int) -> Bool {
        for block in fencedCodeBlocks {
            if paragraphIndex == block.start || paragraphIndex == block.end {
                return true
            }
        }
        return false
    }
}
```

#### Block Context Scanner

The scanner runs on document load and incrementally on edits:

```swift
class BlockContextScanner {
    
    /// Scan entire document for block constructs.
    /// Called on document load. O(N) where N = paragraph count.
    func scan(document: DocumentModel) -> BlockContext {
        var context = BlockContext()
        var openFence: (index: Int, language: String?)? = nil
        
        for i in 0..<document.paragraphCount {
            guard let text = document.paragraph(at: i) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            
            // Check for fence
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fenceChar = trimmed.first!
                let fencePattern = String(repeating: String(fenceChar), count: 3)
                
                if let open = openFence {
                    // This is a closing fence
                    context.fencedCodeBlocks.append((
                        start: open.index,
                        end: i,
                        language: open.language
                    ))
                    openFence = nil
                } else {
                    // This is an opening fence - extract language
                    let afterFence = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    let language = afterFence.isEmpty ? nil : afterFence
                    openFence = (index: i, language: language)
                }
            }
        }
        
        // Handle unclosed fence (extends to end of document)
        if let open = openFence {
            context.fencedCodeBlocks.append((
                start: open.index,
                end: document.paragraphCount - 1,
                language: open.language
            ))
        }
        
        return context
    }
    
    /// Incremental update after an edit.
    /// Re-scans from the affected paragraph to the next stable point.
    func update(
        context: inout BlockContext,
        afterEditAt paragraphIndex: Int,
        in document: DocumentModel
    ) {
        // Find which blocks are affected
        let affectedBlockIndices = context.fencedCodeBlocks.indices.filter { idx in
            let block = context.fencedCodeBlocks[idx]
            return block.start >= paragraphIndex || block.end >= paragraphIndex
        }
        
        // Remove affected blocks
        for idx in affectedBlockIndices.reversed() {
            context.fencedCodeBlocks.remove(at: idx)
        }
        
        // Re-scan from the earliest affected point
        let rescanStart = affectedBlockIndices.first.map { 
            context.fencedCodeBlocks.indices.contains($0) ? context.fencedCodeBlocks[$0].start : paragraphIndex 
        } ?? paragraphIndex
        
        // Scan forward to find new block boundaries
        var openFence: (index: Int, language: String?)? = nil
        
        for i in rescanStart..<document.paragraphCount {
            guard let text = document.paragraph(at: i) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let open = openFence {
                    context.fencedCodeBlocks.append((start: open.index, end: i, language: open.language))
                    openFence = nil
                } else {
                    let afterFence = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    openFence = (index: i, language: afterFence.isEmpty ? nil : afterFence)
                }
            }
        }
        
        // Handle unclosed fence
        if let open = openFence {
            context.fencedCodeBlocks.append((start: open.index, end: document.paragraphCount - 1, language: open.language))
        }
        
        // Sort by start index
        context.fencedCodeBlocks.sort { $0.start < $1.start }
    }
}
```

#### Integration with DocumentModel

```swift
class DocumentModel {
    // ... existing properties ...
    
    /// Block-level context (fenced code blocks, etc.)
    /// Updated on load and incrementally on edits.
    private(set) var blockContext: BlockContext = BlockContext()
    private let blockScanner = BlockContextScanner()
    
    init(contentsOf url: URL) throws {
        // ... existing init code ...
        
        // Scan for block constructs after loading
        blockContext = blockScanner.scan(document: self)
    }
    
    func contentDidChange(in editedRange: NSTextRange, changeInLength delta: Int) {
        // ... existing code ...
        
        // Update block context incrementally
        if let startIndex = paragraphIndex(for: editedRange.location) {
            blockScanner.update(context: &blockContext, afterEditAt: startIndex, in: self)
        }
    }
    
    /// Get tokens for a paragraph, respecting block context.
    func tokens(forParagraphAt index: Int) -> [MarkdownToken] {
        // Check if inside a fenced code block
        let (insideCodeBlock, language) = blockContext.isInsideFencedCodeBlock(paragraphIndex: index)
        
        if insideCodeBlock {
            // Return a single "code content" token - no inline parsing
            guard let text = paragraph(at: index) else { return [] }
            return [MarkdownToken(
                element: .fencedCodeBlock(language: language),
                contentRange: 0..<text.count,
                syntaxRanges: []
            )]
        }
        
        // Check if this is a fence boundary
        if blockContext.isFenceBoundary(paragraphIndex: index) {
            guard let text = paragraph(at: index) else { return [] }
            // The entire line is syntax
            return [MarkdownToken(
                element: .fencedCodeBlock(language: nil),
                contentRange: 0..<0,
                syntaxRanges: [0..<text.count]
            )]
        }
        
        // Normal paragraph - use cached tokens or parse
        if let cached = tokenCache.tokens(forParagraph: index, revision: revision) {
            return cached
        }
        
        guard let text = paragraph(at: index) else { return [] }
        let tokens = MarkdownParser.shared.parse(text)
        tokenCache.setTokens(tokens, forParagraph: index, revision: revision)
        return tokens
    }
}
```

#### Rendering Fenced Code Blocks

`MarkdownLayoutFragment` handles code blocks specially:

```swift
// In MarkdownLayoutFragment.draw()

private func drawFormattedMarkdown(text: String, at point: CGPoint, in context: CGContext) {
    // Check for code block
    if let codeToken = tokens.first(where: { 
        if case .fencedCodeBlock = $0.element { return true }
        return false 
    }) {
        drawCodeBlockContent(text: text, token: codeToken, at: point, in: context)
        return
    }
    
    // ... existing inline formatting logic ...
}

private func drawCodeBlockContent(text: String, token: MarkdownToken, at point: CGPoint, in context: CGContext) {
    // Draw with monospace font, optional background
    let attributes = theme.codeBlockAttributes
    
    // Draw background if this is content (not a fence line)
    if !token.syntaxRanges.isEmpty && token.syntaxRanges[0] == 0..<text.count {
        // This is a fence line - draw with muted syntax color
        let attrString = NSAttributedString(string: text, attributes: theme.syntaxCharacterAttributes)
        drawAttributedString(attrString, at: point, in: context)
    } else {
        // This is code content - draw with code styling
        let attrString = NSAttributedString(string: text, attributes: attributes)
        drawAttributedString(attrString, at: point, in: context)
    }
}
```

#### Cache Invalidation for Block Edits

When an edit affects a fence boundary, tokens for all paragraphs in the affected range must be invalidated:

```swift
class MarkdownTokenCache {
    // ... existing code ...
    
    /// Invalidate tokens for a range of paragraphs.
    /// Used when block context changes affect multiple paragraphs.
    func invalidate(paragraphRange: Range<Int>) {
        for index in paragraphRange {
            entries.removeValue(forKey: index)
        }
    }
}

// In DocumentModel.contentDidChange():
func contentDidChange(in editedRange: NSTextRange, changeInLength delta: Int) {
    let previousBlockContext = blockContext
    
    // ... existing cache updates ...
    
    // Update block context
    if let startIndex = paragraphIndex(for: editedRange.location) {
        blockScanner.update(context: &blockContext, afterEditAt: startIndex, in: self)
    }
    
    // Invalidate tokens for any blocks that changed
    let changedBlocks = findChangedBlocks(previous: previousBlockContext, current: blockContext)
    for block in changedBlocks {
        tokenCache.invalidate(paragraphRange: block.start..<(block.end + 1))
        
        // Invalidate layout for all panes
        if let range = paragraphRangeForBlock(block) {
            notifyLayoutInvalidation(for: range)
        }
    }
}
```

#### Constructs Handled by Block Context

| Construct | Handled | Notes |
|-----------|---------|-------|
| Fenced code blocks (```) | ✅ Yes | Full support via BlockContext |
| Fenced code blocks (~~~) | ✅ Yes | Same mechanism |
| Indented code blocks | ❌ No | Paragraph-local (4-space prefix) |
| Block quotes spanning paragraphs | ⚠️ Partial | Each line needs `>` prefix in v1 |
| Lists with multi-paragraph items | ⚠️ Partial | Basic support only |
| HTML blocks | ❌ No | Out of scope for v1 |

#### Performance Considerations

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Initial scan | O(N) | Once on document load |
| Incremental update | O(K) | K = paragraphs from edit to next stable fence |
| isInsideFencedCodeBlock | O(B) | B = number of blocks, typically small |
| Worst case edit | O(N) | Adding ``` at line 1 re-scans everything |

For typical documents with few code blocks, incremental updates are fast. The worst case (editing a fence at the start of a large document) is rare and still acceptable.

#### Future: Other Multi-Paragraph Constructs

The `BlockContext` pattern extends to other constructs if needed:

```swift
struct BlockContext {
    var fencedCodeBlocks: [(start: Int, end: Int, language: String?)] = []
    
    // Future extensions:
    // var htmlBlocks: [(start: Int, end: Int)] = []
    // var multiParagraphListItems: [(start: Int, end: Int, depth: Int)] = []
}
```

---

### 4. Application Layer

#### `TabManager`

Manages open documents. Unchanged from original design.

```swift
class TabManager {
    private(set) var documents: [UUID: DocumentModel] = [:]
    private(set) var tabOrder: [UUID] = []
    var activeDocumentId: UUID?
    
    func openDocument(at url: URL) throws -> DocumentModel {
        if let existing = documents.values.first(where: { $0.filePath == url }) {
            return existing
        }
        
        let doc = try DocumentModel(contentsOf: url)
        documents[doc.id] = doc
        tabOrder.append(doc.id)
        return doc
    }
    
    func closeDocument(id: UUID, force: Bool = false) -> Bool {
        guard let doc = documents[id] else { return true }
        
        if doc.isDirty && !force {
            return false
        }
        
        documents.removeValue(forKey: id)
        tabOrder.removeAll { $0 == id }
        return true
    }
}
```

#### `SplitViewManager`

Manages panes. Each pane has independent layout and active paragraph state.

```swift
class SplitViewManager {
    private var panes: [UUID: PaneController] = [:]
    private var splitView: NSSplitView
    
    init(splitView: NSSplitView) {
        self.splitView = splitView
    }
    
    func createPane(for document: DocumentModel, direction: SplitDirection? = nil) -> PaneController {
        let pane = PaneController(document: document, frame: calculatePaneFrame())
        panes[pane.id] = pane
        
        if let direction = direction {
            splitView.addArrangedSubview(pane.textView)
            splitView.isVertical = (direction == .horizontal)
        }
        
        return pane
    }
    
    /// Same document can appear in multiple panes.
    /// Each pane has independent active paragraph state.
    func duplicatePane(_ paneId: UUID, direction: SplitDirection) -> PaneController? {
        guard let original = panes[paneId],
              let document = original.document else { return nil }
        
        return createPane(for: document, direction: direction)
    }
    
    func closePane(_ paneId: UUID) {
        guard let pane = panes.removeValue(forKey: paneId) else { return }
        pane.textView.removeFromSuperview()
    }
    
    private func calculatePaneFrame() -> NSRect {
        // Calculate appropriate frame based on split view layout
        return splitView.bounds
    }
}

enum SplitDirection {
    case horizontal
    case vertical
}
```

### 5. File System Layer

#### `AutoSaveController`

Debounced saving. Serializes from content storage.

```swift
class AutoSaveController {
    private let debounceInterval: TimeInterval = 1.5
    private var pendingSaves: [UUID: DispatchWorkItem] = [:]
    
    func scheduleAutoSave(for document: DocumentModel) {
        pendingSaves[document.id]?.cancel()
        
        let workItem = DispatchWorkItem { [weak document] in
            try? document?.save()
        }
        
        pendingSaves[document.id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    func documentDidChange(_ document: DocumentModel) {
        document.isDirty = true
        scheduleAutoSave(for: document)
    }
}
```

#### `FileWatcher`

Monitors workspace for external changes. Uses FSEvents for workspace, optional DispatchSource for open files.

```swift
class FileWatcher {
    private var fsEventStream: FSEventStreamRef?
    private var openFileSources: [URL: DispatchSourceFileSystemObject] = [:]
    
    var onFileChanged: ((URL) -> Void)?
    var onFileDeleted: ((URL) -> Void)?
    var onFileCreated: ((URL) -> Void)?
    
    func watchWorkspace(at root: URL) {
        // FSEvents implementation for efficient directory tree watching
        // (See full implementation in previous version)
    }
    
    func stopWatchingWorkspace() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }
    
    func watchOpenFile(at url: URL) {
        // Optional DispatchSource for immediate change detection
    }
    
    func stopWatchingOpenFile(at url: URL) {
        openFileSources[url]?.cancel()
        openFileSources.removeValue(forKey: url)
    }
}
```

---

## Data Flow

### Typing a Character

```
User types 'a'
    │
    ▼
NSTextView receives keyDown
    │
    ▼
NSTextContentStorage updates (standard text input)
    │
    ├──▶ All connected NSTextLayoutManagers notified automatically
    │         │
    │         ▼
    │    Layout managers re-layout affected paragraphs
    │         │
    │         ▼
    │    MarkdownLayoutFragment.draw() called for affected paragraphs
    │    (Each pane draws independently based on its activeParagraphIndex)
    │
    ├──▶ DocumentModel.contentDidChange()
    │         │
    │         ├──▶ Increment revision
    │         ├──▶ Update paragraphCache
    │         └──▶ Invalidate affected tokenCache entries
    │
    └──▶ AutoSaveController.documentDidChange()
              │
              ▼
         Schedule debounced save
```

**Key point:** No storage mutation for rendering. The content storage contains only the raw text. Rendering attributes are computed in `MarkdownLayoutFragment.draw()`.

### Cursor Movement (Paragraph Change)

```
User presses ↓ (moves to different paragraph)
    │
    ▼
NSTextView selection changes
    │
    ▼
NSTextViewDelegate.textViewDidChangeSelection()
    │
    ▼
PaneController.handleSelectionChange()
    │
    ├──▶ Cancel pending debounce timer
    │
    └──▶ Schedule debounced update (16ms)
              │
              ▼
         updateActiveParagraph()
              │
              ├──▶ Get cursor location
              │
              ├──▶ Calculate paragraph index
              │
              ├──▶ Compare to current activeParagraphIndex
              │         │
              │         Same ──▶ No-op (cursor still in same paragraph)
              │         │
              │         Different ──▼
              │
              ├──▶ Update activeParagraphIndex (PANE-LOCAL state)
              │
              └──▶ layoutManager.invalidateLayout() for affected paragraphs
                        │
                        ▼
                   TextKit 2 calls textLayoutManager(_:textLayoutFragmentFor:in:)
                        │
                        ▼
                   MarkdownLayoutManagerDelegate returns new MarkdownLayoutFragments
                   with updated isActiveParagraph state
                        │
                        ▼
                   Fragments draw themselves:
                   - Old active paragraph: now draws formatted (syntax hidden)
                   - New active paragraph: now draws raw (syntax visible)
```

**Key point:** No storage mutation. Only layout invalidation → redraw.

### Opening Same Document in Second Pane

```
User splits pane
    │
    ▼
SplitViewManager.duplicatePane()
    │
    ▼
Create new PaneController with same DocumentModel
    │
    ├──▶ Create new NSTextLayoutManager
    │
    ├──▶ Create new MarkdownLayoutManagerDelegate
    │         (with reference to new PaneController)
    │
    ├──▶ document.contentStorage.addTextLayoutManager(layoutManager)
    │
    └──▶ Initialize activeParagraphIndex = nil (or current cursor position)
              │
              ▼
         Two panes now show same document:
         - Shared: NSTextContentStorage (raw text)
         - Shared: MarkdownTokenCache (parsed tokens)
         - Independent: NSTextLayoutManager (layout)
         - Independent: activeParagraphIndex (cursor state)
         - Independent: MarkdownLayoutFragment rendering
```

**Key point:** Each pane can have a different active paragraph. No interference because active state is pane-local.

### External File Change

```
FileWatcher detects change
    │
    ▼
onFileChanged callback
    │
    ▼
Check: document.isDirty?
    │
    ├──▶ No (clean): Reload automatically
    │         │
    │         ▼
    │    document.contentStorage.attributedString = new content
    │         │
    │         ├──▶ Increment revision
    │         ├──▶ Clear tokenCache
    │         └──▶ Rebuild paragraphCache
    │         │
    │         ▼
    │    All layout managers automatically re-layout
    │    (TextKit 2 handles this)
    │
    └──▶ Yes (dirty): Prompt user
              │
              ├──▶ "Keep local changes"
              │         → No action
              │
              └──▶ "Reload from disk"
                        → Same as clean case
```

**Key point:** No rendering state to restore. Rendering is purely derived from content + active paragraph state.

---

## Performance Considerations

### Why Layout-Based Rendering Is Faster

| Factor | Storage-Based | Layout-Based |
|--------|---------------|--------------|
| Attribute churn | Every cursor move | Never |
| Storage invalidation | Every cursor move | Never |
| Undo bookkeeping | Every cursor move | Never |
| Cross-pane sync | Required | Not needed |
| What redraws | All storage observers | Only affected fragments |

### TextKit 2 Advantages

- **Viewport-driven layout:** Only lays out visible text + buffer
- **Fragment-level invalidation:** Re-layout only affected paragraphs
- **Native multi-view support:** Shared content storage is designed for this

### Profiling Targets

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Keystroke latency | < 16ms | Time Profiler during typing |
| Paragraph change render | < 8ms | Signpost around `invalidateLayout` + draw |
| Memory per document | < 5MB for 10K lines | Allocations instrument |
| Cold start | < 500ms | App Launch template |

### Memory Management

- `DocumentModel` owns `NSTextContentStorage` and `MarkdownTokenCache`
- `PaneController` owns `NSTextLayoutManager` — released when pane closes
- `MarkdownLayoutFragment` instances are transient — created during layout, not retained
- Token cache entries invalidated on edit — no stale data accumulation

---

## Testing Strategy

### Test Pyramid

| Layer | Test Type | Focus |
|-------|-----------|-------|
| `MarkdownParser` | Unit tests | Text → tokens, edge cases |
| `MarkdownTokenCache` | Unit tests | Invalidation logic, revision tracking |
| `MarkdownLayoutFragment` | Unit tests with mock context | Drawing logic, active vs inactive |
| `PaneController` | Integration tests | Selection → active paragraph → invalidation |
| `DocumentModel` | Unit tests | Content access, cache coordination |
| Full rendering | Visual regression | Screenshot comparison |

### Key Test Cases

**Parser tests:**
```swift
func testBoldParsing() {
    let tokens = MarkdownParser.shared.parse("This is **bold** text")
    XCTAssertEqual(tokens.count, 1)
    XCTAssertEqual(tokens[0].element, .bold)
    XCTAssertEqual(tokens[0].contentRange, 8..<12)  // "bold"
    XCTAssertEqual(tokens[0].syntaxRanges, [6..<8, 12..<14])  // "**"
}
```

**Fragment rendering tests:**
```swift
func testActiveFragmentShowsSyntax() {
    let fragment = MarkdownLayoutFragment(
        textElement: mockParagraph,
        range: mockRange,
        tokens: [boldToken],
        isActiveParagraph: true,  // Active
        theme: .default
    )
    
    let context = MockCGContext()
    fragment.draw(at: .zero, in: context)
    
    // Verify syntax characters were drawn
    XCTAssertTrue(context.drawnStrings.contains("**"))
}

func testInactiveFragmentHidesSyntax() {
    let fragment = MarkdownLayoutFragment(
        textElement: mockParagraph,
        range: mockRange,
        tokens: [boldToken],
        isActiveParagraph: false,  // Inactive
        theme: .default
    )
    
    let context = MockCGContext()
    fragment.draw(at: .zero, in: context)
    
    // Verify syntax characters were NOT drawn
    XCTAssertFalse(context.drawnStrings.contains("**"))
}
```

**Pane independence tests:**
```swift
func testPanesHaveIndependentActiveParagraph() {
    let document = DocumentModel()
    document.contentStorage.attributedString = NSAttributedString(string: "Para 1\nPara 2\nPara 3")
    
    let pane1 = PaneController(document: document, frame: .zero)
    let pane2 = PaneController(document: document, frame: .zero)
    
    // Simulate cursor in different paragraphs
    pane1.activeParagraphIndex = 0
    pane2.activeParagraphIndex = 2
    
    XCTAssertEqual(pane1.activeParagraphIndex, 0)
    XCTAssertEqual(pane2.activeParagraphIndex, 2)
    XCTAssertNotEqual(pane1.activeParagraphIndex, pane2.activeParagraphIndex)
}
```

**Block context tests:**
```swift
func testFencedCodeBlockDetection() {
    let document = DocumentModel()
    document.contentStorage.attributedString = NSAttributedString(string: """
        Line 1
        ```swift
        let x = 1
        let y = 2
        ```
        Line 6
        """)
    
    // Paragraph 0: "Line 1" - not in code block
    XCTAssertFalse(document.blockContext.isInsideFencedCodeBlock(paragraphIndex: 0).0)
    
    // Paragraph 1: "```swift" - fence boundary
    XCTAssertTrue(document.blockContext.isFenceBoundary(paragraphIndex: 1))
    
    // Paragraph 2: "let x = 1" - inside code block
    let (inside, language) = document.blockContext.isInsideFencedCodeBlock(paragraphIndex: 2)
    XCTAssertTrue(inside)
    XCTAssertEqual(language, "swift")
    
    // Paragraph 3: "let y = 2" - inside code block
    XCTAssertTrue(document.blockContext.isInsideFencedCodeBlock(paragraphIndex: 3).0)
    
    // Paragraph 4: "```" - fence boundary
    XCTAssertTrue(document.blockContext.isFenceBoundary(paragraphIndex: 4))
    
    // Paragraph 5: "Line 6" - not in code block
    XCTAssertFalse(document.blockContext.isInsideFencedCodeBlock(paragraphIndex: 5).0)
}

func testFenceInsertionInvalidatesTokens() {
    let document = DocumentModel()
    document.contentStorage.attributedString = NSAttributedString(string: "Line 1\nLine 2\nLine 3")
    
    // Initially no code blocks
    XCTAssertTrue(document.blockContext.fencedCodeBlocks.isEmpty)
    
    // Insert opening fence at line 1
    // (simulate edit that changes "Line 2" to "```")
    // ... perform edit ...
    
    // Verify block context updated
    // Verify tokens for affected lines invalidated
}

func testUnclosedFenceExtendsToEOF() {
    let document = DocumentModel()
    document.contentStorage.attributedString = NSAttributedString(string: """
        Normal text
        ```python
        code line 1
        code line 2
        """)
    
    // Unclosed fence should extend to end of document
    XCTAssertEqual(document.blockContext.fencedCodeBlocks.count, 1)
    XCTAssertEqual(document.blockContext.fencedCodeBlocks[0].start, 1)
    XCTAssertEqual(document.blockContext.fencedCodeBlocks[0].end, 3)  // Last paragraph
}
```

**Undo isolation tests:**
```swift
func testUndoContainsOnlyContentChanges() {
    let document = DocumentModel()
    document.contentStorage.attributedString = NSAttributedString(string: "Hello")
    
    // Make an edit
    document.undoManager.beginUndoGrouping()
    // ... insert text ...
    document.undoManager.endUndoGrouping()
    
    // Simulate cursor move (would trigger rendering in storage-based approach)
    let pane = PaneController(document: document, frame: .zero)
    pane.handleSelectionChange()
    
    // Undo should only undo the content change, not any "rendering"
    document.undoManager.undo()
    
    // Verify content was undone
    XCTAssertEqual(document.fullString(), "Hello")
    
    // Verify undo stack is clean (no rendering artifacts)
    XCTAssertFalse(document.undoManager.canUndo)
}
```

---

## Project Structure

```
MarkdownEditor/
├── Package.swift
├── Sources/
│   └── MarkdownEditor/
│       ├── App/
│       │   ├── AppDelegate.swift
│       │   └── MainWindowController.swift
│       ├── Document/
│       │   ├── DocumentModel.swift
│       │   ├── MarkdownTokenCache.swift
│       │   ├── ParagraphIndexCache.swift
│       │   ├── PaneController.swift
│       │   └── TabManager.swift
│       ├── Rendering/
│       │   ├── MarkdownLayoutManagerDelegate.swift
│       │   ├── MarkdownLayoutFragment.swift
│       │   └── SyntaxTheme.swift
│       ├── Parser/
│       │   ├── MarkdownParser.swift
│       │   ├── MarkdownToken.swift
│       │   ├── MarkdownElement.swift
│       │   ├── BlockContext.swift
│       │   └── BlockContextScanner.swift
│       ├── Workspace/
│       │   ├── WorkspaceManager.swift
│       │   ├── FileWatcher.swift
│       │   └── SidebarController.swift
│       ├── Views/
│       │   ├── SplitViewManager.swift
│       │   ├── TabBarView.swift
│       │   └── FileTreeOutlineView.swift
│       └── Utilities/
│           ├── AutoSaveController.swift
│           └── KeyboardShortcuts.swift
└── Tests/
    └── MarkdownEditorTests/
        ├── Parser/
        │   ├── HeadingParserTests.swift
        │   ├── EmphasisParserTests.swift
        │   ├── ListParserTests.swift
        │   ├── LinkParserTests.swift
        │   ├── BlockContextTests.swift
        │   └── EdgeCaseParserTests.swift
        ├── Rendering/
        │   ├── MarkdownLayoutFragmentTests.swift
        │   ├── CodeBlockRenderingTests.swift
        │   └── SyntaxThemeTests.swift
        ├── Document/
        │   ├── DocumentModelTests.swift
        │   ├── MarkdownTokenCacheTests.swift
        │   ├── ParagraphIndexCacheTests.swift
        │   └── PaneControllerTests.swift
        └── Integration/
            ├── MultiPaneTests.swift
            ├── FencedCodeBlockTests.swift
            └── UndoIsolationTests.swift
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Custom fragment drawing complexity | High | Medium | Start simple; iterate on edge cases |
| Selection/caret alignment with hidden syntax | Medium | High | Test thoroughly; ensure TextKit geometry is preserved |
| Parser edge cases | High | Medium | Explicit scope; parser replacement seam |
| Block context invalidation bugs | Medium | Medium | Extensive tests for fence insertion/deletion |
| CJK/RTL/emoji handling in custom draw | Medium | High | Use Core Text properly; test with diverse input |
| TextKit 2 documentation gaps | Medium | Medium | WWDC sessions; experimentation; DTS |

### Custom Drawing Risks

The `MarkdownLayoutFragment.draw()` implementation requires careful handling:

| Issue | Risk | Mitigation |
|-------|------|------------|
| Font fallback for emoji/CJK | Medium | Use Core Text font cascading |
| Baseline alignment across fonts | Medium | Calculate baselines properly per font |
| Selection highlight rendering | Low | Don't override selection drawing |
| Right-to-left text | Medium | Use Core Text's BiDi handling |
| Performance with many tokens | Low | Token parsing is per-paragraph; drawing is incremental |

### Block Context Risks

| Issue | Risk | Mitigation |
|-------|------|------------|
| Unclosed fence at EOF | Low | Handled explicitly in scanner |
| Nested fences (``` inside ```) | Medium | Not supported in CommonMark; document limitation |
| Fence edit cascades | Medium | Incremental scan limits re-parsing |
| Mixed fence styles (``` vs ~~~) | Low | Track fence character to match correctly |

---

## Milestones

### M1: Core Editor with Layout-Based Rendering (2-3 weeks)
- [ ] `DocumentModel` with `NSTextContentStorage` (no rendering attrs)
- [ ] `MarkdownTokenCache` for parsed token storage
- [ ] `ParagraphIndexCache` for O(1) lookups
- [ ] `MarkdownParser` — headings, bold, italic, inline code
- [ ] `MarkdownLayoutFragment` with custom `draw()`
- [ ] `MarkdownLayoutManagerDelegate` integration
- [ ] `PaneController` with pane-local active paragraph
- [ ] Single document open/save

### M2: Multi-Document (1-2 weeks)
- [ ] `TabManager` with document lifecycle
- [ ] Tab bar UI
- [ ] Per-document undo (content only — automatic with layout-based approach)
- [ ] Dirty state and save prompts

### M3: Split Panes (1 week)
- [ ] `SplitViewManager` with `NSSplitView`
- [ ] Same document in multiple panes
- [ ] Independent active paragraph per pane (should work by construction)
- [ ] Verify: no cross-pane interference

### M4: Workspace (1-2 weeks)
- [ ] `SidebarController` with file tree
- [ ] `WorkspaceManager` mount/unmount
- [ ] `FileWatcher` with external change handling
- [ ] Quick open (Cmd+P)

### M5: Parser Completion (1 week)
- [ ] Lists (ordered/unordered)
- [ ] Blockquotes
- [ ] Code blocks (fenced and indented)
- [ ] Links
- [ ] Horizontal rules

### M6: Polish & Hardening (1 week)
- [ ] CJK/IME testing
- [ ] Large file testing (10K+ lines)
- [ ] Visual regression tests
- [ ] Memory profiling
- [ ] Performance optimization

---

## Appendix: Why Not Storage-Based Rendering

This section documents why the previous approach (mutating `NSTextContentStorage` attributes) was rejected.

### The Storage-Based Approach

```swift
// ❌ DON'T DO THIS
func updateRendering(activeParagraph: Int) {
    contentStorage.performEditingTransaction {
        // Apply "hidden" attributes to syntax characters
        // Apply formatting attributes to content
    }
}
```

### Problems

1. **Undo Corruption**
   - `performEditingTransaction` creates undo groups
   - User types "a" → undo step
   - Cursor moves → rendering attrs change → undo step
   - User presses Undo → restores rendering state, not content
   - Must disable undo registration during rendering → fragile, race conditions

2. **Multi-Pane Interference**
   - Pane 1 cursor at paragraph 5 → storage attrs show paragraph 5 as raw
   - Pane 2 cursor at paragraph 12 → storage attrs change → paragraph 5 now formatted
   - Pane 1 sees wrong rendering
   - Must track "who owns which rendering" → complex, error-prone

3. **External Reload Complexity**
   - File changes on disk → reload content
   - Must recompute and reapply all rendering attrs
   - Must preserve active paragraph state per pane
   - Easy to get into inconsistent state

4. **IME Interference**
   - IME composition in progress
   - Cursor position changes trigger rendering
   - Rendering attrs interfere with IME attrs
   - Must carefully avoid rendering during IME → fragile

### The Layout-Based Solution

All of these problems disappear when rendering happens at the layout layer:

1. **Undo:** Storage only contains content edits. Undo is automatic.
2. **Multi-Pane:** Each pane has its own layout manager. No interference.
3. **External Reload:** Just reload content. Rendering is derived.
4. **IME:** Text input is decoupled from rendering. No interference.

This is what TextKit 2 was designed for. Use it correctly.

---

*Version: 2.0*  
*Last updated: January 2025*
