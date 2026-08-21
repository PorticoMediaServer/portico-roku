function PorticoWatchWithFriendsTaskState() as object
    return {
        envelopeMode: false,
        viewerScope: invalid,
        viewerGeneration: 0,
        activeOperationSequence: 0,
        publicationSequence: 0,
        operationContract: invalid,
        activeCommandKind: ""
    }
end function

sub PorticoWatchWithFriendsTaskAdopt(target as object, state as object)
    for each key in state
        target[key] = state[key]
    end for
end sub

function PorticoWatchWithFriendsAcceptCommand(controller as object, envelope as dynamic) as dynamic
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" or envelope.version <> 1 then return invalid
    if LCase(PorticoCoreSafeIdentifier(envelope.domain, 64)) <> "watch-with-friends" then return invalid
    scope = PorticoViewerScopeNormalize(envelope.viewerScope)
    generation = PorticoViewerScopePositiveInteger(envelope.viewerGeneration)
    sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    command = envelope.command
    if scope = invalid or generation <> scope.viewerGeneration or sequence < 1 or command = invalid or Type(command) <> "roAssociativeArray" then return invalid

    currentScope = PorticoViewerScopeNormalize(controller.viewerScope)
    changedViewer = currentScope = invalid or not PorticoViewerScopeEquals(currentScope, scope)
    if controller.envelopeMode
        if generation < controller.viewerGeneration then return invalid
        if generation = controller.viewerGeneration and changedViewer then return invalid
        if generation = controller.viewerGeneration and sequence <= controller.activeOperationSequence then return invalid
    end if
    loaded = PorticoOperationContractLoad()
    if not loaded.ok then return invalid
    if changedViewer or generation <> controller.viewerGeneration
        controller.viewerScope = scope
        controller.viewerGeneration = generation
        controller.activeOperationSequence = 0
        controller.lastCommandSequence = 0
    end if
    controller.operationContract = loaded.value
    controller.envelopeMode = true
    controller.activeOperationSequence = sequence
    controller.publicationSequence = 0
    controller.activeCommandKind = LCase(PorticoCoreSafeIdentifier(command.kind, 80))
    accepted = {}
    for each key in command
        accepted[key] = command[key]
    end for
    accepted.sequence = sequence
    accepted.viewerGeneration = generation
    accepted.selectedServerId = scope.serverId
    return accepted
end function

function PorticoWatchWithFriendsSession(controller as object) as dynamic
    expected = PorticoViewerScopeNormalize(controller.viewerScope)
    if expected = invalid or expected.viewerGeneration <> controller.viewerGeneration then return invalid
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid then return invalid
    stored = PorticoServerSessionStored(record.payload)
    if stored = invalid then return invalid
    actual = PorticoServerSessionScope(stored, expected.viewerGeneration)
    if actual = invalid or not PorticoViewerScopeEquals(actual, expected) then return invalid
    projection = PorticoServerSessionRequestProjection(stored, expected, record.generation)
    if projection = invalid then return invalid
    projection.generation = record.generation
    return projection
end function

function PorticoWatchWithFriendsSessionStillCurrent(controller as object, expected as dynamic) as boolean
    current = PorticoWatchWithFriendsSession(controller)
    return current <> invalid and expected <> invalid and current.registryGeneration = expected.registryGeneration and PorticoViewerScopeEquals(current.viewerScope, expected.viewerScope)
end function

function PorticoWatchWithFriendsResultEnvelope(controller as object, projection as object) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if not controller.envelopeMode or scope = invalid or controller.activeOperationSequence < 1 then return invalid
    if controller.publicationSequence >= 2147483646 then return invalid
    controller.publicationSequence = controller.publicationSequence + 1
    return {
        version: 1,
        domain: "watch-with-friends",
        viewerGeneration: controller.viewerGeneration,
        viewerScope: scope,
        operationSequence: controller.activeOperationSequence,
        publicationSequence: controller.publicationSequence,
        projection: projection
    }
end function

function PorticoWatchWithFriendsInterrupted(controller as object) as boolean
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return false
    generation = PorticoViewerScopePositiveInteger(envelope.viewerGeneration)
    sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    if generation <> controller.viewerGeneration then return true
    return sequence > controller.activeOperationSequence
end function

function PorticoWatchWithFriendsOperation(controller as object, operationId as string, inputs = invalid as dynamic) as object
    if controller.operationContract = invalid then return {ok: false, code: "operation_contract_unavailable", path: "", method: ""}
    return PorticoOperationContractResolvePath(controller.operationContract, "server", operationId, inputs)
end function

