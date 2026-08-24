function PorticoServerSessionVersion() as integer
    return 3
end function

function PorticoServerSessionRecord(credentials as dynamic, route as dynamic, expected as dynamic) as dynamic
    if not PorticoCoreIsAssociativeArray(credentials) or not PorticoCoreIsAssociativeArray(route) or not PorticoCoreIsAssociativeArray(expected) then return invalid
    if LCase(PorticoCoreSafeText(credentials.tokenType, 16)) <> "bearer" then return invalid
    authority = LCase(PorticoCoreSafeText(credentials.authority, 16))
    if authority <> "hosted" and authority <> "local" then return invalid
    if authority <> LCase(PorticoCoreSafeText(expected.authority, 16)) then return invalid
    accountId = PorticoServerSessionId(credentials.accountId)
    serverId = PorticoServerSessionId(credentials.serverId)
    profileId = PorticoServerSessionId(credentials.profileId)
    authorizationRevision = PorticoServerSessionId(credentials.authorizationRevision)
    installationId = PorticoServerSessionId(expected.installationId)
    routeGeneration = PorticoServerSessionId(route.routeGeneration)
    if accountId = "" or serverId = "" or profileId = "" or authorizationRevision = "" or routeGeneration = "" then return invalid
    if accountId <> PorticoServerSessionId(expected.accountId) or serverId <> PorticoServerSessionId(expected.serverId) or profileId <> PorticoServerSessionId(expected.profileId) then return invalid

    accessToken = PorticoCoreSafeText(credentials.accessToken, 4096)
    refreshToken = PorticoCoreSafeText(credentials.refreshToken, 4096)
    prefixes = PorticoServerSessionTokenPrefixes(authority)
    if Left(accessToken, Len(prefixes.access)) <> prefixes.access or Len(accessToken) < 24 then return invalid
    if Left(refreshToken, Len(prefixes.refresh)) <> prefixes.refresh or Len(refreshToken) < 24 then return invalid
    accessRemaining = PorticoSignedDocumentSecondsUntil(credentials.accessExpiresAt)
    refreshRemaining = PorticoSignedDocumentSecondsUntil(credentials.refreshExpiresAt)
    if accessRemaining = invalid or accessRemaining <= 0 or refreshRemaining = invalid or refreshRemaining <= accessRemaining then return invalid

    user = credentials.user
    device = credentials.device
    if not PorticoCoreIsAssociativeArray(user) or not PorticoCoreIsAssociativeArray(device) then return invalid
    deviceId = PorticoServerSessionId(device.id)
    ' The server-issued Device and rotating refresh family are authoritative.
    ' Never turn echoed client installation metadata into a second credential.
    if deviceId = "" then return invalid
    if PorticoServerSessionId(device.userId) <> accountId then return invalid
    routeType = PorticoCoreSafeIdentifier(route.routeType, 48)
    allowInsecureLan = PorticoServerSessionRouteAllowsInsecureLan(routeType)
    apiBaseUrl = PorticoServerSessionSecureBaseUrl(route.apiBaseUrl, allowInsecureLan)
    fingerprint = PorticoCoreSafeText(route.serverPublicKeyFingerprint, 256)
    if apiBaseUrl = "" or fingerprint = "" then return invalid
    result = {
        version: PorticoServerSessionVersion(), purpose: "profile-bound-native-server-session", signedOut: false,
        authority: authority, accountId: accountId, serverId: serverId, profileId: profileId,
        authorizationRevision: authorizationRevision, routeGeneration: routeGeneration, installationId: installationId,
        serverName: PorticoServerSessionLabel(credentials.serverFriendlyName, PorticoServerSessionLabel(route.serverName, "Portico Server", 80), 80),
        profileName: PorticoServerSessionLabel(user.displayName, PorticoServerSessionLabel(user.username, "Profile", 80), 80),
        apiBaseUrl: apiBaseUrl, routeType: routeType, allowInsecureLan: allowInsecureLan,
        serverPublicKeyFingerprint: fingerprint, deviceId: deviceId,
        accessToken: accessToken, refreshToken: refreshToken,
        accessExpiresAt: PorticoCoreSafeText(credentials.accessExpiresAt, 64),
        refreshExpiresAt: PorticoCoreSafeText(credentials.refreshExpiresAt, 64)
    }
    previous = PorticoServerSessionPreviousRoute(route)
    if previous <> invalid then result.previousRoute = previous
    return result
