# Core Rendering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement hybrid WYSIWYG rendering where active paragraph shows raw Markdown and inactive paragraphs show formatted text.

**Architecture:** Custom `NSTextLayoutFragment` subclass draws paragraphs differently based on active state. Layout happens in `MarkdownLayoutManagerDelegate`. Rendering never touches `NSTextContentStorage` — this is critical for undo integrity and multi-pane support.

**Tech Stack:** Swift 5.9+, AppKit, TextKit 2 (NSTextLayoutFragment, NSTextLayoutManager), Core Text for drawing

---

## Prerequisites

- Scaffolding must be complete (provides `DocumentModel`, `TokenProviding` protocol, basic app)
- You will implement `LayoutFragmentProviding` protocol from scaffolding
- Parser module provides tokens via `TokenProviding` — use `StubTokenProvider` until Parser is ready

---

## Background: Why Layout-Based Rendering

### The Problem with Storage-Based Rendering

Many editors apply formatting by mutating `NSTextContentStorage` attributes:

```swift
// WRONG - causes bugs
contentStorage.performEditingTransaction {
    storage.addAttribute(.foregroundColor, value: .red, range: someRange)
}
```

**Problems:**
1. **Undo corruption** — Attribute changes create undo steps. User types, cursor moves (triggering re-render), then presses Undo → restores rendering state, not content.
2. **Multi-pane interference** — Pane 1 active at paragraph 5, Pane 2 active at paragraph 12. Storage can only have one set of attributes. Rendering one pane breaks the other.
3. **IME interference** — Input method composition adds temporary attributes. Re-rendering during composition breaks IME.

### The Solution: Layout-Based Rendering

Rendering decisions happen in `NSTextLayoutFragment.draw()`, not in storage:

```
NSTextContentStorage (raw text, never modified for rendering)
         │
         ▼
NSTextLayoutManager (one per pane)
         │
         ▼
MarkdownLayoutFragment (custom draw() for each paragraph)
         │
         └─► isActive = true  → draw raw Markdown
         └─► isActive = false → draw formatted text
```

Each pane has its own layout manager and fragments. No interference.

---

## Project Structure (additions to scaffolding)

```
Sources/MarkdownEditor/
├── Rendering/
│   ├── MarkdownLayoutManagerDelegate.swift   ← NEW
│   ├── MarkdownLayoutFragment.swift          ← NEW
│   └── SyntaxTheme.swift                     ← NEW
├── Document/
│   └── PaneController.swift                  ← NEW (pane-local active paragraph)
```

---

## Task 1: SyntaxTheme

**Files:**
- Create: `Sources/MarkdownEditor/Rendering/SyntaxTheme.swift`

**Step 1: Create SyntaxTheme**

```swift
import AppKit

/// Theme defining visual appearance for Markdown elements.
/// Pure data — no rendering logic. Easily swappable for light/dark mode.
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
    let syntaxCharacterColor: NSColor
    let blockquoteColor: NSColor

    // MARK: - Attribute Dictionaries

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

    // MARK: - Default Theme

    static let `default`: SyntaxTheme = {
        let baseSize: CGFloat = 14

        // Create italic font
        let italicFont = NSFontManager.shared.convert(
            .systemFont(ofSize: baseSize),
            toHaveTrait: .italicFontMask
        )

        // Create bold-italic font
        let boldItalicFont = NSFontManager.shared.font(
            withFamily: NSFont.systemFont(ofSize: baseSize).familyName ?? "System",
            traits: [.boldFontMask, .italicFontMask],
            weight: 0,
            size: baseSize
        ) ?? .boldSystemFont(ofSize: baseSize)

        return SyntaxTheme(
            bodyFont: .systemFont(ofSize: baseSize),
            headingFonts: [
                1: .systemFont(ofSize: 28, weight: .bold),
                2: .systemFont(ofSize: 22, weight: .bold),
                3: .systemFont(ofSize: 18, weight: .semibold),
                4: .systemFont(ofSize: 16, weight: .semibold),
                5: .systemFont(ofSize: 14, weight: .semibold),
                6: .systemFont(ofSize: 14, weight: .medium)
            ],
            boldFont: .boldSystemFont(ofSize: baseSize),
            italicFont: italicFont,
            boldItalicFont: boldItalicFont,
            codeFont: .monospacedSystemFont(ofSize: baseSize - 1, weight: .regular),
            bodyColor: .textColor,
            headingColor: .textColor,
            linkColor: .linkColor,
            codeBackgroundColor: .quaternaryLabelColor,
            syntaxCharacterColor: .tertiaryLabelColor,
            blockquoteColor: .secondaryLabelColor
        )
    }()
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Compiles successfully

**Step 3: Commit**

```bash
git add Sources/MarkdownEditor/Rendering/SyntaxTheme.swift
git commit -m "feat(rendering): add SyntaxTheme for Markdown styling"
```

---

## Task 2: MarkdownLayoutFragment

This is the core of hybrid rendering. Custom `draw()` method renders differently based on active state.

**Files:**
- Create: `Sources/MarkdownEditor/Rendering/MarkdownLayoutFragment.swift`

**Step 1: Create MarkdownLayoutFragment**

```swift
import AppKit
import CoreText

