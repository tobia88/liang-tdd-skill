# Plan Schema

Schema for PLAN.md — the execution plan created by the Planner in Phase 3.

```markdown
# Plan: {NN}-{slug}

**Version:** {N}
**Date:** {YYYY-MM-DD}
{If re-plan: **Previous version:** PLAN-v{N-1}.md}
{If re-plan: **QA failures addressed:** {list of failed tests}}

## Overview

{One paragraph: what this task does and why}

## Skills to Load

- `.claude/skills/{skill-name}/SKILL.md` — {reason}

## Test Cycle Steps

### Cycle 1: {test-name}

**RED — Write test:**
- Create `tests/test-01-{name}.sh` with content:
  {exact script content}
- Run: `bash tests/test-01-{name}.sh` -> expect FAILURE
- Snapshot: `cp tests/test-01-{name}.sh tests/.snapshots/RED-test-01-{name}.sh`

**GREEN — Implement:**
- {exact changes to make}
- Run: `bash tests/test-01-{name}.sh` -> expect SUCCESS
- Regression: run all previous tests

**BLUE — Refactor (optional):**
- {cleanup if needed}
- Re-run all tests

### Cycle 2: {test-name}
...

## Final Self-Check

Run all tests before committing:

| # | Test Script | Expected |
|---|-------------|----------|
| 1 | `test-01-{name}.sh` | Exit 0 |
| 2 | `test-02-{name}.sh` | Exit 0 |
```
