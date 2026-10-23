// Platform composition explicitly authorized by ruling 28; no shared package is mirrored.
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, renameSync, readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, resolve, join} from 'node:path';
import {stripTypeScriptTypes, createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const app = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const root = process.env.PORTICO_INTERNAL_ROOT;
if (!root) throw new Error('Set PORTICO_INTERNAL_ROOT to the immutable design Git repository');
const commit = '69f2d45a972ff9ec1bd8743c760183026c92d555';
const load = name => execFileSync('git', ['show', `${commit}:design/ui-v1/${name}`], {cwd: root, maxBuffer: 4 * 1024 * 1024}).toString();
const auth = load('auth.html'), connect = load('connect.html');
const serverRoot = process.env.PORTICO_SERVER_ROOT;
if (!serverRoot) throw new Error('Set PORTICO_SERVER_ROOT for checked MAIN sign-in error copy');
const serverPins = JSON.parse(readFileSync(join(app, 'scripts/accounts-source-pins.json')));
const serverCommit = serverPins.commit;
execFileSync('git', ['merge-base', '--is-ancestor', serverCommit, 'origin/main'], {cwd: serverRoot});
const catalogue = async name => {
  const path = `packages/i18n/src/catalog/en-US/${name}.ts`;
  const bytes = execFileSync('git', ['show', `${serverCommit}:${path}`], {cwd: serverRoot});
  if (createHash('sha256').update(bytes).digest('hex') !== serverPins.files[path]) throw new Error('Pinned catalogue mismatch: ' + path);
  return import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(bytes.toString())).toString('base64'));
};
const {servicesMessages} = await catalogue('services');
const {webMessages} = await catalogue('web');
const {shared: nextSharedMessages} = await catalogue('next/shared');
const sharedIds = ['services.signin.credentials', 'services.signin.unavailable', 'services.signin.tooMany', 'web.signIn.error.credentials', 'web.signIn.error.code', 'web.signIn.error.tooMany', 'web.twoStep.turnOnTitle', 'web.direct.newPasswordTitle', 'web.hostedAccount.signInAgain', 'next.auth.tv.requiredTwoStepBody', 'next.auth.tv.requiredPasswordBody', 'next.auth.tv.handoffHint', 'next.auth.tv.playPause', 'next.auth.tv.deleteDigit'];
const shared = {...servicesMessages, ...webMessages, ...nextSharedMessages};
for (const id of sharedIds) if (typeof shared[id] !== 'string') throw new Error('Missing canonical sign-in error: ' + id);
const messages = {
  'roku.tvSignIn.hostedLead': 'Sign in with your Portico Account to access servers shared with you.',
  'roku.tvSignIn.identity': 'Username or email',
  'roku.tvSignIn.codeLead': 'Two-step verification is on for this account. Enter the code from your authenticator app.',
  'roku.tvSignIn.recovery': 'Lost your phone? Use a recovery code',
  'roku.tvSignIn.agreement': 'By continuing, you agree to Portico’s terms and privacy policy.',
  'roku.tvSignIn.space': 'Space',
  'roku.tvSignIn.clear': 'Clear'
};
for (const [id, text] of Object.entries(messages)) {
  const plain = (id.endsWith('.space') || id.endsWith('.clear') ? connect : auth).replace(/<[^>]+>/g, '').replace(/\s+/g, ' ');
  if (!plain.includes(text)) throw new Error(`Approved frame text missing: ${id}`);
}
const rule = (html, selector) => {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(escaped + ' \\{([^}]+)\\}').exec(html);
  if (!match) throw new Error('Missing design rule: ' + selector);
  return match[1];
};
const px = (css, name) => {
  const match = new RegExp('(?:^|;)\\s*' + name + ':\\s*(-?[.\\d]+)px').exec(css);
  if (!match) throw new Error('Missing design dimension: ' + name);
  return Number(match[1]);
};
const metrics = {
  left: px(rule(auth, '.screen.tv'), '--gutter'), columnWidth: px(rule(auth, '.tvl'), 'width'),
  wordmarkTop: 72, wordmarkHeight: 40,
  titleSize: px(rule(auth, '.tvl h1'), 'font-size'), titleTracking: -.045, titleGap: 22,
  whySize: 24, whyHeight: 34, whyGap: 14,
  leadSize: px(rule(auth, '.tvl .lede'), 'font-size'), leadHeight: 37.7, leadWidth: 760, leadGap: 48,
  fieldWidth: px(rule(connect, '.tf'), 'width'), fieldHeight: px(rule(connect, '.tf'), 'height'),
  fieldRadius: px(rule(connect, '.tf'), 'border-radius'), fieldPadding: 28,
  fieldSize: px(rule(connect, '.tf'), 'font-size'), fieldLabelSize: px(rule(connect, '.tf small'), 'font-size'),
  fieldLabelOffset: 34, fieldGap: 22, fieldBorder: 1.5, fieldFill: '0x0710189E',
  caretWidth: 3, caretHeight: 40, caretGap: 3, caretRadius: 2,
  actionGap: px(rule(auth, '.tvl .btns'), 'gap'), actionTop: 48,
  termsBottom: 64, termsSize: 20, termsLineHeight: 30,
  legalGap: 28,
  padRight: 260, padColumns: 3, padKeyWidth: 148, padKeyHeight: 118, padGap: 20, padRadius: 20, padSize: 48,
  padDeleteSize: 46,
  padFill: '0xEDF5FA12', padFocusFill: '0xEDF5FA2E', padScale: 1.05, padLinkGap: 18, padLinkHeight: 72, padLinkSize: 24,
  boxWidth: 104, boxHeight: 116, boxGap: 18, boxRadius: 18, boxBorder: 2, boxCaretHeight: 52, boxDot: 24,
  keyboardColumns: 9, keyboardGap: 10, keyboardKeyHeight: 72, keyboardRadius: 14, keyboardSize: 28,
  keyboardSpaceSpan: 3, keyboardClearSpan: 2, keyboardFill: '0xEDF5FA0D'
  ,cardRight: 140, cardWidth: 720, cardTop: 52, cardSide: 56, cardBottom: 48, cardRadius: 28,
  cardFill: '0x0D1B25C7', cardBorder: 1.5, cardBorderAlpha: .1,
  qrSide: 300, qrPadding: 20, qrRadius: 20, qrGap: 34,
  hostSize: 30, hostLineHeight: 43.5, refSize: 21, refLineHeight: 30.45,
  cardShadowOffset: 60, cardShadowBlur: 120, cardShadowSpread: -40, cardShadowMargin: 240
};
// Verify composed shorthands too; no free redesign when a source rule changes.
for (const fragment of ['height: 84px', 'padding: 0 28px', 'rgba(7,16,24,.62)']) if (!rule(connect, '.tf').includes(fragment)) throw new Error('Re-read field style');
if (!rule(auth, '.tvkeys').includes('repeat(3, 148px)') || !rule(auth, '.tvpin .boxes i').includes('width: 104px')) throw new Error('Re-read PIN composition');
const emit = (name, value) => {
  const path = join(app, name);
  if (process.argv.includes('--check')) { if (readFileSync(path, 'utf8') !== value) throw new Error('Regenerate ' + name); }
  else { writeFileSync(path + '.tmp', value); renameSync(path + '.tmp', path); }
};
const require = createRequire(process.env.PORTICO_ASSET_TOOLS_ROOT ? join(process.env.PORTICO_ASSET_TOOLS_ROOT, 'package.json') : import.meta.url);
const {Resvg} = require('@resvg/resvg-js');
const backspace = /<symbol id="i-backspace"[^>]*>([\s\S]*?)<\/symbol>/.exec(auth)?.[1];
if (!backspace) throw new Error('Missing drawn backspace symbol');
for (const size of [metrics.padDeleteSize, metrics.fieldSize]) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24">${backspace.replaceAll('currentColor', '#fff')}</svg>`;
  const bytes = new Resvg(svg).render().asPng();
  const path = join(app, `images/icons/tv-auth-backspace-${size}.png`);
  if (process.argv.includes('--check')) { if (!readFileSync(path).equals(bytes)) throw new Error('Regenerate drawn backspace'); }
  else { writeFileSync(path + '.tmp', bytes); renameSync(path + '.tmp', path); }
}
for (let lines = 1; lines <= 4; lines++) {
  const height = metrics.cardTop + metrics.qrSide + metrics.qrGap + lines * metrics.hostLineHeight + 2 * metrics.refLineHeight + metrics.cardBottom;
  const margin = metrics.cardShadowMargin, spread = metrics.cardShadowSpread;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${metrics.cardWidth+margin*2}" height="${Math.ceil(height+margin*2)}"><defs><filter id="b" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="${metrics.cardShadowBlur/2}"/></filter></defs><rect x="${margin-spread}" y="${margin+metrics.cardShadowOffset-spread}" width="${metrics.cardWidth+spread*2}" height="${height+spread*2}" rx="${Math.max(0,metrics.cardRadius+spread)}" fill="#000" fill-opacity=".9" filter="url(#b)"/></svg>`;
  const bytes = new Resvg(svg).render().asPng();
  const path = join(app, `images/shapes/tv-handoff-shadow-${lines}.png`);
  if (process.argv.includes('--check')) { if (!readFileSync(path).equals(bytes)) throw new Error('Regenerate handoff shadow'); }
  else { writeFileSync(path + '.tmp', bytes); renameSync(path + '.tmp', path); }
}
emit('source/ui/TVSignInMetrics.bs', `' Composed by ruling 28: immutable ${commit}, auth8/9/17 + connect36.\nnamespace TVSignInMetrics\n${Object.entries(metrics).map(([key,value]) => '    const ' + key + ' = ' + JSON.stringify(value)).join('\n')}\nend namespace\n`);
const xml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
for (const locale of readdirSync(join(app, 'locale'))) {
  const name = `locale/${locale}/translations.xml`;
  let text = readFileSync(join(app, name), 'utf8').replace(/        <trans-unit id="roku\.tvSignIn\.[^"]*">[\s\S]*?<\/trans-unit>\n/g, '');
  for (const id of sharedIds) text = text.replace(new RegExp('        <trans-unit id="' + id.replaceAll('.', '\\.') + '">[\\s\\S]*?<\\/trans-unit>\\n', 'g'), '');
  if (!text.includes('    </body>')) throw new Error('Expected XLIFF');
  const rows = Object.entries({...messages, ...Object.fromEntries(sharedIds.map(id => [id, shared[id]]))}).map(([id,value]) => `        <trans-unit id="${id}">\n            <source>${id}</source>\n            <target>${xml(value)}</target>\n        </trans-unit>\n`).join('');
  emit(name, text.replace('    </body>', rows + '    </body>'));
}
console.log('TV sign-in composition: auth8/9/17 + connect36; seven drawn strings, no shared source changes');
