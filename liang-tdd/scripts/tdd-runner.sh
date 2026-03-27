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
#   - Project working directory as CWD

set -euo pipefail

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
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()  { echo -e "${CYAN}[runner]${NC} $*"; }
ok()   { echo -e "${GREEN}[  OK  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
fail() { echo -e "${RED}[ FAIL ]${NC} $*"; }

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
  # Fully autonomous: create new mission
  if [[ -z "$MISSION_NAME" ]]; then
    echo "Error: --mission-name required with --prompt-file when no mission-dir given"
    exit 1
  fi
  # Find next mission index
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

if [[ ! -d "$MISSION_DIR" ]]; then
  echo "Error: Mission directory not found: $MISSION_DIR"
  exit 1
fi

LOG_FILE="${MISSION_DIR}/runner.log"
log "Mission: $MISSION_DIR"
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
install_hook() {
  local SETTINGS=".claude/settings.local.json"
  mkdir -p .claude

  if [[ -f "$SETTINGS" ]]; then
    # Check if hook already installed
    if grep -q "tdd-test-guard" "$SETTINGS" 2>/dev/null; then
      log "Test guard hook already installed"
      return
    fi
    # Merge hook into existing settings using node
    node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync('$SETTINGS', 'utf8'));
      if (!s.hooks) s.hooks = {};
      if (!s.hooks.PreToolUse) s.hooks.PreToolUse = [];
      s.hooks.PreToolUse.push({
        matcher: 'Write|Edit',
        hooks: [{
          type: 'command',
          command: 'node \"C:/Users/Liang/.claude/hooks/tdd-test-guard.js\"',
          timeout: 5
        }]
      });
      fs.writeFileSync('$SETTINGS', JSON.stringify(s, null, 2));
    "
  else
    # Create fresh settings with hook
    cat > "$SETTINGS" << 'HOOKJSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "node \"C:/Users/Liang/.claude/hooks/tdd-test-guard.js\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
HOOKJSON
  fi
  ok "Test guard hook installed"
}

# --- Uninstall tdd-test-guard hook ---
uninstall_hook() {
  local SETTINGS=".claude/settings.local.json"
  if [[ ! -f "$SETTINGS" ]]; then return; fi

  node -e "
    const fs = require('fs');
    const s = JSON.parse(fs.readFileSync('$SETTINGS', 'utf8'));
    if (s.hooks && s.hooks.PreToolUse) {
      s.hooks.PreToolUse = s.hooks.PreToolUse.filter(
        e => !JSON.stringify(e).includes('tdd-test-guard')
      );
      if (s.hooks.PreToolUse.length === 0) delete s.hooks.PreToolUse;
      if (Object.keys(s.hooks).length === 0) delete s.hooks;
    }
    fs.writeFileSync('$SETTINGS', JSON.stringify(s, null, 2));
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

  # Phase 1: Prompt file becomes BRAINSTORM.md (if provided)
  if [[ ! -f "$MISSION_DIR/BRAINSTORM.md" ]]; then
    if [[ -n "$PROMPT_FILE" ]]; then
      log "Phase 1: Using $PROMPT_FILE as BRAINSTORM.md"
      cp "$PROMPT_FILE" "$MISSION_DIR/BRAINSTORM.md"
      ok "BRAINSTORM.md created from prompt file"
    else
      fail "No BRAINSTORM.md and no --prompt-file provided"
      exit 1
    fi
  fi

  # Phase 2: Task Manager (auto-accept)
  if [[ ! -f "$MISSION_DIR/TASKS.md" ]]; then
    log "Phase 2: Spawning Task Manager (--auto mode)..."
    claude -p --model "$PLAN_MODEL" \
      --max-turns 30 \
      --allowedTools Read,Write,Glob,Grep \
      "You are the Task Manager for a solo TDD workflow. Read $MISSION_DIR/BRAINSTORM.md and decompose it into tasks. For each task, create $MISSION_DIR/tasks/{NN}-{slug}/TEST_LIST.md with ordered bash test scripts. Auto-accept all tasks (--auto mode). Save task index to $MISSION_DIR/TASKS.md and initialize $MISSION_DIR/PROGRESS.md. Read ~/.claude/liang-tdd/references/agent-prompts.md section 'Task Manager' for your full prompt template and ~/.claude/liang-tdd/references/artifact-schemas.md for output schemas." \
      >> "$LOG_FILE" 2>&1

    if [[ ! -f "$MISSION_DIR/TASKS.md" ]]; then
      fail "Task Manager failed to produce TASKS.md"
      notify "TDD Runner" "Task Manager failed — check $LOG_FILE"
      exit 1
    fi
    ok "Phase 2 complete: TASKS.md created"
  fi
}

