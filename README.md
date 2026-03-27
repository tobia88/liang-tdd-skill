# liang-tdd — Vertical-Slice TDD Skill for Claude Code

A structured workflow that turns a vague idea into verified, tested code through
five phases: Brainstorm > Task Decomposition > Plan > Execute (RED>GREEN>BLUE) > QA.

## Installation

Run the install script to create symlinks from `~/.claude/` into this repo:

```bash
bash install.sh
```

This creates:
- `~/.claude/commands/liang-tdd/` -> `./commands/liang-tdd/`
- `~/.claude/liang-tdd/` -> `./liang-tdd/`
- `~/.claude/hooks/tdd-test-guard.js` -> `./hooks/tdd-test-guard.js`

## Uninstallation

```bash
bash install.sh --uninstall
```

## Commands

```
/liang-tdd:add-mission [--no-limit] "topic"    Start a new mission
/liang-tdd:resume-mission [--auto] [number]     Resume a mission
/liang-tdd:progress [number]                    Show mission progress
/liang-tdd:help                                 Show full help
```

## Structure

```
commands/liang-tdd/     Slash command entry points
liang-tdd/
  workflows/            Core workflow logic and mission operations
  references/           Artifact schemas and agent prompt templates
  scripts/              tdd-runner.sh (overnight autonomous mode)
hooks/                  tdd-test-guard.js (PreToolUse hook)
```

## License

MIT
