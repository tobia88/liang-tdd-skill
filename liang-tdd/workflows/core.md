# Core TDD Workflow

Shared workflow logic for `/liang-tdd:*` commands. This file is the phase router
and orchestration hub. Phase-specific prompts and schemas are loaded on-demand
via @-imports or agent definitions — NOT all at once.

`{mission_dir}` = `.planning/vibe/{NNN}-{slug}/`

---

## Critical Rule: AskUserQuestion for ALL Questions

**NEVER ask questions as inline text.** Every question to the user —
clarifications, "what next?" prompts, failure alerts — MUST use the
AskUserQuestion tool. This applies to:
- Any decision point or "would you like to..." prompt
- Max-iteration failure alerts (the only mid-execution pause)
- Post-task skill suggestions
- Blocker resolution
- Context clearing gates (only in `--manual` mode)

If you catch yourself writing a question as plain text, STOP and use
AskUserQuestion instead.

---

## Flag Parsing

Commands parse flags from `$ARGUMENTS` before processing the topic/number:

| Flag | Supported Commands | Effect |
|------|-------------------|--------|
| `--manual` | add-mission, resume-mission | Enables old interactive mode: context clearing gates + task approval pauses |
| `--research` | add-mission, resume-mission (Phase 1) | Enables upfront research before brainstorming (skipped by default) |
| `--skip-discuss` | add-mission, resume-mission | Skips Phase 1.5 (architecture discussion), goes straight to Task Manager |

**Parsing logic:**
1. Split `$ARGUMENTS` on whitespace
2. Extract recognized flags (`--manual`, `--research`, `--skip-discuss`)
3. Remaining tokens = the actual argument (topic name or mission number)

**Default behavior (no flags):** After Phase 1/1.5 interactive discussion
completes, the workflow auto-advances through Phase 2 (Task Manager with
auto-accept) → Phases 3-5 (Plan → Execute → QA) without pausing. The only
mid-execution pause is when a task hits max iterations (10 QA failures).

---

## Model Routing

| Role | Model | Method |
|------|-------|--------|
| Brainstormer | Opus (current session) | **Inline** (runs directly in main session) |
| Discuss Advisor | Sonnet (per gray area) | Agent tool → `liang-tdd-advisor` agents (parallel) |
| Discuss Orchestrator | Opus (current session) | **Inline** (presents tables, captures decisions) |
| Task Manager | Opus | Agent tool → `liang-tdd-task-manager` agent |
| Planner | Opus | Agent tool → `liang-tdd-planner` agent |
| Executor | Sonnet | `claude -p --model claude-sonnet-4-6` (in worktree) |
| QA Verifier | Sonnet | `claude -p --model claude-sonnet-4-6` |
| Debugger | Sonnet | Agent tool → `liang-tdd-debugger` agent (after QA fail) |

**Model routing is MANDATORY — never override.** The orchestrator MUST use the
exact model specified in the table above. Specifically:
- **NEVER promote Sonnet roles to Opus.** Executors, QA verifiers, and debuggers
  are designed for Sonnet — they follow mechanical plans, not creative judgment.
  Running them on Opus wastes 5x the tokens for no quality benefit.
- **If the designated model hits a rate limit:** pause and alert the user via
  AskUserQuestion. Do NOT silently switch to a more expensive model.
- **If the user explicitly requests a model override:** honor it, but note the
  cost implication in the progress update.

---

## Context Clearing Gates (--manual mode only)

**By default, context clearing gates are SKIPPED.** The workflow auto-advances
from Phase 1.5 → Phase 2 → Phases 3-5 without pausing.

Gates only activate when `--manual` flag is passed:

### Gate: Before Task Manager (Phase 2) — manual only

After Phase 1 (Brainstorm) completes and BRAINSTORM.md is saved:
1. Use AskUserQuestion to ask:
   > "Phase 1 complete. Before the Task Manager starts, would you like to /clear
   > the conversation to free up context? The brainstorm is saved to
   > `{mission_dir}/BRAINSTORM.md` so nothing will be lost."
2. If user says yes → instruct them to run `/clear`, then re-invoke
   `/liang-tdd:resume-mission` (resume detection will pick up from Phase 2)
3. If user says no → proceed directly to Phase 2

### Gate: Before each Planner invocation (Phase 3) — manual only

Before spawning the Planner for each task:
1. Use AskUserQuestion to ask:
   > "About to plan task {task_id}. Want to /clear the conversation first?
   > All progress is saved in `{mission_dir}/PROGRESS.md`."
2. Same logic: if yes → `/clear` + re-invoke; if no → proceed

---

## Phase 0: Resume Detection

