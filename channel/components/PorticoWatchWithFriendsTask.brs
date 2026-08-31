sub init()
    m.top.functionName = "PorticoWatchWithFriendsRun"
end sub

sub PorticoWatchWithFriendsRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    controller = {
        clock: clock,
        lastCommandSequence: 0,
        serverStatus: "not-connected",
        status: "idle",
        errorCode: "",
        groups: [],
        group: invalid,
        selectedGroupId: "",
        localPlayback: invalid,
        syncState: invalid,
        syncDirective: invalid,
        transport: invalid,
        capabilities: {},
        capabilitiesLoaded: false,
        resetRetryAt: 0,
        longPollQuarantined: false,
        mutationInFlight: false,
        longPollRequest: invalid
    }
    PorticoWatchWithFriendsTaskAdopt(controller, PorticoWatchWithFriendsTaskState())
    while true
        PorticoWatchWithFriendsHandleCommand(controller)
        PorticoWatchWithFriendsTick(controller)
        Sleep(100)
    end while
end sub

sub PorticoWatchWithFriendsHandleCommand(controller as object)
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return
    incoming = PorticoViewerScopeNormalize(envelope.viewerScope)
    if controller.envelopeMode and incoming <> invalid and not PorticoViewerScopeEquals(controller.viewerScope, incoming)
        PorticoWatchWithFriendsFence(controller, "viewer-changed")
    end if
    command = PorticoWatchWithFriendsAcceptCommand(controller, envelope)
    if command = invalid then return
    kind = LCase(PorticoCoreSafeIdentifier(command.kind, 80))
    if kind = "viewer-fence" or kind = "cancel"
        PorticoWatchWithFriendsFence(controller, kind)
        PorticoWatchWithFriendsPublish(controller)
    else if kind = "viewer-state"
        controller.capabilities = {}
        if command.capabilities <> invalid and Type(command.capabilities) = "roAssociativeArray" then controller.capabilities = command.capabilities
        controller.capabilitiesLoaded = true
        PorticoWatchWithFriendsServerState(controller, command)
    else if kind = "server-state"
        PorticoWatchWithFriendsServerState(controller, command)
    else if kind = "capabilities"
        controller.capabilities = {}
        if command.capabilities <> invalid and Type(command.capabilities) = "roAssociativeArray" then controller.capabilities = command.capabilities
        controller.capabilitiesLoaded = true
        PorticoWatchWithFriendsReconcileTransport(controller)
    else if kind = "refresh-groups"
        PorticoWatchWithFriendsLoadGroups(controller)
    else if kind = "create-group"
        PorticoWatchWithFriendsCreateGroup(controller, command)
    else if kind = "select-group"
        PorticoWatchWithFriendsSelectGroup(controller, command)
    else if kind = "join-group"
        PorticoWatchWithFriendsJoinLeave(controller, command, true)
    else if kind = "leave-group"
        PorticoWatchWithFriendsJoinLeave(controller, command, false)
    else if kind = "end-group"
        PorticoWatchWithFriendsEndGroup(controller)
    else if kind = "control"
        PorticoWatchWithFriendsControl(controller, command)
    else if kind = "member-state"
        PorticoWatchWithFriendsMemberState(controller, command)
    else if kind = "settings"
        PorticoWatchWithFriendsSettings(controller, command)
    else if kind = "queue-add"
        PorticoWatchWithFriendsQueueAdd(controller, command)
    else if kind = "queue-reorder"
        PorticoWatchWithFriendsQueueReorder(controller, command)
    else if kind = "queue-remove"
        PorticoWatchWithFriendsQueueRemove(controller, command)
    else if kind = "local-playback"
        PorticoWatchWithFriendsLocalPlayback(controller, command)
    else if kind = "local-member-state"
        PorticoWatchWithFriendsLocalPlayback(controller, command)
        PorticoWatchWithFriendsMemberState(controller, command)
    end if
end sub