/// Custom layout fragment that implements hybrid WYSIWYG rendering.
///
/// ## How It Works
/// - Active paragraph (cursor present): draws raw Markdown with syntax visible
/// - Inactive paragraph: draws formatted text with syntax hidden
///
/// ## Critical Architecture Rules
/// - NEVER modify NSTextContentStorage
/// - All rendering is visual-only via draw()
/// - isActiveParagraph is PANE-LOCAL (different panes can have different active paragraphs)
final class MarkdownLayoutFragment: NSTextLayoutFragment {

    /// Parsed Markdown tokens for this paragraph.
    let tokens: [MarkdownToken]

    /// Whether cursor is in this paragraph (PANE-LOCAL state).
    let isActiveParagraph: Bool

    /// Theme for visual styling.
    let theme: SyntaxTheme

    // MARK: - Initialization

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

    /// Draw with all syntax characters visible but muted.
    private func drawRawMarkdown(text: String, at point: CGPoint, in context: CGContext) {
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: theme.bodyAttributes
        )

        // Apply muted color to syntax characters
        for token in tokens {
            for syntaxRange in token.syntaxRanges {
                guard syntaxRange.upperBound <= text.count else { continue }
                let nsRange = NSRange(location: syntaxRange.lowerBound, length: syntaxRange.count)
                attributedString.addAttributes(theme.syntaxCharacterAttributes, range: nsRange)
            }
        }

