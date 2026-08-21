export function conservativeRokuCapabilityProfile({name = 'Roku', osVersion = 'unknown'} = {}) {
  const maxWidth = 1920;
  const maxHeight = 1080;
  return {
    capabilitySchemaVersion: 'playback-capability-v2', clientFamily: 'roku', clientVersion: osVersion,
    device: `Portico on ${name}`, platform: 'Roku', supportsHls: true, supportsMse: false, supportsMpegTs: false,
    supportedContainers: ['hls', 'mp4', 'm4a'], supportedVideoCodecs: ['h264'], supportedAudioCodecs: ['aac'],
    maxWidth, maxHeight, maxAudioChannels: 2, maxVideoBitDepth: 8, supportsHevc: false, supportsHdr: false, supportsEac3: false, supportsAc3: false,
    supportedVideoProfiles: ['h264:main'], supportedPixelFormats: ['yuv420p'], supportedHdrFormats: [], supportedDolbyVisionProfiles: [],
    prefersServerProxy: true, requiresServerProxy: true,
    // Identity is runtime-derived; exact decode/container/audio tuples are not.
    // The server's reviewed Roku OS fallback owns baseline compatibility until
    // a future device probe verifies every tuple on the active hardware.
    capabilityEvidence: [],
  };
}
