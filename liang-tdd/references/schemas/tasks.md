# Tasks Schema

Schema for TASKS.md — the task index created by the Task Manager in Phase 2.

```markdown
# Task List

**Generated:** {YYYY-MM-DD}
**Total tasks:** {N}
**Parallel groups:** {N}

## Tasks

### {NN}-{slug}
- **Goal:** {one sentence}
- **Parallel group:** {N}
- **Dependencies:** {none | list of task IDs}
- **Tests:** {number of tests in TEST_LIST.md}
- **Expected changes:** {list of files}
- **Status:** pending

### {NN}-{slug}
...

## Dependency Graph

{Text-based visualization of task dependencies}

## Parallel Groups

| Group | Tasks | Can Start After |
|-------|-------|-----------------|
| 1 | 01-foo, 02-bar | — |
| 2 | 03-baz | Group 1 complete |
```
