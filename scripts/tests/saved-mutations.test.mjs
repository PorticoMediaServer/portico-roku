import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoSavedTask.brs');
const taskXml = read('channel/components/PorticoSavedTask.xml');
const models = read('channel/source/lib/PorticoSavedModels.brs');
const bridge = read('channel/source/lib/PorticoSaved.brs');
const browseApi = read('channel/source/lib/PorticoBrowseApi.brs');
const discoveryRuntime = read('channel/source/lib/PorticoDiscoveryRuntime.brs');
const contentBridge = read('channel/source/lib/PorticoContent.brs');
const main = read('channel/source/main.brs');
const registry = read('channel/source/lib/PorticoSecureRegistry.brs');
const openapi = JSON.parse(read('../../apps/portico-server/api/openapi/portico-server.openapi.json'));

for (const [path, verb] of [
  ['/watchlist', 'get'], ['/favorites', 'get'], ['/playlists', 'get'], ['/playlists/{playlistId}/items', 'get'],
  ['/collections', 'get'], ['/collections/{collectionId}/items', 'get'], ['/saved-views', 'get'], ['/saved-views/{savedViewId}/browse', 'post'],
  ['/media/{id}/watchlist', 'post'], ['/media/{id}/favorite', 'post'], ['/media/{id}/watched', 'post'],
]) {
  assert.ok(openapi.paths[path]?.[verb], `${verb.toUpperCase()} ${path} disappeared from the Server OpenAPI`);
  assert.equal(openapi.paths[path][verb]['x-portico-auth'], 'session', `${path} must remain session authenticated`);
}

assert.match(taskXml, /component name="PorticoSavedTask" extends="Task"/);
assert.match(taskXml, /<field id="command" type="assocarray"/);
assert.match(taskXml, /<field id="projection" type="assocarray" alwaysNotify="true"/);
assert.doesNotMatch(taskXml, /field id="(?:accessToken|refreshToken|apiBaseUrl|headers|serverSession)"/i);
for (const script of ['PorticoContentModels', 'PorticoBrowseModels', 'PorticoBrowseApi', 'PorticoSavedModels']) assert.match(taskXml, new RegExp(`${script}\\.brs`));

for (const tab of ['watchlist', 'favorites', 'playlists', 'collections', 'saved-views']) assert.match(models, new RegExp(`id: "${tab}"`));
assert.match(task, /"\/api\/" \+ tabId \+ "\?limit=50"/);
assert.match(task, /"\/api\/saved-views\/" \+ controller\.selectedResourceId \+ "\/browse"/);
assert.match(task, /"\/api\/" \+ tabId \+ "\/" \+ controller\.selectedResourceId \+ "\/items\?limit=50"/);
assert.match(task, /PorticoSavedMergeUnique\(controller\.page\.items, normalized\.items, PorticoSavedBufferMaximum\(controller\)\)/);
assert.match(models, /if items\.count\(\) >= 200 then exit for/);
assert.match(models, /if resources\.count\(\) >= 100 then exit for/);

const mutation = task.match(/sub PorticoSavedRunMutation[\s\S]*?\nend sub/)?.[0] ?? '';
assert.ok(mutation.length > 0, 'Saved mutation worker is missing');
assert.match(mutation, /if mutation\.family = "watchlist" then bodyKey = "watchlisted"/);
assert.match(mutation, /"\/api\/media\/" \+ mutation\.mediaId \+ "\/" \+ mutation\.family/);
assert.ok(mutation.indexOf('controller.nonInterruptibleRequest = true') < mutation.indexOf('PorticoDiscoveryRequest'), 'Mutation must become non-interruptible before its write starts');
assert.ok(mutation.indexOf('PorticoDiscoveryRequest') < mutation.indexOf('controller.nonInterruptibleRequest = false'), 'Mutation guard must remain set through the write');
assert.match(browseApi, /if controller\.nonInterruptibleRequest = true then return false/);
assert.match(discoveryRuntime, /if interrupted and \(controller\.nonInterruptibleRequest <> true or PorticoDiscoveryViewerInterrupted\(controller\)\)/);
assert.match(mutation, /if succeeded[\s\S]*PorticoSavedApplyMutationToPage[\s\S]*controller\.requestKind = "page"/);

assert.match(bridge, /controller\.latestMutations\[key\] = \{ token: token, previous: current\.value, desired: desired \}/);
assert.match(bridge, /mutationCommands: \[\], mutationInFlight: false/);
assert.match(bridge, /controller\.mutationCommands\.count\(\) >= 32/);
assert.match(bridge, /if controller\.mutationInFlight or controller\.mutationCommands\.count\(\) = 0 then return/);
assert.match(bridge, /controller\.mutationInFlight = false[\s\S]*PorticoSavedDrainMutationCommand\(controller\)/);
assert.match(bridge, /PorticoSavedJournalMutation\(optimistic, mediaId, family, desired, token\)/);
assert.match(bridge, /if result\.succeeded <> true[\s\S]*PorticoSavedPatchRuntime\(nextState, mediaId, family, pending\.previous\)/);
assert.match(bridge, /PorticoSavedRemoveJournalMutation\(nextState, mediaId, family, pending\.token\)/);
assert.match(bridge, /nextState = PorticoSavedApplyPendingRuntimeMutations\(nextState\)/);
assert.match(contentBridge, /PorticoSavedMutationResolvedValue\(runtime, projection\)/);
assert.match(contentBridge, /kind: "sync-media-state"/);
assert.match(main, /PorticoSavedSynchronizeContentInvalidation\(saved, scene\.runtimeState\)/);
assert.match(main, /PorticoContentSynchronizeSavedMutation\(content, scene\.runtimeState, acceptedSavedProjection\)/);
assert.match(main, /PorticoSearchSynchronizeSavedMutation\(search, scene\.runtimeState, acceptedSavedProjection\)/);
assert.match(main, /PorticoLibrarySynchronizeSavedMutation\(library, scene\.runtimeState, acceptedSavedProjection\)/);

assert.match(registry, /recordType <> "saved-cache"/);
assert.match(task, /payload\.cacheBinding <> controller\.cacheBinding/);
assert.match(task, /PorticoDiscoveryCacheRemoveViewer\("saved-cache", controller\)/);
assert.match(models, /PorticoBrowseCachedItems\(source\.items, 21\)/);
assert.doesNotMatch(models.match(/function PorticoSavedCacheView[\s\S]*?end function/)?.[0] ?? '', /accessToken|refreshToken|apiBaseUrl|headers/);

console.log('Verified Saved resource paging, durable cache boundaries, optimistic mutation rollback, and cross-surface synchronization.');
