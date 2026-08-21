function PorticoViewerPreferencesDefaults() as object
    return {
        profileServer: {
            localization: {locale: "en-US", timeZone: "UTC", dateFormat: "medium", hourCycle: "auto"},
            home: {rowOrder: [], hiddenRowIds: []},
            playback: {
                autoplayNext: true, upNextCountdownSeconds: 10, passoutProtection: true, passoutAfterEpisodes: 3,
                introSkip: "ask", creditsSkip: "ask", startedThresholdPercent: 5, playedThresholdPercent: 95,
                skipBackSeconds: 10, skipForwardSeconds: 30, defaultSpeed: 1.0,
                preferredAudioLanguages: ["original"], preferredSubtitleLanguages: [], subtitlesEnabled: false,
                subtitleSize: "medium", subtitleBackground: "subtle", showSyncedLyrics: true
            },
            music: {shuffleDefault: false, repeatDefault: "none", autoplayDefault: true, audioNormalization: "off", crossfadeSeconds: 0, gapless: true},
            privacy: {pauseWatchHistory: false, showActivityToMembers: true, includeInWatchWithFriends: true},
            search: {rememberHistory: true, recentQueries: []},
            downloads: {quality: {mode: "ask"}, deleteWatched: false}
        },
        profileDeviceClass: {
            deviceClass: "television",
            appearance: {density: "comfortable", cardSizePercent: 100, showBackdrops: true},
            navigation: {sidebarCollapsed: false, pinnedLibraryIds: [], defaultLanding: "home"},
            playback: {
                deliveryRequest: {directPlay: "prefer", directStream: "allow", transcode: "allow"},
                quality: {
                    local: {mode: "original", allowHDR: true}, wifi: {mode: "automatic", allowHDR: true},
                    cellular: {mode: "data-saver", maxVideoBitrateMbps: 4, maxAudioBitrateKbps: 192, maxVideoHeight: 720, allowHDR: false},
                    unknown: {mode: "automatic", allowHDR: false}
                }
            }
        },
        accountServerInstallation: {rememberAccount: true, profileSelection: "ask"}
    }
end function

function PorticoViewerPreferencesDocument(value as dynamic, kind as string) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> "v1" then return invalid
    revision = PorticoProfilesInteger(value.revision, -1)
    if revision < 0 or value.values = invalid or Type(value.values) <> "roAssociativeArray" then return invalid
    normalized = PorticoViewerPreferencesNormalizeValues(value.values, kind)
    if normalized = invalid then return invalid
    return {version: "v1", revision: revision, values: normalized}
end function

function PorticoViewerPreferencesBundle(value as dynamic, expected as object) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.identity = invalid or Type(value.identity) <> "roAssociativeArray" then return invalid
    identity = value.identity
    if LCase(PorticoProfilesSafeText(identity.authority, 16)) <> expected.authority then return invalid
    for each key in ["accountId", "serverId", "profileId", "installationId"]
        if PorticoProfilesSafeId(identity[key]) <> expected[key] then return invalid
    end for
    if LCase(PorticoProfilesSafeText(identity.deviceClass, 20)) <> "television" then return invalid
    profileServer = PorticoViewerPreferencesDocument(value.profileServer, "profile-server")
    profileDevice = PorticoViewerPreferencesDocument(value.profileDeviceClass, "profile-device-class")
    effectiveDevice = PorticoViewerPreferencesDocument(value.effectiveProfileDeviceClass, "profile-device-class")
    accountInstallation = PorticoViewerPreferencesDocument(value.accountServerInstallation, "account-server-installation")
    if profileServer = invalid or profileDevice = invalid or effectiveDevice = invalid or accountInstallation = invalid then return invalid
    return {identity: expected, profileServer: profileServer, profileDeviceClass: profileDevice, effectiveProfileDeviceClass: effectiveDevice, accountServerInstallation: accountInstallation}
end function

