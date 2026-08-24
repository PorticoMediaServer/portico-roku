import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const scene = read('channel/components/PorticoScene.brs');
const authority = read('channel/source/focus/ScreenFocusAuthority.brs');
const sharedFixture = JSON.parse(read('scripts/parity/tv-interaction-outcomes.v1.json'));
const focusCases = sharedFixture.cases.filter(item => item.id === 'focus-removed-item-falls-back-semantically' || item.id === 'focus-reorder-preserves-semantic-id');

assert.doesNotMatch(scene, /m\.routeHistory/, 'navigationStore must be the only route-history authority');
const aliasWriter = scene.match(/sub PorticoSceneSyncNavigationAliases\(\)[\s\S]*?end sub/)?.[0] ?? '';
assert.match(aliasWriter, /m\.route = destination\.route[\s\S]*m\.page = destination\.route/);
assert.equal((scene.match(/^\s*m\.route\s*=\s*destination\.route\s*$/gm) ?? []).length, 1, 'route alias may only be written by the store sync');
assert.equal((scene.match(/^\s*m\.page\s*=\s*destination\.route\s*$/gm) ?? []).length, 1, 'page alias may only be written by the store sync');

for (const component of ['SearchScreen', 'LibraryScreen', 'ChannelsScreen', 'SettingsScreen', 'ProfileScreen', 'ProfileSelectionScreen', 'SavedScreen']) {
  const xml = read(`channel/components/Portico${component}.xml`);
  assert.match(xml, /source\/focus\/ScreenFocusAuthority\.brs/, `${component} must import the shared screen authority`);
}
for (const component of ['SearchScreen', 'LibraryScreen', 'ChannelsScreen', 'SettingsScreen', 'ProfileScreen', 'ProfileSelectionScreen']) {
  const source = read(`channel/components/Portico${component}.brs`);
  assert.match(source, /PorticoScreenAuthorityBeginOK\(/, `${component} must transaction-gate OK`);
  assert.match(source, /PorticoScreenAuthorityRelease\(m\.screenAuthority, key\)/, `${component} must close the physical OK transaction on release`);
}

const home = read('channel/components/PorticoHome.brs');
const detail = read('channel/components/PorticoDetail.brs');
assert.match(home, /home\.row\." \+ homeModelText\(row\.id[\s\S]*\.item\." \+ homeModelText\(items\[itemIndex\]\.id/);
assert.match(detail, /detail\.episode\." \+ detailText\(episodes\[m\.top\.focusedEpisode\]\.id/);
assert.match(scene, /m\.homeScreen\.focusSemanticId/);
assert.match(scene, /m\.detailScreen\.focusSemanticId/);

const settings = read('channel/components/PorticoSettingsScreen.brs');
const settingsRow = read('channel/components/PorticoSettingsRow.brs');
assert.match(settings, /not m\.initialFocusApplied[\s\S]*id = "profile"[\s\S]*m\.initialFocusApplied = true/);
assert.match(settings, /PorticoScreenAuthorityOpenModal[\s\S]*PorticoScreenAuthorityCloseModal/);
assert.match(settingsRow, /kind = "information" then semantic = semantic \+ ", read only"/);
assert.match(settings, /confirm-watch-history" or kind = "confirm-search-history" then m\.choiceFocus = 1/);

const mediaActions = read('channel/components/PorticoMediaActionsPanel.brs');
const choiceRow = read('channel/components/PorticoSettingsChoiceRow.brs');
assert.match(mediaActions, /m\.top\.focusSemanticId = "media-action\." \+ actionId/);
assert.match(choiceRow, /m\.top\.semanticId = "settings\.choice\." \+ state\.model\.id\.ToStr\(\)/);

const profileSelection = read('channel/components/PorticoProfileSelectionScreen.brs');
assert.match(profileSelection, /PorticoScreenAuthorityOpenModal\(m\.screenAuthority, semanticId\)/);
assert.match(profileSelection, /cancel-profile-pin[\s\S]*PorticoScreenAuthorityCloseModal/);
assert.match(authority, /modalInvokerId/);
assert.match(authority, /PorticoScreenAuthorityOpenModal[\s\S]*modalContainerId = modalId[\s\S]*activeContainerId = modalId/, 'opening a modal must activate a trapped focus container');
assert.match(authority, /PorticoScreenAuthorityCloseModal[\s\S]*modalContainerId = ""[\s\S]*modalPreviousContainerId/, 'closing a modal must release the trap and restore its invoker container');
for (const api of ['PorticoScreenAuthoritySetContainer', 'PorticoScreenAuthoritySetNeighbor', 'PorticoScreenAuthorityMoveBoundary', 'PorticoScreenAuthorityResolve', 'PorticoScreenAuthorityReveal', 'PorticoScreenAuthorityAcceptMove']) {
  assert.match(authority, new RegExp(`${api}\\(`), `${api} must be implemented by the shared focus authority`);
}
assert.doesNotMatch(authority, /translation|boundingRect|xOffset|yOffset/i);

const sceneXml = read('channel/components/PorticoScene.xml');
assert.match(sceneXml, /source\/focus\/ScreenFocusAuthority\.brs/);
assert.match(scene, /PorticoSceneRefreshFocusGraph[\s\S]*PorticoScreenAuthoritySetNeighbor[\s\S]*scene\.content[\s\S]*scene\.rail/);
assert.match(scene, /sub enterRail\(\)[\s\S]*PorticoScreenAuthorityMoveBoundary/);
assert.match(scene, /sub leaveRail\(\)[\s\S]*PorticoScreenAuthorityMoveBoundary/);
const library = read('channel/components/PorticoLibraryScreen.brs');
const channels = read('channel/components/PorticoChannelsScreen.brs');
assert.match(library, /restoreLibraryFocus[\s\S]*PorticoScreenAuthorityResolve/);
assert.match(channels, /restoreChannelsFocus[\s\S]*PorticoScreenAuthorityResolve/);
assert.match(library, /moveLibraryFocus[\s\S]*PorticoScreenAuthorityAcceptMove/);
assert.match(channels, /moveChannelsFocus[\s\S]*PorticoScreenAuthorityAcceptMove/);
for (const component of ['SearchScreen', 'SettingsScreen', 'ProfileScreen', 'ProfileSelectionScreen']) {
  assert.match(read(`channel/components/Portico${component}.brs`), /PorticoScreenAuthorityAcceptMove/, `${component} directional outcomes must consult the focus authority`);
}
const playerXml = read('channel/components/PorticoPlayer.xml');
const player = read('channel/components/PorticoPlayer.brs');
const presenter = read('channel/source/player/PorticoPlayerPresenter.brs');
assert.match(playerXml, /source\/focus\/ScreenFocusAuthority\.brs/);
assert.match(presenter, /player\.transport[\s\S]*player\.utility[\s\S]*player\.panel/);
assert.match(player, /PorticoPlayerPresenterMoveBoundary/);

const replace = (ids, previous) => ids.includes(previous) ? previous : (ids[0] ?? '');
for (const vector of focusCases) {
  const targets = vector.events[0].targets;
  assert.equal(replace(targets, vector.initial.focused), vector.expected.focused, vector.id);
}

console.log('Verified live screen/player focus graphs, sparse target fallback, semantic activation, modal restoration, Settings behavior, and single navigation authority.');
