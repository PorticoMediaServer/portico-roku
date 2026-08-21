#!/usr/bin/env node

import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readParityContracts, validateParityContracts} from './parity/parity-contracts.mjs';
import {assertReleaseIdentityDocument, releaseIdentityDocument, resolveRokuReleaseIdentity} from './lib/roku-release-policy.mjs';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const writeInventory = process.argv.includes('--write-inventory');
const archiveArgument = process.argv.slice(2).find(value => value !== '--write-inventory');
const archive = resolve(archiveArgument ?? resolve(root, 'artifacts/portico-roku-release.zip'));
const inventoryPath = resolve(root, 'scripts/release-inventory.snapshot.json');
const releaseIdentity = resolveRokuReleaseIdentity();

function unzip(args, encoding = 'utf8') {
  const result = spawnSync('unzip', args, {cwd: root, encoding, maxBuffer: 32 * 1024 * 1024});
  if (result.error) throw new Error(`Could not inspect the Roku release archive: ${result.error.message}`);
  if (result.status !== 0) throw new Error((result.stderr || result.stdout || 'unzip failed').toString().trim());
  return result.stdout;
}

function entry(name) {
  return unzip(['-p', archive, name]);
}

const archiveBytes = readFileSync(archive);
const names = unzip(['-Z1', archive]).split(/\r?\n/).map(value => value.trim()).filter(Boolean);
const files = names.filter(name => !name.endsWith('/')).sort();
const fileSet = new Set(files);

const required = [
  'manifest',
  'source/main.brs',
  'components/PorticoScene.xml',
  'components/PorticoScene.brs',
  'data/runtime-ui-contract.json',
  'data/release-identity.v1.json',
  'data/parity/tvos-roku-acceptance-matrix.v1.json',
  'data/parity/parity-exceptions.v1.json',
  'data/parity/remote-accessibility.v1.json',
  'data/parity/error-recovery.v1.json',
  'data/parity/roku-hardware-instrumentation.v1.json',
  'data/parity/roku-diagnostics.v1.json',
  'data/parity/tv-interaction-outcomes.v1.json',
  'data/generated/manifest.v1.json',
  'data/generated/operations.v1.json',
  'data/generated/product-contract.v1.json',
  'data/generated/product-language.v1.json',
  'fonts/OFL.txt',
  'images/icons/LICENSE-lucide.txt',
  'images/ui/channel-poster-fhd.png',
  'images/ui/splash-fhd.jpg'
];
for (const name of required) assert.ok(fileSet.has(name), `Release package is missing ${name}.`);

const forbiddenExact = new Set([
  'data/visual-contract.json',
  'development/manifest',
  'development/PorticoScene.xml'
]);
const forbiddenPrefixes = ['images/posters/', 'images/backdrops/', 'development/', 'tests/'];
for (const name of files) {
  assert.ok(!forbiddenExact.has(name), `Development fixture ${name} entered the release package.`);
  assert.ok(!forbiddenPrefixes.some(prefix => name.startsWith(prefix)), `Development fixture path ${name} entered the release package.`);
  assert.ok(!name.startsWith('/') && !name.includes('../') && !/^[A-Za-z]:/.test(name), `Unsafe archive path ${name}.`);
  assert.doesNotMatch(name, /(^|\/)(?:\.env(?:\.|$)|\.DS_Store$|Project Architecture\/|artifacts\/|screenshots?\/|docs?\/)/i, `Sensitive or internal path ${name} entered the release package.`);
  assert.doesNotMatch(name, /\.(?:pem|key|p12|pfx|mobileprovision|log|map|md)$/i, `Credential, debug, source-map, or internal-document file ${name} entered the release package.`);
}

