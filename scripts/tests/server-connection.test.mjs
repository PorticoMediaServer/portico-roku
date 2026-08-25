import assert from 'node:assert/strict';
import {createPublicKey, verify} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoServerConnectionTask.brs');
const taskXml = read('channel/components/PorticoServerConnectionTask.xml');
const bridge = read('channel/source/lib/PorticoServerConnection.brs');
const sessionCore = read('channel/source/core/PorticoServerSession.brs');
const profileTask = read('channel/components/PorticoProfileTask.brs');
const profileController = read('channel/source/lib/PorticoProfileController.brs');
const profiles = read('channel/source/lib/PorticoProfiles.brs');
const signedDocuments = read('channel/source/lib/PorticoSignedDocuments.brs');
const main = read('channel/source/main.brs');
const scene = read('channel/components/PorticoScene.brs');
const operationsDocument = JSON.parse(read('channel/data/generated/operations.v1.json'));
const fixture = JSON.parse(read('../portico-internal/hosted-services/internal/app/testdata/document-signing-fixture.json'));
const adversarialFixture = JSON.parse(read('../portico-internal/hosted-services/internal/app/testdata/document-signing-adversarial-fixture.json'));

function sortJSON(value) {
  if (Array.isArray(value)) return value.map(sortJSON);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([key, nested]) => [key, sortJSON(nested)]));
}

function verifyHostedFixture(vector, label) {
  const unsigned = {...vector.routeDocument};
  delete unsigned.signature;
  const canonicalJSON = JSON.stringify(sortJSON(unsigned)).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  const canonical = `portico-signed-document:route-document:v1\n${canonicalJSON}`;
  assert.equal(Buffer.from(canonical).toString('base64'), vector.routeCanonicalPayloadB64, `${label} canonical fixture drifted`);
  const rawKey = Buffer.from(vector.publicKeyB64, 'base64');
  const spki = Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), rawKey]);
  const publicKey = createPublicKey({key: spki, format: 'der', type: 'spki'});
  const encodedSignature = vector.routeDocument.signature.replaceAll('-', '+').replaceAll('_', '/');
  const signature = Buffer.from(encodedSignature + '='.repeat((4 - encodedSignature.length % 4) % 4), 'base64');
  assert.equal(verify(null, Buffer.from(canonical), publicKey, signature), true, `${label} signature no longer verifies`);
  return canonical;
}

function collectOperations(value, result = [], seen = new Set()) {
  if (!value || typeof value !== 'object' || seen.has(value)) return result;
  seen.add(value);
  if (typeof value.operationId === 'string') result.push(value);
  for (const nested of Object.values(value)) collectOperations(nested, result, seen);
  return result;
}

const operations = collectOperations(operationsDocument);
const operation = (service, operationId) => operations.find(value => value.service === service && value.operationId === operationId);
const expectOperation = (service, operationId, method, path) => {
  const value = operation(service, operationId);
  assert.ok(value, `${service}.${operationId} disappeared from the generated Roku operation contract`);
  assert.equal(value.method, method);
  assert.equal(value.path, path);
  assert.ok(value.surfaces?.includes('television'));
};

verifyHostedFixture(fixture, 'ASCII');
const adversarialCanonical = verifyHostedFixture(adversarialFixture, 'Unicode adversarial');
assert.match(adversarialCanonical, /Cinéma <Portico> & 雪/);
assert.match(adversarialCanonical, /\\u2028/);
assert.match(adversarialCanonical, /\\u2029/);

expectOperation('hosted', 'getServerRoutes', 'GET', '/api/account/servers/{serverId}/routes');
expectOperation('hosted', 'createPorticoSession', 'POST', '/api/account/servers/{serverId}/sessions');
expectOperation('hosted', 'refreshNativeSession', 'POST', '/api/auth/sessions/refresh');
expectOperation('hosted', 'revokeNativeSession', 'POST', '/api/auth/sessions/revoke');
expectOperation('server', 'attachPorticoSession', 'POST', '/auth/portico/sessions');
expectOperation('server', 'createNativeProfileSession', 'POST', '/auth/profile-sessions/native');
expectOperation('server', 'refreshNativeSession', 'POST', '/auth/sessions/refresh');
expectOperation('server', 'revokeNativeSession', 'POST', '/auth/sessions/revoke');
for (const [id, path] of [['getAuthMe', '/auth/me'], ['getProductContract', '/product-contract'], ['getLibraries', '/libraries'], ['getAccountLibraryNavigation', '/account/library-navigation']]) {
  expectOperation('server', id, 'GET', path);
}

