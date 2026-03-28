# Debug Schema

Schema for DEBUG.md — structured diagnosis produced by the `liang-tdd-debugger`
agent after QA failure. Consumed by the re-planner to create a better plan.

One DEBUG.md per task, overwritten on each iteration (previous diagnosis is
superseded by the new one since the codebase changed).

```markdown
# Debug: {task_id} (Iteration {N})

**Status:** {diagnosed | inconclusive}
**Date:** {YYYY-MM-DD}
**Failed tests:** {count}/{total}

## Symptoms

| Test | Expected | Actual | Error |
|------|----------|--------|-------|
| test-{NN}-{name} | {expected behavior} | {actual behavior} | {error message} |

## Hypotheses Tested

### 1. {Hypothesis title}
- **Theory:** {what might be wrong}
- **Check:** {what command/file was examined}
- **Evidence:** {what was found}
- **Verdict:** CONFIRMED | ELIMINATED

### 2. {Hypothesis title}
...

## Diagnosis

### Root Cause
{Clear statement — or "Inconclusive: could not determine root cause from
available evidence. Web research recommended."}

### Affected Tests
- test-{NN}-{name}: {how root cause causes this specific failure}

### Recommended Fix Direction
{High-level guidance for the re-planner}

### Decision Alignment
{Does implementation match DECISIONS.md choices? Flag drift if any.}
```

## How Downstream Agents Use This

- **Planner (re-plan):** Reads DEBUG.md to understand WHY tests failed, not
  just THAT they failed. Uses the diagnosis to avoid repeating the same mistake.
  The "Recommended Fix Direction" guides the new plan's GREEN steps.

- **Research agent (iteration 2+):** If DEBUG.md status is "inconclusive",
  the orchestrator triggers web research focused on the symptoms and
  eliminated hypotheses — avoiding searches for already-ruled-out theories.
