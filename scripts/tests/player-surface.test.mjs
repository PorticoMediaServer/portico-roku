import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const pathFor = path => resolve(root, path);
const read = path => readFileSync(pathFor(path), 'utf8');
const player = read('channel/components/PorticoPlayer.brs');
const playerXml = read('channel/components/PorticoPlayer.xml');
const controller = read('channel/source/player/PorticoPlayerController.brs');
const presenter = read('channel/source/player/PorticoPlayerPresenter.brs');
const transport = read('channel/components/PorticoPlayerTransportButton.brs');
const transportXml = read('channel/components/PorticoPlayerTransportButton.xml');
const playbackTask = read('channel/components/PorticoPlaybackTask.brs');
const assets = read('scripts/generate-assets.mjs');
const contract = JSON.parse(read('channel/data/visual-contract.json'));

function pngSize(path) {
  const data = readFileSync(pathFor(path));
  assert.equal(data.subarray(1, 4).toString(), 'PNG', `${path} is not a PNG`);
  return {width: data.readUInt32BE(16), height: data.readUInt32BE(20)};
}

assert.match(playerXml, /component name="PorticoPlayer" extends="Group"/);
const fields = [...playerXml.matchAll(/<field id="([^"]+)"/g)].map(match => match[1]).sort();
assert.deepEqual(fields, ['focusState', 'playerEvent', 'privateContent', 'remotePlaybackDirective', 'viewState', 'watchGroupState', 'watchSyncDirective']);
assert.equal((playerXml.match(/<Video\b/g) ?? []).length, 1, 'Player must own exactly one Video node');
assert.match(playerXml, /<Video id="video" width="1920" height="1080" enableUI="false" enableTrickPlay="false" notificationInterval="1"/);
assert.match(playerXml, /pkg:\/source\/player\/PorticoPlayerController\.brs/);
assert.match(playerXml, /pkg:\/source\/player\/PorticoPlayerPresenter\.brs/);
for (const id of ['transportContainer', 'utilityContainer', 'panelContainer']) assert.match(playerXml, new RegExp(`<Group id="${id}"`));
assert.doesNotMatch(playerXml + player, /closePlayer|collapsePlayer|fullscreen|exit-fullscreen|Close player/i);