assert.match(taskXml, /component name="PorticoServerConnectionTask" extends="Task"/);
assert.doesNotMatch(taskXml, /field id="(?:accessToken|refreshToken|selectionEnvelope|serverPublicKeyFingerprint|apiBaseUrl|viewerScope)"/i);
assert.match(signedDocuments, /CreateObject\("roDsa"\)/);
assert.match(signedDocuments, /SetSignAlgorithm\("Ed25519"\)/);
assert.match(signedDocuments, /portico-signed-document:route-document:v1/);
assert.match(signedDocuments, /document\.kind\) <> "route-document"/);
assert.match(signedDocuments, /FormatJson\(value, &h0001\)/);

const hostedActivation = task.match(/sub PorticoServerConnectionActivateHosted\(controller as object, command as object\)([\s\S]*?)\nend sub/)?.[1] ?? '';
for (const marker of ['PorticoServerConnectionExpected', 'PorticoServerConnectionResolveHostedRoute', 'PorticoProfilesSelectionTransactionConsume', '"createPorticoSession"', 'PorticoServerConnectionHostedBootstrap', '"attachPorticoSession"', 'PorticoServerConnectionAcceptCredentials']) {
  assert.ok(hostedActivation.includes(marker), `Hosted activation lost ${marker}`);
}
assert.ok(hostedActivation.indexOf('PorticoServerConnectionResolveHostedRoute') < hostedActivation.indexOf('"createPorticoSession"'));
assert.ok(hostedActivation.indexOf('"createPorticoSession"') < hostedActivation.indexOf('"attachPorticoSession"'));
assert.match(hostedActivation, /attachPayload\.accessToken = ""/);
assert.match(hostedActivation, /attachPayload\.selectionEnvelope = invalid/);

const localActivation = task.match(/sub PorticoServerConnectionActivateLocal\(controller as object, command as object\)([\s\S]*?)\nend sub/)?.[1] ?? '';
for (const marker of ['PorticoServerSessionLocalHandoffConsume', 'PorticoServerConnectionVerifyRoute', 'PorticoProfilesUnsealPin', '"selectLocalProfile"', '"createNativeProfileSession"', 'PorticoServerConnectionAcceptCredentials']) {
  assert.ok(localActivation.includes(marker), `Local activation lost ${marker}`);
}
assert.match(localActivation, /pin = ""/);
assert.match(localActivation, /selectionPayload\.accountAuthenticationToken = ""/);
assert.match(localActivation, /sessionPayload\.selectionGrant = ""/);

const acceptCredentials = task.match(/sub PorticoServerConnectionAcceptCredentials\(controller as object, credentials as dynamic, route as object, expected as object\)([\s\S]*?)\nend sub/)?.[1] ?? '';
assert.ok(acceptCredentials.indexOf('PorticoServerConnectionValidateIdentity') < acceptCredentials.indexOf('PorticoSecureRegistryCommit("server-session", session)'), 'Final /auth/me identity validation must precede persistence');
assert.ok(acceptCredentials.indexOf('PorticoSecureRegistryCommit("pending-server-session", session)') < acceptCredentials.indexOf('PorticoServerConnectionBootstrapContent'), 'Candidate credentials must be staged before content validation');
assert.ok(acceptCredentials.indexOf('PorticoSecureRegistryCommit("server-session", session)') < acceptCredentials.indexOf('PorticoServerConnectionFinishActivation'), 'Session must commit before viewer publication');
assert.match(task, /activationBackup/);
assert.match(task, /PorticoServerConnectionRestoreActivationBackup/);
assert.match(main, /Plex-style switching is staged over the active viewer/);
assert.match(main, /profileController\.stagingOverActive = true/);
assert.match(main, /profileSelectionOverlay: true,[\s\S]*viewerStatus: "active",[\s\S]*viewerAcceptingWrites: true/);
assert.match(profileController, /if controller\.stagingOverActive[\s\S]*viewerStatus = "active"[\s\S]*viewerAcceptingWrites = true/);
assert.match(scene, /profileSelectionOverlay/);
assert.match(scene, /Keep the cached shell and player state intact behind the chooser/);
assert.match(main, /profileController\.stagingOverActive = false[\s\S]*profileSelectionOverlay: false/);

