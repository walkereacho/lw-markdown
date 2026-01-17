#!/bin/bash
set -e

# Obsidian Reference Screenshot Capture
# Usage: ./scripts/screenshot-obsidian.sh [fixture-file]
# Example: ./scripts/screenshot-obsidian.sh Tests/Fixtures/headings.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

FIXTURE="${1:-Tests/Fixtures/comprehensive.md}"
FIXTURE_NAME=$(basename "$FIXTURE" .md)
OUTPUT="docs/references/obsidian/${FIXTURE_NAME}.jpg"

mkdir -p docs/references/obsidian

# Get absolute path for Obsidian
ABSOLUTE_FIXTURE="$(cd "$(dirname "$FIXTURE")" && pwd)/$(basename "$FIXTURE")"

echo "Opening $ABSOLUTE_FIXTURE in Obsidian..."
open -a Obsidian "$ABSOLUTE_FIXTURE"
sleep 2

# Find window ID for Obsidian
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
    echo "Make sure Obsidian is running and visible"
    exit 1
fi

# Capture screenshot
echo "Capturing Obsidian window $WINDOW_ID..."
screencapture -x -l "$WINDOW_ID" /tmp/sc.png

# Compress for efficient reading
sips -Z 1024 -s format jpeg -s formatOptions 60 /tmp/sc.png --out "$OUTPUT" 2>/dev/null
rm /tmp/sc.png

echo "Saved: $OUTPUT"
