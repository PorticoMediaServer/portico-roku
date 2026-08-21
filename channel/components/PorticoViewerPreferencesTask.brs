sub init()
    m.top.functionName = "PorticoViewerPreferencesTaskRun"
end sub

sub PorticoViewerPreferencesTaskRun()
    operations = PorticoOperationContractLoad()
    operationContract = invalid
    if operations.ok then operationContract = operations.value
    controller = {
        lastSequence: 0, viewerGeneration: 0, status: "idle", errorCode: "", errorMessageId: "",
        expected: invalid, bundle: invalid, conflictPending: false, operationContract: operationContract,
        historyStatus: "idle", historyResult: "", automaticTrustStatus: "idle", quietRefresh: false
    }
    PorticoViewerPreferencesTaskPublish(controller)
    while true
        command = m.top.command
        if command <> invalid and Type(command) = "roAssociativeArray"
            sequence = PorticoHttpInteger(command.sequence, 0)
            if sequence > controller.lastSequence
                controller.lastSequence = sequence
                generation = PorticoHttpInteger(command.viewerGeneration, 0)
                if generation <> controller.viewerGeneration
                    controller.viewerGeneration = generation
                    controller.status = "idle"
                    controller.bundle = invalid
                    controller.expected = invalid
                    controller.conflictPending = false
                    controller.quietRefresh = false
                end if
                PorticoViewerPreferencesTaskCommand(controller, command)
            end if
        end if
        Sleep(250)
    end while
end sub

sub PorticoViewerPreferencesTaskCommand(controller as object, command as object)
    kind = LCase(PorticoHttpScalarString(command.kind, ""))
    if kind = "viewer-state"
        controller.expected = PorticoViewerPreferencesTaskIdentity(command)
        if command.online = true and controller.expected <> invalid then PorticoViewerPreferencesTaskLoad(controller) else PorticoViewerPreferencesTaskPublish(controller)
    else if kind = "load"
        PorticoViewerPreferencesTaskLoad(controller)
    else if kind = "patch"
        PorticoViewerPreferencesTaskPatch(controller, command)
    else if kind = "automatic-profile"
        PorticoViewerPreferencesTaskAutomaticProfile(controller, command.enabled = true)
    else if kind = "clear-watch-history"
        PorticoViewerPreferencesTaskClearHistory(controller)
    else if kind = "reload"
        PorticoViewerPreferencesTaskLoad(controller)
    else if kind = "quiet-reload"
        controller.quietRefresh = true
        PorticoViewerPreferencesTaskLoad(controller)
    else if kind = "cancel" or kind = "sign-out"
        controller.quietRefresh = false
        controller.status = "idle"
        controller.bundle = invalid
        controller.expected = invalid
        controller.historyStatus = "idle"
        controller.historyResult = ""
        controller.automaticTrustStatus = "idle"
        if kind = "sign-out" then PorticoViewerPreferencesClearLaunch()
        PorticoViewerPreferencesTaskPublish(controller)
    end if
end sub

function PorticoViewerPreferencesTaskIdentity(source as object) as dynamic
    scope = PorticoViewerScopeNormalize(source.viewerScope)
    installationId = PorticoProfilesSafeId(source.installationId)
    if scope = invalid or installationId = "" or scope.viewerGeneration <> PorticoHttpInteger(source.viewerGeneration, 0) then return invalid
    return {
        authority: scope.authority, accountId: scope.accountId, serverId: scope.serverId,
        profileId: scope.profileId, authorizationRevision: scope.authorizationRevision,
        viewerGeneration: scope.viewerGeneration, installationId: installationId, scope: scope
    }
end function

function PorticoViewerPreferencesTaskSession(expected as dynamic) as dynamic
    if expected = invalid then return invalid
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid or record.payload.signedOut = true then return invalid
    value = PorticoServerSessionStored(record.payload)
    if value = invalid or PorticoProfilesSafeId(value.installationId) <> expected.installationId then return invalid
    actualScope = PorticoServerSessionScope(value, expected.viewerGeneration)
    if actualScope = invalid or not PorticoViewerScopeEquals(actualScope, expected.scope) then return invalid
    projection = PorticoServerSessionRequestProjection(value, expected.scope, record.generation)
    if projection = invalid then return invalid
    projection.token = projection.accessToken
    return projection