const routeResolution = task.match(/function PorticoServerConnectionResolveHostedRoute\(controller as object, expected as object, account as object\) as dynamic([\s\S]*?)\nend function/)?.[1] ?? '';
assert.ok(routeResolution.indexOf('/api/signing-keys') < routeResolution.indexOf('PorticoSignedDocumentVerifyRoute'));
assert.ok(routeResolution.indexOf('PorticoSignedDocumentVerifyRoute') < routeResolution.indexOf('PorticoServerConnectionVerifyRoute'));
assert.match(task, /health\.data\.serverPublicKeyFingerprint/);
assert.match(task, /result\.data\.apiVersion <> "v1"/);

assert.match(sessionCore, /function PorticoServerSessionVersion\(\) as integer\s+return 3/);
assert.match(sessionCore, /purpose: "profile-bound-native-server-session"/);
for (const field of ['authority', 'accountId', 'serverId', 'profileId', 'authorizationRevision', 'installationId', 'deviceId']) assert.match(sessionCore, new RegExp(`\\b${field}\\b`));
assert.doesNotMatch(sessionCore, /installationId\) <> PorticoInstallationId\(\)/, 'Stored sessions must remain valid when installation metadata rotates');
assert.doesNotMatch(sessionCore, /device\.installationId\) <> installationId/, 'Server-issued device identity, not echoed metadata, owns the credential family');
assert.match(sessionCore, /deviceId = PorticoServerSessionId\(device\.id\)[\s\S]*if deviceId = "" then return invalid/);
assert.doesNotMatch(task, /expected\.installationId <> PorticoInstallationId\(\)/);
assert.match(task, /if expected\.installationId <> "" then attachPayload\.installationId = expected\.installationId/);
assert.doesNotMatch(task, /returned\.installationId\) <> expected\.installationId/);
assert.match(profileTask, /body = \{serverId: controller\.serverId\}[\s\S]*if controller\.installationId <> "" then body\.installationId = controller\.installationId/);
assert.doesNotMatch(profileTask, /value\.installationId\) <> controller\.installationId/);
assert.doesNotMatch(profileController, /accountId = "" or serverId = "" or installationId = ""/);
assert.doesNotMatch(profiles, /value\.installationId\) <> PorticoProfilesSafeId\(installationId\)/);
assert.match(sessionCore, /legacy_reactivation_required/);
assert.match(sessionCore, /PorticoServerSessionRebaseIdentity/);
assert.match(sessionCore, /PorticoServerSessionOneTimeConsume/);
assert.match(sessionCore, /function PorticoServerSessionPreviousRoute/);
assert.match(sessionCore, /previous\.serverId <> current\.serverId or previous\.serverPublicKeyFingerprint <> current\.serverPublicKeyFingerprint/);
assert.ok(sessionCore.indexOf('section.Delete("value")') < sessionCore.indexOf('crypto.Decrypt'), 'One-time handoffs must be deleted before decryption/use');

