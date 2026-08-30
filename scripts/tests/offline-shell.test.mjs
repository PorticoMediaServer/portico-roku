import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const scene = read('channel/components/PorticoScene.brs');
const sceneXml = read('channel/components/PorticoScene.xml');
const rail = read('channel/components/PorticoRail.brs');
const railXml = read('channel/components/PorticoRail.xml');
const stateScreen = read('channel/components/PorticoStateScreen.brs');
const home = read('channel/components/PorticoHome.brs');
const homeShelf = read('channel/components/PorticoHomeShelf.brs');
const homeShelfXml = read('channel/components/PorticoHomeShelf.xml');
const authGate = read('channel/components/PorticoAuthGate.brs');
const authGateModels = read('channel/source/lib/PorticoAuthGateModels.brs');
const serverSelection = read('channel/components/PorticoServerSelection.brs');
const serverSelectionXml = read('channel/components/PorticoServerSelection.xml');
const serverRow = read('channel/components/PorticoServerRow.brs');
const serverRowXml = read('channel/components/PorticoServerRow.xml');
const main = read('channel/source/main.brs');
const profileController = read('channel/source/lib/PorticoProfileController.brs');
const routes = read('channel/source/core/PorticoRoutes.brs');
const person = read('channel/components/PorticoPersonScreen.brs');
const settings = read('channel/components/PorticoSettingsScreen.brs');
const button = read('channel/components/PorticoButton.brs');

assert.match(sceneXml, /<Group id="designRoot">/);
assert.doesNotMatch(sceneXml, /<PorticoHome id="homeScreen"/);
assert.doesNotMatch(sceneXml, /<PorticoDetail id="detailScreen"/);
assert.match(sceneXml, /<PorticoStateScreen id="stateScreen"/);
assert.doesNotMatch(sceneXml, /<PorticoAuthGate id="authGate"/);
assert.doesNotMatch(sceneXml, /PorticoAccountSetup|accountSetupScreen/);
assert.doesNotMatch(sceneXml, /<PorticoServerSelection id="serverSelectionScreen"/);
assert.match(sceneXml, /<PorticoRail id="rail"/);
assert.match(scene, /PorticoSceneEnsureOverlaySurface\("server-selection"\)/);
assert.match(scene, /PorticoSceneEnsureOverlaySurface\("auth-gate"\)/);
assert.equal((railXml.match(/<PorticoRailItem id="item\d+" \/>/g) ?? []).length, 11);

