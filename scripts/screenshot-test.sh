#!/bin/bash
set -e

# E2E Screenshot Test Runner
# Usage: ./scripts/screenshot-test.sh [fixture-file] [window-size]
# Example: ./scripts/screenshot-test.sh Tests/Fixtures/headings.md 1200x800

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

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