# --- Get pending tasks from PROGRESS.md ---
get_pending_tasks() {
  if [[ ! -f "$MISSION_DIR/PROGRESS.md" ]]; then
    echo ""
    return
  fi
  # Extract task IDs with "pending" or "in_progress" status
  grep -oP '\|\s*(\d+-[a-z0-9-]+)\s*\|\s*(pending|in_progress)' "$MISSION_DIR/PROGRESS.md" \
    | grep -oP '\d+-[a-z0-9-]+' || true
}

# --- Update task status in PROGRESS.md ---
update_progress() {
  local task_id="$1"
  local status="$2"
  local notes="${3:-}"
  if [[ -f "$MISSION_DIR/PROGRESS.md" ]]; then
    # Use sed to update the task row
    sed -i "s/|\s*${task_id}\s*|\s*[a-z_]*\s*/| ${task_id} | ${status} /" "$MISSION_DIR/PROGRESS.md"
  fi
  echo "$(date -Iseconds) — Task ${task_id}: ${status} ${notes}" >> "$LOG_FILE"
}

# --- Run planner for a task ---
run_planner() {
  local task_id="$1"
  local task_dir="$MISSION_DIR/tasks/$task_id"

  if [[ -f "$task_dir/PLAN.md" ]]; then
    log "Plan already exists for $task_id, skipping planner"
    return 0
  fi

  log "Planning $task_id (model: $PLAN_MODEL)..."
  claude -p --model "$PLAN_MODEL" \
    --max-turns 20 \
    --allowedTools Read,Write,Glob,Grep \
    "You are the Planner for task $task_id in a solo TDD workflow. Read your full prompt template from ~/.claude/liang-tdd/references/agent-prompts.md section 'Planner'. Read the test list at $task_dir/TEST_LIST.md. Read artifact schemas from ~/.claude/liang-tdd/references/artifact-schemas.md. List .claude/skills/ and read relevant skills. Write the execution plan to $task_dir/PLAN.md." \
    >> "$LOG_FILE" 2>&1

  [[ -f "$task_dir/PLAN.md" ]]
}

# --- Run executor for a task ---
run_executor() {
  local task_id="$1"
  local task_dir="$MISSION_DIR/tasks/$task_id"
  local worktree=".worktrees/task-$task_id"

  # Setup worktree (git or plain copy)
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -d "$worktree" ]]; then
      log "Worktree exists for $task_id, reusing"
    else
      git worktree add "$worktree" -b "vibe/task-$task_id" 2>> "$LOG_FILE" || {
        # Branch may exist from previous failed run
        git worktree add "$worktree" "vibe/task-$task_id" 2>> "$LOG_FILE" || {
          warn "Worktree setup failed, using direct directory"
          mkdir -p "$worktree"
        }
      }
    fi
  else
    mkdir -p "$worktree"
  fi

  log "Executing $task_id (model: $EXEC_MODEL, max_turns: $MAX_TURNS)..."
  cd "$worktree" 2>/dev/null || true

  claude -p --model "$EXEC_MODEL" \
    --max-turns "$MAX_TURNS" \
    --allowedTools Edit,Write,Bash,Read,Glob,Grep \
    "You are a code executor in a solo TDD workflow. Read your full prompt template from ~/.claude/liang-tdd/references/agent-prompts.md section 'Executor'. Read the plan at $task_dir/PLAN.md and the test list at $task_dir/TEST_LIST.md. Follow vertical-slice TDD: one test at a time through RED -> GREEN -> BLUE cycles. Create test dirs: mkdir -p $task_dir/tests/.snapshots. Work in this worktree. Commit when all tests pass with message: feat(vibe): $task_id" \
    >> "../../$LOG_FILE" 2>&1

  cd - >/dev/null 2>&1 || true
}