On invocation, determine the active mission:

**If creating a new mission (from /liang-tdd:add-mission):**
1. Create the mission directory (see mission-ops.md)
2. Install the TDD test guard hook (see below)
3. Start fresh from Phase 1

**If resuming (from /liang-tdd:resume-mission):**
1. Find the mission by index or auto-detect (see mission-ops.md)
2. Ensure the TDD test guard hook is installed (see below)
3. Read its `PROGRESS.md`
4. Resume from the next incomplete step

**When resuming an existing mission:**
1. Read `{mission_dir}/PROGRESS.md`
2. Determine the last completed phase and task
3. Print a status summary to the user:
   ```
   Resuming mission {NNN}-{slug}:
   - Phase: {current_phase}
   - Last completed: {task_id} — {status}
   - Remaining: {count} tasks ({parallel_count} parallelizable)
   ```
4. Resume from the next incomplete step

### Install TDD Test Guard Hook

The test guard hook prevents test file modification after the RED snapshot phase.
It is scoped to the current project — installed into `.claude/settings.local.json`,
NOT the global settings. This keeps it active only during TDD missions.

**Install logic (Phase 0):**
1. Read `.claude/settings.local.json` (create if missing)
2. Parse existing JSON (preserve all existing config)
3. Run `echo $HOME` via Bash to get the actual home directory path
4. Merge the tdd-test-guard into `hooks.PreToolUse`:
   ```json
   {
     "matcher": "Write|Edit",
     "if": "Write(**/tests/test-*.sh)|Edit(**/tests/test-*.sh)",
     "hooks": [{
       "type": "command",
       "command": "node \"{HOME}/.claude/hooks/tdd-test-guard.js\"",
       "timeout": 5
     }]
   }
   ```
   Replace `{HOME}` with the actual value from `echo $HOME`.
   The `if` field (v2.1.85+) scopes the hook to test script paths only,
   eliminating overhead on every other file edit.
5. Write back `.claude/settings.local.json`
6. The command string containing `tdd-test-guard.js` acts as the uninstall marker

**Idempotency:** Before adding, check if a hook with command containing
`tdd-test-guard.js` already exists. If so, skip installation.

---

## Phase 1: Brainstormer (Inline — Main Session)

The brainstormer runs **directly in the main session** (not as a subagent) so it
can use AskUserQuestion natively. Follow the `/liang-brain-extractor` behavioral
pattern.

**Load on-demand:**
@$HOME/.claude/liang-tdd/references/prompts/brainstormer.md
@$HOME/.claude/liang-tdd/references/schemas/brainstorm.md

**Behavior:**

### Step 0: Upfront Research (only with `--research` flag)

**This step is SKIPPED by default.** Only runs when `--research` flag is passed.

If `research=true`:
1. Spawn a research Agent (general-purpose) with WebSearch/WebFetch
2. Save findings to `{mission_dir}/RESEARCH-BRAINSTORM.md`
3. Use findings to enrich AskUserQuestion options throughout brainstorming

If `research=false` (default): skip directly to Step 1.

### Step 0.5: Confidence Threshold Selection

Use AskUserQuestion to ask the user what confidence level they want to be
prompted at (6/10, 8/10 default, 10/10, or custom). Store as `confidence_gate`.
This is a soft gate — the brainstormer asks whether to stop, never auto-stops.

### Step 1: Socratic Questioning (research-informed)

1. Use AskUserQuestion to conduct Socratic questioning about the task
2. After each user response, rate understanding confidence (1-10 scale)
3. Embed research findings in questions when relevant (if `--research` was used)
4. Steer toward: task breakdown, done criteria, edge cases, dependencies, parallelism
5. **Gate: When confidence reaches `confidence_gate`, ask user whether to stop or keep going (via AskUserQuestion). Never auto-stop. Re-ask at each whole-number increase above threshold. Even past 10/10, continue until user explicitly says stop.**
6. Save output to `{mission_dir}/BRAINSTORM.md` when user chooses to stop

**→ Phase 1.5: Discuss (unless `--skip-discuss`)**
**→ Then auto-advance to Phase 2 (unless `--manual`)**

---

## Phase 1.5: Discuss — Architecture Advisor (Inline — Main Session)

**Skip condition:** If `--skip-discuss` flag is set, skip this phase entirely
and proceed to Phase 2. Print:
`"Skipping architecture discussion (--skip-discuss). Proceeding to task decomposition."`

**Runs by default.** The discuss phase identifies architecture decisions from the
brainstorm that affect test design, researches alternatives via parallel advisor
agents, and captures the user's explicit choices.

