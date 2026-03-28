---
name: liang-tdd:add-todo
description: Capture idea or task as todo from current conversation context
argument-hint: [optional description]
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
  - Glob
  - Grep
---

<objective>
Capture an idea, task, or future mission that surfaces during a TDD session as a
structured todo for later work. Enables "thought → capture → continue" flow.
</objective>

<execution_context>
@$HOME/.claude/liang-tdd/workflows/todo-ops.md
</execution_context>

<context>
Arguments: $ARGUMENTS (optional todo description)
</context>

<process>
**Follow the add-todo section** from `@$HOME/.claude/liang-tdd/workflows/todo-ops.md`.

The workflow handles:
1. Directory creation (.planning/vibe/todos/pending/)
2. Content extraction (from arguments or conversation)
3. Duplicate checking
4. Todo file creation with frontmatter
5. Git commit
6. Confirmation
</process>
