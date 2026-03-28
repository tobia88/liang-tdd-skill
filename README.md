# liang-tdd

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-blue)](https://docs.anthropic.com/en/docs/claude-code)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)

A vertical-slice TDD workflow skill for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that turns a vague idea into verified, tested code through five structured phases.

**Brainstorm** (Socratic questioning) **>** **Discuss** (architecture decisions) **>** **Decompose** (tasks + bash test specs) **>** **Plan** (per-test RED/GREEN/BLUE cycles) **>** **Execute** (isolated worktrees) **>** **QA** (tamper detection)

---

[Quick Start](#quick-start) | [Features](#features) | [Commands](#commands) | [How It Works](#how-it-works) | [Overnight Runner](#overnight-runner) | [Project Structure](#project-structure)

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/tobia88/liang-tdd-skill.git
cd liang-tdd-skill

# 2. Install (creates symlinks into ~/.claude/)
bash install.sh

# 3. Verify — in any Claude Code session:
/liang-tdd:help
```

To uninstall:

```bash
bash install.sh --uninstall
```

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and authenticated
- Git (for worktree-based isolated execution)
- Node.js (for the test guard hook)

## Features

- **Research-backed brainstorming** — Optional upfront web research informs every AskUserQuestion option, so decisions are data-driven instead of guesswork
- **Architecture discussion** — Phase 1.5 identifies gray areas, spawns parallel advisor agents to research alternatives, and captures explicit decisions before any code is written
- **Auto-advance by default** — After interactive brainstorming and discussion, the workflow auto-advances through task decomposition, planning, execution, and QA without pausing. Use `--manual` for the old interactive behavior with context clearing gates
- **Vertical-slice TDD** — One test at a time through RED > GREEN > BLUE. Never write implementation without a failing test first
- **Tamper detection** — RED snapshots catch any test modifications after the initial write. A PreToolUse hook enforces this at the tool level
- **Isolated execution** — Each task runs in its own git worktree. Failures can't corrupt your main branch
- **Todo system** — Capture ideas mid-session with `/liang-tdd:add-todo`, manage and promote to missions with `/liang-tdd:check-todos`
- **Overnight runner** — `tdd-runner.sh` spawns fresh Claude sessions per task, so context never degrades. Do brainstorming during the day, let it execute while you sleep
- **QA failure research** — On 2nd+ QA failure, automatic web research finds solutions and feeds them to the re-planner
- **Language-agnostic tests** — Tests are bash scripts that verify outcomes, not implementation details. Works for any language or framework
- **VCS-agnostic** — Uses file snapshots for checkpoints, not git commits. Works with git, Perforce, or no VCS

## Commands

| Command | Description |
|---------|-------------|
| `/liang-tdd:add-mission [--research] [--skip-discuss] "topic"` | Start a new mission and begin brainstorming |
| `/liang-tdd:resume-mission [--auto] [--research] [--skip-discuss] [number]` | Resume a mission from where it left off |
| `/liang-tdd:progress [number]` | Show mission status, task progress, and next action |
| `/liang-tdd:add-todo [description]` | Capture idea/task as todo (from text or conversation context) |
| `/liang-tdd:check-todos` | List pending todos — edit, delete, or promote to mission |
| `/liang-tdd:help` | Display the full command reference |

### Flags

| Flag | Works on | Effect |
|------|----------|--------|
| `--manual` | `add-mission`, `resume-mission` | Enable interactive mode with context clearing gates and task approval pauses |
| `--research` | `add-mission`, `resume-mission` | Run upfront web research before brainstorming to enrich questions |
| `--skip-discuss` | `add-mission`, `resume-mission` | Skip Phase 1.5 (architecture discussion), go straight to task decomposition |
| `--no-limit` | `add-mission`, `resume-mission` | Disable 8/10 confidence gate in brainstorming; continue until user says stop |

## How It Works

```
You: /liang-tdd:add-mission "receipt scanner"
         |
         v
  Phase 1: Brainstorm          Opus asks Socratic questions until confidence
         |                     >= 8/10. Saves BRAINSTORM.md
         v
  Phase 1.5: Discuss           Identifies architecture gray areas, spawns
         |                     parallel advisor agents, captures decisions.
         v                     Saves DECISIONS.md
  Phase 2: Task Manager        Decomposes into tasks, each with a TEST_LIST.md
         |                     of ordered bash test scripts. Auto-accepted by
         v                     default (use --manual for interactive approval).
  Phase 3: Planner             Writes a step-by-step PLAN.md for each task:
         |                     exact RED > GREEN > BLUE cycle instructions.
         v
  Phase 4: Executor            Sonnet follows the plan in an isolated worktree.
         |                     One test at a time. Commits when all pass.
         v
  Phase 5: QA Verifier         Runs all tests, diffs against RED snapshots,
         |                     checks coverage. PASS > merge. FAIL > re-plan.
         v
      FINAL_REPORT.md          TDD discipline metrics + retrospective
```

Phases 3-5 loop per task. If QA fails, it re-plans with full failure context. On 2nd+ failure, online research is triggered. Max 10 iterations per task before marking it failed.

<details>
<summary><b>Vertical-Slice TDD Cycle (the core discipline)</b></summary>

The executor works through tests **one at a time**:

```
For each test in TEST_LIST.md:
  RED:        Write test script > run > confirm FAILS
  SNAPSHOT:   Copy test to .snapshots/ (tamper detection baseline)
  GREEN:      Write minimal implementation > run > confirm PASSES
  REGRESSION: Re-run ALL previous tests
  BLUE:       Refactor if needed > re-run all tests
  > Next test
```

Key rules:
- NEVER write implementation without a failing test first
- NEVER modify a test after its RED snapshot (fix the implementation instead)
- NEVER write multiple tests at once
- Tests are bash scripts — language-agnostic, zero dependencies

A PreToolUse hook (`tdd-test-guard.js`) enforces test immutability at the tool level. Even if the executor tries to modify a test file that has a RED snapshot, the Write/Edit will be blocked.

</details>

<details>
<summary><b>Model Routing</b></summary>

| Agent | Model | Why |
|-------|-------|-----|
| Brainstormer | Opus (inline) | Needs AskUserQuestion for Socratic questioning |
| Discuss Advisor | Sonnet (subagent, parallel) | Researches each gray area independently |
| Task Manager | Opus (subagent) | Judgment for task decomposition + test design |
| Researcher | Sonnet (subagent, parallel) | Per-task codebase analysis before TEST_LIST |
| Planner | Opus (subagent) | Depth for unambiguous per-cycle plans |
| Executor | Sonnet (CLI) | Follows plan literally in isolated worktree |
| QA Verifier | Sonnet (CLI) | Runs tests, checks snapshots, verifies coverage |
| Debugger | Sonnet (subagent) | Diagnoses QA failures with scientific method |

</details>

<details>
<summary><b>Mission Directory Structure</b></summary>

Every workflow run is a **mission** — a named container under `.planning/vibe/`:

```
.planning/vibe/
├── todos/
│   ├── pending/                   Captured ideas awaiting promotion
│   │   └── 2026-03-28-my-idea.md
│   └── done/                      Promoted/completed todos
└── 001-receipt-scanner/
    ├── BRAINSTORM.md              Socratic Q&A + task breakdown
    ├── DECISIONS.md               Architecture decisions from Phase 1.5
    ├── RESEARCH-BRAINSTORM.md     Upfront web research (with --research)
    ├── TASKS.md                   Task index with dependency graph
    ├── PROGRESS.md                Live status tracker
    ├── FINAL_REPORT.md            TDD metrics + retrospective
    └── tasks/
        └── 01-ocr-setup/
            ├── RESEARCH.md        Codebase analysis for this task
            ├── TEST_LIST.md       Ordered test behaviors + bash scripts
            ├── PLAN.md            Per-test RED > GREEN > BLUE steps
            ├── QA_REPORT.md       Test results + tamper check
            ├── DEBUG.md           Diagnosis after QA failure
            └── tests/
                ├── test-01-file-exists.sh
                ├── test-02-output.sh
                └── .snapshots/
                    ├── RED-test-01-file-exists.sh
                    └── RED-test-02-output.sh
```

</details>

## Overnight Runner

Do Phases 1-2 interactively during the day, then let the runner handle Phases 3-5 autonomously:

```bash
# After brainstorming + task approval:
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh .planning/vibe/003-my-feature
```

Or go fully autonomous with a spec file:

```bash
bash ~/.claude/liang-tdd/scripts/tdd-runner.sh --auto \
  --prompt-file spec.md --mission-name my-feature
```

The runner spawns fresh Claude sessions per task — no context degradation. Sends a desktop notification when done.

<details>
<summary><b>Runner Options</b></summary>

| Flag | Default | Effect |
|------|---------|--------|
| `--max-turns N` | 50 | Max turns per executor spawn |
| `--max-retries N` | 3 | Max QA retries per task |
| `--stop-on-fail N` | 3 | Abort after N consecutive task failures |
| `--plan-model MODEL` | claude-opus-4-6 | Model for planner |
| `--exec-model MODEL` | claude-sonnet-4-6 | Model for executor/QA |
| `--auto` | off | Fully autonomous (Phases 1-5) |
| `--prompt-file FILE` | — | Spec file as BRAINSTORM.md (requires `--auto`) |
| `--mission-name NAME` | — | Slug for new mission (requires `--auto`) |

</details>

## Project Structure

```
liang-tdd-skill/
├── commands/liang-tdd/        Slash command entry points
│   ├── add-mission.md           /liang-tdd:add-mission
│   ├── resume-mission.md        /liang-tdd:resume-mission
│   ├── progress.md              /liang-tdd:progress
│   ├── add-todo.md              /liang-tdd:add-todo
│   ├── check-todos.md           /liang-tdd:check-todos
│   └── help.md                  /liang-tdd:help
├── liang-tdd/
│   ├── workflows/
│   │   ├── core.md              Phase definitions, model routing, orchestration
│   │   ├── mission-ops.md       Mission CRUD, directory conventions
│   │   └── todo-ops.md          Todo capture, listing, promotion to missions
│   ├── references/
│   │   ├── prompts/             Per-agent prompt templates
│   │   │   ├── brainstormer.md    Phase 1 Socratic questioning
│   │   │   ├── discuss.md         Phase 1.5 architecture advisor
│   │   │   ├── task-manager.md    Phase 2 task decomposition
│   │   │   ├── planner.md         Phase 3 TDD cycle planning
│   │   │   ├── executor.md        Phase 4 vertical-slice execution
│   │   │   └── qa-verifier.md     Phase 5 test + tamper verification
│   │   └── schemas/             Per-artifact markdown schemas
│   │       ├── brainstorm.md      BRAINSTORM.md schema
│   │       ├── decisions.md       DECISIONS.md schema
│   │       ├── tasks.md           TASKS.md schema
│   │       ├── test-list.md       TEST_LIST.md schema
│   │       ├── plan.md            PLAN.md schema
│   │       ├── qa-report.md       QA_REPORT.md schema
│   │       ├── debug.md           DEBUG.md schema
│   │       ├── research.md        RESEARCH.md schema
│   │       ├── progress.md        PROGRESS.md schema
│   │       └── final-report.md    FINAL_REPORT.md schema
│   └── scripts/
│       └── tdd-runner.sh        Overnight autonomous runner
├── hooks/
│   └── tdd-test-guard.js       PreToolUse hook — blocks test modification
├── install.sh                  Symlink installer
├── LICENSE
└── README.md
```

## Tips

- **Be generous during brainstorming.** The more context you give, the better the task decomposition and tests.
- **Review every TEST_LIST carefully.** Bad tests = bad QA = wasted iterations.
- **Tests should verify outcomes, not implementation.** Think "what does the user see?" not "what does the code look like?"
- **Capture ideas with `/liang-tdd:add-todo`.** Don't lose thoughts mid-session. Promote them to missions later with `/liang-tdd:check-todos`.
- **Let it auto-advance.** The default behavior runs everything hands-off after brainstorming. Use `--manual` only when you want interactive control.
- **Switch between interactive and runner mid-mission.** Both read/write the same PROGRESS.md.

## Contributing

Contributions are welcome! Please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create a feature branch (`git checkout -b feat/my-change`)
3. Make your changes
4. Test by running `bash install.sh` and using the skill in Claude Code
5. Submit a PR

## License

[MIT](LICENSE)
