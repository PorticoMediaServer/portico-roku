function PorticoPlaybackPreferencesRead() as object
    defaults = PorticoPlaybackPreferencesDefaults()
    section = CreateObject("roRegistrySection", "portico-playback-preferences")
    if section = invalid or not section.Exists("value") then return defaults
    serialized = section.Read("value")
    if serialized = invalid or Len(serialized) > 2048 then return defaults
    parsed = ParseJson(serialized)
    if parsed = invalid or Type(parsed) <> "roAssociativeArray" or (parsed.version <> 1 and parsed.version <> 2) then return defaults
    return PorticoPlaybackPreferencesSanitize(parsed)
end function

function PorticoPlaybackPreferencesDefaults() as object
    return {
        version: 2,
        autoplayNext: true,
        upNextCountdownSeconds: 10,
        passoutProtection: true,
        passoutAfterEpisodes: 3,
        introSkip: "ask",
        creditsSkip: "ask",
        seekBackSeconds: 10,
        seekForwardSeconds: 30,
        seekIntervalSeconds: 10,
        defaultSpeed: 1.0,
        preferredAudioLanguage: "original",
        preferredSubtitleLanguage: "off",
        preferredSubtitleMode: "off",
        qualityProfile: "automatic",
        directPlayPolicy: "prefer",
        directStreamPolicy: "allow",
        transcodePolicy: "allow",
        allowHdr: false,
        showSyncedLyrics: true
    }
end function

function PorticoPlaybackPreferencesUpdate(key as string, value as dynamic) as object
    preferences = PorticoPlaybackPreferencesRead()
    normalizedKey = LCase(key)
    if normalizedKey = "autoplay-next"
        if Type(value) = "Boolean" or Type(value) = "roBoolean" then preferences.autoplayNext = value = true
    else if normalizedKey = "seek-interval"
        seconds = PorticoHttpInteger(value, 10)
        if seconds = 10 or seconds = 15 or seconds = 30 then preferences.seekIntervalSeconds = seconds
    else if normalizedKey = "preferred-audio"
        language = LCase(PorticoHttpScalarString(value, "original"))
        if language = "original" or language = "en" or language = "fr" or language = "es" then preferences.preferredAudioLanguage = language
    else if normalizedKey = "preferred-subtitles"
        language = LCase(PorticoHttpScalarString(value, "off"))
        if language = "off" or language = "en" or language = "fr" or language = "es" then preferences.preferredSubtitleLanguage = language
    end if
    preferences = PorticoPlaybackPreferencesSanitize(preferences)
    section = CreateObject("roRegistrySection", "portico-playback-preferences")
    if section <> invalid
        section.Write("value", FormatJson(preferences))
        section.Flush()
    end if
    return preferences
end function

