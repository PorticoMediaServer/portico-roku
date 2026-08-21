import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, join, resolve} from "node:path";
import {fileURLToPath} from "node:url";

export const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
export const PARITY_SOURCE_DIRECTORY = join(REPOSITORY_ROOT, "scripts/parity");
export const PARITY_CONTRACT_FILES = Object.freeze([
  "tvos-roku-acceptance-matrix.v1.json",
  "parity-exceptions.v1.json",
  "remote-accessibility.v1.json",
  "error-recovery.v1.json",
  "roku-hardware-instrumentation.v1.json",
  "roku-diagnostics.v1.json",
  "tv-interaction-outcomes.v1.json"
]);

export function stableJson(value) {
  const stable = (input) => {
    if (Array.isArray(input)) return input.map(stable);
    if (input && typeof input === "object") return Object.fromEntries(Object.keys(input).sort().map((key) => [key, stable(input[key])]));
    return input;
  };
  return `${JSON.stringify(stable(value), null, 2)}\n`;
}

export function readParityContracts(directory = PARITY_SOURCE_DIRECTORY) {
  return Object.fromEntries(PARITY_CONTRACT_FILES.map((name) => [name, JSON.parse(readFileSync(join(directory, name), "utf8"))]));
}

function record(value, label) {
  assert.ok(value && typeof value === "object" && !Array.isArray(value), `${label} must be an object`);
  return value;
}

function exactKeys(value, expected, label) {
  assert.deepEqual(Object.keys(record(value, label)).sort(), [...expected].sort(), `${label} keys drifted`);
}

function nonEmpty(value, label) {
  assert.equal(typeof value, "string", `${label} must be a string`);
  assert.ok(value.trim(), `${label} must not be empty`);
}

function noSecrets(value, label) {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  assert.doesNotMatch(text, /-----BEGIN|Bearer\s+|access[_-]?token|refresh[_-]?token|media[_-]?grant|password\s*[:=]|private[_-]?key/i, `${label} contains credential material`);
}

function validateAcceptance(matrix) {
  exactKeys(matrix, ["kind", "version", "program", "status", "identityKeys", "authority", "platforms", "cases", "pendingRuntimeCases"], "acceptance matrix");
  assert.equal(matrix.kind, "portico.tvos-roku-acceptance-matrix");
  assert.equal(matrix.version, 1);
  assert.equal(matrix.program, "P08");
  assert.equal(matrix.status, "source-only");
  assert.deepEqual(matrix.identityKeys, ["serverBuild", "hostedBuild", "accountFixture", "profileFixture", "mediaItem", "clientArtifactSha256", "deviceModel", "osVersion"]);
  exactKeys(matrix.authority, ["serverBuild", "hostedBuild", "accountFixture", "profileFixture", "mediaCorpus", "faultCorpus", "artifactDigestPolicy", "devicePolicy"], "acceptance authority");
  for (const key of ["serverBuild", "hostedBuild"]) {
    exactKeys(matrix.authority[key], ["value", "status"], `acceptance authority ${key}`);
    assert.equal(matrix.authority[key].status, "pending-runtime");
  }
  assert.deepEqual(matrix.platforms.map((item) => item.id), ["tvos", "roku"]);
  for (const platform of matrix.platforms) {
    exactKeys(platform, ["id", "family", "formFactor", "playerAuthority", "runtimeStatus", "artifactSha256", "deviceModel", "osVersion"], `acceptance platform ${platform.id}`);
    assert.equal(platform.runtimeStatus, "pending-runtime");
    assert.equal(platform.artifactSha256, null);
    noSecrets(platform, `acceptance platform ${platform.id}`);
  }
  const expectedCases = ["auth-viewer-publication", "browse-route-recovery", "direct-playback-first-frame", "hls-live-dvr-seek", "resume-track-selection-completion", "bounded-error-retry-recovery", "remote-back-focus-restoration", "accessibility-state-announcements", "capability-exception-projection", "deep-link-version-fallback"];
  assert.deepEqual(matrix.cases.map((item) => item.id), expectedCases);
  const identityKeys = new Set(matrix.identityKeys);
  for (const item of matrix.cases) {
    exactKeys(item, ["id", "surface", "key", "platforms", "expectedEvents", "status", "evidence", "sourceRefs", "exceptionIds"], `acceptance case ${item.id}`);
    exactKeys(item.key, matrix.identityKeys, `acceptance case ${item.id} key`);
    assert.ok(item.platforms.length === 2 && item.platforms.includes("tvos") && item.platforms.includes("roku"));
    assert.equal(item.status, "pending-runtime");
    assert.ok(Array.isArray(item.expectedEvents) && item.expectedEvents.length > 0);
    assert.ok(Array.isArray(item.sourceRefs) && item.sourceRefs.length > 0);
    assert.ok(item.exceptionIds.every((id) => typeof id === "string"));
    for (const key of identityKeys) noSecrets(item.key[key], `acceptance case ${item.id} key ${key}`);
    noSecrets(item, `acceptance case ${item.id}`);
  }
  exactKeys(matrix.pendingRuntimeCases[0], ["id", "status", "requires"], "acceptance pending case");
  assert.ok(matrix.pendingRuntimeCases.length >= 4);
  for (const item of matrix.pendingRuntimeCases) {
    assert.equal(item.status, "awaiting-runtime");
    assert.ok(Array.isArray(item.requires) && item.requires.length > 0);
  }
}