sub PorticoWatchWithFriendsServerState(controller as object, command as object)
    status = LCase(PorticoCoreSafeText(command.serverStatus, 40))
    allowed = {online: true, connecting: true, offline: true, blocked: true, "identity-mismatch": true, incompatible: true, "permission-removed": true, "not-connected": true}
    if allowed[status] <> true then status = "not-connected"
    controller.serverStatus = status
    if status <> "online"
        if controller.longPollRequest <> invalid and controller.longPollRequest.transfer <> invalid then controller.longPollRequest.transfer.AsyncCancel()
        controller.longPollRequest = invalid
        if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, "server-unavailable")
        controller.transport = invalid
        controller.capabilitiesLoaded = false
        controller.capabilities = {}
        if controller.group <> invalid then controller.status = "reconnecting" else controller.status = "offline"
        controller.errorCode = ""
        controller.syncDirective = invalid
        PorticoWatchWithFriendsPublish(controller)
        return
    end if
    if not controller.capabilitiesLoaded then PorticoWatchWithFriendsLoadEventCapabilities(controller)
    if controller.group <> invalid
        PorticoWatchWithFriendsReconcileTransport(controller)
    else
        PorticoWatchWithFriendsLoadGroups(controller)
    end if
end sub

sub PorticoWatchWithFriendsLoadEventCapabilities(controller as object)
    response = PorticoWatchWithFriendsRequest(controller, "getProductContract", {}, invalid, "")
    if response.interrupted then return
    if response.ok and PorticoProductContractValidateLive(response.data).ok
        controller.capabilities = {eventTransports: response.data.eventTransports, longPoll: response.data.longPoll}
        controller.capabilitiesLoaded = true
        PorticoWatchWithFriendsReconcileTransport(controller)
    end if
end sub

sub PorticoWatchWithFriendsLoadGroups(controller as object)
    if controller.serverStatus <> "online" then return
    controller.status = "loading"
    controller.errorCode = ""
    PorticoWatchWithFriendsPublish(controller)
    response = PorticoWatchWithFriendsRequest(controller, "getWatchWithFriendsGroups", {}, invalid, "")
    if response.interrupted then return
    if not response.ok
        PorticoWatchWithFriendsFailure(controller, response, "groups-unavailable")
        return
    end if
    groups = PorticoWatchWithFriendsGroups(response.data)
    if groups = invalid
        PorticoWatchWithFriendsSetError(controller, "response-incompatible")
        return
    end if
    controller.groups = groups
    controller.status = "ready"
    controller.errorCode = ""
    PorticoWatchWithFriendsPublish(controller)
end sub

sub PorticoWatchWithFriendsCreateGroup(controller as object, command as object)
    mediaId = PorticoViewerScopeOpaqueId(command.mediaId, 128)
    if mediaId = "" or controller.serverStatus <> "online" then return
    body = {mediaId: mediaId}
    name = PorticoWatchWithFriendsText(command.name, 120)
    if name <> "" then body.name = name
    PorticoWatchWithFriendsMutate(controller, "postWatchWithFriendsGroups", {}, body, "", "create-failed", true)
end sub

sub PorticoWatchWithFriendsSelectGroup(controller as object, command as object)
    groupId = PorticoViewerScopeOpaqueId(command.groupId, 128)
    if groupId = "" or controller.serverStatus <> "online" then return
    controller.selectedGroupId = groupId
    controller.status = "loading"
    controller.errorCode = ""
    PorticoWatchWithFriendsPublish(controller)
    PorticoWatchWithFriendsRefreshGroup(controller, true)
end sub

sub PorticoWatchWithFriendsJoinLeave(controller as object, command as object, joining as boolean)
    groupId = PorticoViewerScopeOpaqueId(command.groupId, 128)
    if groupId = "" and controller.group <> invalid then groupId = controller.group.id
    if groupId = "" then return
    operationId = "postWatchWithFriendsGroupsGroupIdLeave"
    if joining then operationId = "postWatchWithFriendsGroupsGroupIdJoin"
    PorticoWatchWithFriendsMutate(controller, operationId, {groupId: groupId}, invalid, "", "membership-failed", true)
end sub

sub PorticoWatchWithFriendsEndGroup(controller as object)
    if controller.group = invalid or controller.group.permissions.isHost <> true then return
    query = PorticoWatchWithFriendsRevisionQuery(controller, "end")
    PorticoWatchWithFriendsMutate(controller, "deleteWatchWithFriendsGroupsGroupId", {groupId: controller.group.id}, invalid, query, "end-failed", false)
end sub

