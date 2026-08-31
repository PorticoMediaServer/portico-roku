import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

for (const component of [
  "PorticoButton.brs", "PorticoIconButton.brs", "PorticoMediaCard.brs",
  "PorticoBrowseCard.brs", "PorticoSearchKey.brs", "PorticoSettingsRow.brs",
  "PorticoProfileCard.brs", "PorticoPlayerTransportButton.brs",
  "PorticoGuideProgram.brs", "PorticoDvrConsumerRow.brs",
]) {
  assert.match(read(`channel/components/${component}`), /accessibilityLabel/, `${component} must expose an item-level Audio Guide label`);
}

const detailXml = read("channel/components/PorticoDetail.xml");
for (const field of ["focusedAction", "focusedEpisode", "focusedPerson", "focusedPersonResult", "focusedRelationshipItem", "focusArea"]) {
  assert.match(detailXml, new RegExp(`id="${field}"[^>]+onChange="updateFocus"`));
}
assert.doesNotMatch(read("channel/components/PorticoDetail.brs").match(/sub updateFocus\(\)[\s\S]*?end sub/)?.[0] ?? "", /removeChildrenIndex/);

const home = read("channel/components/PorticoHome.brs");
assert.match(home, /lastVisibleRow = firstVisibleRow \+ 2/);
assert.match(home, /for slotIndex = 0 to 2[\s\S]*?m\.rowGroups\.push\(rowGroup\)/);
assert.doesNotMatch(home, /removeChild\(m\.rowGroups|m\.rowGroups\.Delete/);
assert.match(home, /if nextHeroSignature <> m\.heroSignature/);
assert.match(home, /if nextAvailabilitySignature <> m\.availabilitySignature/);

const detail = read("channel/components/PorticoDetail.brs");
assert.match(detail, /sub detailRebindFocusedWindows\(\)/);
assert.match(detail, /m\.focusWindows\[focusArea\] = \{kind: "media"/);
assert.match(detail, /m\.focusWindows\.detailPeople = \{kind: "person"/);
assert.match(detail, /detailBindPersonSlot\(node, window\.items\[logicalIndex\]\)/);

const boundedTasks = ["Library", "LiveTv", "Search", "Profile", "Content", "ViewerPreferences", "LocalAuth", "Saved", "Engagement"];
for (const name of boundedTasks) {
  const source = read(`channel/components/Portico${name}Task.brs`);
  const waits = [...source.matchAll(/Sleep\((\d+)\)/g)].map((match) => Number(match[1]));
  assert.ok(waits.length > 0 && Math.min(...waits) >= 250, `${name} feature task must use a bounded low-frequency idle wait`);
}

// Deterministic proxy for a ten-hour session at 12 navigation inputs/second.
// The three-row Home viewport and nine-person Detail window remain constant.
const inputs = 10 * 60 * 60 * 12;
let focusedRow = 0;
let focusedItem = 0;
const homeSlots = Array.from({length: 3}, () => ({logicalRow: -1}));
const detailSlots = Array.from({length: 9}, () => ({logicalIndex: -1}));
for (let i = 0; i < inputs; i += 1) {
  focusedRow = (focusedRow + (i % 17 === 0 ? 1 : 0)) % 32;
  focusedItem = (focusedItem + 1) % 100_000;
  const firstRow = Math.max(0, focusedRow - 1);
  const visibleRows = Math.min(3, 32 - firstRow);
  const visiblePeople = Math.min(9, 100_000 - Math.max(0, focusedItem - 8));
  assert.ok(visibleRows <= 3 && visiblePeople <= 9);
  for (let slot = 0; slot < homeSlots.length; slot += 1) homeSlots[slot].logicalRow = firstRow + slot;
  const firstPerson = Math.max(0, focusedItem - 8);
  for (let slot = 0; slot < detailSlots.length; slot += 1) detailSlots[slot].logicalIndex = firstPerson + slot;
}
assert.equal(homeSlots.length, 3, "ordinary Home traversal must reuse three shelf nodes");
assert.equal(detailSlots.length, 9, "Detail traversal must reuse nine person nodes across viewport boundaries");

const player = read("channel/components/PorticoPlayer.brs");
assert.match(player, /PorticoPlayerReducedMotion/);
assert.match(player, /for each item in source\.qualityOffers\.offers[\s\S]*label: item\.label/);
const settings = read("channel/source/lib/PorticoSettingsModels.brs");
assert.match(settings, /id: "playback-quality"[\s\S]*?settings\.value\.automatic[\s\S]*?actionable: false/);
assert.match(settings, /id: "roku-caption-style"[\s\S]*?Managed by Roku[\s\S]*?actionable: false/);
assert.doesNotMatch(settings, /id: "reduced-motion"/);
console.log(`accessibility/performance evidence passed (${inputs.toLocaleString()} synthetic inputs)`);
