sub init()
    m.top.functionName = "PorticoLocalAuthRun"
end sub

sub PorticoLocalAuthRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    controller = {
        clock: clock,
        lastCommandSequence: 0,
        status: "idle",
        message: "",
        servers: [],
        candidates: {},
        dnsByName: {},
        dnsInstances: {},
        selected: invalid,
        discovery: invalid,
        discoveryStartedAt: 0,
        lastQueryAt: -100,
        session: invalid,
        sessionGeneration: 0,
        libraryItems: [],
        navigationVerified: false,
        nextRefreshAt: 0,
        refreshFailures: 0,
        last401Generation: -1,
        viewerGeneration: 0,
        localProfileDirectory: invalid,
        localProfileHandoffId: "",
        localProfileInstallationId: ""
    }
    PorticoLocalAuthPublish(controller)
    while true
        PorticoLocalAuthHandleCommand(controller)
        PorticoLocalAuthTick(controller)
        Sleep(250)
    end while
end sub

sub PorticoLocalAuthHandleCommand(controller as object)
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return
    sequence = PorticoHttpInteger(command.sequence, 0)
    if sequence <= controller.lastCommandSequence then return
    controller.lastCommandSequence = sequence
    kind = LCase(PorticoHttpScalarString(command.kind, ""))
    commandGeneration = PorticoHttpInteger(command.viewerGeneration, 0)
    if commandGeneration > 0 and commandGeneration <> controller.viewerGeneration
        PorticoServerSessionLocalHandoffClear()
        controller.viewerGeneration = commandGeneration
        controller.localProfileDirectory = invalid
        controller.localProfileHandoffId = ""
        controller.localProfileInstallationId = ""
    end if

    if kind = "viewer-state"
        generation = commandGeneration
        if generation <> controller.viewerGeneration
            PorticoServerSessionLocalHandoffClear()
            controller.viewerGeneration = generation
            controller.localProfileDirectory = invalid
            controller.localProfileHandoffId = ""
            controller.localProfileInstallationId = ""
        end if
        PorticoLocalAuthPublish(controller)
    else if kind = "prepare-profile-switch"
        PorticoServerSessionLocalHandoffClear()
        controller.localProfileDirectory = invalid
        controller.localProfileHandoffId = ""
        controller.localProfileInstallationId = ""
        if controller.selected = invalid
            controller.status = "idle"
            controller.message = "Choose your Portico Server again to switch profiles."
        else
            ' Re-entering Local Auth credentials creates a new account-scoped,
            ' generation-bound handoff. Never derive it from the active profile.
            controller.status = "credentials"
            controller.message = ""
        end if
        PorticoLocalAuthPublish(controller)
    else if kind = "start-discovery" or kind = "retry-discovery"
        PorticoLocalAuthStartDiscovery(controller)
    else if kind = "stop-discovery"
        PorticoLocalAuthStopDiscovery(controller)
        PorticoLocalAuthDiscardDiscoveryState(controller)
        controller.status = "idle"
        controller.message = ""
        PorticoLocalAuthPublish(controller)
    else if kind = "select-server"
        PorticoLocalAuthSelectDiscovered(controller, PorticoLocalAuthSafeId(command.serverKey))
    else if kind = "manual-address"
        PorticoLocalAuthSelectManual(controller, command.address)
    else if kind = "confirm-trust"
        PorticoLocalAuthConfirmTrust(controller)
    else if kind = "submit-credentials"
        PorticoLocalAuthSubmitSealedCredentials(controller, command.sealedCredentials)
    else if kind = "retry-session"
        ' Authoritative profile-bound sessions are owned by ServerConnectionTask.
        controller.status = "profile-selection-required"
        controller.message = "Choose a profile to continue."
        PorticoLocalAuthPublish(controller)
    else if kind = "sign-out"
        PorticoLocalAuthSignOut(controller)
    else if kind = "cancel"
        PorticoLocalAuthStopDiscovery(controller)
        PorticoLocalAuthDiscardDiscoveryState(controller)
        controller.status = "idle"
        controller.message = ""
        PorticoLocalAuthPublish(controller)
    end if