sub PorticoWatchWithFriendsControl(controller as object, command as object)
    if controller.group = invalid or controller.group.permissions.canControl <> true or controller.serverStatus <> "online" then return
    action = LCase(PorticoCoreSafeText(command.action, 16))
    allowed = {play: true, pause: true, seek: true, stop: true, load: true, next: true, previous: true}
    if allowed[action] <> true then return
    body = {
        action: action,
        expectedRevision: controller.group.revision,
        idempotencyKey: PorticoWatchWithFriendsIdempotencyKey(controller, "control-" + action)
    }
    position = PorticoWatchWithFriendsNonNegativeInteger(command.positionSeconds, -1)
    mediaId = PorticoViewerScopeOpaqueId(command.mediaId, 128)
    entryId = PorticoViewerScopeOpaqueId(command.entryId, 128)
    if action = "seek" and position < 0 then return
    if action = "load" and ((mediaId = "" and entryId = "") or (mediaId <> "" and entryId <> "")) then return
    if position >= 0 then body.positionSeconds = position
    if mediaId <> "" then body.mediaId = mediaId
    if entryId <> "" then body.entryId = entryId
    rate = PorticoWatchWithFriendsRate(command.playbackRate)
    if rate <> invalid then body.playbackRate = rate
    PorticoWatchWithFriendsMutate(controller, "patchWatchWithFriendsGroupsGroupIdState", {groupId: controller.group.id}, body, "", "control-failed", true)
end sub

sub PorticoWatchWithFriendsMemberState(controller as object, command as object)
    if controller.group = invalid or controller.serverStatus <> "online" then return
    state = LCase(PorticoCoreSafeText(command.state, 16))
    allowed = {joined: true, ready: true, buffering: true, playing: true, paused: true}
    if allowed[state] <> true then return
    body = {state: state}
    position = PorticoWatchWithFriendsNonNegativeInteger(command.positionSeconds, -1)
    if position >= 0 then body.positionSeconds = position
    PorticoWatchWithFriendsMutate(controller, "patchWatchWithFriendsGroupsGroupIdMemberState", {groupId: controller.group.id}, body, "", "member-state-failed", true)
end sub

sub PorticoWatchWithFriendsSettings(controller as object, command as object)
    if controller.group = invalid or controller.group.permissions.isHost <> true then return
    body = {expectedRevision: controller.group.revision, idempotencyKey: PorticoWatchWithFriendsIdempotencyKey(controller, "settings")}
    if command.shuffleEnabled <> invalid then body.shuffleEnabled = command.shuffleEnabled = true
    repeatMode = LCase(PorticoCoreSafeText(command.repeatMode, 8))
    if repeatMode = "none" or repeatMode = "one" or repeatMode = "all" then body.repeatMode = repeatMode
    if body.Count() <= 2 then return
    PorticoWatchWithFriendsMutate(controller, "patchWatchWithFriendsGroupsGroupIdSettings", {groupId: controller.group.id}, body, "", "settings-failed", true)
end sub

sub PorticoWatchWithFriendsQueueAdd(controller as object, command as object)
    if controller.group = invalid or controller.group.permissions.canManageQueue <> true then return
    mediaId = PorticoViewerScopeOpaqueId(command.mediaId, 128)
    if mediaId = "" then return
    body = {mediaId: mediaId, expectedRevision: controller.group.revision, idempotencyKey: PorticoWatchWithFriendsIdempotencyKey(controller, "queue-add")}
    PorticoWatchWithFriendsMutate(controller, "postWatchWithFriendsGroupsGroupIdQueue", {groupId: controller.group.id}, body, "", "queue-failed", true)
end sub

sub PorticoWatchWithFriendsQueueReorder(controller as object, command as object)
    if controller.group = invalid or controller.group.permissions.canManageQueue <> true then return
    entryId = PorticoViewerScopeOpaqueId(command.entryId, 128)
    destinationEntryId = PorticoViewerScopeOpaqueId(command.destinationEntryId, 128)
    placement = LCase(PorticoCoreSafeText(command.placement, 8))
    if entryId = "" or destinationEntryId = "" or entryId = destinationEntryId or (placement <> "before" and placement <> "after") then return
    body = {entryId: entryId, destinationEntryId: destinationEntryId, placement: placement, expectedRevision: controller.group.revision, idempotencyKey: PorticoWatchWithFriendsIdempotencyKey(controller, "queue-order")}
    PorticoWatchWithFriendsMutate(controller, "patchWatchWithFriendsGroupsGroupIdQueue", {groupId: controller.group.id}, body, "", "queue-failed", true)
end sub

sub PorticoWatchWithFriendsQueueRemove(controller as object, command as object)
    if controller.group = invalid or controller.group.permissions.canManageQueue <> true then return
    entryId = PorticoViewerScopeOpaqueId(command.entryId, 128)
    if entryId = "" then return
    query = PorticoWatchWithFriendsRevisionQuery(controller, "queue-remove")
    PorticoWatchWithFriendsMutate(controller, "deleteWatchWithFriendsGroupsGroupIdQueueEntryId", {groupId: controller.group.id, entryId: entryId}, invalid, query, "queue-failed", true)
