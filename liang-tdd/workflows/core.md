# Core TDD Workflow

Shared workflow logic for `/liang-tdd:*` commands. All phase definitions,
model routing, context clearing gates, and orchestration live here.

`{mission_dir}` = `.planning/vibe/{NNN}-{slug}/`

---

## Critical Rule: AskUserQuestion for ALL Questions

**NEVER ask questions as inline text.** Every question to the user — context
clearing gates, task approvals, clarifications, "what next?" prompts — MUST use
the AskUserQuestion tool. This applies to:
- Context clearing gates (before Phase 2, before each Planner)
- Task approval during Phase 2
- Any decision point or "would you like to..." prompt
- Post-task skill suggestions
- Blocker resolution

If you catch yourself writing a question as plain text, STOP and use
AskUserQuestion instead.

---

## Flag Parsing

Commands parse flags from `$ARGUMENTS` before processing the topic/number:

| Flag | Supported Commands | Effect |
|------|-------------------|--------|
| `--no-limit` | add-mission, resume-mission (Phase 1) | Disables 8/10 confidence gate; brainstormer continues until user says "stop" |
| `--auto` | resume-mission | Task Manager auto-accepts all tasks without walking through each TEST_LIST |

**Parsing logic:**
1. Split `$ARGUMENTS` on whitespace
2. Extract recognized flags (`--no-limit`, `--auto`)
3. Remaining tokens = the actual argument (topic name or mission number)

---

## Model Routing

| Role | Model | Method |
|------|-------|--------|
| Brainstormer | Opus (current session) | **Inline** (runs directly in main session) |
| Task Manager | Opus (current session) | Agent tool |
| Planner | Opus (current session) | Agent tool |
| Executor | Sonnet | `claude -p --model claude-sonnet-4-6` (in worktree) |
| QA Verifier | Sonnet | `claude -p --model claude-sonnet-4-6` |

---

## Context Clearing Gates

Before heavy phases, offer the user a chance to free up context:

### Gate: Before Task Manager (Phase 2)

After Phase 1 (Brainstorm) completes and BRAINSTORM.md is saved:
1. Use AskUserQuestion to ask:
   > "Phase 1 complete. Before the Task Manager starts, would you like to /clear
   > the conversation to free up context? The brainstorm is saved to
   > `{mission_dir}/BRAINSTORM.md` so nothing will be lost."
2. If user says yes → instruct them to run `/clear`, then re-invoke
   `/liang-tdd:resume-mission` (resume detection will pick up from Phase 2)
3. If user says no → proceed directly to Phase 2

### Gate: Before each Planner invocation (Phase 3)

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
3. Merge the tdd-test-guard into `hooks.PreToolUse`:
   ```json
   {
     "matcher": "Write|Edit",
     "hooks": [{
       "type": "command",
       "command": "node \"C:/Users/Liang/.claude/hooks/tdd-test-guard.js\"",
       "timeout": 5
     }]
   }
   ```
4. Write back `.claude/settings.local.json`
5. Use a marker comment in the hook entry to identify it for removal:
   tag the command string or add it as a known pattern to match during uninstall

**Idempotency:** Before adding, check if a hook with command containing
`tdd-test-guard.js` already exists. If so, skip installation.

---

## Phase 1: Brainstormer (Inline — Main Session)

The brainstormer runs **directly in the main session** (not as a subagent) so it
can use AskUserQuestion natively. Follow the `/liang-brain-extractor` behavioral
pattern.

**Behavior:**

### Step 0: Upfront Research

Before asking the first question, research the topic to inform the conversation:

1. Spawn a research Agent (general-purpose) with WebSearch/WebFetch to gather:
   - Common libraries, frameworks, or tools used for this kind of task
   - Best practices and recommended patterns
   - Common pitfalls and gotchas
   - Alternative approaches with trade-offs
2. The research agent returns a structured summary
3. Save findings to `{mission_dir}/RESEARCH-BRAINSTORM.md`
4. Use these findings to **enrich AskUserQuestion options** throughout brainstorming:
   - When asking about approach/architecture, include research-backed options
   - When asking about libraries/tools, include discovered alternatives as choices
   - Add research context in option `description` fields so the user sees the reasoning
   - Example: instead of asking "What library do you want to use?", offer
     `[{label: "Tesseract.js", description: "Most popular OCR lib, 40k+ GitHub stars, good accuracy"}, ...]`

