# liang-tdd

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-blue)](https://docs.anthropic.com/en/docs/claude-code)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)

A vertical-slice TDD workflow skill for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that turns a vague idea into verified, tested code through five structured phases.

**Brainstorm** (research-backed Socratic questioning) **>** **Decompose** (tasks + bash test specs) **>** **Plan** (per-test RED/GREEN/BLUE cycles) **>** **Execute** (isolated worktrees, one test at a time) **>** **QA** (tamper detection + regression checks)

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

- **Research-backed brainstorming** — Upfront web research informs every AskUserQuestion option, so decisions are data-driven instead of guesswork
- **Vertical-slice TDD** — One test at a time through RED > GREEN > BLUE. Never write implementation without a failing test first
- **Tamper detection** — RED snapshots catch any test modifications after the initial write. A PreToolUse hook enforces this at the tool level
- **Isolated execution** — Each task runs in its own git worktree. Failures can't corrupt your main branch
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
| `/liang-tdd:help` | Display the full command reference |

### Flags

| Flag | Works on | Effect |
|------|----------|--------|
| `--auto` | `resume-mission` | Task Manager auto-accepts all tasks without interactive approval |
| `--research` | `add-mission`, `resume-mission` | Run upfront web research before brainstorming to enrich questions |
| `--skip-discuss` | `add-mission`, `resume-mission` | Skip Phase 1.5 (architecture discussion) |

## How It Works

```
You: /liang-tdd:add-mission "receipt scanner"
         |
         v
  Phase 1: Brainstorm          Opus asks your confidence threshold, then
         |                     Socratic questions until you choose to stop.
         v                     Saves BRAINSTORM.md
  Phase 2: Task Manager        Decomposes into tasks, each with a
         |                     TEST_LIST.md of ordered bash test scripts.
         v                     You approve each task's tests.
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
| Task Manager | Opus (subagent) | Judgment for task decomposition + test design |
| Planner | Opus (subagent) | Depth for unambiguous per-cycle plans |
| Executor | Sonnet (CLI) | Follows plan literally in isolated worktree |
| QA Verifier | Sonnet (CLI) | Runs tests, checks snapshots, verifies coverage |

</details>

<details>
<summary><b>Mission Directory Structure</b></summary>

Every workflow run is a **mission** — a named container under `.planning/vibe/`:

```
.planning/vibe/
└── 001-receipt-scanner/
    ├── BRAINSTORM.md              Research findings + Socratic Q&A
    ├── RESEARCH-BRAINSTORM.md     Upfront web research
    ├── TASKS.md                   Task index with dependency graph
    ├── PROGRESS.md                Live status tracker
    ├── FINAL_REPORT.md            TDD metrics + retrospective
    └── tasks/
        └── 01-ocr-setup/
            ├── TEST_LIST.md       Ordered test behaviors + bash scripts
            ├── PLAN.md            Per-test RED > GREEN > BLUE steps
            ├── QA_REPORT.md       Test results + tamper check
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
│   └── help.md                  /liang-tdd:help
├── liang-tdd/
│   ├── workflows/
│   │   ├── core.md              Phase definitions, model routing, orchestration
│   │   └── mission-ops.md       Mission CRUD, directory conventions
│   ├── references/
│   │   ├── agent-prompts.md     Prompt templates for all 5 agent roles
│   │   └── artifact-schemas.md  Markdown schemas for all mission artifacts
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
- **Use context clearing gates.** Fresh context = better planning. The skill offers these before heavy phases.
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