end sub

sub PorticoLocalAuthTick(controller as object)
    if controller.discovery <> invalid then PorticoLocalAuthDiscoveryTick(controller)
    if controller.session <> invalid and controller.nextRefreshAt > 0 and controller.clock.TotalSeconds() >= controller.nextRefreshAt
        PorticoLocalAuthRefresh(controller, false)
    end if
end sub

sub PorticoLocalAuthStartDiscovery(controller as object)
    PorticoLocalAuthStopDiscovery(controller)
    discovery = PorticoLocalAuthOpenDiscoverySocket()
    controller.servers = []
    controller.candidates = {}
    controller.dnsByName = {}
    controller.dnsInstances = {}
    controller.discoveryStartedAt = controller.clock.TotalSeconds()
    controller.lastQueryAt = -100
    if discovery = invalid
        controller.status = "discovery-unavailable"
        controller.message = "Nearby servers couldn't be searched. Enter a secure server address instead."
    else
        controller.discovery = discovery
        controller.status = "discovering"
        controller.message = ""
        PorticoLocalAuthSendDiscoveryQuery(controller)
    end if
    PorticoLocalAuthPublish(controller)
end sub

sub PorticoLocalAuthStopDiscovery(controller as object)
    if controller.discovery = invalid then return
    if controller.discovery.socket <> invalid
        if controller.discovery.group <> invalid then controller.discovery.socket.DropGroup(controller.discovery.group)
        controller.discovery.socket.Close()
    end if
    controller.discovery = invalid
end sub

sub PorticoLocalAuthDiscardDiscoveryState(controller as object)
    controller.selected = invalid
    controller.servers = []
    controller.candidates = {}
    controller.dnsByName = {}
    controller.dnsInstances = {}
    controller.discoveryStartedAt = 0
    controller.lastQueryAt = -100
end sub

sub PorticoLocalAuthDiscoveryTick(controller as object)
    now = controller.clock.TotalSeconds()
    if now - controller.lastQueryAt >= 3 then PorticoLocalAuthSendDiscoveryQuery(controller)
    socket = controller.discovery.socket
    received = 0
    while socket <> invalid and socket.IsReadable() and received < 12
        packet = CreateObject("roByteArray")
        packet.SetResize(8192, false)
        packetLength = socket.Receive(packet, 0, 8192)
        if packetLength >= 12 then PorticoLocalAuthMergeDNSPacket(controller, packet.Slice(0, packetLength))
        received = received + 1
    end while
    PorticoLocalAuthExpireCandidates(controller)
    if controller.status = "discovering" and now - controller.discoveryStartedAt >= 8
        if controller.servers.Count() = 0
            controller.status = "no-servers"
            controller.message = "No Portico servers were found on this network."
        else
            controller.status = "servers"
            controller.message = ""
        end if
        PorticoLocalAuthPublish(controller)
    end if
end sub

sub PorticoLocalAuthSendDiscoveryQuery(controller as object)
    if controller.discovery = invalid then return
    query = PorticoLocalAuthDNSQuery()
    if query = invalid or query.Count() = 0 then return
    controller.discovery.socket.Send(query, 0, query.Count())
    controller.lastQueryAt = controller.clock.TotalSeconds()
end sub

sub PorticoLocalAuthSelectDiscovered(controller as object, serverKey as string)
    if serverKey = "" or controller.candidates[serverKey] = invalid
        controller.status = "server-unavailable"
        controller.message = "That server is no longer available."
        PorticoLocalAuthPublish(controller)
        return
    end if
    candidate = controller.candidates[serverKey]
    controller.status = "checking-server"
    controller.message = ""
    PorticoLocalAuthPublish(controller)
    secure = PorticoLocalAuthResolveSecureDiscoveredRoute(controller, candidate)
    if secure = invalid then return
    controller.selected = secure
    PorticoLocalAuthRequireTrustOrCredentials(controller)
end sub

