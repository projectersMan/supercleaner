#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign, verify } from 'node:crypto';
import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, mkdtempSync, openSync, readSync, realpathSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';

const signFlags = ['--input', '--private-key', '--release-config', '--commercial-config', '--verifier', '--output'];
const maximumPackBytes = 1_048_576;
const maximumEnvelopeBytes = 1_500_000;

function requiredOptions(args, names) {
  const values = Object.create(null);
  for (let index = 0; index < args.length; index += 2) {
    const name = args[index];
    const value = args[index + 1];
    if (!names.includes(name) || typeof value !== 'string' || value.startsWith('--') || Object.hasOwn(values, name)) {
      throw new Error('Unknown, duplicate or missing rule publishing argument.');
    }
    values[name] = value;
  }
  for (const name of names) {
    if (typeof values[name] !== 'string' || values[name].length === 0) throw new Error(`Required argument: ${name}`);
  }
  return values;
}

function absolutePath(value) {
  if (!isAbsolute(value) || resolve(value) !== value) throw new Error('Use an absolute, normalized path for every publishing file.');
  return value;
}

function validateParent(path) {
  const parent = dirname(path);
  if (realpathSync(parent) !== parent || !lstatSync(parent).isDirectory()) throw new Error('Publishing paths must not traverse symbolic links.');
}

function readRegularFile(path, maximumBytes, privateMaterial) {
  absolutePath(path);
  validateParent(path);
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = fstatSync(descriptor, { bigint: true });
    if (!before.isFile() || before.nlink !== 1n || before.size > BigInt(maximumBytes)) throw new Error('Publishing input must be a bounded regular file without links.');
    if (privateMaterial && ((before.mode & 0o077n) !== 0n || (before.mode & 0o400n) === 0n || before.uid !== BigInt(process.getuid()))) {
      throw new Error('The rule private key must be owned by the current user and readable only by its owner.');
    }
    const buffer = Buffer.alloc(maximumBytes + 1);
    let length = 0;
    while (length < buffer.length) {
      const count = readSync(descriptor, buffer, length, buffer.length - length, null);
      if (count === 0) break;
      length += count;
    }
    const after = fstatSync(descriptor, { bigint: true });
    const named = lstatSync(path, { bigint: true });
    validateParent(path);
    if (length > maximumBytes || BigInt(length) !== before.size || before.dev !== after.dev || before.ino !== after.ino
      || before.size !== after.size || before.mtimeNs !== after.mtimeNs || before.ctimeNs !== after.ctimeNs
      || named.dev !== before.dev || named.ino !== before.ino || !named.isFile()) {
      throw new Error('Publishing input changed while it was being read.');
    }
    return buffer.subarray(0, length);
  } finally {
    closeSync(descriptor);
  }
}

function removeCreatedFile(path, identity) {
  const named = lstatSync(path, { bigint: true, throwIfNoEntry: false });
  if (named !== undefined && named.dev === identity.dev && named.ino === identity.ino && named.isFile()) unlinkSync(path);
}

function writeNewFile(path, bytes, mode) {
  absolutePath(path);
  validateParent(path);
  const descriptor = openSync(path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, mode);
  const identity = fstatSync(descriptor, { bigint: true });
  let completed = false;
  try {
    writeFileSync(descriptor, bytes);
    fsyncSync(descriptor);
    completed = true;
    return identity;
  } finally {
    closeSync(descriptor);
    if (!completed) removeCreatedFile(path, identity);
  }
}