**Load on-demand:**
@$HOME/.claude/liang-tdd/references/prompts/discuss.md
@$HOME/.claude/liang-tdd/references/schemas/decisions.md

**Behavior:**

### Step 1: Identify Gray Areas

Read `{mission_dir}/BRAINSTORM.md` and scan the project codebase briefly.
Identify 2-4 architecture decisions that:
- Could go multiple ways
- Affect how tests will be written
- Are NOT things Claude can decide alone

Generate SPECIFIC decisions, not generic categories.

### Step 2: Present Gray Areas

Use AskUserQuestion with `multiSelect=true`:
- Each gray area as an option with description of what needs deciding
- Description includes how the choice affects test design
- User selects which areas to discuss

### Step 3: Spawn Advisor Agents

For each selected gray area, spawn a `liang-tdd-advisor` agent in parallel:

```
Agent(
  subagent_type: "liang-tdd-advisor",
  prompt: "area_name: {name}\narea_description: {desc}\nbrainstorm_summary: {summary}\nproject_root: {root}"
)
```

Launch ALL advisors simultaneously. Wait for all to complete.

### Step 4: Present Tables and Capture Decisions

For each gray area:
1. Show the advisor's comparison table (Option | Pros | Cons | Complexity | Rec)
2. Show the Test Impact line
3. Use AskUserQuestion to ask which option the user prefers
   - Each table row becomes an option
   - "Other" allows custom input
4. Record as numbered decision (D-01, D-02, etc.)

### Step 5: Write DECISIONS.md

Save to `{mission_dir}/DECISIONS.md` using the decisions schema.

**→ Auto-advance to Phase 2 (or Context Clearing Gate if `--manual`)**

---

## Phase 2: Task Manager (via `liang-tdd-task-manager` agent)

Spawn the `liang-tdd-task-manager` agent via the Agent tool with `subagent_type`.

**Input:** `{mission_dir}/BRAINSTORM.md` and `{mission_dir}/DECISIONS.md` (if exists)

The agent definition at `~/.claude/agents/liang-tdd-task-manager.md` contains:
- The full Task Manager prompt
- Schemas for TASKS.md, TEST_LIST.md, and PROGRESS.md
- Tool allowlist and model config

Pass the mission context in the agent prompt:
```
mission_dir: {mission_dir}
project_root: {project_root}
auto_mode: {true|false}
```

**Default (auto-advance):** Pass `auto_mode: true`. Task Manager auto-accepts
all tasks and TEST_LISTs without user walkthrough.

**Manual mode (`--manual`):** Pass `auto_mode: false`. Task Manager presents
each task and TEST_LIST for user approval before proceeding.

The Task Manager will:
1. Read BRAINSTORM.md
2. Decompose into tasks
3. Spawn `liang-tdd-researcher` agents in parallel per task
4. Write TEST_LIST.md for each task (informed by RESEARCH.md)
5. Assign parallel groups
6. Auto-accept (default) or present to user (`--manual`)
7. Save TASKS.md and initialize PROGRESS.md

---

## Phases 3-5: Vertical-Slice TDD Execution Loop

For each task (respecting dependency order and parallel groups), run this loop:

### Phase 3: Planner (via `liang-tdd-planner` agent)

**→ Context Clearing Gate before each Planner invocation (--manual only)**

Spawn the `liang-tdd-planner` agent via the Agent tool with `subagent_type`.

Pass the task context in the agent prompt:
```
task_id: {task_id}
mission_dir: {mission_dir}
{re_plan_context if applicable}
```

The agent definition at `~/.claude/agents/liang-tdd-planner.md` contains:
- The full Planner prompt with vertical-slice TDD instructions
- Schema for PLAN.md

On re-plan (after QA failure):
- Version the old plan: rename `PLAN.md` → `PLAN-v{N}.md`
- Include QA failure analysis in the agent prompt
- If RESEARCH-{iteration}.md exists, mention it in the prompt

### Phase 4: Executor (Sonnet via CLI + worktree)

The orchestrator (you) manages the worktree setup. Check for VCS type:

**Git projects:**
```bash
git worktree add .worktrees/task-{id} -b vibe/task-{id}
```

**Non-git projects (Perforce, no VCS):**
```bash
mkdir -p .worktrees/task-{id}
cp -r {relevant_dirs} .worktrees/task-{id}/
```

Then spawn the executor in the worktree. Build the prompt from
`~/.claude/liang-tdd/references/prompts/executor.md`, filling in:
- The task ID and slug
- Path to PLAN.md and TEST_LIST.md (using `{mission_dir}`)
- Skill file paths referenced in the plan

