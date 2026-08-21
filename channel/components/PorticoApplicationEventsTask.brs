sub init()
    m.top.functionName = "PorticoApplicationEventsRun"
end sub

sub PorticoApplicationEventsRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    controller = {
        clock: clock,
        serverStatus: "not-connected",
        status: "idle",
        transport: invalid,
        capabilities: {},
        capabilitiesLoaded: false,
        longPollQuarantined: false,
        lastEventId: 0,
        directiveSequence: 0,
        resetRetryAt: 0,
        nextBroadInvalidationAt: 0,
        nextCapabilitiesAt: 0,
        pendingResetToken: "",
        pendingResetSequence: 0,
        pendingBroadInvalidation: false
    }
    PorticoApplicationEventsTaskAdopt(controller, PorticoApplicationEventsTaskState())
    while true
        PorticoApplicationEventsHandleCommand(controller)
        PorticoApplicationEventsTick(controller)
        Sleep(100)
    end while
end sub

sub PorticoApplicationEventsHandleCommand(controller as object)
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return
    incoming = PorticoViewerScopeNormalize(envelope.viewerScope)
    if controller.envelopeMode and incoming <> invalid and not PorticoViewerScopeEquals(controller.viewerScope, incoming)
        PorticoApplicationEventsFence(controller, "viewer-changed")
    end if
    command = PorticoApplicationEventsAcceptCommand(controller, envelope)
    if command = invalid then return
    kind = LCase(PorticoCoreSafeIdentifier(command.kind, 80))
    if kind = "viewer-fence" or kind = "cancel"
        PorticoApplicationEventsFence(controller, kind)
        PorticoApplicationEventsPublish(controller, invalid)
    else if kind = "server-state"
        PorticoApplicationEventsServerState(controller, command)
    else if kind = "acknowledge-reset"
        PorticoApplicationEventsAcknowledgeResetCommand(controller, command)
    end if
end sub

sub PorticoApplicationEventsServerState(controller as object, command as object)
    status = LCase(PorticoCoreSafeText(command.serverStatus, 40))
    allowed = {online: true, connecting: true, offline: true, blocked: true, "identity-mismatch": true, incompatible: true, "permission-removed": true, "not-connected": true}
    if allowed[status] <> true then status = "not-connected"
    controller.serverStatus = status
    projectedCapabilities = PorticoApplicationEventsCapabilityProjection(command.eventCapabilities)
    if projectedCapabilities <> invalid
        controller.capabilities = projectedCapabilities
        controller.capabilitiesLoaded = true
    end if
    if status <> "online"
        if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, "server-unavailable")
        controller.transport = invalid
        controller.status = "offline"
        PorticoApplicationEventsPublish(controller, invalid)
        return
    end if
    PorticoApplicationEventsLoadCapabilities(controller)
    PorticoApplicationEventsReconcileTransport(controller)
    controller.status = "online"
    PorticoApplicationEventsPublish(controller, invalid)
end sub

sub PorticoApplicationEventsTick(controller as object)
    if controller.serverStatus <> "online" or controller.transport = invalid then return
    now = controller.clock.TotalSeconds()
    if controller.pendingBroadInvalidation and now >= controller.nextBroadInvalidationAt
        controller.pendingBroadInvalidation = false
        controller.nextBroadInvalidationAt = now + 30
        PorticoApplicationEventsPublishAll(controller)
        return
    end if
    if not controller.capabilitiesLoaded and now >= controller.nextCapabilitiesAt
        PorticoApplicationEventsLoadCapabilities(controller)
        PorticoApplicationEventsReconcileTransport(controller)
    end if
    if controller.transport.resetPending
        if now >= controller.resetRetryAt then PorticoApplicationEventsPublishReset(controller)
        return
    end if
    request = PorticoEventTransportBeginRequest(controller.transport, controller.viewerScope, now)
    if not request.ok then return
    if request.requestKind = "authoritative-refresh"
        PorticoApplicationEventsPublishAll(controller)
        PorticoEventTransportAcceptResponse(controller.transport, request, {}, controller.viewerScope, controller.clock.TotalSeconds())
        return
    end if
    query = PorticoApplicationEventsPollQuery(request)
    if query = invalid
        PorticoApplicationEventsQuarantineLongPoll(controller, request, "invalid_cursor")
        return
    end if
    response = PorticoApplicationEventsRequest(controller, "pollApplicationEvents", query, 35000)
    if response.interrupted
        PorticoEventTransportAbandonRequest(controller.transport, request, controller.viewerScope, controller.clock.TotalSeconds())
        return
    end if
    if not response.ok
        if response.code = "authorization_revision_changed"
            PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, PorticoApplicationEventsFailureCode(response), response.retryAfterSeconds, controller.clock.TotalSeconds())
            controller.status = "terminal"
            PorticoApplicationEventsPublish(controller, invalid)
        else if response.status = 401 or response.status = 403
            PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, response.code, response.retryAfterSeconds, controller.clock.TotalSeconds())
            controller.status = "backoff"
            PorticoApplicationEventsPublish(controller, invalid)
        else if response.status = 404 or not response.retryable
            PorticoApplicationEventsQuarantineLongPoll(controller, request, response.code)
        else
            PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, response.code, response.retryAfterSeconds, controller.clock.TotalSeconds())
            controller.status = "backoff"
            PorticoApplicationEventsPublish(controller, invalid)
        end if
        return
    end if
    prevalidatedEnvelope = PorticoEventTransportEnvelope(response.data)
    if prevalidatedEnvelope = invalid
        PorticoApplicationEventsQuarantineLongPoll(controller, request, "invalid_response")
        return
    end if
    directives = PorticoApplicationEventDirectives(prevalidatedEnvelope.events, controller.lastEventId)
    if not directives.ok
        PorticoApplicationEventsQuarantineLongPoll(controller, request, "invalid_event")
        return
    end if
    accepted = PorticoEventTransportAcceptResponse(controller.transport, request, response.data, controller.viewerScope, controller.clock.TotalSeconds())
    if not accepted.accepted then return
    if accepted.directive = "backoff"
        PorticoApplicationEventsQuarantineLongPoll(controller, invalid, accepted.code)
        return
    end if
    if accepted.directive = "authoritative-refetch"
        PorticoApplicationEventsPublishReset(controller)
        return
    end if
    controller.lastEventId = directives.lastEventId
    controller.status = "online"
    if directives.broadRequired then controller.pendingBroadInvalidation = true
    if controller.pendingBroadInvalidation and controller.clock.TotalSeconds() >= controller.nextBroadInvalidationAt
        controller.pendingBroadInvalidation = false
        controller.nextBroadInvalidationAt = controller.clock.TotalSeconds() + 30
        PorticoApplicationEventsPublishAll(controller)
        return
    end if
    if directives.domains.Count() > 0 then PorticoApplicationEventsPublishDirective(controller, directives.domains, directives.resourceIds)
