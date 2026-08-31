import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoContentTask.brs');
const models = read('channel/source/lib/PorticoContentModels.brs');
const bridge = read('channel/source/lib/PorticoContent.brs');
const overlay = read('channel/components/PorticoDetailMoreScreen.brs');
const overlayXml = read('channel/components/PorticoDetailMoreScreen.xml');
const scene = read('channel/components/PorticoScene.brs');
const sceneXml = read('channel/components/PorticoScene.xml');
const main = read('channel/source/main.brs');
const openapi = JSON.parse(read('../portico-server/api/openapi/portico-server.openapi.json'));

for (const [path, verb] of [
  ['/playlists', 'get'], ['/playlists', 'post'], ['/playlists/{playlistId}/items:batch', 'post'],
  ['/collections', 'get'], ['/collections', 'post'], ['/collections/{collectionId}/memberships:batch', 'post'],
  ['/media/{id}/rating', 'post'], ['/media/{id}/reaction', 'post'], ['/playback-sessions/{sessionId}/queue', 'get'], ['/playback-sessions/{sessionId}/queue', 'patch'],
]) {
  assert.ok(openapi.paths[path]?.[verb], `${verb.toUpperCase()} ${path} disappeared from the Server OpenAPI`);
  assert.equal(openapi.paths[path][verb]['x-portico-auth'], 'session', `${path} must remain session authenticated`);
}

assert.doesNotMatch(sceneXml, /<PorticoDetailMoreScreen id="detailMoreScreen"/, 'Detail More must be lazily created by SceneGraph');
assert.match(overlayXml, /component name="PorticoDetailMoreScreen" extends="Group"/);
assert.match(overlayXml, /<field id="viewState" type="assocarray" onChange="applyViewState"/);
assert.match(overlayXml, /<field id="activation" type="assocarray" alwaysNotify="true"/);
assert.doesNotMatch(overlayXml + overlay, /accessToken|refreshToken|apiBaseUrl|headers/i);

for (const id of ['queue-play-next', 'queue-append', 'open-playlist-targets', 'open-collection-targets', 'open-rating', 'reaction-like', 'reaction-dislike']) assert.match(models, new RegExp(`id: "${id}"`));
assert.match(models, /PorticoContentHasAction\(safeActions, "queue\.add"\) and queueAvailable/);
assert.match(models, /if rating > 0 then description = "Currently " \+ rating\.ToStr\(\) \+ " out of 10"/);
assert.match(models, /if kind = "like" and current = "like" then return "Remove Like"/);
assert.match(models, /if kind = "dislike" and current = "dislike" then return "Remove Dislike"/);

assert.match(task, /"POST", "\/api\/playback\/active"/);
assert.match(task, /"\/api\/playback-sessions\/" \+ sessionId \+ "\/queue"/);
assert.match(task, /queue\.data\.canMutate <> true/);
assert.match(task, /currentId <> "" and currentId <> controller\.detailModel\.id/);
assert.match(task, /"\/api\/" \+ kind \+ "s\?limit=100"/);
assert.match(task, /body = \{ addMediaIds: \[controller\.detailModel\.id\] \}/);
assert.match(task, /if target\.updatedAt <> "" then body\.expectedUpdatedAt = target\.updatedAt/);
assert.match(task, /visibility: "private"/);
assert.match(task, /PorticoDiscoveryCacheRemoveViewer\("saved-cache", controller\)/);
assert.match(task, /PorticoDiscoveryCacheRemoveViewer\("library-cache", controller\)/);
assert.match(task, /"\/api\/media\/" \+ controller\.detailModel\.id \+ "\/" \+ family/);
assert.match(task, /rating < 0 or rating > 10/);
assert.match(task, /reaction <> "like" and reaction <> "dislike" and reaction <> ""/);
assert.match(task, /body = \{ action: position, expectedRevision: controller\.activeQueueRevision, idempotencyKey: PorticoHttpNewRequestId\(\), mediaId: controller\.detailModel\.id \}/);
assert.match(task, /"PATCH", "\/api\/playback-sessions\/" \+ controller\.activeQueueSessionId \+ "\/queue"/);

for (const command of ['open-detail-targets', 'add-detail-target', 'create-detail-target', 'set-detail-rating', 'set-detail-reaction', 'detail-queue']) assert.match(bridge, new RegExp(`"${command}": true`));
assert.match(overlay, /if LCase\(DetailMoreText\(m\.model\.moreActionStatus, "idle", 20\)\) = "working" then return true/);
assert.match(overlay, /if m\.mode = "rating"[\s\S]*DetailMoreRatingKey\(key\)/);
assert.match(overlay, /DetailMoreEmit\("set-detail-rating", \{targetId: m\.mediaId, rating: rating\}\)/);
assert.match(overlay, /DetailMoreEmit\("close-detail-more", \{\}\)/);
assert.match(scene, /sub detailMoreActivationChanged\(\)[\s\S]*emitForwardedActivation\(action\)/);
assert.match(scene, /PorticoSceneEnsureOverlaySurface\("detail-more"\)/);
assert.match(main, /PorticoContentHandleActivation\(content, activationData\)/);

console.log('Verified Detail More capability gating, playlist/collection mutation, rating/reaction, queue revision, and overlay event contracts.');
