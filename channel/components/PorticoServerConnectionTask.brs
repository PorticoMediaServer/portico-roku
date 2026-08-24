sub init()
    m.top.functionName = "PorticoServerConnectionRun"
end sub

sub PorticoServerConnectionRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    networkPort = CreateObject("roMessagePort")
    deviceInfo = CreateObject("roDeviceInfo")
    networkEventsEnabled = false
    if networkPort <> invalid and deviceInfo <> invalid
        deviceInfo.SetMessagePort(networkPort)
        networkEventsEnabled = deviceInfo.EnableLinkStatusEvent(true)
    end if
    controller = {
        clock: clock,
        lastCommandSequence: 0,
        operationContract: invalid,
        accountSignedIn: false,
        viewerGeneration: 0,
        activationSequence: 0,
        serverStatus: "not-connected",
        serverErrorCode: "",
        serverName: "Portico Server",
        profileName: "",
        session: invalid,
        sessionGeneration: 0,
        nextRefreshAt: 0,
        refreshFailures: 0,
        refreshTerminal: false,
        last401Generation: -1,
        assertionId: "",
        routeFailureCode: "",
        identityFailureCode: "",
        provisionalContext: invalid,
        restoreApproval: invalid,
        activationBackup: invalid,
        profileActivationFailed: false,
        libraryItems: [],
        navigationVerified: false,
        eventCapabilities: invalid,
        productContractRevision: "",
        networkPort: networkPort,
        networkEventsEnabled: networkEventsEnabled,
        nextNetworkRouteRetryAt: 0
    }
    loaded = PorticoOperationContractLoad()
    if loaded.ok
        controller.operationContract = loaded.value
    else
        controller.serverStatus = "incompatible"
        controller.serverErrorCode = "operation-contract-invalid"
    end if
    PorticoServerConnectionPublish(controller, false)
    while true
        PorticoServerConnectionHandleCommand(controller)
        PorticoServerConnectionTick(controller)
        Sleep(100)
    end while
end sub

sub PorticoServerConnectionHandleCommand(controller as object)
    command = m.top.command
    if not PorticoCoreIsAssociativeArray(command) then return
    sequence = PorticoHttpInteger(command.sequence, 0)
    if sequence <= controller.lastCommandSequence then return
    controller.lastCommandSequence = sequence
    kind = LCase(PorticoCoreSafeText(command.kind, 64))

    if kind = "initialize" or kind = "restore-session"
        generation = PorticoHttpInteger(command.viewerGeneration, 0)
        if generation < 1 then return
        if command.accountSignedIn <> invalid then controller.accountSignedIn = command.accountSignedIn = true
        controller.viewerGeneration = generation
        PorticoServerConnectionRestore(controller)
    else if kind = "account-state"
        signedIn = command.accountSignedIn = true
        if controller.accountSignedIn and not signedIn
            PorticoServerConnectionFence(controller, PorticoHttpInteger(command.viewerGeneration, controller.viewerGeneration), "not-connected", "")
            ' Fence intentionally preserves credential authority for profile and
            ' server switches. An account-state sign-out is different: retain no
            ' private belief that Hosted credentials are still available.
            controller.accountSignedIn = false
        else
            controller.accountSignedIn = signedIn
            generation = PorticoHttpInteger(command.viewerGeneration, controller.viewerGeneration)
            if generation > 0 and generation <> controller.viewerGeneration
                PorticoServerConnectionFence(controller, generation, "not-connected", "")
                controller.accountSignedIn = signedIn
            end if
            PorticoServerConnectionPublish(controller, false)
        end if
    else if kind = "prepare-hosted-context"
        PorticoServerConnectionPrepareHostedContext(controller, command)
    else if kind = "activate-hosted-profile"
        PorticoServerConnectionActivateHosted(controller, command)
    else if kind = "activate-local-profile"
        PorticoServerConnectionActivateLocal(controller, command)
    else if kind = "retry-server"
        PorticoServerConnectionRetry(controller)
    else if kind = "fence-viewer"
        PorticoServerConnectionFence(controller, PorticoHttpInteger(command.viewerGeneration, controller.viewerGeneration), "not-connected", "")
    end if
end sub

sub PorticoServerConnectionPrepareHostedContext(controller as object, command as object)
    generation = PorticoHttpInteger(command.viewerGeneration, 0)
    serverId = PorticoServerSessionId(command.serverId)
    controller.accountSignedIn = command.accountSignedIn = true
    account = PorticoServerConnectionAccountCredentials()
    installationId = PorticoInstallationId()
    if generation < 1 or serverId = "" or not controller.accountSignedIn or account = invalid
        controller.provisionalContext = invalid
        PorticoServerConnectionFail(controller, "account-required", false, false)
        return
    end if
    controller.viewerGeneration = generation
    controller.provisionalContext = {
        authority: "hosted", accountId: account.userId, serverId: serverId,
        installationId: installationId, viewerGeneration: generation,
        provenByCredentialTask: true
    }
    controller.serverStatus = "not-connected"
    controller.serverErrorCode = ""
    PorticoServerConnectionPublish(controller, false)
end sub

sub PorticoServerConnectionTick(controller as object)
    PorticoServerConnectionObserveNetworkTransitions(controller)
    if controller.session <> invalid and controller.nextRefreshAt > 0 and controller.clock.TotalSeconds() >= controller.nextRefreshAt
        PorticoServerConnectionRefresh(controller, false)
    end if
end sub

sub PorticoServerConnectionObserveNetworkTransitions(controller as object)
    if controller.networkEventsEnabled <> true or controller.networkPort = invalid then return
    while true
        message = controller.networkPort.GetMessage()
        if message = invalid then exit while
        if Type(message) = "roDeviceInfoEvent" and message.IsStatusMessage()
            info = message.GetInfo()
            if PorticoCoreIsAssociativeArray(info) and info.linkStatus = true
                ' Link restoration can mean a different LAN, NAT, or address. Let
                ' bursts settle, then re-probe durable routes before Hosted.
                controller.nextNetworkRouteRetryAt = controller.clock.TotalSeconds() + 2
            end if
        end if
    end while
    if controller.nextNetworkRouteRetryAt <= 0 or controller.clock.TotalSeconds() < controller.nextNetworkRouteRetryAt then return
    controller.nextNetworkRouteRetryAt = 0
    if PorticoServerSessionStored(controller.session) = invalid then return
    if PorticoServerConnectionVerifyOrRediscoverRoute(controller, false)
        controller.serverStatus = "active"
        controller.serverErrorCode = ""
        PorticoServerConnectionPublish(controller, true)
    end if
end sub

sub PorticoServerConnectionRestore(controller as object)
    PorticoServerSessionScopeAssertionClear()
    controller.assertionId = ""
    controller.activationSequence = controller.activationSequence + 1
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid
        PorticoServerConnectionResetPrivate(controller)
        PorticoServerConnectionPublish(controller, false)
        return
    end if
    migration = PorticoServerSessionMigration(record.payload)
    if not migration.ok
        if migration.code = "legacy_reactivation_required" or migration.code = "invalid_session_record"
            PorticoServerConnectionClearStoredSession()
            PorticoServerConnectionFail(controller, "profile-reactivation-required", false, false)
        else
            PorticoServerConnectionResetPrivate(controller)
            PorticoServerConnectionPublish(controller, false)
        end if
        return
    end if
    controller.session = migration.session
    controller.sessionGeneration = record.generation
    controller.serverName = migration.session.serverName
    controller.profileName = migration.session.profileName
    ' A stored native session proves the credential family, not that its profile
    ' may be silently reopened. Do not publish even the chooser bootstrap scope
    ' until the live policy (or narrow offline evidence) has made a decision.
    controller.provisionalContext = invalid
    profileAuthorizationApproved = PorticoServerConnectionConsumeRestoreApproval(controller, migration.session)
    controller.serverStatus = "connecting"
    controller.serverErrorCode = ""
    PorticoServerConnectionPublish(controller, false)
    if not PorticoServerConnectionVerifyOrRediscoverRoute(controller, false)
        if controller.routeFailureCode = "server-identity-mismatch"
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "identity-mismatch", "server-identity-mismatch")
        else
            PorticoServerConnectionFinishOfflineRestoreIfAllowed(controller, "server-offline")
        end if
        return
    end if
    remaining = PorticoSignedDocumentSecondsUntil(migration.session.accessExpiresAt)
    if remaining = invalid or remaining <= 60
        if not PorticoServerConnectionRefresh(controller, false)
            if controller.serverStatus <> "permission-removed" then PorticoServerConnectionFinishOfflineRestoreIfAllowed(controller, "server-offline")
            return
        end if
    end if
    if not PorticoServerConnectionValidateIdentity(controller, false)
        if controller.identityFailureCode = "server-offline"
            PorticoServerConnectionFinishOfflineRestoreIfAllowed(controller, "server-offline")
        else
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "identity-mismatch", controller.identityFailureCode)
        end if
        return
    end if
    if not profileAuthorizationApproved and not PorticoServerConnectionAuthorizeRestoredProfile(controller) then return
    if not PorticoServerConnectionBootstrapContent(controller) then return
    if not profileAuthorizationApproved then PorticoServerConnectionRememberRestoreApproval(controller)
    controller.provisionalContext = PorticoServerConnectionRestoredContext(controller)
    if controller.provisionalContext = invalid
        PorticoServerConnectionFence(controller, controller.viewerGeneration, "identity-mismatch", "invalid-restored-context")
        return
    end if
    PorticoServerConnectionFinishActivation(controller)
