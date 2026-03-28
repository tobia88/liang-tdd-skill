# Progress Schema

Schema for PROGRESS.md — tracks mission state across sessions.

```markdown
# Progress Tracker

**Started:** {YYYY-MM-DD}
**Last updated:** {YYYY-MM-DD HH:MM}
**Current phase:** {1-5}

## Task Status

| Task | Status | Iterations | Tests Passing | Parallel Group | Notes |
|------|--------|------------|---------------|----------------|-------|
| {NN}-{slug} | {pending|in_progress|passed|failed} | {N} | {M}/{total} | {N} | {notes} |

## Phase History

- {YYYY-MM-DD HH:MM} — Phase 1 complete (BRAINSTORM.md saved)
- {YYYY-MM-DD HH:MM} — Phase 2 complete ({N} tasks created, {M} total tests)
- {YYYY-MM-DD HH:MM} — Task 01-foo: PASS (iteration 1, 5/5 tests green)
- {YYYY-MM-DD HH:MM} — Task 02-bar: QA FAIL (iteration 1, 3/5 tests + 1 tamper)
- {YYYY-MM-DD HH:MM} — Task 02-bar: QA FAIL (iteration 2), researching online
- {YYYY-MM-DD HH:MM} — Task 02-bar: PASS (iteration 3, 5/5 tests green)

## Current State

**Next action:** {what to do next when resuming}
**Blocked by:** {nothing | description of blocker}
```
