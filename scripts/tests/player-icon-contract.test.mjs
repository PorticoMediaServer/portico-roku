import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const fixture = JSON.parse(read('tests/player-icon-parity-cases.json'));
const manifest = JSON.parse(read('channel/data/generated/roku-icons.v1.json'));
const resolver = read('channel/source/core/PorticoIconResolver.brs');
const productLanguage = read('channel/source/core/PorticoProductLanguage.brs');
const contractGenerator = read('scripts/generate-portico-contracts.mjs');
const contractChecker = read('scripts/check-portico-contracts.mjs');
const packageJson = JSON.parse(read('package.json'));

function files(directory) {
  return readdirSync(resolve(root, directory), {withFileTypes: true}).flatMap(entry => {
    const relative = `${directory}/${entry.name}`;
    return entry.isDirectory() ? files(relative) : [relative];
  });
}

assert.equal(fixture.schemaVersion, 1);
for (const icon of fixture.icons.filter(icon => icon.master)) {
  assert.equal(manifest.semanticToMaster[icon.semanticId], icon.master);
  assert.ok(manifest.masters[icon.master][icon.state]);
}
assert.match(resolver, /status\.icon-mapping-missing/);
assert.match(resolver, /#if visual_fixture/);
assert.match(resolver, /return ""[\s\S]*end function\s*$/);
assert.doesNotMatch(resolver, /info(?:\.png|fallback)/i);
assert.match(productLanguage, /PorticoIconResolverUri\(document\.iconManifest, iconId, "default"\)/);
assert.doesNotMatch(productLanguage, /pkg:\/images\/icons\/info\.png/);
assert.match(contractGenerator, /EXTERNALLY_OWNED_GENERATED_FILES = new Set\(\[[\s\S]*'foundation-contract\.v2\.json',[\s\S]*'roku-icons\.v1\.json'[\s\S]*\]\)/);
assert.match(contractGenerator, /EXTERNALLY_OWNED_GENERATED_FILES\.has\(entry\)/);
assert.match(contractChecker, /!EXTERNALLY_OWNED_GENERATED_FILES\.has\(name\)/);
const activeSources = files('channel').filter(path => path.endsWith('.brs') || path.endsWith('.xml'));
const combinedSources = activeSources.map(read).join('\n');
assert.doesNotMatch(combinedSources, /pkg:\/images\/icons/, 'Active Roku source must never construct or embed icon asset paths.');
assert.doesNotMatch(combinedSources, /\bicon\s*:/, 'Active Roku models must publish iconId, never raw glyph names.');
for (const source of activeSources.map(read)) {
  for (const match of source.matchAll(/iconId\s*:\s*"([a-z0-9.-]+)"/g)) assert.ok(manifest.semanticToMaster[match[1]], `Unknown active semantic icon id: ${match[1]}`);
}

for (const component of ['PorticoButton', 'PorticoIconButton', 'PorticoRailItem', 'PorticoBrowseAction', 'PorticoSettingsRow', 'PorticoPlayerTransportButton']) {
  const source = read(`channel/components/${component}.brs`);
  const xml = read(`channel/components/${component}.xml`);
  assert.match(source, /PorticoIconResolverUri/);
  assert.match(xml, /PorticoIconResolver\.brs/);
  assert.doesNotMatch(source, /"pkg:\/images\/icons\/"\s*\+/);
}

assert.equal(packageJson.scripts['icons:sync'], 'node scripts/sync-semantic-icons.mjs');
assert.equal(packageJson.scripts['icons:check'], 'node scripts/sync-semantic-icons.mjs --check');
assert.match(packageJson.scripts['package:release'], /icons:check/);
assert.deepEqual(fixture.playerBack.map(entry => entry.expectedEvent), ['stop', 'exit-browsing', 'exit-browsing']);
assert.equal(fixture.activation.sameKeyUntilRelease, 1);
assert.equal(fixture.activation.staleGenerationCommits, 0);

console.log('Verified generated semantic icon packaging, strict unknown handling, product-language cutover, and Roku player parity fixtures.');
