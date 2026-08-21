#!/usr/bin/env node

import assert from 'node:assert/strict';
import {chmodSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, unlinkSync, utimesSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, relative, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {releaseIdentityDocument, renderManifest, resolveRokuReleaseIdentity} from './lib/roku-release-policy.mjs';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const archive = resolve(root, 'artifacts/portico-roku-release.zip');
const temporary = mkdtempSync(join(tmpdir(), 'portico-roku-release-'));
const staging = resolve(temporary, 'staging');
const comparison = resolve(temporary, 'comparison.zip');

function files(directory, base = directory) {
  return readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? files(path, base) : [relative(base, path)];
  }).sort();
}

function packageZip(target, entries) {
  try { unlinkSync(target); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const result = spawnSync('zip', ['-0', '-X', '-q', target, ...entries], {cwd: staging, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr || result.stdout || 'zip failed');
}

try {
  mkdirSync(staging, {recursive: true});
  const extracted = spawnSync('unzip', ['-q', archive, '-d', staging], {cwd: root, encoding: 'utf8'});
  assert.equal(extracted.status, 0, extracted.stderr || extracted.stdout || 'unzip failed');
  const entries = files(staging);
  assert.ok(entries.length > 0, 'Release staging directory is empty.');
  const identity = resolveRokuReleaseIdentity();
  mkdirSync(resolve(staging, 'data'), {recursive: true});
  writeFileSync(resolve(staging, 'data/release-identity.v1.json'), `${JSON.stringify(releaseIdentityDocument(identity), null, 2)}\n`);
  const manifestPath = resolve(staging, 'manifest');
  writeFileSync(manifestPath, renderManifest(readFileSync(manifestPath, 'utf8'), identity));
  const stableTime = new Date('2020-01-01T00:00:00Z');
  const normalizedEntries = files(staging);
  for (const entry of normalizedEntries) {
    const path = resolve(staging, entry);
    chmodSync(path, 0o644);
    utimesSync(path, stableTime, stableTime);
  }
  packageZip(archive, normalizedEntries);
  packageZip(comparison, normalizedEntries);
  assert.deepEqual(readFileSync(archive), readFileSync(comparison), 'Roku release archive is not reproducible from identical staging input.');
  console.log(`Built reproducible Roku release archive with ${normalizedEntries.length} files (${identity.status}).`);
} finally {
  rmSync(temporary, {recursive: true, force: true});
}
