import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const read = path => readFileSync(resolve(root, path), 'utf8');
const scene = read('channel/components/PorticoScene.brs');
const sceneXml = read('channel/components/PorticoScene.xml');
const developmentContract = JSON.parse(read('channel/data/visual-contract.json'));
const runtimeContract = JSON.parse(read('channel/data/runtime-ui-contract.json'));

assert.deepEqual(runtimeContract.motion, developmentContract.motion);
assert.deepEqual(runtimeContract.motion.pageTransition, {
  enabled: true,
  durationMs: 200,
  style: 'fade-through',
  animatedProperty: 'opacity',
  minimumDurationMs: 180,
  maximumDurationMs: 220
});
assert.equal(runtimeContract.motion.reducedMotion.immediate, true);

// One top-level veil covers every lazy route surface without per-screen hacks.
assert.match(sceneXml, /<Rectangle id="pageTransitionVeil" width="1920" height="1080"[^>]*opacity="0"[^>]*visible="false"/);
assert.match(sceneXml, /<Animation id="pageTransitionAnimation" duration="0\.2" repeat="false" easeFunction="linear">/);
assert.match(sceneXml, /<FloatFieldInterpolator[^>]*keyValue="\[1\.0,0\.0\]"[^>]*fieldToInterp="pageTransitionVeil\.opacity"/);
assert.doesNotMatch(sceneXml, /Vector2DFieldInterpolator|ScaleFieldInterpolator|translation"|scale"/);

const identity = scene.match(/function PorticoSceneFullPageIdentity[\s\S]*?end function/)?.[0] ?? '';
assert.match(identity, /return "auth:" \+ m\.signedOutGateMode/);
assert.match(identity, /profileSelectionOverlay[\s\S]*return "profile-selection"/);
assert.match(identity, /m\.route = "player"[\s\S]*return "player"/);
assert.match(identity, /return "route:" \+ m\.route/);

const reconcile = scene.match(/sub PorticoSceneReconcileFullPageTransition[\s\S]*?end sub/)?.[0] ?? '';
assert.match(reconcile, /previous = m\.lastFullPageIdentity[\s\S]*if not PorticoScenePageMotionEnabled\(\)[\s\S]*PorticoSceneResetPageTransition\(\)[\s\S]*return[\s\S]*if previous = "" or previous = identity then return/);
assert.doesNotMatch(reconcile, /control = "stop"/, 'Restarting a running transition must not enqueue a stale stopped callback.');
assert.match(reconcile, /if durationMs < 180 then durationMs = 180/);
assert.match(reconcile, /if durationMs > 220 then durationMs = 220/);
assert.match(reconcile, /pageTransitionAnimation\.control = "start"/);

const enabled = scene.match(/function PorticoScenePageMotionEnabled[\s\S]*?end function/)?.[0] ?? '';
assert.match(enabled, /state\.reducedMotion = true or state\.animationsEnabled = false then return false/);
assert.match(scene, /sub renderScene\(\)[\s\S]*PorticoSceneReconcileFullPageTransition\(\)/);
assert.equal((scene.match(/PorticoSceneReconcileFullPageTransition\(\)/g) ?? []).length, 2, 'Transition reconciliation must remain centralized: one definition and one render call.');

console.log('Verified centralized, reduced-motion-safe Roku full-page transitions.');
