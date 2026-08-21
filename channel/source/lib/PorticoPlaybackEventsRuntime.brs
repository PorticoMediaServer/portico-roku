function PorticoPlaybackEventsTaskState() as object
    return {viewerScope: invalid, viewerGeneration: 0, operationSequence: 0, publicationSequence: 0, operationContract: invalid}
end function

sub PorticoPlaybackEventsTaskAdopt(target as object, state as object)
    for each key in state
        target[key] = state[key]
    end for
end sub

function PorticoPlaybackEventsAcceptCommand(controller as object, envelope as dynamic) as dynamic
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" or envelope.version <> 1 or LCase(PorticoCoreSafeIdentifier(envelope.domain, 64)) <> "playback-events" then return invalid
    scope = PorticoViewerScopeNormalize(envelope.viewerScope)
    generation = PorticoViewerScopePositiveInteger(envelope.viewerGeneration)
    sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    command = envelope.command
    if scope = invalid or generation <> scope.viewerGeneration or sequence < 1 or command = invalid or Type(command) <> "roAssociativeArray" then return invalid
    current = PorticoViewerScopeNormalize(controller.viewerScope)
    changed = current = invalid or not PorticoViewerScopeEquals(current, scope)
    if controller.viewerGeneration > 0
        if generation < controller.viewerGeneration then return invalid
        if generation = controller.viewerGeneration and changed then return invalid
        if generation = controller.viewerGeneration and sequence <= controller.operationSequence then return invalid
    end if
    loaded = PorticoOperationContractLoad()
    if not loaded.ok then return invalid
    controller.viewerScope = scope
    controller.viewerGeneration = generation
    controller.operationSequence = sequence
    controller.publicationSequence = 0
    controller.operationContract = loaded.value
    accepted = {}
    for each key in command
        accepted[key] = command[key]
    end for
    return accepted
end function

function PorticoPlaybackEventsSession(controller as object) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if scope = invalid or scope.viewerGeneration <> controller.viewerGeneration then return invalid
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid or record.payload.signedOut = true then return invalid
    stored = PorticoServerSessionStored(record.payload)
    if stored = invalid then return invalid
    actual = PorticoServerSessionScope(stored, scope.viewerGeneration)
    if actual = invalid or not PorticoViewerScopeEquals(actual, scope) then return invalid
    return PorticoServerSessionRequestProjection(stored, scope, record.generation)
end function

function PorticoPlaybackEventsSessionStillCurrent(controller as object, expected as object) as boolean
    current = PorticoPlaybackEventsSession(controller)
    return current <> invalid and expected <> invalid and current.registryGeneration = expected.registryGeneration
end function

function PorticoPlaybackEventsOperation(controller as object, operationId as string, inputs as object, expectedMethod as string, expectedPath as string) as object
    if controller.operationContract = invalid then return {ok: false, code: "operation-contract-unavailable"}
    resolved = PorticoOperationContractResolvePath(controller.operationContract, "server", operationId, inputs)
    if not resolved.ok then return resolved
    if resolved.method <> expectedMethod or resolved.path <> expectedPath then return {ok: false, code: "operation-contract-mismatch"}
    return resolved
end function

function PorticoPlaybackEventsResultEnvelope(controller as object, projection as object) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if scope = invalid or controller.operationSequence < 1 or controller.publicationSequence >= 2147483646 then return invalid
    controller.publicationSequence = controller.publicationSequence + 1
    return {version: 1, domain: "playback-events", viewerScope: scope, viewerGeneration: controller.viewerGeneration, operationSequence: controller.operationSequence, publicationSequence: controller.publicationSequence, projection: projection}
end function

function PorticoPlaybackEventsInterrupted(controller as object) as boolean
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return false
    if PorticoViewerScopePositiveInteger(envelope.viewerGeneration) <> controller.viewerGeneration then return true
    return PorticoViewerScopePositiveInteger(envelope.operationSequence) > controller.operationSequence
end function

