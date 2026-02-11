#!/bin/bash
# Generate performance test fixture files with realistic markdown content mix.
# Usage: ./scripts/generate-perf-fixtures.sh

set -euo pipefail

FIXTURE_DIR="$(dirname "$0")/../Tests/Fixtures"

generate_fixture() {
    local target_lines=$1
    local output_file="$FIXTURE_DIR/perf-${target_lines}.md"
    local line=0

    echo "Generating $output_file ($target_lines lines)..."

    > "$output_file"

    while [ $line -lt $target_lines ]; do
        local section=$((RANDOM % 10))

        case $section in
            0|1)
                # Heading + paragraph section (~8 lines)
                local level=$(( (RANDOM % 3) + 1 ))
                local hashes=$(printf '#%.0s' $(seq 1 $level))
                echo "" >> "$output_file"
                echo "$hashes Section heading at line $line" >> "$output_file"
                echo "" >> "$output_file"
                echo "This is a regular paragraph with some text content. It contains **bold text** and *italic text* and some \`inline code\` for good measure. This line is intentionally longer to test wrapping behavior in the editor window." >> "$output_file"
                echo "" >> "$output_file"
                echo "Another paragraph follows with a [link](https://example.com) and more ***bold italic*** formatting mixed in with regular text content." >> "$output_file"
                echo "" >> "$output_file"
                line=$((line + 7))
                ;;
            2|3)
                # Unordered list section (~6 lines)
                echo "" >> "$output_file"
                echo "- First item in the list with **bold** content" >> "$output_file"
                echo "- Second item with \`inline code\` here" >> "$output_file"
                echo "- Third item with *italic* text" >> "$output_file"
                echo "  - Nested item under third" >> "$output_file"
                echo "  - Another nested item" >> "$output_file"
                echo "" >> "$output_file"
                line=$((line + 7))
                ;;
            4)
                # Ordered list section (~5 lines)
                echo "" >> "$output_file"
                echo "1. First ordered item" >> "$output_file"
                echo "2. Second ordered item with **emphasis**" >> "$output_file"
                echo "3. Third ordered item" >> "$output_file"
                echo "" >> "$output_file"
                line=$((line + 5))
                ;;
            5|6)
                # Code block section (~8 lines)
                local langs=("swift" "python" "javascript" "rust" "go")
                local lang=${langs[$((RANDOM % ${#langs[@]}))]}
                echo "" >> "$output_file"
                echo "\`\`\`$lang" >> "$output_file"
                echo "func example$line() {" >> "$output_file"
                echo "    let value = computeResult(input: $line)" >> "$output_file"
                echo "    guard value > 0 else { return }" >> "$output_file"
                echo "    print(\"Result: \\(value)\")" >> "$output_file"
                echo "}" >> "$output_file"
                echo "\`\`\`" >> "$output_file"
                echo "" >> "$output_file"
                line=$((line + 9))
                ;;
            7)
                # Blockquote section (~4 lines)
                echo "" >> "$output_file"
                echo "> This is a blockquote with some important information." >> "$output_file"
                echo "> It spans multiple lines and contains **bold** text." >> "$output_file"
                echo "> > And a nested blockquote for depth." >> "$output_file"
                echo "" >> "$output_file"
                line=$((line + 5))
                ;;
            8)
                # Horizontal rule + text (~4 lines)
                echo "" >> "$output_file"
                echo "---" >> "$output_file"
                echo "" >> "$output_file"
                echo "Text after a horizontal rule with \`code\` and **bold** and *italic*." >> "$output_file"
                line=$((line + 4))
                ;;
            9)
                # Plain paragraphs (~4 lines)
                echo "" >> "$output_file"
                echo "A plain text paragraph at line $line. This tests the most common case — body text with no special markdown syntax, just flowing prose that might wrap across multiple lines depending on the window width." >> "$output_file"
                echo "" >> "$output_file"
                echo "A second paragraph with mixed \`code spans\`, **bold words**, and *italic phrases* to exercise inline token parsing." >> "$output_file"
                line=$((line + 4))
                ;;
        esac
    done

    local actual_lines=$(wc -l < "$output_file" | tr -d ' ')
    echo "  -> Generated $actual_lines lines ($(wc -c < "$output_file" | tr -d ' ') bytes)"
}

generate_fixture 500
generate_fixture 2000
generate_fixture 5000

echo "Done. Files in $FIXTURE_DIR/"