### Step 1: Socratic Questioning (research-informed)

1. Use AskUserQuestion to conduct Socratic questioning about the task
2. After each user response, rate understanding confidence:
   - Format: `"X/10 — [what I understand / what's still unclear]"`
   - Scale: 1-3 low (need fundamentals), 4-5 partial, 6-7 good but gaps,
     8-9 strong understanding, 10 complete clarity
3. **Embed research findings in questions**: When the topic aligns with research
   results, present recommendations as AskUserQuestion options with descriptions
   explaining trade-offs. Let the user pick informed by research rather than
   guessing blind.
4. Steer the conversation toward:
   - What the natural task breakdown looks like
   - What "done" looks like for each piece (success criteria)
   - Edge cases, constraints, and dependencies between pieces
   - Which parts could run in parallel vs must be sequential
4. **Gate (normal mode): Cannot proceed until confidence >= 8/10**
   - If stuck below 8, ask increasingly specific questions about the gaps
5. **Gate (--no-limit mode): No automatic stop.**
   - Continue asking questions indefinitely regardless of confidence level
   - Only stop when the user explicitly says "stop", "enough", "done", or similar
   - Still show the confidence rating after each response for transparency
6. Save output to `{mission_dir}/BRAINSTORM.md` (include a `## Research Findings`
   section summarizing what was discovered and which recommendations were adopted)

The brainstormer behavioral template is in `references/agent-prompts.md` § Brainstormer.

**→ Context Clearing Gate before Phase 2**

---

## Phase 2: Task Manager (Opus via Agent tool)

Spawn a subagent via the Agent tool.

**Input:** `{mission_dir}/BRAINSTORM.md`

**Agent behavior:**
1. Read BRAINSTORM.md thoroughly
2. Decompose into discrete, independently testable tasks
3. For each task, create `{mission_dir}/tasks/{NN}-{slug}/TEST_LIST.md`:
   - **Goal**: 1-sentence description
   - **Ordered test list** with bash test scripts — this IS the TDD spec
   - Tests must be ordered from simplest to most complex
   - Each test script must FAIL before implementation and PASS after
   - Tests verify outcomes, not implementation details
   - **Expected changes**: list of files to be created/modified
4. Analyze dependencies to assign `parallel_group:` tags:
   - Tasks touching the same files → sequential (dependency chain)
   - Tasks modifying skills → must complete before tasks consuming those skills
   - Independent tasks → same parallel_group number

**Normal mode:**
5. Walk through each task's TEST_LIST with the user via AskUserQuestion:
   - Show goal + test list with script previews, ask for approval/edits per task
   - Only proceed once user approves all tasks

**--auto mode:**
5. Auto-accept all tasks. Print each task's goal + test list for visibility,
   but do NOT use AskUserQuestion for approval. Proceed immediately.

6. Save task index to `{mission_dir}/TASKS.md`
7. Initialize `{mission_dir}/PROGRESS.md` with all tasks in `pending` status

The task manager prompt template is in `references/agent-prompts.md` § Task Manager.

---

## Phases 3-5: Vertical-Slice TDD Execution Loop

For each task (respecting dependency order and parallel groups), run this loop:

### Phase 3: Planner (Opus via Agent tool)

**→ Context Clearing Gate before each Planner invocation**

**Input:**
- `{mission_dir}/tasks/{id}/TEST_LIST.md`
- Contents of `.claude/skills/` directory (planner finds relevant skills itself)
- Previous PLAN.md + QA_REPORT.md (if re-planning after failed QA)
- `{mission_dir}/tasks/{id}/RESEARCH-{iteration}.md` (if research was triggered by QA failure)

**Output:** `{mission_dir}/tasks/{id}/PLAN.md`
- Per-test cycle steps (RED → GREEN → BLUE for each test)
- Which skills to read on-demand (with file paths from `.claude/skills/`)
- Exact file changes per GREEN phase
- Snapshot checkpoint instructions for each RED phase

On re-plan (after QA failure):
- Version the old plan: rename `PLAN.md` → `PLAN-v{N}.md`
- Include QA failure analysis in the new plan's context
- Address each failed test specifically
- If RESEARCH-{iteration}.md exists, incorporate its findings