for (const name of files.filter(value => /\.(?:brs|xml|json|txt)$|^manifest$/.test(value))) {
  const content = entry(name);
  assert.doesNotMatch(content, /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|(?:client_secret|refresh_token|access_token)\s*[=:]\s*["'][A-Za-z0-9_\/.+=-]{16,}["']/i, `Credential-like content entered ${name}.`);
  assert.doesNotMatch(content, /(?:Fargo|The Rookie|artifacts\/hardware|Project Architecture)/i, `Development media or internal evidence entered ${name}.`);
}

const manifest = entry('manifest');
assert.match(manifest, /^title=Portico$/m);
const versionParts = releaseIdentity.version.match(/^(\d+)\.(\d+)\.(\d+)/);
assert.ok(versionParts, 'Roku release identity version is not projectable to a manifest.');
assert.match(manifest, new RegExp(`^major_version=${versionParts[1]}$`, 'm'));
assert.match(manifest, new RegExp(`^minor_version=${versionParts[2]}$`, 'm'));
assert.match(manifest, new RegExp(`^build_version=${releaseIdentity.buildNumber}$`, 'm'));
assert.match(manifest, /^bs_const=visual_fixture=false$/m, 'Release manifest must lock conditional fixture code off.');

const packagedIdentity = JSON.parse(entry('data/release-identity.v1.json'));
assertReleaseIdentityDocument(packagedIdentity, releaseIdentity);
const parityNames = [
  'tvos-roku-acceptance-matrix.v1.json',
  'parity-exceptions.v1.json',
  'remote-accessibility.v1.json',
  'error-recovery.v1.json',
  'roku-hardware-instrumentation.v1.json',
  'roku-diagnostics.v1.json',
  'tv-interaction-outcomes.v1.json'
];
const packagedParity = Object.fromEntries(parityNames.map((name) => [name, JSON.parse(entry(`data/parity/${name}`))]));
validateParityContracts(packagedParity);
const canonicalParity = readParityContracts();
for (const name of parityNames) assert.deepEqual(packagedParity[name], canonicalParity[name], `Packaged parity contract drifted at ${name}.`);

const sceneXml = entry('components/PorticoScene.xml');
assert.doesNotMatch(sceneXml, /visualFixtureMode|fixtureModeChanged/, 'Release Scene exposes a fixture-mode field or callback.');

const runtimeContract = JSON.parse(entry('data/runtime-ui-contract.json'));
for (const fixtureKey of ['home', 'detail', 'railLibraryItems']) {
  assert.equal(runtimeContract[fixtureKey], undefined, `Runtime UI contract contains fixture key ${fixtureKey}.`);
}
assert.ok(runtimeContract.canvas?.width === 1920 && runtimeContract.canvas?.height === 1080);
assert.ok(Array.isArray(runtimeContract.railPrimaryItems) && Array.isArray(runtimeContract.railBottomItems));
assert.doesNotMatch(JSON.stringify(runtimeContract), /pkg:\/|Fargo|The Rookie|fixture/i, 'Runtime UI contract contains media or fixture payloads.');
const developmentContract = JSON.parse(readFileSync(resolve(root, 'channel/data/visual-contract.json'), 'utf8'));
for (const key of Object.keys(runtimeContract)) {
  assert.deepEqual(runtimeContract[key], developmentContract[key], `Runtime and visual contracts drifted at ${key}.`);
}

const manifestDocument = JSON.parse(entry('data/generated/manifest.v1.json'));
assert.equal(manifestDocument.schemaVersion, 1);
for (const artifact of manifestDocument.artifacts ?? []) assert.match(artifact.name, /\.v1\.json$/);
const productContract = JSON.parse(entry('data/generated/product-contract.v1.json')).contract;
assert.equal(productContract?.apiVersion, 'v1');
assert.equal(productContract?.actionRevision, 'v1');

const categories = {};
for (const name of files) {
  const category = name.includes('/') ? name.slice(0, name.indexOf('/')) : 'root';
  categories[category] = (categories[category] ?? 0) + 1;
}
const inventory = {
  version: releaseIdentity.version,
  artifact: 'artifacts/portico-roku-release.zip',
  sha256: createHash('sha256').update(archiveBytes).digest('hex'),
  compressedBytes: archiveBytes.length,
  fileCount: files.length,
  categories,
  securityBoundaries: {
    visualFixtureConstant: false,
    visualFixturePublicField: false,
    visualContractPackaged: false,
    posterFixturesPackaged: false,
    backdropFixturesPackaged: false,
    runtimeContractMediaPayloads: false
  },
  requiredFiles: required,
  files
};
const serializedInventory = `${JSON.stringify(inventory, null, 2)}\n`;
if (writeInventory) writeFileSync(inventoryPath, serializedInventory);
else assert.equal(readFileSync(inventoryPath, 'utf8'), serializedInventory, 'Release inventory drifted. Run npm run release:inventory:update after reviewing the package.');
console.log(`Verified Roku release ${inventory.version}: ${files.length} files, ${archiveBytes.length} compressed bytes, sha256 ${inventory.sha256}.`);
console.log(writeInventory ? `Updated ${inventoryPath}.` : `Matched ${inventoryPath}.`);
