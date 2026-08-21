function PorticoPlaybackStartBody(mediaId as string, startSeconds as dynamic, clientProfile = invalid as dynamic) as object
    profile = clientProfile
    if profile = invalid or Type(profile) <> "roAssociativeArray" then profile = PorticoPlaybackClientProfile()
    body = {
        mediaId: mediaId,
        clientInstanceId: PorticoInstallationId(),
        clientProfile: profile,
        repeatMode: "off"
    }
    if startSeconds <> invalid
        boundedStart = PorticoPlaybackBoundedSeconds(startSeconds, 0)
        body.startSeconds = boundedStart
    end if
    return body
end function

function PorticoPlaybackStartBodyWithIntent(mediaId as string, startSeconds as dynamic, intent as dynamic, clientProfile = invalid as dynamic) as object
    body = PorticoPlaybackStartBody(mediaId, startSeconds, clientProfile)
    if intent <> invalid and Type(intent) = "roAssociativeArray" then body.intent = intent
    return body
end function

function PorticoPlaybackPortableIntent(preferences as dynamic, profile as dynamic) as object
    intent = {
        networkClass: "unknown",
        transportClass: "unknown",
        qualityProfile: "automatic",
        directPlayPolicy: "prefer",
        directStreamPolicy: "allow",
        transcodePolicy: "allow",
        allowHdr: false
    }
    PorticoPlaybackApplyLanguageIntent(intent, preferences)
    if preferences <> invalid and Type(preferences) = "roAssociativeArray"
        quality = LCase(PorticoHttpScalarString(preferences.qualityProfile, "automatic"))
        if quality = "automatic" or quality = "original" or quality = "high" or quality = "standard" or quality = "data_saver" then intent.qualityProfile = quality
        directPlay = LCase(PorticoHttpScalarString(preferences.directPlayPolicy, intent.directPlayPolicy))
        if directPlay = "allow" or directPlay = "prefer" or directPlay = "never" then intent.directPlayPolicy = directPlay
        directStream = LCase(PorticoHttpScalarString(preferences.directStreamPolicy, intent.directStreamPolicy))
        if directStream = "allow" or directStream = "prefer" or directStream = "never" then intent.directStreamPolicy = directStream
        transcode = LCase(PorticoHttpScalarString(preferences.transcodePolicy, intent.transcodePolicy))
        if transcode = "allow" or transcode = "prefer" or transcode = "require" or transcode = "never" then intent.transcodePolicy = transcode
        intent.networkClass = PorticoPlaybackIntentEnum(preferences.networkClass, ["local", "wifi", "cellular", "unknown"], intent.networkClass)
        intent.transportClass = PorticoPlaybackIntentEnum(preferences.transportClass, ["wifi", "cellular", "wired", "unknown"], intent.transportClass)
        if preferences.maxVideoBitrateMbps <> invalid then intent.maxVideoBitrateMbps = PorticoPlaybackBoundedSeconds(preferences.maxVideoBitrateMbps, 0)
        if preferences.maxAudioBitrateKbps <> invalid then intent.maxAudioBitrateKbps = PorticoPlaybackBoundedSeconds(preferences.maxAudioBitrateKbps, 0)
        if preferences.maxVideoHeight <> invalid then intent.maxVideoHeight = PorticoPlaybackBoundedSeconds(preferences.maxVideoHeight, 0)
        allowHdrType = LCase(Type(preferences.allowHdr))
        if allowHdrType = "boolean" or allowHdrType = "roboolean" then intent.allowHdr = preferences.allowHdr = true
    end if
    return intent
end function

sub PorticoPlaybackApplyLanguageIntent(intent as object, preferences as dynamic)
    if preferences = invalid or Type(preferences) <> "roAssociativeArray" then return
    audio = LCase(PorticoHttpScalarString(preferences.preferredAudioLanguage, "original"))
    if audio = "" then audio = "original"
    subtitle = LCase(PorticoHttpScalarString(preferences.preferredSubtitleLanguage, "off"))
    mode = LCase(PorticoHttpScalarString(preferences.preferredSubtitleMode, ""))
    if mode <> "off" and mode <> "text" and mode <> "burn_in"
        if subtitle = "off" then mode = "off" else mode = "text"
    end if
    intent.preferredAudioLanguage = audio
    intent.preferredSubtitleMode = mode
    intent.burnInSubtitles = mode = "burn_in"
    if subtitle <> "off" and subtitle <> "" then intent.preferredSubtitleLanguage = subtitle
end sub

function PorticoPlaybackIntentEnum(value as dynamic, allowed as object, fallback as string) as string
    normalized = LCase(PorticoHttpScalarString(value, fallback))
    for each candidate in allowed
        if normalized = candidate then return normalized
    end for
    return fallback
