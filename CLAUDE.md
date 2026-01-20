# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MarkdownEditor is a native macOS Markdown editor built with Swift and AppKit. It implements a hybrid WYSIWYG approach where active paragraphs show raw Markdown syntax while inactive paragraphs display formatted text. Built on TextKit 2 (macOS 13+).

## Build and Test Commands

```bash
# Build
swift build

# Run tests
swift test

# Run single test
swift test --filter MarkdownEditorTests.HeadingParserTests

# Run the app
swift run MarkdownEditor

# Run with test file (E2E testing)
.build/debug/MarkdownEditor --test-file Tests/Fixtures/headings.md --window-size 1200x800

# Screenshot testing
./scripts/screenshot-test.sh Tests/Fixtures/comprehensive.md 1200x800
./scripts/screenshot-obsidian.sh Tests/Fixtures/comprehensive.md
```

## Architecture

### Core Rendering Pipeline

The editor uses a **layout-based** (not storage-based) rendering architecture:

```
NSTextContentStorage (raw markdown, unmodified)
        ↓
MarkdownTokenCache (parsed tokens)
        ↓
Per-Pane TextKit 2 Infrastructure:
├── NSTextLayoutManager
├── MarkdownLayoutManagerDelegate (factory)
└── MarkdownLayoutFragment (custom rendering)
```

**Key principle:** Active paragraph state is pane-local. Each editor pane independently tracks which paragraph is "active" (showing raw syntax vs formatted).

### Module Organization

