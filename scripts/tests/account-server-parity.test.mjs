import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const authorization = read(
  'channel/components/PorticoDeviceAuthorizationTask.brs',
);
const settings = read('channel/source/lib/PorticoSettingsModels.brs');
const scene = read('channel/components/PorticoScene.brs');

assert.match(
  authorization,
  /PorticoAuthorizationTaskPendingLifetimeIsValid[\s\S]*remaining >= 540 and remaining <= 630/,
);
assert.match(
  authorization,
  /https:\/\/web\.getportico\.tv\/authorize-device/,
);
assert.match(
  authorization,
  /else if controller\.renewalPending[\s\S]*PorticoAuthorizationTaskCreate\(controller, true\)/,
);
assert.match(
  authorization,
  /renewalAtSeconds = nowSeconds \+ remaining - 30[\s\S]*nextAuthorizationAtSeconds >= renewalAtSeconds/,
);
const replacement =
  authorization.match(
    /sub PorticoAuthorizationTaskCreate[\s\S]*?end sub/,
  )?.[0] ?? '';
assert.match(
  replacement,
  /PorticoSecureRegistryCommit\("pending-account-authorization", pending\)[\s\S]*controller\.pending = pending/,
);
assert.doesNotMatch(
  replacement,
  /PorticoSecureRegistryClear\("pending-account-authorization"\)/,
);

assert.match(
  settings,
  /PorticoSettingsServerCount\(runtime\.availableServers\) > 1/,
);
assert.match(
  settings,
  /id: "server"[\s\S]*visible: serverRowVisible/,
);
const switchVisible = (authMode, serverCount) =>
  authMode !== 'local' && serverCount > 1;
assert.equal(switchVisible('hosted', 0), false);
assert.equal(switchVisible('hosted', 1), false);
assert.equal(switchVisible('hosted', 2), true);

assert.match(
  scene,
  /id: "empty"[\s\S]*status: "ACCOUNT READY"[\s\S]*statusTone: "account"/,
);
assert.match(
  scene,
  /Your Portico Account is signed in\. When you create a server or someone shares one with you, it will appear here\./,
);

console.log(
  'Verified Roku ten-minute activation, atomic renewal, account-first zero-server state, and server-switch visibility.',
);