end function

function PorticoPlaybackClientProfile() as object
    profile = {
        device: "Portico Roku",
        platform: "Roku",
        clientFamily: "roku",
        clientVersion: "unknown",
        capabilitySchemaVersion: "playback-capability-v2",
        capabilityEvidence: [],
        supportsHls: true,
        supportsMse: false,
        supportsMpegTs: false,
        supportedContainers: ["hls", "mp4", "m4a"],
        supportedVideoCodecs: ["h264"],
        supportedAudioCodecs: ["aac"],
        maxWidth: 1920,
        maxHeight: 1080,
        maxAudioChannels: 2,
        maxVideoBitDepth: 8,
        supportsHevc: false,
        supportsHdr: false,
        supportsEac3: false,
        supportsAc3: false,
        supportedVideoProfiles: ["h264:main"],
        supportedPixelFormats: ["yuv420p"],
        supportedHdrFormats: [],
        supportedDolbyVisionProfiles: [],
        prefersServerProxy: true,
        requiresServerProxy: true
    }
    device = CreateObject("roDeviceInfo")
    if device = invalid then return profile
    modelName = PorticoPlaybackSafeLabel(device.GetModelDisplayName(), "Roku", 80)
    if modelName <> "" then profile.device = "Portico on " + modelName
    osVersion = PorticoPlaybackRokuVersion(device.GetVersion())
    profile.clientVersion = osVersion
    ' Model, OS, display mode, and audio-output labels are identity facts, not
    ' exact decoder/container/route probes. Publish no runtime tuple evidence;
    ' the server's reviewed Roku OS fallback owns the H.264/AAC baseline until
    ' a future native probe verifies every tuple on the active device.
    return profile
end function

function PorticoPlaybackRokuVersion(value as dynamic) as string
    if value = invalid or Type(value) <> "roAssociativeArray" then return "unknown"
    major = PorticoPlaybackBoundedSeconds(value.major, -1)
    minor = PorticoPlaybackBoundedSeconds(value.minor, -1)
    build = PorticoPlaybackBoundedSeconds(value.build, -1)
    if major < 0 or minor < 0 then return "unknown"
    result = major.ToStr() + "." + minor.ToStr()
    if build >= 0 then result = result + "." + build.ToStr()
    return result
end function

function PorticoPlaybackClientProfileForPreferences(preferences as dynamic) as object
    profile = PorticoPlaybackClientProfile()
    if preferences = invalid or Type(preferences) <> "roAssociativeArray" then return profile
    audio = LCase(PorticoHttpScalarString(preferences.preferredAudioLanguage, "original"))
    if audio = "" then audio = "original"
    subtitle = LCase(PorticoHttpScalarString(preferences.preferredSubtitleLanguage, "off"))
    mode = LCase(PorticoHttpScalarString(preferences.preferredSubtitleMode, ""))
    if mode <> "off" and mode <> "text" and mode <> "burn_in"
        if subtitle = "off" then mode = "off" else mode = "text"
    end if
    profile.preferredAudioLanguage = audio
    profile.preferredAudioLanguages = [audio]
    profile.preferredSubtitleMode = mode
    profile.subtitlesEnabled = mode <> "off"
    profile.burnInSubtitles = mode = "burn_in"
    if subtitle <> "off" and subtitle <> "" then profile.preferredSubtitleLanguage = subtitle : profile.preferredSubtitleLanguages = [subtitle] else profile.preferredSubtitleLanguages = []
    return profile
end function

