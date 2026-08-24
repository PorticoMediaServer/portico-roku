function PorticoSettingsModel(runtime as dynamic, language = invalid as dynamic) as object
    if runtime = invalid or Type(runtime) <> "roAssociativeArray" then runtime = {}
    profileName = PorticoSettingsText(runtime.selectedProfileName, PorticoSettingsText(runtime.accountDisplayName, "Portico Account", 100), 100)
    serverName = PorticoSettingsText(runtime.selectedServerName, PorticoSettingsCopy(language, "settings.no-server-connected", "No server connected"), 100)
    authMode = LCase(PorticoSettingsText(runtime.authMode, "hosted", 24))
    authLabel = "Portico Account"
    if authMode = "local" then authLabel = "Direct server sign-in"
    serverDescription = PorticoSettingsCopy(language, "settings.account.server-description", "Choose another server shared with this account")
    serverAction = "open-server-selection"
    if authMode = "local"
        serverDescription = "Current direct server connection"
        serverAction = "open-connection"
    end if
    serverSwitchVisible = authMode <> "local" and PorticoSettingsServerCount(runtime.availableServers) > 1
    serverRowVisible = authMode = "local" or serverSwitchVisible
    connection = PorticoSettingsConnection(runtime.serverStatus, language)
    preferenceState = PorticoSettingsPreferences(runtime.viewerPreferences)
    preferenceStatus = LCase(PorticoSettingsText(runtime.preferencesStatus, "idle", 24))
    preferenceAvailable = preferenceStatus = "ready" or preferenceStatus = "saving" or preferenceStatus = "conflict"
    online = LCase(PorticoSettingsText(runtime.serverStatus, "not-connected", 40)) = "online"
    feedback = runtime.engagementViewState
    feedbackCapabilities = invalid
    if feedback <> invalid and Type(feedback) = "roAssociativeArray" then feedbackCapabilities = feedback.feedbackCapabilities
    canFeedback = online and feedbackCapabilities <> invalid and feedbackCapabilities.enabled = true
    automatic = preferenceState.accountServerInstallation.profileSelection = "last-used"
    playback = preferenceState.profileServer.playback
    privacy = preferenceState.profileServer.privacy
    subtitle = "off"
    if playback.subtitlesEnabled = true and playback.preferredSubtitleLanguages.Count() > 0 then subtitle = playback.preferredSubtitleLanguages[0]
    audio = "original"
    if playback.preferredAudioLanguages.Count() > 0 then audio = playback.preferredAudioLanguages[0]
    preferenceMessageId = "preferences.loading-personal"
    if preferenceStatus = "error" then preferenceMessageId = "preferences.request-failed"
    if preferenceStatus = "conflict" then preferenceMessageId = "preferences.conflict"
    if preferenceStatus = "idle" then preferenceMessageId = "preferences.load-failed"
    showPreferenceState = preferenceStatus <> "ready" and preferenceStatus <> "saving"
    return {
        displayName: profileName,
        serverName: serverName,
        accountLabel: profileName + "  ·  " + serverName,
        authLabel: authLabel,
        connectionLabel: connection.label,
        connectionTone: connection.tone,
        serverAction: serverAction,
        online: online,
        preferenceStatus: preferenceStatus,
        preferenceAvailable: preferenceAvailable,
        automaticProfile: automatic,
        feedbackCapabilities: feedbackCapabilities,
        engagement: feedback,
        preferences: preferenceState,
        rows: [
            {id: "preference-state", section: "account", label: PorticoSettingsCopy(language, preferenceMessageId, "Preferences unavailable"), description: PorticoSettingsBody(language, preferenceMessageId, "Reconnect and try again."), iconId: "status.warning", kind: "action", value: PorticoSettingsCopy(language, "action.retry", "Try again"), actionable: online and preferenceStatus <> "loading", visible: showPreferenceState},
            {id: "profile", section: "account", label: profileName, description: authLabel, iconId: "account.profile", kind: "action", value: PorticoSettingsCopy(language, "profiles.label.profile", "Profile"), actionable: true, visible: true},
            {id: "server", section: "account", label: PorticoSettingsCopy(language, "settings.label.server", "Server"), description: serverDescription, iconId: "navigation.library", kind: "action", value: connection.label, actionable: serverRowVisible, visible: serverRowVisible},
            {id: "automatic-profile", section: "account", label: "Open profile automatically", description: "Open the last verified profile on this Roku.", iconId: "account.profile", kind: "toggle", checked: automatic, actionable: preferenceAvailable and online, visible: true},
            {id: "account-security", section: "account", label: "Account security", description: "Continue account and security changes on a phone or computer.", iconId: "metadata.info", kind: "action", value: "Show link", actionable: true, visible: authMode <> "local"},
            {id: "feedback", section: "account", label: PorticoSettingsCopy(language, "feedback.heading.message", "Send a message"), description: "Send a private message or report a problem to this server's owner.", iconId: "metadata.info", kind: "action", value: "", actionable: canFeedback, visible: true},
            {id: "autoplay-next", section: "playback", label: PorticoSettingsCopy(language, "preferences.playback-autoplay-label", "Autoplay next item"), description: PorticoSettingsCopy(language, "preferences.playback-autoplay-description", "Begin the next item when playback finishes."), iconId: "playback.autoplay", kind: "toggle", checked: playback.autoplayNext, actionable: preferenceAvailable and online, visible: true},
            {id: "playback-quality", section: "playback", label: PorticoSettingsCopy(language, "preferences.playback-quality-label", "Playback quality"), description: PorticoSettingsCopy(language, "preferences.playback-quality-description", "Portico automatically chooses the best format for this device."), iconId: "playback.quality", kind: "information", value: PorticoSettingsCopy(language, "settings.value.automatic", "Automatic"), actionable: false, visible: true},
            {id: "up-next", section: "playback", label: PorticoSettingsCopy(language, "preferences.up-next-label", "Up Next countdown"), description: PorticoSettingsCopy(language, "preferences.up-next-description", "Delay before autoplay begins."), iconId: "playback.autoplay", kind: "action", value: PorticoSettingsSeconds(language, playback.upNextCountdownSeconds), actionable: preferenceAvailable and online, visible: true},
            {id: "seek-interval", section: "playback", label: PorticoSettingsCopy(language, "preferences.seek-interval-label", "Skip interval"), description: PorticoSettingsCopy(language, "preferences.seek-interval-description", "Changes the player skip controls."), iconId: "preference.seek-interval", kind: "action", value: PorticoSettingsSeconds(language, playback.skipForwardSeconds), actionable: preferenceAvailable and online, visible: true},
            {id: "preferred-audio", section: "playback", label: PorticoSettingsCopy(language, "preferences.personal-playback-audio-label", "Preferred audio"), description: PorticoSettingsCopy(language, "preferences.personal-playback-audio-description", "Used when a matching audio track exists."), iconId: "playback.language", kind: "action", value: PorticoSettingsLanguageLabel(language, audio, false), actionable: preferenceAvailable and online, visible: true},
            {id: "preferred-subtitles", section: "playback", label: PorticoSettingsCopy(language, "preferences.personal-playback-subtitles-label", "Preferred subtitles"), description: PorticoSettingsCopy(language, "preferences.personal-playback-subtitles-description", "Used when matching subtitles exist."), iconId: "accessibility.captions", kind: "action", value: PorticoSettingsLanguageLabel(language, subtitle, true), actionable: preferenceAvailable and online, visible: true},
            {id: "roku-caption-style", section: "accessibility", label: "Caption appearance", description: "Text size, color, background, and contrast follow Roku Settings > Accessibility > Captions mode and Captions style.", iconId: "accessibility.captions", kind: "information", value: "Managed by Roku", actionable: false, visible: true},
            {id: "pause-history", section: "privacy", label: PorticoSettingsCopy(language, "preferences.pause-history-label", "Pause watch history"), description: PorticoSettingsCopy(language, "preferences.pause-history-description", "Do not record new plays or resume positions for this profile."), iconId: "playback.pause", kind: "toggle", checked: privacy.pauseWatchHistory, actionable: preferenceAvailable and online, visible: true},
            {id: "clear-watch-history", section: "privacy", label: PorticoSettingsCopy(language, "preferences.history-clear-label", "Clear watch history"), description: PorticoSettingsCopy(language, "preferences.history-clear-confirmation", "Deletes plays and resume positions for this account."), iconId: "action.reset", kind: "action", value: "", actionable: online, visible: true},
            {id: "clear-search-history", section: "privacy", label: PorticoSettingsCopy(language, "preferences.search-history-title", "Search history"), description: PorticoSettingsCopy(language, "search.recent-body", "Searches saved for this viewing profile."), iconId: "navigation.search", kind: "action", value: PorticoSettingsCopy(language, "action.clear-history", "Clear"), actionable: online, visible: true},
            {id: "sign-out", section: "account-action", label: PorticoSettingsCopy(language, "action.sign-out", "Sign out"), description: authLabel, iconId: "account.sign-out", kind: "action", value: "", actionable: true, visible: true}
        ]
    }