function PorticoPlaybackPreferencesSanitize(source as object) as object
    if source = invalid or Type(source) <> "roAssociativeArray" then return PorticoPlaybackPreferencesDefaults()
    seek = PorticoHttpInteger(source.seekIntervalSeconds, 10)
    if seek <> 10 and seek <> 15 and seek <> 30 then seek = 10
    audio = LCase(PorticoHttpScalarString(source.preferredAudioLanguage, "original"))
    if audio <> "original" and audio <> "en" and audio <> "fr" and audio <> "es" then audio = "original"
    subtitles = LCase(PorticoHttpScalarString(source.preferredSubtitleLanguage, "off"))
    if subtitles <> "off" and subtitles <> "en" and subtitles <> "fr" and subtitles <> "es" then subtitles = "off"
    subtitleMode = LCase(PorticoHttpScalarString(source.preferredSubtitleMode, ""))
    if subtitleMode <> "off" and subtitleMode <> "text" and subtitleMode <> "burn_in"
        if subtitles = "off" then subtitleMode = "off" else subtitleMode = "text"
    end if
    autoplay = true
    if Type(source.autoplayNext) = "Boolean" or Type(source.autoplayNext) = "roBoolean" then autoplay = source.autoplayNext = true
    defaults = PorticoPlaybackPreferencesDefaults()
    countdown = PorticoHttpInteger(source.upNextCountdownSeconds, defaults.upNextCountdownSeconds)
    if countdown <> 0 and countdown <> 5 and countdown <> 10 and countdown <> 15 then countdown = defaults.upNextCountdownSeconds
    passoutAfter = PorticoHttpInteger(source.passoutAfterEpisodes, defaults.passoutAfterEpisodes)
    if passoutAfter < 2 or passoutAfter > 5 then passoutAfter = defaults.passoutAfterEpisodes
    intro = LCase(PorticoHttpScalarString(source.introSkip, defaults.introSkip))
    credits = LCase(PorticoHttpScalarString(source.creditsSkip, defaults.creditsSkip))
    if intro <> "ask" and intro <> "automatic" and intro <> "off" then intro = defaults.introSkip
    if credits <> "ask" and credits <> "automatic" and credits <> "off" then credits = defaults.creditsSkip
    seekBack = PorticoHttpInteger(source.seekBackSeconds, seek)
    if seekBack <> 5 and seekBack <> 10 and seekBack <> 15 and seekBack <> 30 then seekBack = seek
    seekForward = PorticoHttpInteger(source.seekForwardSeconds, seek)
    if seekForward <> 10 and seekForward <> 15 and seekForward <> 30 and seekForward <> 45 then seekForward = seek
    speed = PorticoPlaybackPreferenceSpeed(source.defaultSpeed, 1.0)
    passout = defaults.passoutProtection
    if Type(source.passoutProtection) = "Boolean" or Type(source.passoutProtection) = "roBoolean" then passout = source.passoutProtection = true
    lyrics = defaults.showSyncedLyrics
    if Type(source.showSyncedLyrics) = "Boolean" or Type(source.showSyncedLyrics) = "roBoolean" then lyrics = source.showSyncedLyrics = true
    quality = LCase(PorticoHttpScalarString(source.qualityProfile, defaults.qualityProfile))
    if quality = "data-saver" then quality = "data_saver"
    if quality <> "automatic" and quality <> "original" and quality <> "high" and quality <> "standard" and quality <> "data_saver" then quality = defaults.qualityProfile
    directPlay = LCase(PorticoHttpScalarString(source.directPlayPolicy, defaults.directPlayPolicy))
    if directPlay <> "allow" and directPlay <> "prefer" and directPlay <> "never" then directPlay = defaults.directPlayPolicy
    directStream = LCase(PorticoHttpScalarString(source.directStreamPolicy, defaults.directStreamPolicy))
    if directStream <> "allow" and directStream <> "prefer" and directStream <> "never" then directStream = defaults.directStreamPolicy
    transcode = LCase(PorticoHttpScalarString(source.transcodePolicy, defaults.transcodePolicy))
    if transcode <> "allow" and transcode <> "prefer" and transcode <> "require" and transcode <> "never" then transcode = defaults.transcodePolicy
    allowHdr = false
    if Type(source.allowHdr) = "Boolean" or Type(source.allowHdr) = "roBoolean" then allowHdr = source.allowHdr = true
    return {
        version: 2, autoplayNext: autoplay, upNextCountdownSeconds: countdown,
        passoutProtection: passout, passoutAfterEpisodes: passoutAfter,
        introSkip: intro, creditsSkip: credits,
        seekBackSeconds: seekBack, seekForwardSeconds: seekForward, seekIntervalSeconds: seek,
        defaultSpeed: speed, preferredAudioLanguage: audio, preferredSubtitleLanguage: subtitles, preferredSubtitleMode: subtitleMode,
        qualityProfile: quality, directPlayPolicy: directPlay, directStreamPolicy: directStream,
        transcodePolicy: transcode, allowHdr: allowHdr,
        showSyncedLyrics: lyrics
    }
end function

function PorticoPlaybackPreferencesFromViewer(value as dynamic) as object
    if value = invalid or Type(value) <> "roAssociativeArray" then return PorticoPlaybackPreferencesDefaults()
    source = value
    if value.profileServer <> invalid and Type(value.profileServer) = "roAssociativeArray" and value.profileServer.playback <> invalid then source = value.profileServer.playback
    mapped = {
        autoplayNext: source.autoplayNext,
        upNextCountdownSeconds: source.upNextCountdownSeconds,
        passoutProtection: source.passoutProtection,
        passoutAfterEpisodes: source.passoutAfterEpisodes,
        introSkip: source.introSkip,
        creditsSkip: source.creditsSkip,
        seekBackSeconds: source.skipBackSeconds,
        seekForwardSeconds: source.skipForwardSeconds,
        defaultSpeed: source.defaultSpeed,
        showSyncedLyrics: source.showSyncedLyrics
    }
    if source.preferredAudioLanguages <> invalid and GetInterface(source.preferredAudioLanguages, "ifArray") <> invalid and source.preferredAudioLanguages.Count() > 0 then mapped.preferredAudioLanguage = source.preferredAudioLanguages[0]
    if source.preferredSubtitleLanguages <> invalid and GetInterface(source.preferredSubtitleLanguages, "ifArray") <> invalid and source.preferredSubtitleLanguages.Count() > 0
        mapped.preferredSubtitleLanguage = source.preferredSubtitleLanguages[0]
    else
        mapped.preferredSubtitleLanguage = "off"
    end if
    mapped.preferredSubtitleMode = LCase(PorticoHttpScalarString(source.preferredSubtitleMode, ""))
    if mapped.preferredSubtitleMode = "" then
        if mapped.preferredSubtitleLanguage = "off" then mapped.preferredSubtitleMode = "off" else mapped.preferredSubtitleMode = "text"
    end if
    devicePlayback = invalid
    if value.profileDeviceClass <> invalid and Type(value.profileDeviceClass) = "roAssociativeArray" and value.profileDeviceClass.playback <> invalid and Type(value.profileDeviceClass.playback) = "roAssociativeArray"
        devicePlayback = value.profileDeviceClass.playback
    end if
    if devicePlayback <> invalid
        delivery = devicePlayback.deliveryRequest
        if delivery <> invalid and Type(delivery) = "roAssociativeArray"
            mapped.directPlayPolicy = delivery.directPlay
            mapped.directStreamPolicy = delivery.directStream
            mapped.transcodePolicy = delivery.transcode
        end if
        quality = devicePlayback.quality
        if quality <> invalid and Type(quality) = "roAssociativeArray" and quality.unknown <> invalid and Type(quality.unknown) = "roAssociativeArray"
            mapped.qualityProfile = quality.unknown.mode
            mapped.allowHdr = quality.unknown.allowHDR
        end if
    end if
    mapped.seekIntervalSeconds = mapped.seekBackSeconds
    return PorticoPlaybackPreferencesSanitize(mapped)