end function

function PorticoViewerPreferencesTaskSessionStillCurrent(expected as dynamic, session as dynamic) as boolean
    current = PorticoViewerPreferencesTaskSession(expected)
    return current <> invalid and session <> invalid and current.registryGeneration = session.registryGeneration and PorticoViewerScopeEquals(current.viewerScope, session.viewerScope)
end function

sub PorticoViewerPreferencesTaskLoad(controller as object)
    session = PorticoViewerPreferencesTaskSession(controller.expected)
    if session = invalid
        PorticoViewerPreferencesTaskFail(controller, "authentication_required", "problem.connection-failed")
        return
    end if
    if not controller.quietRefresh
        controller.status = "loading"
        PorticoViewerPreferencesTaskPublish(controller)
    end if
    query = "?deviceClass=television&installationId=" + PorticoViewerPreferencesTaskEscape(controller.expected.installationId)
    result = PorticoViewerPreferencesTaskOperation(controller, session, "getViewerPreferenceBundle", {}, query, invalid)
    if result.interrupted then return
    if not result.ok
        PorticoViewerPreferencesTaskFail(controller, result.code, result.messageId)
        return
    end if
    bundle = PorticoViewerPreferencesBundle(result.data, controller.expected)
    if bundle = invalid
        PorticoViewerPreferencesTaskFail(controller, "invalid_preferences", "preferences.invalid")
        return
    end if
    controller.bundle = bundle
    if bundle.accountServerInstallation.values.lastProfileId <> controller.expected.profileId
        activated = PorticoViewerPreferencesTaskOperation(controller, session, "recordViewerProfileActivation", {}, "", {version: "v1", expectedRevision: bundle.accountServerInstallation.revision})
        if activated.interrupted then return
        if not activated.ok
            if activated.status = 409
                controller.conflictPending = true
                PorticoViewerPreferencesTaskLoad(controller)
                return
            end if
            PorticoViewerPreferencesTaskFail(controller, activated.code, "preferences.request-failed")
            return
        end if
        document = PorticoViewerPreferencesDocument(activated.data, "account-server-installation")
        if document = invalid or PorticoProfilesSafeId(document.values.lastProfileId) <> controller.expected.profileId
            PorticoViewerPreferencesTaskFail(controller, "invalid_profile_activation", "auth.profile-selection-failed")
            return
        end if
        controller.bundle.accountServerInstallation = document
    end if
    existing = PorticoViewerPreferencesReadLaunch(controller.expected.authority, controller.expected.accountId, controller.expected.serverId, controller.expected.installationId)
    trust = invalid
    if existing <> invalid and existing.lastProfileId = controller.expected.profileId then trust = existing.trust
    restorePolicyResult = PorticoViewerPreferencesTaskRestorePolicy(controller, session)
    if restorePolicyResult.interrupted then return
    restorePolicy = restorePolicyResult.policy
    if not PorticoViewerPreferencesCommitLaunch(controller.expected, controller.bundle.accountServerInstallation, trust, restorePolicy)
        controller.automaticTrustStatus = "storage-error"
    end if
    if controller.conflictPending
        controller.status = "conflict"
        controller.errorCode = "preference_revision_conflict"
        controller.errorMessageId = "preferences.conflict"
        controller.conflictPending = false
    else
        controller.status = "ready"
        controller.errorCode = ""
        controller.errorMessageId = ""
    end if
    controller.quietRefresh = false
    PorticoViewerPreferencesTaskPublish(controller)
end sub

function PorticoViewerPreferencesTaskRestorePolicy(controller as object, session as object) as dynamic
    result = PorticoViewerPreferencesTaskOperation(controller, session, "listAccountProfiles", {}, "", invalid)
    if result.interrupted then return {interrupted: true, policy: invalid}
    if not result.ok then return {interrupted: false, policy: invalid}
    directory = PorticoProfilesDirectory(result.data, controller.expected.authority, controller.expected.accountId, controller.expected.serverId)
    if directory = invalid then return {interrupted: false, policy: invalid}
    return {interrupted: false, policy: PorticoViewerPreferencesDirectoryRestorePolicy(directory, controller.expected.profileId, controller.expected.authorizationRevision)}
