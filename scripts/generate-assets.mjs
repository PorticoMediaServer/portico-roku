import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const outputRootIndex = process.argv.indexOf('--output-root');
const outputRoot = outputRootIndex >= 0 ? resolve(process.argv[outputRootIndex + 1] ?? '') : root;
if (outputRootIndex >= 0 && !process.argv[outputRootIndex + 1]) throw new Error('--output-root requires a directory.');
const iconDirectory = join(outputRoot, 'channel/images/icons');
const uiDirectory = join(outputRoot, 'channel/images/ui');
const posterDirectory = join(outputRoot, 'channel/images/posters');
const backdropDirectory = join(outputRoot, 'channel/images/backdrops');
mkdirSync(iconDirectory, {recursive: true});
mkdirSync(uiDirectory, {recursive: true});
mkdirSync(posterDirectory, {recursive: true});
mkdirSync(backdropDirectory, {recursive: true});

const icons = {
  home: '<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  search: '<path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/>',
  library: '<path d="m16 6 4 14"/><path d="M12 6v14"/><path d="M8 8v12"/><path d="M4 4v16"/>',
  radio: '<path d="M16.247 7.761a6 6 0 0 1 0 8.478"/><path d="M19.075 4.933a10 10 0 0 1 0 14.134"/><path d="M4.925 19.067a10 10 0 0 1 0-14.134"/><path d="M7.753 16.239a6 6 0 0 1 0-8.478"/><circle cx="12" cy="12" r="2"/>',
  bookmark: '<path d="M17 3a2 2 0 0 1 2 2v15a1 1 0 0 1-1.496.868l-4.512-2.578a2 2 0 0 0-1.984 0l-4.512 2.578A1 1 0 0 1 5 20V5a2 2 0 0 1 2-2z"/>',
  film: '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M7 3v18M3 7.5h4M3 12h18M3 16.5h4M17 3v18M17 7.5h4M17 16.5h4"/>',
  tv: '<path d="m17 2-5 5-5-5"/><rect width="20" height="15" x="2" y="7" rx="2"/>',
  music: '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
  mic2: '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><path d="M12 19v3"/>',
  user: '<circle cx="12" cy="8" r="5"/><path d="M20 21a8 8 0 0 0-16 0"/>',
  settings: '<path d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"/><circle cx="12" cy="12" r="3"/>',
  'refresh-cw': '<path d="M20 11a8.1 8.1 0 0 0-15.5-2M4 4v5h5"/><path d="M4 13a8.1 8.1 0 0 0 15.5 2M20 20v-5h-5"/>',
  'chevron-right': '<path d="m9 18 6-6-6-6"/>',
  'chevron-left': '<path d="m15 18-6-6 6-6"/>',
  'chevron-down': '<path d="m6 9 6 6 6-6"/>',
  'chevron-up': '<path d="m18 15-6-6-6 6"/>',
  'triangle-alert': '<path d="m21.73 18-8-14a2 2 0 0 0-3.46 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  'sliders-horizontal': '<line x1="21" x2="14" y1="4" y2="4"/><line x1="10" x2="3" y1="4" y2="4"/><line x1="21" x2="12" y1="12" y2="12"/><line x1="8" x2="3" y1="12" y2="12"/><line x1="21" x2="16" y1="20" y2="20"/><line x1="12" x2="3" y1="20" y2="20"/><line x1="14" x2="14" y1="2" y2="6"/><line x1="8" x2="8" y1="10" y2="14"/><line x1="16" x2="16" y1="18" y2="22"/>',
  'arrow-down-az': '<path d="m3 16 4 4 4-4"/><path d="M7 20V4"/><path d="M20 8h-5"/><path d="M15 10V6.5a2.5 2.5 0 0 1 5 0V10"/><path d="M15 14h5l-5 6h5"/>',
  grid3x3: '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18M3 15h18M9 3v18M15 3v18"/>',
  list: '<path d="M3 6h.01M3 12h.01M3 18h.01M8 6h13M8 12h13M8 18h13"/>',
  ellipsis: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  star: '<path d="M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.12 2.12 0 0 0 1.595 1.16l5.166.75a.53.53 0 0 1 .294.904l-3.738 3.643a2.12 2.12 0 0 0-.61 1.88l.882 5.146a.53.53 0 0 1-.77.559l-4.62-2.429a2.12 2.12 0 0 0-1.969 0l-4.62 2.43a.53.53 0 0 1-.77-.56l.882-5.145a2.12 2.12 0 0 0-.61-1.88L2.16 9.787a.53.53 0 0 1 .294-.903l5.165-.751a2.12 2.12 0 0 0 1.597-1.16z"/>',
  'thumbs-up': '<path d="M7 10v12"/><path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2h0a3.13 3.13 0 0 1 3 3.88Z"/>',
  'thumbs-down': '<path d="M17 14V2"/><path d="M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22h0a3.13 3.13 0 0 1-3-3.88Z"/>',
  'list-plus': '<path d="M11 12H3M16 6H3M16 18H3M18 9v6M21 12h-6"/>',
  'list-music': '<path d="M21 15V6M18.5 18a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5ZM12 12H3M16 6H3M12 18H3"/>',
  'folder-heart': '<path d="M10 4H2v16h20V6H12l-2-2Z"/><path d="M14.5 11.5a2.5 2.5 0 0 0-5 0c0 2.5 2.5 4 2.5 4s2.5-1.5 2.5-4Z"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  play: '<path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/>',
  pause: '<rect x="14" y="4" width="4" height="16" rx="1"/><rect x="6" y="4" width="4" height="16" rx="1"/>',
  'skip-back': '<path d="M17.971 4.285A2 2 0 0 1 21 6v12a2 2 0 0 1-3.029 1.715l-10-6a2 2 0 0 1 0-3.43z"/><path d="M3 20V4"/>',
  'rotate-ccw': '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/>',
  'rotate-cw': '<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>',
  plus: '<path d="M5 12h14M12 5v14"/>',
  heart: '<path d="M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5"/>',
  headphones: '<path d="M4 14a8 8 0 0 1 16 0"/><path d="M18 19c0 1.1-.9 2-2 2h-1v-7h3a2 2 0 0 1 2 2v1a2 2 0 0 1-2 2z"/><path d="M6 19c0 1.1.9 2 2 2h1v-7H6a2 2 0 0 0-2 2v1a2 2 0 0 0 2 2z"/>',
  languages: '<path d="m5 8 6 6"/><path d="m4 14 6-6 2-3"/><path d="M2 5h12"/><path d="M7 2h1"/><path d="m22 22-5-10-5 10"/><path d="M14 18h6"/>',
  captions: '<rect width="20" height="16" x="2" y="4" rx="2"/><path d="M7 15h4M7 9h2M13 15h4M13 9h4"/>',
  gauge: '<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>',
  accessibility: '<circle cx="16" cy="4" r="1"/><path d="m18 19 1-7-6 1"/><path d="m5 8 3-3 5.5 3-2.36 3.5"/><path d="M4.24 14.5a5 5 0 0 0 6.88 6"/><path d="M13.76 17.5a5 5 0 0 0-6.88-6"/>',
  'log-out': '<path d="M10 17l5-5-5-5"/><path d="M15 12H3"/><path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/>',
  wifi: '<path d="M12 20h.01"/><path d="M2 8.82a15 15 0 0 1 20 0"/><path d="M5 12.859a10 10 0 0 1 14 0"/><path d="M8.5 16.429a5 5 0 0 1 7 0"/>',
  'image-off': '<path d="m2 2 20 20"/><path d="M10.41 10.41a2 2 0 0 0 2.83 2.83"/><path d="M13.5 5H19a2 2 0 0 1 2 2v10.5"/><path d="M3 3v16a2 2 0 0 0 2 2h16"/><path d="m3 17 5-5 4 4"/>'
};

