---
name: liang-tdd:add-mission
description: Create a new TDD mission and start brainstorming
argument-hint: [--research] [--skip-discuss] <topic>
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
Create a new mission directory under `.planning/vibe/` and immediately begin
the Brainstormer phase (Phase 1) of the solo TDD workflow.
</objective>

<execution_context>
@$HOME/.claude/liang-tdd/workflows/core.md
@$HOME/.claude/liang-tdd/workflows/mission-ops.md
</execution_context>

<context>
Arguments: $ARGUMENTS (may include flags + mission topic)
</context>

<process>
1. Parse $ARGUMENTS for flags:
   - If `--research` is present: set research=true, remove flag from arguments
   - If `--skip-discuss` is present: set skip_discuss=true, remove flag from arguments
   - Remaining text = mission topic
2. Read `mission-ops.md` § Creating a Mission
3. Scan `.planning/vibe/` for existing missions to determine the next index
4. Slugify the topic
5. Create the mission directory
6. Proceed to Phase 1 (Brainstormer) from `core.md`:
   - Brainstormer runs INLINE in the main session (not as a subagent)
   - Step 0.5: Ask user their confidence threshold via AskUserQuestion (soft gate)
   - Brainstormer never auto-stops — asks user whether to stop when threshold is reached
7. After Phase 1 completes, proceed to Phase 1.5 (Discuss) unless skip_discuss=true
8. After Discuss (or skip), continue through the full workflow (Phases 2-5)
   following core.md, respecting context clearing gates
</process>
