function PorticoEventTransportCapabilities(value as dynamic) as object
    result = {
        longPollAdvertised: false,
        defaultWaitSeconds: 20,
        maximumWaitSeconds: 25,
        maximumConcurrentStreams: 4
    }
    if value = invalid or GetInterface(value, "ifAssociativeArray") = invalid then return result
    source = value
    if value.capabilities <> invalid and GetInterface(value.capabilities, "ifAssociativeArray") <> invalid then source = value.capabilities

    transports = source.eventTransports
    if transports <> invalid and GetInterface(transports, "ifArray") <> invalid
        for each transportValue in transports
            transport = PorticoEventTransportToken(transportValue, 32)
            if transport = "long-poll" then result.longPollAdvertised = true
        end for
    end if

    settings = source.longPoll
    if settings <> invalid and GetInterface(settings, "ifAssociativeArray") <> invalid
        defaultWait = PorticoEventTransportInteger(settings.defaultWaitSeconds, 20)
        maximumWait = PorticoEventTransportInteger(settings.maximumWaitSeconds, 25)
        maximumStreams = PorticoEventTransportInteger(settings.maximumConcurrentStreams, 4)
        if maximumWait < 1 then maximumWait = 1
        if maximumWait > 25 then maximumWait = 25
        if defaultWait < 1 then defaultWait = 1
        if defaultWait > maximumWait then defaultWait = maximumWait
        if maximumStreams < 1 then maximumStreams = 1
        ' Roku keeps a stricter local ceiling than a server may advertise. The
        ' coordinator still owns aggregate allocation across independent Tasks.
        if maximumStreams > 4 then maximumStreams = 4
        result.defaultWaitSeconds = defaultWait
        result.maximumWaitSeconds = maximumWait
        result.maximumConcurrentStreams = maximumStreams
    end if
    return result
end function

function PorticoEventTransportMode(capabilityValue as dynamic) as string
    capabilities = PorticoEventTransportCapabilities(capabilityValue)
    if capabilities.longPollAdvertised then return "long-poll"
    return "bounded-refresh"
end function

function PorticoEventTransportCreate(scopeValue as dynamic, streamKindValue as dynamic, resourceIdValue as dynamic, capabilityValue as dynamic, nowSeconds = 0 as integer) as dynamic
    scope = PorticoViewerScopeNormalize(scopeValue)
    streamKind = PorticoEventTransportStreamKind(streamKindValue)
    resourceId = PorticoEventTransportResourceId(resourceIdValue)
    if scope = invalid or streamKind = "" then return invalid
    if PorticoEventTransportResourceRequired(streamKind) and resourceId = "" then return invalid
    if not PorticoEventTransportResourceRequired(streamKind) then resourceId = ""
    if nowSeconds < 0 then nowSeconds = 0
    capabilities = PorticoEventTransportCapabilities(capabilityValue)
    mode = PorticoEventTransportMode(capabilityValue)
    route = PorticoEventTransportRoute(streamKind, resourceId, mode)
    if mode = "long-poll" and route = "" then return invalid
    return {
        version: 1,
        viewerScope: scope,
        streamKind: streamKind,
        resourceId: resourceId,
        mode: mode,
        route: route,
        active: true,
        outstanding: false,
        requestSequence: 0,
        outstandingSequence: 0,
        cursor: "",
        cursorHistory: [],
        resetPending: false,
        drainPending: false,
        consecutiveDrainCount: 0,
        maximumConsecutiveDrains: 8,
        failureCount: 0,
        jitterSeed: PorticoEventTransportJitterSeed(scope),
        nextAttemptAt: nowSeconds,
        refreshIntervalSeconds: PorticoEventTransportRefreshInterval(streamKind),
        defaultWaitSeconds: capabilities.defaultWaitSeconds,
        maximumWaitSeconds: capabilities.maximumWaitSeconds,
        lastServerTime: "",
        terminalCode: ""
    }
end function

