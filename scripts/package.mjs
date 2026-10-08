#!/usr/bin/env node
/** Compiles the channel into build/staging and zips it into a sideloadable package with roku-deploy. */
import {execFileSync} from 'node:child_process';
import {mkdirSync, rmSync, statSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {rokuDeploy} from 'roku-deploy';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const staging = join(app, 'build', 'staging');
const zip = join(app, 'build', 'portico-roku.zip');
rmSync(staging, {recursive: true, force: true});
mkdirSync(dirname(zip), {recursive: true});
execFileSync(join(app, 'node_modules', '.bin', 'bsc'), ['--project', 'bsconfig.json'], {cwd: app, stdio: 'inherit'});
rmSync(zip, {force: true});
await rokuDeploy.zipFolder(staging, zip);
console.log(`package: build/portico-roku.zip, ${(statSync(zip).size / 1024).toFixed(0)} KB`);
