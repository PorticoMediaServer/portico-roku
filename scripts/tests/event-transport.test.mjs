import assert from 'node:assert/strict';
import {readFileSync, readdirSync, statSync} from 'node:fs';
import {extname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const filesUnder = directory => readdirSync(directory).flatMap(name => {
  const path = join(directory, name);
  return statSync(path).isDirectory() ? filesUnder(path) : [path];
});

const operations = JSON.parse(read('channel/data/generated/operations.v1.json')).operations;
const productContract = JSON.parse(read('channel/data/generated/product-contract.v1.json')).contract;
const transport = read('channel/source/core/PorticoEventTransport.brs');
const productContractValidator = read('channel/source/core/PorticoProductContract.brs');
const runtimeFiles = filesUnder(resolve(root, 'channel'))
  .filter(path => ['.brs', '.xml'].includes(extname(path)))
  .filter(path => !path.includes(`${join('channel', 'development')}`));
const runtime = runtimeFiles.map(path => readFileSync(path, 'utf8')).join('\n');

const expectedOperations = [
  ['pollApplicationEvents', '/events/poll', 'authenticated', 'ApplicationEventLongPollEnvelope'],
  ['pollViewerNotificationInvalidations', '/notifications/events/poll', 'authenticated', 'NotificationInvalidationLongPollEnvelope'],
  ['pollPlaybackSessionCommands', '/playback-sessions/{sessionId}/command/events/poll', 'play-media', 'PlaybackCommandLongPollEnvelope'],
  ['pollWatchWithFriendsGroupEvents', '/watch-with-friends/groups/{groupId}/events/poll', 'play-media', 'WatchWithFriendsLongPollEnvelope'],
];

const pollOperations = operations.filter(operation => operation.service === 'server' && operation.path.endsWith('/poll'));
assert.equal(pollOperations.length, expectedOperations.length, 'Roku contract must expose exactly the four approved v1 long-poll operations');
for (const [operationId, path, permission, responseSchema] of expectedOperations) {
  const operation = pollOperations.find(candidate => candidate.operationId === operationId);
  assert.ok(operation, `${operationId} is missing from the generated Roku Operation Contract`);
  assert.equal(operation.method, 'GET');
  assert.equal(operation.path, path);
  assert.equal(operation.audience, 'viewer');
  assert.equal(operation.auth, 'session');
  assert.equal(operation.permission, permission);
  assert.equal(operation.ratePolicy, 'long-poll');
  assert.equal(operation.mutation, false);
  assert.ok(operation.surfaces.includes('television'));
  assert.deepEqual(operation.responseSchemas, [responseSchema]);
  assert.match(runtime, new RegExp(`\\b${operationId}\\b`), `${operationId} has no Roku runtime consumer`);
}

// The old Server-relayed receiver command stream was superseded by key-bound,
// direct receiver authorization. Roku must stay fail-closed until it implements
// that protocol; retaining a generated legacy operation would falsely advertise
// a route the Server no longer publishes.
for (const removed of [
  'postPlaybackReceivers',
  'patchPlaybackReceiversReceiverId',
  'postPlaybackReceiversReceiverIdCommand',
  'pollPlaybackReceiverEvents',
]) {
  assert.equal(operations.some(operation => operation.operationId === removed), false, `${removed} must not be advertised`);
}

assert.deepEqual(productContract.eventTransports, ['sse', 'long-poll']);
assert.deepEqual(productContract.longPoll, {
  defaultWaitSeconds: 20,
  maximumConcurrentStreams: 4,
  maximumWaitSeconds: 25,
});
assert.deepEqual(productContract.semanticIdentity, {
  digest: 'b4e5d9085d5bff25a281c7ee5bb1a8a547dda9e52e66b38bdada2745a74cbba9',
  digestAlgorithm: 'sha256',
  id: 'portico.product-contract',
  revision: 'v2',
});
assert.deepEqual(productContract.applicationEvents.eventTypes, ['data.changed', 'library.scan.completed']);
assert.deepEqual(productContract.applicationEvents.authoritativeResetErrorCodes, ['invalid_poll_cursor']);
assert.equal(productContract.applicationEvents.longPollResetField, 'resetRequired');
assert.match(productContractValidator, /eventTransports: true/);
assert.match(productContractValidator, /longPoll: true/);
assert.match(productContractValidator, /semanticIdentity: true/);
assert.match(productContractValidator, /applicationEvents: true/);
assert.match(productContractValidator, /PorticoProductContractSemanticIdentityValid/);
assert.match(productContractValidator, /PorticoProductContractSystemSupports/);
assert.match(productContractValidator, /PorticoProductContractValidateApplicationEvents/);
assert.match(productContractValidator, /productContractRevision: contract\.semanticIdentity\.digest/);
assert.match(productContractValidator, /PorticoProductContractValidateEventTransports/);
assert.match(productContractValidator, /PorticoProductContractValidateLongPoll/);
assert.match(productContractValidator, /PorticoProductContractStringArrayValid\(transports, 2, 9, true, allowed, true\)/);
assert.match(productContractValidator, /longPoll\.Count\(\) <> 3/);
assert.match(productContractValidator, /PorticoProductContractIntegerInRange\(longPoll\.defaultWaitSeconds, 20, 20\)/);
assert.match(productContractValidator, /PorticoProductContractIntegerInRange\(longPoll\.maximumWaitSeconds, 25, 25\)/);
assert.match(productContractValidator, /PorticoProductContractIntegerInRange\(longPoll\.maximumConcurrentStreams, 4, 4\)/);
assert.match(transport, /if maximumStreams > 4 then maximumStreams = 4/);

// Capability presence is necessary but never sufficient: callers must also
// prove that the exact generated operation is allowed before selecting it.
assert.match(transport, /if capabilities\.longPollAdvertised then return "long-poll"/);
assert.match(transport, /if transport = "long-poll" then result\.longPollAdvertised = true/);
assert.doesNotMatch(transport, /if transport = "sse" then result\.longPollAdvertised = true/);
assert.match(runtime, /PorticoOperationContractRecordAllowed\(operation\)/);
for (const [, path] of expectedOperations) {
  const concretePrefix = path.replace('{sessionId}', '" + encoded + "').replace('{receiverId}', '" + encoded + "').replace('{groupId}', '" + encoded + "');
  assert.ok(runtime.includes(`operation.path = "${path}"`) || runtime.includes(`"${path}"`) || runtime.includes(`"${concretePrefix}"`), `${path} is not operation-gated by the Roku runtime`);
}

// One request at a time, exact viewer binding, and stale-response rejection.
assert.match(transport, /if state\.outstanding then return \{ok: false, code: "poll_already_active"\}/);
assert.match(transport, /state\.outstandingSequence = state\.requestSequence/);
assert.match(transport, /PorticoViewerScopePositiveInteger\(request\.requestSequence\) <> state\.outstandingSequence/);
assert.match(transport, /PorticoViewerScopePositiveInteger\(request\.viewerGeneration\) <> state\.viewerScope\.viewerGeneration/);
assert.match(transport, /not PorticoViewerScopeEquals\(request\.viewerScope, state\.viewerScope\)/);
assert.match(transport, /not PorticoViewerScopeEquals\(currentScopeValue, state\.viewerScope\)/);

// Exact v1 request and response envelope. Cursor is opaque, bounded, escaped,
// never persisted, and zero-wait draining occurs only after hasMore.
assert.match(transport, /requestKind = "long-poll"[\s\S]*waitSeconds = state\.defaultWaitSeconds[\s\S]*if state\.drainPending then waitSeconds = 0[\s\S]*cursor = state\.cursor/);
assert.match(runtime, /cursor[\s\S]*waitSeconds/);
assert.match(runtime, /Escape\(.*cursor|PorticoEventTransportEscape\(.*cursor/);
assert.match(transport, /PorticoEventTransportToken\(value\.version, 8\) <> "v1"/);
assert.match(transport, /value\.Count\(\) <> 6/);
assert.match(transport, /cursor = PorticoEventTransportOpaqueCursor\(value\.cursor\)/);
assert.match(transport, /serverTime = PorticoEventTransportServerTime\(value\.serverTime\)/);
assert.match(transport, /FromISO8601String\(serverTime\)/);
assert.match(transport, /Type\(value\.resetRequired\)/);
assert.match(transport, /Type\(value\.hasMore\)/);
assert.match(transport, /value\.events\.Count\(\) > 100/);
assert.match(transport, /if value\.resetRequired and \(value\.events\.Count\(\) > 0 or value\.hasMore\) then return invalid/);
assert.match(transport, /if Len\(cursor\) < 1 or Len\(cursor\) > 4096 then return ""/);
assert.doesNotMatch(runtime, /PorticoSecureRegistry(?:Commit|Write)\([^\n]*cursor/i, 'Long-poll cursors must remain in memory');

// Reset means authoritative refetch, never event application. hasMore drains
// immediately; ordinary empty responses reissue without failure backoff.
assert.match(transport, /if envelope\.resetRequired[\s\S]*directive: "authoritative-refetch"[\s\S]*events: \[\]/);
assert.match(transport, /if envelope\.hasMore[\s\S]*directive: "drain"/);
assert.match(transport, /maximumConsecutiveDrains: 8/);
assert.match(transport, /state\.consecutiveDrainCount >= state\.maximumConsecutiveDrains[\s\S]*state\.nextAttemptAt = nowSeconds \+ 1/);
assert.match(transport, /cursorRepeated[\s\S]*"cursor_not_advanced"/);
assert.match(transport, /state\.nextAttemptAt = nowSeconds/);
assert.match(transport, /PorticoEventTransportAcknowledgeReset/);
assert.match(runtime, /authoritative-refetch/);

// Auth/scope failures terminate rather than downgrade or retry forever.
assert.match(transport, /terminal = failureCode = "authentication_required" or failureCode = "forbidden" or failureCode = "not_found" or failureCode = "authorization_revision_changed"/);
assert.match(transport, /if terminal[\s\S]*state\.active = false[\s\S]*state\.cursor = ""/);
assert.match(transport, /PorticoEventTransportRecordFailure\(state, failureCode, retryAfterSeconds, nowSeconds\)/);
assert.match(transport, /if delay > 300 then delay = 300/);
assert.match(transport, /jitterSeed: PorticoEventTransportJitterSeed\(scope\)/);
assert.match(transport, /state\.jitterSeed \+ state\.requestSequence \+ state\.failureCount/);
assert.match(runtime, /retryAfterSeconds/);
assert.match(runtime, /PorticoEventTransportFailRequest\(controller\.notificationTransport, request, controller\.viewerScope, PorticoEngagementTransportFailureCode\(response\), response\.retryAfterSeconds,/);

// Capability rollback/fallback is explicit. It clears continuity, requires a
// refetch when entering long-poll, and never treats an auth failure as a mode change.
assert.match(transport, /return "bounded-refresh"/);
assert.match(transport, /state\.mode = nextMode[\s\S]*state\.outstanding = false[\s\S]*state\.cursor = ""/);
assert.match(transport, /state\.resetPending = nextMode = "long-poll"/);
assert.match(transport, /directive: "authoritative-refetch"/);

// Cancellation must synchronously fence publication and clear all continuation
// state. Consumers must call it for replacement/resource exit and server loss.
assert.match(transport, /sub PorticoEventTransportCancel[\s\S]*state\.active = false[\s\S]*state\.outstanding = false[\s\S]*state\.cursor = ""/);
for (const reason of ['replaced', 'server-unavailable']) assert.ok(runtime.includes(`"${reason}"`));
assert.match(runtime, /PorticoEventTransportCancel\(/);
assert.match(runtime, /AsyncCancel\(\)/);
const watchRuntime = read('channel/components/PorticoWatchWithFriendsTask.brs');
assert.match(watchRuntime, /PorticoWatchWithFriendsBeginLongRequest/);
assert.match(watchRuntime, /PorticoWatchWithFriendsPollLongRequest/);
assert.match(watchRuntime, /controller\.longPollRequest <> invalid[\s\S]*PorticoWatchWithFriendsPollLongRequest/);
assert.doesNotMatch(watchRuntime.match(/sub PorticoWatchWithFriendsTick[\s\S]*?\nend sub/)?.[0] ?? '', /PorticoWatchWithFriendsRequest\(controller, "pollWatchWithFriendsGroupEvents"/);

// Every long-poll HTTP path stays private, TLS-verified, response-bounded, and
// must allow the advertised 25-second wait with bounded transport overhead.
assert.match(runtime, /PorticoHttpValidatePrivateRequest\(request\)/);
assert.match(runtime, /SetCertificatesFile\("common:\/certs\/ca-bundle\.crt"\)/);
assert.match(runtime, /EnablePeerVerification\(true\)/);
assert.match(runtime, /EnableHostVerification\(true\)/);
assert.match(runtime, /PorticoHttpLimits\(\)\.maximumResponseBytes/);
assert.match(transport, /budget = \{nodes: 2048, text: 524288\}/);
assert.match(transport, /PorticoEventTransportValueWithinBudget/);
assert.match(runtime, /timeoutMs:\s*(?:30000|35000)|timeoutMs\s*=\s*(?:30000|35000)|,\s*35000\)/);

// The notification stream carries invalidations only. Roku must refetch the
// authorized notification list and never project private notification payloads.
assert.match(runtime, /pollViewerNotificationInvalidations/);
assert.match(runtime, /notifications\.invalidated/);
assert.match(runtime, /authoritative-refetch/);

console.log(`Verified ${expectedOperations.length} generated long-poll operations, capability/operation gating, exact envelopes, cursor/reset/drain behavior, viewer fencing, teardown, fallback, and private bounded TLS transport.`);
