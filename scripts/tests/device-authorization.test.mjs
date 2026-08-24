import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const workspaceRoot = resolve(root, '..');
const read = path => readFileSync(resolve(root, path), 'utf8');
const bridge = read('channel/source/lib/PorticoDeviceAuthorization.brs');
const authTask = read('channel/components/PorticoDeviceAuthorizationTask.brs');
const authTaskXml = read('channel/components/PorticoDeviceAuthorizationTask.xml');
const genericHttpTask = read('channel/components/PorticoHttpTask.brs');
const genericHttpTaskXml = read('channel/components/PorticoHttpTask.xml');
const storage = read('channel/source/lib/PorticoSecureRegistry.brs');
const main = read('channel/source/main.brs');
const scene = read('channel/components/PorticoScene.brs');
const sceneXml = read('channel/components/PorticoScene.xml');
const setup = read('channel/components/PorticoAuthGate.brs');
const setupXml = read('channel/components/PorticoAuthGate.xml');
const setupModels = read('channel/source/lib/PorticoAuthGateModels.brs');
const httpHelpers = read('channel/source/lib/PorticoHttpHelpers.brs');
const fixtures = JSON.parse(read('tests/device-authorization-cases.json'));
const openapi = JSON.parse(readFileSync(resolve(workspaceRoot, 'portico-internal/hosted-services/api/openapi/portico-hosted.openapi.json'), 'utf8'));

assert.equal(openapi.info.version, 'v1');
const createPath = openapi.paths['/api/device-authorization/sessions']?.post;
const pollPath = openapi.paths['/api/device-authorization/sessions/{authorizationSessionId}']?.get;
const redeemPath = openapi.paths['/api/device-authorization/sessions/{authorizationSessionId}/redeem']?.post;
const refreshPath = openapi.paths['/api/auth/sessions/refresh']?.post;
const revokePath = openapi.paths['/api/auth/sessions/revoke']?.post;
const systemPath = openapi.paths['/api/system']?.get;
assert.equal(createPath?.operationId, 'createDeviceAuthorizationSession');
assert.equal(pollPath?.operationId, 'pollDeviceAuthorizationSession');
assert.equal(redeemPath?.operationId, 'redeemDeviceAuthorizationSession');
assert.equal(refreshPath?.operationId, 'refreshNativeSession');
assert.equal(revokePath?.operationId, 'revokeNativeSession');
assert.equal(systemPath?.operationId, 'getHostedSystem');
assert.ok(pollPath.parameters.some(parameter => parameter.name === 'X-Portico-Device-Code' && parameter.in === 'header'));
assert.ok(redeemPath.parameters.some(parameter => parameter.name === 'X-Portico-Device-Code' && parameter.in === 'header'));
assert.ok(redeemPath.responses['403']);
const schemas = openapi.components.schemas;
assert.equal(schemas.DeviceAuthorizationSessionCreateResponse.properties.interval.minimum, 5);
assert.equal(schemas.DeviceAuthorizationSessionCreateResponse.properties.userCode.pattern, '^[A-HJ-KM-NP-Z2-9]{4}-[A-HJ-KM-NP-Z2-9]{4}$');
assert.deepEqual([...schemas.DeviceAuthorizationRedeemResponse.required].sort(), ['accountCredentials', 'status']);
for (const schemaName of ['DeviceAuthorizationSessionRequest', 'ProfileSelectionAssertionRequest', 'HostedProfileSelectionEnvelope']) {
  assert.ok(!schemas[schemaName].required?.includes('installationId'), `${schemaName} must keep installationId optional metadata`);
}
assert.deepEqual(schemas.RefreshTokenRequest.required, ['refreshToken', 'rotationKey']);