for (const source of [rail, stateScreen, serverSelection]) {
  assert.doesNotMatch(source, /removeChildrenIndex/);
  assert.doesNotMatch(source, /CreateObject\("roSGNode"/);
}
assert.equal((authGate.match(/CreateObject\("roSGNode"/g) ?? []).length, 1);
assert.match(authGate, /CreateObject\("roSGNode", "StandardKeyboardDialog"\)/);
assert.match(scene, /m\.stateScreen\.viewState/);
assert.match(scene, /m\.rail\.viewState/);
assert.match(rail, /sub applyViewState\(\)/);
assert.match(stateScreen, /sub applyViewState\(\)/);

// Account authentication owns the shell even before a server/viewer exists.
// Server-dependent routes render contextual state while global profile,
// settings, and the explicit server chooser remain reachable from the rail.
assert.match(scene, /if signedInShellAvailableWithoutViewer\(\)[\s\S]*renderSignedInShellWithoutViewer\(\)/);
assert.match(scene, /function signedInShellAvailableWithoutViewer\(\)[\s\S]*selectedServerId[\s\S]*serverStatus = "offline"[\s\S]*profileStatus = "unavailable"[\s\S]*viewerStatus = "transition-failed"/);
const signedInEmptyShell = scene.match(/sub renderSignedInShellWithoutViewer\(\)([\s\S]*?)end sub/)?.[1] ?? '';
assert.match(signedInEmptyShell, /m\.content\.visible = true/);
assert.match(signedInEmptyShell, /m\.railLayer\.visible = not showServerSelection/);
assert.match(signedInEmptyShell, /showProfile = m\.route = "profile"/);
assert.match(signedInEmptyShell, /showSettings = m\.route = "settings"/);
assert.match(signedInEmptyShell, /showServerSelection = m\.route = "server-selection"/);
assert.match(signedInEmptyShell, /m\.stateScreen\.viewState = \{model: routeStateModel\(m\.route\)/);
assert.doesNotMatch(signedInEmptyShell, /PorticoNavigationTransition\(m\.navigationStore, "server-selection"/);

// Ordinary Home restoration uses destination geometry rather than replacing
// the signed-in shell with a generic state screen. Empty descriptors remain
// available to the data layer but never produce visible shelves or focus stops.
assert.match(scene, /showVisualHome = m\.route = "home" and \(homeModel <> invalid or homeShouldReserveContent\(\)\)/);
assert.match(scene, /function reservedHomeModel\(\)[\s\S]*loadStatus: "restoring"/);
assert.match(scene, /sceneArray\(row\.items\)\.count\(\) > 0 then result\.push\(row\)/);
assert.match(home, /m\.rowGroups = \[\]/);
assert.match(home, /for slotIndex = 0 to 2[\s\S]*CreateObject\("roSGNode", "PorticoHomeShelf"\)/);
assert.match(home, /homeModelCards\(row\.items\)\.count\(\) > 0 then result\.push\(row\)/);
assert.match(home, /if items\.count\(\) > 0[\s\S]*rowGroup\.visible = true[\s\S]*else[\s\S]*rowGroup\.visible = false/);
assert.match(home, /CreateObject\("roSGNode", "PorticoHomeShelf"\)/);
assert.match(homeShelfXml, /component name="PorticoHomeShelf"/);
assert.equal((homeShelfXml.match(/<PorticoMediaCard id="card\d"/g) ?? []).length, 7);

// Focus continuity is keyed to server-provided row and media identities rather
// than array positions, and that state is fenced on viewer replacement.
assert.match(scene, /m\.homeFocusedRowId = ""/);
assert.match(scene, /m\.homeFocusedItemIds = \{\}/);
assert.match(scene, /rememberedRowIndex = sceneIndexByStableId\(rows, m\.homeFocusedRowId\)/);
assert.match(scene, /rememberedIndex = sceneIndexByStableId\(items, rememberedItemId\)/);
assert.match(scene, /homeFocusedItemIds: copySceneStringMap\(m\.homeFocusedItemIds\)/);
assert.match(scene, /sub resetViewerPresentation\(\)[\s\S]*m\.homeFocusedRowId = ""[\s\S]*m\.homeFocusedItemIds = \{\}/);

const runtimeChanged = scene.match(/sub runtimeChanged\(\)([\s\S]*?)end sub/)?.[1] ?? '';
assert.ok(runtimeChanged.length > 0);
assert.doesNotMatch(runtimeChanged, /^\s*m\.focusArea\s*=/m);
assert.match(scene, /captureRouteSnapshot/);
assert.match(scene, /restoreRouteSnapshot/);
assert.match(scene, /m\.navigationStore\.history/);
assert.doesNotMatch(scene, /m\.routeHistory/);

assert.match(scene, /navigationSnapshotVerified <> true/);
assert.match(scene, /state\.libraryItems/);
assert.match(main, /navigationSnapshotVerified: false/);
assert.match(main, /libraryItems: \[\]/);
assert.doesNotMatch(scene, /m\.contract\.railLibraryItems/);
assert.match(main, /function PorticoMainPrepareProfileContextChange/);
assert.match(main, /PorticoMainFenceDiscoveryOwners[\s\S]*PorticoPlaybackTransitionFence[\s\S]*PorticoWatchWithFriendsTransitionFence[\s\S]*PorticoEngagementCancel/);
assert.match(main, /if not teardownReady then return[\s\S]*PorticoProfileControllerSynchronize\(profileController, viewerController, bootstrapContext, teardownReady\)/);
assert.match(main, /if teardownKey = profileController\.contextTeardownBlockedKey then return false/);
assert.match(main, /profileController\.contextTeardownBlockedKey = teardownKey[\s\S]*viewerTransitionReason: "profile-context-teardown-failed"/);
assert.match(profileController, /if not teardownReady then return \{changed: false, available: controller\.context <> invalid, code: "profile_context_teardown_required"\}/);

assert.match(authGateModels, /authorizationUserCode/);
assert.match(authGateModels, /verificationDisplayUri/);
assert.doesNotMatch(scene, /deviceCode/);
assert.doesNotMatch(main, /deviceCode/);
assert.ok(!scene.includes('"getportico.tv/device"'));
assert.match(authGate, /PorticoFont\("700", 96\)/);
assert.match(scene, /showAuthGate = not PorticoSceneVisualFixtureEnabled\(\) and not accountIsSignedIn\(\)/);
assert.match(scene, /m\.localAuthScreen = PorticoSceneEnsureOverlaySurface\("local-auth"\)/);
assert.match(scene, /m\.authGate = PorticoSceneEnsureOverlaySurface\("auth-gate"\)/);
assert.match(scene, /m\.content\.visible = false/);
assert.match(scene, /m\.railLayer\.visible = false/);
assert.match(scene, /m\.localAuthScreen\.viewState = m\.top\.runtimeState/);
assert.match(scene, /m\.localAuthScreen\.visible = true/);
assert.match(scene, /m\.authGate\.viewState = PorticoSignedOutGateModel\(m\.top\.runtimeState, m\.signedOutGateMode\)/);
assert.match(scene, /m\.authGate\.visible = true/);
assert.match(scene, /m\.authGate\.setFocus\(true\)[\s\S]*return/);
assert.doesNotMatch(scene, /showAccountSetup|accountSetupModel|route = "account-setup"/);
assert.match(main, /PorticoDeviceAuthorizationHandleActivation\(accountAuthorization, activationData\)/);
assert.match(serverSelectionXml, /<Poster id="scrim" width="1920" height="1080"/);
assert.match(serverSelectionXml, /<Group id="panel" translation="\[1110,90\]">/);
assert.match(serverSelection, /m\.title\.text = "Profile and server"/);
assert.match(serverSelectionXml, /<PorticoIconButton id="closeAction"/);
assert.match(serverSelectionXml, /<Group id="catalogState"/);
assert.match(serverSelectionXml, /<Label id="catalogStatus"/);
assert.match(serverSelectionXml, /<Label id="catalogBody"/);
assert.equal((serverSelectionXml.match(/<PorticoServerRow id="serverRow\d"/g) ?? []).length, 6);
assert.match(serverSelectionXml, /translation="\[0,82\]"/);
assert.match(scene, /iconId: "action\.retry"/);
assert.doesNotMatch(serverSelection, /iconId: "navigation\.settings"/);
assert.match(serverRowXml, /<Poster id="selectionIndicator"/);
assert.doesNotMatch(serverRowXml, /id="selection(?:Ring|Dot)"/);
assert.match(serverRow, /indicatorState = "-selected-focus"/);
assert.match(serverRow, /pkg:\/images\/ui\/server-radio/);
assert.match(scene, /sub focusSelectedServer\(\)[\s\S]*m\.serverFocusedIndex = selectedIndex[\s\S]*clampServerSelectionFocus\(\)/);
assert.match(scene, /showServerSelection = m\.route = "server-selection" and not PorticoSceneVisualFixtureEnabled\(\)/);
assert.match(scene, /if not serverSelectionListReady\(\)[\s\S]*m\.focusArea = "serverActions"/);
assert.match(scene, /serverPickerWasWaiting[\s\S]*focusSelectedServer\(\)[\s\S]*m\.serverPickerWaitingForList = false/);
for (const state of ['loading', 'denied', 'incompatible', 'offline', 'empty']) {
  assert.match(scene, new RegExp(`id: "${state}"`));
}
assert.match(scene, /serverSelectionCatalogState\(\)/);
assert.match(scene, /serverSelectionActions\(\)/);
assert.match(scene, /serverSelectionActionCount\(\)/);
assert.match(scene, /else if m\.focusArea = "serverActions"[\s\S]*serverSelectionListReady\(\)[\s\S]*m\.focusArea = "serverClose"/);
assert.match(serverSelection, /m\.catalogState\.visible = catalogState <> invalid and visibleRows = 0/);
assert.match(serverSelection, /panelHeight = 218 \+ \(contentSlots \* 82\) \+ \(visibleActions \* 82\)/);
assert.match(serverSelection, /pkg:\/images\/ui\/server-panel-compact\.png/);
assert.match(scene, /serverListStatus = "denied"[\s\S]*body = "This Portico Account can't access the server list\."/);
assert.match(scene, /listIsStale[\s\S]*availabilityLabel = "Not checked"/);
assert.match(scene, /if result\.count\(\) >= 500 then exit for/);
assert.match(scene, /selectedId = runtimeValue\("selectedServerId", ""\)[\s\S]*if selectedId <> "" and selectedName <> ""/);
assert.doesNotMatch(scene, /Hosted Services/);
assert.match(scene, /else if m\.focusArea = "serverClose"[\s\S]*navigateBack\(\)/);
assert.match(serverSelection, /lastSpaceIndex = position/);

for (const internalCopy of ['fixture media', 'authentication checks succeed', 'fresh content appears only after', 'Hosted Task', 'in this build', 'Server-scoped credentials', 'Connection diagnostics', 'discovered directly on this local network', 'not advertised by this server', 'securely sign it in', 'server-defined presentation', 'this view does not publish']) {
  assert.ok(!scene.includes(internalCopy), `Visible implementation copy leaked into the shell: ${internalCopy}`);
}
assert.match(scene, /if result\.count\(\) >= 32 then exit for/);
assert.match(home, /firstVisibleRow = m\.top\.focusedRow - 1[\s\S]*lastVisibleRow = firstVisibleRow \+ 2/);
assert.match(person, /firstVisible = m\.focusIndex - 3[\s\S]*visibleIndex = index - firstVisible/);
assert.match(settings, /if row\.actionable <> false then m\.visibleRows\.Push\(index\)/);
assert.match(button, /button-primary-focus\.png/);
assert.match(routes, /allowed = \{home: true, search: true, library: true, channels: true, saved: true, profile: true, settings: true/);
assert.match(scene, /PorticoSceneNormalizeExternalRoute\(request\.route\)/);
assert.match(scene, /emitActivation\("exit-channel", "root-back"\)/);

for (const viewport of [{width: 1920, height: 1080}, {width: 1280, height: 720}]) {
  const scale = viewport.width / 1920;
  const safe = {left: 72 * scale, top: 54 * scale, right: viewport.width - 72 * scale, bottom: viewport.height - 54 * scale};
  for (const rect of [{x: 72, y: 58, width: 850, height: 72}, {x: 144, y: 102, width: 1680, height: 864}]) {
    assert.ok(rect.x * scale >= safe.left && rect.y * scale >= safe.top);
    assert.ok((rect.x + rect.width) * scale <= safe.right && (rect.y + rect.height) * scale <= safe.bottom);
  }
}

console.log('Verified persistent, offline-capable Roku shell invariants.');
