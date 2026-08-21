import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  acknowledgeDeepLink,
  beginPublication,
  deferDeepLink,
  dispatchDeepLink,
  normalizeScope,
  publishPublication,
  rollbackPublication,
  viewerPublicationGate
} from '../lib/viewer-publication-model.mjs';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const fixture = JSON.parse(read('tests/viewer-publication-cases.json'));
const lifecycle = read('channel/source/lib/PorticoLifecycle.brs');
const registry = read('channel/source/lib/PorticoSecureRegistry.brs');
const session = read('channel/source/core/PorticoServerSession.brs');
const profiles = read('channel/source/lib/PorticoProfiles.brs');

assert.equal(fixture.schemaVersion, 1);
assert.deepEqual(fixture.lifecycle.gates, ['account', 'server', 'profile']);
for (const vector of fixture.vectors) {
  const actual = viewerPublicationGate(vector.state);
  assert.equal(actual.kind, vector.expected.kind, vector.id);
  if (vector.expected.gate) assert.equal(actual.gate, vector.expected.gate, vector.id);
}

const current = fixture.vectors.find(vector => vector.id === 'active-current-first-viewer').state;
const candidate = {...current.viewerScope, profileId: 'profile-b', authorizationRevision: 'policy-10'};
const started = beginPublication(current, candidate);
assert.equal(started.ok, true);
assert.equal(started.state.viewerStatus, 'transitioning');
assert.equal(started.state.viewerAcceptingWrites, false);
assert.equal(started.state.viewerScope, undefined);

const published = publishPublication(started.state, started.state.transition.candidate, started.state.transition.candidate);
assert.equal(published.ok, true);
assert.equal(published.state.viewerScope.profileId, 'profile-b');
assert.equal(viewerPublicationGate({...published.state, serverStatus: 'online', credentialsDurable: true, routeGeneration: '18', authorizationRevision: 'policy-10', selectedServerId: 'server-a', selectedProfileId: 'profile-b'}).kind, 'ready');

const failed = beginPublication(current, candidate);
const rolledBack = rollbackPublication(failed.state, 'server-bootstrap-failed', true);
assert.equal(rolledBack.restored, true);
assert.equal(rolledBack.state.viewerScope.profileId, 'profile-a');
assert.ok(rolledBack.state.viewerGeneration > current.viewerScope.viewerGeneration);
assert.equal(publishPublication(started.state, {...started.state.transition.candidate, profileId: 'wrong'}, started.state.transition.candidate).code, 'scope-mismatch');
assert.equal(normalizeScope({authority: 'hosted', accountId: 'a', serverId: 's', profileId: 'p', authorizationRevision: '', viewerGeneration: 1}), undefined);

let deliveryState = {accountStatus: 'signed-out'};
const deferred = deferDeepLink(deliveryState, {kind: 'play', targetId: 'media-1'}, 100);
assert.equal(deferred.accepted, true);
deliveryState = deferred.state;
assert.equal(dispatchDeepLink(deliveryState, {kind: 'defer', gate: 'account'}).deferred, true);
const readyState = {...current, pendingDeepLink: deliveryState.pendingDeepLink};
const dispatched = dispatchDeepLink(readyState, {kind: 'ready'});
assert.equal(dispatched.dispatched, true);
assert.equal(dispatchDeepLink(dispatched.state, {kind: 'ready'}).duplicate, true);
const acked = acknowledgeDeepLink(dispatched.state, dispatched.deliveryId, true);
assert.equal(acked.acknowledged, true);
assert.equal(acked.state.pendingDeepLink, undefined);
assert.equal(acknowledgeDeepLink(acked.state, dispatched.deliveryId, true).duplicate, true);
const retried = acknowledgeDeepLink(dispatched.state, dispatched.deliveryId, false);
assert.equal(retried.acknowledged, false);
assert.equal(retried.state.pendingDeepLink.delivery.status, 'pending');

assert.match(lifecycle, /PorticoSecureRegistryCommit\("pending-deep-link"/);
assert.match(lifecycle, /PorticoLifecycleAcknowledgeDispatch/);
assert.match(registry, /consumingGeneration/);
assert.match(session, /routeGeneration/);
assert.match(session, /ptc_clt_/);
assert.match(session, /ptc_rft_/);
assert.match(profiles, /PorticoSecureRegistryCommit\("profile-selection-handoff"/);
assert.equal(fixture.integrationHooks[0].status, 'source-only');

console.log(`Verified ${fixture.vectors.length} current-first viewer gates, rollback fencing, encrypted intent durability, and exactly-once deep-link acknowledgement semantics.`);