end sub

sub PorticoApplicationEventsLoadCapabilities(controller as object)
    if controller.capabilitiesLoaded then return
    controller.nextCapabilitiesAt = controller.clock.TotalSeconds() + 30
    response = PorticoApplicationEventsRequest(controller, "getProductContract", "", 15000)
    if response.interrupted then return
    if response.ok and PorticoProductContractValidateLive(response.data).ok
        controller.capabilities = {eventTransports: response.data.eventTransports, longPoll: response.data.longPoll}
        controller.capabilitiesLoaded = true
        controller.nextCapabilitiesAt = 0
    end if
end sub

sub PorticoApplicationEventsReconcileTransport(controller as object)
    if controller.serverStatus <> "online" then return
    capabilities = PorticoEventTransportCapabilities(controller.capabilities)
    operation = PorticoApplicationEventsOperation(controller, "pollApplicationEvents")
    if not PorticoApplicationEventsPollOperationAllowed(operation) or controller.longPollQuarantined then capabilities.longPollAdvertised = false
    if controller.transport = invalid
        controller.transport = PorticoEventTransportCreate(controller.viewerScope, "shell", "", capabilities, controller.clock.TotalSeconds())
    else
        PorticoEventTransportReconcileCapabilities(controller.transport, capabilities, controller.viewerScope, controller.clock.TotalSeconds())
    end if
end sub

sub PorticoApplicationEventsQuarantineLongPoll(controller as object, request as dynamic, reason as dynamic)
    if controller.transport <> invalid and request <> invalid and controller.transport.outstanding
        PorticoEventTransportAbandonRequest(controller.transport, request, controller.viewerScope, controller.clock.TotalSeconds())
    end if
    if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, reason)
    controller.transport = invalid
    controller.longPollQuarantined = true
    controller.status = "backoff"
    PorticoApplicationEventsReconcileTransport(controller)
    PorticoApplicationEventsPublishAll(controller)
end sub

sub PorticoApplicationEventsPublishAll(controller as object)
    PorticoApplicationEventsPublishDirective(controller, PorticoApplicationEventsAllDomains(), [])
end sub

sub PorticoApplicationEventsPublishReset(controller as object)
    if controller.pendingResetToken = ""
        controller.directiveSequence = controller.directiveSequence + 1
        controller.pendingResetSequence = controller.directiveSequence
        controller.pendingResetToken = "reset-" + controller.viewerGeneration.ToStr() + "-" + controller.pendingResetSequence.ToStr()
    end if
    directive = {version: 1, kind: "reset-domains", sequence: controller.pendingResetSequence, domains: PorticoApplicationEventsAllDomains(), resourceIds: [], ackToken: controller.pendingResetToken}
    controller.resetRetryAt = controller.clock.TotalSeconds() + 5
    PorticoApplicationEventsPublish(controller, directive)
end sub