sub PorticoLocalAuthSelectManual(controller as object, rawAddress as dynamic)
    baseUrl = PorticoLocalAuthSecureBaseUrl(rawAddress)
    if baseUrl = ""
        controller.status = "manual-address-error"
        controller.message = "Enter a valid Portico Server address on this network."
        PorticoLocalAuthPublish(controller)
        return
    end if
    controller.status = "checking-server"
    controller.message = ""
    PorticoLocalAuthPublish(controller)
    health = PorticoLocalAuthRequest(controller, "GET", baseUrl + "/api/remote-access/health", invalid, invalid, 7000)
    if health.interrupted then return
    if not health.ok
        controller.status = "server-unavailable"
        controller.message = "Portico couldn't reach a trusted server at that address."
        PorticoLocalAuthPublish(controller)
        return
    end if
    selected = PorticoLocalAuthIdentityFromHealth(baseUrl, health.data, "manual")
    if selected = invalid
        controller.status = "identity-error"
        controller.message = "The address did not return a valid Portico server identity."
        PorticoLocalAuthPublish(controller)
        return
    end if
    if not PorticoLocalAuthSystemCompatible(controller, selected.apiBaseUrl) then return
    controller.selected = selected
    PorticoLocalAuthRequireTrustOrCredentials(controller)
end sub

function PorticoLocalAuthResolveSecureDiscoveredRoute(controller as object, candidate as object) as dynamic
    if candidate.route = "" or Left(LCase(candidate.route), 7) <> "http://"
        controller.status = "identity-error"
        controller.message = "The nearby server advertisement was not valid."
        PorticoLocalAuthPublish(controller)
        return invalid
    end if
    hint = PorticoLocalAuthRequest(controller, "GET", candidate.route + "/api/remote-access/health", invalid, invalid, 4000, true)
    if hint.interrupted then return invalid
    if not hint.ok or hint.data = invalid or Type(hint.data) <> "roAssociativeArray"
        controller.status = "server-unavailable"
        controller.message = "That nearby server could not be reached."
        PorticoLocalAuthPublish(controller)
        return invalid
    end if
    if PorticoHttpScalarString(hint.data.serverPublicKeyFingerprint, "") <> candidate.fingerprint
        controller.status = "identity-error"
        controller.message = "The nearby server identity changed. No credentials were sent."
        PorticoLocalAuthPublish(controller)
        return invalid
    end if
    if candidate.serverId <> "" and PorticoLocalAuthSafeId(hint.data.serverId) <> candidate.serverId
        controller.status = "identity-error"
        controller.message = "The nearby server identity did not match its advertisement."
        PorticoLocalAuthPublish(controller)
        return invalid
    end if
    hostname = PorticoLocalAuthHostname(hint.data.assignedHostname)
    certStatus = LCase(PorticoHttpScalarString(hint.data.certificateStatus, ""))
    if hostname = "" or (certStatus <> "valid" and certStatus <> "active")
        controller.status = "secure-route-required"
        controller.message = "This server does not have a trusted secure route for direct server sign-in."
        PorticoLocalAuthPublish(controller)
        return invalid
    end if
    baseUrl = "https://" + hostname
    verified = PorticoLocalAuthRequest(controller, "GET", baseUrl + "/api/remote-access/health", invalid, invalid, 7000)
    if verified.interrupted then return invalid
    if not verified.ok
        controller.status = "secure-route-unavailable"
        controller.message = "The server's secure route could not be reached."
        PorticoLocalAuthPublish(controller)
        return invalid
    end if
    selected = PorticoLocalAuthIdentityFromHealth(baseUrl, verified.data, "discovered")
    if selected = invalid or selected.fingerprint <> candidate.fingerprint or (candidate.serverId <> "" and selected.serverId <> candidate.serverId)
        controller.status = "identity-error"
        controller.message = "The secure route did not match the nearby server identity."
        PorticoLocalAuthPublish(controller)
        return invalid
    end if
    selected.name = candidate.name
    if not PorticoLocalAuthSystemCompatible(controller, selected.apiBaseUrl) then return invalid
    return selected
end function