The planner prompt is in `references/agent-prompts.md` § Planner.

### Phase 4: Executor (Sonnet via CLI + worktree)

The orchestrator (you) manages the worktree setup. Check for VCS type:

**Git projects:**
```bash
git worktree add .worktrees/task-{id} -b vibe/task-{id}
```

**Non-git projects (Perforce, no VCS):**
```bash
mkdir -p .worktrees/task-{id}
# Copy relevant project files to the worktree
cp -r {relevant_dirs} .worktrees/task-{id}/
```

Then spawn the executor in the worktree:

```bash
cd .worktrees/task-{id} && claude -p --model claude-sonnet-4-6 \
  --allowedTools Edit,Write,Bash,Read,Glob,Grep \
  "$(cat {mission_dir}/tasks/{id}/EXECUTOR_PROMPT.txt)"
```

Build the executor prompt from `references/agent-prompts.md` § Executor, filling in:
- The task ID and slug
- Path to PLAN.md and TEST_LIST.md (using `{mission_dir}`)
- Skill file paths referenced in the plan

The executor works in isolation in the worktree, following the vertical-slice
TDD cycle: RED → snapshot → GREEN → regression check → BLUE → next test.
It commits its work when all tests pass.

### Phase 5: QA Verifier (Sonnet via CLI)

```bash
claude -p --model claude-sonnet-4-6 \
  --allowedTools Read,Bash,Glob,Grep \
  "$(cat {mission_dir}/tasks/{id}/QA_PROMPT.txt)"
```

Build the QA prompt from `references/agent-prompts.md` § QA Verifier, filling in:
- The worktree path
- Path to TEST_LIST.md (using `{mission_dir}`)

The QA verifier performs three checks:
1. **Test execution**: Runs every test script, records pass/fail
2. **Tamper detection**: Diffs each test against its RED snapshot — any
   modification after the RED phase is a FAIL
3. **Coverage check**: Verifies every test in TEST_LIST.md has a script

Results are written to `{mission_dir}/tasks/{id}/QA_REPORT.md`.

**Decision logic after QA:**

| Result | Action |
|--------|--------|
| ALL PASS + no tamper + full coverage | Merge worktree back (git merge or file copy) |
| ANY FAIL, iteration 1 | Version artifacts (QA_REPORT.md → QA_REPORT-v{N}.md), go back to Phase 3 (normal re-plan) |
| ANY FAIL, iteration >= 2 | **Trigger online research** (see below), then go back to Phase 3 with research context |
| ANY FAIL, iteration >= 10 | Mark `failed` in PROGRESS.md, alert user, continue to next task |
| Merge conflict (git only) | Attempt auto-resolve; if fails → AskUserQuestion for manual resolution |

**Merge logic by VCS type:**

Git:
```bash
git checkout {main} && git merge vibe/task-{id} && git worktree remove .worktrees/task-{id} && git branch -d vibe/task-{id}
```

Non-git:
```bash
# Copy changed files back from worktree to project
cp -r .worktrees/task-{id}/{changed_files} .
rm -rf .worktrees/task-{id}
```

### QA Failure Research (triggered on 2nd+ failure)

When a task fails QA for the 2nd time or more:

1. **Research online** using WebSearch/WebFetch:
   - Search for solutions related to the failed tests
   - Look for common patterns, library docs, or known issues
2. **Save findings** to `{mission_dir}/tasks/{id}/RESEARCH-{iteration}.md`
3. **Feed research to Planner**: The next re-plan iteration receives the research
   file as additional context alongside the failed QA report
4. **Track skill suggestions**: If the research reveals a skill gap, note it in
   the research file under a `## Skill Suggestion` section with a suggested prompt
   for `/example-skills:skill-creator`

### Post-Task Skill Suggestion

After a task completes (PASS or FAIL at max iterations), if any
`RESEARCH-{iteration}.md` files contain a `## Skill Suggestion` section:

1. Use AskUserQuestion to present the suggestion:
   > "During task {task_id}, research identified a potential skill gap:
   > {description}. Would you like to create a skill for this?
   > Suggested prompt for `/example-skills:skill-creator`:
   > `{suggested_prompt}`"
