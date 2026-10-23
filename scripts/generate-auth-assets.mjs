#!/usr/bin/env node
// Frame 40's colour-only backdrop and checked MAIN's bundled Manrope ExtraBold face.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync, renameSync, readdirSync} from 'node:fs';
import {dirname, resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {Resvg} from '@resvg/resvg-js';
const app = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pins = JSON.parse(readFileSync(join(app, 'scripts/auth-assets-source-pins.json'), 'utf8'));
const roots = {native: process.env.PORTICO_REACT_NATIVE_ROOT, internal: process.env.PORTICO_INTERNAL_ROOT};
const checked = {};
for (const input of pins.inputs) {
  if (!roots[input.root]) throw new Error(`Missing checked ${input.root} repository path`);
  if (input.root === 'native') execFileSync('git', ['merge-base', '--is-ancestor', input.commit, 'origin/main'], {cwd: roots.native});
  for (const [path, hash] of Object.entries(input.files)) {
    const bytes = execFileSync('git', ['show', `${input.commit}:${path}`], {cwd: roots[input.root]});
    if (createHash('sha256').update(bytes).digest('hex') !== hash) throw new Error(`Source mismatch: ${path}`);
    checked[path] = bytes;
  }
}
const emit = (path, bytes) => {
  const target = join(app, path);
  if (process.argv.includes('--check')) {
    if (!readFileSync(target).equals(Buffer.from(bytes))) throw new Error(`Regenerate ${path}`);
  } else { const temp = `${target}.tmp-${process.pid}`; writeFileSync(temp, bytes); renameSync(temp, target); }
};
emit('fonts/manrope-800.ttf', checked['apps/native/assets/manrope-800.ttf']);
emit('fonts/OFL-Manrope-800.txt', checked['apps/native/assets/OFL-Manrope-800.txt']);
const html = checked['design/ui-v1/connect.html'].toString();
const kit = checked['design/ui-v1/kit.css'].toString();
const backdrop = /\.gen \{[^}]*?background:([\s\S]*?); \}/.exec(html)?.[1];
const ink = /--ink:\s*(#[0-9a-f]{6})/i.exec(kit)?.[1];
if (!backdrop || !ink) throw new Error('Re-read frame backdrop rules');
const parts = value => {
  const result = []; let depth = 0, start = 0;
  for (let i = 0; i < value.length; i++) {
    if (value[i] === '(') depth++;
    if (value[i] === ')') depth--;
    if (value[i] === ',' && depth === 0) { result.push(value.slice(start, i).trim()); start = i + 1; }
  }
  return [...result, value.slice(start).trim()];
};
const gradients = parts(backdrop).map((value, index) => {
  if (!value.startsWith('radial-gradient(') || !value.endsWith(')')) throw new Error('Unsupported backdrop layer');
  const [ellipse, ...stops] = parts(value.slice(16, -1));
  const axes = /^(\d+)% (\d+)% at (\d+)% (\d+)%$/.exec(ellipse)?.slice(1).map(Number);
  if (!axes) throw new Error('Unsupported backdrop ellipse');
  const [rx, ry, cx, cy] = [axes[0] * 19.2, axes[1] * 10.8, axes[2] * 19.2, axes[3] * 10.8];
  let previousColor = '#000';
  const nodes = stops.map(stop => {
    const match = /^(rgba\((\d+),(\d+),(\d+),([.\d]+)\)|transparent) (\d+)%$/.exec(stop);
    if (!match) throw new Error('Unsupported backdrop stop');
    if (match[1] !== 'transparent') previousColor = `rgb(${match[2]},${match[3]},${match[4]})`;
    // CSS interpolates transparent stops with premultiplied alpha. Keep the prior RGB at alpha0
    // so SVG does not also darken it towards black before the compositor applies its opacity.
    return `<stop offset="${match[6]}%" stop-color="${previousColor}" stop-opacity="${match[1] === 'transparent' ? 0 : match[5]}"/>`;
  }).join('');
  return `<radialGradient id="g${index}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="1" gradientTransform="translate(${cx} ${cy}) scale(${rx} ${ry})">${nodes}</radialGradient>`;
});
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><defs>${gradients.join('')}</defs><rect width="1920" height="1080" fill="${ink}"/>${gradients.map((_, i) => `<rect width="1920" height="1080" fill="url(#g${i})"/>`).reverse().join('')}</svg>`;
emit('images/gradients/auth-left.png', new Resvg(svg).render().asPng());
const rule = selector => {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return [...html.matchAll(new RegExp(`${escaped} \\{([^}]+)\\}`, 'g'))].map(match => match[1]).join(';');
};
const pixels = (css, key) => {
  const value = [...css.matchAll(new RegExp(`(?:^|;)\\s*${key}:\\s*(-?[.\\d]+)px`, 'g'))].at(-1)?.[1];
  if (value === undefined) throw new Error(`Missing frame metric ${key}`);
  return Number(value);
};
const front = /data-f="40"[\s\S]*?<\/div><\/div>/.exec(html)?.[0];
if (!front) throw new Error('Missing TV front door frame');
const heading = /<h1 style="([^"]+)"/.exec(front)?.[1];
const buttons = /class="btns" style="([^"]+)"/.exec(front)?.[1];
if (!heading || !buttons) throw new Error('Missing front door overrides');
const size = pixels(heading, 'font-size');
const titleGap = pixels(heading, 'margin-bottom');
const buttonHeight = pixels(rule('.tv .btn'), 'height');
const hhea = checkedFontMetrics(checked['apps/native/assets/manrope-700.ttf']);
const buttonSize = pixels(rule('.tv .btn'), 'font-size');
const values = {
  width: pixels(rule('.tvl'), 'width'), left: pixels(rule('.screen.tv'), '--gutter'),
  wordmarkHeight: pixels(rule('.tvl .wm'), 'height'), wordmarkTop: pixels(rule('.tvl .wm'), 'top'),
  titleSize: size, titleHeight: size, titleTracking: size * -0.045,
  titleTextOffset: -(checkedFontMetrics(checked['apps/native/assets/manrope-800.ttf']) * size - size) / 2,
  titleTop: (1080 - size - titleGap - buttonHeight) / 2,
  buttonTop: (1080 - size - titleGap - buttonHeight) / 2 + size + titleGap,
  buttonGap: pixels(buttons, 'gap'), buttonPadding: 38, buttonSize,
  buttonLineHeight: Math.round(buttonSize * hhea), glassAlpha: 0.14,
};
// These declarations are read directly from the same immutable frame rules above.
const pad = /padding:\s*0 (\d+)px/.exec(rule('.tv .btn'));
const glass = /background:\s*rgba\(237,245,250,([.\d]+)\)/.exec(rule('.tv .btn.glass'));
const tracking = /letter-spacing:\s*(-?[.\d]+)em/.exec(rule('.tvl h1'));
if (!pad || !glass || !tracking) throw new Error('Missing auth control or type rules');
values.buttonPadding = Number(pad[1]); values.glassAlpha = Number(glass[1]); values.titleTracking = size * Number(tracking[1]);
const shadow = /0 (\d+)px (\d+)px (-?\d+)px var\(--glow\)/.exec(rule('.tv .ring'));
const ring = /0 0 0 (\d+)px var\(--focus\)/.exec(rule('.tv .ring'));
const glowColor = /--glow:\s*rgba\((\d+),(\d+),(\d+),([.\d]+)\)/.exec(rule('.screen.tv'));
const buttonRadius = pixels(rule('.tv .btn'), 'border-radius');
if (!shadow || !glowColor || !ring) throw new Error('Missing TV focus shadow');
const glassBorder = /inset 0 0 0 (\d+)px rgba\(237,245,250,([.\d]+)\)/.exec(rule('.glass'));
if (!glassBorder) throw new Error('Missing glass inset edge');
values.glassBorderWidth = Number(glassBorder[1]); values.glassBorderAlpha = Number(glassBorder[2]);
values.ringInset = Number(ring[1]);
values.shadowMargin = Number(shadow[2]) * 2;
values.shadowOffset = Number(shadow[1]);
const spread = Number(shadow[3]);
const sampleWidth = buttonHeight * 5;
const patchWidth = sampleWidth + values.shadowMargin * 2;
const patchHeight = buttonHeight + values.shadowMargin * 2;
const shadowSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${patchWidth + 2}" height="${patchHeight + 2}"><defs><filter id="b" x="-200%" y="-400%" width="500%" height="900%"><feGaussianBlur stdDeviation="${Number(shadow[2]) / 2}"/></filter><mask id="outside"><rect width="100%" height="100%" fill="white"/><rect x="${1 + values.shadowMargin}" y="${1 + values.shadowMargin - values.shadowOffset}" width="${sampleWidth}" height="${buttonHeight}" rx="${buttonRadius}" fill="black"/></mask></defs><rect x="${1 + values.shadowMargin - spread}" y="${1 + values.shadowMargin - spread}" width="${sampleWidth + spread * 2}" height="${buttonHeight + spread * 2}" rx="${Math.max(0, buttonRadius + spread)}" fill="rgb(${glowColor[1]},${glowColor[2]},${glowColor[3]})" fill-opacity="${glowColor[4]}" filter="url(#b)" mask="url(#outside)"/><rect x="${1 + patchWidth / 2}" y="0" width="1" height="1" fill="#000"/><rect x="0" y="${1 + patchHeight / 2}" width="1" height="1" fill="#000"/></svg>`;
emit('images/shapes/auth-focus.9.png', new Resvg(shadowSvg).render().asPng());
const textShadow = /text-shadow:\s*0 (\d+)px (\d+)px rgba\((\d+),(\d+),(\d+),([.\d]+)\)/.exec(rule('.tvl h1'));
if (!textShadow) throw new Error('Missing title shadow rule');
const titles = readdirSync(join(app, 'locale')).map(locale => {
  const xml = readFileSync(join(app, 'locale', locale, 'translations.xml'), 'utf8');
  return /<trans-unit id="web\.signin\.welcomeHome">[\s\S]*?<target>([^<]+)<\/target>/.exec(xml)?.[1];
});
if (new Set(titles).size !== 1 || !titles[0] || titles[0].includes('&')) throw new Error('Generate a separate title shadow for each differing locale');
values.titleShadowText = titles[0];
values.titleShadowPadding = Number(textShadow[2]) * 2;
const baseline = values.titleHeight + values.titleTextOffset + (checkedFontMetrics(checked['apps/native/assets/manrope-800.ttf'], true) * size - size);
const titleShadowSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${values.width + values.titleShadowPadding * 2}" height="${values.titleHeight + values.titleShadowPadding * 2}"><defs><filter id="s" x="-100%" y="-300%" width="300%" height="700%"><feGaussianBlur stdDeviation="${Number(textShadow[2]) / 2}"/></filter></defs><text x="${values.titleShadowPadding}" y="${values.titleShadowPadding + baseline + Number(textShadow[1])}" font-family="Manrope ExtraBold" font-size="${size}" letter-spacing="${values.titleTracking}" fill="rgb(${textShadow[3]},${textShadow[4]},${textShadow[5]})" fill-opacity="${textShadow[6]}" filter="url(#s)">${titles[0]}</text></svg>`;
emit('images/gradients/auth-title-shadow.png', new Resvg(titleShadowSvg, {font: {loadSystemFonts: false, fontFiles: [join(app, 'fonts/manrope-800.ttf')], defaultFontFamily: 'Manrope ExtraBold'}}).render().asPng());
emit('source/ui/AuthFrameMetrics.bs', `' Generated from immutable connect.html frame40 at ${pins.inputs.find(x => x.root === 'internal').commit}.\n' No shared theme source or draft is mirrored.\nnamespace AuthFrameMetrics\n${Object.entries(values).map(([key, value]) => `    const ${key} = ${JSON.stringify(value)}`).join('\n')}\nend namespace\n`);
console.log('auth assets verified from immutable design and checked Native MAIN Git objects');

function checkedFontMetrics(bytes, ascentOnly = false) {
  const tables = {};
  for (let i = 0; i < bytes.readUInt16BE(4); i++) { const at = 12 + i * 16; tables[bytes.toString('ascii', at, at + 4)] = bytes.readUInt32BE(at + 8); }
  if (tables.head === undefined || tables.hhea === undefined) throw new Error('Missing bundled font metrics');
  const units = bytes.readUInt16BE(tables.head + 18);
  if (ascentOnly) return bytes.readInt16BE(tables.hhea + 4) / units;
  return (bytes.readInt16BE(tables.hhea + 4) - bytes.readInt16BE(tables.hhea + 6) + bytes.readInt16BE(tables.hhea + 8)) / units;
}