```bash
cd .worktrees/task-{id} && claude -p --model claude-sonnet-4-6 \
  --allowedTools Edit,Write,Bash,Read,Glob,Grep \
  "$(cat {mission_dir}/tasks/{id}/EXECUTOR_PROMPT.txt)"
```

The executor works in isolation, following vertical-slice TDD:
RED → snapshot → GREEN → regression check → BLUE → next test.
It commits its work when all tests pass.

### Phase 5: QA Verifier (Sonnet via CLI)

Build the QA prompt from `~/.claude/liang-tdd/references/prompts/qa-verifier.md`,
filling in the worktree path and TEST_LIST.md path.

```bash
claude -p --model claude-sonnet-4-6 \
  --allowedTools Read,Bash,Glob,Grep,Write \
  "$(cat {mission_dir}/tasks/{id}/QA_PROMPT.txt)"
```

**Decision logic after QA:**

| Result | Action |
|--------|--------|
| ALL PASS + no tamper + full coverage | Merge worktree back (git merge or file copy) |
| ANY FAIL (any iteration < 10) | **Diagnose** → then re-plan (see below) |
| ANY FAIL, iteration >= 10 | Mark `failed` in PROGRESS.md, **pause and alert user via AskUserQuestion** (see below) |
| Merge conflict (git only) | Attempt auto-resolve; if fails → AskUserQuestion for manual resolution |

**Max-iteration failure pause:** This is the only mid-execution pause in
auto-advance mode. When a task hits 10 failed iterations:
1. Mark task as `failed` in PROGRESS.md
2. Use AskUserQuestion to alert the user:
   > "Task {task_id} failed after 10 iterations. {brief diagnosis summary}.
   > How would you like to proceed?"
   Options: "Skip and continue to next task" / "Abort mission" / "Retry with different approach"
3. Act on user's choice before continuing

**Merge logic by VCS type:**

Git:
```bash
git checkout {main} && git merge vibe/task-{id} && git worktree remove .worktrees/task-{id} && git branch -d vibe/task-{id}
```

Non-git:
```bash
cp -r .worktrees/task-{id}/{changed_files} .
rm -rf .worktrees/task-{id}
```

### QA Failure Flow: Diagnose → Research → Re-plan

When QA fails (ANY iteration):

**Step 1: Diagnose (every failure)**

Spawn the `liang-tdd-debugger` agent:
```
Agent(
  subagent_type: "liang-tdd-debugger",
  prompt: "task_id: {task_id}\niteration: {N}\nmission_dir: {mission_dir}\nworktree_path: .worktrees/task-{id}"
)
```

The debugger reads QA_REPORT, test scripts, and implementation code.
It writes `{mission_dir}/tasks/{id}/DEBUG.md` with:
- Symptoms table (expected vs actual per test)
- Hypotheses tested with evidence
- Root cause diagnosis (or "inconclusive")
- Recommended fix direction
- Decision alignment check (drift from DECISIONS.md)

**Step 2: Research (iteration 2+ OR inconclusive diagnosis)**

Trigger online research if:
- This is the 2nd+ QA failure for this task, OR
- DEBUG.md status is "inconclusive"

When triggered:
1. Research online using WebSearch/WebFetch
   - Focus searches on symptoms and root cause from DEBUG.md
   - Avoid searching for hypotheses already eliminated in DEBUG.md
2. Save findings to `{mission_dir}/tasks/{id}/RESEARCH-{iteration}.md`
3. Track skill suggestions in the research file

**Step 3: Re-plan**

Version artifacts:
- `QA_REPORT.md` → `QA_REPORT-v{N}.md`
- `PLAN.md` → `PLAN-v{N}.md`

