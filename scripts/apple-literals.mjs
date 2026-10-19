/**
 * Numbers the Apple TV app types in its own source (they are not design tokens), by the name the
 * channel reads them under as `Theme.apple.<name>`. Each entry names the file and the exact source
 * text it was read from; `generate.mjs` fails when that text is no longer in the file, so a change
 * in the Apple app cannot pass unnoticed. Television values only (`isTV ? tv : handheld` → tv).
 */
const ui = 'apps/native/src/ui';
const shell = 'apps/native/src/shell';

export const appleLiterals = {
  // ui/Focusable.tsx
  focusRingGap: {value: 2, file: `${ui}/Focusable.tsx`, source: 'const inset = -(metrics.focusRing + 2);'},
  disabledOpacity: {value: 0.45, file: `${ui}/Focusable.tsx`, source: 'disabled ? {opacity: 0.45}'},
  busyOpacity: {value: 0.6, file: `${ui}/Focusable.tsx`, source: 'busy ? {opacity: 0.6}'},
  // ui/FocusHalo.tsx
  haloShadowOpacity: {value: 0.7, file: `${ui}/FocusHalo.tsx`, source: 'shadowOpacity: 0.7'},
  haloShadowRadius: {value: 28, file: `${ui}/FocusHalo.tsx`, source: 'shadowRadius: 28'},
  haloShadowOffsetY: {value: 10, file: `${ui}/FocusHalo.tsx`, source: 'shadowOffset: {width: 0, height: 10}'},
  // ui/Button.tsx
  buttonNumberSize: {value: 0.34, file: `${ui}/Button.tsx`, source: 'fontSize: Math.round(iconSize * 0.34)'},
  buttonNumberTop: {value: 0.3, file: `${ui}/Button.tsx`, source: 'top: iconSize * 0.3'},
  // ui/Card.tsx
  cardWatchedBadge: {value: 30, file: `${ui}/Card.tsx`, source: 'width: isTV ? 30 : 20, height: isTV ? 30 : 20'},
  cardWatchedIcon: {value: 18, file: `${ui}/Card.tsx`, source: 'size={isTV ? 18 : 12}'},
  cardMarkAlpha: {value: 0.82, file: `${ui}/Card.tsx`, source: 'backgroundColor: alpha(colors.ink, 0.82)'},
  cardBadgePadY: {value: 2, file: `${ui}/Card.tsx`, source: 'paddingVertical: 2, borderRadius: metrics.radius.small'},
  cardCaptionPadX: {value: 2, file: `${ui}/Card.tsx`, source: 'paddingHorizontal: 2, minHeight: isTV ? 60 : 38'},
  cardCaptionMinHeight: {value: 60, file: `${ui}/Card.tsx`, source: 'minHeight: isTV ? 60 : 38'},
  cardSubtitleGap: {value: 1, file: `${ui}/Card.tsx`, source: 'style={{marginTop: 1}}'},
  personCardSize: {value: 150, file: `${ui}/Card.tsx`, source: 'width ?? (isTV ? 150 : 84)'},
  bannerCardFactor: {value: 1.4, file: `${ui}/Card.tsx`, source: 'metrics.landscapeWidth * 1.4'},
  bannerScrimAlpha: {value: 0.55, file: `${ui}/Card.tsx`, source: 'backgroundColor: alpha(colors.ink, 0.55)'},
  // ui/Artwork.tsx
  artworkPlaceholderAlpha: {value: 0.75, file: `${ui}/Artwork.tsx`, source: 'backgroundColor: alpha(colors.raisedHigh, 0.75)'},
  artworkSmall: {value: 80, file: `${ui}/Artwork.tsx`, source: 'Math.min(w, h) < 80'},
  artworkIconFactor: {value: 0.32, file: `${ui}/Artwork.tsx`, source: 'size={Math.min(w, h) * 0.32}'},
  artworkIconAlpha: {value: 0.7, file: `${ui}/Artwork.tsx`, source: 'alpha(colors.textTertiary, 0.7)'},
  artworkFadeMs: {value: 200, file: `${ui}/Artwork.tsx`, source: 'duration: priority ? 120 : 200'},
  artworkFadePriorityMs: {value: 120, file: `${ui}/Artwork.tsx`, source: 'duration: priority ? 120 : 200'},
  artworkTitleLines: {value: 4, file: `${ui}/Artwork.tsx`, source: "lines={shape === 'landscape' ? 2 : 4}"},
  artworkTitleLinesLandscape: {value: 2, file: `${ui}/Artwork.tsx`, source: "lines={shape === 'landscape' ? 2 : 4}"},
  progressLineHeight: {value: 4, file: `${ui}/Artwork.tsx`, source: 'bottom: 0, height: 4, backgroundColor: alpha(colors.black, 0.45)'},
  progressTrackAlpha: {value: 0.45, file: `${ui}/Artwork.tsx`, source: 'backgroundColor: alpha(colors.black, 0.45)'},
  // ui/Shelf.tsx
  shelfSnapFraction: {value: 0.28, file: `${ui}/Shelf.tsx`, source: 'scrollSnapOffset: Math.round(window.height * 0.28)'},
  // ui/Grid.tsx
  gridCaptionHeight: {value: 56, file: `${ui}/Grid.tsx`, source: 'columnWidth * aspect + 56 + space.lg'},
  gridPrefetchRows: {value: 4, file: `${ui}/Grid.tsx`, source: 'list.ensureRange(0, columns * 4 - 1)'},
  // ui/Page.tsx
  pageTopInset: {value: 60, file: `${ui}/Page.tsx`, source: 'isTV ? Math.max(insets.top, 60) - space.lg'},
  // ui/ListRow.tsx
  rowOrdinalExtra: {value: 12, file: `${ui}/ListRow.tsx`, source: 'r.leadingBox[platform] + (isTV ? 12 : 4)'},
  rowDescriptionGap: {value: 2, file: `${ui}/ListRow.tsx`, source: 'lines={2} style={{marginTop: 2}}'},
  rowMetaMaxFraction: {value: 0.45, file: `${ui}/ListRow.tsx`, source: "maxWidth: '45%'"},
  rowTitleLines: {value: 2, file: `${ui}/ListRow.tsx`, source: 'lines={media ? 1 : 2}'},
  rowGroupFocusRoom: {value: 8, file: `${ui}/ListRow.tsx`, source: 'padding: Math.max(space.sm, metrics.focusRing + 8)'},
  // ui/Tabs.tsx
  tabFocusScale: {value: 1.04, file: `${ui}/Tabs.tsx`, source: 'scale={isTV ? 1.04 : 1}'},
  tabUnderlineHeight: {value: 4, file: `${ui}/Tabs.tsx`, source: 'height: isTV ? 4 : 3, borderRadius: 2'},
  tabUnderlineRadius: {value: 2, file: `${ui}/Tabs.tsx`, source: 'height: isTV ? 4 : 3, borderRadius: 2'},
  // ui/Chip.tsx
  chipCloseFactor: {value: 0.875, file: `${ui}/Chip.tsx`, source: 'Math.round(iconSize * 0.875)'},
  // ui/Toast.tsx
  toastTravel: {value: 12, file: `${ui}/Toast.tsx`, source: 'translateY: (1 - progress.value) * (isTV ? -12 : 12)'},
  toastTop: {value: 60, file: `${ui}/Toast.tsx`, source: 'top: Math.max(insets.top, 60)'},
  toastInsetX: {value: 80, file: `${ui}/Toast.tsx`, source: 'paddingHorizontal: isTV ? 80 : space.page'},
  // ui/Feedback.tsx
  spinnerTurnMs: {value: 1000, file: `${ui}/Feedback.tsx`, source: 'toValue: 1, duration: 1000, easing: Easing.linear'},
  skeletonAlpha: {value: 0.8, file: `${ui}/Feedback.tsx`, source: 'backgroundColor: alpha(colors.raisedHigh, 0.8)'},
  skeletonBeatMs: {value: 900, file: `${ui}/Feedback.tsx`, source: 'toValue: 1, duration: 900'},
  skeletonBeats: {value: 4, file: `${ui}/Feedback.tsx`, source: 'Animated.loop(beat, {iterations: 4})'},
  skeletonRestOpacity: {value: 0.5, file: `${ui}/Feedback.tsx`, source: 'new Animated.Value(0.5)'},
  badgeAlpha: {value: 0.16, file: `${ui}/Feedback.tsx`, source: 'backgroundColor: alpha(color, 0.16)'},
  badgePadY: {value: 2, file: `${ui}/Feedback.tsx`, source: 'paddingHorizontal: space.sm, paddingVertical: 2, borderRadius: metrics.radius.small, backgroundColor: alpha(color, 0.16)'},
  progressBarHeight: {value: 4, file: `${ui}/Feedback.tsx`, source: 'const h = height ?? 4;'},
  // ui/Canvas.tsx
  surfaceBorderAlpha: {value: 0.9, file: `${ui}/Canvas.tsx`, source: 'borderColor: alpha(colors.lineSoft, 0.9)'},
  // ui/theme.ts
  entryFocusClaimMs: {value: 600, file: `${ui}/theme.ts`, source: 'useEntryFocus(ready = true, claimMs = 600, patienceMs = 6000)'},
  entryFocusPatienceMs: {value: 6000, file: `${ui}/theme.ts`, source: 'useEntryFocus(ready = true, claimMs = 600, patienceMs = 6000)'},
  textScaleLarge: {value: 1.2, file: `${ui}/theme.ts`, source: 'TV only: the "Text size" device preference (1 or 1.2)'},
  // shell/Rail.tsx and shell/rail-expansion.ts
  railCollapsedAlpha: {value: 0.5, file: `${shell}/Rail.tsx`, source: 'alpha(colors.ink, isTV ? 0.5 : 0.72)'},
  railBorderAlpha: {value: 0.7, file: `${shell}/Rail.tsx`, source: 'borderRightColor: alpha(colors.lineSoft, 0.7)'},
  railTopInset: {value: 60, file: `${shell}/Rail.tsx`, source: 'Math.max(insets.top, isTV ? 60 : 0)'},
  railBottomInset: {value: 40, file: `${shell}/Rail.tsx`, source: 'Math.max(insets.bottom, isTV ? 40 : space.md)'},
  railHeadHeight: {value: 44, file: `${shell}/Rail.tsx`, source: 'height: isTV ? 44 : 30'},
  railMarkHeight: {value: 34, file: `${shell}/Rail.tsx`, source: '<BrandMark size={isTV ? 34 : 24} />'},
  railWordmarkHeight: {value: 30, file: `${shell}/Rail.tsx`, source: '<Wordmark height={isTV ? 30 : 20} />'},
  railItemGap: {value: 4, file: `${shell}/Rail.tsx`, source: 'gap: compact ? 2 : isTV ? 4 : space.xs'},
  railListPad: {value: 4, file: `${shell}/Rail.tsx`, source: 'paddingVertical: isTV ? 4 : 0, paddingHorizontal: isTV ? 4 : 0'},
  railDividerAlpha: {value: 0.8, file: `${shell}/Rail.tsx`, source: 'backgroundColor: alpha(colors.lineSoft, 0.8)'},
  railActiveAlpha: {value: 0.14, file: `${shell}/Rail.tsx`, source: 'alpha(colors.accent, 0.14)'},
  railActiveBarWidth: {value: 3, file: `${shell}/Rail.tsx`, source: 'bottom: size * 0.25, width: 3, borderRadius: 2'},
  railActiveBarInset: {value: 0.25, file: `${shell}/Rail.tsx`, source: 'top: size * 0.25, bottom: size * 0.25'},
  railBadgeSize: {value: 9, file: `${shell}/Rail.tsx`, source: 'width: 9, height: 9, borderRadius: 5'},
  railBadgeTop: {value: -2, file: `${shell}/Rail.tsx`, source: 'top: -2, right: -4'},
  railBadgeRight: {value: -4, file: `${shell}/Rail.tsx`, source: 'top: -2, right: -4'},
  railCollapseDelayMs: {value: 140, file: `${shell}/rail-expansion.ts`, source: 'options.collapseDelayMs ?? 140'},
  wordmarkAspect: {value: 512 / 117, file: `${ui}/Brand.tsx`, source: 'width: height * (512 / 117)'},
};

