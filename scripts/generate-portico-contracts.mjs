import {createHash} from 'node:crypto';
import {
  mkdirSync,
  lstatSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  renameSync,
  writeFileSync
} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {
  CANONICAL_SOURCES,
  GENERATED_DIRECTORY,
  ROKU_ROOT,
  assertPathInside,
  generatedPath
} from './lib/canonical-sources.mjs';
import {
  FORBIDDEN_ROKU_OPERATION_TERMS,
  FORBIDDEN_ROKU_SERVER_PATHS,
  ROKU_SERVER_OPERATION_ALLOWLIST
} from './lib/roku-operation-policy.mjs';

const GENERATOR_REVISION = 1;
const MAX_SOURCE_BYTES = 8 * 1024 * 1024;
const MAX_OPERATIONS = 600;
const MAX_MESSAGES = 2500;
const MAX_ICONS = 256;

const HOSTED_OPERATION_ALLOWLIST = new Set([
  'authorizeLocalServerLogin',
  'createDeviceAuthorizationSession',
  'createHostedProfileSelectionEnvelope',
  'createPorticoSession',
  'getAccountProfile',
  'getAccountServer',
  'getDocumentSigningKeys',
  'getHostedAuthState',
  'getHostedSystem',
  'getServerRoutes',
  'listAccountProfiles',
  'listAccountServers',
  'pollDeviceAuthorizationSession',
  'redeemDeviceAuthorizationSession',
  'refreshNativeSession',
  'reportServerRouteFailure',
  'revokeNativeSession'
]);

const ROKU_CONSUMER_ACTIONS = Object.freeze([
  'collection.add',
  'favorite.add',
  'favorite.remove',
  'feedback.report-problem',
  'feedback.request-higher-quality',
  'live.play',
  'play',
  'play.from-beginning',
  'playlist.add',
  'queue.add',
  'rating.set',
  'reaction.set',
  'watched.mark',
  'watched.set',
  'watched.unmark',
  'watchlist.add',
  'watchlist.remove',
  'watch-with-friends.start'
]);

const ICON_ASSET_ALIASES = Object.freeze({
  Activity: 'info',
  Archive: 'library',
  ArrowDown: 'chevron-down',
  ArrowLeft: 'chevron-left',
  ArrowRight: 'chevron-right',
  ArrowUp: 'chevron-up',
  BadgeCheck: 'check',
  Bell: 'info',
  BookmarkPlus: 'bookmark',
  BookOpen: 'library',
  CheckCheck: 'check',
  CircleCheck: 'check',
  CircleCheckBig: 'check',
  CircleDot: 'radio',
  CirclePlay: 'play',
  CircleUserRound: 'user',
  CircleX: 'x',
  Download: 'arrow-down-az',
  DownloadCloud: 'arrow-down-az',
  FastForward: 'rotate-cw',
  Flag: 'info',
  HardDrive: 'library',
  Inbox: 'library',
  LibraryBig: 'library',
  LoaderCircle: 'rotate-cw',
  LockKeyhole: 'user',
  LogIn: 'user',
  Maximize2: 'plus',
  MessageSquareWarning: 'triangle-alert',
  Mail: 'info',
  MessageSquare: 'info',
  Music2: 'music',
  Minimize2: 'x',
  Pencil: 'settings',
  KeyRound: 'user',
  Repeat: 'rotate-cw',
  Repeat1: 'rotate-cw',
  Rewind: 'rotate-ccw',
  ServerOff: 'wifi',
  Settings2: 'settings',
  Shuffle: 'list-music',
  SkipForward: 'rotate-cw',
  Timer: 'info',
  Trash2: 'x',
  TvMinimalPlay: 'tv',
  Users: 'user',
  UsersRound: 'user',
  Volume2: 'music',
  VolumeX: 'x',
  WandSparkles: 'plus',
  WifiOff: 'wifi'
});

function readBounded(path) {
  const buffer = readFileSync(path);
  if (buffer.length === 0 || buffer.length > MAX_SOURCE_BYTES) {
    throw new Error(`Canonical source ${basename(path)} is empty or exceeds ${MAX_SOURCE_BYTES} bytes.`);
  }
  return buffer;
}

function parseJson(path) {
  const text = readBounded(path).toString('utf8');
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`Canonical source ${basename(path)} is not valid JSON: ${error.message}`);
  }
}

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

function sourceRevision(path) {
  return {name: basename(path), sha256: sha256(readBounded(path))};
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableValue(value[key])]));
  }
  return value;
}