end function

function PorticoSettingsServerCount(value as dynamic) as integer
    if value = invalid or GetInterface(value, "ifArray") = invalid then return 0
    return value.Count()
end function

function PorticoSettingsPreferences(value as dynamic) as object
    defaults = PorticoViewerPreferencesDefaults()
    if value = invalid or Type(value) <> "roAssociativeArray" then return defaults
    profileServer = value.profileServer
    accountInstallation = value.accountServerInstallation
    if profileServer = invalid or Type(profileServer) <> "roAssociativeArray" then profileServer = defaults.profileServer
    if accountInstallation = invalid or Type(accountInstallation) <> "roAssociativeArray" then accountInstallation = defaults.accountServerInstallation
    playback = profileServer.playback
    privacy = profileServer.privacy
    if playback = invalid or Type(playback) <> "roAssociativeArray" then playback = defaults.profileServer.playback
    if privacy = invalid or Type(privacy) <> "roAssociativeArray" then privacy = defaults.profileServer.privacy
    result = ParseJson(FormatJson(defaults))
    if Type(playback.autoplayNext) = "Boolean" or Type(playback.autoplayNext) = "roBoolean" then result.profileServer.playback.autoplayNext = playback.autoplayNext = true
    countdown = PorticoHttpInteger(playback.upNextCountdownSeconds, 10)
    if countdown = 0 or countdown = 5 or countdown = 10 or countdown = 15 then result.profileServer.playback.upNextCountdownSeconds = countdown
    forward = PorticoHttpInteger(playback.skipForwardSeconds, 30)
    if forward = 10 or forward = 15 or forward = 30 or forward = 45 then result.profileServer.playback.skipForwardSeconds = forward
    if Type(playback.subtitlesEnabled) = "Boolean" or Type(playback.subtitlesEnabled) = "roBoolean" then result.profileServer.playback.subtitlesEnabled = playback.subtitlesEnabled = true
    result.profileServer.playback.preferredAudioLanguages = PorticoSettingsLanguages(playback.preferredAudioLanguages)
    result.profileServer.playback.preferredSubtitleLanguages = PorticoSettingsLanguages(playback.preferredSubtitleLanguages)
    if Type(privacy.pauseWatchHistory) = "Boolean" or Type(privacy.pauseWatchHistory) = "roBoolean" then result.profileServer.privacy.pauseWatchHistory = privacy.pauseWatchHistory = true
    result.accountServerInstallation = {rememberAccount: true, profileSelection: "ask"}
    if Type(accountInstallation.rememberAccount) = "Boolean" or Type(accountInstallation.rememberAccount) = "roBoolean" then result.accountServerInstallation.rememberAccount = accountInstallation.rememberAccount = true
    mode = LCase(PorticoSettingsText(accountInstallation.profileSelection, "ask", 20))
    if mode <> "ask" and mode <> "last-used" then mode = "ask"
    result.accountServerInstallation.profileSelection = mode
    return result