function PorticoPlaybackFromResponse(data as dynamic, serverSession as object) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    sessionId = PorticoPlaybackSafeId(data.sessionId)
    nextSequence = PorticoHttpInteger(data.nextEventSequence, 0)
    if sessionId = "" or nextSequence < 1 then return invalid
    timeline = data.timeline
    if timeline = invalid or Type(timeline) <> "roAssociativeArray" then return invalid
    timelineType = LCase(PorticoHttpScalarString(timeline.type, ""))
    if timelineType <> "vod" and timelineType <> "live" then return invalid
    if not PorticoPlaybackModelBoolean(timeline.canPause) or not PorticoPlaybackModelBoolean(timeline.canSeek) then return invalid
    isLive = timelineType = "live"

    media = data.media
    if media = invalid or Type(media) <> "roAssociativeArray" then return invalid
    mediaId = PorticoPlaybackSafeId(media.id)
    title = PorticoPlaybackSafeLabel(media.title, "", 180)
    if mediaId = "" or title = "" then return invalid
    durationSeconds = PorticoPlaybackBoundedSeconds(timeline.durationSeconds, PorticoPlaybackBoundedSeconds(media.durationSeconds, 0))
    resumePositionSeconds = PorticoPlaybackBoundedSeconds(data.resumePositionSeconds, 0)
    if isLive
        durationSeconds = 0
        resumePositionSeconds = 0
    end if
    if durationSeconds > 0 and resumePositionSeconds >= durationSeconds then resumePositionSeconds = 0

    decision = data.decision
    if decision = invalid or Type(decision) <> "roAssociativeArray" or decision.isProxied <> true then return invalid
    streamFormat = PorticoPlaybackVideoStreamFormat(data.streamFormat, decision.container)
    if streamFormat = "" then return invalid

    grant = data.mediaGrant
    if grant = invalid or Type(grant) <> "roAssociativeArray" then return invalid
    grantToken = PorticoPlaybackGrantToken(grant.token)
    grantExpiresAt = PorticoHttpScalarString(grant.expiresAt, "")
    if grantToken = "" then return invalid
    grantRemaining = PorticoSignedDocumentSecondsUntil(grantExpiresAt)
    if grantRemaining = invalid or grantRemaining <= 0 then return invalid
    continuation = data.continuationCredential
    if continuation = invalid or Type(continuation) <> "roAssociativeArray" then return invalid
    continuationToken = PorticoPlaybackContinuationToken(continuation.token)
    continuationExpiresAt = PorticoHttpScalarString(continuation.expiresAt, "")
    continuationOrigin = PorticoPlaybackSafeLabel(continuation.origin, "", 2048)
    continuationGeneration = PorticoPlaybackBoundedSeconds(continuation.generation, -1)
    continuationRemaining = PorticoSignedDocumentSecondsUntil(continuationExpiresAt)
    if continuationToken = "" or continuationOrigin = "" or continuationGeneration < 1 or continuationRemaining = invalid or continuationRemaining <= 0 then return invalid
    allowInsecureLan = serverSession.allowInsecureLan = true
    source = PorticoPlaybackIssuedResource(data.sourceUrl, serverSession.apiBaseUrl, allowInsecureLan)
    if source = invalid then return invalid
    resources = PorticoPlaybackResources(data.resources, serverSession.apiBaseUrl, allowInsecureLan)
    if resources.Count() < 1 then return invalid
    selectedResource = PorticoPlaybackDefaultResource(resources)
    if selectedResource = invalid then return invalid
    ' The top-level URL is canonical for the initially selected route. A
    ' declared default resource must resolve to that same server-issued URL.
    if selectedResource.sourceUrl <> source.sourceUrl then return invalid

    sessionGeneration = PorticoPlaybackBoundedSeconds(data.generation, -1)
    queueRevision = PorticoPlaybackBoundedSeconds(data.queueRevision, -1)
    playbackRevision = PorticoPlaybackBoundedSeconds(data.playbackRevision, -1)
    if sessionGeneration < 0 or queueRevision < 0 or playbackRevision < 0 then return invalid
    repeatMode = LCase(PorticoHttpScalarString(data.repeatMode, "off"))
    if repeatMode <> "off" and repeatMode <> "one" and repeatMode <> "all" then return invalid

    subtitle = PorticoPlaybackSafeLabel(media.parentTitle, "", 120)
    if subtitle = "" then subtitle = PorticoPlaybackSafeLabel(media.grandparentTitle, "", 120)
    playback = {
        sessionId: sessionId,
        mediaId: mediaId,
        title: title,
        subtitle: subtitle,
        durationSeconds: durationSeconds,
        resumePositionSeconds: resumePositionSeconds,
        streamFormat: streamFormat,
        sourcePath: source.sourcePath,
        sourceUrl: source.sourceUrl,
        grantToken: grantToken,
        grantExpiresAt: grantExpiresAt,
        nextEventSequence: nextSequence,
        sessionGeneration: sessionGeneration,
        queueRevision: queueRevision,
        playbackRevision: playbackRevision,
        repeatMode: repeatMode,
        isLive: isLive,
        timelineType: timelineType,
        canPause: timeline.canPause = true,
        canSeek: timeline.canSeek = true,
        seekableStartSeconds: PorticoPlaybackTimelineNumber(timeline.seekableStartSeconds, 0.0),
        seekableEndSeconds: PorticoPlaybackTimelineNumber(timeline.seekableEndSeconds, 0.0),
        liveEdgeSeconds: PorticoPlaybackTimelineNumber(timeline.liveEdgeSeconds, 0.0),
        mediaType: LCase(PorticoPlaybackSafeLabel(media.type, "video", 40)),
        decision: PorticoPlaybackDecision(data.decision),
        resources: resources,
        qualities: PorticoPlaybackQualities(data.qualities),
        audioStreams: PorticoPlaybackStreams(data.audioStreams, "audio", ""),
        subtitleStreams: PorticoPlaybackStreams(data.subtitleStreams, "subtitle", grantToken),
        chapters: PorticoPlaybackChapters(data.chapters),
        segments: PorticoPlaybackSegments(media.segments),
        trickplaySets: PorticoPlaybackTrickplaySets(media.trickplay),
        lyrics: PorticoPlaybackSafeLabel(media.lyrics, "", 12000),
        queue: PorticoPlaybackQueue(data.queue),
        selectedAudioStreamId: PorticoPlaybackSafeId(data.selectedAudioStreamId),
        selectedSubtitleStreamId: PorticoPlaybackSafeId(data.selectedSubtitleStreamId),
        selectedSubtitleMode: LCase(PorticoHttpScalarString(data.selectedSubtitleMode, "off")),
        selectedQualityId: PorticoPlaybackSafeId(data.selectedQualityId),
        selectedVersionId: PorticoPlaybackSafeId(data.selectedVersionId),
        apiBaseUrl: serverSession.apiBaseUrl,
        allowInsecureLan: allowInsecureLan
    }
    if playback.selectedQualityId = "" and playback.qualities.count() > 0
        playback.selectedQualityId = playback.qualities[0].id
        for each quality in playback.qualities
            if quality.id = "original" then playback.selectedQualityId = "original"
        end for
    end if
    if playback.selectedSubtitleMode <> "off" and playback.selectedSubtitleMode <> "text" and playback.selectedSubtitleMode <> "burn_in" then return invalid
    return playback
