---
name: liang-tdd:add-mission
description: Create a new TDD mission and start brainstorming
argument-hint: [--no-limit] <topic>
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
@$HOME/.claude/liang-tdd/workflows/mission-ops.md
@$HOME/.claude/liang-tdd/workflows/core.md
@$HOME/.claude/liang-tdd/references/agent-prompts.md
@$HOME/.claude/liang-tdd/references/artifact-schemas.md
</execution_context>

<context>
Arguments: $ARGUMENTS (may include --no-limit flag + mission topic)
</context>

<process>
1. Parse $ARGUMENTS for flags:
   - If `--no-limit` is present: set no_limit=true, remove flag from arguments
   - Remaining text = mission topic
2. Read `mission-ops.md` § Creating a Mission
3. Scan `.planning/vibe/` for existing missions to determine the next index
4. Slugify the topic
5. Create the mission directory
6. Proceed to Phase 1 (Brainstormer) from `core.md`:
   - Brainstormer runs INLINE in the main session (not as a subagent)
   - If no_limit=true: disable the 8/10 confidence gate, keep asking until user says stop
   - If no_limit=false: normal 8/10 confidence gate
7. After Phase 1 completes, continue through the full workflow (Phases 2-5)
   following core.md, respecting context clearing gates
</process>
