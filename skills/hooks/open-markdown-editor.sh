#!/bin/bash

# Claude Code PostToolUse hook: Opens markdown files in MarkdownEditor
# Triggers on Write|Edit operations for .md files

# Configure path to MarkdownEditor binary
# Set MARKDOWN_EDITOR_PATH env var, or edit this default:
MARKDOWN_EDITOR="${MARKDOWN_EDITOR_PATH:-$HOME/Desktop/code/Markdown/.build/debug/MarkdownEditor}"

# Read hook input (JSON from Claude Code)
hook_input=$(cat)

# Extract file path
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // empty')

# Skip if no file path
[[ -z "$file_path" ]] && exit 0

# Skip if not markdown
[[ "$file_path" != *.md ]] && exit 0

# Skip test fixtures (noise)
[[ "$file_path" == */Tests/Fixtures/* ]] && exit 0

# Skip if MarkdownEditor not found
[[ ! -x "$MARKDOWN_EDITOR" ]] && exit 0

# Open with MarkdownEditor (fully detached so hook returns immediately)
# Must redirect stdin/stdout/stderr AND disown to prevent Claude Code from waiting
nohup "$MARKDOWN_EDITOR" --test-file "$file_path" </dev/null >/dev/null 2>&1 &
disown

exit 0