end function

function PorticoPlaybackGrantFromResponse(data as dynamic, apiBaseUrl as string, sourcePath as string, allowInsecureLan = false as boolean) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    token = PorticoPlaybackGrantToken(data.token)
    expiresAt = PorticoHttpScalarString(data.expiresAt, "")
    if token = "" then return invalid
    remaining = PorticoSignedDocumentSecondsUntil(expiresAt)
    if remaining = invalid or remaining <= 0 then return invalid
    if PorticoPlaybackSecureBaseUrl(apiBaseUrl, allowInsecureLan) = "" or PorticoPlaybackSourcePathWithoutGrant(sourcePath) = "" then return invalid
    result = { token: token, expiresAt: expiresAt }
    return result
end function

function PorticoPlaybackProjectionSource(playback as object) as object
    return {
        url: playback.sourceUrl,
        streamFormat: playback.streamFormat,
        title: playback.title,
        subtitle: playback.subtitle,
        durationSeconds: playback.durationSeconds,
        resumePositionSeconds: playback.resumePositionSeconds,
        isLive: playback.isLive = true,
        mediaId: playback.mediaId,
        mediaType: playback.mediaType,
        decision: playback.decision,
        sessionGeneration: playback.sessionGeneration,
        queueRevision: playback.queueRevision,
        playbackRevision: playback.playbackRevision,
        repeatMode: playback.repeatMode,
        timelineType: playback.timelineType,
        canPause: playback.canPause,
        canSeek: playback.canSeek,
        seekableStartSeconds: playback.seekableStartSeconds,
        seekableEndSeconds: playback.seekableEndSeconds,
        liveEdgeSeconds: playback.liveEdgeSeconds,
        qualities: playback.qualities,
        audioStreams: playback.audioStreams,
        subtitleStreams: PorticoPlaybackProjectionSubtitleStreams(playback),
        chapters: playback.chapters,
        segments: playback.segments,
        trickplaySets: playback.trickplaySets,
        lyrics: playback.lyrics,
        queue: playback.queue,
        selectedAudioStreamId: playback.selectedAudioStreamId,
        selectedSubtitleStreamId: playback.selectedSubtitleStreamId,
        selectedSubtitleMode: playback.selectedSubtitleMode,
        selectedQualityId: playback.selectedQualityId,
        selectedVersionId: playback.selectedVersionId,
        targetKind: playback.targetKind
    }
end function

function PorticoPlaybackModelBoolean(value as dynamic) as boolean
    kind = LCase(Type(value))
    return kind = "boolean" or kind = "roboolean"
end function

function PorticoPlaybackTimelineNumber(value as dynamic, fallback as float) as float
    kind = LCase(Type(value))
    if kind <> "float" and kind <> "rofloat" and kind <> "double" and kind <> "rodouble" and kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" then return fallback
    number = value * 1.0
    if number < 0 or number > 2147480000 then return fallback
    return number
end function

