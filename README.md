# MarkdownEditor

A native macOS Markdown editor built with Swift and AppKit. Features a hybrid WYSIWYG approach where the active paragraph shows raw Markdown syntax while inactive paragraphs display beautifully formatted text.

Built on TextKit 2, requiring macOS 13 (Ventura) or later.

## Features

- **Hybrid WYSIWYG Editing** - Edit in raw Markdown when focused, see formatted output elsewhere
- **Full Markdown Support** - Headings, bold, italic, inline code, code blocks, lists, blockquotes, and more
- **Syntax Highlighting** - Code blocks with language-aware syntax highlighting via [Highlightr](https://github.com/raspu/Highlightr)
- **Workspace Support** - Open folders as workspaces with a file tree sidebar
- **Quick Open** - Fast file navigation with `Cmd+P`
- **Tabs** - Work with multiple documents simultaneously
- **File Watching** - Sidebar updates automatically when files change on disk
- **Native Performance** - Pure AppKit, no Electron, no web views

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
- **File > Quick Open** (`Cmd+P`) - Fuzzy search files in the current workspace
- Drag and drop `.md` files onto the window

### Opening a Workspace

A workspace is a folder containing Markdown files. When opened, the sidebar shows the file tree and enables Quick Open across all files.

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Document | `Cmd+N` |
| Open File | `Cmd+O` |
| Quick Open | `Cmd+P` |
| Save | `Cmd+S` |
| Save As | `Cmd+Shift+S` |
| Undo | `Cmd+Z` |
| Redo | `Cmd+Shift+Z` |
| Quit | `Cmd+Q` |

## How It Works

MarkdownEditor uses a **layout-based rendering architecture**:

1. Raw Markdown text is stored unmodified in `NSTextContentStorage`
2. The parser tokenizes each paragraph into `MarkdownToken` elements
3. Each editor pane tracks which paragraph is "active" (cursor present)
4. Custom `NSTextLayoutFragment` subclasses render:
   - **Active paragraphs**: Show syntax characters (like `#`, `*`, `` ` ``) with muted styling
   - **Inactive paragraphs**: Hide syntax, show formatted text

This gives you the best of both worlds: see exactly what you're typing while editing, but enjoy clean formatted output everywhere else.

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
│   ├── FileWatcher.swift
│   └── QuickOpenController.swift
├── Protocols/              # Core interfaces
└── Stubs/                  # Test doubles
```

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

[Add your license here]