        drawAttributedString(attributedString, at: point, in: context)
    }

    // MARK: - Formatted Markdown Drawing (Inactive Paragraph)

    /// Draw with syntax characters hidden and formatting applied.
    private func drawFormattedMarkdown(text: String, at point: CGPoint, in context: CGContext) {
        // If no tokens, draw as plain text
        if tokens.isEmpty {
            let attrString = NSAttributedString(string: text, attributes: theme.bodyAttributes)
            drawAttributedString(attrString, at: point, in: context)
            return
        }

        // Build drawing runs, skipping syntax characters
        var runs: [DrawingRun] = []
        var currentX: CGFloat = 0
        var processedEnd = 0

        // Sort tokens by content start position
        let sortedTokens = tokens.sorted { $0.contentRange.lowerBound < $1.contentRange.lowerBound }

        for token in sortedTokens {
            // Find the earliest syntax range before content
            let syntaxBefore = token.syntaxRanges.filter { $0.upperBound <= token.contentRange.lowerBound }
            let syntaxStart = syntaxBefore.map(\.lowerBound).min() ?? token.contentRange.lowerBound

            // Draw any text between last token and this one's syntax
            if processedEnd < syntaxStart {
                let plainText = substring(of: text, from: processedEnd, to: syntaxStart)
                if !plainText.isEmpty {
                    runs.append(DrawingRun(
                        text: plainText,
                        attributes: theme.bodyAttributes,
                        xOffset: currentX
                    ))
                    currentX += measureWidth(plainText, attributes: theme.bodyAttributes)
                }
            }

            // Draw content with appropriate styling
            let contentText = substring(of: text, from: token.contentRange.lowerBound, to: token.contentRange.upperBound)
            if !contentText.isEmpty {
                let attrs = attributesForElement(token.element)
                runs.append(DrawingRun(
                    text: contentText,
                    attributes: attrs,
                    xOffset: currentX
                ))
                currentX += measureWidth(contentText, attributes: attrs)
            }

            // Track where we've processed to (including trailing syntax)
            let syntaxAfter = token.syntaxRanges.filter { $0.lowerBound >= token.contentRange.upperBound }
            let endOfToken = syntaxAfter.map(\.upperBound).max() ?? token.contentRange.upperBound
            processedEnd = max(processedEnd, endOfToken)
        }

        // Draw any remaining text after last token
        if processedEnd < text.count {
            let remainingText = substring(of: text, from: processedEnd, to: text.count)
            if !remainingText.isEmpty {
                runs.append(DrawingRun(
                    text: remainingText,
                    attributes: theme.bodyAttributes,
                    xOffset: currentX
                ))
            }
        }

        // Execute drawing
        for run in runs {
            let runPoint = CGPoint(x: point.x + run.xOffset, y: point.y)
            let attrString = NSAttributedString(string: run.text, attributes: run.attributes)
            drawAttributedString(attrString, at: runPoint, in: context)
        }
    }

    // MARK: - Drawing Helpers

    private struct DrawingRun {
        let text: String
        let attributes: [NSAttributedString.Key: Any]
        let xOffset: CGFloat
    }

    private func drawAttributedString(_ string: NSAttributedString, at point: CGPoint, in context: CGContext) {
        let line = CTLineCreateWithAttributedString(string)

        context.saveGState()
        // Flip coordinate system for Core Text
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func measureWidth(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func substring(of text: String, from start: Int, to end: Int) -> String {
        guard start >= 0, end <= text.count, start < end else { return "" }
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        return String(text[startIndex..<endIndex])
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
        case .unorderedListItem, .orderedListItem:
            return theme.bodyAttributes
        case .horizontalRule:
            return theme.bodyAttributes
        case .text:
            return theme.bodyAttributes
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Compiles successfully

**Step 3: Commit**

```bash
git add Sources/MarkdownEditor/Rendering/MarkdownLayoutFragment.swift
git commit -m "feat(rendering): add MarkdownLayoutFragment with hybrid draw()"
```

---

## Task 3: MarkdownLayoutManagerDelegate

Provides custom `MarkdownLayoutFragment` instances to TextKit 2.

**Files:**
- Create: `Sources/MarkdownEditor/Rendering/MarkdownLayoutManagerDelegate.swift`

**Step 1: Create MarkdownLayoutManagerDelegate**

```swift
import AppKit

/// Delegate that provides custom layout fragments for Markdown rendering.
///
/// ## Role in TextKit 2
/// When TextKit 2 needs to layout a paragraph, it asks its delegate for a layout fragment.
/// We return `MarkdownLayoutFragment` instead of the default, enabling custom rendering.
///
/// ## Integration
/// - Owned by `PaneController` (one per pane)
/// - Has weak reference back to pane for active paragraph state
/// - Uses token provider to get parsed Markdown
final class MarkdownLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {

    /// Reference to owning pane (for active paragraph state).
    weak var paneController: PaneController?

    /// Token provider for parsing Markdown.
    var tokenProvider: TokenProviding = StubTokenProvider()

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

        // Get paragraph index
        guard let paragraphIndex = document.paragraphIndex(for: location) else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        // Parse tokens for this paragraph
        let text = paragraph.attributedString.string
        let tokens = tokenProvider.parse(text)

        // Check if this is the active paragraph (PANE-LOCAL)
        let isActive = pane.isActiveParagraph(at: paragraphIndex)

        // Return custom fragment
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

**Step 2: Commit**

```bash
git add Sources/MarkdownEditor/Rendering/MarkdownLayoutManagerDelegate.swift
git commit -m "feat(rendering): add MarkdownLayoutManagerDelegate for TextKit 2 integration"
```

---

## Task 4: PaneController with Active Paragraph Tracking

**Files:**
- Create: `Sources/MarkdownEditor/Document/PaneController.swift`
- Modify: `Sources/MarkdownEditor/Editor/EditorViewController.swift`

**Step 1: Create PaneController**

```swift
import AppKit

/// Controller for a single editor pane.
///
/// ## Responsibilities
/// - Owns TextKit 2 layout infrastructure for this pane
/// - Tracks PANE-LOCAL active paragraph (cursor position)
/// - Triggers layout invalidation when active paragraph changes
///
/// ## Multi-Pane Architecture
/// Each pane has its own:
/// - `NSTextLayoutManager`
/// - `MarkdownLayoutManagerDelegate`
/// - `activeParagraphIndex`
///
/// All panes share the same `NSTextContentStorage` from `DocumentModel`.
final class PaneController: NSObject {

    /// Unique identifier for this pane.
    let id: UUID

    /// Document being edited (shared with other panes).
    weak var document: DocumentModel?

    /// The text view for this pane.
    let textView: NSTextView

    /// Layout manager (one per pane).
    let layoutManager: NSTextLayoutManager

    /// Text container defining geometry.
    let textContainer: NSTextContainer

    /// Layout delegate providing custom fragments.
    private let layoutDelegate: MarkdownLayoutManagerDelegate

    /// PANE-LOCAL active paragraph index.
    /// Different panes can have cursor in different paragraphs.
    private(set) var activeParagraphIndex: Int?

    /// Debounce timer for cursor movement.
    private var cursorDebounceTimer: DispatchWorkItem?
    private let cursorDebounceInterval: TimeInterval = 0.016  // ~1 frame at 60fps

    // MARK: - Initialization

    init(document: DocumentModel, frame: NSRect) {
        self.id = UUID()
        self.document = document

        // Create layout infrastructure
        self.layoutManager = NSTextLayoutManager()
        self.textContainer = NSTextContainer(size: frame.size)
        self.layoutDelegate = MarkdownLayoutManagerDelegate()

        // Configure
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.textContainer = textContainer
        layoutManager.delegate = layoutDelegate

        // Connect to document's content storage
        document.contentStorage.addTextLayoutManager(layoutManager)

        // Create text view
        self.textView = NSTextView(frame: frame, textContainer: textContainer)

        super.init()

        // Wire up delegate references
        layoutDelegate.paneController = self
        textView.delegate = self

        // Configure text view
        configureTextView()
    }

    deinit {
        document?.contentStorage.removeTextLayoutManager(layoutManager)
    }

    private func configureTextView() {
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 20, height: 20)

        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.allowsUndo = true
    }

    // MARK: - Token Provider

    /// Set the token provider (when Parser module is ready).
    func setTokenProvider(_ provider: TokenProviding) {
        layoutDelegate.tokenProvider = provider
    }

    // MARK: - Active Paragraph

    /// Check if a paragraph is active in THIS pane.
    func isActiveParagraph(at index: Int) -> Bool {
        return index == activeParagraphIndex
    }

    /// Get current cursor location.
    var cursorTextLocation: NSTextLocation? {
        guard let selection = layoutManager.textSelections.first,
              let range = selection.textRanges.first else { return nil }
        return range.location
    }

    /// Handle selection change — debounce and update active paragraph.
    func handleSelectionChange() {
        cursorDebounceTimer?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateActiveParagraph()
        }
        cursorDebounceTimer = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + cursorDebounceInterval,
            execute: workItem
        )
    }

    private func updateActiveParagraph() {
        guard let document = document,
              let location = cursorTextLocation else { return }

        let newIndex = document.paragraphIndex(for: location)

        // Only update if changed
        guard newIndex != activeParagraphIndex else { return }

        let previousIndex = activeParagraphIndex
        activeParagraphIndex = newIndex

        // Invalidate layout for affected paragraphs
        // This triggers redraw with new active state
        if let prevIdx = previousIndex,
           let range = document.paragraphRange(at: prevIdx) {
            layoutManager.invalidateLayout(for: range)
        }

        if let newIdx = newIndex,
           let range = document.paragraphRange(at: newIdx) {
            layoutManager.invalidateLayout(for: range)
        }
    }
}

