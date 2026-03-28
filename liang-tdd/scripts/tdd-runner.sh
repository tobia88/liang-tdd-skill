#!/bin/bash
# tdd-runner.sh — Overnight runner for /liang-tdd missions
#
# A thin outer harness that spawns fresh Claude sessions per phase per task.
# Each session gets a clean context window. Progress is tracked on disk via
# PROGRESS.md, not in conversation memory.
#
# Usage:
#   tdd-runner.sh <mission-dir> [options]
#
# Modes:
#   Default       Runs Phases 3-5 only. Requires TASKS.md to exist
#                 (do Phases 1-2 interactively first).
#   --auto        Fully autonomous. Requires --prompt-file. FILE becomes
#                 BRAINSTORM.md, Task Manager auto-generates TASKS.md,
#                 then runs Phases 3-5.
#
# Options:
#   --auto                Enable fully autonomous mode (Phases 1-5)
#   --prompt-file FILE    Spec file that becomes BRAINSTORM.md (requires --auto)
#   --mission-name NAME   Slug for new mission (required with --auto if no mission-dir)
#   --max-turns N         Max turns per executor spawn (default: 50)
#   --max-retries N       Max QA retries per task (default: 3)
#   --stop-on-fail N      Abort after N consecutive task failures (default: 3)
#   --plan-model MODEL    Model for planner (default: claude-opus-4-6)
#   --exec-model MODEL    Model for executor/QA (default: claude-sonnet-4-6)
#
# Examples:
#   # Run phases 3-5 for a mission that already has TASKS.md:
#   tdd-runner.sh .planning/vibe/003-auth-system
#
#   # Fully autonomous from a spec file:
#   tdd-runner.sh --auto --prompt-file auth-spec.md --mission-name auth-system
#
# Requirements:
#   - claude CLI in PATH
#   - node in PATH (for hook install/uninstall)
#   - Project working directory as CWD

set -euo pipefail

# MUST be set before any cd or path operations
PROJECT_ROOT="$(pwd)"

# --- Defaults ---
AUTO_MODE=false
MAX_TURNS=50
MAX_RETRIES=3
STOP_ON_FAIL=3
PLAN_MODEL="claude-opus-4-6"
EXEC_MODEL="claude-sonnet-4-6"
PROMPT_FILE=""
MISSION_NAME=""
MISSION_DIR=""
CONSECUTIVE_FAILS=0
LOG_FILE=""

# --- Color output ---
RED_C='\033[0;31m'
GREEN_C='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[runner]${NC} $*"; }
ok()   { echo -e "${GREEN_C}[  OK  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
fail() { echo -e "${RED_C}[ FAIL ]${NC} $*"; }

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --auto)          AUTO_MODE=true; shift ;;
    --prompt-file)   PROMPT_FILE="$2"; shift 2 ;;
    --mission-name)  MISSION_NAME="$2"; shift 2 ;;
    --max-turns)     MAX_TURNS="$2"; shift 2 ;;
    --max-retries)   MAX_RETRIES="$2"; shift 2 ;;
    --stop-on-fail)  STOP_ON_FAIL="$2"; shift 2 ;;
    --plan-model)    PLAN_MODEL="$2"; shift 2 ;;
    --exec-model)    EXEC_MODEL="$2"; shift 2 ;;
    -*)              echo "Unknown option: $1"; exit 1 ;;
    *)               MISSION_DIR="$1"; shift ;;
  esac
done

# --- Validate --auto dependencies ---
if [[ -n "$PROMPT_FILE" && "$AUTO_MODE" != true ]]; then
  echo "Error: --prompt-file requires --auto flag"
  exit 1
fi
if [[ "$AUTO_MODE" == true && -z "$PROMPT_FILE" && -z "$MISSION_DIR" ]]; then
  echo "Error: --auto requires either --prompt-file or an existing mission-dir with BRAINSTORM.md"
  exit 1
fi