function validateExceptions(registry) {
  exactKeys(registry, ["kind", "version", "baseline", "consumer", "status", "entries"], "parity registry");
  assert.equal(registry.kind, "portico.parity-exception-registry");
  assert.equal(registry.version, 1);
  assert.equal(registry.status, "source-contract");
  assert.ok(registry.entries.length >= 8);
  const ids = new Set();
  const classifications = new Set(["platform_limitation", "product_decision", "temporary_missing", "accidental_inconsistency"]);
  for (const entry of registry.entries) {
    exactKeys(entry, ["id", "feature", "tvosBehavior", "rokuBehavior", "classification", "uiBehavior", "serverCapability", "reason", "followUp"], `parity entry ${entry.id}`);
    assert.ok(!ids.has(entry.id), `parity entry ${entry.id} repeats`);
    ids.add(entry.id);
    assert.ok(classifications.has(entry.classification), `parity entry ${entry.id} classification is unknown`);
    for (const key of ["feature", "tvosBehavior", "rokuBehavior", "uiBehavior", "serverCapability", "reason", "followUp"]) nonEmpty(entry[key], `parity entry ${entry.id}.${key}`);
    noSecrets(entry, `parity entry ${entry.id}`);
  }
}

function validateRemote(contract) {
  exactKeys(contract, ["kind", "version", "status", "actions", "mappings", "backHierarchy", "chromePolicy", "focus", "accessibility"], "remote contract");
  assert.equal(contract.kind, "portico.semantic-remote-accessibility-contract");
  assert.equal(contract.version, 1);
  assert.deepEqual(contract.actions, ["move", "select", "back", "play-pause", "seek", "context-menu", "info", "dismiss"]);
  for (const platform of ["tvos", "roku"]) {
    record(contract.mappings[platform], `remote mapping ${platform}`);
    for (const action of Object.values(contract.mappings[platform])) assert.ok(contract.actions.includes(action), `remote mapping ${platform} contains unknown action ${action}`);
  }
  assert.deepEqual(contract.backHierarchy, ["close-top-utility-overlay", "close-modal-or-panel", "exit-player-to-previous-route", "navigate-to-previous-route", "remain-at-root"]);
  assert.equal(contract.chromePolicy, "back-never-toggles-chrome-forever");
  assert.deepEqual(contract.accessibility.requiredStates, ["label", "selected", "disabled", "loading", "error"]);
  noSecrets(contract, "remote contract");
}

function validateRecovery(contract) {
  exactKeys(contract, ["kind", "version", "status", "entries", "retryPolicy"], "error recovery contract");
  assert.equal(contract.kind, "portico.shared-error-recovery-contract");
  assert.equal(contract.version, 1);
  const expected = new Set(["authentication-required", "forbidden", "conflict", "throttled", "server-error", "transport-timeout", "malformed-response", "native-playback-error", "unknown-required-action"]);
  assert.deepEqual(new Set(contract.entries.map((entry) => entry.id)), expected);
  for (const entry of contract.entries) {
    exactKeys(entry, ["id", "input", "classification", "retryable", "maxAttempts", "action", "terminalAction"], `recovery entry ${entry.id}`);
    assert.ok(Number.isInteger(entry.maxAttempts) && entry.maxAttempts >= 0 && entry.maxAttempts <= 2);
    if (!entry.retryable) assert.equal(entry.maxAttempts, 0);
    noSecrets(entry, `recovery entry ${entry.id}`);
  }
  exactKeys(contract.retryPolicy, ["maxRetryAfterSeconds", "backoffSeconds", "neverRetryMethods", "unknownOptionalCapability", "unknownRequiredSemantic"], "retry policy");
  assert.equal(contract.retryPolicy.maxRetryAfterSeconds, 86400);
  assert.deepEqual(contract.retryPolicy.backoffSeconds, [1, 3]);
  assert.equal(contract.retryPolicy.unknownOptionalCapability, "ignore-and-preserve");
  assert.equal(contract.retryPolicy.unknownRequiredSemantic, "reject-actionably");
}