function PorticoEventTransportBeginRequest(state as dynamic, currentScopeValue as dynamic, nowSeconds as integer) as object
    if not PorticoEventTransportValid(state) or not state.active then return {ok: false, code: "subscription_inactive"}
    if not PorticoViewerScopeEquals(state.viewerScope, currentScopeValue) then return {ok: false, code: "viewer_scope_mismatch"}
    if state.outstanding then return {ok: false, code: "poll_already_active"}
    if state.resetPending then return {ok: false, code: "reset_required"}
    if nowSeconds < state.nextAttemptAt then return {ok: false, code: "not_due", retryAt: state.nextAttemptAt}
    if state.requestSequence >= 2147483646 then return {ok: false, code: "request_sequence_exhausted"}

    state.requestSequence = state.requestSequence + 1
    state.outstandingSequence = state.requestSequence
    state.outstanding = true
    waitSeconds = 0
    cursor = ""
    requestKind = "authoritative-refresh"
    if state.mode = "long-poll"
        requestKind = "long-poll"
        waitSeconds = state.defaultWaitSeconds
        if state.drainPending then waitSeconds = 0
        cursor = state.cursor
    end if
    return {
        ok: true,
        code: "ok",
        requestKind: requestKind,
        requestSequence: state.requestSequence,
        viewerGeneration: state.viewerScope.viewerGeneration,
        viewerScope: PorticoViewerRuntimeCloneScope(state.viewerScope),
        streamKind: state.streamKind,
        resourceId: state.resourceId,
        route: state.route,
        cursor: cursor,
        waitSeconds: waitSeconds
    }
end function

function PorticoEventTransportAcceptResponse(state as dynamic, request as dynamic, response as dynamic, currentScopeValue as dynamic, nowSeconds as integer) as object
    requestCheck = PorticoEventTransportRequestCurrent(state, request, currentScopeValue)
    if not requestCheck.ok then return {accepted: false, code: requestCheck.code}
    state.outstanding = false
    state.outstandingSequence = 0

    if state.mode = "bounded-refresh"
        state.failureCount = 0
        state.nextAttemptAt = nowSeconds + state.refreshIntervalSeconds
        return {accepted: true, code: "ok", directive: "authoritative-state", projection: response, nextAttemptAt: state.nextAttemptAt}
    end if

    envelope = PorticoEventTransportEnvelope(response)
    if envelope = invalid
        return PorticoEventTransportRecordFailure(state, "invalid_response", 0, nowSeconds)
    end if
    previousCursor = state.cursor
    cursorRepeated = previousCursor <> "" and PorticoEventTransportCursorSeen(state.cursorHistory, envelope.cursor)
    if cursorRepeated and (envelope.hasMore or envelope.events.Count() > 0)
        return PorticoEventTransportRecordFailure(state, "cursor_not_advanced", 0, nowSeconds)
    end if

    state.cursor = envelope.cursor
    PorticoEventTransportRememberCursor(state, envelope.cursor)
    state.lastServerTime = envelope.serverTime
    state.resetPending = envelope.resetRequired
    state.drainPending = envelope.hasMore
    state.failureCount = 0
    state.nextAttemptAt = nowSeconds

    if envelope.resetRequired
        state.consecutiveDrainCount = 0
        return {accepted: true, code: "ok", directive: "authoritative-refetch", cursor: state.cursor, events: [], nextAttemptAt: nowSeconds}
    end if
    if envelope.hasMore
        state.consecutiveDrainCount = state.consecutiveDrainCount + 1
        ' Preserve legitimate batches, but insert a short yield after a bounded
        ' number of zero-wait drains so a malicious hasMore chain cannot create
        ' a tight request loop across a constrained device and server.
        if state.consecutiveDrainCount >= state.maximumConsecutiveDrains
            state.consecutiveDrainCount = 0
            state.nextAttemptAt = nowSeconds + 1
        end if
        return {accepted: true, code: "ok", directive: "drain", cursor: state.cursor, events: envelope.events, nextAttemptAt: state.nextAttemptAt}
    end if
    state.consecutiveDrainCount = 0
    return {accepted: true, code: "ok", directive: "events", cursor: state.cursor, events: envelope.events, nextAttemptAt: nowSeconds}
end function

function PorticoEventTransportAcknowledgeReset(state as dynamic, currentScopeValue as dynamic) as boolean
    if not PorticoEventTransportValid(state) or not PorticoViewerScopeEquals(state.viewerScope, currentScopeValue) then return false
    state.resetPending = false
    state.drainPending = false
    state.consecutiveDrainCount = 0
    return true
end function

