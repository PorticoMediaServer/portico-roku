#!/usr/bin/env node
/**
 * Golden fixtures: runs the TypeScript the channel's BrightScript was ported from (packages/i18n,
 * packages/client-core) over a set of inputs and writes the inputs with their real outputs to
 * test/fixtures/golden/. The BrightScript tests replay them, so a port that drifts from the
 * TypeScript fails. The fixtures are committed; `npm test` rewrites them first.
 */
import {mkdirSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {enUS} from '../../portico-server/packages/i18n/src/catalog/en-US.ts';
import {formatMessage, parseMessage} from '../../portico-server/packages/i18n/src/messageformat.ts';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const write = (name, value) => {
  const file = join(app, 'test', 'fixtures', 'golden', name);
  mkdirSync(dirname(file), {recursive: true});
  writeFileSync(file, `${JSON.stringify(value, null, 1)}\n`);
};

// ── Messages: every catalogue message that takes arguments, with several value sets ──────────
{
  const cases = [];
  const kinds = nodes => {
    const out = new Map();
    const walk = list => {
      for (const n of list) {
        if ('name' in n) out.set(n.name, out.get(n.name) === 'plural' ? 'plural' : n.kind === 'select' ? {select: Object.keys(n.options)} : n.kind);
        if (n.kind === 'plural' || n.kind === 'select') Object.values(n.options).forEach(walk);
      }
    };
    walk(nodes);
    return out;
  };
  const numbers = [0, 1, 2, 3, 11, 21, 1234];
  for (const [id, source] of Object.entries(enUS)) {
    if (!source.includes('{') && !source.includes("'")) continue;
    const args = kinds(parseMessage(source));
    // Dates and times follow the machine's zone; the channel formats those itself (core/Format.bs).
    if ([...args.values()].some(k => k === 'date' || k === 'time')) continue;
    const numeric = [...args.values()].some(k => k === 'plural' || k === 'number');
    const selects = [...args.entries()].filter(([, k]) => typeof k === 'object');
    const rounds = numeric ? numbers.length : selects.length ? Math.max(...selects.map(([, k]) => k.select.length)) : 1;
    for (let round = 0; round < rounds; round++) {
      const values = {};
      for (const [name, kind] of args) {
        if (kind === 'plural' || kind === 'number') values[name] = numbers[round % numbers.length];
        else if (typeof kind === 'object') values[name] = kind.select[round % kind.select.length];
        else values[name] = `${name[0].toUpperCase()}${name.slice(1)} ${round + 1}`;
      }
      cases.push({id, source, values, expected: formatMessage(source, values, {locale: 'en-US'})});
    }
  }
  write('messages.json', cases);
}
// ── Ed25519: signatures from Node's own implementation, with the digest the verifier needs ──
{
  const {createHash, createPrivateKey, createPublicKey, sign} = await import('node:crypto');
  const pkcs8 = seed => Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), Buffer.from(seed, 'hex')]);
  // RFC 8032 §7.1 test keys (TEST 1, TEST 2, TEST 3); the public keys are derived here.
  const seeds = [
    ['9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60', ''],
    ['4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb', '72'],
    ['c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7', 'af82'],
  ];
  const cases = [];
  const digest = (signature, publicKey, message) => createHash('sha512').update(Buffer.concat([signature.subarray(0, 32), publicKey, message])).digest('hex');
  seeds.forEach(([seed, messageHex], index) => {
    const key = createPrivateKey({key: pkcs8(seed), format: 'der', type: 'pkcs8'});
    const publicKey = createPublicKey(key).export({format: 'der', type: 'spki'}).subarray(-32);
    const message = Buffer.from(messageHex, 'hex');
    const signature = sign(null, message, key);
    const hex = b => Buffer.from(b).toString('hex');
    if (index === 0) {
      cases.push({name: 'RFC 8032 key 1: the signature verifies', publicKey: hex(publicKey), signature: hex(signature), digest: digest(signature, publicKey, message), valid: true});
      const other = Buffer.from('portico');
      cases.push({name: 'a different message does not verify', publicKey: hex(publicKey), signature: hex(signature), digest: digest(signature, publicKey, other), valid: false});
      const bent = Buffer.from(signature); bent[40] ^= 1;
      cases.push({name: 'a changed signature does not verify', publicKey: hex(publicKey), signature: hex(bent), digest: digest(bent, publicKey, message), valid: false});
    }
    if (index === 1) {
      const proof = Buffer.from(JSON.stringify({kind: 'portico.route-proof', version: '1', baseUrl: 'http://192.168.1.20:32500', nonce: 'n'}));
      const signed = sign(null, proof, key);
      cases.push({name: 'a route proof payload verifies', publicKey: hex(publicKey), signature: hex(signed), digest: digest(signed, publicKey, proof), valid: true});
      const wrongKey = createPublicKey(createPrivateKey({key: pkcs8(seeds[2][0]), format: 'der', type: 'pkcs8'})).export({format: 'der', type: 'spki'}).subarray(-32);
      cases.push({name: 'another server\'s key does not verify it', publicKey: hex(wrongKey), signature: hex(signed), digest: digest(signed, wrongKey, proof), valid: false});
    }
  });
  write('ed25519.json', cases);
}
// ── Timestamps: local-session.ts `currentUTCTimestamp` and `utcOrderKey`, Date.parse ──────────
{
  const {currentUTCTimestamp, utcOrderKey} = await import('../../portico-server/packages/client-core/src/local-session.ts');
  const values = ['2026-10-03T12:00:00Z', '2026-10-03T12:00:00.123Z', '2026-10-03T12:00:00.123456789Z', '2026-10-03t12:00:00z', '2026-10-03T12:00:00+00:00', '1970-01-01T00:00:00Z', '2000-02-29T23:59:59Z', '2100-02-28T00:00:00Z', '2099-12-31T23:59:59.9Z',
    '2026-02-29T00:00:00Z', '2100-02-29T00:00:00Z', '2026-13-01T00:00:00Z', '2026-10-32T00:00:00Z', '2026-10-03T24:00:00Z', '2026-10-03T12:60:00Z', '2026-10-03T12:00:00', '2026-10-03T12:00:00+01:00', '2026-10-03 12:00:00Z', '2026-10-03T12:00:00.1234567890Z', '', 'yesterday'];
  write('time.json', values.map(value => currentUTCTimestamp(value) ? {value, valid: true, seconds: String(Math.floor(Date.parse(value) / 1000)), orderKey: utcOrderKey(value)} : {value, valid: false}));
}
// ── Route identity: route-identity.ts and portico-servers.ts, run with Node's crypto ──────────
{
  const {createHash, createPrivateKey, createPublicKey, sign} = await import('node:crypto');
  const route = await import('../../portico-server/packages/client-core/src/route-identity.ts');
  const {requestPorticoChallenge} = await import('../../portico-server/packages/client-core/src/portico-servers.ts');
  const b64 = bytes => route.routeBase64(new Uint8Array(bytes));
  const hex = bytes => Buffer.from(bytes).toString('hex');
  const digests = [];
  const verdicts = [];
  const sha = (algorithm, bytes) => { const out = createHash(algorithm).update(Buffer.from(bytes)).digest(); digests.push({algorithm, input: hex(bytes), digest: hex(out)}); return new Uint8Array(out); };
  const nonceBytes = new Uint8Array(32).map((_, i) => (i * 7 + 3) & 255);
  const crypto = {
    random: () => nonceBytes,
    sha256: async bytes => sha('sha256', bytes),
    verify: async (key, signature, raw) => {
      const digest = sha('sha512', Buffer.concat([Buffer.from(signature).subarray(0, 32), Buffer.from(key), Buffer.from(raw)]));
      const valid = await route.webRouteCrypto.verify(key, signature, raw);
      verdicts.push({publicKey: hex(key), signature: hex(signature), digest: hex(digest), valid});
      return valid;
    },
  };
  const keyFrom = seed => {
    const privateKey = createPrivateKey({key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), Buffer.from(seed, 'hex')]), format: 'der', type: 'pkcs8'});
    const raw = createPublicKey(privateKey).export({format: 'der', type: 'spki'}).subarray(-32);
    const context = Buffer.concat([Buffer.from('portico.server.identity.v1\0'), raw]);
    return {privateKey, publicKey: b64(raw), fingerprint: b64(sha('sha256', raw)), serverId: 'srv_' + b64(sha('sha256', context))};
  };
  const server = keyFrom('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60');
  const other = keyFrom('4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb');
  const hosted = keyFrom('c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7');
  const pinOf = k => ({serverId: k.serverId, publicKey: k.publicKey, fingerprint: k.fingerprint});
  const signedBy = (key, document, extra = {}) => { const payload = Buffer.from(JSON.stringify(document)); return {payload: b64(payload), signature: b64(sign(null, payload, key.privateKey)), ...extra}; };
  const now = Date.parse('2026-10-03T12:00:00Z');
  const iso = offsetMs => new Date(now + offsetMs).toISOString();
  const nonce = b64(nonceBytes);
  const outcome = async work => { try { return {ok: true, value: await work()}; } catch (e) { return {ok: false, code: e.code ?? 'error'}; } };

  // Addresses.
  const origins = ['http://192.168.1.20:32500', 'http://192.168.1.20:32500/', 'HTTP://192.168.1.20:80', 'https://portico.example.com', 'https://Portico.Example.com:443/', 'https://portico.example.com:8443', 'http://localhost:32500', 'http://nas.local:32500', 'http://10.0.0.5', 'http://172.16.4.4:1', 'http://172.32.0.1', 'http://169.254.10.10',
    'http://portico.example.com', 'http://8.8.8.8:32500', 'https://user@portico.example.com', 'https://portico.example.com/path', 'https://portico.example.com/?q=1', 'https://portico.example.com/#x', 'https://portico.example.com.', 'ftp://portico.example.com', 'portico.example.com', 'https://0x7f.0.0.1', 'https://127.1', 'https://2130706433', 'http://192.168.001.20', 'https://exa mple.com', 'http://[::1]:32500', 'http://[fd12:3456::1]', 'https://[2001:db8::1]', 'http://[2001:db8::1]', 'https://portico.example.com:99999', ''];
  const originCases = origins.map(raw => { try { return {raw, ok: true, origin: route.routeOrigin(raw)}; } catch { return {raw, ok: false}; } });
  const hosts = ['localhost', '::1', '[::1]', 'nas.local', '10.1.2.3', '127.0.0.1', '192.168.0.1', '192.169.0.1', '172.15.0.1', '172.16.0.1', '172.31.255.255', '172.32.0.1', '169.254.0.1', '8.8.8.8', '256.1.1.1', '010.1.1.1', 'fd00::1', 'fc12:1::2', 'fe80::1', 'fec0::1', '2001:db8::1', 'example.com', 'fe80::1%en0'];
  const hostCases = hosts.map(host => ({host, private: route.privateRouteHost(host)}));

  // Pins.
  const pinCases = [];
  for (const [name, args] of [['the server\'s own pin', [server.serverId, server.publicKey, server.fingerprint]], ['without a fingerprint', [server.serverId, server.publicKey, undefined]], ['another server\'s id', [other.serverId, server.publicKey, server.fingerprint]], ['another fingerprint', [server.serverId, server.publicKey, other.fingerprint]], ['a key that is not 32 bytes', [server.serverId, 'AAAA', undefined]], ['a key in the wrong alphabet', [server.serverId, server.publicKey.replace(/.$/, '+'), undefined]]]) {
    const result = await outcome(() => route.serverPin(args[0], args[1], args[2], crypto));
    pinCases.push({name, serverId: args[0], publicKey: args[1], fingerprint: args[2] ?? null, ok: result.ok, code: result.code ?? null});
  }

  // Identity proofs (probeRoute).
  const baseUrl = 'http://192.168.1.20:32500';
  const proof = (overrides = {}, key = server) => ({kind: 'portico.route-proof', version: '1', baseUrl, nonce, serverId: key.serverId, publicKey: key.publicKey, fingerprint: key.fingerprint, issuedAt: iso(-1000), expiresAt: iso(20000), ...overrides});
  const bend = envelope => { const raw = Buffer.from(route.routeBytes(envelope.signature, 64)); raw[5] ^= 4; return {...envelope, signature: b64(raw)}; };
  const proofCases = [];
  const probe = async (name, answer, pin) => {
    const fetcher = async () => new Response(JSON.stringify(answer), {status: 200, headers: {'Content-Type': 'application/json'}});
    const result = await outcome(() => route.probeRoute(baseUrl, pin, {fetcher, crypto, now: () => now}));
    proofCases.push({name, answer, baseUrl, nonce, pin: pin ?? null, now: Math.floor(now / 1000), ok: result.ok, code: result.code ?? null, serverId: result.value?.serverId ?? null});
  };
  await probe('a first contact is pinned', signedBy(server, proof()));
  await probe('the pinned server proves itself again', signedBy(server, proof()), pinOf(server));
  await probe('a different server at a pinned address', signedBy(other, proof({}, other)), pinOf(server));
  await probe('another nonce', signedBy(server, proof({nonce: b64(new Uint8Array(32))})));
  await probe('another address', signedBy(server, proof({baseUrl: 'http://192.168.1.21:32500'})));
  await probe('an expired proof', signedBy(server, proof({issuedAt: iso(-60000), expiresAt: iso(-40000)})));
  await probe('a proof valid for too long', signedBy(server, proof({expiresAt: iso(120000)})));
  await probe('a proof from the future', signedBy(server, proof({issuedAt: iso(300000), expiresAt: iso(320000)})));
  await probe('a changed signature', bend(signedBy(server, proof())));
  await probe('signed by a key that is not the one named', signedBy(other, proof()));
  await probe('an id that is not the key\'s digest', signedBy(server, proof({serverId: other.serverId})));
  await probe('an extra field in the envelope', {...signedBy(server, proof()), keyId: 'k1'});
  await probe('a wrong kind', signedBy(server, proof({kind: 'portico.routes'})));
  await probe('not an envelope', {error: {code: 'not_found'}});

  // Signed routes (verifyRoutes).
  const key = {keyId: 'hosted-key-1', publicKey: hosted.publicKey};
  const routes = (overrides = {}) => ({kind: 'portico.routes', version: '1', algorithm: 'Ed25519', keyId: key.keyId, audience: 'acct_1', serverId: server.serverId, publicKey: server.publicKey, fingerprint: server.fingerprint, name: 'Den', policyRevision: 3, generation: '12', claimGeneration: '2', credentialGeneration: '5',
    candidates: [{baseUrl: 'http://192.168.1.20:32500', class: 'lan', quality: 'reachable', generation: '12'}, {baseUrl: 'https://den.example.com', class: 'public', quality: 'probe_required', generation: '11'}], issuedAt: iso(-60000), expiresAt: iso(30 * 60000), ...overrides});
  const routeCases = [];
  const verify = async (name, value, expected = {}) => {
    const full = {accountId: 'acct_1', serverId: server.serverId, now, ...expected};
    const result = await outcome(() => route.verifyRoutes(value, key, full, crypto));
    routeCases.push({name, value, key, expected: {accountId: full.accountId, serverId: full.serverId, pin: full.pin ?? null, allowExpiredHint: full.allowExpiredHint === true}, now: Math.floor(now / 1000), ok: result.ok, code: result.code ?? null, candidates: result.value?.document.candidates ?? null, name_: result.value?.document.name ?? null});
  };
  const withKey = (k, document) => signedBy(k, document, {keyId: key.keyId});
  await verify('the account service\'s routes', withKey(hosted, routes()));
  await verify('with the server\'s pin', withKey(hosted, routes()), {pin: pinOf(server)});
  await verify('with a certificate attached', {...withKey(hosted, routes()), certificate: {payload: 'x', signature: 'y'}});
  await verify('another server\'s pin', withKey(hosted, routes()), {pin: pinOf(other)});
  await verify('another account', withKey(hosted, routes({audience: 'acct_2'})));
  await verify('a rotated key id', signedBy(hosted, routes(), {keyId: 'hosted-key-2'}));
  await verify('not signed by the account service', withKey(other, routes()));
  await verify('a changed signature', {...bend(withKey(hosted, routes()))});
  await verify('a public candidate over HTTP', withKey(hosted, routes({candidates: [{baseUrl: 'http://den.example.com', class: 'public', quality: 'reachable', generation: '1'}]})));
  await verify('a LAN candidate that is not private', withKey(hosted, routes({candidates: [{baseUrl: 'https://den.example.com', class: 'lan', quality: 'reachable', generation: '1'}]})));
  await verify('duplicate candidates', withKey(hosted, routes({candidates: [{baseUrl: 'https://den.example.com', class: 'public', quality: 'reachable', generation: '1'}, {baseUrl: 'https://den.example.com', class: 'manual', quality: 'reachable', generation: '1'}]})));
  await verify('a candidate newer than the document', withKey(hosted, routes({candidates: [{baseUrl: 'https://den.example.com', class: 'public', quality: 'reachable', generation: '13'}]})));
  await verify('expired routes', withKey(hosted, routes({issuedAt: iso(-50 * 60000), expiresAt: iso(-10 * 60000)})));
  await verify('expired routes as a hint', withKey(hosted, routes({issuedAt: iso(-50 * 60000), expiresAt: iso(-10 * 60000)})), {allowExpiredHint: true});
  await verify('no candidates', withKey(hosted, routes({candidates: []})));

  // Portico Account challenges (requestPorticoChallenge).
  const challengeCases = [];
  const challenge = async (name, answer, serverId = server.serverId) => {
    const result = await outcome(() => requestPorticoChallenge({request: async () => answer}, serverId, undefined, crypto));
    challengeCases.push({name, answer, serverId, nonce, ok: result.ok, code: result.code ?? null, challenge: result.value ?? null});
  };
  const challengeProof = (overrides = {}, k = server) => ({kind: 'portico.challenge-proof', version: '1', serverId: k.serverId, challenge: 'chal_abc', nonce, publicKey: k.publicKey, fingerprint: k.fingerprint, ...overrides});
  await challenge('a proven challenge', {challenge: 'chal_abc', proof: signedBy(server, challengeProof())});
  await challenge('a proof for another challenge', {challenge: 'chal_xyz', proof: signedBy(server, challengeProof())});
  await challenge('another nonce', {challenge: 'chal_abc', proof: signedBy(server, challengeProof({nonce: 'AAAA'}))});
  await challenge('a relay with its own key', {challenge: 'chal_abc', proof: signedBy(other, challengeProof({}, other))});
  await challenge('the server\'s id with a relay\'s signature', {challenge: 'chal_abc', proof: signedBy(other, challengeProof())});
  await challenge('a changed signature', {challenge: 'chal_abc', proof: bend(signedBy(server, challengeProof()))});
  await challenge('no proof', {challenge: 'chal_abc'});

  const unique = [...new Map(digests.map(d => [d.algorithm + d.input, d])).values()];
  write('route-identity.json', {digests: unique, verdicts, origins: originCases, hosts: hostCases, pins: pinCases, proofs: proofCases, routes: routeCases, challenges: challengeCases});
}
// ── Sessions and direct sign-in: local-session.ts and profile-management.ts ─────────────────
{
  const {parseLocalSession} = await import('../../portico-server/packages/client-core/src/local-session.ts');
  const {parseDirectSignIn, parseDirectSnapshot, parseManagedProfiles} = await import('../../portico-server/packages/client-core/src/profile-management.ts');
  const outcome = work => { try { return {ok: true, value: work()}; } catch (e) { return {ok: false, code: e.code ?? 'session_mismatch'}; } };
  const key = 'A'.repeat(43);
  const session = (overrides = {}, viewer = {}) => ({accessToken: 'token-abcdefghijklmnop', expiresAt: '2099-01-01T00:00:00Z', sessionFamilyId: 'fam_1', tokenGeneration: '7', authorizationHorizon: '2099-06-01T00:00:00Z', viewer: {accountId: 'acct_1', profileId: 'prof_1', serverId: 'srv_1', authority: 'local', role: 'viewer', ...viewer}, ...overrides});
  const without = (object, name) => { const copy = {...object}; delete copy[name]; return copy; };
  const sessionCases = [];
  const parse = (name, raw, expected, stored = false) => {
    const result = outcome(() => parseLocalSession(raw, expected ?? {}, {stored}));
    sessionCases.push({name, raw, expected: expected ?? null, stored, ok: result.ok, code: result.code ?? null, session: result.value ?? null});
  };
  parse('a viewer session', session());
  parse('with every optional field', session({deviceId: 'dev_1', installationId: 'inst_1', refreshToken: 'r'.repeat(43), serverIdentity: {publicKey: key, fingerprint: key}}));
  parse('the expected viewer', session(), {authority: 'local', accountId: 'acct_1', serverId: 'srv_1', profileId: 'prof_1'});
  parse('another account than expected', session(), {accountId: 'acct_2'});
  parse('another authority than expected', session({}, {authority: 'hosted'}), {authority: 'local'});
  parse('an unknown field', session({extra: 1}));
  parse('an unknown field, stored', session({extra: 1}), undefined, true);
  parse('an unknown viewer field', session({}, {extra: 1}));
  parse('an unknown viewer field, stored', session({}, {extra: 1}), undefined, true);
  parse('expired', session({expiresAt: '2020-01-01T00:00:00Z', authorizationHorizon: '2020-06-01T00:00:00Z'}));
  parse('expired, stored', session({expiresAt: '2020-01-01T00:00:00Z', authorizationHorizon: '2020-06-01T00:00:00Z'}), undefined, true);
  parse('expires after its horizon', session({expiresAt: '2099-07-01T00:00:00Z'}));
  parse('expires at its horizon', session({expiresAt: '2099-06-01T00:00:00Z'}));
  parse('a horizon a fraction later', session({expiresAt: '2099-06-01T00:00:00Z', authorizationHorizon: '2099-06-01T00:00:00.5Z'}));
  parse('a generation of zero', session({tokenGeneration: '0'}));
  parse('a numeric generation', session({tokenGeneration: 7}));
  parse('the largest generation', session({tokenGeneration: '9223372036854775807'}));
  parse('a generation past the largest', session({tokenGeneration: '9223372036854775808'}));
  parse('a family id with a space', session({sessionFamilyId: 'fam 1'}));
  parse('an unknown authority', session({}, {authority: 'portico'}));
  parse('no profile', session({}, {profileId: ''}));
  parse('a short refresh token', session({refreshToken: 'short'}));
  parse('a server identity with a short key', session({serverIdentity: {publicKey: 'AAAA', fingerprint: key}}));
  parse('a server identity with an extra field', session({serverIdentity: {publicKey: key, fingerprint: key, name: 'x'}}));
  parse('an empty token', session({accessToken: ''}));
  parse('a token with a control character', session({accessToken: 'abc\u0007def'}));
  parse('no family', without(session(), 'sessionFamilyId'));
  parse('a local date', session({expiresAt: '2099-01-01T00:00:00+02:00'}));
  parse('not an object', 'token');
  parse('an array', [session()]);

  const profile = (overrides = {}) => ({id: 'prof_1', name: 'Justin', primary: true, position: 0, art: 'blue', revision: 1, pinRevision: 1, pinRequired: false, ...overrides});
  const second = (overrides = {}) => profile({id: 'prof_2', name: 'Guest', primary: false, position: 1, art: 'coral', ...overrides});
  const profileCases = [];
  const profiles = (name, raw) => { const result = outcome(() => parseManagedProfiles(raw)); profileCases.push({name, raw, ok: result.ok, ids: result.value?.map(p => p.id) ?? null}); };
  profiles('one profile', [profile()]);
  profiles('ordered by position', [second({position: 5}), profile({position: 9}), profile({id: 'prof_3', primary: false, position: 2})]);
  profiles('ordered by id when positions tie', [second({id: 'prof_b', position: 1}), second({id: 'prof_a', position: 1}), profile({position: 1})]);
  profiles('with a trust revision and libraries', [profile({trustRevision: 3, allowedLibraries: ['lib_1', 'lib_2']})]);
  profiles('with unrestricted libraries', [profile({allowedLibraries: null})]);
  profiles('no profiles', []);
  profiles('nine profiles', Array.from({length: 9}, (_, i) => profile({id: 'p' + i, primary: i === 0})));
  profiles('two primaries', [profile(), second({primary: true})]);
  profiles('no primary', [profile({primary: false})]);
  profiles('duplicate ids', [profile(), second({id: 'prof_1'})]);
  profiles('an unknown art colour', [profile({art: 'teal'})]);
  profiles('a revision of zero', [profile({revision: 0})]);
  profiles('a fractional position', [profile({position: 1.5})]);
  profiles('duplicate libraries', [profile({allowedLibraries: ['lib_1', 'lib_1']})]);
  profiles('a name too long', [profile({name: 'x'.repeat(121)})]);

  const snapshot = (overrides = {}, account = {}) => ({authority: 'local', serverId: 'srv_1', canManage: true, account: {id: 'acct_1', username: 'justin', primaryProfileId: 'prof_1', role: 'owner', revision: 4, disabled: false, allowedLibraries: [], ...account}, profiles: [profile()], ...overrides});
  const signInCases = [];
  const signIn = (name, raw) => {
    const result = outcome(() => parseDirectSignIn(raw));
    const v = result.value;
    signInCases.push({name, raw, ok: result.ok, code: result.code ?? null, kind: v?.kind ?? null, accountScoped: v?.accountScoped ?? null, passwordChangeRequired: v?.passwordChangeRequired ?? null, role: v?.snapshot?.account.role ?? null, profiles: v?.snapshot?.profiles.length ?? null, token: v?.token ?? null, deviceId: v?.deviceId ?? null, custodyPending: v?.snapshot?.custodyPending === true});
  };
  signIn('one unprotected profile signs in as the viewer', {...snapshot(), session: session()});
  signIn('several profiles give an account session', {...snapshot({profiles: [profile(), second()]}), session: session({}, {role: 'account'})});
  signIn('a PIN gives an account session', {...snapshot({profiles: [profile({pinRequired: true})]}), session: session({}, {role: 'account'})});
  signIn('a viewer session with several profiles is refused', {...snapshot({profiles: [profile(), second()]}), session: session()});
  signIn('a viewer session with a PIN is refused', {...snapshot({profiles: [profile({pinRequired: true})]}), session: session()});
  signIn('a required password change', {...snapshot(), passwordChangeRequired: true, session: session({}, {role: 'account'})});
  signIn('a required password change with a viewer session is refused', {...snapshot(), passwordChangeRequired: true, session: session()});
  signIn('a Portico Account member', {...snapshot({custodyPending: true}, {hostedAccountId: 'pa_1', role: 'member'}), session: session()});
  signIn('a session for another account', {...snapshot(), session: session({}, {accountId: 'acct_9'})});
  signIn('a session for another server', {...snapshot(), session: session({}, {serverId: 'srv_9'})});
  signIn('a session for a profile that is not the primary', {...snapshot(), session: session({}, {profileId: 'prof_2'})});
  signIn('a hosted session', {...snapshot(), session: session({}, {authority: 'hosted'})});
  signIn('a two-step challenge', {challenge: {token: 'chal_token', expiresAt: '2099-01-01T00:00:00Z'}});
  signIn('a challenge with no token', {challenge: {expiresAt: '2099-01-01T00:00:00Z'}});
  signIn('a device waiting for approval', {deviceApprovalPending: true, deviceId: 'dev_1', installationId: 'inst_1'});
  signIn('a pending device with a session is refused', {deviceApprovalPending: true, deviceId: 'dev_1', installationId: 'inst_1', session: session()});
  signIn('an unknown role', {...snapshot({}, {role: 'guest'}), session: session()});
  signIn('a primary profile that is not listed', {...snapshot({}, {primaryProfileId: 'prof_9'}), session: session()});
  signIn('no session', snapshot());
  signIn('a hosted authority snapshot', {...snapshot({authority: 'hosted'}), session: session()});
  signIn('nothing', null);
  write('sessions.json', {now: Math.floor(Date.now() / 1000), sessions: sessionCases, profiles: profileCases, signIns: signInCases});
}
// ── Error presentation: presentation/errors.ts ───────────────────────────────────────────────
{
  const {presentError} = await import('../../portico-server/packages/client-core/src/presentation/errors.ts');
  const errors = [
    {code: 'network'}, {code: 'timeout'}, {code: 'cancelled'}, {code: 'abort'}, {code: 'unauthorized', status: 401}, {code: 'forbidden', status: 403}, {code: 'not_found', status: 404},
    {code: 'rate_limited', status: 429, retryAfterSeconds: 12}, {code: 'rate_limited', status: 429}, {code: 'unsupported_version', status: 426}, {code: 'storage_full', status: 507},
    {code: 'invalid_request', status: 400}, {code: 'invalid_response'}, {code: 'library_not_found', status: 404}, {code: 'server_busy', status: 503}, {code: 'transcode_capacity_reached'},
    {code: 'stale_continuation', status: 409}, {code: 'revision_conflict', status: 409}, {code: 'identity_mismatch'}, {code: 'route_stale'}, {code: 'invalid_address'}, {code: 'invalid_current_session'},
    {code: 'metadata_unavailable', status: 503}, {code: 'queue_too_large', status: 422}, {code: 'local_metadata_only', status: 409}, {code: 'method_not_allowed', status: 405}, {code: 'artwork_pending', status: 404},
    {code: 'upstream_timeout', status: 504}, {code: 'request_failed', status: 500}, {code: 'internal_error', status: 500}, {code: 'something_new', status: 418}, {code: 'something_new'},
    {status: 401}, {status: 403}, {status: 404}, {status: 409}, {status: 412}, {status: 428}, {status: 426}, {status: 429}, {status: 507}, {status: 408}, {status: 503}, {status: 400}, {status: 422}, {status: 500}, {},
  ];
  const variants = [['home', {}], ['library', {operation: 'save'}], ['sign-in', {operation: 'action'}], ['sign-in', {operation: 'action', service: 'portico-account'}], ['portico-account', {}], ['generic', {retrying: true}], ['link', {retrying: true}]];
  const cases = [];
  for (const error of errors) for (const [context, options] of variants) {
    const p = presentError(error, context, options);
    cases.push({error, context, options, category: p.category, messageId: p.messageId, action: p.action, silent: p.silent, title: p.title, body: p.body});
  }
  write('errors.json', cases);
}
// ── Server presence: index.ts sortServersByPresence and presenceLabel ───────────────────────
{
  const core = await import('../../portico-server/packages/client-core/src/index.ts');
  const now = Date.parse('2026-10-03T12:00:00Z');
  const servers = [
    {id: 'unknown-1', name: 'A'},
    {id: 'offline-old', name: 'B', presence: {online: false, lastSeenAt: '2026-09-01T00:00:00Z'}},
    {id: 'online-1', name: 'C', presence: {online: true, lastSeenAt: '2026-10-03T11:59:00Z'}},
    {id: 'offline-recent', name: 'D', presence: {online: false, lastSeenAt: '2026-10-03T11:30:00Z'}},
    {id: 'never', name: 'E', presence: {online: false, lastSeenAt: null}},
    {id: 'online-2', name: 'F', presence: {online: true, lastSeenAt: null}},
    {id: 'malformed', name: 'G', presence: {online: 'yes'}},
    {id: 'bad-date', name: 'H', presence: {online: false, lastSeenAt: 'last week'}},
  ];
  const parsed = servers.map(s => { const presence = core.parseServerPresence(s.presence); return presence ? {...s, presence} : {id: s.id, name: s.name}; });
  write('presence.json', {now: Math.floor(now / 1000), servers, order: core.sortServersByPresence(parsed).map(s => s.id), labels: parsed.map(s => ({id: s.id, label: core.presenceLabel(s.presence, now)}))});
}
// ── QR codes: the `qrcode` package (what react-native-qrcode-svg draws from), level M ─────────
{
  const {default: QRCode} = await import('qrcode');
  const grid = (text, maskPattern) => {
    const code = QRCode.create([{data: Buffer.from(text), mode: 'byte'}], {errorCorrectionLevel: 'M', ...(maskPattern === undefined ? {} : {maskPattern})});
    const {size, data} = code.modules;
    return {size, mask: code.maskPattern, rows: Array.from({length: size}, (_, y) => Array.from({length: size}, (_, x) => (data[y * size + x] ? '1' : '0')).join(''))};
  };
  const texts = ['https://web.getportico.tv/device#code=ABCD-EFGH', 'http://192.168.1.20:32500/device#code=WXYZ-2345', 'PORTICO', 'https://media.example.com:8443/device#code=QRST-6789&really=long-enough-to-need-version-seven-or-more-of-the-symbol-so-version-bits-are-drawn'];
  const forced = [];
  for (const text of texts.slice(0, 2)) for (let mask = 0; mask < 8; mask++) forced.push({text, ...grid(text, mask)});
  const long = 'https://media.example.com/device#code=LMNP-7Q8R&' + 'padding-to-reach-a-sixteen-bit-length-and-four-alignment-rows-'.repeat(4);
  forced.push({text: texts[2], ...grid(texts[2], 3)}, {text: texts[3], ...grid(texts[3], 5)}, {text: long, ...grid(long, 2)});
  write('qr.json', forced);
  write('qr-auto.json', texts.map(text => ({text, ...grid(text)})));
}
// ── Formatting: packages/i18n createI18n, for the regions the channel has ───────────────────
{
  const {createI18n, enUS} = await import('../../portico-server/packages/i18n/src/index.ts');
  const {passwordStrength} = await import('../../portico-server/packages/client-core/src/password-strength.ts');
  const now = Date.parse('2026-10-03T12:00:00Z');
  const ids = Object.keys(enUS).filter(id => /^(duration\.|relative\.|list\.)/.test(id));
  const regions = [];
  for (const [locale, hour12] of [['en-US', true], ['en-GB', false], ['en-CA', true], ['en-GB', true], ['en-US', false]]) {
    const i18n = createI18n({uiLocale: locale, formatLocale: locale, timeZone: 'UTC', hour12});
    const stamps = ['2026-10-03T12:00:00Z', '2026-09-01T00:05:00Z', '2026-01-09T21:41:30Z', '2025-12-31T23:59:59Z', '2026-05-17T08:07:00Z'];
    regions.push({
      locale, hour12,
      catalogue: Object.fromEntries(ids.map(id => [id, i18n.t(id) === undefined ? '' : (locale === 'en-US' ? enUS[id] : enUS[id])])),
      dates: stamps.flatMap(value => ['medium', 'dayMonth', 'monthYear', 'year', 'weekday'].map(style => ({value, style, text: i18n.date(value, style)}))),
      times: stamps.map(value => ({value, text: i18n.time(value).replace(/ /g, ' ')})),
      durations: [0, 5, 59, 60, 61, 90, 3599, 3600, 3660, 6120, 86400, 90061].flatMap(seconds => ['short', 'long'].map(style => ({seconds, style, text: i18n.duration(seconds, style)}))),
      clocks: [0, 5, 65, 245, 3600, 3723, 36000, -4].map(seconds => ({seconds, text: i18n.clock(seconds)})),
      relative: [10, 44, 45, 300, 3300, 3600, 7200, 80000, 86400, 100000, 300000, 600000, 6000000, 30000000].map(ago => ({value: new Date(now - ago * 1000).toISOString(), text: i18n.relativeTime(now - ago * 1000, now)})),
      bytes: [0, 512, 1023, 1024, 1536, 10240, 1048576, 1500000000, 5368709120, 1099511627776 * 3].map(value => ({value, text: i18n.bytes(value)})),
      lists: [[], ['A'], ['A', 'B'], ['A', 'B', 'C'], ['A', 'B', 'C', 'D']].map(items => ({items, text: i18n.list(items)})),
    });
  }
  const passwords = ['', 'short', '1234567', '12345678', 'correct horse battery staple', 'p'.repeat(72), 'p'.repeat(73), 'pässwörd', 'é'.repeat(36), 'é'.repeat(37), '😀'.repeat(8), '😀'.repeat(7)];
  write('format.json', {now: Math.floor(now / 1000), regions, passwords: passwords.map(password => ({password, acceptable: passwordStrength(password).acceptable}))});
}
// ── Home: home.ts, library-content.ts entries, card-caption.ts, card-shape.ts, home-hero.ts ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const {validateHomeDocument, validateHomeRow, appendHomeRowPage, homeRowHeading} = await import('../../portico-server/packages/client-core/src/home.ts');
  const {validateContentEntry} = await import('../../portico-server/packages/client-core/src/library-content.ts');
  const caption = await import('../../portico-server/packages/client-core/src/presentation/card-caption.ts');
  const {shapeFor} = await import('../../portico-server/packages/client-core/src/presentation/card-shape.ts');
  const {homeHero} = await import('../../portico-server/packages/client-core/src/presentation/home-hero.ts');
  const {createI18n, enUS} = await import('../../portico-server/packages/i18n/src/index.ts');
  const i18n = createI18n({uiLocale: 'en-US', formatLocale: 'en-US', timeZone: 'UTC', hour12: true});
  const file = join(app, 'test', 'fixtures', 'server', 'home.json');
  const real = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : undefined;
  const attempt = work => { try { return {ok: true, value: work()}; } catch { return {ok: false}; } };
  const year = new Date().getFullYear();
  const synthetic = [
    {id: 'a1', kind: 'album', title: 'Kind of Blue', artist: {id: 'ar1', name: 'Miles Davis'}, year: 1959},
    {id: 'a2', kind: 'album', title: 'Untitled', subtitle: 'Various Artists · 2001'},
    {id: 'a3', kind: 'album', title: 'No facts'},
    {id: 'ar1', kind: 'artist', title: 'Miles Davis', count: 12},
    {id: 'ar2', kind: 'artist', title: 'Nobody', count: 0},
    {id: 'b1', kind: 'book', title: 'Dune', author: 'Frank Herbert'},
    {id: 'b2', kind: 'book', title: 'Dune', subtitle: '1965 · Frank Herbert'},
    {id: 'e1', kind: 'episode', title: 'Ozymandias', subtitle: 'Breaking Bad · Season 5', seasonNumber: 5, episodeNumber: 14, airDate: `${year}-09-15`, duration: 2880, progressSeconds: 1440},
    {id: 'e2', kind: 'episode', title: 'Pilot', subtitle: 'Some Show', episodeNumber: 1, airDate: '2019-01-02'},
    {id: 'e3', kind: 'episode', title: 'Wano', subtitle: 'One Piece', seasonNumber: 21, episodeNumber: 5, absoluteNumber: 1043, duration: 1440, progressSeconds: 30},
    {id: 'e4', kind: 'episode', title: 'Lost', subtitle: ''},
    {id: 's1', kind: 'show', title: 'Severance', subtitle: '2022', latestEpisode: {airDate: `${year}-03-21T00:00:00Z`, seasonNumber: 2, episodeNumber: 10, count: 1}},
    {id: 's2', kind: 'show', title: 'Daily', latestEpisode: {airDate: '2024-11-05', episodeNumber: 3, count: 4}},
    {id: 's3', kind: 'show', title: 'Plain', year: 2011},
    {id: 'm1', kind: 'movie', title: 'Heat', year: 1995, duration: 10200, progressSeconds: 3600, contentRating: 'R', genres: ['Crime', 'Drama', 'Thriller'], backdropUrl: '/b'},
    {id: 'm2', kind: 'movie', title: 'Heat', subtitle: '1995 · Director\'s Cut', year: 1995},
    {id: 'm3', kind: 'movie', title: 'Short', duration: 100, progressSeconds: 95},
    {id: 'c1', kind: 'collection', title: 'Marvel', count: 23},
    {id: 'c2', kind: 'category', title: 'Jazz', count: 0, subtitle: 'Genre'},
    {id: 'au1', kind: 'author', title: 'Frank Herbert', count: 6},
    {id: 'bs1', kind: 'book_series', title: 'Dune', count: 1},
    {id: 'so1', kind: 'song', title: 'So What', artist: {id: 'ar1', name: 'Miles Davis'}, album: {id: 'a1', name: 'Kind of Blue'}, duration: 562, progressSeconds: 120, subtitle: 'Miles Davis'},
    {id: 'f1', kind: 'audiobook_file', title: 'Part 1', author: 'Frank Herbert', duration: 36000, progressSeconds: 3000},
    {id: 'x1', kind: 'extra', title: 'Trailer'},
    {id: 'd1', kind: 'disc', title: 'Disc 2'},
    {id: 'se1', kind: 'season', title: 'Season 2', subtitle: '10 episodes'},
  ];
  const refused = [
    {id: '', kind: 'movie', title: 'No id'}, {id: 'k', kind: 'movie'}, {id: 'k', kind: 'movie', title: 'x', year: -1}, {id: 'k', kind: 'movie', title: 'x', duration: -4},
    {id: 'k', kind: 'movie', title: 'x', watched: 'yes'}, {id: 'k', kind: 'movie', title: 'x', count: 1.5}, {id: 'k', kind: 'movie', title: 'x', navigation: {view: 'nowhere'}},
    {id: 'k', kind: 'movie', title: 'x', playback: {}}, {id: 'k', kind: 'movie', title: 'x', subtitle: 5}, {id: 'k', kind: 'song', title: 'x', plays: 0}, {id: 'k', kind: 'movie', title: 'x', overview: 'bad\u0001'},
    {id: 'k', kind: 'hologram', title: 'x'}, 'entry', null,
  ];
  const lenient = [
    {id: 'k', kind: 'movie', title: 'x', genres: ['Drama', 7, '', 'Crime'], artist: {id: '', name: 'x'}, role: 'bootleg', artworkPaths: ['/a', 3, '/b', '/c', '/d', '/e'], airDate: '2024-1-2', rating: 11, resolution: '8k', overviewSourceUrl: 'http://x', latestEpisode: {airDate: 'soon'}, addedAt: null, overview: 'line\none\ttab'},
  ];
  const realEntries = real ? real.rows.flatMap(r => r.entries) : [];
  const describe = raw => {
    const parsed = attempt(() => validateContentEntry(raw));
    if (!parsed.ok) return {raw, ok: false};
    const e = parsed.value;
    return {raw, ok: true, keys: Object.keys(e).sort(), genres: e.genres ?? null, artworkPaths: e.artworkPaths ?? null,
      caption: caption.cardCaption(e, i18n.t, {locale: 'en-US'}) ?? null, continueCaption: caption.continueCaption(e, i18n.t) ?? null, continueTitle: caption.continueTitle(e),
      remaining: caption.remainingLabel(e, i18n.t) ?? null, episodeCode: caption.episodeCode(e, i18n.t) ?? null,
      shapes: Object.fromEntries(['shelf', 'grid', 'list', 'showWorkspace', 'detailExtras', 'hero'].map(c => [c, shapeFor(e.kind, c)])), squareFamily: shapeFor(e.kind, 'shelf', 'music'),
      watched: caption.watchedWords(e.kind)};
  };
  const entries = [...realEntries, ...synthetic, ...lenient, ...refused].map(describe);
  const documents = [];
  const doc = (name, value) => {
    const parsed = attempt(() => validateHomeDocument(value));
    const d = parsed.value;
    const hero = parsed.ok ? homeHero(d, i18n.t, {duration: s => i18n.duration(s)}) : undefined;
    documents.push({name, value, ok: parsed.ok, rows: d ? d.rows.map(r => ({id: r.id, entries: r.entries.map(e => e.id), heading: homeRowHeading(r)})) : null, heroRef: d?.hero ?? null,
      hero: hero ? {title: hero.title, line: hero.line ?? null, meta: hero.meta ?? null, progress: hero.progress, playLabel: hero.playLabel, art: hero.art, coverShape: hero.coverShape, entryId: hero.entry.id} : null});
  };
  if (real) {
    const copy = () => JSON.parse(JSON.stringify(real));
    doc('the development server\'s Home', real);
    let d = copy(); d.hero = {rowId: 'continue', entryId: 'not-there'}; doc('a hero that names no entry', d);
    d = copy(); delete d.hero; doc('no hero', d);
    // The first row that holds entries (a profile with nothing in progress has an empty first row).
    const full = Math.max(0, real.rows.findIndex(r => r.entries.length > 0));
    d = copy(); d.rows[full].entries[0].kind = 'hologram'; doc('an entry of an unknown kind is left out, and a hero on it is absent', d);
    d = copy(); d.rows[full === 1 ? 0 : 1].id = d.rows[full].id; doc('two rows with one id', d);
    d = copy(); d.rows[full].entries.push(d.rows[full].entries[0]); doc('an entry twice in a row', d);
    d = copy(); d.layout.hiddenRowIds = [d.rows[2].id]; doc('a row the viewer hid', d);
    d = copy(); d.rows[3].entries = []; doc('an empty row that is not critical', d);
    d = copy(); d.rows[3].entries = []; d.rows[3].critical = true; doc('an empty critical row', d);
    d = copy(); d.rows[full].required = true; d.rows[full].hideable = true; doc('a row both required and hideable', d);
    d = copy(); d.rows[full].artworkShape = 'circle'; doc('an unknown artwork shape', d);
    d = copy(); d.rows[full].total = 0; doc('more entries than the total', d);
    d = copy(); d.rows[full].titleText = {code: 5}; doc('a malformed title text', d);
    d = copy(); delete d.layout; doc('no layout', d);
    d = copy(); d.generatedAt = ''; doc('no generation time', d);
    d = copy(); d.rows[4].entries[0] = {...d.rows[4].entries[0], backdropUrl: undefined}; d.hero = {rowId: d.rows[4].id, entryId: d.rows[4].entries[0].id}; doc('a hero with only a cover', d);
    d = copy(); d.hero = {rowId: d.rows[1].id, entryId: d.rows[1].entries[0].id}; doc('a hero from Continue Listening', d);
  }
  let paging = null;
  if (real) {
    const row = validateHomeRow(real.rows.find(r => r.hasMore));
    const page = {...row, entries: [row.entries[1], {...row.entries[0], id: 'new-1'}, {...row.entries[0], id: 'new-2'}], nextCursor: 'cursor-2', hasMore: true, total: row.total + 1};
    const merged = appendHomeRowPage(row, page);
    const big = {...row, entries: Array.from({length: 99}, (_, i) => ({...row.entries[0], id: 'e' + i}))};
    const capped = appendHomeRowPage(big, page);
    paging = {row: real.rows.find(r => r.hasMore), page: {...real.rows.find(r => r.hasMore), entries: page.entries, nextCursor: 'cursor-2', hasMore: true, total: row.total + 1}, merged: {ids: merged.entries.map(e => e.id), nextCursor: merged.nextCursor, total: merged.total}, big: big.entries.map(e => e.id), capped: {count: capped.entries.length, nextCursor: capped.nextCursor}};
  }
  const ids = Object.keys(enUS).filter(id => /^(title\.|card\.|entry\.|duration\.|action\.play$)/.test(id));
  write('home.json', {now: Math.floor(Date.now() / 1000), catalogue: Object.fromEntries(ids.map(id => [id, enUS[id]])), entries, documents, paging});
}
// ── Library: library-tabs.ts, browse.ts, browse-toolbar.ts and library-content.ts projections ──
{
  const {existsSync, readFileSync, readdirSync} = await import('node:fs');
  const tabsModule = await import('../../portico-server/packages/client-core/src/presentation/library-tabs.ts');
  const browse = await import('../../portico-server/packages/client-core/src/browse.ts');
  const toolbar = await import('../../portico-server/packages/client-core/src/presentation/browse-toolbar.ts');
  const {validateContentProjection} = await import('../../portico-server/packages/client-core/src/library-content.ts');
  const {createI18n, enUS} = await import('../../portico-server/packages/i18n/src/index.ts');
  const i18n = createI18n({uiLocale: 'en-US', formatLocale: 'en-US', timeZone: 'UTC', hour12: true});
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => JSON.parse(readFileSync(join(dir, name), 'utf8'));
  const names = existsSync(dir) ? readdirSync(dir).sort() : [];
  const attempt = work => { try { return {ok: true, value: work()}; } catch { return {ok: false}; } };
  const clone = v => JSON.parse(JSON.stringify(v));

  const tabOut = t => ({id: t.id, label: t.label, shows: t.shows, ...(t.pivot ? {pivot: t.pivot} : {}), ...(t.fixedSort ? {fixedSort: t.fixedSort} : {}), ...(t.fixedFilter ? {fixedFilter: t.fixedFilter} : {}), ...(t.opens ? {opens: {tabId: t.opens.tab, field: t.opens.field}} : {})});
  const kinds = ['movie', 'tv', 'anime', 'music', 'audiobook', 'recordings', ''];
  const tabs = [];
  for (const kind of kinds) for (const owner of [false, true]) for (const unmatched of [false, true]) tabs.push({kind, owner, unmatched, tabs: tabsModule.libraryTabs(kind, {owner, unmatched}).map(tabOut)});
  const tabFor = [];
  for (const kind of kinds) for (const id of ['discover', 'browse', 'aired', 'releases', 'songs', 'genres', 'playlists', 'unmatched', 'authors', 'series', 'collections', 'nope']) tabFor.push({kind, id, tab: tabsModule.libraryTab(kind, id, {owner: true, unmatched: true}).id});
  const pivotFor = [];
  for (const kind of kinds) for (const pivot of ['movies', 'shows', 'collections', 'artists', 'albums', 'songs', 'genres', 'books', 'authors', 'series', 'nope']) pivotFor.push({kind, pivot, tab: tabsModule.libraryTabForPivot(kind, pivot)?.id ?? null});
  const releaseEntries = [{id: '1', role: 'album'}, {id: '2'}, {id: '3', role: 'single'}, {id: '4', role: 'ep'}, {id: '5', role: 'compilation'}, {id: '6', role: 'appearance'}, {id: '7', role: 'album'}];
  const releases = [releaseEntries, releaseEntries.slice(0, 2), releaseEntries.slice(4), []].map(entries => ({entries, groups: tabsModule.artistReleaseGroups(entries).map(g => ({id: g.id, label: g.label, ids: g.entries.map(e => e.id)}))}));

  // Capabilities: the server's own, and each with one thing wrong.
  const capabilityOut = c => ({library: {id: c.library.id, name: c.library.name, kind: c.library.kind}, pivots: c.pivots.map(p => p.id), resolvedPivot: c.resolvedPivot ? {id: c.resolvedPivot.id, labelKey: c.resolvedPivot.labelKey, defaultSort: c.resolvedPivot.defaultSort, browsable: c.resolvedPivot.browsable} : null, fields: c.fields.map(f => ({id: f.id, labelKey: f.labelKey, type: f.type, controlHint: f.controlHint, operators: f.operators, ...(f.allowedValues ? {allowedValues: f.allowedValues} : {}), ...(f.facetSource ? {facetSource: f.facetSource} : {})})), sorts: c.sorts.map(x => ({id: x.id, labelKey: x.labelKey, directions: x.directions, defaultDirection: x.defaultDirection})), quickFilters: c.quickFilters, maximumLimit: c.queryLimits.maximumLimit});
  const capabilities = [];
  const parsedCapabilities = {};
  for (const name of names.filter(n => /-capabilities-/.test(n))) {
    const raw = load(name);
    const parsed = browse.parseBrowseCapabilities(raw);
    parsedCapabilities[name] = parsed;
    capabilities.push({name, raw, ok: true, value: capabilityOut(parsed)});
  }
  const firstCapabilities = capabilities[0]?.raw;
  if (firstCapabilities) {
    const breakers = {
      'no library': r => { delete r.library; },
      'library id empty': r => { r.library.id = ''; },
      'limits missing': r => { delete r.queryLimits.maximumLimit; },
      'limit below default': r => { r.queryLimits.maximumLimit = r.queryLimits.defaultLimit - 1; },
      'duplicate pivot': r => { r.pivots.push(r.pivots[0]); },
      'pivot not browsable flag': r => { r.pivots[0].browsable = 'yes'; },
      'unknown field type': r => { r.fields[0].type = 'colour'; },
      'unknown control hint': r => { r.fields[0].controlHint = 'slider'; },
      'unknown operator': r => { r.fields[0].operators = ['roughly']; },
      'unknown complexity': r => { r.fields[0].complexity = 'expert'; },
      'duplicate field': r => { r.fields.push(r.fields[0]); },
      'sort default not offered': r => { r.sorts[0].directions = ['asc']; r.sorts[0].defaultDirection = 'desc'; },
      'sort expensive missing': r => { delete r.sorts[0].expensive; },
      'quick filter malformed': r => { r.quickFilters = [{id: 'x', labelKey: 'filter.x', query: {field: 'genre', operator: 'in', value: 'Drama'}}]; },
      'quick filter presence with value': r => { r.quickFilters = [{id: 'x', labelKey: 'filter.x', query: {field: 'genre', operator: 'is-present', value: true}}]; },
      'quick filter nested': r => { r.quickFilters = [{id: 'x', labelKey: 'filter.x', query: {all: [{field: 'genre', operator: 'in', value: ['Drama']}, {not: {any: [{field: 'year', operator: 'between', value: [1990, 1999]}]}}]}}]; },
      'quick filter empty group': r => { r.quickFilters = [{id: 'x', labelKey: 'filter.x', query: {all: []}}]; },
      'resolved pivot unknown': r => { r.resolvedPivot = {...r.pivots[0], id: 'elsewhere'}; },
      'resolved pivot null': r => { r.resolvedPivot = null; },
      'too many fields': r => { r.fields = Array.from({length: 129}, (_, i) => ({...r.fields[0], id: 'f' + i})); },
    };
    for (const [name, breaker] of Object.entries(breakers)) {
      const raw = clone(firstCapabilities);
      breaker(raw);
      const result = attempt(() => capabilityOut(browse.parseBrowseCapabilities(raw)));
      capabilities.push({name, raw, ok: result.ok, ...(result.ok ? {value: result.value} : {})});
    }
  }

  const resultOut = r => ({pivot: r.pivot, start: r.pageInfo.start, total: r.pageInfo.total, revision: r.pageInfo.revision, hasMore: r.pageInfo.hasMore, positionIndex: r.positionIndex, ids: r.entries.map(e => e.id)});
  const results = [];
  for (const name of names.filter(n => /-browse-/.test(n))) {
    const raw = load(name);
    results.push({name, raw, ok: true, value: resultOut(browse.parseBrowseResult(raw))});
  }
  const firstResult = results.find(r => r.raw.entries.length > 2)?.raw;
  if (firstResult) {
    const breakers = {
      'no page info': r => { delete r.pageInfo; },
      'start past total': r => { r.pageInfo.start = r.pageInfo.total + 1; },
      'has more disagrees': r => { r.pageInfo.hasMore = !r.pageInfo.hasMore; },
      'duplicate entry': r => { r.entries.push(r.entries[0]); r.pageInfo.total += 1; },
      'entry malformed': r => { r.entries[0].title = 7; },
      'anchors out of order': r => { r.positionIndex = [{key: 'B', index: 1}, {key: 'A', index: 0}]; },
      'anchor past total': r => { r.positionIndex = [{key: 'A', index: r.pageInfo.total}]; },
      'anchor of unknown shape dropped': r => { r.positionIndex = [{key: 'A', index: 0}, {letter: 'B'}, {key: 'C', index: 1}]; },
      'anchors missing': r => { delete r.positionIndex; },
      'applied sort missing': r => { delete r.applied.sort; },
      'applied query malformed': r => { r.applied.query = {field: 'genre'}; },
      'applied seek empty': r => { r.applied.seek = {prefix: ''}; },
      'revision empty': r => { r.pageInfo.revision = ''; },
    };
    for (const [name, breaker] of Object.entries(breakers)) {
      const raw = clone(firstResult);
      breaker(raw);
      const result = attempt(() => resultOut(browse.parseBrowseResult(raw)));
      results.push({name, raw, ok: result.ok, ...(result.ok ? {value: result.value} : {})});
    }
  }

  const facets = [];
  for (const name of names.filter(n => /-facets-/.test(n))) {
    const raw = load(name);
    for (const expected of [raw.field, 'elsewhere', '']) {
      const result = attempt(() => browse.parseBrowseFacets(raw, expected || undefined).values.map(v => ({value: v.value, label: v.label, total: v.count})));
      facets.push({name, raw, expected, ok: result.ok, ...(result.ok ? {values: result.value} : {})});
    }
  }
  if (facets[0]) for (const [name, breaker] of Object.entries({'zero count': r => { r.values = [{value: 'a', label: 'A', count: 0}]; }, 'duplicate value': r => { r.values = [{value: 'a', label: 'A', count: 1}, {value: 'a', label: 'A', count: 2}]; }, 'empty label': r => { r.values = [{value: 'a', label: '', count: 1}]; }})) {
    const raw = clone(facets[0].raw);
    breaker(raw);
    const result = attempt(() => browse.parseBrowseFacets(raw, raw.field).values);
    facets.push({name, raw, expected: raw.field, ok: result.ok});
  }

  // The toolbar. `fieldLabel` and `valueText` live in the Apple app beside React Native imports,
  // so they are repeated here from apps/native/src/app/browse.ts and screens/BrowseFilters.tsx;
  // the tables they read are the ones scripts/generate.mjs extracts from that file.
  const browseSource = readFileSync(join(app, '..', 'native', 'src', 'app', 'browse.ts'), 'utf8');
  const table = pattern => Function(`return (${pattern.exec(browseSource)[1]})`)();
  const fieldNames = table(/const fieldNames: Record<string, string> = (\{[^}]*\});/);
  const quickNames = table(/const names: Record<string, string> = (\{[^}]*\});/);
  const sentence = key => key.replace(/([A-Z])/g, ' $1').toLowerCase().replace(/^./, c => c.toUpperCase());
  const fieldLabel = (id, labelKey) => {
    if (labelKey === 'sort.forYou') return i18n.t('sort.forYou');
    const key = (labelKey ?? '').replace(/^browse\.field\./, '').replace(/^sort\./, '') || id;
    return fieldNames[key] ?? fieldNames[id] ?? sentence(key);
  };
  const quickFilterLabel = labelKey => { const key = labelKey.replace(/^filter\./, ''); return quickNames[key] ?? sentence(key); };
  const valueText = (field, value) => (field.id === 'year' && /^\d{3}0$/.test(value) ? `${value}s` : field.type === 'boolean' ? (value === 'true' ? i18n.t('lib.yes') : i18n.t('lib.no')) : toolbar.browseValueLabel(value));
  const directionLabel = (field, direction) => i18n.t('lib.direction', {kind: /title|name|artist|album|author/.test(field) ? 'alpha' : /added|date|year|release|played|last/.test(field) ? 'date' : /rating/.test(field) ? 'rating' : /duration|length/.test(field) ? 'duration' : 'other', dir: direction});
  const now = new Date('2026-10-03T12:00:00Z');
  const predicateSets = [
    [],
    [{field: 'genre', operator: 'contains-any', value: ['Drama', 'Comedy']}],
    [{field: 'decade', operator: 'in', value: [1990, 2000]}, {field: 'favorite', operator: 'equals', value: true}],
    [{field: 'playState', operator: 'equals', value: 'unwatched'}, {field: 'communityRating', operator: 'at-least', value: 8}],
    [{field: 'durationSeconds', operator: 'between', value: [1800, 3600]}, {field: 'resolution', operator: 'equals', value: '4k'}],
    [{field: 'durationSeconds', operator: 'at-least', value: 1800}, {field: 'durationSeconds', operator: 'at-most', value: 3600}, {field: 'collection', operator: 'is-missing', value: null}],
    [{field: 'dateAdded', operator: 'at-least', value: '2026-09-03'}, {field: 'dynamicRange', operator: 'not-equals', value: 'dolby_vision'}, {field: 'title', operator: 'starts-with', value: 'The'}],
  ];
  const toolbars = [];
  for (const [name, parsed] of Object.entries(parsedCapabilities)) {
    const kind = parsed.library.kind;
    const sorts = [parsed.resolvedPivot?.defaultSort[0] ?? {field: 'title', direction: 'asc'}, ...parsed.sorts.slice(0, 3).map(x => ({field: x.id, direction: x.defaultDirection}))];
    const quick = parsed.quickFilters.map(q => q.query).filter(q => 'field' in q);
    const sets = [...predicateSets, ...(quick.length ? [[quick[0]], [quick[quick.length - 1], {field: 'genre', operator: 'contains-any', value: ['Jazz']}]] : [])];
    const cases = [];
    for (const owner of [false, true]) for (const [index, predicates] of sets.entries()) {
      const sort = sorts[index % sorts.length];
      const model = toolbar.toolbarModel(parsed, kind, predicates, sort, {owner, textEntry: false});
      const sortCap = parsed.sorts.find(x => x.id === sort.field);
      cases.push({
        owner, predicates, sort,
        model: {promoted: model.promoted.map(f => f.id), quick: model.quick.map(q => q.id), groups: model.groups.map(g => ({id: g.id, fields: g.fields.map(f => f.id)})), sorts: model.sorts.map(x => x.id), sort: model.sort, applied: model.applied},
        summaries: Object.fromEntries(model.groups.flatMap(g => g.fields).map(f => [f.id, toolbar.fieldSelectionSummary({...f, id: f.id}, predicates.filter(p => p.field === f.id || (f.id === 'year' && p.field === 'decade')).map(p => ({...p, field: f.id})), v => valueText(f, String(v))) ?? ''])),
        labels: predicates.map(p => toolbar.appliedFilterLabel(p, id => fieldLabel(id, parsed.fields.find(f => f.id === id)?.labelKey), i18n.t)),
        sortLabel: model.sort.flippable ? i18n.t('lib.sortChip', {field: fieldLabel(sort.field, sortCap?.labelKey), direction: directionLabel(sort.field, sort.direction)}) : fieldLabel(sort.field, sortCap?.labelKey),
        nextSorts: parsed.sorts.map(x => ({field: x.id, next: toolbar.nextToolbarSort(parsed, sort, x.id)})),
      });
    }
    toolbars.push({
      name, kind, cases,
      fields: parsed.fields.map(f => ({id: f.id, label: fieldLabel(f.id, f.labelKey), group: toolbar.toolbarGroupOf(f.id), control: toolbar.filterControlOf(f), values: toolbar.filterValuesField(f), presets: toolbar.rangePresets(f, now).map(p => ({id: p.id, label: i18n.t(p.label.id, p.label.values), predicates: p.predicates}))})),
      sortLabels: parsed.sorts.map(x => ({id: x.id, label: fieldLabel(x.id, x.labelKey), directions: {asc: directionLabel(x.id, 'asc'), desc: directionLabel(x.id, 'desc')}})),
      quickLabels: parsed.quickFilters.map(q => ({labelKey: q.labelKey, label: quickFilterLabel(q.labelKey)})),
    });
  }
  const durationField = {id: 'durationSeconds', type: 'number', operators: ['at-least', 'at-most', 'between'], controlHint: 'number-range'};
  const presets = toolbar.rangePresets(durationField, now);
  const active = [[], presets[0].predicates, presets[2].predicates, [{field: 'durationSeconds', operator: 'at-least', value: 1}]].map(predicates => ({predicates, active: toolbar.activeRangePreset(presets, predicates) ?? ''}));
  const anchors = [['', 'title', 'No value'], ['A', 'title', ''], ['#', 'title', ''], ['2019', 'year', ''], ['1990s', 'year', ''], ['2026-09', 'added', ''], ['2026-13', 'added', ''], ['2026', 'lastPlayed', ''], ['8', 'communityRating', ''], ['3', 'personalRating', ''], ['90', 'duration', ''], ['120', 'duration', ''], ['30', 'duration', ''], ['0', 'duration', ''], ['x', 'duration', ''], ['Q', 'unknown', '']].map(([key, sortField, noValue]) => ({key, sortField, noValue, label: browse.formatBrowseAnchor(key, sortField, noValue)}));
  const valueLabels = ['sdr', 'HDR10', 'hdr10+', 'dolby_vision', 'dolby-vision', '4k', 'UHD', 'fhd', '1080P', '720p', '1999', 'in_progress', 'not-started', 'Drama', 'science fiction', ''].map(value => ({value, label: toolbar.browseValueLabel(value)}));
  const yearField = {id: 'year'};
  const ordering = [{field: yearField, values: [{value: '1990'}, {value: '2020'}, {value: '1950'}, {value: '2000'}]}, {field: {id: 'genre'}, values: [{value: 'b'}, {value: 'a'}]}].map(c => ({...c, order: toolbar.orderFilterValues(c.field, c.values).map(v => v.value)}));

  // Projections: each library's Discover and the entity pages, as asked for and as asked for wrongly.
  const sectionOut = x => ({id: x.id, type: x.type, heading: x.heading, ids: x.entries.map(e => e.id), totalCount: x.totalCount, nextCursor: x.nextCursor, ...(x.start === undefined ? {} : {start: x.start}), ...(x.seeAll ? {seeAll: x.seeAll} : {})});
  const projectionOut = p => ({heading: p.heading, scope: p.scope, revision: p.revision, query: p.query, sorts: p.sorts, sections: p.sections.map(sectionOut), ...(p.entity ? {entity: p.entity.id} : {}), ...(p.empty ? {empty: p.empty} : {})});
  const projections = [];
  for (const name of names.filter(n => /-discover\.json$|^entity-/.test(n))) {
    const raw = load(name);
    const route = {libraryId: raw.scope.libraryId, view: raw.scope.view, ...(raw.scope.entityId ? {entityId: raw.scope.entityId} : {})};
    const bound = {serverId: raw.scope.serverId, viewerId: 'viewer'};
    const variants = [
      ['as asked', raw, route, bound.serverId],
      ['another server', raw, route, 'srv_other'],
      ['another library', raw, {...route, libraryId: 'elsewhere'}, bound.serverId],
      ['another view', raw, {...route, view: route.view === 'discover' ? 'browse' : 'discover', entityId: undefined}, bound.serverId],
    ];
    const first = raw.sections.find(x => x.entries.length > 1);
    // The broken variants repeat the whole document: one Discover and one entity page carry them.
    const carries = name === names.find(n => /-discover\.json$/.test(n)) || name === names.find(n => /^entity-/.test(n));
    if (first && carries) {
      const broken = (label, breaker) => { const copy = clone(raw); breaker(copy, copy.sections.find(x => x.id === first.id)); variants.push([label, copy, route, bound.serverId]); };
      broken('duplicate entry', (c, x) => { x.entries.push(x.entries[0]); x.totalCount += 1; });
      broken('total below entries', (c, x) => { x.totalCount = x.entries.length - 1; });
      broken('entry of another library', (c, x) => { x.entries[0].libraryId = 'elsewhere'; });
      broken('entry of a future kind is left out', (c, x) => { x.entries[0].kind = 'hologram'; });
      broken('unknown section type', (c, x) => { x.type = 'carousel'; });
      broken('heading with params', (c, x) => { x.heading = {key: 'home.row.becauseYouWatched', fallback: 'Because you watched Heat', params: {title: 'Heat'}}; });
      broken('heading malformed', (c, x) => { x.heading = {key: '', fallback: 'x'}; });
      broken('see all', (c, x) => { x.seeAll = {pivot: 'movies', sort: [{field: 'added', direction: 'desc'}], query: {field: 'genre', operator: 'contains-any', value: ['Drama']}}; });
      broken('see all with an unreadable query', (c, x) => { x.seeAll = {pivot: 'movies', sort: [{field: 'added', direction: 'desc'}], query: {field: 'genre', operator: 'roughly', value: 1}}; });
      broken('see all without a sort', (c, x) => { x.seeAll = {pivot: 'movies', sort: []}; });
      broken('search mode unknown', c => { c.query.searchMode = 'fuzzy'; });
      broken('limit past the page size', c => { c.query.limit = 41; });
      broken('revision missing', c => { delete c.revision.viewer; });
    }
    for (const [label, value, expected, serverId] of variants) {
      const asked = Object.fromEntries(Object.entries(expected).filter(([, v]) => v !== undefined));
      const result = attempt(() => projectionOut(validateContentProjection(value, asked, {serverId, viewerId: 'viewer'}, 40)));
      projections.push({name: `${name}: ${label}`, raw: value, route: asked, serverId, ok: result.ok, ...(result.ok ? {value: result.value} : {})});
    }
  }
  const ids = Object.keys(enUS).filter(id => /^(lib\.|filter\.|library\.|sort\.|title\.|home\.row\.|shelf\.)/.test(id));
  write('library.json', {now: Math.floor(now.getTime() / 1000), catalogue: Object.fromEntries(ids.map(id => [id, enUS[id]])), tabs, tabFor, pivotFor, releases, capabilities, results, facets, toolbars, presets: {field: durationField, active}, anchors, valueLabels, ordering, projections});
}
// ── Title pages: detail.ts, show-workspace.ts, people.ts, recommendations.ts, container-state.ts,
//    presentation/title-page.ts, detail-actions.ts, entry-actions.ts, title-files.ts, language.ts ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const detailModule = await import('../../portico-server/packages/client-core/src/detail.ts');
  const {ShowWorkspaceService} = await import('../../portico-server/packages/client-core/src/show-workspace.ts');
  const people = await import('../../portico-server/packages/client-core/src/people.ts');
  const recommendations = await import('../../portico-server/packages/client-core/src/recommendations.ts');
  const containers = await import('../../portico-server/packages/client-core/src/container-state.ts');
  const page = await import('../../portico-server/packages/client-core/src/presentation/title-page.ts');
  const {detailActions} = await import('../../portico-server/packages/client-core/src/presentation/detail-actions.ts');
  const {entryActions} = await import('../../portico-server/packages/client-core/src/presentation/entry-actions.ts');
  const files = await import('../../portico-server/packages/client-core/src/presentation/title-files.ts');
  const language = await import('../../portico-server/packages/client-core/src/presentation/language.ts');
  const facts = await import('../../portico-react-native/apps/native/src/screens/title/facts.ts');
  const {createI18n, enUS} = await import('../../portico-server/packages/i18n/src/index.ts');
  const i18n = createI18n({uiLocale: 'en-US', formatLocale: 'en-US', timeZone: 'UTC', hour12: true});
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const attempt = async work => { try { return {ok: true, value: await work()}; } catch { return {ok: false}; } };
  const clone = v => JSON.parse(JSON.stringify(v));
  const requestId = async () => '11111111-2222-4333-8444-555555555555';

  // The detail projection is read through the service (its parser is not exported).
  const readDetail = async (raw, serverId, target) => {
    const service = new detailModule.DetailService({api: {request: async () => raw}, scope: {serverId, viewerId: 'viewer'}, requestId});
    await service.select(target);
    const snapshot = service.getSnapshot();
    service.dispose();
    if (!snapshot.data) throw new Error('refused');
    return snapshot.data;
  };
  const languageNames = new Intl.DisplayNames('en', {type: 'language'});
  const languageName = code => { const key = language.languageKey(code) || code; const known = enUS[`language.${key}`]; if (known) return known; try { return languageNames.of(key) ?? key; } catch { return key; } };
  const groupOut = groups => groups.map(g => ({id: g.id, actions: g.actions.map(a => ({id: a.id, label: a.label, icon: a.icon, ...(a.selected === undefined ? {} : {selected: a.selected})}))}));
  const detailOut = d => ({
    scope: d.scope, revision: d.revision,
    item: Object.fromEntries(Object.entries(d.item).filter(([k]) => k !== 'sources')),
    personal: {watchlisted: d.personal.watchlisted, favorite: d.personal.favorite, rating: d.personal.rating, revision: d.personal.revision, watched: d.personal.watched, progressSeconds: d.personal.progressSeconds, lastPlayedAt: d.personal.lastPlayedAt, status: d.personal.status, conflicts: d.personal.conflicts.length},
    actions: d.actions,
    metadata: {status: d.metadata.status, ratings: d.metadata.ratings.map(r => ({provider: r.provider, value: r.value, max: r.max})), genres: d.metadata.genres, credits: d.metadata.credits, ...(d.metadata.creditTotals ? {creditTotals: d.metadata.creditTotals} : {})},
    ...(d.facts ? {facts: d.facts} : {}), ...(d.files ? {files: d.files} : {}),
    ...(d.related ? {related: d.related.rows.map(r => ({id: r.id, relation: r.relation, heading: r.heading, ids: r.entries.map(e => e.id)}))} : {}),
    ...(d.extras ? {extras: d.extras.map(x => ({type: x.type, label: x.label, ids: x.items.map(e => e.id)}))} : {}),
  });
  const pageOf = d => {
    const actions = detailActions(d, {platform: 'tv'});
    const credits = d.metadata.credits;
    const crew = credits.filter(c => !facts.isActing(c.department));
    return {
      actions: {primary: actions.primary ? {id: actions.primary.id, label: actions.primary.label, remaining: actions.primary.remaining ?? '', playback: actions.primary.playback} : null, quick: actions.quick, more: groupOut(actions.more)},
      cast: credits.filter(c => facts.isActing(c.department)).map(c => c.id),
      keyCrew: facts.keyCrew(crew).map(c => c.id),
      directors: page.dedupeNames(facts.namesIn(crew, ['directing']), 3), writers: page.dedupeNames(facts.namesIn(crew, ['writing']), 3),
      genres: page.dedupeNames(d.metadata.genres.map(g => g.name)),
      related: page.relatedRowsForPage(d.related?.rows ?? []).map(r => r.id),
      files: (d.files ?? []).map(file => files.titleFileLines(file, (id, values) => i18n.t(id, values), languageName)),
    };
  };
  const details = [];
  for (const name of ['item-movie-detail.json', 'item-episode-detail.json']) {
    const raw = load(name);
    if (!raw) continue;
    const target = {libraryId: raw.scope.libraryId, itemId: raw.scope.itemId};
    const variants = [['as asked', raw, raw.scope.serverId, target], ['another server', raw, 'srv_other', target], ['another library', raw, raw.scope.serverId, {...target, libraryId: 'elsewhere'}], ['another item', raw, raw.scope.serverId, {...target, itemId: 'elsewhere'}]];
    const broken = (label, breaker) => { const copy = clone(raw); breaker(copy); variants.push([label, copy, raw.scope.serverId, target]); };
    broken('rating out of range', c => { c.personal.rating = 5.5; });
    broken('rating in quarter stars', c => { c.personal.rating = 3.25; });
    broken('rating in half stars', c => { c.personal.rating = 3.5; c.personal.watchlisted = true; c.personal.favorite = true; });
    broken('watched and resumable', c => { c.personal.watched = true; c.item.progressSeconds = 0; });
    broken('in progress', c => { c.item.progressSeconds = Math.floor(c.item.duration / 3); c.actions = c.actions.map(a => (a.playback ? {...a, playback: {...a.playback, startSeconds: a.id === 'start_over' ? 0 : Math.floor(c.item.duration / 3)}} : a)); });
    broken('play past the end', c => { const a = c.actions.find(x => x.playback); if (a) a.playback.startSeconds = c.item.duration + 1; else c.item.duration = -1; });
    broken('play for another item', c => { const a = c.actions.find(x => x.playback); if (a) a.playback.itemId = 'elsewhere'; else c.item.duration = -1; });
    broken('duplicate action', c => { c.actions.push(c.actions[0]); });
    broken('actions disabled', c => { c.actions = c.actions.map(a => ({...a, enabled: false})); });
    broken('metadata status unknown', c => { c.metadata.status = 'maybe'; });
    broken('rating above its maximum', c => { c.metadata.ratings = [{provider: 'tmdb', value: 11, max: 10, sourceUrl: '', observedAt: ''}]; });
    broken('ratings of three kinds', c => { c.metadata.ratings = [{provider: 'tmdb', value: 7.84, max: 10, sourceUrl: '', observedAt: ''}, {provider: 'critic', value: 91.4, max: 100, sourceUrl: '', observedAt: ''}, {provider: 'imdb', value: 8, max: 10, sourceUrl: '', observedAt: '', votes: 12}]; });
    broken('credit portrait elsewhere', c => { c.metadata.credits = [{id: 'c1', name: 'A', role: 'B', department: 'Acting', provider: 'tmdb', portraitUrl: '/v1/metadata/item/other/art/portrait?x=1'}]; });
    broken('crew of every rank', c => { c.metadata.credits = [['c1', 'Ann', 'Property Master', 'Art'], ['c2', 'Bob', 'Executive Producer', 'Production'], ['c3', 'Cy', 'Original Music Composer', 'Sound'], ['c4', 'Di', 'Creator', 'Creator'], ['c5', 'Ed', 'Screenplay', 'Writing'], ['c6', 'Flo', 'Director', 'Directing'], ['c7', 'Flo', 'Writer', 'Writing'], ['c8', 'Gus', 'Hero', 'Acting'], ['c9', 'Hal', '', 'Production'], ['c10', 'Ivy', 'Novel', 'Writing'], ['c11', 'Jo', 'Co-Director', 'Crew'], ['c12', 'Kit', 'Producer', 'Production'], ['c13', 'Lu', 'Associate Producer', 'Production']].map(([id, name, role, department]) => ({id, name, role, department, provider: 'tmdb', ...(id === 'c7' ? {personId: 'p-flo'} : id === 'c6' ? {personId: 'p-flo'} : {})})); });
    broken('facts and files', c => { c.facts = {contentRating: 'PG-13', studio: 'A24', network: 'Anime', tagline: 'One line.', releaseDate: '2021-09-15', originalTitle: c.item.title.toUpperCase(), country: 'US', edition: '', nothing: 'x'}; c.files = [{id: 'f1', path: '/media/a.mkv', size: 58200000000, container: 'mkv', duration: 9300, bitRate: 62000000, available: true, video: {codec: 'hevc', width: 3840, height: 2160, dynamicRange: 'dolby_vision', frameRate: 23.976, bitDepth: 10}, audio: [{codec: 'truehd', language: 'eng', channels: 8, channelLayout: '7.1', objectAudio: 'atmos', default: true}, {codec: 'ac3', language: 'fra', title: 'Français', channels: 6}, {codec: 'aac', title: 'Commentary', channels: 2}, {codec: 'weird', language: 'und', channels: 3}], subtitles: [{codec: 'subrip', language: 'en', title: 'English - SDH', external: true}, {codec: 'hdmv_pgs_subtitle', language: 'spa', forced: true}, {codec: 'ass', language: 'ja', title: 'Subtitles'}]}, {id: 'f2', size: 1500000000, container: 'mp4', duration: 9300, bitRate: 640000, available: false, video: {codec: 'h264', width: 1280, height: 720, dynamicRange: 'hdr10', hdr10Plus: true, frameRate: 24}, audio: [{codec: 'aac', channelLayout: 'mono'}], subtitles: []}]; });
    broken('file malformed', c => { c.files = [{id: 'f1', size: -1, container: 'mkv', duration: 1, available: true}]; });
    broken('extras', c => { c.extras = [{type: 'trailer', label: 'Trailers', items: [{id: 'x1', kind: 'extra', title: 'Trailer', duration: 120, playback: {itemId: 'x1'}}]}]; });
    broken('extras of an unknown type', c => { c.extras = [{type: 'bloopers', label: 'Bloopers', items: [{id: 'x1', kind: 'extra', title: 'B', playback: {itemId: 'x1'}}]}]; });
    broken('extra that is the title itself', c => { c.extras = [{type: 'trailer', label: 'Trailers', items: [{id: c.item.id, kind: 'extra', title: 'T', playback: {itemId: c.item.id}}]}]; });
    broken('related for another library', c => { c.related = {version: 1, libraryId: 'elsewhere', libraryName: 'X', rows: []}; });
    broken('overview with a control character', c => { c.item.overview = 'a\u0001b'; });
    broken('personal missing', c => { delete c.personal; });
    for (const [label, value, serverId, where] of variants) {
      const result = await attempt(() => readDetail(value, serverId, where));
      details.push({name: `${name}: ${label}`, raw: value, serverId, target: where, ok: result.ok, ...(result.ok ? {value: detailOut(result.value), page: pageOf(result.value)} : {})});
    }
  }

  const creditPages = [];
  const creditRaw = load('item-movie-credits.json');
  const movieRaw = load('item-movie-detail.json');
  if (creditRaw && movieRaw) for (const [label, value, itemId, group] of [['as asked', creditRaw, movieRaw.scope.itemId, 'cast'], ['another group', creditRaw, movieRaw.scope.itemId, 'crew'], ['empty cursor', {...creditRaw, nextCursor: ''}, movieRaw.scope.itemId, 'cast'], ['with a cursor', {...creditRaw, nextCursor: 'c2'}, movieRaw.scope.itemId, 'cast']]) {
    const result = await attempt(() => detailModule.parseCreditPage(value, itemId, group));
    creditPages.push({name: label, raw: value, itemId, group, ok: result.ok, ...(result.ok ? {value: {credits: result.value.credits, total: result.value.total, nextCursor: result.value.nextCursor ?? ''}} : {})});
  }

  // Entry menus: the same capabilities as the TypeScript and the channel name them.
  const menuCases = [
    {ts: {}, bs: {}},
    {ts: {playable: true}, bs: {playable: true}},
    {ts: {playable: true, progressSeconds: 300, queue: true}, bs: {playable: true, progressSeconds: 300, queue: true}},
    {ts: {kind: 'movie', playable: true, watchlisted: false, favorite: true, watched: false, rating: null, addToPlaylist: true, addToCollection: true, details: true}, bs: {kind: 'movie', playable: true, watchlisted: false, favorite: true, watched: false, hasRating: true, addToPlaylist: true, addToCollection: true, details: true}},
    {ts: {kind: 'book', watchlisted: true, favorite: false, watched: true, rating: 4, details: true}, bs: {kind: 'book', watchlisted: true, favorite: false, watched: true, hasRating: true, rating: 4, details: true}},
    {ts: {kind: 'album', playable: true, favorite: false, watched: false, continueWatching: true}, bs: {kind: 'album', playable: true, favorite: false, watched: false, continueWatching: true}},
    {ts: {kind: 'show', notInterested: true, details: true}, bs: {kind: 'show', notInterested: true, details: true}},
    // In a Watch Together group that lets this viewer add.
    {ts: {kind: 'movie', playable: true, group: true, watchlisted: false}, bs: {kind: 'movie', playable: true, group: true, watchlisted: false}},
    {ts: {kind: 'show', group: true, details: true}, bs: {kind: 'show', group: true, details: true}},
  ].map(c => ({caps: c.bs, groups: groupOut(entryActions(c.ts))}));

  // The show workspace is read through its service too.
  const readShow = async (raw, serverId, route) => {
    const service = new ShowWorkspaceService({api: {request: async () => raw}, scope: {serverId, viewerId: 'viewer'}});
    await service.select(route);
    const snapshot = service.getSnapshot();
    service.dispose();
    if (!snapshot.data) throw new Error('refused');
    return snapshot.data;
  };
  const showOut = d => ({scope: d.scope, revision: d.revision, show: d.show, seasons: d.seasons, seasonTotalCount: d.seasonTotalCount, groups: d.groups.map(g => ({id: g.id, title: g.title, total: g.count})), selected: d.selected, settings: d.settings, episodes: d.episodes.sections.flatMap(x => x.entries.map(e => e.id)), ...(d.nextUp ? {nextUp: d.nextUp.id} : {})});
  const showPage = d => {
    const peopleOf = page.showPeople(d.show.credits);
    const entries = d.episodes.sections[0]?.entries ?? [];
    return {
      cast: peopleOf.cast.map(c => c.name), crew: peopleOf.crew.map(c => c.name),
      creditLines: page.showCreditLines(peopleOf.crew, (role, names) => i18n.t(role === 'creator' ? 'title.createdBy' : role === 'director' ? 'title.directedBy' : 'title.writtenBy', {names})),
      seasons: facts.orderSeasons(d.seasons).map(x => ({id: x.id, label: facts.seasonLabel(i18n, x)})),
      nextUp: facts.nextUpIn(entries)?.id ?? null,
      episodes: entries.map(e => ({id: e.id, code: facts.episodeCode(i18n, e), fraction: facts.resumeFraction(e) ?? null})),
      network: page.networkName(d.show.network) ?? '', original: page.originalTitleLine(d.show.title, d.show.originalTitle) ?? '',
    };
  };
  const shows = [];
  for (const name of ['show-workspace.json', 'show-workspace-season.json']) {
    const raw = load(name);
    if (!raw) continue;
    const base = {libraryId: raw.scope.libraryId, showId: raw.show.id};
    const route = name.includes('season') ? {...base, selectedSeasonId: raw.selected.seasonId} : base;
    const variants = [['as asked', raw, raw.scope.serverId, route], ['another server', raw, 'srv_other', route], ['another show', raw, raw.scope.serverId, {...route, showId: 'elsewhere'}], ['another season asked for', raw, raw.scope.serverId, {...base, selectedSeasonId: 'elsewhere'}], ['a group asked for', raw, raw.scope.serverId, {...base, group: 'all'}], ['an episode asked for', raw, raw.scope.serverId, {...base, episodeId: 'elsewhere'}]];
    const broken = (label, breaker) => { const copy = clone(raw); breaker(copy); variants.push([label, copy, raw.scope.serverId, route]); };
    broken('poster from elsewhere', c => { c.show.posterUrl = '/v1/metadata/show/other/art/poster?x=1'; });
    broken('logo from elsewhere is dropped', c => { c.show.logoUrl = '/v1/metadata/show/other/art/logo?x=1'; });
    broken('credits', c => { c.showCredits = [{name: 'Zed', role: 'Lead', department: 'Acting', ordinal: 2, id: 'p1'}, {name: 'Amy', ordinal: 1}, {name: 'Vince', role: 'Creator', department: 'Creator', ordinal: 9, id: 'p2'}, {name: 'Vince', role: 'Director', department: 'Directing', ordinal: 10, id: 'p2'}, {name: 'Wes', role: 'Writer', department: 'Writing', ordinal: 3}, {name: 'Xi', role: 'Executive Producer', ordinal: 4}, {name: 'Yo', role: 'Gaffer', department: 'Lighting', ordinal: 5}, {name: '', role: 'x'}, 7]; c.show.network = 'Anime'; c.show.originalTitle = c.show.title.toLowerCase(); c.show.genres = ['Drama', '', 3, 'Crime']; });
    broken('flat by ranges', c => { c.settings = {hideSeasons: false, absoluteNumbering: true, ranges: true, newestFirst: false, revision: 3}; });
    broken('season of another show', c => { if (c.seasons[0]) c.seasons[0].showId = 'other'; else c.seasonTotalCount = -1; });
    broken('season total below the page', c => { c.seasonTotalCount = c.seasons.length - 1; });
    broken('an episode that is not one', c => { const x = c.episodes.sections[0]; if (x?.entries[0]) x.entries[0].kind = 'movie'; else c.revision.catalog = -1; });
    broken('episodes at another revision', c => { c.episodes.revision.catalog += 1; });
    broken('next up malformed is dropped', c => { c.nextUp = {id: '', kind: 'episode', title: 'x'}; });
    broken('next up that is a movie is dropped', c => { c.nextUp = {id: 'm1', kind: 'movie', title: 'x'}; });
    broken('provider link elsewhere', c => { c.show.providerSourceUrl = 'https://example.com/tv/1'; });
    broken('provider link', c => { c.show.providerSourceUrl = 'https://www.themoviedb.org/tv/1'; });
    for (const [label, value, serverId, where] of variants) {
      const result = await attempt(() => readShow(value, serverId, where));
      shows.push({name: `${name}: ${label}`, raw: value, serverId, route: where, ok: result.ok, ...(result.ok ? {value: showOut(result.value), page: showPage(result.value)} : {})});
    }
  }

  const persons = [];
  for (const [name, role] of [['person.json', 'all'], ['person-cast.json', 'cast']]) {
    const raw = load(name);
    if (!raw) continue;
    const request = {role, limit: 40, personId: raw.person.id};
    const variants = [['as asked', raw, raw.serverId, request], ['another server', raw, 'srv_other', request], ['another person', raw, raw.serverId, {...request, personId: 'elsewhere'}], ['crew asked for', raw, raw.serverId, {...request, role: 'crew'}]];
    const broken = (label, breaker) => { const copy = clone(raw); breaker(copy); variants.push([label, copy, raw.serverId, request]); };
    broken('total below the page', c => { c.pageInfo.total = c.credits.length - 1; });
    broken('a cursor on a short page', c => { c.pageInfo.nextCursor = 'c2'; c.credits = c.credits.slice(0, 3); c.pageInfo.total = 9; });
    broken('biography with line breaks', c => { c.person.biography = 'One.\n\nTwo.'; c.person.birthDate = '1962-07-03'; c.person.deathDate = ''; });
    broken('name empty', c => { c.person.name = ''; });
    for (const [label, value, serverId, asked] of variants) {
      const result = await attempt(() => people.parsePersonPage(value, {serverId, viewerId: 'viewer'}, asked));
      persons.push({name: `${name}: ${label}`, raw: value, serverId, request: asked, ok: result.ok, ...(result.ok ? {value: {person: {id: result.value.person.id, name: result.value.person.name, biography: result.value.person.biography, birthDate: result.value.person.birthDate, deathDate: result.value.person.deathDate, portraitUrl: result.value.person.portraitUrl, roles: result.value.person.roles, knownFor: result.value.person.knownFor.map(e => e.id)}, credits: result.value.credits.map(c => ({id: c.media.id, role: c.role, character: c.character, department: c.department, creditKind: c.creditKind})), total: result.value.pageInfo.total, nextCursor: result.value.pageInfo.nextCursor}} : {})});
    }
  }
  const personPaths = [['p 1', 'all', ''], ['p1', 'cast', 'c=2']].map(([id, role, cursor]) => ({id, role, cursor, path: people.personPath(id, {role, limit: 40, ...(cursor ? {cursor} : {})})}));

  const rows = [];
  for (const [name, field] of [['item-movie-recommendations.json', 'itemId'], ['show-recommendations.json', 'showId']]) {
    const raw = load(name);
    if (!raw) continue;
    const validate = field === 'itemId' ? recommendations.validateItemRecommendations : recommendations.validateShowRecommendations;
    const variants = [['as asked', raw, raw[field]], ['another title', raw, 'elsewhere']];
    if (raw.rows[0]) {
      const echo = clone(raw); echo.rows[0].entries[0].id = raw[field]; variants.push(['a row that echoes its title', echo, raw[field]]);
      const bare = clone(raw); delete bare.rows[0].relation; variants.push(['a row without a relation', bare, raw[field]]);
      const twice = clone(raw); twice.rows.push(twice.rows[0]); variants.push(['a row twice', twice, raw[field]]);
    }
    for (const [label, value, id] of variants) {
      const result = await attempt(() => validate(value, id));
      rows.push({name: `${name}: ${label}`, raw: value, field, id, ok: result.ok, ...(result.ok ? {value: recommendations.titleRecommendationRows(result.value).map(r => ({id: r.id, ids: r.entries.map(e => e.id)})), shown: page.relatedRowsForPage(recommendations.titleRecommendationRows(result.value)).map(r => r.id)} : {})});
    }
  }

  // Container state: the parser is private; the reads are made through a stub API.
  const states = [];
  for (const name of ['container-show.json', 'container-album.json']) {
    const raw = load(name);
    if (!raw) continue;
    const kind = name.includes('show') ? 'show' : 'album';
    const variants = [['as read', raw], ['an unknown field', {...raw, extra: 1}], ['no counts', Object.fromEntries(Object.entries(raw).filter(([k]) => k !== 'watchedCount'))], ['flags', {...raw, watchlisted: true, favorite: true}], ['flag of the wrong type', {...raw, favorite: 'yes'}]];
    for (const [label, value] of variants) {
      const result = await attempt(() => containers.getContainerState({request: async () => value}, kind, 'c1'));
      states.push({name: `${name}: ${label}`, raw: value, counts: true, ok: result.ok, ...(result.ok ? {value: {revision: result.value.revision, watched: result.value.watched, watchlisted: result.value.watchlisted, favorite: result.value.favorite, watchedCount: result.value.watchedCount, unwatchedCount: result.value.unwatchedCount, ...(result.value.libraryId ? {libraryId: result.value.libraryId} : {})}} : {})});
    }
    const written = await attempt(() => containers.setContainerFlag({request: async () => ({revision: 4, watched: false, watermark: 'w', favorite: true})}, kind, 'c1', 'favorite', true));
    states.push({name: `${name}: a write's answer`, raw: {revision: 4, watched: false, watermark: 'w', favorite: true}, counts: false, ok: written.ok, ...(written.ok ? {value: {revision: 4, watched: false, watchlisted: false, favorite: true}} : {})});
  }
  const carries = [];
  for (const kind of ['show', 'season', 'album', 'book', 'artist', 'movie', '']) for (const flag of ['watched', 'watchlisted', 'favorite']) carries.push({kind, flag, carries: containers.containerCarries(kind, flag)});

  const names = [['Drama', 'drama ', ' Crime', '', 'Thriller', 'War'], [], ['A', 'a', 'B']].map(list => ({list, three: page.dedupeNames(list), twenty: page.dedupeNames(list, 20)}));
  const ranks = [['Directing', ''], ['Writing', 'Screenplay'], ['Crew', 'Screenplay'], ['Creator', ''], ['Sound', 'Original Music Composer'], ['Music', ''], ['Production', ''], ['Production', 'Producer'], ['Production', 'Casting'], ['Art', 'Property Master'], [' DIRECTING ', ''], ['Crew', 'Co-Director']].map(([department, role]) => ({department, role, rank: facts.crewRank(department, role)}));
  const progress = [[undefined, 3], [0, 0], [6, 4], [0, 10]].map(([w, u]) => ({watched: w ?? null, unwatched: u ?? null, progress: page.seasonProgress(w, u) ?? null}));
  const pins = [[undefined, {id: 'a'}, 1], [{id: 'a'}, {id: 'a'}, 1], [{id: 'b', seasonNumber: 2}, {id: 'a'}, 1], [{id: 'b', seasonNumber: 1}, {id: 'a'}, 1], [{id: 'b'}, {id: 'a'}, undefined], [{id: 'b'}, undefined, 1]].map(([nextUp, first, season]) => ({nextUp: nextUp ?? null, first: first ?? null, season: season ?? null, pin: page.nextUpPin(nextUp, first, season)?.id ?? null}));
  const years = [[1965, 1970], [1996, undefined], [undefined, 2000], [undefined, undefined]].map(([b, e]) => ({begin: b ?? null, end: e ?? null, label: page.activeYearsLabel(b, e, y => i18n.t('title.activeSince', {year: y})) ?? ''}));
  const factLines = [[['2019', '', undefined, 107, false, 'PG'], ['', undefined], [0, 'x']]].flat().map(parts => ({parts: parts.map(p => (p === undefined ? null : p)), line: facts.factsLine(parts)}));
  const tracks = [{language: 'fra', title: 'Français'}, {language: 'fr', title: 'French'}, {language: 'en', title: 'English - SDH'}, {language: 'en', title: 'English (Forced)'}, {language: 'eng', title: 'Director\'s commentary'}, {language: 'ja', title: 'Subtitles'}, {language: 'und', title: 'Track 2'}, {title: 'Commentary'}, {language: 'zxx'}, {language: 'de'}, {language: 'pt-BR', title: 'Brazilian'}, {}].map(track => ({track, name: language.trackName(track, 'en'), key: language.languageKey(track.language)}));
  const ids = Object.keys(enUS).filter(id => /^(title\.|entry\.|action\.|quality\.|mediaInfo\.|count\.|language\.|duration\.)/.test(id));
  write('title.json', {catalogue: Object.fromEntries(ids.map(id => [id, enUS[id]])), details, creditPages, menus: menuCases, shows, persons, personPaths, rows, states, carries, names, ranks, progress, pins, years, factLines, tracks});
}
// ── Search and Saved: search.ts, presentation/search-model.ts, saved.ts, personal-saved.ts ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const {SearchService, searchPath, searchQueryProblem} = await import('../../portico-server/packages/client-core/src/search.ts');
  const model = await import('../../portico-server/packages/client-core/src/presentation/search-model.ts');
  const {SavedService, savedListPath} = await import('../../portico-server/packages/client-core/src/saved.ts');
  const {PersonalSavedService} = await import('../../portico-server/packages/client-core/src/personal-saved.ts');
  const {enUS} = await import('../../portico-server/packages/i18n/src/index.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const clone = v => JSON.parse(JSON.stringify(v));
  const requestId = async () => '11111111-2222-4333-8444-555555555555';
  const attempt = async work => { try { return {ok: true, value: await work()}; } catch { return {ok: false}; } };

  const readSearch = async (raw, serverId, q, group) => {
    const service = new SearchService({api: {request: async () => raw}, scope: {serverId, viewerId: 'viewer'}});
    await service.select(q, group);
    const snapshot = service.getSnapshot();
    service.dispose();
    if (!snapshot.data) throw new Error('refused');
    return snapshot.data;
  };
  const groupOut = g => ({id: g.id, title: g.title, status: g.status, errorCode: g.errorCode, ids: g.items.map(e => e.id), totalCount: g.totalCount, hasMore: g.hasMore, nextCursor: g.nextCursor});
  const searches = [];
  for (const [name, group] of [['search.json', undefined], ['search-the.json', undefined], ['search-movies.json', 'movies']]) {
    const raw = load(name);
    if (!raw) continue;
    const q = raw.query.q;
    const variants = [['as asked', raw, raw.scope.serverId, q, group], ['another server', raw, 'srv_other', q, group], ['other words', raw, raw.scope.serverId, q + ' x', group], ['another group asked for', raw, raw.scope.serverId, q, group ? undefined : 'shows']];
    const broken = (label, breaker) => { const copy = clone(raw); breaker(copy); variants.push([label, copy, raw.scope.serverId, q, group]); };
    const full = raw.groups.find(g => g.items.length > 0);
    broken('a group failed', c => { const g = c.groups.find(x => x.items.length === 0) ?? c.groups[c.groups.length - 1]; g.status = 'error'; g.errorCode = 'search_group_timeout'; g.items = []; g.totalCount = 0; g.hasMore = false; g.nextCursor = ''; });
    broken('a failed group with results', c => { const g = c.groups.find(x => x.id === full?.id) ?? c.groups[0]; g.status = 'error'; g.errorCode = 'search_group_timeout'; });
    broken('a success with a failure code', c => { c.groups[0].errorCode = 'search_group_unavailable'; });
    broken('has more without a cursor', c => { c.groups[0].hasMore = true; });
    broken('a group twice', c => { c.groups.push(c.groups[0]); });
    broken('a group not asked for', c => { c.query.groups = c.query.groups.slice(1); });
    broken('an unavailable group without a reason', c => { c.capabilities.groups[0].available = false; delete c.capabilities.groups[0].reason; });
    broken('people', c => { const g = c.groups.find(x => x.id === 'people'); if (g) { g.items = [{id: 'p1', kind: 'person', title: 'Ann Lee', subtitle: 'Actor', count: 3, navigation: {view: 'person', entityId: 'p1'}}]; g.totalCount = 1; } });
    broken('a person with a library', c => { const g = c.groups.find(x => x.id === 'people'); if (g) { g.items = [{id: 'p1', kind: 'person', title: 'Ann Lee', libraryId: 'l', navigation: {view: 'person', entityId: 'p1'}}]; g.totalCount = 1; } else c.revision.catalog = -1; });
    broken('recorded when not asked', c => { c.query.recorded = true; });
    broken('a sections field', c => { c.sections = []; });
    if (full) broken('an entry of another kind', c => { c.groups.find(x => x.id === full.id).items[0].kind = 'show'; });
    for (const [label, value, serverId, words, wanted] of variants) {
      const result = await attempt(() => readSearch(value, serverId, words, wanted));
      const top = result.ok && !wanted ? model.topSearchResult(words, result.value.groups) : undefined;
      searches.push({name: `${name}: ${label}`, raw: value, serverId, asked: {q: words, ...(wanted ? {group: wanted} : {})}, ok: result.ok, ...(result.ok ? {groups: result.value.groups.map(groupOut), ordered: model.orderedSearchGroups(result.value.groups).map(g => g.id), top: top ? {group: top.group, id: top.entry.id} : null} : {})});
    }
  }
  const entry = (id, title) => ({id, kind: 'movie', title});
  const tops = [
    ['heat', [{id: 'movies', items: [entry('1', 'Heat'), entry('2', 'Heat 2')]}]],
    ['heat', [{id: 'movies', items: [entry('1', 'Heat')]}, {id: 'shows', items: [entry('3', 'Heat')]}]],
    ['the wire', [{id: 'shows', items: [entry('1', 'The Wire: Extended'), entry('2', 'Thewire')]}]],
    ['blade', [{id: 'movies', items: [entry('1', 'Blade Runner')]}, {id: 'albums', items: [entry('2', 'Blade II')]}]],
    ['bl', [{id: 'movies', items: [entry('1', 'Bl Something')]}]],
    ['a', [{id: 'movies', items: [entry('1', 'A')]}]],
    ['Spider-Man', [{id: 'movies', items: [entry('1', 'Spider Man'), entry('2', 'Spider-Man 2')]}]],
    ['heat', [{id: 'episodes', items: [entry('1', 'Heat')]}, {id: 'songs', items: [entry('2', 'Heat')]}]],
  ].map(([query, groups]) => { const top = model.topSearchResult(query, groups); return {query, groups, top: top ? {group: top.group, id: top.entry.id} : null}; });
  const searchable = ['', 'a', 'ab', ' a b ', 'a b c d e f g h i', 'star   wars', '!!', 'x'.repeat(129), 'x'.repeat(128), 'é', 'éa', '1 2', '12'].map(q => ({q, searchable: searchQueryProblem(q.trim().slice(0, 128)) === undefined && q.trim() !== ''}));
  const paths = [['star wars', undefined, undefined], ['a&b', 'movies', undefined], ['x y', 'live-tv', 'c=1']].map(([q, group, cursor]) => ({q, group: group ?? '', cursor: cursor ?? '', path: searchPath({q, ...(group ? {group} : {})}, 40, cursor)}));
  const chips = model.SEARCH_CHIPS.map(c => ({id: c.id, label: c.label}));
  const kinds = ['movies', 'shows', 'episodes', 'artists', 'albums', 'songs', 'books', 'people', 'live-tv'].map(group => ({group, label: model.topResultKindLabel(group) ?? model.searchGroupLabel(group)}));

  const readSaved = async (raw, serverId, route) => {
    const service = new SavedService({api: {request: async () => raw}, scope: {serverId, viewerId: 'viewer'}, requestId});
    await service.select(route);
    const snapshot = service.getSnapshot();
    service.dispose();
    if (!snapshot.projection) throw new Error('refused');
    return snapshot.projection;
  };
  const savedOut = p => ({view: p.scope.view, sections: p.sections.map(x => ({id: x.id, type: x.type, title: x.heading.fallback, ids: x.entries.map(e => e.id), totalCount: x.totalCount, nextCursor: x.nextCursor})), sorts: p.sorts, sort: p.query.sort, direction: p.query.direction, emptyTitle: p.empty?.fallback ?? '', viewerFence: p.scope.viewerFence, revision: p.revision});
  const saved = [];
  for (const [name, view] of [['saved-watchlist.json', 'watchlist'], ['saved-favorites.json', 'favorites'], ['saved-playlists.json', 'playlists']]) {
    const raw = load(name);
    if (!raw) continue;
    const route = {view};
    const variants = [['as asked', raw, raw.scope.serverId, route], ['another server', raw, 'srv_other', route], ['another view', raw, raw.scope.serverId, {view: view === 'watchlist' ? 'favorites' : 'watchlist'}], ['another sort asked for', raw, raw.scope.serverId, view === 'playlists' ? route : {view, sort: 'elsewhere'}]];
    const broken = (label, breaker) => { const copy = clone(raw); breaker(copy); variants.push([label, copy, raw.scope.serverId, route]); };
    broken('a limit other than forty', c => { c.query.limit = 20; });
    broken('a search inside saved', c => { c.query.q = 'x'; });
    broken('a library scope', c => { c.scope.libraryId = 'l'; });
    broken('a playlist card', c => { if (view === 'playlists') { c.sections = [{id: 'playlists', type: 'list', heading: {key: 'saved.playlists', fallback: 'Playlists'}, entries: [{id: 'pl1', kind: 'playlist', title: 'Road trip', subtitle: 'For the drive', count: 12, navigation: {view: 'playlist', entityId: 'pl1'}}, {id: 'pl2', kind: 'playlist', title: 'Empty', navigation: {view: 'playlist', entityId: 'pl2'}}], totalCount: 2, nextCursor: ''}]; } else c.sections = [{id: 'x', type: 'grid', heading: {key: 'k', fallback: 'F'}, entries: [{id: 'pl1', kind: 'playlist', title: 'Road trip', navigation: {view: 'playlist', entityId: 'pl1'}}], totalCount: 1, nextCursor: ''}]; });
    broken('a playlist card that plays', c => { c.sections = [{id: 'playlists', type: 'list', heading: {key: 'saved.playlists', fallback: 'Playlists'}, entries: [{id: 'pl1', kind: 'playlist', title: 'Road trip', playback: {itemId: 'x'}, navigation: {view: 'playlist', entityId: 'pl1'}}], totalCount: 1, nextCursor: ''}]; });
    broken('total below the page', c => { if (c.sections[0]) c.sections[0].totalCount = -1; else c.revision.catalog = -1; });
    for (const [label, value, serverId, asked] of variants) {
      const result = await attempt(() => readSaved(value, serverId, asked));
      saved.push({name: `${name}: ${label}`, raw: value, serverId, selected: asked, ok: result.ok, ...(result.ok ? {value: savedOut(result.value)} : {})});
    }
  }
  const savedPaths = [['watchlist', undefined, undefined, undefined], ['favorites', 'added', 'desc', undefined], ['watchlist', 'title', 'asc', 'c=2']].map(([view, sort, direction, cursor]) => ({view, sort: sort ?? '', direction: direction ?? '', cursor: cursor ?? '', path: savedListPath(view, {...(sort ? {sort} : {}), ...(direction ? {direction} : {}), ...(cursor ? {cursor} : {})})}));

  const readPersonal = async (raw, serverId, route) => {
    const service = new PersonalSavedService({request: async () => raw}, {serverId, viewerId: 'viewer'}, requestId);
    await service.select(route);
    const snapshot = service.getSnapshot();
    service.dispose();
    if (snapshot.error) throw new Error('refused');
    return snapshot;
  };
  const personal = [];
  const history = load('saved-history.json');
  if (history) {
    const variants = [['as read', history, history.serverId], ['another server', history, 'srv_other']];
    const broken = (label, breaker) => { const copy = clone(history); breaker(copy); variants.push([label, copy, history.serverId]); };
    broken('an entry twice', c => { c.entries.push(c.entries[0]); });
    broken('a negative position', c => { c.entries[0].positionSeconds = -1; });
    broken('no revision', c => { delete c.revision; });
    for (const [label, value, serverId] of variants) {
      const result = await attempt(() => readPersonal(value, serverId, {view: 'history'}));
      personal.push({name: `history: ${label}`, kind: 'history', raw: value, serverId, ok: result.ok, ...(result.ok ? {value: {entries: result.value.entries.map(e => ({id: e.id, media: e.media.id, updatedAt: e.updatedAt, positionSeconds: e.positionSeconds, completed: e.completed})), nextCursor: result.value.nextCursor, revision: result.value.revision, viewerFence: result.value.viewerFence}} : {})});
    }
  }
  const resourceRow = (id, kind, extra = {}) => ({serverId: 'srv_1', viewerFence: 'fence-1', id, kind, name: kind === 'view' ? 'Unwatched dramas' : 'Favourites of 1999', summary: '', visibility: 'private', revision: 3, entryCount: kind === 'view' ? 0 : 12, role: 'owner', status: 'ready', pinned: false, pinRevision: 0, actions: ['pin', 'update', 'delete'], invalidComponents: [], shares: [], ...(kind === 'view' ? {definition: {libraryId: 'lib1', pivot: 'movies', query: null, sort: [{field: 'title', direction: 'asc'}], presentation: 'grid'}} : {}), ...extra});
  const lists = [
    ['collections', 'collection', {serverId: 'srv_1', viewerFence: 'fence-1', revision: 2, resources: [resourceRow('c1', 'collection'), resourceRow('c2', 'collection', {visibility: 'server', name: 'Family films', summary: 'For everyone'})], nextCursor: ''}],
    ['collections with a view in it', 'collection', {serverId: 'srv_1', viewerFence: 'fence-1', revision: 2, resources: [resourceRow('v1', 'view')], nextCursor: ''}],
    ['views', 'view', {serverId: 'srv_1', viewerFence: 'fence-1', revision: 2, resources: [resourceRow('v1', 'view')], nextCursor: 'c2'}],
    ['a viewer who may update', 'collection', {serverId: 'srv_1', viewerFence: 'fence-1', revision: 2, resources: [resourceRow('c1', 'collection', {role: 'viewer'})], nextCursor: ''}],
    ['another fence', 'collection', {serverId: 'srv_1', viewerFence: 'fence-2', revision: 2, resources: [resourceRow('c1', 'collection')], nextCursor: ''}],
    ['a blank name', 'collection', {serverId: 'srv_1', viewerFence: 'fence-1', revision: 2, resources: [resourceRow('c1', 'collection', {name: '  '})], nextCursor: ''}],
  ];
  for (const [label, kind, raw] of lists) {
    const result = await attempt(() => readPersonal(raw, 'srv_1', {view: kind === 'view' ? 'views' : 'collections'}));
    personal.push({name: `resources: ${label}`, kind, raw, serverId: 'srv_1', ok: result.ok, ...(result.ok ? {value: {resources: result.value.resources.map(r => ({id: r.id, kind: r.kind, name: r.name, summary: r.summary, visibility: r.visibility, entryCount: r.entryCount})), nextCursor: result.value.nextCursor}} : {})});
  }
  const media = (id, extra = {}) => ({id, libraryId: 'lib1', kind: 'movie', title: 'Movie ' + id, ...extra});
  const contents = [
    ['a collection', {resource: resourceRow('c1', 'collection'), entries: [{id: 'e1', hidden: false, media: media('m1')}, {id: 'e2', hidden: true}, {id: 'e3', hidden: false, media: media('m3')}], nextCursor: 'c2'}],
    ['a hidden entry that says more', {resource: resourceRow('c1', 'collection'), entries: [{id: 'e2', hidden: true, media: media('m2')}], nextCursor: ''}],
    ['another resource', {resource: resourceRow('c9', 'collection'), entries: [], nextCursor: ''}],
    ['a saved view', {resource: resourceRow('c1', 'view'), nextCursor: '', browse: {pivot: 'movies', applied: {query: null, sort: [{field: 'title', direction: 'asc'}]}, entries: [media('m1'), media('m2')], pageInfo: {start: 0, total: 5, revision: 'r1', hasMore: true, nextCursor: 'b2'}}}],
    ['a saved view on another pivot', {resource: resourceRow('c1', 'view'), nextCursor: '', browse: {pivot: 'shows', applied: {query: null, sort: [{field: 'title', direction: 'asc'}]}, entries: [], pageInfo: {start: 0, total: 0, revision: 'r1', hasMore: false, nextCursor: ''}}}],
  ];
  for (const [label, raw] of contents) {
    const result = await attempt(() => readPersonal(raw, 'srv_1', {view: 'resource', resourceId: 'c1'}));
    personal.push({name: `content: ${label}`, kind: 'content', raw, serverId: 'srv_1', resourceId: 'c1', ok: result.ok, ...(result.ok ? {value: {entries: result.value.entries.map(e => ({id: e.id, hidden: e.hidden, ...(e.media ? {media: e.media.id} : {})})), nextCursor: result.value.nextCursor, name: result.value.resource.name}} : {})});
  }
  const ids = Object.keys(enUS).filter(id => /^(search\.|saved\.|web\.search\.|web\.saved\.|shelf\.|lib\.|relative\.|title\.|count\.)/.test(id));
  write('saved.json', {catalogue: Object.fromEntries(ids.map(id => [id, enUS[id]])), searches, tops, searchable, paths, chips, kinds, saved, savedPaths, personal});
}
// ── Playback v1: playback-v1/types.ts, capability-profile.ts and client-profile.ts ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const types = await import('../../portico-server/packages/client-core/src/playback-v1/types.ts');
  const {rokuDeclaredProfile} = await import('../../portico-server/packages/client-core/src/client-profile.ts');
  const {capabilityProfileFromClient} = await import('../../portico-server/packages/client-core/src/playback-v1/capability-profile.ts');
  const {qualityLadder} = await import('../../portico-server/packages/client-core/src/playback-v1/quality.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const clone = v => JSON.parse(JSON.stringify(v));
  const attempt = work => { try { return {ok: true, value: work()}; } catch { return {ok: false}; } };
  const optionsOut = o => ({itemId: o.itemId, kind: o.kind, resume: o.resume ?? null, versions: o.versions.map(v => ({id: v.id, label: v.label, edition: v.edition ?? null, container: v.container ?? null, durationMs: v.durationMs, parts: v.parts.map(p => ({id: p.id, index: p.index, durationMs: p.durationMs})), video: v.video.map(x => x.id), audio: v.audio.map(a => ({id: a.id, codec: a.codec, channels: a.channels ?? null, language: a.language ?? null, title: a.title ?? null, atmos: a.atmos, isDefault: a.default})), subtitles: v.subtitles.map(x => ({id: x.id, format: x.format, source: x.source, language: x.language ?? null, forced: x.forced, sdh: x.sdh, isDefault: x.default}))})), chapters: o.chapters.map(c => ({startMs: c.startMs, title: c.title})), markers: o.markers, preferred: o.preferred ?? null, plan: o.plan ? {versionId: o.plan.versionId, mode: o.plan.mode, streams: o.plan.streams} : null});
  const options = [];
  for (const name of ['item-movie-playback-options.json', 'item-episode-playback-options.json', 'item-song-playback-options.json']) {
    const raw = load(name);
    if (!raw) continue;
    const variants = [['as read', raw]];
    const broken = (label, breaker) => { const copy = clone(raw); breaker(copy); variants.push([label, copy]); };
    broken('an item id with a space', c => { c.itemId = 'a b'; });
    broken('a version without an id', c => { if (c.versions[0]) delete c.versions[0].id; else c.itemId = ''; });
    broken('tracks and markers', c => { const v = c.versions[0]; if (v) { v.audio = [{id: 'a1', codec: 'truehd', channels: 8, layout: '7.1', atmos: true, language: 'en', title: 'English', default: true}, {id: 'a2', codec: 'ac3', channels: 6, language: 'fr', commentary: true}]; v.subtitles = [{id: 's1', format: 'pgs', source: 'embedded', language: 'en', sdh: true}, {id: 's2', format: 'srt', source: 'elsewhere', forced: true, default: true}]; } c.markers = [{id: 'm1', type: 'intro', startMs: 30000, endMs: 90000, confidence: 'detected', automaticSafe: true}, {id: 'm2', type: 'bumper', startMs: 1, endMs: 2}]; c.chapters = [{startMs: 0, title: 'One'}, {startMs: 60000, title: 'Two', thumbnail: '/v1/x'}]; c.resume = {positionMs: 1234000, partIndex: 0}; });
    broken('a preferred audio that is not an id', c => { c.preferred = {versionId: c.versions[0]?.id ?? 'v', audioId: 'a b', reason: 'x'}; });
    broken('a plan in an unknown mode', c => { c.plan = {versionId: c.versions[0]?.id ?? 'v', mode: 'teleport', streams: [{id: 'v0', action: 'beam', reasons: ['x', 3]}]}; });
    broken('trickplay from elsewhere', c => { c.trickplay = {url: 'ftp://x', intervalMs: 1}; });
    for (const [label, value] of variants) {
      const result = attempt(() => optionsOut(types.parseOptions(value)));
      options.push({name: `${name}: ${label}`, raw: value, ok: result.ok, ...(result.ok ? {value: result.value} : {})});
    }
  }
  const sessionOut = x => ({id: x.id, revision: x.revision, kind: x.kind, role: x.role, state: x.state, itemId: x.itemId ?? null, versionId: x.versionId ?? null, queue: x.queue ?? null, reportEveryMs: x.lease.reportEveryMs, presentation: {generation: x.presentation.generation, mode: x.presentation.mode, url: x.presentation.url, startPositionMs: x.presentation.startPositionMs, subtitles: x.presentation.subtitles, decision: Object.fromEntries(Object.entries(x.presentation.decision).filter(([, d]) => d).map(([k, d]) => [k, {action: d.action, reasons: d.reasons, ...(d.to ? {to: d.to} : {}), ...(d.channels ? {channels: d.channels} : {})}])), bitrateKbps: x.presentation.bitrateKbps ?? null}, endReason: x.end?.reason ?? null, endMessage: x.end?.message ?? null});
  const sessions = [];
  for (const name of ['playback-session.json', 'playback-session-limited.json']) {
    const raw = load(name);
    if (!raw) continue;
    const variants = [['as read', raw]];
    const broken = (label, breaker) => { const copy = clone(raw); breaker(copy); variants.push([label, copy]); };
    broken('no presentation', c => { delete c.presentation; });
    broken('a url from nowhere', c => { c.presentation.url = 'file:///etc/passwd'; });
    broken('a negative generation', c => { c.presentation.generation = -1; });
    broken('an empty revision', c => { c.revision = ''; });
    broken('a stream with subtitles and a decision', c => { c.presentation.mode = 'stream'; c.presentation.url = '/v1/media/g/3/master.m3u8'; c.presentation.subtitles = [{trackId: 's1', format: 'webvtt', url: '/v1/media/g/3/subs/s1.vtt'}]; c.presentation.decision = {video: {action: 'copy', reasons: []}, audio: {action: 'transcode', to: 'eac3', channels: 6, reasons: ['audio_codec_unsupported']}, subtitles: {action: 'sidecar'}}; c.presentation.bitrateKbps = 8000; c.lease = {reportEveryMs: 10000}; });
    broken('a subtitle from nowhere', c => { c.presentation.subtitles = [{trackId: 's1', format: 'webvtt', url: 'data:x'}]; });
    broken('ended by an administrator', c => { c.state = 'ended'; c.end = {reason: 'terminated', message: 'Bedtime.'}; });
    broken('in a queue', c => { c.queue = {queueId: 'q1', entryId: 'e1'}; c.kind = 'hologram'; });
    broken('a queue entry that is not an id', c => { c.queue = {queueId: 'q1', entryId: 'e 1'}; });
    for (const [label, value] of variants) {
      const result = attempt(() => sessionOut(types.parseSession(value)));
      sessions.push({name: `${name}: ${label}`, raw: value, ok: result.ok, ...(result.ok ? {value: result.value} : {})});
    }
  }
  const queueOut = q => ({id: q.id, revision: q.revision, total: q.total, repeat: q.repeat, shuffled: !!q.shuffle, current: q.current ?? null, upcoming: q.next ? {available: q.next.available, reason: q.next.reason, ...(q.next.entryId ? {entryId: q.next.entryId} : {})} : null, postPlay: q.postPlay ? {autoplay: q.postPlay.autoplay, countdownSeconds: q.postPlay.countdownSeconds, passoutCheckDue: q.postPlay.passoutCheckDue} : null});
  const entryOut = e => ({entryId: e.entryId, position: e.position, itemId: e.itemId, kind: e.kind, title: e.title, available: e.available, durationMs: e.durationMs ?? null, albumId: e.albumId ?? null});
  const queues = [];
  for (const name of ['playback-queue.json', 'playback-queue-advance.json']) {
    const raw = load(name);
    if (!raw) continue;
    const variants = [['as read', raw]];
    const broken = (label, breaker) => { const copy = clone(raw); breaker(copy); variants.push([label, copy]); };
    broken('no total', c => { delete c.queue.total; });
    broken('shuffled, repeating, at its end', c => { c.queue.shuffle = {seed: 's', lap: 0}; c.queue.repeat = 'all'; c.queue.next = {entryId: null, available: false, reason: 'end'}; });
    broken('an unavailable entry', c => { c.window = [{entryId: 'e9', position: 9, available: false, kind: 'pending', title: ''}]; });
    broken('an available entry without an item', c => { c.window = [{entryId: 'e9', position: 9, kind: 'track', title: 'x'}]; });
    broken('the header alone', c => { for (const k of Object.keys(c)) if (k !== 'queue') delete c[k]; Object.assign(c, c.queue); delete c.queue; });
    for (const [label, value] of variants) {
      const result = attempt(() => { const header = types.obj(value) && value.queue !== undefined ? value.queue : value; return {queue: queueOut(types.parseQueue(header)), window: Array.isArray(value.window) ? value.window.map(e => entryOut(types.parseEntry(e))) : [], session: value.session !== undefined ? types.parseSession(value.session).id : null}; });
      queues.push({name: `${name}: ${label}`, raw: value, ok: result.ok, ...(result.ok ? {value: result.value} : {})});
    }
  }
  const profiles = [{uhd: true, osVersion: '14.0', model: '4800X'}, {uhd: false, osVersion: '13.5', model: '3930X'}].map(o => { const profile = rokuDeclaredProfile(o); return {facts: {model: o.model, osVersion: o.osVersion, uhd: o.uhd, av1: false, dolbyVision: false, hdr10: false, hlg: false, surround: false}, profile, capability: capabilityProfileFromClient(profile, {form: 'tv', network: {class: 'local'}})}; });
  write('playback.json', {options, sessions, queues, profiles, ladder: qualityLadder, receipt: load('playback-client-profile-receipt.json') ?? null});
}
// ── Settings: presentation/settings-structure.ts, preferences.ts, server-admin/* ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const structure = await import('../../portico-server/packages/client-core/src/presentation/settings-structure.ts');
  const {parsePreferenceSnapshot, preferenceValue} = await import('../../portico-server/packages/client-core/src/preferences.ts');
  const {preferenceValueLabel} = await import('../../portico-server/packages/client-core/src/presentation/preference-copy.ts');
  const types = await import('../../portico-server/packages/client-core/src/playback-v1/types.ts');
  const playing = await import('../../portico-server/packages/client-core/src/server-admin/now-playing.ts');
  const dashboard = await import('../../portico-server/packages/client-core/src/server-admin/dashboard.ts');
  const words = await import('../../portico-server/packages/client-core/src/server-admin/console-words.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const clone = v => JSON.parse(JSON.stringify(v));
  const attempt = work => { try { return {ok: true, value: work()}; } catch { return {ok: false}; } };
  const raw = load('preferences-television.json');
  const snapshot = raw ? parsePreferenceSnapshot(raw.data) : undefined;
  const keys = snapshot ? snapshot.registry.fields.map(f => f.key) : [];

  // The structure a television shows, for the viewers there are.
  const capabilitySets = [
    {}, {localAccount: true, deviceName: true, manageSignIn: true}, {localAccount: true, porticoMember: true, deviceName: true, manageSignIn: false},
    {hostedAccount: true, deviceName: true}, {localAccount: true, hostedAccount: true, downloads: true, deviceName: true, liveTV: true}, {liveTV: false},
    // A Roku: its player has one speed and renders no audio effects.
    {localAccount: true, deviceName: true, playbackSpeed: false, audioEffects: false}, {playbackSpeed: true, audioEffects: false}, {playbackSpeed: false, audioEffects: true},
  ];
  const structures = [];
  for (const owner of [false, true]) for (const [index, capabilities] of capabilitySets.entries()) for (const withKeys of owner && index === 1 ? ['none', 'all', 'some'] : ['none']) {
    const preferenceKeys = withKeys === 'none' ? undefined : withKeys === 'all' ? keys : keys.filter((_, i) => i % 3 === 0);
    structures.push({context: {owner, capabilities: {...capabilities, ...(preferenceKeys ? {preferenceKeys} : {})}}, expected: structure.settingsStructure({owner, platform: 'tv', capabilities: {...capabilities, ...(preferenceKeys ? {preferenceKeys: new Set(preferenceKeys)} : {})}})});
  }
  const full = structure.settingsStructure({owner: true, platform: 'tv', capabilities: {localAccount: true, deviceName: true}});
  const addresses = ['profile', 'playback', 'server-dashboard', 'dashboard', 'nowhere', ''].map(address => { const found = structure.findSettingsPage(full, address || undefined); return {address, heading: found?.heading.id ?? null, page: found?.page.id ?? null}; });

  // The registry: what the parser keeps, each value in words, and broken documents.
  const preferences = [];
  const labels = [];
  if (raw && snapshot) {
    const out = s => ({deviceClass: s.deviceClass, order: s.registry.fields.map(f => f.key), documents: s.documents.map(d => ({scope: d.scope, revision: d.revision})), effective: s.effective, defaults: Object.fromEntries(s.registry.fields.map(f => [f.key, f.default])), scopes: Object.fromEntries(s.registry.fields.map(f => [f.key, f.scopes]))});
    const push = (name, document) => { const r = attempt(() => parsePreferenceSnapshot(document.data)); preferences.push({name, document, ok: r.ok, expected: r.ok ? out(r.value) : null}); };
    push('as served', raw);
    const broken = (name, change) => { const copy = clone(raw); change(copy.data); push(name, copy); };
    broken('a device class that is not one', d => { d.deviceClass = 'watch'; });
    broken('no fields', d => { d.registry.fields = []; });
    broken('a field of a type this client does not know', d => { d.registry.fields[0].type = 'colour'; });
    broken('a field listed twice', d => { d.registry.fields.push(clone(d.registry.fields[0])); });
    broken('one document', d => { d.documents = d.documents.slice(0, 1); });
    broken('a boolean that is text', d => { const f = d.registry.fields.find(x => x.type === 'boolean'); d.effective[f.key] = 'yes'; });
    broken('a list with a repeat', d => { const f = d.registry.fields.find(x => x.type === 'languageList'); if (f) d.effective[f.key] = ['en', 'en']; else d.deviceClass = 'watch'; });
    broken('an effective value missing', d => { delete d.effective[d.registry.fields[0].key]; });
    for (const field of snapshot.registry.fields) {
      for (const value of field.allowedValues ?? []) labels.push({key: field.key, value, label: preferenceValueLabel(field.key, value)});
      if (typeof field.default === 'number') labels.push({key: field.key, value: field.default, label: preferenceValueLabel(field.key, field.default)});
    }
    for (const [key, value] of [['quality.local.maxVideoHeight', 4320], ['quality.local.maxVideoHeight', 2160], ['quality.wifi.maxVideoHeight', 1080], ['quality.local.mode', 'data-saver'], ['made.upSeconds', 12], ['made.upSpeed', 1], ['made.upSpeed', 1.5], ['made.upKbps', 320], ['made.upMbps', 8], ['made.upPercent', 90], ['made.upEpisodes', 3], ['made.up', 7], ['made.up', 'someValue'], ['made.up', 'data-saver']]) labels.push({key, value, label: preferenceValueLabel(key, value)});
  }

  // Composites: what each shows for stored values, and what each choice writes.
  const composites = [];
  if (snapshot) {
    const ids = ['quality.home', 'quality.away', 'quality.cellular', 'playbackMethod', 'hdr', 'cardSize'];
    const variants = [{}, {'quality.local.mode': 'original'}, {'quality.local.maxVideoHeight': 1080}, {'quality.wifi.maxVideoHeight': 720, 'quality.unknown.maxVideoHeight': 2160}, {'quality.wifi.mode': 'data-saver'}, {'quality.local.mode': 'standard'}, {'quality.local.maxVideoBitrateMbps': 8}, {'quality.local.maxVideoBitrateMbps': 1}, {'quality.local.maxVideoBitrateMbps': 25},
      {'delivery.directPlay': 'never'}, {'delivery.transcode': 'never'}, {'delivery.directPlay': 'require', 'delivery.transcode': 'never'},
      {'quality.local.allowHDR': false}, {'quality.local.allowHDR': false, 'quality.wifi.allowHDR': false, 'quality.cellular.allowHDR': false, 'quality.unknown.allowHDR': false},
      {'appearance.cardSizePercent': 85}, {'appearance.cardSizePercent': 125}, {'quality.cellular.maxVideoHeight': 480}];
    for (const variant of variants) {
      const values = {...snapshot.effective, ...variant};
      const read = key => (snapshot.registry.fields.some(f => f.key === key) ? values[key] : undefined);
      composites.push({change: variant, read: Object.fromEntries(ids.map(id => [id, structure.readComposite(id, read)]))});
    }
    var patches = [];
    for (const id of ['quality.home', 'quality.away', 'quality.cellular']) for (const choice of ['automatic', 'original', '2160', '1080', '720', '480']) patches.push({id, choice, patch: structure.compositePatch(id, choice)});
    for (const choice of ['automatic', 'original', 'convert', 'other']) patches.push({id: 'playbackMethod', choice, patch: structure.compositePatch('playbackMethod', choice)});
    for (const choice of ['automatic', 'off']) patches.push({id: 'hdr', choice, patch: structure.compositePatch('hdr', choice)});
    for (const choice of ['small', 'medium', 'large']) patches.push({id: 'cardSize', choice, patch: structure.compositePatch('cardSize', choice)});
  }

  // The Dashboard: sessions (the server's, and made ones: none are playing when fixtures are fetched), health, load, alerts, tasks.
  const sessionsRaw = load('admin-sessions.json') ?? {items: []};
  const made = [
    {id: 's1', user: {id: 'u1', name: 'justin'}, profile: {id: 'p1', name: 'Justin'}, device: {id: 'd1', name: 'Living Room'}, item: {id: 'i1', title: 'Arrival'}, kind: 'vod', state: 'playing', positionMs: 1000, decision: {video: {action: 'direct'}, audio: {action: 'direct'}}, bitrateKbps: 8400, location: 'local', startedAt: '2026-10-03T04:05:00Z'},
    {id: 's2', user: 'sam', profile: 'sam', device: 'Phone', title: 'Severance', kind: 'vod', state: 'paused', positionMs: 0, decision: {video: {action: 'transcode'}, audio: {action: 'copy'}}, bandwidthKbps: 12500, bitrateKbps: 4000, location: 'remote'},
    {id: 's3', user: '', profile: '', device: '', itemId: 'i3', title: '', kind: 'audio', state: 'buffering', positionMs: 0, decision: {audio: {action: 'transcode'}}, location: 'elsewhere'},
    {id: 's4', user: 'ana', profile: 'Kids', device: 'TV', title: 'Bluey', kind: 'channel', state: 'ended', positionMs: 0, decision: {video: {action: 'copy'}, subtitles: {action: 'burn'}}, bitrateKbps: 960, location: 'local'},
    {id: 's5', user: 'ana', profile: 'ana', device: 'TV', title: 'Song', kind: 'audio', state: 'preparing', positionMs: 0, decision: {}, location: 'local'},
  ];
  const t = (id, values) => `${id}${values ? JSON.stringify(values) : ''}`;
  const sessionsOut = list => list.map(x => ({id: x.id, user: x.user, profile: x.profile, device: x.device, itemId: x.itemId ?? null, title: x.title, kind: x.kind, state: x.state, location: x.location, startedAt: x.startedAt ?? null,
    delivery: playing.deliveryId(x.decision) ?? '', stateId: playing.stateId(x.state) ?? '', locationId: playing.locationId(x.location) ?? '', rate: playing.rateMbps(x) ?? '', viewer: playing.sessionViewer(x, t)}));
  const sessions = [{name: 'as served', document: sessionsRaw}, {name: 'made', document: {items: made}}, {name: 'no list', document: {page: {}}}, {name: 'a session without an id', document: {items: [{title: 'x'}]}}].map(c => { const r = attempt(() => types.parsePage(c.document, types.parseAdminSession).items); return {...c, ok: r.ok, expected: r.ok ? sessionsOut(r.value) : null}; });
  const health = load('admin-panel-health.json'), storage = load('admin-panel-storage.json'), telemetry = load('admin-telemetry-1h.json'), alerts = load('admin-alerts.json'), jobs = load('admin-jobs.json');
  const healthCases = [];
  if (health && storage) {
    const push = (name, h, s) => healthCases.push({name, health: h, storage: s, expected: dashboard.healthFacts(h?.data, s?.data)});
    push('as served', health, storage);
    const h2 = clone(health); h2.data.facts.database = {state: 'degraded', value: null}; push('a database that needs attention', h2, storage);
    const h3 = clone(health); delete h3.data.facts.uptime; push('no uptime', h3, storage);
    const s2 = clone(storage); s2.data.facts.stateVolumeAvailable = {state: 'unavailable', value: null}; push('no free space figure', health, s2);
    push('no storage', health, undefined);
  }
  const loadCases = [];
  if (telemetry) {
    const push = (name, doc) => loadCases.push({name, document: doc, expected: dashboard.measuredLoadTiles(doc.data.status).map(tile => ({metric: tile.metric, label: tile.label, value: dashboard.loadValue(tile, doc.data.status[tile.metric])}))});
    push('as served', telemetry);
    const all = clone(telemetry); for (const [name, value] of [['cpu', 12.4], ['memory', 99.5], ['netOut', 1536], ['diskRead', 52428800], ['gpuUsage', 0], ['gpuEncoder', 71.5]]) all.data.status[name] = {status: 'available', value}; push('every figure measured', all);
    const none = clone(telemetry); for (const name of Object.keys(none.data.status)) none.data.status[name].status = 'unavailable'; push('nothing measured', none);
  }
  const alertWords = ['state-permissions', 'backup_failed', 'low_storage', 'database_degraded', 'something.newHere'].map(code => ({code, label: words.alertLabel({code})}));
  const jobWords = ['library_scan', 'scan', 'metadata_refresh', 'analysis', 'somethingNew_here'].map(kind => ({kind, label: words.jobLabel(kind)}));
  const jobStates = Object.entries(words.jobStateLabel).map(([state, label]) => ({state, label}));
  const durations = [0, 12, 59.6, 60, 2447, 3600, 86399, 86400, 200000].map(seconds => ({seconds, text: words.duration(seconds)}));
  // The words the tests need (the off-device run has no translations).
  const {enUS} = await import('../../portico-server/packages/i18n/src/index.ts');
  const prefixes = ['pref.', 'settings.', 'preferences.', 'locale.', 'language.', 'web.nowPlaying.', 'web.telemetry.', 'server.', 'web.console.', 'action.', 'entry.resume'];
  const catalogue = Object.fromEntries(Object.entries(enUS).filter(([id]) => prefixes.some(prefix => id.startsWith(prefix))));
  write('settings.json', {catalogue, structures, addresses, preferences, labels, composites, patches: patches ?? [], sessions, health: healthCases, load: loadCases, alerts: alerts ?? null, jobs: jobs ?? null, alertWords, jobWords, jobStates, durations});
}
// ── The guide: channel-guide.ts (the server here has no sources: the guides are made) ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const guide = await import('../../portico-server/packages/client-core/src/channel-guide.ts');
  const {v1ChannelId} = await import('../../portico-server/packages/client-core/src/playback-v1/channel-control.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const clone = v => JSON.parse(JSON.stringify(v));
  const attempt = work => { try { return {ok: true, value: work()}; } catch { return {ok: false}; } };
  const at = Date.parse('2026-10-03T08:20:00Z');
  const window = guide.guideWindow(new Date(at));
  const route = kind => ({kind, start: window.start, end: window.end, timezone: 'UTC', search: '', sourceId: ''});
  const serverId = 'srv_made';
  const made = kind => ({protocolVersion: '1.0', serverId, guide: {state: 'ready', viewerFence: 'f'.repeat(64), start: window.start, end: window.end, timezone: 'UTC', nextCursor: 'c2', observedAt: '2026-10-03T08:19:30Z', days: 7,
    sources: [{id: 's1', name: 'Antenna', generation: 'g1', publishedAt: '2026-10-03T06:00:00Z', availableStart: '2026-10-03T00:00:00Z', availableEnd: '2026-10-10T00:00:00Z', provenance: kind, refreshState: 'fresh'}],
    channels: [
      {id: 'c1', sourceId: 's1', provenance: kind, name: 'One', number: '1.1', group: 'News', generation: 'g1', logoPath: '', tuneAvailable: true, recordAvailable: false, tuneUnavailableReason: '', recordUnavailableReason: 'not-recordable', favorite: true, hidden: false, preferenceRevision: 2, programmes: [
        {id: 'p1', channelId: 'c1', title: 'Morning News', start: '2026-10-03T07:30:00Z', end: '2026-10-03T08:30:00Z', lineage: 'provider-id', description: 'Headlines.', subtitle: 'Saturday', episode: {season: 3, number: 12}, flags: {live: true, new: true}, year: 2026, categories: ['News']},
        {id: 'p2', channelId: 'c1', title: 'Weather', start: '2026-10-03T08:30:00Z', end: '2026-10-03T09:00:00Z', lineage: 'interval-only', newEvidence: 'repeat', episode: {display: 'Part 2', season: 0}, flags: 'no', year: 12},
        {id: 'p3', channelId: 'c1', title: 'Late', start: '2026-10-03T10:00:00.250Z', end: '2026-10-03T12:00:00Z', lineage: 'generated'}]},
      {id: 'c2', sourceId: 's1', provenance: kind, name: 'Two', number: '2', group: '', generation: 'g1', logoPath: '/v1/items/abc_DEF-1/art/poster', tuneAvailable: false, recordAvailable: false, tuneUnavailableReason: 'source-unavailable', recordUnavailableReason: 'recording-unavailable', favorite: false, hidden: false, preferenceRevision: 0, programmes: []},
    ]}});
  const out = g => ({state: g.state, nextCursor: g.nextCursor, sources: g.sources.map(s => ({id: s.id, name: s.name, generation: s.generation})), channels: g.channels.map(c => ({id: c.id, sourceId: c.sourceId, provenance: c.provenance, name: c.name, number: c.number, group: c.group, generation: c.generation, logoPath: c.logoPath, tuneAvailable: c.tuneAvailable, tuneUnavailableReason: c.tuneUnavailableReason, favorite: c.favorite, hidden: c.hidden,
    programmes: c.programmes.map(p => ({id: p.id, channelId: p.channelId, title: p.title, start: Math.floor(Date.parse(p.start) / 1000), end: Math.floor(Date.parse(p.end) / 1000), description: p.description, subtitle: p.subtitle ?? null, episode: p.episode ?? null, flags: p.flags ?? null, year: p.year ?? null}))}))});
  const cases = [];
  const push = (name, kind, document, id = serverId) => { const r = attempt(() => guide.parseChannelGuide(document, id, route(kind))); cases.push({name, kind, serverId: id, route: route(kind), document, ok: r.ok, expected: r.ok ? out(r.value) : null}); };
  push('a live guide', 'live-source', made('live-source'));
  push('library channels', 'library-channel', made('library-channel'));
  for (const kind of ['live-source', 'library-channel']) { const served = load(`guide-${kind}.json`); if (served) cases.push((() => { const r = {kind, start: served.guide.start, end: served.guide.end, timezone: 'UTC', search: '', sourceId: ''}; const got = attempt(() => guide.parseChannelGuide(served, served.serverId, r)); return {name: `as served, ${kind}`, kind, serverId: served.serverId, route: r, document: served, ok: got.ok, expected: got.ok ? out(got.value) : null}; })()); }
  const broken = (name, change, kind = 'live-source') => { const copy = made(kind); change(copy.guide, copy); push(name, kind, copy); };
  broken('another server', (g, d) => { d.serverId = 'srv_other'; });
  broken('another protocol', (g, d) => { d.protocolVersion = '2.0'; });
  broken('a state that is not one', g => { g.state = 'asleep'; });
  broken('a window that is not the one asked for', g => { g.start = '2026-10-03T09:00:00Z'; });
  broken('an instant that is not one', g => { g.observedAt = '2026-10-03 08:19'; });
  broken('a day that does not exist', g => { g.observedAt = '2026-02-30T08:19:30Z'; });
  broken('a channel listed twice', g => { g.channels.push(clone(g.channels[1])); });
  broken('a channel of an unknown source', g => { g.channels[1].sourceId = 's9'; });
  broken('a channel of another generation', g => { g.channels[1].generation = 'g2'; });
  broken('a channel of the other kind', g => { g.channels[0].provenance = 'library-channel'; });
  broken('tunable with a reason not to', g => { g.channels[0].tuneUnavailableReason = 'source-disabled'; });
  broken('a reason that is not one', g => { g.channels[1].tuneUnavailableReason = 'because'; });
  broken('a logo from elsewhere', g => { g.channels[1].logoPath = 'https://example.com/logo.png'; });
  broken('a library channel that records', g => { g.channels[0].recordAvailable = true; g.channels[0].recordUnavailableReason = ''; }, 'library-channel');
  broken('a programme of another channel', g => { g.channels[0].programmes[0].channelId = 'c2'; });
  broken('a programme that ends before it starts', g => { g.channels[0].programmes[0].end = '2026-10-03T07:00:00Z'; });
  broken('programmes that overlap', g => { g.channels[0].programmes[1].start = '2026-10-03T08:00:00Z'; });
  broken('a programme outside the window', g => { g.channels[0].programmes[2].start = '2026-10-03T11:00:00Z'; });
  broken('a programme listed twice', g => { g.channels[0].programmes[2].id = 'p1'; });
  broken('a lineage that is not one', g => { g.channels[0].programmes[0].lineage = 'guessed'; });
  broken('a title with a control character', g => { g.channels[0].programmes[0].title = 'Bad\u0007'; });
  broken('thirty-one channels', g => { for (let i = 0; i < 29; i++) g.channels.push({...clone(g.channels[1]), id: `x${i}`}); });
  const windows = [at, Date.parse('2026-10-03T23:59:59Z'), Date.parse('2026-12-31T22:10:00Z'), 0].map(ms => ({seconds: Math.floor(ms / 1000), window: guide.guideWindow(new Date(ms))}));
  const channel = guide.parseChannelGuide(made('live-source'), serverId, route('live-source')).channels[0];
  const ids = [{kind: 'live-source', sourceId: 's1', channelId: 'c1', generation: 'g1'}, {kind: 'library-channel', sourceId: 's1', channelId: 'c9', generation: 'g4'}].map(ref => ({ref, id: v1ChannelId(ref)}));
  // A tuned channel's session (playback-v1/channel-control.ts), as the development server answered it.
  const {parseChannelSession} = await import('../../portico-server/packages/client-core/src/playback-v1/channel-control.ts');
  const tuned = load('playback-channel-session-library-channel.json');
  const sessions = [];
  if (tuned) {
    const pushSession = (name, document) => { let ok = true, expected = null; try { const s = parseChannelSession(document); const l = s.presentation.linear; const programme = p => (p ? {id: p.id, title: p.title, startMs: p.startMs, endMs: p.endMs} : null);
      expected = {id: s.id, revision: s.revision, state: s.state, generation: s.presentation.generation, url: s.presentation.url, ready: !!s.presentation.url && s.presentation.generation > 0, ended: s.state === 'ended' || !!s.end, linear: l ? {name: l.name, state: l.state, errorCode: l.errorCode ?? '', programme: programme(l.programme), upcoming: programme(l.next)} : null}; } catch { ok = false; } sessions.push({name, document, ok, expected}); };
    pushSession('as served (the stream is being prepared)', tuned);
    const alter = (name, change) => { const c = clone(tuned); change(c); pushSession(name, c); };
    alter('the stream exists', c => { c.revision = '3'; c.presentation.generation = 2; c.presentation.url = '/v1/media/<grant>/live.m3u8'; c.presentation.linear.state = 'ready'; });
    alter('paused', c => { c.state = 'paused'; });
    alter('ended by the owner', c => { c.state = 'ended'; c.end = {reason: 'terminated', message: 'Bedtime.'}; });
    alter('nothing scheduled', c => { delete c.presentation.linear.programme; delete c.presentation.linear.next; });
    alter('without a clock', c => { delete c.presentation.linear; });
    alter('a programme without a title', c => { delete c.presentation.linear.programme.title; });
    alter('a clock without a state', c => { delete c.presentation.linear.state; });
    alter('a generation that is text', c => { c.presentation.generation = '1'; });
    alter('no address field', c => { delete c.presentation.url; });
    alter('no revision', c => { delete c.revision; });
  }
  write('guide.json', {cases, windows, now: Math.floor(at / 1000), ids, channel: {id: channel.id}, sessions});
}
// ── Profile pictures: identity-restrictions.ts `parseProfileAvatar` ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const {parseProfileAvatar} = await import('../../portico-server/packages/client-core/src/identity-restrictions.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const read = raw => { if (!Array.isArray(raw?.items) || raw.items.length > 64) throw new Error('unreadable'); return raw.items.map(parseProfileAvatar).map(a => ({profileId: a.profileId, url: a.url})); };
  const one = {profileId: 'p_1-A', version: 3, updatedAt: '2026-10-01T10:00:00Z', sourceMime: 'image/jpeg', url: '/v1/profiles/p_1-A/avatar?v=3'};
  const cases = [];
  const push = (name, document) => { let expected = null, ok = true; try { expected = read(document); } catch { ok = false; } cases.push({name, document, ok, expected}); };
  const served = load('profile-avatars.json');
  if (served) push('as served', served);
  push('two pictures', {items: [one, {...one, profileId: 'p2', sourceMime: 'image/webp', url: '/v1/profiles/p2/avatar'}]});
  push('none', {items: []});
  push('no list', {avatars: []});
  push('a picture at another origin', {items: [{...one, url: 'https://example.com/a.png'}]});
  push('a path that is not a profile', {items: [{...one, url: '/v1/items/x/art/poster'}]});
  push('a type that is not an image', {items: [{...one, sourceMime: 'text/html'}]});
  push('a version of nothing', {items: [{...one, version: 0}]});
  push('an id with a slash', {items: [{...one, profileId: 'a/b'}]});
  push('a date that is not one', {items: [{...one, updatedAt: 'yesterday'}]});
  push('a field nobody asked for', {items: [{...one, owner: true}]});
  push('sixty-five pictures', {items: Array.from({length: 65}, (_, i) => ({...one, profileId: `p${i}`}))});
  write('avatars.json', {cases});
}
// ── Lyrics: lyrics.ts ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const lyrics = await import('../../portico-server/packages/client-core/src/lyrics.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const clone = v => JSON.parse(JSON.stringify(v));
  const served = load('lyrics.json');
  const cases = [], active = [], seeks = [];
  if (served) {
    const target = {itemId: served.scope.itemId, libraryId: served.scope.libraryId, sessionId: served.scope.sessionId, sessionGeneration: served.scope.sessionGeneration};
    const out = v => ({source: v.source ? {id: v.source.id, version: v.source.version, startSeconds: v.source.startSeconds, duration: v.source.duration, sourceDuration: v.source.sourceDuration} : null, selectionRevision: v.selection.revision,
      resources: v.resources.map(r => ({id: r.id, revision: r.revision, language: r.language, offsetMs: r.offsetMs, format: r.format, deleted: r.deleted, label: r.provenance.label})),
      selected: v.selection.resource ? {id: v.selection.resource.id, revision: v.selection.resource.revision, language: v.selection.resource.language, offsetMs: v.selection.resource.offsetMs, format: v.selection.resource.format, deleted: v.selection.resource.deleted, label: v.selection.resource.provenance.label, document: {format: v.selection.resource.document.format, lines: v.selection.resource.document.lines.map(l => (l.atMs === null ? {text: l.text} : {atMs: l.atMs, text: l.text}))}} : null});
    const push = (name, document, t = target) => { let expected = null, ok = true; try { expected = out(lyrics.parseLyricsView(document, {serverId: served.scope.serverId}, t)); } catch { ok = false; } cases.push({name, document, serverId: served.scope.serverId, target: t, ok, expected}); };
    const provenance = {origin: 'sidecar', providerId: '', label: 'From the album folder', rights: ''};
    const doc = {format: 'lrc', text: '[00:01.00]One\n[00:05.50]Two\n[00:05.50]\n[00:20.00]Three', embeddedOffsetMs: 0, lines: [{atMs: 1000, text: 'One'}, {atMs: 5500, text: 'Two'}, {atMs: 5500, text: ''}, {atMs: 20000, text: 'Three'}]};
    const resource = {id: 'lyr_1', revision: 2, scope: 'library', canManage: true, deleted: false, language: 'en', offsetMs: 250, format: 'lrc', digest: 'a'.repeat(64), provenance, createdAt: '2026-10-01T10:00:00Z'};
    const withLyrics = () => { const c = clone(served); c.resources = [resource, {...resource, id: 'lyr_2', language: 'ja', deleted: true, provenance: {...provenance, label: ''}}, {...resource, id: 'lyr_3', format: 'text', offsetMs: 0, provenance: {...provenance, origin: 'upload', label: 'Typed in'}}]; c.selection = {revision: 4, resource: {...resource, document: doc}}; return clone(c); };
    push('as served', served);
    push('with synced lyrics chosen', withLyrics());
    const plain = withLyrics(); plain.selection.resource = {...clone(resource), id: 'lyr_3', format: 'text', offsetMs: 0, document: {format: 'text', text: 'One\nTwo', embeddedOffsetMs: 0, lines: [{atMs: null, text: 'One'}, {atMs: null, text: 'Two'}]}}; push('with plain lyrics chosen', plain);
    const broken = (name, change) => { const c = withLyrics(); change(c); push(name, c); };
    broken('another song', c => { c.scope.itemId = 'other'; });
    broken('another session', c => { c.scope.sessionId = 'ps_other'; });
    broken('another generation', c => { c.scope.sessionGeneration = 9; });
    broken('another server', c => { c.scope.serverId = 'srv_other'; });
    broken('a chosen source that is not listed', c => { c.source.id = 'elsewhere'; });
    broken('a source listed twice', c => { c.sources.push(clone(c.sources[0])); });
    broken('lyrics without a source', c => { c.source = null; });
    broken('lyrics listed twice', c => { c.resources.push(clone(c.resources[0])); });
    broken('chosen lyrics without their words', c => { delete c.selection.resource.document; });
    broken('lines out of order', c => { c.selection.resource.document.lines[1].atMs = 500; });
    broken('a line after the song ends', c => { c.selection.resource.document.lines[3].atMs = 999000; });
    broken('plain words with times', c => { c.selection.resource.format = 'text'; c.selection.resource.offsetMs = 0; c.selection.resource.document.format = 'text'; });
    broken('a language that is not one', c => { c.resources[0].language = 'e'; });
    broken('an offset of an hour', c => { c.resources[0].offsetMs = 3600000; });
    broken('a provider that is not one', c => { c.resources[0].provenance.origin = 'guessed'; });
    broken('no lines', c => { c.selection.resource.document.lines = []; });
    push('for a song without a session', (() => { const c = clone(served); c.scope.sessionId = ''; c.scope.sessionGeneration = 0; return c; })(), {...target, sessionId: '', sessionGeneration: 0});
    push('lyrics chosen without a session', (() => { const c = withLyrics(); c.scope.sessionId = ''; c.scope.sessionGeneration = 0; return c; })(), {...target, sessionId: '', sessionGeneration: 0});
    const parsed = lyrics.parseLyricsView(withLyrics(), {serverId: served.scope.serverId}, target);
    const document = parsed.selection.resource.document;
    for (const [position, offset, start] of [[0, 0, 0], [0.99, 0, 0], [1, 0, 0], [5.5, 0, 0], [5.49, 0, 0], [19.9, 0, 0], [30, 0, 0], [1.2, 250, 0], [1.25, 250, 0], [0.5, -600, 0], [0, 0, 5.5], [-3, 0, 0]]) active.push({position, offset, start, index: lyrics.activeLyricLine(document, position, offset, start)});
    for (const [index, offset, start] of [[0, 0, 0], [3, 250, 0], [0, -2000, 0], [3, 0, 0], [1, 0, 4], [1, 0, 6]]) { const source = {...parsed.source, startSeconds: start, duration: 25}; seeks.push({line: document.lines[index], offset, source: {startSeconds: start, duration: 25}, seconds: lyrics.lyricSeekPosition(document.lines[index], offset, source)}); }
  }
  write('lyrics.json', {cases, active, seeks});
}
// ── The receiver: social-playback.ts (receiver, grant, handoff) and remote-playback.ts ──
{
  const social = await import('../../portico-server/packages/client-core/src/social-playback.ts');
  const remote = await import('../../portico-server/packages/client-core/src/remote-playback.ts');
  const clone = v => JSON.parse(JSON.stringify(v));
  const attempt = work => { try { return {ok: true, value: work()}; } catch { return {ok: false}; } };
  const receiver = {id: 'rcv_1', kind: 'portico', deviceId: 'dev-1', displayName: 'Living Room', platform: 'roku', keyFingerprint: 'f'.repeat(43), supportedCommands: ['load', 'play', 'pause', 'seek', 'stop'], grantPolicy: 'per-device', authorizationRevision: '3', state: 'active', presence: 'online', lastSeenAt: '2026-10-05T10:00:00Z', createdAt: '2026-10-01T10:00:00Z'};
  const grant = {id: 'gr_1', receiverId: 'rcv_1', controllerDeviceId: 'phone-1', controllerDisplayName: 'Justin’s iPhone', receiverKeyFingerprint: 'f'.repeat(43), allowedCommands: ['load', 'play', 'pause', 'seek', 'stop'], authorizationRevision: '3', state: 'pending', expiresAt: '2026-10-05T10:01:00Z', createdAt: '2026-10-05T10:00:00Z', decidedAt: null};
  const handoff = {id: 'ho_1', receiverId: 'rcv_1', grantId: 'gr_1', requestId: 'req-1', state: 'prepared', outcome: 'waiting', reason: '', revision: '1', itemId: 'item_1', sourcePlaybackId: 'ps_1', receiverPlaybackId: '', requestedPositionUs: '754250000', readyPositionUs: '0', committedPositionUs: '0', sourceRetired: false, createdAt: '2026-10-05T10:00:10Z', expiresAt: '2026-10-05T10:02:10Z', settledAt: null};
  const receivers = [], grants = [], handoffs = [];
  const one = (list, name, document, parse, out) => { const r = attempt(() => parse(document)); list.push({name, document, ok: r.ok, expected: r.ok ? out(r.value) : null}); };
  const receiverOut = r => ({id: r.id, deviceId: r.deviceId, displayName: r.displayName, state: r.state});
  const grantOut = g => ({id: g.id, receiverId: g.receiverId, controllerDisplayName: g.controllerDisplayName, state: g.state});
  const handoffOut = h => ({id: h.id, receiverId: h.receiverId, state: h.state, outcome: h.outcome, revision: h.revision, itemId: h.itemId, requestedPositionUs: h.requestedPositionUs, expiresAt: h.expiresAt});
  one(receivers, 'a television', receiver, social.parseReceiver, receiverOut);
  for (const [name, change] of [['a kind that is not one', r => { r.kind = 'airplay'; }], ['an id with a space', r => { r.id = 'a b'; }], ['a policy that is not one', r => { r.grantPolicy = 'never'; }], ['a revision that is a number', r => { r.authorizationRevision = 3; }], ['commands that are not text', r => { r.supportedCommands = [1]; }], ['a presence that is not one', r => { r.presence = 'asleep'; }], ['retired', r => { r.state = 'retired'; }]]) { const c = clone(receiver); change(c); one(receivers, name, c, social.parseReceiver, receiverOut); }
  one(grants, 'a phone asking', grant, social.parseReceiverGrant, grantOut);
  one(grants, 'wrapped as the server sends one', {protocolVersion: '1.0', serverTime: '', grant}, social.parseReceiverGrant, grantOut);
  for (const [name, change] of [['accepted', g => { g.state = 'accepted'; g.decidedAt = '2026-10-05T10:00:20Z'; }], ['accepted but unable to load', g => { g.state = 'accepted'; g.allowedCommands = ['pause']; }], ['a state that is not one', g => { g.state = 'maybe'; }], ['a decision time that is a number', g => { g.decidedAt = 5; }], ['no receiver', g => { delete g.receiverId; }]]) { const c = clone(grant); change(c); one(grants, name, c, social.parseReceiverGrant, grantOut); }
  one(handoffs, 'waiting for the television', handoff, social.parseHandoff, handoffOut);
  one(handoffs, 'wrapped as the server sends one', {protocolVersion: '1.0', serverTime: '', handoff}, social.parseHandoff, handoffOut);
  for (const [name, change] of [['the television is playing', h => { h.outcome = 'pending'; h.receiverPlaybackId = 'ps_tv'; h.readyPositionUs = '754250000'; }], ['pending without the television\'s playback', h => { h.outcome = 'pending'; }],
    ['committed', h => { h.state = 'committed'; h.outcome = 'accepted'; h.sourceRetired = true; h.receiverPlaybackId = 'ps_tv'; h.readyPositionUs = '754250000'; h.committedPositionUs = '754250000'; h.settledAt = '2026-10-05T10:00:30Z'; }],
    ['committed somewhere else than it was ready', h => { h.state = 'committed'; h.outcome = 'accepted'; h.sourceRetired = true; h.receiverPlaybackId = 'ps_tv'; h.readyPositionUs = '1'; h.committedPositionUs = '2'; }],
    ['retired without committing', h => { h.sourceRetired = true; }], ['accepted without committing', h => { h.outcome = 'accepted'; }], ['a position that is a number', h => { h.requestedPositionUs = 5; }], ['a position with a leading zero', h => { h.requestedPositionUs = '05'; }], ['expired', h => { h.state = 'expired'; h.outcome = 'rejected'; }], ['a state that is not one', h => { h.state = 'lost'; }]]) { const c = clone(handoff); change(c); one(handoffs, name, c, social.parseHandoff, handoffOut); }
  const delays = [[30000, 0], [30000, 0.5], [30000, 1], [60000, 0.25], [30000, -3]].map(([base, roll]) => ({base, roll, delay: remote.receiverPollDelay(base, () => roll)}));
  const starts = ['0', '999', '1000', '754250000', '12500000', '86400000000'].map(us => ({us, seconds: Number(BigInt(us) / 1000n) / 1000}));
  const micros = [0, 0.5, 12.5, 754.25, 86400, 3.9999996, -2].map(seconds => ({seconds, us: String(Math.max(0, Math.round(seconds * 1e6)))}));
  write('receiver.json', {protocol: social.SOCIAL_PROTOCOL, receivers, grants, handoffs, delays, starts, micros, receiver, grant, handoff});
}
// ── Devices: identity-devices.ts ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const {parseDevices} = await import('../../portico-server/packages/client-core/src/identity-devices.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const clone = v => JSON.parse(JSON.stringify(v));
  const out = list => list.map(d => ({id: d.id, name: d.name, platform: d.platform, ip: d.ip, lastSeen: Math.floor(Date.parse(d.lastSeen) / 1000), trusted: d.trusted, approvalState: d.approvalState, current: d.current, sessions: d.sessions}));
  const one = {id: 'dev_1', authority: 'local', installationId: 'i'.repeat(40), name: 'Living Room', platform: 'roku', app: 'Portico', appVersion: '0.1.0', ip: '192.168.1.20', firstSeen: '2026-10-01T10:00:00Z', lastSeen: '2026-10-05T10:00:00Z', trusted: true, approvalState: 'approved', lastProfileId: 'p1', rememberAccount: false, current: true, sessions: 1};
  const made = {items: [one, {...one, id: 'dev_2', installationId: 'j'.repeat(40), name: 'Justin’s iPad', platform: 'ipados', ip: '', current: false, sessions: 0, trusted: false, approvalState: 'pending', lastProfileId: ''}, {...one, id: 'dev_3', installationId: 'k'.repeat(40), name: 'Browser', platform: 'web', ip: 'fe80::1', current: false, sessions: 2}]};
  const cases = [];
  const push = (name, document) => { let expected = null, ok = true; try { expected = out(parseDevices(document)); } catch { ok = false; } cases.push({name, document, ok, expected}); };
  const served = load('devices.json');
  if (served) push('as served', served);
  push('three devices', made);
  const broken = (name, change) => { const c = clone(made); change(c); push(name, c); };
  broken('two that say they are this device', c => { c.items[1].current = true; });
  broken('a device listed twice', c => { c.items[1].id = 'dev_1'; });
  broken('an address that is not one', c => { c.items[0].ip = 'evil.example'; });
  broken('an installation id that could be guessed', c => { c.items[0].installationId = 'short'; });
  broken('no name', c => { c.items[0].name = ''; });
  broken('a state that is not one', c => { c.items[0].approvalState = 'maybe'; });
  broken('a field nobody asked for', c => { c.items[0].owner = true; });
  broken('a list with something beside it', c => { c.total = 3; });
  broken('a time that is not one', c => { c.items[0].lastSeen = 'today'; });
  broken('more sessions than there can be', c => { c.items[0].sessions = 5000; });
  broken('an authority that is not one', c => { c.items[0].authority = 'guest'; });
  broken('a name with a control character', c => { c.items[0].name = 'TV\u0007'; });
  write('devices.json', {cases});
}
// ── Notifications: notifications.ts ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const notes = await import('../../portico-server/packages/client-core/src/notifications.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const clone = v => JSON.parse(JSON.stringify(v));
  const data = raw => (raw && typeof raw === 'object' && 'data' in raw ? raw.data : raw);
  const out = inbox => ({counts: {unread: inbox.counts.unread, read: inbox.counts.read, archived: inbox.counts.archived, total: inbox.counts.total}, nextCursor: inbox.nextCursor, audiences: (a => (a.length ? a : ['profile']))(inbox.audiences.filter(a => a === 'profile' || a === 'account-admin')),
    items: inbox.items.map(n => ({id: n.id, audience: n.audience, severity: n.severity, title: n.title, body: n.body, createdAt: n.createdAt, read: n.read, archived: n.archived}))});
  const note = {id: 'n1', audience: 'profile', severity: 'info', source: 'feedback', category: 'reply', title: 'A reply to your report', body: 'Thanks, it is fixed.', arguments: {report: 'r1'}, actions: [{kind: 'navigate', label: 'Open', target: {view: 'item', entityId: 'i1'}}, {kind: 'command', label: 'Retry', command: 'retry-download'}], dedupeKey: 'reply:r1', revision: 2, createdAt: 1791012951517, updatedAt: 1791012951517, expiresAt: 1793604951517, readAt: null, archivedAt: null, read: false, archived: false, cursor: 'c1'};
  const made = {scope: {serverId: 'srv', viewerFence: 'f'.repeat(64)}, data: {revision: 7, audience: 'profile', audiences: ['profile', 'account-admin', 'household'], state: 'all', counts: {unread: 1, read: 1, archived: 0, total: 2}, items: [note, {...note, id: 'n2', severity: 'critical', title: 'Storage is running low', body: '', actions: [], read: true, readAt: 1791012999999, cursor: 'c2'}], nextCursor: 'next', observedAt: 1791013000000, retentionDays: 90}};
  const cases = [];
  const push = (name, document) => { let expected = null, ok = true; try { expected = out(notes.parseNotificationInbox(data(document))); } catch { ok = false; } cases.push({name, document, ok, expected}); };
  for (const name of ['notifications-inbox-all.json', 'notifications-inbox-unread.json', 'notifications-inbox-admin.json']) { const served = load(name); if (served) push(`as served, ${name}`, served); }
  push('two messages', made);
  const broken = (name, change) => { const c = clone(made); change(c.data); push(name, c); };
  broken('no audiences this build knows', d => { d.audiences = ['household']; });
  broken('an audience that is not one', d => { d.items[0].audience = 'everyone'; });
  broken('a severity that is not one', d => { d.items[0].severity = 'loud'; });
  broken('no title', d => { d.items[0].title = ''; });
  broken('four actions', d => { d.items[0].actions = [1, 2, 3, 4].map(() => ({kind: 'command', label: 'x', command: 'y'})); });
  broken('an action that navigates and commands', d => { d.items[0].actions[0].command = 'both'; });
  broken('an action of an unknown kind', d => { d.items[0].actions[0].kind = 'dance'; });
  broken('a time that is negative', d => { d.items[0].createdAt = -1; });
  broken('read that is not yes or no', d => { d.items[0].read = 'yes'; });
  broken('counts without a total', d => { delete d.counts.total; });
  broken('a hundred and one messages', d => { d.items = Array.from({length: 101}, (_, i) => ({...d.items[0], id: `n${i}`})); });
  broken('an argument that is not text', d => { d.items[0].arguments = {report: 5}; });
  const unread = load('notifications-unread.json');
  const summaries = [unread, {scope: {}, data: {revision: 3, observedAt: 5, audience: 'profile', counts: {unread: 4, read: 0, archived: 0, total: 4}}}, {data: {revision: 3, observedAt: 5, audience: 'profile', counts: {unread: 'many'}}}].filter(Boolean).map(document => { let value = null; try { value = notes.parseNotificationSummary(data(document)).counts.unread; } catch { value = null; } return {document, unread: value}; });
  const batches = [{data: {revision: 8, audience: 'profile', applied: 1, receipts: [{action: 'read', id: 'n1', outcome: 'applied'}], counts: {unread: 0, read: 2, archived: 0, total: 2}}}, {data: {revision: 8, audience: 'profile', applied: 1, receipts: [{action: 'read', outcome: 'maybe'}], counts: {unread: 0, read: 2, archived: 0, total: 2}}}].map(document => { let ok = true, counts = null; try { counts = notes.parseNotificationBatchResult(data(document)).counts; } catch { ok = false; } return {document, ok, counts}; });
  write('notifications.json', {cases, summaries, batches});
}
// ── The Portico Account's notices: account-notifications.ts ──
{
  const account = await import('../../portico-server/packages/client-core/src/account-notifications.ts');
  const clone = v => JSON.parse(JSON.stringify(v));
  const one = {id: 'an_1', kind: 'server_offline', occurredAt: '2026-10-05T10:00:00Z', read: false, server: {id: 'srv_1', name: 'Home'}, detail: {}};
  const made = {items: [one, {...one, id: 'an_2', kind: 'new_device', read: true, server: null, detail: {name: 'Justin’s iPhone', platform: 'ios', count: 3}}, {...one, id: 'an_3', kind: 'security_event', detail: {event: 'two_step_enabled'}}, {...one, id: 'an_4', kind: 'signing_key_expiring', detail: {keyId: 'k1', expiresAt: '2026-11-01T00:00:00Z'}}, {...one, id: 'an_5', kind: 'something_new'}], unread: 4, nextCursor: 'c2'};
  const out = page => ({unread: page.unread, nextCursor: page.nextCursor ?? '', items: page.items.map(n => ({id: n.id, kind: n.kind, occurredAt: Math.floor(Date.parse(n.occurredAt) / 1000), read: n.read, server: n.server ? {id: n.server.id, name: n.server.name} : null, detail: n.detail}))});
  const cases = [];
  const push = (name, document) => { let ok = true, expected = null; try { expected = out(account.parseAccountNotificationPage(document)); } catch { ok = false; } cases.push({name, document, ok, expected}); };
  push('five notices', made);
  push('none', {items: [], unread: 0});
  const broken = (name, change) => { const c = clone(made); change(c); push(name, c); };
  broken('an empty cursor', c => { c.nextCursor = ''; });
  broken('no id', c => { c.items[0].id = ''; });
  broken('a time that is not one', c => { c.items[0].occurredAt = 'recently'; });
  broken('read that is not yes or no', c => { c.items[0].read = 1; });
  broken('a server without an id', c => { c.items[0].server = {name: 'Home'}; });
  broken('detail that is a list', c => { c.items[0].detail = ['x']; });
  broken('an unread count that is negative', c => { c.unread = -1; });
  broken('an unread count that is text', c => { c.unread = 'four'; });
  broken('a cursor that is a number', c => { c.nextCursor = 7; });
  broken('no list', c => { delete c.items; });
  const preferences = [{serverOffline: true, storageNearlyFull: false, invitationAccepted: true}, {serverOffline: 'yes', storageNearlyFull: false, invitationAccepted: true}, {serverOffline: true}].map(document => { let value = null; try { value = account.parseNotificationPreferences(document); } catch { value = null; } return {document, expected: value}; });
  write('account-notices.json', {cases, preferences, kinds: account.ACCOUNT_NOTIFICATION_KINDS, events: account.ACCOUNT_SECURITY_EVENTS});
}
// ── Watch Together: social-playback.ts and group-session.ts ──
{
  const {existsSync, readFileSync} = await import('node:fs');
  const social = await import('../../portico-server/packages/client-core/src/social-playback.ts');
  const {GroupFollower} = await import('../../portico-server/packages/client-core/src/group-session.ts');
  const dir = join(app, 'test', 'fixtures', 'server');
  const load = name => (existsSync(join(dir, name)) ? JSON.parse(readFileSync(join(dir, name), 'utf8')) : undefined);
  const clone = v => JSON.parse(JSON.stringify(v));
  const queueOut = q => ({revision: q.revision, position: q.position, entries: q.entries.map(e => ({entryId: e.entryId, position: e.position, itemId: e.itemId ?? '', unavailable: e.unavailable})), blocked: (q.eligibility?.members ?? []).filter(m => m.blockedEntryIds.length).map(m => m.displayName)});
  const groupOut = g => ({id: g.id, name: g.name, state: g.state, revision: g.revision, queueRevision: g.queueRevision, endedReason: g.endedReason, viewerMemberId: g.viewerMemberId, hostMemberId: g.hostMemberId,
    permissions: g.permissions, host: {presence: g.host.presence, pauseAt: g.host.pauseAt, endAt: g.host.endAt}, timeline: g.timeline, sync: {noCorrectionUnderMs: g.sync.noCorrectionUnderMs, rateCorrectionMaxMs: g.sync.rateCorrectionMaxMs, seekAtOrOverMs: g.sync.seekAtOrOverMs},
    readiness: g.readiness, members: g.members.map(m => ({id: m.id, displayName: m.displayName, role: m.role, state: m.state, readiness: m.readiness, presence: m.presence})), queue: g.queue ? queueOut(g.queue) : null});
  const snapshots = [], lists = [], queues = [], receipts = [], invites = [];
  const push = (list, name, document, parse, out) => { let ok = true, expected = null; try { expected = out(parse(document)); } catch { ok = false; } list.push({name, document, ok, expected}); };
  const playing = load('group-snapshot-playing.json');
  for (const name of ['group-snapshot.json', 'group-snapshot-loaded.json', 'group-snapshot-playing.json', 'group-snapshot-ended.json']) { const d = load(name); if (d) push(snapshots, `as served, ${name}`, d, social.parseGroupSnapshot, s => ({serverTime: s.serverTime, group: groupOut(s.group)})); }
  if (playing) {
    const broken = (name, change) => { const c = clone(playing); change(c.group, c); push(snapshots, name, c, social.parseGroupSnapshot, s => ({serverTime: s.serverTime, group: groupOut(s.group)})); };
    broken('another protocol', (g, d) => { d.protocolVersion = '2.0'; });
    broken('a state that is not one', g => { g.state = 'dancing'; });
    broken('a state that disagrees with its clock', g => { g.state = 'paused'; });
    broken('a host who cannot control', g => { g.permissions.canControl = false; });
    broken('two hosts', g => { g.members.push({...clone(g.members[0]), id: 'm_two'}); g.readiness.memberCount += 1; g.readiness[g.members[0].readiness] += 1; });
    broken('counts that do not add up', g => { g.readiness.ready += 1; });
    broken('ready while someone lags', g => { g.readiness.aggregate = 'ready'; g.readiness.lagging = g.readiness.ready + g.readiness.buffering; g.readiness.ready = 0; g.readiness.buffering = 0; });
    broken('bands out of order', g => { g.sync.noCorrectionUnderMs = g.sync.seekAtOrOverMs + 1; });
    broken('a rate of nothing', g => { g.timeline.rate.denominator = '0'; });
    broken('a position that is a number', g => { g.timeline.anchorPositionUs = 5; });
    broken('a revision with a leading zero', g => { g.revision = '01'; });
    broken('a member in a state that is not one', g => { g.members[0].state = 'lurking'; });
    broken('an authority that is not one', g => { g.authority.state = 'stale'; });
  }
  const list = load('group-list.json');
  if (list) { push(lists, 'as served', list, d => social.parseGroupList(d).filter(g => g.state !== 'ended' && g.state !== 'failed'), l => l.map(groupOut)); push(lists, 'no list', {protocolVersion: '1.0', serverTime: 'now'}, social.parseGroupList, l => l.map(groupOut)); }
  const queue = load('group-queue.json');
  if (queue) {
    const q = queue.queue ?? queue;
    push(queues, 'as served', q, social.parseGroupQueue, queueOut);
    const broken = (name, change) => { const c = clone(q); change(c); push(queues, name, c, social.parseGroupQueue, queueOut); };
    broken('with an entry this viewer cannot see', c => { c.entries.push({entryId: 'e_hidden', position: c.entries.length, itemId: null, unavailable: true, addedBy: ''}); c.eligibility = {blockedEntries: 1, currentEntryBlocked: false, members: [{memberId: 'm_kid', displayName: 'Kid', blockedEntryIds: [c.entries[0].entryId]}, {memberId: 'm_ok', displayName: 'Ok', blockedEntryIds: []}]}; });
    broken('a hidden entry that names its title', c => { c.entries[0].unavailable = true; });
    broken('an entry out of place', c => { c.entries[0].position = 4; });
    broken('an entry listed twice', c => { c.entries.push({...clone(c.entries[0]), position: c.entries.length}); });
    broken('an entry without a title', c => { c.entries[0].itemId = null; });
  }
  for (const name of ['group-transport.json', 'group-transport-play.json']) { const d = load(name); if (d) push(receipts, `as served, ${name}`, d, social.parseGroupTransportReceipt, r => ({revision: r.revision, timeline: r.timeline})); }
  const receipt = load('group-transport-play.json');
  if (receipt) for (const [name, change] of [['a command that is not one', c => { c.command = 'rewind'; }], ['a disposition that is not one', c => { c.disposition = 'maybe'; }], ['an override without members', c => { c.override = {reason: 'host'}; }]]) { const c = clone(receipt); change(c); push(receipts, name, c, social.parseGroupTransportReceipt, r => ({revision: r.revision, timeline: r.timeline})); }
  const invite = load('group-invite.json');
  if (invite) { push(invites, 'as served', invite, social.parseGroupInvite, i => ({inviteCode: i.code, expiresAt: i.expiresAt, maxUses: i.maxUses})); const c = clone(invite); c.invite.code = 'abc1'; push(invites, 'a code in small letters', c, social.parseGroupInvite, i => ({inviteCode: i.code, expiresAt: i.expiresAt, maxUses: i.maxUses})); }

  // The group's clock and the bands.
  const timeline = {itemId: 'i1', currentEntryId: 'e1', state: 'playing', anchorPositionUs: '754250000', anchorAt: '2026-10-05T10:00:00.250Z', rate: {numerator: '1', denominator: '1'}, queuePosition: 0};
  const anchorMs = Date.parse(timeline.anchorAt);
  const targets = [[timeline, anchorMs], [timeline, anchorMs + 1500], [timeline, anchorMs - 400], [{...timeline, state: 'paused'}, anchorMs + 90000], [{...timeline, rate: {numerator: '3', denominator: '2'}}, anchorMs + 2000], [{...timeline, anchorPositionUs: '0'}, anchorMs + 10]].map(([t, at]) => ({timeline: t, serverNowMs: at, seconds: Number(social.groupTargetPositionUs(t, Date.parse(t.anchorAt), at) / 1000n) / 1000}));
  const sync = {noCorrectionUnderMs: 250, rateCorrectionMinimum: '0.97', rateCorrectionMaximum: '1.03', rateCorrectionMaxMs: 4000, seekAtOrOverMs: 2000};
  const corrections = [0, 0.1, 0.249, 0.25, -0.25, 1.9, 2, -2, 30].map(drift => ({drift, action: social.groupCorrection(sync, BigInt(Math.round(drift * 1e6)), 0n).action}));

  // The follower, step by step: the real GroupFollower with a recorded player and a set clock.
  const follow = [];
  if (playing) {
    const base = clone(playing.group); base.sync = sync;
    const scenario = (name, steps) => {
      let now = 1_000_000, offset = 0, group = social.parseGroup(base), phase = 'live';
      const calls = []; let local = {itemId: '', positionSeconds: 0, playing: false, buffering: false, ready: false};
      const reports = [];
      const service = {getSnapshot: () => ({group, phase, clockOffsetMs: offset}), serverNow: () => now + offset, subscribe: () => () => {}, readiness: async (r, us) => { reports.push(r); }};
      const player = {state: () => local, load: (itemId, seconds, playingWanted) => calls.push({kind: 'load', itemId, seconds, playing: playingWanted}), play: () => calls.push({kind: 'play'}), pause: () => calls.push({kind: 'pause'}), seek: seconds => calls.push({kind: 'seek', seconds}), setRate: () => {}};
      const follower = new GroupFollower(service, player, () => now);
      const out = [];
      for (const step of steps) {
        if (step.timeline) group = social.parseGroup({...clone(base), state: step.state ?? base.state, timeline: {...base.timeline, ...step.timeline}});
        if (step.local) local = {...local, ...step.local};
        if (step.phase) phase = step.phase;
        now += step.advanceMs ?? 1000;
        const anchor = Date.parse(group.timeline.anchorAt);
        offset = anchor + (step.intoMs ?? 0) - now;
        calls.length = 0; reports.length = 0;
        follower['tick']();
        out.push({group: groupOut(group), live: phase === 'live' || phase === 'reconnecting', local: {...local}, nowMs: now, serverNowMs: now + offset, actions: calls.map(c => ({...c})), reported: reports[0] ?? ''});
      }
      follow.push({name, steps: out});
    };
    const item = base.timeline.itemId, startSeconds = Number(BigInt(base.timeline.anchorPositionUs) / 1000n) / 1000;
    scenario('a title is loaded once, then followed', [
      {intoMs: 0}, {intoMs: 1000}, {local: {itemId: item, ready: false}, intoMs: 2000}, {local: {ready: true, positionSeconds: startSeconds + 3}, intoMs: 3000},
      {local: {playing: true, positionSeconds: startSeconds + 4}, intoMs: 4000}, {local: {positionSeconds: startSeconds + 4.2}, intoMs: 5000},
    ]);
    scenario('a small drift is left for the hold, then closed by a seek', [
      {local: {itemId: item, ready: true, playing: true, positionSeconds: startSeconds + 0.4}, intoMs: 1000}, {local: {positionSeconds: startSeconds + 1.4}, intoMs: 2000, advanceMs: 1000},
      {local: {positionSeconds: startSeconds + 4.4}, intoMs: 5000, advanceMs: 3000}, {local: {positionSeconds: startSeconds + 5.5}, intoMs: 6100, advanceMs: 1100}, {local: {positionSeconds: startSeconds + 7.1}, intoMs: 7100},
    ]);
    scenario('a large drift is a seek at once', [{local: {itemId: item, ready: true, playing: true, positionSeconds: startSeconds + 30}, intoMs: 1000}, {local: {positionSeconds: startSeconds + 2}, intoMs: 2000}]);
    scenario('the group pauses', [{local: {itemId: item, ready: true, playing: true, positionSeconds: startSeconds + 1}, intoMs: 1000}, {timeline: {state: 'paused'}, state: 'paused', intoMs: 0}, {local: {playing: false, positionSeconds: startSeconds + 1.3}, intoMs: 0}, {local: {positionSeconds: startSeconds}, intoMs: 0}]);
    scenario('buffering is said, and nothing is asked of a player that is', [{local: {itemId: item, ready: true, playing: false, buffering: true, positionSeconds: startSeconds}, intoMs: 1000}]);
    scenario('a room that is not live asks nothing', [{phase: 'ended', local: {itemId: item, ready: true, playing: true, positionSeconds: startSeconds}, intoMs: 1000}]);
    scenario('nothing chosen', [{timeline: {itemId: '', currentEntryId: '', state: 'idle'}, state: 'lobby', intoMs: 0}]);
  }
  write('together.json', {snapshots, lists, queues, receipts, invites, targets, sync, corrections, follow});
}
console.log('golden: fixtures written to test/fixtures/golden');
