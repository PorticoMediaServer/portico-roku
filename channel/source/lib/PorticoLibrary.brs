function PorticoLibraryController(scene as object, port as object, viewerController = invalid as dynamic) as object
    task = CreateObject("roSGNode", "PorticoLibraryTask")
    if task = invalid then return { scene: scene, task: invalid, commandSequence: 0, stateSignature: "", openLibraryId: "", contentInvalidationRevision: 0, dvrInvalidationRevision: 0 }
    task.ObserveField("projection", port)
    task.ObserveField("projectionEnvelope", port)
    task.control = "RUN"
    return { scene: scene, task: task, viewerController: viewerController, envelopeMode: viewerController <> invalid, productContractRevision: "", commandSequence: 0, stateSignature: "", openLibraryId: "", contentInvalidationRevision: 0, dvrInvalidationRevision: 0 }
end function

function PorticoLibraryViewerCommand(controller as object, viewerController as object, contractRevision as dynamic, values as object) as boolean
    if controller = invalid or controller.task = invalid or viewerController = invalid then return false
    revision = PorticoViewerScopeOpaqueId(contractRevision, 128)
    if revision = "" then return false
    command = {}
    for each key in values
        if key <> "sequence" then command[key] = values[key]
    end for
    command.productContractRevision = revision
    envelope = PorticoViewerRuntimeControllerCommand(viewerController, "library", command)
    if envelope = invalid then return false
    controller.viewerController = viewerController
    controller.envelopeMode = true
    controller.productContractRevision = revision
    controller.task.command = {sequence: envelope.operationSequence, kind: "viewer-fence"}
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoLibraryViewerStateChanged(controller as object, viewerController as object, contractRevision as dynamic, state as dynamic) as boolean
    scope = PorticoViewerRuntimeControllerCurrentScope(viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    return PorticoLibraryViewerCommand(controller, viewerController, contractRevision, {kind: "server-state", selectedServerId: scope.serverId, selectedServerName: PorticoHttpScalarString(state.selectedServerName, "Portico Server"), serverStatus: LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))})
end function

sub PorticoLibraryAssignCommand(controller as object, command as object)
    if controller.envelopeMode
        PorticoLibraryViewerCommand(controller, controller.viewerController, controller.productContractRevision, command)
    else
        controller.task.command = command
    end if
end sub

sub PorticoLibrarySynchronizeContentInvalidation(controller as object, runtime as dynamic)
    if controller.task = invalid or runtime = invalid or Type(runtime) <> "roAssociativeArray" then return
    revision = PorticoHttpInteger(runtime.savedResourcesRevision, 0)
    if revision <= controller.contentInvalidationRevision then return
    controller.contentInvalidationRevision = revision
    controller.commandSequence = controller.commandSequence + 1
    PorticoLibraryAssignCommand(controller, { sequence: controller.commandSequence, kind: "invalidate-saved-resources" })
end sub

sub PorticoLibrarySynchronizeDvrInvalidation(controller as object, runtime as dynamic)
    if controller.task = invalid or runtime = invalid or Type(runtime) <> "roAssociativeArray" or runtime.channelsViewState = invalid or Type(runtime.channelsViewState) <> "roAssociativeArray" then return
    revision = PorticoHttpInteger(runtime.channelsViewState.dvrMutationRevision, 0)
    if revision <= controller.dvrInvalidationRevision then return
    controller.dvrInvalidationRevision = revision
    controller.commandSequence = controller.commandSequence + 1
    PorticoLibraryAssignCommand(controller, { sequence: controller.commandSequence, kind: "invalidate-dvr-schedule" })
end sub

