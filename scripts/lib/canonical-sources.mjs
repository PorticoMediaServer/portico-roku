import {existsSync, realpathSync} from 'node:fs';
import {dirname, isAbsolute, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const SCRIPT_DIRECTORY = dirname(fileURLToPath(import.meta.url));
export const ROKU_ROOT = realpathSync(resolve(SCRIPT_DIRECTORY, '..', '..'));

export function assertPathInside(parent, candidate, label = 'path') {
  const normalizedParent = resolve(parent);
  const normalizedCandidate = resolve(candidate);
  const child = relative(normalizedParent, normalizedCandidate);
  if (child === '' || (!child.startsWith(`..${sep}`) && child !== '..' && !isAbsolute(child))) {
    return normalizedCandidate;
  }
  throw new Error(`${label} escapes its allowed root.`);
}

function canonicalRoot(environmentName, siblingName) {
  const configured = process.env[environmentName]?.trim();
  const candidate = configured ? resolve(configured) : resolve(ROKU_ROOT, '..', siblingName);
  if (!existsSync(candidate)) {
    throw new Error(`Required ${siblingName} checkout is unavailable at ${candidate}. Set ${environmentName} when it is not a sibling of portico-roku.`);
  }
  return realpathSync(candidate);
}

export const SERVER_ROOT = canonicalRoot('PORTICO_SERVER_ROOT', 'portico-server');

function canonicalPath(root, ...segments) {
  const candidate = assertPathInside(root, resolve(root, ...segments), 'canonical source');
  if (!existsSync(candidate)) throw new Error(`Required canonical source is unavailable: ${segments.join('/')}`);
  return assertPathInside(root, realpathSync(candidate), 'canonical source');
}

export const CANONICAL_SOURCES = Object.freeze({
  productLanguage: canonicalPath(SERVER_ROOT, 'api', 'product-language', 'en-US.json'),
  productLanguageSchema: canonicalPath(SERVER_ROOT, 'api', 'schema', 'product-language.schema.json'),
  productLanguageRuntime: canonicalPath(SERVER_ROOT, 'packages', 'portico-client-core', 'src', 'productLanguage.ts'),
  productContractSchema: canonicalPath(SERVER_ROOT, 'api', 'schema', 'product-contract.schema.json'),
  serverOpenApi: canonicalPath(SERVER_ROOT, 'api', 'openapi', 'portico-server.openapi.json'),
  hostedOpenApi: canonicalPath(SERVER_ROOT, 'api', 'openapi', 'hosted', 'portico-hosted.openapi.json'),
  serverGoRoot: SERVER_ROOT,
  serverAppDirectory: canonicalPath(SERVER_ROOT, 'internal', 'app')
});

export const GENERATED_DIRECTORY = assertPathInside(ROKU_ROOT, resolve(ROKU_ROOT, 'channel', 'data', 'generated'), 'generated output');

export function generatedPath(...segments) {
  return assertPathInside(GENERATED_DIRECTORY, resolve(GENERATED_DIRECTORY, ...segments), 'generated output');
}
