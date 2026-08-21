#!/usr/bin/env node

import {mkdirSync, writeFileSync} from 'node:fs';
import {basename, dirname, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const projectRoot = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const command = process.argv[2] ?? 'help';
const commandArgs = process.argv.slice(3);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) fail(`${name} is required for this command.`);
  if (/\r|\n/.test(value)) fail(`${name} contains an invalid newline.`);
  return value;
}

function deviceHost() {
  const value = requiredEnvironment('ROKU_DEVICE_HOST')
    .replace(/^https?:\/\//i, '')
    .replace(/\/$/, '');
  if (!/^[A-Za-z0-9._:-]+$/.test(value)) fail('ROKU_DEVICE_HOST must be a hostname or address without a path.');
  return value;
}

function curlConfigValue(value) {
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}

function runCurlConfig(lines, options = {}) {
  const config = [...lines, 'silent', 'show-error', 'fail-with-body'].join('\n') + '\n';
  const result = spawnSync('curl', ['--config', '-'], {
    cwd: projectRoot,
    encoding: options.binary ? null : 'utf8',
    input: config,
    maxBuffer: 16 * 1024 * 1024
  });
  if (result.error) fail(`Could not start curl: ${result.error.message}`);
  if (result.status !== 0) {
    const stderr = Buffer.isBuffer(result.stderr) ? result.stderr.toString('utf8') : result.stderr;
    const stdout = Buffer.isBuffer(result.stdout) ? result.stdout.toString('utf8') : result.stdout;
    fail(`Roku request failed (${result.status}): ${(stderr || stdout || 'unknown error').trim()}`);
  }
  return result.stdout;
}

function developerConfig(url, extra = []) {
  const username = process.env.ROKU_DEV_USER?.trim() || 'rokudev';
  const password = requiredEnvironment('ROKU_DEV_PASSWORD');
  if (/\r|\n/.test(username)) fail('ROKU_DEV_USER contains an invalid newline.');
  return [
    `url = "${curlConfigValue(url)}"`,
    'digest',
    `user = "${curlConfigValue(`${username}:${password}`)}"`,
    ...extra
  ];
}

async function ecpPost(path) {
  const response = await fetch(`http://${deviceHost()}:8060/${path}`, {method: 'POST'});
  if (!response.ok) fail(`Roku ECP request failed with HTTP ${response.status}.`);
}

async function ecpGet(path) {
  const response = await fetch(`http://${deviceHost()}:8060/${path}`);
  if (!response.ok) fail(`Roku ECP request failed with HTTP ${response.status}.`);
  return response.text();
}

function install() {
  const archive = resolve(commandArgs[0] ?? resolve(projectRoot, 'artifacts/portico-roku-release.zip'));
  const body = runCurlConfig(developerConfig(`http://${deviceHost()}/plugin_install`, [
    'request = "POST"',
    'form = "mysubmit=Install"',
    `form = "archive=@${curlConfigValue(archive)}"`
  ]));
  if (!/success/i.test(body)) fail(`The developer installer did not report success for ${basename(archive)}.`);
  console.log(`Installed ${basename(archive)}.`);
}

function screenshot() {
  const inspectBody = runCurlConfig(developerConfig(`http://${deviceHost()}/plugin_inspect`, [
    'request = "POST"',
    'form = "mysubmit=Screenshot"'
  ]));
  const match = inspectBody.match(/(?:src|href)=["']([^"']*pkgs\/dev\.(?:jpg|png)\?[^"']+)["']/i)
    ?? inspectBody.match(/(pkgs\/dev\.(?:jpg|png)\?[^"'<>\s]+)/i);
  if (!match) fail('The developer console did not return a screenshot URL.');
  const screenshotPath = match[1].replaceAll('&amp;', '&').replace(/^\//, '');
  const extension = screenshotPath.match(/dev\.(jpg|png)/i)?.[1]?.toLowerCase() ?? 'jpg';
  const requestedOutput = commandArgs[0];
  const timestamp = new Date().toISOString().replaceAll(':', '-').replace(/\.\d{3}Z$/, 'Z');
  const output = resolve(requestedOutput ?? resolve(projectRoot, `artifacts/hardware/device-${timestamp}.${extension}`));
  const bytes = runCurlConfig(developerConfig(`http://${deviceHost()}/${screenshotPath}`), {binary: true});
  mkdirSync(dirname(output), {recursive: true});
  writeFileSync(output, bytes);
  console.log(output);
}

function debugConsole() {
  const result = spawnSync('nc', [deviceHost(), '8085'], {stdio: 'inherit'});
  if (result.error) fail(`Could not start nc: ${result.error.message}`);
  process.exit(result.status ?? 1);
}

function help() {
  console.log(`Usage: npm run device -- <command> [argument]

Environment:
  ROKU_DEVICE_HOST      Roku hostname or address (required)
  ROKU_DEV_USER         Developer username (defaults to rokudev)
  ROKU_DEV_PASSWORD     Developer password/PIN (install and screenshot only)

Commands:
  info                  Print ECP device information
  install [zip]         Sideload a package through the developer installer
  launch                Launch the sideloaded dev channel
  key <name>            Send an ECP key such as Home, Select, Back, Up, or Down
  screenshot [path]     Save a developer-console screenshot
  debug                 Attach to the BrightScript console on port 8085
  deploy [zip]          Install and then launch the dev channel`);
}

switch (command) {
  case 'info':
    console.log(await ecpGet('query/device-info'));
    break;
  case 'install':
    install();
    break;
  case 'launch':
    await ecpPost('launch/dev');
    console.log('Launched dev channel.');
    break;
  case 'key': {
    const key = commandArgs[0];
    if (!key || !/^[A-Za-z0-9_-]+$/.test(key)) fail('A valid ECP key name is required.');
    await ecpPost(`keypress/${encodeURIComponent(key)}`);
    console.log(`Sent ${key}.`);
    break;
  }
  case 'screenshot':
    screenshot();
    break;
  case 'debug':
    debugConsole();
    break;
  case 'deploy':
    install();
    await ecpPost('launch/dev');
    console.log('Installed and launched dev channel.');
    break;
  case 'help':
  case '--help':
  case '-h':
    help();
    break;
  default:
    fail(`Unknown device command: ${command}`);
}
