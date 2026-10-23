// Platform composition explicitly authorized by ruling 28; no shared package is mirrored.
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, renameSync, readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, resolve, join} from 'node:path';
const app = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const root = process.env.PORTICO_INTERNAL_ROOT;
if (!root) throw new Error('Set PORTICO_INTERNAL_ROOT to the immutable design Git repository');
const commit = '69f2d45a972ff9ec1bd8743c760183026c92d555';
const load = name => execFileSync('git', ['show', `${commit}:design/ui-v1/${name}`], {cwd: root, maxBuffer: 4 * 1024 * 1024}).toString();
const auth = load('auth.html'), connect = load('connect.html');
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
  left: 200, columnWidth: px(rule(auth, '.tvl'), 'width'),
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
  padFill: '0xEDF5FA12', padFocusFill: '0xEDF5FA2E', padScale: 1.05, padLinkGap: 18, padLinkHeight: 72, padLinkSize: 24,
  boxWidth: 104, boxHeight: 116, boxGap: 18, boxRadius: 18, boxBorder: 2, boxCaretHeight: 52, boxDot: 24,
  keyboardColumns: 9, keyboardGap: 10, keyboardKeyHeight: 72, keyboardRadius: 14, keyboardSize: 28,
  keyboardSpaceSpan: 3, keyboardClearSpan: 2, keyboardFill: '0xEDF5FA0D'
};
// Verify composed shorthands too; no free redesign when a source rule changes.
for (const fragment of ['height: 84px', 'padding: 0 28px', 'rgba(7,16,24,.62)']) if (!rule(connect, '.tf').includes(fragment)) throw new Error('Re-read field style');
if (!rule(auth, '.tvkeys').includes('repeat(3, 148px)') || !rule(auth, '.tvpin .boxes i').includes('width: 104px')) throw new Error('Re-read PIN composition');
const emit = (name, value) => {
  const path = join(app, name);
  if (process.argv.includes('--check')) { if (readFileSync(path, 'utf8') !== value) throw new Error('Regenerate ' + name); }
  else { writeFileSync(path + '.tmp', value); renameSync(path + '.tmp', path); }
};
emit('source/ui/TVSignInMetrics.bs', `' Composed by ruling 28: immutable ${commit}, auth8/9/17 + connect36.\nnamespace TVSignInMetrics\n${Object.entries(metrics).map(([key,value]) => '    const ' + key + ' = ' + JSON.stringify(value)).join('\n')}\nend namespace\n`);
const xml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
for (const locale of readdirSync(join(app, 'locale'))) {
  const name = `locale/${locale}/translations.xml`;
  let text = readFileSync(join(app, name), 'utf8').replace(/        <trans-unit id="roku\.tvSignIn\.[^"]*">[\s\S]*?<\/trans-unit>\n/g, '');
  if (!text.includes('    </body>')) throw new Error('Expected XLIFF');
  const rows = Object.entries(messages).map(([id,value]) => `        <trans-unit id="${id}">\n            <source>${id}</source>\n            <target>${xml(value)}</target>\n        </trans-unit>\n`).join('');
  emit(name, text.replace('    </body>', rows + '    </body>'));
}
console.log('TV sign-in composition: auth8/9/17 + connect36; seven drawn strings, no shared source changes');
