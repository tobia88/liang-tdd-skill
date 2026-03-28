# QA Report Schema

Schema for QA_REPORT.md — the verification report created by QA Verifier in Phase 5.

```markdown
# QA Report: {NN}-{slug}

**Version:** {N}
**Date:** {YYYY-MM-DD}
**Overall: {PASS | FAIL}**

## Test Results

| # | Test Script | Result | Evidence |
|---|-------------|--------|----------|
| 1 | `test-01-{name}.sh` | {PASS|FAIL} | {exit code, output} |

## Tamper Detection

| # | Test Script | Snapshot | Tampered? | Details |
|---|-------------|----------|-----------|---------|
| 1 | `test-01-{name}.sh` | `RED-test-01-{name}.sh` | {YES|NO} | {diff details if tampered} |

## Coverage

| Test from TEST_LIST.md | Script Found? |
|------------------------|---------------|
| {test-name} | {YES|NO} |

## Failed Items Detail

{Only present if overall is FAIL}

### {Item type}: {description}
- **Expected:** {what should have been true}
- **Actual:** {what was found}
- **Evidence:** {command output, file contents, diff output}
- **Suggested fix:** {if obvious}
```
