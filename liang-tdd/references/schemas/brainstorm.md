# Brainstorm Schemas

Schemas for Phase 1 artifacts.

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
