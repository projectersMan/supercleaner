import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createPublicKey, generateKeyPairSync, sign, verify } from 'node:crypto';
import { chmodSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';
import test from 'node:test';

const script = resolve('Scripts/sign-rule-update.mjs');
const verifier = process.env.SUPERCLEANER_RULE_VERIFIER;
const fixtureRoot = resolve('Tests/commercial-launch/fixtures');

function removeFixture(root) {
  rmSync(root, { recursive: true });
}

function publicBytes(key) {
  const exported = key.export({ format: 'jwk' });
  return Buffer.from(exported.x, 'base64url').toString('base64');
}

function makeFixture(context) {
  assert.ok(typeof verifier === 'string' && isAbsolute(verifier), 'SUPERCLEANER_RULE_VERIFIER must explicitly name the compiled CoreContractChecks executable');
  mkdirSync(fixtureRoot, { recursive: true });
  const root = mkdtempSync(join(fixtureRoot, 'rule-publishing-'));
  context.after(removeFixture.bind(null, root));
  const ruleKey = generateKeyPairSync('ed25519');
  const sparkleKey = generateKeyPairSync('ed25519');
  const licenseKey = generateKeyPairSync('ed25519');
  const input = join(root, 'raw-pack.json');
  const privateKey = join(root, 'rule-private.pem');
  const releasePath = join(root, 'release.json');
  const commercialPath = join(root, 'commercial.json');
  const output = join(root, 'signed-update.json');
  const pack = { version: 'production-fixture-1', issuedAt: Math.floor(Date.now() / 1000) - 978307200 - 1,
    revokedRuleIDs: [], rules: [{ ruleID: 'fixture.cache', category: 'cache', relativePaths: ['Library/Caches/Fixture'],
      minimumAgeDays: 30, defaultRisk: 'review', sourceReference: 'rule-publishing-fixture' }] };
  const release = { schemaVersion: 1, bundleIdentifier: 'dev.supercleaner.App', teamIdentifier: 'A1B2C3D4E5',
    ruleUpdateURL: 'https://updates.supercleaner.dev/rules.json', applicationUpdateURL: 'https://updates.supercleaner.dev/appcast.xml',
    rulePublicKey: publicBytes(ruleKey.publicKey), applicationPublicKey: publicBytes(sparkleKey.publicKey),
    allowedHosts: ['updates.supercleaner.dev'] };
  const commercial = { schemaVersion: 1, productID: 'supercleaner.buyout', apiBaseURL: 'https://commerce.supercleaner.dev',
    licensePublicKey: publicBytes(licenseKey.publicKey) };
  writeFileSync(input, `  ${JSON.stringify(pack, null, 2)}\n\n`, { flag: 'wx' });
  writeFileSync(privateKey, ruleKey.privateKey.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600, flag: 'wx' });
  writeFileSync(releasePath, JSON.stringify(release), { flag: 'wx' });
  writeFileSync(commercialPath, JSON.stringify(commercial), { flag: 'wx' });
  return { root, ruleKey, sparkleKey, licenseKey, input, privateKey, releasePath, commercialPath, output, pack, release, commercial };
}

function signArguments(fixture) {
  return [script, 'sign', '--input', fixture.input, '--private-key', fixture.privateKey,
    '--release-config', fixture.releasePath, '--commercial-config', fixture.commercialPath,
    '--verifier', realpathSync(verifier), '--output', fixture.output];
}

function runSigner(fixture) {
  return spawnSync(process.execPath, signArguments(fixture), { encoding: 'utf8', timeout: 60000 });
}

function assertFailedWithoutOutput(fixture, result) {
  assert.notEqual(result.status, 0, 'unsafe rule publication unexpectedly succeeded');
  assert.equal(lstatSync(fixture.output, { throwIfNoEntry: false }), undefined, 'failed publication left an output');
}

function signsOriginalBytesAndPassesActualSwiftVerifier(context) {
  const fixture = makeFixture(context);
  const result = runSigner(fixture);
  assert.equal(result.status, 0, result.stderr);
  const envelope = JSON.parse(readFileSync(fixture.output, 'utf8'));
  const original = readFileSync(fixture.input);
  assert.deepEqual(Buffer.from(envelope.packData, 'base64'), original, 'raw whitespace/byte order was rewritten');
  assert.equal(Buffer.from(envelope.signature, 'base64').length, 64);
  assert.ok(verify(null, original, fixture.ruleKey.publicKey, Buffer.from(envelope.signature, 'base64')));
  const back = spawnSync(verifier, ['--validate-rule-update', fixture.releasePath, fixture.input, fixture.output], { encoding: 'utf8' });
  assert.equal(back.status, 0, back.stderr);
  assert.match(result.stdout, /PASS/u);
}