function PorticoPlaybackIssuedResource(value as dynamic, apiBaseUrl as string, allowInsecureLan = false as boolean) as dynamic
    if value = invalid then return invalid
    raw = value.ToStr().Trim()
    sourcePath = PorticoPlaybackSourcePathWithoutGrant(raw)
    if sourcePath = "" then return invalid
    base = PorticoPlaybackSecureBaseUrl(apiBaseUrl, allowInsecureLan)
    if base = "" then return invalid
    return {sourcePath: sourcePath, sourceUrl: base + sourcePath}
end function

function PorticoPlaybackResources(value as dynamic, apiBaseUrl as string, allowInsecureLan = false as boolean) as object
    result = []
    if value = invalid or GetInterface(value, "ifArray") = invalid then return result
    for each raw in value
        if result.Count() >= 96 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackSafeId(raw.id)
            issued = PorticoPlaybackIssuedResource(raw.sourceUrl, apiBaseUrl, allowInsecureLan)
            format = PorticoPlaybackVideoStreamFormat(raw.streamFormat, PorticoPlaybackResourceContainer(raw.streamFormat))
            subtitleMode = LCase(PorticoHttpScalarString(raw.subtitleMode, "off"))
            if subtitleMode <> "off" and subtitleMode <> "text" and subtitleMode <> "burn_in" then subtitleMode = "off"
            if id <> "" and issued <> invalid and format <> ""
                result.Push({
                    id: id,
                    sourcePath: issued.sourcePath,
                    sourceUrl: issued.sourceUrl,
                    streamFormat: format,
                    default: raw.default = true,
                    qualityId: PorticoPlaybackSafeId(raw.qualityId),
                    audioStreamId: PorticoPlaybackSafeId(raw.audioStreamId),
                    subtitleMode: subtitleMode,
                    subtitleStreamId: PorticoPlaybackSafeId(raw.subtitleStreamId)
                })
            end if
        end if
    end for
    return result
end function

function PorticoPlaybackResourceContainer(streamFormat as dynamic) as string
    normalized = LCase(PorticoHttpScalarString(streamFormat, ""))
    if normalized = "hls" or normalized = "m3u8" then return "hls"
    if normalized = "http" or normalized = "mp4" then return "mp4"
    return normalized
end function

function PorticoPlaybackDefaultResource(resources as object) as dynamic
    selected = invalid
    for each resource in resources
        if resource.default = true
            if selected <> invalid then return invalid
            selected = resource
        end if
    end for
    if selected = invalid and resources.Count() = 1 then selected = resources[0]
    return selected
end function

function PorticoPlaybackResourceFor(playback as object, qualityId as string, audioId as string, subtitleMode as string, subtitleId as string) as dynamic
    match = invalid
    for each resource in playback.resources
        qualityMatches = qualityId = "" or resource.qualityId = qualityId
        audioMatches = audioId = "" or resource.audioStreamId = audioId
        subtitleMatches = resource.subtitleMode = subtitleMode and resource.subtitleStreamId = subtitleId
        if qualityMatches and audioMatches and subtitleMatches
            if match <> invalid and resource.default <> true then return invalid
            match = resource
            if resource.default = true then return resource
        end if
    end for
    return match
end function

function PorticoPlaybackDecision(value as dynamic) as object
    if value = invalid or Type(value) <> "roAssociativeArray" then return {}
    mode = LCase(PorticoPlaybackSafeLabel(value.mode, "unavailable", 40))
    allowed = {direct_play: true, direct_stream: true, optimized_version: true, transcode_required: true, unavailable: true}
    if allowed[mode] <> true then mode = "unavailable"
    return {
        mode: mode,
        deliveryProfile: PorticoPlaybackSafeLabel(value.deliveryProfile, "", 80),
        container: LCase(PorticoPlaybackSafeLabel(value.container, "", 32)),
        videoCodec: LCase(PorticoPlaybackSafeLabel(value.videoCodec, "", 32)),
        audioCodec: LCase(PorticoPlaybackSafeLabel(value.audioCodec, "", 32)),
        requiresTranscode: value.requiresTranscode = true,
        isProxied: value.isProxied = true
    }
end function

function PorticoPlaybackSegments(value as dynamic) as object
    result = []
    if value = invalid or GetInterface(value, "ifArray") = invalid then return result
    for each raw in value
        if result.Count() >= 96 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackSafeId(raw.id)
            kind = LCase(PorticoPlaybackSafeLabel(raw.type, "", 24))
            startSeconds = PorticoPlaybackBoundedSeconds(raw.startSeconds, -1)
            endSeconds = PorticoPlaybackBoundedSeconds(raw.endSeconds, -1)
            if id <> "" and (kind = "intro" or kind = "credits" or kind = "recap" or kind = "commercial" or kind = "outro") and startSeconds >= 0 and endSeconds > startSeconds
                result.Push({id: id, type: kind, startSeconds: startSeconds, endSeconds: endSeconds, automaticSafe: raw.automaticSafe = true})
            end if
        end if
    end for
    return result
