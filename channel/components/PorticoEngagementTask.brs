sub init()
    m.top.functionName = "PorticoEngagementRun"
end sub

sub PorticoEngagementRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    languageResult = PorticoProductLanguageLoad()
    language = invalid
    if languageResult.ok then language = languageResult.value
    controller = {
        clock: clock,
        language: language,
        lastCommandSequence: 0,
        serverStatus: "not-connected",
        notificationStatus: "idle",
        feedbackStatus: "idle",
        errorCode: "",
        notificationPage: invalid,
        feedbackCapabilities: invalid,
        feedbackReceipt: invalid,
        nextRefreshAt: 0,
        notificationTransport: invalid,
        eventCapabilities: {},
        eventCapabilitiesLoaded: false,
        resetRetryAt: 0,
        lastNotificationLoadSucceeded: false,
        lastNotificationResponse: invalid,
        notificationLongPollQuarantined: false
    }
    PorticoEngagementTaskAdopt(controller, PorticoEngagementTaskState())
    while true
        PorticoEngagementHandleCommand(controller)
        PorticoEngagementTick(controller)
        Sleep(250)
    end while
end sub

sub PorticoEngagementHandleCommand(controller as object)
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return
    incoming = PorticoViewerScopeNormalize(envelope.viewerScope)
    if controller.envelopeMode and incoming <> invalid and not PorticoViewerScopeEquals(controller.viewerScope, incoming)
        PorticoEngagementFence(controller)
    end if
    command = PorticoEngagementAcceptCommand(controller, envelope)
    if command = invalid then return
    kind = LCase(PorticoCoreSafeIdentifier(command.kind, 80))
    if kind = "viewer-fence" or kind = "cancel"
        PorticoEngagementFence(controller)
        PorticoEngagementPublish(controller)
    else if kind = "server-state"
        controller.eventCapabilities = {}
        if command.capabilities <> invalid and Type(command.capabilities) = "roAssociativeArray" then controller.eventCapabilities = command.capabilities
        controller.eventCapabilitiesLoaded = true
        PorticoEngagementServerState(controller, command)
    else if kind = "refresh" or kind = "refresh-notifications"
        PorticoEngagementLoadNotifications(controller, true)
        if kind = "refresh" then PorticoEngagementLoadFeedbackCapabilities(controller)
    else if kind = "dismiss-notification"
        PorticoEngagementDismissNotification(controller, command)
    else if kind = "submit-feedback"
        PorticoEngagementSubmitFeedback(controller, command)
    end if
end sub

sub PorticoEngagementServerState(controller as object, command as object)
    status = LCase(PorticoCoreSafeText(command.serverStatus, 40))
    allowed = {online: true, connecting: true, offline: true, blocked: true, "identity-mismatch": true, incompatible: true, "permission-removed": true, "not-connected": true}
    if allowed[status] <> true then status = "not-connected"
    controller.serverStatus = status
    if status <> "online"
        if controller.notificationTransport <> invalid then PorticoEventTransportCancel(controller.notificationTransport, "server-unavailable")
        controller.notificationTransport = invalid
        controller.eventCapabilitiesLoaded = false
        controller.eventCapabilities = {}
        controller.notificationLongPollQuarantined = false
        if controller.notificationPage = invalid then controller.notificationStatus = "offline"
        if controller.feedbackCapabilities = invalid then controller.feedbackStatus = "offline"
        controller.nextRefreshAt = 0
        PorticoEngagementPublish(controller)
        return
    end if
    PorticoEngagementLoadEventCapabilities(controller)
    PorticoEngagementLoadNotifications(controller, false)
    PorticoEngagementLoadFeedbackCapabilities(controller)
    PorticoEngagementReconcileNotificationTransport(controller)
end sub