Feed the planner ALL available context:
- Previous PLAN-v{N}.md
- QA_REPORT-v{N}.md
- DEBUG.md (diagnosis with root cause and fix direction)
- RESEARCH-{iteration}.md (if research was triggered)
- DECISIONS.md (to prevent drift from user's choices)

---

## Outer Loop: Task Orchestration

1. Read `{mission_dir}/TASKS.md` for the full task list and parallel_group tags
2. Process tasks in dependency order:
   - **Sequential tasks**: one at a time through Phases 3→4→5
   - **Parallel group**: launch concurrent worktree agents (multiple `claude -p`
     processes via Bash with `run_in_background`)
3. After each task completes (pass or fail):
   - Update `{mission_dir}/PROGRESS.md` with status, iteration count, and notes
   - Print real-time status update to the user
   - Check for skill suggestions from research files
4. After all tasks complete → proceed to Final Report

### Parallel Execution Details

For tasks in the same parallel_group:
1. Create all worktrees simultaneously
2. Run all planners (if using Agent tool, run sequentially; plans are fast)
3. Launch all executors concurrently via `run_in_background`
4. As each executor completes, run its QA
5. Merge completed tasks sequentially (to avoid conflicts)
6. If a merge conflict occurs on a parallel task, ask the user

### Progress Updates

After each task completion, print:
```
[{completed}/{total}] Mission {NNN}-{slug} | Task {id}-{task_slug}: {PASS|FAIL} (iteration {N}, {tests_passing}/{total_tests} tests)
  Remaining: {remaining_tasks}
  Next: {next_task_id}-{next_slug} ({sequential|parallel with X})
```

### Post-Task Skill Suggestion

After a task completes (PASS or FAIL at max iterations), if any
`RESEARCH-{iteration}.md` files contain a `## Skill Suggestion` section:
1. Use AskUserQuestion to present the suggestion
2. If user agrees → they can run `/example-skills:skill-creator` with the prompt
3. If user declines → move on

---

## Final Report

After all tasks are processed:

**Load on-demand:**
Read `~/.claude/liang-tdd/references/schemas/final-report.md` for the schema.

1. Generate and save to `{mission_dir}/FINAL_REPORT.md`
2. **Uninstall the TDD test guard hook** (see below)

### Uninstall TDD Test Guard Hook

Remove the guard from `.claude/settings.local.json` when the mission completes:
1. Read `.claude/settings.local.json`
2. Find and remove the PreToolUse entry with command containing `tdd-test-guard.js`
3. If `hooks.PreToolUse` array is now empty, remove the key
4. If `hooks` object is now empty, remove the key
5. Write back `.claude/settings.local.json` (preserve all other config)

---

## Important Notes

- **Test files are HARD-LOCKED by a PreToolUse hook during missions.** The
  `tdd-test-guard.js` hook blocks ALL Write/Edit operations on test scripts
  (`tests/test-*.sh`) once their RED snapshot exists. This works even with
  `bypassPermissions`.
- **Never skip the TEST_LIST step.** Every task must have its ordered test list
  before any code is written.
- **Tests are written ONE AT A TIME.** Vertical-slice TDD: RED → GREEN → BLUE → next.
- **Snapshot before implementing.** QA uses RED snapshots for tamper detection.
- **Never modify tests to make them pass.** Fix the implementation instead.
- **Skill-modifying tasks must be sequential.**
- **Auto-advance is the default.** After Phase 1/1.5 discussion, everything runs
  hands-off. Task decomposition and TEST_LISTs are auto-accepted. Use `--manual`
  for the old interactive behavior with gates and task approval.
- **Only mid-execution pause: max-iteration failure.** When a task hits 10 QA
  failures, the workflow pauses to alert the user via AskUserQuestion.
- **Re-plans get full context** (failed QA_REPORT + previous PLAN).
- **Research triggers on 2nd+ QA failure.**
- **Worktrees are cleaned up after merge.**
- **Max 10 iterations per task.**
- **Context clearing gates are `--manual` only** — skipped by default.
- **Brainstormer runs inline** (not subagent) for AskUserQuestion access.
- **VCS-agnostic** — file snapshots for checkpoints, not git commits.
- **NEVER switch model routing.** If Sonnet is rate-limited for executor/QA/debugger,
  PAUSE and ask the user — do not silently upgrade to Opus. Model assignments exist
  for cost control.

---

## Autonomous Runner (Overnight Mode)

For unattended overnight execution, use `tdd-runner.sh` — a thin bash harness
that spawns fresh Claude sessions per phase per task.

**Location:** `~/.claude/liang-tdd/scripts/tdd-runner.sh`

### Two modes

**Default (Phases 3-5 only)** — you do Phases 1-2 interactively, runner handles execution:
```bash
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh .planning/vibe/003-my-feature
```

**`--auto` (Phases 1-5)** — provide a spec file, runner does everything:
```bash
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh --auto \
  --prompt-file my-feature-spec.md \
  --mission-name my-feature
```

### Runner flags

| Flag | Default | Effect |
|------|---------|--------|
| `--max-turns N` | 50 | Max turns per executor spawn |
| `--max-retries N` | 3 | Max QA retries per task |
| `--stop-on-fail N` | 3 | Abort after N consecutive task failures |
| `--plan-model MODEL` | claude-opus-4-6 | Model for planner |
| `--exec-model MODEL` | claude-sonnet-4-6 | Model for executor/QA |
| `--auto` | off | Enable fully autonomous mode (Phases 1-5) |
| `--prompt-file FILE` | — | Spec file → BRAINSTORM.md (requires --auto) |
| `--mission-name NAME` | — | Slug for new mission (requires --auto + --prompt-file) |
