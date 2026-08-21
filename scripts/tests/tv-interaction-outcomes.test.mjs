import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const rokuRoot = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const fixture = JSON.parse(readFileSync(resolve(rokuRoot, '../../scripts/parity/tv-interaction-outcomes.v1.json'), 'utf8'));
const byId = Object.fromEntries(fixture.cases.map(item => [item.id, item]));
const read = path => readFileSync(resolve(rokuRoot, path), 'utf8');
const navigationAuthority = read('channel/source/navigation/PorticoNavigationStore.brs');
const backAuthority = read('channel/source/navigation/BackCoordinator.brs');
const activationAuthority = read('channel/source/navigation/ActivationTransactions.brs');
const focusAuthority = read('channel/source/focus/ScreenFocusAuthority.brs');
const playerPresenter = read('channel/source/player/PorticoPlayerPresenter.brs');
const player = read('channel/components/PorticoPlayer.brs');
const playbackTask = read('channel/components/PorticoPlaybackTask.brs');

const navigation = structuredClone(byId['destination-primary-replaces-history'].initial);
for (const event of byId['destination-primary-replaces-history'].events) {
  if (event.kind === 'push') navigation.history.push(navigation.current);
  if (event.kind === 'primary') navigation.history = [];
  navigation.current = event.destination;
  navigation.routeEpoch += 1;
}
assert.deepEqual(navigation, byId['destination-primary-replaces-history'].expected);
assert.match(navigationAuthority, /transitionMode = "push"[\s\S]*store\.history\.Push\(store\.current\)[\s\S]*transitionMode = "primary"[\s\S]*store\.history = \[\][\s\S]*store\.routeEpoch = store\.routeEpoch \+ 1[\s\S]*store\.current =/);

const backOutcomes = initial => {
  const state = structuredClone(initial);
  const outcomes = [];
  return event => {
    if (event.kind !== 'back') return;
    if (state.rail === 'open') {
      if (state.railOrigin === 'root-back') outcomes.push('system-exit');
      else { outcomes.push('close-rail'); state.rail = 'closed'; }
    } else if (state.history.length) outcomes.push('navigate-back');
    else { outcomes.push('open-rail'); state.rail = 'open'; state.railOrigin = 'root-back'; }
    return outcomes;
  };
};
for (const vector of fixture.cases.filter(item => item.category === 'back')) {
  const step = backOutcomes(vector.initial);
  let outcomes = [];
  for (const event of vector.events) outcomes = step(event) ?? outcomes;
  assert.deepEqual(outcomes, vector.expected.outcomes, vector.id);
  if (vector.expected.focused) assert.equal(vector.initial.invoker, vector.expected.focused, vector.id);
}
assert.ok(backAuthority.indexOf('if context.railExpanded = true') < backAuthority.indexOf('if context.hasHistory = true'), 'live Back authority must resolve an expanded rail before history');
for (const kind of ['close-overlay', 'close-panel', 'exit-channel', 'close-rail', 'route-back', 'open-rail']) assert.match(backAuthority, new RegExp(`kind: "${kind}"`));

assert.match(activationAuthority, /state: "requested"/);
assert.match(activationAuthority, /transactions\.state = "committing"/);
assert.match(activationAuthority, /transactions\.state = "committed"/);
assert.match(activationAuthority, /transactions\.state = "cancelled"/);
assert.match(activationAuthority, /transactions\.activeKey = key/);
assert.match(activationAuthority, /transactions\.coalescedCount = transactions\.coalescedCount \+ 1/);
assert.match(activationAuthority, /transaction\.viewerEpoch <> viewerEpoch or transaction\.routeEpoch <> routeEpoch/);

for (const id of ['focus-removed-item-falls-back-semantically', 'focus-reorder-preserves-semantic-id']) {
  const vector = byId[id];
  const targets = vector.events[0].targets;
  assert.equal(targets.includes(vector.initial.focused) ? vector.initial.focused : targets[0], vector.expected.focused, id);
}
const modal = byId['focus-modal-traps-and-restores-invoker'];
assert.equal(modal.initial.focused, modal.expected.focused);
assert.equal(modal.events.filter(event => event.kind === 'boundary').length, modal.expected.blockedBoundaries);
const boundary = byId['focus-content-to-rail-boundary'];
assert.equal(boundary.initial.containers[boundary.events[0].to][0], boundary.expected.focused);
assert.match(focusAuthority, /PorticoFocusContainerReplace\(container, semanticIds\)/);
assert.match(focusAuthority, /if not PorticoScreenAuthorityContains\(authority, target\) then target = fallbackId/);
assert.match(focusAuthority, /if authority\.modalContainerId <> "" and nextId <> authority\.modalContainerId then return ""/);
assert.match(focusAuthority, /target = authority\.modalInvokerId[\s\S]*PorticoFocusTraceRecord\(authority\.trace, "modal-close"/);

const five = byId['player-five-transport-to-utilities'];
let transportIndex = five.expected.transportOrder.indexOf(five.initial.focused.replace('player.transport.', ''));
let playerContainer = five.initial.container;
for (const event of five.events) {
  if (event.kind === 'right' && transportIndex + 1 < five.expected.transportOrder.length) transportIndex += 1;
  else if (event.kind === 'right') playerContainer = 'utility';
}
assert.equal(playerContainer, five.expected.container);
assert.equal(five.expected.focused, 'player.utility.volume');
const liveTransport = playerPresenter.match(/controlIds = \[([^\]]+)\]/)?.[1].match(/"([^"]+)"/g).map(value => value.slice(1, -1));
assert.deepEqual(liveTransport, five.expected.transportOrder, 'shared transport order must match the live Roku presenter');
const buildUtilities = player.match(/sub PorticoPlayerBuildUtilities\(\)[\s\S]*?\nend sub/)?.[0] ?? '';
const liveUtilityOrder = [...buildUtilities.matchAll(/dockTargets\.push\(\{kind: "([^"]+)"/g)].map(match => match[1]);
assert.deepEqual(liveUtilityOrder, five.expected.utilityOrder, 'shared utility order must match the live capability-gated Roku dock');
assert.match(player, /focusedControl = 0[\s\S]*PorticoPlayerEmit\("previous"/);
assert.match(playbackTask, /kind = "previous" or kind = "remote-previous"[\s\S]*PorticoPlaybackAdvancePrevious\(controller\)/);
for (const id of ['player-back-unwinds-panel-before-exit', 'player-audio-back-returns-to-browsing']) {
  const vector = byId[id];
  assert.equal(vector.expected.outcomes.length, vector.events.length, id);
}

assert.deepEqual(fixture.auditTrace.map(item => item.issue), ['RK-31', 'RK-33', 'RK-34', 'RK-35', 'RK-36', 'RK-37', 'RK-38', 'RK-39', 'RK-40']);
console.log(`Verified ${fixture.cases.length} platform-neutral TV interaction outcomes and ${fixture.auditTrace.length} Roku audit traces.`);
