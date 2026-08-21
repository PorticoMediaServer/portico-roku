import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');

const identity = (generation, profileId = `profile-${generation}`) => ({
  authority: 'local', accountId: 'account-1', serverId: 'server-1', profileId,
  authorizationRevision: String(generation), viewerGeneration: generation,
});
const sameScope = (left, right) => ['authority', 'accountId', 'serverId', 'profileId', 'authorizationRevision', 'viewerGeneration']
  .every(field => left?.[field] === right?.[field]);

function fenceWatchWithFriends(controller) {
  return {...controller, groups: [], group: null, selectedGroupId: '', localPlayback: null, syncState: null,
    syncDirective: null, transport: null, mutationInFlight: false, status: 'idle', errorCode: ''};
}
function acceptCompletion(controller, request) {
  return sameScope(controller.scope, request.scope) && controller.registryGeneration === request.registryGeneration
    ? {...controller, groups: request.groups}
    : controller;
}

const oldController = {
  scope: identity(7), registryGeneration: 20, groups: [{id: 'old-group', name: 'Private movie night', mediaTitle: 'Old title'}],
  group: {id: 'old-group'}, selectedGroupId: 'old-group', localPlayback: {mediaId: 'old-media'}, transport: {active: true}, status: 'active',
};
const oldRequest = {scope: oldController.scope, registryGeneration: 20, groups: [{id: 'late-old-group', mediaTitle: 'Old title'}]};
const replacement = {...fenceWatchWithFriends(oldController), scope: identity(8), registryGeneration: 21};
assert.deepEqual(replacement.groups, []);
assert.equal(replacement.group, null);
assert.equal(replacement.localPlayback, null);
assert.equal(replacement.transport, null);
assert.deepEqual(acceptCompletion(replacement, oldRequest), replacement, 'late old-viewer response repopulated replacement scope');
assert.deepEqual(acceptCompletion(replacement, {...oldRequest, scope: replacement.scope}), replacement, 'old session generation crossed device/session replacement');
const currentRequest = {scope: replacement.scope, registryGeneration: 21, groups: [{id: 'new-group', mediaTitle: 'New title'}]};
assert.deepEqual(acceptCompletion(replacement, currentRequest).groups, currentRequest.groups);

const runtime = read('channel/source/lib/PorticoViewerRuntimeController.brs');
for (const field of ['homeModel', 'detailModel', 'searchViewState', 'personViewState', 'libraryViewState', 'savedViewState', 'savedMutationResolution', 'savedMutationError', 'channelsViewState', 'playbackViewState', 'watchWithFriendsViewState', 'notificationsViewState', 'engagementViewState']) {
  assert.match(runtime, new RegExp(`${field}:`), `viewer transition clear patch omitted ${field}`);
}
const watchTask = read('channel/components/PorticoWatchWithFriendsTask.brs');
assert.match(watchTask, /PorticoWatchWithFriendsFence[\s\S]*controller\.groups = \[\]/, 'RK-02 old groups are not synchronously destroyed');
assert.match(watchTask, /PorticoWatchWithFriendsSessionStillCurrent\(controller, session\)/, 'late group responses are not session fenced');
const discovery = read('channel/source/lib/PorticoDiscoveryRuntime.brs');
assert.match(discovery, /PorticoDiscoveryViewerInterrupted\(controller\)/, 'noninterruptible mutations can cross viewer scope');
assert.match(discovery, /PorticoDiscoverySessionStillCurrent\(controller, session\)/, 'content results can cross a replaced session/device');
const live = read('channel/components/PorticoLiveTvTask.brs');
assert.match(live, /previousGeneration[\s\S]*PorticoLiveTvFence\(controller\)/, 'Live TV projections are not cleared on generation change');
for (const path of [
  'channel/components/PorticoApplicationEventsTask.brs',
  'channel/components/PorticoEngagementTask.brs',
  'channel/source/lib/PorticoPlaybackEventsRuntime.brs',
]) assert.match(read(path), /session[_-]fenced|session_fenced/, `${path} does not fence a response from a replaced session`);

console.log('Verified synchronous viewer clearing and late task/session response fencing across Package A domains.');