function PorticoEventTransportFailRequest(state as dynamic, request as dynamic, currentScopeValue as dynamic, failureCodeValue as dynamic, retryAfterSeconds = 0 as integer, nowSeconds = 0 as integer) as object
    requestCheck = PorticoEventTransportRequestCurrent(state, request, currentScopeValue)
    if not requestCheck.ok then return {accepted: false, code: requestCheck.code}
    state.outstanding = false
    state.outstandingSequence = 0
    failureCode = PorticoEventTransportToken(failureCodeValue, 80)
    if failureCode = "" then failureCode = "transport_error"

    terminal = failureCode = "authentication_required" or failureCode = "forbidden" or failureCode = "not_found" or failureCode = "authorization_revision_changed"
    if terminal
        state.active = false
        state.cursor = ""
        state.cursorHistory = []
        state.drainPending = false
        state.resetPending = false
        state.consecutiveDrainCount = 0
        state.terminalCode = failureCode
        return {accepted: true, code: failureCode, directive: "lifecycle", terminal: true}
    end if
    return PorticoEventTransportRecordFailure(state, failureCode, retryAfterSeconds, nowSeconds)
end function

function PorticoEventTransportAbandonRequest(state as dynamic, request as dynamic, currentScopeValue as dynamic, nowSeconds = 0 as integer) as boolean
    requestCheck = PorticoEventTransportRequestCurrent(state, request, currentScopeValue)
    if not requestCheck.ok then return false
    state.outstanding = false
    state.outstandingSequence = 0
    state.nextAttemptAt = nowSeconds
    return true
end function

function PorticoEventTransportRecordFailure(state as object, failureCode as string, retryAfterSeconds as integer, nowSeconds as integer) as object
    state.failureCount = state.failureCount + 1
    if state.failureCount > 10 then state.failureCount = 10
    delay = retryAfterSeconds
    if delay < 1
        exponent = state.failureCount - 1
        delay = 1
        for iteration = 1 to exponent
            delay = delay * 2
            if delay >= 30
                delay = 30
                exit for
            end if
        end for
        jitterMaximum = Int(delay / 4)
        if jitterMaximum > 0 then delay = delay + ((state.jitterSeed + state.requestSequence + state.failureCount) mod (jitterMaximum + 1))
    end if
    if delay < 1 then delay = 1
    if delay > 300 then delay = 300
    state.nextAttemptAt = nowSeconds + delay
    state.drainPending = false
    state.consecutiveDrainCount = 0
    return {accepted: true, code: failureCode, directive: "backoff", terminal: false, retryAt: state.nextAttemptAt}
end function

function PorticoEventTransportJitterSeed(scope as object) as integer
    identity = PorticoViewerScopeCanonicalIdentity(scope, false)
    seed = 0
    for index = 1 to Len(identity)
        seed = (seed + (Asc(Mid(identity, index, 1)) * index)) mod 2147480000
    end for
    if seed < 0 then seed = 0
    return seed
end function

function PorticoEventTransportReconcileCapabilities(state as dynamic, capabilityValue as dynamic, currentScopeValue as dynamic, nowSeconds as integer) as object
    if not PorticoEventTransportValid(state) or not PorticoViewerScopeEquals(state.viewerScope, currentScopeValue) then return {ok: false, code: "viewer_scope_mismatch"}
    capabilities = PorticoEventTransportCapabilities(capabilityValue)
    nextMode = PorticoEventTransportMode(capabilityValue)
    if nextMode = state.mode
        state.defaultWaitSeconds = capabilities.defaultWaitSeconds
        state.maximumWaitSeconds = capabilities.maximumWaitSeconds
        return {ok: true, code: "unchanged", mode: state.mode}
    end if

    state.mode = nextMode
    state.route = PorticoEventTransportRoute(state.streamKind, state.resourceId, nextMode)
    state.outstanding = false
    state.outstandingSequence = 0
    state.cursor = ""
    state.cursorHistory = []
    state.resetPending = nextMode = "long-poll"
    state.drainPending = false
    state.consecutiveDrainCount = 0
    state.failureCount = 0
    state.nextAttemptAt = nowSeconds
    state.defaultWaitSeconds = capabilities.defaultWaitSeconds
    state.maximumWaitSeconds = capabilities.maximumWaitSeconds
    return {ok: true, code: "capability_changed", mode: state.mode, directive: "authoritative-refetch"}
