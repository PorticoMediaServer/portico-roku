import {existsSync, readFileSync, readdirSync, statSync} from 'node:fs';
import {extname, join, relative, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const channel = join(root, 'channel');
const contractPath = join(channel, 'data/visual-contract.json');
const contract = JSON.parse(readFileSync(contractPath, 'utf8'));
const parityDirectory = join(channel, 'data/parity');
const releaseIdentity = JSON.parse(readFileSync(join(channel, 'data/release-identity.v1.json'), 'utf8'));
const failures = [];
let assertions = 0;

function assert(condition, message) {
  assertions += 1;
  if (!condition) failures.push(message);
}

function filesUnder(directory) {
  return readdirSync(directory).flatMap(name => {
    const path = join(directory, name);
    return statSync(path).isDirectory() ? filesUnder(path) : [path];
  });
}

function pngSize(path) {
  const data = readFileSync(path);
  assert(data.subarray(1, 4).toString() === 'PNG', `${relative(root, path)} is not a PNG`);
  return {width: data.readUInt32BE(16), height: data.readUInt32BE(20), colorType: data[25]};
}

function assertPng(relativePath, width, height, requireAlpha = false) {
  const path = join(channel, relativePath);
  assert(existsSync(path), `${relativePath} is missing`);
  if (!existsSync(path)) return;
  const size = pngSize(path);
  assert(size.width === width && size.height === height, `${relativePath} must be ${width}x${height}; found ${size.width}x${size.height}`);
  if (requireAlpha) assert(size.colorType === 4 || size.colorType === 6, `${relativePath} must contain an alpha channel`);
}

assert(contract.canvas.width === 1920 && contract.canvas.height === 1080, 'Canvas must remain exactly 1920x1080');
assert(contract.rail.x === 24 && contract.rail.y === 24, 'Rail origin must remain 24,24');
assert(contract.rail.collapsedWidth === 80 && contract.rail.expandedWidth === 280, 'Rail widths must remain 80/280');
assert(contract.rail.contentX === 136 && contract.rail.expandedContentTranslation === 200, 'Content datum/translation must remain 136/200');
assert(contract.hero.homeHeight === 430 && contract.hero.detailHeight === 570, 'Home/Detail heroes must remain 430/570');
assert(contract.hero.titleSize === 66 && contract.hero.metaSize === 22 && contract.hero.summarySize === 23, 'Home hero type overrides must remain 66/22/23');
assert(contract.controls.height === 64 && contract.controls.focusBorder === 3, 'Controls must retain 64px height and allocated 3px focus border');
assert(contract.shelf.cardWidth === 214 && contract.shelf.cardHeight === 395 && contract.shelf.artworkWidth === 202 && contract.shelf.artworkHeight === 321, 'Poster envelope/interior must remain 214x395 / 202x321');
assert(contract.shelf.landscapeCardWidth === 320 && contract.shelf.landscapeCardHeight === 248 && contract.shelf.landscapeArtworkWidth === 308 && contract.shelf.landscapeArtworkHeight === 180, 'Landscape envelope/interior must remain 320x248 / 308x180');
assert(contract.shelf.cardGap === 18 && contract.shelf.rowGap === 42, 'Shelf/card spacing must remain 18/42');
assert(contract.colors.projector === '#070B10' && contract.colors.focus === '#EAF6FF' && contract.colors.screenBlueStrong === '#70BCE8', 'Core Portico colors changed');
const railItems = [
  ...(contract.railPrimaryItems ?? []),
  ...(contract.railLibraryItems ?? []),
  ...(contract.railBottomItems ?? [])
];
const semanticIcons = JSON.parse(readFileSync(join(channel, 'data/generated/roku-icons.v1.json'), 'utf8'));
assert(railItems.length > 0, 'Rail must declare navigation destinations');
assert((contract.railLibraryItems ?? []).length <= 4, 'Rail may expose at most four library destinations');
assert(!railItems.some(item => ['Scenarios', 'Downloads', 'Cast'].includes(item.label)), 'Rail contains a removed prototype-only destination');
for (const item of railItems) {
  assert(typeof item.id === 'string' && item.id.length > 0, `Rail item ${item.label ?? '<unlabelled>'} is missing its stable id`);
  assert(typeof item.route === 'string' && item.route.length > 0, `Rail item ${item.label ?? '<unlabelled>'} is missing its route`);
  assert(typeof item.iconId === 'string' && item.iconId.length > 0, `Rail item ${item.label ?? '<unlabelled>'} is missing its semantic icon id`);
  const master = semanticIcons.semanticToMaster[item.iconId];
  assert(master, `Rail semantic icon is unknown: ${item.iconId}`);
  for (const state of ['default', 'dark-background', 'rail', 'selected']) assert(existsSync(join(channel, `images/icons/generated/${semanticIcons.masters[master][state].path}`)), `Rail icon state is missing: ${item.iconId} ${state}`);
}
assert(contract.railLibraryItems.find(item => item.id === 'music')?.iconId === 'media.music', 'Music must use the approved semantic media icon');

const manifestPath = join(channel, 'manifest');
const manifest = readFileSync(manifestPath, 'utf8');
assert(manifest.endsWith('\n'), 'Manifest must end with a newline');
assert(manifest.includes('ui_resolutions=fhd'), 'Manifest must declare FHD');
assert(manifest.includes('rsg_version=1.3'), 'Manifest must declare the certification-target SceneGraph version');
assert(manifest.includes('splash_screen_fhd=pkg:/images/ui/splash-fhd.jpg'), 'Manifest splash reference is missing');
assert(releaseIdentity.schemaVersion === 1 && releaseIdentity.status === 'development-sideload', 'Source Roku identity must remain an explicit development sideload contract');
assert(releaseIdentity.publisherId === null && releaseIdentity.channelId === null && releaseIdentity.signingIdentity === null, 'Source Roku identity must not contain unreviewed publisher or signing values');
for (const required of [
  'tvos-roku-acceptance-matrix.v1.json',
  'parity-exceptions.v1.json',
  'remote-accessibility.v1.json',
  'error-recovery.v1.json',
  'roku-hardware-instrumentation.v1.json',
  'roku-diagnostics.v1.json'
]) assert(existsSync(join(parityDirectory, required)), `Parity contract is missing: ${required}`);

const deviceHelperPath = join(root, 'scripts/device/roku-device.mjs');
const deviceHelper = readFileSync(deviceHelperPath, 'utf8');
assert(!/(?:192\.168\.|10\.\d+\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(deviceHelper), 'Device helper must not contain a hard-coded private-network address');
assert(!/ROKU_DEV_PASSWORD\s*=\s*["'][^"']+["']/.test(deviceHelper), 'Device helper must not contain a developer password');
assert(deviceHelper.includes("spawnSync('curl', ['--config', '-']"), 'Device helper must pass curl credentials through standard input');

for (const required of [
  'components/PorticoScene.xml',
  'components/PorticoSearchScreen.xml',
  'components/PorticoSearchScreen.brs',
  'components/PorticoSearchResult.xml',
  'components/PorticoSearchKey.xml',
  'components/PorticoLibraryScreen.xml',
  'components/PorticoLibraryScreen.brs',
  'components/PorticoBrowseCard.xml',
  'components/PorticoBrowseListRow.xml',
  'components/PorticoBrowseTile.xml',
  'components/PorticoBrowseTab.xml',
  'components/PorticoBrowseAction.xml',
  'components/PorticoRail.xml',
  'components/PorticoRailItem.xml',
  'components/PorticoButton.xml',
  'components/PorticoIconButton.xml',
  'components/PorticoMediaCard.xml',
  'components/PorticoHome.xml',
  'components/PorticoDetail.xml',
  'components/PorticoStateScreen.xml',
  'components/PorticoAuthGate.xml',
  'components/PorticoAuthAction.xml',
  'components/PorticoServerSelection.xml',
  'components/PorticoServerRow.xml',
  'components/PorticoDeviceAuthorizationTask.xml',
  'components/PorticoServerCatalogTask.xml',
  'components/PorticoServerConnectionTask.xml',
  'components/PorticoContentTask.xml',
  'components/PorticoPlaybackTask.xml',
  'components/PorticoHttpTask.xml',
  'source/lib/PorticoDeviceAuthorization.brs',
  'source/lib/PorticoAuthGateModels.brs',
  'source/lib/PorticoServerCatalog.brs',
  'source/lib/PorticoServerConnection.brs',
  'source/lib/PorticoContent.brs',
  'source/lib/PorticoContentModels.brs',
  'source/lib/PorticoPlayback.brs',
  'source/lib/PorticoPlaybackModels.brs',
  'source/lib/PorticoSignedDocuments.brs',
  'source/lib/PorticoHttpConstants.brs',
  'source/lib/PorticoHttpHelpers.brs',
  'source/lib/PorticoSecureRegistry.brs',
  'fonts/manrope-400.ttf',
  'fonts/manrope-500.ttf',
  'fonts/manrope-600.ttf',
  'fonts/manrope-700.ttf',
  'fonts/OFL.txt',
  'images/icons/LICENSE-lucide.txt'
]) assert(existsSync(join(channel, required)), `${required} is missing`);

const sourceFiles = filesUnder(channel).filter(path => ['.brs', '.xml', '.json'].includes(extname(path)) || path.endsWith('/manifest'));
const source = sourceFiles.map(path => readFileSync(path, 'utf8')).join('\n');
const sceneSource = readFileSync(join(channel, 'components/PorticoScene.brs'), 'utf8');
const sceneXml = readFileSync(join(channel, 'components/PorticoScene.xml'), 'utf8');
const developmentSceneXml = readFileSync(join(channel, 'development/PorticoScene.xml'), 'utf8');
const serverSelectionXml = readFileSync(join(channel, 'components/PorticoServerSelection.xml'), 'utf8');
const railSource = readFileSync(join(channel, 'components/PorticoRail.brs'), 'utf8');
const railXml = readFileSync(join(channel, 'components/PorticoRail.xml'), 'utf8');
const stateScreenSource = readFileSync(join(channel, 'components/PorticoStateScreen.brs'), 'utf8');
const authGateSource = readFileSync(join(channel, 'components/PorticoAuthGate.brs'), 'utf8');
const authGateModelsSource = readFileSync(join(channel, 'source/lib/PorticoAuthGateModels.brs'), 'utf8');
const mainSource = readFileSync(join(channel, 'source/main.brs'), 'utf8');
const authorizationBridgeSource = readFileSync(join(channel, 'source/lib/PorticoDeviceAuthorization.brs'), 'utf8');
const authorizationTaskSource = readFileSync(join(channel, 'components/PorticoDeviceAuthorizationTask.brs'), 'utf8');
const authorizationTaskXml = readFileSync(join(channel, 'components/PorticoDeviceAuthorizationTask.xml'), 'utf8');
const httpTaskSource = readFileSync(join(channel, 'components/PorticoHttpTask.brs'), 'utf8');
const httpTaskXml = readFileSync(join(channel, 'components/PorticoHttpTask.xml'), 'utf8');
const serverCatalogTaskSource = readFileSync(join(channel, 'components/PorticoServerCatalogTask.brs'), 'utf8');
const serverCatalogTaskXml = readFileSync(join(channel, 'components/PorticoServerCatalogTask.xml'), 'utf8');
const serverCatalogBridgeSource = readFileSync(join(channel, 'source/lib/PorticoServerCatalog.brs'), 'utf8');
const serverConnectionTaskSource = readFileSync(join(channel, 'components/PorticoServerConnectionTask.brs'), 'utf8');
const serverConnectionTaskXml = readFileSync(join(channel, 'components/PorticoServerConnectionTask.xml'), 'utf8');
const serverConnectionBridgeSource = readFileSync(join(channel, 'source/lib/PorticoServerConnection.brs'), 'utf8');
const contentTaskSource = readFileSync(join(channel, 'components/PorticoContentTask.brs'), 'utf8');
const contentTaskXml = readFileSync(join(channel, 'components/PorticoContentTask.xml'), 'utf8');
const contentBridgeSource = readFileSync(join(channel, 'source/lib/PorticoContent.brs'), 'utf8');
const contentModelSource = readFileSync(join(channel, 'source/lib/PorticoContentModels.brs'), 'utf8');
const playbackTaskSource = readFileSync(join(channel, 'components/PorticoPlaybackTask.brs'), 'utf8');
const playbackTaskXml = readFileSync(join(channel, 'components/PorticoPlaybackTask.xml'), 'utf8');
const playbackBridgeSource = readFileSync(join(channel, 'source/lib/PorticoPlayback.brs'), 'utf8');
const playbackModelSource = readFileSync(join(channel, 'source/lib/PorticoPlaybackModels.brs'), 'utf8');
const signedDocumentSource = readFileSync(join(channel, 'source/lib/PorticoSignedDocuments.brs'), 'utf8');
assert(!/"summaryLines"\s*:/.test(source), 'Runtime UI data must not depend on fixture-authored summaryLines');
assert(source.includes('function PorticoBreakText(') && source.includes('function PorticoGlyphWidths(') && source.includes('units * size) / 2000'), 'Render-thread text must use the packaged Manrope glyph-advance tables');
const nodeHelperSource = readFileSync(join(channel, 'source/PorticoNodes.brs'), 'utf8');
assert(!/roFontRegistry|GetOneLineWidth/.test(nodeHelperSource), 'Render-thread helpers must not create Main/Task-only font measurement components');
assert(source.includes('id="activation"') && source.includes('id="routeRequested"'), 'Scene must expose explicit action and route events');
assert(source.includes('homeFocusedIndices') && source.includes('detailFocusedAction') && source.includes('focusBeforeRail'), 'Scene must preserve per-row, Detail-action, and rail-return focus state');
assert(sceneSource.includes('homeActionIds(activeHomeModel()).count()') && sceneSource.includes('nextHomeRowIndex(m.homeFocusedRow)') && source.includes('function homeScrollOffset(rows as object, hasHero as boolean)') && source.includes('m.rows.translation = [0, scrollY]'), 'Home traversal must follow the active model actions and available rows');
assert(sceneSource.includes('sub activateRail()') && sceneSource.includes('m.focusArea = m.focusBeforeRail'), 'Rail activation and exact prior focus restoration must remain explicit');
assert(sceneSource.includes('episodes = detailEpisodes(activeDetailModel())') && sceneSource.includes('sceneMoveIndex(m.focusedEpisode, detailEpisodes(model).count(), direction)') && sceneSource.includes('m.focusedEpisode >= episodes.count() then return'), 'Detail episode traversal must follow the runtime row length');
assert(source.includes('id="fallbackBed"') && source.includes('id="fallbackIcon"') && source.includes('id="artworkCorners"'), 'Media cards must own recess, ImageOff, and rounded-artwork fallback layers');
assert(source.includes('observeField("loadStatus", "onArtworkLoadStatus")'), 'Artwork fallback must respond to Roku Poster load failure');
const lazySceneTags = [
  'PorticoDeviceAuthorizationTask',
  'PorticoLocalAuthTask',
  'PorticoServerCatalogTask',
  'PorticoServerConnectionTask',
  'PorticoContentTask',
  'PorticoSearchTask',
  'PorticoLibraryTask',
  'PorticoSavedTask',
  'PorticoLiveTvTask',
  'PorticoPlaybackTask',
  'PorticoWatchWithFriendsTask',
  'PorticoEngagementTask',
  'PorticoApplicationEventsTask',
  'PorticoPlaybackEventsTask',
  'PorticoProfileTask',
  'PorticoViewerPreferencesTask',
  'PorticoHttpTask',
  'PorticoHome',
  'PorticoDetail',
  'PorticoSearchScreen',
  'PorticoPersonScreen',
  'PorticoLibraryScreen',
  'PorticoSavedScreen',
  'PorticoChannelsScreen',
  'PorticoProfileScreen',
  'PorticoSettingsScreen',
  'PorticoPlayer',
  'PorticoDetailMoreScreen',
  'PorticoHomeCustomizeOverlay',
  'PorticoDetailSeasonOverlay',
  'PorticoWatchWithFriendsOverlay',
  'PorticoImportantNotice',
  'PorticoFeedbackOverlay',
  'PorticoServerSelection',
  'PorticoProfileSelectionScreen',
  'PorticoAuthGate',
  'PorticoLocalAuthScreen'
];
for (const [variant, document] of [['release', sceneXml], ['development', developmentSceneXml]]) {
  assert(document.includes('<Group id="designRoot">') && document.includes('<Group id="content"') && document.includes('<PorticoRail id="rail"') && document.includes('<PorticoStateScreen id="stateScreen"'), `${variant} Scene must keep only the static frame, rail, and state surface mounted`);
  for (const tag of lazySceneTags) assert(!new RegExp(`<${tag}\\b`).test(document), `${variant} Scene must lazy-own ${tag}`);
}
assert(
  sceneSource.includes('function PorticoSceneCreateSurface(') &&
    sceneSource.includes('function PorticoSceneEnsureRouteSurface(') &&
    sceneSource.includes('function PorticoSceneEnsureOverlaySurface(') &&
    sceneSource.includes('sub PorticoSceneReleaseInactiveRouteSurfaces(') &&
    sceneSource.includes('sub PorticoSceneReleaseClosedOverlays(') &&
    sceneSource.includes('parent.removeChild(node)') &&
    sceneSource.includes('m.surfaceGeneration = m.surfaceGeneration + 1') &&
    !sceneSource.includes('removeChildrenIndex'),
  'Scene must own lazy surface creation and explicit inactive/closed cleanup',
);
assert(
  ![railSource, stateScreenSource].some(value => value.includes('removeChildrenIndex') || value.includes('CreateObject("roSGNode"')) &&
    sceneSource.includes('sub PorticoSceneReleaseNode(') &&
    sceneSource.includes('node.privateContent = invalid'),
  'Persistent frame components must remain in-place while released player surfaces clear private content',
);
assert((railXml.match(/<PorticoRailItem id="item\d+" \/>/g) ?? []).length === 11, 'Rail must preallocate all 5 primary, 4 library, and 2 bottom item nodes');
assert(sceneSource.includes('m.stateScreen.viewState') && railSource.includes('sub applyViewState()') && stateScreenSource.includes('sub applyViewState()'), 'Persistent shell components must receive in-place view-state updates');
for (const route of ['home', 'search', 'library', 'channels', 'saved', 'profile', 'settings']) {
  assert(source.includes(`route = "${route}"`), `Local shell is missing the ${route} route`);
}
assert(source.includes('function PorticoSceneVisualFixtureEnabled()') && mainSource.includes('serverStatus: "not-connected"'), 'Fixture media must be compile-time gated while the default runtime remains honestly disconnected');
assert(mainSource.includes('navigationSnapshotVerified: false') && mainSource.includes('libraryItems: []'), 'Default runtime must not expose fixture library shortcuts');
assert(sceneSource.includes('state.navigationSnapshotVerified <> true') && sceneSource.includes('state.libraryItems'), 'Library shortcuts must require a verified runtime navigation snapshot');
assert(sceneSource.includes('m.navigationStore') && sceneSource.includes('PorticoNavigationTransition') && !sceneSource.includes('m.routeHistory'), 'Transient and internal routes must use the single navigation-store history authority');
const runtimeChangedBody = sceneSource.match(/sub runtimeChanged\(\)([\s\S]*?)end sub/)?.[1] ?? '';
assert(runtimeChangedBody.length > 0 && !/^\s*m\.focusArea\s*=/m.test(runtimeChangedBody), 'Runtime-state changes must not steal focus');
assert(sceneSource.includes('if m.designRoot = invalid then return invalid') && sceneSource.includes('PorticoSceneCreateSurface("PorticoServerSelection", "serverSelectionScreen", m.designRoot') && sceneSource.includes('parent.appendChild(node)'), 'Server picker must be lazily appended over the complete shell');
assert(sceneSource.includes('sub focusSelectedServer()') && sceneSource.includes('if not serverSelectionListReady()') && sceneSource.includes('serverPickerWasWaiting'), 'Server picker must reveal the selected server and recover focus across list-state changes');
assert(sceneSource.includes('showServerSelection = m.route = "server-selection" and not PorticoSceneVisualFixtureEnabled()') && sceneSource.includes('function serverSelectionCatalogState()') && serverSelectionXml.includes('id="catalogState"'), 'Server-picker loading and failure states must remain inside the modal');
assert(sceneSource.includes('m.focusArea = "serverActions"') && sceneSource.includes('m.focusArea = "serverClose"') && sceneSource.includes('serverSelectionActionCount()'), 'Server-picker state focus must remain trapped between modal actions and Close');
assert(sceneSource.includes('if result.count() >= 500 then exit for'), 'Server picker must not truncate the catalog below its bounded 500-membership contract');
assert(sceneSource.includes('serverListStatus = "denied"') && sceneSource.includes('This Portico Account can\'t access the server list.') && !sceneSource.includes('Hosted Services'), 'Server picker denied and compatibility copy must stay user-facing');
assert(source.includes('start-account-setup') && source.includes("Portico couldn't start account sign-in.") && source.includes('No reachable Portico server was found'), 'Signed-out gate must preserve honest Account and Local Auth availability');
assert(authGateModelsSource.includes('authorizationUserCode') && authGateModelsSource.includes('verificationDisplayUri') && !sceneSource.includes('deviceCode') && !mainSource.includes('deviceCode'), 'Scene/UI state must receive only the display user code, never the polling secret');
assert(authGateSource.includes('PorticoFont("700", 96)') && sceneSource.includes('m.authGate.viewState'), 'Account authorization must use the full-screen 10-foot auth-gate composition');
assert(authorizationTaskXml.includes('field id="command"') && authorizationTaskXml.includes('field id="projection"') && !/field id="(?:request|result|deviceCode|accessToken|refreshToken)"/i.test(authorizationTaskXml), 'Authorization Task public fields must remain secret-free');
assert(authorizationTaskXml.includes('uri="pkg:/components/PorticoDeviceAuthorizationTask.brs"'), 'Authorization Task must stay top-level so Roku OS registers it at runtime');
assert(httpTaskXml.includes('uri="pkg:/components/PorticoHttpTask.brs"'), 'Generic HTTP Task must stay top-level so Roku OS registers it at runtime');
assert(serverCatalogTaskXml.includes('uri="pkg:/components/PorticoServerCatalogTask.brs"'), 'Server Catalog Task must stay top-level so Roku OS registers it at runtime');
assert(serverConnectionTaskXml.includes('uri="pkg:/components/PorticoServerConnectionTask.brs"'), 'Server Connection Task must stay top-level so Roku OS registers it at runtime');
assert(
  authorizationBridgeSource.includes('CreateObject("roSGNode", "PorticoDeviceAuthorizationTask")') &&
    serverCatalogBridgeSource.includes('CreateObject("roSGNode", "PorticoServerCatalogTask")') &&
    serverConnectionBridgeSource.includes('CreateObject("roSGNode", "PorticoServerConnectionTask")') &&
    contentBridgeSource.includes('CreateObject("roSGNode", "PorticoContentTask")') &&
    !sceneXml.includes('id="httpTaskRegistrationAnchor"') &&
    !developmentSceneXml.includes('id="httpTaskRegistrationAnchor"'),
  'Credential-owning Tasks must be created by their owning bridges, not retained as root Scene anchors',
);
assert(!/deviceCode|accessToken|refreshToken|authorizationSessionId/.test(authorizationBridgeSource + mainSource + sceneSource + authGateSource + authGateModelsSource), 'Authorization secrets escaped the credential-owning Task');
assert(!/serverPublicKey|serverPublicKeyFingerprint|assignedHostname|signature|accessToken|refreshToken/.test(serverCatalogBridgeSource + sceneSource), 'Server trust or credential material escaped the credential-owning Task');
const serverCatalogLoadBody = serverCatalogTaskSource.match(/sub PorticoServerCatalogLoad\(controller as object\)([\s\S]*?)end sub/)?.[1] ?? '';
assert(serverCatalogTaskSource.includes('PorticoHttpValidatePrivateRequest(request)') && serverCatalogTaskSource.includes('/api/system') && serverCatalogTaskSource.includes('/api/account/servers?limit=100') && serverCatalogLoadBody.indexOf('PorticoServerCatalogEnsureHostedCompatibility(controller)') < serverCatalogLoadBody.indexOf('PorticoServerCatalogCredentials()'), 'Server catalog must preflight exact Hosted compatibility before loading memberships');
assert(serverCatalogTaskSource.includes('data.apiVersion.ToStr() <> "v1"') && !/data\.(?:version|schemaRevision)/.test(serverCatalogTaskSource.match(/function PorticoServerCatalogHostedSystemIsCompatible[\s\S]*?end function/)?.[0] ?? ''), 'Server catalog Hosted v1 compatibility preflight drifted');
assert(serverCatalogTaskSource.includes('refreshRequestedGeneration <> controller.credentialGeneration'), 'Server catalog 401 refresh requests must be generation-latched');
assert(signedDocumentSource.includes('CreateObject("roDsa")') && signedDocumentSource.includes('SetSignAlgorithm("Ed25519")') && signedDocumentSource.includes('dsa.Verify(message, signature)'), 'Signed route documents must use Roku native Ed25519 verification');
const hostedActivationSource = serverConnectionTaskSource.match(/sub PorticoServerConnectionActivateHosted[\s\S]*?\nend sub/)?.[0] ?? '';
const routeResolutionSource = serverConnectionTaskSource.match(/function PorticoServerConnectionResolveHostedRoute[\s\S]*?\nend function/)?.[0] ?? '';
assert(routeResolutionSource.indexOf('PorticoSignedDocumentVerifyRoute') < routeResolutionSource.indexOf('PorticoServerConnectionVerifyRoute'), 'Server connection trust ordering drifted');
assert(/for each candidate in PorticoServerConnectionRouteCandidates[\s\S]*PorticoServerConnectionVerifyRoute\(controller, route\) then return route/.test(routeResolutionSource) && (hostedActivationSource.match(/PorticoServerConnectionAcceptCredentials/g) ?? []).length === 1, 'Server connection route failover may duplicate or roll back a credential family');
assert(/PorticoServerConnectionHostedBootstrap\(hosted\.data, envelope, expected\)/.test(hostedActivationSource) && /PorticoServerSessionRebaseIdentity\(controller\.session, result\.data, allowRevisionAdvance\)/.test(serverConnectionTaskSource), 'Server connection credential binding drifted');
assert(/"refreshNativeSession"/.test(serverConnectionTaskSource) && /rotationKey: rotation\.rotationKey/.test(serverConnectionTaskSource) && /PorticoSecureRegistryCommit\(recordType, replacement\)/.test(serverConnectionTaskSource) && /PorticoSecureRegistryCommit\("server-session", tombstone\)[\s\S]*PorticoSecureRegistryClear\("server-session"\)/.test(serverConnectionTaskSource), 'Server connection rotation or durable teardown drifted');
assert(!/accessToken: true|refreshToken: true|apiBaseUrl: true|serverPublicKeyFingerprint: true|accountUserId: true|accountDeviceId: true|membershipId: true|signature: true|routes: true/.test(serverConnectionBridgeSource), 'Server connection secret/trust material escaped through the public bridge');
assert(contentTaskXml.includes('field id="command"') && contentTaskXml.includes('field id="projection"') && !/field id="(?:accessToken|refreshToken|apiBaseUrl|headers)"/i.test(contentTaskXml), 'Content Task public fields must remain secret-free');
assert(!contentBridgeSource.includes('findNode(') && contentBridgeSource.includes('CreateObject("roSGNode", "PorticoContentTask")'), 'Content controller must create its Task directly without a blocking Scene rendezvous');
assert(!/accessToken: true|refreshToken: true|apiBaseUrl: true|headers: true/.test(contentBridgeSource), 'Content credential material escaped through the public bridge');
assert((contentTaskSource.match(/PorticoSecureRegistryRead\("server-session"\)/g) ?? []).length === 1 && contentTaskSource.includes('function PorticoContentSessionForController') && contentTaskSource.includes('PorticoDiscoverySessionForController(controller)'), 'Content Task must use one narrow server-session reader');
assert(contentTaskSource.includes('PorticoHttpValidatePrivateRequest(request)') && contentTaskSource.includes('AsyncGetToFile(tempPath)') && contentTaskSource.includes('tmp:/portico-content/'), 'Content JSON and artwork loads must stay credential-private and use temporary artwork storage');
assert(contentModelSource.includes('function PorticoContentCachedHome') && contentModelSource.includes('function PorticoContentCachedDetail') && contentModelSource.includes('function PorticoContentHomeUiActions') && contentModelSource.includes('model.uiActions = PorticoContentDetailUiActions(model.actions)'), 'Content models must provide safe cached projections and capability-derived supported UI actions');
assert(playbackTaskXml.includes('field id="command"') && playbackTaskXml.includes('field id="projection"') && !/field id="(?:accessToken|serverSession|sessionId|grantToken|apiBaseUrl|headers)"/i.test(playbackTaskXml), 'Playback Task public fields must remain credential and session-id free');
assert(playbackTaskXml.includes('uri="pkg:/components/PorticoPlaybackTask.brs"') && playbackTaskXml.includes('uri="pkg:/source/lib/PorticoPlaybackModels.brs"'), 'Playback Task and model scripts must stay top-level for Roku OS registration');
const playbackCredentialQueryMarkers = playbackTaskSource + playbackModelSource + playbackBridgeSource;
assert(/PorticoPlaybackCredentialQueryUnsafe/.test(playbackModelSource) && /PorticoPlaybackBridgeCredentialQueryUnsafe/.test(playbackBridgeSource), 'Playback must reject credential-bearing query parameters');
assert(/content\.url = sourceUrl/.test(playbackModelSource) && /content\.HttpHeaders = \["Authorization: PorticoMedia " \+ token\]/.test(playbackModelSource), 'Playback media grants must travel in private ContentNode headers while media URLs remain clean');
assert(!/(?:sourceUrl|content\.url)\s*=.*(?:media_grant|download_grant|access_token)/i.test(playbackCredentialQueryMarkers), 'Playback source URLs must not contain credential query parameters');
assert((playbackCredentialQueryMarkers.match(/access_token=/gi) ?? []).length === 2 && (playbackCredentialQueryMarkers.match(/accesstoken=/gi) ?? []).length === 2 && !/(?:https?:|sourceUrl|url\s*=)[^\n]*access_?token=/i.test(playbackCredentialQueryMarkers), 'Playback source must reject account-token media URLs without packaging credential-shaped URL templates');
assert(
  /capabilitySchemaVersion: "playback-capability-v2"/.test(playbackModelSource) &&
    /supportedContainers: \["hls", "mp4", "m4a"\]/.test(playbackModelSource) &&
    /supportedVideoCodecs: \["h264"\]/.test(playbackModelSource) &&
    /supportedAudioCodecs: \["aac"\]/.test(playbackModelSource) &&
    /supportsMpegTs: false/.test(playbackModelSource) &&
    /supportsHevc: false/.test(playbackModelSource) &&
    /supportsHdr: false/.test(playbackModelSource) &&
    /requiresServerProxy: true/.test(playbackModelSource) &&
    /capabilityEvidence: \[\]/.test(playbackModelSource) &&
    !/GetVideoMode|PorticoPlaybackRokuCapabilityTuples|source: "native_runtime"/.test(playbackModelSource),
  'Roku playback capability negotiation must defer exact tuples to the reviewed server fallback until a real native probe exists',
);
assert(/PorticoPlaybackAccessTokenQueryMarker\(\)/.test(playbackModelSource) && /PorticoPlaybackCompactAccessTokenQueryMarker\(\)/.test(playbackModelSource) && /markers = \["media_grant=", "download_grant=", "access_token="/.test(playbackBridgeSource), 'Playback URL validation must reject every credential-bearing query marker');
const playbackProgressSource = playbackTaskSource.match(/sub PorticoPlaybackSendProgress\([\s\S]*?\nend sub/)?.[0] ?? '';
const playbackStopSource = playbackTaskSource.match(/function PorticoPlaybackStopActive\([\s\S]*?\nend function/)?.[0] ?? '';
assert(/controller\.playback\.nextEventSequence = sequence \+ 1/.test(playbackTaskSource) && /AsyncPostFromString\(request\.body\)/.test(playbackTaskSource) && /highestEventSequence/.test(playbackTaskSource), 'Playback progress must advance ordered event sequence before asynchronous transmission and reconcile acknowledgements');
assert(playbackStopSource.indexOf('PorticoPlaybackSendProgress') < playbackStopSource.indexOf('method: "DELETE"'), 'Playback stop must report final progress before closing the session');
assert(/delaySeconds = remaining - 60/.test(playbackTaskSource) && /nextHeartbeatAtSeconds = controller\.clock\.TotalSeconds\(\) \+ 10/.test(playbackTaskSource), 'Playback grant renewal and heartbeat cadence drifted');
assert(/replacement\.generation <= session\.generation/.test(playbackTaskSource) && /result\.status <> 401/.test(playbackTaskSource) && /PorticoPlaybackRequestReconnect\(controller\)/.test(playbackTaskSource), 'Playback 401 handling must replay only on a newer encrypted session generation and otherwise request reconnect');
assert(/CreateObject\("roSGNode", "ContentNode"\)/.test(playbackBridgeSource) && !/sessionId: true|grantToken: true|accessToken: true|apiBaseUrl: true|serverSession: true|headers: true/.test(playbackBridgeSource), 'Playback bridge must expose only a Video-node-safe projection');
assert(authorizationTaskSource.includes('PorticoHttpValidatePrivateRequest(request)') && httpTaskSource.includes('PorticoHttpValidateRequest(request)'), 'Private and public HTTP validation boundaries drifted');
assert(authorizationTaskSource.includes('GetSecondsToISO8601Date(normalized)') && !authorizationTaskSource.includes('FromISO8601String'), 'Hosted RFC3339 timestamps must use Roku-compatible UTC normalization');
assert(authorizationTaskSource.includes('data.apiVersion.ToStr() <> "v1"') && !/data\.(?:version|schemaRevision)/.test(authorizationTaskSource.match(/function PorticoAuthorizationTaskHostedSystemIsCompatible[\s\S]*?end function/)?.[0] ?? ''), 'Hosted v1 compatibility preflight drifted');
const deauthorizeBody = authorizationTaskSource.match(/sub PorticoAuthorizationTaskDeauthorize[\s\S]*?end sub/)?.[0] ?? '';
const terminalBody = authorizationTaskSource.match(/sub PorticoAuthorizationTaskTerminal[\s\S]*?end sub/)?.[0] ?? '';
assert(/if not durable[\s\S]*authorization-unavailable[\s\S]*return[\s\S]*credentials = invalid/.test(deauthorizeBody), 'Automatic deauthorization must not discard credentials or publish a terminal state before durable removal');
assert(/if not durable[\s\S]*authorization-unavailable[\s\S]*return[\s\S]*Publish\(accountStatus/.test(terminalBody), 'Authorization terminal state must not publish before its pending record is durably committed or cleared');
for (const forbiddenCopy of ['fixture media', 'moving through the app', 'authentication checks succeed', 'fresh content appears only after', 'invented while disconnected', 'future verified cache', 'Hosted Task', 'in this build', 'does not imply', 'Server-scoped credentials', 'Connection diagnostics', 'discovered directly on this local network', 'not advertised by this server', 'securely sign it in', 'server-defined presentation', 'this view does not publish']) {
  assert(!sceneSource.includes(forbiddenCopy), `Offline state UI contains implementation commentary: ${forbiddenCopy}`);
}
for (const forbidden of [
  ['SystemFont', /SystemFont/i],
  ['stock Button node', /<Button(?:Group)?\b/],
  ['stock focus feedback', /drawFocusFeedback\s*=\s*["']true/i],
  ['developer-machine path', /\/Users\//],
  ['obvious credential', /(?:^|[\s,{])(?:access[_-]?token|refresh[_-]?token|client[_-]?secret|api[_-]?key)\s*[:=]\s*["'][^"'\r\n]+["']/im]
]) assert(!forbidden[1].test(source), `Forbidden ${forbidden[0]} found in channel source`);
assert(source.includes('mask = group.CreateChild("MaskGroup")') && source.includes('mask.maskUri = "pkg:/images/ui/settings-avatar.png"') && source.includes('mask.maskSize = [144, 144]'), 'Cast avatars must keep their packaged rounded mask instead of exposing rectangular artwork');

const releaseSource = sourceFiles.filter(path => !path.includes(`${join('channel', 'development')}`)).map(path => readFileSync(path, 'utf8')).join('\n');
const sceneRoots = (releaseSource.match(/<component\s+name="[^"]+"\s+extends="Scene"/g) ?? []).length;
assert(sceneRoots === 1, `Exactly one Scene root is required; found ${sceneRoots}`);
assert(!filesUnder(channel).some(path => extname(path).toLowerCase() === '.svg'), 'SVG assets cannot be packaged as Roku Poster sources');
assert(!filesUnder(channel).some(path => path.endsWith('.DS_Store')), 'Hidden macOS metadata found in channel package');

const packageReferences = new Set();
for (const match of source.matchAll(/pkg:\/([A-Za-z0-9_./-]+\.(?:png|jpg|jpeg|ttf|json|brs|xml))/gi)) packageReferences.add(match[1]);
for (const reference of packageReferences) assert(existsSync(join(channel, reference)), `Unresolved package reference: pkg:/${reference}`);

assertPng('images/ui/button-primary.png', 166, 64, true);
assertPng('images/ui/icon-button-focus.png', 64, 64, true);
assertPng('images/ui/rail-bed-collapsed.png', 80, 1032);
assertPng('images/ui/rail-bed-expanded.png', 280, 1032);
assertPng('images/ui/poster-card-focus.png', 214, 395, true);
assertPng('images/ui/landscape-card-focus.png', 320, 248, true);
assertPng('images/ui/poster-artwork-corners.png', 202, 321, true);
assertPng('images/ui/poster-artwork-corners-focus.png', 202, 321, true);
assertPng('images/ui/landscape-artwork-corners.png', 308, 180, true);
assertPng('images/ui/landscape-artwork-corners-focus.png', 308, 180, true);
assertPng('images/ui/overlay-scrim.png', 1920, 1080, true);
assertPng('images/ui/server-row-focus.png', 700, 82, true);
assertPng('images/ui/server-radio.png', 28, 28, true);
assertPng('images/ui/server-radio-selected-focus.png', 28, 28, true);
assertPng('images/ui/server-avatar.png', 52, 52, true);
for (let visibleRows = 1; visibleRows <= 6; visibleRows += 1) assertPng(`images/ui/server-panel-${visibleRows}.png`, 720, 382 + (visibleRows * 82), true);
assertPng('images/ui/server-panel-compact.png', 720, 382, true);
assertPng('images/ui/search-field-idle.png', 1200, 68, true);
assertPng('images/ui/search-field-focus.png', 1200, 68, true);
assertPng('images/ui/search-keyboard-panel.png', 1200, 288, true);
assertPng('images/ui/search-key-focus.png', 104, 56, true);
assertPng('images/ui/search-result-focus.png', 846, 174, true);
assertPng('images/ui/search-result-artwork-corners-focus.png', 100, 150, true);
assertPng('images/ui/browse-tab-focus.png', 168, 68, true);
assertPng('images/ui/browse-action-focus.png', 360, 64, true);
assertPng('images/ui/square-card-focus.png', 214, 288, true);
assertPng('images/ui/square-artwork-corners-focus.png', 202, 202, true);
assertPng('images/ui/browse-list-focus.png', 1712, 158, true);
assertPng('images/ui/browse-facet-focus.png', 250, 150, true);
assertPng('images/ui/browse-resource-focus.png', 530, 190, true);
assertPng('images/ui/state-icon-bed.png', 82, 82, true);
assertPng('images/icons/image-off-rail.png', 64, 64, true);
assertPng('images/icons/refresh-cw-rail.png', 64, 64, true);
assertPng('images/icons/chevron-right-rail.png', 64, 64, true);
assertPng('images/icons/chevron-down-rail.png', 64, 64, true);
assertPng('images/icons/chevron-up-rail.png', 64, 64, true);
assertPng('images/icons/x.png', 64, 64, true);
assertPng('images/ui/channel-poster-fhd.png', 540, 405, true);
assertPng('images/ui/hero-vertical-home.png', 1784, 430, true);
assertPng('images/ui/hero-vertical-strong.png', 1784, 570, true);
assertPng('images/ui/hero-horizontal.png', 1784, 570, true);
for (const name of ['fargo', 'rookie', 'hurt-locker', 'dolphin-reef', 'earth-stood-still', 'martian', 'blade-runner', 'life-aquatic', 'project-hail-mary']) {
  assertPng(`images/posters/${name}.png`, 202, 321, true);
}
for (const name of ['rookie-episode-1', 'rookie-episode-2', 'rookie-episode-3']) assertPng(`images/backdrops/${name}.png`, 308, 180, true);

for (const golden of [
  'home-default.png', 'home-rail-expanded.png', 'home-rookie-focused.png', 'home-recently-focused.png',
  'detail-rookie.png', 'home-long-title.png', 'detail-long-title.png',
  'home-server-picker-loading.png', 'home-server-picker-offline.png',
  'search-results.png', 'search-keyboard.png', 'library-grid.png', 'library-empty.png',
  'player-preparing.png', 'player-buffering.png', 'player-playing.png', 'player-paused.png', 'player-ended.png', 'player-error.png',
  'auth-landing.png', 'auth-account-code.png', 'saved-resources.png',
  'channels-grid.png', 'channels-guide.png', 'channels-dvr-expanded.png',
  'detail-cast-versions.png', 'detail-versions-expanded.png', 'detail-more.png',
  'profile.png', 'settings.png', 'player-quality-panel.png', 'player-streams-panel.png'
]) {
  const path = join(root, 'artifacts/golden', golden);
  assert(existsSync(path), `Golden render ${golden} is missing`);
  if (existsSync(path)) {
    const size = pngSize(path);
    assert(size.width === 1920 && size.height === 1080, `${golden} must be 1920x1080`);
  }
}

const packagePath = join(root, 'artifacts/portico-roku-release.zip');
assert(existsSync(packagePath), 'Sideload ZIP is missing; run npm run compile');
if (existsSync(packagePath)) {
  const listing = spawnSync('unzip', ['-Z1', packagePath], {encoding: 'utf8'});
  assert(listing.status === 0, `Could not inspect sideload ZIP: ${listing.stderr}`);
  const entries = listing.stdout.trim().split('\n');
  assert(entries.includes('manifest'), 'Sideload ZIP does not contain root manifest');
  assert(entries.includes('components/PorticoScene.xml'), 'Sideload ZIP does not contain PorticoScene');
  assert(entries.every(entry => !entry.includes('..') && !entry.startsWith('/') && !entry.includes('.DS_Store')), 'Sideload ZIP contains an unsafe or hidden path');
  assert(entries.every(entry => !entry.endsWith('.svg') && !entry.endsWith('.map')), 'Sideload ZIP contains unsupported or development-only assets');
}

if (failures.length) {
  console.error(`Verification failed (${failures.length}/${assertions} assertions):`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Verified ${assertions} Roku visual-parity assertions.`);
