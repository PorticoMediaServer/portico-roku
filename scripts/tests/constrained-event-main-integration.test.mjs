import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const main = read('channel/source/Main.brs');
const scene = read('channel/components/PorticoScene.xml');
const sceneScript = read('channel/components/PorticoScene.brs');
const contentTask = read('channel/components/PorticoContentTask.brs');
const playbackTask = read('channel/components/PorticoPlaybackTask.brs');
const playbackBridge = read('channel/source/lib/PorticoPlayback.brs');
const applicationBridge = read('channel/source/lib/PorticoApplicationEvents.brs');
const playbackEventsBridge = read('channel/source/lib/PorticoPlaybackEvents.brs');
const playerXml = read('channel/components/PorticoPlayer.xml');
const player = read('channel/components/PorticoPlayer.brs');
const engagementTask = read('channel/components/PorticoEngagementTask.brs');
const engagementBridge = read('channel/source/lib/PorticoEngagement.brs');
const watchBridge = read('channel/source/lib/PorticoWatchWithFriends.brs');

assert.doesNotMatch(scene, /PorticoApplicationEventsTask id="applicationEventsTaskRegistrationAnchor"/, 'Application events task must be owned by its bridge');
assert.doesNotMatch(scene, /PorticoPlaybackEventsTask id="playbackEventsTaskRegistrationAnchor"/, 'Playback events task must be owned by its bridge');
assert.match(applicationBridge, /CreateObject\("roSGNode", "PorticoApplicationEventsTask"\)/);
assert.match(playbackEventsBridge, /CreateObject\("roSGNode", "PorticoPlaybackEventsTask"\)/);
assert.match(main, /PorticoApplicationEventsController\(port, viewerRuntime\)/);
assert.match(main, /PorticoPlaybackEventsController\(port, viewerRuntime\)/);
assert.match(main, /PorticoPlaybackEventsHandleNodeEvent/);
assert.match(main, /PorticoPlaybackEventsAcknowledgeDirective\(playbackEvents, playbackEventResult\.directive\.ackToken\)/);

// Shell home + detail invalidations share ContentTask's latest-value mailbox,
// so Main must fan them in as one command and Task must schedule both loads.
assert.match(main, /refreshHome or refreshDetail[\s\S]*kind: "quiet-refresh-content"/);
assert.match(contentTask, /kind = "quiet-refresh-content"[\s\S]*command\.refreshHome = true[\s\S]*detailMediaId/);

// Playback-session identity remains private and only the narrow lifecycle handoff
// crosses from PlaybackTask to the dedicated constrained-event owner.
assert.match(playbackTask, /m\.top\.eventState = eventState/);
assert.doesNotMatch(playbackTask, /projection\.sessionId|projection = \{[^}]*sessionId/s);
assert.match(main, /PorticoPlaybackEventsSetActiveSession\(playbackEvents, eventState\.sessionId, eventState\.playbackGeneration\)/);

// Remote commands have their own Player mailbox and cannot overwrite WFF sync.
assert.match(playerXml, /field id="remotePlaybackDirective"[^>]*onChange="applyRemotePlaybackDirective"/);
assert.match(player, /sub applyRemotePlaybackDirective\(\)/);
assert.doesNotMatch(main, /watchSyncDirective = \{type: (?:kind|"seek")/);

// Receiver load is acknowledged only after its viewer-scoped start command was
// enqueued, then a private Scene command visibly presents Player without writing
// the Scene activation output and starting playback a second time.
assert.match(playbackBridge, /function PorticoPlaybackStartTargetCommand[\s\S]*PorticoPlaybackViewerCommand[\s\S]*return true/);
assert.match(main, /if not PorticoPlaybackStartTargetCommand\([\s\S]*then return false[\s\S]*playbackViewState:[\s\S]*scene\.playbackPresentationCommand/);
assert.match(scene, /field id="playbackPresentationCommand"[^>]*onChange="playbackPresentationCommandChanged"/);
assert.match(sceneScript, /sub playbackPresentationCommandChanged\(\)[\s\S]*pushRoute\("player"[\s\S]*PorticoSceneSyncNavigationAliases\(\)[\s\S]*renderScene\(\)/);
assert.doesNotMatch(sceneScript.match(/sub playbackPresentationCommandChanged\(\)([\s\S]*?)end sub/)?.[1] ?? '', /m\.top\.activation|emitActivation|emitPlaybackActivation/);
const presentationHandler = sceneScript.match(/sub playbackPresentationCommandChanged\(\)([\s\S]*?)end sub/)?.[1] ?? '';
assert.match(main, /playbackPresentationCommand = \{[\s\S]*viewerGeneration: PorticoViewerScopePositiveInteger\(scene\.runtimeState\.viewerGeneration\)/);
assert.match(presentationHandler, /command\.Count\(\) <> 4/);
assert.match(presentationHandler, /generation <> PorticoSceneSafeInteger\(state\.viewerGeneration, 0\) then return/);
assert.match(presentationHandler, /not accountIsSignedIn\(\) or not activeViewerPublished\(\) then return/);
assert.ok(presentationHandler.indexOf('not accountIsSignedIn() or not activeViewerPublished() then return') < presentationHandler.indexOf('pushRoute("player"'));

// Previous is an authoritative queue-history handoff, not a seek-to-zero alias.
assert.match(playbackTask, /function PorticoPlaybackAdvancePrevious[\s\S]*\/queue[\s\S]*data\.history[\s\S]*PorticoPlaybackAdvanceNext\(controller, false, previousId, true\)/);
assert.match(playbackBridge, /PorticoPlaybackRemotePreviousCommand/);
assert.match(playbackTask, /playback-remote-stopped/);
assert.match(player, /playback\.remote-stopped/);

// Rollback and already-fenced lifecycle paths must actively clear/STOP owners.
assert.match(engagementBridge, /projectedCapabilities = \{\}/);
assert.match(watchBridge, /projectedCapabilities = \{\}/);
assert.match(engagementBridge, /not PorticoViewerRuntimeAccepting[\s\S]*task\.control = "STOP"/);
assert.match(watchBridge, /not PorticoViewerRuntimeAccepting[\s\S]*task\.control = "STOP"/);
assert.match(engagementTask, /response\.status = 404[\s\S]*PorticoEngagementQuarantineNotificationLongPoll/);
assert.match(engagementTask, /if response\.status = 404 then return "operation_not_found"/);

console.log('Verified constrained-event Main fan-in, private playback lifecycle, dedicated remote commands, queue-history previous, rollback, and teardown.');
