#!/usr/bin/env node
/**
 * Fetches real documents from a development server into test/fixtures/server/, for the parsers'
 * tests. Run by hand when the server's documents change; the fixtures are committed.
 *
 *   node scripts/fixtures.mjs --account <path to DEV-ACCOUNT.md> [--server http://127.0.0.1:32500]
 *
 * The account file holds `username:` and `password:` lines. Nothing from it is printed or written.
 * Tokens are stripped from what is saved: session and refresh tokens, signed page cursors, and the
 * grant in media URLs.
 */
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';

import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const arg = name => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : undefined; };
const server = (arg('server') ?? 'http://127.0.0.1:32500').replace(/\/+$/, '');
const accountPath = arg('account');
if (!accountPath) { console.error('fixtures: pass --account <path to the development account file>'); process.exit(1); }
const account = readFileSync(accountPath, 'utf8');
const field = name => new RegExp(`^${name}:\\s*(\\S+)`, 'm').exec(account)?.[1];
const username = field('username'), password = field('password');
if (!username || !password) { console.error('fixtures: the account file needs username: and password: lines'); process.exit(1); }

const installation = {'X-Portico-Installation-Id': 'fixtures-roku-0000000000000000000000000000', 'X-Portico-Device-Name': 'Roku fixtures', 'X-Portico-Device-Platform': 'roku', 'X-Portico-App': 'Portico', 'X-Portico-App-Version': '0.1.0'};
let token = '';
async function request(path, method = 'GET', body, extra = {}) {
  const response = await fetch(server + path, {method, headers: {Accept: 'application/json', 'X-Portico-Device-Class': 'television', ...(body ? {'Content-Type': 'application/json'} : {}), ...(token ? {Authorization: `Bearer ${token}`} : {}), ...(method === 'POST' ? installation : {}), ...extra}, ...(body ? {body: JSON.stringify(body)} : {})});
  const text = await response.text();
  let data;
  try { data = text ? JSON.parse(text) : undefined; } catch { data = undefined; }
  return {status: response.status, data};
}
const secret = /^(accessToken|refreshToken|token|setupToken)$/;
// What a stripped token is replaced with: the shape of a token, so the parsers still accept the document.
const stripped = 'stripped-token-000000000000000000000000000';
const scrub = value => {
  if (Array.isArray(value)) return value.map(scrub);
  // A page cursor is a signed continuation bound to the viewer: opaque to the channel, so a placeholder serves.
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, secret.test(k) && typeof v === 'string' ? stripped : /cursor$/i.test(k) && typeof v === 'string' && v ? 'stripped-cursor' : scrub(v)]));
  if (typeof value === 'string') return value.replace(/\/v1\/media\/[^/]+\//g, '/v1/media/<grant>/');
  return value;
};
const saved = [];
function save(name, value) {
  const file = join(app, 'test', 'fixtures', 'server', name);
  mkdirSync(dirname(file), {recursive: true});
  writeFileSync(file, `${JSON.stringify(scrub(value), null, 1)}\n`);
  saved.push(name);
}
async function keep(name, path, method, body, extra) {
  const answer = await request(path, method, body, extra);
  if (answer.status >= 200 && answer.status < 300 && answer.data !== undefined) { save(name, answer.data); return answer.data; }
  console.log(`fixtures: ${path} answered ${answer.status}; ${name} not written`);
  return undefined;
}

const signIn = await request('/v1/direct/sign-in', 'POST', {username, password});
if (signIn.status !== 200 || !signIn.data?.session) { console.error(`fixtures: sign-in answered ${signIn.status}${signIn.data?.challenge ? ' (two-step verification)' : ''}`); process.exit(1); }
save('direct-sign-in.json', signIn.data);
token = signIn.data.session.accessToken;
if (signIn.data.session.viewer.role === 'account') {
  const profile = signIn.data.profiles.find(p => !p.pinRequired) ?? signIn.data.profiles[0];
  const chosen = await request(`/v1/direct/profiles/${encodeURIComponent(profile.id)}/select`, 'POST', {installationId: installation['X-Portico-Installation-Id']});
  if (chosen.status !== 200) { console.error(`fixtures: choosing a profile answered ${chosen.status}`); process.exit(1); }
  token = chosen.data.session.accessToken;
}
try {
  await keep('system.json', '/v1/system');
  const libraries = await keep('libraries.json', '/v1/libraries');
  const home = await keep('home.json', '/v1/home');
  const extra = (await import('./fixtures-more.mjs').catch(() => ({default: undefined}))).default;
  if (extra) await extra({keep, request, save, libraries, home});
} finally {
  await request('/v1/sessions/current', 'DELETE');
}
console.log(`fixtures: wrote ${saved.length} documents to test/fixtures/server (${saved.join(', ')})`);
