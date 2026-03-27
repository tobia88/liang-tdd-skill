---
name: liang-tdd:progress
description: Show mission progress, status, and next action
argument-hint: [mission-number]
allowed-tools:
  - Read
  - Glob
---

<objective>
Display detailed progress for a mission and suggest the next action. If no
mission number is given, show the active mission. If no active mission exists,
show a list of all missions.

Output the progress report directly. Do NOT add commentary beyond the report.
</objective>

<execution_context>
@$HOME/.claude/liang-tdd/workflows/mission-ops.md
</execution_context>

<context>
Arguments: $ARGUMENTS (optional mission number)
</context>

<process>
1. If $ARGUMENTS contains a mission number:
   - Find the mission directory matching that index in `.planning/vibe/`
   - Show detailed progress for that mission
2. If no argument:
   - Scan `.planning/vibe/` for missions
   - If exactly one incomplete mission → show its detailed progress
   - If multiple incomplete → show mission list (see mission-ops.md § Listing Missions),
     highlight the most recently updated one
   - If none incomplete → show mission list with all statuses

3. For detailed mission progress, read PROGRESS.md and display:

```
Mission {NNN}-{slug}
Phase: {current_phase_name} ({N}/5)
Started: {date}  |  Last updated: {date}

Tasks:
| #  | Task           | Status      | Iterations | Notes                    |
|----|----------------|-------------|------------|--------------------------|
| 01 | {slug}         | {status}    | {N}        | {notes}                  |
| 02 | {slug}         | {status}    | {N}        | {notes}                  |

Progress: [{completed}/{total}] {percentage}% complete
  Passed: {N}  |  Failed: {N}  |  In Progress: {N}  |  Pending: {N}

Next action: {description of what to do next}
  → Run: /liang-tdd:resume-mission {number}
```

4. Determine "Next action" based on current state:
   - No BRAINSTORM.md → "Start brainstorming"
   - BRAINSTORM.md exists, no TASKS.md → "Run Task Manager to decompose tasks"
   - Tasks pending → "Execute task {next_task_id}"
   - Task in_progress → "Continue task {task_id} (iteration {N})"
   - All tasks done → "Generate final report" or "Mission complete"
   - Has failed tasks → "Review failed tasks: {list}"
</process>
