sub init()
    m.top.functionName = "PorticoPlaybackEventsRun"
end sub

sub PorticoPlaybackEventsRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    controller = {
        clock: clock,
        lastHandledSequence: 0,
        online: false,
        enabled: true,
        eventCapabilities: {},
        capabilitySignature: "bounded-refresh|20|25|4",
        mode: "none",
        transport: invalid,
        quarantinedResourceKey: "",
        longPollQuarantined: false,
        terminalBlocked: false,
        receiverId: "",
        receiverCode: "",
        activeSessionId: "",
        activePlaybackGeneration: 0,
        commandResourceKey: "",
        commandIds: [],
        nextRegisterAt: 0,
        nextHeartbeatAt: 0,
        resetRetryAt: 0,
        status: "idle",
        errorCode: "",
        directiveSequence: 0,
        directiveQueue: [],
        pendingDirective: invalid,
        resetAwaitingDirectiveToken: "",
        lastDirectivePublishAt: 0
    }
    PorticoPlaybackEventsTaskAdopt(controller, PorticoPlaybackEventsTaskState())
    while true
        PorticoPlaybackEventsHandleCommand(controller)
        PorticoPlaybackEventsTick(controller)
        Sleep(100)
    end while
end sub

sub PorticoPlaybackEventsHandleCommand(controller as object)
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return
    incomingSequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    if incomingSequence < 1 then return
    incomingScope = PorticoViewerScopeNormalize(envelope.viewerScope)
    if controller.viewerScope <> invalid and incomingScope <> invalid and not PorticoViewerScopeEquals(controller.viewerScope, incomingScope)
        PorticoPlaybackEventsFence(controller, "viewer-changed", true)
    end if
    command = PorticoPlaybackEventsAcceptCommand(controller, envelope)
    if command = invalid then return
    controller.lastHandledSequence = incomingSequence
    kind = LCase(PorticoCoreSafeIdentifier(command.kind, 80))
    if kind = "viewer-fence" or kind = "cancel"
        PorticoPlaybackEventsFence(controller, kind, true)
        PorticoPlaybackEventsPublish(controller)
    else if kind = "viewer-state"
        PorticoPlaybackEventsApplyViewerState(controller, command)
    else if kind = "capabilities"
        PorticoPlaybackEventsApplyCapabilities(controller, command.eventCapabilities)
    else if kind = "active-session"
        PorticoPlaybackEventsApplyActiveSession(controller, command)
    else if kind = "acknowledge-directive"
        PorticoPlaybackEventsAcknowledgePendingDirective(controller, command.ackToken)
    end if
end sub

sub PorticoPlaybackEventsApplyViewerState(controller as object, command as object)
    online = command.online = true
    enabled = command.enabled <> false
    capabilities = controller.eventCapabilities
    if command.eventCapabilities <> invalid and Type(command.eventCapabilities) = "roAssociativeArray" then capabilities = command.eventCapabilities
    capabilitySignature = PorticoPlaybackEventsTaskCapabilitySignature(capabilities)
    connectionChanged = online <> controller.online or enabled <> controller.enabled
    capabilityChanged = capabilitySignature <> controller.capabilitySignature
    changed = connectionChanged or capabilityChanged
    controller.online = online
    controller.enabled = enabled
    controller.eventCapabilities = capabilities
    controller.capabilitySignature = capabilitySignature
    if changed
        controller.terminalBlocked = false
        controller.quarantinedResourceKey = ""
        controller.longPollQuarantined = false
    end if
    if not online or not enabled
        PorticoPlaybackEventsCancelStream(controller, "inactive")
        PorticoPlaybackEventsClearReceiver(controller)
        if not online then controller.status = "offline" else controller.status = "idle"
        controller.errorCode = ""
        PorticoPlaybackEventsPublish(controller)
        return
    end if
    if connectionChanged
        PorticoPlaybackEventsSwitchToDesiredMode(controller)
    else if capabilityChanged
        PorticoPlaybackEventsRebuildTransport(controller, "capability-changed")
    end if
end sub

sub PorticoPlaybackEventsApplyCapabilities(controller as object, capabilities as dynamic)
    if capabilities = invalid or Type(capabilities) <> "roAssociativeArray" then capabilities = {}
    signature = PorticoPlaybackEventsTaskCapabilitySignature(capabilities)
    if signature = controller.capabilitySignature then return
    controller.eventCapabilities = capabilities
    controller.capabilitySignature = signature
    controller.terminalBlocked = false
    controller.quarantinedResourceKey = ""
    controller.longPollQuarantined = false
    if controller.online and controller.enabled then PorticoPlaybackEventsRebuildTransport(controller, "capability-changed")
