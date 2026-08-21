function PorticoApplicationEventsController(port as object, viewerController as object) as object
    task = CreateObject("roSGNode", "PorticoApplicationEventsTask")
    if task = invalid then return {task: invalid, port: port, viewerController: viewerController, projection: invalid, stateSignature: "", taskFenced: true}
    task.ObserveField("projectionEnvelope", port)
    task.control = "RUN"
    return {task: task, port: port, viewerController: viewerController, projection: invalid, stateSignature: "", taskFenced: false}
end function

function PorticoApplicationEventsStartTask(controller as object) as boolean
    if controller = invalid or controller.port = invalid then return false
    if controller.task <> invalid then return true
    task = CreateObject("roSGNode", "PorticoApplicationEventsTask")
    if task = invalid then return false
    task.ObserveField("projectionEnvelope", controller.port)
    task.control = "RUN"
    controller.task = task
    controller.taskFenced = false
    return true
end function

function PorticoApplicationEventsViewerCommand(controller as object, values as object) as boolean
    if controller = invalid or controller.task = invalid or controller.viewerController = invalid then return false
    envelope = PorticoViewerRuntimeControllerCommand(controller.viewerController, "application-events", values)
    if envelope = invalid then return false
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoApplicationEventsViewerStateChanged(controller as object, state as dynamic) as boolean
    if controller = invalid or controller.viewerController = invalid or not PorticoViewerRuntimeAccepting(controller.viewerController.runtime) then return false
    if not PorticoApplicationEventsStartTask(controller) then return false
    scope = PorticoViewerRuntimeControllerCurrentScope(controller.viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    serverStatus = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    command = {kind: "server-state", serverStatus: serverStatus}
    capabilities = PorticoApplicationEventsCapabilityProjection(state.eventCapabilities)
    if capabilities <> invalid then command.eventCapabilities = capabilities
    capabilitySignature = "none"
    if capabilities <> invalid
        capabilitySignature = ""
        for each transport in capabilities.eventTransports
            capabilitySignature = capabilitySignature + transport + ","
        end for
        capabilitySignature = capabilitySignature + "|20|25|4"
    end if
    revision = PorticoViewerScopeOpaqueId(state.productContractRevision, 128)
    signature = scope.serverId + "|" + scope.viewerGeneration.ToStr() + "|" + serverStatus + "|" + revision + "|" + capabilitySignature
    if signature = controller.stateSignature then return true
    issued = PorticoApplicationEventsViewerCommand(controller, command)
    if issued then controller.stateSignature = signature
    return issued
end function

function PorticoApplicationEventsAcknowledgeReset(controller as object, ackToken as dynamic) as boolean
    token = PorticoCoreSafeIdentifier(ackToken, 80)
    if token = "" then return false
    return PorticoApplicationEventsViewerCommand(controller, {kind: "acknowledge-reset", ackToken: token})
end function

function PorticoApplicationEventsTransitionFence(controller as object) as boolean
    if controller = invalid then return false
    controller.projection = invalid
    controller.stateSignature = ""
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
    return PorticoApplicationEventsViewerCommand(controller, {kind: "viewer-fence"})
end function

function PorticoApplicationEventsHandleNodeEvent(controller as object, event as object) as object
    if controller = invalid or controller.task = invalid or event.GetField() <> "projectionEnvelope" then return {handled: false, projection: invalid, directive: invalid}
    source = event.GetRoSGNode()
    if source = invalid or not source.IsSameNode(controller.task) then return {handled: false, projection: invalid, directive: invalid}
    envelope = event.GetData()
    accepted = PorticoViewerRuntimeAcceptProjection(controller.viewerController.runtime, envelope)
    if not accepted.accepted then return {handled: true, projection: invalid, directive: invalid}
    projection = PorticoApplicationEventsProjection(envelope.projection)
    if projection = invalid then return {handled: true, projection: invalid, directive: invalid}
    controller.projection = projection
    return {handled: true, projection: projection, directive: projection.directive}
end function

function PorticoApplicationEventsProjection(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.Count() <> 3 then return invalid
    status = LCase(PorticoCoreSafeIdentifier(value.status, 24))
    mode = LCase(PorticoCoreSafeIdentifier(value.mode, 24))
    statuses = {idle: true, online: true, offline: true, backoff: true, terminal: true}
    modes = {"long-poll": true, "bounded-refresh": true}
    if statuses[status] <> true or modes[mode] <> true then return invalid
    directive = invalid
    if value.directive <> invalid
        directive = PorticoApplicationEventsDirective(value.directive)
        if directive = invalid then return invalid
    end if
    return {status: status, mode: mode, directive: directive}
end function

function PorticoApplicationEventsDirective(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    kind = PorticoCoreSafeIdentifier(value.kind, 24)
    if value.version <> 1 or (kind <> "invalidate-domains" and kind <> "reset-domains") then return invalid
    if kind = "invalidate-domains" and value.Count() <> 5 then return invalid
    if kind = "reset-domains" and value.Count() <> 6 then return invalid
    sequence = PorticoViewerScopePositiveInteger(value.sequence)
    if sequence < 1 then return invalid
    if value.domains = invalid or GetInterface(value.domains, "ifArray") = invalid or value.domains.Count() < 1 or value.domains.Count() > 9 then return invalid
    allowed = {home: true, detail: true, search: true, library: true, saved: true, channels: true, settings: true, profile: true}
    domains = []
    seen = {}
    for each rawDomain in value.domains
        domain = LCase(PorticoCoreSafeIdentifier(rawDomain, 24))
        if allowed[domain] <> true or seen[domain] = true then return invalid
        seen[domain] = true
        domains.Push(domain)
    end for
    if value.resourceIds = invalid or GetInterface(value.resourceIds, "ifArray") = invalid or value.resourceIds.Count() > 100 then return invalid
    resourceIds = []
    seenIds = {}
    for each rawId in value.resourceIds
        id = PorticoViewerScopeOpaqueId(rawId, 128)
        if id = "" or seenIds[id] = true then return invalid
        seenIds[id] = true
        resourceIds.Push(id)
    end for
    result = {version: 1, kind: kind, sequence: sequence, domains: domains, resourceIds: resourceIds}
    if kind = "reset-domains"
        ackToken = PorticoCoreSafeIdentifier(value.ackToken, 80)
        if ackToken = "" then return invalid
        result.ackToken = ackToken
    end if
    return result
end function
