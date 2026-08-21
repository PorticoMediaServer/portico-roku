import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const scene = read('channel/components/PorticoScene.brs');
const sceneXml = read('channel/components/PorticoScene.xml');
const developmentSceneXml = read('channel/development/PorticoScene.xml');
const httpTask = read('channel/components/PorticoHttpTask.brs');
const httpHelpers = read('channel/source/lib/PorticoHttpHelpers.brs');
const visualContract = JSON.parse(read('channel/data/visual-contract.json'));
const runtimeContract = JSON.parse(read('channel/data/runtime-ui-contract.json'));
const manifest = read('channel/manifest');
const developmentManifest = read('channel/development/manifest');

const heavySceneTags = [
  'PorticoDeviceAuthorizationTask',
  'PorticoLocalAuthTask',
  'PorticoServerCatalogTask',
  'PorticoServerConnectionTask',
  'PorticoContentTask',
  'PorticoSearchTask',
  'PorticoLibraryTask',
  'PorticoSavedTask',
  'PorticoLiveTvTask',
  'PorticoPlaybackTask',
  'PorticoHttpTask',
  'PorticoHome',
  'PorticoDetail',
  'PorticoSearchScreen',
  'PorticoPersonScreen',
  'PorticoLibraryScreen',
  'PorticoSavedScreen',
  'PorticoChannelsScreen',
  'PorticoProfileScreen',
  'PorticoSettingsScreen',
  'PorticoPlayer',
  'PorticoDetailMoreScreen',
  'PorticoHomeCustomizeOverlay',
  'PorticoDetailSeasonOverlay',
  'PorticoWatchWithFriendsOverlay',
  'PorticoImportantNotice',
  'PorticoFeedbackOverlay'
];

