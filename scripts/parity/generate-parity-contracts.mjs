#!/usr/bin/env node

import {mkdirSync, readFileSync, writeFileSync} from "node:fs";
import {join} from "node:path";
import {PARITY_CONTRACT_FILES, PARITY_SOURCE_DIRECTORY, REPOSITORY_ROOT, stableJson, validateParityFiles} from "./parity-contracts.mjs";

validateParityFiles();
const outputDirectory = join(REPOSITORY_ROOT, "channel", "data", "parity");
mkdirSync(outputDirectory, {recursive: true});
for (const name of PARITY_CONTRACT_FILES) {
  const value = JSON.parse(readFileSync(join(PARITY_SOURCE_DIRECTORY, name), "utf8"));
  writeFileSync(join(outputDirectory, name), stableJson(value));
}
console.log(`Generated ${PARITY_CONTRACT_FILES.length} Roku parity contracts.`);