assert.match(player, /m\.playerController = PorticoPlayerControllerCreate\(/);
assert.match(player, /m\.playerPresenter = PorticoPlayerPresenterCreate\(\)/);
assert.doesNotMatch(player, /m\.(?:activePlaybackGeneration|activeSourceGeneration|eventSequence|nativeState|focusArea|focusedControl|panelKind|chromeVisible)\b/);
for (const field of ['playbackGeneration', 'sourceGeneration', 'eventSequence', 'timers', 'activation']) assert.match(controller, new RegExp(`${field}:`));
assert.match(controller, /PorticoPlayerControllerAccepts/);
assert.match(controller, /transaction\.phase = "requested"/);
assert.match(controller, /transaction\.phase = "committing"/);
assert.match(controller, /controller\.activation\.phase = "committed"/);
assert.match(controller, /transaction\.phase = "cancelled"/);
assert.match(controller, /transaction\.playbackGeneration <> controller\.playbackGeneration or transaction\.sourceGeneration <> controller\.sourceGeneration/);
assert.match(player, /if not press[\s\S]*PorticoPlayerControllerReleaseActivation/);
assert.match(player, /PorticoPlayerControllerBeginActivation[\s\S]*PorticoPlayerControllerCommitActivation[\s\S]*PorticoPlayerControllerCompleteActivation/);

assert.match(presenter, /focusArea: "transport"/);
assert.match(presenter, /player\.transport\./);
assert.match(presenter, /player\.utility\./);
assert.match(presenter, /player\.panel\./);
assert.match(presenter, /close-overlay[\s\S]*close-panel[\s\S]*close-utility[\s\S]*exit/);
assert.doesNotMatch(presenter, /reveal-chrome/);
assert.match(player, /semanticId: PorticoPlayerPresenterSemanticId\(m\.playerPresenter\)/);

assert.match(player, /PorticoPlayerControllerIsAudio\(m\.playerController\)[\s\S]*PorticoPlayerEmit\("exit-browsing", \{exitRequested: true, keepPlayback: true/);
assert.match(player, /PorticoPlayerEmit\("stop", \{exitRequested: true/);
assert.match(player, /if kind = "stop"[\s\S]*m\.playerController\.stopEventEmitted/);
assert.match(player, /key = "play" and controlsAvailable and not overlayVisible[\s\S]*PorticoPlayerTogglePlayback\(\)/);

assert.match(player, /PorticoPlayerControllerAccepts\(m\.playerController, model\.playbackGeneration, model\.sourceGeneration\)/);
assert.match(player, /m\.playerController\.privateContent\.porticoPlaybackGeneration/);
assert.match(player, /m\.playerController\.video\.content = content/);
assert.match(player, /m\.playerController\.video\.observeField\("position", "onVideoPositionChanged"\)/);
assert.doesNotMatch(player, /Print|roUrlTransfer|accessToken|grantToken|sessionId|apiBaseUrl/i);

for (const id of ['previous', 'back', 'playPause', 'forward', 'next']) assert.match(playerXml, new RegExp(`<PorticoPlayerTransportButton id="${id}"`));
assert.equal((playerXml.match(/<PorticoPlayerTransportButton\b/g) ?? []).length, 5);
for (const id of ['playback.previous', 'playback.seek-back', 'playback.play', 'playback.pause', 'playback.seek-forward', 'playback.next']) assert.match(transport + player, new RegExp(id.replaceAll('.', '\\.')));
assert.match(player, /focusedControl = 0[\s\S]*PorticoPlayerEmit\("previous"/);
assert.doesNotMatch(player, /focusedControl = 0[\s\S]{0,120}PorticoPlayerSeekTo\(0\)/);
assert.match(player, /kind: "volume"[\s\S]*kind: "subtitles"[\s\S]*kind: "quality"[\s\S]*kind: "speed"[\s\S]*kind: "sleep"[\s\S]*kind: "queue"/);
assert.doesNotMatch(player.match(/sub PorticoPlayerBuildUtilities\(\)[\s\S]*?\nend sub/)?.[0] ?? '', /kind: "(?:chapters|settings|lyrics|watch|streams)"/);
assert.match(transportXml, /PorticoIconResolver\.brs/);
assert.doesNotMatch(transport, /pkg:\/images\/icons\//);

const heartbeatUpdate = playbackTask.match(/sub PorticoPlaybackPlayerState\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(heartbeatUpdate, /if immediate[\s\S]*PorticoPlaybackSendProgress[\s\S]*else if not controller\.heartbeatScheduled/);
assert.equal((heartbeatUpdate.match(/nextHeartbeatAtSeconds = controller\.clock\.TotalSeconds\(\) \+ 10/g) ?? []).length, 2);

for (const measurement of [['identityX', 72], ['identityY', 58], ['progressWidth', 1776], ['transportButtonSize', 60], ['transportMainSize', 78]]) {
  assert.equal(contract.player[measurement[0]], measurement[1]);
}
for (const asset of [['player-overlay-scrim.png', 1920, 1080], ['player-transport-dock.png', 286, 88], ['player-transport-idle.png', 60, 60], ['player-transport-main.png', 78, 78]]) {
  assert.match(assets, new RegExp(`'${asset[0].replace('.', '\\.')}[^\n]*${asset[1]}[^\n]*${asset[2]}`));
  assert.deepEqual(pngSize(`channel/images/ui/${asset[0]}`), {width: asset[1], height: asset[2]});
}
assert.ok(existsSync(pathFor('artifacts/golden/player-playing.png')));

console.log('Verified the Roku player controller/presenter split, generation fencing, semantic focus, repeat-safe activation, deterministic Back, and audio persistence boundary.');
