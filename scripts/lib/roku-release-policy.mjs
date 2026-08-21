import {readFileSync} from "node:fs";
import {join, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const rokuRoot = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const foundationPath = join(rokuRoot, "config/release-identity.json");
const manifestPath = join(rokuRoot, "channel/manifest");
const packagePath = join(rokuRoot, "package.json");
const PLACEHOLDER = /PLACEHOLDER|REQUIRED|UNCONFIGURED|EXAMPLE|TODO|PENDING|DEVELOPMENT/i;
const PROTECTED_CHANNELS = new Set(["staging", "production", "stable", "beta"]);

function nonEmpty(value, name) {
  const result = String(value ?? "").trim();
  if (!result || /\r|\n/.test(result)) throw new Error(`${name} is required and must be one line.`);
  return result;
}

function optional(value, name) {
  const result = String(value ?? "").trim();
  if (/\r|\n/.test(result)) throw new Error(`${name} must be one line.`);
  if (result && /-----BEGIN|Bearer\s+|access[_-]?token|private[_-]?key/i.test(result)) throw new Error(`${name} contains credential material.`);
  if (result && !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(result)) throw new Error(`${name} contains unsupported identity characters.`);
  return result && !PLACEHOLDER.test(result) ? result : null;
}

function httpsOrigin(value, name) {
  const text = nonEmpty(value, name);
  let url;
  try { url = new URL(text); } catch { throw new Error(`${name} must be a valid HTTPS origin or URL.`); }
  if (url.protocol !== "https:" || !url.hostname || url.username || url.password || url.query || url.hash) throw new Error(`${name} must be HTTPS without credentials, query, or fragment.`);
  return text.replace(/\/$/, "");
}

function manifestVersion(text) {
  const major = text.match(/^major_version=(\d+)$/m)?.[1];
  const minor = text.match(/^minor_version=(\d+)$/m)?.[1];
  const build = text.match(/^build_version=(\d+)$/m)?.[1];
  if (major === undefined || minor === undefined || build === undefined) throw new Error("Roku manifest must declare numeric major/minor/build version fields.");
  return {version: `${major}.${minor}.${build}`, major: Number(major), minor: Number(minor), build: Number(build)};
}

function semver(value, name) {
  const text = nonEmpty(value, name);
  if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(text)) throw new Error(`${name} must be a semantic version.`);
  return text;
}

function positiveInteger(value, name) {
  const text = nonEmpty(value, name);
  if (!/^[1-9]\d{0,11}$/.test(text)) throw new Error(`${name} must be a positive integer.`);
  return text;
}

function nonNegativeInteger(value, name) {
  const text = nonEmpty(value, name);
  if (!/^\d{1,12}$/.test(text)) throw new Error(`${name} must be a non-negative integer.`);
  return text;
}

function commit(value, name) {
  const text = nonEmpty(value, name);
  if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(text)) throw new Error(`${name} must be an exact 40- or 64-character lowercase commit SHA.`);
  return text;
}

function countries(value, name) {
  const values = String(value ?? "").split(",").map((item) => item.trim()).filter(Boolean);
  if (values.length === 0 || values.some((item) => !/^[A-Z]{2}$/.test(item)) || new Set(values).size !== values.length) throw new Error(`${name} must be a comma-separated list of unique ISO-3166 alpha-2 country codes.`);
  return values;
}

export function foundationReleaseIdentity() {
  return JSON.parse(readFileSync(foundationPath, "utf8"));
}

export function sourceManifestVersion() {
  return manifestVersion(readFileSync(manifestPath, "utf8"));
}

