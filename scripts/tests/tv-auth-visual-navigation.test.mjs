import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const action = read('channel/components/PorticoAuthAction.brs');
const actionXml = read('channel/components/PorticoAuthAction.xml');
const gate = read('channel/components/PorticoAuthGate.brs');
const gateXml = read('channel/components/PorticoAuthGate.xml');
const gateModels = read('channel/source/lib/PorticoAuthGateModels.brs');
const local = read('channel/components/PorticoLocalAuthScreen.brs');
const scene = read('channel/components/PorticoScene.brs');
const task = read('channel/components/PorticoDeviceAuthorizationTask.brs');
const assetGenerator = read('scripts/generate-assets.mjs');
const developmentContract = JSON.parse(read('channel/data/visual-contract.json'));
const runtimeContract = JSON.parse(read('channel/data/runtime-ui-contract.json'));

// A TV action is a large, focusable surface. Credential rows are the sole
// exception: they remain dark inset fields with a visible focus outline.
assert.match(actionXml, /width="560" height="72"/);
assert.match(action, /m\.top\.focusable = true/);
assert.match(action, /isField = actionId = "account-login" or actionId = "account-password"/);
assert.match(action, /auth-field-idle\.png/);
assert.match(action, /auth-field-focus\.png/);
assert.match(action, /auth-action-primary\.png/);
assert.match(action, /auth-action-primary-focus\.png/);
assert.doesNotMatch(action, /auth-action-(?:secondary|tertiary)/);
assert.match(action, /m\.label\.color = "#070B10"/);
assert.deepEqual(runtimeContract.auth, developmentContract.auth);
assert.deepEqual(runtimeContract.controls, developmentContract.controls);
assert.deepEqual(runtimeContract.auth.action, {
  width: 560,
  height: 72,
  radius: 8,
  fill: '#70BCE8',
  focusFill: '#378EC3',
  text: '#070B10'
});
assert.equal(runtimeContract.auth.tvNavigation.inlineLinks, false);
assert.equal(runtimeContract.auth.tvNavigation.backUnwindsSubpage, true);
assert.deepEqual(runtimeContract.auth.legal, {focusable: false, termsUrl: 'getportico.tv/terms', privacyUrl: 'getportico.tv/privacy'});
assert.match(gateXml, /<Label id="legalNotice"/);
assert.match(gateXml, /<Label id="legalUrls"/);
assert.match(gate, /Terms: getportico\.tv\/terms  •  Privacy: getportico\.tv\/privacy/);
assert.doesNotMatch(gateXml, /<(?:PorticoAuthAction|Button)[^>]*id="legal/);
assert.equal(runtimeContract.controls.primaryFill, '#70BCE8');
assert.equal(runtimeContract.controls.primaryText, '#070B10');
assert.match(assetGenerator, /\['button-primary\.png', 166, 64,[^\n]*'#70BCE8'/);
assert.match(assetGenerator, /\['button-primary-focus\.png', 166, 64,[^\n]*'#378EC3'[^\n]*'#EAF6FF'/);
assert.match(assetGenerator, /\['auth-field-idle\.png', 560, 72,[^\n]*'#101820'/);

// TV auth never exposes small web-style account-management links.
assert.doesNotMatch(gate + gateModels + local, /Forgot Password|Forgot password|Create Account|Create account/);
assert.doesNotMatch(gate + gateModels, /label: "Try Again"/);
assert.match(gateModels, /label: "Request New Code"/);
assert.match(gateModels, /accountStatus = "authorization-denied"[\s\S]*accountSignInError, true/);
assert.match(gateModels, /accountStatus = "authorization-expired"[\s\S]*Portico will create a new one automatically\.[\s\S]*accountSignInError\)/);
assert.match(gateModels, /accountStatus = "authorization-interrupted"[\s\S]*Portico will create a new code automatically\.[\s\S]*accountSignInError\)/);

// Back from the local credential sub-flow is consumed and returned to the
// signed-out landing page before Roku may close the channel from its root.
assert.match(local, /key = "back"[\s\S]*emitLocalActivation\("local-back", invalid\)[\s\S]*return true/);
assert.match(scene, /if kind = "local-back"[\s\S]*m\.signedOutGateMode = "landing"/);
assert.match(gate, /if m\.stateName <> "landing"[\s\S]*emitAuthGateActivation\(\{id: "back-auth-landing"\}\)[\s\S]*return true[\s\S]*return false/);

// Hosted activation recovers itself every five seconds while active, honors a
// longer Retry-After, and stops its timer when the user leaves account auth.
const creationRetry = task.match(/sub PorticoAuthorizationTaskScheduleCreationRetry[\s\S]*?end sub/)?.[0] ?? '';
const authorizationRetry = task.match(/sub PorticoAuthorizationTaskScheduleAuthorizationRetry[\s\S]*?end sub/)?.[0] ?? '';
const pause = task.match(/sub PorticoAuthorizationTaskPause[\s\S]*?end sub/)?.[0] ?? '';
const tick = task.match(/sub PorticoAuthorizationTaskTick[\s\S]*?end sub/)?.[0] ?? '';
const terminal = task.match(/sub PorticoAuthorizationTaskTerminal[\s\S]*?end sub/)?.[0] ?? '';
const expired = task.match(/sub PorticoAuthorizationTaskRenewExpiredSession[\s\S]*?end sub/)?.[0] ?? '';
for (const retry of [creationRetry, authorizationRetry]) {
  assert.match(retry, /delay = 5/);
  assert.match(retry, /retryAfter <> invalid and retryAfter > delay/);
  assert.match(retry, /nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds\(controller\) \+ delay/);
  assert.doesNotMatch(retry, /multiplier|exponent/);
}
assert.match(pause, /controller\.authorizationActive = false/);
assert.match(pause, /controller\.authorizationRequested = false[\s\S]*if not controller\.authorizationActive then return/);
assert.match(tick, /if controller\.authorizationActive and nowSeconds >= controller\.nextAuthorizationAtSeconds/);
assert.match(terminal, /selfHealing = accountStatus = "authorization-expired" or accountStatus = "authorization-interrupted"/);
assert.match(terminal, /if selfHealing[\s\S]*PorticoSecureRegistryClear\("pending-account-authorization"\)[\s\S]*controller\.authorizationActive = true[\s\S]*nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds\(controller\) \+ 5[\s\S]*PorticoAuthorizationTaskPublish\("authorizing", "connecting"\)/);
assert.match(terminal, /if not controller\.authorizationRequested[\s\S]*PorticoAuthorizationTaskPublish\("signed-out", "unknown"\)[\s\S]*return/);
assert.match(expired, /nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds\(controller\) \+ 5/);
assert.match(gateModels, /Portico will continue automatically when this TV is back online\./);
assert.match(gateModels, /This is taking longer than usual\. Portico will keep trying automatically\./);
assert.match(task, /controller\.hostedFailureKind = "service"[\s\S]*if result\.status = 0 then controller\.hostedFailureKind = "offline"/);
assert.match(task, /authorizationStartedAtSeconds: -1/);
assert.match(task, /PorticoAuthorizationTaskDelayedHostedStatus\(controller, hostedStatus\)/);
assert.match(task, /PorticoAuthorizationTaskNowSeconds\(controller\) - startedAt < 8 then return "connecting"/);

console.log('Verified the canonical Roku TV auth visual, retry, and Back-navigation contract.');
