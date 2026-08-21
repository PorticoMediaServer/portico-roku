import {existsSync, readFileSync, readdirSync} from 'node:fs';
import {buildArtifacts, EXTERNALLY_OWNED_GENERATED_FILES, stableJson} from './generate-portico-contracts.mjs';
import {GENERATED_DIRECTORY, generatedPath} from './lib/canonical-sources.mjs';

const expected = buildArtifacts();
const actualNames = existsSync(GENERATED_DIRECTORY)
  ? readdirSync(GENERATED_DIRECTORY).filter((name) => name.endsWith('.json') && !EXTERNALLY_OWNED_GENERATED_FILES.has(name)).sort()
  : [];
const expectedNames = [...expected.keys()].sort();

const differences = [];
if (actualNames.join('\n') !== expectedNames.join('\n')) differences.push('generated file inventory differs');
for (const [name, value] of expected) {
  const path = generatedPath(name);
  if (!existsSync(path)) {
    differences.push(`${name} is missing`);
    continue;
  }
  if (readFileSync(path, 'utf8') !== stableJson(value)) differences.push(`${name} is stale`);
}

if (differences.length > 0) {
  console.error(`Roku canonical inputs are not current: ${differences.join('; ')}.`);
  console.error('Run npm run contracts:generate from the Roku project.');
  process.exitCode = 1;
} else {
  console.log(`Verified ${expectedNames.length} deterministic Roku contract artifacts.`);
}