end function

function PorticoPlaybackPreferencesTransientUpdate(current as dynamic, key as string, value as dynamic) as object
    source = current
    if source = invalid or Type(source) <> "roAssociativeArray" then source = PorticoPlaybackPreferencesDefaults()
    clone = ParseJson(FormatJson(source))
    normalized = LCase(key)
    if normalized = "autoplay-next"
        clone.autoplayNext = value = true
    else if normalized = "seek-interval"
        clone.seekIntervalSeconds = value
        clone.seekBackSeconds = value
        clone.seekForwardSeconds = value
    else if normalized = "preferred-audio"
        clone.preferredAudioLanguage = value
    else if normalized = "preferred-subtitles"
        clone.preferredSubtitleLanguage = value
    end if
    return PorticoPlaybackPreferencesSanitize(clone)
end function

function PorticoPlaybackPreferenceSpeed(value as dynamic, fallback as float) as float
    kind = LCase(Type(value))
    if kind <> "float" and kind <> "rofloat" and kind <> "double" and kind <> "rodouble" and kind <> "integer" and kind <> "roint" then return fallback
    speed = value * 1.0
    allowed = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    for each candidate in allowed
        if speed = candidate then return speed
    end for
    return fallback
end function

' Stable allowlisted contract shared by Settings, player controls, and PlaybackTask.
' Callers must not add auth, account, or server state to this projection.
function PorticoPlaybackPreferencesProjection() as object
    source = PorticoPlaybackPreferencesRead()
    return {
        version: 1,
        autoplayNext: source.autoplayNext,
        upNextCountdownSeconds: source.upNextCountdownSeconds,
        passoutProtection: source.passoutProtection,
        passoutAfterEpisodes: source.passoutAfterEpisodes,
        introSkip: source.introSkip,
        creditsSkip: source.creditsSkip,
        seekBackSeconds: source.seekBackSeconds,
        seekForwardSeconds: source.seekForwardSeconds,
        seekIntervalSeconds: source.seekIntervalSeconds,
        defaultSpeed: source.defaultSpeed,
        preferredAudioLanguage: source.preferredAudioLanguage,
        preferredSubtitleLanguage: source.preferredSubtitleLanguage,
        preferredSubtitleMode: source.preferredSubtitleMode,
        showSyncedLyrics: source.showSyncedLyrics
    }
end function

function PorticoPlaybackPreferenceLabel(kind as string, value as dynamic) as string
    normalizedKind = LCase(kind)
    normalizedValue = LCase(PorticoHttpScalarString(value, ""))
    if normalizedKind = "seek" then return PorticoHttpInteger(value, 10).ToStr() + " seconds"
    if normalizedValue = "original" then return "Original"
    if normalizedValue = "off" then return "Off"
    if normalizedValue = "en" then return "English"
    if normalizedValue = "fr" then return "French"
    if normalizedValue = "es" then return "Spanish"
    return ""
end function

function PorticoPlaybackLanguageMatches(preference as string, language as dynamic, title as dynamic) as boolean
    if preference = "original" or preference = "off" then return false
    normalized = LCase(PorticoHttpScalarString(language, "").Replace("_", "-"))
    if normalized = "" then normalized = LCase(PorticoHttpScalarString(title, ""))
    aliases = {}
    aliases.en = ["en", "eng", "english"]
    aliases.fr = ["fr", "fra", "fre", "french", "francais", "français"]
    aliases.es = ["es", "spa", "spanish", "espanol", "español"]
    candidates = aliases[preference]
    if candidates = invalid then return false
    for each alias in candidates
        if normalized = alias or Left(normalized, Len(alias) + 1) = alias + "-" then return true
    end for
    return false
end function