2. If user agrees → they can run `/example-skills:skill-creator` with the prompt
3. If user declines → move on

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

---

## Final Report

After all tasks are processed:
1. Generate and save to `{mission_dir}/FINAL_REPORT.md`
   using the schema from `references/artifact-schemas.md` § FINAL_REPORT.md.
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
  `tdd-test-guard.js` hook is installed into the project's
  `.claude/settings.local.json` at mission start (Phase 0) and removed at mission
  end (Final Report). It blocks ALL Write/Edit operations on test scripts
  (`tests/test-*.sh`) once their RED snapshot exists. This is a machine-enforced
  guardrail — it works even with `bypassPermissions`. The executor CANNOT modify
  tests after the RED phase, period. If a test is genuinely wrong, the RED
  snapshot must be manually deleted first.
- **Never skip the TEST_LIST step.** Every task must have its ordered test list
  before any code is written. This is the TDD in "solo TDD".
- **Tests are written ONE AT A TIME.** The executor follows vertical-slice TDD:
  write one test (RED) → implement (GREEN) → refactor (BLUE) → next test.
  NEVER write all tests first.
- **Snapshot before implementing.** Every test script gets a RED snapshot before
  any implementation begins. QA uses these to detect test tampering.
- **Never modify tests to make them pass.** Fix the implementation instead.
  If a test is genuinely wrong, it must be caught during the TEST_LIST approval
  phase, not during execution. The tdd-test-guard hook enforces this at the
  tool level during active missions — even if Claude tries, the Write/Edit
  will be blocked.
- **Skill-modifying tasks must be sequential.** If a task modifies a skill that
  another task depends on, the modifier must complete and merge first.
- **The user approves every TEST_LIST (unless --auto).** In normal mode,
  walk through each one with the user via AskUserQuestion. In --auto mode,
  auto-accept and print for visibility.
- **Re-plans get full context.** When QA fails, the planner receives both the
  failed QA_REPORT and the previous PLAN so it can learn from mistakes.
- **Research triggers on 2nd+ QA failure.** First failure gets a normal re-plan.
  Second and subsequent failures trigger online research for additional context.
- **Worktrees are cleaned up after merge.** Don't leave stale worktrees around.
- **Max 10 iterations per task.** If a task can't pass QA in 10 tries, something
  is fundamentally wrong — flag it and move on.
- **Context clearing gates are optional.** The user can always decline and proceed.
  But always offer before Task Manager and each Planner invocation.
- **Brainstormer runs inline.** It is NOT a subagent — it runs in the main session
  so it can use AskUserQuestion directly.
- **VCS-agnostic.** The workflow uses file snapshots for checkpoints, not git
  commits. This works with git, Perforce, or no VCS at all.

---

## Autonomous Runner (Overnight Mode)

For unattended overnight execution, use `tdd-runner.sh` — a thin bash harness
that spawns fresh Claude sessions per phase per task. The runner never runs out
of context because each session is independent.

**Location:** `~/.claude/liang-tdd/scripts/tdd-runner.sh`

### Two modes

**Default (Phases 3-5 only)** — you do Phases 1-2 interactively, runner handles execution:
```bash
# 1. Do brainstorm + task approval interactively during the day
/liang-tdd:add-mission "my feature"
# 2. Once TASKS.md exists, kick off the runner and go to bed
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh .planning/vibe/003-my-feature
```

**`--auto` (Phases 1-5)** — provide a spec file, runner does everything:
```bash
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh --auto \
  --prompt-file my-feature-spec.md \
  --mission-name my-feature
```
The spec file becomes BRAINSTORM.md directly. Task Manager auto-generates TASKS.md.
Without `--auto`, the runner refuses to start if TASKS.md doesn't exist.

### Runner behavior

- Spawns fresh `claude -p` per phase: Planner (Opus) → Executor (Sonnet) → QA (Sonnet)
- Each session gets a clean context window — no degradation
- Progress tracked on disk via PROGRESS.md, not conversation memory
- Conservative defaults: 50 turns/executor, 3 QA retries, abort after 3 consecutive failures
- Installs tdd-test-guard hook at start, removes at end
- Sends Windows notification on completion/abort
- Logs everything to `{mission_dir}/runner.log`
- Switchable: start interactive → go to bed → runner takes over → wake up → resume interactive

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