end function

sub PorticoViewerPreferencesTaskPatch(controller as object, command as object)
    scopeType = LCase(PorticoHttpScalarString(command.scopeType, ""))
    changes = PorticoViewerPreferencesSafePatch(scopeType, command.changes)
    expectedRevision = PorticoHttpInteger(command.expectedRevision, -1)
    if changes = invalid or expectedRevision < 0
        PorticoViewerPreferencesTaskFail(controller, "invalid_preferences", "preferences.invalid")
        return
    end if
    session = PorticoViewerPreferencesTaskSession(controller.expected)
    if session = invalid
        PorticoViewerPreferencesTaskFail(controller, "authentication_required", "problem.connection-failed")
        return
    end if
    controller.status = "saving"
    PorticoViewerPreferencesTaskPublish(controller)
    query = "?deviceClass=television&installationId=" + PorticoViewerPreferencesTaskEscape(controller.expected.installationId)
    body = {version: "v1", expectedRevision: expectedRevision, changes: changes}
    result = PorticoViewerPreferencesTaskOperation(controller, session, "patchViewerPreferenceDocument", {scopeType: scopeType}, query, body)
    if result.interrupted then return
    if not result.ok
        if result.code = "preference_conflict" or result.code = "preference_revision_conflict"
            controller.conflictPending = true
            PorticoViewerPreferencesTaskLoad(controller)
            return
        end if
        PorticoViewerPreferencesTaskFail(controller, result.code, result.messageId)
        return
    end if
    PorticoViewerPreferencesTaskLoad(controller)
end sub

sub PorticoViewerPreferencesTaskAutomaticProfile(controller as object, enabled as boolean)
    if controller.bundle = invalid or controller.expected = invalid
        PorticoViewerPreferencesTaskFail(controller, "preferences_unavailable", "preferences.request-failed")
        return
    end if
    session = PorticoViewerPreferencesTaskSession(controller.expected)
    if session = invalid
        PorticoViewerPreferencesTaskFail(controller, "authentication_required", "problem.connection-failed")
        return
    end if
    controller.status = "saving"
    controller.automaticTrustStatus = "saving"
    PorticoViewerPreferencesTaskPublish(controller)
    requestBody = {}
    if controller.expected.installationId <> "" then requestBody.installationId = controller.expected.installationId
    if not enabled
        revoked = PorticoViewerPreferencesTaskOperation(controller, session, "revokeAutomaticProfileTrusts", {}, "", requestBody)
        if revoked.interrupted then return
        PorticoViewerPreferencesForgetLaunch(controller.expected.authority, controller.expected.accountId, controller.expected.serverId, controller.expected.installationId)
        if not revoked.ok and revoked.status <> 404
            controller.automaticTrustStatus = "error"
            PorticoViewerPreferencesTaskFail(controller, revoked.code, "auth.automatic-profile-trust-failed")
            return
        end if
    end if
    expectedRevision = controller.bundle.accountServerInstallation.revision
    query = "?deviceClass=television&installationId=" + PorticoViewerPreferencesTaskEscape(controller.expected.installationId)
    selectionMode = "ask"
    if enabled then selectionMode = "last-used"
    patch = {version: "v1", expectedRevision: expectedRevision, changes: {profileSelection: selectionMode}}
    updated = PorticoViewerPreferencesTaskOperation(controller, session, "patchViewerPreferenceDocument", {scopeType: "account-server-installation"}, query, patch)
    if updated.interrupted then return
    if not updated.ok
        if updated.status = 409
            controller.conflictPending = true
            PorticoViewerPreferencesTaskLoad(controller)
            return
        end if
        controller.automaticTrustStatus = "error"
        PorticoViewerPreferencesTaskFail(controller, updated.code, "preferences.request-failed")
        return
    end if
    document = PorticoViewerPreferencesDocument(updated.data, "account-server-installation")
    if document = invalid
        controller.automaticTrustStatus = "error"
        PorticoViewerPreferencesTaskFail(controller, "invalid_preferences", "preferences.invalid")
        return
    end if
    controller.bundle.accountServerInstallation = document
    if enabled
        trustResult = PorticoViewerPreferencesTaskOperation(controller, session, "createAutomaticProfileTrust", {}, "", requestBody)
        if trustResult.interrupted then return
        trust = PorticoViewerPreferencesAutomaticTrust(trustResult.data, {
            authority: controller.expected.authority,
            accountId: controller.expected.accountId,
            serverId: controller.expected.serverId,
            installationId: controller.expected.installationId,
            lastProfileId: controller.expected.profileId
        })
        if not trustResult.ok or trust = invalid or not PorticoViewerPreferencesCommitLaunch(controller.expected, document, trust)
            ' A trust that cannot be stored must not remain live on the server.
            PorticoViewerPreferencesTaskOperation(controller, session, "revokeAutomaticProfileTrusts", {}, "", requestBody)
            PorticoViewerPreferencesForgetLaunch(controller.expected.authority, controller.expected.accountId, controller.expected.serverId, controller.expected.installationId)
            rollbackBody = {version: "v1", expectedRevision: document.revision, changes: {profileSelection: "ask"}}
            rollback = PorticoViewerPreferencesTaskOperation(controller, session, "patchViewerPreferenceDocument", {scopeType: "account-server-installation"}, query, rollbackBody)
            if rollback.ok
                rollbackDocument = PorticoViewerPreferencesDocument(rollback.data, "account-server-installation")
                if rollbackDocument <> invalid
                    controller.bundle.accountServerInstallation = rollbackDocument
                    PorticoViewerPreferencesCommitLaunch(controller.expected, rollbackDocument, invalid)
                end if
            end if
            controller.automaticTrustStatus = "error"
            PorticoViewerPreferencesTaskFail(controller, "automatic_profile_trust_failed", "auth.automatic-profile-trust-failed")
            return
        end if
    else
        if not PorticoViewerPreferencesCommitLaunch(controller.expected, document, invalid)
            controller.automaticTrustStatus = "storage-error"
            PorticoViewerPreferencesTaskFail(controller, "preference_storage_failed", "preferences.request-failed")
            return
        end if
    end if
    controller.automaticTrustStatus = "ready"
    controller.status = "ready"
    controller.errorCode = ""
    controller.errorMessageId = ""
    PorticoViewerPreferencesTaskPublish(controller)
