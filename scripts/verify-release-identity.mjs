#!/usr/bin/env node

import {releaseIdentityDocument, resolveRokuReleaseIdentity} from "./lib/roku-release-policy.mjs";

try {
  const identity = resolveRokuReleaseIdentity();
  const document = releaseIdentityDocument(identity);
  if (process.argv.includes("--json")) console.log(JSON.stringify(document, null, 2));
  else console.log(`Roku ${identity.status}: ${identity.version} build ${identity.buildNumber} (${identity.environment}).`);
} catch (error) {
  console.error(`Roku release identity rejected: ${error.message}`);
  process.exitCode = 1;
}
