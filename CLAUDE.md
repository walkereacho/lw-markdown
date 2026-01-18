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
- **Workspace/** - `WorkspaceManager` (file tree), `FileWatcher` (FSEvents), `QuickOpenController`

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
| **Bullets** | Show `* ` as typed | Transform to `•` glyph (future) |
| **Blockquotes** | Show `>` muted | Visual treatment (future) |
| **Code blocks** | Syntax visible | Syntax highlighting (future) |

**Key implementation details:**
- Storage has element-specific fonts (headings) → TextKit 2 calculates correct cursor metrics
- Custom `draw()` methods handle visual presentation:
  - `drawActiveHeading()` - syntax visible but muted
  - `drawInactiveHeading()` - syntax hidden, content only
- Heading detection triggers immediately after `# ` (space), not waiting for content
- `NSTextParagraph.attributedString.string` includes trailing newline; must trim before parsing

## Test Fixtures

Test fixtures in `Tests/Fixtures/` cover headings, lists, code blocks, blockquotes, inline formatting, and edge cases (empty files, long lines, deep nesting).

## CLI Arguments (E2E Testing)

- `--test-file <path>` - Load markdown file on startup
- `--window-size WxH` - Set window size (e.g., "1200x800")
- `--cursor-line N` - Position cursor at line N