end sub

sub PorticoViewerPreferencesTaskClearHistory(controller as object)
    session = PorticoViewerPreferencesTaskSession(controller.expected)
    if session = invalid
        PorticoViewerPreferencesTaskFail(controller, "authentication_required", "problem.connection-failed")
        return
    end if
    controller.historyStatus = "clearing"
    controller.historyResult = ""
    PorticoViewerPreferencesTaskPublish(controller)
    result = PorticoViewerPreferencesTaskOperation(controller, session, "deleteAccountWatchHistory", {}, "", invalid)
    if result.interrupted then return
    if not result.ok
        controller.historyStatus = "error"
        controller.historyResult = "preferences.request-failed"
    else
        controller.historyStatus = "cleared"
        controller.historyResult = "preferences.history-cleared"
    end if
    PorticoViewerPreferencesTaskPublish(controller)
end sub

function PorticoViewerPreferencesTaskOperation(controller as object, session as object, operationId as string, inputs as object, query as string, body as dynamic) as object
    if controller.operationContract = invalid then return {ok: false, interrupted: false, status: 0, code: "operation_contract_unavailable", messageId: "problem.request-failed", data: invalid}
    operation = PorticoOperationContractResolvePath(controller.operationContract, "server", operationId, inputs)
    if not operation.ok then return {ok: false, interrupted: false, status: 0, code: operation.code, messageId: "problem.request-failed", data: invalid}
    return PorticoViewerPreferencesTaskRequest(controller, session, operation.method, "/api" + operation.path + query, body)
end function