end sub

sub PorticoPlaybackEventsApplyActiveSession(controller as object, command as object)
    active = command.active = true
    generation = PorticoViewerScopePositiveInteger(command.playbackGeneration)
    if active
        id = PorticoViewerScopeOpaqueId(command.sessionId, 128)
        if id = "" or generation < 1 then return
        if generation < controller.activePlaybackGeneration then return
        changed = id <> controller.activeSessionId or generation <> controller.activePlaybackGeneration
        controller.activeSessionId = id
        controller.activePlaybackGeneration = generation
        if changed and controller.online and controller.enabled then PorticoPlaybackEventsSwitchToDesiredMode(controller)
    else
        if generation < 1 or generation <> controller.activePlaybackGeneration then return
        controller.activeSessionId = ""
        controller.activePlaybackGeneration = 0
        if controller.online and controller.enabled then PorticoPlaybackEventsSwitchToDesiredMode(controller)
    end if
end sub

sub PorticoPlaybackEventsSwitchToDesiredMode(controller as object)
    desired = "receiver"
    if controller.activeSessionId <> "" and controller.activePlaybackGeneration > 0 then desired = "session"
    desiredResourceKey = "playback-receiver:" + controller.receiverId
    if desired = "session" then desiredResourceKey = "playback-commands:" + controller.activeSessionId
    resourceChanged = desiredResourceKey <> controller.commandResourceKey
    PorticoPlaybackEventsCancelStream(controller, "mode-switch")
    if resourceChanged
        controller.commandIds = []
        controller.commandResourceKey = desiredResourceKey
        controller.directiveQueue = []
        controller.pendingDirective = invalid
        controller.resetAwaitingDirectiveToken = ""
        controller.lastDirectivePublishAt = 0
    end if
    controller.terminalBlocked = false
    controller.resetRetryAt = 0
    if desired = "session"
        PorticoPlaybackEventsClearReceiver(controller)
        controller.mode = "session"
        controller.status = "active"
    else
        controller.mode = "receiver"
        controller.status = "registering"
        controller.nextRegisterAt = controller.clock.TotalSeconds()
    end if
    controller.errorCode = ""
    PorticoPlaybackEventsPublish(controller)
end sub

sub PorticoPlaybackEventsTick(controller as object)
    if not controller.online or not controller.enabled or controller.viewerScope = invalid then return
    now = controller.clock.TotalSeconds()
    if controller.directiveQueue.Count() > 0 and now >= controller.lastDirectivePublishAt + 2 then PorticoPlaybackEventsPublish(controller)
    if controller.terminalBlocked then return
    if controller.activeSessionId <> "" and controller.activePlaybackGeneration > 0
        if controller.mode <> "session" then PorticoPlaybackEventsSwitchToDesiredMode(controller)
        PorticoPlaybackEventsTickSession(controller)
    else
        if controller.mode <> "receiver" then PorticoPlaybackEventsSwitchToDesiredMode(controller)
        PorticoPlaybackEventsTickReceiver(controller)
    end if
end sub

sub PorticoPlaybackEventsTickReceiver(controller as object)
    now = controller.clock.TotalSeconds()
    if controller.receiverId = ""
        if now < controller.nextRegisterAt then return
        PorticoPlaybackEventsRegisterReceiver(controller)
        return
    end if
    if controller.transport = invalid then PorticoPlaybackEventsCreateTransport(controller, "playback-receiver", controller.receiverId)
    if controller.transport = invalid then return
    if controller.transport.resetPending
        if controller.resetAwaitingDirectiveToken <> "" then return
        if now >= controller.resetRetryAt then PorticoPlaybackEventsAuthoritativeReset(controller)
        return
    end if
    if controller.transport.mode = "long-poll" and now >= controller.nextHeartbeatAt
        if not PorticoPlaybackEventsHeartbeatReceiver(controller, invalid) then return
    end if
    PorticoPlaybackEventsPoll(controller)
end sub

