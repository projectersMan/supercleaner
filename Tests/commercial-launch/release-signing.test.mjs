import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

function interruptedSignatureDoesNotCommitSubmissionArtifact() {
  const base = resolve('Tests/commercial-launch/fixtures');
  mkdirSync(base, { recursive: true });
  const directory = mkdtempSync(join(base, 'signature-'));
  const pending = join(directory, 'submitted.pending.dmg');
  const submitted = join(directory, 'submitted.dmg');
  writeFileSync(pending, 'unsigned fixture');
  writeFileSync(join(directory, 'codesign'), `#!/bin/zsh
set -euo pipefail
if [[ $1 == --force && ! -f "$TEST_SIGNING_DIRECTORY/retried" ]]; then
  touch "$TEST_SIGNING_DIRECTORY/retried"
  exit 75
fi
`, { mode: 0o700 });
  const environment = { ...process.env, PATH: `${directory}:${process.env.PATH}`, TEST_SIGNING_DIRECTORY: directory, SUPERCLEANER_SIGN_IDENTITY: 'fixture-identity' };
  const command = resolve('Scripts/sign-release-artifact.sh');
  const failed = spawnSync('/bin/zsh', [command, pending, submitted], { env: environment, encoding: 'utf8' });
  assert.notEqual(failed.status, 0);
  assert.equal(existsSync(submitted), false, 'failed signing must not look like an immutable submitted DMG');
  assert.equal(existsSync(pending), true, 'failed signing preserves the recoverable pending artifact');
  const resumed = spawnSync('/bin/zsh', [command, pending, submitted], { env: environment, encoding: 'utf8' });
  assert.equal(resumed.status, 0, resumed.stderr);
  assert.equal(existsSync(pending), false);
  assert.equal(readFileSync(submitted, 'utf8'), 'unsigned fixture');
  const repeated = spawnSync('/bin/zsh', [command, submitted, submitted], { env: environment, encoding: 'utf8' });
  assert.notEqual(repeated.status, 0, 'committed submission artifact must never be re-signed');
  rmSync(directory, { recursive: true });
}

test('Signing interruption stays pending and can resume before any immutable submission', interruptedSignatureDoesNotCommitSubmissionArtifact);
