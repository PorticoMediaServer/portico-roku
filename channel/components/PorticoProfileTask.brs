sub init()
    m.top.functionName = "PorticoProfileTaskRun"
end sub

sub PorticoProfileTaskRun()
    controller = {
        lastSequence: 0, viewerGeneration: 0, authority: "", accountId: "", serverId: "",
        installationId: "", status: "idle", errorCode: "", errorMessageId: "",
        directory: invalid, selectedProfileId: "", selectionEnvelope: invalid, selectionTransactionId: ""
    }
    PorticoProfileTaskPublish(controller)
    while true
        PorticoProfileTaskHandleCommand(controller)
        Sleep(250)
    end while
end sub

sub PorticoProfileTaskHandleCommand(controller as object)
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return
    sequence = PorticoHttpInteger(command.sequence, 0)
    if sequence <= controller.lastSequence then return
    controller.lastSequence = sequence
    generation = PorticoHttpInteger(command.viewerGeneration, 0)
    if generation <> controller.viewerGeneration
        PorticoProfileTaskFence(controller, generation)
    end if
    kind = LCase(PorticoHttpScalarString(command.kind, ""))
    if kind = "viewer-state"
        PorticoProfileTaskApplyViewerState(controller, command)
    else if kind = "load-directory"
        PorticoProfileTaskLoadHostedDirectory(controller)
    else if kind = "select-profile"
        PorticoProfileTaskSelectHostedProfile(controller, command)
    else if kind = "set-local-directory"
        PorticoProfileTaskSetLocalDirectory(controller, command)
    else if kind = "clear-selection"
        controller.selectionEnvelope = invalid
        controller.selectionTransactionId = ""
        controller.selectedProfileId = ""
        controller.status = "ready"
        PorticoProfileTaskPublish(controller)
    else if kind = "cancel" or kind = "sign-out"
        PorticoProfileTaskFence(controller, generation)
        PorticoProfileTaskPublish(controller)
    end if
end sub

sub PorticoProfileTaskFence(controller as object, generation as integer)
    PorticoProfilesSelectionTransactionClear()
    controller.viewerGeneration = generation
    controller.status = "idle"
    controller.errorCode = ""
    controller.errorMessageId = ""
    controller.directory = invalid
    controller.selectedProfileId = ""
    controller.selectionEnvelope = invalid
    controller.selectionTransactionId = ""
end sub

sub PorticoProfileTaskApplyViewerState(controller as object, command as object)
    controller.authority = LCase(PorticoProfilesSafeText(command.authority, 16))
    controller.accountId = PorticoProfilesSafeId(command.accountId)
    controller.serverId = PorticoProfilesSafeId(command.serverId)
    controller.installationId = PorticoProfilesSafeId(command.installationId)
    if controller.authority <> "hosted" and controller.authority <> "local" then controller.authority = ""
    if command.signedIn <> true
        PorticoProfileTaskFence(controller, controller.viewerGeneration)
        PorticoProfileTaskPublish(controller)
        return
    end if
    if controller.authority = "hosted" and controller.accountId <> "" and controller.serverId <> ""
        PorticoProfileTaskLoadHostedDirectory(controller)
    else
        controller.status = "awaiting-directory"
        PorticoProfileTaskPublish(controller)
    end if
end sub

sub PorticoProfileTaskLoadHostedDirectory(controller as object)
    if controller.authority <> "hosted" then return
    credentials = PorticoProfileTaskAccountCredentials(controller.accountId)
    if credentials = invalid
        PorticoProfileTaskFail(controller, "authentication_required", "problem.connection-failed")
        return
    end if
    controller.status = "loading"
    PorticoProfileTaskPublish(controller)
    result = PorticoProfileTaskRequest(controller, "GET", "https://api.getportico.tv/api/account/profiles", credentials.accessToken, invalid)
    if result.interrupted then return
    if not result.ok
        PorticoProfileTaskFail(controller, result.code, result.messageId)
        return
    end if
    source = result.data
    if source <> invalid and Type(source) = "roAssociativeArray" and source.profilesAllowed = invalid then source.profilesAllowed = true
    directory = PorticoProfilesDirectory(source, "hosted", controller.accountId, controller.serverId)
    if directory = invalid
        PorticoProfileTaskFail(controller, "invalid_profile_directory", "problem.profile-request-failed")
        return
    end if
    controller.directory = directory
    controller.status = "ready"
    controller.errorCode = ""
    controller.errorMessageId = ""
    PorticoProfileTaskPublish(controller)
