import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve, extname} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const channel = join(root, 'channel');
const output = join(root, 'artifacts/golden');
const contract = JSON.parse(readFileSync(join(channel, 'data/visual-contract.json'), 'utf8'));
const semanticIcons = JSON.parse(readFileSync(join(channel, 'data/generated/roku-icons.v1.json'), 'utf8'));
const requestedRenders = new Set(process.argv.slice(2));
mkdirSync(output, {recursive: true});

const mime = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg'};
const imageCache = new Map();
function imageUri(uri) {
  if (imageCache.has(uri)) return imageCache.get(uri);
  const path = uri.startsWith('pkg:/') ? join(channel, uri.slice(5)) : uri;
  const value = `data:${mime[extname(path).toLowerCase()]};base64,${readFileSync(path).toString('base64')}`;
  imageCache.set(uri, value);
  return value;
}

function escapeXml(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function image(uri, x, y, width, height, opacity = 1, displayMode = 'fill') {
  const aspect = displayMode === 'cover' ? 'xMidYMid slice' : displayMode === 'contain' ? 'xMidYMid meet' : 'none';
  return `<image href="${imageUri(uri)}" x="${x}" y="${y}" width="${width}" height="${height}" opacity="${opacity}" preserveAspectRatio="${aspect}"/>`;
}

function text(value, x, y, size, weight, color, options = {}) {
  const {width, anchor = 'start', opacity = 1} = options;
  const clip = width ? ` textLength="${Math.min(width, Math.max(1, value.length * size * .54))}" lengthAdjust="spacingAndGlyphs"` : '';
  return `<text x="${x}" y="${y + size * .82}" fill="${color}" opacity="${opacity}" font-family="Manrope" font-size="${size}" font-weight="${weight}" text-anchor="${anchor}"${clip}>${escapeXml(value)}</text>`;
}

function breakText(value, maxCharacters, maxLines = 2) {
  const words = value.split(/\s+/);
  const lines = [];
  let line = '';
  for (const word of words) {
    const next = line ? `${line} ${word}` : word;
    if (next.length > maxCharacters && line) {
      lines.push(line);
      line = word;
    } else {
      line = next;
    }
  }
  if (line) lines.push(line);
  if (lines.length > maxLines) {
    const clipped = lines.slice(0, maxLines);
    clipped[maxLines - 1] = `${clipped[maxLines - 1].slice(0, Math.max(1, maxCharacters - 3)).trimEnd()}...`;
    return clipped;
  }
  return lines;
}

function prebrokenText(lines, x, y, size, weight, color, lineHeight) {
  return lines.map((entry, index) => text(entry, x, y + index * lineHeight, size, weight, color)).join('');
}

function truncate(value, maximum = 20) {
  return value.length > maximum ? `${value.slice(0, maximum - 1).trimEnd()}…` : value;
}

function icon(name, x, y, size, variant = '') {
  return image(`pkg:/images/icons/${name}${variant}.png`, x, y, size, size, 1, 'contain');
}

function controlButton(label, iconName, x, y, width = 166, primary = true, focused = false) {
  const surface = primary ? 'button-primary.png' : focused ? 'button-dark-focus.png' : 'button-dark.png';
  return [
    image(`pkg:/images/ui/${surface}`, x, y, width, 64),
    icon(iconName, x + 22, y + 19, 26, primary ? '-dark' : ''),
    text(label, x + 60, y + 18, 21, 600, primary ? contract.colors.projector : contract.colors.silver)
  ].join('');
}

function iconButton(iconName, x, y, focused = false, selected = false) {
  const state = selected ? (focused ? 'icon-button-selected-focus.png' : 'icon-button-selected.png') : (focused ? 'icon-button-focus.png' : 'icon-button.png');
  return image(`pkg:/images/ui/${state}`, x, y, 64, 64) + icon(iconName, x + 17, y + 17, contract.controls.iconGlyphSize, selected ? '-selected' : '');
}

function card(model, x, y, focused = false, shape = 'poster') {
  const landscape = shape === 'landscape';
  const outerWidth = landscape ? 320 : 214;
  const outerHeight = landscape ? contract.shelf.landscapeCardHeight : contract.shelf.cardHeight;
  const artworkWidth = landscape ? 308 : 202;
  const artworkHeight = landscape ? 180 : 321;
  const artwork = landscape ? model.artwork : model.poster;
  const parts = [];
  if (focused) parts.push(image(`pkg:/images/ui/${landscape ? 'landscape-card-focus.png' : 'poster-card-focus.png'}`, x, y, outerWidth, outerHeight));
  parts.push(`<rect x="${x + 6}" y="${y + 6}" width="${artworkWidth}" height="${artworkHeight}" fill="${contract.colors.recess}"/>`);
  if (artwork) {
    parts.push(image(artwork, x + 6, y + 6, artworkWidth, artworkHeight, 1, 'cover'));
  } else {
    parts.push(icon('image-off', x + 6 + (artworkWidth - 40) / 2, y + 6 + (artworkHeight - 40) / 2, 40, '-rail'));
  }
  if (model.progress !== undefined) {
    const progressWidth = Math.max(Math.round((artworkWidth - 10) * .04), Math.round((artworkWidth - 10) * model.progress / 100));
    parts.push(`<rect x="${x + 11}" y="${y + artworkHeight - 3}" width="${artworkWidth - 10}" height="4" fill="#F4F7FA" opacity=".28"/>`);
    parts.push(`<rect x="${x + 11}" y="${y + artworkHeight - 3}" width="${progressWidth}" height="4" fill="#70BCE8"/>`);
  }
  parts.push(image(`pkg:/images/ui/${landscape ? 'landscape' : 'poster'}-artwork-corners${focused ? '-focus' : ''}.png`, x + 6, y + 6, artworkWidth, artworkHeight));
  parts.push(text(truncate(model.title, landscape ? 28 : 20), x + 6, y + artworkHeight + 17, 21, 600, contract.colors.silver));
  parts.push(text(model.meta, x + 6, y + artworkHeight + 45, 18, 400, contract.colors.dimSilver));
  return parts.join('');
}

function railIcon(semanticId, x, y, size, selected = false) {
  const master = semanticIcons.semanticToMaster[semanticId];
  const state = selected ? 'selected' : 'rail';
  const path = master && semanticIcons.masters[master]?.[state]?.path;
  assert(path, `Unknown semantic rail icon: ${semanticId}`);
  return image(`pkg:/images/icons/generated/${path}`, x, y, size, size);
}

function rail(expanded, focusedIndex = -1, selectedId = '') {
  const x = 24;
  const y = 24;
  const width = expanded ? 280 : 80;
  const parts = [image(`pkg:/images/ui/rail-bed-${expanded ? 'expanded' : 'collapsed'}.png`, x, y, width, 1032)];
  if (expanded) {
    parts.push(image('pkg:/images/brand/portico-wordmark.png', x + 19, y + 28, 154, 34, 1, 'contain'));
  } else {
    parts.push(image('pkg:/images/ui/brand-mark-bed.png', x + 19, y + 26, 38, 38));
    parts.push(image('pkg:/images/brand/portico-symbol.png', x + 24, y + 31, 28, 28, 1, 'contain'));
  }
  const itemsX = x + 8;
  const itemsY = y + 74;
  const entries = [
    ...contract.railPrimaryItems.map((item, index) => ({item, itemY: index * 68})),
    ...contract.railLibraryItems.map((item, index) => ({item, itemY: 357 + index * 66})),
    ...contract.railBottomItems.map((item, index) => ({item, itemY: 812 + index * 66}))
  ];
  for (let index = 0; index < entries.length; index++) {
    const {item, itemY} = entries[index];
    const selected = selectedId ? item.id === selectedId : item.selected === true;
    if (focusedIndex === index || selected) {
      const state = focusedIndex === index ? 'focus' : 'selected';
      parts.push(image(`pkg:/images/ui/rail-${state}-${expanded ? 'expanded' : 'collapsed'}.png`, itemsX, itemsY + itemY, expanded ? 264 : 64, 64));
    }
    if (selected) parts.push(`<rect x="${itemsX}" y="${itemsY + itemY + 8}" width="3" height="48" fill="#378EC3"/>`);
    parts.push(railIcon(item.iconId, itemsX + 18, itemsY + itemY + 18, 28, selected));
    if (expanded) parts.push(text(item.label, itemsX + 64, itemsY + itemY + 18, 21, 600, contract.colors.silver));
  }
  parts.push(`<rect x="${x + 16}" y="${y + 420}" width="${width - 32}" height="1" fill="#8F9BA6" opacity=".22"/>`);
  return parts.join('');
}

function serverPickerAction(label, iconName, y, focused) {
  const x = 1120;
  return [
    image(`pkg:/images/ui/server-row-${focused ? 'focus' : 'idle'}.png`, x, y, 700, 82),
    icon(iconName, x + 16, y + 27, 28, '-rail'),
    text(label, x + 62, y + 26, 22, 600, contract.colors.silver),
    icon('chevron-right', x + 656, y + 27, 28, '-rail')
  ].join('');
}

function serverPickerStateOverlay({status, body, tone, actions}) {
  const panelX = 1110;
  const panelY = 90;
  const panelHeight = actions.length === 1 ? 382 : 464;
  const panelAsset = actions.length === 1 ? 'server-panel-compact.png' : 'server-panel-1.png';
  const statusColors = {
    account: contract.colors.screenBlueStrong,
    danger: '#ED5B67',
    warning: '#D7A34D'
  };
  const parts = [
    image('pkg:/images/ui/overlay-scrim.png', 0, 0, 1920, 1080),
    image(`pkg:/images/ui/${panelAsset}`, panelX, panelY, 720, panelHeight),
    text('Profile and server', panelX + 22, panelY + 24, 30, 600, contract.colors.silver),
    iconButton('x', panelX + 634, panelY + 11),
    `<rect x="${panelX}" y="${panelY + 86}" width="720" height="1" fill="#33404A" opacity=".55"/>`,
    image('pkg:/images/ui/server-avatar.png', panelX + 22, panelY + 107, 52, 52),
    text('JE', panelX + 48, panelY + 123, 17, 700, contract.colors.silver, {anchor: 'middle'}),
    text('Justin Ehler', panelX + 88, panelY + 100, 25, 600, contract.colors.silver),
    text('No server selected', panelX + 88, panelY + 138, 18, 400, contract.colors.dimSilver),
    `<rect x="${panelX + 22}" y="${panelY + 178}" width="676" height="1" fill="#33404A" opacity=".35"/>`,
    text(status, panelX + 26, panelY + 199, 17, 600, statusColors[tone] ?? contract.colors.dimSilver),
    text(body, panelX + 26, panelY + 230, 18, 400, contract.colors.softSilver),
    `<rect x="${panelX + 22}" y="${panelY + 280}" width="676" height="1" fill="#33404A" opacity=".35"/>`
  ];
  actions.forEach((action, index) => parts.push(serverPickerAction(action.label, action.icon, panelY + 290 + index * 82, index === 0)));
  return parts.join('');
}

function addOverlay(source, overlay) {
  return source.replace('</svg>', `${overlay}</svg>`);
}

function searchResultCard(item, x, y, focused = false) {
  const parts = [image(`pkg:/images/ui/search-result-${focused ? 'focus' : 'idle'}.png`, x, y, 846, 174)];
  parts.push(`<rect x="${x + 10}" y="${y + 12}" width="100" height="150" fill="#101820"/>`);
  if (item.poster) parts.push(image(item.poster, x + 10, y + 12, 100, 150, 1, 'cover'));
  parts.push(image(`pkg:/images/ui/search-result-artwork-corners${focused ? '-focus' : ''}.png`, x + 10, y + 12, 100, 150));
  parts.push(text(item.title, x + 128, y + 21, 24, 600, contract.colors.silver));
  parts.push(text(item.meta, x + 128, y + 55, 18, 500, contract.colors.screenBlue));
  const summary = breakText(item.summary, 62, 2);
  parts.push(prebrokenText(summary, x + 128, y + 91, 19, 400, contract.colors.dimSilver, 27));
  return parts.join('');
}

function searchComposition({keyboard = false} = {}) {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  parts.push(text('Search', x, 34, 48, 700, contract.colors.silver));
  parts.push(image(`pkg:/images/ui/search-field-${keyboard ? 'idle' : 'focus'}.png`, x, 108, 1200, 68));
  parts.push(icon('search', x + 20, 127, 30, '-rail'));
  parts.push(text(keyboard ? 'FA' : 'fargo', x + 64, 125, 24, 400, contract.colors.silver));
  if (keyboard) {
    parts.push(image('pkg:/images/ui/search-keyboard-panel.png', x, 194, 1200, 288));
    const keys = [...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'SPACE', 'DEL', 'CLEAR', 'SEARCH'];
    keys.forEach((label, index) => {
      const keyX = x + 22 + (index % 10) * 112;
      const keyY = 214 + Math.floor(index / 10) * 64;
      const focused = label === 'R';
      parts.push(image(`pkg:/images/ui/search-key-${focused ? 'focus' : 'idle'}.png`, keyX, keyY, 104, 56));
      parts.push(text(label, keyX + 52, keyY + (label.length > 2 ? 19 : 17), label.length > 2 ? 16 : 19, 600, focused ? contract.colors.silver : contract.colors.softSilver, {anchor: 'middle'}));
    });
  } else {
    parts.push(text('Results for "fargo"', x, 204, 30, 600, contract.colors.silver));
    parts.push(text('Movies & Shows', x, 262, 30, 600, contract.colors.silver));
    const items = [
      {...contract.home.continueWatching[0], meta: '2015  ·  TV Show  ·  48m', summary: 'A quiet Midwestern town is changed by an unexpected crime.'},
      {...contract.home.continueWatching[1], title: 'The Rookie', meta: '2018  ·  TV Show  ·  43m', summary: 'A late-career rookie starts over with the Los Angeles Police Department.'},
      {...contract.home.recentlyAdded[0], meta: '2021  ·  Movie  ·  118m', summary: 'A mission to save humanity begins with one astronaut waking alone.'},
      {...contract.home.recentlyAdded[1], meta: '2018  ·  Documentary  ·  90m', summary: 'A close look at a hidden world beneath the ocean surface.'},
    ];
    items.forEach((item, index) => parts.push(searchResultCard(item, x + (index % 2) * 858, 314 + Math.floor(index / 2) * 186, index === 0)));
  }
  parts.push(rail(false, -1, 'search'));
  return svg(parts.join(''));
}

function libraryComposition({empty = false} = {}) {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  parts.push(text('Movies', x, 25, 36, 700, contract.colors.silver));
  parts.push(text('Living Room Server', x, 67, 18, 500, contract.colors.dimSilver));
  const tabs = ['Discover', 'Movies', 'Collections', 'Categories'];
  tabs.forEach((label, index) => {
    const tabX = x + index * 180;
    parts.push(image(`pkg:/images/ui/browse-tab-${index === 1 ? 'focus' : 'idle'}.png`, tabX, 102, 168, 68));
    parts.push(text(label, tabX + 84, 121, 22, 600, index === 1 ? contract.colors.silver : contract.colors.dimSilver, {anchor: 'middle'}));
    if (index === 1) parts.push(`<rect x="${tabX + 8}" y="167" width="152" height="3" fill="${contract.colors.screenBlue}"/>`);
  });
  parts.push(`<rect x="${x}" y="169" width="1712" height="1" fill="#C5DAEB" opacity=".08"/>`);
  const actions = [
    {label: 'Filter', icon: 'sliders-horizontal', width: 180},
    {label: 'Sort: Title', icon: 'arrow-down-az', width: 240},
    {label: 'Grid', icon: 'grid3x3', width: 170},
  ];
  let actionX = x;
  actions.forEach(action => {
    parts.push(image('pkg:/images/ui/browse-action-idle.png', actionX, 192, action.width, 64));
    parts.push(icon(action.icon, actionX + 18, 211, 26, '-rail'));
    parts.push(text(action.label, actionX + 56, 211, 21, 600, contract.colors.silver));
    actionX += action.width + 12;
  });
  if (empty) {
    parts.push(image('pkg:/images/ui/state-icon-bed.png', x + 815, 364, 82, 82));
    parts.push(icon('triangle-alert', x + 835, 384, 42, '-rail'));
    parts.push(text('Movies is empty', x + 856, 472, 30, 600, contract.colors.silver, {anchor: 'middle'}));
    parts.push(text('This library does not contain any visible media yet.', x + 856, 522, 20, 400, contract.colors.dimSilver, {anchor: 'middle'}));
  } else {
    parts.push(text('84 results', x + 1712, 211, 18, 500, contract.colors.dimSilver, {anchor: 'end'}));
    const items = [
      {title: 'Blade Runner 2049', meta: '2017', poster: 'pkg:/images/posters/blade-runner.png'},
      {title: 'Dolphin Reef', meta: '2018', poster: 'pkg:/images/posters/dolphin-reef.png'},
      {title: 'The Day the Earth Stood Still', meta: '2008', poster: 'pkg:/images/posters/earth-stood-still.png'},
      {title: 'The Hurt Locker', meta: '2008', poster: 'pkg:/images/posters/hurt-locker.png'},
      {title: 'The Life Aquatic', meta: '2004', poster: 'pkg:/images/posters/life-aquatic.png'},
      {title: 'The Martian', meta: '2015', poster: 'pkg:/images/posters/martian.png'},
      {title: 'Fargo', meta: '2015', poster: 'pkg:/images/posters/fargo.png'}
    ];
    items.forEach((item, index) => parts.push(card(item, x + index * 238, 282, index === 0)));
  }
  parts.push(rail(false, -1, 'movies'));
  return svg(parts.join(''));
}

function homeComposition({expanded = false, focusedCard = -1, focusedRow = 0, heroOverride} = {}) {
  const contentX = contract.rail.contentX + (expanded ? contract.rail.expandedContentTranslation : 0);
  const heroWidth = 1920 - contract.rail.contentX;
  let heroModel = contract.home.hero;
  if (focusedRow === 0 && contract.home.continueWatching[focusedCard]?.hero) heroModel = contract.home.continueWatching[focusedCard].hero;
  if (heroOverride) heroModel = {...heroModel, ...heroOverride};
  const parts = [];
  parts.push(`<rect width="1920" height="1080" fill="#070B10"/>`);
  if (focusedRow === 1) parts.push('<g transform="translate(0,-430)">');
  parts.push(image(heroModel.backdrop, contentX, 0, heroWidth, 430, 1, 'cover'));
  parts.push(image('pkg:/images/ui/hero-vertical-home.png', contentX, 0, heroWidth, 430));
  parts.push(image('pkg:/images/ui/hero-horizontal.png', contentX, 0, heroWidth, 430));
  const titleLines = breakText(heroModel.title, 25, 2);
  const summaryLines = breakText(heroModel.summary, 72, 2);
  if (titleLines.length === 1) parts.push(image('pkg:/images/brand/portico-wordmark.png', contentX, 48, 154, 34, 1, 'contain'));
  const actionsY = 316;
  const summaryY = actionsY - 24 - summaryLines.length * 32;
  const metaY = summaryY - 12 - 29;
  const titleY = metaY - 10 - (69 + (titleLines.length - 1) * 72);
  parts.push(prebrokenText(titleLines, contentX, titleY, 66, 700, contract.colors.silver, 72));
  parts.push(text(heroModel.meta, contentX, metaY, 22, 600, contract.colors.softSilver));
  parts.push(prebrokenText(summaryLines, contentX, summaryY, 23, 400, contract.colors.softSilver, 32));
  parts.push(controlButton('Resume', 'play', contentX, actionsY));
  parts.push(iconButton(heroModel.watchlisted ? 'heart' : 'plus', contentX + 178, actionsY, false, heroModel.watchlisted === true));
  parts.push(iconButton('info', contentX + 254, actionsY));
  parts.push(iconButton('heart', contentX + 330, actionsY));

  parts.push(text('Continue Watching', contentX, 430, 30, 600, contract.colors.silver));
  contract.home.continueWatching.forEach((item, index) => parts.push(card(item, contentX + index * 232, 482, focusedRow === 0 && focusedCard === index)));
  parts.push(text('Recently Added', contentX, 920, 30, 600, contract.colors.silver));
  contract.home.recentlyAdded.forEach((item, index) => parts.push(card(item, contentX + index * 232, 972, focusedRow === 1 && focusedCard === index)));
  if (focusedRow === 1) parts.push('</g>');
  parts.push(rail(expanded, expanded ? 3 : -1));
  return svg(parts.join(''));
}

function detailComposition(modelOverride) {
  const contentX = contract.rail.contentX;
  const heroWidth = 1920 - contentX;
  const model = {...contract.detail, ...modelOverride};
  const parts = [`<rect width="1920" height="1080" fill="#070B10"/>`];
  parts.push(image(model.backdrop, contentX, 0, heroWidth, 570, 1, 'cover'));
  parts.push(image('pkg:/images/ui/hero-vertical-strong.png', contentX, 0, heroWidth, 570));
  parts.push(image('pkg:/images/ui/hero-horizontal.png', contentX, 0, heroWidth, 570));
  parts.push(text(model.parent, contentX, 181, 21, 600, contract.colors.screenBlueStrong));
  const titleLines = breakText(model.title, 34, 2);
  const summaryLines = breakText(model.summary, 70, 2);
  const dependentShift = (titleLines.length - 1) * 60;
  parts.push(prebrokenText(titleLines, contentX, 217, 52, 700, contract.colors.silver, 60));
  parts.push(text(model.meta, contentX, 286 + dependentShift, 22, 600, contract.colors.softSilver));
  parts.push(prebrokenText(summaryLines, contentX, 328 + dependentShift, 23, 400, contract.colors.softSilver, 32));
  parts.push(`<rect x="${contentX}" y="${410 + dependentShift}" width="700" height="6" fill="#F4F7FA" opacity=".28"/><rect x="${contentX}" y="${410 + dependentShift}" width="${Math.round(700 * model.progress / 100)}" height="6" fill="#70BCE8"/>`);
  parts.push(controlButton('Resume', 'play', contentX, 440 + dependentShift));
  parts.push(iconButton('bookmark', contentX + 178, 440 + dependentShift));
  parts.push(iconButton('heart', contentX + 254, 440 + dependentShift));
  parts.push(text('Episodes', contentX, 600, 30, 600, contract.colors.silver));
  model.episodes.forEach((episode, index) => parts.push(card(episode, contentX + index * 338, 652, index === 1, 'landscape')));
  parts.push(text('Cast & Crew', contentX, 946, 30, 600, contract.colors.silver));
  parts.push(rail(false));
  return svg(parts.join(''));
}

function authAction(label, x, y, {primary = false, focused = false} = {}) {
  const kind = primary ? 'primary' : 'secondary';
  const state = focused ? '-focus' : '';
  return image(`pkg:/images/ui/auth-action-${kind}${state}.png`, x, y, 520, 64)
    + text(label, x + 260, y + 18, 21, 600, primary ? contract.colors.projector : contract.colors.silver, {anchor: 'middle'});
}

function authComposition({code = false} = {}) {
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  parts.push(image('pkg:/images/brand/portico-wordmark.png', 883, 286, 154, 34, 1, 'contain'));
  parts.push(text('Connect this TV', 960, 382, 48, 700, contract.colors.silver, {anchor: 'middle'}));
  if (code) {
    parts.push(text('PORTICO ACCOUNT', 960, 342, 18, 600, contract.colors.screenBlueStrong, {anchor: 'middle'}));
    parts.push(text('On a phone or computer, open the address below and enter this code.', 960, 462, 24, 400, contract.colors.softSilver, {anchor: 'middle'}));
    parts.push(text('portico.media/activate', 960, 538, 28, 600, contract.colors.screenBlueStrong, {anchor: 'middle'}));
    parts.push(text('7K3M-9Q2P', 960, 590, 96, 700, contract.colors.silver, {anchor: 'middle'}));
    parts.push(authAction('Use Local Auth', 700, 792, {focused: true}));
    parts.push(authAction('Back', 700, 868));
  } else {
    parts.push(text('Choose how you want to sign in.', 960, 462, 24, 400, contract.colors.softSilver, {anchor: 'middle'}));
    parts.push(authAction('Sign In with a Portico Account', 700, 542, {primary: true, focused: true}));
    parts.push(authAction('Use Local Auth', 700, 618));
  }
  return svg(parts.join(''));
}

function resourceCard(title, meta, summary, x, y, focused = false) {
  const parts = [`<rect x="${x}" y="${y}" width="848" height="144" rx="10" fill="${focused ? contract.colors.raisedSlate : contract.colors.recess}" stroke="${focused ? contract.colors.focus : '#C5DAEB'}" stroke-opacity="${focused ? 1 : .08}" stroke-width="${focused ? 3 : 1}"/>`];
  parts.push(icon('folder-heart', x + 22, y + 21, 34, focused ? '' : '-rail'));
  parts.push(text(title, x + 76, y + 18, 25, 600, contract.colors.silver));
  parts.push(text(meta, x + 76, y + 51, 18, 500, contract.colors.screenBlue));
  parts.push(text(summary, x + 22, y + 96, 19, 400, contract.colors.softSilver));
  parts.push(icon('chevron-right', x + 796, y + 58, 28, '-rail'));
  return parts.join('');
}

function savedResourcesComposition() {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  parts.push(text('Saved', x, 25, 36, 700, contract.colors.silver));
  parts.push(text('Living Room Server', x, 67, 18, 500, contract.colors.dimSilver));
  const tabs = ['Watchlist', 'Playlists', 'Collections'];
  tabs.forEach((label, index) => {
    const tabX = x + index * 180;
    parts.push(image(`pkg:/images/ui/browse-tab-${index === 1 ? 'focus' : 'idle'}.png`, tabX, 102, 168, 68));
    parts.push(text(label, tabX + 84, 121, 22, 600, index === 1 ? contract.colors.silver : contract.colors.dimSilver, {anchor: 'middle'}));
    if (index === 1) parts.push(`<rect x="${tabX + 8}" y="167" width="152" height="3" fill="${contract.colors.screenBlue}"/>`);
  });
  parts.push(`<rect x="${x}" y="169" width="1712" height="1" fill="#C5DAEB" opacity=".08"/>`);
  parts.push(text('Playlists', x, 205, 30, 600, contract.colors.silver));
  parts.push(text('4 playlists', x + 1712, 211, 18, 500, contract.colors.dimSilver, {anchor: 'end'}));
  const resources = [
    ['Weekend movies', '12 items', 'Movies queued for Friday and Saturday night.'],
    ['Comfort television', '18 items', 'Familiar episodes for a quiet evening.'],
    ['Documentaries', '9 items', 'Science, nature, history, and exploration.'],
    ['Watch with friends', '7 items', 'A short list for the next group movie night.']
  ];
  resources.forEach((entry, index) => parts.push(resourceCard(entry[0], entry[1], entry[2], x + (index % 2) * 864, 264 + Math.floor(index / 2) * 160, index === 0)));
  parts.push(rail(false, -1, 'saved'));
  return svg(parts.join(''));
}

function channelsHeader(parts, active = 0) {
  const x = contract.rail.contentX;
  parts.push(text('Channels', x, 10, 48, 700, contract.colors.silver));
  parts.push(text('Living Room Server  ·  HDHomeRun', x, 67, 18, 500, contract.colors.dimSilver));
  ['Channels', 'Guide', 'DVR'].forEach((label, index) => {
    const tabX = x + index * 180;
    parts.push(image(`pkg:/images/ui/browse-tab-${index === active ? 'focus' : 'idle'}.png`, tabX, 102, 168, 68));
    parts.push(text(label, tabX + 84, 121, 22, 600, index === active ? contract.colors.silver : contract.colors.dimSilver, {anchor: 'middle'}));
    if (index === active) parts.push(`<rect x="${tabX + 8}" y="167" width="152" height="3" fill="${contract.colors.screenBlue}"/>`);
  });
}

function channelTile(title, number, mark, now, x, y, focused = false) {
  return `<rect x="${x}" y="${y}" width="848" height="118" rx="9" fill="${focused ? contract.colors.raisedSlate : contract.colors.recess}" stroke="${focused ? contract.colors.focus : '#C5DAEB'}" stroke-opacity="${focused ? 1 : .08}" stroke-width="${focused ? 3 : 1}"/>`
    + `<rect x="${x + 18}" y="${y + 25}" width="68" height="68" rx="8" fill="#17232E"/>`
    + text(mark, x + 52, y + 46, 22, 700, contract.colors.silver, {anchor: 'middle'})
    + text(title, x + 106, y + 19, 24, 600, contract.colors.silver)
    + text(now, x + 106, y + 54, 18, 500, contract.colors.softSilver)
    + text(number, x + 812, y + 47, 16, 400, contract.colors.dimSilver, {anchor: 'end'});
}

function channelsGridComposition() {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  channelsHeader(parts, 0);
  const channels = [
    ['CBC Halifax', '3.1', 'CBC', 'The National'], ['CTV Atlantic', '5.1', 'CTV', 'Late News'],
    ['Global Halifax', '8.1', 'G', 'The Rookie'], ['Sportsnet East', '21', 'SN', 'Blue Jays Central'],
    ['TVO', '24', 'TVO', 'The Agenda'], ['CBC News Network', '26', 'CBC', 'Power & Politics'],
    ['Knowledge', '31', 'K', 'Coastal Lives'], ['Weather Network', '38', 'WN', 'Atlantic Forecast']
  ];
  channels.forEach((entry, index) => parts.push(channelTile(entry[0], entry[1], entry[2], entry[3], x + (index % 2) * 864, 190 + Math.floor(index / 2) * 134, index === 0)));
  parts.push(rail(false, -1, 'channels'));
  return svg(parts.join(''));
}

function guideProgram(title, meta, x, y, width, focused = false) {
  return `<rect x="${x}" y="${y}" width="${width}" height="96" rx="7" fill="${focused ? contract.colors.raisedSlate : contract.colors.recess}" stroke="${focused ? contract.colors.focus : '#C5DAEB'}" stroke-opacity="${focused ? 1 : .08}" stroke-width="${focused ? 3 : 1}"/>`
    + text(title, x + 16, y + 16, 20, 600, contract.colors.silver)
    + text(meta, x + 16, y + 51, 16, 400, contract.colors.dimSilver);
}

function guideComposition() {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  channelsHeader(parts, 1);
  parts.push(`<rect x="${x}" y="190" width="1712" height="330" fill="${contract.colors.recess}"/><rect x="${x}" y="190" width="6" height="330" fill="${contract.colors.amber}"/>`);
  parts.push(text('LIVE  ·  8:00 PM – 9:00 PM', x + 32, 266, 17, 600, contract.colors.amber));
  parts.push(text('The National', x + 32, 298, 44, 700, contract.colors.silver));
  parts.push(text('CBC Halifax  ·  News  ·  60 min', x + 32, 355, 22, 500, contract.colors.softSilver));
  parts.push(controlButton('Watch live', 'play', x + 32, 407, 180, true, true));
  parts.push(controlButton('Record', 'plus', x + 224, 407, 166, false));
  parts.push(text('Today', x, 538, 21, 600, contract.colors.silver));
  ['8:00 PM', '8:30 PM', '9:00 PM'].forEach((label, index) => parts.push(text(label, x + 244 + index * 493, 538, 19, 500, contract.colors.dimSilver)));
  const rows = [['CBC','3.1','The National','Marketplace'],['CTV','5.1','Late News','The Tonight Show'],['G','8.1','The Rookie','Global News'],['SN','21','Blue Jays Central','MLB Baseball']];
  rows.forEach((row, index) => {
    const y = 586 + index * 110;
    parts.push(`<rect x="${x}" y="${y}" width="222" height="104" fill="#0B1219"/>`);
    parts.push(text(row[0], x + 24, y + 25, 21, 700, contract.colors.silver));
    parts.push(text(row[1], x + 24, y + 58, 16, 400, contract.colors.dimSilver));
    parts.push(guideProgram(row[2], '8:00 PM', x + 244, y + 4, 486, index === 0));
    parts.push(guideProgram(row[3], '8:30 PM', x + 737, y + 4, 486));
    parts.push(guideProgram('Up next', '9:00 PM', x + 1230, y + 4, 482));
  });
  parts.push(`<rect x="${x + 230}" y="586" width="3" height="440" fill="${contract.colors.amber}" opacity=".85"/>`);
  parts.push(rail(false, -1, 'channels'));
  return svg(parts.join(''));
}

function dvrRow(title, meta, x, y, {focused = false, expanded = false} = {}) {
  const header = `<rect x="${x}" y="${y}" width="1712" height="108" fill="${focused ? contract.colors.focus : contract.colors.recess}"/>`
    + `<rect x="${x + 3}" y="${y + 3}" width="1706" height="102" fill="${contract.colors.recess}"/>`
    + text(title, x + 20, y + 17, 24, 600, contract.colors.silver)
    + text(meta, x + 20, y + 56, 18, 400, contract.colors.dimSilver)
    + text(expanded ? 'Hide details' : 'View details', x + 1626, y + 39, 18, 500, contract.colors.softSilver, {anchor: 'end'})
    + icon(expanded ? 'chevron-up' : 'chevron-down', x + 1642, y + 40, 28, '-rail');
  if (!expanded) return header;
  return header + `<rect x="${x}" y="${y + 108}" width="1712" height="108" fill="${contract.colors.recess}"/><rect x="${x}" y="${y + 108}" width="1712" height="1" fill="#C7D0D8" opacity=".12"/>`
    + text('DURATION', x + 20, y + 128, 16, 500, contract.colors.dimSilver) + text('43 min', x + 20, y + 158, 20, 600, contract.colors.silver)
    + text('SOURCE', x + 360, y + 128, 16, 500, contract.colors.dimSilver) + text('HDHomeRun', x + 360, y + 158, 20, 600, contract.colors.silver)
    + text('PLAYBACK', x + 1010, y + 128, 16, 500, contract.colors.dimSilver) + text('Ready', x + 1010, y + 158, 20, 600, contract.colors.silver)
    + controlButton('Play recording', 'play', x + 1392, y + 130, 280, true);
}

function dvrComposition() {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  channelsHeader(parts, 2);
  parts.push(`<rect x="${x}" y="190" width="1712" height="96" fill="#0B1219"/>`);
  parts.push(icon('radio', x + 24, 215, 46, '-rail'));
  parts.push(text('DVR storage', x + 88, 208, 24, 600, contract.colors.silver));
  parts.push(text('238 GB available  ·  18 recordings', x + 88, 241, 18, 400, contract.colors.dimSilver));
  parts.push(dvrRow('The Rookie — The Hammer', 'Recorded today at 8:00 PM  ·  TV-14', x, 308, {focused: true, expanded: true}));
  parts.push(dvrRow('The National', 'Recorded yesterday at 9:00 PM', x, 536));
  parts.push(dvrRow('Blue Jays vs. Yankees', 'Recorded Sunday at 2:00 PM', x, 656));
  parts.push(rail(false, -1, 'channels'));
  return svg(parts.join(''));
}

function castCard(initials, name, role, x, y, focused = false) {
  return `<rect x="${x}" y="${y}" width="170" height="232" rx="10" fill="${focused ? contract.colors.raisedSlate : 'transparent'}" stroke="${focused ? contract.colors.focus : 'transparent'}" stroke-width="3"/>`
    + `<circle cx="${x + 85}" cy="${y + 78}" r="72" fill="#286F9D"/>`
    + text(initials, x + 85, y + 50, 28, 700, contract.colors.silver, {anchor: 'middle'})
    + text(name, x + 85, y + 163, 19, 600, contract.colors.silver, {anchor: 'middle'})
    + text(role, x + 85, y + 192, 16, 400, contract.colors.dimSilver, {anchor: 'middle'});
}

function detailCastVersionsComposition({expanded = false} = {}) {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  parts.push(text('Cast & Crew', x, 46, 30, 600, contract.colors.silver));
  const people = [['NF','Nathan Fillion','John Nolan'],['MA','Melissa O’Neil','Lucy Chen'],['EW','Eric Winter','Tim Bradford'],['AJ','Alyssa Diaz','Angela Lopez'],['RM','Richard T. Jones','Wade Grey'],['ML','Mekia Cox','Nyla Harper'],['SL','Shawn Ashmore','Wesley Evers'],['LT','Lisseth Chavez','Celina Juarez'],['JS','Jenna Dewan','Bailey Nune']];
  people.forEach((person, index) => parts.push(castCard(person[0], person[1], person[2], x + index * 190, 100, index === 0)));
  const factsY = 384;
  parts.push(`<rect x="${x}" y="${factsY}" width="1712" height="1" fill="#C7D0D8" opacity=".12"/>`);
  if (expanded) parts.push(`<rect x="${x}" y="${factsY + 1}" width="1712" height="90" fill="${contract.colors.raisedSlate}"/>`);
  parts.push(text('Versions & media information', x, factsY + 27, 24, 600, expanded ? contract.colors.focus : contract.colors.softSilver));
  parts.push(icon(expanded ? 'chevron-up' : 'chevron-down', x + 1660, factsY + 31, 26, '-rail'));
  parts.push(`<rect x="${x}" y="${factsY + 91}" width="1712" height="1" fill="#C7D0D8" opacity=".12"/>`);
  if (expanded) {
    const facts = [['VIDEO','4K HEVC'],['AUDIO','EAC3 5.1'],['SUBTITLES','English'],['FILE','MKV  ·  5.8 GB']];
    parts.push(`<rect x="${x}" y="${factsY + 112}" width="1712" height="116" fill="${contract.colors.recess}"/>`);
    facts.forEach((fact, index) => {
      const cellX = x + index * 428;
      if (index) parts.push(`<rect x="${cellX}" y="${factsY + 130}" width="1" height="80" fill="#C7D0D8" opacity=".12"/>`);
      parts.push(text(fact[0], cellX + 20, factsY + 132, 17, 500, contract.colors.dimSilver));
      parts.push(text(fact[1], cellX + 20, factsY + 171, 22, 600, contract.colors.silver));
    });
  }
  parts.push(rail(false));
  return svg(parts.join(''));
}

function detailMoreComposition() {
  const base = detailComposition();
  const x = 1110;
  const y = 144;
  const overlay = [image('pkg:/images/ui/overlay-scrim.png', 0, 0, 1920, 1080), `<rect x="${x}" y="${y}" width="720" height="792" rx="16" fill="#101820" stroke="#C7D0D8" stroke-opacity=".16"/>`];
  overlay.push(text('The Hammer', x + 28, y + 25, 17, 500, contract.colors.dimSilver));
  overlay.push(text('More actions', x + 28, y + 52, 32, 600, contract.colors.silver));
  overlay.push(iconButton('x', x + 632, y + 40, true));
  overlay.push(`<rect x="${x + 28}" y="${y + 112}" width="664" height="1" fill="#C7D0D8" opacity=".12"/>`);
  const rows = [
    ['list-plus','Play Next','Place this title immediately after what is playing'],
    ['list','Add to Queue','Place this title at the end of the active queue'],
    ['list-music','Add to Playlist','Choose or create an ordered playlist'],
    ['folder-heart','Add to Collection','Choose or create a collection'],
    ['star','Rate','Help tune recommendations for this account'],
    ['thumbs-up','Like',''],
    ['thumbs-down','Dislike','']
  ];
  rows.forEach((row, index) => {
    const rowY = y + 132 + index * 86;
    overlay.push(`<rect x="${x + 20}" y="${rowY}" width="680" height="84" rx="8" fill="${index === 0 ? contract.colors.raisedSlate : 'transparent'}" stroke="${index === 0 ? contract.colors.focus : '#C5DAEB'}" stroke-opacity="${index === 0 ? 1 : .08}" stroke-width="${index === 0 ? 3 : 1}"/>`);
    overlay.push(icon(row[0], x + 40, rowY + 27, 28, '-rail'));
    overlay.push(text(row[1], x + 88, rowY + 13, 23, 600, contract.colors.silver));
    overlay.push(text(row[2], x + 88, rowY + 47, 17, 400, contract.colors.dimSilver));
    overlay.push(icon('chevron-right', x + 646, rowY + 28, 26, '-rail'));
  });
  return addOverlay(base, overlay.join(''));
}

function settingsRow(label, description, value, iconName, x, y, focused = false, {toggle = false, actionable = true} = {}) {
  const trailing = toggle
    ? image('pkg:/images/ui/settings-toggle-on.png', x + 1618, y + 29, 62, 36)
    : text(value, x + 1636, y + 31, 19, 500, contract.colors.softSilver, {anchor: 'end'}) + (actionable ? icon('chevron-right', x + 1656, y + 35, 24, '-rail') : '');
  return `<rect x="${x}" y="${y}" width="1712" height="94" rx="8" fill="${focused ? contract.colors.raisedSlate : contract.colors.recess}" stroke="${focused ? contract.colors.focus : '#C5DAEB'}" stroke-opacity="${focused ? 1 : .08}" stroke-width="${focused ? 3 : 1}"/>`
    + icon(iconName, x + 22, y + 33, 28, '-rail')
    + text(label, x + 72, y + 14, 22, 600, contract.colors.silver)
    + text(description, x + 72, y + 48, 17, 400, contract.colors.dimSilver)
    + trailing;
}

function profileComposition() {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  parts.push(text('Profile and server', x, 46, 48, 700, contract.colors.silver));
  parts.push(`<rect x="${x}" y="132" width="1712" height="118" fill="${contract.colors.recess}"/><rect x="${x}" y="249" width="1712" height="1" fill="#C7D0D8" opacity=".12"/>`);
  parts.push(image('pkg:/images/ui/settings-avatar.png', x + 20, 159, 64, 64));
  parts.push(text('J', x + 52, 177, 24, 700, contract.colors.silver, {anchor: 'middle'}));
  parts.push(text('Justin Ehler', x + 104, 150, 25, 600, contract.colors.silver));
  parts.push(text('Portico Account', x + 104, 184, 18, 400, contract.colors.dimSilver));
  parts.push(text('Living Room Server  ·  Connected', x + 104, 212, 18, 500, contract.colors.screenBlueStrong));
  parts.push(text('ACCOUNT', x, 278, 17, 600, contract.colors.dimSilver));
  parts.push(settingsRow('Server', 'Living Room Server', 'Connected', 'library', x, 312, true));
  parts.push(settingsRow('Settings', 'Playback, language, and accessibility preferences', '', 'settings', x, 414));
  parts.push(settingsRow('Sign out', 'Portico Account', '', 'log-out', x, 552));
  parts.push(rail(false, -1, 'profile'));
  return svg(parts.join(''));
}

function settingsComposition() {
  const x = contract.rail.contentX;
  const parts = [`<rect width="1920" height="1080" fill="${contract.colors.projector}"/>`];
  parts.push(text('Settings', x, 46, 48, 700, contract.colors.silver));
  parts.push(text('Justin Ehler  ·  Living Room Server', x, 116, 19, 400, contract.colors.dimSilver));
  parts.push(`<rect x="${x}" y="165" width="1712" height="1" fill="#C7D0D8" opacity=".12"/>`);
  parts.push(text('ACCOUNT', x, 166, 17, 600, contract.colors.dimSilver));
  parts.push(settingsRow('Justin Ehler', 'Portico Account', 'Profile', 'user', x, 200, true));
  parts.push(settingsRow('Server', 'Choose another server shared with this account', 'Connected', 'library', x, 302));
  parts.push(text('PLAYBACK', x, 420, 17, 600, contract.colors.dimSilver));
  parts.push(settingsRow('Auto-play next item', 'Automatically continue to the next queued episode or title', '', 'play', x, 454, false, {toggle: true}));
  parts.push(settingsRow('Skip interval', 'Changes the back and forward controls in the player', '10 seconds', 'rotate-cw', x, 556));
  parts.push(settingsRow('Preferred audio', 'Used when a matching audio stream is available', 'Automatic', 'languages', x, 658));
  parts.push(settingsRow('Preferred subtitles', 'Used when a matching subtitle stream is available', 'Off', 'captions', x, 760));
  parts.push(settingsRow('Playback quality', 'Portico automatically chooses the best format for this device', 'Automatic', 'gauge', x, 862, false, {actionable: false}));
  parts.push(rail(false, -1, 'profile'));
  return svg(parts.join(''));
}

function playerTransportButton(iconName, x, y, {focused = false, main = false} = {}) {
  const size = main ? 78 : 60;
  const iconSize = main ? 34 : 28;
  const surfaceName = main
    ? `player-transport-main${focused ? '-focus' : ''}.png`
    : `player-transport-${focused ? 'focus' : 'idle'}.png`;
  const inset = Math.floor((size - iconSize) / 2);
  return image(`pkg:/images/ui/${surfaceName}`, x, y, size, size) + icon(iconName, x + inset, y + inset, iconSize);
}

function playerUtilityDock(parts, panel = '') {
  const icons = ['gauge', 'captions', 'list', 'list-plus'];
  icons.forEach((iconName, index) => parts.push(iconButton(iconName, 1568 + index * 72, 974, panel !== '' && index === 0, panel !== '' && index === 0)));
  if (panel === '') return;
  const panelX = 1428;
  const rows = panel === 'quality'
    ? ['Original','High · Up to 20 Mbps','Medium · Up to 8 Mbps','Data saver · Up to 3 Mbps']
    : ['Audio · English — EAC3 5.1','Audio · English — Stereo','Subtitles · Off','Subtitles · English CC'];
  const panelHeight = 100 + rows.length * 70;
  const panelY = 974 - panelHeight;
  parts.push(`<rect x="${panelX}" y="${panelY}" width="420" height="${panelHeight}" fill="${contract.colors.recess}" opacity=".96"/><rect x="${panelX}" y="${panelY}" width="2" height="${panelHeight}" fill="${contract.colors.screenBlue}" opacity=".72"/>`);
  parts.push(text(panel === 'quality' ? 'Playback quality' : 'Audio and subtitles', panelX + 18, panelY + 18, 26, 600, contract.colors.silver));
  rows.forEach((row, index) => {
    const y = panelY + 82 + index * 70;
    parts.push(`<rect x="${panelX + 18}" y="${y}" width="384" height="64" rx="8" fill="${index === 0 ? contract.colors.silver : 'transparent'}" stroke="${index === 0 ? contract.colors.focus : '#C5DAEB'}" stroke-opacity="${index === 0 ? 1 : .08}" stroke-width="${index === 0 ? 3 : 1}"/>`);
    parts.push(text(row, panelX + 36, y + 19, 20, 600, index === 0 ? contract.colors.projector : contract.colors.softSilver));
    if (index === 0) parts.push(icon('check', panelX + 354, y + 20, 24, '-dark'));
  });
}

function playerComposition(state, {panel = ''} = {}) {
  const p = contract.player;
  const parts = [image(contract.detail.backdrop, 0, 0, 1920, 1080, 1, 'cover')];
  parts.push(image('pkg:/images/ui/player-overlay-scrim.png', 0, 0, 1920, 1080));
  parts.push(text(contract.detail.title, p.identityX, p.identityY, p.titleSize, 600, contract.colors.silver));
  parts.push(text(`${contract.detail.parent}  ·  S06 E04  ·  43 min`, p.identityX, p.identityY + 38, p.metaSize, 400, contract.colors.dimSilver));

  if (['preparing', 'buffering'].includes(state)) {
    parts.push(image('pkg:/images/ui/player-spinner.png', 932, 454, p.spinnerSize, p.spinnerSize));
    parts.push(text(state === 'preparing' ? 'Preparing playback…' : 'Buffering…', 960, 530, 26, 600, contract.colors.silver, {anchor: 'middle'}));
  }

  if (['playing', 'paused', 'buffering'].includes(state)) {
    parts.push(`<rect x="0" y="${p.bottomY}" width="1920" height="199" fill="#070B10" opacity=".52"/>`);
    parts.push(text('42:18', p.horizontalInset, p.bottomY + 20, p.timeSize, 500, contract.colors.softSilver));
    parts.push(text('1:59:02', 1920 - p.horizontalInset, p.bottomY + 20, p.timeSize, 500, contract.colors.softSilver, {anchor: 'end'}));
    parts.push(`<rect x="${p.horizontalInset}" y="${p.progressY}" width="${p.progressWidth}" height="${p.progressHeight}" fill="#F4F7FA" opacity=".28"/>`);
    parts.push(`<rect x="${p.horizontalInset}" y="${p.progressY}" width="632" height="${p.progressHeight}" fill="${contract.colors.screenBlueStrong}"/>`);
    parts.push(image('pkg:/images/ui/player-transport-dock.png', p.transportX, p.transportY, p.transportWidth, p.transportHeight));
    parts.push(playerTransportButton('skip-back', 822, 970));
    parts.push(playerTransportButton('rotate-ccw', 888, 970));
    parts.push(playerTransportButton(state === 'playing' ? 'pause' : 'play', 954, 961, {focused: true, main: true}));
    parts.push(playerTransportButton('rotate-cw', 1038, 970));
    playerUtilityDock(parts, panel);
  }

  if (state === 'ended') {
    parts.push(image('pkg:/images/ui/player-ended-panel.png', 700, 405, 520, 230));
    parts.push(text('Playback complete', 960, 444, 38, 700, contract.colors.silver, {anchor: 'middle'}));
    parts.push(text('You’ve reached the end of this title.', 960, 499, 22, 400, contract.colors.softSilver, {anchor: 'middle'}));
    parts.push(controlButton('Back to details', 'chevron-left', 845, 550, 230));
  }

  if (state === 'error') {
    parts.push(image('pkg:/images/ui/player-error-panel.png', 610, 385, 700, 280));
    parts.push(text('Playback unavailable', 648, 419, 38, 700, contract.colors.silver));
    parts.push(text('Portico couldn’t continue this stream.', 648, 476, 22, 400, contract.colors.softSilver));
    parts.push(text('Your playback position is safe.', 648, 508, 22, 400, contract.colors.softSilver));
    parts.push(controlButton('Back to details', 'chevron-left', 648, 573, 230));
  }
  return svg(parts.join(''));
}

function svg(body) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080"><rect width="1920" height="1080" fill="#070B10"/>${body}</svg>`;
}