end sub

sub PorticoServerConnectionRememberRestoreApproval(controller as object)
    session = PorticoServerSessionStored(controller.session)
    if session = invalid then return
    controller.restoreApproval = {
        purpose: "immediate-profile-restore-publication",
        activationSequence: controller.activationSequence,
        authority: session.authority,
        accountId: session.accountId,
        serverId: session.serverId,
        profileId: session.profileId,
        authorizationRevision: session.authorizationRevision,
        installationId: session.installationId
    }
end sub

function PorticoServerConnectionConsumeRestoreApproval(controller as object, session as dynamic) as boolean
    approval = controller.restoreApproval
    controller.restoreApproval = invalid
    stored = PorticoServerSessionStored(session)
    if approval = invalid or Type(approval) <> "roAssociativeArray" or stored = invalid then return false
    if approval.purpose <> "immediate-profile-restore-publication" or PorticoHttpInteger(approval.activationSequence, 0) <> controller.activationSequence - 1 then return false
    return approval.authority = stored.authority and approval.accountId = stored.accountId and approval.serverId = stored.serverId and approval.profileId = stored.profileId and approval.authorizationRevision = stored.authorizationRevision and approval.installationId = stored.installationId
end function

function PorticoServerConnectionProfileBootstrapContext(controller as object) as dynamic
    session = PorticoServerSessionStored(controller.session)
    if session = invalid then return invalid
    return {
        authority: session.authority,
        accountId: session.accountId,
        serverId: session.serverId,
        installationId: session.installationId,
        viewerGeneration: controller.viewerGeneration,
        provenByCredentialTask: true
    }
end function

sub PorticoServerConnectionProfileSelectionRequired(controller as object)
    PorticoServerSessionScopeAssertionClear()
    controller.assertionId = ""
    controller.restoreApproval = invalid
    controller.provisionalContext = PorticoServerConnectionProfileBootstrapContext(controller)
    PorticoServerConnectionFail(controller, "profile-reactivation-required", false, false)
end sub

sub PorticoServerConnectionFinishOfflineRestoreIfAllowed(controller as object, code as string)
    session = PorticoServerSessionStored(controller.session)
    if session = invalid
        PorticoServerConnectionProfileSelectionRequired(controller)
        return
    end if
    launch = PorticoViewerPreferencesReadLaunch(session.authority, session.accountId, session.serverId, session.installationId)
    if not PorticoViewerPreferencesOfflineRestoreAllowed(launch, session)
        PorticoServerConnectionProfileSelectionRequired(controller)
        return
    end if
    controller.provisionalContext = PorticoServerConnectionRestoredContext(controller)
    PorticoServerConnectionFinishOfflineRestore(controller, code)
end sub

function PorticoServerConnectionAuthorizeRestoredProfile(controller as object) as boolean
    session = PorticoServerSessionStored(controller.session)
    if session = invalid
        PorticoServerConnectionProfileSelectionRequired(controller)
        return false
    end if
    result = PorticoServerConnectionServerRequest(controller, "GET", "listAccountProfiles", invalid, true)
    if result.interrupted then return false
    if result.sessionRefreshFailed = true
        if result.sessionRefreshTerminal = true
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "permission-removed", "server-session-expired")
        else
            PorticoServerConnectionFinishOfflineRestoreIfAllowed(controller, "server-offline")
        end if
        return false
    end if
    if not result.ok
        if result.retryable
            PorticoServerConnectionFinishOfflineRestoreIfAllowed(controller, "server-offline")
        else
            PorticoServerConnectionProfileSelectionRequired(controller)
        end if
        return false
    end if
    directory = PorticoProfilesDirectory(result.data, session.authority, session.accountId, session.serverId)
    if directory = invalid
        PorticoServerConnectionProfileSelectionRequired(controller)
        return false
    end if
    current = PorticoProfilesFind(directory, session.profileId)
    if current = invalid
        PorticoServerConnectionProfileSelectionRequired(controller)
        return false
    end if
    eligible = directory.profiles
    if directory.profilesAllowed = false
        eligible = []
        for each profile in directory.profiles
            if profile.isPrimary then eligible.Push(profile)
        end for
    end if
    currentEligible = false
    for each profile in eligible
        if profile.id = current.id then currentEligible = true
    end for
    if not currentEligible
        PorticoServerConnectionProfileSelectionRequired(controller)
        return false
    end if
    if eligible.Count() = 1 and current.hasPIN = false then return true

    launch = PorticoViewerPreferencesReadLaunch(session.authority, session.accountId, session.serverId, session.installationId)
    if launch = invalid or launch.profileSelection <> "last-used" or launch.lastProfileId <> session.profileId
        PorticoServerConnectionProfileSelectionRequired(controller)
        return false
    end if
    policy = PorticoViewerPreferencesRestorePolicy(launch.restorePolicy, {lastProfileId: session.profileId})
    policyMatches = policy <> invalid
    if policyMatches then policyMatches = policy.authorizationRevision = session.authorizationRevision
    if policyMatches then policyMatches = policy.eligibleProfileCount = eligible.Count()
    if policyMatches then policyMatches = policy.profileHasPIN = current.hasPIN and policy.profilePinRevision = current.pinRevision
    if not policyMatches or not PorticoProfilesTrustMatches(launch.trust, directory, current)
        PorticoViewerPreferencesForgetLaunch(session.authority, session.accountId, session.serverId, session.installationId)
        PorticoServerConnectionProfileSelectionRequired(controller)
        return false
    end if
    redeemed = PorticoServerConnectionServerRequest(controller, "POST", "redeemAutomaticProfileTrust", {token: launch.trust.token}, true)
    if redeemed.interrupted then return false
    if redeemed.sessionRefreshFailed = true
        if redeemed.sessionRefreshTerminal = true
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "permission-removed", "server-session-expired")
        else
            PorticoServerConnectionFinishOfflineRestoreIfAllowed(controller, "server-offline")
        end if
        return false
    end if
    if not redeemed.ok
        if redeemed.retryable
            ' Locked and multi-profile restores require a successful online
            ' redemption. They intentionally cannot fall back to cached trust.
            PorticoServerConnectionProfileSelectionRequired(controller)
        else
            PorticoViewerPreferencesForgetLaunch(session.authority, session.accountId, session.serverId, session.installationId)
            PorticoServerConnectionProfileSelectionRequired(controller)
        end if
        return false
    end if
    return true
end function

function PorticoServerConnectionRestoredContext(controller as object) as dynamic
    session = PorticoServerSessionStored(controller.session)
    if session = invalid then return invalid
    return {
        authority: session.authority,
        accountId: session.accountId,
        serverId: session.serverId,
        installationId: session.installationId,
        profileId: session.profileId,
        profileName: PorticoServerSessionLabel(session.profileName, "Profile", 80),
        viewerGeneration: controller.viewerGeneration,
        provenByCredentialTask: true,
        restored: true
    }
end function

