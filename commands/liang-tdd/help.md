---
name: liang-tdd:help
description: Show available /liang-tdd commands and usage guide
---

<objective>
Display the complete /liang-tdd command reference.

Output ONLY the reference content below. Do NOT add:
- Project-specific analysis
- Git status or file context
- Next-step suggestions
- Any commentary beyond the reference
</objective>

<process>
Output the following reference directly:

# /liang-tdd — Vertical-Slice TDD Workflow

A structured workflow that turns a vague idea into verified, tested code through
five phases: Brainstorm → Task Decomposition → Plan → Execute (RED→GREEN→BLUE) → QA.

## Commands

```
/liang-tdd:add-mission [--no-limit] "topic"    Start a new mission
/liang-tdd:resume-mission [--auto] [--no-limit] [number]
                                                Resume a mission (or auto-detect latest)
/liang-tdd:progress [number]                    Show mission progress and next action
/liang-tdd:help                                 Show this help
```

## Runner (Overnight Mode)

```bash
# Default: Phases 3-5 only (requires TASKS.md from interactive Phases 1-2)
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh .planning/vibe/003-my-feature

# --auto: Fully autonomous Phases 1-5 (spec file → BRAINSTORM → TASKS → execute)
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh --auto \
  --prompt-file spec.md --mission-name my-feature

# With custom limits
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh .planning/vibe/003-my-feature \
  --max-turns 100 --max-retries 5
```

The runner spawns fresh Claude sessions per task — no context degradation.
Sends a Windows notification when done.

## Flags

```
--no-limit    Disable the 8/10 confidence gate in brainstorming.
              The brainstormer keeps asking questions until you say "stop".
              Works on: add-mission, resume-mission (when in Phase 1)

--auto        Task Manager auto-accepts all tasks without walking through
              each TEST_LIST for approval. Other phases unaffected.
              Works on: resume-mission
```

## Workflow Phases

```
Phase 1: Brainstorm    — Upfront research on your topic, then Socratic questioning with research-backed
                         recommendations shown as AskUserQuestion options (8/10 confidence gate)
                         Runs INLINE in main session (not a subagent) for AskUserQuestion support
Phase 2: Task Manager  — Break work into tasks, each with a TEST_LIST.md (ordered bash test scripts)
Phase 3: Planner       — Write per-test-cycle execution plan (RED→GREEN→BLUE steps for each test)
Phase 4: Executor      — Sonnet runs in isolated worktree, follows vertical-slice TDD:
                         Write test (RED) → snapshot → implement (GREEN) → refactor (BLUE) → next
Phase 5: QA Verifier   — Runs all test scripts + checks RED snapshots for tamper detection
```

Phases 3-5 loop per task: if QA fails, it re-plans with full context (up to 10 iterations).
On 2nd+ QA failure, online research is triggered to help the planner find better solutions.

## Vertical-Slice TDD (the core discipline)

The executor works through tests ONE AT A TIME:

```
For each test in TEST_LIST.md:
  RED:        Write test script → run → confirm FAILS
  SNAPSHOT:   Copy test to .snapshots/ (tamper detection baseline)
  GREEN:      Write minimal implementation → run → confirm PASSES
  REGRESSION: Re-run ALL previous tests
  BLUE:       Refactor if needed → re-run all tests
  → Next test
```

Key rules:
- NEVER write implementation without a failing test first
- NEVER modify a test after its RED snapshot — fix the implementation instead
- NEVER write multiple tests at once — one test per cycle
- Tests are bash scripts (language-agnostic, zero dependencies)

## Mission System

Every workflow run is a **mission** — a named, numbered container for all artifacts.
Missions live under `.planning/vibe/` with a 3-digit prefix:

```
.planning/vibe/
├── 001-receipt-scanner/
│   ├── BRAINSTORM.md
│   ├── TASKS.md
│   ├── PROGRESS.md
│   ├── FINAL_REPORT.md
│   └── tasks/
│       └── 01-ocr-setup/
│           ├── TEST_LIST.md       (ordered test behaviors + bash scripts)
│           ├── PLAN.md            (per-test RED→GREEN→BLUE cycle steps)
│           ├── QA_REPORT.md       (test results + tamper check + coverage)
│           ├── RESEARCH-2.md      (on 2nd+ QA failure)
│           └── tests/
│               ├── test-01-file-exists.sh
│               ├── test-02-output.sh
│               └── .snapshots/
│                   ├── RED-test-01-file-exists.sh
│                   └── RED-test-02-output.sh
```

## Model Routing

| Agent | Model | Why |
|-------|-------|-----|
| Brainstormer | Opus (inline) | Needs AskUserQuestion for Socratic questioning |
| Task Manager | Opus (subagent) | Needs judgment for task decomposition + test design |
| Planner | Opus (subagent) | Needs depth for unambiguous per-cycle plans |
| Executor | Sonnet (CLI) | Follows plan literally, runs vertical-slice TDD in worktree |
| QA Verifier | Sonnet (CLI) | Runs tests, checks snapshots, verifies coverage |

## Key Concepts

**Mission** — A named container (e.g., `001-receipt-scanner`) for one full
brainstorm→execute cycle. Multiple missions can coexist.

**TEST_LIST.md** — The TDD spec. An ordered list of behaviors with bash test
scripts. Written before any code. Tests go from simplest to most complex.

**RED Snapshot** — A copy of each test script made immediately after writing it
(before implementation). QA diffs against snapshots to detect test tampering.

**Vertical Slicing** — One test at a time through RED→GREEN→BLUE. Never write
all tests first, never implement without a failing test.

**Parallel Groups** — Independent tasks get the same group number and run
concurrently in separate worktrees. Tasks sharing files are sequential.

**VCS-Agnostic** — Checkpoints use file snapshots, not git commits. Works
with git, Perforce, or no version control.

**QA Failure Research** — On 2nd+ QA failure, online research is triggered.
Findings are saved and fed to the planner for better re-plans.

**Confidence Gate** — Phase 1 blocks until the brainstormer rates understanding
at 8/10 or higher. Use `--no-limit` to disable and keep brainstorming until
you say "stop".

**Context Clearing Gates** — Optional conversation clearing offered before
Task Manager and each Planner to keep context fresh. Progress is always saved.

**Max Iterations** — A task that fails QA 10 times is marked `failed` and
skipped. Something fundamental is wrong — fix it manually.

## Tips

- Be generous during brainstorming. The more context you give, the better
  the task decomposition and test lists will be.
- Review every TEST_LIST carefully. Bad tests = bad QA = wasted iterations.
- Tests should verify OUTCOMES, not implementation details. Think "what does
  the user see?" not "what does the code look like internally?"
- If a task keeps failing QA, check whether the tests are realistic before
  blaming the executor.
- Use `/liang-tdd:progress` to see where your mission stands.
- Take advantage of context clearing gates — fresh context = better planning.
- The final report includes TDD discipline metrics — use them to improve.
- For overnight runs, do Phases 1-2 during the day, then use `tdd-runner.sh`
  to execute Phases 3-5 autonomously while you sleep.
- You can switch between interactive and runner mode mid-mission — both
  read/write the same PROGRESS.md.
</process>
