#!/usr/bin/env node

import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, readdirSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, relative, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const temporary = mkdtempSync(join(tmpdir(), 'portico-roku-assets-'));

function files(directory, base = directory) {
  return readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? files(path, base) : [relative(base, path)];
  }).sort();
}

try {
  const generated = spawnSync(process.execPath, [resolve(root, 'scripts/generate-assets.mjs'), '--output-root', temporary], {cwd: root, encoding: 'utf8'});
  assert.equal(generated.status, 0, generated.stderr || generated.stdout);
  for (const kind of ['icons', 'ui']) {
    const expectedDirectory = resolve(temporary, `channel/images/${kind}`);
    const actualDirectory = resolve(root, `channel/images/${kind}`);
    const expectedFiles = files(expectedDirectory);
    for (const name of expectedFiles) {
      assert.deepEqual(readFileSync(resolve(actualDirectory, name)), readFileSync(resolve(expectedDirectory, name)), `Generated Roku asset drift: channel/images/${kind}/${name}`);
    }
  }
  console.log('Verified deterministic Roku assets without mutating the working tree.');
} finally {
  rmSync(temporary, {recursive: true, force: true});
}