end function

function PorticoServerSessionStored(value as dynamic) as dynamic
    if not PorticoCoreIsAssociativeArray(value) or value.signedOut = true then return invalid
    if value.version <> PorticoServerSessionVersion() or value.purpose <> "profile-bound-native-server-session" then return invalid
    authority = LCase(PorticoCoreSafeText(value.authority, 16))
    if authority <> "hosted" and authority <> "local" then return invalid
    for each field in ["accountId", "serverId", "profileId", "authorizationRevision", "routeGeneration", "deviceId"]
        if PorticoServerSessionId(value[field]) = "" then return invalid
    end for
    allowInsecureLan = PorticoServerSessionRouteAllowsInsecureLan(value.routeType)
    if value.allowInsecureLan <> allowInsecureLan then return invalid
    if PorticoServerSessionSecureBaseUrl(value.apiBaseUrl, allowInsecureLan) = "" or PorticoCoreSafeText(value.serverPublicKeyFingerprint, 256) = "" then return invalid
    accessToken = PorticoCoreSafeText(value.accessToken, 4096)
    refreshToken = PorticoCoreSafeText(value.refreshToken, 4096)
    prefixes = PorticoServerSessionTokenPrefixes(authority)
    if Left(accessToken, Len(prefixes.access)) <> prefixes.access or Len(accessToken) < 24 then return invalid
    if Left(refreshToken, Len(prefixes.refresh)) <> prefixes.refresh or Len(refreshToken) < 24 then return invalid
    if PorticoSignedDocumentSecondsUntil(value.refreshExpiresAt) = invalid or PorticoSignedDocumentSecondsUntil(value.refreshExpiresAt) <= 0 then return invalid
    if value.previousRoute <> invalid and PorticoServerSessionPreviousRoute(value) = invalid then return invalid
    return value
end function

function PorticoServerSessionRouteRecord(source as dynamic) as dynamic
    if not PorticoCoreIsAssociativeArray(source) then return invalid
    serverId = PorticoServerSessionId(source.serverId)
    fingerprint = PorticoCoreSafeText(source.serverPublicKeyFingerprint, 256)
    routeGeneration = PorticoServerSessionId(source.routeGeneration)
    routeType = PorticoCoreSafeIdentifier(source.routeType, 48)
    allowInsecureLan = PorticoServerSessionRouteAllowsInsecureLan(routeType)
    apiBaseUrl = PorticoServerSessionSecureBaseUrl(source.apiBaseUrl, allowInsecureLan)
    if serverId = "" or fingerprint = "" or routeGeneration = "" or routeType = "" or apiBaseUrl = "" then return invalid
    return {
        apiBaseUrl: apiBaseUrl, routeType: routeType, allowInsecureLan: allowInsecureLan,
        serverId: serverId, serverPublicKeyFingerprint: fingerprint, routeGeneration: routeGeneration
    }
end function

function PorticoServerSessionPreviousRoute(session as dynamic) as dynamic
    if not PorticoCoreIsAssociativeArray(session) or not PorticoCoreIsAssociativeArray(session.previousRoute) then return invalid
    current = PorticoServerSessionRouteRecord(session)
    previous = PorticoServerSessionRouteRecord(session.previousRoute)
    if current = invalid or previous = invalid then return invalid
    if previous.serverId <> current.serverId or previous.serverPublicKeyFingerprint <> current.serverPublicKeyFingerprint then return invalid
    return previous
end function