// Added with the overlay and field primitives.
Object.assign(appleLiterals, {
  fieldFocusScale: {value: 1.01, file: `${ui}/Field.tsx`, source: 'scale={1.01}'},
  fieldSecureMax: {value: 24, file: `${ui}/Field.tsx`, source: "'•'.repeat(Math.min(value.length, 24))"},
  sheetFocusRoomX: {value: 12, file: `${ui}/Sheet.tsx`, source: 'Math.max(inset - rowInset, metrics.focusRing + 12)'},
  sheetFocusRoomY: {value: 8, file: `${ui}/Sheet.tsx`, source: 'Math.max(space.sm, metrics.focusRing + 8)'},
  sheetTitleLines: {value: 2, file: `${ui}/Sheet.tsx`, source: '<Text variant="heading" lines={2}>{title}</Text>'},
  backdropRetryMs: {value: 1000, file: `${ui}/Canvas.tsx`, source: '[1000, 3000, 8000, 20000][attempt]'},
});

// Sign-in screens (apps/native/src/screens/auth) and the shell frame.
const auth = 'apps/native/src/screens/auth';
Object.assign(appleLiterals, {
  authWidth: {value: 720, file: `${auth}/AuthFrame.tsx`, source: 'wide ? 1240 : isTV ? 720 : 560'},
  authWidthWide: {value: 1240, file: `${auth}/AuthFrame.tsx`, source: 'wide ? 1240 : isTV ? 720 : 560'},
  authTopInset: {value: 60, file: `${auth}/AuthFrame.tsx`, source: 'Math.max(insets.top, isTV ? 60 : 0)'},
  authWordmark: {value: 44, file: `${auth}/AuthFrame.tsx`, source: 'height={centered ? 64 : isTV ? 44 : 30}'},
  authWordmarkCentered: {value: 64, file: `${auth}/AuthFrame.tsx`, source: 'height={centered ? 64 : isTV ? 44 : 30}'},
  activationQr: {value: 260, file: `${auth}/Activation.tsx`, source: '<QRCode value={link} size={260}'},
  activationQrRadius: {value: 12, file: `${auth}/Activation.tsx`, source: 'backgroundColor: colors.white, borderRadius: 12'},
  activationMinHeight: {value: 300, file: `${auth}/Activation.tsx`, source: 'gap: space.xxl, minHeight: 300'},
  activationCopyWidth: {value: 640, file: `${auth}/Activation.tsx`, source: 'gap: space.md, maxWidth: 640'},
  activationCodeSize: {value: 84, file: `${auth}/Activation.tsx`, source: 'fontSize: 84, lineHeight: 96, letterSpacing: 10'},
  activationCodeLine: {value: 96, file: `${auth}/Activation.tsx`, source: 'fontSize: 84, lineHeight: 96, letterSpacing: 10'},
  activationCodeSpacing: {value: 10, file: `${auth}/Activation.tsx`, source: 'fontSize: 84, lineHeight: 96, letterSpacing: 10'},
  quickConnectQr: {value: 240, file: `${auth}/QuickConnect.tsx`, source: '<QRCode value={link} size={240}'},
  profileAvatar: {value: 180, file: `${auth}/DirectProfiles.tsx`, source: 'const avatar = isTV ? 180 : 88;'},
  profileTileExtra: {value: 40, file: `${auth}/DirectProfiles.tsx`, source: 'width: avatar + 40'},
  profileFocusScale: {value: 1.08, file: `${auth}/DirectProfiles.tsx`, source: 'scale={isTV ? 1.08 : 1}'},
  profileLock: {value: 14, file: `${auth}/DirectProfiles.tsx`, source: '<Icon name="lock" size={14}'},
  profileBorder: {value: 3, file: `${auth}/ProfileAvatar.tsx`, source: 'borderWidth: 3, borderColor: focused ? colors.focus'},
  serverOfflineOpacity: {value: 0.55, file: `${auth}/PorticoLanding.tsx`, source: '{opacity: 0.55}'},
  savedServerRing: {value: 28, file: `${auth}/SavedServerUnavailable.tsx`, source: '<Ring size={isTV ? 28 : 18} thickness={2} />'},
  shellFrameWidth: {value: 900, file: `${shell}/ShellFrame.tsx`, source: 'maxWidth: isTV ? 900 : 560'},
  challengeMinLength: {value: 6, file: `${auth}/DirectSignIn.tsx`, source: 'value.trim().length >= 6'},
});