sub PorticoPlaybackEventsTickSession(controller as object)
    if controller.transport = invalid then PorticoPlaybackEventsCreateTransport(controller, "playback-commands", controller.activeSessionId)
    if controller.transport = invalid then return
    if controller.transport.resetPending
        if controller.resetAwaitingDirectiveToken <> "" then return
        if controller.clock.TotalSeconds() >= controller.resetRetryAt then PorticoPlaybackEventsAuthoritativeReset(controller)
        return
    end if
    PorticoPlaybackEventsPoll(controller)
end sub

sub PorticoPlaybackEventsRegisterReceiver(controller as object)
    controller.status = "registering"
    PorticoPlaybackEventsPublish(controller)
    body = {name: "Portico on Roku", app: "Portico", platform: "Roku", supportedCommands: ["load"]}
    response = PorticoPlaybackEventsRequest(controller, "postPlaybackReceivers", {}, "POST", "/playback/receivers", body, "", 15000)
    if response.interrupted then return
    if not response.ok
        terminal = not response.retryable and response.status <> 401 and response.status <> 403
        if terminal then controller.terminalBlocked = true
        controller.nextRegisterAt = controller.clock.TotalSeconds() + PorticoPlaybackEventsRetryDelay(response)
        if terminal then controller.status = "error" else controller.status = "reconnecting"
        controller.errorCode = PorticoPlaybackEventsFailureCode(response)
        PorticoPlaybackEventsPublish(controller)
        return
    end if
    receiver = PorticoPlaybackEventsPrivateReceiver(response.data)
    if receiver = invalid
        controller.terminalBlocked = true
        controller.status = "error"
        controller.errorCode = "receiver-response-incompatible"
        PorticoPlaybackEventsPublish(controller)
        return
    end if
    controller.receiverId = receiver.id
    controller.receiverCode = receiver.code
    controller.commandIds = []
    controller.nextHeartbeatAt = controller.clock.TotalSeconds() + 30
    PorticoPlaybackEventsCreateTransport(controller, "playback-receiver", controller.receiverId)
    PorticoPlaybackEventsProcessPrivateCommand(controller, receiver.command, false)
    controller.status = "active"
    controller.errorCode = ""
    PorticoPlaybackEventsPublish(controller)
end sub

function PorticoPlaybackEventsHeartbeatReceiver(controller as object, request as dynamic) as boolean
    id = controller.receiverId
    if id = "" then return false
    encoded = PorticoEventTransportEscape(id)
    if encoded = "" then return false
    controller.nextHeartbeatAt = controller.clock.TotalSeconds() + 30
    response = PorticoPlaybackEventsRequest(controller, "patchPlaybackReceiversReceiverId", {receiverId: id}, "PATCH", "/playback/receivers/" + encoded, invalid, "", 15000)
    if response.interrupted
        if request <> invalid then PorticoEventTransportAbandonRequest(controller.transport, request, controller.viewerScope, controller.clock.TotalSeconds())
        return false
    end if
    if not response.ok
        if request <> invalid then PorticoPlaybackEventsRecordTransportFailure(controller, request, response)
        if response.status = 404
            PorticoPlaybackEventsCancelStream(controller, "receiver-expired")
            PorticoPlaybackEventsClearReceiver(controller)
            controller.nextRegisterAt = controller.clock.TotalSeconds() + 1
        end if
        if request = invalid
            controller.resetRetryAt = controller.clock.TotalSeconds() + PorticoPlaybackEventsRetryDelay(response)
            if response.status = 404
                controller.terminalBlocked = false
                controller.status = "registering"
            else if not response.retryable and response.status <> 401 and response.status <> 403
                controller.terminalBlocked = true
                controller.status = "error"
            else
                controller.status = "reconnecting"
            end if
            controller.errorCode = PorticoPlaybackEventsFailureCode(response)
            PorticoPlaybackEventsPublish(controller)
        end if
        return false
    end if
    receiver = PorticoPlaybackEventsPrivateReceiver(response.data, id)
    if receiver = invalid
        if request <> invalid then PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_response", 0, controller.clock.TotalSeconds())
        if request = invalid then controller.terminalBlocked = true
        controller.status = "error"
        controller.errorCode = "receiver-response-incompatible"
        controller.resetRetryAt = controller.clock.TotalSeconds() + 5
        PorticoPlaybackEventsPublish(controller)
        return false
    end if
    controller.nextHeartbeatAt = controller.clock.TotalSeconds() + 30
    if request <> invalid
        accepted = PorticoEventTransportAcceptResponse(controller.transport, request, response.data, controller.viewerScope, controller.clock.TotalSeconds())
        if not accepted.accepted then return false
    end if
    resetFlow = request = invalid and controller.transport <> invalid and controller.transport.resetPending
    result = PorticoPlaybackEventsProcessPrivateCommand(controller, receiver.command, resetFlow)
    if resetFlow then PorticoPlaybackEventsResolveResetCommand(controller, receiver.command, result)
    return true
