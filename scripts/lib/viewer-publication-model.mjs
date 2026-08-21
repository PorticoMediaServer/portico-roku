const IDENTIFIER = /^[^\u0000-\u001f\u007f\s]{1,128}$/u;

export const VIEWER_PUBLICATION_CONTRACT_REVISION = 1;
export const NAVIGATION_CONTRACT_REVISION = 'v1';

function text(value) {
  return typeof value === 'string' && IDENTIFIER.test(value) ? value : '';
}

export function normalizeScope(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const authority = value.authority === 'hosted' || value.authority === 'local' ? value.authority : '';
  const accountId = text(value.accountId);
  const serverId = text(value.serverId);
  const profileId = text(value.profileId);
  const authorizationRevision = text(value.authorizationRevision);
  const viewerGeneration = Number.isInteger(value.viewerGeneration) && value.viewerGeneration > 0 ? value.viewerGeneration : 0;
  if (!authority || !accountId || !serverId || !profileId || !authorizationRevision || viewerGeneration < 1) return undefined;
  return {version: 1, authority, accountId, serverId, profileId, authorizationRevision, viewerGeneration};
}

export function viewerPublicationGate(state, expected = {}) {
  if (!state || typeof state !== 'object' || state.registryCorrupt === true) return {kind: 'fail-closed', gate: 'registry'};
  const accountStatus = state.accountStatus;
  if (!['signed-in', 'refreshing', 'hosted-unavailable'].includes(accountStatus)) return {kind: 'defer', gate: 'account'};
  if (state.credentialsDurable !== true) return {kind: 'defer', gate: 'account'};
  if (!text(state.selectedServerId) || state.serverStatus !== 'online') return {kind: 'defer', gate: 'server'};
  if (!text(state.routeGeneration)) return {kind: 'defer', gate: 'server'};
  if (!text(state.selectedProfileId)) return {kind: 'defer', gate: 'profile'};
  if (state.viewerStatus !== 'active' || state.viewerAcceptingWrites !== true) return {kind: 'defer', gate: 'profile'};
  const scope = normalizeScope(state.viewerScope);
  if (!scope || scope.serverId !== state.selectedServerId || scope.profileId !== state.selectedProfileId) return {kind: 'defer', gate: 'profile'};
  if (text(state.authorizationRevision) && state.authorizationRevision !== scope.authorizationRevision) return {kind: 'defer', gate: 'profile'};
  if (expected.serverId && expected.serverId !== scope.serverId) return {kind: 'defer', gate: 'server'};
  if (expected.profileId && expected.profileId !== scope.profileId) return {kind: 'defer', gate: 'profile'};
  if (expected.authorizationRevision && expected.authorizationRevision !== scope.authorizationRevision) return {kind: 'defer', gate: 'profile'};
  return {kind: 'ready', scope, routeGeneration: state.routeGeneration};
}

export function beginPublication(state, candidate) {
  if (!state || state.transition) return {ok: false, code: 'transition-in-progress', state};
  const current = normalizeScope(state.viewerScope);
  const currentGeneration = Number.isInteger(state.viewerGeneration) ? state.viewerGeneration : (current?.viewerGeneration ?? 0);
  const next = normalizeScope({...candidate, viewerGeneration: currentGeneration + 1});
  if (!next) return {ok: false, code: 'scope-invalid', state};
  return {
    ok: true,
    state: {
      ...state,
      viewerGeneration: next.viewerGeneration,
      viewerScope: undefined,
      viewerStatus: 'transitioning',
      viewerAcceptingWrites: false,
      transition: {candidate: next, previous: current}
    }
  };
}

export function publishPublication(state, credentialScope, profileScope) {
  if (!state?.transition) return {ok: false, code: 'transition-missing', state};
  const candidate = state.transition.candidate;
  const credentials = normalizeScope(credentialScope);
  const profile = normalizeScope(profileScope);
  if (!credentials || !profile || JSON.stringify(credentials) !== JSON.stringify(candidate) || JSON.stringify(profile) !== JSON.stringify(candidate)) {
    return {ok: false, code: 'scope-mismatch', state: {...state, transition: undefined, viewerScope: undefined, viewerStatus: 'unavailable', viewerAcceptingWrites: false}};
  }
  return {ok: true, state: {...state, transition: undefined, viewerScope: candidate, viewerStatus: 'active', viewerAcceptingWrites: true}};
}

export function rollbackPublication(state, reason = 'transition-failed', restorePrevious = true) {
  const previous = normalizeScope(state?.transition?.previous);
  if (!previous || !restorePrevious) return {state: {...state, transition: undefined, viewerScope: undefined, viewerStatus: 'unavailable', viewerAcceptingWrites: false, viewerTransitionReason: reason}, restored: false};
  const restored = {...previous, viewerGeneration: Math.max(state.viewerGeneration ?? 0, previous.viewerGeneration) + 1};
  return {state: {...state, transition: undefined, viewerScope: restored, viewerGeneration: restored.viewerGeneration, viewerStatus: 'active', viewerAcceptingWrites: true, viewerTransitionReason: reason}, restored: true};
}

export function deferDeepLink(state, request, nowSeconds = 0) {
  if (!state || state.registryCorrupt === true) return {accepted: false, code: 'registry-corrupt', state};
  if (!request || typeof request !== 'object' || !request.kind) return {accepted: false, code: 'request-invalid', state};
  const intentId = text(request.intentId) || `intent-${(state.intentSequence ?? 0) + 1}`;
  const pending = {
    ...request,
    intentId,
    contractRevision: NAVIGATION_CONTRACT_REVISION,
    createdAt: nowSeconds,
    expiresAt: nowSeconds + 600,
    delivery: {intentId, status: 'pending', attempts: 0}
  };
  return {accepted: true, state: {...state, intentSequence: (state.intentSequence ?? 0) + 1, pendingDeepLink: pending}};
}

export function dispatchDeepLink(state, gate) {
  const pending = state?.pendingDeepLink;
  if (!pending) return {dispatched: false, code: 'not-found', state};
  if (pending.delivery?.status === 'in-flight') return {dispatched: false, duplicate: true, deliveryId: pending.intentId, state};
  if (gate?.kind !== 'ready') return {dispatched: false, deferred: true, gate: gate?.gate ?? 'account', state};
  const next = {...pending, delivery: {intentId: pending.intentId, status: 'in-flight', attempts: (pending.delivery?.attempts ?? 0) + 1}};
  return {dispatched: true, deliveryId: pending.intentId, request: pending, state: {...state, pendingDeepLink: next}};
}

export function acknowledgeDeepLink(state, deliveryId, ok = true) {
  const pending = state?.pendingDeepLink;
  if (!pending || pending.intentId !== deliveryId || pending.delivery?.status !== 'in-flight') return {acknowledged: false, duplicate: true, state};
  if (!ok) return {acknowledged: false, state: {...state, pendingDeepLink: {...pending, delivery: {...pending.delivery, status: 'pending'}}}};
  return {acknowledged: true, state: {...state, pendingDeepLink: undefined, consumedDeepLinks: [...(state.consumedDeepLinks ?? []), deliveryId]}};
}
