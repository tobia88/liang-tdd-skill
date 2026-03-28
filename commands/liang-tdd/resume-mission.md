---
name: liang-tdd:resume-mission
description: Resume a TDD mission by index number
argument-hint: [--auto] [--research] [--skip-discuss] [mission-number]
allowed-tools:
  - Read
  - Write
  - Bash
  - Agent
  - AskUserQuestion
  - Glob
  - Grep
  - WebSearch
  - WebFetch
---

<objective>
Resume an existing mission, picking up from where it left off. If no mission
number is given, auto-detect the latest incomplete mission (or prompt to choose).
</objective>

<execution_context>
@$HOME/.claude/liang-tdd/workflows/core.md
@$HOME/.claude/liang-tdd/workflows/mission-ops.md
</execution_context>

<context>
Arguments: $ARGUMENTS (may include --auto, --research, --skip-discuss flags + optional mission number)
</context>

<process>
1. Parse $ARGUMENTS for flags:
   - If `--auto` is present: set auto=true, remove flag from arguments
   - If `--research` is present: set research=true, remove flag from arguments
   - If `--skip-discuss` is present: set skip_discuss=true, remove flag from arguments
   - Remaining text = mission number (optional)
2. If mission number is given:
   - Read `mission-ops.md` § Resuming a Mission by Index
   - Find the mission directory matching the index in `.planning/vibe/`
3. If NO mission number is given:
   - Read `mission-ops.md` § Auto-Detect
   - Scan for incomplete missions, auto-select or ask user
4. Read the mission's `PROGRESS.md` to determine current state
5. Follow `core.md` § Phase 0: Resume Detection to continue from the next
   incomplete step
6. Apply flags to relevant phases:
   - --auto: Task Manager (Phase 2) auto-accepts all tasks without AskUserQuestion
   - --research: Brainstormer (Phase 1) runs upfront research before questioning
   - --skip-discuss: Skip Phase 1.5 (architecture discussion)
7. Continue through the remaining workflow phases, respecting context clearing gates
</process>
