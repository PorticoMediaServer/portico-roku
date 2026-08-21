function PorticoPlaybackEventsController(port as object, viewerController as object) as object
    controller = {task: invalid, port: port, viewerController: viewerController, stateSignature: "", activeSessionId: "", activePlaybackGeneration: 0, taskFenced: true, pendingAckToken: ""}
    PorticoPlaybackEventsStartTask(controller)
    return controller
end function

function PorticoPlaybackEventsStartTask(controller as object) as boolean
    if controller = invalid or controller.port = invalid then return false
    if controller.task <> invalid then return true
    task = CreateObject("roSGNode", "PorticoPlaybackEventsTask")
    if task = invalid then return false
    task.ObserveField("projectionEnvelope", controller.port)
    task.control = "RUN"
    controller.task = task
    controller.taskFenced = false
    return true
end function

function PorticoPlaybackEventsSend(controller as object, values as object) as boolean
    if controller = invalid or controller.viewerController = invalid or not PorticoViewerRuntimeAccepting(controller.viewerController.runtime) then return false
    if not PorticoPlaybackEventsStartTask(controller) then return false
    envelope = PorticoViewerRuntimeControllerCommand(controller.viewerController, "playback-events", values)
    if envelope = invalid then return false
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoPlaybackEventsViewerStateChanged(controller as object, state as dynamic, eventCapabilities = invalid as dynamic) as boolean
    if controller = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    scope = PorticoViewerRuntimeControllerCurrentScope(controller.viewerController)
    if scope = invalid or PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    status = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    capabilities = PorticoPlaybackEventsCapabilityProjection(eventCapabilities)
    signature = scope.serverId + "|" + scope.viewerGeneration.ToStr() + "|" + status + "|" + PorticoPlaybackEventsCapabilitySignature(capabilities)
    if signature = controller.stateSignature then return true
    command = {kind: "viewer-state", online: status = "online", enabled: true, eventCapabilities: capabilities}
    issued = PorticoPlaybackEventsSend(controller, command)
    if issued
        controller.stateSignature = signature
        controller.taskFenced = false
    end if
    return issued
end function

function PorticoPlaybackEventsSetCapabilities(controller as object, eventCapabilities as dynamic) as boolean
    capabilities = PorticoPlaybackEventsCapabilityProjection(eventCapabilities)
    return PorticoPlaybackEventsSend(controller, {kind: "capabilities", eventCapabilities: capabilities})
end function

function PorticoPlaybackEventsSetActiveSession(controller as object, sessionId as dynamic, playbackGeneration as dynamic) as boolean
    id = PorticoViewerScopeOpaqueId(sessionId, 128)
    generation = PorticoViewerScopePositiveInteger(playbackGeneration)
    if id = "" or generation < 1 then return false
    if id = controller.activeSessionId and generation = controller.activePlaybackGeneration then return true
    issued = PorticoPlaybackEventsSend(controller, {kind: "active-session", active: true, sessionId: id, playbackGeneration: generation})
    if issued
        controller.activeSessionId = id
        controller.activePlaybackGeneration = generation
    end if
    return issued
end function

function PorticoPlaybackEventsClearActiveSession(controller as object, playbackGeneration as dynamic) as boolean
    generation = PorticoViewerScopePositiveInteger(playbackGeneration)
    if generation < 1 or generation <> controller.activePlaybackGeneration then return false
    issued = PorticoPlaybackEventsSend(controller, {kind: "active-session", active: false, playbackGeneration: generation})
    if issued
        controller.activeSessionId = ""
        controller.activePlaybackGeneration = 0
    end if
    return issued
end function

function PorticoPlaybackEventsAcknowledgeDirective(controller as object, ackToken as dynamic) as boolean
    token = PorticoCoreSafeIdentifier(ackToken, 80)
    if token = "" then return false
    ' Routing succeeded before Main calls this API. Retain the local token even
    ' if the single-field Task mailbox is overwritten; repeated projections
    ' retry only the acknowledgement and never dispatch the action twice.
    controller.pendingAckToken = token
    return PorticoPlaybackEventsSend(controller, {kind: "acknowledge-directive", ackToken: token})
end function

function PorticoPlaybackEventsCancel(controller as object) as boolean
    if controller = invalid then return false
    controller.stateSignature = ""
    controller.activeSessionId = ""
    controller.activePlaybackGeneration = 0
    controller.pendingAckToken = ""
    if controller.task = invalid
        controller.taskFenced = true
        return true
    end if
    if controller.viewerController = invalid or not PorticoViewerRuntimeAccepting(controller.viewerController.runtime)
        controller.task.control = "STOP"
        controller.task = invalid
        controller.taskFenced = true
        return true
    end if
    issued = PorticoPlaybackEventsSend(controller, {kind: "cancel"})
    if issued then controller.taskFenced = true
    return issued
end function

