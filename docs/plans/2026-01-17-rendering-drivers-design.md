# Rendering Drivers Implementation Design

## Overview

Build out all rendering drivers for the MarkdownEditor hybrid WYSIWYG system. Each driver handles a specific markdown element type, implementing both active (syntax visible) and inactive (syntax hidden) rendering states.

## Agent Architecture

6 sequential agents, each working in the main repo on a dedicated feature branch (one at a time):

| Agent | Branch | Obsidian Ref | Fixture |
|-------|--------|--------------|---------|
| Blockquotes | `feature/blockquotes-driver` | `blockquotes.png` | `blockquotes.md` |
| Code Blocks | `feature/code-blocks-driver` | `code-blocks.png` | `code-blocks.md` |
| Horizontal Rules | `feature/horizontal-rules-driver` | `horizontal-rules.png` | `horizontal-rules.md` |
| Inline Formatting | `feature/inline-formatting-driver` | `inline-formatting.png` | `inline-formatting.md` |
| Lists Unordered | `feature/lists-unordered-driver` | `lists-unordered.png` | `lists-unordered.md` |
| Lists Ordered | `feature/lists-ordered-driver` | `lists-ordered.png` | `lists-ordered.md` |

**Validation:** Lists-Mixed (`lists-mixed.md`) tests integration of both list drivers after completion.

## Agent Workflow

```
┌─────────────────────────────────────────────────────────┐
│                    Driver Agent                          │
├─────────────────────────────────────────────────────────┤
│  1. Read Obsidian reference(s)                          │
│     └── docs/references/obsidian/<feature>.png          │
│                                                          │
│  2. Read existing code                                   │
│     └── MarkdownLayoutFragment.swift                    │
│     └── SyntaxTheme.swift                               │
│     └── Parser (if tokens need work)                    │
│                                                          │
│  3. Write implementation plan                           │
│     └── Plan active/inactive rendering methods          │
│     └── Identify theme additions needed                 │
│                                                          │
│  4. Implement driver                                    │
│     └── Add draw methods to MarkdownLayoutFragment      │
│     └── Update attributesForElement() routing           │
│                                                          │
│  5. Take screenshot (markdown-editor-screenshot-testing)│
│     └── Uses Tests/Fixtures/<feature>.md                │
│                                                          │
│  6. Spawn Review Sub-Agent                              │
│     └── Compare Obsidian vs new screenshot              │
│     └── Score 1-10 on structural criteria               │
│                                                          │
│  7. If score < 8 and iterations < 5: Ralph Loop         │
│     If score >= 8 OR iterations = 5: Commit and done    │
└─────────────────────────────────────────────────────────┘
```

## Scoring Rubric

Review sub-agents score on structural criteria (10 points total):

| Criterion | Points | What to Check |
|-----------|--------|---------------|
| Element renders correctly | 4 | Element type is visually distinguishable and properly formatted |
| Syntax hidden when inactive | 2 | Raw markdown characters not visible in inactive paragraphs |
| Indentation/nesting correct | 2 | Nested elements indent properly, hierarchy is clear |
| No visual glitches | 2 | No clipping, overlapping, or rendering artifacts |

**Pass threshold:** Score >= 8

**Acceptable differences (don't penalize):**
- Font family/size variations
- Exact color differences
- Pixel-level spacing variations
- Window chrome/UI differences

## Orchestration Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     Main Orchestrator                            │
├─────────────────────────────────────────────────────────────────┤
│  For each driver in sequence:                                    │
│                                                                  │
│  1. Create feature branch from main                             │
│     └── git checkout -b feature/{driver}-driver                 │
│                                                                  │
│  2. Launch agent for this driver                                │
│     └── Agent implements driver in main repo                    │
│     └── Agent uses Ralph Loop (max 5 iterations)                │
│     └── Agent commits when score >= 8 or iterations = 5         │
│                                                                  │
│  3. Wait for agent to complete                                  │
│     └── Record final score and status                           │
│     └── Merge branch to main if score >= 8                      │
│                                                                  │
│  4. Return to main branch for next driver                       │
│     └── git checkout main                                       │
│                                                                  │
│  After all 6 drivers complete:                                   │
│                                                                  │
│  5. Run Lists-Mixed validation                                  │
│     └── Screenshot test with lists-mixed.md                     │
│     └── Review sub-agent scores the integration                 │
│                                                                  │
│  6. Report results                                              │
│     └── Per-driver: final score, iterations used, status        │
│     └── Lists-Mixed integration score                           │
└─────────────────────────────────────────────────────────────────┘
```

## Execution Order

1. **Horizontal Rules** - Simplest, single-line element
2. **Inline Formatting** - Enhances existing drawFormattedMarkdown()
3. **Blockquotes** - Block-level with visual indicator
4. **Code Blocks** - Block-level with background
5. **Lists Unordered** - Line-level with bullet transformation
6. **Lists Ordered** - Line-level with number alignment

## Agent Prompt Template

```
You are implementing the {DRIVER_NAME} rendering driver for MarkdownEditor.

## Your Branch
- Branch: feature/{driver-name}-driver
- Location: /Users/walkereacho/Desktop/code/Markdown (main repo)

## Reference Materials
1. Obsidian screenshot: docs/references/obsidian/{feature}.png
   {If multi-page: also read {feature}-page-two.png}
2. Test fixture: Tests/Fixtures/{feature}.md
3. Existing code: Sources/MarkdownEditor/Rendering/MarkdownLayoutFragment.swift

## Your Task
1. Read the Obsidian reference screenshot(s) - understand the target rendering
2. Read the existing MarkdownLayoutFragment.swift - understand the pattern
3. Plan your implementation (active + inactive rendering methods)
4. Implement the driver following the heading driver pattern
5. Use markdown-editor-screenshot-testing skill to capture your result
6. Spawn a review sub-agent to compare screenshots and score (rubric provided)
7. If score < 8 and iterations < 5: use Ralph Loop to iterate
8. If score >= 8 OR iterations = 5: commit your work and report final score

## Scoring Rubric (provide to review sub-agent)
- Element renders correctly (4 pts)
- Syntax hidden when inactive (2 pts)
- Indentation/nesting correct (2 pts)
- No visual glitches (2 pts)
Pass threshold: 8/10
```

## Deliverables

**Per-Agent:**
- Implementation in `MarkdownLayoutFragment.swift` (draw methods)
- Any theme additions in `SyntaxTheme.swift` (if needed)
- Committed to feature branch with descriptive message
- Final score report (score, iterations used)

**Orchestrator:**
- Summary report with all 6 driver scores
- Lists-Mixed integration test score
- List of branches ready for merge
- Any agents that didn't reach score >= 8 flagged for manual review

## Success Criteria

- All 6 drivers score >= 8 (or flagged after 5 attempts)
- Lists-Mixed integration test passes (score >= 8)
- All feature branches cleanly mergeable to main
