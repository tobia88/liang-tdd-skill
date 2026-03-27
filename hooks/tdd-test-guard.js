#!/usr/bin/env node
// liang-tdd Test Guard — PreToolUse hook
// Blocks Write/Edit on TDD test scripts that have been snapshot (RED phase complete).
// Once a test has a RED snapshot, only the implementation should change — never the test.
//
// Logic:
//   1. Check if the target file matches */tests/test-*.sh
//   2. Derive the snapshot path: tests/.snapshots/RED-test-{name}.sh
//   3. If snapshot exists → EXIT 2 (block)
//   4. If no snapshot → EXIT 0 (allow — this is the initial RED phase write)
//
// Works with bypassPermissions — hooks are independent of the permission system.

const fs = require('fs');
const path = require('path');

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const toolName = data.tool_name;

    // Only guard Write and Edit
    if (toolName !== 'Write' && toolName !== 'Edit') {
      process.exit(0);
    }

    const filePath = (data.tool_input?.file_path || '').replace(/\\/g, '/');

    // Only guard TDD test scripts: */tests/test-*.sh
    const testMatch = filePath.match(/\/tests\/(test-\d+-[^/]+\.sh)$/);
    if (!testMatch) {
      process.exit(0);
    }

    const testFilename = testMatch[1]; // e.g., "test-01-csv-headers.sh"
    const testsDir = filePath.substring(0, filePath.lastIndexOf('/tests/') + '/tests/'.length);
    const snapshotPath = testsDir + '.snapshots/RED-' + testFilename;

    // Normalize for fs.existsSync on Windows
    const snapshotPathNative = snapshotPath.replace(/\//g, path.sep);

    if (!fs.existsSync(snapshotPathNative)) {
      // No snapshot yet — this is the RED phase write, allow it
      process.exit(0);
    }

    // Snapshot exists — test is frozen, block modification
    process.stderr.write(
      `BLOCKED by tdd-test-guard: Cannot modify "${testFilename}" — ` +
      `RED snapshot exists at ${snapshotPath}. ` +
      `Fix the IMPLEMENTATION, not the test. ` +
      `If the test is genuinely wrong, delete its RED snapshot first, ` +
      `then re-run the RED phase.`
    );
    process.exit(2);
  } catch {
    // Silent fail — never block on hook errors
    process.exit(0);
  }
});
