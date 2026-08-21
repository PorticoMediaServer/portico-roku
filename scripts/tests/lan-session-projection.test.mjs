import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');

const privateHost = host => {
  if (host === 'localhost' || host === '::1' || host.endsWith('.local')) return true;
  if (/^(fc|fd|fe80)/i.test(host)) return true;
  const octets = host.split('.').map(Number);
  if (octets.length !== 4 || octets.some(value => !Number.isInteger(value) || value < 0 || value > 255)) return false;
  return octets[0] === 10 || octets[0] === 127 || (octets[0] === 169 && octets[1] === 254)
    || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) || (octets[0] === 192 && octets[1] === 168);
};

const exactOrigin = (value, allowInsecureLan) => {
  let url;
  try { url = new URL(value); } catch { return ''; }
  if (url.username || url.password || url.search || url.hash || (url.pathname !== '/' && url.pathname !== '')) return '';
  if (url.protocol === 'https:') return value.replace(/\/$/, '');
  if (url.protocol === 'http:' && allowInsecureLan && privateHost(url.hostname)) return value.replace(/\/$/, '');
  return '';
};

const sameScope = (left, right) => ['authority', 'accountId', 'serverId', 'profileId', 'authorizationRevision', 'viewerGeneration']
  .every(field => left[field] === right[field]);

function project(session, scope, registryGeneration) {
  const allowInsecureLan = session.routeType === 'private-lan-http';
  if (session.allowInsecureLan !== allowInsecureLan || !sameScope(session, scope)) return null;
  const origin = exactOrigin(session.apiBaseUrl, allowInsecureLan);
  if (!origin) return null;
  return {
    purpose: 'viewer-bound-request-session', authority: session.authority, authMode: session.authority === 'local' ? 'local' : 'portico',
    accountId: session.accountId, serverId: session.serverId, profileId: session.profileId,
    authorizationRevision: session.authorizationRevision, viewerGeneration: scope.viewerGeneration,
    installationId: session.installationId, deviceId: session.deviceId, origin, apiBaseUrl: origin,
    accessToken: session.accessToken, routeType: session.routeType, allowInsecureLan, registryGeneration,
  };
}

const scope = {authority: 'local', accountId: 'account-1', serverId: 'server-1', profileId: 'profile-1', authorizationRevision: '7', viewerGeneration: 12};
const lan = {...scope, installationId: 'installation-1', deviceId: 'device-1', accessToken: 'opaque', apiBaseUrl: 'http://192.168.1.20:32400', routeType: 'private-lan-http', allowInsecureLan: true};
const projectedLan = project(lan, scope, 41);
assert.deepEqual(projectedLan && {origin: projectedLan.origin, allowInsecureLan: projectedLan.allowInsecureLan, viewerGeneration: projectedLan.viewerGeneration, registryGeneration: projectedLan.registryGeneration}, {
  origin: 'http://192.168.1.20:32400', allowInsecureLan: true, viewerGeneration: 12, registryGeneration: 41,
});
const remote = {...lan, authority: 'hosted', apiBaseUrl: 'https://server.direct.getportico.tv', routeType: 'remote-https', allowInsecureLan: false};
const remoteScope = {...scope, authority: 'hosted'};
assert.equal(project(remote, remoteScope, 42)?.allowInsecureLan, false);
assert.equal(project({...lan, apiBaseUrl: 'http://203.0.113.4:32400'}, scope, 1), null, 'public HTTP must fail closed');
assert.equal(project({...lan, allowInsecureLan: false}, scope, 1), null, 'stored LAN policy mismatch must fail closed');
assert.equal(project({...lan, apiBaseUrl: 'http://192.168.1.20:32400/api'}, scope, 1), null, 'session authority must remain an exact origin');
assert.equal(project(lan, {...scope, profileId: 'profile-2'}, 1), null, 'viewer changes must invalidate the projection');

const sources = {
  discovery: read('channel/source/lib/PorticoDiscoveryRuntime.brs'),
  channels: read('channel/source/lib/PorticoChannelsRuntime.brs'),
  preferences: read('channel/components/PorticoViewerPreferencesTask.brs'),
  applicationEvents: read('channel/components/PorticoApplicationEventsTask.brs'),
  engagement: read('channel/components/PorticoEngagementTask.brs'),
  watchWithFriends: read('channel/components/PorticoWatchWithFriendsTask.brs'),
  playbackEvents: read('channel/source/lib/PorticoPlaybackEventsRuntime.brs'),
  playback: read('channel/source/lib/PorticoPlaybackRuntime.brs'),
};
for (const [domain, source] of Object.entries(sources)) {
  assert.match(source, /allowInsecureLan:\s*session\.allowInsecureLan = true|PorticoServerSessionRequestProjection/, `${domain} dropped the exact LAN authority`);
}
const core = read('channel/source/core/PorticoServerSession.brs');
assert.match(core, /purpose: "viewer-bound-request-session"/);
assert.match(core, /if value\.allowInsecureLan <> allowInsecureLan then return invalid/);

console.log('Verified exact viewer-bound LAN/HTTPS request projection and post-auth domain propagation.');
