function PorticoLiveTvController(scene as object, port as object, viewerController = invalid as dynamic) as object
    task = CreateObject("roSGNode", "PorticoLiveTvTask")
    if task = invalid then return {scene: scene, task: invalid, commandSequence: 0, stateSignature: ""}
    task.ObserveField("projection", port)
    task.ObserveField("projectionEnvelope", port)
    task.control = "RUN"
    return {
        scene: scene,
        task: task,
        viewerController: viewerController,
        envelopeMode: viewerController <> invalid,
        productContractRevision: "",
        commandSequence: 0,
        stateSignature: "",
        mutationQueue: [],
        mutationInFlight: false
    }
end function

function PorticoLiveTvViewerCommand(controller as object, viewerController as object, contractRevision as dynamic, values as object) as boolean
    if controller = invalid or controller.task = invalid or viewerController = invalid then return false
    revision = PorticoViewerScopeOpaqueId(contractRevision, 128)
    if revision = "" then return false
    command = {}
    for each key in values
        if key <> "sequence" then command[key] = values[key]
    end for
    command.productContractRevision = revision
    envelope = PorticoViewerRuntimeControllerCommand(viewerController, "channels", command)
    if envelope = invalid then return false
    controller.viewerController = viewerController
    controller.envelopeMode = true
    controller.productContractRevision = revision
    controller.task.command = {sequence: envelope.operationSequence, kind: "viewer-fence"}
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoLiveTvViewerStateChanged(controller as object, viewerController as object, contractRevision as dynamic, state as dynamic) as boolean
    scope = PorticoViewerRuntimeControllerCurrentScope(viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    return PorticoLiveTvViewerCommand(controller, viewerController, contractRevision, {
        kind: "server-state",
        selectedServerId: scope.serverId,
        selectedServerName: PorticoHttpScalarString(state.selectedServerName, "Portico Server"),
        serverStatus: LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    })
end function

sub PorticoLiveTvAssignCommand(controller as object, command as object)
    if controller.envelopeMode
        PorticoLiveTvViewerCommand(controller, controller.viewerController, controller.productContractRevision, command)
    else
        controller.task.command = command
    end if
end sub

sub PorticoLiveTvHandleActivation(controller as object, activation as dynamic)
    if controller.task = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    allowed = {
        "select-source": true, "select-channel-tab": true, "select-program": true, "open-guide-program": true,
        "select-library-channel": true, "record-program": true, "record-series": true,
        "set-guide-day": true, "shift-guide-window": true, "set-guide-filter": true,
        "set-guide-group": true, "set-guide-query": true, "retry-channels": true,
        "page-channels": true, "load-more-guide": true, "load-more-channels": true,
        "load-more-library-channels": true, "load-more-dvr": true,
        "load-more-dvr-recordings": true, "load-more-dvr-rules": true, "load-more-dvr-schedule": true,
        "toggle-dvr-rule": true, "delete-dvr-rule": true,
        "cancel-dvr-recording": true, "delete-dvr-recording": true
    }
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = {sequence: controller.commandSequence, kind: kind}
    if kind = "select-source"
        command.sourceId = PorticoViewerScopeOpaqueId(activation.targetId, 128)
    else if kind = "select-channel-tab"
        command.kind = "select-tab"
        command.tabId = PorticoCoreSafeIdentifier(activation.targetId, 40)
    else if kind = "select-program" or kind = "open-guide-program" or kind = "record-program" or kind = "record-series"
        command.programId = PorticoViewerScopeOpaqueId(activation.targetId, 160)
    else if kind = "select-library-channel"
        command.channelId = PorticoViewerScopeOpaqueId(activation.targetId, 128)
    else if kind = "set-guide-day"
        command.dayOffset = PorticoHttpInteger(activation.targetId, -1)
    else if kind = "shift-guide-window"
        command.deltaMinutes = PorticoHttpInteger(activation.delta, 0)
    else if kind = "set-guide-filter"
        command.filterId = PorticoCoreSafeIdentifier(activation.targetId, 24)
    else if kind = "set-guide-group"
        command.group = PorticoHttpScalarString(activation.targetId, "")
    else if kind = "set-guide-query"
        command.query = PorticoHttpScalarString(activation.query, "")
    else if kind = "page-channels"
        command.delta = PorticoHttpInteger(activation.delta, 0)
    else if kind = "toggle-dvr-rule" or kind = "delete-dvr-rule"
        command.ruleId = PorticoViewerScopeOpaqueId(activation.targetId, 128)
    else if kind = "cancel-dvr-recording" or kind = "delete-dvr-recording"
        command.recordingId = PorticoViewerScopeOpaqueId(activation.targetId, 128)
    end if
    mutationKind = kind = "record-program" or kind = "record-series" or kind = "toggle-dvr-rule" or kind = "delete-dvr-rule" or kind = "cancel-dvr-recording" or kind = "delete-dvr-recording"
    if mutationKind
        if controller.mutationQueue.count() < 32 then controller.mutationQueue.push(command)
        PorticoLiveTvDrainMutation(controller)
    else
        PorticoLiveTvAssignCommand(controller, command)
    end if
end sub

sub PorticoLiveTvDrainMutation(controller as object)
    if controller.mutationInFlight or controller.mutationQueue.count() = 0 then return
    controller.mutationInFlight = true
    PorticoLiveTvAssignCommand(controller, controller.mutationQueue.shift())
end sub

sub PorticoLiveTvAcknowledgeMutation(controller as object, projection as dynamic)
    if not controller.mutationInFlight or projection = invalid or Type(projection) <> "roAssociativeArray" then return
    state = projection.channelsViewState
    if state = invalid or Type(state) <> "roAssociativeArray" or LCase(PorticoHttpScalarString(state.status, "")) = "working" then return
    controller.mutationInFlight = false
    PorticoLiveTvDrainMutation(controller)
end sub

sub PorticoLiveTvServerStateChanged(controller as object, state as dynamic)
    if controller.task = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return
    serverId = PorticoViewerScopeOpaqueId(state.selectedServerId, 128)
    serverStatus = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    serverName = PorticoHttpScalarString(state.selectedServerName, "Portico Server")
    signature = serverId + "|" + serverStatus + "|" + serverName
    if signature = controller.stateSignature then return
    controller.mutationQueue = []
    controller.mutationInFlight = false
    controller.stateSignature = signature
    controller.commandSequence = controller.commandSequence + 1
    PorticoLiveTvAssignCommand(controller, {sequence: controller.commandSequence, kind: "server-state", selectedServerId: serverId, selectedServerName: serverName, serverStatus: serverStatus})
end sub

function PorticoLiveTvHandleNodeEvent(controller as object, event as object, viewerController = invalid as dynamic) as boolean
    if controller.task = invalid then return false
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return false
    if event.GetField() = "projectionEnvelope"
        activeViewer = viewerController
        if activeViewer = invalid then activeViewer = controller.viewerController
        envelope = event.GetData()
        reconnect = false
        if envelope <> invalid and Type(envelope) = "roAssociativeArray" and envelope.projection <> invalid and Type(envelope.projection) = "roAssociativeArray" then reconnect = envelope.projection.channelsServerReconnectRequired = true
        accepted = PorticoViewerRuntimeControllerAcceptProjection(activeViewer, envelope, {channelsViewState: true})
        if not accepted.accepted then return false
        PorticoLiveTvAcknowledgeMutation(controller, accepted.projection)
        return reconnect
    end if
    if event.GetField() <> "projection" or controller.envelopeMode then return false
    source = event.GetData()
    if source = invalid or Type(source) <> "roAssociativeArray" then return false
    current = controller.scene.runtimeState
    nextState = {}
    if current <> invalid and Type(current) = "roAssociativeArray"
        for each key in current
            nextState[key] = current[key]
        end for
    end if
    if source.channelsViewState <> invalid then nextState.channelsViewState = source.channelsViewState
    PorticoLiveTvAcknowledgeMutation(controller, source)
    controller.scene.runtimeState = nextState
    return source.channelsServerReconnectRequired = true
end function

function PorticoLiveTvPlaybackTarget(activation as dynamic) as dynamic
    if activation = invalid or Type(activation) <> "roAssociativeArray" then return invalid
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    targetId = PorticoViewerScopeOpaqueId(activation.targetId, 160)
    if targetId = "" then return invalid
    if kind = "play-live" then return {targetKind: "live", targetId: targetId}
    if kind = "play-dvr" then return {targetKind: "dvr", targetId: targetId}
    if kind = "play-library-channel" then return {targetKind: "library-channel", targetId: targetId}
    return invalid
end function
