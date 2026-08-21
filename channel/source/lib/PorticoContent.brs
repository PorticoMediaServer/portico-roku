function PorticoContentController(scene as object, port as object, viewerController = invalid as dynamic) as object
    task = CreateObject("roSGNode", "PorticoContentTask")
    if task = invalid then return { scene: scene, task: invalid, commandSequence: 0, stateSignature: "", playbackWasActive: false, lastPlaybackGeneration: 0, lastInvalidatedPlaybackGeneration: -1 }
    task.ObserveField("projection", port)
    task.ObserveField("projectionEnvelope", port)
    task.control = "RUN"
    return { scene: scene, task: task, viewerController: viewerController, envelopeMode: viewerController <> invalid, productContractRevision: "", commandSequence: 0, stateSignature: "", playbackWasActive: false, lastPlaybackGeneration: 0, lastInvalidatedPlaybackGeneration: -1 }
end function

function PorticoContentViewerCommand(controller as object, viewerController as object, contractRevision as dynamic, values as object) as boolean
    if controller = invalid or controller.task = invalid or viewerController = invalid then return false
    revision = PorticoViewerScopeOpaqueId(contractRevision, 128)
    if revision = "" then return false
    command = {}
    for each key in values
        if key <> "sequence" then command[key] = values[key]
    end for
    command.productContractRevision = revision
    envelope = PorticoViewerRuntimeControllerCommand(viewerController, "content", command)
    if envelope = invalid then return false
    controller.viewerController = viewerController
    controller.envelopeMode = true
    controller.productContractRevision = revision
    controller.task.command = {sequence: envelope.operationSequence, kind: "viewer-fence"}
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoContentViewerStateChanged(controller as object, viewerController as object, contractRevision as dynamic, state as dynamic) as boolean
    scope = PorticoViewerRuntimeControllerCurrentScope(viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    homeOrder = []
    hiddenRows = []
    if state.viewerPreferences <> invalid and Type(state.viewerPreferences) = "roAssociativeArray" and state.viewerPreferences.profileServer <> invalid and Type(state.viewerPreferences.profileServer) = "roAssociativeArray" and state.viewerPreferences.profileServer.home <> invalid and Type(state.viewerPreferences.profileServer.home) = "roAssociativeArray"
        home = state.viewerPreferences.profileServer.home
        if home.rowOrder <> invalid then homeOrder = home.rowOrder
        if home.hiddenRowIds <> invalid then hiddenRows = home.hiddenRowIds
    end if
    return PorticoContentViewerCommand(controller, viewerController, contractRevision, {kind: "server-state", selectedServerId: scope.serverId, serverStatus: LCase(PorticoHttpScalarString(state.serverStatus, "not-connected")), homeRowOrder: homeOrder, hiddenHomeRowIds: hiddenRows})
end function

sub PorticoContentAssignCommand(controller as object, command as object)
    if controller.envelopeMode
        PorticoContentViewerCommand(controller, controller.viewerController, controller.productContractRevision, command)
    else
        controller.task.command = command
    end if
end sub

sub PorticoContentSynchronizePlayback(controller as object, projection as dynamic)
    if controller.task = invalid or projection = invalid or Type(projection) <> "roAssociativeArray" then return
    status = LCase(PorticoHttpScalarString(projection.playbackStatus, ""))
    generation = PorticoHttpInteger(projection.playbackGeneration, controller.lastPlaybackGeneration)
    if generation > controller.lastPlaybackGeneration then controller.lastPlaybackGeneration = generation
    activeStatuses = { preparing: true, ready: true, playing: true, paused: true, buffering: true, stopping: true }
    if activeStatuses[status] = true
        controller.playbackWasActive = true
        return
    end if
    if (status = "ended" or status = "idle") and controller.playbackWasActive and controller.lastInvalidatedPlaybackGeneration <> controller.lastPlaybackGeneration
        controller.playbackWasActive = false
        controller.lastInvalidatedPlaybackGeneration = controller.lastPlaybackGeneration
        controller.commandSequence = controller.commandSequence + 1
        PorticoContentAssignCommand(controller, { sequence: controller.commandSequence, kind: "invalidate-playback-state" })
    end if
end sub

sub PorticoContentHandleActivation(controller as object, activation as dynamic)
    if controller.task = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = PorticoHttpScalarString(activation.kind, "")
    if kind = "refresh-home"
        PorticoContentCommand(controller, kind, "")
    else if kind = "open-detail"
        PorticoContentDetailCommand(controller, activation)
    else if kind = "select-detail-season" or kind = "load-more-detail-episodes" or kind = "retry-detail-episodes"
        PorticoContentSeasonCommand(controller, kind, activation)
    else if kind = "select-person"
        PorticoContentPersonCommand(controller, kind, activation.targetId, activation.personName)
    else if kind = "retry-person"
        PorticoContentPersonCommand(controller, kind, activation.targetId, activation.personName)
    else if kind = "load-more-person"
        PorticoContentPersonCommand(controller, kind, activation.targetId, activation.personName)
    else if kind = "load-more-home-row"
        PorticoContentHomeRowCommand(controller, activation.targetId)
    else if kind = "open-detail-targets" or kind = "add-detail-target" or kind = "create-detail-target" or kind = "set-detail-rating" or kind = "set-detail-reaction" or kind = "detail-queue"
        PorticoContentMoreActionCommand(controller, kind, activation)
    end if
end sub

sub PorticoContentDetailCommand(controller as object, activation as object)
    mediaId = PorticoContentBridgeSafeId(activation.targetId)
    if controller.task = invalid or mediaId = "" then return
    controller.commandSequence = controller.commandSequence + 1
    command = {sequence: controller.commandSequence, kind: "open-detail", mediaId: mediaId}
    seasonId = PorticoContentBridgeSafeId(activation.seasonId)
    episodeId = PorticoContentBridgeSafeId(activation.episodeId)
    if seasonId <> "" then command.seasonId = seasonId
    if episodeId <> "" then command.episodeId = episodeId
    PorticoContentAssignCommand(controller, command)
end sub

sub PorticoContentSeasonCommand(controller as object, kind as string, activation as object)
    if controller.task = invalid then return
    allowed = {"select-detail-season": true, "load-more-detail-episodes": true, "retry-detail-episodes": true}
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = {sequence: controller.commandSequence, kind: kind}
    if kind = "select-detail-season" then command.seasonId = PorticoContentBridgeSafeId(activation.targetId)
    PorticoContentAssignCommand(controller, command)
end sub

sub PorticoContentSynchronizeSavedMutation(controller as object, runtime as dynamic, projection as dynamic)
    if controller.task = invalid or projection = invalid or Type(projection) <> "roAssociativeArray" then return
    result = projection.savedMutationResult
    if result = invalid or Type(result) <> "roAssociativeArray" then return
    mediaId = PorticoContentBridgeSafeId(result.mediaId)
    family = LCase(PorticoHttpScalarString(result.family, ""))
    if mediaId = "" or (family <> "watchlist" and family <> "favorite" and family <> "watched") then return
    state = PorticoSavedMutationResolvedValue(runtime, projection)
    if state = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    PorticoContentAssignCommand(controller, {sequence: controller.commandSequence, kind: "sync-media-state", mediaId: mediaId, family: family, value: state = true})
end sub

function PorticoContentBridgeFindMediaState(value as dynamic, mediaId as string, family as string, depth as integer) as dynamic
    if value = invalid or depth > 10 then return invalid
    if Type(value) = "roAssociativeArray"
        if PorticoContentBridgeSafeId(value.id) = mediaId
            if family = "watchlist" and value.watchlisted <> invalid then return value.watchlisted = true
            if family = "favorite" and value.favorite <> invalid then return value.favorite = true
            if family = "watched" and value.watched <> invalid then return value.watched = true
            if value.state <> invalid and Type(value.state) = "roAssociativeArray"
                if family = "watchlist" and value.state.watchlisted <> invalid then return value.state.watchlisted = true
                if family = "favorite" and value.state.favorite <> invalid then return value.state.favorite = true
                if family = "watched" and value.state.watched <> invalid then return value.state.watched = true
            end if
        end if
        for each key in value
            found = PorticoContentBridgeFindMediaState(value[key], mediaId, family, depth + 1)
            if found <> invalid then return found
        end for
    else if GetInterface(value, "ifArray") <> invalid
        for each item in value
            found = PorticoContentBridgeFindMediaState(item, mediaId, family, depth + 1)
            if found <> invalid then return found
        end for
    end if
    return invalid
end function

sub PorticoContentMoreActionCommand(controller as object, kind as string, activation as object)
    if controller.task = invalid then return
    allowed = { "open-detail-targets": true, "add-detail-target": true, "create-detail-target": true, "set-detail-rating": true, "set-detail-reaction": true, "detail-queue": true }
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = { sequence: controller.commandSequence, kind: kind }
    if activation.targetKind <> invalid then command.targetKind = LCase(PorticoHttpScalarString(activation.targetKind, ""))
    if activation.savedTargetId <> invalid then command.savedTargetId = PorticoContentBridgeSafeId(activation.savedTargetId)
    if activation.title <> invalid then command.title = PorticoHttpScalarString(activation.title, "")
    if activation.rating <> invalid then command.rating = activation.rating
    if activation.reaction <> invalid then command.reaction = LCase(PorticoHttpScalarString(activation.reaction, ""))
    if activation.position <> invalid then command.position = LCase(PorticoHttpScalarString(activation.position, ""))
    PorticoContentAssignCommand(controller, command)
end sub

sub PorticoContentHomeRowCommand(controller as object, rawRowId as dynamic)
    if controller.task = invalid then return
    rowId = PorticoContentBridgeSafeId(rawRowId)
    if rowId = "" then return
    controller.commandSequence = controller.commandSequence + 1
    PorticoContentAssignCommand(controller, { sequence: controller.commandSequence, kind: "load-more-home-row", rowId: rowId })
end sub

sub PorticoContentServerStateChanged(controller as object, state as dynamic)
    if controller.task = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return
    serverId = PorticoContentBridgeSafeId(state.selectedServerId)
    serverStatus = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    signature = serverId + "|" + serverStatus
    if signature = controller.stateSignature then return
    controller.stateSignature = signature
    controller.commandSequence = controller.commandSequence + 1
    PorticoContentAssignCommand(controller, {
        sequence: controller.commandSequence,
        kind: "server-state",
        selectedServerId: serverId,
        serverStatus: serverStatus
    })
end sub

sub PorticoContentCommand(controller as object, kind as string, mediaId as string)
    if controller.task = invalid then return
    allowed = { "refresh-home": true, "open-detail": true }
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = { sequence: controller.commandSequence, kind: kind }
    if kind = "open-detail" then command.mediaId = PorticoContentBridgeSafeId(mediaId)
    PorticoContentAssignCommand(controller, command)
end sub

function PorticoContentHandleNodeEvent(controller as object, event as object, viewerController = invalid as dynamic) as boolean
    if controller.task = invalid then return false
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return false
    if event.GetField() = "projectionEnvelope"
        activeViewer = viewerController
        if activeViewer = invalid then activeViewer = controller.viewerController
        rawEnvelope = event.GetData()
        reconnectRequired = false
        if rawEnvelope <> invalid and Type(rawEnvelope) = "roAssociativeArray" and rawEnvelope.projection <> invalid then reconnectRequired = rawEnvelope.projection.serverReconnectRequired = true
        allowed = {contentServerId: true, homeStatus: true, homeModel: true, detailStatus: true, detailMediaId: true, detailModel: true, personViewState: true, savedResourcesRevision: true, contentInvalidations: true}
        accepted = PorticoViewerRuntimeControllerAcceptProjection(activeViewer, rawEnvelope, allowed)
        if not accepted.accepted then return false
        controller.scene.runtimeState = PorticoSavedApplyPendingRuntimeMutations(controller.scene.runtimeState)
        return reconnectRequired
    end if
    if event.GetField() <> "projection" or controller.envelopeMode then return false
    source = PorticoContentProjection(event.GetData())
    if source = invalid then return false

    current = controller.scene.runtimeState
    nextState = {}
    if current <> invalid and Type(current) = "roAssociativeArray"
        for each key in current
            nextState[key] = current[key]
        end for
    end if
    reconnectRequired = source.serverReconnectRequired = true
    source.Delete("serverReconnectRequired")
    for each key in source
        if source[key] = invalid
            nextState.Delete(key)
        else
            nextState[key] = source[key]
        end if
    end for
    nextState = PorticoSavedApplyPendingRuntimeMutations(nextState)
    controller.scene.runtimeState = nextState
    return reconnectRequired
end function

function PorticoContentProjection(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    allowed = {
        contentServerId: true,
        homeStatus: true,
        homeModel: true,
        detailStatus: true,
        detailMediaId: true,
        detailModel: true,
        personViewState: true,
        savedResourcesRevision: true,
        contentInvalidations: true,
        serverReconnectRequired: true
    }
    projection = {}
    for each key in source
        if allowed[key] = true then projection[key] = source[key]
    end for
    return projection
end function

function PorticoContentBridgeSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

sub PorticoContentPersonCommand(controller as object, kind as string, rawId as dynamic, rawName as dynamic)
    if controller.task = invalid or (kind <> "select-person" and kind <> "retry-person" and kind <> "load-more-person") then return
    controller.commandSequence = controller.commandSequence + 1
    command = { sequence: controller.commandSequence, kind: kind }
    if kind = "select-person"
        command.personId = PorticoContentBridgeSafeId(rawId)
        command.personName = PorticoHttpScalarString(rawName, "")
    end if
    PorticoContentAssignCommand(controller, command)
end sub
