# Artifact Schemas

Markdown schemas for all mission artifacts. Each section shows the exact
structure agents should produce.

`{mission_dir}` = `.planning/vibe/{NNN}-{slug}/` (e.g., `.planning/vibe/001-receipt-scanner/`)

---

## BRAINSTORM.md

```markdown
# Brainstorm: {Task Title}

**Date:** {YYYY-MM-DD}
**Confidence:** {N}/10
**Confidence Justification:** {Why this rating}

## Summary

{2-3 paragraph summary of what the user wants to accomplish}

## Task Breakdown

### {Piece 1 Name}
- **What:** {description}
- **Done when:** {success criteria in plain language}
- **Dependencies:** {none | list of pieces this depends on}

### {Piece 2 Name}
...

## Parallelism Analysis

- **Can run in parallel:** {list of piece combinations}
- **Must be sequential:** {list with reasons}

## Edge Cases & Constraints

- {constraint or edge case 1}
- {constraint or edge case 2}

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| {decision} | {choice} | {why} |

## Research Findings

{Summary of upfront research conducted before brainstorming. Include:}

### Discovered Options
| Category | Option | Notes |
|----------|--------|-------|
| {e.g., Library} | {name} | {stars, trade-offs, why recommended or not} |

### Recommendations Adopted
- {recommendation that was presented to user and accepted, with rationale}

### Recommendations Declined
- {recommendation that was presented but user chose differently, with their reasoning}

## Open Questions (Resolved)

| Question | Answer |
|----------|--------|
| {question asked during brainstorm} | {user's answer} |
```

---

## RESEARCH-BRAINSTORM.md

Created by the research agent before Socratic questioning begins. Consumed by
the brainstormer to inform AskUserQuestion options throughout Phase 1.

```markdown
# Research: {Topic}

**Date:** {YYYY-MM-DD}
**Search queries:** {list of queries used}

## Libraries & Tools

| Name | Stars/Popularity | Pros | Cons | Link |
|------|-----------------|------|------|------|
| {name} | {metric} | {pros} | {cons} | {url} |

## Recommended Patterns

- **{Pattern name}**: {description, when to use, trade-offs}

## Common Pitfalls

- {pitfall 1}: {why it happens, how to avoid}

## Alternative Approaches

| Approach | Complexity | Best For |
|----------|-----------|----------|
| {approach} | {low/med/high} | {use case} |

## Sources

- {url 1} — {what was learned}
- {url 2} — {what was learned}
```

---

## TASKS.md

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

---

## TEST_LIST.md

Replaces the old DESIRED_OUTCOME.md. This is the TDD golden standard — an
ordered list of behaviors to test ONE AT A TIME in vertical-slice TDD cycles.

```markdown
# Test List: {NN}-{slug}

**Goal:** {One sentence describing what this task accomplishes}

## Tests (ordered, simplest → most complex)

### Test 01: {test-name}
**Behavior:** {What specific behavior this test verifies}
**Script:**
#!/bin/bash
set -e
{test commands that exit 0 on success, non-zero on failure}

### Test 02: {test-name}
**Behavior:** {description}
**Script:**
#!/bin/bash
set -e
{test commands}

### Test 03: {test-name}
...

## Expected Changes

| File | Action |
|------|--------|
| {path} | create |
| {path} | modify |
```

### Test Script Guidelines

- Scripts MUST `set -e` for fail-fast behavior
- Scripts MUST exit 0 on success, non-zero on failure
- Scripts test OUTCOMES, not implementation details
- Scripts are language-agnostic — they verify results via:
  - File existence checks: `[ -f path ]`
  - Content pattern matching: `grep -q 'pattern' file`
  - Command output comparison: `[ "$(command)" = "expected" ]`
  - Build/compile verification: `build_command && echo PASS`
  - Data validation: `awk`, `wc -l`, `head`, `diff`
- Order matters: earlier tests verify foundational behaviors

### Test Script Examples

**CSV data validation:**
```bash
#!/bin/bash
set -e
expected="date,description,amount,category"
actual=$(head -1 data/2025/expenses.csv)
[ "$expected" = "$actual" ]
```

**File structure check:**
```bash
#!/bin/bash
set -e
[ -f Source/MyGame/MyComponent.h ]
grep -q 'class.*UMyComponent' Source/MyGame/MyComponent.h
```

