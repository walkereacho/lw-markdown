---
name: md-comments
description: Use when reviewing feedback on a plan, or when asked to read comments from a markdown document
---

# Reading Markdown Comments

Read comments left on a markdown document in MarkdownEditor.

## Comment File Location

Comments are stored in a sidecar JSON file alongside the markdown file:

- Markdown: `docs/plans/2026-01-20-feature-design.md`
- Comments: `docs/plans/2026-01-20-feature-design.comments.json`

## File Structure

```json
{
  "comments": [
    {
      "id": "UUID",
      "anchorText": "the selected text this comment is attached to",
      "content": "the comment itself",
      "isResolved": false,
      "isCollapsed": false,
      "createdAt": "ISO8601 timestamp"
    }
  ],
  "version": 1
}
```

## What To Do

1. Identify the plan file you're working with
2. Read the corresponding `.comments.json` sidecar file
3. Present the contents to interpret the feedback
