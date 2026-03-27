# Mission Operations

Shared logic for mission management across `/liang-tdd:*` commands.

---

## Mission Directory Structure

Every workflow run is a **mission** — a named container with its own artifact
directory under `.planning/vibe/`.

```
.planning/vibe/
├── 001-receipt-scanner/
│   ├── BRAINSTORM.md
│   ├── TASKS.md
│   ├── PROGRESS.md
│   ├── FINAL_REPORT.md
│   └── tasks/
│       └── 01-ocr-setup/
│           ├── TEST_LIST.md
│           ├── PLAN.md
│           ├── QA_REPORT.md
│           ├── RESEARCH-2.md       (created on 2nd+ QA failure)
│           └── tests/
│               ├── test-01-file-exists.sh
│               ├── test-02-output-format.sh
│               └── .snapshots/
│                   ├── RED-test-01-file-exists.sh
│                   └── RED-test-02-output-format.sh
├── 002-currency-converter/
│   └── ...
```

All artifact paths use `{mission_dir}` as shorthand for
`.planning/vibe/{NNN}-{slug}/` (e.g., `.planning/vibe/001-receipt-scanner/`).

---

## Creating a Mission

1. Scan `.planning/vibe/` for existing mission directories matching `[0-9][0-9][0-9]-*`
2. Determine the next index (max existing + 1, or 001 if none exist)
3. Slugify the topic: lowercase, replace spaces/special chars with hyphens, trim
4. Create `{mission_dir}` (e.g., `.planning/vibe/003-new-topic/`)

---

## Listing Missions

1. Scan `.planning/vibe/` for mission directories
2. For each, read `PROGRESS.md` (if exists) to determine status
3. Display a table:

```
Missions:
| #   | Name               | Status      | Tasks     | Tests      | Last Updated |
|-----|--------------------|-------------|-----------|------------|--------------|
| 001 | receipt-scanner    | complete    | 3/3 pass  | 12/12 pass | 2026-03-20   |
| 002 | currency-converter | in-progress | 1/4 pass  | 5/8 pass   | 2026-03-25   |
| 003 | new-topic          | pending     | —         | —          | 2026-03-25   |
```

Status values: `pending` (no BRAINSTORM.md yet), `brainstorming`, `planning`,
`executing`, `complete`, `stalled` (has failed tasks).

---

## Resuming a Mission by Index

1. Find mission directory matching index N (e.g., `002-*`)
2. Read its `PROGRESS.md` to determine where to resume
3. Continue from the next incomplete step (same logic as Phase 0 in core.md)

---

## Auto-Detect (no index given)

1. Scan for missions with incomplete status
2. If exactly one → resume it
3. If multiple → show the list and ask user which to resume via AskUserQuestion
4. If none → ask user if they want to create a new mission via AskUserQuestion