function parseObject(bytes, label) {
  const value = JSON.parse(bytes.toString('utf8'));
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${label} must be a JSON object.`);
  return value;
}

function isZero(byte) {
  return byte === 0;
}

function publicKeyBytes(value) {
  if (typeof value !== 'string') throw new Error('An explicit Ed25519 public key is required.');
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length !== 32 || bytes.toString('base64') !== value || bytes.every(isZero)) throw new Error('Invalid raw Ed25519 public key.');
  return bytes;
}

function rawPublicKey(key) {
  return Buffer.from(key.export({ format: 'jwk' }).x, 'base64url');
}

function commercialPublicKey(bytes) {
  const value = parseObject(bytes, 'Commercial configuration');
  const names = ['schemaVersion', 'productID', 'apiBaseURL', 'licensePublicKey'];
  if (Object.keys(value).length !== names.length) throw new Error('Commercial configuration must contain only its four public required fields.');
  for (const name of Object.keys(value)) {
    if (!names.includes(name)) throw new Error('Unknown or private commercial configuration field.');
  }
  if (value.schemaVersion !== 1 || typeof value.productID !== 'string' || value.productID.trim().length === 0 || value.productID !== value.productID.trim()) {
    throw new Error('Invalid commercial configuration identity.');
  }
  const url = new URL(value.apiBaseURL);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.port
    || !url.hostname.includes('.') || /(?:^|\.)(?:test|example|invalid|localhost|local)$/iu.test(url.hostname)
    || /example\.(?:com|org|net)$/iu.test(url.hostname)) throw new Error('Commercial configuration must identify a production HTTPS endpoint.');
  return publicKeyBytes(value.licensePublicKey);
}

function validateRawPack(bytes) {
  const pack = parseObject(bytes, 'RulePack');
  if (typeof pack.version !== 'string' || pack.version.trim().length === 0 || pack.version !== pack.version.trim()
    || pack.version.length > 100 || /[\u0000-\u001f\u007f-\u009f]/u.test(pack.version)) throw new Error('RulePack version must be a nonempty printable label of at most 100 characters.');
  if (!Number.isFinite(pack.issuedAt) || pack.issuedAt > Date.now() / 1000 - 978307200 + 600) {
    throw new Error('RulePack issuedAt must use the existing Swift 2001 epoch and must not be future-dated.');
  }
  return pack;
}

function readEnvelope(bytes, raw, key) {
  const value = parseObject(bytes, 'SignedRuleUpdate');
  if (Object.keys(value).length !== 2 || typeof value.packData !== 'string' || typeof value.signature !== 'string') throw new Error('Invalid signed rule envelope.');
  const payload = Buffer.from(value.packData, 'base64');
  const signature = Buffer.from(value.signature, 'base64');
  if (payload.toString('base64') !== value.packData || signature.toString('base64') !== value.signature
    || signature.length !== 64 || !payload.equals(raw) || !verify(null, payload, key, signature)) {
    throw new Error('Signed rule envelope failed original-byte and signature readback.');
  }
}

function runCoreVerifier(executable, releasePath, rawPath, envelopePath) {
  absolutePath(executable);
  validateParent(executable);
  const before = lstatSync(executable, { bigint: true });
  if (!before.isFile() || (before.mode & 0o111n) === 0n) throw new Error('The verifier must be an explicit regular executable.');
  const result = spawnSync(executable, ['--validate-rule-update', releasePath, rawPath, envelopePath], {
    encoding: 'utf8', timeout: 60000, maxBuffer: 65536, stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.error !== undefined) throw result.error;
  const after = lstatSync(executable, { bigint: true });
  if (before.dev !== after.dev || before.ino !== after.ino || before.size !== after.size
    || before.mtimeNs !== after.mtimeNs || before.ctimeNs !== after.ctimeNs || !after.isFile()) throw new Error('The verifier changed while validating the publication.');
  if (result.status !== 0) throw new Error(`The application RuleStore verifier rejected this publication (exit ${result.status}).`);
  const digest = createHash('sha256').update(readRegularFile(rawPath, maximumPackBytes, false)).digest('hex');
  const expected = `PASS: published RulePack original bytes, Ed25519 signature and application RuleStore schema; SHA256 ${digest}`;
  if (result.stdout.trim() !== expected) throw new Error('The executable did not return the application RuleStore validation receipt for these exact bytes.');
}

function signRuleUpdate(options) {
  const raw = readRegularFile(options['--input'], maximumPackBytes, false);
  const pack = validateRawPack(raw);
  const releaseBytes = readRegularFile(options['--release-config'], 65_536, false);
  const commercialBytes = readRegularFile(options['--commercial-config'], 65_536, false);
  const release = parseObject(releaseBytes, 'Release configuration');
  const configuredKey = publicKeyBytes(release.rulePublicKey);
  const sparkleKey = publicKeyBytes(release.applicationPublicKey);
  const licenseKey = commercialPublicKey(commercialBytes);
  const privateBytes = readRegularFile(options['--private-key'], 65_536, true);
  const privateKey = createPrivateKey({ key: privateBytes, format: 'pem' });
  if (privateKey.asymmetricKeyType !== 'ed25519') throw new Error('Rule publishing requires a dedicated Ed25519 private key.');
  const publicKey = createPublicKey(privateKey);
  const actualKey = rawPublicKey(publicKey);
  if (!actualKey.equals(configuredKey)) throw new Error('Rule private key does not match release-configuration.rulePublicKey.');
  if (actualKey.equals(sparkleKey) || actualKey.equals(licenseKey) || sparkleKey.equals(licenseKey)) {
    throw new Error('Rule, Sparkle and commercial license keys must be independent.');
  }
  const output = absolutePath(options['--output']);
  validateParent(output);
  if (lstatSync(output, { throwIfNoEntry: false }) !== undefined) throw new Error('Output already exists; rule publishing never overwrites files or links.');
  const signature = sign(null, raw, privateKey);
  const envelope = Buffer.from(`${JSON.stringify({ packData: raw.toString('base64'), signature: signature.toString('base64') })}\n`);
  if (envelope.length > maximumEnvelopeBytes) throw new Error('Signed envelope exceeds the application download limit.');
  readEnvelope(envelope, raw, publicKey);
  // All verification material stays under Tests, including production dry-run state.
  const fixtureDirectory = resolve('Tests/commercial-launch/fixtures');
  if (realpathSync(resolve('.')) !== resolve('.') || !lstatSync(resolve('Package.swift')).isFile()) throw new Error('Run the signer from the repository root.');
  mkdirSync(fixtureDirectory, { recursive: true, mode: 0o700 });
  if (realpathSync(fixtureDirectory) !== fixtureDirectory) throw new Error('Verification material directory must not be a symbolic link.');
  const staging = mkdtempSync(join(fixtureDirectory, 'rule-publication-'));
  let published;
  let completed = false;
  try {
    const releasePath = join(staging, 'release.json');
    const rawPath = join(staging, 'raw-pack.json');
    const envelopePath = join(staging, 'envelope.json');
    writeNewFile(releasePath, releaseBytes, 0o600);
    writeNewFile(rawPath, raw, 0o600);
    writeNewFile(envelopePath, envelope, 0o600);
    runCoreVerifier(options['--verifier'], releasePath, rawPath, envelopePath);
    published = writeNewFile(output, envelope, 0o644);
    readEnvelope(readRegularFile(output, maximumEnvelopeBytes, false), raw, publicKey);
    runCoreVerifier(options['--verifier'], releasePath, rawPath, output);
    completed = true;
    console.log(`PASS: rule ${pack.version} signed and read back by the application RuleStore; SHA256 ${createHash('sha256').update(raw).digest('hex')}`);
  } finally {
    if (!completed && published !== undefined) removeCreatedFile(output, published);
    rmSync(staging, { recursive: true });
  }
}

function generateRuleKey(options) {
  const directory = absolutePath(options['--directory']);
  validateParent(directory);
  mkdirSync(directory, { mode: 0o700 });
  const pair = generateKeyPairSync('ed25519');
  writeNewFile(join(directory, 'rule-private.pem'), pair.privateKey.export({ format: 'pem', type: 'pkcs8' }), 0o600);
  writeNewFile(join(directory, 'rule-public-key.txt'), `${rawPublicKey(pair.publicKey).toString('base64')}\n`, 0o644);
  console.log('PASS: dedicated rule key created; keep rule-private.pem secret and copy only rule-public-key.txt into public release configuration.');
}

function main(args) {
  const command = args[0];
  if (command === 'sign') {
    signRuleUpdate(requiredOptions(args.slice(1), signFlags));
    return;
  }
  if (command === 'generate-key') {
    generateRuleKey(requiredOptions(args.slice(1), ['--directory']));
    return;
  }
  throw new Error('Usage: node Scripts/sign-rule-update.mjs sign --input RAW_JSON --private-key PRIVATE_PEM --release-config PUBLIC_JSON --commercial-config PUBLIC_JSON --verifier CORE_CONTRACT_CHECKS --output NEW_ENVELOPE_JSON; or generate-key --directory NEW_ABSOLUTE_DIRECTORY');
}

main(process.argv.slice(2));
