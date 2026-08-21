import {existsSync, realpathSync} from 'node:fs';
import {dirname, isAbsolute, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const SCRIPT_DIRECTORY = dirname(fileURLToPath(import.meta.url));
export const ROKU_ROOT = realpathSync(resolve(SCRIPT_DIRECTORY, '..', '..'));

function findRepositoryRoot(start) {
  let cursor = realpathSync(start);
  for (let depth = 0; depth < 8; depth += 1) {
    const server = resolve(cursor, 'apps', 'portico-server');
    const hosted = resolve(cursor, 'apps', 'portico-cloud');
    if (existsSync(server) && existsSync(hosted)) return cursor;
    const parent = dirname(cursor);
    if (parent === cursor) break;
    cursor = parent;
  }
  throw new Error('Unable to locate the Portico repository root from the Roku project.');
}

export const REPOSITORY_ROOT = findRepositoryRoot(ROKU_ROOT);

export function assertPathInside(parent, candidate, label = 'path') {
  const normalizedParent = resolve(parent);
  const normalizedCandidate = resolve(candidate);
  const child = relative(normalizedParent, normalizedCandidate);
  if (child === '' || (!child.startsWith(`..${sep}`) && child !== '..' && !isAbsolute(child))) {
    return normalizedCandidate;
  }
  throw new Error(`${label} escapes its allowed root.`);
}

function canonicalPath(...segments) {
  const candidate = assertPathInside(REPOSITORY_ROOT, resolve(REPOSITORY_ROOT, ...segments), 'canonical source');
  if (!existsSync(candidate)) throw new Error(`Required canonical source is unavailable: ${segments.join('/')}`);
  return assertPathInside(REPOSITORY_ROOT, realpathSync(candidate), 'canonical source');
}

export const CANONICAL_SOURCES = Object.freeze({
  productLanguage: canonicalPath('apps', 'portico-server', 'api', 'product-language', 'en-US.json'),
  productLanguageSchema: canonicalPath('apps', 'portico-server', 'api', 'schema', 'product-language.schema.json'),
  productLanguageRuntime: canonicalPath('apps', 'portico-server', 'packages', 'portico-client-core', 'src', 'productLanguage.ts'),
  productContractSchema: canonicalPath('apps', 'portico-server', 'api', 'schema', 'product-contract.schema.json'),
  serverOpenApi: canonicalPath('apps', 'portico-server', 'api', 'openapi', 'portico-server.openapi.json'),
  hostedOpenApi: canonicalPath('apps', 'portico-cloud', 'api', 'openapi', 'portico-hosted.openapi.json'),
  serverGoRoot: canonicalPath('apps', 'portico-server'),
  serverAppDirectory: canonicalPath('apps', 'portico-server', 'internal', 'app')
});

export const GENERATED_DIRECTORY = assertPathInside(ROKU_ROOT, resolve(ROKU_ROOT, 'channel', 'data', 'generated'), 'generated output');

export function generatedPath(...segments) {
  return assertPathInside(GENERATED_DIRECTORY, resolve(GENERATED_DIRECTORY, ...segments), 'generated output');
}
