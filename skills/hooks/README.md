# MarkdownEditor Hooks for Claude Code

## Setup

Add this to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/open-markdown-editor.sh"
          }
        ]
      }
    ]
  }
}
```

Then copy the hook script:

```bash
mkdir -p ~/.claude/hooks
cp skills/hooks/open-markdown-editor.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/open-markdown-editor.sh
```

Optionally set the path to your MarkdownEditor binary:

```bash
export MARKDOWN_EDITOR_PATH="/path/to/MarkdownEditor"
```

Or edit the default path in the script directly.

## What It Does

When Claude writes or edits a `.md` file, the hook automatically opens it in MarkdownEditor. This enables a workflow where:

1. Claude writes a plan to `docs/plans/YYYY-MM-DD-topic.md`
2. Hook opens it in MarkdownEditor
3. You review and add comments (⌥⌘M)
4. Use `/md-comments` to have Claude read your feedback