end function

sub PorticoPlaybackEventsCreateTransport(controller as object, streamKind as string, resourceId as string)
    capabilities = {}
    resourceKey = streamKind + ":" + resourceId
    if resourceKey <> controller.quarantinedResourceKey and PorticoPlaybackEventsLongPollAllowed(controller, streamKind, resourceId) then capabilities = controller.eventCapabilities
    controller.transport = PorticoEventTransportCreate(controller.viewerScope, streamKind, resourceId, capabilities, controller.clock.TotalSeconds())
    if resourceKey <> controller.commandResourceKey
        controller.commandResourceKey = resourceKey
        controller.commandIds = []
    end if
end sub

function PorticoPlaybackEventsLongPollAllowed(controller as object, streamKind as string, resourceId as string) as boolean
    capabilities = PorticoEventTransportCapabilities(controller.eventCapabilities)
    if not capabilities.longPollAdvertised then return false
    encoded = PorticoEventTransportEscape(resourceId)
    if encoded = "" then return false
    if streamKind = "playback-receiver"
        operation = PorticoPlaybackEventsOperation(controller, "pollPlaybackReceiverEvents", {receiverId: resourceId}, "GET", "/playback/receivers/" + encoded + "/events/poll")
    else
        operation = PorticoPlaybackEventsOperation(controller, "pollPlaybackSessionCommands", {sessionId: resourceId}, "GET", "/playback-sessions/" + encoded + "/command/events/poll")
    end if
    return operation.ok
end function

sub PorticoPlaybackEventsPoll(controller as object)
    now = controller.clock.TotalSeconds()
    request = PorticoEventTransportBeginRequest(controller.transport, controller.viewerScope, now)
    if not request.ok then return
    if controller.transport.mode = "bounded-refresh"
        PorticoPlaybackEventsBoundedRefresh(controller, request)
        return
    end if
    query = PorticoPlaybackEventsPollQuery(request)
    if query = invalid
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_cursor", 0, now)
        return
    end if
    resourceId = controller.transport.resourceId
    encoded = PorticoEventTransportEscape(resourceId)
    if controller.mode = "receiver"
        operationId = "pollPlaybackReceiverEvents"
        inputs = {receiverId: resourceId}
        path = "/playback/receivers/" + encoded + "/events/poll"
    else
        operationId = "pollPlaybackSessionCommands"
        inputs = {sessionId: resourceId}
        path = "/playback-sessions/" + encoded + "/command/events/poll"
    end if
    response = PorticoPlaybackEventsRequest(controller, operationId, inputs, "GET", path, invalid, query, 30000)
    if response.interrupted
        PorticoEventTransportAbandonRequest(controller.transport, request, controller.viewerScope, controller.clock.TotalSeconds())
        return
    end if
    if not response.ok
        PorticoPlaybackEventsRecordTransportFailure(controller, request, response)
        return
    end if
    envelope = PorticoEventTransportEnvelope(response.data)
    if envelope = invalid
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_response", 0, controller.clock.TotalSeconds())
        PorticoPlaybackEventsQuarantineLongPoll(controller, "event-envelope-incompatible")
        controller.status = "reconnecting"
        controller.errorCode = "event-response-incompatible"
        PorticoPlaybackEventsPublish(controller)
        return
    end if
    if not PorticoPlaybackEventsValidateEvents(controller, envelope.events)
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_response", 0, controller.clock.TotalSeconds())
        PorticoPlaybackEventsQuarantineLongPoll(controller, "event-payload-incompatible")
        controller.status = "reconnecting"
        controller.errorCode = "event-response-incompatible"
        PorticoPlaybackEventsPublish(controller)
        return
    end if
    if not PorticoPlaybackEventsEventsFit(controller, envelope.events)
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "directive_queue_full", 2, controller.clock.TotalSeconds())
        return
    end if
    accepted = PorticoEventTransportAcceptResponse(controller.transport, request, response.data, controller.viewerScope, controller.clock.TotalSeconds())
    if not accepted.accepted then return
    if accepted.directive = "authoritative-refetch"
        PorticoPlaybackEventsAuthoritativeReset(controller)
        return
    end if
    PorticoPlaybackEventsProcessEvents(controller, envelope.events)
    controller.status = "active"
    controller.errorCode = ""