function PorticoPlaybackEventsRequest(controller as object, operationId as string, inputs as object, expectedMethod as string, expectedPath as string, body as dynamic, query = "" as string, timeoutMs = 15000 as integer) as object
    session = PorticoPlaybackEventsSession(controller)
    if session = invalid then return PorticoPlaybackEventsFailure(0, false, "server-session-required", 0)
    operation = PorticoPlaybackEventsOperation(controller, operationId, inputs, expectedMethod, expectedPath)
    if not operation.ok then return PorticoPlaybackEventsFailure(0, false, operation.code, 0)
    request = PorticoHttpNormalizeRequest({method: operation.method, url: session.apiBaseUrl + "/api" + operation.path + query, body: body, headers: {Authorization: "Bearer " + session.accessToken}, timeoutMs: timeoutMs, expectJson: true, allowInsecureLan: session.allowInsecureLan = true})
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoPlaybackEventsFailure(0, false, validation.code, 0)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoPlaybackEventsFailure(0, true, "transport-error", 0)
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoPlaybackEventsFailure(0, true, "transport-error", 0)
    if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return PorticoPlaybackEventsFailure(0, true, "transport-error", 0)
    for each name in request.headers
        if not transfer.AddHeader(name, request.headers[name]) then return PorticoPlaybackEventsFailure(0, false, "invalid-header", 0)
    end for
    if request.method = "GET" then issued = transfer.AsyncGetToString() else issued = transfer.AsyncPostFromString(request.body)
    if not issued then return PorticoPlaybackEventsFailure(0, true, "transport-error", 0)
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoPlaybackEventsInterrupted(controller)
            transfer.AsyncCancel()
            return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "cancelled", retryAfterSeconds: 0}
        end if
        event = Wait(100, port)
        if event <> invalid and Type(event) = "roUrlEvent" and event.GetSourceIdentity() = identity
            if PorticoPlaybackEventsInterrupted(controller) or not PorticoPlaybackEventsSessionStillCurrent(controller, session) then return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "session-fenced", retryAfterSeconds: 0}
            status = event.GetResponseCode()
            headers = PorticoHttpResponseHeaders(event.GetResponseHeadersArray())
            retryAfter = 0
            if headers <> invalid then retryAfter = PorticoHttpInteger(headers["retry-after"], 0)
            classification = PorticoHttpClassifyStatus(status)
            if classification.classification <> "success" then return PorticoPlaybackEventsFailure(status, classification.retryable, classification.classification, retryAfter)
            payload = event.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoPlaybackEventsFailure(status, false, "response-too-large", 0)
            parsed = PorticoHttpParseJson(payload)
            if not parsed.ok then return PorticoPlaybackEventsFailure(status, false, "parse-error", 0)
            return {interrupted: false, ok: true, status: status, retryable: false, data: parsed.value, code: "", retryAfterSeconds: 0}
        end if
    end while
    transfer.AsyncCancel()
    return PorticoPlaybackEventsFailure(0, true, "timeout", 0)
end function

function PorticoPlaybackEventsFailure(status as integer, retryable as boolean, code as string, retryAfterSeconds as integer) as object
    return {interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: PorticoCoreSafeIdentifier(code, 80), retryAfterSeconds: retryAfterSeconds}
end function

function PorticoPlaybackEventsFailureCode(response as object) as string
    if response.status = 401 then return "authentication_required"
    if response.status = 403 then return "forbidden"
    if response.status = 404 then return "not_found"
    return PorticoCoreSafeIdentifier(response.code, 80)
end function

function PorticoPlaybackEventsPollQuery(request as object) as dynamic
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return invalid
    waitSeconds = PorticoHttpInteger(request.waitSeconds, 0)
    if waitSeconds < 0 then waitSeconds = 0
    if waitSeconds > 25 then waitSeconds = 25
    cursor = PorticoEventTransportOpaqueCursor(request.cursor)
    if PorticoCoreSafeText(request.cursor, 4096) <> "" and cursor = "" then return invalid
    query = "?waitSeconds=" + waitSeconds.ToStr()
    if cursor <> "" then query = query + "&cursor=" + transfer.Escape(cursor)
    return query
end function
