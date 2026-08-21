import {readParityContracts} from "./parity-contracts.mjs";

const contracts = readParityContracts();
const remoteContract = contracts["remote-accessibility.v1.json"];
const recoveryContract = contracts["error-recovery.v1.json"];
const diagnosticsContract = contracts["roku-diagnostics.v1.json"];

const recoveryByInput = new Map(recoveryContract.entries.map((entry) => [entry.input, entry]));
const recoveryByClassification = new Map(recoveryContract.entries.map((entry) => [entry.classification, entry]));
const allowedDiagnosticFields = new Set(diagnosticsContract.allowedFields);
const normalizeDiagnosticKey = (key) => key.replace(/[^a-z0-9]/gi, "").toLowerCase();
const privateDiagnosticFields = new Set(diagnosticsContract.privateFields.map(normalizeDiagnosticKey));
const secretLikeDiagnosticKey = /(?:access|refresh)?token|password|passcode|pin|secret|grant|credential|authorization|cookie|apikey|privatekey|rawerror|mediaid|serverorigin|url|headers?|filesystempath/i;

export function mapRemoteInput(platform, input) {
  const mapping = remoteContract.mappings[platform];
  if (!mapping || typeof input !== "string") return null;
  return mapping[input] ?? null;
}

export function reduceBack(state = {}) {
  if ((state.utilityOverlayCount ?? 0) > 0) return {action: "close-top-utility-overlay", finalEvent: null};
  if ((state.modalOrPanelCount ?? 0) > 0) return {action: "close-modal-or-panel", finalEvent: null};
  if (state.playerActive === true) return {action: "exit-player-to-previous-route", finalEvent: "stop"};
  if (state.routeDepth > 0) return {action: "navigate-to-previous-route", finalEvent: null};
  return {action: "remain-at-root", finalEvent: null};
}

export function classifyFailure(input) {
  return recoveryByInput.get(input) ?? null;
}

export function planRecovery(input, attempt = 0) {
  const entry = classifyFailure(input);
  if (!entry) return {classification: "unknown_failure", action: "terminal", terminal: true, retryAttempt: 0};
  if (!entry.retryable || attempt >= entry.maxAttempts) {
    return {classification: entry.classification, action: entry.terminalAction, terminal: true, retryAttempt: Math.max(0, attempt)};
  }
  return {classification: entry.classification, action: entry.action, terminal: false, retryAttempt: attempt + 1};
}

export function planRecoveryByClassification(classification, attempt = 0) {
  const entry = recoveryByClassification.get(classification);
  return entry ? planRecovery(entry.input, attempt) : planRecovery("unknown-failure", attempt);
}

function safeValue(value, maximum = 160) {
  if (typeof value !== "string" && typeof value !== "number") return null;
  const normalized = String(value).trim();
  if (!normalized || normalized.length > maximum || /-----BEGIN|Bearer\s+|access[_-]?token|refresh[_-]?token|media[_-]?grant|password|pin|secret|private[_-]?key|https?:\/\//i.test(normalized)) return null;
  return normalized;
}

export function sanitizeDiagnostic(event = {}) {
  if (!event || typeof event !== "object" || Array.isArray(event)) return null;
  const sanitized = {};
  for (const [key, value] of Object.entries(event)) {
    const normalizedKey = normalizeDiagnosticKey(key);
    if (privateDiagnosticFields.has(normalizedKey) || secretLikeDiagnosticKey.test(normalizedKey)) return null;
    if (!allowedDiagnosticFields.has(key)) continue;
    const safe = safeValue(value, key === "eventKind" || key === "taskKind" ? 64 : 160);
    if (safe === null) return null;
    sanitized[key] = safe;
  }
  if (!sanitized.eventKind || !sanitized.occurredAt) return null;
  if (Object.keys(sanitized).length > 13) return null;
  return sanitized;
}

export function acceptCapability(name, required, knownCapabilities) {
  if (knownCapabilities?.[name] !== undefined) return knownCapabilities[name];
  return required ? {state: "unsupported", action: "upgrade_client"} : {state: "unknown", action: "ignore_and_preserve"};
}
