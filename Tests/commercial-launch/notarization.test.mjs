import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

const script = resolve('Scripts/notarize-artifact.sh');
const fixtures = resolve('Tests/commercial-launch/fixtures');

function fixture() {
  mkdirSync(fixtures, { recursive: true });
  const directory = mkdtempSync(join(fixtures, 'notary-'));
  const executable = join(directory, 'xcrun');
  const body = `#!/bin/zsh
set -euo pipefail
print -r -- "$2" >> "$TEST_NOTARY_DIRECTORY/calls"
case "$2" in
submit) print '{"id":"00000000-0000-0000-0000-000000000001","message":"Uploaded"}' ;;
info) print '{"id":"00000000-0000-0000-0000-000000000001","status":"Accepted"}' ;;
log) print '{"issues":[]}' ;;
*) exit 90 ;;
esac
`;
  writeFileSync(executable, body, { mode: 0o700 });
  writeFileSync(join(directory, 'app.zip'), 'immutable archive');
  return directory;
}

function run(directory) {
  return spawnSync('/bin/zsh', [script, join(directory, 'app.zip'), join(directory, 'evidence')], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${directory}:${process.env.PATH}`, SUPERCLEANER_NOTARY_PROFILE: 'fixture-profile', TEST_NOTARY_DIRECTORY: directory },
  });
}

function acceptedSubmissionResumesWithoutResubmitting() {
  const directory = fixture();
  const first = run(directory);
  assert.equal(first.status, 0, first.stderr);
  const second = run(directory);
  assert.equal(second.status, 0, second.stderr);
  assert.equal(readFileSync(join(directory, 'calls'), 'utf8').split('\n').filter(isSubmit).length, 1);
  assert.equal(JSON.parse(readFileSync(join(directory, 'evidence/status.json'), 'utf8')).status, 'Accepted');
  rmSync(directory, { recursive: true });
}

function isSubmit(value) { return value === 'submit'; }

function changedArtifactCannotReuseSubmission() {
  const directory = fixture();
  assert.equal(run(directory).status, 0);
  writeFileSync(join(directory, 'app.zip'), 'changed archive');
  const result = run(directory);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /changed|不同|变化/i);
  assert.equal(readFileSync(join(directory, 'calls'), 'utf8').split('\n').filter(isSubmit).length, 1);
  rmSync(directory, { recursive: true });
}

function uncertainSubmissionCannotBeSilentlyRepeated() {
  const directory = fixture();
  mkdirSync(join(directory, 'evidence'));
  writeFileSync(join(directory, 'evidence/SUBMISSION-ATTEMPTED'), '');
  const result = run(directory);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /uncertain|不确定|reconcile|核对/i);
  rmSync(directory, { recursive: true });
}

test('Accepted submission resumes without another upload', acceptedSubmissionResumesWithoutResubmitting);
test('Changed artifact cannot reuse or replace a submission', changedArtifactCannotReuseSubmission);
test('Uncertain upload requires reconciliation before any resubmission', uncertainSubmissionCannotBeSilentlyRepeated);
