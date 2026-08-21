#!/usr/bin/env node

import {readFileSync, readdirSync} from "node:fs";
import {join} from "node:path";
import {PARITY_CONTRACT_FILES, PARITY_SOURCE_DIRECTORY, REPOSITORY_ROOT, stableJson, validateParityFiles, validateTVArchitectureDocs} from "./parity-contracts.mjs";

validateParityFiles();
validateTVArchitectureDocs();
const outputDirectory = join(REPOSITORY_ROOT, "Client Prototypes", "roku-visual-parity", "channel", "data", "parity");
const actual = readdirSync(outputDirectory).filter((name) => name.endsWith(".json")).sort();
if (actual.join("\n") !== [...PARITY_CONTRACT_FILES].sort().join("\n")) throw new Error("Roku parity contract inventory drifted.");
for (const name of PARITY_CONTRACT_FILES) {
  const source = JSON.parse(readFileSync(join(PARITY_SOURCE_DIRECTORY, name), "utf8"));
  const generated = readFileSync(join(outputDirectory, name), "utf8");
  if (generated !== stableJson(source)) throw new Error(`Roku parity contract is stale: ${name}`);
}
console.log(`Verified ${PARITY_CONTRACT_FILES.length} Roku parity contracts.`);
