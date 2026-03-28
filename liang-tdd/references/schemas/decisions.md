# Decisions Schema

Schema for DECISIONS.md — architecture decisions captured during Phase 1.5 (Discuss).
Consumed by the Task Manager (Phase 2) and Planner (Phase 3) to write better
TEST_LISTs and execution plans.

```markdown
# Architecture Decisions

**Date:** {YYYY-MM-DD}
**Mission:** {NNN}-{slug}
**Areas discussed:** {N}

## Decisions

### D-01: {Decision Title}
**Choice:** {Selected option}
**Rationale:** {Why this option was chosen — user's reasoning}
**Test Impact:** {How this affects test design}

**Comparison:**
| Option | Pros | Cons | Complexity | Recommendation |
|--------|------|------|------------|----------------|
| {option} | {pros} | {cons} | {complexity} | {conditional_rec} |

### D-02: {Decision Title}
**Choice:** {Selected option}
**Rationale:** {Why}
**Test Impact:** {How this affects tests}

**Comparison:**
| ... | ... | ... | ... | ... |

## Deferred Ideas

{Ideas suggested during discussion that are out of scope for this mission.
If none: "No deferred ideas."}

- {idea} — suggested during {area} discussion, deferred because {reason}
```

## How Downstream Agents Use This

- **Task Manager (Phase 2):** Reads decisions to inform task decomposition and
  TEST_LIST.md creation. D-01's choice of SQLite means tests need setup/teardown;
  D-02's choice of fail-fast means fewer retry edge case tests.

- **Planner (Phase 3):** Reads decisions to plan implementation approach. The
  chosen library/pattern dictates what files to create and how to structure code.

- **Researcher (Phase 2):** Cross-references decisions when analyzing codebase
  patterns. Avoids recommending patterns that contradict user decisions.
