function PorticoSavedController(scene as object, port as object, viewerController = invalid as dynamic) as object
    task = CreateObject("roSGNode", "PorticoSavedTask")
    if task = invalid then return { scene: scene, task: invalid, commandSequence: 0, stateSignature: "", serverId: "", mutationSequence: 0, latestMutations: {}, contentInvalidationRevision: 0 }
    task.ObserveField("projection", port)
    task.ObserveField("projectionEnvelope", port)
    task.control = "RUN"
    return { scene: scene, task: task, viewerController: viewerController, envelopeMode: viewerController <> invalid, viewerGeneration: 0, productContractRevision: "", commandSequence: 0, stateSignature: "", serverId: "", mutationSequence: 0, latestMutations: {}, mutationCommands: [], mutationInFlight: false, contentInvalidationRevision: 0 }
end function

function PorticoSavedViewerCommand(controller as object, viewerController as object, contractRevision as dynamic, values as object) as boolean
    if controller = invalid or controller.task = invalid or viewerController = invalid then return false
    revision = PorticoViewerScopeOpaqueId(contractRevision, 128)
    if revision = "" then return false
    command = {}
    for each key in values
        if key <> "sequence" then command[key] = values[key]
    end for
    command.productContractRevision = revision
    envelope = PorticoViewerRuntimeControllerCommand(viewerController, "saved", command)
    if envelope = invalid then return false
    controller.viewerController = viewerController
    controller.envelopeMode = true
    controller.productContractRevision = revision
    controller.task.command = {sequence: envelope.operationSequence, kind: "viewer-fence"}
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoSavedViewerStateChanged(controller as object, viewerController as object, contractRevision as dynamic, state as dynamic) as boolean
    scope = PorticoViewerRuntimeControllerCurrentScope(viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    if controller.viewerGeneration <> scope.viewerGeneration
        controller.viewerGeneration = scope.viewerGeneration
        controller.latestMutations = {}
        controller.mutationCommands = []
        controller.mutationInFlight = false
        controller.scene.runtimeState = PorticoSavedClearMutationJournal(controller.scene.runtimeState)
    end if
    return PorticoSavedViewerCommand(controller, viewerController, contractRevision, {kind: "server-state", selectedServerId: scope.serverId, selectedServerName: PorticoHttpScalarString(state.selectedServerName, "Portico Server"), serverStatus: LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))})
end function

sub PorticoSavedSynchronizeContentInvalidation(controller as object, runtime as dynamic)
    if controller.task = invalid or runtime = invalid or Type(runtime) <> "roAssociativeArray" then return
    revision = PorticoHttpInteger(runtime.savedResourcesRevision, 0)
    if revision <= controller.contentInvalidationRevision then return
    controller.contentInvalidationRevision = revision
    PorticoSavedCommand(controller, { kind: "invalidate-saved-resources" })
end sub

sub PorticoSavedServerStateChanged(controller as object, state as dynamic)
    if controller.task = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return
    serverId = PorticoSavedBridgeSafeId(state.selectedServerId)
    status = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    serverName = PorticoHttpScalarString(state.selectedServerName, "Portico Server")
    signature = serverId + "|" + status + "|" + serverName
    if signature = controller.stateSignature then return
    if serverId <> controller.serverId
        controller.latestMutations = {}
        controller.mutationCommands = []
        controller.mutationInFlight = false
        controller.scene.runtimeState = PorticoSavedClearMutationJournal(controller.scene.runtimeState)
    end if
    controller.serverId = serverId
    controller.stateSignature = signature
    PorticoSavedCommand(controller, { kind: "server-state", selectedServerId: serverId, selectedServerName: serverName, serverStatus: status })
end sub