end function

function PorticoSettingsLanguages(value as dynamic) as object
    result = []
    if value = invalid or GetInterface(value, "ifArray") = invalid then return result
    for each raw in value
        if result.Count() >= 12 then exit for
        code = LCase(PorticoSettingsText(raw, "", 24))
        if code = "original" or code = "en" or code = "fr" or code = "es" then result.Push(code)
    end for
    return result
end function

function PorticoProfileModel(runtime as dynamic, language = invalid as dynamic) as object
    settings = PorticoSettingsModel(runtime, language)
    initial = "P"
    if settings.displayName <> "" then initial = UCase(Left(settings.displayName, 1))
    statusDetail = settings.serverName
    if settings.connectionLabel <> "" then statusDetail = statusDetail + "  ·  " + settings.connectionLabel
    return {
        displayName: settings.displayName, initial: initial, authLabel: settings.authLabel,
        serverName: settings.serverName, connectionLabel: settings.connectionLabel,
        connectionTone: settings.connectionTone, serverAction: settings.serverAction,
        statusDetail: statusDetail,
        rows: [
            {id: "server", label: PorticoSettingsCopy(language, "settings.label.server", "Server"), description: settings.serverName, iconId: "navigation.library", kind: "action", value: settings.connectionLabel, actionable: true},
            {id: "switch-profile", label: "Switch profile", description: "Choose who is watching.", iconId: "account.profile", kind: "action", value: "", actionable: true},
            {id: "settings", label: PorticoSettingsCopy(language, "settings.title", "Settings"), description: "Account, playback, and privacy preferences", iconId: "navigation.settings", kind: "action", value: "", actionable: true},
            {id: "sign-out", label: PorticoSettingsCopy(language, "action.sign-out", "Sign out"), description: settings.authLabel, iconId: "account.sign-out", kind: "action", value: "", actionable: true}
        ]
    }
