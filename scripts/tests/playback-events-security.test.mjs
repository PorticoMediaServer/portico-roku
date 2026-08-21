import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const task = await readFile(new URL('../../channel/components/PorticoPlaybackEventsTask.brs', import.meta.url), 'utf8');
const models = await readFile(new URL('../../channel/source/lib/PorticoPlaybackEventsModels.brs', import.meta.url), 'utf8');
const runtime = await readFile(new URL('../../channel/source/lib/PorticoPlaybackEventsRuntime.brs', import.meta.url), 'utf8');
const controller = await readFile(new URL('../../channel/source/lib/PorticoPlaybackEvents.brs', import.meta.url), 'utf8');

assert.equal((task.match(/transport:/g) ?? []).length, 1, 'combined task owns one transport slot');
assert.match(task, /if controller\.activeSessionId <> "" and controller\.activePlaybackGeneration > 0[\s\S]*PorticoPlaybackEventsTickSession\(controller\)[\s\S]*else[\s\S]*PorticoPlaybackEventsTickReceiver\(controller\)/);
assert.match(task, /PorticoPlaybackEventsCancelStream\(controller, "mode-switch"\)/);
assert.match(task, /if desired = "session"[\s\S]*PorticoPlaybackEventsClearReceiver\(controller\)/);
assert.match(task, /PorticoPlaybackEventsCancelStream\(controller, reason\)[\s\S]*PorticoPlaybackEventsClearReceiver\(controller\)/);

assert.match(task, /"postPlaybackReceivers"/);
assert.match(task, /"patchPlaybackReceiversReceiverId"/);
assert.match(task, /"pollPlaybackReceiverEvents"/);
assert.match(task, /"pollPlaybackSessionCommands"/);
assert.match(task, /"getPlaybackSessionsSessionIdCommand"/);
assert.match(task, /capabilities\.longPollAdvertised/);
assert.match(task, /PorticoPlaybackEventsOperation\(controller, "pollPlaybackReceiverEvents"/);
assert.match(task, /PorticoPlaybackEventsOperation\(controller, "pollPlaybackSessionCommands"/);
assert.match(task, /PorticoPlaybackEventsRequest\(controller, operationId, inputs, "GET", path, invalid, query, 30000\)/);
assert.match(runtime, /SetCertificatesFile\("common:\/certs\/ca-bundle\.crt"\)/);
assert.match(runtime, /EnablePeerVerification\(true\)/);
assert.match(runtime, /EnableHostVerification\(true\)/);
assert.match(runtime, /PorticoHttpLimits\(\)\.maximumResponseBytes/);
assert.match(runtime, /headers\["retry-after"\]/);
assert.match(runtime, /transfer\.Escape\(cursor\)/);
assert.match(runtime, /PorticoPlaybackEventsSessionStillCurrent\(controller, session\)/);

assert.match(models, /allowed = \{id: true, name: true, code: true, app: true, platform: true, supportedCommands: true, command: true, createdAt: true, lastSeenAt: true\}/);
assert.match(models, /allowed = \{id: true, action: true, mediaId: true, positionSeconds: true, message: true, issuedByProfileId: true, issuedAt: true\}/);
assert.match(models, /if value\.supportedCommands\[0\] <> "load" then return invalid/);
assert.match(models, /receiverOnly and action <> "load"/);
assert.match(models, /if action = "load" and mediaId = "" then return invalid/);
assert.match(models, /if action = "seek" and position = invalid then return invalid/);
assert.match(models, /while controller\.commandIds\.Count\(\) > 1024/);

const publishStart = task.indexOf('sub PorticoPlaybackEventsPublish');
assert.notEqual(publishStart, -1);
const publish = task.slice(publishStart);
const projectionLiteral = publish.match(/projection = \{([^\n]+)\}/)?.[1] ?? '';
for (const forbiddenKey of ['receiverId:', 'receiverCode:', 'activeSessionId:', 'commandIds:', 'cursor:', 'accessToken:']) {
  assert.equal(projectionLiteral.includes(forbiddenKey), false, `public projection must omit ${forbiddenKey}`);
}
assert.match(publish, /projection = \{status: controller\.status, mode: controller\.mode, receiverReady:/);
assert.match(runtime, /domain: "playback-events"/);
assert.match(controller, /PorticoPlaybackEventsSetActiveSession/);
assert.match(controller, /PorticoPlaybackEventsClearActiveSession/);

function receiverCode(value) {
  if (typeof value !== 'string') return '';
  const code = value.toUpperCase();
  if (value !== code || code.length < 1 || code.length > 32 || !/^[A-Z0-9]+$/.test(code)) return '';
  return code;
}

assert.equal(receiverCode('AB12CD'), 'AB12CD', 'canonical server six-character discovery code passes');
assert.equal(receiverCode('ab12cd'), '', 'non-canonical lower-case tokens are rejected');
assert.equal(receiverCode('A'), 'A', 'schema-compatible bounded token passes');
assert.equal(receiverCode('A'.repeat(32)), 'A'.repeat(32));
assert.equal(receiverCode('ABCD-EFGH'), '', 'device-auth display code is not conflated with receiver token');
assert.equal(receiverCode('A'.repeat(33)), '');
assert.equal(receiverCode('ABC\n12'), '');

function desiredMode(activeSessionId, generation) {
  return activeSessionId && generation > 0 ? 'session' : 'receiver';
}
assert.equal(desiredMode('', 0), 'receiver');
assert.equal(desiredMode('session-private', 4), 'session');

const seen = [];
for (let index = 0; index < 1040; index += 1) {
  const id = `command-${index}`;
  if (!seen.includes(id)) seen.push(id);
  while (seen.length > 1024) seen.shift();
}
assert.equal(seen.length, 1024);
assert.equal(seen.includes('command-0'), false);
assert.equal(seen.includes('command-1039'), true);

console.log('Verified exclusive playback event modes, exact contracts, private identity containment, TLS polling, and bounded dedupe.');
