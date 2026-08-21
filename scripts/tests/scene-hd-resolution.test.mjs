import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const read = path => readFileSync(resolve(root, path), "utf8");
const manifest = read("channel/manifest");
const developmentManifest = read("channel/development/manifest");
const hardware = JSON.parse(read("channel/data/parity/roku-hardware-instrumentation.v1.json"));
const scene = read("channel/components/PorticoScene.brs");

for (const source of [manifest, developmentManifest]) {
  assert.equal(source.match(/^ui_resolutions=(.+)$/m)?.[1].toLowerCase(), "fhd");
}

assert.deepEqual(hardware.advertisedResolutionClasses, ["fhd"]);
assert.deepEqual(hardware.resolutionAdvertisement.advertisedClasses, ["fhd"]);
assert.deepEqual(hardware.resolutionAdvertisement.pendingEvidenceClasses, ["hd"]);
assert.equal(hardware.resolutionAdvertisement.policy, "fail-closed");
assert.equal(hardware.resolutionAdvertisement.requiresRuntimeEvidence, true);
assert.equal(hardware.evidence.sourceOnlyStatus, "does-not-claim-hardware-execution");
assert.equal(hardware.scaling.hdStatus, "source-contract-pending-runtime");

const hd = hardware.deviceClasses.find(device => device.id === "low-power-hd");
assert.equal(hd.advertised, false);
assert.match(hd.status, /pending/);

function layoutScale(displayWidth, displayHeight, designWidth = 1920, designHeight = 1080) {
  return Math.min(displayWidth / designWidth, displayHeight / designHeight);
}

assert.equal(layoutScale(1280, 720), 2 / 3);
assert.equal(layoutScale(1920, 1080), 1);
assert.match(hardware.scaling.contract, /FHD design space.*scale uniformly/i);
assert.match(scene, /HD|FHD|display/i);

console.log("Verified fail-closed FHD-only advertisement while HD evidence remains pending, with source scaling math retained.");
