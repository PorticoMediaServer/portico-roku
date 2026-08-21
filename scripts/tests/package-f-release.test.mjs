import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {conservativeRokuCapabilityProfile} from '../lib/roku-capability-profile.mjs';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const profile = conservativeRokuCapabilityProfile({model: '4800X', name: 'Roku Ultra', osVersion: '14.1.4', maxWidth: 3840, maxHeight: 2160});

assert.equal(profile.capabilitySchemaVersion, 'playback-capability-v2');
assert.equal(profile.clientFamily, 'roku');
assert.equal(profile.clientVersion, '14.1.4');
assert.deepEqual(profile.capabilityEvidence, [], 'Display/model identity must not fabricate runtime decoder tuples.');
assert.equal(profile.maxWidth, 1920);
assert.equal(profile.maxHeight, 1080);
assert.deepEqual(profile.supportedVideoProfiles, ['h264:main']);
for (const field of ['supportsHevc', 'supportsHdr', 'supportsAc3', 'supportsEac3']) assert.equal(profile[field], false);
assert.equal(profile.maxAudioChannels, 2);
assert.deepEqual(profile.supportedHdrFormats, []);
assert.deepEqual(profile.supportedDolbyVisionProfiles, []);

const source = readFileSync(resolve(root, 'channel/source/lib/PorticoPlaybackModels.brs'), 'utf8');
assert.match(source, /capabilitySchemaVersion: "playback-capability-v2"/);
assert.match(source, /clientFamily: "roku"/);
assert.doesNotMatch(source, /function PorticoPlaybackRokuCapabilityTuples/);
assert.doesNotMatch(source, /CanDecodeVideo\(\{codec: "hevc"|CanDecodeAudio\(\{codec: "(?:ac3|eac3)"/);
assert.match(source, /Publish no runtime tuple evidence/);

console.log('Verified conservative Roku capability projection and Package F source parity.');
