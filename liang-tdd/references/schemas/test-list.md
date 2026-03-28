# Test List Schema

Schema for TEST_LIST.md — the TDD spec for each task. Replaces the old
DESIRED_OUTCOME.md. An ordered list of behaviors to test ONE AT A TIME
in vertical-slice TDD cycles.

```markdown
# Test List: {NN}-{slug}

**Goal:** {One sentence describing what this task accomplishes}

## Tests (ordered, simplest -> most complex)

### Test 01: {test-name}
**Behavior:** {What specific behavior this test verifies}
**Script:**
#!/bin/bash
set -e
{test commands that exit 0 on success, non-zero on failure}

### Test 02: {test-name}
**Behavior:** {description}
**Script:**
#!/bin/bash
set -e
{test commands}

### Test 03: {test-name}
...

## Expected Changes

| File | Action |
|------|--------|
| {path} | create |
| {path} | modify |
```

## Test Script Guidelines

- Scripts MUST `set -e` for fail-fast behavior
- Scripts MUST exit 0 on success, non-zero on failure
- Scripts test OUTCOMES, not implementation details
- Scripts are language-agnostic — they verify results via:
  - File existence checks: `[ -f path ]`
  - Content pattern matching: `grep -q 'pattern' file`
  - Command output comparison: `[ "$(command)" = "expected" ]`
  - Build/compile verification: `build_command && echo PASS`
  - Data validation: `awk`, `wc -l`, `head`, `diff`
- Order matters: earlier tests verify foundational behaviors

## Test Script Examples

**CSV data validation:**
```bash
#!/bin/bash
set -e
expected="date,description,amount,category"
actual=$(head -1 data/2025/expenses.csv)
[ "$expected" = "$actual" ]
```

**File structure check:**
```bash
#!/bin/bash
set -e
[ -f Source/MyGame/MyComponent.h ]
grep -q 'class.*UMyComponent' Source/MyGame/MyComponent.h
```

**Command output validation:**
```bash
#!/bin/bash
set -e
output=$(python3 scripts/calculate.py --year 2025)
echo "$output" | grep -q 'Total: MYR'
```

**Build verification:**
```bash
#!/bin/bash
set -e
npm run build 2>&1
```

## Test File Structure

```
{mission_dir}/tasks/{NN}-{slug}/
├── TEST_LIST.md              — ordered test behaviors (the TDD spec)
├── PLAN.md                   — execution plan for vertical-slice cycles
├── QA_REPORT.md              — verification results
├── tests/
│   ├── test-01-{name}.sh     — individual test scripts
│   ├── test-02-{name}.sh
│   ├── test-03-{name}.sh
│   └── .snapshots/           — RED phase snapshots for tamper detection
│       ├── RED-test-01-{name}.sh
│       ├── RED-test-02-{name}.sh
│       └── RED-test-03-{name}.sh
└── RESEARCH-{N}.md           — (created on 2nd+ QA failure)
```
