# E2E Screenshot Testing Harness Design

## Overview

A screenshot-based testing harness for interactive debugging of the WYSIWYG markdown editor. Enables a Claude-in-the-loop workflow: make code changes → capture screenshot → critique against Obsidian reference → iterate.

## Components

### 1. CLI Argument Support

Add to `AppDelegate.applicationDidFinishLaunching`:

```swift
// Check for --test-file argument
if let testFileIndex = CommandLine.arguments.firstIndex(of: "--test-file"),
   testFileIndex + 1 < CommandLine.arguments.count {
    let filePath = CommandLine.arguments[testFileIndex + 1]
    let url = URL(fileURLWithPath: filePath)
    mainWindowController.openFile(at: url)
}

// Check for --window-size argument (e.g., "1200x800")
if let sizeIndex = CommandLine.arguments.firstIndex(of: "--window-size"),
   sizeIndex + 1 < CommandLine.arguments.count {
    let sizeStr = CommandLine.arguments[sizeIndex + 1]
    let parts = sizeStr.split(separator: "x")
    if parts.count == 2,
       let width = Int(parts[0]),
       let height = Int(parts[1]) {
        mainWindowController.window?.setContentSize(NSSize(width: width, height: height))
    }
}

// Check for --cursor-line argument
if let lineIndex = CommandLine.arguments.firstIndex(of: "--cursor-line"),
   lineIndex + 1 < CommandLine.arguments.count,
   let line = Int(CommandLine.arguments[lineIndex + 1]) {
    // Position cursor at specified line (implementation in MainWindowController)
    mainWindowController.setCursorLine(line)
}
```

### 2. Test Fixtures

Directory: `Tests/Fixtures/`

| File | Content |
|------|---------|
| `inline-formatting.md` | Bold, italic, bold-italic, code, links |
| `headings.md` | H1 through H6 with body text |
| `blockquotes.md` | Single and nested blockquotes |
| `code-blocks.md` | Fenced code blocks with language hints |
| `lists-unordered.md` | Bullet lists, nested |
| `lists-ordered.md` | Numbered lists, nested |
| `lists-mixed.md` | Combination of ordered/unordered |
| `horizontal-rules.md` | Various HR syntaxes |
| `edge-empty.md` | Empty/minimal content |
| `edge-long-lines.md` | Very long paragraphs |
| `edge-deep-nesting.md` | Deeply nested lists/quotes |
| `comprehensive.md` | Kitchen sink for quick smoke test |

### 3. Test Runner Script

File: `scripts/screenshot-test.sh`

```bash
#!/bin/bash
set -e

FIXTURE="${1:-Tests/Fixtures/comprehensive.md}"
WINDOW_SIZE="${2:-1200x800}"
OUTPUT_DIR="docs/screenshots/test-runs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FIXTURE_NAME=$(basename "$FIXTURE" .md)
OUTPUT_FILE="$OUTPUT_DIR/${FIXTURE_NAME}-${TIMESTAMP}.jpg"

# Build the app
echo "Building..."
swift build -q

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Launch app with test file
echo "Launching with $FIXTURE..."
.build/debug/MarkdownEditor \
    --test-file "$FIXTURE" \
    --window-size "$WINDOW_SIZE" &

APP_PID=$!

# Wait for window to render
sleep 2

# Find window ID for MarkdownEditor
WINDOW_ID=$(swift -e '
import CoreGraphics
let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
    for window in windowList {
        if let owner = window["kCGWindowOwnerName"] as? String,
           owner.contains("MarkdownEditor"),
           let windowID = window["kCGWindowNumber"] as? Int {
            print(windowID)
            break
        }
    }
}
' 2>/dev/null)

if [ -z "$WINDOW_ID" ]; then
    echo "Error: Could not find MarkdownEditor window"
    kill $APP_PID 2>/dev/null || true
    exit 1
fi

# Capture screenshot
echo "Capturing window $WINDOW_ID..."
screencapture -x -l "$WINDOW_ID" /tmp/sc.png

# Compress for efficient reading
sips -Z 1024 -s format jpeg -s formatOptions 60 /tmp/sc.png --out "$OUTPUT_FILE" 2>/dev/null
rm /tmp/sc.png

# Cleanup app
kill $APP_PID 2>/dev/null || true

echo "Screenshot saved: $OUTPUT_FILE"
```

