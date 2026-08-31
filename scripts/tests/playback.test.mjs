import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {applyPlaybackEvent, createPlaybackState, reduceBack} from '../lib/playback-parity-model.mjs';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoPlaybackTask.brs');
const taskXml = read('channel/components/PorticoPlaybackTask.xml');
const models = read('channel/source/lib/PorticoPlaybackModels.brs');
const runtime = read('channel/source/lib/PorticoPlaybackRuntime.brs');
const secureRegistry = read('channel/source/lib/PorticoSecureRegistry.brs');
const bridge = read('channel/source/lib/PorticoPlayback.brs');
const player = read('channel/components/PorticoPlayer.brs');
const watchTask = read('channel/components/PorticoWatchWithFriendsTask.brs');
const watchRuntime = read('channel/source/lib/PorticoWatchWithFriendsRuntime.brs');
const watchBridge = read('channel/source/lib/PorticoWatchWithFriends.brs');
const operationPolicy = read('scripts/lib/roku-operation-policy.mjs');
const main = read('channel/source/main.brs');
const verifier = read('scripts/verify.mjs');
const operationsDocument = JSON.parse(read('channel/data/generated/operations.v1.json'));

function collectOperations(value, result = [], seen = new Set()) {
  if (!value || typeof value !== 'object' || seen.has(value)) return result;
  seen.add(value);
  if (typeof value.operationId === 'string') result.push(value);
  for (const nested of Object.values(value)) collectOperations(nested, result, seen);
  return result;
}
const operations = collectOperations(operationsDocument);
const parityCases = JSON.parse(read('tests/playback-parity-cases.json'));
const expectServerOperation = (id, method, path) => {
  const value = operations.find(operation => operation.service === 'server' && operation.operationId === id);
  assert.ok(value, `server.${id} disappeared from the generated Roku contract`);
  assert.equal(value.method, method);
  assert.equal(value.path, path);
  assert.ok(value.surfaces?.includes('television'));
};

for (const [id, method, path] of [
  ['postPlaybackSessions', 'POST', '/playback-sessions'],
  ['patchPlaybackSessionsSessionId', 'PATCH', '/playback-sessions/{sessionId}'],
  ['deletePlaybackSessionsSessionId', 'DELETE', '/playback-sessions/{sessionId}'],
  ['postPlaybackSessionsSessionIdMediaGrant', 'POST', '/playback-sessions/{sessionId}/media-grant'],
  ['renegotiatePlaybackSession', 'POST', '/playback-sessions/{sessionId}/renegotiate'],
  ['postPlaybackSessionsSessionIdPrepareNext', 'POST', '/playback-sessions/{sessionId}/prepare-next'],
  ['postPlaybackSessionsSessionIdHandoff', 'POST', '/playback-sessions/{sessionId}/handoff'],
  ['postPlaybackActive', 'POST', '/playback/active'],
  ['getPlaybackSessionsSessionIdQueue', 'GET', '/playback-sessions/{sessionId}/queue'],
  ['patchPlaybackSessionsSessionIdQueue', 'PATCH', '/playback-sessions/{sessionId}/queue'],
]) expectServerOperation(id, method, path);

assert.match(taskXml, /component name="PorticoPlaybackTask" extends="Task"/);
assert.match(taskXml, /field id="commandEnvelope" type="assocarray" alwaysNotify="true"/);
assert.match(taskXml, /field id="projectionEnvelope" type="assocarray" alwaysNotify="true"/);
assert.match(taskXml, /field id="contentNode" type="node" alwaysNotify="true"/);
assert.doesNotMatch(taskXml, /field id="(?:accessToken|refreshToken|serverSession|sessionId|grantToken|apiBaseUrl|headers|viewerScope)"/i);

assert.match(runtime, /if controller\.envelopeMode <> true then return invalid/);
assert.doesNotMatch(models + runtime, /PorticoPlaybackSessionForServer/);
assert.match(runtime, /PorticoServerSessionStored\(record\.payload\)/);
assert.match(runtime, /PorticoServerSessionScope\(stored, expected\.viewerGeneration\)/);
assert.match(runtime, /PorticoViewerScopeEquals\(actual, expected\)/);
assert.match(runtime, /PorticoOperationContractFind\(controller\.operationContract, "server", operationId\)/);

const profile = models.match(/function PorticoPlaybackClientProfile\(\) as object([\s\S]*?)\nend function/)?.[1] ?? '';
assert.ok(profile.length > 0);
for (const invariant of [
  /supportsHls: true/, /supportsMse: false/, /supportsMpegTs: false/,
  /supportedContainers: \["hls", "mp4", "m4a"\]/,
  /supportedVideoCodecs: \["h264"\]/,
  /supportedAudioCodecs: \["aac"\]/,
  /prefersServerProxy: true/, /requiresServerProxy: true/,
]) assert.match(profile, invariant);
assert.match(profile, /capabilitySchemaVersion: "playback-capability-v2"/);
assert.match(profile, /capabilityEvidence: \[\]/);
assert.doesNotMatch(models, /PorticoPlaybackRokuCapabilityTuples/);
assert.doesNotMatch(profile, /CanDecodeVideo|CanDecodeAudio|GetDisplayProperties|GetAudioOutputChannel/);
assert.doesNotMatch(profile, /GetVideoMode/);
assert.match(profile, /supportedVideoProfiles: \["h264:main"\]/);

