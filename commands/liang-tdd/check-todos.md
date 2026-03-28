---
name: liang-tdd:check-todos
description: List pending todos and select one to work on
argument-hint:
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
  - Glob
  - Grep
  - Skill
---

<objective>
List all pending todos, allow selection, and route to action: edit, delete, or
promote to a /liang-tdd:add-mission.
</objective>

<execution_context>
@$HOME/.claude/liang-tdd/workflows/todo-ops.md
</execution_context>

<context>
Arguments: $ARGUMENTS (unused, reserved for future filtering)
</context>

<process>
**Follow the check-todos section** from `@$HOME/.claude/liang-tdd/workflows/todo-ops.md`.

The workflow handles:
1. Scanning .planning/vibe/todos/pending/ for todo files
2. Listing with title and age
3. Interactive selection
4. Full context display
5. Action routing (edit, delete, promote to mission)
6. Git commits for state changes
</process>
