import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoApplicationEventsTask.brs');
const xml = read('channel/components/PorticoApplicationEventsTask.xml');
const runtime = read('channel/source/lib/PorticoApplicationEventsRuntime.brs');
const bridge = read('channel/source/lib/PorticoApplicationEvents.brs');
const main = read('channel/source/main.brs');
const contentTask = read('channel/components/PorticoContentTask.brs');
const searchTask = read('channel/components/PorticoSearchTask.brs');
const libraryTask = read('channel/components/PorticoLibraryTask.brs');
const savedTask = read('channel/components/PorticoSavedTask.brs');
const liveTvTask = read('channel/components/PorticoLiveTvTask.brs');
const libraryScreen = read('channel/components/PorticoLibraryScreen.brs');
const eventTransport = read('channel/source/core/PorticoEventTransport.brs');
const serverConnection = read('channel/components/PorticoServerConnectionTask.brs');
const preferenceController = read('channel/source/lib/PorticoViewerPreferencesController.brs');
const preferenceTask = read('channel/components/PorticoViewerPreferencesTask.brs');

assert.match(xml, /PorticoApplicationEventsTask/);
assert.match(xml, /PorticoProductContract\.brs/);
assert.match(xml, /PorticoProductLanguage\.brs/);
assert.match(xml, /PorticoEventTransport\.brs/);

