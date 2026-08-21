import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const settings = read('channel/source/lib/PorticoSettingsModels.brs');
const settingsScreen = read('channel/components/PorticoSettingsScreen.brs');
const preferences = read('channel/source/lib/PorticoViewerPreferences.brs');
const preferencesTask = read('channel/components/PorticoViewerPreferencesTask.brs');
const preferencesController = read('channel/source/lib/PorticoViewerPreferencesController.brs');
const serverConnection = read('channel/components/PorticoServerConnectionTask.brs');
const task = read('channel/components/PorticoLocalAuthTask.brs');
const taskXml = read('channel/components/PorticoLocalAuthTask.xml');
const local = read('channel/source/lib/PorticoLocalAuth.brs');
const bridge = read('channel/source/lib/PorticoLocalAuthBridge.brs');
const main = read('channel/source/main.brs');
const openapi = JSON.parse(read('../../apps/portico-server/api/openapi/portico-server.openapi.json'));

for (const path of ['/auth/sessions', '/auth/sessions/refresh', '/auth/sessions/revoke']) assert.ok(openapi.paths[path]?.post, `POST ${path} disappeared from the Server OpenAPI`);
for (const path of ['/remote-access/health', '/auth/me', '/product-contract', '/libraries', '/account/library-navigation']) assert.ok(openapi.paths[path]?.get, `GET ${path} disappeared from the Server OpenAPI`);
for (const schemaName of ['NativeSessionCreateRequest', 'NativeProfileSessionRequest', 'PorticoSessionAttachPayload', 'TVSetupSessionRequest']) {
  assert.ok(!openapi.components.schemas[schemaName].required?.includes('installationId'), `${schemaName} must keep installationId optional metadata`);
}
assert.deepEqual(openapi.components.schemas.NativeSessionRefreshRequest.required, ['refreshToken', 'rotationKey']);