function PorticoServerSessionRequestProjection(value as dynamic, scope as dynamic, registryGeneration = 0 as integer) as dynamic
    stored = PorticoServerSessionStored(value)
    expected = PorticoViewerScopeNormalize(scope)
    if stored = invalid or expected = invalid or expected.viewerGeneration < 1 then return invalid
    actual = PorticoServerSessionScope(stored, expected.viewerGeneration)
    if actual = invalid or not PorticoViewerScopeEquals(actual, expected) then return invalid
    remaining = PorticoSignedDocumentSecondsUntil(stored.accessExpiresAt)
    if remaining = invalid or remaining <= 0 then return invalid
    allowInsecureLan = PorticoServerSessionRouteAllowsInsecureLan(stored.routeType)
    origin = PorticoServerSessionSecureBaseUrl(stored.apiBaseUrl, allowInsecureLan)
    if origin = "" then return invalid
    authMode = "portico"
    if stored.authority = "local" then authMode = "local"
    return {
        version: 1, purpose: "viewer-bound-request-session",
        authority: stored.authority, authMode: authMode,
        accountId: stored.accountId, serverId: stored.serverId, profileId: stored.profileId,
        authorizationRevision: stored.authorizationRevision, routeGeneration: stored.routeGeneration, viewerGeneration: expected.viewerGeneration,
        viewerScope: expected, installationId: stored.installationId, deviceId: stored.deviceId,
        apiBaseUrl: origin, origin: origin, accessToken: stored.accessToken,
        routeType: stored.routeType, allowInsecureLan: allowInsecureLan,
        registryGeneration: registryGeneration,
        cacheBinding: PorticoViewerScopeCanonicalIdentity(expected, false)
    }
end function

function PorticoServerSessionMigration(value as dynamic) as object
    if not PorticoCoreIsAssociativeArray(value) then return {ok: false, code: "not_found", session: invalid}
    if value.signedOut = true and value.version = PorticoServerSessionVersion() then return {ok: false, code: "signed_out", session: invalid}
    current = PorticoServerSessionStored(value)
    if current <> invalid then return {ok: true, code: "current", session: current}
    if value.version = 1 then return {ok: false, code: "legacy_reactivation_required", session: invalid}
    return {ok: false, code: "invalid_session_record", session: invalid}
end function

function PorticoServerSessionIdentityMatches(session as dynamic, identity as dynamic) as boolean
    return PorticoServerSessionRebaseIdentity(session, identity, false) <> invalid
end function

function PorticoServerSessionRebaseIdentity(session as dynamic, identity as dynamic, allowRevisionAdvance as boolean) as dynamic
    stored = PorticoServerSessionStored(session)
    if stored = invalid or not PorticoCoreIsAssociativeArray(identity) or identity.authenticated <> true then return invalid
    if LCase(PorticoCoreSafeText(identity.authority, 16)) <> stored.authority then return invalid
    expectedProvider = "local"
    if stored.authority = "hosted" then expectedProvider = "portico"
    if LCase(PorticoCoreSafeText(identity.authProvider, 16)) <> expectedProvider then return invalid
    if PorticoServerSessionId(identity.accountId) <> stored.accountId then return invalid
    if PorticoServerSessionId(identity.serverId) <> stored.serverId then return invalid
    if PorticoServerSessionId(identity.profileId) <> stored.profileId then return invalid
    revision = PorticoServerSessionId(identity.authorizationRevision)
    if revision = "" then return invalid
    if not allowRevisionAdvance and revision <> stored.authorizationRevision then return invalid
    stored.authorizationRevision = revision
    return stored
end function

function PorticoServerSessionScope(session as dynamic, viewerGeneration as integer) as dynamic
    stored = PorticoServerSessionStored(session)
    if stored = invalid or viewerGeneration < 1 then return invalid
    return PorticoViewerScopeNormalize({
        authority: stored.authority, accountId: stored.accountId, serverId: stored.serverId,
        profileId: stored.profileId, authorizationRevision: stored.authorizationRevision,
        viewerGeneration: viewerGeneration
    })
end function