end sub

sub PorticoPlaybackEventsBoundedRefresh(controller as object, request as object)
    if controller.mode = "receiver"
        PorticoPlaybackEventsHeartbeatReceiver(controller, request)
        return
    end if
    id = controller.activeSessionId
    encoded = PorticoEventTransportEscape(id)
    response = PorticoPlaybackEventsRequest(controller, "getPlaybackSessionsSessionIdCommand", {sessionId: id}, "GET", "/playback-sessions/" + encoded + "/command", invalid, "", 15000)
    if response.interrupted
        PorticoEventTransportAbandonRequest(controller.transport, request, controller.viewerScope, controller.clock.TotalSeconds())
        return
    end if
    if not response.ok
        PorticoPlaybackEventsRecordTransportFailure(controller, request, response)
        return
    end if
    command = PorticoPlaybackEventsPrivateCommand(response.data, true, false)
    if command = invalid
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_response", 0, controller.clock.TotalSeconds())
        return
    end if
    accepted = PorticoEventTransportAcceptResponse(controller.transport, request, response.data, controller.viewerScope, controller.clock.TotalSeconds())
    if not accepted.accepted then return
    PorticoPlaybackEventsProcessPrivateCommand(controller, command, false)
end sub

sub PorticoPlaybackEventsAuthoritativeReset(controller as object)
    if controller.mode = "receiver"
        if PorticoPlaybackEventsHeartbeatReceiver(controller, invalid)
            if controller.resetAwaitingDirectiveToken = "" then controller.resetRetryAt = 0
        end if
        return
    end if
    id = controller.activeSessionId
    encoded = PorticoEventTransportEscape(id)
    response = PorticoPlaybackEventsRequest(controller, "getPlaybackSessionsSessionIdCommand", {sessionId: id}, "GET", "/playback-sessions/" + encoded + "/command", invalid, "", 15000)
    if response.interrupted then return
    if not response.ok
        failureCode = PorticoPlaybackEventsFailureCode(response)
        terminal = failureCode = "not_found" or failureCode = "authorization_revision_changed"
        if terminal
            controller.terminalBlocked = true
            PorticoPlaybackEventsCancelStream(controller, failureCode)
            controller.status = "error"
        else
            controller.resetRetryAt = controller.clock.TotalSeconds() + PorticoPlaybackEventsRetryDelay(response)
            controller.status = "reconnecting"
        end if
        controller.errorCode = failureCode
        PorticoPlaybackEventsPublish(controller)
        return
    end if
    command = PorticoPlaybackEventsPrivateCommand(response.data, true, false)
    if command = invalid
        PorticoPlaybackEventsQuarantineLongPoll(controller, "command-response-incompatible")
        controller.resetRetryAt = controller.clock.TotalSeconds() + 5
        controller.status = "reconnecting"
        controller.errorCode = "command-response-incompatible"
        PorticoPlaybackEventsPublish(controller)
        return
    end if
    result = PorticoPlaybackEventsProcessPrivateCommand(controller, command, true)
    PorticoPlaybackEventsResolveResetCommand(controller, command, result)
end sub

function PorticoPlaybackEventsValidateEvents(controller as object, events as object) as boolean
    for each eventValue in events
        if controller.mode = "receiver"
            receiver = PorticoPlaybackEventsPrivateReceiver(eventValue, controller.receiverId)
            if receiver = invalid then return false
            command = receiver.command
        else
            command = PorticoPlaybackEventsPrivateCommand(eventValue, false, false)
            if command = invalid then return false
        end if
    end for
    return true
end function

function PorticoPlaybackEventsEventsFit(controller as object, events as object) as boolean
    newIds = {}
    newCount = 0
    for each eventValue in events
        if controller.mode = "receiver"
            command = PorticoPlaybackEventsPrivateReceiver(eventValue, controller.receiverId).command
        else
            command = PorticoPlaybackEventsPrivateCommand(eventValue, false, false)
        end if
        if not command.empty and not PorticoPlaybackEventsCommandSeen(controller, command.id) and not PorticoPlaybackEventsCommandQueued(controller, command.id) and newIds[command.id] <> true
            newIds[command.id] = true
            newCount = newCount + 1
        end if
    end for
    return controller.directiveQueue.Count() + newCount <= 64
