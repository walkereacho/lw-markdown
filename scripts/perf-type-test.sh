#!/bin/bash
# Run typing performance harness across fixture sizes to expose O(N) scaling.
# Usage: ./scripts/perf-type-test.sh [--type-count N]
#
# Builds the app, then runs --perf-type-test against perf-500, perf-2000, perf-5000.
# Results are printed to stderr and appended to /tmp/markdowneditor-perf.log.

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="$PROJECT_DIR/Tests/Fixtures"

TYPE_COUNT="${1:-50}"

echo "=== Typing Performance Test ==="
echo "Type count: $TYPE_COUNT chars per scenario"
echo ""

# Build first
echo "Building..."
cd "$PROJECT_DIR"
swift build 2>&1 | tail -1
echo ""

BINARY="$PROJECT_DIR/.build/debug/MarkdownEditor"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

for SIZE in 500 2000 5000; do
    FIXTURE="$FIXTURE_DIR/perf-${SIZE}.md"
    if [ ! -f "$FIXTURE" ]; then
        echo "SKIP: $FIXTURE not found (run scripts/generate-perf-fixtures.sh)"
        continue
    fi

    LINES=$(wc -l < "$FIXTURE" | tr -d ' ')
    echo "--- perf-${SIZE}.md ($LINES lines) ---"

    "$BINARY" \
        --test-file "$FIXTURE" \
        --window-size 1200x800 \
        --perf-type-test \
        --type-count "$TYPE_COUNT" \
        2>&1 | grep '\[PERF\]' || true

    echo ""
done

echo "=== Done. Full log at /tmp/markdowneditor-perf.log ==="