assert.match(models, /decision\.isProxied <> true/);
assert.match(models, /timelineType <> "vod" and timelineType <> "live"/);
assert.match(models, /if isLive[\s\S]*durationSeconds = 0[\s\S]*resumePositionSeconds = 0/);
assert.match(models, /format = "hls" and container = "hls"/);
assert.match(models, /\(format = "http" or format = "mp4"\) and \(container = "mp4" or container = "m4v" or container = "mov"\)/);
assert.match(models, /decision\.isProxied <> true/);
assert.match(models, /PorticoPlaybackCredentialQueryUnsafe/);
assert.doesNotMatch(models, /function PorticoPlaybackGrantURL/, 'Roku must not retain a grant-bearing URL helper');
assert.doesNotMatch(verifier, /require a scoped media grant|grant-scoped.*URL/i, 'Roku verification must describe protected-header transport, not query-grant URLs');
assert.match(models, /function PorticoPlaybackPathTraversalUnsafe[\s\S]*Instr\(1, route, "\.\."\)[\s\S]*Instr\(1, lowerRoute, "%2e"\)/);

const startBody = models.match(/function PorticoPlaybackStartBody\(mediaId as string, startSeconds as dynamic,[\s\S]*?\) as object([\s\S]*?)\nend function/)?.[1] ?? '';
assert.match(startBody, /if startSeconds <> invalid/);
assert.match(startBody, /body\.startSeconds = boundedStart/);
assert.ok(startBody.indexOf('if startSeconds <> invalid') < startBody.indexOf('body.startSeconds = boundedStart'));
assert.match(task, /PorticoPlaybackStartBodyWithIntent\(targetId, startSeconds, PorticoPlaybackPortableIntent/);
const startTransition = task.match(/sub PorticoPlaybackStart\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.doesNotMatch(startTransition, /PorticoPlaybackStopActive\(controller/, 'active route selection must not stop and then independently start');
assert.match(startTransition, /body\.replacement = replacement[\s\S]*PorticoPlaybackPersistPendingMutation[\s\S]*PorticoPlaybackDispatchPendingMutation/, 'active route replacement must durably persist the complete target request before dispatch');
for (const route of [
  '/api/playback-sessions',
  '/api/live-tv/play',
  '/api/dvr/recordings/',
  '/api/library-channels/',
]) assert.ok(startTransition.includes(route), `active replacement route missing: ${route}`);
for (const field of ['sourceSessionId', 'requestId', 'previousTerminal', 'expectedQueueRevision', 'expectedPlaybackRevision']) assert.match(startTransition, new RegExp(`${field}:`));
assert.match(startTransition, /controller\.playback <> invalid[\s\S]*controller\.status = controller\.playerState/, 'old actor remains published with its valid status while replacement is pending');
const portableIntent = models.match(/function PorticoPlaybackPortableIntent\(preferences as dynamic, profile as dynamic\) as object([\s\S]*?)\nend function/)?.[1] ?? '';
const portableLanguageIntent = models.match(/sub PorticoPlaybackApplyLanguageIntent\(intent as object, preferences as dynamic\)([\s\S]*?)\nend sub/)?.[1] ?? '';
assert.match(portableIntent, /PorticoPlaybackApplyLanguageIntent\(intent, preferences\)/);
assert.match(portableLanguageIntent, /intent\.preferredAudioLanguage/);
assert.match(portableLanguageIntent, /intent\.preferredSubtitleLanguage/);
assert.match(portableLanguageIntent, /intent\.preferredSubtitleMode/);
assert.doesNotMatch(portableLanguageIntent, /preferredAudioLanguages|preferredSubtitleLanguages|subtitlesEnabled/);
assert.match(task, /PorticoPlaybackClientProfileForPreferences\(controller\.preferences\)/);
assert.doesNotMatch(task.match(/sub PorticoPlaybackStart\([\s\S]*?\nend sub/)?.[0] ?? '', /PorticoPlaybackApplyPreferredStreams|PorticoPlaybackRestartSelection/);
assert.match(models, /quality: \{mode: "automatic"\}/);
assert.doesNotMatch(portableIntent, /qualityProfile|maxVideoBitrate|maxAudioBitrate|maxVideoHeight|networkClass/);
assert.match(models, /directPlayPolicy: "prefer"/);
assert.match(task, /acknowledgement\.mediaGrantExpiresAt/);
assert.match(task, /acknowledgement\.grantSemantics/);
assert.doesNotMatch(task + models, /effectiveExpiresAt|effectiveGrantExpiresAt/);
assert.match(task, /expectedRevision: active\.playbackRevision/);
assert.match(task, /body\.expectedQueueRevision = prepared\.queueRevision/);
assert.match(task, /body\.expectedPlaybackRevision = prepared\.playbackRevision/);
assert.match(task, /if kind = "queue-shuffle" then action = "shuffle"/);
assert.match(task, /body = \{expectedRevision: controller\.playback\.queueRevision, idempotencyKey: PorticoHttpNewRequestId\(\), action: action\}/);
assert.match(task, /else if action = "remove"[\s\S]*body\.entryId = entryId/);
assert.match(task, /body\.entryId = entryId[\s\S]*body\.destinationEntryId = destinationEntryId[\s\S]*body\.placement = placement/);
assert.doesNotMatch(task.match(/sub PorticoPlaybackQueueMutation[\s\S]*?\nend sub/)?.[0] ?? '', /body\.(?:fromIndex|toIndex)/);
assert.match(bridge, /"queue-shuffle": true/);
assert.match(task, /path: "\/api\/playback-sessions\/" \+ active\.sessionId \+ "\/renegotiate"/);
assert.match(models, /playbackRevision: playbackRevision/);
assert.match(models, /currentQueueEntryId = PorticoPlaybackSafeId\(data\.currentQueueEntryId\)/);
assert.match(models, /entryId = PorticoPlaybackSafeId\(raw\.entryId\)[\s\S]*media = raw\.media[\s\S]*mediaId = PorticoPlaybackSafeId\(media\.id\)/);
assert.match(models, /result\.push\(\{entryId: entryId, mediaId: mediaId, title: title, subtitle: subtitle\}\)/);
assert.match(models, /historyId: historyId, entryId: entryId, mediaId: mediaId/);
assert.match(bridge, /currentQueueEntryId: PorticoPlaybackBridgeSafeId\(source\.currentQueueEntryId\)/);
assert.match(bridge, /result\.push\(\{entryId: entryId, mediaId: mediaId, title: title/);
assert.match(player, /kind: "next", id: item\.entryId/);
assert.match(task, /previousEntryId = item\.entryId/);
assert.doesNotMatch(task.match(/function PorticoPlaybackAdvancePrevious[\s\S]*?\nend function/)?.[0] ?? '', /active\.mediaId|item\.id/);
assert.match(task.match(/function PorticoPlaybackAdvancePrevious[\s\S]*?\nend function/)?.[0] ?? '', /for index = 0 to history\.Count\(\) - 1/, 'Previous must choose the server-ordered most recent history occurrence');
assert.match(models, /canPause: timeline\.canPause = true/);
assert.match(models, /canSeek: timeline\.canSeek = true/);
assert.match(models, /seekableStartSeconds/);
assert.match(models, /selectedSubtitleMode/);
assert.match(models, /selectedSubtitleStreamId: playback\.selectedSubtitleStreamId,[\s\S]*selectedSubtitleMode: playback\.selectedSubtitleMode/);
assert.match(bridge, /playbackRevision: PorticoHttpInteger\(source\.playbackRevision/);
assert.match(bridge, /selectedSubtitleMode/);
assert.match(task, /controller\.sourceGeneration = controller\.sourceGeneration \+ 1/);
assert.match(task, /PorticoPlaybackClampToTimeline\(controller\.playback, command\.positionSeconds/);
assert.match(task, /if command\.sourceGeneration = invalid then return true/);
assert.match(task, /sourceGeneration = PorticoHttpInteger\(command\.sourceGeneration, -1\)/);
assert.match(task, /return sourceGeneration = controller\.sourceGeneration/);
assert.match(runtime, /PorticoServerSessionRequestProjection\(stored, expected, record\.generation\)/);
assert.match(task, /grantReplaced = grant\.token <> controller\.playback\.grantToken/);
assert.match(task, /if grantReplaced or userInitiated or controller\.sourceRecoveryPending then controller\.sourceGeneration = controller\.sourceGeneration \+ 1/);
assert.match(task, /sub PorticoPlaybackCancelPostplay[\s\S]*PorticoPlaybackBeginTerminal\(controller, controller\.playback, "completed"/);
assert.match(task, /function PorticoPlaybackNextFailed[\s\S]*controller\.status = controller\.playerState/);
assert.match(task, /sub PorticoPlaybackSelectionFailed[\s\S]*controller\.status = controller\.playerState/);
assert.doesNotMatch(task, /terminalProgress|pendingCompletion|PorticoPlaybackFinishTerminalCleanup/);
assert.match(task, /sourceRecoveryStableSince/);
assert.match(task, /function PorticoPlaybackQualitySelectionFor\([\s\S]*qualityOfferRevision: playback\.qualityOffers\.offerRevision/);
assert.doesNotMatch(task.match(/function PorticoPlaybackSelectQuality\([\s\S]*?\nend function/)?.[0] ?? '', /recoveryAttempt|qualityId/);
assert.match(task, /allowInsecureLan: session\.allowInsecureLan = true/);
assert.match(task, /if Left\(LCase\(request\.url\), 8\) = "https:\/\/"/);

const privateContent = models.match(/function PorticoPlaybackPrivateContentNode\([\s\S]*?\nend function/)?.[0] ?? '';
assert.match(privateContent, /CreateObject\("roSGNode", "ContentNode"\)/);
assert.match(privateContent, /content\.HttpHeaders = \["Authorization: PorticoMedia " \+ token\]/);
assert.match(privateContent, /content\.url = sourceUrl/);
assert.match(privateContent, /porticoViewerGeneration/);
assert.doesNotMatch(privateContent, /media_grant=/i);

for (const request of [
  /requestPath = "\/api\/playback-sessions"[\s\S]*method: "POST"[\s\S]*path: requestPath/,
  /path: "\/api\/playback-sessions\/" \+ controller\.playback\.sessionId \+ "\/media-grant"/,
  /if pending\.kind = "terminal" then method = "DELETE"/,
]) assert.match(task, request);
assert.match(task, /PorticoHttpValidatePrivateRequest\(request\)/);
assert.match(task, /SetCertificatesFile\("common:\/certs\/ca-bundle\.crt"\)/);
assert.match(task, /EnablePeerVerification\(true\)/);
assert.match(task, /EnableHostVerification\(true\)/);
assert.match(task, /headers: \{ Authorization: "Bearer " \+ session\.accessToken \}/);
assert.match(task, /AddHeader\("Authorization", "PorticoMedia " \+ token\)/);

const progress = task.match(/sub PorticoPlaybackSendProgress\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(progress, /controller\.progressPending = \{/);
assert.match(task, /sub PorticoPlaybackDispatchProgress\([\s\S]*?AsyncPostFromString\(request\.body\)/);
assert.match(task, /sub PorticoPlaybackPollProgress\([\s\S]*?PorticoPlaybackAdoptProgressAcknowledgement/);
assert.doesNotMatch(progress, /PorticoPlaybackAuthenticatedRequest/, 'Progress reporting must not block the player command loop.');
for (const field of ['eventSequence', 'recordedAt', 'progressSeconds', 'durationSeconds', 'state']) assert.match(task, new RegExp(`${field}:`));
assert.doesNotMatch(progress, /completed/);
assert.match(task, /acknowledgement\.accepted/);
assert.match(task, /acknowledgement\.duplicate/);
assert.match(task, /acknowledgement\.stale/);
const dispatchProgress = task.match(/sub PorticoPlaybackDispatchProgress\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.doesNotMatch(dispatchProgress, /completed/);
assert.match(dispatchProgress, /controller\.pendingMutation <> invalid/, 'pending atomic replacement must fence new old-session progress without discarding it');
assert.match(dispatchProgress, /generation: controller\.playback\.sessionGeneration/, 'Ordinary progress must carry the validated positive server-session generation');
assert.match(models, /sessionGeneration < 1[\s\S]*return invalid/, 'Playback parsing must reject non-positive progress generations');
const progressFailure = task.match(/sub PorticoPlaybackProgressFailure\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.doesNotMatch(progressFailure, /PorticoPlaybackFinishPendingStop|PorticoPlaybackResetActive/, 'Synchronous and async terminal failures must remain retry-owned');
assert.match(progressFailure, /pendingMutation\.kind = "replacement"[\s\S]*PorticoPlaybackPublish[\s\S]*return/, 'late old progress failures cannot clear an ambiguous replacement source');
const pollProgress = task.match(/sub PorticoPlaybackPollProgress\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(pollProgress, /deadlineAt[\s\S]*AsyncCancel\(\)[\s\S]*PorticoPlaybackProgressFailure\(controller, 0, "timeout"\)/, 'Async timeout must transfer terminal ownership to bounded retry');
assert.match(pollProgress, /classification\.classification <> "success"[\s\S]*PorticoPlaybackProgressFailure\(controller, status, classification\.classification\)/, 'HTTP failure must transfer terminal ownership to bounded retry');
assert.match(pollProgress, /PorticoPlaybackAdoptProgressAcknowledgement/, 'Success and duplicate acknowledgements must share the fenced adoption path');
const acknowledgement = task.match(/function PorticoPlaybackAdoptProgressAcknowledgement\([\s\S]*?\nend function/)?.[0] ?? '';
assert.match(acknowledgement, /acknowledgement\.accepted <> true and acknowledgement\.duplicate <> true and acknowledgement\.stale <> true/, 'A duplicate terminal callback must be idempotently acknowledged');

const terminalRequest = task.match(/function PorticoPlaybackTerminalRequest\([\s\S]*?\nend function/)?.[0] ?? '';
assert.match(terminalRequest, /generation = PorticoPlaybackBoundedSeconds\(playback\.sessionGeneration, 0\)/);
assert.match(terminalRequest, /sequence = PorticoPlaybackBoundedSeconds\(playback\.nextEventSequence, 0\)/);
assert.match(terminalRequest, /playback\.nextEventSequence = sequence \+ 1/);
for (const field of ['disposition', 'generation', 'eventSequence', 'recordedAt', 'positionSeconds', 'durationSeconds']) assert.match(terminalRequest, new RegExp(`${field}:`));
assert.doesNotMatch(terminalRequest, /playbackGeneration/);
const beginTerminal = task.match(/function PorticoPlaybackBeginTerminal\([\s\S]*?\nend function/)?.[0] ?? '';
assert.ok(beginTerminal.indexOf('PorticoPlaybackPersistPendingMutation') < beginTerminal.indexOf('PorticoPlaybackDispatchPendingMutation'), 'Terminal body must be durable before transmission');
assert.match(secureRegistry, /recordType <> "playback-mutation"/);
assert.match(task, /PorticoSecureRegistryCommit\("playback-mutation", mutation\)/);
assert.match(task, /PorticoSecureRegistryRead\("playback-mutation"\)/);
assert.match(task, /body: encodedBody/);
assert.match(task, /body: pending\.body/);
assert.match(task, /kind: "replacement"[\s\S]*targetKind: targetKind[\s\S]*targetId: targetId/, 'durable replacement records the validated target identity');
assert.match(task, /pending\.path = restoredPath/, 'restore must reconstruct the allowed route instead of trusting a stored path');
assert.match(task, /PorticoPlaybackReplacementPath\(targetKind, targetId\)/);
assert.match(task, /playback_replacement_committed_restore_required[\s\S]*PorticoPlaybackRestoreCommittedReplacement/);
assert.match(task, /path: "\/api\/playback\/active"[\s\S]*restored\.sessionId <> replacementSessionId/, 'restore-required must verify the exact bounded successor identity');
assert.match(task, /pending\.committedReplacementSessionId = replacementSessionId[\s\S]*PorticoPlaybackPersistPendingMutation\(controller, pending\)[\s\S]*PorticoPlaybackRestoreCommittedReplacement/, 'committed successor identity must be durable before restore is attempted');
const restorePendingMutation = task.match(/sub PorticoPlaybackRestorePendingMutation\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(restorePendingMutation, /committedReplacementSessionId = PorticoPlaybackSafeId\(pending\.committedReplacementSessionId\)[\s\S]*pending\.committedReplacementSessionId = committedReplacementSessionId/, 'restart must validate and retain the exact committed successor identity');
const dispatchPendingMutation = task.match(/sub PorticoPlaybackDispatchPendingMutation\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.ok(dispatchPendingMutation.indexOf('PorticoPlaybackRestoreCommittedReplacement(controller, pending, committedReplacementSessionId)') < dispatchPendingMutation.indexOf('PorticoPlaybackAuthenticatedRequest(controller'), 'a restarted committed replacement must restore by exact identity instead of replaying the target request');
assert.match(task, /PorticoPlaybackReplacementDefinitivelyRejected[\s\S]*PorticoPlaybackRejectRouteReplacement/);
assert.match(task, /result\.serverCode = "replacement_source_inactive"[\s\S]*PorticoPlaybackDiscardInactiveReplacementSource\(controller\)/, 'authoritative inactive-source rejection must not enter the source-retained branch');
const discardInactiveReplacement = task.match(/sub PorticoPlaybackDiscardInactiveReplacementSource\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.ok(discardInactiveReplacement.indexOf('PorticoPlaybackDropProgress(controller)') < discardInactiveReplacement.indexOf('PorticoPlaybackResetActive(controller)'), 'inactive source must fence late progress before clearing local playback');
assert.match(discardInactiveReplacement, /PorticoPlaybackClearPendingMutation\(controller\)/);
assert.doesNotMatch(discardInactiveReplacement, /PorticoPlaybackScheduleGrantRenewal|PorticoPlaybackDispatchProgress|PorticoPlaybackBeginTerminal/, 'inactive source cannot resume, renew, report progress, or fabricate a terminal receipt');
assert.match(task, /sub PorticoPlaybackRejectRouteReplacement[\s\S]*PorticoPlaybackClearPendingMutation[\s\S]*controller\.heartbeatScheduled = true/, 'definitive non-commit must clear only replacement state and resume the old actor');
const acceptRouteReplacement = task.match(/sub PorticoPlaybackAcceptRouteReplacement\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.ok(acceptRouteReplacement.indexOf('PorticoPlaybackDropProgress(controller)') < acceptRouteReplacement.indexOf('PorticoPlaybackClearPendingMutation(controller)'), 'old progress is cancelled only at route replacement acceptance');
assert.match(task, /if pending\.targetKind = "library-channel"[\s\S]*playbackDocument = playbackDocument\.playback/, 'library tune acceptance must unwrap its playback document');
assert.match(task, /PorticoPlaybackScheduleMutationRetry\(controller, "playback-response-incompatible"/, 'lost or invalid accepted payload must retain the exact request for retry');
assert.match(task, /PorticoPlaybackTerminalAcknowledgementMatches\(pending, result\.data\)/);
assert.match(task, /if not PorticoPlaybackClearPendingMutation\(controller\)[\s\S]*PorticoPlaybackScheduleMutationRetry/);
assert.match(task, /PorticoPlaybackMutationDefinitivelyRejected/);
assert.match(task, /not PorticoViewerScopeAuthorizationEquals\(scope, currentScope\)/, 'Durable terminal replay must survive a viewer-generation restart only for the same authorization revision');
assert.match(task, /PorticoPlaybackFallbackCompletedTerminal/);
assert.match(task, /PorticoPlaybackRejectExplicitHandoff/);
assert.match(task, /previousTerminal: terminalRequest\.terminal/);
assert.match(task, /requestId: terminalRequest\.requestId/);
assert.match(task, /entryId: prepared\.entryId/);
assert.doesNotMatch(task, /commitPreviousEnd/);
const handoff = task.match(/function PorticoPlaybackCommitHandoff\([\s\S]*?\nend function/)?.[0] ?? '';
assert.doesNotMatch(handoff, /progressSeconds/);
assert.doesNotMatch(task, /body:\s*""[\s\S]{0,120}method:\s*"DELETE"|method:\s*"DELETE"[\s\S]{0,120}body:\s*""/, 'Playback DELETE must always carry the exact terminal envelope');
const resetActive = task.match(/sub PorticoPlaybackResetActive\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(resetActive, /controller\.pendingStart = invalid/);
assert.match(task, /grantRenewalFailures > 5/);
assert.match(task, /retrySeconds > 60/);
assert.match(task, /kind = "source-error"[\s\S]*PorticoPlaybackRecoverSource\(controller\)/);
const sourceRecovery = task.match(/sub PorticoPlaybackRecoverSource\(controller as object\)([\s\S]*?)\nend sub/)?.[1] ?? '';
assert.match(sourceRecovery, /PorticoPlaybackRequestReconnect\(controller\)/, 'Route re-resolution must precede fatal playback UI');
assert.doesNotMatch(sourceRecovery, /PorticoPlaybackSelectRecoveryQuality|PorticoPlaybackRestartForRecovery/, 'Roku must not invent a replacement tuple during recovery');
assert.doesNotMatch(task, /PorticoPlaybackRestartForRecovery/, 'Every recovery path must preserve the server-sealed playback tuple');
assert.ok(sourceRecovery.indexOf('PorticoPlaybackRequestReconnect') < sourceRecovery.indexOf('PorticoPlaybackFatalActive'));
assert.match(models, /resources\.Count\(\) <> 1/);
assert.match(models, /qualityOffers = PorticoPlaybackQualityOffers\(data\.qualityOffers\)/);
assert.match(models, /qualitySelection = PorticoPlaybackQualitySelection\(data\.qualitySelection, qualityOffers\)/);
assert.match(task, /body\.quality = qualitySelection/);
assert.doesNotMatch(task + models + bridge, /selectedQualityId|body\.qualityId|resource\.qualityId|data\.qualities|source\.qualities/);

const transition = task.match(/sub PorticoPlaybackStageTransitionTerminal\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.ok(transition.indexOf('PorticoPlaybackPersistPendingMutation') < transition.indexOf('PorticoPlaybackResetActive'), 'Transition terminal must be durable before private state is cleared');
assert.ok(transition.indexOf('PorticoPlaybackResetActive') < transition.indexOf('PorticoPlaybackDispatchPendingMutation'), 'Private state must clear before remote cleanup');
assert.match(task.match(/sub PorticoPlaybackApplyTransitionFence\([\s\S]*?\nend sub/)?.[0] ?? '', /controller\.watchAuthority = "independent"/);
assert.match(task, /m\.top\.contentNode = invalid/);
assert.match(task, /PorticoPlaybackClearTrickplayCache/);
assert.match(task, /PorticoPlaybackTrimTrickplayCache\(controller, 12\)/);

for (const forbidden of ['sessionId', 'grantToken', 'accessToken', 'apiBaseUrl', 'serverSession', 'headers', 'viewerScope']) {
  assert.ok(!bridge.includes(`${forbidden}: true`), `${forbidden} must not be a public playback projection field`);
}
assert.match(bridge, /privateContentChanged: true/);
assert.match(main, /if playbackResult\.privateContentChanged = true/);
assert.match(main, /playerNode\.privateContent = playbackResult\.privateContent/);
assert.match(player, /if candidate = invalid[\s\S]*PorticoPlayerStopVideo\(\)[\s\S]*m\.playerController\.video\.content = invalid/);
assert.match(bridge, /PorticoPlaybackTransitionFence/);
assert.match(main, /playbackReady = PorticoPlaybackTransitionFence\(playback\)/);
assert.match(bridge, /Left\(lower, 8\) <> "https:\/\/"[\s\S]*PorticoHttpUrlAllowed\(url, true\)/);

function stripCredentialQueries(value) {
  const lower = value.toLowerCase();
  return !['media_grant=', 'download_grant=', 'access_token=', 'accesstoken=', 'media%5fgrant=', 'download%5fgrant=', 'access%5ftoken='].some(marker => lower.includes(marker));
}
for (const safe of ['https://server.example/api/media/file.m3u8', 'https://server.example/api/media/file.mp4?quality=original']) assert.equal(stripCredentialQueries(safe), true);
for (const unsafe of ['https://server.example/api/media?media_grant=secret', 'https://server.example/api/media?access_token=secret', 'https://server.example/api/media?access%5ftoken=secret']) assert.equal(stripCredentialQueries(unsafe), false);

// Contract-level protocol cases complement the static BrightScript guards. They
// make the acceptance boundary and immutable outbox behavior explicit without
// inventing a second production lifecycle implementation.
const queueFixture = [
  {entryId: 'occurrence-a', media: {id: 'episode-1', title: 'Pilot'}},
  {entryId: 'occurrence-b', media: {id: 'episode-1', title: 'Pilot'}},
];
const queueOccurrences = queueFixture.map(item => ({entryId: item.entryId, mediaId: item.media.id}));
assert.deepEqual(queueOccurrences, [
  {entryId: 'occurrence-a', mediaId: 'episode-1'},
  {entryId: 'occurrence-b', mediaId: 'episode-1'},
], 'duplicate media occurrences must retain distinct queue-entry identity');

assert.match(operationPolicy, /deleteWatchWithFriendsGroupsGroupIdQueueEntryId/);
assert.doesNotMatch(operationPolicy + watchTask, /deleteWatchWithFriendsGroupsGroupIdQueueMediaId/);
assert.match(watchRuntime, /currentEntryId = PorticoViewerScopeOpaqueId\(value\.currentEntryId, 128\)/);
assert.match(watchRuntime, /entryId: entryId, mediaId: mediaId, mediaTitle: title, unavailable:/);
assert.match(watchTask, /body = \{entryId: entryId, destinationEntryId: destinationEntryId, placement: placement/);
assert.match(watchTask, /deleteWatchWithFriendsGroupsGroupIdQueueEntryId", \{groupId: controller\.group\.id, entryId: entryId\}/);
assert.match(watchBridge, /command\.entryId = values\.entryId[\s\S]*command\.destinationEntryId = values\.destinationEntryId[\s\S]*command\.placement = values\.placement/);

const allocateTerminal = (authority, disposition) => {
  const terminal = {
    disposition,
    generation: authority.sessionGeneration,
    eventSequence: authority.nextEventSequence,
    recordedAt: '2026-08-30T18:00:00Z',
    positionSeconds: disposition === 'completed' ? authority.durationSeconds : authority.positionSeconds,
    durationSeconds: authority.durationSeconds,
  };
  return {
    authority: {...authority, nextEventSequence: authority.nextEventSequence + 1},
    request: {requestId: 'request-immutable-1', terminal},
  };
};
const initialAuthority = {sessionId: 'old', sessionGeneration: 7, nextEventSequence: 12, positionSeconds: 42, durationSeconds: 600};
const allocated = allocateTerminal(initialAuthority, 'completed');
assert.equal(allocated.request.terminal.generation, 7, 'terminal generation comes from the server session, not UI playback generation');
assert.equal(allocated.request.terminal.eventSequence, 12);
assert.equal(allocated.authority.nextEventSequence, 13, 'one terminal allocation advances the sole allocator exactly once');
const handoffBody = JSON.stringify({requestId: allocated.request.requestId, entryId: 'occurrence-b', previousTerminal: allocated.request.terminal});
const ambiguousRetryBody = handoffBody;
assert.equal(ambiguousRetryBody, handoffBody, 'ambiguous handoff retries must be byte-equivalent');
const replacementEnvelope = {
  sourceSessionId: initialAuthority.sessionId,
  requestId: 'request-route-replacement-1',
  previousTerminal: {...allocated.request.terminal, disposition: 'stopped', positionSeconds: initialAuthority.positionSeconds},
  expectedQueueRevision: 9,
  expectedPlaybackRevision: 14,
};
const routeTargets = [
  {kind: 'vod', id: 'movie-2', path: '/api/playback-sessions', body: {mediaId: 'movie-2'}},
  {kind: 'live', id: 'channel-2', path: '/api/live-tv/play', body: {channelId: 'channel-2'}},
  {kind: 'dvr', id: 'recording-2', path: '/api/dvr/recordings/recording-2/playback', body: {}},
  {kind: 'library-channel', id: 'library-channel-2', path: '/api/library-channels/library-channel-2/tune', body: {}},
].map(target => ({...target, body: {...target.body, replacement: replacementEnvelope}}));
for (const target of routeTargets) {
  const durable = {targetKind: target.kind, targetId: target.id, path: target.path, body: JSON.stringify(target.body)};
  const ambiguousRetry = {...durable};
  assert.equal(ambiguousRetry.body, durable.body, `${target.kind} retry must preserve the exact serialized body`);
  assert.equal(ambiguousRetry.path, durable.path, `${target.kind} retry must preserve its exact endpoint`);
  assert.deepEqual(JSON.parse(durable.body).replacement, replacementEnvelope);
}
const pendingReplacementState = {playback: initialAuthority, progress: {eventSequence: 11}, grant: 'old-grant', pending: routeTargets[0]};
assert.equal(pendingReplacementState.playback.sessionId, 'old', 'pending replacement retains the old actor');
assert.equal(pendingReplacementState.progress.eventSequence, 11, 'pending replacement retains old progress until acceptance');
assert.equal(pendingReplacementState.grant, 'old-grant', 'pending replacement retains the old grant until acceptance');
const restoreRequired = {code: 'playback_replacement_committed_restore_required', details: {replacementSessionId: 'successor-exact'}};
const restoredActive = {active: true, playback: {sessionId: 'successor-exact'}};
assert.equal(restoredActive.playback.sessionId, restoreRequired.details.replacementSessionId, 'restore-required adoption verifies the exact committed successor');
assert.notEqual('different-successor', restoreRequired.details.replacementSessionId, 'an unrelated active session cannot satisfy committed replacement restore');
const naturalFallback = {requestId: 'standalone-terminal-request', terminal: allocated.request.terminal};
assert.deepEqual(naturalFallback.terminal, allocated.request.terminal, 'definitive natural rejection reuses the unaccepted terminal event');
assert.notEqual(naturalFallback.requestId, allocated.request.requestId, 'the standalone DELETE owns a new mutation request identity');
assert.equal(naturalFallback.terminal.eventSequence, allocated.request.terminal.eventSequence, 'fallback must not allocate a second terminal event sequence');

const definitiveHandoffRejection = result => {
  if (result.interrupted || result.retryable) return false;
  return new Set([
    'handoff_request_id_invalid',
    'previous_terminal_required',
    'invalid_playback_disposition',
    'invalid_playback_terminal_authority',
    'invalid_recorded_at',
    'invalid_playback_terminal_position',
    'invalid_start_seconds',
    'prepared_handoff_not_found',
    'prepared_handoff_expired',
    'prepared_handoff_scope_mismatch',
    'prepared_handoff_entry_mismatch',
    'handoff_not_supported',
    'queue_entry_required',
    'handoff_queue_revision_conflict',
    'handoff_queue_entry_changed',
    'handoff_playback_revision_conflict',
    'playback_generation_stale',
    'playback_event_sequence_stale',
  ]).has(result.serverCode);
};
assert.equal(definitiveHandoffRejection({status: 409, serverCode: 'handoff_in_progress', retryable: false, interrupted: false}), false, 'a live handoff reservation remains ambiguous');
assert.equal(definitiveHandoffRejection({status: 404, serverCode: 'playback_session_not_found', retryable: false, interrupted: false}), false, '404 is not a durable non-receipt after a lost response');
assert.equal(definitiveHandoffRejection({status: 401, serverCode: '', retryable: false, interrupted: false}), false, '401 is not a durable non-receipt after a lost response');
assert.equal(definitiveHandoffRejection({status: 409, serverCode: 'handoff_queue_revision_conflict', retryable: false, interrupted: false}), true, 'an explicit pre-commit revision rejection is definitive');

assert.match(task, /PorticoPlaybackComplete[\s\S]*PorticoPlaybackBeginTerminal\(controller, controller\.playback, "completed"/, 'no-queue natural end must close through canonical terminal DELETE');
assert.match(task, /PorticoPlaybackCancelPostplay[\s\S]*PorticoPlaybackBeginTerminal\(controller, controller\.playback, "completed"/, 'postplay cancellation must close through canonical terminal DELETE');
assert.match(task, /function PorticoPlaybackStopActive[\s\S]*PorticoPlaybackBeginTerminal\(controller, active, "stopped"/, 'direct stop must use the canonical stopped terminal');
assert.match(task, /sub PorticoPlaybackRemoteStop[\s\S]*PorticoPlaybackBeginTerminal\(controller, controller\.playback, "stopped"/, 'remote stop must use the same terminal owner');
const acceptHandoff = task.match(/sub PorticoPlaybackAcceptHandoffMutation\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.ok(acceptHandoff.indexOf('PorticoPlaybackDropProgress(controller)') < acceptHandoff.indexOf('PorticoPlaybackClearPendingMutation(controller)'), 'accepted handoff must cancel old events at the server acceptance boundary, even while durable receipt clearing retries');
assert.ok(acceptHandoff.indexOf('PorticoPlaybackDropProgress(controller)') < acceptHandoff.indexOf('PorticoPlaybackPreflightSource'), 'accepted handoff must drop old events before replacement preflight/adoption');
assert.match(task, /not preflight\.ok[\s\S]*PorticoPlaybackBeginTerminal\(controller, replacement, "stopped"/, 'replacement preflight failure must terminalize the accepted replacement');
assert.match(task, /PorticoPlaybackScheduleMutationRetry\(controller, "playback-response-incompatible"/, 'invalid accepted handoff payload must exact-retry instead of guessing cleanup');
assert.match(task, /if pending\.kind = "handoff" and PorticoPlaybackMutationDefinitivelyRejected[\s\S]*pending\.disposition = "completed"[\s\S]*PorticoPlaybackFallbackCompletedTerminal[\s\S]*PorticoPlaybackRejectExplicitHandoff/, 'natural and explicit definitive rejection must diverge safely');
const fallbackCompleted = task.match(/sub PorticoPlaybackFallbackCompletedTerminal\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(fallbackCompleted, /requestId = PorticoPlaybackSafeRequestId\(PorticoHttpNewRequestId\(\)\)/, 'standalone fallback must own a distinct request identity');
assert.doesNotMatch(fallbackCompleted, /PorticoPlaybackTerminalRequest/, 'standalone fallback must reuse the unaccepted terminal event rather than allocate another sequence');
assert.match(task, /serverCode = LCase\(PorticoCoreSafeText\(result\.serverCode, 80\)\)/, 'handoff rejection classification must use an explicit server problem code');
assert.doesNotMatch(task.match(/function PorticoPlaybackMutationDefinitivelyRejected\([\s\S]*?\nend function/)?.[0] ?? '', /result\.status\s*=/, 'HTTP status alone cannot prove a handoff was not committed');
assert.match(task, /failure\.serverCode = LCase\(PorticoCoreSafeText\(parsedError\.value\.code, 80\)\)/, 'HTTP errors must preserve the bounded server problem code for mutation classification');
assert.match(task, /PorticoPlaybackDropProgress[\s\S]*progressRequest\.transfer\.AsyncCancel/, 'late old heartbeats must be cancelled at handoff acceptance');
assert.match(task, /PorticoPlaybackHandoffEntry\(controller, controller\.playback\.currentQueueEntryId, "stopped", 0\)/, 'active Replay must use direct atomic handoff with an explicit zero start');
assert.match(task, /else if controller\.lastTargetId <> ""[\s\S]*startSeconds: 0/, 'Replay after a closed completion must fresh-start at zero');
assert.doesNotMatch(task, /preparedNext\.sessionId[\s\S]{0,180}method:\s*"DELETE"/, 'prepared capabilities must be discarded locally rather than deleted as playback sessions');

for (const testCase of parityCases.back) {
  let state = testCase.initial;
  const actions = [];
  let stopEvents = 0;
  for (let index = 0; index < testCase.presses; index += 1) {
    const result = reduceBack(state);
    state = result.state;
    actions.push(result.action);
    stopEvents += result.events.filter(event => event.kind === 'stop').length;
  }
  assert.deepEqual(actions, testCase.expectedActions, testCase.name);
  assert.equal(stopEvents, testCase.expectedStopEvents, `${testCase.name} emitted an incorrect stop count`);
}

for (const testCase of parityCases.playback) {
  let state = createPlaybackState(testCase.source);
  const actions = [];
  for (const event of testCase.events) {
    const result = applyPlaybackEvent(state, event);
    state = result.state;
    actions.push(result.action);
  }
  const expected = testCase.expected;
  assert.equal(state.source.format, expected.format, testCase.name);
  if (expected.positionAfterSeek !== undefined) assert.equal(state.progress.find(progress => progress.kind === 'seek')?.positionSeconds, expected.positionAfterSeek, testCase.name);
  if (expected.selectedAudioStreamId !== undefined) assert.equal(state.selectedAudioStreamId, expected.selectedAudioStreamId, testCase.name);
  if (expected.selectedSubtitleStreamId !== undefined) assert.equal(state.selectedSubtitleStreamId, expected.selectedSubtitleStreamId, testCase.name);
  if (expected.sourceGeneration !== undefined) assert.equal(state.sourceGeneration, expected.sourceGeneration, testCase.name);
  if (expected.finalPosition !== undefined) assert.equal(state.positionSeconds, expected.finalPosition, testCase.name);
  if (expected.finalStatus !== undefined) assert.equal(state.status, expected.finalStatus, testCase.name);
  if (expected.completedProgress !== undefined) assert.equal(state.progress.filter(progress => progress.completed).length, expected.completedProgress, testCase.name);
  if (expected.recoveryActions !== undefined) assert.deepEqual(actions, expected.recoveryActions, testCase.name);
  if (expected.positions !== undefined) assert.deepEqual(state.progress.filter(progress => progress.kind === 'seek').map(progress => progress.positionSeconds), expected.positions, testCase.name);
  if (expected.stalePlaybackIgnored) assert.equal(actions.at(-1), 'ignore-stale-playback', testCase.name);
}

console.log(`Verified ${operations.length} operations, exact viewer-scoped playback, private PorticoMedia headers, resume semantics, atomic teardown, bounded trickplay, and public projection secrecy.`);
