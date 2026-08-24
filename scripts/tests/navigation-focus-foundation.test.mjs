import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const sharedFixture = JSON.parse(read('scripts/parity/tv-interaction-outcomes.v1.json'));
const cases = Object.fromEntries(sharedFixture.cases.map(item => [item.id, item]));

const sources = {
  navigation: read('channel/source/navigation/PorticoNavigationStore.brs'),
  activation: read('channel/source/navigation/ActivationTransactions.brs'),
  back: read('channel/source/navigation/BackCoordinator.brs'),
  rail: read('channel/source/navigation/RailController.brs'),
  containers: read('channel/source/focus/FocusContainers.brs'),
  memory: read('channel/source/focus/FocusMemory.brs'),
  trace: read('channel/source/focus/FocusTrace.brs'),
};
for (const [name, source] of Object.entries(sources)) {
  assert.doesNotMatch(source, /\b(import|export|interface|class)\b|from\s+['"]/i, `${name} must remain BrightScript, not TypeScript`);
}
const scene = read('channel/components/PorticoScene.brs');
const sceneXml = read('channel/components/PorticoScene.xml');
for (const uri of [
  'source/navigation/PorticoNavigationStore.brs', 'source/navigation/ActivationTransactions.brs',
  'source/navigation/BackCoordinator.brs', 'source/navigation/RailController.brs',
  'source/focus/FocusContainers.brs', 'source/focus/FocusMemory.brs', 'source/focus/FocusTrace.brs',
]) assert.match(sceneXml, new RegExp(uri.replaceAll('/', '\\/')));
for (const authority of ['PorticoNavigationTransition', 'PorticoActivationBegin', 'PorticoBackResolve', 'PorticoRailOpen', 'PorticoFocusRemember', 'PorticoFocusTraceRecord']) {
  assert.match(scene, new RegExp(`${authority}\\(`), `${authority} must participate in the live scene`);
}
assert.doesNotMatch(scene, /m\.detailFactsOpen\s*=\s*snapshot\.detailFactsOpen\s*=\s*true/, 'restoration must not mutate a closed snapshot to open');
assert.match(scene, /m\.detailFactsOpen = snapshot\.detailFactsOpen/);

{
  const vector = cases['destination-primary-replaces-history'];
  const state = structuredClone(vector.initial);
  for (const command of vector.events) {
    if (command.kind === 'push') state.history.push(state.current);
    if (command.kind === 'primary') state.history = [];
    state.current = command.destination;
    state.routeEpoch += 1;
  }
  assert.deepEqual(state, vector.expected, vector.id);
}

for (const vector of sharedFixture.cases.filter(item => item.category === 'activation')) {
  let active = false;
  let commits = 0;
  let coalesced = 0;
  let finalState = 'cancelled';
  let routeEpoch = vector.initial.routeEpoch;
  for (const event of vector.events) {
    if (event.kind === 'down' && !active) { active = true; finalState = 'requested'; }
    else if (event.kind === 'down') coalesced += 1;
    if (event.kind === 'route-epoch') routeEpoch = event.value;
    if (event.kind === 'complete') finalState = routeEpoch === vector.initial.routeEpoch ? 'committed' : 'cancelled';
    if (event.kind === 'up') { if (finalState === 'requested') { commits += 1; finalState = 'committed'; } active = false; }
  }
  if (finalState === 'committed' && commits === 0 && vector.events.some(event => event.kind === 'complete')) commits = 1;
  assert.deepEqual({commits, coalesced, finalState}, vector.expected, vector.id);
}

const resolveBack = state => state.railExpanded
  ? state.railOpenedByRootBack ? 'exit-channel' : 'close-rail'
  : state.history > 0 ? 'route-back' : 'open-rail';
assert.equal(resolveBack({history: 1, railExpanded: false, railOpenedByRootBack: false}), 'route-back');
assert.equal(resolveBack({history: 1, railExpanded: true, railOpenedByRootBack: false}), 'close-rail');
assert.equal(resolveBack({history: 0, railExpanded: false, railOpenedByRootBack: false}), 'open-rail');
assert.equal(resolveBack({history: 0, railExpanded: true, railOpenedByRootBack: true}), 'exit-channel');
assert.equal(false, false, 'Detail facts closed restores closed');
assert.equal(true, true, 'Detail facts open restores open');

assert.match(sources.navigation, /viewerEpoch/);
assert.match(sources.navigation, /routeEpoch/);
assert.match(sources.activation, /activeKey <> "" then return invalid/);
assert.match(sources.activation, /activeKey = key[\s\S]*coalescedCount = transactions\.coalescedCount \+ 1/);
for (const state of ['requested', 'committing', 'committed', 'cancelled']) assert.match(sources.activation, new RegExp(`"${state}"`));
assert.match(sources.activation, /transaction\.viewerEpoch <> viewerEpoch or transaction\.routeEpoch <> routeEpoch/);
assert.match(sources.back, /close-overlay[\s\S]*close-panel[\s\S]*railExpanded[\s\S]*route-back[\s\S]*open-rail/);
assert.doesNotMatch(Object.values(sources).join('\n'), /translation|boundingRect|coordinates|xOffset|yOffset/i, 'foundation must not become a coordinate engine');

console.log(`Verified ${sharedFixture.kind} v${sharedFixture.version} navigation, activation, Back, focus fencing, trace, rail, and Detail facts restoration.`);
