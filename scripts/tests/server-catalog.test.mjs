import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoServerCatalogTask.brs');
const taskXml = read('channel/components/PorticoServerCatalogTask.xml');
const bridge = read('channel/source/lib/PorticoServerCatalog.brs');
const scene = read('channel/components/PorticoScene.brs');
const main = read('channel/source/main.brs');
const registry = read('channel/source/lib/PorticoSecureRegistry.brs');
const openapi = JSON.parse(read('../portico-internal/hosted-services/api/openapi/portico-hosted.openapi.json'));

assert.ok(openapi.paths['/api/account/servers']?.get, 'Hosted OpenAPI no longer publishes the server-list operation');
assert.equal(openapi.paths['/api/account/servers'].get.operationId, 'listAccountServers');
assert.equal(openapi.components.schemas.ServerList.properties.items.type, 'array');
assert.equal(openapi.components.schemas.ServerList.required.includes('items'), true);
assert.equal(openapi.components.schemas.ServerList.required.includes('pageInfo'), true);
assert.ok(openapi.paths['/api/account/servers'].get.parameters.some(parameter => parameter.name === 'cursor' && parameter.in === 'query'));

assert.match(taskXml, /component name="PorticoServerCatalogTask" extends="Task"/);
assert.match(taskXml, /field id="command" type="assocarray"/);
assert.match(taskXml, /field id="projection" type="assocarray"/);
assert.doesNotMatch(taskXml, /field id="(?:accessToken|refreshToken|routeDocument|serverPublicKey|signature)"/i);
assert.match(taskXml, /pkg:\/components\/PorticoServerCatalogTask\.brs/);

assert.match(registry, /recordType <> "account-server-catalog"/);
assert.match(task, /PorticoSecureRegistryRead\("account-credentials"\)/);
assert.match(task, /PorticoSecureRegistryCommit\("account-server-catalog"/);
assert.match(task, /payload\.accountUserId\) <> controller\.accountUserId/);

const preflightIndex = task.indexOf('url: "https://api.getportico.tv/api/system"');
const listIndex = task.indexOf('url = "https://api.getportico.tv/api/account/servers?limit=100"');
const loadBody = task.match(/sub PorticoServerCatalogLoad\(controller as object\)([\s\S]*?)end sub/)?.[1] ?? '';
assert.ok(preflightIndex >= 0 && listIndex >= 0, 'Hosted compatibility or server-list route is missing');
assert.ok(loadBody.indexOf('PorticoServerCatalogEnsureHostedCompatibility(controller)') < loadBody.indexOf('PorticoServerCatalogCredentials()'), 'Hosted server list must follow an exact compatibility preflight');
assert.equal(openapi.components.schemas.HostedSystemInfo.properties.apiVersion.const, 'v1');
assert.ok(task.includes(`data.apiVersion.ToStr() <> "v1"`));
assert.doesNotMatch(task.match(/function PorticoServerCatalogHostedSystemIsCompatible[\s\S]*?end function/)?.[0] ?? '', /data\.(?:version|schemaRevision)/);

assert.match(task, /headers: \{ Authorization: "Bearer " \+ credentials\.accessToken \}/);
assert.match(task, /PorticoHttpValidatePrivateRequest\(request\)/);
assert.match(task, /refreshRequestedGeneration <> controller\.credentialGeneration/);
assert.doesNotMatch(task.match(/else if result\.status = 403[\s\S]*?else/)?.[0] ?? '', /refreshRequestedGeneration/);
assert.match(task, /if PorticoServerCatalogInterruptRequested\(controller\)/);
assert.match(task, /if compatibility = "interrupted"[\s\S]*PorticoServerCatalogRescheduleInterruptedLoad\(controller\)/);
assert.match(task, /if result\.interrupted[\s\S]*PorticoServerCatalogRescheduleInterruptedLoad\(controller\)/);
assert.match(task, /stateChanged = not controller\.accountStateInitialized or accountChanged or generationChanged[\s\S]*if not stateChanged then return/);