sub PorticoServerConnectionActivateHosted(controller as object, command as object)
    expected = PorticoServerConnectionExpected(command, "hosted")
    if expected = invalid
        PorticoServerConnectionFail(controller, "invalid-profile-activation", false, false)
        return
    end if
    PorticoServerConnectionBeginActivation(controller, expected.viewerGeneration)
    PorticoServerSessionLocalHandoffClear()
    account = PorticoServerConnectionAccountCredentials()
    if account = invalid or account.userId <> expected.accountId
        PorticoServerConnectionFail(controller, "account-required", false, false)
        return
    end if
    context = controller.provisionalContext
    if not PorticoCoreIsAssociativeArray(context) or context.accountId <> expected.accountId or context.serverId <> expected.serverId or context.viewerGeneration <> expected.viewerGeneration
        PorticoServerConnectionFail(controller, "profile-context-mismatch", false, false)
        return
    end if
    route = PorticoServerConnectionResolveHostedRoute(controller, expected, account)
    if route = invalid then return
    envelope = PorticoProfilesSelectionTransactionConsume(PorticoServerSessionId(command.handoffId), "hosted", expected.accountId, expected.serverId, expected.profileId, expected.viewerGeneration)
    if envelope = invalid
        PorticoServerConnectionFail(controller, "profile-selection-expired", false, false)
        return
    end if
    hostedPath = PorticoServerConnectionOperationPath(controller, "hosted", "createPorticoSession", {serverId: expected.serverId})
    if hostedPath = ""
        envelope = invalid
        PorticoServerConnectionFail(controller, "operation-contract-invalid", false, false)
        return
    end if
    hosted = PorticoServerConnectionHttp(controller, {
        method: "POST", url: PorticoServerConnectionHostedBaseUrl() + hostedPath,
        body: FormatJson({selectionEnvelope: envelope}),
        headers: {Authorization: "Bearer " + account.accessToken, "Content-Type": "application/json"},
        timeoutMs: 15000, expectJson: true
    })
    if hosted.interrupted then return
    if not hosted.ok
        envelope = invalid
        PorticoServerConnectionHandleHostedFailure(controller, hosted, account.generation)
        return
    end if
    bootstrap = PorticoServerConnectionHostedBootstrap(hosted.data, envelope, expected)
    envelope = invalid
    if bootstrap = invalid
        PorticoServerConnectionFail(controller, "invalid-hosted-bootstrap", false, false)
        return
    end if
    attachPath = PorticoServerConnectionOperationPath(controller, "server", "attachPorticoSession", invalid)
    if attachPath = ""
        bootstrap = invalid
        PorticoServerConnectionFail(controller, "operation-contract-invalid", false, false)
        return
    end if
    attachPayload = {
        accessToken: bootstrap.accessToken,
        selectionEnvelope: bootstrap.selectionEnvelope,
        deviceName: PorticoServerConnectionDeviceName(), app: "Portico", platform: "Roku"
    }
    if expected.installationId <> "" then attachPayload.installationId = expected.installationId
    attached = PorticoServerConnectionHttp(controller, {
        method: "POST", url: route.apiBaseUrl + attachPath,
        body: FormatJson(attachPayload), headers: {"Content-Type": "application/json"},
        timeoutMs: 15000, expectJson: true
    })
    attachPayload.accessToken = ""
    attachPayload.selectionEnvelope = invalid
    bootstrap = invalid
    if attached.interrupted then return
    if not attached.ok
        PorticoServerConnectionFail(controller, "server-attachment-failed", attached.retryable, false)
        return
    end if
    PorticoServerConnectionAcceptCredentials(controller, attached.data, route, expected)
end sub

sub PorticoServerConnectionActivateLocal(controller as object, command as object)
    generation = PorticoHttpInteger(command.viewerGeneration, 0)
    profileId = PorticoServerSessionId(command.profileId)
    handoffId = PorticoServerSessionId(command.handoffId)
    if generation < 1 or profileId = "" or handoffId = ""
        PorticoServerConnectionFail(controller, "invalid-profile-activation", false, false)
        return
    end if
    PorticoServerConnectionBeginActivation(controller, generation)
    handoff = PorticoServerSessionLocalHandoffConsume(handoffId, profileId, generation)
    if handoff = invalid
        PorticoServerConnectionFail(controller, "profile-selection-expired", false, false)
        return
    end if
    route = handoff.route
    if not PorticoServerConnectionVerifyRoute(controller, {
        apiBaseUrl: route.apiBaseUrl, routeType: route.routeType, routeGeneration: route.routeGeneration,
        serverId: handoff.serverId, serverPublicKeyFingerprint: route.serverPublicKeyFingerprint
    })
        handoff.accountAuthenticationToken = ""
        PorticoServerConnectionFail(controller, controller.routeFailureCode, controller.routeFailureCode = "server-offline", false)
        return
    end if
    pin = PorticoProfilesUnsealPin(command.sealedPin, profileId, generation)
    needsPin = handoff.selectedProfile.hasPIN = true
    if needsPin and pin = ""
        handoff.accountAuthenticationToken = ""
        PorticoServerConnectionFail(controller, "profile-pin-required", false, false)
        return
    end if
    selectionPayload = {accountAuthenticationToken: handoff.accountAuthenticationToken, profileId: profileId}
    if pin <> "" then selectionPayload.pin = pin
    selectPath = PorticoServerConnectionOperationPath(controller, "server", "selectLocalProfile", invalid)
    selection = PorticoServerConnectionHttp(controller, {
        method: "POST", url: route.apiBaseUrl + selectPath, body: FormatJson(selectionPayload),
        headers: {"Content-Type": "application/json"}, timeoutMs: 12000, expectJson: true
    })
    pin = ""
    selectionPayload.accountAuthenticationToken = ""
    if selectionPayload.pin <> invalid then selectionPayload.pin = ""
    handoff.accountAuthenticationToken = ""
    if selection.interrupted then return
    if not selection.ok
        PorticoServerConnectionFail(controller, "profile-selection-denied", false, false)
        return
    end if
    grant = PorticoServerConnectionLocalGrant(selection.data, handoff, profileId)
    if grant = invalid
        PorticoServerConnectionFail(controller, "invalid-profile-grant", false, false)
        return
    end if
    sessionPath = PorticoServerConnectionOperationPath(controller, "server", "createNativeProfileSession", invalid)
    sessionPayload = {
        selectionGrant: grant.token,
        deviceName: PorticoServerConnectionDeviceName(), app: "Portico", platform: "Roku"
    }
    if PorticoServerSessionId(handoff.installationId) <> "" then sessionPayload.installationId = handoff.installationId
    native = PorticoServerConnectionHttp(controller, {
        method: "POST", url: route.apiBaseUrl + sessionPath, body: FormatJson(sessionPayload),
        headers: {"Content-Type": "application/json"}, timeoutMs: 12000, expectJson: true
    })
    sessionPayload.selectionGrant = ""
    grant.token = ""
    if native.interrupted then return
    if not native.ok
        PorticoServerConnectionFail(controller, "native-session-failed", false, false)
        return
    end if
    expected = {
        authority: "local", accountId: handoff.accountId, serverId: handoff.serverId,
        profileId: profileId, installationId: handoff.installationId, viewerGeneration: generation
    }
    PorticoServerConnectionAcceptCredentials(controller, native.data, route, expected)
end sub

