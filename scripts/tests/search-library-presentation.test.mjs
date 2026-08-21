import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const search = read('channel/components/PorticoSearchScreen.brs');
const searchXml = read('channel/components/PorticoSearchScreen.xml');
const searchResult = read('channel/components/PorticoSearchResult.brs');
const library = read('channel/components/PorticoLibraryScreen.brs');
const libraryXml = read('channel/components/PorticoLibraryScreen.xml');
const browseCard = read('channel/components/PorticoBrowseCard.brs');
const browseList = read('channel/components/PorticoBrowseListRow.brs');
const browseTile = read('channel/components/PorticoBrowseTile.brs');

for (const component of [search, searchResult, library, browseCard, browseList, browseTile]) {
  assert.doesNotMatch(component, /removeChildrenIndex|CreateObject\("roSGNode"/);
  assert.doesNotMatch(component, /Fargo|The Rookie|fixture|sample media/i, 'runtime presentation source must not contain fixture data');
}

assert.equal((searchXml.match(/<PorticoSearchKey id="key\d+"/g) ?? []).length, 40);
assert.equal((searchXml.match(/<PorticoSearchResult id="result\d+"/g) ?? []).length, 24);
assert.equal((searchXml.match(/<PorticoButton id="more\d+"/g) ?? []).length, 6);
assert.match(searchXml, /<Poster id="querySurface" width="1200" height="68"/);
assert.match(search, /"A","B","C","D","E","F","G","H","I","J"/);
for (const special of ['SPACE', 'DEL', 'CLEAR', 'SEARCH']) assert.match(search, new RegExp(`"${special}"`));
for (const activation of ['query-changed', 'clear-search', 'submit-search', 'retry-search', 'open-detail', 'play-live', 'load-more']) {
  assert.match(search, new RegExp(`"${activation}"`));
}
for (const status of ['loading', 'ready', 'empty', 'error', 'idle']) assert.match(search, new RegExp(`"${status}"`));
assert.match(search, /if Len\(m\.query\) < 120/);
assert.match(search, /if Len\(m\.query\.Trim\(\)\) >= 2/);
assert.match(search, /if m\.keyboardVisible[\s\S]*m\.focusArea = "query"[\s\S]*return true/);
assert.match(search, /PorticoSearchSafeUri[\s\S]*Left\(normalized, 5\) = "pkg:\/"[\s\S]*Left\(normalized, 5\) = "tmp:\/"/);

assert.equal((libraryXml.match(/<PorticoBrowseTab id="tab\d+"/g) ?? []).length, 6);
assert.equal((libraryXml.match(/<PorticoBrowseAction id="toolbar\d+"/g) ?? []).length, 4);
assert.equal((libraryXml.match(/<PorticoBrowseCard id="card\d+"/g) ?? []).length, 21);
assert.equal((libraryXml.match(/<PorticoBrowseListRow id="list\d+"/g) ?? []).length, 12);
assert.equal((libraryXml.match(/<PorticoBrowseTile id="tile\d+"/g) ?? []).length, 12);
for (const presentation of ['shelves', 'list', 'facets', 'resources', 'schedule']) assert.match(library, new RegExp(`presentation = "${presentation}"`));
for (const activation of ['select-tab', 'open-detail', 'select-facet', 'select-resource', 'load-more', 'retry-library']) assert.match(library, new RegExp(`"${activation}"`));
for (const state of ['loading', 'ready', 'empty', 'error']) assert.match(library, new RegExp(`"${state}"`));
assert.match(library, /PorticoLibrarySafeUri[\s\S]*Left\(normalized, 5\) = "pkg:\/"[\s\S]*Left\(normalized, 5\) = "tmp:\/"/);
assert.match(libraryXml, /<Label id="availabilityLabel"[\s\S]*horizAlign="right"/);
assert.match(library, /status = "offline"[\s\S]*"OFFLINE"[\s\S]*status = "refresh-failed"[\s\S]*"COULDN'T REFRESH"/);
assert.match(search, /function PorticoSearchResultModel[\s\S]*if id = "" or title = "" then return invalid/);
assert.match(search, /destination = "live"[\s\S]*kind: "play-live"[\s\S]*targetId: target\.id/, 'live channel results must direct tune instead of opening generic media detail');
assert.match(search, /function PorticoSearchSafeInteger/);
assert.match(library, /function PorticoLibrarySafeInteger/);
assert.match(browseCard, /shape = "square"[\s\S]*square-card-focus/);
assert.match(browseList, /m\.top\.focusable = not schedule/);
assert.match(browseTile, /m\.top\.tileKind = "resource"/);

const keys = [
  ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123',
  '4', '5', '6', '7', '8', '9', 'SPACE', 'DEL', 'CLEAR', 'SEARCH',
];
assert.equal(keys.length, 40);
const move = (index, key) => {
  if (key === 'left' && index % 10 > 0) return index - 1;
  if (key === 'right' && index % 10 < 9) return index + 1;
  if (key === 'up' && index >= 10) return index - 10;
  if (key === 'down' && index < 30) return index + 10;
  return index;
};
assert.equal(move(0, 'left'), 0);
assert.equal(move(9, 'right'), 9);
assert.equal(move(30, 'down'), 30);
assert.equal(move(17, 'up'), 7);

console.log('Verified model-driven Search and Library SceneGraph presentation and focus contracts.');
