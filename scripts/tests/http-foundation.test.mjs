import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const fixtures = JSON.parse(readFileSync(resolve(root, 'tests/http-foundation-cases.json'), 'utf8'));
const constantsSource = readFileSync(resolve(root, 'channel/source/lib/PorticoHttpConstants.brs'), 'utf8');
const helpersSource = readFileSync(resolve(root, 'channel/source/lib/PorticoHttpHelpers.brs'), 'utf8');
const taskSource = readFileSync(resolve(root, 'channel/components/PorticoHttpTask.brs'), 'utf8');
const taskXml = readFileSync(resolve(root, 'channel/components/PorticoHttpTask.xml'), 'utf8');

assert.match(taskXml, /uri="pkg:\/components\/PorticoHttpTask\.brs"/, 'The generic HTTP Task must stay in the top-level components directory for real Roku registration');

function classification(classification, retryable, recommendedAction) {
  return {
    classification,
    retryable,
    recommendedAction,
    authAction: recommendedAction === 'refresh_once' ? 'refresh_once' : 'none'
  };
}

function classifyStatus(status) {
  if (status >= 200 && status <= 299) return classification('success', false, 'none');
  if (status === 400) return classification('bad_request', false, 'none');
  if (status === 401) return classification('authentication_required', false, 'refresh_once');
  if (status === 403) return classification('forbidden', false, 'none');
  if (status === 409) return classification('conflict', false, 'reload_authoritative_state');
  if (status === 422) return classification('unprocessable', false, 'remove_unsupported_option');
  if (status === 429) return classification('throttled', true, 'honor_retry_after');
  if (status >= 500 && status <= 599) return classification('server_error', true, 'retry_with_budget');
  if (status >= 400 && status <= 499) return classification('client_error', false, 'none');
  if (status >= 300 && status <= 399) return classification('redirect_error', false, 'none');
  return classification('protocol_error', false, 'none');
}

function classifyFailure(kind) {
  if (kind === 'timeout') return classification('timeout', true, 'retry_with_budget');
  if (kind === 'cancelled') return classification('cancelled', false, 'none');
  if (kind === 'transport') return classification('transport_error', true, 'retry_with_budget');
  if (kind === 'parse') return classification('parse_error', false, 'none');
  if (kind === 'request') return classification('request_error', false, 'none');
  return classification('unknown_error', false, 'none');
}

