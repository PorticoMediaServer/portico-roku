import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoLiveTvTask.brs');
const taskXml = read('channel/components/PorticoLiveTvTask.xml');
const models = read('channel/source/lib/PorticoLiveTvModels.brs');
const bridge = read('channel/source/lib/PorticoLiveTv.brs');
const runtime = read('channel/source/lib/PorticoChannelsRuntime.brs');
const scene = read('channel/components/PorticoScene.brs');
const main = read('channel/source/main.brs');
const openapi = JSON.parse(read('../portico-server/api/openapi/portico-server.openapi.json'));

for (const [path, verb] of [
  ['/live-tv/sources', 'get'], ['/live-tv/sources/{sourceId}/channels', 'get'], ['/live-tv/sources/{sourceId}/guide', 'get'],
  ['/dvr/recordings', 'get'], ['/dvr/recordings', 'post'], ['/dvr/status', 'get'],
]) {
  assert.ok(openapi.paths[path]?.[verb], `${verb.toUpperCase()} ${path} disappeared from the Server OpenAPI`);
  assert.equal(openapi.paths[path][verb]['x-portico-auth'], 'session', `${path} must remain session authenticated`);
}

assert.match(taskXml, /component name="PorticoLiveTvTask" extends="Task"/);
assert.match(taskXml, /PorticoContentModels\.brs/);
assert.match(taskXml, /PorticoBrowseApi\.brs/);
assert.match(taskXml, /PorticoLiveTvModels\.brs/);
assert.doesNotMatch(taskXml, /field id="(?:accessToken|refreshToken|apiBaseUrl|headers|serverSession)"/i);
for (const tab of ['guide', 'channels', 'dvr']) assert.match(task, new RegExp(`id: "${tab}", label:`));
for (const operationId of ['getLiveTv', 'getLiveTvSourcesSourceIdChannels', 'getLiveTvSourcesSourceIdGuide', 'getDvrRecordings', 'getDVRStatus']) {
  assert.match(task, new RegExp(`PorticoChannelsRequest\\(controller, "${operationId}"`));
}
assert.match(runtime, /PorticoOperationContractResolvePath\(controller\.operationContract, "server", operationId, inputs\)/);
assert.match(runtime, /resolved\.path = "\/api" \+ resolved\.path \+ suffix/);
assert.match(task, /else if controller\.selectedTab = "channels"[\s\S]*pageSize = 8/);
assert.match(task, /PorticoLiveTvSlice\(controller\.dvr\.recordings, controller\.dvrPage \* 4, 4\)/);

const record = task.match(/sub PorticoLiveTvRecordProgram[\s\S]*?\nend sub/)?.[0] ?? '';
assert.match(record, /if series[\s\S]*action = "dvr\.record-series"/);
assert.match(record, /PorticoLiveTvHasAction\(target\.actions, action\)/);
assert.match(record, /body = \{sourceId: controller\.selectedSourceId, channelId: target\.channelId, programId: target\.id, title: target\.title, startsAt: target\.startAt, endsAt: target\.endAt\}/);
assert.match(record, /PorticoChannelsRequest\(controller, operationId, \{\}, \{\}, body\)/);
assert.match(record, /if result\.status = 409 then PorticoLiveTvLoadDvr/);
assert.match(record, /PorticoLiveTvLoadDvr\(controller, "", "", ""\)/);
assert.match(task, /load-more-dvr-recordings/);
assert.match(task, /load-more-dvr-rules/);
assert.match(task, /load-more-dvr-schedule/);
assert.match(task, /dvrCollectionState/);
const dvrCollectionLoader = task.match(/sub PorticoLiveTvLoadDvrCollection\([\s\S]*?\nend sub/)?.[0] ?? '';
assert.ok(dvrCollectionLoader.length > 0, 'DVR collections require an isolated cursor loader.');
assert.equal((dvrCollectionLoader.match(/PorticoChannelsRequest\(/g) ?? []).length, 1, 'One collection advance must issue exactly one endpoint request.');
assert.match(dvrCollectionLoader, /if kind = "recordings"[\s\S]*operationId = "getDvrRecordings"/);
assert.match(dvrCollectionLoader, /else if kind = "rules"[\s\S]*operationId = "getDvrRules"/);
assert.match(dvrCollectionLoader, /else if kind = "schedule"[\s\S]*operationId = "getDvrSchedule"/);
assert.doesNotMatch(dvrCollectionLoader, /getDVRStatus/);
assert.match(dvrCollectionLoader, /if not result\.ok[\s\S]*dvrCollectionState\[kind\] = "error"[\s\S]*return/);
for (const [command, collection] of [['load-more-dvr-recordings', 'recordings'], ['load-more-dvr-rules', 'rules'], ['load-more-dvr-schedule', 'schedule']]) {
  assert.match(task, new RegExp(`kind = "${command}"[\\s\\S]*PorticoLiveTvLoadDvrCollection\\(controller, "${collection}"`));
}
assert.match(task, /controller\.reconnectRequestedGeneration <> controller\.viewerGeneration/);

assert.match(models, /if channels\.Count\(\) >= 250 then exit for/);
assert.match(models, /if recordings\.Count\(\) >= 200 then exit for/);
for (const action of ['live.play', 'dvr.record', 'dvr.play', 'dvr.cancel']) assert.ok(models.includes(`"${action}": true`));
assert.ok(models.includes('play: true'));
for (const activation of ['select-channel-tab', 'select-program', 'record-program', 'retry-channels', 'page-channels']) assert.ok(bridge.includes(`"${activation}": true`));
assert.match(scene, /if kind = "play-live" or kind = "play-dvr"[\s\S]*openPlayback\(kind, action\.targetId/);
assert.match(main, /PorticoLiveTvHandleActivation\(liveTv, activationData\)/);
assert.match(main, /PorticoLiveTvHandleNodeEvent\(liveTv, message, viewerRuntime\)/);

console.log('Verified Channels guide/source loading, bounded DVR projection, scheduling, playback routing, and reconnect contracts.');