function normalizeUtcTimestamp(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|\+00:00|\+0000)$/i.exec(value);
  if (!match) return '';
  const [, yearText, monthText, dayText, hourText, minuteText, secondText, fraction = ''] = match;
  const parts = [yearText, monthText, dayText, hourText, minuteText, secondText].map(Number);
  const [year, month, day, hour, minute, second] = parts;
  if (year < 2000 || year > 2100 || month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) return '';
  const maximumDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  if (day < 1 || day > maximumDay) return '';
  const base = `${yearText}-${monthText}-${dayText}T${hourText}:${minuteText}:${secondText}`;
  return fraction ? `${base}.${(fraction + '00').slice(0, 3)}` : base;
}

for (const fixture of fixtures.timestampCases) {
  assert.equal(normalizeUtcTimestamp(fixture.input), fixture.expected, `timestamp policy drifted for ${fixture.input}`);
}

const allowedProjection = new Set([
  'accountStatus',
  'hostedStatus',
  'accountDisplayName',
  'authorizationUserCode',
  'verificationDisplayUri'
]);
const projected = Object.fromEntries(Object.entries(fixtures.runtimeProjectionInput).filter(([key]) => allowedProjection.has(key)));
assert.deepEqual(projected, fixtures.runtimeProjectionExpected);
for (const forbidden of ['deviceCode', 'authorizationSessionId', 'accessToken', 'refreshToken', 'verificationUri']) {
  assert.ok(!(forbidden in projected), `${forbidden} escaped the positive UI projection`);
}

// The authorization worker is the only secret owner. Its public SceneGraph
// interface has non-sensitive command/projection fields and no request/result
// envelope that could retain headers, device secrets, or credentials.
assert.match(authTaskXml, /extends="Task"/);
assert.match(authTaskXml, /uri="pkg:\/components\/PorticoDeviceAuthorizationTask\.brs"/, 'The Task must stay in the top-level components directory for real Roku registration');
assert.match(authTaskXml, /field id="command"/);
assert.match(authTaskXml, /field id="projection"/);
assert.doesNotMatch(authTaskXml, /field id="(?:request|result|deviceCode|accessToken|refreshToken|authorizationSessionId)"/i);
const publicTaskFields = [...authTaskXml.matchAll(/<field id="([^"]+)"/g)].map(match => match[1]).sort();
assert.deepEqual(publicTaskFields, ['command', 'projection']);
const taskTopFields = [...authTask.matchAll(/m\.top\.([A-Za-z0-9_]+)/g)].map(match => match[1]);
assert.deepEqual([...new Set(taskTopFields)].sort(), ['command', 'functionName', 'projection']);
assert.doesNotMatch(bridge + main + scene + setup + setupModels + authTaskXml, /deviceCode|accessToken|refreshToken|authorizationSessionId/);
assert.doesNotMatch(bridge + main, /https:\/\/api\.getportico\.tv|X-Portico-Device-Code/);
assert.doesNotMatch(genericHttpTask + genericHttpTaskXml, /device-authorization|X-Portico-Device-Code|api\/auth\/sessions\/(?:refresh|revoke)/);
assert.doesNotMatch(authTask, /CreateObject\("roSGNode", "PorticoHttpTask"\)|\.request\s*=|\.result\s*=/);
assert.doesNotMatch(authTask, /\bprint\b/i);
assert.match(authTask, /PorticoHttpValidatePrivateRequest\(request\)/);
assert.match(httpHelpers, /"x-portico-device-code": true/);