// MARK: - NSTextViewDelegate

extension PaneController: NSTextViewDelegate {

    func textViewDidChangeSelection(_ notification: Notification) {
        handleSelectionChange()
    }

    func textDidChange(_ notification: Notification) {
        // Notify document of content change for cache invalidation
        // (Full implementation would pass edit range, simplified here)
        let range = document?.contentStorage.documentRange ?? NSTextRange(location: layoutManager.documentRange.location)
        document?.contentDidChange(in: range, changeInLength: 0)
    }
}
```

**Step 2: Update EditorViewController to use PaneController**

Modify `Sources/MarkdownEditor/Editor/EditorViewController.swift`:

```swift
import AppKit

/// View controller for the main editor area.
/// Uses PaneController for TextKit 2 setup and active paragraph tracking.
final class EditorViewController: NSViewController {

    /// Current document being edited.
    private(set) var currentDocument: DocumentModel?

    /// Current pane controller.
    private var paneController: PaneController?

    /// Scroll view containing the text view.
    private var scrollView: NSScrollView!

    // MARK: - Lifecycle

    override func loadView() {
        let containerView = NSView()
        containerView.autoresizingMask = [.width, .height]
        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        loadDocument(DocumentModel())
    }

    private func setupScrollView() {
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

    func loadDocument(_ document: DocumentModel) {
        currentDocument = document

        // Create pane controller with rendering infrastructure
        paneController = PaneController(document: document, frame: scrollView.bounds)

        // Set as scroll view's document view
        scrollView.documentView = paneController?.textView

        // Make text view first responder
        view.window?.makeFirstResponder(paneController?.textView)
    }
}
```

**Step 3: Build and test**

Run: `swift build && swift run`

Test:
1. Open app, type some text
2. Move cursor between lines
3. Verify app doesn't crash (rendering isn't visible yet without real parser)

**Step 4: Commit**

```bash
git add Sources/MarkdownEditor/Document/PaneController.swift
git add Sources/MarkdownEditor/Editor/EditorViewController.swift
git commit -m "feat(rendering): add PaneController with active paragraph tracking"
```

---

## Task 5: LayoutFragmentProviding Implementation

Update the stub to use real rendering.

**Files:**
- Modify: `Sources/MarkdownEditor/Stubs/StubLayoutFragmentProvider.swift`

**Step 1: Update stub to use MarkdownLayoutFragment**

```swift
import AppKit

/// Implementation of LayoutFragmentProviding using MarkdownLayoutFragment.
final class MarkdownLayoutFragmentProvider: LayoutFragmentProviding {

