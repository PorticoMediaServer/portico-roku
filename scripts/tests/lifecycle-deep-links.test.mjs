import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const lifecycle = read('channel/source/lib/PorticoLifecycle.brs');
const main = read('channel/source/main.brs');
const sceneXml = read('channel/components/PorticoScene.xml');

assert.match(main, /lifecycle = PorticoLifecycleController\(args\)/);
assert.match(main, /input = CreateObject\("roInput"\)/);
assert.match(main, /type\(message\) = "roInputEvent" and message\.IsInput\(\)[\s\S]*PorticoLifecycleAcceptInput\(lifecycle, message\.GetInfo\(\)\)/);
assert.match(main, /message\.IsScreenClosed\(\)[\s\S]*PorticoLifecycleRememberPage[\s\S]*PorticoPlaybackShutdown\(playback, port, 3500\)/);
assert.match(sceneXml, /<field id="externalRequest" type="assocarray" alwaysNotify="true"/);

assert.match(lifecycle, /PorticoLifecycleArgument\(args, \["contentid", "content-id"\]\)/);
assert.match(lifecycle, /PorticoLifecycleArgument\(args, \["mediatype", "media-type"\]\)/);
assert.match(lifecycle, /if mediaType = "season"[\s\S]*kind: "open-detail"/);
for (const type of ['movie', 'episode', 'series', 'shortformvideo', 'tvspecial']) assert.match(lifecycle, new RegExp(`mediaType = "${type}"`));
assert.match(lifecycle, /return \{kind: "route", route: "home", origin: "invalid-deep-link"\}/);
assert.match(lifecycle, /allowedKinds = \{route: true, "open-detail": true, play: true\}/);
assert.match(lifecycle, /request\.origin = PorticoLifecycleText\(source\.origin, "lifecycle", 32\)/);
assert.match(lifecycle, /scene\.externalRequest = request/);

assert.match(lifecycle, /if not PorticoLifecycleSignedIn\(state\) then return/);
assert.match(lifecycle, /gate\.gate = "server"[\s\S]*route: "server-selection", origin: "deep-link"/);
assert.match(lifecycle, /serverStatus, "", 40\)\) <> "online" then return/);
assert.match(lifecycle, /awaitingLaunchSurface = "player"/);
assert.match(lifecycle, /awaitingLaunchSurface = "detail"/);
assert.match(lifecycle, /signalBeacon\("AppDialogInitiate"\)/);
assert.match(lifecycle, /signalBeacon\("AppDialogComplete"\)/);
assert.match(lifecycle, /signalBeacon\("AppLaunchComplete"\)/);

assert.match(lifecycle, /PorticoSecureRegistryRead\("navigation"\)/);
assert.match(lifecycle, /PorticoSecureRegistryCommit\("navigation", payload\)/);
assert.match(lifecycle, /PorticoSecureRegistryCommit\("pending-deep-link", payload\)/);
assert.match(lifecycle, /function PorticoLifecycleAcknowledgeDispatch\(/);
assert.match(lifecycle, /deliveryInFlight/);
assert.match(lifecycle, /if route = "" or route = "server-selection" then return/);
assert.match(lifecycle, /if Left\(route, 8\) = "library\/"[\s\S]*selectedServerId = PorticoLifecycleSafeId\(state\.selectedServerId\)/);
assert.match(lifecycle, /boundServerId = "" or boundServerId <> selectedServerId then route = "library"/);
assert.match(lifecycle, /kind = "sign-out-account" or kind = "sign-out-local"[\s\S]*PorticoLifecycleClearNavigation/);
assert.match(lifecycle, /allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\._-"/);

console.log('Verified launch/input deep links, signed-in/server gating, Roku beacons, bounded route restore, and graceful shutdown contracts.');