sub PorticoLocalAuthRequireTrustOrCredentials(controller as object)
    selected = controller.selected
    if selected = invalid then return
    pin = PorticoLocalAuthTrustPin(selected.apiBaseUrl)
    if pin <> invalid
        if pin.fingerprint <> selected.fingerprint or (pin.serverId <> "" and selected.serverId <> "" and pin.serverId <> selected.serverId)
            controller.status = "identity-changed"
            controller.message = "This server's identity has changed. Direct server sign-in was blocked."
            PorticoLocalAuthPublish(controller)
            return
        end if
        controller.status = "credentials"
        controller.message = ""
    else
        controller.status = "confirm-trust"
        controller.message = "Confirm that this is your Portico Server before signing in."
    end if
    PorticoLocalAuthPublish(controller)
end sub

sub PorticoLocalAuthConfirmTrust(controller as object)
    if controller.selected = invalid or controller.status <> "confirm-trust" then return
    if not PorticoLocalAuthPersistTrust(controller.selected)
        controller.status = "storage-error"
        controller.message = "Server trust could not be saved on this Roku."
    else
        controller.status = "credentials"
        controller.message = ""
    end if
    PorticoLocalAuthPublish(controller)
end sub

sub PorticoLocalAuthSubmitSealedCredentials(controller as object, sealed as dynamic)
    if controller.selected = invalid or controller.status <> "credentials" then return
    credentials = PorticoLocalAuthOpenSealedCredentials(sealed)
    if credentials = invalid
        controller.status = "credentials-error"
        controller.message = "The sign-in details could not be read. Enter them again."
        PorticoLocalAuthPublish(controller)
        return
    end if
    login = PorticoLocalAuthSecret(credentials.login, 320)
    password = PorticoLocalAuthSecret(credentials.password, 72)
    credentials.login = ""
    credentials.password = ""
    ' Authentication clients must not impose a stronger password policy than
    ' the Server. Existing accounts can legitimately use the Server's exact
    ' eight-character minimum, and only the Server owns credential validity.
    if login = "" or password = ""
        password = ""
        controller.status = "credentials-error"
        controller.message = "Enter your username or email and password."
        PorticoLocalAuthPublish(controller)
        return
    end if
    controller.status = "signing-in"
    controller.message = ""
    PorticoLocalAuthPublish(controller)
    if controller.viewerGeneration < 1
        login = ""
        password = ""
        controller.status = "session-error"
        controller.message = "Choose this server again to continue."
        PorticoLocalAuthPublish(controller)
        return
    end if
    installationId = PorticoInstallationId()
    if PorticoLocalAuthSafeId(controller.selected.serverId) = ""
        login = ""
        password = ""
        controller.status = "identity-error"
        controller.message = "The server did not provide a stable identity."
        PorticoLocalAuthPublish(controller)
        return
    end if
    payload = {
        login: login,
        password: password,
        purpose: "native",
        deviceName: PorticoLocalAuthDeviceName(),
        app: "Portico",
        platform: "Roku"
    }
    if installationId <> "" then payload.installationId = installationId
    response = PorticoLocalAuthRequest(controller, "POST", controller.selected.apiBaseUrl + "/api/auth/profile-authentications/local", payload, invalid, 15000)
    payload.login = ""
    payload.password = ""
    login = ""
    password = ""
    if response.interrupted then return
    if not response.ok
        controller.status = "credentials-error"
        if response.status = 401
            controller.message = "The username or password was not accepted."
        else if response.status = 403
            controller.message = "Direct server sign-in is not enabled on this server."
        else if response.status = 429
            controller.message = "Too many sign-in attempts. Wait a moment and try again."
        else
            controller.message = "Portico couldn't authenticate with this server."
        end if
        PorticoLocalAuthPublish(controller)
        return
    end if
    sourceDirectory = invalid
    if response.data <> invalid and Type(response.data) = "roAssociativeArray" then sourceDirectory = response.data.directory
    accountId = ""
    if sourceDirectory <> invalid and Type(sourceDirectory) = "roAssociativeArray" then accountId = PorticoProfilesSafeId(sourceDirectory.accountId)
    directory = PorticoProfilesDirectory(sourceDirectory, "local", accountId, PorticoLocalAuthSafeId(controller.selected.serverId))
    if directory = invalid
        controller.status = "session-error"
        controller.message = "The server did not return a usable profile directory."
        PorticoLocalAuthPublish(controller)
        return
    end if
    selected = {
        apiBaseUrl: controller.selected.apiBaseUrl, serverId: controller.selected.serverId,
        fingerprint: controller.selected.fingerprint, name: controller.selected.name,
        routeType: controller.selected.routeType, routeGeneration: controller.selected.routeGeneration,
        installationId: installationId
    }
    handoffId = PorticoHttpNewRequestId()
    if not PorticoServerSessionLocalHandoffWrite(handoffId, selected, response.data, controller.viewerGeneration)
        if response.data <> invalid and Type(response.data) = "roAssociativeArray" then response.data.accountAuthenticationToken = ""
        controller.status = "storage-error"
        controller.message = "Profile selection could not be secured on this Roku."
        PorticoLocalAuthPublish(controller)
        return
    end if
    response.data.accountAuthenticationToken = ""
    controller.localProfileDirectory = directory
    controller.localProfileHandoffId = handoffId
    controller.localProfileInstallationId = installationId
    controller.status = "profile-selection-required"
    controller.message = ""
    PorticoLocalAuthStopDiscovery(controller)
    ' Discovery candidates include LAN origins and trust fingerprints that are
    ' only needed while the user is choosing a server. Keep the authenticated
    ' session in the encrypted registry/private Task state and remove the
    ' discovery topology before publishing the signed-in projection.
    controller.servers = []
    controller.candidates = {}
    controller.dnsByName = {}
    controller.dnsInstances = {}
    PorticoLocalAuthPublish(controller)