sub PorticoServerConnectionAcceptCredentials(controller as object, credentials as dynamic, route as object, expected as object)
    session = PorticoServerSessionRecord(credentials, route, expected)
    if session = invalid
        PorticoServerConnectionFail(controller, "invalid-native-session", false, false)
        return
    end if
    controller.session = session
    controller.serverName = session.serverName
    controller.profileName = session.profileName
    if not PorticoServerConnectionValidateIdentity(controller, true)
        PorticoServerConnectionDiscardSession(controller, controller.activationBackup = invalid)
        PorticoServerConnectionFail(controller, controller.identityFailureCode, controller.identityFailureCode = "server-offline", false)
        return
    end if
    session = PorticoServerSessionStored(controller.session)
    if session = invalid
        PorticoServerConnectionFail(controller, "invalid-native-session", false, false)
        return
    end if
    staged = PorticoSecureRegistryCommit("pending-server-session", session)
    if not staged.ok
        PorticoServerConnectionRevokeBestEffort(controller, session)
        PorticoServerConnectionDiscardSession(controller, false)
        PorticoServerConnectionFail(controller, "storage-unavailable", true, false)
        return
    end if
    if not PorticoServerConnectionBootstrapContent(controller) then return
    session = PorticoServerSessionStored(controller.session)
    if session = invalid
        PorticoServerConnectionFail(controller, "invalid-native-session", false, false)
        return
    end if
    committed = PorticoSecureRegistryCommit("server-session", session)
    if not committed.ok
        PorticoServerConnectionRevokeBestEffort(controller, session)
        PorticoServerConnectionDiscardSession(controller, false)
        PorticoServerConnectionFail(controller, "storage-unavailable", true, false)
        return
    end if
    PorticoSecureRegistryClear("pending-server-session")
    controller.sessionGeneration = committed.generation
    controller.last401Generation = -1
    PorticoSecureRegistryClear("server-refresh-rotation")
    PorticoServerConnectionScheduleRefresh(controller)
    PorticoServerConnectionFinishActivation(controller)
    previous = invalid
    if PorticoCoreIsAssociativeArray(controller.activationBackup) then previous = controller.activationBackup.session
    controller.activationBackup = invalid
    if previous <> invalid then PorticoServerConnectionRevokeBestEffort(controller, previous)
end sub

sub PorticoServerConnectionBeginActivation(controller as object, viewerGeneration as integer)
    controller.activationBackup = invalid
    current = PorticoServerSessionStored(controller.session)
    if current <> invalid
        controller.activationBackup = {
            session: current,
            sessionGeneration: controller.sessionGeneration,
            nextRefreshAt: controller.nextRefreshAt,
            refreshFailures: controller.refreshFailures,
            last401Generation: controller.last401Generation,
            serverStatus: controller.serverStatus,
            serverErrorCode: controller.serverErrorCode,
            serverName: controller.serverName,
            profileName: controller.profileName,
            libraryItems: controller.libraryItems,
            navigationVerified: controller.navigationVerified,
            eventCapabilities: controller.eventCapabilities,
            productContractRevision: controller.productContractRevision,
            assertionId: controller.assertionId
        }
    end if
    PorticoSecureRegistryClear("pending-server-session")
    PorticoServerSessionScopeAssertionClear()
    controller.activationSequence = controller.activationSequence + 1
    controller.restoreApproval = invalid
    controller.viewerGeneration = viewerGeneration
    controller.assertionId = ""
    controller.session = invalid
    controller.sessionGeneration = 0
    controller.serverStatus = "connecting"
    controller.serverErrorCode = ""
    controller.serverName = "Portico Server"
    controller.profileName = ""
    controller.libraryItems = []
    controller.navigationVerified = false
    if controller.activationBackup = invalid then PorticoServerConnectionPublish(controller, false)
end sub

function PorticoServerConnectionRestoreActivationBackup(controller as object) as boolean
    backup = controller.activationBackup
    if not PorticoCoreIsAssociativeArray(backup) then return false
    candidate = controller.session
    restoredCommit = PorticoSecureRegistryCommit("server-session", backup.session)
    if not restoredCommit.ok
        controller.activationBackup = invalid
        return false
    end if
    controller.activationBackup = invalid
    controller.session = backup.session
    controller.sessionGeneration = restoredCommit.generation
    controller.nextRefreshAt = backup.nextRefreshAt
    controller.refreshFailures = backup.refreshFailures
    controller.last401Generation = backup.last401Generation
    controller.serverStatus = backup.serverStatus
    controller.serverErrorCode = backup.serverErrorCode
    controller.serverName = backup.serverName
    controller.profileName = backup.profileName
    controller.libraryItems = backup.libraryItems
    controller.navigationVerified = backup.navigationVerified
    controller.eventCapabilities = backup.eventCapabilities
    controller.productContractRevision = backup.productContractRevision
    controller.assertionId = backup.assertionId
    PorticoSecureRegistryClear("pending-server-session")
    if candidate <> invalid then PorticoServerConnectionRevokeBestEffort(controller, candidate)
    PorticoServerConnectionPublish(controller, false)
    return true
end function

sub PorticoServerConnectionFinishActivation(controller as object)
    scope = PorticoServerSessionScope(controller.session, controller.viewerGeneration)
    assertionId = PorticoHttpNewRequestId()
    if scope = invalid or not PorticoServerSessionScopeAssertionWrite(assertionId, controller.activationSequence, scope)
        PorticoServerConnectionDiscardSession(controller, true)
        PorticoServerConnectionFail(controller, "scope-assertion-unavailable", false, false)
        return
    end if
    controller.assertionId = assertionId
    controller.serverStatus = "online"
    controller.serverErrorCode = ""
    controller.navigationVerified = true
    PorticoServerConnectionRememberRestoreApproval(controller)
    PorticoServerConnectionPublish(controller, false)
end sub

sub PorticoServerConnectionFinishOfflineRestore(controller as object, code as string)
    scope = PorticoServerSessionScope(controller.session, controller.viewerGeneration)
    assertionId = PorticoHttpNewRequestId()
    if scope = invalid or not PorticoServerSessionScopeAssertionWrite(assertionId, controller.activationSequence, scope)
        PorticoServerConnectionFail(controller, "scope-assertion-unavailable", false, false)
        return
    end if
    controller.assertionId = assertionId
    controller.serverStatus = "offline"
    controller.serverErrorCode = code
    ' The stored identity remains authoritative while its refresh credential is
    ' locally valid. Existing cached navigation is not cleared by an outage.
    PorticoServerConnectionPublish(controller, false)
end sub

sub PorticoServerConnectionRetry(controller as object)
    controller.activationSequence = controller.activationSequence + 1
    PorticoServerSessionScopeAssertionClear()
    controller.assertionId = ""
    if controller.session = invalid or controller.serverErrorCode = "profile-reactivation-required"
        PorticoServerConnectionRestore(controller)
        return
    end if
    controller.serverStatus = "connecting"
    controller.serverErrorCode = ""
    PorticoServerConnectionPublish(controller, false)
    if not PorticoServerConnectionVerifyOrRediscoverRoute(controller, true)
        if controller.routeFailureCode = "server-identity-mismatch"
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "identity-mismatch", "server-identity-mismatch")
        else
            PorticoServerConnectionFinishOfflineRestore(controller, "server-offline")
        end if
        return
    end if
    remaining = PorticoSignedDocumentSecondsUntil(controller.session.accessExpiresAt)
    if remaining = invalid or remaining <= 60
        if not PorticoServerConnectionRefresh(controller, false) then return
    end if
    if not PorticoServerConnectionBootstrap(controller) then return
    PorticoServerConnectionFinishActivation(controller)
end sub

sub PorticoServerConnectionFence(controller as object, viewerGeneration as integer, status as string, code as string)
    source = controller.session
    PorticoProfilesSelectionTransactionClear()
    PorticoServerSessionLocalHandoffClear()
    PorticoServerSessionScopeAssertionClear()
    PorticoServerConnectionClearStoredSession()
    PorticoSecureRegistryClear("server-refresh-rotation")
    PorticoSecureRegistryClear("pending-server-session")
    PorticoServerConnectionResetPrivate(controller)
    if viewerGeneration > 0 then controller.viewerGeneration = viewerGeneration
    controller.activationSequence = controller.activationSequence + 1
    controller.serverStatus = status
    controller.serverErrorCode = code
    PorticoServerConnectionPublish(controller, false)
    if source <> invalid then PorticoServerConnectionRevokeBestEffort(controller, source)
end sub

sub PorticoServerConnectionResetPrivate(controller as object)
    controller.session = invalid
    controller.sessionGeneration = 0
    controller.last401Generation = -1
    controller.nextRefreshAt = 0
    controller.refreshFailures = 0
    controller.refreshTerminal = false
    controller.assertionId = ""
    controller.provisionalContext = invalid
    controller.restoreApproval = invalid
    controller.serverStatus = "not-connected"
    controller.serverErrorCode = ""
    controller.serverName = "Portico Server"
    controller.profileName = ""
    controller.libraryItems = []
    controller.navigationVerified = false
    controller.eventCapabilities = invalid
    controller.productContractRevision = ""
end sub