end function

sub PorticoPlaybackEventsProcessEvents(controller as object, events as object)
    for each eventValue in events
        if controller.mode = "receiver"
            receiver = PorticoPlaybackEventsPrivateReceiver(eventValue, controller.receiverId)
            PorticoPlaybackEventsProcessPrivateCommand(controller, receiver.command, false)
        else
            command = PorticoPlaybackEventsPrivateCommand(eventValue, false, false)
            PorticoPlaybackEventsProcessPrivateCommand(controller, command, false)
        end if
    end for
end sub

function PorticoPlaybackEventsProcessPrivateCommand(controller as object, command as dynamic, acknowledgeReset as boolean) as object
    if command = invalid or command.empty then return {queued: false, ackToken: ""}
    if PorticoPlaybackEventsCommandSeen(controller, command.id) or PorticoPlaybackEventsCommandQueued(controller, command.id) then return {queued: false, ackToken: ""}
    if controller.directiveQueue.Count() >= 64 then return {queued: false, ackToken: ""}
    if controller.directiveSequence >= 2147483646
        controller.terminalBlocked = true
        controller.status = "error"
        controller.errorCode = "directive-sequence-exhausted"
        PorticoPlaybackEventsPublish(controller)
        return {queued: false, ackToken: ""}
    end if
    controller.directiveSequence = controller.directiveSequence + 1
    directive = {version: 1, sequence: controller.directiveSequence, ackToken: "delivery-" + controller.viewerGeneration.ToStr() + "-" + controller.directiveSequence.ToStr(), kind: command.directive.kind}
    for each key in ["mediaId", "positionSeconds", "message"]
        if command.directive[key] <> invalid then directive[key] = command.directive[key]
    end for
    if controller.mode = "session" then directive.playbackGeneration = controller.activePlaybackGeneration
    entry = {commandId: command.id, directive: directive, acknowledgeReset: acknowledgeReset}
    controller.directiveQueue.Push(entry)
    if controller.directiveQueue.Count() = 1
        controller.pendingDirective = directive
        PorticoPlaybackEventsPublish(controller)
    end if
    return {queued: true, ackToken: directive.ackToken}
end function

sub PorticoPlaybackEventsAcknowledgePendingDirective(controller as object, tokenValue as dynamic)
    token = PorticoCoreSafeIdentifier(tokenValue, 80)
    if token = "" or controller.directiveQueue.Count() = 0 then return
    entry = controller.directiveQueue[0]
    if entry.directive.ackToken <> token then return
    PorticoPlaybackEventsRememberCommand(controller, entry.commandId)
    if entry.acknowledgeReset and controller.transport <> invalid
        PorticoEventTransportAcknowledgeReset(controller.transport, controller.viewerScope)
        controller.resetAwaitingDirectiveToken = ""
        controller.resetRetryAt = 0
    end if
    controller.directiveQueue.Shift()
    controller.pendingDirective = invalid
    if controller.directiveQueue.Count() > 0 then controller.pendingDirective = controller.directiveQueue[0].directive
    controller.lastDirectivePublishAt = 0
    PorticoPlaybackEventsPublish(controller)
end sub

function PorticoPlaybackEventsCommandQueued(controller as object, commandId as string) as boolean
    for each entry in controller.directiveQueue
        if entry.commandId = commandId then return true
    end for
    return false
end function

sub PorticoPlaybackEventsResolveResetCommand(controller as object, command as dynamic, result as object)
    if command = invalid then return
    if command.empty or PorticoPlaybackEventsCommandSeen(controller, command.id)
        PorticoEventTransportAcknowledgeReset(controller.transport, controller.viewerScope)
        controller.resetAwaitingDirectiveToken = ""
        controller.resetRetryAt = 0
        return
    end if
    token = result.ackToken
    if token = ""
        for each entry in controller.directiveQueue
            if entry.commandId = command.id
                entry.acknowledgeReset = true
                token = entry.directive.ackToken
            end if
        end for
    end if
    if token <> ""
        controller.resetAwaitingDirectiveToken = token
        controller.resetRetryAt = controller.clock.TotalSeconds() + 2
    else
        controller.resetRetryAt = controller.clock.TotalSeconds() + 2
    end if