# --- Run QA verifier for a task ---
run_qa() {
  local task_id="$1"
  local task_dir="$MISSION_DIR/tasks/$task_id"

  log "QA verifying $task_id..."
  claude -p --model "$EXEC_MODEL" \
    --max-turns 20 \
    --allowedTools Read,Bash,Glob,Grep,Write \
    "You are a QA verifier in a solo TDD workflow. Read your full prompt template from ~/.claude/liang-tdd/references/agent-prompts.md section 'QA Verifier'. Read artifact schemas from ~/.claude/liang-tdd/references/artifact-schemas.md. The work is in: .worktrees/task-$task_id/. The test list is at $task_dir/TEST_LIST.md. Run all tests, check tamper detection against RED snapshots, verify coverage. Write report to $task_dir/QA_REPORT.md." \
    >> "$LOG_FILE" 2>&1

  # Check QA result
  if [[ -f "$task_dir/QA_REPORT.md" ]]; then
    grep -qi "Overall.*PASS" "$task_dir/QA_REPORT.md" && return 0
  fi
  return 1
}

# --- Merge worktree back ---
merge_worktree() {
  local task_id="$1"
  local worktree=".worktrees/task-$task_id"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local current_branch
    current_branch=$(git branch --show-current)
    git merge "vibe/task-$task_id" --no-edit >> "$LOG_FILE" 2>&1 && \
    git worktree remove "$worktree" >> "$LOG_FILE" 2>&1 && \
    git branch -d "vibe/task-$task_id" >> "$LOG_FILE" 2>&1 && \
    ok "Merged and cleaned worktree for $task_id"
  else
    # Non-git: copy files back
    cp -r "$worktree"/* . 2>/dev/null || true
    rm -rf "$worktree"
    ok "Copied files back from $task_id worktree"
  fi
}

# --- Cleanup worktree without merge ---
cleanup_worktree() {
  local task_id="$1"
  local worktree=".worktrees/task-$task_id"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git worktree remove "$worktree" --force >> "$LOG_FILE" 2>&1 || true
    git branch -D "vibe/task-$task_id" >> "$LOG_FILE" 2>&1 || true
  else
    rm -rf "$worktree" 2>/dev/null || true
  fi
}

# ============================================================
# MAIN
# ============================================================

install_hook
setup_autonomous

# Verify we have tasks
if [[ ! -f "$MISSION_DIR/TASKS.md" ]]; then
  fail "No TASKS.md found. Run Phases 1-2 interactively first, or use --prompt-file."
  exit 1
fi

TOTAL_TASKS=$(get_pending_tasks | wc -l)
COMPLETED=0

log "Starting execution: $TOTAL_TASKS tasks pending"
notify "TDD Runner" "Starting $TOTAL_TASKS tasks in $(basename "$MISSION_DIR")"

# --- Main loop: one task at a time ---
while IFS= read -r TASK_ID; do
  [[ -z "$TASK_ID" ]] && continue

  log "━━━ Task $TASK_ID [$((COMPLETED + 1))/$TOTAL_TASKS] ━━━"
  update_progress "$TASK_ID" "in_progress"

  # Phase 3: Plan
  if ! run_planner "$TASK_ID"; then
    fail "Planner failed for $TASK_ID"
    update_progress "$TASK_ID" "failed" "(planner failed)"
    CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
    if [[ $CONSECUTIVE_FAILS -ge $STOP_ON_FAIL ]]; then
      fail "Aborting: $CONSECUTIVE_FAILS consecutive failures"
      break
    fi
    continue
  fi

  # Phase 4-5: Execute + QA (with retry loop)
  RETRIES=0
  PASSED=false

  while [[ $RETRIES -lt $MAX_RETRIES ]]; do
    run_executor "$TASK_ID"

    if run_qa "$TASK_ID"; then
      PASSED=true
      break
    fi

    RETRIES=$((RETRIES + 1))
    warn "QA failed for $TASK_ID (attempt $RETRIES/$MAX_RETRIES)"

    if [[ $RETRIES -lt $MAX_RETRIES ]]; then
      # Version artifacts for re-plan
      TASK_DIR="$MISSION_DIR/tasks/$TASK_ID"
      [[ -f "$TASK_DIR/PLAN.md" ]] && mv "$TASK_DIR/PLAN.md" "$TASK_DIR/PLAN-v${RETRIES}.md"
      [[ -f "$TASK_DIR/QA_REPORT.md" ]] && mv "$TASK_DIR/QA_REPORT.md" "$TASK_DIR/QA_REPORT-v${RETRIES}.md"

      # Clean worktree for fresh attempt
      cleanup_worktree "$TASK_ID"

      # Re-plan with failure context
      log "Re-planning $TASK_ID with QA failure context..."
      claude -p --model "$PLAN_MODEL" \
        --max-turns 20 \
        --allowedTools Read,Write,Glob,Grep \
        "You are the Planner for task $TASK_ID (re-plan after QA failure). Read ~/.claude/liang-tdd/references/agent-prompts.md section 'Planner' for your template. Previous plan: $TASK_DIR/PLAN-v${RETRIES}.md. QA report: $TASK_DIR/QA_REPORT-v${RETRIES}.md. Read both. Address each failed test specifically. Write new plan to $TASK_DIR/PLAN.md." \
        >> "$LOG_FILE" 2>&1
    fi
  done

  if $PASSED; then
    ok "Task $TASK_ID: PASS"
    update_progress "$TASK_ID" "passed"
    merge_worktree "$TASK_ID"
    CONSECUTIVE_FAILS=0
  else
    fail "Task $TASK_ID: FAIL (exhausted $MAX_RETRIES retries)"
    update_progress "$TASK_ID" "failed" "(max retries)"
    cleanup_worktree "$TASK_ID"
    CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
    if [[ $CONSECUTIVE_FAILS -ge $STOP_ON_FAIL ]]; then
      fail "Aborting: $CONSECUTIVE_FAILS consecutive failures"
      break
    fi
  fi

  COMPLETED=$((COMPLETED + 1))
  log "Progress: $COMPLETED/$TOTAL_TASKS"

done < <(get_pending_tasks)

# --- Final report ---
log "Generating final report..."
claude -p --model "$PLAN_MODEL" \
  --max-turns 10 \
  --allowedTools Read,Write,Glob,Grep \
  "Read $MISSION_DIR/PROGRESS.md and all QA_REPORT.md files under $MISSION_DIR/tasks/. Read the FINAL_REPORT.md schema from ~/.claude/liang-tdd/references/artifact-schemas.md. Generate $MISSION_DIR/FINAL_REPORT.md." \
  >> "$LOG_FILE" 2>&1

# --- Cleanup ---
uninstall_hook

PASSED_COUNT=$(grep -c "passed" "$MISSION_DIR/PROGRESS.md" 2>/dev/null || echo "0")
FAILED_COUNT=$(grep -c "failed" "$MISSION_DIR/PROGRESS.md" 2>/dev/null || echo "0")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Mission complete: $(basename "$MISSION_DIR")"
echo "  Passed: $PASSED_COUNT  Failed: $FAILED_COUNT"
echo "  Report: $MISSION_DIR/FINAL_REPORT.md"
echo "  Log: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "--- Runner finished $(date -Iseconds) ---" >> "$LOG_FILE"

notify "TDD Runner" "Done: $PASSED_COUNT passed, $FAILED_COUNT failed — $(basename "$MISSION_DIR")"
