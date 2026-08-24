import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');

const task = read('channel/components/PorticoContentTask.brs');
const taskXml = read('channel/components/PorticoContentTask.xml');
const models = read('channel/source/lib/PorticoContentModels.brs');
const bridge = read('channel/source/lib/PorticoContent.brs');
const registry = read('channel/source/lib/PorticoSecureRegistry.brs');
const httpHelpers = read('channel/source/lib/PorticoHttpHelpers.brs');
const main = read('channel/source/main.brs');
const scene = read('channel/components/PorticoScene.brs');
const sceneXml = read('channel/components/PorticoScene.xml');
const rokuHome = read('channel/components/PorticoHome.brs');
const rokuHomeShelf = read('channel/components/PorticoHomeShelf.brs');
const rokuDetail = read('channel/components/PorticoDetail.brs');
const client = read('../portico-server/packages/portico-client-core/src/client.ts');
const homeScreen = read('../portico-react-native/packages/app/src/ui/screens/HomeScreen.tsx');
const detailScreen = read('../portico-react-native/packages/app/src/ui/screens/DetailPlayerScreens.tsx');
const mediaAdapters = read('../portico-react-native/packages/app/src/data/mediaAdapters.ts');
const detailAdapter = read('../portico-react-native/packages/app/src/data/detail.ts');
const openapi = JSON.parse(read('../portico-server/api/openapi/portico-server.openapi.json'));

for (const path of ['/home', '/home/rows/{id}', '/media/{id}']) {
  assert.ok(openapi.paths[path]?.get, `${path} disappeared from the Server OpenAPI`);
  assert.equal(openapi.paths[path].get['x-portico-auth'], 'session', `${path} must remain session-authenticated`);
}
assert.equal(openapi.paths['/home/rows/{id}'].get.parameters.find(parameter => parameter.name === 'limit')?.schema?.maximum, 50);

