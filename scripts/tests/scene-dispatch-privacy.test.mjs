import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const scene = readFileSync(resolve(root, "channel/components/PorticoScene.brs"), "utf8");

const allowedPayloadKeys = new Set([
  "sequence", "kind", "contractRevision", "ackRequired", "deliveryId", "intentId",
  "gateDelivery", "route", "targetId", "mediaType", "origin", "viewerGeneration",
  "lifecycleGeneration", "serverId", "profileId", "showImportantNotice"
]);

function privateDispatchKey(value) {
  const compact = value.toLowerCase().replaceAll(/[-_. ]/g, "");
  return ["authorization", "password", "token", "grant", "secret", "header", "session", "apikey"]
    .some(fragment => compact.includes(fragment));
}

function validateExternalRequest(request, {viewerGeneration = 7, lifecycleGeneration = 3, acknowledgementAvailable = true} = {}) {
  if (!request || typeof request !== "object" || Array.isArray(request)) return false;
  for (const key of Object.keys(request)) {
    if (privateDispatchKey(key) || !allowedPayloadKeys.has(key)) return false;
  }
  if (!Number.isInteger(request.sequence) || request.sequence < 1) return false;
  if (!new Set(["route", "open-detail", "play"]).has(request.kind)) return false;
  if (request.contractRevision !== "v1" || request.ackRequired !== true || !acknowledgementAvailable) return false;
  if (typeof request.deliveryId !== "string" || !/^[A-Za-z0-9._-]{1,128}$/.test(request.deliveryId)) return false;
  if (request.intentId !== undefined && request.intentId !== request.deliveryId) return false;
  if (request.kind === "route" ? typeof request.route !== "string" || request.route === "" : typeof request.targetId !== "string" || request.targetId === "") return false;
  if (request.viewerGeneration !== undefined && request.viewerGeneration !== viewerGeneration) return false;
  if (request.lifecycleGeneration !== undefined && request.lifecycleGeneration !== lifecycleGeneration) return false;
  return true;
}

const valid = {
  sequence: 8,
  kind: "route",
  contractRevision: "v1",
  ackRequired: true,
  deliveryId: "intent-8",
  intentId: "intent-8",
  route: "home",
  origin: "deep-link",
  viewerGeneration: 7,
  lifecycleGeneration: 3,
  serverId: "server-1",
  profileId: "profile-1"
};

assert.equal(validateExternalRequest(valid), true);
assert.equal(validateExternalRequest({...valid, unexpected: "value"}), false);
assert.equal(validateExternalRequest({...valid, contractRevision: "v2"}), false);
assert.equal(validateExternalRequest({...valid, ackRequired: false}), false);
assert.equal(validateExternalRequest({...valid, deliveryId: ""}), false);
assert.equal(validateExternalRequest({...valid, viewerGeneration: 6}), false);

for (const key of [
  "Authorization", "PASSWORD", "refreshToken", "grant", "mediaSecret", "Headers",
  "SESSION_ID", "API-Key", "api_key", "x-api-key"
]) {
  assert.equal(validateExternalRequest({...valid, [key]: "opaque"}), false, `${key} must be private at any case`);
}

assert.equal(validateExternalRequest(valid, {acknowledgementAvailable: false}), false);
assert.match(scene, /function PorticoSceneExternalRequestAllowedPayloadKeys\(/);
assert.match(scene, /function PorticoSceneValidateExternalRequest\(/);
assert.match(scene, /function PorticoScenePrivateDispatchKey\(/);
assert.match(scene, /contractRevision: "v1"/);
assert.match(scene, /ackRequired/);
assert.match(scene, /externalRequestAcknowledgement/);
assert.match(scene, /HasField\("externalRequestAcknowledgement"\)/);

const internalForwarding = scene.match(/sub emitForwardedActivation\(action as object\)[\s\S]*?end sub/)?.[0] ?? "";
assert.match(internalForwarding, /for each key in action/);
assert.match(internalForwarding, /forwarded\[key\] = action\[key\]/);
assert.doesNotMatch(internalForwarding, /PorticoSceneValidateExternalRequest/);

console.log("Verified strict external-request envelope/privacy boundaries and preservation of ordinary internal activation payloads.");
