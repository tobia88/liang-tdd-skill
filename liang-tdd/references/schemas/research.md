# Research Schema

Schema for RESEARCH-{iteration}.md — created when a task fails QA for the 2nd+
time. Contains online research findings to help the planner create a better re-plan.

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