sub PorticoEngagementTick(controller as object)
    if controller.serverStatus <> "online" or controller.notificationTransport = invalid then return
    now = controller.clock.TotalSeconds()
    if controller.notificationTransport.resetPending
        if now >= controller.resetRetryAt then PorticoEngagementNotificationAuthoritativeReset(controller)
        return
    end if
    request = PorticoEventTransportBeginRequest(controller.notificationTransport, controller.viewerScope, now)
    if not request.ok then return
    if request.requestKind = "authoritative-refresh"
        PorticoEngagementLoadNotifications(controller, false)
        if controller.lastNotificationLoadSucceeded
            PorticoEventTransportAcceptResponse(controller.notificationTransport, request, controller.notificationPage, controller.viewerScope, controller.clock.TotalSeconds())
        else
            PorticoEventTransportFailRequest(controller.notificationTransport, request, controller.viewerScope, "refresh_failed", 0, controller.clock.TotalSeconds())
        end if
        return
    end if
    query = PorticoEngagementPollQuery(request)
    if query = invalid
        PorticoEventTransportFailRequest(controller.notificationTransport, request, controller.viewerScope, "invalid_cursor", 0, controller.clock.TotalSeconds())
        return
    end if
    response = PorticoEngagementRequest(controller, "pollViewerNotificationInvalidations", {}, invalid, query, 35000)
    if response.interrupted
        PorticoEventTransportAbandonRequest(controller.notificationTransport, request, controller.viewerScope, controller.clock.TotalSeconds())
        return
    end if
    if not response.ok
        failureCode = PorticoEngagementTransportFailureCode(response)
        failed = PorticoEventTransportFailRequest(controller.notificationTransport, request, controller.viewerScope, PorticoEngagementTransportFailureCode(response), response.retryAfterSeconds, controller.clock.TotalSeconds())
        if failed.terminal = true
            controller.notificationStatus = "error"
            controller.errorCode = PorticoCoreSafeIdentifier(failureCode, 80)
            PorticoEngagementPublish(controller)
        else if not response.retryable
            PorticoEngagementQuarantineNotificationLongPoll(controller)
        end if
        return
    end if
    validatedEnvelope = PorticoEventTransportEnvelope(response.data)
    if validatedEnvelope = invalid or not PorticoEngagementInvalidationEventsValid(validatedEnvelope.events)
        PorticoEventTransportFailRequest(controller.notificationTransport, request, controller.viewerScope, "invalid_response", 0, controller.clock.TotalSeconds())
        PorticoEngagementQuarantineNotificationLongPoll(controller)
        return
    end if
    accepted = PorticoEventTransportAcceptResponse(controller.notificationTransport, request, response.data, controller.viewerScope, controller.clock.TotalSeconds())
    if not accepted.accepted then return
    if accepted.directive = "authoritative-refetch"
        PorticoEngagementNotificationAuthoritativeReset(controller)
        return
    end if
    if accepted.events.Count() > 0
        controller.notificationTransport.resetPending = true
        PorticoEngagementNotificationAuthoritativeReset(controller)
    end if
end sub

sub PorticoEngagementLoadEventCapabilities(controller as object)
    if controller.eventCapabilitiesLoaded then return
    response = PorticoEngagementRequest(controller, "getProductContract", {}, invalid, "")
    if response.interrupted then return
    if response.ok and PorticoProductContractValidateLive(response.data).ok
        controller.eventCapabilities = {eventTransports: response.data.eventTransports, longPoll: response.data.longPoll}
        controller.eventCapabilitiesLoaded = true
    end if
end sub

sub PorticoEngagementReconcileNotificationTransport(controller as object)
    if controller.serverStatus <> "online" then return
    capabilities = PorticoEventTransportCapabilities(controller.eventCapabilities)
    if controller.notificationLongPollQuarantined then capabilities.longPollAdvertised = false
    if not PorticoEngagementSupportsNotificationLongPoll(controller.operationContract) then capabilities.longPollAdvertised = false
    if controller.notificationTransport = invalid
        controller.notificationTransport = PorticoEventTransportCreate(controller.viewerScope, "notifications", "", capabilities, controller.clock.TotalSeconds())
        if controller.notificationTransport <> invalid and controller.notificationTransport.mode = "bounded-refresh" then controller.notificationTransport.nextAttemptAt = controller.clock.TotalSeconds() + controller.notificationTransport.refreshIntervalSeconds
    else
        PorticoEventTransportReconcileCapabilities(controller.notificationTransport, capabilities, controller.viewerScope, controller.clock.TotalSeconds())
    end if
