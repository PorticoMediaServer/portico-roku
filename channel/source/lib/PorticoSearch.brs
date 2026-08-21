function PorticoSearchController(scene as object, port as object, viewerController = invalid as dynamic) as object
    task = CreateObject("roSGNode", "PorticoSearchTask")
    if task = invalid then return { scene: scene, task: invalid, commandSequence: 0, stateSignature: "" }
    task.ObserveField("projection", port)
    task.ObserveField("projectionEnvelope", port)
    task.control = "RUN"
    return { scene: scene, task: task, viewerController: viewerController, envelopeMode: viewerController <> invalid, productContractRevision: "", commandSequence: 0, stateSignature: "" }
end function

function PorticoSearchViewerCommand(controller as object, viewerController as object, contractRevision as dynamic, values as object) as boolean
    if controller = invalid or controller.task = invalid or viewerController = invalid then return false
    revision = PorticoViewerScopeOpaqueId(contractRevision, 128)
    if revision = "" then return false
    command = {}
    for each key in values
        if key <> "sequence" then command[key] = values[key]
    end for
    command.productContractRevision = revision
    envelope = PorticoViewerRuntimeControllerCommand(viewerController, "search", command)
    if envelope = invalid then return false
    controller.viewerController = viewerController
    controller.envelopeMode = true
    controller.productContractRevision = revision
    controller.task.command = {sequence: envelope.operationSequence, kind: "viewer-fence"}
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoSearchViewerStateChanged(controller as object, viewerController as object, contractRevision as dynamic, state as dynamic) as boolean
    scope = PorticoViewerRuntimeControllerCurrentScope(viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    return PorticoSearchViewerCommand(controller, viewerController, contractRevision, {kind: "server-state", selectedServerId: scope.serverId, serverStatus: LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))})
end function

sub PorticoSearchAssignCommand(controller as object, command as object)
    if controller.envelopeMode
        PorticoSearchViewerCommand(controller, controller.viewerController, controller.productContractRevision, command)
    else
        controller.task.command = command
    end if
end sub

sub PorticoSearchHandleActivation(controller as object, activation as dynamic)
    if controller.task = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    allowed = {
        "query-changed": true, "clear-search": true, "submit-search": true, "retry-search": true, "load-more": true,
        "select-search-group": true, "cycle-search-sort": true, "toggle-search-direction": true,
        "select-recent-search": true, "clear-search-history": true
    }
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = {
        sequence: controller.commandSequence,
        kind: kind,
        query: PorticoHttpScalarString(activation.query, ""),
        queryRevision: PorticoHttpInteger(activation.queryRevision, 0)
    }
    if kind = "load-more" then command.groupId = PorticoSearchBridgeSafeId(activation.targetId)
    if kind = "select-search-group" then command.groupId = PorticoSearchBridgeSafeId(activation.targetId)
    if kind = "select-recent-search" then command.query = PorticoHttpScalarString(activation.query, "")
    PorticoSearchAssignCommand(controller, command)
end sub

sub PorticoSearchServerStateChanged(controller as object, state as dynamic)
    if controller.task = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return
    serverId = PorticoSearchBridgeSafeId(state.selectedServerId)
    serverStatus = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    signature = serverId + "|" + serverStatus
    if signature = controller.stateSignature then return
    controller.stateSignature = signature
    controller.commandSequence = controller.commandSequence + 1
    PorticoSearchAssignCommand(controller, { sequence: controller.commandSequence, kind: "server-state", selectedServerId: serverId, serverStatus: serverStatus })
end sub

function PorticoSearchHandleNodeEvent(controller as object, event as object, viewerController = invalid as dynamic) as boolean
    if controller.task = invalid then return false
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return false
    if event.GetField() = "projectionEnvelope"
        activeViewer = viewerController
        if activeViewer = invalid then activeViewer = controller.viewerController
        rawEnvelope = event.GetData()
        reconnectRequired = false
        if rawEnvelope <> invalid and Type(rawEnvelope) = "roAssociativeArray" and rawEnvelope.projection <> invalid then reconnectRequired = rawEnvelope.projection.searchServerReconnectRequired = true
        accepted = PorticoViewerRuntimeControllerAcceptProjection(activeViewer, rawEnvelope, {searchViewState: true})
        if not accepted.accepted then return false
        controller.scene.runtimeState = PorticoSavedApplyPendingRuntimeMutations(controller.scene.runtimeState)
        return reconnectRequired
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
    if source.searchViewState <> invalid then nextState.searchViewState = source.searchViewState
    nextState = PorticoSavedApplyPendingRuntimeMutations(nextState)
    controller.scene.runtimeState = nextState
    return source.searchServerReconnectRequired = true
end function

sub PorticoSearchSynchronizeSavedMutation(controller as object, runtime as dynamic, projection as dynamic)
    if controller.task = invalid or projection = invalid or Type(projection) <> "roAssociativeArray" then return
    result = projection.savedMutationResult
    if result = invalid or Type(result) <> "roAssociativeArray" then return
    mediaId = PorticoSearchBridgeSafeId(result.mediaId)
    family = LCase(PorticoHttpScalarString(result.family, ""))
    if mediaId = "" or (family <> "watchlist" and family <> "favorite" and family <> "watched") then return
    state = PorticoSavedMutationResolvedValue(runtime, projection)
    if state = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    PorticoSearchAssignCommand(controller, { sequence: controller.commandSequence, kind: "sync-media-state", mediaId: mediaId, family: family, value: state = true })
end sub

function PorticoSearchBridgeSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function