function PorticoViewerPreferencesNormalizeValues(value as object, kind as string) as dynamic
    allowed = invalid
    if kind = "profile-server" then allowed = ["localization", "home", "playback", "music", "privacy", "search", "downloads"]
    if kind = "profile-device-class" then allowed = ["deviceClass", "appearance", "navigation", "playback"]
    if kind = "account-server-installation" then allowed = ["rememberAccount", "profileSelection", "lastProfileId"]
    if allowed = invalid then return invalid
    for each key in value
        if not PorticoViewerPreferencesArrayContains(allowed, key) then return invalid
    end for
    encoded = FormatJson(value)
    if Len(encoded) < 2 or Len(encoded) > 131072 then return invalid
    clone = ParseJson(encoded)
    if clone = invalid then return invalid
    if kind = "profile-server"
        for each required in ["localization", "home", "playback", "music", "privacy", "search", "downloads"]
            if clone[required] = invalid or Type(clone[required]) <> "roAssociativeArray" then return invalid
        end for
        if not PorticoViewerPreferencesProfileServerValid(clone) then return invalid
    else if kind = "profile-device-class"
        if LCase(PorticoProfilesSafeText(clone.deviceClass, 20)) <> "television" then return invalid
        if clone.appearance = invalid or clone.navigation = invalid or clone.playback = invalid then return invalid
        if Type(clone.appearance) <> "roAssociativeArray" or Type(clone.navigation) <> "roAssociativeArray" or Type(clone.playback) <> "roAssociativeArray" then return invalid
    else
        if Type(clone.rememberAccount) <> "roBoolean" and Type(clone.rememberAccount) <> "Boolean" then return invalid
        mode = LCase(PorticoProfilesSafeText(clone.profileSelection, 20))
        if mode <> "ask" and mode <> "last-used" then return invalid
        if clone.lastProfileId <> invalid and PorticoProfilesSafeId(clone.lastProfileId) = "" then return invalid
    end if
    return clone
end function

function PorticoViewerPreferencesProfileServerValid(value as object) as boolean
    playback = value.playback
    privacy = value.privacy
    home = value.home
    search = value.search
    if Type(playback) <> "roAssociativeArray" or Type(privacy) <> "roAssociativeArray" or Type(home) <> "roAssociativeArray" or Type(search) <> "roAssociativeArray" then return false
    for each key in ["autoplayNext", "passoutProtection", "subtitlesEnabled", "showSyncedLyrics"]
        if not PorticoViewerPreferencesBoolean(playback[key]) then return false
    end for
    if not PorticoViewerPreferencesIntegerAllowed(playback.upNextCountdownSeconds, [0,5,10,15]) then return false
    if not PorticoViewerPreferencesIntegerAllowed(playback.passoutAfterEpisodes, [2,3,4,5]) then return false
    if not PorticoViewerPreferencesIntegerAllowed(playback.skipBackSeconds, [5,10,15,30]) then return false
    if not PorticoViewerPreferencesIntegerAllowed(playback.skipForwardSeconds, [10,15,30,45]) then return false
    intro = LCase(PorticoProfilesSafeText(playback.introSkip, 16))
    credits = LCase(PorticoProfilesSafeText(playback.creditsSkip, 16))
    if (intro <> "ask" and intro <> "automatic" and intro <> "off") or (credits <> "ask" and credits <> "automatic" and credits <> "off") then return false
    if not PorticoViewerPreferencesLanguageArray(playback.preferredAudioLanguages) or not PorticoViewerPreferencesLanguageArray(playback.preferredSubtitleLanguages) then return false
    for each key in ["pauseWatchHistory", "showActivityToMembers", "includeInWatchWithFriends"]
        if not PorticoViewerPreferencesBoolean(privacy[key]) then return false
    end for
    if not PorticoViewerPreferencesBoolean(search.rememberHistory) then return false
    if search.recentQueries = invalid or GetInterface(search.recentQueries, "ifArray") = invalid or search.recentQueries.Count() > 20 then return false
    for each query in search.recentQueries
        if PorticoProfilesSafeText(query, 160) = "" then return false
    end for
    for each key in ["rowOrder", "hiddenRowIds"]
        list = home[key]
        if list = invalid or GetInterface(list, "ifArray") = invalid or list.Count() > 100 then return false
        for each id in list
            if PorticoProfilesSafeId(id) = "" then return false
        end for
    end for
    return true
end function

function PorticoViewerPreferencesBoolean(value as dynamic) as boolean
    return Type(value) = "Boolean" or Type(value) = "roBoolean"
end function

function PorticoViewerPreferencesIntegerAllowed(value as dynamic, allowed as object) as boolean
    number = PorticoProfilesInteger(value, -9999)
    for each candidate in allowed
        if number = candidate then return true
    end for
    return false
end function

function PorticoViewerPreferencesLanguageArray(value as dynamic) as boolean
    if value = invalid or GetInterface(value, "ifArray") = invalid or value.Count() > 12 then return false
    for each raw in value
        if PorticoProfilesSafeText(raw, 64) = "" then return false
    end for
    return true
end function