end sub

sub PorticoEngagementNotificationAuthoritativeReset(controller as object)
    PorticoEngagementLoadNotifications(controller, false)
    if not controller.lastNotificationLoadSucceeded
        response = controller.lastNotificationResponse
        if response <> invalid and (response.status = 401 or response.status = 403 or response.code = "authorization_revision_changed")
            PorticoEventTransportCancel(controller.notificationTransport, PorticoEngagementTransportFailureCode(response))
            controller.notificationTransport = invalid
            controller.notificationStatus = "error"
            controller.errorCode = PorticoCoreSafeIdentifier(response.code, 80)
            PorticoEngagementPublish(controller)
            return
        end if
        if response <> invalid and response.status = 404
            PorticoEngagementQuarantineNotificationLongPoll(controller)
            controller.notificationStatus = "error"
            controller.errorCode = "notification-route-unavailable"
            PorticoEngagementPublish(controller)
            return
        end if
        controller.resetRetryAt = controller.clock.TotalSeconds() + 5
        return
    end if
    if not PorticoEventTransportAcknowledgeReset(controller.notificationTransport, controller.viewerScope) then return
    controller.resetRetryAt = 0
end sub

sub PorticoEngagementLoadNotifications(controller as object, explicitRefresh as boolean)
    controller.lastNotificationLoadSucceeded = false
    controller.lastNotificationResponse = invalid
    if controller.serverStatus <> "online" then return
    if controller.language = invalid
        controller.notificationStatus = "error"
        controller.errorCode = "product-language-unavailable"
        PorticoEngagementPublish(controller)
        return
    end if
    if controller.notificationPage = invalid then controller.notificationStatus = "loading" else controller.notificationStatus = "refreshing"
    if explicitRefresh then controller.errorCode = ""
    PorticoEngagementPublish(controller)
    response = PorticoEngagementRequest(controller, "listViewerNotifications", {}, invalid, "?audience=profile&limit=25&includeArchived=false")
    controller.lastNotificationResponse = response
    if response.interrupted then return
    controller.nextRefreshAt = controller.clock.TotalSeconds() + 30
    if not response.ok
        if controller.notificationPage = invalid then controller.notificationStatus = "error" else controller.notificationStatus = "stale"
        controller.errorCode = PorticoCoreSafeIdentifier(response.code, 80)
        PorticoEngagementPublish(controller)
        return
    end if
    page = PorticoEngagementNotificationPage(response.data, controller.viewerScope, controller.language)
    if page = invalid
        controller.notificationStatus = "error"
        controller.errorCode = "notification-response-incompatible"
        PorticoEngagementPublish(controller)
        return
    end if
    controller.notificationPage = page
    controller.lastNotificationLoadSucceeded = true
    controller.notificationStatus = "ready"
    controller.errorCode = ""
    PorticoEngagementPublish(controller)
end sub

sub PorticoEngagementLoadFeedbackCapabilities(controller as object)
    if controller.serverStatus <> "online" then return
    controller.feedbackStatus = "loading"
    PorticoEngagementPublish(controller)
    response = PorticoEngagementRequest(controller, "getViewerFeedbackCapabilities", {}, invalid, "")
    if response.interrupted then return
    if not response.ok
        controller.feedbackStatus = "error"
        controller.errorCode = PorticoCoreSafeIdentifier(response.code, 80)
        PorticoEngagementPublish(controller)
        return
    end if
    capabilities = PorticoEngagementFeedbackCapabilities(response.data)
    if capabilities = invalid
        controller.feedbackStatus = "error"
        controller.errorCode = "feedback-capabilities-incompatible"
        PorticoEngagementPublish(controller)
        return
    end if
    controller.feedbackCapabilities = capabilities
    controller.feedbackStatus = "ready"
    controller.errorCode = ""
    PorticoEngagementPublish(controller)
end sub