for (const row of ['profile', 'server', 'automatic-profile', 'account-security', 'feedback', 'autoplay-next', 'up-next', 'seek-interval', 'preferred-audio', 'preferred-subtitles', 'pause-history', 'clear-watch-history', 'clear-search-history', 'sign-out']) assert.match(settings, new RegExp(`id: "${row}"`));
assert.match(settings, /if authMode = "local" then authLabel = "Server Only Authentication"/);
assert.match(settings, /if authMode = "local"[\s\S]*serverAction = "open-connection"/);
assert.doesNotMatch(settingsScreen, /PorticoPlaybackPreferences(?:Read|Update|Projection)/);
assert.match(settingsScreen, /PorticoSettingsPatchPlayback\(\{autoplayNext:/);
assert.match(settingsScreen, /PorticoSettingsOpenChoice\("seek"\)/);
assert.match(settingsScreen, /PorticoSettingsOpenChoice\("audio"\)/);
assert.match(settingsScreen, /PorticoSettingsOpenChoice\("subtitles"\)/);
assert.match(settingsScreen, /PorticoSettingsEmit\("sign-out-account", \{\}\)/);
assert.match(preferences, /profileServer:[\s\S]*autoplayNext: true/);
assert.match(preferences, /accountServerInstallation: \{rememberAccount: true, profileSelection: "ask"\}/);
assert.match(preferences, /PorticoSecureRegistryCommit\("profile-launch"/);
assert.match(preferences, /PorticoViewerPreferencesAutomaticTrust/);
assert.doesNotMatch(preferences, /installationId <> expected\.installationId/, 'Installation metadata must not authorize automatic profile selection');
assert.doesNotMatch(preferences, /launch\.installationId <> installationId/, 'Local restore evidence is keyed by authenticated account/server identity');
assert.match(preferences, /function PorticoViewerPreferencesOfflineRestoreAllowed/);
assert.match(preferences, /function PorticoViewerPreferencesForgetLaunch/);
assert.match(preferences, /policy\.eligibleProfileCount = 1 and policy\.profileHasPIN = false/);
assert.match(preferencesTask, /recordViewerProfileActivation/);
assert.match(preferencesTask, /"listAccountProfiles"/);
assert.match(preferencesTask, /patchViewerPreferenceDocument/);
assert.match(preferencesTask, /createAutomaticProfileTrust/);
assert.match(preferencesTask, /requestBody = \{\}[\s\S]*if controller\.expected\.installationId <> "" then requestBody\.installationId = controller\.expected\.installationId/);
assert.match(preferencesTask, /revokeAutomaticProfileTrusts/);
assert.match(preferencesTask, /deleteAccountWatchHistory/);
assert.match(preferencesController, /PorticoViewerPreferencesControllerHandleActivation/);
assert.match(serverConnection, /PorticoServerConnectionAuthorizeRestoredProfile/);
assert.match(serverConnection, /"redeemAutomaticProfileTrust"/);
assert.match(serverConnection, /launch\.profileSelection <> "last-used" or launch\.lastProfileId <> session\.profileId/);
assert.match(serverConnection, /policy\.authorizationRevision = session\.authorizationRevision/);
assert.match(serverConnection, /if eligible\.Count\(\) = 1 and current\.hasPIN = false then return true/);
assert.match(serverConnection, /controller\.session = invalid or controller\.serverErrorCode = "profile-reactivation-required"/);

assert.match(taskXml, /component name="PorticoLocalAuthTask" extends="Task"/);
assert.match(taskXml, /<field id="command" type="assocarray"/);
assert.match(taskXml, /<field id="projection" type="assocarray" alwaysNotify="true"/);
assert.doesNotMatch(taskXml, /field id="(?:login|password|accessToken|refreshToken|apiBaseUrl|headers|serverSession)"/i);
assert.match(task, /PorticoLocalAuthOpenDiscoverySocket\(\)/);
assert.match(task, /PorticoLocalAuthSendDiscoveryQuery\(controller\)/);
assert.match(task, /received < 12/);
assert.match(task, /packet\.SetResize\(8192, false\)/);
assert.match(task, /"\/api\/remote-access\/health"/);
assert.match(task, /if not PorticoLocalAuthSystemCompatible\(controller, selected\.apiBaseUrl\) then return/);
assert.match(task, /PorticoLocalAuthOpenSealedCredentials\(sealed\)/);
assert.match(task, /if login = "" or password = ""/);
assert.doesNotMatch(task, /Len\(password\)\s*[<>=]/, 'Roku must defer password validity to the Server');
assert.match(task, /"POST", controller\.selected\.apiBaseUrl \+ "\/api\/auth\/profile-authentications\/local"/);
assert.match(task, /if installationId <> "" then payload\.installationId = installationId/);
assert.doesNotMatch(task, /if installationId = "" or PorticoLocalAuthSafeId\(controller\.selected\.serverId\) = ""/);
assert.match(task, /PorticoServerSessionLocalHandoffWrite\(handoffId, selected, response\.data, controller\.viewerGeneration\)/);
assert.match(task, /controller\.status = "profile-selection-required"/);
assert.match(task, /kind = "prepare-profile-switch"[\s\S]*controller\.status = "credentials"/);
assert.match(task, /PorticoLocalAuthValidateIdentity\(controller, controller\.session\)/);
assert.match(task, /"\/api\/auth\/me"/);
assert.match(task, /"\/api\/product-contract"/);
assert.match(task, /"\/api\/account\/library-navigation"/);
const localRefresh = task.match(/function PorticoLocalAuthRefresh\(controller as object, afterUnauthorized as boolean\) as boolean([\s\S]*?)\nend function/)?.[1] ?? '';
const localCommitFailure = localRefresh.match(/committed = PorticoSecureRegistryCommit\("server-session", replacement\)([\s\S]*?)controller\.session = replacement/)?.[1] ?? '';
assert.match(localCommitFailure, /if not committed\.ok/);
assert.doesNotMatch(localCommitFailure, /controller\.session = replacement|PorticoLocalAuthClearSession|PorticoSecureRegistryClear\("server-refresh-rotation"\)/, 'Local refresh commit failure must preserve the old session and exact receipt');
assert.match(localCommitFailure, /Portico will retry/);
assert.match(task, /if existing\.payload\.refreshToken = session\.refreshToken[\s\S]*then return existing\.payload/);

{
  const durable = {session: {refreshToken: 'local-old'}, receipt: {refreshToken: 'local-old', rotationKey: 'stable-local-key'}};
  let memory = durable.session;
  const firstRequest = {...durable.receipt};
  const successor = {refreshToken: 'local-new'};
  assert.equal(memory.refreshToken, 'local-old');
  memory = durable.session; // simulated restart after failed commit
  assert.deepEqual(durable.receipt, firstRequest);
  const retryRequest = {...durable.receipt};
  assert.deepEqual(retryRequest, firstRequest);
  durable.session = successor;
  durable.receipt = undefined;
  memory = durable.session;
  assert.equal(memory.refreshToken, 'local-new');
  assert.equal(durable.receipt, undefined);
}

assert.match(local, /PorticoSecureRegistryRead\("local-auth-trust"\)/);
assert.match(local, /PorticoSecureRegistryCommit\("local-auth-trust"/);
assert.match(local, /Left\(value, 8\) = "ptc_loc_"/);
assert.doesNotMatch(local, /device\.installationId, ""\) <> installationId/);
const projected = local.match(/sub PorticoLocalAuthPublish[\s\S]*?\nend sub/)?.[0] ?? '';
assert.doesNotMatch(projected, /login:|password:|accessToken:|refreshToken:|apiBaseUrl:/);
for (const safe of ['localAuthStatus', 'nearbyServers', 'selectedLocalServerFingerprintDisplay', 'localAuthSignedIn', 'localAuthHasSession', 'navigationSnapshotVerified', 'libraryItems']) assert.match(projected, new RegExp(`${safe}:`));

const signOut = task.match(/sub PorticoLocalAuthSignOut[\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(signOut, /PorticoSecureRegistryCommit\("server-session", tombstone\)/);
assert.match(signOut, /if not durable then durable = PorticoSecureRegistryClear\("server-session"\)/);
assert.match(bridge, /ownsSharedServerState = Left\(currentAuthMode, 5\) = "local"/);
assert.match(bridge, /not sharedServerField or ownsSharedServerState/);
assert.match(bridge, /source\.localAuthSignedIn = true and ownsSharedServerState[\s\S]*nextState\.authMode = "local"/);
assert.match(bridge, /sub PorticoLocalAuthPrepareProfileSwitch/);
assert.match(main, /if not PorticoMainUsesLocalAuth\(scene\.runtimeState\)[\s\S]*PorticoServerCatalogHandleActivation/);

console.log('Verified Settings preferences and credential-private Local Auth discovery, trust, durable session, restore, and sign-out contracts.');
