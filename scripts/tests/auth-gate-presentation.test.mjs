import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const gate = read('channel/components/PorticoAuthGate.brs');
const gateXml = read('channel/components/PorticoAuthGate.xml');
const helper = read('channel/source/lib/PorticoAuthGateModels.brs');

assert.match(gateXml, /<Rectangle id="canvas" width="1920" height="1080"/);
assert.doesNotMatch(gateXml + gate, /<PorticoRail|id="railLayer"|server-selection|profileScreen|connectionScreen/i);
for (const state of ['landing', 'account-loading', 'account-code', 'account-error', 'local-loading', 'local-error']) {
  assert.match(gate + helper, new RegExp(`"${state}"`));
}
for (const action of ['start-account-setup', 'sign-in-account', 'account-login', 'account-password', 'account-submit', 'start-local-auth']) {
  assert.match(gate + helper, new RegExp(`"${action}"`));
}
assert.doesNotMatch(gate + helper, /retry-local-auth/);
assert.match(gate, /key = "back"[\s\S]*return true/);
assert.match(gate, /key = "left" or key = "right"[\s\S]*return true/);
assert.match(helper, /localAuthStatus, "unavailable"/);
assert.match(helper, /accountStatus = "authorizing" and code <> "" and verificationUri <> ""/);
assert.match(gateXml, /id="divider"/);
assert.match(gateXml, /id="accountTitle"/);
assert.match(gate, /StandardKeyboardDialog/);
assert.match(gate, /PorticoAuthGateSeal/);
assert.match(gate + helper, /Sign in with server-only authentication/);
assert.match(helper, /runtime\.hostedStatus[\s\S]*= "incompatible"[\s\S]*title: "Update required"/);
assert.match(helper, /Len\(normalized\) <> 9[\s\S]*Mid\(normalized, 5, 1\) <> "-"/);
assert.equal((gate.match(/CreateObject\("roSGNode"/g) ?? []).length, 1);
assert.match(gate, /CreateObject\("roSGNode", "StandardKeyboardDialog"\)/);
assert.doesNotMatch(gate + helper, /fixture|sample/i);

console.log('Verified full-screen signed-out auth gate and model projection contract.');
