#!/usr/bin/env node
/** Narrow generation from the checked canonical account seam; preserves all other producer pins. */
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, renameSync, readdirSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {stripTypeScriptTypes} from 'node:module';
const app = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const root = process.env.PORTICO_SERVER_ROOT;
if (!root) throw new Error('Set PORTICO_SERVER_ROOT to the checkout containing the pinned canonical source.');
const pins = JSON.parse(readFileSync(join(app, 'scripts/accounts-source-pins.json'), 'utf8'));
execFileSync('git', ['merge-base', '--is-ancestor', pins.commit, 'origin/main'], {cwd: root});
const source = {};
for (const [name, hash] of Object.entries(pins.files)) {
  const bytes = execFileSync('git', ['show', `${pins.commit}:${name}`], {cwd: root, maxBuffer: 16 * 1024 * 1024});
  if (createHash('sha256').update(bytes).digest('hex') !== hash) throw new Error(`Pinned source hash mismatch: ${name}`);
  source[name] = bytes.toString('utf8');
}
const cataloguePath = 'packages/i18n/src/catalog/en-US/accounts.ts';
// Evaluate only checked bytes; another writer's working catalogue is never consumed.
const {accountMessages} = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source[cataloguePath])).toString('base64'));
const welcome = /'web.signin.welcomeHome': '([^']+)'/.exec(source['packages/i18n/src/catalog/en-US/web.ts']);
if (!welcome) throw new Error('Re-read the checked welcome catalogue entry.');
const messages = {...accountMessages, 'web.signin.welcomeHome': welcome[1]};
const {schemas} = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source['packages/contracts/src/hosted/schemas.ts'])).toString('base64'));
const grant = schemas.DeviceAuthorizationTokenResponse;
const grantKeys = Object.keys(grant.properties);
if (grantKeys.includes('profiles') || !grant.properties.account?.properties) throw new Error('Expected checked profile-free Hosted producer.');
const grantAccountKeys = Object.keys(grant.properties.account.properties);
const noticePreferenceKeys = Object.keys(schemas.AccountNotificationPreferencesGetResponse.properties);
const {schemas: serverSchemas} = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source['packages/contracts/src/schemas.ts'])).toString('base64'));
const moves = serverSchemas.GetSystemResponse.properties.move;
if (!moves?.nullable || !Array.isArray(moves.enum)) throw new Error('Expected nullable checked SystemInfo move enum');
const deviceKeysSource = /const deviceKeys=\[([^\]]+)\] as const/.exec(source['packages/client-core/src/identity-devices.ts']);
if (!deviceKeysSource) throw new Error('Re-read checked device contract keys');
const deviceKeys = [...deviceKeysSource[1].matchAll(/'([^']+)'/g)].map(match => match[1].toLowerCase());
if (deviceKeys.includes('trusted') || deviceKeys.includes('approvalstate')) throw new Error('Retired device approval fields');