sub PorticoEngagementDismissNotification(controller as object, command as object)
    if controller.serverStatus <> "online" or controller.notificationPage = invalid then return
    id = PorticoViewerScopeOpaqueId(command.notificationId, 128)
    expectedRevision = PorticoEngagementInteger(command.expectedRevision, -1)
    if id = "" or expectedRevision <> controller.notificationPage.revision then return
    body = {version: "v1", recipient: controller.notificationPage.recipient, notificationIds: [id], action: "mark-read", expectedRevision: expectedRevision}
    controller.notificationStatus = "saving"
    PorticoEngagementPublish(controller)
    response = PorticoEngagementRequest(controller, "updateViewerNotificationReceipts", {}, body, "?audience=profile")
    if response.interrupted then return
    if response.status = 409
        controller.errorCode = "notification-revision-conflict"
        PorticoEngagementLoadNotifications(controller, true)
        return
    end if
    if not response.ok
        controller.notificationStatus = "error"
        controller.errorCode = PorticoCoreSafeIdentifier(response.code, 80)
        PorticoEngagementPublish(controller)
        return
    end if
    PorticoEngagementLoadNotifications(controller, false)
end sub

sub PorticoEngagementSubmitFeedback(controller as object, command as object)
    if controller.serverStatus <> "online" then return
    body = PorticoEngagementFeedbackSubmission(command, controller.feedbackCapabilities, PorticoEngagementAppVersion())
    if body = invalid
        controller.feedbackStatus = "error"
        controller.errorCode = "feedback-selection-invalid"
        PorticoEngagementPublish(controller)
        return
    end if
    controller.feedbackStatus = "sending"
    controller.feedbackReceipt = invalid
    PorticoEngagementPublish(controller)
    response = PorticoEngagementRequest(controller, "submitViewerFeedback", {}, body, "")
    if response.interrupted then return
    if not response.ok
        controller.feedbackStatus = "error"
        controller.errorCode = PorticoCoreSafeIdentifier(response.code, 80)
        PorticoEngagementPublish(controller)
        return
    end if
    receipt = PorticoEngagementFeedbackReceipt(response.data)
    if receipt = invalid
        controller.feedbackStatus = "error"
        controller.errorCode = "feedback-receipt-incompatible"
        PorticoEngagementPublish(controller)
        return
    end if
    controller.feedbackReceipt = receipt
    controller.feedbackStatus = "sent"
    controller.errorCode = ""
    PorticoEngagementPublish(controller)
end sub

function PorticoEngagementRequest(controller as object, operationId as string, inputs as object, body as dynamic, query as string, timeoutMs = 15000 as integer) as object
    session = PorticoEngagementSession(controller)
    if session = invalid then return PorticoEngagementFailure(0, false, "server-session-required")
    operation = PorticoEngagementOperation(controller, operationId, inputs)
    if not operation.ok then return PorticoEngagementFailure(0, false, operation.code)
    request = PorticoHttpNormalizeRequest({method: operation.method, url: session.apiBaseUrl + "/api" + operation.path + query, body: body, headers: {Authorization: "Bearer " + session.accessToken}, timeoutMs: timeoutMs, expectJson: true, allowInsecureLan: session.allowInsecureLan = true})
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoEngagementFailure(0, false, validation.code)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoEngagementFailure(0, true, "transport-error")
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoEngagementFailure(0, true, "transport-error")
    if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return PorticoEngagementFailure(0, true, "transport-error")
    for each name in request.headers
        if not transfer.AddHeader(name, request.headers[name]) then return PorticoEngagementFailure(0, false, "invalid-header")
    end for
    if request.method = "GET" then issued = transfer.AsyncGetToString() else issued = transfer.AsyncPostFromString(request.body)
    if not issued then return PorticoEngagementFailure(0, true, "transport-error")
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoEngagementInterrupted(controller)
            transfer.AsyncCancel()
            return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "cancelled"}
        end if
        event = Wait(100, port)
        if event <> invalid and Type(event) = "roUrlEvent" and event.GetSourceIdentity() = identity
            currentSession = PorticoEngagementSession(controller)
            if PorticoEngagementInterrupted(controller) or currentSession = invalid or currentSession.registryGeneration <> session.registryGeneration then return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "session-fenced"}
            status = event.GetResponseCode()
            headers = PorticoHttpResponseHeaders(event.GetResponseHeadersArray())
            retryAfter = 0
            if headers <> invalid then retryAfter = PorticoHttpInteger(headers["retry-after"], 0)
            classification = PorticoHttpClassifyStatus(status)
            if classification.classification <> "success" then return PorticoEngagementFailure(status, classification.retryable, classification.classification, retryAfter)
            payload = event.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoEngagementFailure(status, false, "response-too-large")
            parsed = PorticoHttpParseJson(payload)
            if not parsed.ok then return PorticoEngagementFailure(status, false, "parse-error")
            return {interrupted: false, ok: true, status: status, retryable: false, data: parsed.value, code: ""}
        end if
    end while
    transfer.AsyncCancel()
    return PorticoEngagementFailure(0, true, "timeout")