end sub

sub PorticoWatchWithFriendsLocalPlayback(controller as object, command as object)
    mediaId = PorticoViewerScopeOpaqueId(command.mediaId, 128)
    if mediaId = "" then return
    controller.localPlayback = {
        mediaId: mediaId,
        positionSeconds: PorticoWatchWithFriendsNonNegativeInteger(command.positionSeconds, 0),
        paused: command.paused = true,
        buffering: command.buffering = true
    }
    if controller.group <> invalid then PorticoWatchWithFriendsApplySync(controller)
end sub

sub PorticoWatchWithFriendsMutate(controller as object, operationId as string, inputs as object, body as dynamic, query as string, failureCode as string, retainGroup as boolean)
    if controller.mutationInFlight or controller.serverStatus <> "online" then return
    controller.mutationInFlight = true
    controller.status = "working"
    controller.errorCode = ""
    PorticoWatchWithFriendsPublish(controller)
    response = PorticoWatchWithFriendsRequest(controller, operationId, inputs, body, query)
    controller.mutationInFlight = false
    if response.interrupted then return
    if not response.ok
        PorticoWatchWithFriendsFailure(controller, response, failureCode)
        return
    end if
    group = PorticoWatchWithFriendsGroup(response.data)
    if group = invalid
        PorticoWatchWithFriendsSetError(controller, "response-incompatible")
        return
    end if
    if retainGroup
        PorticoWatchWithFriendsAdoptGroup(controller, group)
    else
        PorticoWatchWithFriendsFence(controller, "group-ended")
        controller.groups = []
        controller.status = "ready"
        PorticoWatchWithFriendsLoadGroups(controller)
    end if
end sub

sub PorticoWatchWithFriendsAdoptGroup(controller as object, group as object)
    if controller.group = invalid or controller.group.id <> group.id then controller.longPollQuarantined = false
    controller.group = group
    controller.selectedGroupId = group.id
    controller.status = "active"
    controller.errorCode = ""
    PorticoWatchWithFriendsApplySync(controller)
    PorticoWatchWithFriendsReconcileTransport(controller)
    PorticoWatchWithFriendsPublish(controller)
end sub

sub PorticoWatchWithFriendsApplySync(controller as object)
    if controller.group = invalid then return
    result = PorticoWatchWithFriendsSync(controller.syncState, controller.group, controller.localPlayback, controller.clock.TotalSeconds())
    controller.syncState = result.state
    controller.syncDirective = result.action
end sub

sub PorticoWatchWithFriendsReconcileTransport(controller as object)
    if controller.group = invalid or controller.serverStatus <> "online" then return
    capabilities = PorticoWatchWithFriendsTransportCapabilities(controller, controller.capabilities)
    if controller.longPollQuarantined then capabilities.longPollAdvertised = false
    if controller.transport = invalid or controller.transport.resourceId <> controller.group.id or not PorticoViewerScopeEquals(controller.transport.viewerScope, controller.viewerScope)
        if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, "replaced")
        controller.transport = PorticoEventTransportCreate(controller.viewerScope, "watch-with-friends", controller.group.id, capabilities, controller.clock.TotalSeconds())
        if controller.transport <> invalid and controller.transport.mode = "bounded-refresh" then controller.transport.nextAttemptAt = controller.clock.TotalSeconds() + controller.transport.refreshIntervalSeconds
    else
        PorticoEventTransportReconcileCapabilities(controller.transport, capabilities, controller.viewerScope, controller.clock.TotalSeconds())
    end if
end sub