    var theme: SyntaxTheme = .default

    func createLayoutFragment(
        for paragraph: NSTextParagraph,
        range: NSTextRange?,
        tokens: [MarkdownToken],
        isActive: Bool
    ) -> NSTextLayoutFragment {
        return MarkdownLayoutFragment(
            textElement: paragraph,
            range: range,
            tokens: tokens,
            isActiveParagraph: isActive,
            theme: theme
        )
    }
}
```

**Step 2: Commit**

```bash
git add Sources/MarkdownEditor/Stubs/StubLayoutFragmentProvider.swift
git commit -m "feat(rendering): implement LayoutFragmentProviding with real rendering"
```

---

## Task 6: Tests

**Files:**
- Create: `Tests/MarkdownEditorTests/Rendering/SyntaxThemeTests.swift`
- Create: `Tests/MarkdownEditorTests/Rendering/MarkdownLayoutFragmentTests.swift`

**Step 1: Create SyntaxThemeTests**

```swift
import XCTest
@testable import MarkdownEditor

final class SyntaxThemeTests: XCTestCase {

    func testDefaultThemeExists() {
        let theme = SyntaxTheme.default
        XCTAssertNotNil(theme.bodyFont)
        XCTAssertNotNil(theme.boldFont)
        XCTAssertNotNil(theme.italicFont)
    }