function renderSvg(svg, outputPath, width, height, {requireAlpha = false} = {}) {
  const result = spawnSync('rsvg-convert', ['-w', String(width), '-h', String(height), '-o', outputPath], {
    encoding: 'utf8',
    input: svg
  });
  if (result.status !== 0) throw new Error(`rsvg-convert failed for ${outputPath}: ${result.stderr}`);
  if (requireAlpha) {
    const alphaResult = spawnSync('magick', [outputPath, '-define', 'png:color-type=6', outputPath], {encoding: 'utf8'});
    if (alphaResult.status !== 0) throw new Error(`ImageMagick failed to preserve alpha for ${outputPath}: ${alphaResult.stderr}`);
  }
}

function iconSvg(body, color) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
}

for (const [name, body] of Object.entries(icons)) {
  renderSvg(iconSvg(body, '#F4F7FA'), join(iconDirectory, `${name}.png`), 64, 64);
  renderSvg(iconSvg(body, '#070B10'), join(iconDirectory, `${name}-dark.png`), 64, 64);
  renderSvg(iconSvg(body, '#C7D0D8'), join(iconDirectory, `${name}-rail.png`), 64, 64);
  const selectedFill = name === 'home' ? '#70BCE8' : 'none';
  const selected = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="${selectedFill}" stroke="#70BCE8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
  renderSvg(selected, join(iconDirectory, `${name}-selected.png`), 64, 64);
}