end sub

sub PorticoLocalAuthRestore(controller as object)
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid or record.payload.signedOut = true then return
    session = PorticoLocalAuthStoredSession(record.payload)
    if session = invalid or session.authMode <> "local" then return
    controller.status = "restoring"
    controller.session = session
    controller.sessionGeneration = record.generation
    remaining = PorticoSignedDocumentSecondsUntil(session.accessExpiresAt)
    if remaining = invalid or remaining <= 60
        if not PorticoLocalAuthRefresh(controller, false) then return
    end if
    if not PorticoLocalAuthValidateIdentity(controller, controller.session) then return
    controller.status = "authenticated"
    controller.message = ""
    PorticoLocalAuthScheduleRefresh(controller)
end sub

function PorticoLocalAuthRefresh(controller as object, afterUnauthorized as boolean) as boolean
    session = controller.session
    if session = invalid then return false
    rotation = PorticoLocalAuthPendingRotation(session)
    if rotation = invalid
        controller.status = "server-unavailable"
        controller.message = "The direct server session couldn't be refreshed."
        PorticoLocalAuthPublish(controller)
        return false
    end if
    response = PorticoLocalAuthRequest(controller, "POST", session.apiBaseUrl + "/api/auth/sessions/refresh", {refreshToken: session.refreshToken, rotationKey: rotation.rotationKey}, invalid, 12000)
    if response.interrupted then return false
    if not response.ok
        if PorticoLocalAuthRefreshFailureIsTerminal(response)
            PorticoSecureRegistryClear("server-refresh-rotation")
            PorticoLocalAuthClearSession(controller, "session-expired", "Your direct server session has expired.")
        else
            controller.refreshFailures = controller.refreshFailures + 1
            if controller.refreshFailures > 6 then controller.refreshFailures = 6
            controller.nextRefreshAt = controller.clock.TotalSeconds() + 5 * (2 ^ (controller.refreshFailures - 1))
            if afterUnauthorized or PorticoSignedDocumentSecondsUntil(session.accessExpiresAt) <= 0
                controller.status = "server-unavailable"
                controller.message = "The direct server session couldn't be refreshed."
                PorticoLocalAuthPublish(controller)
            end if
        end if
        return false
    end if
    replacement = PorticoLocalAuthSessionFromCredentials({
        apiBaseUrl: session.apiBaseUrl,
        serverId: session.serverId,
        fingerprint: session.serverPublicKeyFingerprint,
        name: session.serverName,
        routeType: session.routeType, routeGeneration: session.routeGeneration
    }, response.data)
    if replacement = invalid or replacement.accountUserId <> session.accountUserId or replacement.accountDeviceId <> session.accountDeviceId
        PorticoLocalAuthClearSession(controller, "session-expired", "Your direct server session could not be renewed.")
        return false
    end if
    committed = PorticoSecureRegistryCommit("server-session", replacement)
    if not committed.ok
        ' Preserve both the old durable session and its refresh receipt. A later
        ' retry (including after restart) resubmits the exact old token/key pair
        ' and receives the same successor; storage failure is not sign-out.
        controller.refreshFailures = controller.refreshFailures + 1
        if controller.refreshFailures > 6 then controller.refreshFailures = 6
        controller.nextRefreshAt = controller.clock.TotalSeconds() + 5 * (2 ^ (controller.refreshFailures - 1))
        controller.status = "server-unavailable"
        controller.message = "The refreshed session couldn't be saved yet. Portico will retry."
        PorticoLocalAuthPublish(controller)
        return false
    end if
    controller.session = replacement
    PorticoSecureRegistryClear("server-refresh-rotation")
    controller.sessionGeneration = committed.generation
    controller.refreshFailures = 0
    PorticoLocalAuthScheduleRefresh(controller)
    if controller.status <> "authenticated"
        controller.status = "authenticated"
        controller.message = ""
        PorticoLocalAuthPublish(controller)
    end if
    return true