for (const source of [sceneXml, developmentSceneXml]) {
  assert.match(source, /<field id="externalRequestAcknowledgement" type="assocarray" alwaysNotify="true" \/>/);
  assert.match(source, /<Group id="designRoot">/);
  assert.match(source, /<Group id="content"/);
  assert.match(source, /<PorticoRail id="rail" \/>/);
  assert.match(source, /<PorticoStateScreen id="stateScreen"/);
  for (const tag of heavySceneTags) assert.doesNotMatch(source, new RegExp(`<${tag}\\b`), `${tag} must be lazy-owned by PorticoScene`);
}
assert.match(scene, /function PorticoSceneCreateSurface\(/);
assert.match(scene, /function PorticoSceneEnsureRouteSurface\(/);
assert.match(scene, /function PorticoSceneEnsureOverlaySurface\(/);
assert.match(scene, /sub PorticoSceneReleaseInactiveRouteSurfaces\(/);
assert.match(scene, /sub PorticoSceneReleaseClosedOverlays\(/);
assert.match(scene, /parent\.removeChild\(node\)/);
assert.match(scene, /m\.surfaceGeneration = m\.surfaceGeneration \+ 1/);

function responseBudget(headers, maximum = 2 * 1024 * 1024) {
  const transferEncoding = String(headers['transfer-encoding'] ?? '').trim().toLowerCase();
  const rawLength = String(headers['content-length'] ?? '').trim();
  const declaredLength = /^[0-9]+$/.test(rawLength) ? Number(rawLength) : undefined;
  if (declaredLength !== undefined && transferEncoding === '') {
    return {
      ok: declaredLength <= maximum,
      trustedLength: true,
      declaredLength,
      materializationLimit: maximum
    };
  }
  return {
    ok: true,
    trustedLength: false,
    declaredLength: undefined,
    materializationLimit: Math.floor(maximum / 2)
  };
}

assert.equal(responseBudget({'content-length': '1024'}).trustedLength, true);
assert.equal(responseBudget({'content-length': '1024'}).ok, true);
assert.equal(responseBudget({'content-length': String(2 * 1024 * 1024 + 1)}).ok, false);
assert.equal(responseBudget({}).trustedLength, false);
assert.equal(responseBudget({'content-length': 'not-a-length'}).trustedLength, false);
assert.equal(responseBudget({'content-length': '1024', 'transfer-encoding': 'chunked'}).trustedLength, false);
assert.equal(responseBudget({}).materializationLimit, 1024 * 1024);

assert.match(httpHelpers, /function PorticoHttpResponseContentLength\(/);
assert.match(httpHelpers, /function PorticoHttpResponseBudget\(/);
assert.match(httpHelpers, /transferEncoding = LCase\(/);
assert.match(httpHelpers, /declared <> invalid and transferEncoding = ""/);
assert.match(httpHelpers, /maximumResponseBytes \/ 2/);
assert.match(httpTask, /AsyncGetToFile\(responsePath\)/);
assert.match(httpTask, /PorticoHttpDeleteResponseFile\(request\)/);
const budgetIndex = httpTask.indexOf('budget = PorticoHttpResponseBudget');
const readBodyIndex = httpTask.indexOf('bodyResult = PorticoHttpReadResponseBody');
assert.ok(budgetIndex >= 0 && budgetIndex < readBodyIndex, 'Response budget must be decided before body materialization');
const fileSizeIndex = httpTask.indexOf('size = PorticoHttpFileSize(path)');
const readFileIndex = httpTask.indexOf('body = ReadAsciiFile(path)');
assert.ok(fileSizeIndex >= 0 && fileSizeIndex < readFileIndex, 'File response size must be checked before ReadAsciiFile');
const boundedEventIndex = httpTask.indexOf('if budget.trustedLength <> true then return');
const getStringIndex = httpTask.indexOf('body = event.GetString()');
assert.ok(boundedEventIndex >= 0 && boundedEventIndex < getStringIndex, 'Undeclared mutation responses must fail before GetString');

function deriveLayout(contract, mode) {
  const layout = contract.layout;
  const design = layout.designCanvas;
  const display = layout.displayModes[mode];
  const scale = Math.min(display.width / design.width, display.height / design.height);
  const safeZonePixels = Object.fromEntries(Object.entries(display.safeZone).map(([key, value]) => [key, Math.floor(value * scale)]));
  return {mode, scale, safeZoneDesign: display.safeZone, safeZonePixels};
}

for (const contract of [visualContract, runtimeContract]) {
  assert.deepEqual(Object.keys(contract.layout.displayModes).sort(), ['fhd', 'hd']);
  assert.deepEqual(contract.layout.designCanvas, contract.canvas);
  const hd = deriveLayout(contract, 'hd');
  const fhd = deriveLayout(contract, 'fhd');
  assert.equal(hd.scale, 2 / 3);
  assert.equal(fhd.scale, 1);
  assert.deepEqual(hd.safeZonePixels, {left: 48, top: 36, right: 48, bottom: 36});
  assert.deepEqual(fhd.safeZonePixels, {left: 72, top: 54, right: 72, bottom: 54});
}
assert.match(scene, /function PorticoSceneDisplayMode\(/);
assert.match(scene, /function PorticoSceneApplyGeometry\(/);
assert.match(scene, /safeZoneDesign:/);
assert.match(scene, /safeZonePixels:/);
assert.match(scene, /m\.designRoot\.scale = \[scale, scale\]/);
assert.match(scene, /m\.designRoot\.translation =/);
for (const sourceManifest of [manifest, developmentManifest]) {
  const resolutionLine = sourceManifest.match(/^ui_resolutions=(.+)$/m)?.[1] ?? '';
  assert.deepEqual(new Set(resolutionLine.toLowerCase().split(',')), new Set(['fhd']));
}

const dispatchKinds = new Set([
  'route',
  'open-detail',
  'play',
  'select-person',
  'watch-load',
  'select-profile',
  'local-submit-credentials',
  'watch-with-friends-overlay-action'
]);
function validateDispatch(action, state) {
  if (!action || typeof action !== 'object' || typeof action.kind !== 'string' || !/^[a-z0-9][a-z0-9._-]*$/i.test(action.kind)) return false;
  if (!dispatchKinds.has(action.kind)) return false;
  if (['route', 'open-detail', 'play', 'select-person', 'watch-load'].includes(action.kind) && !action.targetId) return false;
  if (action.kind === 'route' && !action.route) return false;
  if (action.kind === 'select-profile' && !action.profileId) return false;
  if (action.kind === 'local-submit-credentials' && !action.sealedCredentials) return false;
  if (action.kind === 'watch-with-friends-overlay-action' && !action.overlayAction) return false;
  if (action.viewerGeneration !== undefined && action.viewerGeneration !== state.viewerGeneration) return false;
  if (action.lifecycleGeneration !== undefined && action.lifecycleGeneration !== state.lifecycleGeneration) return false;
  if (['privateContent', 'credential', 'accessToken', 'refreshToken'].some(key => key in action)) return false;
  return Object.keys(action).length <= 16;
}

const current = {viewerGeneration: 7, lifecycleGeneration: 3};
assert.equal(validateDispatch({kind: 'open-detail', targetId: 'media-1', viewerGeneration: 7, lifecycleGeneration: 3}, current), true);
assert.equal(validateDispatch({kind: 'open-detail', targetId: 'media-1', viewerGeneration: 6}, current), false);
assert.equal(validateDispatch({kind: 'open-detail', targetId: 'media-1', lifecycleGeneration: 2}, current), false);
assert.equal(validateDispatch({kind: 'open-detail'}, current), false);
assert.equal(validateDispatch({kind: 'unknown-action', targetId: 'media-1'}, current), false);
assert.equal(validateDispatch({kind: 'select-profile', profileId: 'profile-1'}, current), true);
assert.equal(validateDispatch({kind: 'open-detail', targetId: 'media-1', accessToken: 'secret'}, current), false);
assert.match(scene, /function PorticoSceneDispatchSpec\(/);
assert.match(scene, /function PorticoSceneValidateDispatch\(/);
assert.match(scene, /function PorticoScenePublishActivation\(/);
assert.match(scene, /sub PorticoScenePublishExternalRequestAcknowledgement\(/);
assert.match(scene, /m\.lifecycleGeneration = m\.lifecycleGeneration \+ 1/);
assert.match(scene, /action\.lifecycleGeneration <> invalid/);
assert.match(scene, /action\.viewerGeneration <> invalid/);
assert.match(scene, /if not PorticoScenePublishActivation\(\{[\s\S]*kind: "route"/);

console.log('Verified lazy SceneGraph ownership, bounded Roku HTTP response handling, HD/FHD geometry, safe zones, and lifecycle-fenced dispatch models.');