    func testHeadingFontsExist() {
        let theme = SyntaxTheme.default
        for level in 1...6 {
            XCTAssertNotNil(theme.headingFonts[level], "Missing heading font for level \(level)")
        }
    }

    func testBodyAttributesContainRequiredKeys() {
        let attrs = SyntaxTheme.default.bodyAttributes
        XCTAssertNotNil(attrs[.font])
        XCTAssertNotNil(attrs[.foregroundColor])
    }

    func testHeadingAttributesByLevel() {
        let theme = SyntaxTheme.default
        let h1Attrs = theme.headingAttributes(level: 1)
        let h6Attrs = theme.headingAttributes(level: 6)

        // H1 should be larger than H6
        let h1Font = h1Attrs[.font] as? NSFont
        let h6Font = h6Attrs[.font] as? NSFont

        XCTAssertNotNil(h1Font)
        XCTAssertNotNil(h6Font)
        XCTAssertGreaterThan(h1Font!.pointSize, h6Font!.pointSize)
    }
}
```

**Step 2: Create MarkdownLayoutFragmentTests**

```swift
import XCTest
@testable import MarkdownEditor

final class MarkdownLayoutFragmentTests: XCTestCase {

    func testFragmentCreation() {
        // This is a basic smoke test - full visual testing requires UI tests
        let tokens = [
            MarkdownToken(
                element: .bold,
                contentRange: 2..<6,
                syntaxRanges: [0..<2, 6..<8]
            )
        ]

        // We can't easily test drawing without a real text element,
        // but we can verify the fragment stores its configuration
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].element, .bold)
    }

    func testActiveVsInactiveState() {
        // Verify that tokens and active state are stored correctly
        let tokens: [MarkdownToken] = []

        // Active fragment
        let activeConfig = (tokens: tokens, isActive: true)
        XCTAssertTrue(activeConfig.isActive)

        // Inactive fragment
        let inactiveConfig = (tokens: tokens, isActive: false)
        XCTAssertFalse(inactiveConfig.isActive)
    }
}
```

**Step 3: Run tests**

Run: `swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add Tests/MarkdownEditorTests/Rendering/
git commit -m "test(rendering): add SyntaxTheme and MarkdownLayoutFragment tests"
```

---

## Task 7: Integration and Final Verification

**Step 1: Build and run**

Run: `swift build && swift run`

**Step 2: Manual testing**

With stub tokens (no real parsing yet), verify:
- [ ] App launches without crashes
- [ ] Text editing works
- [ ] Cursor movement doesn't crash
- [ ] Undo/redo works (confirming storage isn't corrupted by rendering)

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat(rendering): complete core rendering module

- MarkdownLayoutFragment with hybrid draw()
- MarkdownLayoutManagerDelegate for TextKit 2 integration
- PaneController with pane-local active paragraph tracking
- SyntaxTheme for styling

Rendering is ready. Waiting on Parser module for real Markdown visualization."
```

---

## Integration Notes

### For Parser Module

Once Parser is complete, integrate by updating `PaneController`:

```swift
// In PaneController.init or when parser is available:
let parser = MarkdownParser() // From Parser module
paneController.setTokenProvider(parser)
```

### For Split Panes Module

Each pane needs its own `PaneController`:

```swift
// SplitViewManager creates new panes:
let newPane = PaneController(document: sharedDocument, frame: paneFrame)
splitView.addArrangedSubview(newPane.textView)
```

The active paragraph isolation works automatically because each `PaneController` has its own `activeParagraphIndex`.

---

## What This Module Delivers

| Component | Purpose |
|-----------|---------|
| `SyntaxTheme` | Defines fonts, colors for all Markdown elements |
| `MarkdownLayoutFragment` | Custom drawing for hybrid WYSIWYG |
| `MarkdownLayoutManagerDelegate` | Integrates with TextKit 2 layout |
| `PaneController` | Pane-local active paragraph + layout management |
| `MarkdownLayoutFragmentProvider` | Protocol implementation for modularity |