function validateHardware(contract) {
  exactKeys(contract, ["kind", "version", "status", "minimumRokuOs", "advertisedResolutionClasses", "resolutionAdvertisement", "deviceClasses", "scaling", "measurements", "budgets", "evidence"], "hardware contract");
  assert.equal(contract.kind, "portico.roku-hardware-instrumentation-contract");
  assert.equal(contract.version, 1);
  assert.deepEqual(contract.advertisedResolutionClasses, ["fhd"]);
  exactKeys(contract.resolutionAdvertisement, ["advertisedClasses", "pendingEvidenceClasses", "policy", "requiresRuntimeEvidence"], "hardware resolution advertisement");
  assert.deepEqual(contract.resolutionAdvertisement.advertisedClasses, ["fhd"]);
  assert.deepEqual(contract.resolutionAdvertisement.pendingEvidenceClasses, ["hd"]);
  assert.equal(contract.resolutionAdvertisement.policy, "fail-closed");
  assert.equal(contract.resolutionAdvertisement.requiresRuntimeEvidence, true);
  assert.deepEqual(contract.deviceClasses.map((item) => item.id), ["low-power-hd", "mainstream-fhd", "current-high-end-fhd"]);
  assert.equal(contract.scaling.hdStatus, "source-contract-pending-runtime");
  assert.deepEqual(contract.measurements.map((item) => item.id), ["launch-time", "navigation-latency", "scene-node-count-proxy", "texture-bytes-proxy", "memory-warning-count", "playback-duration", "network-restart-recovery", "ten-hour-soak"]);
  assert.equal(contract.evidence.sourceOnlyStatus, "does-not-claim-hardware-execution");
  noSecrets(contract, "hardware contract");
}

function validateDiagnostics(contract) {
  exactKeys(contract, ["kind", "version", "status", "ring", "allowedFields", "privateFields", "eventKinds", "redaction"], "diagnostics contract");
  assert.equal(contract.kind, "portico.roku-diagnostics-contract");
  assert.equal(contract.version, 1);
  assert.ok(contract.ring.maxEvents > 0 && contract.ring.maxExportBytes <= 16384);
  assert.ok(contract.allowedFields.includes("requestId") && contract.allowedFields.includes("viewerGeneration"));
  assert.ok(contract.privateFields.includes("accessToken") && contract.privateFields.includes("mediaId"));
  assert.equal(contract.redaction.unknownFields, "drop");
  assert.equal(contract.redaction.rawMessages, "drop");
  assert.ok(contract.allowedFields.every((field) => !contract.privateFields.includes(field)));
  assert.ok(!contract.allowedFields.some((field) => contract.privateFields.includes(field)), "diagnostics contract overlaps public and private fields");
}

