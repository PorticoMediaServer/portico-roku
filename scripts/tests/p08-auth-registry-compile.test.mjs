import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const profiles = read('channel/source/lib/PorticoProfiles.brs');
const selectionXml = read('channel/components/PorticoProfileSelectionScreen.xml');
const sourceOnly = profiles.replace(/^\s*'.*$/gm, '');

assert.match(selectionXml, /uri="pkg:\/source\/lib\/PorticoProfiles\.brs"/);
assert.match(selectionXml, /<script type="text\/brightscript" uri="pkg:\/source\/lib\/PorticoSecureRegistry\.brs" \/>/);

const transactionBody = sourceOnly.match(/function PorticoProfilesSelectionTransactionWrite[\s\S]*?end function/)?.[0] ?? '';
const consumeBody = sourceOnly.match(/function PorticoProfilesSelectionTransactionConsume[\s\S]*?end function/)?.[0] ?? '';
assert.match(transactionBody, /PorticoSecureRegistryCommit\("profile-selection-handoff", payload\)/);
assert.match(consumeBody, /PorticoSecureRegistryRead\("profile-selection-handoff"\)/);
assert.match(consumeBody, /PorticoSecureRegistryConsume\("profile-selection-handoff"\)/);
assert.match(profiles, /PorticoSecureRegistryClear\("profile-selection-handoff"\)/);
for (const helper of ['PorticoProfilesSelectionRegistryRead', 'PorticoProfilesSelectionRegistryCommit', 'PorticoProfilesSelectionRegistryConsume', 'PorticoProfilesSelectionRegistryClear']) {
  assert.doesNotMatch(profiles, new RegExp(helper));
}

console.log('Verified P08 profile-selection registry import and canonical single-registry calls.');