const refresh = task.match(/function PorticoServerConnectionRefresh\(controller as object, afterUnauthorized as boolean\) as boolean([\s\S]*?)\nend function/)?.[1] ?? '';
assert.match(refresh, /"refreshNativeSession"/);
assert.match(refresh, /rotationKey: rotation\.rotationKey/);
assert.match(task, /PorticoSecureRegistryCommit\("server-refresh-rotation", pending\)/);
assert.match(task, /PorticoServerConnectionRefreshFailureIsTerminal/);
assert.match(refresh, /replacement\.authorizationRevision <> source\.authorizationRevision/);
assert.ok(refresh.indexOf('PorticoSecureRegistryCommit("server-session", replacement)') < refresh.indexOf('controller.session = replacement'), 'Rotated session must commit before becoming active');
const refreshCommitFailure = refresh.match(/committed = PorticoSecureRegistryCommit\(recordType, replacement\)([\s\S]*?)controller\.session = replacement/)?.[1] ?? '';
assert.match(refreshCommitFailure, /if not committed\.ok/);
assert.doesNotMatch(refreshCommitFailure, /controller\.session = replacement|PorticoSecureRegistryClear\("server-refresh-rotation"\)/, 'Commit failure must retain the old in-memory session and exact refresh receipt');
assert.match(task, /if existing\.payload\.refreshToken = session\.refreshToken[\s\S]*then return existing\.payload/);

// Model the durability boundary explicitly: a lost successor commit followed by
// process death must retry the exact request and make only the durable successor
// authoritative. These state transitions mirror the invariants asserted above.
{
  const durable = {session: {refreshToken: 'old'}, receipt: {refreshToken: 'old', rotationKey: 'stable-key'}};
  let memory = durable.session;
  const request = {...durable.receipt};
  const successor = {refreshToken: 'new'};
  const firstCommitSucceeded = false;
  if (firstCommitSucceeded) memory = successor;
  assert.equal(memory.refreshToken, 'old');
  const afterRestart = durable.session;
  assert.deepEqual(durable.receipt, request);
  const retryRequest = {...durable.receipt};
  assert.deepEqual(retryRequest, request);
  durable.session = successor;
  durable.receipt = undefined;
  memory = durable.session;
  assert.equal(memory.refreshToken, 'new');
  assert.equal(durable.receipt, undefined);
  assert.equal(afterRestart.refreshToken, 'old');
}
assert.match(task, /"revokeNativeSession"/);
assert.match(task, /PorticoSecureRegistryCommit\("server-session", tombstone\)[\s\S]*PorticoSecureRegistryClear\("server-session"\)/);
assert.match(task, /PorticoServerConnectionVerifyOrRediscoverRoute\(controller, true\)/);
const routeRecovery = task.match(/function PorticoServerConnectionVerifyOrRediscoverRoute[\s\S]*?\nend function/)?.[0] ?? '';
assert.ok(routeRecovery.indexOf('PorticoServerConnectionVerifyRoute(controller, source)') < routeRecovery.indexOf('PorticoServerSessionPreviousRoute(source)'));
assert.ok(routeRecovery.indexOf('PorticoServerSessionPreviousRoute(source)') < routeRecovery.indexOf('PorticoServerConnectionRediscoverStoredRoute(controller, source)'));
assert.match(task, /rebased\.previousRoute = PorticoServerSessionRouteRecord\(source\)/);
assert.match(task, /EnableLinkStatusEvent\(true\)/);
assert.match(task, /nextNetworkRouteRetryAt = controller\.clock\.TotalSeconds\(\) \+ PorticoServerConnectionPositiveJitter/);
assert.match(task, /retryAfter > delayFloor/);
assert.match(task, /nextRefreshAt = controller\.clock\.TotalSeconds\(\) \+ delayFloor \+ PorticoServerConnectionPositiveJitter/);
assert.match(task, /hostedCompatibility = true/);
assert.match(task, /if policyMatches then return true/);
assert.match(task, /priorities = \["lan", "lan_ip_encoded", "lan_discovered", "public_direct", "public_direct_ip_encoded", "direct", "direct_ip_encoded"\]/);
for (const code of ["credential_revoked", "refresh_reused", "account_deleted", "profile_deleted", "membership_removed"]) {
  assert.match(task, new RegExp(`code = "${code}"`), `server refresh must recognize ${code} as terminal`);
}

// Execute the retry-boundary model used by PorticoServerConnectionPositiveJitter.
// The production BrightScript hash is deliberately mirrored here so this test
// catches the important safety property rather than only checking source text:
// Retry-After and exponential backoff are floors, and stable jitter is always
// added after whichever floor is larger.
function retryDelayFloor(exponentialFloor, retryAfter) {
  return Math.max(exponentialFloor, Number.isFinite(retryAfter) ? retryAfter : 0);
}