end function

function PorticoEngagementFailure(status as integer, retryable as boolean, code as string, retryAfterSeconds = 0 as integer) as object
    return {interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: code, retryAfterSeconds: retryAfterSeconds}
end function

function PorticoEngagementAppVersion() as string
    app = CreateObject("roAppInfo")
    if app = invalid then return "0.0.0"
    major = PorticoCoreSafeText(app.GetValue("major_version"), 12)
    minor = PorticoCoreSafeText(app.GetValue("minor_version"), 12)
    build = PorticoCoreSafeText(app.GetValue("build_version"), 12)
    if major = "" or minor = "" or build = "" then return "0.0.0"
    return major + "." + minor + "." + build
end function

sub PorticoEngagementFence(controller as object)
    if controller.notificationTransport <> invalid then PorticoEventTransportCancel(controller.notificationTransport, "viewer-fence")
    controller.notificationTransport = invalid
    controller.eventCapabilities = {}
    controller.eventCapabilitiesLoaded = false
    controller.notificationLongPollQuarantined = false
    controller.notificationStatus = "idle"
    controller.feedbackStatus = "idle"
    controller.errorCode = ""
    controller.notificationPage = invalid
    controller.feedbackCapabilities = invalid
    controller.feedbackReceipt = invalid
    controller.nextRefreshAt = 0
end sub

sub PorticoEngagementQuarantineNotificationLongPoll(controller as object)
    controller.notificationLongPollQuarantined = true
    if controller.notificationTransport <> invalid then PorticoEventTransportCancel(controller.notificationTransport, "protocol-incompatible")
    controller.notificationTransport = PorticoEventTransportCreate(controller.viewerScope, "notifications", "", {}, controller.clock.TotalSeconds() + 5)
end sub

function PorticoEngagementPollQuery(request as object) as dynamic
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

function PorticoEngagementInvalidationEventsValid(events as dynamic) as boolean
    if events = invalid or GetInterface(events, "ifArray") = invalid or events.Count() > 100 then return false
    for each eventValue in events
        if eventValue = invalid or Type(eventValue) <> "roAssociativeArray" or eventValue.Count() <> 3 then return false
        if eventValue.version <> "v1" or eventValue.kind <> "notifications.invalidated" then return false
        if PorticoEventTransportServerTime(eventValue.occurredAt) = "" then return false
    end for
    return true
end function

function PorticoEngagementTransportFailureCode(response as object) as string
    if response.status = 401 then return "authentication_required"
    if response.status = 403 then return "forbidden"
    if response.status = 404 then return "operation_not_found"
    return response.code
end function

sub PorticoEngagementPublish(controller as object)
    projection = {
        notificationStatus: controller.notificationStatus,
        feedbackStatus: controller.feedbackStatus,
        errorCode: controller.errorCode,
        unreadCount: 0,
        importantNotice: invalid,
        feedbackCapabilities: controller.feedbackCapabilities,
        feedbackReceipt: controller.feedbackReceipt
    }
    if controller.notificationPage <> invalid
        projection.unreadCount = controller.notificationPage.unreadCount
        projection.notificationRevision = controller.notificationPage.revision
        projection.importantNotice = controller.notificationPage.important
    end if
    envelope = PorticoEngagementResultEnvelope(controller, projection)
    if envelope <> invalid then m.top.projectionEnvelope = envelope
end sub