test('signs original pack bytes and round-trips through the actual Swift RuleStore', signsOriginalBytesAndPassesActualSwiftVerifier);

function refusesMismatchedOrReusedKeys(kind, context) {
  const fixture = makeFixture(context);
  if (kind === 'mismatched rule key') fixture.release.rulePublicKey = publicBytes(fixture.sparkleKey.publicKey);
  if (kind === 'Sparkle key reuse') fixture.release.applicationPublicKey = fixture.release.rulePublicKey;
  if (kind === 'commercial license key reuse') fixture.commercial.licensePublicKey = fixture.release.rulePublicKey;
  if (kind === 'Sparkle and commercial license key reuse') fixture.commercial.licensePublicKey = fixture.release.applicationPublicKey;
  writeFileSync(fixture.releasePath, JSON.stringify(fixture.release));
  writeFileSync(fixture.commercialPath, JSON.stringify(fixture.commercial));
  assertFailedWithoutOutput(fixture, runSigner(fixture));
}

for (const kind of ['mismatched rule key', 'Sparkle key reuse', 'commercial license key reuse', 'Sparkle and commercial license key reuse']) {
  test(`rejects ${kind}`, refusesMismatchedOrReusedKeys.bind(null, kind));
}

function refusesInvalidRule(kind, context) {
  const fixture = makeFixture(context);
  if (kind === 'empty version') fixture.pack.version = '';
  if (kind === 'whitespace version') fixture.pack.version = '   ';
  if (kind === 'future issue time') fixture.pack.issuedAt += 3600;
  if (kind === 'pre-bundled issue time') fixture.pack.issuedAt = 0;
  if (kind === 'path traversal') fixture.pack.rules[0].relativePaths = ['../Library/Caches'];
  if (kind === 'safe rule without evidence') fixture.pack.rules[0].defaultRisk = 'safe';
  if (kind === 'duplicate rule IDs') fixture.pack.rules.push(fixture.pack.rules[0]);
  if (kind === 'local activation revision') fixture.pack.activationID = 'F08C3CFB-E6C8-4840-8015-EE399D74A85B';
  if (kind === 'unknown category') fixture.pack.rules[0].category = 'unsafe-new-category';
  if (kind === 'invalid registry regex') fixture.pack.rules[0].referenceInventory = {
    registryDirectory: 'Library/Caches/Fixture', manifestFile: 'manifest.json', entriesKey: 'entries', nameKey: 'name', revisionKey: 'revision',
    artifactPattern: '[', replaceNameHyphensWithUnderscores: false };
  writeFileSync(fixture.input, JSON.stringify(fixture.pack));
  assertFailedWithoutOutput(fixture, runSigner(fixture));
}

for (const kind of ['empty version', 'whitespace version', 'future issue time', 'pre-bundled issue time', 'path traversal', 'safe rule without evidence',
  'duplicate rule IDs', 'local activation revision', 'unknown category', 'invalid registry regex']) {
  test(`rejects ${kind} before publication`, refusesInvalidRule.bind(null, kind));
}

function refusesExistingOutputAndSymbolicLink(context) {
  const fixture = makeFixture(context);
  writeFileSync(fixture.output, 'preserve-me', { flag: 'wx' });
  assert.notEqual(runSigner(fixture).status, 0);
  assert.equal(readFileSync(fixture.output, 'utf8'), 'preserve-me');
  rmSync(fixture.output);
  const target = join(fixture.root, 'unrelated.txt');
  writeFileSync(target, 'untouched');
  symlinkSync(target, fixture.output);
  assert.notEqual(runSigner(fixture).status, 0);
  assert.equal(readFileSync(target, 'utf8'), 'untouched');
  assert.ok(lstatSync(fixture.output).isSymbolicLink());
}

test('refuses output overwrite and symlink without touching either existing target', refusesExistingOutputAndSymbolicLink);

function refusesLinkedOutputDirectory(context) {
  const fixture = makeFixture(context);
  const alias = join(fixture.root, 'output-alias');
  symlinkSync(fixture.root, alias);
  fixture.output = join(alias, 'new-output.json');
  assertFailedWithoutOutput(fixture, runSigner(fixture));
}

test('refuses publication through a linked output directory', refusesLinkedOutputDirectory);

function refusesLinkedInput(field, context) {
  const fixture = makeFixture(context);
  const alias = join(fixture.root, 'alias');
  symlinkSync(fixture[field], alias);
  fixture[field] = alias;
  assertFailedWithoutOutput(fixture, runSigner(fixture));
}

