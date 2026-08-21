const clone = value => JSON.parse(JSON.stringify(value));

const finiteInteger = (value, fallback = 0) => {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : fallback;
};

export function clampPosition(source, value, fallback = 0) {
  const position = Math.max(0, finiteInteger(value, fallback));
  const minimum = Math.max(0, finiteInteger(source?.seekableStartSeconds, 0));
  let maximum = finiteInteger(source?.seekableEndSeconds, 0);
  if (maximum <= minimum && source?.isLive === true) maximum = finiteInteger(source?.liveEdgeSeconds, 0);
  if (maximum <= minimum && source?.isLive !== true) maximum = finiteInteger(source?.durationSeconds, 0);
  return Math.min(Math.max(position, minimum), maximum > minimum ? maximum : Number.MAX_SAFE_INTEGER);
}

export function reduceBack(input) {
  const state = clone(input);
  if (state.overlayKind) {
    state.overlayKind = '';
    return {state, action: 'close-overlay', events: []};
  }
  if (state.focusArea === 'panel') {
    state.focusArea = 'dock';
    return {state, action: 'close-panel', events: []};
  }
  if (state.focusArea === 'dock') {
    state.focusArea = 'transport';
    return {state, action: 'close-dock', events: []};
  }
  if (!state.chromeVisible) {
    state.chromeVisible = true;
    return {state, action: 'reveal-chrome', events: []};
  }
  if (state.stopEventEmitted) return {state, action: 'consume-exit', events: []};
  state.stopEventEmitted = true;
  return {
    state,
    action: 'exit',
    events: [{kind: 'stop', exitRequested: true, positionSeconds: state.positionSeconds, durationSeconds: state.durationSeconds}]
  };
}

export function createPlaybackState(source, {playbackGeneration = 1, sourceGeneration = 1} = {}) {
  const normalizedSource = clone(source);
  return {
    playbackGeneration,
    sourceGeneration,
    source: normalizedSource,
    status: 'ready',
    positionSeconds: clampPosition(normalizedSource, normalizedSource.resumePositionSeconds, 0),
    durationSeconds: normalizedSource.isLive ? 0 : Math.max(0, finiteInteger(normalizedSource.durationSeconds, 0)),
    selectedAudioStreamId: normalizedSource.selectedAudioStreamId ?? '',
    selectedSubtitleStreamId: normalizedSource.selectedSubtitleStreamId ?? '',
    grantToken: normalizedSource.grantToken ?? '',
    recoveryAttempts: 0,
    progress: [],
    progressKeys: [],
    stopEventEmitted: false
  };
}

function sourceGenerationMatches(state, event) {
  return event.sourceGeneration == null || event.sourceGeneration === 0 || event.sourceGeneration === state.sourceGeneration;
}

function appendProgress(state, kind, {completed = false, force = false} = {}) {
  const key = [state.playbackGeneration, state.sourceGeneration, kind, state.positionSeconds, completed].join(':');
  if (!force && state.progressKeys.includes(key)) return false;
  state.progressKeys.push(key);
  state.progress.push({
    sequence: state.progress.length + 1,
    kind,
    playbackGeneration: state.playbackGeneration,
    sourceGeneration: state.sourceGeneration,
    positionSeconds: state.positionSeconds,
    durationSeconds: state.durationSeconds,
    completed
  });
  return true;
}

export function applyPlaybackEvent(input, event) {
  const state = clone(input);
  if (!event || event.playbackGeneration !== state.playbackGeneration) {
    return {state, accepted: false, action: 'ignore-stale-playback'};
  }
  if (event.type !== 'source-ready' && event.type !== 'grant-renewed' && !sourceGenerationMatches(state, event)) {
    return {state, accepted: false, action: 'ignore-stale-source'};
  }

  if (event.type === 'source-ready') {
    if (!Number.isInteger(event.sourceGeneration) || event.sourceGeneration <= state.sourceGeneration) {
      return {state, accepted: false, action: 'ignore-stale-source'};
    }
    state.sourceGeneration = event.sourceGeneration;
    state.source = {...state.source, ...clone(event.source ?? {})};
    state.positionSeconds = clampPosition(state.source, event.resumePositionSeconds ?? state.positionSeconds, state.positionSeconds);
    state.durationSeconds = state.source.isLive ? 0 : Math.max(0, finiteInteger(state.source.durationSeconds, state.durationSeconds));
    state.status = event.status ?? 'ready';
    return {state, accepted: true, action: 'source-ready'};
  }

  if (event.type === 'player-state') {
    if (!['playing', 'paused', 'buffering'].includes(event.status)) return {state, accepted: false, action: 'ignore-invalid-state'};
    const previousStatus = state.status;
    const previousPosition = state.positionSeconds;
    state.status = event.status;
    state.positionSeconds = clampPosition(state.source, event.positionSeconds, state.positionSeconds);
    if (!state.source.isLive) state.durationSeconds = Math.max(0, finiteInteger(event.durationSeconds, state.durationSeconds));
    if (event.immediate === true || previousStatus !== state.status || previousPosition !== state.positionSeconds) appendProgress(state, 'state');
    return {state, accepted: true, action: 'state'};
  }

  if (event.type === 'seek') {
    state.positionSeconds = clampPosition(state.source, event.positionSeconds, state.positionSeconds);
    appendProgress(state, 'seek');
    return {state, accepted: true, action: 'seek'};
  }

  if (event.type === 'select-audio') {
    const valid = (state.source.audioStreams ?? []).some(stream => stream.id === event.streamId);
    if (!valid) return {state, accepted: false, action: 'ignore-track'};
    state.selectedAudioStreamId = event.streamId;
    return {state, accepted: true, action: 'audio-selected'};
  }

  if (event.type === 'select-subtitle') {
    if (event.off === true) {
      state.selectedSubtitleStreamId = '';
      return {state, accepted: true, action: 'subtitles-off'};
    }
    const valid = (state.source.subtitleStreams ?? []).some(stream => stream.id === event.streamId);
    if (!valid) return {state, accepted: false, action: 'ignore-track'};
    state.selectedSubtitleStreamId = event.streamId;
    return {state, accepted: true, action: 'subtitle-selected'};
  }

  if (event.type === 'grant-renewed') {
    if (!Number.isInteger(event.newSourceGeneration) || event.newSourceGeneration <= state.sourceGeneration || !event.grantToken) {
      return {state, accepted: false, action: 'ignore-stale-grant'};
    }
    state.sourceGeneration = event.newSourceGeneration;
    state.grantToken = event.grantToken;
    state.status = 'buffering';
    return {state, accepted: true, action: 'grant-renewed'};
  }

  if (event.type === 'source-error') {
    if (event.retryable !== true) {
      state.status = 'error';
      return {state, accepted: true, action: 'terminal-error'};
    }
    state.recoveryAttempts += 1;
    if (state.recoveryAttempts > 3) {
      state.status = 'error';
      return {state, accepted: true, action: 'terminal-error'};
    }
    state.status = 'buffering';
    return {state, accepted: true, action: 'recover'};
  }

  if (event.type === 'complete') {
    state.positionSeconds = clampPosition(state.source, state.durationSeconds, state.positionSeconds);
    state.status = 'ended';
    appendProgress(state, 'completed', {completed: true});
    return {state, accepted: true, action: 'complete'};
  }

  if (event.type === 'stop') {
    if (!state.stopEventEmitted) {
      state.stopEventEmitted = true;
      appendProgress(state, 'stop');
    }
    return {state, accepted: true, action: 'stop'};
  }

  return {state, accepted: false, action: 'ignore-unknown'};
}