sub PorticoServerConnectionDiscardSession(controller as object, clearStored as boolean)
    if clearStored then PorticoServerConnectionClearStoredSession()
    controller.restoreApproval = invalid
    controller.session = invalid
    controller.sessionGeneration = 0
    controller.nextRefreshAt = 0
    controller.last401Generation = -1
end sub

sub PorticoServerConnectionClearStoredSession()
    tombstone = {version: PorticoServerSessionVersion(), purpose: "profile-bound-native-server-session", signedOut: true}
    committed = PorticoSecureRegistryCommit("server-session", tombstone)
    if not committed.ok then PorticoSecureRegistryClear("server-session")
    PorticoSecureRegistryClear("server-refresh-rotation")
    PorticoSecureRegistryClear("pending-server-session")
end sub

function PorticoServerConnectionExpected(command as object, authority as string) as dynamic
    expected = {
        authority: authority,
        accountId: PorticoServerSessionId(command.accountId),
        serverId: PorticoServerSessionId(command.serverId),
        profileId: PorticoServerSessionId(command.profileId),
        installationId: PorticoServerSessionId(command.installationId),
        viewerGeneration: PorticoHttpInteger(command.viewerGeneration, 0)
    }
    if expected.accountId = "" or expected.serverId = "" or expected.profileId = "" or expected.viewerGeneration < 1 then return invalid
    return expected
end function

function PorticoServerConnectionHostedBootstrap(data as dynamic, envelope as dynamic, expected as object) as dynamic
    if not PorticoCoreIsAssociativeArray(data) or not PorticoCoreIsAssociativeArray(envelope) then return invalid
    if LCase(PorticoCoreSafeText(data.tokenType, 16)) <> "bearer" then return invalid
    token = PorticoCoreSafeText(data.accessToken, 4096)
    if token = "" or PorticoSignedDocumentSecondsUntil(data.accessExpiresAt) = invalid or PorticoSignedDocumentSecondsUntil(data.accessExpiresAt) <= 0 then return invalid
    returned = data.selectionEnvelope
    if not PorticoCoreIsAssociativeArray(returned) then return invalid
    for each key in ["version", "assertionId", "audience", "accountId", "profileId", "serverId", "deviceId", "issuedAt", "expiresAt", "signatureAlgorithm", "signatureKeyId", "signature"]
        if PorticoCoreSafeText(returned[key], 8192) = "" or PorticoCoreSafeText(returned[key], 8192) <> PorticoCoreSafeText(envelope[key], 8192) then return invalid
    end for
    if returned.version <> "v1" or returned.audience <> "portico-media-server" or returned.signatureAlgorithm <> "ed25519" then return invalid
    if not PorticoCoreIsNumber(returned.accountRevision) or not PorticoCoreIsNumber(returned.pinRevision) then return invalid
    if returned.accountRevision <> envelope.accountRevision or returned.pinRevision <> envelope.pinRevision then return invalid
    if not PorticoCoreIsArray(returned.profiles) or returned.profiles.Count() < 1 or returned.profiles.Count() > 8 then return invalid
    if FormatJson(returned.profiles) <> FormatJson(envelope.profiles) then return invalid
    if FormatJson(returned) <> FormatJson(envelope) then return invalid
    if PorticoServerSessionId(returned.accountId) <> expected.accountId or PorticoServerSessionId(returned.serverId) <> expected.serverId then return invalid
    if PorticoServerSessionId(returned.profileId) <> expected.profileId then return invalid
    membership = data.membership
    if not PorticoCoreIsAssociativeArray(membership) then return invalid
    if PorticoServerSessionId(membership.serverId) <> expected.serverId or PorticoServerSessionId(membership.userId) <> expected.accountId then return invalid
    if LCase(PorticoCoreSafeText(membership.status, 32)) <> "active" then return invalid
    return {accessToken: token, selectionEnvelope: returned}
end function

function PorticoServerConnectionLocalGrant(data as dynamic, handoff as object, profileId as string) as dynamic
    if not PorticoCoreIsAssociativeArray(data) then return invalid
    token = PorticoCoreSafeText(data.token, 4096)
    if token = "" or LCase(PorticoCoreSafeText(data.authority, 16)) <> "local" then return invalid
    if PorticoServerSessionId(data.accountId) <> handoff.accountId or PorticoServerSessionId(data.serverId) <> handoff.serverId then return invalid
    if PorticoServerSessionId(data.profileId) <> profileId then return invalid
    if PorticoSignedDocumentSecondsUntil(data.expiresAt) = invalid or PorticoSignedDocumentSecondsUntil(data.expiresAt) <= 0 then return invalid
    return {token: token}
end function

function PorticoServerConnectionResolveHostedRoute(controller as object, expected as object, account as object) as dynamic
    if not PorticoServerConnectionHostedCompatible(controller, account) then return invalid
    keys = PorticoServerConnectionHttp(controller, {method: "GET", url: PorticoServerConnectionHostedBaseUrl() + "/api/signing-keys", body: "", headers: {}, timeoutMs: 10000, expectJson: true})
    if keys.interrupted then return invalid
    if not keys.ok
        PorticoServerConnectionHandleHostedFailure(controller, keys, account.generation)
        return invalid
    end if
    keySet = PorticoSignedDocumentKeySet(keys.data)
    if not keySet.ok
        PorticoServerConnectionFail(controller, "route-trust-failed", false, false)
        return invalid
    end if
    routes = PorticoServerConnectionHttp(controller, {
        method: "GET", url: PorticoServerConnectionHostedBaseUrl() + "/api/account/servers/" + expected.serverId + "/routes",
        body: "", headers: {Authorization: "Bearer " + account.accessToken}, timeoutMs: 15000, expectJson: true
    })
    if routes.interrupted then return invalid
    if not routes.ok
        PorticoServerConnectionHandleHostedFailure(controller, routes, account.generation)
        return invalid
    end if
    verified = PorticoSignedDocumentVerifyRoute(routes.data, expected.serverId, keySet.keys)
    if not verified.ok
        PorticoServerConnectionFail(controller, verified.code, false, false)
        return invalid
    end if
    routeGeneration = PorticoSignedDocumentRouteGeneration(routes.data)
    if routeGeneration = ""
        PorticoServerConnectionFail(controller, "route-generation-missing", false, false)
        return invalid
    end if
    fingerprint = PorticoCoreSafeText(routes.data.serverPublicKeyFingerprint, 256)
    for each candidate in PorticoServerConnectionRouteCandidates(routes.data.routes)
        candidateGeneration = PorticoServerSessionId(candidate.generation)
        if candidateGeneration = "" then candidateGeneration = routeGeneration
        route = {
            apiBaseUrl: candidate.url, routeType: candidate.type,
            serverId: expected.serverId, serverName: PorticoCoreSafeText(routes.data.serverName, 80),
            serverPublicKeyFingerprint: fingerprint, routeGeneration: candidateGeneration
        }
        if PorticoServerConnectionVerifyRoute(controller, route) then return route
    end for
    PorticoServerConnectionFail(controller, "server-unreachable", true, true)
    return invalid
end function

function PorticoServerConnectionVerifyRoute(controller as object, route as object) as boolean
    controller.routeFailureCode = "server-offline"
    baseUrl = PorticoServerSessionSecureBaseUrl(route.apiBaseUrl, PorticoServerSessionRouteAllowsInsecureLan(route.routeType))
    serverId = PorticoServerSessionId(route.serverId)
    fingerprint = PorticoCoreSafeText(route.serverPublicKeyFingerprint, 256)
    routeGeneration = PorticoServerSessionId(route.routeGeneration)
    if baseUrl = "" or serverId = "" or fingerprint = "" or routeGeneration = ""
        controller.routeFailureCode = "server-identity-mismatch"
        return false
    end if
    health = PorticoServerConnectionHttp(controller, {
        method: "GET", url: baseUrl + "/api/remote-access/health", body: "", headers: {}, timeoutMs: 5000, expectJson: true,
        allowInsecureLan: PorticoServerSessionRouteAllowsInsecureLan(route.routeType)
    })
    if health.interrupted or not health.ok then return false
    if not PorticoCoreIsAssociativeArray(health.data)
        controller.routeFailureCode = "server-identity-mismatch"
        return false
    end if
    if PorticoServerSessionId(health.data.serverId) <> serverId or PorticoCoreSafeText(health.data.serverPublicKeyFingerprint, 256) <> fingerprint
        controller.routeFailureCode = "server-identity-mismatch"
        return false
    end if
    controller.routeFailureCode = ""
    return true