const moveStages = /stage:([^;]+);revision:/.exec(source['packages/client-core/src/account-move.ts']);
if (!moveStages) throw new Error('Re-read checked AccountMove stages');
const stages = [...moveStages[1].matchAll(/'([^']+)'/g)].map(match => match[1]);
if (stages.length !== 5) throw new Error('Expected checked AccountMove stage contract');
// Canonical account-move text rejects Unicode Cc/Cf, not just ASCII controls. Generate the
// portable ranges rather than relying on different Roku/Node regular-expression dialects.
const controls = [];
for (let cp = 0; cp <= 0x10ffff; cp++) if (/[\p{Cc}\p{Cf}]/u.test(String.fromCodePoint(cp))) {
  const last = controls.at(-1);
  if (last && last[1] === cp - 1) last[1] = cp; else controls.push([cp, cp]);
}
const check = process.argv.includes('--check');
const emit = (name, content) => {
  const path = join(app, name);
  if (check) { if (readFileSync(path, 'utf8') !== content) throw new Error(`Run generate:accounts: ${name}`); }
  else { const tmp = `${path}.tmp-${process.pid}`; writeFileSync(tmp, content); renameSync(tmp, path); }
};
const xml = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
for (const locale of readdirSync(join(app, 'locale'))) {
  const name = `locale/${locale}/translations.xml`;
  let contents = readFileSync(join(app, name), 'utf8');
  if (!contents.includes('<xliff version="1.2">') || !contents.includes('    </body>')) throw new Error(`Expected Roku XLIFF: ${name}`);
  contents = contents.replace(/        <trans-unit id="(?:accounts\.[^"]*|web\.signin\.welcomeHome)">[\s\S]*?<\/trans-unit>\n/g, '');
  const added = Object.entries(messages).map(([id, text]) => `        <trans-unit id="${xml(id)}">\n            <source>${xml(id)}</source>\n            <target>${xml(text)}</target>\n        </trans-unit>\n`).join('');
  contents = contents.replace('    </body>', added + '    </body>');
  emit(name, contents);
}
const route = (file, id) => {
  const found = new RegExp(`"${id}": "([^"]+)"`).exec(source[file]);
  if (!found) throw new Error(`Missing canonical route ${id}`);
  return found[1];
};
const local = 'packages/contracts/src/routes.ts', hosted = 'packages/contracts/src/hosted/routes.ts';
const routes = {
  system: route(local, 'get_system'),
  signInStatus: route(local, 'get_sign_in_settings'),
  localConsentReview: route(local, 'post_quick_connect_review'),
  localConsentDecision: route(local, 'post_quick_connect_decision'),
  porticoConsentReview: route(hosted, 'device_authorization_review'),
  porticoConsentDecision: route(hosted, 'device_authorization_decide'),
  porticoCodeCreate: route(hosted, 'device_authorization_create'),
  porticoCodePoll: route(hosted, 'device_authorization_token'),
  porticoCodeCancel: route(hosted, 'device_authorization_cancel'),
  porticoRefresh: route(hosted, 'session_refresh'),
  porticoRevoke: route(hosted, 'session_revoke'),
  porticoServers: route(hosted, 'servers_list'),
  porticoIdentity: route(hosted, 'server_identity_issue'),
};
const settingsPath = /new URL\('([^']+)',routeOrigin\(serverOrigin\)\)/.exec(source['packages/client-core/src/sign-in.ts']);
if (!settingsPath) throw new Error('Re-read the checked server Sign-in URL function.');
emit('source/core/AccountRoutes.bs', `' Generated by scripts/generate-accounts.mjs from canonical contracts at ${pins.commit}.\n' Do not edit; verified source hashes are in scripts/accounts-source-pins.json.\nnamespace AccountRoutes\n${Object.entries({...routes, signInSettingsPath:settingsPath[1]}).map(([id, path]) => `    const ${id} = ${JSON.stringify(path)}`).join('\n')}\nend namespace\n\nfunction ServerSignInMoveKinds() as object\n    return ${JSON.stringify(moves.enum)}\nend function\n\nfunction SignInMoveStages() as object\n    return ${JSON.stringify(stages)}\nend function\n\nfunction SignInTextControlRanges() as object\n    return ${JSON.stringify(controls)}\nend function\n\nfunction DeviceContractKeys() as object\n    return ${JSON.stringify(deviceKeys)}\nend function\n\nfunction HostedGrantContractKeys() as object\n    return ${JSON.stringify(grantKeys)}\nend function\n\nfunction HostedGrantAccountKeys() as object\n    return ${JSON.stringify(grantAccountKeys)}\nend function\n\nfunction HostedNoticePreferenceKeys() as object\n    return ${JSON.stringify(noticePreferenceKeys)}\nend function\n`);
console.log(`accounts generation ${check ? 'verified' : 'updated'}: ${Object.keys(messages).length} canonical messages and ${Object.keys(routes).length} routes; profile-free Hosted contract`);