function PorticoPlaybackEventsHandleNodeEvent(controller as object, event as object) as object
    empty = {handled: false, projection: invalid, directive: invalid}
    if controller = invalid or controller.task = invalid or event.GetField() <> "projectionEnvelope" then return empty
    source = event.GetRoSGNode()
    if source = invalid or not source.IsSameNode(controller.task) then return empty
    if controller.taskFenced then return {handled: true, projection: invalid, directive: invalid}
    envelope = event.GetData()
    accepted = PorticoViewerRuntimeAcceptProjection(controller.viewerController.runtime, envelope)
    if not accepted.accepted then return {handled: true, projection: invalid, directive: invalid}
    projection = PorticoPlaybackEventsProjection(envelope.projection)
    if projection = invalid then return {handled: true, projection: invalid, directive: invalid}
    directive = projection.directive
    if directive <> invalid
        if controller.pendingAckToken = directive.ackToken
            PorticoPlaybackEventsSend(controller, {kind: "acknowledge-directive", ackToken: directive.ackToken})
            directive = invalid
        else if controller.pendingAckToken <> ""
            controller.pendingAckToken = ""
        end if
    else if controller.pendingAckToken <> ""
        controller.pendingAckToken = ""
    end if
    return {handled: true, projection: projection, directive: directive}
end function

function PorticoPlaybackEventsProjection(value as dynamic) as dynamic
    allowed = {status: true, mode: true, receiverReady: true, directiveSequence: true, directive: true, errorCode: true}
    if value = invalid or Type(value) <> "roAssociativeArray" or value.Count() <> 6 then return invalid
    for each key in value
        if allowed[key] <> true then return invalid
    end for
    status = LCase(PorticoCoreSafeIdentifier(value.status, 24))
    mode = LCase(PorticoCoreSafeIdentifier(value.mode, 16))
    statuses = {idle: true, registering: true, active: true, reconnecting: true, offline: true, error: true}
    modes = {none: true, receiver: true, session: true}
    if statuses[status] <> true or modes[mode] <> true then return invalid
    if Type(value.receiverReady) <> "roBoolean" and Type(value.receiverReady) <> "Boolean" then return invalid
    sequence = PorticoPlaybackEventsSafeNonNegative(value.directiveSequence)
    if sequence = invalid then return invalid
    directive = invalid
    if value.directive <> invalid
        directive = PorticoPlaybackEventsDirective(value.directive, mode)
        if directive = invalid or directive.sequence <> sequence then return invalid
    end if
    return {status: status, mode: mode, receiverReady: value.receiverReady, directiveSequence: sequence, directive: directive, errorCode: PorticoCoreSafeIdentifier(value.errorCode, 80)}
end function

function PorticoPlaybackEventsDirective(value as dynamic, mode as string) as dynamic
    allowed = {version: true, sequence: true, ackToken: true, kind: true, mediaId: true, positionSeconds: true, message: true, playbackGeneration: true}
    if value = invalid or Type(value) <> "roAssociativeArray" or value.Count() < 4 or value.Count() > 8 then return invalid
    for each key in value
        if allowed[key] <> true then return invalid
    end for
    if value.version <> 1 then return invalid
    sequence = PorticoViewerScopePositiveInteger(value.sequence)
    token = PorticoCoreSafeIdentifier(value.ackToken, 80)
    kind = LCase(PorticoCoreSafeIdentifier(value.kind, 16))
    actions = {play: true, pause: true, seek: true, stop: true, load: true, next: true, previous: true}
    if sequence < 1 or token = "" or actions[kind] <> true then return invalid
    if mode = "receiver" and kind <> "load" then return invalid
    if mode = "session" and PorticoViewerScopePositiveInteger(value.playbackGeneration) < 1 then return invalid
    mediaId = PorticoViewerScopeOpaqueId(value.mediaId, 128)
    if kind = "load" and mediaId = "" then return invalid
    position = invalid
    if value.positionSeconds <> invalid
        position = PorticoPlaybackEventsSafeNonNegative(value.positionSeconds)
        if position = invalid then return invalid
    end if
    if kind = "seek" and position = invalid then return invalid
    result = {version: 1, sequence: sequence, ackToken: token, kind: kind}
    if mediaId <> "" then result.mediaId = mediaId
    if position <> invalid then result.positionSeconds = position
    if value.message <> invalid
        if kind <> "stop" then return invalid
        result.message = PorticoCoreSafeText(value.message, 500)
    end if
    if mode = "session" then result.playbackGeneration = PorticoViewerScopePositiveInteger(value.playbackGeneration)
    return result
end function

function PorticoPlaybackEventsCapabilityProjection(value as dynamic) as object
    normalized = PorticoEventTransportCapabilities(value)
    transports = []
    if normalized.longPollAdvertised then transports.Push("long-poll")
    return {eventTransports: transports, longPoll: {defaultWaitSeconds: normalized.defaultWaitSeconds, maximumWaitSeconds: normalized.maximumWaitSeconds, maximumConcurrentStreams: normalized.maximumConcurrentStreams}}
end function

function PorticoPlaybackEventsCapabilitySignature(value as object) as string
    normalized = PorticoEventTransportCapabilities(value)
    mode = "bounded-refresh"
    if normalized.longPollAdvertised then mode = "long-poll"
    return mode + "|" + normalized.defaultWaitSeconds.ToStr() + "|" + normalized.maximumWaitSeconds.ToStr() + "|" + normalized.maximumConcurrentStreams.ToStr()
end function

function PorticoPlaybackEventsSafeNonNegative(value as dynamic) as dynamic
    kind = LCase(Type(value))
    if kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" then return invalid
    result = Int(value)
    if result < 0 or result >= 2147480000 then return invalid
    return result
end function