end function

function PorticoServerConnectionVerifyOrRediscoverRoute(controller as object, preferFresh as boolean) as boolean
    source = PorticoServerSessionStored(controller.session)
    if source = invalid then return false
    if PorticoServerConnectionVerifyRoute(controller, source) then return true
    previous = PorticoServerSessionPreviousRoute(source)
    if previous <> invalid and PorticoServerConnectionVerifyRoute(controller, previous)
        if PorticoServerConnectionAdoptStoredRoute(controller, source, previous) then return true
    end if
    if source.authority = "hosted" then return PorticoServerConnectionRediscoverStoredRoute(controller, source)
    return false
end function

function PorticoServerConnectionAdoptStoredRoute(controller as object, source as object, route as object) as boolean
    replacement = {}
    for each key in source
        replacement[key] = source[key]
    end for
    replacement.previousRoute = PorticoServerSessionRouteRecord(source)
    replacement.apiBaseUrl = route.apiBaseUrl
    replacement.routeType = route.routeType
    replacement.allowInsecureLan = route.allowInsecureLan
    replacement.serverPublicKeyFingerprint = route.serverPublicKeyFingerprint
    replacement.routeGeneration = route.routeGeneration
    if PorticoServerSessionStored(replacement) = invalid then return false
    committed = PorticoSecureRegistryCommit("server-session", replacement)
    if not committed.ok then return false
    controller.session = replacement
    controller.sessionGeneration = committed.generation
    controller.last401Generation = -1
    return true
end function

function PorticoServerConnectionRediscoverStoredRoute(controller as object, source as object) as boolean
    account = PorticoServerConnectionAccountCredentials()
    if account = invalid or account.userId <> source.accountId then return false
    expected = {
        authority: source.authority,
        accountId: source.accountId,
        serverId: source.serverId,
        profileId: source.profileId,
        installationId: source.installationId,
        viewerGeneration: controller.viewerGeneration
    }
    route = PorticoServerConnectionResolveHostedRoute(controller, expected, account)
    if route = invalid then return false
    rebased = {}
    for each key in source
        rebased[key] = source[key]
    end for
    rebased.previousRoute = PorticoServerSessionRouteRecord(source)
    rebased.apiBaseUrl = route.apiBaseUrl
    rebased.routeType = route.routeType
    rebased.allowInsecureLan = PorticoServerSessionRouteAllowsInsecureLan(route.routeType)
    rebased.serverPublicKeyFingerprint = route.serverPublicKeyFingerprint
    rebased.routeGeneration = route.routeGeneration
    if PorticoCoreSafeText(route.serverName, 80) <> "" then rebased.serverName = route.serverName
    if not PorticoServerConnectionVerifyRoute(controller, rebased) then return false
    committed = PorticoSecureRegistryCommit("server-session", rebased)
    if not committed.ok then return false
    controller.session = rebased
    controller.sessionGeneration = committed.generation
    controller.serverName = rebased.serverName
    controller.last401Generation = -1
    return true
end function

function PorticoServerConnectionHostedCompatible(controller as object, account as object) as boolean
    result = PorticoServerConnectionHttp(controller, {method: "GET", url: PorticoServerConnectionHostedBaseUrl() + "/api/system", body: "", headers: {}, timeoutMs: 10000, expectJson: true})
    if result.interrupted then return false
    if not result.ok
        PorticoServerConnectionHandleHostedFailure(controller, result, account.generation)
        return false
    end if
    if not PorticoCoreIsAssociativeArray(result.data) or result.data.name <> "Portico" or result.data.status <> "ok" or result.data.apiVersion <> "v1"
        PorticoServerConnectionFail(controller, "hosted-incompatible", false, false)
        return false
    end if
    return true
end function

function PorticoServerConnectionBootstrap(controller as object) as boolean
    if not PorticoServerConnectionValidateIdentity(controller, false)
        if controller.identityFailureCode = "server-offline"
            PorticoServerConnectionFinishOfflineRestore(controller, "server-offline")
        else
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "identity-mismatch", controller.identityFailureCode)
        end if
        return false
    end if
    return PorticoServerConnectionBootstrapContent(controller)
end function

function PorticoServerConnectionValidateIdentity(controller as object, allowRevisionAdvance as boolean) as boolean
    controller.identityFailureCode = "server-identity-mismatch"
    result = PorticoServerConnectionServerRequest(controller, "GET", "getAuthMe", invalid, true)
    if result.interrupted or (not result.ok and result.retryable)
        controller.identityFailureCode = "server-offline"
        return false
    end if
    if result.sessionRefreshFailed = true then
        if result.sessionRefreshTerminal = true
            controller.identityFailureCode = "server-session-expired"
        else
            controller.identityFailureCode = "server-offline"
        end if
        return false
    end if
    if not result.ok
        if result.status = 401 or result.status = 403 then controller.identityFailureCode = "server-offline"
        return false
    end if
    rebased = PorticoServerSessionRebaseIdentity(controller.session, result.data, allowRevisionAdvance)
    if rebased = invalid then return false
    controller.session = rebased
    controller.identityFailureCode = ""
    return true
end function

function PorticoServerConnectionBootstrapContent(controller as object) as boolean
    contract = PorticoServerConnectionServerRequest(controller, "GET", "getProductContract", invalid, true)
    if contract.interrupted then return false
    if contract.sessionRefreshFailed = true
        if contract.sessionRefreshTerminal = true
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "permission-removed", "server-session-expired")
        else
            PorticoServerConnectionFail(controller, "server-offline", true, true)
        end if
        return false
    end if
    if not contract.ok or not PorticoProductContractValidateLive(contract.data).ok
        PorticoServerConnectionFail(controller, "product-contract-incompatible", false, false)
        return false
    end if
    controller.eventCapabilities = {
        eventTransports: contract.data.eventTransports,
        longPoll: contract.data.longPoll
    }
    controller.productContractRevision = PorticoViewerScopeOpaqueId(contract.data.actionRevision, 128)
    libraries = PorticoServerConnectionServerRequest(controller, "GET", "getLibraries", invalid, true)
    navigation = PorticoServerConnectionServerRequest(controller, "GET", "getAccountLibraryNavigation", invalid, true)
    if libraries.interrupted or navigation.interrupted then return false
    if libraries.sessionRefreshFailed = true or navigation.sessionRefreshFailed = true
        terminalRefresh = libraries.sessionRefreshTerminal = true or navigation.sessionRefreshTerminal = true
        if terminalRefresh
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "permission-removed", "server-session-expired")
        else
            PorticoServerConnectionFail(controller, "server-offline", true, true)
        end if
        return false
    end if
    if not libraries.ok or not navigation.ok
        PorticoServerConnectionFail(controller, "bootstrap-failed", true, true)
        return false
    end if
    controller.libraryItems = PorticoServerConnectionLibraryItems(libraries.data, navigation.data)
    controller.navigationVerified = true
    return true
end function

function PorticoServerConnectionServerRequest(controller as object, method as string, operationId as string, body as dynamic, authenticated as boolean) as object
    path = PorticoServerConnectionOperationPath(controller, "server", operationId, invalid)
    if path = "" then return PorticoServerConnectionHttpFailure(0, false, "operation_not_allowed")
    headers = {}
    if body <> invalid then headers["Content-Type"] = "application/json"
    if authenticated then headers.Authorization = "Bearer " + controller.session.accessToken
    bodyText = ""
    if body <> invalid then bodyText = FormatJson(body)
    result = PorticoServerConnectionHttp(controller, {method: method, url: controller.session.apiBaseUrl + path, body: bodyText, headers: headers, timeoutMs: 12000, expectJson: true})
    if authenticated and not result.interrupted and result.status = 401 and controller.sessionGeneration <> controller.last401Generation
        controller.last401Generation = controller.sessionGeneration
        if PorticoServerConnectionRefresh(controller, true)
            headers.Authorization = "Bearer " + controller.session.accessToken
            result = PorticoServerConnectionHttp(controller, {method: method, url: controller.session.apiBaseUrl + path, body: bodyText, headers: headers, timeoutMs: 12000, expectJson: true})
        else
            result.sessionRefreshFailed = true
            result.sessionRefreshTerminal = controller.refreshTerminal
        end if
    end if
    return result