assert.match(task, /url = url \+ "&cursor=" \+ cursor/);
assert.match(task, /PorticoServerCatalogPageFromResponse/);
assert.match(task, /seenServerIds\[server\.id\]/);
assert.match(task, /seenCursors\[page\.nextCursor\]/);
assert.match(task, /function PorticoServerCatalogMaximumServers\(\) as integer[\s\S]*return 500/);
assert.match(task, /function PorticoServerCatalogMaximumPages\(\) as integer[\s\S]*return 5/);
assert.match(task, /function PorticoServerCatalogMaximumCachedServers\(\) as integer[\s\S]*return 100/);
assert.match(task, /allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"/);

assert.match(task, /nextLoadAtSeconds/);
assert.match(task, /hostedCompatibilityCheckedAtSeconds/);
assert.match(task, /controller\.clock\.TotalSeconds\(\)/);
assert.doesNotMatch(task, /nextLoadAtMs|hostedCompatibilityCheckedAtMs|PorticoServerCatalogNowMs/);

const selectBody = task.match(/sub PorticoServerCatalogSelect\([\s\S]*?end sub/)?.[0] ?? '';
assert.match(selectBody, /committed = PorticoServerCatalogPersist\(controller\)/);
assert.match(selectBody, /if committed\.ok[\s\S]*durableSelectedServerId[\s\S]*else[\s\S]*PorticoServerCatalogRestoreDurableSelection/);
assert.ok(selectBody.indexOf('PorticoServerCatalogPersist(controller)') < selectBody.indexOf('PorticoServerCatalogPublish(controller, false)'), 'selection must not be projected before its durable commit result is handled');
assert.match(task, /servers: PorticoServerCatalogServersForCache\(controller\)/);

for (const safeField of ['id', 'name', 'preferredAuthMode', 'remoteAccessEnabled', 'availabilityState']) {
  assert.match(task, new RegExp(`${safeField}:`), `Sanitized server projection lost ${safeField}`);
}
for (const secretOrTrustField of ['assignedHostname', 'serverPublicKey', 'serverPublicKeyFingerprint', 'signature', 'routes', 'certificate']) {
  assert.ok(!bridge.includes(secretOrTrustField), `${secretOrTrustField} crossed into the render-thread bridge`);
  assert.ok(!scene.includes(secretOrTrustField), `${secretOrTrustField} crossed into the Scene`);
}

const projectionBody = bridge.match(/function PorticoServerCatalogProjection[\s\S]*?end function/)?.[0] ?? '';
for (const safeProjection of ['serverListStatus', 'availableServers', 'selectedServerId', 'selectedServerName', 'serverStatus', 'accountRefreshRequired']) {
  assert.match(projectionBody, new RegExp(`${safeProjection}: true`));
}
assert.doesNotMatch(projectionBody, /accessToken|refreshToken|route|fingerprint|signature/i);
assert.match(main, /sourceNode\.IsSameNode\(serverCatalog\.task\)/);
assert.match(main, /PorticoServerCatalogAccountStateChanged\(serverCatalog, scene\.runtimeState\)/);
assert.match(main, /PorticoDeviceAuthorizationHandleActivation\(accountAuthorization, activationData\)/);
assert.doesNotMatch(main, /currentPage|ObserveField\("page", port\)/);
assert.match(scene, /availabilityLabel = "Local network only"/);
assert.doesNotMatch(scene, /availabilityLabel = "Unavailable"/);
assert.match(scene, /listIsStale[\s\S]*availabilityLabel = "Not checked"/);
assert.match(scene, /if result\.count\(\) >= 500 then exit for/);
assert.match(scene, /serverListStatus = "denied"[\s\S]*status = "ACCESS DENIED"/);
assert.match(scene, /id: "empty"[\s\S]*status: "ACCOUNT READY"[\s\S]*statusTone: "account"/);
assert.match(scene, /Your Portico Account is signed in\. When you create a server or someone shares one with you, it will appear here\./);
assert.match(scene, /selectedServerId = ""[\s\S]*serverListStatus = "ready"/);
assert.doesNotMatch(scene, /Hosted Services/);
assert.match(scene, /emitActivation\("select-server", server\.id\)[\s\S]*openInternalRoute\("connection"\)/);

function aggregatePages(pages, maximum = 500) {
  const servers = [];
  const seenServerIds = new Set();
  const seenCursors = new Set();
  for (let index = 0; index < pages.length && servers.length < maximum; index += 1) {
    const page = pages[index];
    for (const server of page.items) {
      if (!seenServerIds.has(server.id)) {
        seenServerIds.add(server.id);
        servers.push(server);
      }
      if (servers.length >= maximum) break;
    }
    if (servers.length >= maximum || !page.hasMore) return servers;
    if (!/^[A-Za-z0-9_-]{1,2048}$/.test(page.nextCursor ?? '') || seenCursors.has(page.nextCursor)) throw new Error('invalid cursor chain');
    seenCursors.add(page.nextCursor);
  }
  throw new Error('incomplete bounded pagination');
}

const pagedServers = Array.from({length: 250}, (_, index) => ({id: `srv_${index}`}));
assert.equal(aggregatePages([
  {items: pagedServers.slice(0, 100), hasMore: true, nextCursor: 'cursor_1'},
  {items: [pagedServers[99], ...pagedServers.slice(100, 200)], hasMore: true, nextCursor: 'cursor_2'},
  {items: pagedServers.slice(200), hasMore: false, nextCursor: null}
]).length, 250, 'cursor aggregation must cross the first 100 and deduplicate stable IDs');
assert.throws(() => aggregatePages([
  {items: pagedServers.slice(0, 100), hasMore: true, nextCursor: 'repeat'},
  {items: pagedServers.slice(100, 200), hasMore: true, nextCursor: 'repeat'}
]), /invalid cursor chain/);
const oversized = Array.from({length: 600}, (_, index) => ({id: `srv_big_${index}`}));
assert.equal(aggregatePages(Array.from({length: 6}, (_, index) => ({
  items: oversized.slice(index * 100, (index + 1) * 100),
  hasMore: index < 5,
  nextCursor: index < 5 ? `next_${index}` : null
}))).length, 500, 'the catalog must cap a hostile or unexpectedly large membership set');

console.log('Verified credential-private Hosted server catalog and persistent server-selection contracts.');