end function

sub PorticoEventTransportCancel(state as dynamic, reasonValue = "cancelled" as dynamic)
    if not PorticoEventTransportValid(state) then return
    state.active = false
    state.outstanding = false
    state.outstandingSequence = 0
    state.cursor = ""
    state.cursorHistory = []
    state.resetPending = false
    state.drainPending = false
    state.consecutiveDrainCount = 0
    state.terminalCode = PorticoEventTransportToken(reasonValue, 80)
end sub

function PorticoEventTransportRequestCurrent(state as dynamic, request as dynamic, currentScopeValue as dynamic) as object
    if not PorticoEventTransportValid(state) or not state.active then return {ok: false, code: "subscription_inactive"}
    if request = invalid or GetInterface(request, "ifAssociativeArray") = invalid then return {ok: false, code: "request_invalid"}
    if not state.outstanding then return {ok: false, code: "request_not_outstanding"}
    if PorticoViewerScopePositiveInteger(request.requestSequence) <> state.outstandingSequence then return {ok: false, code: "request_not_current"}
    if PorticoViewerScopePositiveInteger(request.viewerGeneration) <> state.viewerScope.viewerGeneration then return {ok: false, code: "viewer_generation_mismatch"}
    if not PorticoViewerScopeEquals(request.viewerScope, state.viewerScope) or not PorticoViewerScopeEquals(currentScopeValue, state.viewerScope) then return {ok: false, code: "viewer_scope_mismatch"}
    return {ok: true, code: "ok"}
end function

function PorticoEventTransportEnvelope(value as dynamic) as dynamic
    if value = invalid or GetInterface(value, "ifAssociativeArray") = invalid then return invalid
    if value.Count() <> 6 then return invalid
    allowedKeys = {version: true, cursor: true, serverTime: true, resetRequired: true, hasMore: true, events: true}
    for each key in value
        if allowedKeys[key] <> true then return invalid
    end for
    if PorticoEventTransportToken(value.version, 8) <> "v1" then return invalid
    cursor = PorticoEventTransportOpaqueCursor(value.cursor)
    serverTime = PorticoEventTransportServerTime(value.serverTime)
    if cursor = "" or serverTime = "" then return invalid
    if Type(value.resetRequired) <> "roBoolean" and Type(value.resetRequired) <> "Boolean" then return invalid
    if Type(value.hasMore) <> "roBoolean" and Type(value.hasMore) <> "Boolean" then return invalid
    if value.events = invalid or GetInterface(value.events, "ifArray") = invalid or value.events.Count() > 100 then return invalid
    if value.resetRequired and (value.events.Count() > 0 or value.hasMore) then return invalid
    events = []
    budget = {nodes: 2048, text: 524288}
    for each eventValue in value.events
        if eventValue = invalid or GetInterface(eventValue, "ifAssociativeArray") = invalid then return invalid
        if not PorticoEventTransportValueWithinBudget(eventValue, 0, budget) then return invalid
        events.Push(eventValue)
    end for
    return {cursor: cursor, serverTime: serverTime, resetRequired: value.resetRequired, hasMore: value.hasMore, events: events}
end function

function PorticoEventTransportCursorSeen(history as dynamic, cursor as string) as boolean
    if history = invalid or GetInterface(history, "ifArray") = invalid then return false
    for each prior in history
        if prior = cursor then return true
    end for
    return false
end function

sub PorticoEventTransportRememberCursor(state as object, cursor as string)
    if cursor = "" then return
    if state.cursorHistory = invalid or GetInterface(state.cursorHistory, "ifArray") = invalid then state.cursorHistory = []
    if PorticoEventTransportCursorSeen(state.cursorHistory, cursor) then return
    state.cursorHistory.Push(cursor)
    while state.cursorHistory.Count() > 16
        state.cursorHistory.Shift()
    end while
end sub