// App.tsx `Connecting`: the brand and a ring while the remembered sign-in is read.
Object.assign(appleLiterals, {
  connectingWordmark: {value: 56, file: 'apps/native/App.tsx', source: '<Wordmark height={isTV ? 56 : 32} />'},
  connectingRing: {value: 44, file: 'apps/native/App.tsx', source: '<Ring size={isTV ? 44 : 28} thickness={isTV ? 3 : 2} />'},
});

// Home (apps/native/src/screens/Home.tsx).
const screens = 'apps/native/src/screens';
Object.assign(appleLiterals, {
  homeHeroArtExtra: {value: 120, file: `${screens}/Home.tsx`, source: 'height={heroHeight + 120}'},
  homeHeroArtOpacity: {value: 0.85, file: `${screens}/Home.tsx`, source: 'align="right" opacity={0.85}'},
  homeHeroWidthFraction: {value: 0.62, file: `${screens}/Home.tsx`, source: 'maxWidth: isTV ? window.width * 0.62 : undefined'},
  homeHeroCover: {value: 260, file: `${screens}/Home.tsx`, source: 'const coverWidth = isTV ? 260 : 112;'},
  homeHeroOverviewWidth: {value: 760, file: `${screens}/Home.tsx`, source: 'maxWidth: isTV ? 760 : 520'},
  homeHeroOverviewLines: {value: 3, file: `${screens}/Home.tsx`, source: 'lines={isTV ? 3 : 2}'},
  homeHeroProgressWidth: {value: 420, file: `${screens}/Home.tsx`, source: 'maxWidth: isTV ? 420 : 240'},
  homeHeroShadeFraction: {value: 0.4, file: `${screens}/Home.tsx`, source: 'height: height * 0.4, backgroundColor: colors.ink, opacity: 0.35'},
  homeHeroShadeOpacity: {value: 0.35, file: `${screens}/Home.tsx`, source: 'height: height * 0.4, backgroundColor: colors.ink, opacity: 0.35'},
  homeSkeletonTitleWidth: {value: 520, file: `${screens}/Home.tsx`, source: '<Skeleton width={isTV ? 520 : 220} height={isTV ? 56 : 36} />'},
  homeSkeletonTitleHeight: {value: 56, file: `${screens}/Home.tsx`, source: '<Skeleton width={isTV ? 520 : 220} height={isTV ? 56 : 36} />'},
  homeSkeletonLineWidth: {value: 260, file: `${screens}/Home.tsx`, source: '<Skeleton width={isTV ? 260 : 140} height={isTV ? 22 : 16} />'},
  homeSkeletonLineHeight: {value: 22, file: `${screens}/Home.tsx`, source: '<Skeleton width={isTV ? 260 : 140} height={isTV ? 22 : 16} />'},
  homeSkeletonButtonWidth: {value: 180, file: `${screens}/Home.tsx`, source: '<Skeleton width={isTV ? 180 : 110} height={metrics.control} radius={metrics.radius.control} />'},
  homeSkeletonHeadingWidth: {value: 180, file: `${screens}/Home.tsx`, source: '<Skeleton width={180} height={metrics.icon} radius={6} />'},
  homeSkeletonCards: {value: 7, file: `${screens}/Home.tsx`, source: '[0, 1, 2, 3, 4, 5, 6].map(i => ('},
  homeRowAhead: {value: 20, file: `${screens}/HomeRow.tsx`, source: 'last >= entries.length - 20'},
  // player/VideoPlayer.tsx, Timeline.tsx, SkipPrompt.tsx, MiniPlayer.tsx
  playerInset: {value: 60, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'const topInset = Math.max(insets.top, isTV ? 60 : space.md);'},
  playerSide: {value: 80, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'const side = isTV ? 80 : Math.max(insets.left, space.lg);'},
  playerChromeMs: {value: 4000, file: 'apps/native/src/player/VideoPlayer.tsx', source: '    }, 4000);'},
  playerScrimTop: {value: 260, file: 'apps/native/src/player/VideoPlayer.tsx', source: '<Scrim position="top" height={isTV ? 260 : 160} />'},
  playerScrimBottom: {value: 420, file: 'apps/native/src/player/VideoPlayer.tsx', source: '<Scrim position="bottom" height={isTV ? 420 : 300} />'},
  playerSkipBack: {value: 10, file: 'apps/native/src/player/VideoPlayer.tsx', source: "prefs.value<number>('playback.skipBackSeconds', 10)"},
  playerSkipForward: {value: 30, file: 'apps/native/src/player/VideoPlayer.tsx', source: "prefs.value<number>('playback.skipForwardSeconds', 30)"},
  playerSkipPromptBottom: {value: 260, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'bottom={bottomInset + (isTV ? 260 : 190)}'},
  playerUndoSeconds: {value: 6, file: 'packages/client-core/src/segment-skip.ts', source: 'export const UNDO_SECONDS = 6;'},
  playerUpNextWidth: {value: 560, file: 'apps/native/src/player/UpNextCredits.tsx', source: 'maxWidth: isTV ? 560 : 360'},
  playerUpNextAlpha: {value: 0.86, file: 'apps/native/src/player/UpNextCredits.tsx', source: 'backgroundColor: alpha(colors.ink, 0.86)'},
  playerAudioArtFraction: {value: 0.42, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'isTV ? 0.42 : 0.7'},
  playerAudioTop: {value: 120, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'paddingTop: topInset + (isTV ? 120 : 72)'},
  playerAudioBottom: {value: 320, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'paddingBottom: bottomInset + (isTV ? 320 : 220)'},
  playerPreparingSlowMs: {value: 10000, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'setTimeout(() => setSlow(true), 10000)'},
  playerClockWidth: {value: 160, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'right: 0, bottom: 64, width: 160, height: 32'},
  timelineTrack: {value: 8, file: 'apps/native/src/player/Timeline.tsx', source: 'const trackHeight = isTV ? 8 : 4;'},
  timelineKnob: {value: 22, file: 'apps/native/src/player/Timeline.tsx', source: 'const knob = isTV ? 22 : 14;'},
  timelineTarget: {value: 64, file: 'apps/native/src/player/Timeline.tsx', source: 'height: isTV ? 64 : 32'},
  timelineTrackAlpha: {value: 0.28, file: 'apps/native/src/player/Timeline.tsx', source: 'backgroundColor: alpha(colors.white, 0.28)'},
  timelineKnobFocus: {value: 1.5, file: 'apps/native/src/player/Timeline.tsx', source: 'scale: focused || preview !== undefined ? 1.5 : 1'},
  pillTop: {value: 60, file: 'apps/native/src/player/MiniPlayer.tsx', source: "top: 60, right: 80"},
  pillArt: {value: 48, file: 'apps/native/src/player/MiniPlayer.tsx', source: 'shape="square" width={48} radius={24}'},
  pillMaxWidth: {value: 520, file: 'apps/native/src/player/MiniPlayer.tsx', source: 'maxWidth: 520'},
  pillAlpha: {value: 0.95, file: 'apps/native/src/player/MiniPlayer.tsx', source: 'alpha(colors.material, 0.95)'},
  pillBorderAlpha: {value: 0.5, file: 'apps/native/src/player/MiniPlayer.tsx', source: 'borderColor: alpha(colors.lineStrong, 0.5), maxWidth: 520'},
  pillRight: {value: 80, file: 'apps/native/src/player/MiniPlayer.tsx', source: "top: 60, right: 80"},
  // screens/Search.tsx, screens/Saved.tsx
  searchRecentMax: {value: 8, file: `${screens}/Search.tsx`, source: '.slice(0, 8));'},
  searchTopArt: {value: 160, file: `${screens}/Search.tsx`, source: 'const width = isTV ? 160 : 84;'},
  searchSkeletonCards: {value: 6, file: `${screens}/Search.tsx`, source: '{[0, 1, 2, 3, 4, 5].map(i => ('},
  // screens/title/*, screens/Detail.tsx, screens/Show.tsx
  heroSynopsisMoreAt: {value: 160, file: `${screens}/title/TitleHero.tsx`, source: 'synopsis.length > (isTV ? 160 : phone ? 100 : 160)'},
  heroLogoHeight: {value: 120, file: `${screens}/title/TitleHero.tsx`, source: 'const height = isTV ? 120 : 64;'},
  heroSkeletonEyebrowHeight: {value: 12, file: `${screens}/title/TitleHero.tsx`, source: '<Skeleton height={12} width={120} />'},
  heroSkeletonEyebrowWidth: {value: 120, file: `${screens}/title/TitleHero.tsx`, source: '<Skeleton height={12} width={120} />'},
  heroSkeletonTitleFraction: {value: 0.6, file: `${screens}/title/TitleHero.tsx`, source: '<Skeleton height={metrics.iconLarge} width="60%" />'},
  heroSkeletonLineHeight: {value: 14, file: `${screens}/title/TitleHero.tsx`, source: '<Skeleton height={14} width="80%" />'},
  heroSkeletonLineFraction: {value: 0.8, file: `${screens}/title/TitleHero.tsx`, source: '<Skeleton height={14} width="80%" />'},
  heroTaglineLines: {value: 2, file: `${screens}/title/TitleHero.tsx`, source: "lines={2} style={{maxWidth: synopsisMax, fontStyle: 'italic'}}"},
  episodeRowHeight: {value: 92, file: `${screens}/title/Episodes.tsx`, source: 'const TV_ROW = 92;'},
  episodeRowsVisible: {value: 6, file: `${screens}/title/Episodes.tsx`, source: 'Math.min(total, 6) * TV_ROW'},
  episodeListFraction: {value: 0.42, file: `${screens}/title/Episodes.tsx`, source: '(window.width - space.page * 2) * 0.42'},
  episodePreviewMax: {value: 780, file: `${screens}/title/Episodes.tsx`, source: 'listWidth - space.xxxl, 780)'},
  episodeNumberWidth: {value: 44, file: `${screens}/title/Episodes.tsx`, source: 'style={{width: 44, color: focused ? colors.ink : colors.textTertiary}}'},
  episodeProgressHeight: {value: 3, file: `${screens}/title/Episodes.tsx`, source: 'height={3} style={{maxWidth: 220}}'},
  episodeProgressMax: {value: 220, file: `${screens}/title/Episodes.tsx`, source: 'height={3} style={{maxWidth: 220}}'},
  episodeOverviewLines: {value: 4, file: `${screens}/title/Episodes.tsx`, source: '<Text variant="body" tone="secondary" lines={4}>{shown.overview}</Text>'},
  episodeFocusedMetaAlpha: {value: 0.72, file: `${screens}/title/Episodes.tsx`, source: 'alpha(colors.ink, 0.72)'},
  episodeHighlightAlpha: {value: 0.16, file: `${screens}/title/Episodes.tsx`, source: 'alpha(colors.accent, 0.16)'},
  episodePanelWidth: {value: 640, file: `${screens}/title/EpisodePanel.tsx`, source: '(isTV ? 640 : 440) - space.md * 4'},
  episodePanelProgressMax: {value: 240, file: `${screens}/title/EpisodePanel.tsx`, source: 'maxWidth: 240'},
  rateStars: {value: 5, file: `${screens}/title/TitleSheets.tsx`, source: '{[1, 2, 3, 4, 5].map(stars => ('},
  castOnPage: {value: 12, file: `${screens}/Detail.tsx`, source: 'const CAST_ON_PAGE = 12;'},
  seasonTabLimit: {value: 8, file: `${screens}/title/SeasonSwitcher.tsx`, source: 'const TAB_LIMIT = 8;'},
  nextUpHops: {value: 4, file: `${screens}/Show.tsx`, source: 'const NEXT_UP_HOPS = 4;'},
  scoresOnHero: {value: 3, file: `${screens}/Detail.tsx`, source: '.slice(0, 3).map(r => ({provider: providerLabel(i18n, r.provider)'},
  detailSubtitleLines: {value: 3, file: `${screens}/title/TitleDetails.tsx`, source: 'subtitleLines={3}'},
  fileSubtitleLines: {value: 12, file: `${screens}/title/TitleDetails.tsx`, source: 'subtitleLines={12}'},
  relatedEntries: {value: 12, file: 'apps/native/src/app/detail.ts', source: 'const MORE_LIKE_THIS_ENTRIES = 12;'},
  // screens/Library.tsx, screens/BrowseFilters.tsx, screens/LibraryTabs.tsx
  filterMaxValues: {value: 40, file: `${screens}/BrowseFilters.tsx`, source: 'const MAX_VALUES = 40;'},
  jumpKeyMinWidth: {value: 72, file: `${screens}/BrowseFilters.tsx`, source: 'style={{minWidth: 72}}'},
  jumpMinAnchors: {value: 4, file: `${screens}/BrowseFilters.tsx`, source: 'if (index.length < 4) return null;'},
  trackQueueMax: {value: 200, file: `${screens}/Library.tsx`, source: 'i < index + 200'},
  librarySkeletonRows: {value: 2, file: `${screens}/Library.tsx`, source: 'Array.from({length: columns * 2})'},
  playlistSkeletonWidth: {value: 280, file: `${screens}/LibraryTabs.tsx`, source: '<Skeleton width={280} height={56} />'},
  playlistSkeletonHeight: {value: 56, file: `${screens}/LibraryTabs.tsx`, source: '<Skeleton width={280} height={56} />'},
});
Object.assign(appleLiterals, {
  settingsColumn: {value: 560, file: `${screens}/Settings.tsx`, source: 'const TV_COLUMN = 560;'},
  handoffQr: {value: 200, file: `${screens}/SettingsPages.tsx`, source: 'size={200}'},
  handoffQrRadius: {value: 12, file: `${screens}/SettingsPages.tsx`, source: 'borderRadius: 12'},
  dashboardRefreshMs: {value: 30000, file: `${screens}/server/Dashboard.tsx`, source: "client.measurement('health'), [client], {every: 30000}"},
});
Object.assign(appleLiterals, {
  playerLyricsArtFraction: {value: 0.22, file: 'apps/native/src/player/VideoPlayer.tsx', source: 'lyricsShown ? (isTV ? 0.22 : 0.4)'},
  lyricsAnchorDivisor: {value: 3, file: 'apps/native/src/player/Lyrics.tsx', source: 'y - height / 3'},
  lyricsDimOpacity: {value: 0.5, file: 'apps/native/src/player/Lyrics.tsx', source: 'opacity: active ? 1 : 0.5'},
  lyricsRefreshMs: {value: 30000, file: 'apps/native/src/player/Lyrics.tsx', source: 'setInterval(refresh, 30000)'},
});