function PorticoWatchWithFriendsGroup(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(value.id, 128)
    mediaId = PorticoViewerScopeOpaqueId(value.mediaId, 128)
    name = PorticoWatchWithFriendsText(value.name, 120)
    mediaTitle = PorticoWatchWithFriendsText(value.mediaTitle, 180)
    state = LCase(PorticoCoreSafeText(value.state, 16))
    if id = "" or mediaId = "" or name = "" or mediaTitle = "" then return invalid
    if state <> "paused" and state <> "playing" and state <> "stopped" then return invalid
    revision = PorticoWatchWithFriendsNonNegativeInteger(value.revision, -1)
    playbackRevision = PorticoWatchWithFriendsNonNegativeInteger(value.playbackRevision, -1)
    reconnectGeneration = PorticoWatchWithFriendsNonNegativeInteger(value.reconnectGeneration, -1)
    position = PorticoWatchWithFriendsNonNegativeInteger(value.positionSeconds, -1)
    playbackRate = PorticoWatchWithFriendsRate(value.playbackRate)
    if revision < 0 or playbackRevision < 0 or reconnectGeneration < 0 or position < 0 or playbackRate = invalid then return invalid
    permissions = value.permissions
    if permissions = invalid or Type(permissions) <> "roAssociativeArray" then return invalid
    command = PorticoWatchWithFriendsCommand(value.command)
    members = PorticoWatchWithFriendsMembers(value.members)
    queue = PorticoWatchWithFriendsQueue(value.queue)
    if members = invalid or queue = invalid then return invalid
    repeatMode = LCase(PorticoCoreSafeText(value.repeatMode, 8))
    if repeatMode <> "none" and repeatMode <> "one" and repeatMode <> "all" then repeatMode = "none"
    return {
        id: id,
        name: name,
        ownerName: PorticoWatchWithFriendsText(value.ownerName, 120),
        mediaId: mediaId,
        mediaTitle: mediaTitle,
        state: state,
        positionSeconds: position,
        positionUpdatedAt: PorticoCoreSafeText(value.positionUpdatedAt, 64),
        serverTime: PorticoCoreSafeText(value.serverTime, 64),
        playbackRate: playbackRate,
        revision: revision,
        playbackRevision: playbackRevision,
        reconnectGeneration: reconnectGeneration,
        permissions: {isHost: permissions.isHost = true, canControl: permissions.canControl = true, canManageQueue: permissions.canManageQueue = true},
        shuffleEnabled: value.shuffleEnabled = true,
        repeatMode: repeatMode,
        command: command,
        members: members,
        queue: queue
    }
end function

function PorticoWatchWithFriendsGroups(value as dynamic) as dynamic
    items = value
    if value <> invalid and Type(value) = "roAssociativeArray" then items = value.items
    if items = invalid or GetInterface(items, "ifArray") = invalid then return invalid
    result = []
    for each raw in items
        if result.Count() >= 100 then exit for
        group = PorticoWatchWithFriendsGroup(raw)
        if group <> invalid then result.Push(group)
    end for
    return result
end function

function PorticoWatchWithFriendsMembers(value as dynamic) as dynamic
    if value = invalid or GetInterface(value, "ifArray") = invalid then return invalid
    result = []
    for each raw in value
        if result.Count() >= 100 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoViewerScopeOpaqueId(raw.profileId, 128)
            if id = "" then id = PorticoViewerScopeOpaqueId(raw.id, 128)
            name = PorticoWatchWithFriendsText(raw.displayName, 120)
            state = LCase(PorticoCoreSafeText(raw.state, 16))
            allowed = {joined: true, ready: true, buffering: true, playing: true, paused: true}
            if state = "" then state = "joined"
            if id <> "" and name <> "" and allowed[state] = true
                result.Push({id: id, displayName: name, state: state, positionSeconds: PorticoWatchWithFriendsNonNegativeInteger(raw.positionSeconds, 0)})
            end if
        end if
    end for
    return result
end function

function PorticoWatchWithFriendsQueue(value as dynamic) as dynamic
    if value = invalid or GetInterface(value, "ifArray") = invalid then return invalid
    result = []
    for each raw in value
        if result.Count() >= 200 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            mediaId = PorticoViewerScopeOpaqueId(raw.mediaId, 128)
            title = PorticoWatchWithFriendsText(raw.mediaTitle, 180)
            order = PorticoWatchWithFriendsNonNegativeInteger(raw.sortOrder, -1)
            if mediaId <> "" and title <> "" and order >= 0 then result.Push({mediaId: mediaId, mediaTitle: title, sortOrder: order})
        end if
    end for
    return result
end function

function PorticoWatchWithFriendsCommand(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    action = LCase(PorticoCoreSafeText(value.action, 16))
    allowed = {play: true, pause: true, seek: true, stop: true, load: true, next: true, previous: true}
    if allowed[action] <> true then return invalid
    result = {id: PorticoViewerScopeOpaqueId(value.id, 128), action: action}
    mediaId = PorticoViewerScopeOpaqueId(value.mediaId, 128)
    if mediaId <> "" then result.mediaId = mediaId
    position = PorticoWatchWithFriendsNonNegativeInteger(value.positionSeconds, -1)
    if position >= 0 then result.positionSeconds = position
    return result
end function

function PorticoWatchWithFriendsSync(previous as dynamic, group as object, local as dynamic, nowSeconds as integer) as object
    state = {revision: group.revision, playbackRevision: group.playbackRevision, reconnectGeneration: group.reconnectGeneration}
    if previous <> invalid and Type(previous) = "roAssociativeArray"
        if group.reconnectGeneration < previous.reconnectGeneration then return {state: previous, action: {type: "ignore", reason: "stale"}}
        if group.reconnectGeneration = previous.reconnectGeneration and group.revision < previous.revision then return {state: previous, action: {type: "ignore", reason: "stale"}}
    end if
    target = group.positionSeconds
    if group.state = "playing"
        anchor = PorticoWatchWithFriendsISOSeconds(group.positionUpdatedAt)
        server = PorticoWatchWithFriendsISOSeconds(group.serverTime)
        if anchor >= 0 and server >= anchor then target = target + Int((server - anchor) * group.playbackRate)
    end if
    if local = invalid or Type(local) <> "roAssociativeArray" or PorticoViewerScopeOpaqueId(local.mediaId, 128) <> group.mediaId
        return {state: state, action: {type: "load", mediaId: group.mediaId, positionSeconds: target, paused: group.state <> "playing"}}
    end if
    if local.buffering = true then return {state: state, action: {type: "ignore", reason: "buffering"}}
    localPosition = PorticoWatchWithFriendsNonNegativeInteger(local.positionSeconds, 0)
    drift = target - localPosition
    absoluteDrift = Abs(drift)
    if absoluteDrift >= 3 then return {state: state, action: {type: "seek", positionSeconds: target, paused: group.state <> "playing", driftSeconds: drift}}
    paused = local.paused = true
    if group.state = "paused" and not paused then return {state: state, action: {type: "pause"}}
    if group.state = "playing" and paused then return {state: state, action: {type: "play"}}
    if group.state = "playing" and absoluteDrift >= 1
        rate = group.playbackRate + (drift * 0.025)
        if rate < 0.9 then rate = 0.9
        if rate > 1.1 then rate = 1.1
        return {state: state, action: {type: "rate", playbackRate: rate, durationMs: 4000, driftSeconds: drift}}
    end if
    return {state: state, action: {type: "none", driftSeconds: drift}}
end function

function PorticoWatchWithFriendsSupportsLongPoll(operationContract as dynamic) as boolean
    if operationContract = invalid or Type(operationContract) <> "roAssociativeArray" or GetInterface(operationContract.operations, "ifArray") = invalid then return false
    for each operation in operationContract.operations
        if operation <> invalid and Type(operation) = "roAssociativeArray" and operation.operationId = "pollWatchWithFriendsGroupEvents" and operation.service = "server" and operation.method = "GET" and operation.path = "/watch-with-friends/groups/{groupId}/events/poll" and PorticoOperationContractRecordAllowed(operation) then return true
    end for
    return false
end function

function PorticoWatchWithFriendsTransportCapabilities(controller as object, value as dynamic) as object
    capabilities = PorticoEventTransportCapabilities(value)
    if not PorticoWatchWithFriendsSupportsLongPoll(controller.operationContract) then capabilities.longPollAdvertised = false
    return capabilities
end function

function PorticoWatchWithFriendsIdempotencyKey(controller as object, operation as string) as string
    op = PorticoCoreSafeIdentifier(operation, 40)
    if op = "" then op = "mutation"
    return "roku-" + controller.viewerGeneration.ToStr() + "-" + controller.activeOperationSequence.ToStr() + "-" + op
end function

function PorticoWatchWithFriendsText(value as dynamic, maximum as integer) as string
    return PorticoCoreSafeText(value, maximum)
end function

function PorticoWatchWithFriendsNonNegativeInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    kind = LCase(Type(value))
    if kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" then return fallback
    number = Int(value)
    if number < 0 or number >= 2147480000 then return fallback
    return number
end function

function PorticoWatchWithFriendsRate(value as dynamic) as dynamic
    kind = LCase(Type(value))
    if kind <> "float" and kind <> "rofloat" and kind <> "double" and kind <> "rodouble" and kind <> "integer" and kind <> "roint" then return invalid
    rate = value * 1.0
    if rate < 0.5 or rate > 2 then return invalid
    return rate
end function

function PorticoWatchWithFriendsISOSeconds(value as dynamic) as integer
    text = PorticoCoreSafeText(value, 64)
    if text = "" then return -1
    date = CreateObject("roDateTime")
    if date = invalid or not date.FromISO8601String(text) then return -1
    return date.AsSeconds()
end function