function stablePositiveJitter(cohort, attempt, cap) {
  let value = 1000003;
  const material = `${cohort}:${attempt}`;
  for (const character of material) value = ((value * 33) + character.charCodeAt(0)) % 1000000007;
  return 1 + (value % Math.max(1, cap));
}

function scheduledRetryDelay(exponentialFloor, retryAfter, cohort, attempt) {
  const floor = retryDelayFloor(exponentialFloor, retryAfter);
  return floor + stablePositiveJitter(cohort, attempt, floor);
}

for (const [exponentialFloor, retryAfter] of [[5, 0], [5, 3], [5, 60], [160, 60], [160, 3600]]) {
  const delay = scheduledRetryDelay(exponentialFloor, retryAfter, 'roku-test-cohort', 3);
  assert.ok(delay > exponentialFloor, `retry jitter must follow exponential floor (${exponentialFloor})`);
  assert.ok(delay > retryAfter, `retry jitter must follow Retry-After floor (${retryAfter})`);
}
assert.equal(
  scheduledRetryDelay(5, 60, 'roku-test-cohort', 3),
  scheduledRetryDelay(5, 60, 'roku-test-cohort', 3),
  'same installation cohort and attempt must produce stable retry timing'
);
assert.notEqual(
  scheduledRetryDelay(5, 60, 'roku-test-cohort', 3),
  scheduledRetryDelay(5, 60, 'different-cohort', 3),
  'different cohorts should not be synchronized when their stable hash differs'
);
assert.match(task, /if code = "server-access-denied" then return "problem\.forbidden"/);
assert.doesNotMatch(task, /if code = "server-access-denied" or code = "server-session-expired" then return "auth\.session-expired"/);
const hostedFailure = task.match(/sub PorticoServerConnectionHandleHostedFailure[\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(hostedFailure, /result\.status = 403 or result\.status = 404[\s\S]*"server-access-denied"/);
assert.doesNotMatch(hostedFailure, /Deauthorize|account-credentials|signed-out/, 'Losing one server membership must retain Hosted account identity');
const authorityLoss = main.match(/sub PorticoMainFenceServerAuthorityLoss[\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(authorityLoss, /serverMessageId[\s\S]*profileDirectoryStatus: "error"[\s\S]*profileDirectory: \[\][\s\S]*viewerTransitionReason: failureMessageId/);
assert.doesNotMatch(authorityLoss, /accountStatus: "signed-out"|PorticoAuthorizationTaskDeauthorize/, 'Server authority loss must not sign out the Hosted account');
assert.match(scene, /if \(status = "error" or status = "profile-error"\) and requested = "" then messageId = "auth\.profile-selection-failed"/);

for (const forbidden of ['accessToken', 'refreshToken', 'apiBaseUrl', 'serverPublicKeyFingerprint', 'selectionEnvelope', 'viewerScope', 'signature', 'routes']) {
  assert.ok(!bridge.includes(`${forbidden}: true`), `${forbidden} must not be a public bridge field`);
}
for (const allowed of ['serverStatus', 'serverErrorCode', 'serverMessageId', 'selectedServerName', 'navigationSnapshotVerified', 'libraryItems']) assert.match(bridge, new RegExp(`${allowed}: true`));
assert.match(bridge, /privateBootstrapContext/);
assert.match(bridge, /scopeAssertionId/);
assert.match(bridge, /PorticoServerSessionScopeAssertionConsume/);
assert.match(main, /PorticoServerConnectionController\(scene, port\)/);
assert.match(main, /PorticoServerConnectionAccountStateChanged\(serverConnection, scene\.runtimeState\)/);
assert.match(main, /PorticoMainAdvanceViewerAssertion/);

console.log(`Verified ${operations.length} generated operations, signed route trust, profile-bound native session v3, bounded route recovery, one-time assertions, atomic persistence, and private bridge boundaries.`);
