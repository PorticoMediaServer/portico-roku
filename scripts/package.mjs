#!/usr/bin/env node
/** Compiles the channel into build/staging and zips it into a sideloadable package with roku-deploy. */
import {execFileSync} from 'node:child_process';
import {mkdirSync, rmSync, statSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {rokuDeploy} from 'roku-deploy';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const build = process.env.PORTICO_BUILD_DIR ?? join(app, 'build');
const staging = join(build, 'staging');
const zip = join(build, 'portico-roku.zip');
rmSync(staging, {recursive: true, force: true});
mkdirSync(dirname(zip), {recursive: true});
execFileSync(join(app, 'node_modules', '.bin', 'bsc'), ['--project', 'bsconfig.json', '--staging-dir', staging], {cwd: app, stdio: 'inherit'});
rmSync(zip, {force: true});
await rokuDeploy.zipFolder(staging, zip);
console.log(`package: ${zip}, ${(statSync(zip).size / 1024).toFixed(0)} KB`);