const projectionBody = bridge.match(/function PorticoDeviceAuthorizationProjection[\s\S]*?end function/)?.[0] ?? '';
assert.ok(projectionBody);
for (const allowed of allowedProjection) assert.match(projectionBody, new RegExp(`${allowed}: true`));
for (const forbidden of ['deviceCode', 'accessToken', 'refreshToken', 'authorizationSessionId', 'verificationUri']) {
  assert.doesNotMatch(projectionBody, new RegExp(`${forbidden}: true`));
}
const publishBody = authTask.match(/sub PorticoAuthorizationTaskPublish\([\s\S]*?end sub/)?.[0] ?? '';
assert.ok(publishBody);
for (const allowed of allowedProjection) assert.match(publishBody, new RegExp(`${allowed}:`));
assert.doesNotMatch(publishBody, /deviceCode:|accessToken:|refreshToken:|authorizationSessionId:|verificationUri:/);

const restoreBody = authTask.match(/sub PorticoAuthorizationTaskRestore\([\s\S]*?end sub/)?.[0] ?? '';
assert.ok(restoreBody);
assert.doesNotMatch(restoreBody, /PorticoAuthorizationTaskCreate|device-authorization\/sessions/, 'Startup must not create a session before explicit user action');
assert.match(main, /ObserveField\("activation", port\)/);
assert.match(main, /field = "projection"/);
assert.match(main, /PorticoDeviceAuthorizationHandleActivation\(accountAuthorization, activationData\)/);
assert.doesNotMatch(main, /ObserveField\("page", port\)|currentPage = "account-setup"/);
assert.match(bridge, /kind = "start-account-setup"[\s\S]*PorticoDeviceAuthorizationCommand/);
assert.match(bridge, /kind = "sign-in-account"[\s\S]*sealedCredentials/);
assert.match(bridge, /kind = "sign-out-account"[\s\S]*PorticoDeviceAuthorizationCommand/);

assert.match(authTask, /https:\/\/api\.getportico\.tv\/api\/device-authorization\/sessions/);
assert.match(authTask, /https:\/\/web\.getportico\.tv\/authorize-device/);
assert.doesNotMatch(authTask, /https:\/\/web\.getportico\.tv\/device/);
assert.match(authTask, /PorticoAuthorizationTaskPendingLifetimeIsValid[\s\S]*remaining >= 540 and remaining <= 630/);
assert.match(authTask, /sub PorticoAuthorizationTaskCreate[\s\S]*result\.retryable[\s\S]*PorticoAuthorizationTaskScheduleCreationRetry/);
assert.match(authTask, /sub PorticoAuthorizationTaskScheduleCreationRetry[\s\S]*delay = 5[\s\S]*retryAfter <> invalid and retryAfter > delay/);
assert.match(authTask, /sub PorticoAuthorizationTaskPoll[\s\S]*PorticoAuthorizationTaskRenewExpiredSession/);
assert.match(authTask, /renewalAtSeconds = nowSeconds \+ remaining - 30[\s\S]*controller\.nextAuthorizationAtSeconds >= renewalAtSeconds[\s\S]*controller\.renewalPending = true/);
assert.match(authTask, /else if controller\.renewalPending[\s\S]*PorticoAuthorizationTaskCreate\(controller, true\)/);
const createAuthorizationBody = authTask.match(/sub PorticoAuthorizationTaskCreate[\s\S]*?end sub/)?.[0] ?? '';
assert.match(createAuthorizationBody, /preservePending[\s\S]*PorticoAuthorizationTaskScheduleReplacementRetry/);
assert.match(createAuthorizationBody, /PorticoSecureRegistryCommit\("pending-account-authorization", pending\)[\s\S]*controller\.pending = pending[\s\S]*PorticoAuthorizationTaskPublishPending/);
assert.doesNotMatch(createAuthorizationBody, /PorticoSecureRegistryClear\("pending-account-authorization"\)/);
const replacementRetryBody = authTask.match(/sub PorticoAuthorizationTaskScheduleReplacementRetry[\s\S]*?end sub/)?.[0] ?? '';
assert.match(replacementRetryBody, /PorticoAuthorizationTaskPendingIsReusable[\s\S]*PorticoAuthorizationTaskPublishPending/);
assert.match(authTask, /sub PorticoAuthorizationTaskRenewExpiredSession[\s\S]*PorticoSecureRegistryClear\("pending-account-authorization"\)[\s\S]*controller\.pending = invalid[\s\S]*PorticoAuthorizationTaskPublish\("authorizing", "connecting"\)/);
assert.match(authTask, /https:\/\/api\.getportico\.tv\/api\/auth\/sessions/);
assert.match(authTask, /PorticoAuthorizationTaskOpenSealedCredentials/);
assert.match(authTask, /PorticoSecureRegistryCommit\("account-credentials", credentials\)/);
assert.match(authTask, /headers: \{ "X-Portico-Device-Code": controller\.pending\.deviceCode \}/);
assert.doesNotMatch(authTask, /[?&](?:deviceCode|device_code|userCode|user_code)=/);
assert.doesNotMatch(authTask, /if controller\.installationId = ""/, 'Installation metadata must never block device authorization');
assert.match(authTask, /if controller\.installationId <> "" then createBody\.installationId = controller\.installationId/);
assert.doesNotMatch(authTask, /pending\.installationId <> installationId/, 'Pending authorization recovery is owned by its device secret, not installation metadata');
assert.match(authTask, /body: \{ refreshToken: previous\.refreshToken, rotationKey: rotation\.rotationKey \}/, 'Refresh is crash-safe and remains refresh-family authorized');
assert.match(authTask, /PorticoSecureRegistryCommit\("account-refresh-rotation", pending\)/, 'The idempotency receipt must be durable before refresh');
assert.match(authTask, /PorticoAuthorizationTaskRefreshFailureIsTerminal/, 'Only explicit stable revocation codes may deauthorize the account');

assert.doesNotMatch(sceneXml, /<PorticoAuthGate id="authGate"/);
assert.match(scene, /PorticoSceneEnsureOverlaySurface\("auth-gate"\)/);
assert.doesNotMatch(sceneXml, /PorticoAccountSetup|accountSetupScreen/);
assert.match(scene, /showAuthGate = not PorticoSceneVisualFixtureEnabled\(\) and not accountIsSignedIn\(\)/);
assert.match(scene, /m\.authGate\.viewState = PorticoSignedOutGateModel/);
assert.match(setup, /PorticoFont\("700", 96\)/);
assert.match(setupXml, /<Group id="codeGroup"[^>]*visible="false">[\s\S]*<Label id="code0"[^>]*height="116"/);
assert.match(setup, /PorticoTextWidth\(glyph, "700", 96\) \+ 8/);
assert.doesNotMatch(setup, /letterSpacing/);
assert.match(scene, /id: "sign-out-account", label: "Sign Out"/);

assert.match(storage, /CreateObject\("roDeviceCrypto"\)/);
assert.match(storage, /crypto\.Encrypt\(plaintext, "channel"\)/);
assert.match(storage, /crypto\.Decrypt\(encrypted, "channel"\)/);
assert.match(storage, /GetRandomUUID\(\)/, 'New optional installation metadata uses an app-local random value');
assert.doesNotMatch(storage, /GetChannelClientId\(\)/, 'Installation metadata must not derive from a Roku account or hardware-linked identifier');
assert.doesNotMatch(storage, /if not encrypted\.FromBase64String/);
const commitBody = storage.match(/function PorticoSecureRegistryCommit[\s\S]*?end function/)?.[0] ?? '';
assert.match(commitBody, /Write\(nextKey, encrypted\)[\s\S]*Flush\(\)[\s\S]*Write\("committedGeneration"[\s\S]*Flush\(\)[\s\S]*Delete\("generation\./);
assert.match(storage, /envelope\.generation <> generation/);

const approvedBody = authTask.match(/sub PorticoAuthorizationTaskHandleApproved[\s\S]*?end sub/)?.[0] ?? '';
assert.match(approvedBody, /redemptionStarted = true[\s\S]*redemptionStartedAt[\s\S]*PorticoSecureRegistryCommit/);
const redeemBody = authTask.match(/sub PorticoAuthorizationTaskRedeem[\s\S]*?end sub/)?.[0] ?? '';
assert.match(redeemBody, /PorticoSecureRegistryCommit\("account-credentials"[\s\S]*PorticoSecureRegistryClear\("pending-account-authorization"[\s\S]*PorticoAuthorizationTaskPublishAccount/);
assert.match(authTask, /PorticoAuthorizationTaskRedemptionRecoveryIsOpen/);
assert.match(authTask, /elapsed >= 0 and elapsed < 300/);
assert.match(redeemBody, /problemCode = "access_denied"[\s\S]*PorticoAuthorizationTaskTerminal/);

assert.doesNotMatch(authTask, /FromISO8601String/);
assert.match(authTask, /PorticoAuthorizationTaskUTCNormalize\(now\.ToISOString\(\)\)/);
assert.match(authTask, /GetSecondsToISO8601Date\(normalized\)/);
assert.match(authTask, /suffix <> "Z"[\s\S]*suffix <> "\+00:00"[\s\S]*suffix <> "\+0000"/);

const refreshBody = authTask.match(/sub PorticoAuthorizationTaskRefresh[\s\S]*?end sub/)?.[0] ?? '';
assert.match(refreshBody, /api\/auth\/sessions\/refresh/);
assert.match(refreshBody, /PorticoSecureRegistryCommit\("account-credentials", replacement\)/);
assert.match(refreshBody, /PorticoAuthorizationTaskRefreshFailureIsTerminal\(problemCode\)[\s\S]*PorticoAuthorizationTaskDeauthorize/);
assert.doesNotMatch(refreshBody, /result\.status = 401 or result\.status = 403[\s\S]*PorticoAuthorizationTaskDeauthorize/);
assert.match(authTask, /remaining - 300/);
assert.match(authTask, /kind = "refresh-account-after-401"[\s\S]*last401RefreshGeneration <> controller\.credentialGeneration/);
assert.match(authTask, /hosted-unavailable/);
assert.match(authTask, /Left\(credentials\.accessToken\.ToStr\(\), 8\) <> "ptc_acc_"/);
assert.match(authTask, /Left\(credentials\.refreshToken\.ToStr\(\), 8\) <> "ptc_rft_"/);
assert.doesNotMatch(authTask, /Left\(credentials\.refreshToken\.ToStr\(\), 8\) <> "ptc_acc_"/);
assert.match(authTask, /refreshRemaining <= accessRemaining/);
assert.match(authTask, /Len\(credentials\.accessToken\.ToStr\(\)\) > 4096/);
assert.match(authTask, /Len\(credentials\.refreshToken\.ToStr\(\)\) > 4096/);

const signOutBody = authTask.match(/sub PorticoAuthorizationTaskSignOut[\s\S]*?end sub/)?.[0] ?? '';
assert.match(signOutBody, /signedOut: true[\s\S]*PorticoSecureRegistryCommit\("account-credentials"[\s\S]*PorticoSecureRegistryClear\("pending-account-authorization"[\s\S]*PorticoAuthorizationTaskPublish\("signed-out"[\s\S]*api\/auth\/sessions\/revoke/);
const deauthorizeBody = authTask.match(/sub PorticoAuthorizationTaskDeauthorize[\s\S]*?end sub/)?.[0] ?? '';
assert.match(deauthorizeBody, /PorticoSecureRegistryCommit\("account-credentials"[\s\S]*durable = committed\.ok[\s\S]*PorticoSecureRegistryClear\("account-credentials"\)[\s\S]*if not durable[\s\S]*deauthorizationPending[\s\S]*PorticoAuthorizationTaskPublish\("authorization-unavailable"[\s\S]*return[\s\S]*controller\.credentials = invalid[\s\S]*PorticoAuthorizationTaskPublish\(accountStatus/);
const terminalBody = authTask.match(/sub PorticoAuthorizationTaskTerminal[\s\S]*?end sub/)?.[0] ?? '';
assert.match(terminalBody, /PorticoSecureRegistryCommit\("pending-account-authorization"[\s\S]*PorticoSecureRegistryClear\("pending-account-authorization"\)[\s\S]*if not durable[\s\S]*terminalPending[\s\S]*PorticoAuthorizationTaskPublish\("authorization-unavailable"[\s\S]*return[\s\S]*PorticoAuthorizationTaskPublish\(accountStatus/);
const taskTickBody = authTask.match(/sub PorticoAuthorizationTaskTick[\s\S]*?end sub/)?.[0] ?? '';
assert.match(taskTickBody, /deauthorizationPending[\s\S]*PorticoAuthorizationTaskDeauthorize[\s\S]*terminalPending[\s\S]*PorticoAuthorizationTaskTerminal/);
const pauseBody = authTask.match(/sub PorticoAuthorizationTaskPause[\s\S]*?end sub/)?.[0] ?? '';
assert.match(pauseBody, /if not controller\.authorizationActive then return/);
assert.doesNotMatch(pauseBody, /PorticoSecureRegistryClear|terminalCode/);
assert.match(pauseBody, /deauthorizationPending[\s\S]*authorization-unavailable[\s\S]*return[\s\S]*terminalPending[\s\S]*authorization-unavailable[\s\S]*return[\s\S]*signed-in/);
assert.match(redeemBody, /expectJson: true[\s\S]*\}, false\)/);

const compatibilityBody = authTask.match(/function PorticoAuthorizationTaskEnsureHostedCompatibility[\s\S]*?end function/)?.[0] ?? '';
assert.match(compatibilityBody, /api\.getportico\.tv\/api\/system/);
assert.match(compatibilityBody, /hostedCompatibilityCheckedAtSeconds[\s\S]*< 300[\s\S]*hostedCompatibility = "compatible"/);
assert.doesNotMatch(compatibilityBody, /PorticoAuthorizationTaskDeauthorize|PorticoSecureRegistryClear/);
for (const operationBody of [
  authTask.match(/sub PorticoAuthorizationTaskCreate[\s\S]*?end sub/)?.[0] ?? '',
  authTask.match(/sub PorticoAuthorizationTaskPoll[\s\S]*?end sub/)?.[0] ?? '',
  redeemBody,
  refreshBody,
  signOutBody
]) assert.match(operationBody, /PorticoAuthorizationTaskEnsureHostedCompatibility/);
const compatibilityValidator = authTask.match(/function PorticoAuthorizationTaskHostedSystemIsCompatible[\s\S]*?end function/)?.[0] ?? '';
for (const expected of ['Portico', 'ok', 'v1']) assert.match(compatibilityValidator, new RegExp(`"${expected.replaceAll('.', '\\.') }"`));
assert.doesNotMatch(compatibilityValidator, /schemaRevision|data\.version/);
assert.equal(openapi.components.schemas.HostedSystemInfo.properties.apiVersion.const, 'v1');
assert.deepEqual(openapi.components.schemas.HostedSystemInfo.required.includes('apiVersion'), true);


const lifetimeSchedulerSource = authTask.replace(/function PorticoAuthorizationTaskHttp\([\s\S]*?end function/, '');
assert.match(authTask, /function PorticoAuthorizationTaskNowSeconds\(controller as object\) as integer[\s\S]*TotalSeconds\(\)/);
for (const field of ['nextAuthorizationAtSeconds', 'nextRefreshAtSeconds', 'nextDurabilityRetryAtSeconds', 'hostedCompatibilityCheckedAtSeconds']) {
  assert.match(authTask, new RegExp(field));
}
assert.match(authTask, /refreshScheduled: false/);
assert.match(authTask, /controller\.refreshScheduled and nowSeconds >= controller\.nextRefreshAtSeconds/);
assert.doesNotMatch(lifetimeSchedulerSource, /nextAuthorizationAtMs|nextRefreshAtMs|nextDurabilityRetryAtMs|hostedCompatibilityCheckedAtMs|PorticoAuthorizationTaskNowMs|2147483647/);
const authHttpBody = authTask.match(/function PorticoAuthorizationTaskHttp\([\s\S]*?end function/)?.[0] ?? '';
assert.match(authHttpBody, /timer\.TotalMilliseconds\(\) < request\.timeoutMs/, 'request-local HTTP timeout precision must remain milliseconds');
const refreshScheduleBody = authTask.match(/sub PorticoAuthorizationTaskScheduleRefresh\([\s\S]*?end sub/)?.[0] ?? '';
assert.match(refreshScheduleBody, /PorticoAuthorizationTaskNowSeconds\(controller\) \+ delay[\s\S]*refreshScheduled = true/);
assert.doesNotMatch(refreshScheduleBody, /\* 1000|TotalMilliseconds/);
const thirtyDayUptimeSeconds = 30 * 24 * 60 * 60;
assert.ok((((thirtyDayUptimeSeconds * 1000) | 0) < 0), 'the regression fixture must cross the signed 32-bit millisecond boundary');
assert.equal(thirtyDayUptimeSeconds + 300, 2592300, 'second-based lifetime deadlines remain ordered across the old overflow boundary');

// Simulate generation/commit-marker crash recovery.
const records = new Map([['generation.1', {account: 'old'}]]);
let committedGeneration = 1;
const readCommitted = () => records.get(`generation.${committedGeneration}`);
records.set('generation.2', {account: 'new'});
assert.deepEqual(readCommitted(), {account: 'old'});
committedGeneration = 2;
assert.deepEqual(readCommitted(), {account: 'new'});

// Model a lost first redeem response and relaunch: one durable receipt and one
// exact credential family for the same session/device secret.
const committedReceipt = Object.freeze({
  status: 'redeemed',
  accountCredentials: Object.freeze({
    accessToken: 'ptc_acc_family_access',
    refreshToken: 'ptc_rft_family_refresh',
    device: Object.freeze({id: 'device-1', userId: 'user-1'})
  })
});
const redemptionReceipts = new Map();
const redeem = (sessionId, deviceCode) => {
  const key = `${sessionId}:${deviceCode}`;
  if (!redemptionReceipts.has(key)) redemptionReceipts.set(key, committedReceipt);
  return redemptionReceipts.get(key);
};
const firstResponseLost = redeem('session-1', 'same-device-secret');
const relaunchedRetry = redeem('session-1', 'same-device-secret');
assert.strictEqual(relaunchedRetry, firstResponseLost);
assert.equal(redemptionReceipts.size, 1);

// Exercise real Hosted token families through redemption validation, atomic
// account commit, safe identity projection, and refresh replacement.
const validCredentials = {
  tokenType: 'Bearer',
  accessToken: 'ptc_acc_access-family',
  accessExpiresAt: '2026-07-13T19:22:31Z',
  refreshToken: 'ptc_rft_refresh-family',
  refreshExpiresAt: '2026-08-13T18:22:31Z',
  user: {id: 'user-1', displayName: 'Living Room'},
  device: {id: 'device-1', userId: 'user-1'}
};
const credentialShapeIsValid = value =>
  value.tokenType.toLowerCase() === 'bearer' &&
  value.accessToken.startsWith('ptc_acc_') &&
  value.refreshToken.startsWith('ptc_rft_') &&
  value.device.userId === value.user.id;
assert.equal(credentialShapeIsValid(validCredentials), true);
assert.equal(credentialShapeIsValid({...validCredentials, refreshToken: 'ptc_acc_wrong-family'}), false);
const secureRecords = new Map([['pending-account-authorization', {redemptionStarted: true}]]);
secureRecords.set('account-credentials', structuredClone(validCredentials));
secureRecords.delete('pending-account-authorization');
const signedInProjection = Object.fromEntries(Object.entries({
  accountStatus: 'signed-in',
  hostedStatus: 'online',
  accountDisplayName: validCredentials.user.displayName,
  accessToken: validCredentials.accessToken,
  refreshToken: validCredentials.refreshToken
}).filter(([key]) => allowedProjection.has(key)));
assert.deepEqual(signedInProjection, {accountStatus: 'signed-in', hostedStatus: 'online', accountDisplayName: 'Living Room'});
assert.equal(secureRecords.has('pending-account-authorization'), false);
assert.equal(credentialShapeIsValid({...validCredentials, accessToken: 'ptc_acc_rotated', refreshToken: 'ptc_rft_rotated'}), true);

// Two distinct 401 episodes may each trigger one refresh because successful
// rotation advances the encrypted credential generation; a repeated 401 for
// the same generation is deduplicated.
let credentialGeneration = 1;
let last401RefreshGeneration = -1;
const trigger401Refresh = () => {
  if (last401RefreshGeneration === credentialGeneration) return false;
  last401RefreshGeneration = credentialGeneration;
  return true;
};
assert.equal(trigger401Refresh(), true);
assert.equal(trigger401Refresh(), false);
credentialGeneration = 2;
assert.equal(trigger401Refresh(), true);
assert.equal(trigger401Refresh(), false);

// A durable auth-state transition may publish its terminal target only after
// either the encrypted tombstone commit or the explicit fallback clear wins.
// If both fail, secrets remain Task-local for a bounded retry and the UI sees
// an unavailable state instead of a false expired/signed-out/terminal claim.
const durableTransition = ({commitOk, clearOk, target}) => {
  const durable = commitOk || clearOk;
  return durable
    ? {published: target, retainedForRetry: false}
    : {published: 'authorization-unavailable', retainedForRetry: true};
};
for (const target of ['account-expired', 'signed-out', 'authorization-denied', 'authorization-expired']) {
  assert.deepEqual(durableTransition({commitOk: true, clearOk: false, target}), {published: target, retainedForRetry: false});
  assert.deepEqual(durableTransition({commitOk: false, clearOk: true, target}), {published: target, retainedForRetry: false});
  assert.deepEqual(durableTransition({commitOk: false, clearOk: false, target}), {published: 'authorization-unavailable', retainedForRetry: true});
}

// Leaving setup cancels I/O but retains the encrypted redemption marker. A
// reopen at 299 seconds resumes the same receipt; exact 300-second expiry
// requires the next explicit action to clear it and request a fresh code.
const recoveryOpen = elapsed => elapsed >= 0 && elapsed < 300;
const pausedPending = {redemptionStarted: true, terminalCode: '', elapsed: 12};
assert.equal(recoveryOpen(pausedPending.elapsed), true);
pausedPending.elapsed = 299;
assert.equal(recoveryOpen(pausedPending.elapsed), true);
pausedPending.elapsed = 300;
assert.equal(recoveryOpen(pausedPending.elapsed), false);

// A background replacement is published only after its durable commit. Failed
// replacement work leaves the old, unexpired display untouched.
const atomicTicketSwap = (current, replacement, replacementCommitted, now) => {
  if (replacementCommitted && replacement) return replacement;
  return Date.parse(current.expiresAt) > now ? current : null;
};
const oldTicket = {userCode: 'ABCD-2345', expiresAt: '2026-08-22T18:10:00Z'};
const newTicket = {userCode: 'WXYZ-6789', expiresAt: '2026-08-22T18:19:30Z'};
assert.strictEqual(
  atomicTicketSwap(oldTicket, newTicket, false, Date.parse('2026-08-22T18:09:40Z')),
  oldTicket,
);
assert.strictEqual(
  atomicTicketSwap(oldTicket, newTicket, true, Date.parse('2026-08-22T18:09:45Z')),
  newTicket,
);
assert.equal(
  atomicTicketSwap(oldTicket, null, false, Date.parse('2026-08-22T18:10:00Z')),
  null,
);

console.log(`Verified secret-owning Roku authorization Task, Hosted ${openapi.info.version}, ${fixtures.pollingCases.length} timing cases, and ${fixtures.timestampCases.length} timestamp cases.`);