end function

function PorticoServerConnectionRefresh(controller as object, afterUnauthorized as boolean) as boolean
    controller.refreshTerminal = false
    source = PorticoServerSessionStored(controller.session)
    if source = invalid then return false
    rotation = PorticoServerConnectionPendingRotation(source)
    if rotation = invalid
        PorticoServerConnectionScheduleRefreshFailure(controller, source, afterUnauthorized)
        return false
    end if
    path = PorticoServerConnectionOperationPath(controller, "server", "refreshNativeSession", invalid)
    result = PorticoServerConnectionHttp(controller, {
        method: "POST", url: source.apiBaseUrl + path, body: FormatJson({refreshToken: source.refreshToken, rotationKey: rotation.rotationKey}),
        headers: {"Content-Type": "application/json"}, timeoutMs: 12000, expectJson: true
    })
    if result.interrupted then return false
    if not result.ok
        if PorticoServerConnectionRefreshFailureIsTerminal(result)
            controller.refreshTerminal = true
            PorticoSecureRegistryClear("server-refresh-rotation")
            PorticoServerConnectionFence(controller, controller.viewerGeneration, "permission-removed", "server-session-expired")
        else
            PorticoServerConnectionScheduleRefreshFailure(controller, source, afterUnauthorized)
        end if
        return false
    end if
    expected = {
        authority: source.authority, accountId: source.accountId, serverId: source.serverId,
        profileId: source.profileId, installationId: source.installationId
    }
    replacement = PorticoServerSessionRecord(result.data, source, expected)
    if replacement = invalid or replacement.authorizationRevision <> source.authorizationRevision
        PorticoServerConnectionFence(controller, controller.viewerGeneration, "permission-removed", "session-scope-changed")
        return false
    end if
    recordType = "server-session"
    if PorticoCoreIsAssociativeArray(controller.activationBackup) then recordType = "pending-server-session"
    committed = PorticoSecureRegistryCommit(recordType, replacement)
    if not committed.ok
        ' The old session and its old-token/rotation-key journal remain the only
        ' authoritative durable pair. Never advance memory to a successor that
        ' cannot survive process death; retrying the same pair recovers the same
        ' idempotent successor after storage becomes available.
        PorticoServerConnectionFail(controller, "storage-unavailable", true, true)
        return false
    end if
    controller.session = replacement
    PorticoSecureRegistryClear("server-refresh-rotation")
    controller.sessionGeneration = committed.generation
    controller.last401Generation = -1
    controller.refreshFailures = 0
    controller.refreshTerminal = false
    PorticoServerConnectionScheduleRefresh(controller)
    return true
end function

function PorticoServerConnectionPendingRotation(session as object) as dynamic
    existing = PorticoSecureRegistryRead("server-refresh-rotation")
    if existing.ok and PorticoCoreIsAssociativeArray(existing.payload)
        if existing.payload.refreshToken = session.refreshToken and Len(PorticoCoreSafeText(existing.payload.rotationKey, 128)) >= 43 then return existing.payload
    end if
    rotationKey = PorticoSecureRegistryRotationKey()
    if rotationKey = "" then return invalid
    pending = {version: 1, purpose: "crash-safe-refresh-rotation", refreshToken: session.refreshToken, rotationKey: rotationKey}
    if not PorticoSecureRegistryCommit("server-refresh-rotation", pending).ok then return invalid
    return pending
end function

function PorticoServerConnectionRefreshFailureIsTerminal(result as object) as boolean
    code = ""
    if PorticoCoreIsAssociativeArray(result.problem) then code = LCase(PorticoCoreSafeIdentifier(result.problem.code, 96))
    return code = "credential_revoked" or code = "refresh_reused" or code = "account_deleted" or code = "profile_deleted" or code = "membership_removed" or code = "server_session_revoked" or code = "invalid_refresh_token" or code = "refresh_token_reuse"
end function

sub PorticoServerConnectionScheduleRefreshFailure(controller as object, source as object, afterUnauthorized as boolean)
    controller.refreshFailures = controller.refreshFailures + 1
    if controller.refreshFailures > 7 then controller.refreshFailures = 7
    controller.nextRefreshAt = controller.clock.TotalSeconds() + (5 * (2 ^ (controller.refreshFailures - 1)))
    if afterUnauthorized or PorticoSignedDocumentSecondsUntil(source.accessExpiresAt) <= 0
        PorticoServerConnectionFail(controller, "server-offline", true, true)
    end if
end sub

sub PorticoServerConnectionScheduleRefresh(controller as object)
    remaining = PorticoSignedDocumentSecondsUntil(controller.session.accessExpiresAt)
    delay = 5
    if remaining <> invalid then delay = remaining - 300
    if delay < 5 then delay = 5
    if delay > 1800 then delay = 1800
    controller.nextRefreshAt = controller.clock.TotalSeconds() + delay
end sub

sub PorticoServerConnectionRevokeBestEffort(controller as object, session as dynamic)
    stored = PorticoServerSessionStored(session)
    if stored = invalid then return
    path = PorticoServerConnectionOperationPath(controller, "server", "revokeNativeSession", invalid)
    if path = "" then return
    PorticoServerConnectionHttp(controller, {
        method: "POST", url: stored.apiBaseUrl + path, body: FormatJson({refreshToken: stored.refreshToken}),
        headers: {"Content-Type": "application/json"}, timeoutMs: 5000, expectJson: true
    })
end sub

sub PorticoServerConnectionHandleHostedFailure(controller as object, result as object, accountGeneration as integer)
    if result.status = 401
        PorticoServerConnectionFail(controller, "account-refresh-required", true, true)
        PorticoServerConnectionPublish(controller, true)
    else if result.status = 403 or result.status = 404
        PorticoServerConnectionFail(controller, "server-access-denied", false, false)
    else
        PorticoServerConnectionFail(controller, "hosted-offline", true, true)
    end if
end sub

sub PorticoServerConnectionFail(controller as object, code as string, retryable as boolean, preserveContent as boolean)
    if PorticoCoreIsAssociativeArray(controller.activationBackup)
        controller.profileActivationFailed = true
        if PorticoServerConnectionRestoreActivationBackup(controller) then return
    end if
    controller.serverErrorCode = PorticoCoreSafeIdentifier(code, 96)
    controller.serverStatus = "blocked"
    if retryable then controller.serverStatus = "offline"
    if code = "server-identity-mismatch" or code = "route-trust-failed" then controller.serverStatus = "identity-mismatch"
    if code = "hosted-incompatible" or code = "product-contract-incompatible" or code = "operation-contract-invalid" then controller.serverStatus = "incompatible"
    if code = "server-access-denied" or code = "server-session-expired" then controller.serverStatus = "permission-removed"
    if not preserveContent
        controller.libraryItems = []
    controller.navigationVerified = false
    controller.eventCapabilities = invalid
    controller.productContractRevision = ""
    end if
    PorticoServerConnectionPublish(controller, false)
end sub

sub PorticoServerConnectionPublish(controller as object, accountRefreshRequired as boolean)
    projection = {
        serverStatus: controller.serverStatus,
        serverErrorCode: controller.serverErrorCode,
        serverMessageId: PorticoServerConnectionMessageId(controller.serverErrorCode),
        selectedServerName: PorticoServerSessionLabel(controller.serverName, "Portico Server", 80),
        activeProfileName: PorticoServerSessionLabel(controller.profileName, "", 80),
        navigationSnapshotVerified: controller.navigationVerified,
        libraryItems: controller.libraryItems,
        accountRefreshRequired: accountRefreshRequired,
        scopeAssertionReady: controller.assertionId <> "",
        viewerGeneration: controller.viewerGeneration,
        activationSequence: controller.activationSequence,
        productContractStatus: "idle",
        productContractRevision: controller.productContractRevision
    }
    session = PorticoServerSessionStored(controller.session)
    if session <> invalid
        projection.authorizationRevision = session.authorizationRevision
        projection.routeGeneration = session.routeGeneration
    else
        projection.authorizationRevision = ""
        projection.routeGeneration = ""
    end if
    if controller.profileActivationFailed = true then projection.profileActivationFailed = true
    if controller.eventCapabilities <> invalid
        projection.eventCapabilities = controller.eventCapabilities
        projection.productContractStatus = "ready"
    else if controller.serverStatus = "incompatible"
        projection.productContractStatus = "error"
    end if
    if controller.assertionId <> "" then projection.scopeAssertionId = controller.assertionId
    if PorticoCoreIsAssociativeArray(controller.provisionalContext) then projection.privateBootstrapContext = controller.provisionalContext
    m.top.projection = projection
    controller.profileActivationFailed = false