function render(name, source) {
  if (requestedRenders.size > 0 && !requestedRenders.has(name)) return;
  const svgPath = join(output, `${name}.svg`);
  const pngPath = join(output, `${name}.png`);
  writeFileSync(svgPath, source);
  const fontRoot = mkdtempSync(join(tmpdir(), 'portico-roku-fonts-'));
  const cache = join(fontRoot, 'cache');
  mkdirSync(cache);
  const fontConfig = join(fontRoot, 'fonts.conf');
  writeFileSync(fontConfig, `<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>${escapeXml(join(channel, 'fonts'))}</dir><cachedir>${escapeXml(cache)}</cachedir></fontconfig>`);
  const result = spawnSync('rsvg-convert', ['-w', '1920', '-h', '1080', '-o', pngPath, svgPath], {
    encoding: 'utf8',
    env: {...process.env, FONTCONFIG_FILE: fontConfig}
  });
  rmSync(fontRoot, {recursive: true, force: true});
  if (result.status !== 0) throw new Error(`Failed to render ${name}: ${result.stderr}`);
  console.log(`Rendered ${pngPath}`);
}

render('home-default', homeComposition());
render('home-rail-expanded', homeComposition({expanded: true}));
render('home-rookie-focused', homeComposition({focusedCard: 1}));
render('home-recently-focused', homeComposition({focusedRow: 1, focusedCard: 2}));
render('detail-rookie', detailComposition());
render('home-long-title', homeComposition({heroOverride: {title: 'The Curious Incident Under a Northern Sky'}}));
render('detail-long-title', detailComposition({title: 'A Very Long and Unexpectedly Complicated Assignment'}));
render('home-server-picker-loading', addOverlay(homeComposition(), serverPickerStateOverlay({
  status: 'LOADING SERVERS',
  body: '',
  tone: 'account',
  actions: [{label: 'Account', icon: 'user'}]
})));
render('home-server-picker-offline', addOverlay(homeComposition(), serverPickerStateOverlay({
  status: 'SERVERS UNAVAILABLE',
  body: 'Check your internet connection and try again.',
  tone: 'warning',
  actions: [{label: 'Refresh', icon: 'refresh-cw'}, {label: 'Account', icon: 'user'}]
})));
render('search-results', searchComposition());
render('search-keyboard', searchComposition({keyboard: true}));
render('library-grid', libraryComposition());
render('library-empty', libraryComposition({empty: true}));
for (const state of ['preparing', 'buffering', 'playing', 'paused', 'ended', 'error']) render(`player-${state}`, playerComposition(state));
render('auth-landing', authComposition());
render('auth-account-code', authComposition({code: true}));
render('saved-resources', savedResourcesComposition());
render('channels-grid', channelsGridComposition());
render('channels-guide', guideComposition());
render('channels-dvr-expanded', dvrComposition());
render('detail-cast-versions', detailCastVersionsComposition());
render('detail-versions-expanded', detailCastVersionsComposition({expanded: true}));
render('detail-more', detailMoreComposition());
render('profile', profileComposition());
render('settings', settingsComposition());
render('player-quality-panel', playerComposition('paused', {panel: 'quality'}));
render('player-streams-panel', playerComposition('paused', {panel: 'streams'}));
