# Comment Sidebar Design

A right-hand sidebar for adding review comments to markdown documents.

## Overview

**Use case**: Review/editing workflow with resolvable comments (like Word/Google Docs).

**Key behaviors**:
- Select text, hit ⌥⌘M to add a comment
- Comments anchor to the exact selected text
- Sidebar auto-shows when document has comments
- Comments persist in a sidecar JSON file

## Data Model

```swift
struct Comment: Codable, Identifiable {
    let id: UUID
    var anchorText: String      // The exact text that was selected
    var content: String         // The comment itself
    var isResolved: Bool        // Checkbox state
    var isCollapsed: Bool       // Individual collapse state
    let createdAt: Date
}

struct CommentStore: Codable {
    var comments: [Comment]
    var version: Int = 1        // For future migrations
}
```

**Anchor matching**: Search for `anchorText` in document string. First occurrence wins if multiple matches.

## Persistence

- **Location**: `/path/to/doc.md` → `/path/to/doc.comments.json`
- **Save**: Debounced 500ms after any comment change
- **Load**: When document opens, check for companion JSON
- **Cleanup**: Delete JSON file when last comment is removed
- **Untitled docs**: Comments held in memory until document is saved
- **External changes**: Reload on external modification, external version wins

## UI Structure

### Window Layout

```
NSSplitView (horizontal)
├── SidebarController (left, 220px) — existing file tree
├── EditorArea (center, flexible)
│   ├── TabBarView
│   └── EditorViewController
└── CommentSidebarController (right, 280px) — new
```

### Sidebar Layout

```
┌─────────────────────────┐
│ Comments (3)        [×] │  ← Header with count + close button
├─────────────────────────┤
│ ┌─────────────────────┐ │
│ │ ☐ "the quick brown" │ │  ← Checkbox + anchor snippet
│ │   Needs citation    │ │  ← Comment content
│ │   for this claim... │ │
│ └─────────────────────┘ │
│ ┌─────────────────────┐ │
│ │ ☐ "performance"     │ │
│ │   Can we add        │ │
│ │   benchmarks?       │ │
│ └─────────────────────┘ │
├─────────────────────────┤
│ ▶ Resolved (2)          │  ← Collapsed section
└─────────────────────────┘
```

### Interactions

- **Click comment card** → scroll editor to anchor, briefly highlight
- **Checkbox** → toggle resolved, animate to/from resolved section
- **Disclosure triangle** → collapse to anchor snippet only

## Adding a Comment (⌥⌘M)

1. Validate: If no selection, show toast "Select text to comment on"
2. Capture `anchorText` from selection
3. Open sidebar if hidden (slide from right, ~200ms)
4. Add new comment card at top in edit mode, text field focused
5. Enter saves, Escape cancels, click-outside saves if content exists
6. Briefly highlight anchor text in editor (~300ms) to confirm link

## Orphaned Comments

When anchor text is deleted from document:
1. Detect on text edit (debounced ~300ms)
2. Show toast: "Comment removed: anchor text was deleted"
3. Delete comment from store
4. Save updated store

## Sidebar Visibility

- **Auto-show**: Opens when document with comments is loaded
- **Toggle**: ⌥⌘M with no selection, or close button, or menu item
- **Resize**: Min 200px, max constrained by window/left sidebar
- **Width**: Remembered per session

## Menu Integration

```
Edit
├── ...existing items...
├── ─────────────
├── Add Comment           ⌥⌘M
└── Toggle Comment Sidebar
```

## Theme Integration

Use existing `ThemeManager`:
- Background: `colors.sidebarBackground`
- Comment cards: slightly elevated
- Anchor text: `colors.syntaxCharacter` (muted)
- Resolved comments: reduced opacity