sub PorticoSavedHandleActivation(controller as object, activation as dynamic)
    if controller.task = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    if kind = "saved-toggle"
        PorticoSavedMutateFromScene(controller, "watchlist", activation.targetId)
    else if kind = "favorite-toggle"
        PorticoSavedMutateFromScene(controller, "favorite", activation.targetId)
    else if kind = "watched-toggle"
        PorticoSavedMutateFromScene(controller, "watched", activation.targetId)
    else if kind = "select-saved-tab"
        PorticoSavedCommand(controller, { kind: kind, tabId: PorticoSavedBridgeSafeId(activation.targetId) })
    else if kind = "select-saved-resource"
        PorticoSavedCommand(controller, { kind: kind, resourceId: PorticoSavedBridgeSafeId(activation.targetId), resourceTitle: PorticoBrowseSafeText(activation.title, 140) })
    else if kind = "close-saved-resource" or kind = "load-more-saved" or kind = "retry-saved" or kind = "open-saved"
        PorticoSavedCommand(controller, { kind: kind })
    else if kind = "dismiss-saved-mutation-error"
        state = controller.scene.runtimeState
        if state <> invalid and Type(state) = "roAssociativeArray" and state.savedMutationError <> invalid
            nextState = ParseJson(FormatJson(state))
            nextState.Delete("savedMutationError")
            controller.scene.runtimeState = nextState
        end if
    end if
end sub

sub PorticoSavedMutateFromScene(controller as object, family as string, rawMediaId as dynamic)
    mediaId = PorticoSavedBridgeSafeId(rawMediaId)
    if mediaId = "" or controller.scene.runtimeState = invalid or controller.mutationCommands.count() >= 32 then return
    controller.mutationCommands.push({family: family, mediaId: mediaId})
    PorticoSavedDrainMutationCommand(controller)
end sub

sub PorticoSavedDrainMutationCommand(controller as object)
    if controller.mutationInFlight or controller.mutationCommands.count() = 0 then return
    queued = controller.mutationCommands.shift()
    family = queued.family
    mediaId = queued.mediaId
    current = PorticoSavedFindMediaState(controller.scene.runtimeState, mediaId, family)
    if current = invalid or current.supported <> true
        PorticoSavedDrainMutationCommand(controller)
        return
    end if
    desired = not current.value
    controller.mutationSequence = controller.mutationSequence + 1
    token = controller.mutationSequence.ToStr() + "-" + family
    key = mediaId + "|" + family
    controller.latestMutations[key] = { token: token, previous: current.value, desired: desired }
    controller.mutationInFlight = true
    optimistic = PorticoSavedPatchRuntime(controller.scene.runtimeState, mediaId, family, desired)
    controller.scene.runtimeState = PorticoSavedJournalMutation(optimistic, mediaId, family, desired, token)
    PorticoSavedCommand(controller, { kind: "mutate-media-state", mediaId: mediaId, family: family, value: desired, token: token })
end sub