end function

function PorticoLocalAuthPendingRotation(session as object) as dynamic
    existing = PorticoSecureRegistryRead("server-refresh-rotation")
    if existing.ok and existing.payload <> invalid and Type(existing.payload) = "roAssociativeArray"
        if existing.payload.refreshToken = session.refreshToken and Len(PorticoHttpScalarString(existing.payload.rotationKey, "")) >= 43 then return existing.payload
    end if
    rotationKey = PorticoSecureRegistryRotationKey()
    if rotationKey = "" then return invalid
    pending = {version: 1, purpose: "crash-safe-refresh-rotation", refreshToken: session.refreshToken, rotationKey: rotationKey}
    if not PorticoSecureRegistryCommit("server-refresh-rotation", pending).ok then return invalid
    return pending
end function

function PorticoLocalAuthRefreshFailureIsTerminal(response as object) as boolean
    code = ""
    if response.problem <> invalid and Type(response.problem) = "roAssociativeArray" then code = LCase(PorticoHttpScalarString(response.problem.code, ""))
    return code = "credential_revoked" or code = "refresh_reused" or code = "account_deleted" or code = "profile_deleted" or code = "membership_removed" or code = "server_session_revoked" or code = "invalid_refresh_token" or code = "refresh_token_reuse"
end function

sub PorticoLocalAuthScheduleRefresh(controller as object)
    remaining = PorticoSignedDocumentSecondsUntil(controller.session.accessExpiresAt)
    delay = 5
    if remaining <> invalid then delay = remaining - 300
    if delay < 5 then delay = 5
    if delay > 1800 then delay = 1800
    controller.nextRefreshAt = controller.clock.TotalSeconds() + delay
end sub