# --- Resolve mission directory ---
if [[ "$AUTO_MODE" == true && -n "$PROMPT_FILE" && -z "$MISSION_DIR" ]]; then
  if [[ -z "$MISSION_NAME" ]]; then
    echo "Error: --mission-name required with --prompt-file when no mission-dir given"
    exit 1
  fi
  VIBE_DIR=".planning/vibe"
  mkdir -p "$VIBE_DIR"
  LAST_IDX=$(ls -d "$VIBE_DIR"/[0-9][0-9][0-9]-* 2>/dev/null | sort | tail -1 | grep -oP '\d{3}' | head -1 || echo "000")
  NEXT_IDX=$(printf "%03d" $((10#$LAST_IDX + 1)))
  MISSION_DIR="$VIBE_DIR/${NEXT_IDX}-${MISSION_NAME}"
  mkdir -p "$MISSION_DIR"
  log "Created mission: $MISSION_DIR"
fi

if [[ -z "$MISSION_DIR" ]]; then
  echo "Usage: tdd-runner.sh <mission-dir> [options]"
  echo "       tdd-runner.sh --auto --prompt-file spec.md --mission-name slug [options]"
  echo ""
  echo "Without --auto: runs Phases 3-5 (requires existing TASKS.md)"
  echo "With --auto:    runs Phases 1-5 (requires --prompt-file or existing BRAINSTORM.md)"
  exit 1
fi

if [[ ! -d "${PROJECT_ROOT}/${MISSION_DIR}" && ! -d "$MISSION_DIR" ]]; then
  echo "Error: Mission directory not found: $MISSION_DIR"
  exit 1
fi

# Normalise MISSION_DIR to be relative to PROJECT_ROOT
MISSION_DIR="${MISSION_DIR#${PROJECT_ROOT}/}"

LOG_FILE="${PROJECT_ROOT}/${MISSION_DIR}/runner.log"
log "Mission: $MISSION_DIR"
log "Root: $PROJECT_ROOT"
log "Log: $LOG_FILE"
log "Config: auto=$AUTO_MODE max_turns=$MAX_TURNS max_retries=$MAX_RETRIES stop_on_fail=$STOP_ON_FAIL"
echo "--- Runner started $(date -Iseconds) ---" >> "$LOG_FILE"

# --- Notification helper (Windows) ---
notify() {
  local title="$1"
  local msg="$2"
  powershell -ExecutionPolicy Bypass -Command "
    [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null;
    \$notify = New-Object System.Windows.Forms.NotifyIcon;
    \$notify.Icon = [System.Drawing.SystemIcons]::Information;
    \$notify.Visible = \$true;
    \$notify.ShowBalloonTip(10000, '$title', '$msg', 'Info');
    Start-Sleep -Seconds 3;
    \$notify.Dispose()
  " 2>/dev/null &
}

# --- Install tdd-test-guard hook ---
# Scoped to project .claude/settings.local.json
# Includes conditional `if` field (v2.1.85) so the hook only fires for test scripts
install_hook() {
  local SETTINGS="${PROJECT_ROOT}/.claude/settings.local.json"
  mkdir -p "${PROJECT_ROOT}/.claude"

  if [[ -f "$SETTINGS" ]]; then
    if grep -q "tdd-test-guard" "$SETTINGS" 2>/dev/null; then
      log "Test guard hook already installed"
      return
    fi
    node -e "
      const fs = require('fs');
      const home = (process.env.HOME || process.env.USERPROFILE || '').replace(/\x5C/g, '/');
      const hookPath = home + '/.claude/hooks/tdd-test-guard.js';
      const s = JSON.parse(fs.readFileSync('${SETTINGS}', 'utf8'));
      if (!s.hooks) s.hooks = {};
      if (!s.hooks.PreToolUse) s.hooks.PreToolUse = [];
      s.hooks.PreToolUse.push({
        matcher: 'Write|Edit',
        'if': 'Write(**/tests/test-*.sh)|Edit(**/tests/test-*.sh)',
        hooks: [{
          type: 'command',
          command: 'node \"' + hookPath + '\"',
          timeout: 5
        }]
      });
      fs.writeFileSync('${SETTINGS}', JSON.stringify(s, null, 2));
    "
  else
    node -e "
      const fs = require('fs');
      const home = (process.env.HOME || process.env.USERPROFILE || '').replace(/\x5C/g, '/');
      const hookPath = home + '/.claude/hooks/tdd-test-guard.js';
      const config = {
        hooks: {
          PreToolUse: [{
            matcher: 'Write|Edit',
            'if': 'Write(**/tests/test-*.sh)|Edit(**/tests/test-*.sh)',
            hooks: [{
              type: 'command',
              command: 'node \"' + hookPath + '\"',
              timeout: 5
            }]
          }]
        }
      };
      fs.writeFileSync('${SETTINGS}', JSON.stringify(config, null, 2));
    "
  fi
  ok "Test guard hook installed"
}

# --- Uninstall tdd-test-guard hook ---
uninstall_hook() {
  local SETTINGS="${PROJECT_ROOT}/.claude/settings.local.json"
  if [[ ! -f "$SETTINGS" ]]; then return; fi

  node -e "
    const fs = require('fs');
    const s = JSON.parse(fs.readFileSync('${SETTINGS}', 'utf8'));
    if (s.hooks && s.hooks.PreToolUse) {
      s.hooks.PreToolUse = s.hooks.PreToolUse.filter(
        e => !JSON.stringify(e).includes('tdd-test-guard')
      );
      if (s.hooks.PreToolUse.length === 0) delete s.hooks.PreToolUse;
      if (Object.keys(s.hooks).length === 0) delete s.hooks;
    }
    fs.writeFileSync('${SETTINGS}', JSON.stringify(s, null, 2));
  "
  ok "Test guard hook uninstalled"
}

# --- Phase 1-2: Autonomous setup (only with --auto) ---
setup_autonomous() {
  if [[ "$AUTO_MODE" != true ]]; then return; fi

  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: Prompt file not found: $PROMPT_FILE"
    exit 1
  fi

  local abs_mission="${PROJECT_ROOT}/${MISSION_DIR}"

  # Phase 1: Prompt file becomes BRAINSTORM.md
  if [[ ! -f "${abs_mission}/BRAINSTORM.md" ]]; then
    if [[ -n "$PROMPT_FILE" ]]; then
      log "Phase 1: Using $PROMPT_FILE as BRAINSTORM.md"
      cp "$PROMPT_FILE" "${abs_mission}/BRAINSTORM.md"
      ok "BRAINSTORM.md created from prompt file"
    else
      fail "No BRAINSTORM.md and no --prompt-file provided"
      exit 1
    fi
  fi

  # Phase 2: Task Manager (auto-accept)
  if [[ ! -f "${abs_mission}/TASKS.md" ]]; then
    log "Phase 2: Spawning Task Manager (--auto mode)..."
    claude -p --model "$PLAN_MODEL" \
      --max-turns 30 \
      --allowedTools Read,Write,Glob,Grep \
      "You are the Task Manager for a solo TDD workflow. Read ${abs_mission}/BRAINSTORM.md and decompose it into tasks. For each task, create ${abs_mission}/tasks/{NN}-{slug}/TEST_LIST.md with ordered bash test scripts. Auto-accept all tasks (--auto mode). Save task index to ${abs_mission}/TASKS.md and initialize ${abs_mission}/PROGRESS.md. Read ${HOME}/.claude/liang-tdd/references/prompts/task-manager.md for your full prompt template. Read schemas: ${HOME}/.claude/liang-tdd/references/schemas/tasks.md, ${HOME}/.claude/liang-tdd/references/schemas/test-list.md, ${HOME}/.claude/liang-tdd/references/schemas/progress.md." \
      >> "$LOG_FILE" 2>&1

    if [[ ! -f "${abs_mission}/TASKS.md" ]]; then
      fail "Task Manager failed to produce TASKS.md"
      notify "TDD Runner" "Task Manager failed — check $LOG_FILE"
      exit 1
    fi
    ok "Phase 2 complete: TASKS.md created"
  fi
}

# --- Get pending tasks from PROGRESS.md ---
get_pending_tasks() {
  local progress_file="${PROJECT_ROOT}/${MISSION_DIR}/PROGRESS.md"
  if [[ ! -f "$progress_file" ]]; then
    echo ""
    return
  fi
  grep -oP '\|\s*(\d+-[a-z0-9-]+)\s*\|\s*(pending|in_progress)' "$progress_file" \
    | grep -oP '\d+-[a-z0-9-]+' || true
}

# --- Parse TASKS.md into parallel groups ---
# Returns JSON: {"1": ["01-foo", "02-bar"], "2": ["03-baz"]}
# Returns {} if TASKS.md missing or has no group info
get_task_groups_json() {
  local tasks_file="${PROJECT_ROOT}/${MISSION_DIR}/TASKS.md"
  if [[ ! -f "$tasks_file" ]]; then
    echo "{}"
    return
  fi

  node -e "
    const fs = require('fs');
    const content = fs.readFileSync('${tasks_file}', 'utf8');
    const groups = {};
    let currentTask = null;
    for (const line of content.split('\n')) {
      const taskMatch = line.match(/^### (\d+-[\w-]+)/);
      if (taskMatch) currentTask = taskMatch[1];
      const groupMatch = line.match(/\*\*Parallel group:\*\*\s*(\d+)/);
      if (groupMatch && currentTask) {
        const g = groupMatch[1];
        if (!groups[g]) groups[g] = [];
        if (!groups[g].includes(currentTask)) groups[g].push(currentTask);
      }
    }
    console.log(JSON.stringify(groups));
  " 2>/dev/null || echo "{}"
}

# --- Update task status in PROGRESS.md ---
update_progress() {
  local task_id="$1"
  local status="$2"
  local notes="${3:-}"
  local progress_file="${PROJECT_ROOT}/${MISSION_DIR}/PROGRESS.md"
  if [[ -f "$progress_file" ]]; then
    sed -i "s/|\s*${task_id}\s*|\s*[a-z_]*\s*/| ${task_id} | ${status} /" "$progress_file"
  fi
  echo "$(date -Iseconds) — Task ${task_id}: ${status} ${notes}" >> "$LOG_FILE"
}

# --- Run planner for a task ---
run_planner() {
  local task_id="$1"
  local abs_task_dir="${PROJECT_ROOT}/${MISSION_DIR}/tasks/${task_id}"

  if [[ -f "${abs_task_dir}/PLAN.md" ]]; then
    log "Plan already exists for $task_id, skipping planner"
    return 0
  fi

  log "Planning $task_id (model: $PLAN_MODEL)..."
  claude -p --model "$PLAN_MODEL" \
    --max-turns 20 \
    --allowedTools Read,Write,Glob,Grep \
    "You are the Planner for task $task_id in a solo TDD workflow. Read your full prompt template from ${HOME}/.claude/liang-tdd/references/prompts/planner.md. Read the plan schema from ${HOME}/.claude/liang-tdd/references/schemas/plan.md. Read the test list at ${abs_task_dir}/TEST_LIST.md. List ${PROJECT_ROOT}/.claude/skills/ and read relevant skills. Write the execution plan to ${abs_task_dir}/PLAN.md." \
    >> "$LOG_FILE" 2>&1

  [[ -f "${abs_task_dir}/PLAN.md" ]]
}

# --- Run executor for a task (from PROJECT_ROOT, not from inside worktree) ---
run_executor() {
  local task_id="$1"
  local abs_task_dir="${PROJECT_ROOT}/${MISSION_DIR}/tasks/${task_id}"
  local abs_worktree="${PROJECT_ROOT}/.worktrees/task-${task_id}"

  # Setup worktree (git or plain copy)
  if git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -d "$abs_worktree" ]]; then
      log "Worktree exists for $task_id, reusing"
    else
      git -C "${PROJECT_ROOT}" worktree add "$abs_worktree" -b "vibe/task-$task_id" 2>> "$LOG_FILE" || {
        git -C "${PROJECT_ROOT}" worktree add "$abs_worktree" "vibe/task-$task_id" 2>> "$LOG_FILE" || {
          warn "Worktree setup failed, using direct directory"
          mkdir -p "$abs_worktree"
        }
      }
    fi
  else
    mkdir -p "$abs_worktree"
  fi

  log "Executing $task_id (model: $EXEC_MODEL, max_turns: $MAX_TURNS)..."
  # Runs from PROJECT_ROOT. Executor navigates into the worktree via Bash commands internally.
  claude -p --model "$EXEC_MODEL" \
    --max-turns "$MAX_TURNS" \
    --allowedTools Edit,Write,Bash,Read,Glob,Grep \
    "You are a code executor in a solo TDD workflow. Read your full prompt template from ${HOME}/.claude/liang-tdd/references/prompts/executor.md. Read the plan at ${abs_task_dir}/PLAN.md and the test list at ${abs_task_dir}/TEST_LIST.md. Your isolated worktree is at ${abs_worktree}/. Use 'cd ${abs_worktree}' in Bash tool calls when running tests or builds that require the worktree context. Create test dirs: mkdir -p ${abs_task_dir}/tests/.snapshots. Follow vertical-slice TDD: one test at a time through RED -> GREEN -> BLUE cycles. When all tests pass, commit from within the worktree with: cd ${abs_worktree} && git add -A && git commit -m 'feat(vibe): $task_id'" \
    >> "$LOG_FILE" 2>&1
}

# --- Run QA verifier for a task ---
run_qa() {
  local task_id="$1"
  local abs_task_dir="${PROJECT_ROOT}/${MISSION_DIR}/tasks/${task_id}"
  local abs_worktree="${PROJECT_ROOT}/.worktrees/task-${task_id}"

  log "QA verifying $task_id..."
  claude -p --model "$EXEC_MODEL" \
    --max-turns 20 \
    --allowedTools Read,Bash,Glob,Grep,Write \
    "You are a QA verifier in a solo TDD workflow. Read your full prompt template from ${HOME}/.claude/liang-tdd/references/prompts/qa-verifier.md. Read the QA report schema from ${HOME}/.claude/liang-tdd/references/schemas/qa-report.md. The work is in: ${abs_worktree}/. The test list is at ${abs_task_dir}/TEST_LIST.md. Run all tests (cd into ${abs_worktree} first), check tamper detection against RED snapshots, verify coverage. Write report to ${abs_task_dir}/QA_REPORT.md." \
    >> "$LOG_FILE" 2>&1

  if [[ -f "${abs_task_dir}/QA_REPORT.md" ]]; then
    grep -qi "Overall.*PASS" "${abs_task_dir}/QA_REPORT.md" && return 0
  fi
  return 1
}

# --- Diagnose QA failure (every failure) ---
run_debugger() {
  local task_id="$1"
  local iteration="$2"
  local abs_task_dir="${PROJECT_ROOT}/${MISSION_DIR}/tasks/${task_id}"
  local abs_worktree="${PROJECT_ROOT}/.worktrees/task-${task_id}"

  log "Diagnosing $task_id failure (iteration $iteration)..."
  claude -p --model "$EXEC_MODEL" \
    --max-turns 15 \
    --allowedTools Read,Bash,Glob,Grep,Write \
    "You are a debugger for a TDD workflow. Read your full prompt from ${HOME}/.claude/liang-tdd/references/prompts/debugger.md (if exists) or follow these instructions: Diagnose why tests failed for task $task_id. Read the QA report at ${abs_task_dir}/QA_REPORT-v${iteration}.md. Read the plan at ${abs_task_dir}/PLAN-v${iteration}.md. Read test scripts and implementation in ${abs_worktree}/. Read ${HOME}/.claude/liang-tdd/references/schemas/debug.md for the output format. Form hypotheses, test them with evidence, and write your diagnosis to ${abs_task_dir}/DEBUG.md. Do NOT fix anything — only diagnose." \
    >> "$LOG_FILE" 2>&1
  ok "Diagnosis complete for $task_id iteration $iteration"
}

# --- Run online research (triggered on 2nd+ QA failure or inconclusive diagnosis) ---
run_research() {
  local task_id="$1"
  local iteration="$2"
  local abs_task_dir="${PROJECT_ROOT}/${MISSION_DIR}/tasks/${task_id}"

  log "Researching solutions for $task_id (iteration $iteration)..."
  claude -p --model "$PLAN_MODEL" \
    --max-turns 15 \
    --allowedTools Read,Write,WebSearch,WebFetch \
    "You are a QA failure researcher for a TDD workflow. Read the QA report at ${abs_task_dir}/QA_REPORT-v${iteration}.md and the diagnosis at ${abs_task_dir}/DEBUG.md to understand what failed and why. Focus searches on the diagnosed root cause. Avoid searching for hypotheses already eliminated in DEBUG.md. Save your findings to ${abs_task_dir}/RESEARCH-${iteration}.md following the schema from ${HOME}/.claude/liang-tdd/references/schemas/research.md." \
    >> "$LOG_FILE" 2>&1
  ok "Research complete for $task_id iteration $iteration"
}

# --- Re-plan a task after QA failure ---
replan_task() {
  local task_id="$1"
  local iteration="$2"
  local abs_task_dir="${PROJECT_ROOT}/${MISSION_DIR}/tasks/${task_id}"
  local research_context=""
  local debug_context=""

  if [[ -f "${abs_task_dir}/DEBUG.md" ]]; then
    debug_context="Read the debugger's diagnosis at ${abs_task_dir}/DEBUG.md FIRST — it contains root cause analysis, eliminated hypotheses (do NOT retry these), and recommended fix direction."
  fi

  if [[ $iteration -ge 2 && -f "${abs_task_dir}/RESEARCH-${iteration}.md" ]]; then
    research_context="Also read the online research findings at ${abs_task_dir}/RESEARCH-${iteration}.md and incorporate its solutions into your new plan."
  fi

  log "Re-planning $task_id (iteration $iteration)..."
  claude -p --model "$PLAN_MODEL" \
    --max-turns 20 \
    --allowedTools Read,Write,Glob,Grep \
    "You are the Planner for task $task_id (re-plan after QA failure, iteration $iteration). Read ${HOME}/.claude/liang-tdd/references/prompts/planner.md for your template. Read the plan schema from ${HOME}/.claude/liang-tdd/references/schemas/plan.md. ${debug_context} Previous plan: ${abs_task_dir}/PLAN-v${iteration}.md. QA report: ${abs_task_dir}/QA_REPORT-v${iteration}.md. Address each failing test specifically. ${research_context} Write the new plan to ${abs_task_dir}/PLAN.md." \
    >> "$LOG_FILE" 2>&1
}

# --- QA + retry loop for one task ---
# Called after executor has already run once (sequential) or after parallel executors complete
qa_and_retry_task() {
  local task_id="$1"
  local abs_task_dir="${PROJECT_ROOT}/${MISSION_DIR}/tasks/${task_id}"
  local retries=0
  local passed=false

  while [[ $retries -lt $MAX_RETRIES ]]; do
    if run_qa "$task_id"; then
      passed=true
      break
    fi

    retries=$((retries + 1))
    warn "QA failed for $task_id (attempt $retries/$MAX_RETRIES)"

    if [[ $retries -lt $MAX_RETRIES ]]; then
      # Version artifacts for re-plan
      [[ -f "${abs_task_dir}/PLAN.md" ]] && mv "${abs_task_dir}/PLAN.md" "${abs_task_dir}/PLAN-v${retries}.md"
      [[ -f "${abs_task_dir}/QA_REPORT.md" ]] && mv "${abs_task_dir}/QA_REPORT.md" "${abs_task_dir}/QA_REPORT-v${retries}.md"

      # Diagnose every failure
      run_debugger "$task_id" "$retries"

      cleanup_worktree "$task_id"

      # Research on 2nd+ failure or inconclusive diagnosis
      if [[ $retries -ge 2 ]] || grep -qi "inconclusive" "${abs_task_dir}/DEBUG.md" 2>/dev/null; then
        run_research "$task_id" "$retries"
      fi

      replan_task "$task_id" "$retries"
      run_executor "$task_id"
    fi
  done

  if $passed; then
    ok "Task $task_id: PASS"
    update_progress "$task_id" "passed"
    merge_worktree "$task_id"
    CONSECUTIVE_FAILS=0
  else
    fail "Task $task_id: FAIL (exhausted $MAX_RETRIES retries)"
    update_progress "$task_id" "failed" "(max retries)"
    cleanup_worktree "$task_id"
    CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
  fi
}

# --- Process a single task: plan → execute → QA+retry ---
process_task() {
  local task_id="$1"

  log "━━━ Task $task_id [$((COMPLETED + 1))/$TOTAL_TASKS] ━━━"
  update_progress "$task_id" "in_progress"

  if ! run_planner "$task_id"; then
    fail "Planner failed for $task_id"
    update_progress "$task_id" "failed" "(planner failed)"
    CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
    COMPLETED=$((COMPLETED + 1))
    log "Progress: $COMPLETED/$TOTAL_TASKS"
    return
  fi

  run_executor "$task_id"
  qa_and_retry_task "$task_id"

  COMPLETED=$((COMPLETED + 1))
  log "Progress: $COMPLETED/$TOTAL_TASKS"
}

# --- Process a parallel group: plan all → execute all (parallel) → QA+retry each ---
process_parallel_group() {
  local group_num="$1"
  shift
  local group_tasks=("$@")

  log "━━━ Parallel Group $group_num: ${group_tasks[*]} [tasks $((COMPLETED + 1))-$((COMPLETED + ${#group_tasks[@]}))/$TOTAL_TASKS] ━━━"

  # Step 1: Plan all tasks sequentially (planning is fast, benefits from sequential context)
  local planned_tasks=()
  for task_id in "${group_tasks[@]}"; do
    update_progress "$task_id" "in_progress"
    if run_planner "$task_id"; then
      planned_tasks+=("$task_id")
    else
      fail "Planner failed for $task_id"
      update_progress "$task_id" "failed" "(planner failed)"
      CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
      COMPLETED=$((COMPLETED + 1))
    fi
  done

  if [[ ${#planned_tasks[@]} -eq 0 ]]; then return; fi

  # Step 2: Launch all executors in parallel (background)
  declare -A exec_pids
  for task_id in "${planned_tasks[@]}"; do
    log "Launching executor for $task_id in background..."
    run_executor "$task_id" &
    exec_pids[$task_id]=$!
  done

  # Step 3: Wait for all executors to complete
  log "Waiting for ${#planned_tasks[@]} parallel executors..."
  for task_id in "${planned_tasks[@]}"; do
    wait "${exec_pids[$task_id]}" || true
    log "Executor done: $task_id"
  done

  # Step 4: Run QA + retry for each task sequentially (avoids merge conflicts)
  for task_id in "${planned_tasks[@]}"; do
    qa_and_retry_task "$task_id"
    COMPLETED=$((COMPLETED + 1))
    log "Progress: $COMPLETED/$TOTAL_TASKS"
  done
}

# --- Merge worktree back into main branch ---
merge_worktree() {
  local task_id="$1"
  local abs_worktree="${PROJECT_ROOT}/.worktrees/task-${task_id}"

  if git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${PROJECT_ROOT}" merge "vibe/task-$task_id" --no-edit >> "$LOG_FILE" 2>&1 && \
    git -C "${PROJECT_ROOT}" worktree remove "$abs_worktree" >> "$LOG_FILE" 2>&1 && \
    git -C "${PROJECT_ROOT}" branch -d "vibe/task-$task_id" >> "$LOG_FILE" 2>&1 && \
    ok "Merged and cleaned worktree for $task_id"
  else
    cp -r "${abs_worktree}"/* "${PROJECT_ROOT}/." 2>/dev/null || true
    rm -rf "$abs_worktree"
    ok "Copied files back from $task_id worktree"
  fi
}

# --- Remove worktree without merging (on failure) ---
cleanup_worktree() {
  local task_id="$1"
  local abs_worktree="${PROJECT_ROOT}/.worktrees/task-${task_id}"

  if git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${PROJECT_ROOT}" worktree remove "$abs_worktree" --force >> "$LOG_FILE" 2>&1 || true
    git -C "${PROJECT_ROOT}" branch -D "vibe/task-$task_id" >> "$LOG_FILE" 2>&1 || true
  else
    rm -rf "$abs_worktree" 2>/dev/null || true
  fi
}

# ============================================================
# MAIN
# ============================================================

install_hook
setup_autonomous

# Verify we have tasks
if [[ ! -f "${PROJECT_ROOT}/${MISSION_DIR}/TASKS.md" ]]; then
  fail "No TASKS.md found. Run Phases 1-2 interactively first, or use --prompt-file."
  exit 1
fi

PENDING_TASKS=$(get_pending_tasks)
TOTAL_TASKS=$(echo "$PENDING_TASKS" | grep -c '\S' || echo "0")
COMPLETED=0

log "Starting execution: $TOTAL_TASKS tasks pending"
notify "TDD Runner" "Starting $TOTAL_TASKS tasks in $(basename "$MISSION_DIR")"

# --- Route tasks: parallel groups or sequential ---
GROUPS_JSON=$(get_task_groups_json)
HAS_GROUPS=$(node -e "
  const g = JSON.parse('$(echo "$GROUPS_JSON" | sed "s/'/\\\\'/g")');
  const anyMulti = Object.values(g).some(arr => arr.length > 1);
  console.log(Object.keys(g).length > 0 && anyMulti ? 'yes' : 'no');
" 2>/dev/null || echo "no")

if [[ "$HAS_GROUPS" == "yes" ]]; then
  log "Parallel groups detected — using group-based execution"

  # Get sorted group numbers
  GROUP_NUMS=$(node -e "
    const g = JSON.parse('$(echo "$GROUPS_JSON" | sed "s/'/\\\\'/g")');
    Object.keys(g).sort((a,b) => parseInt(a) - parseInt(b)).forEach(k => console.log(k));
  ")

  for GROUP_NUM in $GROUP_NUMS; do
    # Get tasks in this group that are still pending
    GROUP_TASKS=()
    PENDING=$(get_pending_tasks)
    while IFS= read -r task_id; do
      [[ -z "$task_id" ]] && continue
      IN_GROUP=$(node -e "
        const g = JSON.parse('$(echo "$GROUPS_JSON" | sed "s/'/\\\\'/g")');
        const group = g['${GROUP_NUM}'] || [];
        console.log(group.includes('${task_id}') ? 'yes' : 'no');
      " 2>/dev/null || echo "no")
      if [[ "$IN_GROUP" == "yes" ]]; then
        GROUP_TASKS+=("$task_id")
      fi
    done <<< "$PENDING"

    [[ ${#GROUP_TASKS[@]} -eq 0 ]] && continue

    if [[ ${#GROUP_TASKS[@]} -eq 1 ]]; then
      process_task "${GROUP_TASKS[0]}"
    else
      process_parallel_group "$GROUP_NUM" "${GROUP_TASKS[@]}"
    fi

    if [[ $CONSECUTIVE_FAILS -ge $STOP_ON_FAIL ]]; then
      fail "Aborting: $CONSECUTIVE_FAILS consecutive failures"
      break
    fi
  done

else
  log "No parallel groups detected — sequential execution"

  while IFS= read -r TASK_ID; do
    [[ -z "$TASK_ID" ]] && continue
    process_task "$TASK_ID"
    if [[ $CONSECUTIVE_FAILS -ge $STOP_ON_FAIL ]]; then
      fail "Aborting: $CONSECUTIVE_FAILS consecutive failures"
      break
    fi
  done <<< "$PENDING_TASKS"
fi

# --- Final report ---
log "Generating final report..."
claude -p --model "$PLAN_MODEL" \
  --max-turns 10 \
  --allowedTools Read,Write,Glob,Grep \
  "Read ${PROJECT_ROOT}/${MISSION_DIR}/PROGRESS.md and all QA_REPORT.md files under ${PROJECT_ROOT}/${MISSION_DIR}/tasks/. Read the FINAL_REPORT.md schema from ${HOME}/.claude/liang-tdd/references/schemas/final-report.md. Generate ${PROJECT_ROOT}/${MISSION_DIR}/FINAL_REPORT.md." \
  >> "$LOG_FILE" 2>&1

# --- Cleanup hook ---
uninstall_hook

PASSED_COUNT=$(grep -c "passed" "${PROJECT_ROOT}/${MISSION_DIR}/PROGRESS.md" 2>/dev/null || echo "0")
FAILED_COUNT=$(grep -c "failed" "${PROJECT_ROOT}/${MISSION_DIR}/PROGRESS.md" 2>/dev/null || echo "0")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Mission complete: $(basename "$MISSION_DIR")"
echo "  Passed: $PASSED_COUNT  Failed: $FAILED_COUNT"
echo "  Report: ${PROJECT_ROOT}/${MISSION_DIR}/FINAL_REPORT.md"
echo "  Log: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "--- Runner finished $(date -Iseconds) ---" >> "$LOG_FILE"

notify "TDD Runner" "Done: $PASSED_COUNT passed, $FAILED_COUNT failed — $(basename "$MISSION_DIR")"