sub PorticoWatchWithFriendsTick(controller as object)
    if controller.longPollRequest <> invalid
        completed = PorticoWatchWithFriendsPollLongRequest(controller)
        if completed = invalid then return
        PorticoWatchWithFriendsHandleLongPollResponse(controller, completed.transportRequest, completed.response)
        return
    end if
    if controller.transport = invalid or controller.serverStatus <> "online" or controller.group = invalid or controller.mutationInFlight then return
    now = controller.clock.TotalSeconds()
    if controller.transport.resetPending
        if now >= controller.resetRetryAt then PorticoWatchWithFriendsAuthoritativeReset(controller)
        return
    end if
    request = PorticoEventTransportBeginRequest(controller.transport, controller.viewerScope, now)
    if not request.ok then return
    if request.requestKind = "long-poll"
        query = PorticoWatchWithFriendsPollQuery(request)
        if query = invalid
            PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_cursor", 0, controller.clock.TotalSeconds())
            return
        end if
        if not PorticoWatchWithFriendsBeginLongRequest(controller, request, query)
            PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "transport_error", 0, controller.clock.TotalSeconds())
        end if
        return
    end if
    response = PorticoWatchWithFriendsRequest(controller, "getWatchWithFriendsGroupsGroupId", {groupId: controller.group.id}, invalid, "")
    if response.interrupted
        PorticoEventTransportAbandonRequest(controller.transport, request, controller.viewerScope, controller.clock.TotalSeconds())
        return
    end if
    if not response.ok
        retryAfter = response.retryAfterSeconds
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, response.code, retryAfter, controller.clock.TotalSeconds())
        controller.status = "reconnecting"
        controller.errorCode = ""
        controller.syncDirective = invalid
        PorticoWatchWithFriendsPublish(controller)
        return
    end if
    group = PorticoWatchWithFriendsGroup(response.data)
    if group = invalid
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_response", 0, controller.clock.TotalSeconds())
        return
    end if
    accepted = PorticoEventTransportAcceptResponse(controller.transport, request, response.data, controller.viewerScope, controller.clock.TotalSeconds())
    if not accepted.accepted then return
    controller.group = group
    controller.status = "active"
    controller.errorCode = ""
    PorticoWatchWithFriendsApplySync(controller)
    PorticoWatchWithFriendsPublish(controller)
end sub

sub PorticoWatchWithFriendsHandleLongPollResponse(controller as object, request as object, response as object)
    if response.interrupted
        PorticoEventTransportAbandonRequest(controller.transport, request, controller.viewerScope, controller.clock.TotalSeconds())
        return
    end if
    if not response.ok
        failureCode = PorticoWatchWithFriendsTransportFailureCode(response)
        failed = PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, failureCode, response.retryAfterSeconds, controller.clock.TotalSeconds())
        if failed.terminal = true
            PorticoWatchWithFriendsFailure(controller, response, "group-unavailable")
        else if not response.retryable
            PorticoWatchWithFriendsQuarantineLongPoll(controller)
        end if
        return
    end if
    validatedEnvelope = PorticoEventTransportEnvelope(response.data)
    if validatedEnvelope = invalid
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_response", 0, controller.clock.TotalSeconds())
        PorticoWatchWithFriendsQuarantineLongPoll(controller)
        return
    end if
    latest = PorticoWatchWithFriendsLatestEventGroup(validatedEnvelope.events, controller.group.id)
    if latest = invalid and validatedEnvelope.events.Count() > 0
        PorticoEventTransportFailRequest(controller.transport, request, controller.viewerScope, "invalid_response", 0, controller.clock.TotalSeconds())
        PorticoWatchWithFriendsQuarantineLongPoll(controller)
        return
    end if
    accepted = PorticoEventTransportAcceptResponse(controller.transport, request, response.data, controller.viewerScope, controller.clock.TotalSeconds())
    if not accepted.accepted then return
    if accepted.directive = "authoritative-refetch"
        PorticoWatchWithFriendsAuthoritativeReset(controller)
        return
    end if
    if latest <> invalid
        controller.group = latest
        controller.status = "active"
        controller.errorCode = ""
        PorticoWatchWithFriendsApplySync(controller)
        PorticoWatchWithFriendsPublish(controller)
    end if
end sub

sub PorticoWatchWithFriendsAuthoritativeReset(controller as object)
    response = PorticoWatchWithFriendsRequest(controller, "getWatchWithFriendsGroupsGroupId", {groupId: controller.group.id}, invalid, "")
    if response.interrupted
        controller.resetRetryAt = controller.clock.TotalSeconds() + 1
        return
    end if
    if not response.ok
        if response.status = 401 or response.status = 403 or response.status = 404 or response.code = "authorization_revision_changed"
            PorticoEventTransportCancel(controller.transport, PorticoWatchWithFriendsTransportFailureCode(response))
            controller.transport = invalid
            PorticoWatchWithFriendsFailure(controller, response, "group-unavailable")
            return
        end if
        controller.resetRetryAt = controller.clock.TotalSeconds() + 5
        return
    end if
    group = PorticoWatchWithFriendsGroup(response.data)
    if group = invalid
        controller.resetRetryAt = controller.clock.TotalSeconds() + 5
        return
    end if
    controller.group = group
    if not PorticoEventTransportAcknowledgeReset(controller.transport, controller.viewerScope) then return
    controller.resetRetryAt = 0
    controller.status = "active"
    controller.errorCode = ""
    PorticoWatchWithFriendsApplySync(controller)
    PorticoWatchWithFriendsPublish(controller)