**Command output validation:**
```bash
#!/bin/bash
set -e
output=$(python3 scripts/calculate.py --year 2025)
echo "$output" | grep -q 'Total: MYR'
```

**Build verification:**
```bash
#!/bin/bash
set -e
npm run build 2>&1
```

---

## Test File Structure

```
{mission_dir}/tasks/{NN}-{slug}/
├── TEST_LIST.md              — ordered test behaviors (the TDD spec)
├── PLAN.md                   — execution plan for vertical-slice cycles
├── QA_REPORT.md              — verification results
├── tests/
│   ├── test-01-{name}.sh     — individual test scripts
│   ├── test-02-{name}.sh
│   ├── test-03-{name}.sh
│   └── .snapshots/           — RED phase snapshots for tamper detection
│       ├── RED-test-01-{name}.sh
│       ├── RED-test-02-{name}.sh
│       └── RED-test-03-{name}.sh
└── RESEARCH-{N}.md           — (created on 2nd+ QA failure)
```

---

## PLAN.md

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
- Run: `bash tests/test-01-{name}.sh` → expect FAILURE
- Snapshot: `cp tests/test-01-{name}.sh tests/.snapshots/RED-test-01-{name}.sh`

**GREEN — Implement:**
- {exact changes to make}
- Run: `bash tests/test-01-{name}.sh` → expect SUCCESS
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

---

## QA_REPORT.md

```markdown
# QA Report: {NN}-{slug}

**Version:** {N}
**Date:** {YYYY-MM-DD}
**Overall: {PASS | FAIL}**

## Test Results

| # | Test Script | Result | Evidence |
|---|-------------|--------|----------|
| 1 | `test-01-{name}.sh` | {PASS|FAIL} | {exit code, output} |

## Tamper Detection

| # | Test Script | Snapshot | Tampered? | Details |
|---|-------------|----------|-----------|---------|
| 1 | `test-01-{name}.sh` | `RED-test-01-{name}.sh` | {YES|NO} | {diff details if tampered} |

## Coverage

| Test from TEST_LIST.md | Script Found? |
|------------------------|---------------|
| {test-name} | {YES|NO} |

## Failed Items Detail

{Only present if overall is FAIL}

### {Item type}: {description}
- **Expected:** {what should have been true}
- **Actual:** {what was found}
- **Evidence:** {command output, file contents, diff output}
- **Suggested fix:** {if obvious}
```

---

## RESEARCH-{iteration}.md

Created when a task fails QA for the 2nd+ time. Contains online research
findings to help the planner create a better re-plan.

```markdown
# Research: {NN}-{slug} (Iteration {N})

**Date:** {YYYY-MM-DD}
**Triggered by:** QA failure iteration {N}
**Failed tests:** {list of failed test summaries}

## Search Queries

- {query 1} — {what was found}
- {query 2} — {what was found}

## Findings

### Finding 1: {Title}
- **Source:** {URL or reference}
- **Relevance:** {how this relates to the failed tests}
- **Key insight:** {the actionable takeaway}

### Finding 2: ...

## Recommended Approach

{Summary of how these findings should change the execution plan}

## Skill Suggestion

{Only present if research reveals a reusable skill gap}

**Gap:** {description of the missing skill}
**Suggested `/example-skills:skill-creator` prompt:**
> {prompt text that can be copy-pasted to create the skill}
```

---

## PROGRESS.md

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

---

## FINAL_REPORT.md

```markdown
# /liang-tdd Run Complete

**Date:** {YYYY-MM-DD}
**Duration:** {approximate}
**Tasks:** {passed}/{total} passed

## Results

| Task | Status | Iterations | Tests | Notes |
|------|--------|------------|-------|-------|
| {NN}-{slug} | {PASS|FAIL} | {N} | {M}/{total} | {notes} |

## TDD Discipline

| Metric | Value |
|--------|-------|
| Total test scripts written | {N} |
| Tamper violations detected | {N} |
| Tests that passed on first GREEN | {N}/{total} |
| Regressions caught | {N} |

## Skill Suggestions

{List any skill suggestions from RESEARCH files, with /example-skills:skill-creator prompts.
If none: "No skill gaps identified."}

## Retrospective

- {Analysis of tasks that needed multiple iterations}
- {Skill gaps that caused friction}
- {TDD discipline observations}
- {Recommendations for future runs}
```