function redactUrl(value) {
  const withoutQuery = value.split(/[?#]/, 1)[0];
  try {
    const url = new URL(withoutQuery);
    url.username = '';
    url.password = '';
    return url.toString().replace(/\/$/, withoutQuery.endsWith('/') ? '/' : '');
  } catch {
    return withoutQuery;
  }
}

const sensitiveHeaders = new Set([
  'authorization',
  'cookie',
  'proxy-authorization',
  'set-cookie',
  'x-api-key',
  'x-portico-csrf',
  'x-portico-device-code'
]);

function redactHeaders(headers) {
  return Object.fromEntries(Object.entries(headers).map(([name, value]) => [
    name,
    sensitiveHeaders.has(name.toLowerCase()) ? '[REDACTED]' : String(value).trim().slice(0, 512)
  ]));
}

const sensitiveBodyKeys = new Set([
  'authorization', 'accesstoken', 'access_token', 'refreshtoken', 'refresh_token',
  'devicecode', 'device_code', 'clientsecret', 'client_secret', 'apikey', 'api_key',
  'password', 'credential', 'credentials'
]);

function publicRequestContainsSensitiveMaterial(headers, body) {
  if (Object.keys(headers).some(name => sensitiveHeaders.has(name.toLowerCase()))) return true;
  let parsed;
  try { parsed = JSON.parse(body || '{}'); } catch { return false; }
  return parsed && typeof parsed === 'object' && !Array.isArray(parsed) &&
    Object.keys(parsed).some(key => sensitiveBodyKeys.has(key.toLowerCase()));
}

function isLanHost(host) {
  const lower = host.toLowerCase();
  if (lower === 'localhost' || lower === '::1' || lower.endsWith('.local')) return true;
  if (lower.startsWith('fc') || lower.startsWith('fd') || lower.startsWith('fe80')) return true;
  const parts = lower.split('.');
  if (parts.length !== 4 || parts.some(part => !/^(0|[1-9]\d{0,2})$/.test(part) || Number(part) > 255)) return false;
  const [first, second] = parts.map(Number);
  return first === 10 || first === 127 || (first === 169 && second === 254) || (first === 172 && second >= 16 && second <= 31) || (first === 192 && second === 168);
}

function urlAllowed(value, allowInsecureLan) {
  const schemeMarker = value.indexOf('://');
  if (schemeMarker < 0 || value.slice(schemeMarker + 3).startsWith('/')) return false;
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (!url.hostname || url.username || url.password) return false;
  if (url.protocol === 'https:') return true;
  return url.protocol === 'http:' && allowInsecureLan && isLanHost(url.hostname);
}

function retryAfterSeconds(value) {
  const normalized = String(value).trim();
  if (!/^\d+$/.test(normalized)) return null;
  return Math.min(Number(normalized), 86_400);
}

for (const fixture of fixtures.statusCases) {
  assert.deepEqual(classifyStatus(fixture.status), {
    classification: fixture.classification,
    retryable: fixture.retryable,
    recommendedAction: fixture.recommendedAction,
    authAction: fixture.authAction
  }, `HTTP ${fixture.status} classification drifted`);
  assert.match(constantsSource, new RegExp(`"${fixture.classification}"`), `BrightScript is missing ${fixture.classification}`);
}

for (const fixture of fixtures.failureCases) {
  assert.deepEqual(classifyFailure(fixture.kind), {
    classification: fixture.classification,
    retryable: fixture.retryable,
    recommendedAction: fixture.recommendedAction,
    authAction: fixture.authAction
  }, `${fixture.kind} failure classification drifted`);
  assert.match(constantsSource, new RegExp(`"${fixture.classification}"`), `BrightScript is missing ${fixture.classification}`);
}

for (const fixture of fixtures.redactedUrlCases) {
  assert.equal(redactUrl(fixture.input), fixture.expected, 'URL redaction retained credentials, query, or fragment data');
}
for (const fixture of fixtures.urlPolicyCases) {
  assert.equal(urlAllowed(fixture.url, fixture.allowInsecureLan), fixture.allowed, `URL policy drifted for ${fixture.url}`);
}
for (const fixture of fixtures.retryAfterCases) {
  assert.equal(retryAfterSeconds(fixture.value), fixture.seconds, `Retry-After policy drifted for ${JSON.stringify(fixture.value)}`);
}
assert.deepEqual(redactHeaders(fixtures.headerCase.input), fixtures.headerCase.expected, 'Header redaction contract drifted');
for (const headerName of ['Authorization', 'Cookie', 'Proxy-Authorization', 'X-API-Key', 'X-Portico-CSRF', 'X-Portico-Device-Code']) {
  assert.equal(publicRequestContainsSensitiveMaterial({[headerName]: 'opaque'}, ''), true, `${headerName} escaped the public Task boundary`);
}
for (const bodyKey of ['accessToken', 'refreshToken', 'deviceCode', 'clientSecret', 'apiKey', 'password', 'credentials']) {
  assert.equal(publicRequestContainsSensitiveMaterial({}, JSON.stringify({[bodyKey]: 'opaque'})), true, `${bodyKey} escaped the public Task boundary`);
}
assert.equal(publicRequestContainsSensitiveMaterial({'Accept': 'application/json'}, JSON.stringify({query: 'Fargo'})), false);

assert.match(taskXml, /extends="Task"/, 'HTTP transport must remain a SceneGraph Task');
assert.match(taskXml, /PorticoHttpConstants\.brs[\s\S]*PorticoHttpHelpers\.brs[\s\S]*PorticoHttpTask\.brs/, 'Task scripts must load helpers before execution');
assert.match(taskSource, /CreateObject\("roUrlTransfer"\)/, 'HTTP task must use roUrlTransfer');
assert.doesNotMatch(constantsSource + helpersSource, /roUrlTransfer/i, 'roUrlTransfer escaped the Task boundary');
assert.match(taskSource, /common:\/certs\/ca-bundle\.crt/, 'HTTPS must use Roku common CA roots');
assert.match(taskSource, /EnablePeerVerification\(true\)/, 'TLS peer verification must stay enabled');
assert.match(taskSource, /EnableHostVerification\(true\)/, 'TLS host verification must stay enabled');
assert.match(taskSource, /RetainBodyOnError\(true\)/, 'Problem Details bodies must be retained on HTTP errors');
assert.match(taskSource, /AsyncCancel\(\)/, 'Timeout and cancellation must abort the transfer');
assert.match(taskSource, /request\.timeoutMs/, 'The Task must enforce the normalized bounded timeout');
assert.match(helpersSource, /minimumTimeoutMs[\s\S]*maximumTimeoutMs/, 'Timeout clamping is missing');
assert.match(helpersSource, /headers\["X-Request-ID"\] = requestId/, 'Every request must receive a newly generated request ID');
assert.match(helpersSource, /PorticoHttpNormalizeProblem/, 'Problem Details normalization is missing');
assert.match(helpersSource, /PorticoHttpRedactHeaders/, 'Header redaction helper is missing');
assert.match(helpersSource, /PorticoHttpValidateRequestWithPolicy\(request, false\)/, 'Public HTTP validation must reject secret material');
assert.match(helpersSource, /PorticoHttpValidateRequestWithPolicy\(request, true\)/, 'Only credential-owning Tasks may request private validation');
assert.match(helpersSource, /PorticoHttpHeaderIsSensitive\(LCase\(headerName\)\)/, 'Public request headers must reject credential names');
assert.match(helpersSource, /PorticoHttpBodyContainsCredential\(request\.body\)/, 'Public request bodies must reject credential keys');
assert.match(taskSource, /PorticoHttpValidateRequest\(request\)/, 'Generic HTTP Task must use the public no-secrets validator');
assert.match(helpersSource, /PorticoHttpUrlContainsUserInfo/, 'Credential-bearing URL rejection is missing');
assert.match(helpersSource, /allowInsecureLan[\s\S]*PorticoHttpIsLanHost/, 'Insecure HTTP must stay constrained to explicit LAN policy');
assert.match(taskSource, /url: PorticoHttpRedactUrl\(request\.url\)/, 'Results must not expose query credentials or URL user-info');
assert.doesNotMatch(taskSource, /GetFailureReason\(/, 'Raw transport failure text can leak endpoint or credential details');
assert.doesNotMatch(taskSource, /\bprint\b/i, 'The HTTP Task must not log request or response material');
assert.doesNotMatch(taskSource, /body:\s*request\.body|headers:\s*request\.headers/, 'Results must not echo request secrets');

const packagedSource = constantsSource + helpersSource + taskSource + taskXml;
for (const secret of ['access-secret', 'cookie-secret', 'csrf-secret', 'api-secret', 'grant-secret', 'server-secret', 'account-secret', 'television-password']) {
  assert.doesNotMatch(packagedSource, new RegExp(secret), `Fixture secret ${secret} leaked into channel source`);
}

console.log(`Verified ${fixtures.statusCases.length} HTTP statuses, ${fixtures.failureCases.length} task failures, ${fixtures.urlPolicyCases.length} URL policies, and redaction/TLS invariants.`);