function validateTVInteractionOutcomes(contract) {
  exactKeys(contract, ["kind", "version", "status", "vocabulary", "cases", "auditTrace"], "TV interaction outcomes");
  assert.equal(contract.kind, "portico.tv-interaction-outcomes");
  assert.equal(contract.version, 1);
  assert.equal(contract.status, "source-contract");
  exactKeys(contract.vocabulary, ["current", "focused", "selected"], "TV interaction vocabulary");
  const requiredCases = new Set([
    "destination-primary-replaces-history", "back-history-before-root-reveal", "back-root-reveal-then-system",
    "back-dpad-rail-restores-invoker", "activation-held-select-coalesces", "activation-stale-completion-cancelled",
    "focus-content-to-rail-boundary", "focus-removed-item-falls-back-semantically", "focus-reorder-preserves-semantic-id",
    "focus-modal-traps-and-restores-invoker", "player-five-transport-to-utilities",
    "player-back-unwinds-panel-before-exit", "player-audio-back-returns-to-browsing"
  ]);
  assert.deepEqual(new Set(contract.cases.map((item) => item.id)), requiredCases);
  for (const item of contract.cases) {
    exactKeys(item, ["id", "category", "initial", "events", "expected"], `TV interaction case ${item.id}`);
    assert.ok(["navigation", "back", "activation", "focus", "player"].includes(item.category));
    assert.ok(Array.isArray(item.events) && item.events.length > 0);
    noSecrets(item, `TV interaction case ${item.id}`);
  }
  assert.deepEqual(contract.auditTrace.map((item) => item.issue), ["RK-31", "RK-33", "RK-34", "RK-35", "RK-36", "RK-37", "RK-38", "RK-39", "RK-40"]);
  for (const item of contract.auditTrace) {
    exactKeys(item, ["issue", "outcome"], `TV audit trace ${item.issue}`);
    nonEmpty(item.outcome, `TV audit trace ${item.issue}.outcome`);
  }
  const player = contract.cases.find((item) => item.id === "player-five-transport-to-utilities");
  assert.deepEqual(player.expected.transportOrder, ["previous", "seek-back", "play-pause", "seek-forward", "next"]);
  assert.deepEqual(player.expected.utilityOrder, ["volume", "subtitles", "quality", "speed", "sleep", "queue"]);
  assert.deepEqual(player.initial.capabilities, player.expected.utilityOrder);
  assert.equal(player.expected.focused, "player.utility.volume");
  noSecrets(contract, "TV interaction outcomes");
}

export function validateParityContracts(contracts) {
  validateAcceptance(contracts["tvos-roku-acceptance-matrix.v1.json"]);
  validateExceptions(contracts["parity-exceptions.v1.json"]);
  validateRemote(contracts["remote-accessibility.v1.json"]);
  validateRecovery(contracts["error-recovery.v1.json"]);
  validateHardware(contracts["roku-hardware-instrumentation.v1.json"]);
  validateDiagnostics(contracts["roku-diagnostics.v1.json"]);
  validateTVInteractionOutcomes(contracts["tv-interaction-outcomes.v1.json"]);
  return contracts;
}

export function validateParityFiles(directory = PARITY_SOURCE_DIRECTORY) {
  return validateParityContracts(readParityContracts(directory));
}

export function validateTVArchitectureDocs() {
  const docs = {
    product: readFileSync(join(REPOSITORY_ROOT, "Project Architecture", "03 API and Cross-Platform Product Contract.md"), "utf8"),
    design: readFileSync(join(REPOSITORY_ROOT, "Project Architecture", "07 Brand and UI Design System.md"), "utf8"),
    quality: readFileSync(join(REPOSITORY_ROOT, "Project Architecture", "09 Quality and Release Gates.md"), "utf8"),
    player: readFileSync(join(REPOSITORY_ROOT, "Project Architecture", "12 Apple Playback Cast Mobile Chrome and Roku Parity.md"), "utf8"),
    navigation: readFileSync(join(REPOSITORY_ROOT, "Project Architecture", "15 React Native Navigation Architecture.md"), "utf8")
  };
  assert.match(docs.product, /current[\s\S]*focused[\s\S]*selected/);
  assert.match(docs.design, /Television surface taxonomy[\s\S]*Account Hub[\s\S]*Personal Settings/);
  assert.match(docs.design, /Icon contract and governance[\s\S]*unknown semantic ID[\s\S]*unavailable in production/);
  assert.match(docs.player, /does not show Close, Collapse, or Fullscreen[\s\S]*Previous item, Seek Back, Play\/Pause, Seek Forward, and Next item/);
  assert.match(docs.player, /Volume, Subtitles, Quality, Speed, Sleep, and Queue/);
  assert.match(docs.player, /On iOS[\s\S]*On tvOS[\s\S]*On Roku/);
  assert.match(docs.navigation, /requested[\s\S]*committing[\s\S]*committed[\s\S]*cancelled/);
  assert.match(docs.navigation, /expanded rail before route history[\s\S]*Virtual focus containers/);
  for (const issue of ["RK-31", "RK-33", "RK-34", "RK-35", "RK-36", "RK-37", "RK-38", "RK-39", "RK-40"]) assert.match(docs.quality, new RegExp(issue));
  return docs;
}
