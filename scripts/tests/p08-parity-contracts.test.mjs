import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join, resolve} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {
  PARITY_SOURCE_DIRECTORY,
  readParityContracts,
  validateParityFiles,
  validateParityContracts
} from "../../../../scripts/parity/parity-contracts.mjs";
import {
  acceptCapability,
  mapRemoteInput,
  planRecovery,
  reduceBack,
  sanitizeDiagnostic
} from "../../../../scripts/parity/parity-models.mjs";
import {
  renderManifest,
  releaseIdentityDocument,
  resolveRokuReleaseIdentity,
  sourceManifestVersion
} from "../lib/roku-release-policy.mjs";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));

const diagnosticFixture = {
  buildVersion: "0.1.0",
  buildChannel: "development",
  platform: "roku",
  routeId: "home",
  viewerGeneration: 4,
  requestId: "request-123",
  eventKind: "route",
  occurredAt: "2026-08-17T00:00:00Z"
};

test("P08 parity contracts are versioned, complete, and source-only", () => {
  assert.doesNotThrow(() => validateParityFiles());
  const contracts = readParityContracts(PARITY_SOURCE_DIRECTORY);
  assert.doesNotThrow(() => validateParityContracts(contracts));
  const matrix = contracts["tvos-roku-acceptance-matrix.v1.json"];
  assert.equal(matrix.cases.length, 10);
  assert.ok(matrix.cases.every((item) => item.key.clientArtifactSha256 === null && item.status === "pending-runtime"));
  assert.ok(matrix.pendingRuntimeCases.every((item) => item.status === "awaiting-runtime"));
  const registry = contracts["parity-exceptions.v1.json"];
  assert.ok(registry.entries.some((entry) => entry.id === "downloads" && entry.rokuBehavior === "unsupported"));
  assert.ok(registry.entries.some((entry) => entry.id === "deep-link-unknown-route" && entry.classification === "product_decision"));
});

test("semantic remote model has one safe Back hierarchy and platform mappings", () => {
  assert.equal(mapRemoteInput("roku", "back"), "back");
  assert.equal(mapRemoteInput("tvos", "menu"), "back");
  assert.equal(mapRemoteInput("roku", "unknown"), null);
  assert.deepEqual(reduceBack({utilityOverlayCount: 1, playerActive: true}), {action: "close-top-utility-overlay", finalEvent: null});
  assert.deepEqual(reduceBack({modalOrPanelCount: 1, playerActive: true}), {action: "close-modal-or-panel", finalEvent: null});
  assert.deepEqual(reduceBack({playerActive: true, chromeVisible: false}), {action: "exit-player-to-previous-route", finalEvent: "stop"});
  assert.deepEqual(reduceBack({playerActive: true, chromeVisible: true}), {action: "exit-player-to-previous-route", finalEvent: "stop"});
  assert.deepEqual(reduceBack({routeDepth: 0}), {action: "remain-at-root", finalEvent: null});
  const rokuSource = readFileSync(join(root, "channel/source/lib/PorticoRemoteAccessibilityModels.brs"), "utf8");
  assert.match(rokuSource, /function PorticoRemoteMapKey/);
  assert.match(rokuSource, /function PorticoRemoteBackDecision/);
});

test("shared recovery model bounds retries and rejects unknown required semantics", () => {
  assert.deepEqual(planRecovery("http-401", 0), {classification: "authentication_required", action: "refresh_credentials", terminal: false, retryAttempt: 1});
  assert.deepEqual(planRecovery("http-401", 1), {classification: "authentication_required", action: "sign_in", terminal: true, retryAttempt: 1});
  assert.deepEqual(planRecovery("http-429", 1), {classification: "throttled", action: "retry_after", terminal: false, retryAttempt: 2});
  assert.deepEqual(planRecovery("http-429", 2), {classification: "throttled", action: "contact_support", terminal: true, retryAttempt: 2});
  assert.deepEqual(planRecovery("unknown-required-action"), {classification: "unsupported_required_action", action: "upgrade_client", terminal: true, retryAttempt: 0});
  assert.deepEqual(planRecovery("not-in-catalog"), {classification: "unknown_failure", action: "terminal", terminal: true, retryAttempt: 0});
  assert.deepEqual(acceptCapability("futureOptional", false, {}), {state: "unknown", action: "ignore_and_preserve"});
  assert.deepEqual(acceptCapability("futureRequired", true, {}), {state: "unsupported", action: "upgrade_client"});
});