- **Document/** - `DocumentModel` (content/undo), `PaneController` (TextKit 2 layout), `ParagraphIndexCache` (O(log N) lookup)
- **Parser/** - `MarkdownParser` (lexical analysis), `BlockContext`/`BlockContextScanner` (stateful block parsing)
- **Rendering/** - `MarkdownLayoutFragment` (custom drawing), `MarkdownLayoutManagerDelegate` (fragment factory), `SyntaxTheme`
- **Tabs/** - `TabManager` (document lifecycle), `TabBarView`/`TabView` (UI)
- **Workspace/** - `WorkspaceManager` (file tree), `FileWatcher` (FSEvents), `SidebarController`

### Protocols

Five core protocols enable dependency injection and testability:

1. **TokenProviding** - Parser interface: `text → [MarkdownToken]`
2. **LayoutFragmentProviding** - Creates `NSTextLayoutFragment` instances
3. **TabManaging** - Document/tab lifecycle
4. **WorkspaceProviding** - File tree and watching
5. **PaneManaging** - Split pane interface

### MarkdownToken Structure

```swift
struct MarkdownToken {
    let element: MarkdownElement    // Type (heading, bold, etc.)
    let contentRange: Range<Int>    // What to display
    let syntaxRanges: [Range<Int>]  // What to hide when formatted
    let nestingDepth: Int           // For nested elements
}
```

### Rendering Flow

1. User edits text → `NSTextContentStorage` updated
2. `PaneController.applyHeadingFontsToStorage()` applies heading fonts to storage for correct cursor metrics
3. Layout requested → `MarkdownLayoutManagerDelegate` parses tokens (strips trailing newlines first)
4. `MarkdownLayoutFragment` created with tokens and pane reference
5. Fragment `draw()` checks `isActiveParagraph` at draw time and renders accordingly

### Active Paragraph Switching

When cursor moves between paragraphs:
1. `textViewDidChangeSelection` → `updateActiveParagraph()`
2. TextKit 2 caches fragments aggressively, so we force recreation by detaching/reattaching the text container
3. `textView.display()` forces immediate redraw

### Rendering Drivers (Element-Specific Rendering)

Each markdown element type has different rendering needs handled by dedicated methods in `MarkdownLayoutFragment`:

| Element | Active (cursor present) | Inactive |
|---------|------------------------|----------|
| **Headings** | Show `#` muted, heading font | Hide `#`, heading font |
| **Bold/Italic** | Formatted text + muted `*` | Formatted text, `*` hidden |
| **Inline code** | Code font + muted `` ` `` + background | Code font + background, `` ` `` hidden |
| **Bullets** | Show `- ` muted | Show `•` glyph |
| **Blockquotes** | Show `>` muted, italic font | Hide `>`, italic font + bar |
| **Code blocks** | Syntax highlighted (same as inactive) | Syntax highlighted |
| **Fence lines** | Show ```` ``` ```` muted | Hide ```` ``` ```` |

**Key implementation details:**
- Storage has element-specific fonts → TextKit 2 calculates correct cursor metrics
- Custom `draw()` methods handle visual presentation
- Inline formatting renders live in active paragraphs (not just when inactive)
- Code block content is consistent regardless of cursor position
- `NSTextParagraph.attributedString.string` includes trailing newline; must trim before parsing

## Cursor Positioning & Font Management

**Critical Rule:** TextKit 2 calculates cursor position from font attributes in `NSTextStorage`, NOT from custom `draw()` rendering. Storage fonts must match rendering fonts exactly.

### Font Application Timing

Apply fonts in `textStorage(_:willProcessEditing:...)` BEFORE TextKit 2 creates layout fragments:

```swift
// In DocumentModel - NSTextStorageDelegate
func textStorage(_ textStorage: NSTextStorage, willProcessEditing...) {
    // Detect paragraph type (heading, code block, blockquote, list)
    // Apply appropriate font to storage
    // This ensures correct cursor metrics from the start
}
```

### Syntax Character Rendering

When showing syntax characters (`*`, `>`, `-`, `` ` ``) in active paragraphs:
- **Only change COLOR**, not font
- Changing font causes cursor mismatch (storage has content font, rendering has different font)

```swift
// WRONG - causes cursor offset
attributedString.addAttributes(theme.syntaxCharacterAttributes, range: nsRange)

// CORRECT - only change color
attributedString.addAttribute(.foregroundColor, value: theme.syntaxCharacterColor, range: nsRange)
```

### Document Load Initialization

Fonts must be applied to ALL paragraphs on document load, not just when edited:

1. Build `BlockContext` FIRST (to detect code blocks)
2. Then apply fonts based on paragraph type
3. Order matters: block context → fonts → layout

```swift
private func initializeAfterContentLoad() {
    updateBlockContextFull()      // 1. Detect code blocks
    applyFontsToAllParagraphs()   // 2. Apply fonts
    // ... rest of init
}
```

### Code Block Rendering

- Content lines render the SAME regardless of active/inactive state
- Only fence lines (```` ``` ````) change based on cursor position
- When using Highlightr, override its font with `theme.codeFont` to match storage

```swift
let mutableHighlighted = NSMutableAttributedString(attributedString: highlighted)
mutableHighlighted.addAttribute(.font, value: theme.codeFont,
    range: NSRange(location: 0, length: mutableHighlighted.length))
```

### Inline Code Backgrounds

Draw backgrounds manually for full line height (attributed string `.backgroundColor` only covers text height):

```swift
// Draw rounded rect background BEFORE drawing text
let bgRect = CGRect(x: point.x + xOffset, y: point.y, width: codeWidth, height: lineHeight)
let path = CGPath(roundedRect: bgRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
context.addPath(path)
context.fillPath()
```

### Live Inline Formatting

Active paragraphs show formatted text (bold, italic) WITH syntax visible:
- Apply formatting attributes to content ranges
- Apply muted color to syntax ranges
- Keeps visual feedback while editing

## Test Fixtures

Test fixtures in `Tests/Fixtures/` cover headings, lists, code blocks, blockquotes, inline formatting, and edge cases (empty files, long lines, deep nesting).

## CLI Arguments (E2E Testing)

- `--test-file <path>` - Load markdown file on startup
- `--window-size WxH` - Set window size (e.g., "1200x800")
- `--cursor-line N` - Position cursor at line N