export function resolveRokuReleaseIdentity(environment = process.env) {
  const foundation = foundationReleaseIdentity();
  const protectedEnvironments = new Set(foundation.safety?.protectedEnvironments ?? ["staging", "production"]);
  const envName = environment.PORTICO_ENVIRONMENT?.trim() || foundation.environment;
  const protectedRelease = protectedEnvironments.has(envName) || environment.PORTICO_RELEASE_SAFETY_CLASS === "protected";
  const manifest = sourceManifestVersion();
  const packageVersion = JSON.parse(readFileSync(packagePath, "utf8")).version;
  const versionValue = environment.PORTICO_VERSION?.trim() || (protectedRelease ? null : manifest.version || packageVersion);
  const buildNumberValue = environment.PORTICO_BUILD_NUMBER?.trim() || (protectedRelease ? null : String(manifest.build));
  const channelValue = environment.PORTICO_BUILD_CHANNEL?.trim() || (protectedRelease ? null : foundation.channel);
  const commitValue = environment.PORTICO_BUILD_COMMIT?.trim() || (protectedRelease ? null : "UNSTAMPED_DEVELOPMENT");
  const previousBuildValue = environment.PORTICO_ROKU_PREVIOUS_BUILD_NUMBER?.trim() || (protectedRelease ? null : "0");
  const publisherId = optional(environment.PORTICO_ROKU_PUBLISHER_ID, "PORTICO_ROKU_PUBLISHER_ID");
  const channelId = optional(environment.PORTICO_ROKU_CHANNEL_ID, "PORTICO_ROKU_CHANNEL_ID");
  const signingIdentity = optional(environment.PORTICO_ROKU_SIGNING_IDENTITY, "PORTICO_ROKU_SIGNING_IDENTITY");

  if (!envName || !["development", "test", "staging", "production"].includes(envName)) throw new Error("PORTICO_ENVIRONMENT is invalid.");
  if (protectedRelease) {
    for (const [name, value] of Object.entries({PORTICO_VERSION: versionValue, PORTICO_BUILD_NUMBER: buildNumberValue, PORTICO_BUILD_CHANNEL: channelValue, PORTICO_BUILD_COMMIT: commitValue, PORTICO_ROKU_PUBLISHER_ID: publisherId, PORTICO_ROKU_CHANNEL_ID: channelId, PORTICO_ROKU_SIGNING_IDENTITY: signingIdentity, PORTICO_ROKU_PRIVACY_URL: environment.PORTICO_ROKU_PRIVACY_URL, PORTICO_ROKU_STORE_COUNTRIES: environment.PORTICO_ROKU_STORE_COUNTRIES, PORTICO_ROKU_SEARCH_FEED_URL: environment.PORTICO_ROKU_SEARCH_FEED_URL, PORTICO_ROKU_DEEP_LINK_BASE_URL: environment.PORTICO_ROKU_DEEP_LINK_BASE_URL, PORTICO_ROKU_PREVIOUS_BUILD_NUMBER: previousBuildValue})) {
      if (!value || PLACEHOLDER.test(String(value))) throw new Error(`${name} is required for protected Roku packaging.`);
    }
    if (!PROTECTED_CHANNELS.has(channelValue)) throw new Error("PORTICO_BUILD_CHANNEL must identify a protected release channel.");
  }

  const version = semver(versionValue, "PORTICO_VERSION");
  const buildNumber = protectedRelease ? positiveInteger(buildNumberValue, "PORTICO_BUILD_NUMBER") : nonNegativeInteger(buildNumberValue, "PORTICO_BUILD_NUMBER");
  const previousBuildNumber = String(previousBuildValue ?? "0");
  if (!/^\d+$/.test(previousBuildNumber) || (protectedRelease ? Number(previousBuildNumber) >= Number(buildNumber) : Number(previousBuildNumber) > Number(buildNumber))) throw new Error("Roku build number must increase strictly over PORTICO_ROKU_PREVIOUS_BUILD_NUMBER.");
  const buildCommit = protectedRelease ? commit(commitValue, "PORTICO_BUILD_COMMIT") : commitValue;
  const metadata = {
    privacyUrl: protectedRelease ? httpsOrigin(environment.PORTICO_ROKU_PRIVACY_URL, "PORTICO_ROKU_PRIVACY_URL") : null,
    supportedCountries: protectedRelease ? countries(environment.PORTICO_ROKU_STORE_COUNTRIES, "PORTICO_ROKU_STORE_COUNTRIES") : [],
    searchFeedUrl: protectedRelease ? httpsOrigin(environment.PORTICO_ROKU_SEARCH_FEED_URL, "PORTICO_ROKU_SEARCH_FEED_URL") : null,
    deepLinkBaseUrl: protectedRelease ? httpsOrigin(environment.PORTICO_ROKU_DEEP_LINK_BASE_URL, "PORTICO_ROKU_DEEP_LINK_BASE_URL") : null
  };
  return Object.freeze({
    schemaVersion: 1,
    environment: envName,
    protected: protectedRelease,
    status: protectedRelease ? "protected-inputs-validated" : "development-sideload",
    version,
    buildNumber,
    previousBuildNumber,
    channel: channelValue,
    commit: buildCommit,
    publisherId,
    channelId,
    signingIdentity,
    metadata,
    foundationDefaults: {environment: foundation.environment, channel: foundation.channel, version: foundation.version, buildNumber: foundation.buildNumber}
  });
}

export function releaseIdentityDocument(identity) {
  return {
    schemaVersion: identity.schemaVersion,
    environment: identity.environment,
    status: identity.status,
    version: identity.version,
    buildNumber: identity.buildNumber,
    previousBuildNumber: identity.previousBuildNumber,
    channel: identity.channel,
    commit: identity.commit,
    publisherId: identity.publisherId,
    channelId: identity.channelId,
    signingIdentity: identity.signingIdentity,
    metadata: identity.metadata,
    evidence: identity.protected ? "source-package-input-validation-only" : "development-sideload-only"
  };
}

export function renderManifest(source, identity) {
  const parsed = manifestVersion(source);
  const match = identity.version.match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!match) throw new Error("Roku release version cannot be projected to a manifest.");
  const replacements = {major_version: match[1], minor_version: match[2], build_version: identity.buildNumber};
  let result = source;
  for (const [key, value] of Object.entries(replacements)) result = result.replace(new RegExp(`^${key}=.*$`, "m"), `${key}=${value}`);
  if (!result.endsWith("\n")) result += "\n";
  if (parsed.version === identity.version && identity.buildNumber === String(parsed.build)) return result;
  return result;
}

export function assertReleaseIdentityDocument(document, identity) {
  const expected = releaseIdentityDocument(identity);
  if (JSON.stringify(document) !== JSON.stringify(expected)) throw new Error("Roku release identity document does not match the validated package inputs.");
  return document;
}
