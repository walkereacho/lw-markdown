# MarkdownEditor

A macOS Markdown editor built with Swift, AppKit, and TextKit 2. It uses a hybrid approach where the paragraph you're editing shows raw Markdown syntax and the rest show formatted text — similar to how Typora or iA Writer handle things, but simpler.

This is a personal project. It works for basic editing but isn't trying to compete with established editors. It's primarily an exercise in building a custom text editor on top of TextKit 2, which has its own set of challenges.

Requires macOS 13 (Ventura) or later.

## What it does

- Headings, bold, italic, inline code, code blocks, lists, blockquotes
- Syntax highlighting in code blocks via [Highlightr](https://github.com/raspu/Highlightr)
- Workspace sidebar with file tree
- Tabs for multiple documents
- File watching (sidebar updates when files change on disk)
- Inline comments with a toggleable sidebar — comments are anchored to text and persisted in `.comments.json` files alongside your documents

## What it doesn't do (yet, or maybe ever)

- No export to HTML/PDF
- No vim mode, no plugin system
- Markdown coverage is incomplete — no tables, no footnotes, no task lists
- Undo can be flaky in edge cases
- Large files haven't been stress-tested much

## Requirements

- macOS 13.0 (Ventura) or later
- Swift 5.9 or later
- Xcode 15+ (for development)

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/walkereacho/lw-markdown.git
cd lw-markdown

# Build
swift build

# Run
swift run MarkdownEditor
```

### Build for Release

```bash
swift build -c release
```

The binary will be at `.build/release/MarkdownEditor`.

## Usage

### Running the App

```bash
# Run directly
swift run MarkdownEditor

# Or run the built binary
.build/debug/MarkdownEditor
```

### Opening Files

- **File > Open** (`Cmd+O`) - Open a single Markdown file
- Drag and drop `.md` files onto the window

### Opening a Workspace

A workspace is a folder containing Markdown files. When opened, the sidebar shows the file tree.

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Document | `Cmd+N` |
| Open File | `Cmd+O` |
| Save | `Cmd+S` |
| Save As | `Cmd+Shift+S` |
| Add Comment | `Cmd+Option+M` |
| Undo | `Cmd+Z` |
| Redo | `Cmd+Shift+Z` |
| Quit | `Cmd+Q` |

## How it works

The raw Markdown stays unmodified in `NSTextContentStorage`. A parser tokenizes each paragraph, and custom `NSTextLayoutFragment` subclasses handle rendering. The paragraph under the cursor shows syntax characters (like `#`, `*`, `` ` ``) with muted styling; everything else hides the syntax and shows formatted text.

Most of the complexity lives in keeping cursor positioning correct — TextKit 2 calculates cursor position from font attributes in storage, not from what you draw, so the two have to stay in sync.

## Testing

### Run All Tests

```bash
swift test
```

### Run Specific Tests

```bash
swift test --filter MarkdownEditorTests.HeadingParserTests
```

### E2E / Screenshot Testing

The app supports CLI arguments for automated testing:

```bash
# Open a test file with specific window size
.build/debug/MarkdownEditor --test-file Tests/Fixtures/comprehensive.md --window-size 1200x800

# Position cursor at a specific line
.build/debug/MarkdownEditor --test-file Tests/Fixtures/headings.md --cursor-line 5
```

#### CLI Arguments

| Argument | Description | Example |
|----------|-------------|---------|
| `--test-file <path>` | Load a Markdown file on startup | `--test-file Tests/Fixtures/headings.md` |
| `--window-size <WxH>` | Set window dimensions | `--window-size 1200x800` |
| `--cursor-line <N>` | Position cursor at line N | `--cursor-line 10` |
| `--perf-scroll-test` | Run automated scroll profiling | |
| `--perf-type-test` | Run automated typing profiling | |
| `--type-count <N>` | Character count for typing test | `--type-count 500` |

Performance results are logged to `/tmp/markdowneditor-perf.log`.

### Test Fixtures

Test fixtures are located in `Tests/Fixtures/` and cover various Markdown scenarios:

- `headings.md` - All heading levels
- `lists-unordered.md` - Bullet lists
- `lists-ordered.md` - Numbered lists
- `lists-mixed.md` - Nested and mixed lists
- `code-blocks.md` - Fenced code blocks with syntax highlighting
- `blockquotes.md` - Blockquotes and nested quotes
- `inline-formatting.md` - Bold, italic, inline code
- `comprehensive.md` - Mixed content for full coverage
- `edge-*.md` - Edge cases (empty files, long lines, deep nesting)

## Project Structure

```
Sources/MarkdownEditor/
├── App/                    # Application entry point and window management
│   ├── AppDelegate.swift
│   └── MainWindowController.swift
├── Document/               # Document model and text infrastructure
│   ├── DocumentModel.swift      # Content, undo/redo, NSTextStorage
│   ├── PaneController.swift     # TextKit 2 layout per editor pane
│   └── ParagraphIndexCache.swift
├── Parser/                 # Markdown parsing
│   ├── MarkdownParser.swift     # Lexical analysis → tokens
│   ├── BlockContext.swift       # Stateful block tracking
│   └── BlockContextScanner.swift
├── Rendering/              # Custom TextKit 2 rendering
│   ├── MarkdownLayoutFragment.swift   # Custom drawing
│   ├── MarkdownLayoutManagerDelegate.swift
│   ├── SyntaxTheme.swift        # Colors and fonts
│   └── SyntaxHighlighter.swift  # Code block highlighting
├── Tabs/                   # Tab bar and document tabs
│   ├── TabManager.swift
│   ├── TabBarView.swift
│   └── TabView.swift
├── Theme/                  # Theming system
│   ├── DesignSystem.swift
│   ├── ThemeManager.swift
│   └── MoodyTheme.swift
├── Workspace/              # File tree and workspace management
│   ├── WorkspaceManager.swift
│   ├── SidebarController.swift
│   └── FileWatcher.swift
├── Protocols/              # Core interfaces
└── Stubs/                  # Test doubles
```

## License

[Add your license here]