end sub

function PorticoServerConnectionMessageId(code as string) as string
    if code = "" then return ""
    if code = "server-offline" or code = "server-unreachable" or code = "hosted-offline" or code = "bootstrap-failed" then return "problem.server-unavailable"
    if code = "account-required" or code = "account-refresh-required" then return "auth.device-session-required"
    if code = "profile-pin-required" then return "auth.profile-pin-required"
    if code = "profile-selection-expired" or code = "profile-reactivation-required" then return "auth.profile-selection-required"
    if code = "hosted-incompatible" then return "auth.client-update-required"
    if code = "product-contract-incompatible" or code = "operation-contract-invalid" then return "auth.server-update-required"
    if code = "server-access-denied" then return "problem.forbidden"
    if code = "server-session-expired" then return "auth.session-expired"
    if code = "server-identity-mismatch" or code = "route-trust-failed" then return "problem.connection-failed"
    return "problem.request-failed"
end function

function PorticoServerConnectionOperationPath(controller as object, service as string, operationId as string, inputs as dynamic) as string
    if controller.operationContract = invalid then return ""
    resolved = PorticoOperationContractResolvePath(controller.operationContract, service, operationId, inputs)
    if not resolved.ok then return ""
    if service = "server" then return "/api" + resolved.path
    return resolved.path
end function

function PorticoServerConnectionHostedBaseUrl() as string
    return "https://api.getportico.tv"
end function

function PorticoServerConnectionAccountCredentials() as dynamic
    record = PorticoSecureRegistryRead("account-credentials")
    if not record.ok or not PorticoCoreIsAssociativeArray(record.payload) or record.payload.signedOut = true then return invalid
    token = PorticoCoreSafeText(record.payload.accessToken, 4096)
    if Left(token, 8) <> "ptc_acc_" or Len(token) < 16 then return invalid
    user = record.payload.user
    device = record.payload.device
    if not PorticoCoreIsAssociativeArray(user) or not PorticoCoreIsAssociativeArray(device) then return invalid
    userId = PorticoServerSessionId(user.id)
    deviceId = PorticoServerSessionId(device.id)
    if userId = "" or deviceId = "" or PorticoServerSessionId(device.userId) <> userId then return invalid
    return {accessToken: token, generation: record.generation, userId: userId, deviceId: deviceId}
end function

function PorticoServerConnectionRouteCandidates(source as dynamic) as object
    result = []
    if not PorticoCoreIsArray(source) then return result
    ' A healthy identity-pinned LAN route is the default data plane. Signed
    ' public routes remain verified fallbacks for topology changes and outages.
    priorities = ["lan", "lan_ip_encoded", "lan_discovered", "public_direct", "public_direct_ip_encoded", "direct", "direct_ip_encoded"]
    seen = {}
    for each routeType in priorities
        for each rawRoute in source
            if result.Count() >= 12 then return result
            if PorticoCoreIsAssociativeArray(rawRoute) and LCase(PorticoCoreSafeText(rawRoute.type, 48)) = routeType
                quality = LCase(PorticoCoreSafeText(rawRoute.quality, 48))
                blocked = quality = "stale" or quality = "failed" or quality = "http_failed" or quality = "tls_failed" or quality = "identity_mismatch" or quality = "repairing" or quality = "repair_requested"
                url = PorticoServerSessionSecureBaseUrl(rawRoute.url, PorticoServerSessionRouteAllowsInsecureLan(routeType))
                if not blocked and url <> "" and seen[url] <> true
                    seen[url] = true
                    generation = PorticoSignedDocumentPositiveRevision(rawRoute.generation)
                    result.Push({type: routeType, url: url, generation: generation})
                end if
            end if
        end for
    end for
    return result
end function

function PorticoServerConnectionLibraryItems(libraryResponse as dynamic, navigation as dynamic) as object
    result = []
    if not PorticoCoreIsAssociativeArray(libraryResponse) or not PorticoCoreIsArray(libraryResponse.items) then return result
    if not PorticoCoreIsAssociativeArray(navigation) or not PorticoCoreIsArray(navigation.pinnedLibraryIds) then return result
    byId = {}
    for each library in libraryResponse.items
        if PorticoCoreIsAssociativeArray(library)
            id = PorticoServerSessionId(library.id)
            name = PorticoServerSessionLabel(library.name, "", 48)
            kind = LCase(PorticoCoreSafeText(library.type, 32))
            if id <> "" and name <> "" and (kind = "movie" or kind = "show" or kind = "anime" or kind = "music" or kind = "audiobook" or kind = "recorded-tv")
                byId[id] = {id: id, name: name, kind: kind}
            end if
        end if
    end for
    for each rawId in navigation.pinnedLibraryIds
        id = PorticoServerSessionId(rawId)
        if id <> "" and byId[id] <> invalid
            result.Push(byId[id])
            if result.Count() >= 4 then return result
        end if
    end for
    return result
end function

function PorticoServerConnectionDeviceName() as string
    info = CreateObject("roDeviceInfo")
    if info = invalid then return "Roku"
    model = PorticoCoreSafeText(info.GetModelDisplayName(), 100)
    if model = "" then model = PorticoCoreSafeText(info.GetModel(), 100)
    return PorticoServerSessionLabel(model, "Roku", 100)
end function

function PorticoServerConnectionHttp(controller as object, rawRequest as object) as object
    requestSource = rawRequest
    if not PorticoCoreIsAssociativeArray(requestSource) then requestSource = {}
    if controller.session <> invalid and PorticoServerSessionRouteAllowsInsecureLan(controller.session.routeType)
        requestSource.allowInsecureLan = true
    end if
    request = PorticoHttpNormalizeRequest(requestSource)
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoServerConnectionHttpFailure(0, false, validation.code)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoServerConnectionHttpFailure(0, true, "transport_error")
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if Left(LCase(request.url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoServerConnectionHttpFailure(0, true, "transport_error")
        if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return PorticoServerConnectionHttpFailure(0, true, "transport_error")
    end if
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return PorticoServerConnectionHttpFailure(0, false, "invalid_header")
    end for
    issued = false
    if request.method = "POST"
        issued = transfer.AsyncPostFromString(request.body)
    else
        issued = transfer.AsyncGetToString()
    end if
    if not issued then return PorticoServerConnectionHttpFailure(0, true, "transport_error")
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoServerConnectionInterrupted(controller)
            transfer.AsyncCancel()
            return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid}
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            return PorticoServerConnectionHttpResult(request, message)
        end if
    end while
    transfer.AsyncCancel()
    return PorticoServerConnectionHttpFailure(0, true, "timeout")
end function

function PorticoServerConnectionInterrupted(controller as object) as boolean
    command = m.top.command
    if not PorticoCoreIsAssociativeArray(command) then return false
    return PorticoHttpInteger(command.sequence, 0) > controller.lastCommandSequence
end function

function PorticoServerConnectionHttpResult(request as object, event as object) as object
    status = event.GetResponseCode()
    if status < 0 then return PorticoServerConnectionHttpFailure(status, true, "transport_error")
    classification = PorticoHttpClassifyStatus(status)
    payload = event.GetString()
    if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoServerConnectionHttpFailure(status, false, "response_too_large")
    parsed = PorticoHttpParseJson(payload)
    if classification.classification = "success"
        if request.expectJson and not parsed.ok then return PorticoServerConnectionHttpFailure(status, false, "parse_error")
        return {interrupted: false, ok: true, status: status, retryable: false, data: parsed.value}
    end if
    problem = invalid
    if parsed.ok and PorticoCoreIsAssociativeArray(parsed.value) then problem = parsed.value
    return {interrupted: false, ok: false, status: status, retryable: classification.retryable, data: invalid, problem: problem}
end function

function PorticoServerConnectionHttpFailure(status as integer, retryable as boolean, code as string) as object
    return {interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: code}
end function