// Deliberate capability selection plus exact generated operation gating.
assert.match(task, /PorticoProductContractValidateLive\(response\.data\)\.ok/);
assert.match(task, /PorticoApplicationEventsCapabilityProjection\(command\.eventCapabilities\)/);
assert.match(task, /PorticoApplicationEventsOperation\(controller, "pollApplicationEvents"\)/);
assert.match(task, /if not PorticoApplicationEventsPollOperationAllowed\(operation\) or controller\.longPollQuarantined then capabilities\.longPollAdvertised = false/);
assert.match(runtime, /operation\.method = "GET" and operation\.path = "\/events\/poll"/);
assert.match(task, /PorticoEventTransportCreate\(controller\.viewerScope, "shell"/);
assert.match(task, /"pollApplicationEvents", query, 35000/);
assert.match(task, /request\.requestKind = "authoritative-refresh"[\s\S]*PorticoApplicationEventsPublishAll/);

// Validate every event before cursor publication. Invalid stable responses
// quarantine this subscription into bounded refresh instead of looping.
assert.ok(task.indexOf('prevalidatedEnvelope = PorticoEventTransportEnvelope(response.data)') < task.indexOf('accepted = PorticoEventTransportAcceptResponse'));
assert.ok(task.indexOf('directives = PorticoApplicationEventDirectives(prevalidatedEnvelope.events') < task.indexOf('accepted = PorticoEventTransportAcceptResponse'));
assert.match(task, /PorticoApplicationEventsQuarantineLongPoll/);
assert.match(task, /response\.code = "authorization_revision_changed"/);
assert.match(task, /else if response\.status = 401 or response\.status = 403[\s\S]*controller\.status = "backoff"/);
assert.match(task, /else if response\.status = 404 or not response\.retryable/);
assert.match(task, /response\.retryAfterSeconds/);

// Exact AppEvent schema, bounded fields, monotonic ID dedupe, and only
// allowlisted coalesced directive domains cross into Main.
assert.match(runtime, /value\.Count\(\) < 4 or value\.Count\(\) > 7/);
for (const key of ['id', 'type', 'tags', 'createdAt', 'resource', 'resourceId', 'fields']) assert.match(runtime, new RegExp(`${key}: true`));
assert.match(runtime, /if eventValue\.id > highest/);
assert.match(runtime, /playback-progress[\s\S]*for each domain in \["home", "detail", "library", "saved"\]/);
assert.doesNotMatch(runtime.match(/else if tag = "playback"[\s\S]*?else if tag = "dvr"/)?.[0] ?? '', /_broad/, 'Progress events must not churn unrelated domains');
for (const tag of ['home', 'libraries', 'new-media', 'browse', 'search', 'playlists', 'favorites', 'watchlist', 'watched', 'history', 'progress', 'resume', 'library-channels', 'display-preferences', 'account']) assert.ok(runtime.includes(`tag = "${tag}"`), `missing known AppEvent mapping: ${tag}`);
assert.match(runtime, /broadRequired: domains\["_unknown"\] = true or domains\["_broad"\] = true/);
assert.match(task, /nextBroadInvalidationAt = controller\.clock\.TotalSeconds\(\) \+ 30/);
assert.match(task, /pendingBroadInvalidation: false/);
assert.match(task, /if directives\.broadRequired then controller\.pendingBroadInvalidation = true/);
assert.doesNotMatch(task, /projection.*events/i, 'raw application events must not enter shared runtime state');
assert.doesNotMatch(task, /projection.*fields/i, 'AppEvent fields must not enter shared runtime state');

// Main dispatches background-only commands. No application invalidation may
// change the visible route or Scene-owned focus/scroll coordinates.
const dispatch = main.match(/function PorticoMainDispatchApplicationEventDirective[\s\S]*?\nend function/)?.[0] ?? '';
for (const command of ['quiet-refresh-content', 'quiet-refresh-search', 'quiet-refresh-library', 'quiet-refresh-saved', 'quiet-refresh-channels']) assert.ok(dispatch.includes(`kind: "${command}"`), `missing quiet invalidation command ${command}`);
assert.match(dispatch, /quiet-retry-preferences/);
assert.doesNotMatch(dispatch, /retry-profile-directory/, 'Generic data invalidation must not reopen the profile chooser');
assert.doesNotMatch(dispatch, /scene\.(?:page|route|focus)|focused|scroll|windowOffset|translation|setFocus/i);
assert.match(dispatch, /PorticoMainInvalidationDomainActive\(scene, domain\)/);
assert.match(dispatch, /m\.porticoPendingInvalidations\[domain\] = true/);
assert.match(main, /sub PorticoMainFlushActiveInvalidations[\s\S]*PorticoMainDispatchApplicationEventDirective/);
assert.match(main, /if domain = "library" then return page = "library" or Left\(page, 8\) = "library\/"/);
assert.match(main, /PorticoMainFlushActiveInvalidations\(viewerRuntime, scene, content, search, library, saved, liveTv, profiles, viewerPreferences\)/);
assert.match(main, /sub PorticoMainFenceConstrainedEventOwners\(\)[\s\S]*m\.porticoPendingInvalidations = \{\}/);
assert.match(contentTask, /else if kind = "quiet-refresh-content"[\s\S]*Keep the current projection[\s\S]*homeLoadRequested = true/);
assert.match(searchTask, /else if kind = "quiet-refresh-search"[\s\S]*quietRefresh = true[\s\S]*searchRequested = true/);
assert.match(searchTask, /preservedOffsets[\s\S]*group\.windowOffset = preservedOffsets\[group\.id\]/);
assert.match(searchTask, /if controller\.quietRefresh and controller\.groups\.Count\(\) > 0[\s\S]*controller\.status = "ready"/);
assert.match(libraryTask, /else if kind = "quiet-refresh-library"[\s\S]*quietWindowOffset = controller\.windowOffset[\s\S]*requestKind = "page"/);
assert.match(libraryTask, /if controller\.quietRefresh then controller\.windowOffset = controller\.quietWindowOffset else controller\.windowOffset = 0/);
assert.match(savedTask, /else if kind = "quiet-refresh-saved"[\s\S]*quietWindowOffset = controller\.windowOffset[\s\S]*requestKind = "page"/);
assert.match(savedTask, /if controller\.quietRefresh then controller\.windowOffset = controller\.quietWindowOffset else controller\.windowOffset = 0/);
assert.match(liveTvTask, /else if kind = "quiet-refresh-channels"[\s\S]*controller\.quietRefresh = true[\s\S]*PorticoLiveTvRetry/);
assert.match(liveTvTask, /sub PorticoLiveTvBeginRefresh[\s\S]*if controller\.quietRefresh then return/);
assert.match(libraryScreen, /status = "refreshing" or status = "stale"[\s\S]*status = "ready"/);
assert.match(preferenceController, /kind = "quiet-retry-preferences"[\s\S]*"quiet-reload"/);
assert.match(preferenceTask, /kind = "quiet-reload"[\s\S]*quietRefresh = true/);
assert.match(preferenceTask, /if not controller\.quietRefresh[\s\S]*controller\.status = "loading"/);
assert.match(preferenceTask, /if controller\.quietRefresh and controller\.bundle <> invalid[\s\S]*controller\.status = "ready"[\s\S]*return/);

// Roku cannot consume SSE directly. SSE advertisement alone remains bounded
// refresh; long-poll additionally requires its exact reviewed operation.
assert.match(eventTransport, /if transport = "long-poll" then result\.longPollAdvertised = true/);
assert.doesNotMatch(eventTransport, /transport = "sse" then result\.longPollAdvertised = true/);
assert.match(task, /if not PorticoApplicationEventsPollOperationAllowed\(operation\) or controller\.longPollQuarantined then capabilities\.longPollAdvertised = false/);

// Access credentials rotate independently of the stream. Every poll reloads
// the durable server session, while the owner refreshes five minutes before
// expiry; an in-flight old-token rejection enters bounded retry and the next
// poll consumes the replacement without resetting the shell.
assert.match(runtime, /PorticoSecureRegistryRead\("server-session"\)/);
assert.match(runtime, /PorticoServerSessionRequestProjection\(stored, scope, record\.generation\)/);
assert.match(serverConnection, /remaining - 300/);
assert.match(task, /response\.status = 401 or response\.status = 403[\s\S]*controller\.status = "backoff"/);
assert.match(eventTransport, /if delay > 300 then delay = 300/);

// Reset publication remains fenced until Main confirms every authoritative
// refresh command was successfully issued for this generation.
assert.match(task, /kind: "reset-domains"[\s\S]*ackToken:/);
assert.match(task, /PorticoApplicationEventsAcknowledgeResetCommand/);
assert.match(task, /PorticoEventTransportAcknowledgeReset/);
assert.match(bridge, /PorticoApplicationEventsAcknowledgeReset/);
assert.match(bridge, /PorticoViewerRuntimeAcceptProjection/);
assert.match(bridge, /controller\.task\.control = "STOP"[\s\S]*controller\.task = invalid[\s\S]*controller\.taskFenced = true/);
assert.match(bridge, /PorticoApplicationEventsStartTask/);
assert.match(bridge, /value\.Count\(\) <> 6/);
assert.match(bridge, /allowed = \{home: true, detail: true, search: true, library: true, saved: true, channels: true, settings: true, profile: true\}/);

// Viewer/server replacement fences the transport and the HTTP request loop
// performs synchronous cancellation with private TLS and bounded responses.
assert.match(task, /PorticoEventTransportCancel\(controller\.transport, "server-unavailable"\)/);
assert.match(task, /PorticoEventTransportCancel\(controller\.transport, reason\)/);
assert.match(task, /PorticoApplicationEventsInterrupted[\s\S]*transfer\.AsyncCancel\(\)/);
assert.match(task, /PorticoHttpValidatePrivateRequest\(request\)/);
assert.match(task, /EnablePeerVerification\(true\)/);
assert.match(task, /EnableHostVerification\(true\)/);
assert.match(task, /PorticoHttpLimits\(\)\.maximumResponseBytes/);

console.log('Verified capability/operation-gated shell application events, strict prevalidation/dedupe, throttled allowlisted directives, reset acknowledgement, bounded fallback, fencing, and private TLS transport.');