test("diagnostic model emits only the bounded privacy-safe allowlist", () => {
  assert.deepEqual(sanitizeDiagnostic(diagnosticFixture), {
    buildVersion: "0.1.0",
    buildChannel: "development",
    platform: "roku",
    routeId: "home",
    viewerGeneration: "4",
    requestId: "request-123",
    eventKind: "route",
    occurredAt: "2026-08-17T00:00:00Z"
  });
  assert.equal(sanitizeDiagnostic({...diagnosticFixture, accessToken: "opaque"}), null);
  assert.equal(sanitizeDiagnostic({...diagnosticFixture, rawError: "password=should-not-be-recorded"}), null);
  assert.equal(sanitizeDiagnostic({eventKind: "route"}), null);
  const rokuSource = readFileSync(join(root, "channel/source/lib/PorticoDiagnosticsModels.brs"), "utf8");
  assert.match(rokuSource, /function PorticoDiagnosticsSanitize/);
  assert.match(rokuSource, /function PorticoDiagnosticsPrivateFields/);
});

test("diagnostic model rejects every private and secret-like key case-insensitively", () => {
  const privateFields = [
    "accessToken",
    "refreshToken",
    "mediaGrant",
    "password",
    "pin",
    "accountEmail",
    "profileName",
    "mediaTitle",
    "mediaId",
    "serverOrigin",
    "url",
    "headers",
    "filesystemPath",
    "rawError"
  ];
  for (const field of privateFields) {
    assert.equal(sanitizeDiagnostic({...diagnosticFixture, [field]: "private-value"}), null, `${field} must invalidate the event`);
  }

  for (const field of ["ACCESS_TOKEN", "MediaID", "rAwErRoR", "server_origin", "PRIVATE-KEY"]) {
    assert.equal(sanitizeDiagnostic({...diagnosticFixture, [field]: "private-value"}), null, `${field} must invalidate the event`);
  }

  for (const field of ["apiSecret", "authorizationHeader", "session_token", "credentialValue"]) {
    assert.equal(sanitizeDiagnostic({...diagnosticFixture, [field]: "secret-value"}), null, `${field} must not be retained`);
  }
});

test("Roku development identity remains usable while protected identity fails closed", () => {
  const development = resolveRokuReleaseIdentity({PORTICO_ENVIRONMENT: "development"});
  assert.equal(development.protected, false);
  assert.equal(development.status, "development-sideload");
  assert.equal(development.publisherId, null);
  assert.equal(development.channelId, null);
  assert.equal(development.buildNumber, "0");
  assert.throws(() => resolveRokuReleaseIdentity({PORTICO_ENVIRONMENT: "production"}), /required for protected Roku packaging/);

  const protectedEnvironment = {
    PORTICO_ENVIRONMENT: "staging",
    PORTICO_VERSION: "1.2.3",
    PORTICO_BUILD_NUMBER: "8",
    PORTICO_BUILD_CHANNEL: "staging",
    PORTICO_BUILD_COMMIT: "a".repeat(40),
    PORTICO_ROKU_PREVIOUS_BUILD_NUMBER: "7",
    PORTICO_ROKU_PUBLISHER_ID: "publisher-1",
    PORTICO_ROKU_CHANNEL_ID: "channel-1",
    PORTICO_ROKU_SIGNING_IDENTITY: "roku-publisher-key-1",
    PORTICO_ROKU_PRIVACY_URL: "https://getportico.tv/privacy",
    PORTICO_ROKU_STORE_COUNTRIES: "CA,US",
    PORTICO_ROKU_SEARCH_FEED_URL: "https://getportico.tv/roku/search",
    PORTICO_ROKU_DEEP_LINK_BASE_URL: "https://getportico.tv/roku"
  };
  const identity = resolveRokuReleaseIdentity(protectedEnvironment);
  assert.equal(identity.protected, true);
  assert.equal(identity.status, "protected-inputs-validated");
  assert.deepEqual(identity.metadata.supportedCountries, ["CA", "US"]);
  assert.equal(releaseIdentityDocument(identity).evidence, "source-package-input-validation-only");
  assert.throws(() => resolveRokuReleaseIdentity({...protectedEnvironment, PORTICO_ROKU_CHANNEL_ID: "EXPLICIT_PLACEHOLDER"}), /required for protected Roku packaging/);
  assert.throws(() => resolveRokuReleaseIdentity({...protectedEnvironment, PORTICO_BUILD_NUMBER: "7"}), /must increase strictly/);

  const source = readFileSync(join(root, "channel/manifest"), "utf8");
  const rendered = renderManifest(source, identity);
  assert.match(rendered, /^major_version=1$/m);
  assert.match(rendered, /^minor_version=2$/m);
  assert.match(rendered, /^build_version=8$/m);
  assert.equal(sourceManifestVersion().version, "0.1.0");
});