end sub

sub PorticoProfileTaskSetLocalDirectory(controller as object, command as object)
    if controller.authority <> "local" then return
    directory = PorticoProfilesDirectory(command.directory, "local", controller.accountId, controller.serverId)
    if directory = invalid
        PorticoProfileTaskFail(controller, "invalid_profile_directory", "problem.profile-request-failed")
        return
    end if
    controller.directory = directory
    controller.status = "ready"
    PorticoProfileTaskPublish(controller)
end sub

sub PorticoProfileTaskSelectHostedProfile(controller as object, command as object)
    if controller.authority <> "hosted" or controller.directory = invalid then return
    profile = PorticoProfilesFind(controller.directory, PorticoProfilesSafeId(command.profileId))
    if profile = invalid
        PorticoProfileTaskFail(controller, "profile_not_found", "auth.profile-not-found")
        return
    end if
    pin = ""
    if command.sealedPin <> invalid then pin = PorticoProfilesUnsealPin(command.sealedPin, profile.id, controller.viewerGeneration)
    command.sealedPin = ""
    currentCommand = m.top.command
    if currentCommand <> invalid and PorticoHttpInteger(currentCommand.sequence, -1) = controller.lastSequence
        m.top.command = {sequence: controller.lastSequence, kind: "consumed", viewerGeneration: controller.viewerGeneration}
    end if
    if profile.hasPIN and pin = ""
        controller.selectedProfileId = profile.id
        controller.status = "pin-required"
        PorticoProfileTaskPublish(controller)
        return
    end if
    credentials = PorticoProfileTaskAccountCredentials(controller.accountId)
    if credentials = invalid
        PorticoProfileTaskFail(controller, "authentication_required", "problem.connection-failed")
        return
    end if
    body = {serverId: controller.serverId}
    ' Profile authority comes from the account session and signed assertion.
    if controller.installationId <> "" then body.installationId = controller.installationId
    if pin <> "" then body.pin = pin
    controller.status = "authorizing"
    controller.selectedProfileId = profile.id
    PorticoProfileTaskPublish(controller)
    path = "https://api.getportico.tv/api/account/profiles/" + PorticoProfileTaskEscape(profile.id) + "/selection-assertions"
    result = PorticoProfileTaskRequest(controller, "POST", path, credentials.accessToken, body)
    pin = ""
    if result.interrupted then return
    if not result.ok
        if result.code = "profile_pin_required" or result.code = "profile_pin_invalid" then controller.status = "pin-required"
        if controller.status <> "pin-required" then controller.status = "error"
        controller.errorCode = result.code
        controller.errorMessageId = result.messageId
        PorticoProfileTaskPublish(controller)
        return
    end if
    envelope = PorticoProfileTaskSelectionEnvelope(result.data, controller, profile)
    if envelope = invalid
        PorticoProfileTaskFail(controller, "invalid_profile_selection", "auth.profile-selection-failed")
        return
    end if
    controller.selectionTransactionId = PorticoHttpNewRequestId()
    if PorticoProfileTaskInterrupted(controller) or not PorticoProfilesSelectionTransactionWrite(controller.selectionTransactionId, envelope, "hosted", controller.accountId, controller.serverId, profile.id, controller.viewerGeneration)
        controller.selectionTransactionId = ""
        PorticoProfileTaskFail(controller, "profile_selection_handoff_failed", "auth.profile-selection-failed")
        return
    end if
    controller.selectionEnvelope = invalid
    controller.status = "selection-authorized"
    controller.errorCode = ""
    controller.errorMessageId = ""
    PorticoProfileTaskPublish(controller)
end sub

function PorticoProfileTaskSelectionEnvelope(value as dynamic, controller as object, profile as object) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> "v1" then return invalid
    if value.audience <> "portico-media-server" or PorticoProfilesSafeId(value.accountId) <> controller.accountId then return invalid
    if PorticoProfilesSafeId(value.serverId) <> controller.serverId or PorticoProfilesSafeId(value.profileId) <> profile.id then return invalid
    accountRevision = PorticoProfilesInteger(value.accountRevision, -1)
    if controller.directory = invalid or accountRevision < 1 or accountRevision <> PorticoProfilesInteger(controller.directory.revision, 0) then return invalid
    if PorticoProfilesInteger(value.pinRevision, -1) <> profile.pinRevision then return invalid
    if PorticoProfilesSafeText(value.signature, 4096) = "" or PorticoProfilesSafeText(value.expiresAt, 64) = "" then return invalid
    return value