function PorticoServerSessionLocalHandoffWrite(handoffId as string, selected as dynamic, response as dynamic, viewerGeneration as integer) as boolean
    id = PorticoServerSessionId(handoffId)
    if id = "" or viewerGeneration < 1 or not PorticoCoreIsAssociativeArray(selected) or not PorticoCoreIsAssociativeArray(response) then return false
    directory = response.directory
    if not PorticoCoreIsAssociativeArray(directory) or LCase(PorticoCoreSafeText(directory.authority, 16)) <> "local" then return false
    accountId = PorticoServerSessionId(directory.accountId)
    serverId = PorticoServerSessionId(directory.serverId)
    installationId = PorticoServerSessionId(selected.installationId)
    routeGeneration = PorticoServerSessionId(selected.routeGeneration)
    if accountId = "" or serverId = "" or serverId <> PorticoServerSessionId(selected.serverId) or routeGeneration = "" then return false
    token = PorticoCoreSafeText(response.accountAuthenticationToken, 4096)
    if token = "" or PorticoSignedDocumentSecondsUntil(response.expiresAt) = invalid or PorticoSignedDocumentSecondsUntil(response.expiresAt) <= 0 then return false
    payload = {
        version: 1, purpose: "local-profile-selection-handoff", handoffId: id, viewerGeneration: viewerGeneration,
        accountId: accountId, serverId: serverId, installationId: installationId,
        accountAuthenticationToken: token, expiresAt: PorticoCoreSafeText(response.expiresAt, 64),
        directory: directory,
        route: {
            apiBaseUrl: selected.apiBaseUrl, serverId: serverId,
            serverName: PorticoServerSessionLabel(selected.name, "Portico Server", 80),
            routeType: PorticoCoreSafeIdentifier(selected.routeType, 48),
            serverPublicKeyFingerprint: PorticoCoreSafeText(selected.fingerprint, 256),
            routeGeneration: routeGeneration
        }
    }
    wrote = PorticoServerSessionOneTimeWrite("portico.secure.local-profile-handoff.v1", payload)
    payload.accountAuthenticationToken = ""
    token = ""
    return wrote
end function

function PorticoServerSessionLocalHandoffConsume(handoffId as string, profileId as string, viewerGeneration as integer) as dynamic
    payload = PorticoServerSessionOneTimeConsume("portico.secure.local-profile-handoff.v1")
    if payload = invalid or payload.version <> 1 or payload.purpose <> "local-profile-selection-handoff" then return invalid
    if PorticoServerSessionId(payload.handoffId) <> PorticoServerSessionId(handoffId) or payload.viewerGeneration <> viewerGeneration
        payload.accountAuthenticationToken = ""
        return invalid
    end if
    if PorticoSignedDocumentSecondsUntil(payload.expiresAt) = invalid or PorticoSignedDocumentSecondsUntil(payload.expiresAt) <= 0
        payload.accountAuthenticationToken = ""
        return invalid
    end if
    selectedProfile = invalid
    if PorticoCoreIsAssociativeArray(payload.directory) and PorticoCoreIsArray(payload.directory.profiles)
        for each profile in payload.directory.profiles
            if PorticoCoreIsAssociativeArray(profile) and PorticoServerSessionId(profile.id) = PorticoServerSessionId(profileId) then selectedProfile = profile
        end for
    end if
    if selectedProfile = invalid
        payload.accountAuthenticationToken = ""
        return invalid
    end if
    payload.selectedProfile = selectedProfile
    return payload
end function

sub PorticoServerSessionLocalHandoffClear()
    PorticoServerSessionOneTimeClear("portico.secure.local-profile-handoff.v1")
end sub

function PorticoServerSessionScopeAssertionWrite(assertionId as string, activationSequence as integer, scope as dynamic) as boolean
    normalized = PorticoViewerScopeNormalize(scope)
    id = PorticoServerSessionId(assertionId)
    if normalized = invalid or id = "" or activationSequence < 1 then return false
    return PorticoServerSessionOneTimeWrite("portico.secure.server-scope-assertion.v1", {
        version: 1, purpose: "server-scope-assertion", assertionId: id,
        activationSequence: activationSequence, viewerGeneration: normalized.viewerGeneration,
        scope: normalized
    })
end function

function PorticoServerSessionScopeAssertionConsume(assertionId as string, activationSequence as integer, viewerGeneration as integer) as dynamic
    payload = PorticoServerSessionOneTimeConsume("portico.secure.server-scope-assertion.v1")
    if payload = invalid or payload.version <> 1 or payload.purpose <> "server-scope-assertion" then return invalid
    if PorticoServerSessionId(payload.assertionId) <> PorticoServerSessionId(assertionId) then return invalid
    if payload.activationSequence <> activationSequence or payload.viewerGeneration <> viewerGeneration then return invalid
    return PorticoViewerScopeNormalize(payload.scope)