### 4. Obsidian Reference Script

File: `scripts/screenshot-obsidian.sh`

```bash
#!/bin/bash
set -e

FIXTURE="${1:-Tests/Fixtures/comprehensive.md}"
FIXTURE_NAME=$(basename "$FIXTURE" .md)
OUTPUT="docs/references/obsidian/${FIXTURE_NAME}.jpg"

mkdir -p docs/references/obsidian

open -a Obsidian "$FIXTURE"
sleep 2

WINDOW_ID=$(swift -e '
import CoreGraphics
if let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] {
    for w in list where (w["kCGWindowOwnerName"] as? String)?.contains("Obsidian") == true {
        if let id = w["kCGWindowNumber"] as? Int { print(id); break }
    }
}
' 2>/dev/null)

if [ -z "$WINDOW_ID" ]; then
    echo "Error: Could not find Obsidian window"
    exit 1
fi

screencapture -x -l "$WINDOW_ID" /tmp/sc.png
sips -Z 1024 -s format jpeg -s formatOptions 60 /tmp/sc.png --out "$OUTPUT" 2>/dev/null
rm /tmp/sc.png

echo "Saved: $OUTPUT"
```

### 5. Directory Structure

```
docs/
├── references/
│   └── obsidian/              # Reference screenshots from Obsidian
│       ├── headings.jpg
│       ├── inline-formatting.jpg
│       └── ...
└── screenshots/
    └── test-runs/             # Output from screenshot-test.sh
        └── headings-20260117-143022.jpg

scripts/
├── screenshot-test.sh         # Capture MarkdownEditor
└── screenshot-obsidian.sh     # Capture Obsidian reference

Tests/
└── Fixtures/
    ├── headings.md
    ├── inline-formatting.md
    └── ...
```

### 6. Critique Checklist

Used by subagent when analyzing screenshots:

```markdown
## Rendering Correctness
- [ ] Headings are visually distinct (H1 largest → H6 smallest)
- [ ] Bold text appears bold
- [ ] Italic text appears italic
- [ ] Code spans have monospace font and distinct background
- [ ] Links are visually identifiable
- [ ] Blockquotes have visible indentation/styling
- [ ] Lists show proper bullets/numbers and indentation

## Active/Inactive Behavior
- [ ] Active paragraph (with cursor) shows raw markdown syntax
- [ ] Inactive paragraphs hide syntax characters (**, *, `, etc.)
- [ ] Transition between states is clean (no visual glitches)

## Visual Polish
- [ ] Consistent spacing between elements
- [ ] Text alignment is correct (no unexpected shifts)
- [ ] Font sizes are proportional and readable
- [ ] Colors have good contrast
- [ ] No clipping or overflow issues

## Compared to Obsidian
- [ ] Overall visual quality comparable to Obsidian
- [ ] Specific gaps: [list any areas where Obsidian is better]
```

## Claude Workflow

1. Make code changes to rendering/layout
2. Run: `./scripts/screenshot-test.sh Tests/Fixtures/headings.md`
3. Read the output screenshot with Read tool
4. Spawn critique subagent with screenshot, checklist, and Obsidian reference
5. Based on critique, iterate or move to next fixture

## Reference Capture Workflow

One-time setup per fixture:

```bash
./scripts/screenshot-obsidian.sh Tests/Fixtures/headings.md
# Repeat for each fixture file
```

## Implementation Order

1. Add CLI argument parsing to AppDelegate
2. Create test fixture markdown files
3. Create scripts directory and shell scripts
4. Create directory structure for screenshots
5. Capture Obsidian references for each fixture