function PorticoSavedHandleNodeEvent(controller as object, event as object, viewerController = invalid as dynamic) as boolean
    if controller.task = invalid then return false
    node = event.GetRoSGNode()
    if node = invalid or not node.IsSameNode(controller.task) then return false
    if event.GetField() = "projectionEnvelope"
        activeViewer = viewerController
        if activeViewer = invalid then activeViewer = controller.viewerController
        envelope = event.GetData()
        reconnectRequired = false
        if envelope <> invalid and Type(envelope) = "roAssociativeArray" and envelope.projection <> invalid then reconnectRequired = envelope.projection.savedServerReconnectRequired = true
        accepted = PorticoViewerRuntimeControllerAcceptProjection(activeViewer, envelope, {savedViewState: true, savedMutationResult: true})
        if not accepted.accepted then return false
        PorticoSavedApplyAcceptedMutation(controller, accepted.projection)
        return reconnectRequired
    end if
    if event.GetField() <> "projection" or controller.envelopeMode then return false
    projection = event.GetData()
    if projection = invalid or Type(projection) <> "roAssociativeArray" then return false
    state = controller.scene.runtimeState
    nextState = {}
    if state <> invalid and Type(state) = "roAssociativeArray"
        for each key in state
            nextState[key] = state[key]
        end for
    end if
    if projection.savedViewState <> invalid then nextState.savedViewState = projection.savedViewState
    result = projection.savedMutationResult
    if result <> invalid and Type(result) = "roAssociativeArray"
        mediaId = PorticoSavedBridgeSafeId(result.mediaId)
        family = LCase(PorticoBrowseSafeText(result.family, 16))
        key = mediaId + "|" + family
        pending = controller.latestMutations[key]
        if pending <> invalid and pending.token = PorticoBrowseSafeId(result.token)
            if result.succeeded <> true
                nextState = PorticoSavedPatchRuntime(nextState, mediaId, family, pending.previous)
                nextState.savedMutationError = PorticoSavedMutationErrorModel(result, pending.token, mediaId, family)
                resolvedValue = pending.previous
            else
                nextState.Delete("savedMutationError")
                resolvedValue = pending.desired
            end if
            nextState.savedMutationResolution = { token: pending.token, mediaId: mediaId, family: family, value: resolvedValue }
            nextState = PorticoSavedRemoveJournalMutation(nextState, mediaId, family, pending.token)
            controller.latestMutations.Delete(key)
            controller.mutationInFlight = false
            PorticoSavedDrainMutationCommand(controller)
        end if
    end if
    nextState = PorticoSavedApplyPendingRuntimeMutations(nextState)
    controller.scene.runtimeState = nextState
    return projection.savedServerReconnectRequired = true
end function

sub PorticoSavedApplyAcceptedMutation(controller as object, projection as dynamic)
    if projection = invalid or Type(projection) <> "roAssociativeArray" then return
    result = projection.savedMutationResult
    if result = invalid or Type(result) <> "roAssociativeArray" then return
    mediaId = PorticoSavedBridgeSafeId(result.mediaId)
    family = LCase(PorticoBrowseSafeText(result.family, 16))
    key = mediaId + "|" + family
    pending = controller.latestMutations[key]
    if pending = invalid or pending.token <> PorticoBrowseSafeId(result.token) then return
    nextState = controller.scene.runtimeState
    if result.succeeded <> true
        nextState = PorticoSavedPatchRuntime(nextState, mediaId, family, pending.previous)
        nextState.savedMutationError = PorticoSavedMutationErrorModel(result, pending.token, mediaId, family)
        resolvedValue = pending.previous
    else
        nextState.Delete("savedMutationError")
        resolvedValue = pending.desired
    end if
    nextState.savedMutationResolution = {token: pending.token, mediaId: mediaId, family: family, value: resolvedValue}
    nextState = PorticoSavedRemoveJournalMutation(nextState, mediaId, family, pending.token)
    controller.latestMutations.Delete(key)
    controller.scene.runtimeState = PorticoSavedApplyPendingRuntimeMutations(nextState)
    controller.mutationInFlight = false
    PorticoSavedDrainMutationCommand(controller)
end sub

function PorticoSavedMutationErrorModel(result as object, token as string, mediaId as string, family as string) as object
    conflict = result.conflict = true or PorticoHttpInteger(result.status, 0) = 409
    title = "Change not saved"
    body = "That change couldn't be saved."
    if conflict
        title = "Saved media changed"
        body = "This item changed elsewhere. Portico is loading the latest saved state."
    end if
    return {
        id: "saved-mutation-" + token,
        revision: 0,
        mediaId: mediaId,
        family: family,
        conflict: conflict,
        title: title,
        body: body,
        iconId: "status.warning"
    }
end function

