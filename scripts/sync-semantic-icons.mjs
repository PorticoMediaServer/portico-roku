#!/usr/bin/env node

import assert from 'node:assert/strict';
import {copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const rokuRoot = resolve(fileURLToPath(new URL('..', import.meta.url)));
const repositoryRoot = resolve(rokuRoot, '../..');
const sourceRoot = resolve(repositoryRoot, 'assets/icons/generated/roku');
const sourceManifestPath = join(sourceRoot, 'manifest.json');
const assetRoot = resolve(rokuRoot, 'channel/images/icons/generated');
const packagedManifestPath = resolve(rokuRoot, 'channel/data/generated/roku-icons.v1.json');
const check = process.argv.includes('--check');

const sourceManifest = JSON.parse(readFileSync(sourceManifestPath, 'utf8'));
assert.equal(sourceManifest.schemaVersion, 1, 'Unsupported Roku semantic icon manifest schema.');
assert.ok(sourceManifest.registryVersion, 'Semantic icon registry version is missing.');
assert.ok(sourceManifest.semanticToMaster && sourceManifest.masters, 'Semantic icon manifest is incomplete.');

const packagedMasters = Object.fromEntries(Object.entries(sourceManifest.masters).map(([master, states]) => [
  master,
  Object.fromEntries(Object.entries(states).map(([state, entry]) => [state, {...entry, uri: `pkg:/images/icons/generated/${entry.path}`}]))
]));
const packagedManifest = {
  schemaVersion: sourceManifest.schemaVersion,
  registryVersion: sourceManifest.registryVersion,
  states: sourceManifest.states,
  semanticToMaster: sourceManifest.semanticToMaster,
  masters: packagedMasters,
};
const manifestBytes = `${JSON.stringify(packagedManifest, null, 2)}\n`;
const files = [...new Set(Object.values(sourceManifest.masters).flatMap(states => Object.values(states).map(entry => entry.path)))].sort();

if (check) {
  assert.ok(existsSync(packagedManifestPath), 'Packaged Roku semantic icon manifest is missing; run npm run icons:sync.');
  assert.equal(readFileSync(packagedManifestPath, 'utf8'), manifestBytes, 'Packaged Roku semantic icon manifest drifted.');
  const actual = existsSync(assetRoot) ? readdirSync(assetRoot).filter(name => name.endsWith('.png')).sort() : [];
  assert.deepEqual(actual, files, 'Packaged Roku semantic icon file inventory drifted.');
  for (const name of files) assert.deepEqual(readFileSync(join(assetRoot, name)), readFileSync(join(sourceRoot, name)), `Packaged semantic icon drifted: ${name}`);
  console.log(`Verified ${files.length} generated Roku semantic icon assets from registry ${sourceManifest.registryVersion}.`);
} else {
  mkdirSync(assetRoot, {recursive: true});
  mkdirSync(dirname(packagedManifestPath), {recursive: true});
  for (const name of files) copyFileSync(join(sourceRoot, name), join(assetRoot, name));
  writeFileSync(packagedManifestPath, manifestBytes);
  console.log(`Synchronized ${files.length} generated Roku semantic icon assets from registry ${sourceManifest.registryVersion}.`);
}
