import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const task = read('channel/components/PorticoServerConnectionTask.brs');
const bridge = read('channel/source/lib/PorticoServerConnection.brs');
const main = read('channel/source/main.brs');

// Only the validated, non-private capability projection can enter runtimeState.
assert.match(task, /PorticoProductContractValidateLive\(contract\.data\)\.ok/);
assert.match(task, /eventCapabilities = \{[\s\S]*eventTransports: contract\.data\.eventTransports,[\s\S]*longPoll: contract\.data\.longPoll/);
assert.match(task, /productContractRevision = PorticoViewerScopeOpaqueId\(contract\.data\.semanticIdentity\.digest, 128\)/);
assert.match(task, /controller\.eventCapabilities = invalid[\s\S]*controller\.productContractRevision = ""/);
assert.match(bridge, /allowed = \{[\s\S]*productContractRevision: true,[\s\S]*eventCapabilities: true/);
assert.match(bridge, /result = \{eventTransports: transports\}/);
assert.match(bridge, /result\.longPoll = \{/);
assert.doesNotMatch(bridge, /eventCapabilities[\s\S]{0,240}actionRevision/);
assert.doesNotMatch(bridge, /nextState\.(?:productContract|contractData|mediaActions|serverCapabilities)/);

// Main forwards the same narrow projection to every event consumer and LiveTV
// consumes the validated live action revision rather than a packaged snapshot.
assert.match(main, /eventCapabilities = domainState\.eventCapabilities/);
assert.match(main, /PorticoApplicationEventsViewerStateChanged\([^\n]*(?:domainState|scene\.runtimeState)/);
assert.match(main, /PorticoPlaybackEventsViewerStateChanged\([^\n]*eventCapabilities/);
assert.match(main, /PorticoWatchWithFriendsViewerStateChanged\([^\n]*eventCapabilities/);
assert.match(main, /PorticoEngagementViewerStateChanged\([^\n]*eventCapabilities/);
assert.match(main, /productContractRevision = PorticoViewerScopeOpaqueId\(domainState\.productContractRevision, 128\)/);
assert.match(main, /PorticoLiveTvViewerStateChanged\([^\n]*productContractRevision/);

console.log('Verified sanitized live Product Contract capability propagation, consumer fan-out, runtime-state privacy, and LiveTV revision flow.');