assert.match(client, /home:\s*\([^)]*\)\s*=>\s*request<HomeResponse>\("\/api\/home"/s);
assert.match(client, /homeRow:[\s\S]*?return request<HomeRow>\([\s\S]*?`\/api\/home\/rows\//);
assert.match(client, /media: .*includeRecommendations/s);
assert.match(homeScreen, /client\.home\(\{signal\}\)/);
assert.match(homeScreen, /const rowId = row\.id;[\s\S]*const cursor = row\.nextCursor;[\s\S]*client\.homeRow\(rowId, \{cursor, limit: 24\}\)/);
assert.match(detailScreen, /client\.media\(mediaId, \{includeRecommendations: true\}/);
assert.match(mediaAdapters, /\.filter\(row => \(row\.required \|\| !hidden\.has\(row\.id\)\) && \(row\.defaultVisible \|\| order\.has\(row\.id\)\)\)/);
assert.doesNotMatch(mediaAdapters, /\.filter\(row => row\.items\.length > 0\)/, 'Advertised Home rows must remain available for ordered slot reservation');
assert.doesNotMatch(mediaAdapters, /continuityRank/, 'Clients must not replace authoritative Home ordering with invented priority');
assert.match(homeScreen, /reserveOrderedSurfaceSlots/);
assert.match(homeScreen, /client\.homeRow\(row\.id, \{limit: 24\}, \{signal\}\)/);
assert.match(homeScreen, /slot\.resolution === 'ready'/);
assert.match(homeScreen, /slot\.resolution === 'failed'/);
assert.doesNotMatch(homeScreen, /ReservedHomeRow/, 'Empty and pending Home rows must not reserve visible shelf space');
assert.match(detailAdapter, /episodeItems\(item\)\.map/);
assert.match(detailAdapter, /item\.recommendationRows/);

assert.match(taskXml, /component name="PorticoContentTask" extends="Task"/);
assert.match(taskXml, /<field id="command" type="assocarray"/);
assert.match(taskXml, /<field id="projection" type="assocarray"/);
assert.doesNotMatch(taskXml, /field id="(?:accessToken|refreshToken|apiBaseUrl|serverSession|headers)"/i);
assert.match(taskXml, /pkg:\/source\/lib\/PorticoContentModels\.brs/);
assert.match(taskXml, /pkg:\/components\/PorticoContentTask\.brs/);
assert.doesNotMatch(bridge, /findNode\(/, 'Main-thread controllers must never rendezvous with Scene nodes after screen.Show');
assert.match(bridge, /CreateObject\("roSGNode", "PorticoContentTask"\)/);
assert.doesNotMatch(sceneXml, /<PorticoContentTask id="contentTask" \/>/, 'Content Task must be created by its owning bridge');
assert.match(main, /PorticoContentController\(scene, port, viewerRuntime\)/);
assert.match(main, /PorticoContentHandleActivation\(content, (?:message\.GetData\(\)|activationData)\)/);
assert.match(main, /PorticoContentViewerStateChanged\(content, viewerController, contractRevision, domainState\)/);
assert.match(main, /sourceNode\.IsSameNode\(content\.task\)/);
assert.match(main, /PorticoContentHandleNodeEvent\(content, message, viewerRuntime\)/);
assert.doesNotMatch(main + scene, /accessToken|refreshToken|apiBaseUrl/);

assert.match(task, /PorticoContentGet\(controller, session, "\/api\/home"\)/);
assert.match(task, /"\/api\/media\/" \+ mediaId \+ "\?includeRecommendations=true"/);
assert.match(task, /PorticoHttpValidatePrivateRequest\(request\)/);
assert.match(task, /SetCertificatesFile\("common:\/certs\/ca-bundle\.crt"\)/);
assert.match(task, /EnablePeerVerification\(true\)/);
assert.match(task, /EnableHostVerification\(true\)/);

const sessionReader = task.match(/function PorticoContentSessionForController[\s\S]*?end function/)?.[0] ?? '';
assert.ok(sessionReader.length > 0, 'Content Task must own one narrow server-session reader');
assert.equal((task.match(/PorticoSecureRegistryRead\("server-session"\)/g) ?? []).length, 1, 'Content Task may read the raw server session in one narrow function only');
assert.match(sessionReader, /if controller\.envelopeMode then return PorticoDiscoverySessionForController\(controller\)/);
assert.match(sessionReader, /session\.version <> 1/);
assert.match(sessionReader, /PorticoContentSafeId\(session\.serverId\) <> serverId/);
assert.match(sessionReader, /PorticoContentSecureBaseUrl\(session\.apiBaseUrl\)/);
assert.match(sessionReader, /not PorticoHttpServerAccessTokenValid\(accessToken\)/);
assert.match(httpHelpers, /function PorticoHttpServerAccessTokenValid[\s\S]*prefix = "ptc_clt_" or prefix = "ptc_loc_"/);
for (const binding of ['accountUserId', 'accountDeviceId', 'membershipId']) assert.match(sessionReader, new RegExp(`PorticoContentSafeId\\(session\\.${binding}\\)`));
assert.match(sessionReader, /cacheBinding: accountUserId \+ "\|" \+ accountDeviceId \+ "\|" \+ membershipId/);
assert.match(sessionReader, /PorticoSignedDocumentSecondsUntil\(session\.accessExpiresAt\)/);
assert.match(sessionReader, /remaining <= 0/);

for (const forbidden of ['accessToken', 'refreshToken', 'apiBaseUrl', 'headers']) {
  assert.ok(!bridge.includes(`${forbidden}: true`), `${forbidden} must not be a public bridge projection`);
}
for (const allowed of ['homeStatus', 'homeModel', 'detailStatus', 'detailMediaId', 'detailModel']) {
  assert.match(bridge, new RegExp(`${allowed}: true`));
}

assert.match(registry, /recordType <> "content-cache"/);
assert.match(task, /PorticoDiscoveryCacheCommit\("content-cache", controller, "content", "home-and-detail", payload\)/);
assert.match(task, /PorticoDiscoveryCacheRead\("content-cache", controller, "content", "home-and-detail"\)/);
assert.match(task, /payload\.cacheBinding <> controller\.cacheBinding/);
assert.match(task, /serverId: controller\.serverId, cacheBinding: controller\.cacheBinding/);
assert.match(task, /PorticoContentCachedHome\(normalized\.model\)/);
assert.match(task, /PorticoContentCachedDetail\(normalized\.model\)/);
assert.match(models, /function PorticoContentCachedHome/);
assert.match(models, /function PorticoContentCachedDetail/);
const cachedModels = models.slice(models.indexOf('function PorticoContentCachedHome'), models.indexOf('function PorticoContentSafeActions'));
assert.doesNotMatch(cachedModels, /\.poster\b|\.backdrop\b|\.artwork\b|tmp:\//, 'Durable content projections must strip artwork URIs');

assert.match(task, /AsyncGetToFile\(tempPath\)/);
assert.match(task, /sourceDigest = PorticoBrowseArtworkDigest\(job\.source/);
assert.match(task, /for each extension in \["jpg", "png", "gif"\][\s\S]*PorticoContentTouchArtwork\(controller, cachedPath\)[\s\S]*return cachedPath/);
assert.equal((task.match(/^[ \t]+PorticoContentClearArtworkDirectory\(controller\)/gm) ?? []).length, 0, 'Content artwork cache must not clear during ordinary viewer/server changes');
assert.match(task, /headers: \{ Authorization: "Bearer " \+ session\.accessToken \}/);
assert.match(task, /tempPath = "tmp:\/portico-content\//);
assert.match(task, /contentType, 10\) = "image\/jpeg"/);
assert.match(task, /contentType, 9\) = "image\/png"/);
assert.match(task, /contentType, 9\) = "image\/gif"/);
assert.doesNotMatch(task, /(?:access_token|accessToken|token)=/i, 'Content credentials must never enter artwork query strings');
assert.match(models, /Left\(path, 5\) <> "\/api\/"/);
assert.match(models, /Instr\(1, route, "\.\."\) > 0/);
assert.match(models, /Instr\(1, lowerRoute, "%2e"\) > 0/);

assert.match(task, /reconnect = missingSession or status = 401/);
assert.match(task, /controller\.reconnectRequestedGeneration <> controller\.sessionGeneration/);
assert.match(task, /if status = 403[\s\S]*PorticoDiscoveryCacheRemoveViewer\("content-cache", controller\)/);
assert.match(task, /controller\.homeModel <> invalid then controller\.homeStatus = "stale"/);
assert.match(task, /controller\.detailModel <> invalid then controller\.detailStatus = "stale"/);
assert.match(task, /if status = 404 then controller\.detailStatus = "not-found"/);
assert.match(task, /PorticoContentAvailabilityStatus\(controller\.homeStatus, controller\.serverStatus\)/);
assert.match(task, /if serverStatus = "online" then return "refresh-failed"/);

assert.match(models, /if visibleRows\.count\(\) >= 32 then exit for/);
assert.match(models, /if examinedRows > 64 then exit for/);
assert.match(models, /rawRow\.defaultVisible = true/);
assert.match(models, /if items\.count\(\) >= 24 then exit for/);
assert.match(models, /for each row in visibleRows[\s\S]*rows\.push\(/);
assert.match(models, /hasMore: source\.hasMore = true and PorticoContentSafeCursor\(source\.nextCursor\) <> ""/);
assert.match(models, /function PorticoContentSafeCursor/);
assert.match(models, /if model\.rows\.count\(\) >= 32 then exit for/);
assert.match(task, /if attempted >= 64 or budget\.TotalSeconds\(\) >= 20 then return/);
assert.match(task, /PorticoContentTouchArtwork\(controller, finalPath\)[\s\S]*PorticoContentTrimArtwork\(controller, finalPath\)/);
assert.match(task, /while candidates\.Count\(\) > 96 or totalBytes > 100663296/);
assert.match(task, /Right\(LCase\(filename\), 5\) = "\.part"[\s\S]*DeleteFile\(path\)/);
assert.match(models, /if model\.episodes\.count\(\) >= 12 then exit for/);
assert.match(models, /if result\.count\(\) >= 20 then exit for/);
assert.match(models, /source\.defaultVisible = true/);
assert.match(models, /PorticoContentBoundedProgress/);
assert.match(models, /PorticoContentSafeActions/);
assert.match(models, /function PorticoContentHomeUiActions[\s\S]*result\.push\("open-detail"\)/);
assert.match(models, /model\.uiActions = PorticoContentDetailUiActions\(model\.actions\)/);
assert.match(models, /model\.moreActions = PorticoContentMoreActions[\s\S]*model\.uiActions\.push\("more"\)/);
assert.match(scene, /function activeHomeModel\(\)/);
assert.match(scene, /model\.rows\.count\(\) = 0 then return invalid/);
assert.match(scene, /function activeDetailModel\(\)/);
assert.match(scene, /homeActionIds\(model\)/);
assert.match(scene, /detailActionIds\(model\)/);
assert.match(scene, /firstHomeRowIndex\(model\)/);
assert.match(scene, /detailEpisodes\(model\)/);
assert.match(rokuHome, /heroModel = invalid/);
assert.match(rokuHome, /if hasHero[\s\S]*renderHomeHero\(heroModel\)[\s\S]*else[\s\S]*renderEmptyHomeHero\(\)/);
assert.match(rokuHome, /homeModelCards\(row\.items\)\.count\(\) > 0 then result\.push\(row\)/, 'Home must omit empty authoritative rows from presentation');
assert.match(rokuHome, /if items\.count\(\) > 0[\s\S]*rowGroup\.visible = true[\s\S]*else[\s\S]*rowGroup\.visible = false/, 'Home shelves must remain hidden when a row has no content');
assert.match(rokuHomeShelf, /for index = 0 to 6[\s\S]*m\.cards\.push\(m\.top\.findNode\("card" \+ index\.ToStr\(\)\)\)/, 'Home shelves must bind seven preallocated stable media card nodes');
assert.match(rokuHome, /model\.availabilityStatus = "refresh-failed" then label = "COULDN'T REFRESH"/);
assert.match(rokuHome, /allowed = \{ play: true, "saved-toggle": true, "open-detail": true, "favorite-toggle": true \}/, 'Home must retain its four approved controls');
assert.match(rokuHome, /result\.count\(\) < 4/);
assert.match(rokuDetail, /if model\.progress <> invalid and model\.progress > 0/);
assert.match(rokuDetail, /episodes = detailArray\(model\.episodes\)/);
assert.match(rokuDetail, /if episodes\.count\(\) > 0/);
assert.match(rokuDetail, /model\.availabilityStatus = "refresh-failed" then label = "COULDN'T REFRESH"/);
for (const action of ['play.from-beginning', 'watch-with-friends.start', 'feedback.report-problem', 'feedback.request-higher-quality']) {
  assert.ok(rokuDetail.includes(`"${action}": true`), `Detail action ${action} must survive the renderer allowlist`);
}
assert.match(rokuDetail, /result\.count\(\) < 9/);
assert.match(rokuDetail, /if shape = "landscape"[\s\S]*cardWidth = 320[\s\S]*pitch = 338/);
assert.match(rokuDetail, /if x \+ cardWidth > 1712 then exit for/);
assert.doesNotMatch(task + models, /pkg:\/images\/(?:posters|backdrops)\//);
for (const fixtureId of ['rookie', 'fargo', 'hurt-locker', 'martian']) {
  assert.ok(!new RegExp(`\\b${fixtureId}\\b`, 'i').test(task + models), `Fixture id ${fixtureId} leaked into the runtime content layer`);
}

console.log('Verified real Home/detail contracts, credential-private loading, safe caching, and authenticated artwork boundaries.');
