#!/usr/bin/env node
/**
 * Unit tests for the channel's logic (parsing, deciding, formatting). There is no Roku to run them
 * on, so the BrighterScript is compiled and the result runs in the off-device `brs` interpreter.
 * Screens and layout are not tested.
 */
import {execFileSync, spawnSync} from 'node:child_process';
import {existsSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(app, 'build', 'test');
const bin = name => join(app, 'node_modules', '.bin', name);
if (existsSync(join(app, 'scripts', 'golden.mjs'))) execFileSync(process.execPath, [join(app, 'scripts', 'golden.mjs')], {cwd: app, stdio: 'inherit'});
rmSync(out, {recursive: true, force: true});
execFileSync(bin('bsc'), ['--project', 'bsconfig.test.json'], {cwd: app, stdio: 'inherit'});
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
// `node scripts/test.mjs Library` runs only the tests whose name holds that word (while fixing one area).
const only = (process.argv[2] ?? '').toLowerCase();
for (const file of files) for (const m of readFileSync(file, 'utf8').matchAll(/^\s*sub (test_\w+)\(\)/gim)) if (!only || m[1].toLowerCase().includes(only)) tests.push(m[1]);
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
