import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoPlaybackEventsTask.brs');
const models = read('channel/source/lib/PorticoPlaybackEventsModels.brs');
const bridge = read('channel/source/lib/PorticoPlaybackEvents.brs');
const main = read('channel/source/Main.brs');

const section = (source, start, end) => {
  const from = source.indexOf(start);
  assert.notEqual(from, -1, `missing ${start}`);
  const to = source.indexOf(end, from + start.length);
  return source.slice(from, to === -1 ? source.length : to);
};

// Registration must establish the resource/dedupe scope before applying a
// command returned in the registration snapshot.
const registration = section(task, 'sub PorticoPlaybackEventsRegisterReceiver', 'function PorticoPlaybackEventsHeartbeatReceiver');
assert.ok(registration.indexOf('PorticoPlaybackEventsCreateTransport') < registration.indexOf('PorticoPlaybackEventsProcessPrivateCommand'), 'receiver command must not be remembered before CreateTransport clears dedupe state');
assert.match(registration, /terminal = not response\.retryable and response\.status <> 401 and response\.status <> 403/);
assert.match(registration, /if terminal then controller\.terminalBlocked = true/, 'stable registration failure must not retry every tick');

// Directive publication is at-least-once until a generation-scoped Main ack.
const processCommand = section(task, 'function PorticoPlaybackEventsProcessPrivateCommand', 'sub PorticoPlaybackEventsRecordTransportFailure');
assert.match(processCommand, /directiveQueue\.Push\(entry\)/, 'commands must remain queued until Main acknowledges delivery');
assert.match(task, /acknowledge-directive/);
assert.match(task, /PorticoPlaybackEventsRememberCommand/);
assert.match(task, /pendingDirective/);
assert.match(bridge, /PorticoPlaybackEventsHandleNodeEvent/);
assert.match(bridge, /PorticoViewerRuntimeAcceptProjection/);
assert.match(bridge, /PorticoPlaybackEventsAcknowledgeDirective/);

// Reset refetch retries are bounded and terminal lifecycle failures terminate.
assert.match(task, /resetRetryAt/);
assert.match(task, /if .*resetPending[\s\S]*resetRetryAt/);
const reset = section(task, 'sub PorticoPlaybackEventsAuthoritativeReset', 'function PorticoPlaybackEventsValidateEvents');
assert.match(reset, /retryAfterSeconds|RetryDelay/);
assert.match(reset, /authentication_required|forbidden|not_found|terminal/);
assert.match(reset, /PorticoPlaybackEventsProcessPrivateCommand\(controller, command, true\)/, 'authoritative commands must be tagged for reset completion');
assert.match(task, /if entry\.acknowledgeReset and controller\.transport <> invalid[\s\S]*PorticoEventTransportAcknowledgeReset/, 'reset may complete only after Main acknowledges the queued directive');

// Scheduled receiver heartbeat failures may not spin at 100ms, and response
// publication must cross the EventTransport generation fence first.
const heartbeat = section(task, 'function PorticoPlaybackEventsHeartbeatReceiver', 'sub PorticoPlaybackEventsCreateTransport');
assert.match(heartbeat, /nextHeartbeatAt/);
assert.ok(heartbeat.indexOf('PorticoEventTransportAcceptResponse') < heartbeat.indexOf('PorticoPlaybackEventsProcessPrivateCommand'), 'heartbeat command must be fenced before publication');
assert.match(heartbeat, /resetFlow = request = invalid[\s\S]*PorticoPlaybackEventsResolveResetCommand/, 'receiver reset must remain pending until its authoritative command is acknowledged');

// Stable protocol failures quarantine only long-poll and preserve bounded
// authoritative refresh; auth/scope failures remain lifecycle terminal.
assert.match(task, /longPollQuarantined|QuarantineLongPoll/);
assert.match(task, /capabilities\.longPollAdvertised = false/);
assert.match(task, /not response\.retryable/);

// Same-online capability rollback must be observable without recreating the
// viewer, and the controller must hard-stop a Task when no accepting scope can
// carry a cancellation command.
assert.match(bridge, /stateSignature/);
assert.match(bridge, /PorticoPlaybackEventsCapabilitySignature\(capabilities\)/);
assert.match(task, /capabilit(?:y|ies).*changed|changedCapabilities|capabilityChanged/i);
assert.match(bridge, /task\.control = "STOP"/);

// Main owns the private PlaybackTask session handoff and acknowledges an
// event directive only after the generation-scoped action is accepted.
assert.match(main, /playbackEvents = PorticoPlaybackEventsController\(port, viewerRuntime\)/);
assert.match(main, /privateEventStateChanged[\s\S]*PorticoPlaybackEventsSetActiveSession/);
assert.match(main, /PorticoPlaybackEventsHandleNodeEvent/);
const playbackEventBranch = section(main, 'else if sourceNode <> invalid and playbackEvents.task', 'PorticoLifecycleReconcile');
assert.ok(playbackEventBranch.indexOf('PorticoMainDispatchPlaybackEventDirective') < playbackEventBranch.indexOf('PorticoPlaybackEventsAcknowledgeDirective'), 'Main must dispatch before acknowledging a playback directive');
assert.doesNotMatch(main, /PorticoMainMergeRuntimeState\([^\n]*(?:privateEventState|playbackEventResult)/, 'private session and event transport state must not enter runtimeState');

// Dedupe covers the same bounded replay window as Client Core.
assert.match(models, /while controller\.commandIds\.Count\(\) > 1024/);

console.log('Verified playback event registration/heartbeat/reset retry bounds, protocol quarantine, capability reconciliation, generation-scoped directive acknowledgement, teardown, and 1024-command dedupe.');