function PorticoLocalAuthValidateIdentity(controller as object, session as object) as boolean
    health = PorticoLocalAuthRequest(controller, "GET", session.apiBaseUrl + "/api/remote-access/health", invalid, invalid, 7000)
    if not health.ok
        controller.status = "server-unavailable"
        controller.message = "The direct server connection is unavailable."
        PorticoLocalAuthPublish(controller)
        return false
    end if
    if health.data = invalid or PorticoHttpScalarString(health.data.serverPublicKeyFingerprint, "") <> session.serverPublicKeyFingerprint
        PorticoLocalAuthClearSession(controller, "identity-error", "The server identity could not be verified.")
        return false
    end if
    if session.serverId <> "" and PorticoLocalAuthSafeId(health.data.serverId) <> session.serverId
        PorticoLocalAuthClearSession(controller, "identity-error", "The server identity has changed.")
        return false
    end if
    identity = PorticoLocalAuthRequest(controller, "GET", session.apiBaseUrl + "/api/auth/me", invalid, {Authorization: "Bearer " + session.accessToken}, 10000)
    if identity.status = 401 and controller.last401Generation <> controller.sessionGeneration
        controller.last401Generation = controller.sessionGeneration
        if PorticoLocalAuthRefresh(controller, true)
            session = controller.session
            identity = PorticoLocalAuthRequest(controller, "GET", session.apiBaseUrl + "/api/auth/me", invalid, {Authorization: "Bearer " + session.accessToken}, 10000)
        end if
    end if
    if not identity.ok
        if PorticoLocalAuthEndpointFailureIsTerminal(identity)
            PorticoLocalAuthClearSession(controller, "session-expired", "The server did not accept this direct server session.")
        else
            controller.status = "server-unavailable"
            controller.message = "The direct server connection is unavailable."
            PorticoLocalAuthPublish(controller)
        end if
        return false
    end if
    if identity.data = invalid or identity.data.authenticated <> true or LCase(PorticoHttpScalarString(identity.data.authProvider, "")) <> "local"
        PorticoLocalAuthClearSession(controller, "session-expired", "The server did not accept this direct server session.")
        return false
    end if
    user = identity.data.user
    if user = invalid or Type(user) <> "roAssociativeArray" or PorticoLocalAuthSafeId(user.id) <> session.accountUserId
        PorticoLocalAuthClearSession(controller, "identity-error", "The server profile did not match this session.")
        return false
    end if
    contract = PorticoLocalAuthRequest(controller, "GET", session.apiBaseUrl + "/api/product-contract", invalid, {Authorization: "Bearer " + session.accessToken}, 10000)
    if not contract.ok
        if PorticoLocalAuthEndpointFailureIsTerminal(contract)
            PorticoLocalAuthClearSession(controller, "session-expired", "The server did not accept this direct server session.")
        else
            controller.status = "server-unavailable"
            controller.message = "The direct server connection is unavailable."
            PorticoLocalAuthPublish(controller)
        end if
        return false
    end if
    if contract.data = invalid or contract.data.apiVersion <> "v1"
        controller.status = "server-incompatible"
        controller.message = "Update Portico Server before using this Roku."
        PorticoLocalAuthPublish(controller)
        return false
    end if
    libraries = PorticoLocalAuthRequest(controller, "GET", session.apiBaseUrl + "/api/libraries", invalid, {Authorization: "Bearer " + session.accessToken}, 10000)
    navigation = PorticoLocalAuthRequest(controller, "GET", session.apiBaseUrl + "/api/account/library-navigation", invalid, {Authorization: "Bearer " + session.accessToken}, 10000)
    if not libraries.ok or not navigation.ok
        if PorticoLocalAuthEndpointFailureIsTerminal(libraries) or PorticoLocalAuthEndpointFailureIsTerminal(navigation)
            PorticoLocalAuthClearSession(controller, "session-expired", "The server did not accept this direct server session.")
        else
            controller.status = "server-unavailable"
            controller.message = "The direct server connection could not load your libraries."
            PorticoLocalAuthPublish(controller)
        end if
        return false
    end if
    controller.libraryItems = PorticoLocalAuthLibraryItems(libraries.data, navigation.data)
    controller.navigationVerified = true
    return true
end function

function PorticoLocalAuthEndpointFailureIsTerminal(response as object) as boolean
    code = ""
    if response.problem <> invalid and Type(response.problem) = "roAssociativeArray" then code = LCase(PorticoHttpScalarString(response.problem.code, ""))
    return code = "server_session_revoked" or code = "session_revoked" or code = "account_revoked"
end function

