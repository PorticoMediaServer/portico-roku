#!/usr/bin/env node
/**
 * Unit tests for the channel's logic (parsing, deciding, formatting). There is no Roku to run them
 * on, so the BrighterScript is compiled and the result runs in the off-device `brs` interpreter.
 * Screens and layout are not tested.
 */
import {execFileSync, spawnSync} from 'node:child_process';
import {readFileSync, readdirSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(process.env.PORTICO_BUILD_DIR ?? join(app, 'build'), 'test');
const bin = name => join(app, 'node_modules', '.bin', name);
rmSync(out, {recursive: true, force: true});
execFileSync(bin('bsc'), ['--project', 'bsconfig.test.json', '--staging-dir', out], {cwd: app, stdio: 'inherit'});
const files = [];
(function walk(dir) {
  for (const name of readdirSync(dir).sort()) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path);
    else if (name.endsWith('.brs')) files.push(path);
  }
})(join(out, 'source'));
// The runner: one call per `sub Test_…()` the compiled tests declare.
const tests = [];
// A comma-separated filter keeps related checks in one interpreter, including fixture-isolation checks.
const only = (process.argv[2] ?? '').toLowerCase().split(',').filter(Boolean);
for (const file of files) for (const m of readFileSync(file, 'utf8').matchAll(/^\s*sub (test_\w+)\(\)/gim)) if (!only.length || only.some(part => m[1].toLowerCase().includes(part))) tests.push(m[1]);
if (!tests.length) throw new Error('No tests matched the requested filter');
const runner = join(out, 'source', 'test', 'TestRunner.brs');
writeFileSync(runner, `sub main()\n${tests.map(t => `    TestBegin("${t}")\n    ${t}()`).join('\n')}\n    TestReport()\nend sub\n`);
files.push(runner);
const run = spawnSync(bin('brs'), ['--root', out, '--no-color', ...files], {cwd: app, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
process.stdout.write(run.stdout ?? '');
process.stderr.write(run.stderr ?? '');
const passed = /^TESTS PASSED: (\d+) checks in (\d+) tests$/m.exec(run.stdout ?? '');
if (run.status !== 0 || !passed) {
  console.error('test: FAILED');
  process.exit(1);
}