sub PorticoLibraryHandleActivation(controller as object, activation as dynamic)
    if controller.task = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    allowed = {
        "select-tab": true, "select-facet": true, "select-resource": true, "select-library": true, "load-more": true, "retry-library": true,
        "clear-selection": true, "toggle-filter": true, "open-library-filters": true, "update-library-filter-draft": true,
        "apply-library-filters": true, "cancel-library-filters": true, "cycle-sort": true, "toggle-sort-direction": true,
        "alphabet-seek": true, "save-library-view": true, "launch-saved-view": true, "toggle-view": true
    }
    if allowed[kind] <> true then return
    targetId = PorticoLibraryBridgeSafeId(activation.targetId)
    controller.commandSequence = controller.commandSequence + 1
    command = { sequence: controller.commandSequence, kind: kind }
    if kind = "select-tab" then command.tabId = targetId
    if kind = "select-facet" then command.facetId = targetId
    if kind = "select-resource" then command.resourceId = targetId
    if kind = "select-library" then command.libraryId = targetId
    if kind = "update-library-filter-draft" or kind = "apply-library-filters"
        command.fieldId = PorticoLibraryBridgeSafeId(activation.fieldId)
        command.operatorId = PorticoLibraryBridgeSafeId(activation.operatorId)
        command.value = PorticoHttpScalarString(activation.value, "")
    end if
    if kind = "alphabet-seek" then command.prefix = PorticoHttpScalarString(activation.prefix, "")
    if kind = "save-library-view" then command.title = PorticoHttpScalarString(activation.title, "")
    if kind = "launch-saved-view" then command.savedViewId = targetId
    PorticoLibraryAssignCommand(controller, command)
end sub

sub PorticoLibraryServerStateChanged(controller as object, state as dynamic)
    if controller.task = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return
    serverId = PorticoLibraryBridgeSafeId(state.selectedServerId)
    serverStatus = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    serverName = PorticoHttpScalarString(state.selectedServerName, "Portico Server")
    signature = serverId + "|" + serverStatus + "|" + serverName
    if signature = controller.stateSignature then return
    controller.stateSignature = signature
    controller.commandSequence = controller.commandSequence + 1
    PorticoLibraryAssignCommand(controller, { sequence: controller.commandSequence, kind: "server-state", selectedServerId: serverId, selectedServerName: serverName, serverStatus: serverStatus })
end sub

sub PorticoLibraryOpen(controller as object, libraryId as string)
    if controller.task = invalid then return
    safeId = PorticoLibraryBridgeSafeId(libraryId)
    if safeId = controller.openLibraryId then return
    controller.openLibraryId = safeId
    controller.commandSequence = controller.commandSequence + 1
    PorticoLibraryAssignCommand(controller, { sequence: controller.commandSequence, kind: "open-library", libraryId: safeId })
end sub

function PorticoLibraryHandleNodeEvent(controller as object, event as object, viewerController = invalid as dynamic) as boolean
    if controller.task = invalid then return false
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return false
    if event.GetField() = "projectionEnvelope"
        activeViewer = viewerController
        if activeViewer = invalid then activeViewer = controller.viewerController
        rawEnvelope = event.GetData()
        reconnectRequired = false
        if rawEnvelope <> invalid and Type(rawEnvelope) = "roAssociativeArray" and rawEnvelope.projection <> invalid then reconnectRequired = rawEnvelope.projection.libraryServerReconnectRequired = true
        accepted = PorticoViewerRuntimeControllerAcceptProjection(activeViewer, rawEnvelope, {libraryViewState: true})
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
    if source.libraryViewState <> invalid then nextState.libraryViewState = source.libraryViewState
    nextState = PorticoSavedApplyPendingRuntimeMutations(nextState)
    controller.scene.runtimeState = nextState
    return source.libraryServerReconnectRequired = true
end function

sub PorticoLibrarySynchronizeSavedMutation(controller as object, runtime as dynamic, projection as dynamic)
    if controller.task = invalid or projection = invalid or Type(projection) <> "roAssociativeArray" then return
    result = projection.savedMutationResult
    if result = invalid or Type(result) <> "roAssociativeArray" then return
    mediaId = PorticoLibraryBridgeSafeId(result.mediaId)
    family = LCase(PorticoHttpScalarString(result.family, ""))
    if mediaId = "" or (family <> "watchlist" and family <> "favorite" and family <> "watched") then return
    state = PorticoSavedMutationResolvedValue(runtime, projection)
    if state = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    PorticoLibraryAssignCommand(controller, { sequence: controller.commandSequence, kind: "sync-media-state", mediaId: mediaId, family: family, value: state = true })
end sub

function PorticoLibraryBridgeSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function