end sub

function PorticoWatchWithFriendsLatestEventGroup(events as dynamic, expectedGroupId as string) as dynamic
    if events = invalid or GetInterface(events, "ifArray") = invalid or events.Count() > 100 then return invalid
    latest = invalid
    for each eventValue in events
        if not PorticoWatchWithFriendsEventGroupExact(eventValue) then return invalid
        group = PorticoWatchWithFriendsGroup(eventValue)
        if group = invalid or group.id <> expectedGroupId then return invalid
        latest = group
    end for
    return latest
end function

function PorticoWatchWithFriendsEventGroupExact(value as dynamic) as boolean
    if value = invalid or Type(value) <> "roAssociativeArray" or value.Count() <> 23 then return false
    allowed = {id: true, name: true, ownerProfileId: true, ownerName: true, mediaId: true, currentEntryId: true, mediaTitle: true, state: true, positionSeconds: true, positionUpdatedAt: true, serverTime: true, playbackRate: true, revision: true, playbackRevision: true, reconnectGeneration: true, permissions: true, shuffleEnabled: true, repeatMode: true, command: true, members: true, queue: true, createdAt: true, updatedAt: true}
    for each key in value
        if allowed[key] <> true then return false
    end for
    return true
end function

sub PorticoWatchWithFriendsQuarantineLongPoll(controller as object)
    if controller.longPollRequest <> invalid and controller.longPollRequest.transfer <> invalid then controller.longPollRequest.transfer.AsyncCancel()
    controller.longPollRequest = invalid
    controller.longPollQuarantined = true
    if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, "protocol-incompatible")
    controller.transport = PorticoEventTransportCreate(controller.viewerScope, "watch-with-friends", controller.group.id, {}, controller.clock.TotalSeconds() + 5)
end sub

function PorticoWatchWithFriendsPollQuery(request as object) as dynamic
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return invalid
    waitSeconds = PorticoHttpInteger(request.waitSeconds, 0)
    if waitSeconds < 0 then waitSeconds = 0
    if waitSeconds > 25 then waitSeconds = 25
    query = "?waitSeconds=" + waitSeconds.ToStr()
    rawCursor = request.cursor
    cursor = PorticoEventTransportOpaqueCursor(rawCursor)
    if PorticoCoreSafeText(rawCursor, 4096) <> "" and cursor = "" then return invalid
    if cursor <> "" then query = query + "&cursor=" + transfer.Escape(cursor)
    return query
end function

function PorticoWatchWithFriendsTransportFailureCode(response as object) as string
    if response.status = 401 then return "authentication_required"
    if response.status = 403 then return "forbidden"
    if response.status = 404 then return "not_found"
    return response.code
end function

sub PorticoWatchWithFriendsRefreshGroup(controller as object, reconcileTransport as boolean)
    if controller.selectedGroupId = "" then return
    response = PorticoWatchWithFriendsRequest(controller, "getWatchWithFriendsGroupsGroupId", {groupId: controller.selectedGroupId}, invalid, "")
    if response.interrupted then return
    if not response.ok
        PorticoWatchWithFriendsFailure(controller, response, "group-unavailable")
        return
    end if
    group = PorticoWatchWithFriendsGroup(response.data)
    if group = invalid
        PorticoWatchWithFriendsSetError(controller, "response-incompatible")
        return
    end if
    controller.group = group
    controller.status = "active"
    controller.errorCode = ""
    PorticoWatchWithFriendsApplySync(controller)
    if reconcileTransport then PorticoWatchWithFriendsReconcileTransport(controller)
    PorticoWatchWithFriendsPublish(controller)
end sub