export function stableJson(value) {
  return `${JSON.stringify(stableValue(value), null, 2)}\n`;
}

// The semantic icon synchronizer shares this package directory but owns its
// manifest independently. Contract generation must preserve that boundary.
export const EXTERNALLY_OWNED_GENERATED_FILES = new Set(['roku-icons.v1.json']);

function own(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function validateProductLanguage(catalog) {
  if (!catalog || typeof catalog !== 'object' || Array.isArray(catalog)) throw new Error('Product Language must be an object.');
  if (catalog.revision !== 'v1' || catalog.locale !== 'en-US' || catalog.fallbackLocale !== 'en-US' || catalog.iconFamily !== 'lucide') {
    throw new Error('Product Language compatibility fields do not match the Roku v1 contract.');
  }
  const iconIds = Object.keys(catalog.icons ?? {});
  const messageIds = Object.keys(catalog.messages ?? {});
  if (iconIds.length < 1 || iconIds.length > MAX_ICONS || messageIds.length < 1 || messageIds.length > MAX_MESSAGES) {
    throw new Error('Product Language inventory is outside Roku generation bounds.');
  }
  for (const id of iconIds) {
    if (!/^[a-z][a-z0-9.-]*$/.test(id)) throw new Error(`Invalid semantic icon identifier ${id}.`);
    const icon = catalog.icons[id];
    if (!icon || typeof icon.glyph !== 'string' || !icon.glyph.trim() || typeof icon.label !== 'string' || !icon.label.trim()) {
      throw new Error(`Semantic icon ${id} is incomplete.`);
    }
  }
  for (const id of messageIds) {
    if (!/^[a-z][a-z0-9.-]*$/.test(id)) throw new Error(`Invalid Product Language message identifier ${id}.`);
    const message = catalog.messages[id];
    if (!message || typeof message !== 'object' || Array.isArray(message)) throw new Error(`Product message ${id} is invalid.`);
    if (![message.text, message.title].some((value) => typeof value === 'string' && value.length > 0)) {
      throw new Error(`Product message ${id} has no display text.`);
    }
    if (message.icon && !own(catalog.icons, message.icon)) throw new Error(`Product message ${id} references unknown icon ${message.icon}.`);
    for (const actionId of message.actions ?? []) {
      if (!own(catalog.messages, actionId) || !actionId.startsWith('action.')) {
        throw new Error(`Product message ${id} references unknown action ${actionId}.`);
      }
    }
  }
}

function extractProblemCodeMessages(source, catalog) {
  const match = source.match(/const problemCodeMessages:[\s\S]*?Object\.freeze\(\{([\s\S]*?)\n\}\);/);
  if (!match) throw new Error('Unable to locate the canonical Product Language problem-code map.');
  const result = {};
  const pattern = /^\s*([a-z][a-z0-9_]*)\s*:\s*"([a-z][a-z0-9.-]*)",?\s*$/gm;
  for (const entry of match[1].matchAll(pattern)) {
    const [, code, messageId] = entry;
    if (own(result, code)) throw new Error(`Duplicate Product Language problem code ${code}.`);
    if (!own(catalog.messages, messageId)) throw new Error(`Problem code ${code} references unknown message ${messageId}.`);
    result[code] = messageId;
  }
  if (Object.keys(result).length < 25) throw new Error('Canonical Product Language problem-code map is unexpectedly small.');
  return result;
}

function placeholderNames(catalog) {
  const names = new Set();
  for (const message of Object.values(catalog.messages)) {
    for (const value of [message.text, message.title, message.body]) {
      if (typeof value !== 'string') continue;
      for (const match of value.matchAll(/\{([A-Za-z][A-Za-z0-9]*)\}/g)) names.add(match[1]);
    }
  }
  return [...names].sort();
}

function pascalToKebab(value) {
  return value.replace(/([a-z0-9])([A-Z])/g, '$1-$2').replace(/([A-Z])([A-Z][a-z])/g, '$1-$2').toLowerCase();
}

function rokuIconAssets(catalog) {
  const iconDirectory = assertPathInside(ROKU_ROOT, resolve(ROKU_ROOT, 'channel', 'images', 'icons'), 'icon directory');
  const packaged = new Set(readdirSync(iconDirectory).filter((name) => name.endsWith('.png')).map((name) => name.slice(0, -4)));
  const result = {};
  for (const [id, definition] of Object.entries(catalog.icons)) {
    const candidate = ICON_ASSET_ALIASES[definition.glyph] ?? pascalToKebab(definition.glyph);
    if (!packaged.has(candidate)) throw new Error(`Semantic icon ${id} glyph ${definition.glyph} has no reviewed Roku asset mapping.`);
    result[id] = `pkg:/images/icons/${candidate}.png`;
  }
  return result;
}

function exportCanonicalProductContract() {
  const temporary = mkdtempSync(join(tmpdir(), 'portico-roku-contract-'));
  try {
    const overlayTarget = resolve(CANONICAL_SOURCES.serverAppDirectory, 'roku_product_contract_export_test.go');
    const helper = assertPathInside(ROKU_ROOT, resolve(ROKU_ROOT, 'scripts', 'lib', 'roku_product_contract_export_test.go'), 'Go export helper');
    const overlayPath = join(temporary, 'overlay.json');
    writeFileSync(overlayPath, JSON.stringify({Replace: {[overlayTarget]: helper}}));
    const result = spawnSync('go', [
      'test',
      '-v',
      '-run', '^TestRokuExportCanonicalProductContract$',
      '-count=1',
      `-overlay=${overlayPath}`,
      '.'
    ], {
      cwd: CANONICAL_SOURCES.serverAppDirectory,
      encoding: 'utf8',
      maxBuffer: 16 * 1024 * 1024,
      timeout: 180_000
    });
    if (result.error) throw new Error(`Unable to execute the canonical Product Contract exporter: ${result.error.message}`);
    if (result.status !== 0) throw new Error(`Canonical Product Contract exporter failed:\n${(result.stderr || result.stdout).trim()}`);
    const marker = result.stdout.match(/PORTICO_ROKU_PRODUCT_CONTRACT:([A-Za-z0-9+/=]+)/);
    if (!marker) throw new Error('Canonical Product Contract exporter returned no payload.');
    return JSON.parse(Buffer.from(marker[1], 'base64').toString('utf8'));
  } finally {
    rmSync(temporary, {recursive: true, force: true});
  }
}

function validateProductContract(contract, catalog, schema) {
  const required = schema.required ?? [];
  if (!contract || typeof contract !== 'object' || Array.isArray(contract)) throw new Error('Product Contract must be an object.');
  for (const field of required) if (!own(contract, field)) throw new Error(`Product Contract is missing ${field}.`);
  if (contract.apiVersion !== 'v1' || contract.actionRevision !== 'v1') throw new Error('Product Contract is incompatible with Roku v1.');
  if (contract.language?.revision !== catalog.revision || contract.language?.defaultLocale !== catalog.locale) {
    throw new Error('Product Contract language reference does not match the generated catalog.');
  }
  const actionIds = new Set();
  for (const action of contract.mediaActions ?? []) {
    if (!action || typeof action.id !== 'string' || actionIds.has(action.id)) throw new Error('Product Contract has an invalid or duplicate media action.');
    actionIds.add(action.id);
    if (!own(catalog.messages, action.presentation?.labelMessageId)) throw new Error(`Media action ${action.id} has an unknown label.`);
    if (!own(catalog.icons, action.presentation?.iconId)) throw new Error(`Media action ${action.id} has an unknown icon.`);
  }
  for (const actionId of ROKU_CONSUMER_ACTIONS) {
    if (!actionIds.has(actionId)) throw new Error(`Roku consumer action ${actionId} is not published by the canonical Product Contract.`);
  }
}

function schemaName(schema) {
  if (!schema || typeof schema !== 'object') return undefined;
  if (typeof schema.$ref === 'string') return schema.$ref.split('/').at(-1);
  if (schema.items) return schemaName(schema.items);
  return undefined;
}

function responseSchemaNames(operation) {
  const result = new Set();
  for (const [status, response] of Object.entries(operation.responses ?? {})) {
    if (!/^2\d\d$/.test(status)) continue;
    for (const media of Object.values(response.content ?? {})) {
      const name = schemaName(media.schema);
      if (name) result.add(name);
    }
  }
  return [...result].sort();
}

function idempotencyMetadata(pathItem, operation) {
  const parameters = [...(pathItem.parameters ?? []), ...(operation.parameters ?? [])];
  for (const parameter of parameters) {
    if (!parameter || parameter.$ref || String(parameter.name).toLowerCase() !== 'idempotencykey') continue;
    return {required: parameter.required === true, location: parameter.in};
  }
  return {required: false, location: 'none'};
}

function assertServerOperationPolicy(openApi) {
  const published = new Map();
  for (const [path, pathItem] of Object.entries(openApi.paths ?? {})) {
    for (const method of ['delete', 'get', 'head', 'patch', 'post', 'put']) {
      const operation = pathItem[method];
      if (operation?.operationId) published.set(operation.operationId, {path, operation});
    }
  }
  for (const operationId of ROKU_SERVER_OPERATION_ALLOWLIST) {
    const record = published.get(operationId);
    if (!record) throw new Error(`Reviewed Roku server operation ${operationId} is no longer published.`);
    if (record.operation['x-portico-audience'] !== 'viewer' || !record.operation['x-portico-surfaces']?.includes('television')) {
      throw new Error(`Reviewed Roku server operation ${operationId} is no longer a television viewer operation.`);
    }
    if (FORBIDDEN_ROKU_OPERATION_TERMS.test(operationId) || FORBIDDEN_ROKU_SERVER_PATHS.some((pattern) => pattern.test(record.path))) {
      throw new Error(`Forbidden server operation ${operationId} entered the Roku allowlist.`);
    }
  }
}

function operationRecords(openApi, service) {
  if (service === 'server') assertServerOperationPolicy(openApi);
  const records = [];
  for (const [path, pathItem] of Object.entries(openApi.paths ?? {})) {
    for (const method of ['delete', 'get', 'head', 'patch', 'post', 'put']) {
      const operation = pathItem[method];
      if (!operation) continue;
      const operationId = operation.operationId;
      if (typeof operationId !== 'string' || !/^[A-Za-z][A-Za-z0-9]*$/.test(operationId)) {
        throw new Error(`${service} operation ${method.toUpperCase()} ${path} has no safe operationId.`);
      }
      if (service === 'server' && !ROKU_SERVER_OPERATION_ALLOWLIST.has(operationId)) continue;
      if (service === 'hosted' && !HOSTED_OPERATION_ALLOWLIST.has(operationId)) continue;
      if (service === 'server' && (FORBIDDEN_ROKU_OPERATION_TERMS.test(operationId) || FORBIDDEN_ROKU_SERVER_PATHS.some((pattern) => pattern.test(path)))) {
        throw new Error(`Forbidden server operation ${operationId} entered the generated Roku artifact.`);
      }
      const surfaces = service === 'server' ? operation['x-portico-surfaces'] : ['television'];
      const auth = service === 'server' ? operation['x-portico-auth'] : operation['x-portico-auth'];
      records.push({
        service,
        operationId,
        method: method.toUpperCase(),
        path,
        audience: service === 'server' ? 'viewer' : 'television-client',
        auth,
        permission: service === 'server' ? operation['x-portico-permission'] : auth,
        ratePolicy: service === 'server' ? operation['x-portico-rate-policy'] : operation['x-portico-rate-class'],
        surfaces,
        mutation: !['get', 'head'].includes(method),
        idempotency: idempotencyMetadata(pathItem, operation),
        responseSchemas: responseSchemaNames(operation)
      });
    }
  }
  return records.sort((left, right) => left.operationId.localeCompare(right.operationId) || left.method.localeCompare(right.method));
}

function assertSafeArtifact(name, value) {
  const serialized = JSON.stringify(value);
  if (serialized.includes('/Users/') || serialized.includes('\\Users\\') || serialized.includes('BEGIN PRIVATE KEY')) {
    throw new Error(`${name} contains local path or private-key material.`);
  }
  if (/ptc_(?:clt|loc|rft|lrf)_[A-Za-z0-9_-]{12,}/.test(serialized)) throw new Error(`${name} contains token-like material.`);
  if (/https?:\/\/[^\s"/]+:[^\s"@]+@/.test(serialized)) throw new Error(`${name} contains URL user information.`);
}

export function buildArtifacts() {
  const catalog = parseJson(CANONICAL_SOURCES.productLanguage);
  const languageSchema = parseJson(CANONICAL_SOURCES.productLanguageSchema);
  const contractSchema = parseJson(CANONICAL_SOURCES.productContractSchema);
  const languageRuntime = readBounded(CANONICAL_SOURCES.productLanguageRuntime).toString('utf8');
  validateProductLanguage(catalog, languageSchema);

  const contract = exportCanonicalProductContract();
  validateProductContract(contract, catalog, contractSchema);

  const operations = [
    ...operationRecords(parseJson(CANONICAL_SOURCES.serverOpenApi), 'server'),
    ...operationRecords(parseJson(CANONICAL_SOURCES.hostedOpenApi), 'hosted')
  ].sort((left, right) => left.service.localeCompare(right.service) || left.operationId.localeCompare(right.operationId));
  if (operations.length < 20 || operations.length > MAX_OPERATIONS) throw new Error('Generated operation inventory is outside Roku bounds.');
  const operationIds = new Set();
  for (const operation of operations) {
    const key = `${operation.service}:${operation.operationId}`;
    if (operationIds.has(key)) throw new Error(`Duplicate generated operation ${key}.`);
    operationIds.add(key);
  }

  const sources = {
    productLanguage: sourceRevision(CANONICAL_SOURCES.productLanguage),
    productLanguageSchema: sourceRevision(CANONICAL_SOURCES.productLanguageSchema),
    productLanguageRuntime: sourceRevision(CANONICAL_SOURCES.productLanguageRuntime),
    productContractSchema: sourceRevision(CANONICAL_SOURCES.productContractSchema),
    serverOpenApi: sourceRevision(CANONICAL_SOURCES.serverOpenApi),
    hostedOpenApi: sourceRevision(CANONICAL_SOURCES.hostedOpenApi)
  };

  const artifacts = new Map([
    ['product-language.v1.json', {
      schemaVersion: 1,
      generatorRevision: GENERATOR_REVISION,
      source: sources.productLanguage,
      catalog,
      allowedParameters: placeholderNames(catalog),
      problemCodeMessages: extractProblemCodeMessages(languageRuntime, catalog),
      rokuIconAssets: rokuIconAssets(catalog)
    }],
    ['product-contract.v1.json', {
      schemaVersion: 1,
      generatorRevision: GENERATOR_REVISION,
      snapshotRole: 'build-time-validation-and-conformance-only',
      sources: {
        productContractSchema: sources.productContractSchema,
        productLanguage: sources.productLanguage
      },
      contract,
      rokuPolicy: {
        deviceClass: 'television',
        platform: 'roku',
        consumerActionAllowlist: ROKU_CONSUMER_ACTIONS,
        forbiddenActionGroups: ['administration'],
        forbiddenActionIds: ['download', 'media.analyze', 'media.delete', 'media.optimize', 'metadata.edit', 'metadata.refresh'],
        unknownActions: 'hide'
      }
    }],
    ['operations.v1.json', {
      schemaVersion: 1,
      generatorRevision: GENERATOR_REVISION,
      sources: {serverOpenApi: sources.serverOpenApi, hostedOpenApi: sources.hostedOpenApi},
      operations
    }]
  ]);

  const manifestEntries = [];
  for (const [name, value] of artifacts) {
    assertSafeArtifact(name, value);
    manifestEntries.push({name, sha256: sha256(Buffer.from(stableJson(value))), bytes: Buffer.byteLength(stableJson(value))});
  }
  artifacts.set('manifest.v1.json', {
    schemaVersion: 1,
    generatorRevision: GENERATOR_REVISION,
    artifacts: manifestEntries.sort((left, right) => left.name.localeCompare(right.name))
  });
  return artifacts;
}

export function writeArtifacts(artifacts = buildArtifacts()) {
  mkdirSync(GENERATED_DIRECTORY, {recursive: true});
  if (lstatSync(GENERATED_DIRECTORY).isSymbolicLink()) throw new Error('Generated output directory must not be a symbolic link.');
  assertPathInside(ROKU_ROOT, realpathSync(GENERATED_DIRECTORY), 'generated output');
  const expected = new Set(artifacts.keys());
  for (const entry of readdirSync(GENERATED_DIRECTORY)) {
    if (!entry.endsWith('.json')) continue;
    if (EXTERNALLY_OWNED_GENERATED_FILES.has(entry)) continue;
    const path = generatedPath(entry);
    if (lstatSync(path).isSymbolicLink()) throw new Error(`Generated output ${entry} must not be a symbolic link.`);
    if (!expected.has(entry)) rmSync(path);
  }
  for (const [name, value] of artifacts) {
    const path = generatedPath(name);
    const temporary = generatedPath(`.${name}.${process.pid}.tmp`);
    writeFileSync(temporary, stableJson(value), {encoding: 'utf8', mode: 0o644, flag: 'wx'});
    try {
      renameSync(temporary, path);
    } finally {
      rmSync(temporary, {force: true});
    }
  }
  return [...artifacts.keys()].sort();
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  const names = writeArtifacts();
  console.log(`Generated ${names.length} deterministic Roku contract artifacts.`);
}