function PorticoViewerPreferencesTaskRequest(controller as object, session as object, method as string, path as string, body as dynamic) as object
    request = PorticoHttpNormalizeRequest({method: method, url: session.origin + path, headers: {Authorization: "Bearer " + session.token}, body: body, timeoutMs: 15000, expectJson: true, allowInsecureLan: session.allowInsecureLan = true})
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return {ok: false, interrupted: false, code: validation.code, messageId: "problem.invalid-request", data: invalid}
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return {ok: false, interrupted: false, code: "network_unavailable", messageId: "problem.connection-failed", data: invalid}
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(method)
    transfer.RetainBodyOnError(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return {ok: false, interrupted: false, code: "network_unavailable", messageId: "problem.connection-failed", data: invalid}
    if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return {ok: false, interrupted: false, code: "network_unavailable", messageId: "problem.connection-failed", data: invalid}
    for each name in request.headers
        if not transfer.AddHeader(name, request.headers[name]) then return {ok: false, interrupted: false, code: "invalid_header", messageId: "problem.invalid-request", data: invalid}
    end for
    started = false
    if method = "GET" then started = transfer.AsyncGetToString() else started = transfer.AsyncPostFromString(request.body)
    if not started then return {ok: false, interrupted: false, code: "network_unavailable", messageId: "problem.connection-failed", data: invalid}
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        command = m.top.command
        if command <> invalid and PorticoHttpInteger(command.sequence, 0) > controller.lastSequence
            transfer.AsyncCancel()
            return {ok: false, interrupted: true, code: "request_cancelled", messageId: "problem.request-failed", data: invalid}
        end if
        event = Wait(100, port)
        if event <> invalid and Type(event) = "roUrlEvent" and event.GetSourceIdentity() = identity
            command = m.top.command
            if (command <> invalid and PorticoHttpInteger(command.sequence, 0) > controller.lastSequence) or not PorticoViewerPreferencesTaskSessionStillCurrent(controller.expected, session) then return {ok: false, interrupted: true, code: "session_fenced", messageId: "problem.request-failed", data: invalid}
            status = event.GetResponseCode()
            payloadText = event.GetString()
            if Len(payloadText) > PorticoHttpLimits().maximumResponseBytes then return {ok: false, interrupted: false, status: status, code: "response_too_large", messageId: "problem.request-failed", data: invalid}
            parsed = PorticoHttpParseJson(payloadText)
            if status >= 200 and status < 300
                if parsed.ok then return {ok: true, interrupted: false, status: status, code: "", messageId: "", data: parsed.value}
                if payloadText.Trim() = "" then return {ok: true, interrupted: false, status: status, code: "", messageId: "", data: {}}
            end if
            code = "request_failed"
            messageId = "problem.request-failed"
            if parsed.ok and parsed.value <> invalid and Type(parsed.value) = "roAssociativeArray"
                code = PorticoHttpSafeIdentifier(parsed.value.code, code)
                messageId = PorticoHttpSafeIdentifier(parsed.value.messageId, messageId)
            end if
            return {ok: false, interrupted: false, status: status, code: code, messageId: messageId, data: invalid}
        end if
    end while
    transfer.AsyncCancel()
    return {ok: false, interrupted: false, status: 0, code: "request_timeout", messageId: "problem.timeout", data: invalid}
end function

function PorticoViewerPreferencesTaskEscape(value as string) as string
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return ""
    return transfer.Escape(value)
end function

sub PorticoViewerPreferencesTaskFail(controller as object, code as string, messageId as string)
    if controller.quietRefresh and controller.bundle <> invalid
        controller.quietRefresh = false
        controller.status = "ready"
        return
    end if
    controller.quietRefresh = false
    controller.status = "error"
    controller.errorCode = PorticoHttpSafeIdentifier(code, "preferences_failed")
    controller.errorMessageId = PorticoHttpSafeIdentifier(messageId, "preferences.request-failed")
    PorticoViewerPreferencesTaskPublish(controller)
end sub

sub PorticoViewerPreferencesTaskPublish(controller as object)
    projection = {viewerGeneration: controller.viewerGeneration, status: controller.status, errorCode: controller.errorCode, errorMessageId: controller.errorMessageId}
    values = PorticoViewerPreferencesProjection(controller.bundle)
    projection.values = values.values
    projection.revisions = values.revisions
    projection.historyStatus = controller.historyStatus
    projection.historyResultMessageId = controller.historyResult
    projection.automaticTrustStatus = controller.automaticTrustStatus
    m.top.projection = projection
end sub