function PorticoWatchWithFriendsRequest(controller as object, operationId as string, inputs as object, body as dynamic, query as string, timeoutMs = 15000 as integer) as object
    session = PorticoWatchWithFriendsSession(controller)
    if session = invalid then return PorticoWatchWithFriendsHttpFailure(0, false, "server_session_required", 0)
    operation = PorticoWatchWithFriendsOperation(controller, operationId, inputs)
    if not operation.ok then return PorticoWatchWithFriendsHttpFailure(0, false, operation.code, 0)
    path = "/api" + operation.path + query
    request = PorticoHttpNormalizeRequest({
        method: operation.method,
        url: session.apiBaseUrl + path,
        body: body,
        headers: {Authorization: "Bearer " + session.accessToken},
        timeoutMs: timeoutMs,
        expectJson: true,
        allowInsecureLan: session.allowInsecureLan = true
    })
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoWatchWithFriendsHttpFailure(0, false, validation.code, 0)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoWatchWithFriendsHttpFailure(0, true, "transport_error", 0)
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoWatchWithFriendsHttpFailure(0, true, "transport_error", 0)
    if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return PorticoWatchWithFriendsHttpFailure(0, true, "transport_error", 0)
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return PorticoWatchWithFriendsHttpFailure(0, false, "invalid_header", 0)
    end for
    if request.method = "GET"
        issued = transfer.AsyncGetToString()
    else
        issued = transfer.AsyncPostFromString(request.body)
    end if
    if not issued then return PorticoWatchWithFriendsHttpFailure(0, true, "transport_error", 0)
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoWatchWithFriendsInterrupted(controller)
            transfer.AsyncCancel()
            return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "cancelled", retryAfterSeconds: 0}
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            if PorticoWatchWithFriendsInterrupted(controller) or not PorticoWatchWithFriendsSessionStillCurrent(controller, session) then return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "session_fenced", retryAfterSeconds: 0}
            status = message.GetResponseCode()
            headers = PorticoHttpResponseHeaders(message.GetResponseHeadersArray())
            retryAfter = 0
            if headers <> invalid then retryAfter = PorticoHttpInteger(headers["retry-after"], 0)
            classification = PorticoHttpClassifyStatus(status)
            if classification.classification <> "success" then return PorticoWatchWithFriendsHttpFailure(status, classification.retryable, classification.classification, retryAfter)
            payload = message.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoWatchWithFriendsHttpFailure(status, false, "response_too_large", 0)
            parsed = PorticoHttpParseJson(payload)
            if not parsed.ok then return PorticoWatchWithFriendsHttpFailure(status, false, "parse_error", 0)
            return {interrupted: false, ok: true, status: status, retryable: false, data: parsed.value, code: "", retryAfterSeconds: 0}
        end if
    end while
    transfer.AsyncCancel()
    return PorticoWatchWithFriendsHttpFailure(0, true, "timeout", 0)
end function