end function

function PorticoProfileTaskAccountCredentials(accountId as string) as dynamic
    record = PorticoSecureRegistryRead("account-credentials")
    if not record.ok or record.payload = invalid or record.payload.signedOut = true then return invalid
    payload = record.payload
    if payload.user = invalid or PorticoProfilesSafeId(payload.user.id) <> accountId then return invalid
    token = PorticoHttpScalarString(payload.accessToken, "")
    if Left(token, 8) <> "ptc_acc_" or Len(token) < 16 or Len(token) > 4096 then return invalid
    return {accessToken: token, generation: record.generation}
end function

function PorticoProfileTaskRequest(controller as object, method as string, url as string, token as string, body as dynamic) as object
    request = PorticoHttpNormalizeRequest({method: method, url: url, headers: {Authorization: "Bearer " + token}, body: body, timeoutMs: 15000, expectJson: true})
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
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return {ok: false, interrupted: false, code: "invalid_header", messageId: "problem.invalid-request", data: invalid}
    end for
    started = false
    if method = "GET" then started = transfer.AsyncGetToString() else started = transfer.AsyncPostFromString(request.body)
    if not started then return {ok: false, interrupted: false, code: "network_unavailable", messageId: "problem.connection-failed", data: invalid}
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoProfileTaskInterrupted(controller)
            transfer.AsyncCancel()
            return {ok: false, interrupted: true, code: "request_cancelled", messageId: "problem.request-failed", data: invalid}
        end if
        event = Wait(100, port)
        if event <> invalid and Type(event) = "roUrlEvent" and event.GetSourceIdentity() = identity
            status = event.GetResponseCode()
            payloadText = event.GetString()
            if Len(payloadText) > PorticoHttpLimits().maximumResponseBytes then return {ok: false, interrupted: false, code: "response_too_large", messageId: "problem.request-failed", data: invalid}
            parsed = PorticoHttpParseJson(payloadText)
            if status >= 200 and status < 300 and parsed.ok then return {ok: true, interrupted: false, code: "", messageId: "", data: parsed.value}
            payload = invalid
            if parsed.ok then payload = parsed.value
            code = "request_failed"
            messageId = "problem.request-failed"
            if payload <> invalid and Type(payload) = "roAssociativeArray"
                code = PorticoHttpSafeIdentifier(payload.code, code)
                messageId = PorticoHttpSafeIdentifier(payload.messageId, messageId)
            else if status = 401
                code = "authentication_required"
                messageId = "problem.request-failed"
            else if status = 403
                code = "forbidden"
                messageId = "problem.forbidden"
            end if
            return {ok: false, interrupted: false, code: code, messageId: messageId, data: invalid}
        end if
    end while
    transfer.AsyncCancel()
    return {ok: false, interrupted: false, code: "request_timeout", messageId: "problem.timeout", data: invalid}
end function

function PorticoProfileTaskInterrupted(controller as object) as boolean
    command = m.top.command
    return command <> invalid and Type(command) = "roAssociativeArray" and PorticoHttpInteger(command.sequence, 0) > controller.lastSequence
end function

function PorticoProfileTaskEscape(value as string) as string
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return ""
    return transfer.Escape(value)
end function

sub PorticoProfileTaskFail(controller as object, code as string, messageId as string)
    controller.status = "error"
    controller.errorCode = PorticoHttpSafeIdentifier(code, "request_failed")
    controller.errorMessageId = PorticoHttpSafeIdentifier(messageId, "problem.request-failed")
    controller.selectionEnvelope = invalid
    PorticoProfilesSelectionTransactionClear()
    controller.selectionTransactionId = ""
    PorticoProfileTaskPublish(controller)
end sub

sub PorticoProfileTaskPublish(controller as object)
    projection = {
        viewerGeneration: controller.viewerGeneration, status: controller.status, errorCode: controller.errorCode,
        errorMessageId: controller.errorMessageId,
        handoffReady: controller.selectionTransactionId <> ""
    }
    if controller.selectionTransactionId <> "" then projection.handoffId = controller.selectionTransactionId
    if controller.directory <> invalid then projection.directory = PorticoProfilesSafeProjection(controller.directory)
    m.top.projection = projection
end sub