for (const field of ['input', 'privateKey', 'releasePath', 'commercialPath']) {
  test(`rejects linked ${field}`, refusesLinkedInput.bind(null, field));
}

function refusesInsecurePrivateKey(context) {
  const fixture = makeFixture(context);
  chmodSync(fixture.privateKey, 0o644);
  assertFailedWithoutOutput(fixture, runSigner(fixture));
}

test('requires private key owner-only permissions', refusesInsecurePrivateKey);

function refusesOversizedRulePack(context) {
  const fixture = makeFixture(context);
  writeFileSync(fixture.input, Buffer.alloc(1_048_577, 32));
  assertFailedWithoutOutput(fixture, runSigner(fixture));
}

test('rejects oversized raw packs before reading or signing them', refusesOversizedRulePack);

function refusesMissingExplicitArguments(context) {
  const fixture = makeFixture(context);
  const args = signArguments(fixture);
  args.splice(args.indexOf('--commercial-config'), 2);
  const result = spawnSync(process.execPath, args, { encoding: 'utf8' });
  assertFailedWithoutOutput(fixture, result);
}

test('requires an explicit commercial public configuration for key separation', refusesMissingExplicitArguments);

function refusesANonVerifyingExecutable(context) {
  const fixture = makeFixture(context);
  fixture.pack.rules[0].relativePaths = ['../private'];
  writeFileSync(fixture.input, JSON.stringify(fixture.pack));
  const args = signArguments(fixture);
  args[args.indexOf('--verifier') + 1] = realpathSync('/usr/bin/true');
  const result = spawnSync(process.execPath, args, { encoding: 'utf8' });
  assertFailedWithoutOutput(fixture, result);
}

test('refuses a non-verifying executable that merely exits successfully', refusesANonVerifyingExecutable);

function rejectsTamperedEnvelopeOnActualSwiftReadback(context) {
  const fixture = makeFixture(context);
  assert.equal(runSigner(fixture).status, 0);
  const envelope = JSON.parse(readFileSync(fixture.output, 'utf8'));
  envelope.signature = Buffer.alloc(64).toString('base64');
  writeFileSync(fixture.output, JSON.stringify(envelope));
  const result = spawnSync(verifier, ['--validate-rule-update', fixture.releasePath, fixture.input, fixture.output], { encoding: 'utf8' });
  assert.notEqual(result.status, 0, 'Swift accepted a corrupted published signature');
}

test('actual Swift verifier rejects a corrupted signature on readback', rejectsTamperedEnvelopeOnActualSwiftReadback);

function rejectsAuthenticReserializedPayload(context) {
  const fixture = makeFixture(context);
  assert.equal(runSigner(fixture).status, 0);
  const changed = Buffer.from(JSON.stringify(fixture.pack));
  const envelope = { packData: changed.toString('base64'), signature: sign(null, changed, fixture.ruleKey.privateKey).toString('base64') };
  writeFileSync(fixture.output, JSON.stringify(envelope));
  const result = spawnSync(verifier, ['--validate-rule-update', fixture.releasePath, fixture.input, fixture.output], { encoding: 'utf8' });
  assert.notEqual(result.status, 0, 'Swift accepted authentic but different raw bytes');
}

test('actual Swift readback rejects a valid signature over reserialized pack bytes', rejectsAuthenticReserializedPayload);

function generatesOnlyIntoANewDedicatedDirectory(context) {
  const fixture = makeFixture(context);
  const directory = join(fixture.root, 'new-rule-key');
  const args = [script, 'generate-key', '--directory', directory];
  const generated = spawnSync(process.execPath, args, { encoding: 'utf8' });
  assert.equal(generated.status, 0, generated.stderr);
  assert.equal(lstatSync(directory).mode & 0o777, 0o700);
  const privatePath = join(directory, 'rule-private.pem');
  assert.equal(lstatSync(privatePath).mode & 0o777, 0o600);
  const publicText = readFileSync(join(directory, 'rule-public-key.txt'), 'utf8').trim();
  const imported = createPublicKey(readFileSync(privatePath));
  assert.equal(publicBytes(imported), publicText);
  const previous = readFileSync(privatePath);
  const repeated = spawnSync(process.execPath, args, { encoding: 'utf8' });
  assert.notEqual(repeated.status, 0);
  assert.deepEqual(readFileSync(privatePath), previous);
}

test('explicit generate-key creates a new 0700 directory and 0600 dedicated private key without overwrite', generatesOnlyIntoANewDedicatedDirectory);