function PorticoSavedMutationResolvedValue(runtime as dynamic, projection as dynamic) as dynamic
    if runtime = invalid or Type(runtime) <> "roAssociativeArray" or projection = invalid or Type(projection) <> "roAssociativeArray" then return invalid
    result = projection.savedMutationResult
    if result = invalid or Type(result) <> "roAssociativeArray" then return invalid
    mediaId = PorticoSavedBridgeSafeId(result.mediaId)
    family = LCase(PorticoBrowseSafeText(result.family, 16))
    if mediaId = "" or (family <> "watchlist" and family <> "favorite" and family <> "watched") then return invalid
    journal = runtime.savedPendingMutations
    if journal <> invalid and GetInterface(journal, "ifArray") <> invalid
        for each entry in journal
            if entry <> invalid and Type(entry) = "roAssociativeArray" and PorticoSavedBridgeSafeId(entry.mediaId) = mediaId and LCase(PorticoBrowseSafeText(entry.family, 16)) = family
                return entry.value = true
            end if
        end for
    end if
    resolution = runtime.savedMutationResolution
    if resolution <> invalid and Type(resolution) = "roAssociativeArray" and PorticoSavedBridgeSafeId(resolution.mediaId) = mediaId and LCase(PorticoBrowseSafeText(resolution.family, 16)) = family
        return resolution.value = true
    end if
    return PorticoContentBridgeFindMediaState(runtime, mediaId, family, 0)
end function

function PorticoSavedJournalMutation(runtime as dynamic, mediaId as string, family as string, value as boolean, token as string) as object
    nextState = runtime
    if nextState = invalid or Type(nextState) <> "roAssociativeArray" then nextState = {}
    journal = []
    existing = nextState.savedPendingMutations
    if existing <> invalid and GetInterface(existing, "ifArray") <> invalid
        for each entry in existing
            if entry <> invalid and Type(entry) = "roAssociativeArray"
                sameKey = PorticoSavedBridgeSafeId(entry.mediaId) = mediaId and LCase(PorticoBrowseSafeText(entry.family, 16)) = family
                if not sameKey then journal.push(entry)
            end if
        end for
    end if
    journal.push({ mediaId: mediaId, family: family, value: value, token: token })
    nextState.savedPendingMutations = journal
    return nextState
end function

function PorticoSavedRemoveJournalMutation(runtime as dynamic, mediaId as string, family as string, token as string) as object
    if runtime = invalid or Type(runtime) <> "roAssociativeArray" then return {}
    existing = runtime.savedPendingMutations
    if existing = invalid or GetInterface(existing, "ifArray") = invalid then return runtime
    journal = []
    for each entry in existing
        remove = false
        if entry <> invalid and Type(entry) = "roAssociativeArray"
            remove = PorticoSavedBridgeSafeId(entry.mediaId) = mediaId and LCase(PorticoBrowseSafeText(entry.family, 16)) = family and PorticoSavedBridgeSafeId(entry.token) = token
        end if
        if not remove then journal.push(entry)
    end for
    if journal.count() = 0
        runtime.Delete("savedPendingMutations")
    else
        runtime.savedPendingMutations = journal
    end if
    return runtime
end function

function PorticoSavedApplyPendingRuntimeMutations(runtime as dynamic) as dynamic
    if runtime = invalid or Type(runtime) <> "roAssociativeArray" then return runtime
    journal = runtime.savedPendingMutations
    if journal = invalid or GetInterface(journal, "ifArray") = invalid then return runtime
    nextState = runtime
    for each entry in journal
        if entry <> invalid and Type(entry) = "roAssociativeArray"
            mediaId = PorticoSavedBridgeSafeId(entry.mediaId)
            family = LCase(PorticoBrowseSafeText(entry.family, 16))
            if mediaId <> "" and (family = "watchlist" or family = "favorite" or family = "watched")
                nextState = PorticoSavedPatchRuntime(nextState, mediaId, family, entry.value = true)
            end if
        end if
    end for
    return nextState
end function

function PorticoSavedClearMutationJournal(runtime as dynamic) as dynamic
    if runtime = invalid or Type(runtime) <> "roAssociativeArray" then return runtime
    nextState = {}
    for each key in runtime
        if key <> "savedPendingMutations" and key <> "savedMutationError" and key <> "savedMutationResolution" then nextState[key] = runtime[key]
    end for
    return nextState
end function