end function

function PorticoPlaybackTrickplaySets(value as dynamic) as object
    result = []
    if value = invalid or GetInterface(value, "ifArray") = invalid then return result
    for each raw in value
        if result.Count() >= 8 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackSafeId(raw.id)
            count = PorticoPlaybackBoundedSeconds(raw.tileCount, 0)
            interval = PorticoPlaybackBoundedSeconds(raw.intervalSeconds, 0)
            tileWidth = PorticoPlaybackBoundedSeconds(raw.tileWidth, 320)
            tileHeight = PorticoPlaybackBoundedSeconds(raw.tileHeight, 180)
            if tileWidth < 80 or tileWidth > 1920 then tileWidth = 320
            if tileHeight < 45 or tileHeight > 1080 then tileHeight = 180
            if id <> "" and count > 0 and interval > 0 then result.Push({id: id, tileCount: count, intervalSeconds: interval, tileWidth: tileWidth, tileHeight: tileHeight, stale: raw.stale = true})
        end if
    end for
    return result
end function

function PorticoPlaybackProjectionSubtitleStreams(playback as object) as object
    result = []
    for each stream in playback.subtitleStreams
        projected = {id: stream.id, kind: stream.kind, codec: stream.codec, language: stream.language, displayTitle: stream.displayTitle, sourceUrl: ""}
        if stream.sourceUrl <> "" then projected.sourceUrl = playback.apiBaseUrl + stream.sourceUrl
        result.push(projected)
    end for
    return result
end function