end sub

sub PorticoPlaybackEventsRecordTransportFailure(controller as object, request as object, response as object)
    failureCode = PorticoPlaybackEventsFailureCode(response)
    failed = PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, failureCode, response.retryAfterSeconds, controller.clock.TotalSeconds())
    controller.errorCode = PorticoCoreSafeIdentifier(failureCode, 80)
    if failed.terminal
        controller.terminalBlocked = true
        controller.status = "error"
        if controller.mode = "receiver" and response.status = 404
            controller.terminalBlocked = false
            PorticoPlaybackEventsCancelStream(controller, "receiver-expired")
            PorticoPlaybackEventsClearReceiver(controller)
            controller.nextRegisterAt = controller.clock.TotalSeconds() + 1
            controller.status = "registering"
        end if
    else if not response.retryable and controller.transport <> invalid and controller.transport.mode = "long-poll"
        PorticoPlaybackEventsQuarantineLongPoll(controller, failureCode)
        controller.status = "reconnecting"
    else
        controller.status = "reconnecting"
    end if
    PorticoPlaybackEventsPublish(controller)
end sub

function PorticoPlaybackEventsRetryDelay(response as object) as integer
    delay = PorticoHttpInteger(response.retryAfterSeconds, 0)
    if delay < 1 then delay = 2
    if delay > 300 then delay = 300
    return delay
end function

sub PorticoPlaybackEventsCancelStream(controller as object, reason as string)
    if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, reason)
    controller.transport = invalid
end sub

sub PorticoPlaybackEventsRebuildTransport(controller as object, reason as string)
    if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, reason)
    controller.transport = invalid
    controller.resetRetryAt = 0
end sub

sub PorticoPlaybackEventsClearReceiver(controller as object)
    controller.receiverId = ""
    controller.receiverCode = ""
    controller.nextHeartbeatAt = 0
end sub

sub PorticoPlaybackEventsFence(controller as object, reason as string, clearSession as boolean)
    PorticoPlaybackEventsCancelStream(controller, reason)
    PorticoPlaybackEventsClearReceiver(controller)
    if clearSession
        controller.activeSessionId = ""
        controller.activePlaybackGeneration = 0
    end if
    controller.mode = "none"
    controller.online = false
    controller.commandResourceKey = ""
    controller.commandIds = []
    controller.status = "idle"
    controller.errorCode = ""
    controller.directiveQueue = []
    controller.pendingDirective = invalid
    controller.resetAwaitingDirectiveToken = ""
    controller.lastDirectivePublishAt = 0
end sub

sub PorticoPlaybackEventsPublish(controller as object)
    directive = controller.pendingDirective
    publishedSequence = controller.directiveSequence
    if directive <> invalid then publishedSequence = directive.sequence
    projection = {status: controller.status, mode: controller.mode, receiverReady: controller.receiverId <> "", directiveSequence: publishedSequence, directive: directive, errorCode: controller.errorCode}
    envelope = PorticoPlaybackEventsResultEnvelope(controller, projection)
    if envelope <> invalid then m.top.projectionEnvelope = envelope
    controller.lastDirectivePublishAt = controller.clock.TotalSeconds()
end sub

sub PorticoPlaybackEventsQuarantineLongPoll(controller as object, reason as string)
    if controller.transport = invalid or controller.transport.mode <> "long-poll" then return
    streamKind = controller.transport.streamKind
    resourceId = controller.transport.resourceId
    controller.quarantinedResourceKey = streamKind + ":" + resourceId
    controller.longPollQuarantined = true
    PorticoEventTransportCancel(controller.transport, reason)
    capabilities = PorticoEventTransportCapabilities({})
    capabilities.longPollAdvertised = false
    controller.transport = PorticoEventTransportCreate(controller.viewerScope, streamKind, resourceId, {}, controller.clock.TotalSeconds())
    controller.resetRetryAt = 0
end sub

function PorticoPlaybackEventsTaskCapabilitySignature(value as dynamic) as string
    normalized = PorticoEventTransportCapabilities(value)
    mode = "bounded-refresh"
    if normalized.longPollAdvertised then mode = "long-poll"
    return mode + "|" + normalized.defaultWaitSeconds.ToStr() + "|" + normalized.maximumWaitSeconds.ToStr() + "|" + normalized.maximumConcurrentStreams.ToStr()
end function