end function

function PorticoSettingsConnection(value as dynamic, language = invalid as dynamic) as object
    status = LCase(PorticoSettingsText(value, "not-connected", 40))
    if status = "online" then return {label: PorticoSettingsCopy(language, "settings.value.connected", "Connected"), tone: "healthy"}
    if status = "connecting" or status = "selected" then return {label: "Connecting", tone: "account"}
    if status = "identity-mismatch" or status = "incompatible" or status = "permission-removed" or status = "blocked" then return {label: "Blocked", tone: "danger"}
    if status = "none" or status = "not-connected" then return {label: "Not connected", tone: "muted"}
    return {label: PorticoSettingsCopy(language, "settings.value.unavailable", "Unavailable"), tone: "warning"}
end function

function PorticoSettingsCopy(language as dynamic, messageId as string, fallback as string, variables = invalid as dynamic) as string
    if language = invalid then return fallback
    message = PorticoProductLanguageMessage(language, messageId, messageId, variables)
    if not message.ok then return fallback
    value = PorticoSettingsText(message.text, "", 240)
    if value = "" then value = PorticoSettingsText(message.title, "", 240)
    if value = "" then value = PorticoSettingsText(message.body, "", 240)
    if value = "" then return fallback
    return value
end function

function PorticoSettingsBody(language as dynamic, messageId as string, fallback as string, variables = invalid as dynamic) as string
    if language = invalid then return fallback
    message = PorticoProductLanguageMessage(language, messageId, messageId, variables)
    if not message.ok then return fallback
    value = PorticoSettingsText(message.body, "", 300)
    if value = "" then value = PorticoSettingsText(message.text, "", 300)
    if value = "" then return fallback
    return value
end function

function PorticoSettingsSeconds(language as dynamic, value as dynamic) as string
    seconds = PorticoHttpInteger(value, 10)
    if seconds = 0 then return PorticoSettingsCopy(language, "preferences.option-off", "Off")
    return PorticoSettingsCopy(language, "preferences.seconds-option", seconds.ToStr() + " seconds", {seconds: seconds})
end function

function PorticoSettingsLanguageLabel(language as dynamic, value as dynamic, subtitle as boolean) as string
    code = LCase(PorticoSettingsText(value, "", 24))
    if code = "en" then return PorticoSettingsCopy(language, "preferences.option-english", "English")
    if code = "fr" then return PorticoSettingsCopy(language, "preferences.option-french", "French")
    if code = "es" then return PorticoSettingsCopy(language, "preferences.option-spanish", "Spanish")
    if subtitle then return PorticoSettingsCopy(language, "preferences.option-off", "Off")
    return PorticoSettingsCopy(language, "preferences.option-original", "Original")
end function

function PorticoSettingsText(value as dynamic, fallback as string, maximum as integer) as string
    if value = invalid then return fallback
    result = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if result = "" then result = fallback
    if Len(result) > maximum then result = Left(result, maximum)
    return result
end function