sub PorticoApplicationEventsAcknowledgeResetCommand(controller as object, command as object)
    token = PorticoCoreSafeIdentifier(command.ackToken, 80)
    if token = "" or token <> controller.pendingResetToken or controller.transport = invalid or not controller.transport.resetPending then return
    if not PorticoEventTransportAcknowledgeReset(controller.transport, controller.viewerScope) then return
    controller.pendingResetToken = ""
    controller.pendingResetSequence = 0
    controller.pendingBroadInvalidation = false
    controller.resetRetryAt = 0
    controller.lastEventId = 0
    controller.status = "online"
    PorticoApplicationEventsPublish(controller, invalid)
end sub

sub PorticoApplicationEventsPublishDirective(controller as object, domains as object, resourceIds as object)
    controller.directiveSequence = controller.directiveSequence + 1
    directive = {version: 1, kind: "invalidate-domains", sequence: controller.directiveSequence, domains: domains, resourceIds: resourceIds}
    PorticoApplicationEventsPublish(controller, directive)
end sub

sub PorticoApplicationEventsPublish(controller as object, directive as dynamic)
    mode = "bounded-refresh"
    if controller.transport <> invalid then mode = controller.transport.mode
    projection = {status: controller.status, mode: mode, directive: directive}
    envelope = PorticoApplicationEventsResultEnvelope(controller, projection)
    if envelope <> invalid then m.top.projectionEnvelope = envelope
end sub

sub PorticoApplicationEventsFence(controller as object, reason as string)
    if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, reason)
    controller.transport = invalid
    controller.capabilities = {}
    controller.capabilitiesLoaded = false
    controller.longPollQuarantined = false
    controller.lastEventId = 0
    controller.directiveSequence = 0
    controller.nextBroadInvalidationAt = 0
    controller.nextCapabilitiesAt = 0
    controller.pendingResetToken = ""
    controller.pendingResetSequence = 0
    controller.status = "idle"
end sub

function PorticoApplicationEventsPollQuery(request as object) as dynamic
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

function PorticoApplicationEventsRequest(controller as object, operationId as string, query as string, timeoutMs as integer) as object
    session = PorticoApplicationEventsSession(controller)
    if session = invalid then return PorticoApplicationEventsHttpFailure(0, false, "server_session_required", 0)
    operation = PorticoApplicationEventsOperation(controller, operationId)
    if not operation.ok then return PorticoApplicationEventsHttpFailure(0, false, operation.code, 0)
    if operationId = "pollApplicationEvents" and not PorticoApplicationEventsPollOperationAllowed(operation) then return PorticoApplicationEventsHttpFailure(0, false, "operation_not_allowed", 0)
    request = PorticoHttpNormalizeRequest({method: operation.method, url: session.apiBaseUrl + "/api" + operation.path + query, body: invalid, headers: {Authorization: "Bearer " + session.accessToken}, timeoutMs: timeoutMs, expectJson: true, allowInsecureLan: session.allowInsecureLan = true})
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoApplicationEventsHttpFailure(0, false, validation.code, 0)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoApplicationEventsHttpFailure(0, true, "transport_error", 0)
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoApplicationEventsHttpFailure(0, true, "transport_error", 0)
    if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return PorticoApplicationEventsHttpFailure(0, true, "transport_error", 0)
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return PorticoApplicationEventsHttpFailure(0, false, "invalid_header", 0)
    end for
    if not transfer.AsyncGetToString() then return PorticoApplicationEventsHttpFailure(0, true, "transport_error", 0)
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoApplicationEventsInterrupted(controller)
            transfer.AsyncCancel()
            return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "cancelled", retryAfterSeconds: 0}
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            currentSession = PorticoApplicationEventsSession(controller)
            if PorticoApplicationEventsInterrupted(controller) or currentSession = invalid or currentSession.registryGeneration <> session.registryGeneration then return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "session_fenced", retryAfterSeconds: 0}
            status = message.GetResponseCode()
            headers = PorticoHttpResponseHeaders(message.GetResponseHeadersArray())
            retryAfter = 0
            if headers <> invalid then retryAfter = PorticoHttpInteger(headers["retry-after"], 0)
            classification = PorticoHttpClassifyStatus(status)
            if classification.classification <> "success" then return PorticoApplicationEventsHttpFailure(status, classification.retryable, classification.classification, retryAfter)
            payload = message.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoApplicationEventsHttpFailure(status, false, "response_too_large", 0)
            parsed = PorticoHttpParseJson(payload)
            if not parsed.ok then return PorticoApplicationEventsHttpFailure(status, false, "parse_error", 0)
            return {interrupted: false, ok: true, status: status, retryable: false, data: parsed.value, code: "", retryAfterSeconds: 0}
        end if
    end while
    transfer.AsyncCancel()
    return PorticoApplicationEventsHttpFailure(0, true, "timeout", 0)
end function

function PorticoApplicationEventsHttpFailure(status as integer, retryable as boolean, code as string, retryAfterSeconds as integer) as object
    return {interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: code, retryAfterSeconds: retryAfterSeconds}
end function

function PorticoApplicationEventsFailureCode(response as object) as string
    if response.status = 401 then return "authentication_required"
    if response.status = 403 then return "forbidden"
    if response.status = 404 then return "not_found"
    return response.code
end function
