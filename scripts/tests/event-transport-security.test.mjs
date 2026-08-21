import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const source = await readFile(new URL('../../channel/source/core/PorticoEventTransport.brs', import.meta.url), 'utf8');

assert.match(source, /if maximumStreams > 4 then maximumStreams = 4/);
assert.match(source, /maximumConsecutiveDrains: 8/);
assert.match(source, /cursorHistory: \[\]/);
assert.match(source, /cursorRepeated[\s\S]*envelope\.hasMore or envelope\.events\.Count\(\) > 0/);
assert.match(source, /state\.nextAttemptAt = nowSeconds \+ 1/);
assert.match(source, /budget = \{nodes: 2048, text: 524288\}/);
assert.match(source, /if value\.Count\(\) <> 6 then return invalid/);
assert.match(source, /allowedKeys = \{version: true, cursor: true, serverTime: true, resetRequired: true, hasMore: true, events: true\}/);
assert.match(source, /if allowedKeys\[key\] <> true then return invalid/);
assert.match(source, /if raw <> serverTime then return ""/);
assert.match(source, /parsed = CreateObject\("roDateTime"\)/);
assert.match(source, /if parsed = invalid or not parsed\.FromISO8601String\(serverTime\) then return ""/);
assert.match(source, /if depth > 10 or budget\.nodes < 1 then return false/);
assert.match(source, /if value\.Count\(\) > 512 then return false/);
assert.match(source, /if value\.Count\(\) > 128 then return false/);
assert.match(source, /while state\.cursorHistory\.Count\(\) > 16/);

const state = {
  cursor: '',
  cursorHistory: [],
  consecutiveDrainCount: 0,
  maximumConsecutiveDrains: 8,
  nextAttemptAt: 0
};

function acceptBatch(cursor, hasMore, eventCount, nowSeconds) {
  const repeated = state.cursor !== '' && state.cursorHistory.includes(cursor);
  if (repeated && (hasMore || eventCount > 0)) return {accepted: false, code: 'cursor_not_advanced'};
  state.cursor = cursor;
  if (!state.cursorHistory.includes(cursor)) state.cursorHistory.push(cursor);
  while (state.cursorHistory.length > 16) state.cursorHistory.shift();
  state.nextAttemptAt = nowSeconds;
  if (!hasMore) {
    state.consecutiveDrainCount = 0;
    return {accepted: true, nextAttemptAt: nowSeconds};
  }
  state.consecutiveDrainCount += 1;
  if (state.consecutiveDrainCount >= state.maximumConsecutiveDrains) {
    state.consecutiveDrainCount = 0;
    state.nextAttemptAt = nowSeconds + 1;
  }
  return {accepted: true, nextAttemptAt: state.nextAttemptAt};
}

for (let index = 1; index <= 7; index += 1) {
  assert.deepEqual(acceptBatch(`cursor_${index}`, true, 100, 100), {accepted: true, nextAttemptAt: 100});
}
assert.deepEqual(acceptBatch('cursor_8', true, 100, 100), {accepted: true, nextAttemptAt: 101});
assert.deepEqual(acceptBatch('cursor_8', true, 1, 101), {accepted: false, code: 'cursor_not_advanced'});
assert.deepEqual(acceptBatch('cursor_9', false, 0, 101), {accepted: true, nextAttemptAt: 101});
assert.equal(state.consecutiveDrainCount, 0);

for (let index = 10; index <= 30; index += 1) acceptBatch(`cursor_${index}`, false, 0, 102 + index);
assert.equal(state.cursorHistory.length, 16);
assert.equal(state.cursorHistory.includes('cursor_1'), false);
assert.equal(state.cursorHistory.includes('cursor_30'), true);

console.log('Verified Roku long-poll concurrency cap, cursor progress, bounded drain yielding, and event envelope budgets.');