function PorticoEventTransportValueWithinBudget(value as dynamic, depth as integer, budget as object) as boolean
    if depth > 10 or budget.nodes < 1 then return false
    budget.nodes = budget.nodes - 1
    if value = invalid then return true
    valueType = LCase(Type(value))
    if valueType = "boolean" or valueType = "roboolean" or valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" or valueType = "float" or valueType = "rofloat" or valueType = "double" or valueType = "rodouble" then return true
    if valueType = "string" or valueType = "rostring"
        length = Len(value.ToStr())
        if length > 65536 or length > budget.text then return false
        budget.text = budget.text - length
        return true
    end if
    if GetInterface(value, "ifArray") <> invalid
        if value.Count() > 512 then return false
        for each item in value
            if not PorticoEventTransportValueWithinBudget(item, depth + 1, budget) then return false
        end for
        return true
    end if
    if GetInterface(value, "ifAssociativeArray") <> invalid
        if value.Count() > 128 then return false
        for each key in value
            keyText = key.ToStr()
            if Len(keyText) < 1 or Len(keyText) > 128 or Len(keyText) > budget.text then return false
            budget.text = budget.text - Len(keyText)
            if not PorticoEventTransportValueWithinBudget(value[key], depth + 1, budget) then return false
        end for
        return true
    end if
    return false
end function

function PorticoEventTransportRoute(streamKind as string, resourceId as string, mode as string) as string
    base = ""
    if streamKind = "shell"
        base = "/api/events"
    else if streamKind = "notifications"
        base = "/api/notifications/events"
    else if streamKind = "playback-commands"
        encodedResource = PorticoEventTransportEscape(resourceId)
        if encodedResource = "" then return ""
        base = "/api/playback-sessions/" + encodedResource + "/command/events"
    else if streamKind = "playback-receiver"
        encodedResource = PorticoEventTransportEscape(resourceId)
        if encodedResource = "" then return ""
        base = "/api/playback/receivers/" + encodedResource + "/events"
    else if streamKind = "watch-with-friends"
        encodedResource = PorticoEventTransportEscape(resourceId)
        if encodedResource = "" then return ""
        base = "/api/watch-with-friends/groups/" + encodedResource + "/events"
    end if
    if base <> "" and mode = "long-poll" then return base + "/poll"
    return ""
end function

function PorticoEventTransportStreamKind(value as dynamic) as string
    kind = PorticoEventTransportToken(value, 48)
    allowed = {shell: true, notifications: true, "playback-commands": true, "playback-receiver": true, "watch-with-friends": true}
    if allowed[kind] = true then return kind
    return ""
end function

function PorticoEventTransportResourceRequired(streamKind as string) as boolean
    return streamKind = "playback-commands" or streamKind = "playback-receiver" or streamKind = "watch-with-friends"
end function

function PorticoEventTransportResourceId(value as dynamic) as string
    return PorticoViewerScopeOpaqueId(value, 128)
end function

function PorticoEventTransportEscape(value as string) as string
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return ""
    return transfer.Escape(value)
end function

function PorticoEventTransportRefreshInterval(streamKind as string) as integer
    if streamKind = "watch-with-friends" then return 2
    if streamKind = "playback-commands" or streamKind = "playback-receiver" then return 5
    if streamKind = "shell" then return 30
    return 60
end function

function PorticoEventTransportOpaqueCursor(value as dynamic) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    cursor = value.ToStr()
    if Len(cursor) < 1 or Len(cursor) > 4096 then return ""
    for position = 1 to Len(cursor)
        code = Asc(Mid(cursor, position, 1))
        if code < 32 or code = 127 then return ""
    end for
    return cursor
end function

function PorticoEventTransportServerTime(value as dynamic) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    raw = value.ToStr()
    serverTime = raw.Trim()
    if raw <> serverTime then return ""
    if Len(serverTime) < 20 or Len(serverTime) > 40 then return ""
    if Mid(serverTime, 5, 1) <> "-" or Mid(serverTime, 8, 1) <> "-" or Mid(serverTime, 11, 1) <> "T" or Right(serverTime, 1) <> "Z" then return ""
    parsed = CreateObject("roDateTime")
    if parsed = invalid or not parsed.FromISO8601String(serverTime) then return ""
    return serverTime
end function

function PorticoEventTransportToken(value as dynamic, maximumLength as integer) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    normalized = LCase(value.ToStr().Trim())
    if normalized = "" or Len(normalized) > maximumLength then return ""
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoEventTransportInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" then return Int(value)
    return fallback
end function

function PorticoEventTransportValid(state as dynamic) as boolean
    return state <> invalid and GetInterface(state, "ifAssociativeArray") <> invalid and state.version = 1
end function
