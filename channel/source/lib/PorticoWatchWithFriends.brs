function PorticoWatchWithFriendsController(port as object, viewerController as object) as object
    task = CreateObject("roSGNode", "PorticoWatchWithFriendsTask")
    if task = invalid then return {task: invalid, port: port, viewerController: viewerController, taskFenced: true}
    task.ObserveField("projectionEnvelope", port)
    task.control = "RUN"
    clock = CreateObject("roTimespan")
    clock.Mark()
    return {task: task, port: port, viewerController: viewerController, taskFenced: false, projection: invalid, serverSignature: "", localClock: clock, lastLocalReportAt: -10, lastLocalState: "", lastMemberReportAt: -20, lastMemberState: ""}
end function

function PorticoWatchWithFriendsStartTask(controller as object) as boolean
    if controller = invalid or controller.port = invalid then return false
    if controller.task <> invalid then return true
    task = CreateObject("roSGNode", "PorticoWatchWithFriendsTask")
    if task = invalid then return false
    task.ObserveField("projectionEnvelope", controller.port)
    task.control = "RUN"
    controller.task = task
    controller.taskFenced = false
    return true
end function

function PorticoWatchWithFriendsViewerCommand(controller as object, values as object) as boolean
    if controller = invalid or controller.task = invalid or controller.viewerController = invalid then return false
    envelope = PorticoViewerRuntimeControllerCommand(controller.viewerController, "watch-with-friends", values)
    if envelope = invalid then return false
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoWatchWithFriendsViewerStateChanged(controller as object, state as dynamic, capabilities = invalid as dynamic) as boolean
    if controller = invalid or controller.viewerController = invalid or not PorticoViewerRuntimeAccepting(controller.viewerController.runtime) then return false
    if not PorticoWatchWithFriendsStartTask(controller) then return false
    scope = PorticoViewerRuntimeControllerCurrentScope(controller.viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    serverStatus = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    normalizedCapabilities = PorticoEventTransportCapabilities(capabilities)
    capabilitySignature = "bounded"
    if normalizedCapabilities.longPollAdvertised then capabilitySignature = "long-poll|" + normalizedCapabilities.defaultWaitSeconds.ToStr() + "|" + normalizedCapabilities.maximumWaitSeconds.ToStr() + "|" + normalizedCapabilities.maximumConcurrentStreams.ToStr()
    signature = scope.serverId + "|" + scope.viewerGeneration.ToStr() + "|" + serverStatus + "|" + capabilitySignature
    if controller.serverSignature = signature then return true
    projectedCapabilities = {}
    if capabilities <> invalid and Type(capabilities) = "roAssociativeArray" then projectedCapabilities = capabilities
    command = {kind: "viewer-state", serverStatus: serverStatus, capabilities: projectedCapabilities}
    issued = PorticoWatchWithFriendsViewerCommand(controller, command)
    if issued then controller.serverSignature = signature
    return issued
end function

function PorticoWatchWithFriendsRefreshCommand(controller as object) as boolean
    return PorticoWatchWithFriendsViewerCommand(controller, {kind: "refresh-groups"})
end function

function PorticoWatchWithFriendsCreateCommand(controller as object, mediaId as dynamic, name = "" as dynamic) as boolean
    id = PorticoViewerScopeOpaqueId(mediaId, 128)
    if id = "" then return false
    command = {kind: "create-group", mediaId: id}
    label = PorticoCoreSafeText(name, 120)
    if label <> "" then command.name = label
    return PorticoWatchWithFriendsViewerCommand(controller, command)
end function

function PorticoWatchWithFriendsSelectCommand(controller as object, groupId as dynamic) as boolean
    id = PorticoViewerScopeOpaqueId(groupId, 128)
    if id = "" then return false
    return PorticoWatchWithFriendsViewerCommand(controller, {kind: "select-group", groupId: id})
end function

function PorticoWatchWithFriendsMembershipCommand(controller as object, groupId as dynamic, joining as boolean) as boolean
    id = PorticoViewerScopeOpaqueId(groupId, 128)
    if id = "" then return false
    kind = "leave-group"
    if joining then kind = "join-group"
    return PorticoWatchWithFriendsViewerCommand(controller, {kind: kind, groupId: id})
end function

function PorticoWatchWithFriendsEndCommand(controller as object) as boolean
    return PorticoWatchWithFriendsViewerCommand(controller, {kind: "end-group"})
end function

function PorticoWatchWithFriendsControlCommand(controller as object, action as dynamic, fields = invalid as dynamic) as boolean
    normalized = LCase(PorticoCoreSafeText(action, 16))
    allowed = {play: true, pause: true, seek: true, stop: true, load: true, next: true, previous: true}
    if allowed[normalized] <> true then return false
    command = {kind: "control", action: normalized}
    if fields <> invalid and Type(fields) = "roAssociativeArray"
        mediaId = PorticoViewerScopeOpaqueId(fields.mediaId, 128)
        if mediaId <> "" then command.mediaId = mediaId
        if fields.positionSeconds <> invalid then command.positionSeconds = fields.positionSeconds
        if fields.playbackRate <> invalid then command.playbackRate = fields.playbackRate
    end if
    return PorticoWatchWithFriendsViewerCommand(controller, command)
end function

function PorticoWatchWithFriendsMemberStateCommand(controller as object, state as dynamic, positionSeconds = invalid as dynamic) as boolean
    command = {kind: "member-state", state: LCase(PorticoCoreSafeText(state, 16))}
    if positionSeconds <> invalid then command.positionSeconds = positionSeconds
    return PorticoWatchWithFriendsViewerCommand(controller, command)
end function

function PorticoWatchWithFriendsSettingsCommand(controller as object, shuffleEnabled as dynamic, repeatMode as dynamic) as boolean
    return PorticoWatchWithFriendsViewerCommand(controller, {kind: "settings", shuffleEnabled: shuffleEnabled, repeatMode: repeatMode})
end function

function PorticoWatchWithFriendsQueueCommand(controller as object, kind as string, values as dynamic) as boolean
    if kind <> "queue-add" and kind <> "queue-reorder" and kind <> "queue-remove" then return false
    command = {kind: kind}
    if values <> invalid and Type(values) = "roAssociativeArray"
        if values.mediaId <> invalid then command.mediaId = values.mediaId
        if values.mediaIds <> invalid then command.mediaIds = values.mediaIds
    end if
    return PorticoWatchWithFriendsViewerCommand(controller, command)
end function

function PorticoWatchWithFriendsLocalPlaybackCommand(controller as object, mediaId as dynamic, positionSeconds as dynamic, paused as boolean, buffering as boolean) as boolean
    id = PorticoViewerScopeOpaqueId(mediaId, 128)
    if id = "" then return false
    return PorticoWatchWithFriendsViewerCommand(controller, {
        kind: "local-playback",
        mediaId: id,
        positionSeconds: positionSeconds,
        paused: paused,
        buffering: buffering
    })
end function

function PorticoWatchWithFriendsLocalMemberStateCommand(controller as object, mediaId as dynamic, positionSeconds as dynamic, paused as boolean, buffering as boolean, memberState as dynamic) as boolean
    id = PorticoViewerScopeOpaqueId(mediaId, 128)
    state = LCase(PorticoCoreSafeText(memberState, 16))
    if id = "" or (state <> "playing" and state <> "paused" and state <> "buffering" and state <> "ready") then return false
    return PorticoWatchWithFriendsViewerCommand(controller, {
        kind: "local-member-state",
        mediaId: id,
        positionSeconds: positionSeconds,
        paused: paused,
        buffering: buffering,
        state: state
    })
end function

function PorticoWatchWithFriendsCancelCommand(controller as object) as boolean
    return PorticoWatchWithFriendsViewerCommand(controller, {kind: "cancel"})
end function

function PorticoWatchWithFriendsTransitionFence(controller as object) as boolean
    if controller = invalid then return false
    if controller.task = invalid
        controller.taskFenced = true
        return true
    end if
    if controller.viewerController = invalid or not PorticoViewerRuntimeAccepting(controller.viewerController.runtime)
        controller.projection = invalid
        controller.serverSignature = ""
        controller.task.control = "STOP"
        controller.task = invalid
        controller.taskFenced = true
        return true
    end if
    issued = PorticoWatchWithFriendsCancelCommand(controller)
    if issued
        controller.projection = invalid
        controller.serverSignature = ""
    end if
    return issued
end function

function PorticoWatchWithFriendsHandleNodeEvent(controller as object, event as object) as object
    if controller = invalid or controller.task = invalid or event.GetField() <> "projectionEnvelope" then return {handled: false, projection: invalid}
    source = event.GetRoSGNode()
    if source = invalid or not source.IsSameNode(controller.task) then return {handled: false, projection: invalid}
    envelope = event.GetData()
    accepted = PorticoViewerRuntimeAcceptProjection(controller.viewerController.runtime, envelope)
    if not accepted.accepted then return {handled: true, projection: invalid}
    projection = PorticoWatchWithFriendsBridgeProjection(envelope.projection)
    controller.projection = projection
    return {handled: true, projection: projection}
end function

function PorticoWatchWithFriendsHandlePlayerEvent(controller as object, eventValue as dynamic) as boolean
    if controller = invalid or eventValue = invalid or Type(eventValue) <> "roAssociativeArray" then return false
    kind = LCase(PorticoHttpScalarString(eventValue.kind, ""))
    projection = controller.projection
    group = invalid
    if projection <> invalid then group = projection.group
    if kind = "watch-control"
        return PorticoWatchWithFriendsControlCommand(controller, eventValue.action, eventValue)
    else if kind = "watch-seek-trickplay"
        return PorticoWatchWithFriendsControlCommand(controller, "seek", {positionSeconds: eventValue.positionSeconds})
    else if kind = "watch-settings"
        return PorticoWatchWithFriendsSettingsCommand(controller, eventValue.shuffleEnabled, eventValue.repeatMode)
    else if kind = "watch-leave"
        return PorticoWatchWithFriendsMembershipCommand(controller, eventValue.groupId, false)
    else if kind = "watch-end"
        return PorticoWatchWithFriendsEndCommand(controller)
    else if kind = "completed"
        if projection <> invalid and projection.controlsEnabled = true then return PorticoWatchWithFriendsControlCommand(controller, "next", {})
        return false
    else if (kind = "player-state" or kind = "seek") and group <> invalid
        state = LCase(PorticoHttpScalarString(eventValue.state, "paused"))
        buffering = state = "buffering"
        paused = state <> "playing"
        nowSeconds = controller.localClock.TotalSeconds()
        localDue = kind = "seek" or state <> controller.lastLocalState or nowSeconds - controller.lastLocalReportAt >= 5
        memberState = state
        if memberState <> "playing" and memberState <> "paused" and memberState <> "buffering" then memberState = "ready"
        memberDue = memberState <> controller.lastMemberState or nowSeconds - controller.lastMemberReportAt >= 15
        if memberDue
            controller.lastLocalReportAt = nowSeconds
            controller.lastLocalState = state
            controller.lastMemberReportAt = nowSeconds
            controller.lastMemberState = memberState
            return PorticoWatchWithFriendsLocalMemberStateCommand(controller, group.mediaId, eventValue.positionSeconds, paused, buffering, memberState)
        else if localDue
            controller.lastLocalReportAt = nowSeconds
            controller.lastLocalState = state
            return PorticoWatchWithFriendsLocalPlaybackCommand(controller, group.mediaId, eventValue.positionSeconds, paused, buffering)
        end if
        return false
    end if
    return false
end function

function PorticoWatchWithFriendsHandleOverlayAction(controller as object, actionValue as dynamic) as object
    if controller = invalid or actionValue = invalid or Type(actionValue) <> "roAssociativeArray" then return {handled: false, closeRequested: false}
    kind = LCase(PorticoHttpScalarString(actionValue.kind, ""))
    if kind = "close" then return {handled: true, closeRequested: true}
    if kind = "create-group"
        handled = PorticoWatchWithFriendsCreateCommand(controller, actionValue.mediaId, actionValue.name)
    else if kind = "join-group"
        handled = PorticoWatchWithFriendsMembershipCommand(controller, actionValue.groupId, true)
    else if kind = "leave-group"
        handled = PorticoWatchWithFriendsMembershipCommand(controller, actionValue.groupId, false)
    else if kind = "end-group"
        handled = PorticoWatchWithFriendsEndCommand(controller)
    else
        return {handled: false, closeRequested: false}
    end if
    return {handled: handled, closeRequested: false}
end function

function PorticoWatchWithFriendsBridgeProjection(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    status = LCase(PorticoCoreSafeText(value.watchWithFriendsStatus, 32))
    allowedStatus = {idle: true, loading: true, ready: true, active: true, working: true, reconnecting: true, offline: true, error: true}
    if allowedStatus[status] <> true then return invalid
    projection = {
        status: status,
        errorCode: PorticoCoreSafeIdentifier(value.watchWithFriendsErrorCode, 80),
        groups: [],
        controlsEnabled: value.controlsEnabled = true,
        groupConnected: value.groupConnected = true,
        authority: LCase(PorticoCoreSafeText(value.authority, 16)),
        syncDirective: PorticoWatchWithFriendsBridgeSyncDirective(value.syncDirective)
    }
    groups = PorticoWatchWithFriendsGroups(value.groups)
    if groups <> invalid then projection.groups = groups
    if value.group <> invalid then projection.group = PorticoWatchWithFriendsGroup(value.group)
    if projection.authority <> "independent" and projection.authority <> "host" and projection.authority <> "participant" then projection.authority = "independent"
    if projection.authority <> "host" then projection.controlsEnabled = false
    return projection
end function

function PorticoWatchWithFriendsBridgeSyncDirective(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    kind = LCase(PorticoCoreSafeText(value.type, 16))
    allowed = {load: true, seek: true, pause: true, play: true, rate: true, none: true, ignore: true}
    if allowed[kind] <> true then return invalid
    result = {type: kind}
    mediaId = PorticoViewerScopeOpaqueId(value.mediaId, 128)
    if kind = "load" and mediaId = "" then return invalid
    if mediaId <> "" then result.mediaId = mediaId
    position = PorticoWatchWithFriendsNonNegativeInteger(value.positionSeconds, -1)
    if (kind = "load" or kind = "seek") and position < 0 then return invalid
    if position >= 0 then result.positionSeconds = position
    if value.paused <> invalid then result.paused = value.paused = true
    rate = PorticoWatchWithFriendsRate(value.playbackRate)
    if kind = "rate" and rate = invalid then return invalid
    if rate <> invalid then result.playbackRate = rate
    drift = PorticoWatchWithFriendsSignedDrift(value.driftSeconds)
    if drift <> invalid then result.driftSeconds = drift
    return result
end function

function PorticoWatchWithFriendsSignedDrift(value as dynamic) as dynamic
    kind = LCase(Type(value))
    if kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" and kind <> "float" and kind <> "rofloat" and kind <> "double" and kind <> "rodouble" then return invalid
    drift = value * 1.0
    if drift < -3600 or drift > 3600 then return invalid
    return drift
end function