sub PorticoSavedCommand(controller as object, values as object)
    if controller.task = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    command = { sequence: controller.commandSequence }
    for each key in values
        command[key] = values[key]
    end for
    if controller.envelopeMode
        PorticoSavedViewerCommand(controller, controller.viewerController, controller.productContractRevision, command)
    else
        controller.task.command = command
    end if
end sub

function PorticoSavedFindMediaState(runtime as dynamic, mediaId as string, family as string) as dynamic
    found = PorticoSavedFindMediaStateValue(runtime, mediaId, family, 0)
    if found = invalid then return invalid
    return found
end function

function PorticoSavedFindMediaStateValue(value as dynamic, mediaId as string, family as string, depth as integer) as dynamic
    if value = invalid or depth > 10 then return invalid
    if Type(value) = "roAssociativeArray"
        if PorticoSavedBridgeSafeId(value.id) = mediaId and PorticoSavedSupportsFamily(value, family)
            stateValue = false
            if family = "watchlist" then stateValue = value.watchlisted = true
            if family = "favorite" then stateValue = value.favorite = true
            if family = "watched" then stateValue = value.watched = true
            if value.state <> invalid and Type(value.state) = "roAssociativeArray"
                if family = "watchlist" then stateValue = value.state.watchlisted = true
                if family = "favorite" then stateValue = value.state.favorite = true
                if family = "watched" then stateValue = value.state.watched = true
            end if
            return { supported: true, value: stateValue }
        end if
        for each key in value
            found = PorticoSavedFindMediaStateValue(value[key], mediaId, family, depth + 1)
            if found <> invalid then return found
        end for
    else if GetInterface(value, "ifArray") <> invalid
        for each item in value
            found = PorticoSavedFindMediaStateValue(item, mediaId, family, depth + 1)
            if found <> invalid then return found
        end for
    end if
    return invalid
end function

function PorticoSavedSupportsFamily(model as object, family as string) as boolean
    actions = model.actions
    if actions = invalid then actions = model.serverActions
    if actions = invalid or GetInterface(actions, "ifArray") = invalid then return false
    for each rawAction in actions
        action = LCase(PorticoBrowseSafeText(rawAction, 48))
        if family = "watched" and action = "watched.set" then return true
        if Left(action, Len(family) + 1) = family + "." then return true
    end for
    return false
end function

function PorticoSavedPatchRuntime(runtime as dynamic, mediaId as string, family as string, value as boolean) as dynamic
    clone = ParseJson(FormatJson(runtime))
    PorticoSavedPatchValue(clone, mediaId, family, value, 0)
    return clone
end function

sub PorticoSavedPatchValue(target as dynamic, mediaId as string, family as string, value as boolean, depth as integer)
    if target = invalid or depth > 10 then return
    if Type(target) = "roAssociativeArray"
        if PorticoSavedBridgeSafeId(target.id) = mediaId and PorticoSavedSupportsFamily(target, family)
            if family = "watchlist" then target.watchlisted = value
            if family = "favorite" then target.favorite = value
            if family = "watched" then target.watched = value
            if target.state <> invalid and Type(target.state) = "roAssociativeArray"
                if family = "watchlist" then target.state.watchlisted = value
                if family = "favorite" then target.state.favorite = value
                if family = "watched" then target.state.watched = value
            end if
            target.actions = PorticoSavedActionsAfterMutation(target.actions, family, value)
            if target.serverActions <> invalid then target.serverActions = PorticoSavedActionsAfterMutation(target.serverActions, family, value)
            if target.uiActions <> invalid then target.uiActions = PorticoSavedUiActions(target.actions)
        end if
        for each key in target
            PorticoSavedPatchValue(target[key], mediaId, family, value, depth + 1)
        end for
    else if GetInterface(target, "ifArray") <> invalid
        for each item in target
            PorticoSavedPatchValue(item, mediaId, family, value, depth + 1)
        end for
    end if
end sub

function PorticoSavedBridgeSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function