function PorticoWatchWithFriendsBeginLongRequest(controller as object, transportRequest as object, query as string) as boolean
    if controller.longPollRequest <> invalid then return false
    session = PorticoWatchWithFriendsSession(controller)
    if session = invalid then return false
    operation = PorticoWatchWithFriendsOperation(controller, "pollWatchWithFriendsGroupEvents", {groupId: controller.group.id})
    if not operation.ok then return false
    request = PorticoHttpNormalizeRequest({
        method: operation.method,
        url: session.apiBaseUrl + "/api" + operation.path + query,
        body: invalid,
        headers: {Authorization: "Bearer " + session.accessToken},
        timeoutMs: 35000,
        expectJson: true,
        allowInsecureLan: session.allowInsecureLan = true
    })
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return false
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return false
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if Left(LCase(request.url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") or not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return false
    end if
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return false
    end for
    if not transfer.AsyncGetToString() then return false
    controller.longPollRequest = {
        transfer: transfer,
        port: port,
        identity: transfer.GetIdentity(),
        deadlineAt: controller.clock.TotalSeconds() + 35,
        session: session,
        viewerScope: controller.viewerScope,
        transportRequest: transportRequest
    }
    return true
end function

function PorticoWatchWithFriendsPollLongRequest(controller as object) as dynamic
    pending = controller.longPollRequest
    if pending = invalid then return invalid
    if not PorticoViewerScopeEquals(pending.viewerScope, controller.viewerScope) or not PorticoWatchWithFriendsSessionStillCurrent(controller, pending.session)
        pending.transfer.AsyncCancel()
        controller.longPollRequest = invalid
        return {transportRequest: pending.transportRequest, response: {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "session_fenced", retryAfterSeconds: 0}}
    end if
    message = pending.port.GetMessage()
    if message = invalid
        if controller.clock.TotalSeconds() < pending.deadlineAt then return invalid
        pending.transfer.AsyncCancel()
        controller.longPollRequest = invalid
        return {transportRequest: pending.transportRequest, response: PorticoWatchWithFriendsHttpFailure(0, true, "timeout", 0)}
    end if
    if Type(message) <> "roUrlEvent" or message.GetSourceIdentity() <> pending.identity then return invalid
    controller.longPollRequest = invalid
    status = message.GetResponseCode()
    headers = PorticoHttpResponseHeaders(message.GetResponseHeadersArray())
    retryAfter = 0
    if headers <> invalid then retryAfter = PorticoHttpInteger(headers["retry-after"], 0)
    classification = PorticoHttpClassifyStatus(status)
    if classification.classification <> "success"
        response = PorticoWatchWithFriendsHttpFailure(status, classification.retryable, classification.classification, retryAfter)
    else
        payload = message.GetString()
        if Len(payload) > PorticoHttpLimits().maximumResponseBytes
            response = PorticoWatchWithFriendsHttpFailure(status, false, "response_too_large", 0)
        else
            parsed = PorticoHttpParseJson(payload)
            if parsed.ok
                response = {interrupted: false, ok: true, status: status, retryable: false, data: parsed.value, code: "", retryAfterSeconds: 0}
            else
                response = PorticoWatchWithFriendsHttpFailure(status, false, "parse_error", 0)
            end if
        end if
    end if
    return {transportRequest: pending.transportRequest, response: response}
end function

function PorticoWatchWithFriendsHttpFailure(status as integer, retryable as boolean, code as string, retryAfter as integer) as object
    return {interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: code, retryAfterSeconds: retryAfter}
end function

function PorticoWatchWithFriendsRevisionQuery(controller as object, operation as string) as string
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid or controller.group = invalid then return ""
    key = PorticoWatchWithFriendsIdempotencyKey(controller, operation)
    return "?expectedRevision=" + controller.group.revision.ToStr() + "&idempotencyKey=" + transfer.Escape(key)
end function

sub PorticoWatchWithFriendsFailure(controller as object, response as object, fallback as string)
    if response.status = 401
        PorticoWatchWithFriendsSetError(controller, "server-session-required")
    else if response.status = 403
        PorticoWatchWithFriendsSetError(controller, "not-permitted")
    else if response.status = 404
        PorticoWatchWithFriendsSetError(controller, "group-unavailable")
    else if response.status = 409
        controller.errorCode = "group-changed"
        controller.status = "reconnecting"
        PorticoWatchWithFriendsPublish(controller)
        PorticoWatchWithFriendsRefreshGroup(controller, true)
    else if response.retryable
        controller.status = "reconnecting"
        controller.errorCode = ""
        controller.syncDirective = invalid
        PorticoWatchWithFriendsPublish(controller)
    else
        PorticoWatchWithFriendsSetError(controller, fallback)
    end if
end sub

sub PorticoWatchWithFriendsSetError(controller as object, code as string)
    controller.status = "error"
    controller.errorCode = PorticoCoreSafeIdentifier(code, 80)
    controller.syncDirective = invalid
    PorticoWatchWithFriendsPublish(controller)
end sub

sub PorticoWatchWithFriendsFence(controller as object, reason as string)
    if controller.longPollRequest <> invalid and controller.longPollRequest.transfer <> invalid then controller.longPollRequest.transfer.AsyncCancel()
    controller.longPollRequest = invalid
    if controller.transport <> invalid then PorticoEventTransportCancel(controller.transport, reason)
    controller.transport = invalid
    controller.groups = []
    controller.group = invalid
    controller.selectedGroupId = ""
    controller.localPlayback = invalid
    controller.syncState = invalid
    controller.syncDirective = invalid
    controller.mutationInFlight = false
    controller.longPollQuarantined = false
    controller.capabilitiesLoaded = false
    controller.capabilities = {}
    controller.status = "idle"
    controller.errorCode = ""
end sub

sub PorticoWatchWithFriendsPublish(controller as object)
    projection = {
        watchWithFriendsStatus: controller.status,
        watchWithFriendsErrorCode: controller.errorCode,
        groups: controller.groups,
        controlsEnabled: false,
        groupConnected: false,
        authority: "independent",
        syncDirective: controller.syncDirective
    }
    if controller.group <> invalid
        projection.group = controller.group
        projection.controlsEnabled = controller.group.permissions.canControl = true and controller.status = "active"
        projection.groupConnected = controller.status = "active"
        if controller.group.permissions.canControl = true
            projection.authority = "host"
        else
            projection.authority = "participant"
        end if
    end if
    envelope = PorticoWatchWithFriendsResultEnvelope(controller, projection)
    if envelope <> invalid then m.top.projectionEnvelope = envelope
end sub
