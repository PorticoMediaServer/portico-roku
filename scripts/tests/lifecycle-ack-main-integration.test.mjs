import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {acknowledgeDeepLink, deferDeepLink, dispatchDeepLink} from '../lib/viewer-publication-model.mjs';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const main = read('channel/source/main.brs');
const lifecycle = read('channel/source/lib/PorticoLifecycle.brs');

const observer = 'scene.ObserveField("externalRequestAcknowledgement", port)';
const observerIndex = main.indexOf(observer);
const firstReconcile = main.indexOf('PorticoLifecycleReconcile(lifecycle, scene)');
assert.ok(observerIndex >= 0, 'Main must observe post-consumption Scene acknowledgements');
assert.ok(observerIndex < firstReconcile, 'The external-request observer must be installed before initial dispatch');
assert.doesNotMatch(main, /^\s*scene\.ObserveField\("externalRequest", port\)\s*$/m, 'Main must not observe raw external requests for acknowledgement');

const nodeLoopStart = main.indexOf('if type(message) = "roSGNodeEvent"');
const externalStart = main.indexOf('if field = "externalRequestAcknowledgement"', nodeLoopStart);
const activationStart = main.indexOf('else if field = "activation"', externalStart);
const accountRefreshStart = main.indexOf('else if field = "accountRefreshRequested"', activationStart);
assert.ok(nodeLoopStart >= 0 && externalStart > nodeLoopStart && activationStart > externalStart && accountRefreshStart > activationStart);

const externalBranch = main.slice(externalStart, activationStart);
const activationBranch = main.slice(activationStart, accountRefreshStart);
assert.equal((externalBranch.match(/PorticoLifecycleAcknowledgeDispatch\(/g) ?? []).length, 1);
assert.match(externalBranch, /PorticoLifecycleAcknowledgeDispatch\(lifecycle, message\.GetData\(\)\)/);
assert.doesNotMatch(externalBranch, /PorticoViewerRuntimeAccepting/);
assert.match(externalBranch, /PorticoLifecycleAcknowledgeDispatch\(lifecycle, message\.GetData\(\)\)[\s\S]*PorticoLifecycleReconcile\(lifecycle, scene\)[\s\S]*PorticoLifecycleUpdateBeacons\(lifecycle, scene, invalid\)/);
assert.doesNotMatch(activationBranch, /PorticoLifecycleAcknowledgeDispatch/);
assert.match(activationBranch, /PorticoLifecycleRememberActivation\(lifecycle, activationData, scene\.runtimeState\)/);
assert.match(activationBranch, /PorticoMainBeginAuthoritySwitch\(/);
assert.match(lifecycle, /if controller\.deliveryKind = "gate"[\s\S]*?controller\.deliveryAcknowledgedId = deliveryId[\s\S]*?return true/);

const current = {
  accountStatus: 'signed-in',
  credentialsDurable: true,
  serverStatus: 'online',
  selectedServerId: 'server-a',
  selectedProfileId: 'profile-a',
  viewerStatus: 'active',
  viewerAcceptingWrites: true,
  viewerGeneration: 12,
  routeGeneration: '17',
  authorizationRevision: 'policy-9',
  viewerScope: {
    authority: 'hosted',
    accountId: 'account-a',
    serverId: 'server-a',
    profileId: 'profile-a',
    authorizationRevision: 'policy-9',
    viewerGeneration: 12
  }
};

const deferred = deferDeepLink({accountStatus: 'signed-out'}, {kind: 'play', targetId: 'media-1'}, 100);
const ready = {...current, pendingDeepLink: deferred.state.pendingDeepLink};
const dispatched = dispatchDeepLink(ready, {kind: 'ready'});
assert.equal(dispatched.dispatched, true);

const accepted = acknowledgeDeepLink(dispatched.state, dispatched.deliveryId, true);
assert.equal(accepted.acknowledged, true);
assert.equal(accepted.state.pendingDeepLink, undefined);
assert.equal(acknowledgeDeepLink(accepted.state, dispatched.deliveryId, true).duplicate, true);

const rejected = acknowledgeDeepLink(dispatched.state, dispatched.deliveryId, false);
assert.equal(rejected.acknowledged, false);
assert.equal(rejected.state.pendingDeepLink.delivery.status, 'pending');

console.log('Verified post-consumption lifecycle acknowledgement wiring, gate-safe dispatch handling, unchanged ordinary activation routing, and accepted/rejected/duplicate delivery transitions.');