function PorticoLocalAuthLibraryItems(libraryResponse as dynamic, navigation as dynamic) as object
    result = []
    if libraryResponse = invalid or libraryResponse.items = invalid or GetInterface(libraryResponse.items, "ifArray") = invalid then return result
    if navigation = invalid or navigation.pinnedLibraryIds = invalid or GetInterface(navigation.pinnedLibraryIds, "ifArray") = invalid then return result
    byId = {}
    for each library in libraryResponse.items
        if library <> invalid and Type(library) = "roAssociativeArray"
            id = PorticoLocalAuthSafeId(library.id)
            name = PorticoLocalAuthSafeLabel(library.name, "", 48)
            kind = LCase(PorticoHttpScalarString(library.type, ""))
            allowedKind = kind = "movie" or kind = "show" or kind = "anime" or kind = "music" or kind = "audiobook" or kind = "recorded-tv"
            if id <> "" and name <> "" and allowedKind then byId[id] = {id: id, name: name, kind: kind}
        end if
    end for
    for each rawId in navigation.pinnedLibraryIds
        id = PorticoLocalAuthSafeId(rawId)
        if id <> "" and byId[id] <> invalid
            result.Push(byId[id])
            if result.Count() >= 4 then return result
        end if
    end for
    return result
end function

sub PorticoLocalAuthSignOut(controller as object)
    PorticoServerSessionLocalHandoffClear()
    controller.localProfileDirectory = invalid
    controller.localProfileHandoffId = ""
    controller.localProfileInstallationId = ""
    source = controller.session
    tombstone = {version: PorticoServerSessionVersion(), signedOut: true, purpose: "profile-bound-native-server-session"}
    committed = PorticoSecureRegistryCommit("server-session", tombstone)
    durable = committed.ok
    if not durable then durable = PorticoSecureRegistryClear("server-session")
    if not durable
        controller.status = "storage-error"
        controller.message = "Direct server sign-in could not be removed from this Roku."
        PorticoLocalAuthPublish(controller)
        return
    end if
    PorticoSecureRegistryClear("server-refresh-rotation")
    PorticoLocalAuthStopDiscovery(controller)
    PorticoLocalAuthDiscardDiscoveryState(controller)
    controller.session = invalid
    controller.sessionGeneration = 0
    controller.nextRefreshAt = 0
    controller.libraryItems = []
    controller.navigationVerified = false
    controller.status = "signed-out"
    controller.message = ""
    PorticoLocalAuthPublish(controller)
    if source <> invalid then PorticoLocalAuthRevoke(controller, source)
end sub

sub PorticoLocalAuthClearSession(controller as object, status as string, message as string)
    PorticoServerSessionLocalHandoffClear()
    controller.localProfileDirectory = invalid
    controller.localProfileHandoffId = ""
    controller.localProfileInstallationId = ""
    source = controller.session
    tombstone = {version: PorticoServerSessionVersion(), signedOut: true, purpose: "profile-bound-native-server-session"}
    committed = PorticoSecureRegistryCommit("server-session", tombstone)
    durable = committed.ok
    if not durable then durable = PorticoSecureRegistryClear("server-session")
    if not durable
        controller.status = "storage-error"
        controller.message = "The expired session could not be removed from this Roku."
        PorticoLocalAuthPublish(controller)
        return
    end if
    PorticoSecureRegistryClear("server-refresh-rotation")
    PorticoLocalAuthStopDiscovery(controller)
    PorticoLocalAuthDiscardDiscoveryState(controller)
    controller.session = invalid
    controller.sessionGeneration = 0
    controller.nextRefreshAt = 0
    controller.libraryItems = []
    controller.navigationVerified = false
    controller.status = status
    controller.message = message
    PorticoLocalAuthPublish(controller)
    if source <> invalid then PorticoLocalAuthRevoke(controller, source)
end sub

sub PorticoLocalAuthRevoke(controller as object, session as dynamic)
    if session = invalid or Type(session) <> "roAssociativeArray" then return
    refresh = PorticoHttpScalarString(session.refreshToken, "")
    if not PorticoLocalAuthRefreshTokenValid(refresh) then return
    PorticoLocalAuthRequest(controller, "POST", session.apiBaseUrl + "/api/auth/sessions/revoke", {refreshToken: refresh}, invalid, 5000)
end sub