function PorticoViewerPreferencesProjection(bundle as dynamic) as object
    defaults = PorticoViewerPreferencesDefaults()
    if bundle = invalid then return {status: "unavailable", values: defaults, revisions: {profileServer: 0, profileDeviceClass: 0, accountServerInstallation: 0}}
    accountValues = ParseJson(FormatJson(bundle.accountServerInstallation.values))
    if accountValues.lastProfileId <> invalid
        accountValues.Delete("lastProfileId")
        accountValues.hasLastProfile = true
    end if
    profileValues = ParseJson(FormatJson(bundle.profileServer.values))
    if profileValues.search <> invalid and Type(profileValues.search) = "roAssociativeArray" then profileValues.search.Delete("recentQueries")
    return {
        status: "ready",
        values: {profileServer: profileValues, profileDeviceClass: bundle.effectiveProfileDeviceClass.values, accountServerInstallation: accountValues},
        revisions: {profileServer: bundle.profileServer.revision, profileDeviceClass: bundle.profileDeviceClass.revision, accountServerInstallation: bundle.accountServerInstallation.revision}
    }
end function

' This encrypted record is a navigation hint plus a separately revocable server
' trust. It is never an authorization grant by itself. Profile activation still
' has to redeem or re-establish authority through the canonical server flow.
function PorticoViewerPreferencesLaunchRecord(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> 1 or value.purpose <> "profile-launch" then return invalid
    authority = LCase(PorticoProfilesSafeText(value.authority, 16))
    if authority <> "hosted" and authority <> "local" then return invalid
    result = {
        version: 1,
        purpose: "profile-launch",
        authority: authority,
        accountId: PorticoProfilesSafeId(value.accountId),
        serverId: PorticoProfilesSafeId(value.serverId),
        installationId: PorticoProfilesSafeId(value.installationId),
        profileSelection: LCase(PorticoProfilesSafeText(value.profileSelection, 20)),
        lastProfileId: PorticoProfilesSafeId(value.lastProfileId),
        preferenceRevision: PorticoProfilesInteger(value.preferenceRevision, -1),
        trust: invalid,
        restorePolicy: invalid
    }
    if result.accountId = "" or result.serverId = "" or result.preferenceRevision < 0 then return invalid
    if result.profileSelection <> "ask" and result.profileSelection <> "last-used" then return invalid
    if result.profileSelection = "last-used" and result.lastProfileId = "" then return invalid
    if value.trust <> invalid
        trust = PorticoViewerPreferencesAutomaticTrust(value.trust, result)
        if trust = invalid then return invalid
        result.trust = trust
    end if
    if value.restorePolicy <> invalid
        restorePolicy = PorticoViewerPreferencesRestorePolicy(value.restorePolicy, result)
        if restorePolicy = invalid then return invalid
        result.restorePolicy = restorePolicy
    end if
    return result
end function

' Cached restore evidence is deliberately narrower than the native session. It
' describes the exact live profile directory observed after viewer activation;
' it never grants access to a locked or multi-profile account while offline.
function PorticoViewerPreferencesRestorePolicy(value as dynamic, expected as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> 1 or value.purpose <> "profile-restore-policy" then return invalid
    authorizationRevision = PorticoProfilesSafeId(value.authorizationRevision)
    profileId = PorticoProfilesSafeId(value.profileId)
    eligibleProfileCount = PorticoProfilesInteger(value.eligibleProfileCount, -1)
    pinRevision = PorticoProfilesInteger(value.profilePinRevision, -1)
    if authorizationRevision = "" or profileId = "" or eligibleProfileCount < 1 or eligibleProfileCount > 8 or pinRevision < 0 then return invalid
    if Type(value.profileHasPIN) <> "roBoolean" and Type(value.profileHasPIN) <> "Boolean" then return invalid
    if expected <> invalid and profileId <> PorticoProfilesSafeId(expected.lastProfileId) then return invalid
    return {
        version: 1,
        purpose: "profile-restore-policy",
        authorizationRevision: authorizationRevision,
        profileId: profileId,
        eligibleProfileCount: eligibleProfileCount,
        profileHasPIN: value.profileHasPIN = true,
        profilePinRevision: pinRevision
    }
end function

function PorticoViewerPreferencesDirectoryRestorePolicy(directory as dynamic, profileId as string, authorizationRevision as string) as dynamic
    profile = PorticoProfilesFind(directory, profileId)
    revision = PorticoProfilesSafeId(authorizationRevision)
    if directory = invalid or profile = invalid or revision = "" then return invalid
    eligibleCount = directory.profiles.Count()
    if directory.profilesAllowed = false
        if not profile.isPrimary then return invalid
        eligibleCount = 1
    end if
    if eligibleCount < 1 or eligibleCount > 8 then return invalid
    return PorticoViewerPreferencesRestorePolicy({
        version: 1,
        purpose: "profile-restore-policy",
        authorizationRevision: revision,
        profileId: profile.id,
        eligibleProfileCount: eligibleCount,
        profileHasPIN: profile.hasPIN,
        profilePinRevision: profile.pinRevision
    }, {lastProfileId: profile.id})
end function

function PorticoViewerPreferencesOfflineRestoreAllowed(launch as dynamic, session as dynamic) as boolean
    if launch = invalid or session = invalid or Type(session) <> "roAssociativeArray" or launch.restorePolicy = invalid then return false
    authority = LCase(PorticoProfilesSafeText(session.authority, 16))
    accountId = PorticoProfilesSafeId(session.accountId)
    serverId = PorticoProfilesSafeId(session.serverId)
    installationId = PorticoProfilesSafeId(session.installationId)
    profileId = PorticoProfilesSafeId(session.profileId)
    authorizationRevision = PorticoProfilesSafeId(session.authorizationRevision)
    if authority = "" or accountId = "" or serverId = "" or profileId = "" or authorizationRevision = "" then return false
    if launch.authority <> authority or launch.accountId <> accountId or launch.serverId <> serverId then return false
    policy = PorticoViewerPreferencesRestorePolicy(launch.restorePolicy, {lastProfileId: profileId})
    if policy = invalid then return false
    if policy.authorizationRevision <> authorizationRevision or policy.profileId <> profileId then return false
    return policy.eligibleProfileCount = 1 and policy.profileHasPIN = false
end function

function PorticoViewerPreferencesAutomaticTrust(value as dynamic, expected as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> "v1" or value.purpose <> "automatic-profile-selection" then return invalid
    authority = LCase(PorticoProfilesSafeText(value.authority, 16))
    accountId = PorticoProfilesSafeId(value.accountId)
    serverId = PorticoProfilesSafeId(value.serverId)
    installationId = PorticoProfilesSafeId(value.installationId)
    profileId = PorticoProfilesSafeId(value.profileId)
    token = PorticoProfilesSafeText(value.token, 2048)
    pinRevision = PorticoProfilesInteger(value.pinRevision, -1)
    expiresAt = PorticoProfilesSafeText(value.expiresAt, 64)
    if authority <> "hosted" and authority <> "local" then return invalid
    if accountId = "" or serverId = "" or profileId = "" or token = "" or pinRevision < 0 or expiresAt = "" then return invalid
    if expected <> invalid
        if authority <> expected.authority or accountId <> expected.accountId or serverId <> expected.serverId then return invalid
        expectedProfileId = PorticoProfilesSafeId(expected.lastProfileId)
        if expectedProfileId <> "" and profileId <> expectedProfileId then return invalid
    end if
    timer = CreateObject("roTimespan")
    if timer = invalid or timer.GetSecondsToISO8601Date(expiresAt) <= 0 then return invalid
    return {version: "v1", purpose: "automatic-profile-selection", token: token, authority: authority, accountId: accountId, serverId: serverId, installationId: installationId, profileId: profileId, pinRevision: pinRevision, expiresAt: expiresAt}
end function

function PorticoViewerPreferencesReadLaunch(authority as string, accountId as string, serverId as string, installationId as string) as dynamic
    record = PorticoSecureRegistryRead("profile-launch")
    if not record.ok or record.payload = invalid then return invalid
    targetAuthority = LCase(authority)
    targetAccount = PorticoProfilesSafeId(accountId)
    targetServer = PorticoProfilesSafeId(serverId)
    entries = PorticoViewerPreferencesLaunchEntries(record.payload)
    for each value in entries
        if value.authority = targetAuthority and value.accountId = targetAccount and value.serverId = targetServer then return value
    end for
    return invalid
end function

function PorticoViewerPreferencesCommitLaunch(expected as object, document as object, trust = invalid as dynamic, restorePolicy = invalid as dynamic) as boolean
    if expected = invalid or document = invalid or document.values = invalid then return false
    mode = LCase(PorticoProfilesSafeText(document.values.profileSelection, 20))
    profileId = PorticoProfilesSafeId(document.values.lastProfileId)
    if mode <> "ask" and mode <> "last-used" then return false
    if restorePolicy = invalid
        prior = PorticoViewerPreferencesReadLaunch(expected.authority, expected.accountId, expected.serverId, expected.installationId)
        if prior <> invalid and prior.lastProfileId = profileId and prior.restorePolicy <> invalid
            priorPolicy = PorticoViewerPreferencesRestorePolicy(prior.restorePolicy, {lastProfileId: profileId})
            if priorPolicy <> invalid and priorPolicy.authorizationRevision = PorticoProfilesSafeId(expected.authorizationRevision) then restorePolicy = priorPolicy
        end if
    end if
    payload = {
        version: 1,
        purpose: "profile-launch",
        authority: expected.authority,
        accountId: expected.accountId,
        serverId: expected.serverId,
        installationId: expected.installationId,
        profileSelection: mode,
        lastProfileId: profileId,
        preferenceRevision: document.revision
    }
    if trust <> invalid
        checked = PorticoViewerPreferencesAutomaticTrust(trust, payload)
        if checked = invalid then return false
        payload.trust = checked
    end if
    if restorePolicy <> invalid
        checkedPolicy = PorticoViewerPreferencesRestorePolicy(restorePolicy, payload)
        if checkedPolicy = invalid then return false
        payload.restorePolicy = checkedPolicy
    end if
    checkedPayload = PorticoViewerPreferencesLaunchRecord(payload)
    if checkedPayload = invalid then return false
    entries = []
    stored = PorticoSecureRegistryRead("profile-launch")
    if stored.ok and stored.payload <> invalid then entries = PorticoViewerPreferencesLaunchEntries(stored.payload)
    nextEntries = [checkedPayload]
    for each entry in entries
        same = entry.authority = checkedPayload.authority and entry.accountId = checkedPayload.accountId and entry.serverId = checkedPayload.serverId
        if not same and nextEntries.Count() < 8 then nextEntries.Push(entry)
    end for
    cache = {version: 1, purpose: "profile-launch-cache", entries: nextEntries}
    return PorticoSecureRegistryCommit("profile-launch", cache).ok
end function

function PorticoViewerPreferencesLaunchEntries(payload as dynamic) as object
    result = []
    single = PorticoViewerPreferencesLaunchRecord(payload)
    if single <> invalid then return [single]
    if payload = invalid or Type(payload) <> "roAssociativeArray" or payload.version <> 1 or payload.purpose <> "profile-launch-cache" then return result
    if payload.entries = invalid or GetInterface(payload.entries, "ifArray") = invalid or payload.entries.Count() > 8 then return result
    keys = {}
    for each raw in payload.entries
        entry = PorticoViewerPreferencesLaunchRecord(raw)
        if entry <> invalid
            key = entry.authority + "|" + entry.accountId + "|" + entry.serverId
            if keys[key] <> true
                keys[key] = true
                result.Push(entry)
            end if
        end if
    end for
    return result
end function

sub PorticoViewerPreferencesClearLaunch()
    PorticoSecureRegistryClear("profile-launch")
end sub

function PorticoViewerPreferencesForgetLaunch(authority as string, accountId as string, serverId as string, installationId as string) as boolean
    record = PorticoSecureRegistryRead("profile-launch")
    if not record.ok or record.payload = invalid then return true
    targetAuthority = LCase(authority)
    targetAccount = PorticoProfilesSafeId(accountId)
    targetServer = PorticoProfilesSafeId(serverId)
    retained = []
    for each entry in PorticoViewerPreferencesLaunchEntries(record.payload)
        same = entry.authority = targetAuthority and entry.accountId = targetAccount and entry.serverId = targetServer
        if not same then retained.Push(entry)
    end for
    if retained.Count() = 0 then return PorticoSecureRegistryClear("profile-launch")
    return PorticoSecureRegistryCommit("profile-launch", {version: 1, purpose: "profile-launch-cache", entries: retained}).ok
end function

function PorticoViewerPreferencesSafePatch(scopeType as string, changes as dynamic) as dynamic
    if changes = invalid or Type(changes) <> "roAssociativeArray" then return invalid
    allowed = invalid
    if scopeType = "profile-server" then allowed = ["localization", "home", "playback", "music", "privacy", "search", "downloads"]
    if scopeType = "profile-device-class" then allowed = ["appearance", "navigation", "playback"]
    if scopeType = "account-server-installation" then allowed = ["rememberAccount", "profileSelection"]
    if allowed = invalid then return invalid
    for each key in changes
        if not PorticoViewerPreferencesArrayContains(allowed, key) then return invalid
    end for
    encoded = FormatJson(changes)
    if Len(encoded) < 2 or Len(encoded) > 32768 then return invalid
    return ParseJson(encoded)
end function

function PorticoViewerPreferencesArrayContains(values as object, target as string) as boolean
    for each value in values
        if value = target then return true
    end for
    return false
end function