const surface = (width, height, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${body}</svg>`;
const rounded = (width, height, radius, fill, stroke = 'none', strokeWidth = 0) => `<rect x="${strokeWidth / 2}" y="${strokeWidth / 2}" width="${width - strokeWidth}" height="${height - strokeWidth}" rx="${radius}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}"/>`;
const cornerCaps = (width, height, radius, fill) => `<path fill="${fill}" fill-rule="evenodd" d="M0 0H${width}V${height}H0Z M${radius} 0H${width - radius}A${radius} ${radius} 0 0 1 ${width} ${radius}V${height - radius}A${radius} ${radius} 0 0 1 ${width - radius} ${height}H${radius}A${radius} ${radius} 0 0 1 0 ${height - radius}V${radius}A${radius} ${radius} 0 0 1 ${radius} 0Z"/>`;

const surfaces = [
  ['button-primary.png', 166, 64, rounded(166, 64, 8, '#70BCE8', '#70BCE8', 3)],
  ['button-primary-focus.png', 166, 64, rounded(166, 64, 8, '#378EC3', '#EAF6FF', 3)],
  ['button-dark.png', 166, 64, rounded(166, 64, 8, 'rgba(0,0,0,0)', 'rgba(197,218,235,.08)', 3)],
  ['button-dark-focus.png', 166, 64, rounded(166, 64, 8, 'rgba(0,0,0,0)', '#EAF6FF', 3)],
  ['icon-button.png', 64, 64, rounded(64, 64, 32, 'rgba(7,11,16,.84)', 'rgba(197,218,235,.08)', 3)],
  ['icon-button-focus.png', 64, 64, rounded(64, 64, 32, 'rgba(7,11,16,.84)', '#EAF6FF', 3)],
  ['icon-button-selected.png', 64, 64, rounded(64, 64, 32, '#1A2632', 'rgba(112,188,232,.30)', 3)],
  ['icon-button-selected-focus.png', 64, 64, rounded(64, 64, 32, '#1A2632', '#EAF6FF', 3)],
  ['rail-bed-collapsed.png', 80, 1032, '<rect width="80" height="1032" fill="#070B10"/><rect x="79" width="1" height="1032" fill="rgba(199,208,216,.12)"/>'],
  ['rail-bed-expanded.png', 280, 1032, '<rect width="280" height="1032" fill="#070B10"/><rect x="279" width="1" height="1032" fill="rgba(199,208,216,.12)"/>'],
  ['rail-selected-collapsed.png', 64, 64, rounded(64, 64, 8, '#151F29')],
  ['rail-selected-expanded.png', 264, 64, rounded(264, 64, 8, '#151F29')],
  ['rail-focus-collapsed.png', 64, 64, rounded(64, 64, 8, '#1A2632', '#EAF6FF', 3)],
  ['rail-focus-expanded.png', 264, 64, rounded(264, 64, 8, '#1A2632', '#EAF6FF', 3)],
  ['brand-mark-bed.png', 38, 38, rounded(38, 38, 8, '#286F9D')],
  ['poster-card-focus.png', 214, 395, rounded(214, 395, 10, '#151F29', '#EAF6FF', 3)],
  ['landscape-card-focus.png', 320, 248, rounded(320, 248, 10, '#151F29', '#EAF6FF', 3)],
  ['poster-artwork-corners.png', 202, 321, cornerCaps(202, 321, 8, '#070B10')],
  ['poster-artwork-corners-focus.png', 202, 321, cornerCaps(202, 321, 8, '#151F29')],
  ['landscape-artwork-corners.png', 308, 180, cornerCaps(308, 180, 8, '#070B10')],
  ['landscape-artwork-corners-focus.png', 308, 180, cornerCaps(308, 180, 8, '#151F29')],
  ['overlay-scrim.png', 1920, 1080, '<rect width="1920" height="1080" fill="rgba(0,0,0,.72)"/>'],
  ['server-row-idle.png', 700, 82, rounded(700, 82, 8, 'rgba(0,0,0,0)')],
  ['server-row-selected.png', 700, 82, rounded(700, 82, 8, '#151F29')],
  ['server-row-focus.png', 700, 82, rounded(700, 82, 8, '#1A2632', '#EAF6FF', 3)],
  ['server-row-selected-focus.png', 700, 82, rounded(700, 82, 8, '#1A2632', '#EAF6FF', 3)],
  ['server-radio.png', 28, 28, '<circle cx="14" cy="14" r="9" fill="none" stroke="#687581" stroke-width="2"/>'],
  ['server-radio-focus.png', 28, 28, '<circle cx="14" cy="14" r="9" fill="none" stroke="#EAF6FF" stroke-width="2"/>'],
  ['server-radio-selected.png', 28, 28, '<circle cx="14" cy="14" r="9" fill="none" stroke="#70BCE8" stroke-width="2"/><circle cx="14" cy="14" r="4.5" fill="#70BCE8"/>'],
  ['server-radio-selected-focus.png', 28, 28, '<circle cx="14" cy="14" r="9" fill="none" stroke="#EAF6FF" stroke-width="2"/><circle cx="14" cy="14" r="4.5" fill="#70BCE8"/>'],
  ['server-avatar.png', 52, 52, '<circle cx="26" cy="26" r="26" fill="#286F9D"/>']
  ,['search-field-idle.png', 1200, 68, rounded(1200, 68, 8, '#101820', 'rgba(197,218,235,.14)', 3)]
  ,['search-field-focus.png', 1200, 68, rounded(1200, 68, 8, '#101820', '#EAF6FF', 3)]
  ,['search-keyboard-panel.png', 1200, 288, rounded(1200, 288, 10, '#101820', 'rgba(197,218,235,.14)', 1)]
  ,['search-key-idle.png', 104, 56, rounded(104, 56, 8, '#0A1017', 'rgba(197,218,235,.08)', 2)]
  ,['search-key-focus.png', 104, 56, rounded(104, 56, 8, '#1A2632', '#EAF6FF', 3)]
  ,['search-result-idle.png', 846, 174, rounded(846, 174, 8, '#0A1017', 'rgba(197,218,235,.08)', 1)]
  ,['search-result-focus.png', 846, 174, rounded(846, 174, 8, '#151F29', '#EAF6FF', 3)]
  ,['search-result-artwork-corners.png', 100, 150, cornerCaps(100, 150, 6, '#0A1017')]
  ,['search-result-artwork-corners-focus.png', 100, 150, cornerCaps(100, 150, 6, '#151F29')]
  ,['browse-tab-idle.png', 168, 68, rounded(168, 68, 8, 'rgba(0,0,0,0)')]
  ,['browse-tab-focus.png', 168, 68, rounded(168, 68, 8, '#151F29')]
  ,['browse-action-idle.png', 360, 64, rounded(360, 64, 8, 'rgba(0,0,0,0)', 'rgba(197,218,235,.08)', 3)]
  ,['browse-action-focus.png', 360, 64, rounded(360, 64, 8, '#151F29', '#EAF6FF', 3)]
  ,['browse-action-selected.png', 360, 64, rounded(360, 64, 8, '#1A2632', 'rgba(112,188,232,.30)', 3)]
  ,['square-card-focus.png', 214, 288, rounded(214, 288, 10, '#151F29', '#EAF6FF', 3)]
  ,['square-artwork-corners.png', 202, 202, cornerCaps(202, 202, 8, '#070B10')]
  ,['square-artwork-corners-focus.png', 202, 202, cornerCaps(202, 202, 8, '#151F29')]
  ,['browse-list-idle.png', 1712, 158, rounded(1712, 158, 8, '#0A1017', 'rgba(197,218,235,.08)', 1)]
  ,['browse-list-focus.png', 1712, 158, rounded(1712, 158, 8, '#151F29', '#EAF6FF', 3)]
  ,['browse-list-artwork-corners.png', 235, 132, cornerCaps(235, 132, 6, '#0A1017')]
  ,['browse-list-artwork-corners-focus.png', 235, 132, cornerCaps(235, 132, 6, '#151F29')]
  ,['browse-facet-idle.png', 250, 150, rounded(250, 150, 10, '#0A1017', 'rgba(197,218,235,.08)', 2)]
  ,['browse-facet-focus.png', 250, 150, rounded(250, 150, 10, '#151F29', '#EAF6FF', 3)]
  ,['browse-resource-idle.png', 530, 190, rounded(530, 190, 10, '#0A1017', 'rgba(197,218,235,.08)', 2)]
  ,['browse-resource-focus.png', 530, 190, rounded(530, 190, 10, '#151F29', '#EAF6FF', 3)]
  ,['state-icon-bed.png', 82, 82, rounded(82, 82, 41, '#101820')]
  ,['auth-action-primary.png', 560, 72, rounded(560, 72, 8, '#70BCE8', '#70BCE8', 3)]
  ,['auth-action-primary-focus.png', 560, 72, rounded(560, 72, 8, '#378EC3', '#EAF6FF', 3)]
  ,['auth-action-secondary.png', 560, 72, rounded(560, 72, 8, 'rgba(0,0,0,0)', 'rgba(112,188,232,.30)', 3)]
  ,['auth-action-secondary-focus.png', 560, 72, rounded(560, 72, 8, '#1A2632', '#EAF6FF', 3)]
  ,['auth-action-tertiary.png', 560, 72, rounded(560, 72, 8, '#101820', 'rgba(112,188,232,.30)', 3)]
  ,['auth-action-tertiary-focus.png', 560, 72, rounded(560, 72, 8, '#151F29', '#EAF6FF', 3)]
  ,['auth-field-idle.png', 560, 72, rounded(560, 72, 8, '#101820', 'rgba(112,188,232,.30)', 3)]
  ,['auth-field-focus.png', 560, 72, rounded(560, 72, 8, '#151F29', '#EAF6FF', 3)]
  ,['player-overlay-scrim.png', 1920, 1080, '<rect width="1920" height="1080" fill="rgba(0,0,0,.34)"/>']
  ,['player-transport-dock.png', 286, 88, rounded(286, 88, 44, 'rgba(7,11,16,.72)', 'rgba(197,218,235,.14)', 1)]
  ,['player-transport-idle.png', 60, 60, rounded(60, 60, 30, 'rgba(0,0,0,0)')]
  ,['player-transport-focus.png', 60, 60, rounded(60, 60, 30, 'rgba(244,247,250,.30)', '#EAF6FF', 3)]
  ,['player-transport-main.png', 78, 78, rounded(78, 78, 39, 'rgba(244,247,250,.22)')]
  ,['player-transport-main-focus.png', 78, 78, rounded(78, 78, 39, 'rgba(244,247,250,.30)', '#EAF6FF', 3)]
  ,['player-ended-panel.png', 520, 230, rounded(520, 230, 16, 'rgba(7,11,16,.88)', 'rgba(197,218,235,.14)', 1)]
  ,['player-error-panel.png', 700, 280, rounded(700, 280, 16, 'rgba(7,11,16,.92)', 'rgba(197,218,235,.14)', 1)]
  ,['player-spinner.png', 56, 56, '<g fill="none" stroke="#F4F7FA" stroke-width="4" stroke-linecap="round"><path d="M28 5v7" opacity="1"/><path d="M44.3 11.7l-5 5" opacity=".85"/><path d="M51 28h-7" opacity=".72"/><path d="M44.3 44.3l-5-5" opacity=".60"/><path d="M28 51v-7" opacity=".48"/><path d="M11.7 44.3l5-5" opacity=".36"/><path d="M5 28h7" opacity=".24"/><path d="M11.7 11.7l5 5" opacity=".12"/></g>']
  ,['settings-row-idle.png', 1600, 94, rounded(1600, 94, 8, '#0A1017', 'rgba(197,218,235,.08)', 1)]
  ,['settings-row-focus.png', 1600, 94, rounded(1600, 94, 8, '#151F29', '#EAF6FF', 3)]
  ,['settings-summary.png', 1080, 190, rounded(1080, 190, 14, '#101820', 'rgba(197,218,235,.14)', 1)]
  ,['settings-avatar.png', 112, 112, '<circle cx="56" cy="56" r="56" fill="#286F9D"/><circle cx="56" cy="56" r="54.5" fill="none" stroke="rgba(234,246,255,.18)" stroke-width="3"/>']
  ,['settings-modal.png', 760, 450, rounded(760, 450, 16, '#101820', 'rgba(197,218,235,.16)', 1)]
  ,['settings-choice-idle.png', 680, 74, rounded(680, 74, 8, 'rgba(0,0,0,0)')]
  ,['settings-choice-selected.png', 680, 74, rounded(680, 74, 8, '#151F29')]
  ,['settings-choice-focus.png', 680, 74, rounded(680, 74, 8, '#1A2632', '#EAF6FF', 3)]
  ,['settings-toggle-off.png', 62, 36, rounded(62, 36, 18, '#26323D') + '<circle cx="18" cy="18" r="14" fill="#C7D0D8"/>']
  ,['settings-toggle-on.png', 62, 36, rounded(62, 36, 18, '#286F9D') + '<circle cx="44" cy="18" r="14" fill="#F4F7FA"/>']
];

for (let visibleRows = 1; visibleRows <= 6; visibleRows += 1) {
  const height = 382 + (visibleRows * 82);
  surfaces.push([
    `server-panel-${visibleRows}.png`,
    720,
    height,
    rounded(720, height, 14, '#101820', 'rgba(197,218,235,.14)', 1)
  ]);
}
surfaces.push([
  'server-panel-compact.png',
  720,
  382,
  rounded(720, 382, 14, '#101820', 'rgba(197,218,235,.14)', 1)
]);

for (const [name, width, height, body] of surfaces) {
  renderSvg(surface(width, height, body), join(uiDirectory, name), width, height);
}

const horizontal = `<defs><linearGradient id="h"><stop offset="0" stop-color="#070B10" stop-opacity=".94"/><stop offset=".48" stop-color="#070B10" stop-opacity=".68"/><stop offset="1" stop-color="#070B10" stop-opacity=".08"/></linearGradient></defs><rect width="1784" height="570" fill="url(#h)"/>`;
const verticalHome = `<defs><linearGradient id="v" x2="0%" y2="100%"><stop offset="0" stop-color="#070B10" stop-opacity=".10"/><stop offset=".5" stop-color="#070B10" stop-opacity=".12"/><stop offset="1" stop-color="#070B10" stop-opacity="1"/></linearGradient></defs><rect width="1784" height="430" fill="url(#v)"/>`;
const verticalStrong = `<defs><linearGradient id="v" x2="0%" y2="100%"><stop offset="0" stop-color="#070B10" stop-opacity=".28"/><stop offset=".5" stop-color="#070B10" stop-opacity=".46"/><stop offset="1" stop-color="#070B10" stop-opacity="1"/></linearGradient></defs><rect width="1784" height="570" fill="url(#v)"/>`;
renderSvg(surface(1784, 570, horizontal), join(uiDirectory, 'hero-horizontal.png'), 1784, 570);
renderSvg(surface(1784, 430, verticalHome), join(uiDirectory, 'hero-vertical-home.png'), 1784, 430);
renderSvg(surface(1784, 570, verticalStrong), join(uiDirectory, 'hero-vertical-strong.png'), 1784, 570);

const wordmark = readFileSync(join(root, 'channel/images/brand/portico-wordmark.png')).toString('base64');
const channelPoster = `<defs><linearGradient id="channel" x2="1" y2="1"><stop stop-color="#1D4277"/><stop offset="1" stop-color="#08131F"/></linearGradient></defs><rect width="540" height="405" rx="34" fill="url(#channel)"/><image href="data:image/png;base64,${wordmark}" x="66" y="156" width="408" height="93" preserveAspectRatio="xMidYMid meet"/>`;
renderSvg(surface(540, 405, channelPoster), join(uiDirectory, 'channel-poster-fhd.png'), 540, 405);

// Deterministic, synthetic media art keeps visual tests self-contained. These
// files are excluded from release packages and carry no third-party artwork.
const fixturePalette = ['#173A55', '#4B2936', '#254C42', '#513A22', '#31325C', '#244154', '#52343A', '#23483D', '#4A3A57'];
const posterNames = ['fargo', 'rookie', 'hurt-locker', 'dolphin-reef', 'earth-stood-still', 'martian', 'blade-runner', 'life-aquatic', 'project-hail-mary'];
for (const [index, name] of posterNames.entries()) {
  const color = fixturePalette[index % fixturePalette.length];
  const body = `<defs><linearGradient id="fixture-${index}" x2="1" y2="1"><stop stop-color="${color}"/><stop offset="1" stop-color="#070B10"/></linearGradient></defs><rect width="202" height="321" fill="url(#fixture-${index})"/><circle cx="150" cy="74" r="58" fill="rgba(112,188,232,.18)"/><path d="M24 274h154" stroke="rgba(244,247,250,.30)" stroke-width="4"/>`;
  renderSvg(surface(202, 321, body), join(posterDirectory, `${name}.png`), 202, 321, {requireAlpha: true});
}
for (const [index, name] of ['rookie-episode-1', 'rookie-episode-2', 'rookie-episode-3'].entries()) {
  const body = `<defs><linearGradient id="episode-${index}" x2="1" y2="1"><stop stop-color="${fixturePalette[index + 1]}"/><stop offset="1" stop-color="#070B10"/></linearGradient></defs><rect width="308" height="180" fill="url(#episode-${index})"/><circle cx="238" cy="52" r="46" fill="rgba(112,188,232,.16)"/>`;
  renderSvg(surface(308, 180, body), join(backdropDirectory, `${name}.png`), 308, 180, {requireAlpha: true});
}
for (const [index, name] of ['fargo', 'rookie'].entries()) {
  const body = `<defs><linearGradient id="backdrop-${index}" x2="1" y2="1"><stop stop-color="${fixturePalette[index]}"/><stop offset="1" stop-color="#070B10"/></linearGradient></defs><rect width="1280" height="720" fill="url(#backdrop-${index})"/><circle cx="980" cy="210" r="230" fill="rgba(112,188,232,.14)"/>`;
  renderSvg(surface(1280, 720, body), join(backdropDirectory, `${name}.png`), 1280, 720);
}

writeFileSync(join(uiDirectory, 'GENERATED-ASSETS.txt'), 'Generated deterministically by scripts/generate-assets.mjs.\n');
console.log(`Generated ${Object.keys(icons).length * 4 + surfaces.length + 18} Roku PNG assets.`);