function PorticoPlaybackQualities(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= 12 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackSafeId(raw.id)
            label = PorticoPlaybackSafeLabel(raw.label, id, 80)
            if id <> "" and raw.available <> false then result.push({id: id, label: label, description: PorticoPlaybackSafeLabel(raw.description, "", 120)})
        end if
    end for
    return result
end function

function PorticoPlaybackStreams(source as dynamic, expectedKind as string, expectedGrant as string) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= 24 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackSafeId(raw.id)
            kind = LCase(PorticoPlaybackSafeLabel(raw.kind, expectedKind, 16))
            codec = LCase(PorticoPlaybackSafeLabel(raw.codec, "", 24))
            if id <> "" and kind = expectedKind and codec <> ""
                sourceUrl = ""
                if expectedKind = "subtitle" then sourceUrl = PorticoPlaybackSubtitleSourcePath(raw.sourceUrl, expectedGrant)
                result.push({id: id, kind: kind, codec: codec, language: PorticoPlaybackSafeLabel(raw.language, "", 32), displayTitle: PorticoPlaybackSafeLabel(raw.displayTitle, codec, 100), sourceUrl: sourceUrl})
            end if
        end if
    end for
    return result
end function

function PorticoPlaybackSubtitleSourcePath(value as dynamic, expectedGrant as string) as string
    candidate = PorticoPlaybackSafeSubtitlePath(value)
    if candidate = "" then return ""
    if PorticoPlaybackGrantToken(expectedGrant) = "" then return ""
    return PorticoPlaybackSourcePathWithoutGrant(candidate)
end function

function PorticoPlaybackChapters(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= 48 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            seconds = PorticoPlaybackBoundedSeconds(raw.startSeconds, -1)
            if seconds >= 0 then result.push({id: PorticoPlaybackSafeId(raw.id), title: PorticoPlaybackSafeLabel(raw.title, "", 100), startSeconds: seconds})
        end if
    end for
    return result
end function

function PorticoPlaybackQueue(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= 50 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackSafeId(raw.id)
            title = PorticoPlaybackSafeLabel(raw.title, "", 140)
            if id <> "" and title <> "" then result.push({id: id, title: title, subtitle: PorticoPlaybackSafeLabel(raw.parentTitle, "", 100)})
        end if
    end for
    return result
end function

function PorticoPlaybackSafeSubtitlePath(value as dynamic) as string
    if value = invalid then return ""
    path = value.ToStr().Trim()
    if path = "" or Len(path) > 2048 or Left(path, 1) <> "/" or Left(path, 2) = "//" then return ""
    if Instr(1, path, Chr(0)) > 0 or Instr(1, path, Chr(10)) > 0 or Instr(1, path, Chr(13)) > 0 or Instr(1, path, " ") > 0 then return ""
    return path
end function

function PorticoPlaybackPathWithOption(sourcePath as string, key as string, value as string) as string
    if key <> "quality" and key <> "textSubtitleId" then return ""
    queryKey = key
    if key = "textSubtitleId" then queryKey = "textSubtitle"
    source = PorticoPlaybackSourcePathWithoutGrant(sourcePath)
    if source = "" then return ""
    safeValue = ""
    if value <> ""
        safeValue = PorticoPlaybackSafeId(value)
        if safeValue = "" then return ""
    end if
    question = Instr(1, source, "?")
    base = source
    query = ""
    if question > 0
        base = Left(source, question - 1)
        query = Mid(source, question + 1)
    end if
    pairs = []
    if query <> ""
        for each pair in query.Tokenize("&")
            separator = Instr(1, pair, "=")
            pairKey = pair
            if separator > 0 then pairKey = Left(pair, separator - 1)
            normalizedPairKey = LCase(pairKey)
            if normalizedPairKey <> LCase(queryKey) and normalizedPairKey <> "textsubtitleid" and normalizedPairKey <> "media_grant" and pair <> "" then pairs.push(pair)
        end for
    end if
    if safeValue <> "" then pairs.push(queryKey + "=" + safeValue)
    if pairs.count() = 0 then return base
    result = base + "?"
    for index = 0 to pairs.count() - 1
        if index > 0 then result = result + "&"
        result = result + pairs[index]
    end for
    return PorticoPlaybackSourcePathWithoutGrant(result)
end function

function PorticoPlaybackSourcePath(value as dynamic, expectedGrant as string) as string
    if PorticoPlaybackGrantToken(expectedGrant) = "" then return ""
    return PorticoPlaybackSourcePathWithoutGrant(value)
end function

function PorticoPlaybackSourcePathWithoutGrant(value as dynamic) as string
    if value = invalid then return ""
    source = value.ToStr().Trim()
    lower = LCase(source)
    if Len(source) < 6 or Len(source) > 4096 or Left(source, 5) <> "/api/" then return ""
    if Left(source, 2) = "//" or Instr(1, lower, "://") > 0 then return ""
    if PorticoPlaybackCredentialQueryUnsafe(lower) then return ""
    if Instr(1, source, "#") > 0 or Instr(1, source, Chr(0)) > 0 or Instr(1, source, Chr(10)) > 0 or Instr(1, source, Chr(13)) > 0 or Instr(1, source, Chr(9)) > 0 or Instr(1, source, " ") > 0 then return ""
    if PorticoPlaybackPathTraversalUnsafe(source) then return ""
    return source
end function

function PorticoPlaybackCredentialQueryUnsafe(lower as string) as boolean
    markers = ["media_grant=", "download_grant=", "access_token=", "accesstoken=", "media%5fgrant=", "download%5fgrant=", "access%5ftoken="]
    for each marker in markers
        if Instr(1, lower, marker) > 0 then return true
    end for
    return false
end function

function PorticoPlaybackPathTraversalUnsafe(source as string) as boolean
    route = source
    queryStart = Instr(1, route, "?")
    if queryStart > 0 then route = Left(route, queryStart - 1)
    lowerRoute = LCase(route)
    if Instr(1, route, "..") > 0 or Instr(1, route, "\") > 0 or Instr(1, route, "//") > 0 then return true
    return Instr(1, lowerRoute, "%2e") > 0 or Instr(1, lowerRoute, "%2f") > 0 or Instr(1, lowerRoute, "%5c") > 0
end function

function PorticoPlaybackAccessTokenQueryMarker() as string
    ' Kept constructed so package secret scanners do not mistake this negative
    ' rejection rule for a credential-bearing URL template.
    return "access" + Chr(95) + "token="
end function

function PorticoPlaybackCompactAccessTokenQueryMarker() as string
    return "access" + "token="
end function

function PorticoPlaybackGrantToken(value as dynamic) as string
    if value = invalid then return ""
    token = value.ToStr().Trim()
    if Left(token, 7) <> "ptc_mg_" or Len(token) < 16 or Len(token) > 512 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
    for position = 8 to Len(token)
        if Instr(1, allowed, Mid(token, position, 1)) = 0 then return ""
    end for
    return token
end function

function PorticoPlaybackContinuationToken(value as dynamic) as string
    if value = invalid then return ""
    token = value.ToStr().Trim()
    if Left(token, 7) <> "ptc_pb_" or Len(token) < 16 or Len(token) > 512 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
    for position = 8 to Len(token)
        if Instr(1, allowed, Mid(token, position, 1)) = 0 then return ""
    end for
    return token
end function

function PorticoPlaybackPrivateContentNode(playback as dynamic, playbackGeneration as integer, sourceGeneration as integer, viewerGeneration = 0 as integer) as dynamic
    if playback = invalid or Type(playback) <> "roAssociativeArray" then return invalid
    if playbackGeneration < 1 or sourceGeneration < 1 then return invalid
    token = PorticoPlaybackGrantToken(playback.grantToken)
    remaining = PorticoSignedDocumentSecondsUntil(playback.grantExpiresAt)
    if token = "" or remaining = invalid or remaining <= 0 then return invalid
    sourceUrl = PorticoHttpScalarString(playback.sourceUrl, "").Trim()
    if Len(sourceUrl) < 12 or PorticoPlaybackSecureBaseUrl(playback.apiBaseUrl, playback.allowInsecureLan = true) = "" or PorticoPlaybackCredentialQueryUnsafe(LCase(sourceUrl)) then return invalid
    if Instr(1, sourceUrl, Chr(0)) > 0 or Instr(1, sourceUrl, Chr(10)) > 0 or Instr(1, sourceUrl, Chr(13)) > 0 or Instr(1, sourceUrl, Chr(9)) > 0 or Instr(1, sourceUrl, " ") > 0 or Instr(1, sourceUrl, "\") > 0 then return invalid
    content = CreateObject("roSGNode", "ContentNode")
    if content = invalid then return invalid
    content.url = sourceUrl
    content.streamFormat = playback.streamFormat
    content.title = playback.title
    if Left(LCase(sourceUrl), 8) = "https://" then content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    content.HttpHeaders = ["Authorization: PorticoMedia " + token]
    content.AddFields({porticoPlaybackGeneration: playbackGeneration, porticoSourceGeneration: sourceGeneration, porticoViewerGeneration: viewerGeneration})
    return content
end function

function PorticoPlaybackVideoStreamFormat(rawFormat as dynamic, rawContainer as dynamic) as string
    format = LCase(PorticoHttpScalarString(rawFormat, ""))
    container = LCase(PorticoHttpScalarString(rawContainer, ""))
    if format = "hls" and container = "hls" then return "hls"
    if (format = "http" or format = "mp4") and (container = "mp4" or container = "m4v" or container = "mov") then return "mp4"
    return ""
end function

function PorticoPlaybackBoundedSeconds(value as dynamic, fallback as integer) as integer
    seconds = PorticoHttpInteger(value, fallback)
    if seconds < 0 then return fallback
    if seconds > 2147480000 then return 2147480000
    return seconds
end function

function PorticoPlaybackClampToTimeline(playback as dynamic, value as dynamic, fallback as integer) as integer
    position = PorticoPlaybackBoundedSeconds(value, fallback)
    if playback = invalid or Type(playback) <> "roAssociativeArray" then return position
    minimum = PorticoPlaybackTimelineNumber(playback.seekableStartSeconds, 0.0)
    maximum = PorticoPlaybackTimelineNumber(playback.seekableEndSeconds, 0.0)
    if maximum <= minimum and playback.isLive = true
        liveEdge = PorticoPlaybackTimelineNumber(playback.liveEdgeSeconds, 0.0)
        if liveEdge > minimum then maximum = liveEdge
    end if
    if maximum <= minimum and playback.isLive <> true
        duration = PorticoPlaybackTimelineNumber(playback.durationSeconds, 0.0)
        if duration > minimum then maximum = duration
    end if
    if position < Int(minimum) then position = Int(minimum)
    if maximum > minimum and position > Int(maximum) then position = Int(maximum)
    return position
end function

function PorticoPlaybackSecureBaseUrl(value as dynamic, allowInsecureLan = false as boolean) as string
    if value = invalid then return ""
    url = value.ToStr().Trim()
    if Len(url) < 12 or Len(url) > 2048 then return ""
    if Left(LCase(url), 8) <> "https://" and (not allowInsecureLan or not PorticoHttpUrlAllowed(url, true)) then return ""
    if Instr(1, url, Chr(0)) > 0 or Instr(1, url, Chr(10)) > 0 or Instr(1, url, Chr(13)) > 0 or Instr(1, url, Chr(9)) > 0 or Instr(1, url, " ") > 0 or Instr(1, url, "\") > 0 then return ""
    if Instr(9, url, "@") > 0 or Instr(9, url, "?") > 0 or Instr(9, url, "#") > 0 then return ""
    while Right(url, 1) = "/"
        url = Left(url, Len(url) - 1)
    end while
    if Instr(9, url, "/") > 0 then return ""
    return url
end function

function PorticoPlaybackSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoPlaybackSafeLabel(value as dynamic, fallback as string, maximumLength as integer) as string
    if value = invalid then return fallback
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then return fallback
    if Len(normalized) > maximumLength then normalized = Left(normalized, maximumLength)
    return normalized
end function