end function

sub PorticoServerSessionScopeAssertionClear()
    PorticoServerSessionOneTimeClear("portico.secure.server-scope-assertion.v1")
end sub

function PorticoServerSessionOneTimeWrite(sectionName as string, payload as object) as boolean
    if not PorticoServerSessionOneTimeSectionAllowed(sectionName) then return false
    section = CreateObject("roRegistrySection", sectionName)
    crypto = CreateObject("roDeviceCrypto")
    plaintext = CreateObject("roByteArray")
    if section = invalid or crypto = invalid or plaintext = invalid then return false
    plaintext.FromAsciiString(FormatJson(payload))
    encrypted = crypto.Encrypt(plaintext, "channel")
    plaintext.Clear()
    if encrypted = invalid then return false
    section.Delete("value")
    encoded = encrypted.ToBase64String()
    encrypted.Clear()
    if Len(encoded) < 8 or Len(encoded) > 32768 then return false
    wrote = section.Write("value", encoded)
    encoded = ""
    if not wrote then return false
    return section.Flush()
end function

function PorticoServerSessionOneTimeConsume(sectionName as string) as dynamic
    if not PorticoServerSessionOneTimeSectionAllowed(sectionName) then return invalid
    section = CreateObject("roRegistrySection", sectionName)
    if section = invalid then return invalid
    encoded = section.Read("value")
    section.Delete("value")
    section.Flush()
    if encoded = invalid or Len(encoded) < 8 or Len(encoded) > 32768 then return invalid
    crypto = CreateObject("roDeviceCrypto")
    encrypted = CreateObject("roByteArray")
    if crypto = invalid or encrypted = invalid then return invalid
    encrypted.FromBase64String(encoded)
    encoded = ""
    if encrypted.Count() = 0 then return invalid
    plaintext = crypto.Decrypt(encrypted, "channel")
    encrypted.Clear()
    if plaintext = invalid then return invalid
    parsed = ParseJson(plaintext.ToAsciiString())
    plaintext.Clear()
    if not PorticoCoreIsAssociativeArray(parsed) then return invalid
    return parsed
end function

sub PorticoServerSessionOneTimeClear(sectionName as string)
    if not PorticoServerSessionOneTimeSectionAllowed(sectionName) then return
    section = CreateObject("roRegistrySection", sectionName)
    if section <> invalid
        section.Delete("value")
        section.Flush()
    end if
end sub

function PorticoServerSessionOneTimeSectionAllowed(sectionName as string) as boolean
    return sectionName = "portico.secure.local-profile-handoff.v1" or sectionName = "portico.secure.server-scope-assertion.v1"
end function

function PorticoServerSessionRouteAllowsInsecureLan(routeType as dynamic) as boolean
    normalized = LCase(PorticoCoreSafeText(routeType, 48))
    return normalized = "lan" or Left(normalized, 4) = "lan_"
end function

function PorticoServerSessionTokenPrefixes(authority as string) as object
    if LCase(authority) = "hosted" then return {access: "ptc_clt_", refresh: "ptc_rft_"}
    return {access: "ptc_loc_", refresh: "ptc_lrf_"}
end function

function PorticoServerSessionSecureBaseUrl(value as dynamic, allowInsecureLan = false as boolean) as string
    url = PorticoCoreSafeText(value, 2048)
    if Len(url) < 12 then return ""
    if Left(LCase(url), 8) <> "https://" and (not allowInsecureLan or not PorticoHttpUrlAllowed(url, true)) then return ""
    if Instr(1, url, "\") > 0 then return ""
    if Instr(9, url, "@") > 0 or Instr(9, url, "?") > 0 or Instr(9, url, "#") > 0 then return ""
    while Right(url, 1) = "/"
        url = Left(url, Len(url) - 1)
    end while
    if Instr(9, url, "/") > 0 then return ""
    return url
end function

function PorticoServerSessionId(value as dynamic) as string
    return PorticoViewerScopeOpaqueId(value, 128)
end function

function PorticoServerSessionLabel(value as dynamic, fallback as string, maximum as integer) as string
    normalized = PorticoCoreSafeText(value, maximum)
    if normalized = "" then normalized = fallback
    return normalized
end function
