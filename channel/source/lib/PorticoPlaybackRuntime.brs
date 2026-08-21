function PorticoPlaybackTaskState() as object
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

sub PorticoPlaybackTaskAdopt(target as object, state as object)
    for each key in state
        target[key] = state[key]
    end for
end sub

function PorticoPlaybackAcceptCommand(controller as object, envelope as dynamic) as dynamic
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" or envelope.version <> 1 then return invalid
    if LCase(PorticoCoreSafeIdentifier(envelope.domain, 64)) <> "playback" then return invalid
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

function PorticoPlaybackSessionForController(controller as object) as dynamic
    ' Production playback is viewer-scoped only. The pre-RC server-only fallback
    ' could read a legacy session without proving profile or generation identity.
    if controller.envelopeMode <> true then return invalid
    expected = PorticoViewerScopeNormalize(controller.viewerScope)
    if expected = invalid or expected.viewerGeneration <> controller.viewerGeneration then return invalid
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid or record.payload.signedOut = true then return invalid
    stored = PorticoServerSessionStored(record.payload)
    if stored = invalid then return invalid
    actual = PorticoServerSessionScope(stored, expected.viewerGeneration)
    if actual = invalid or not PorticoViewerScopeEquals(actual, expected) then return invalid
    projection = PorticoServerSessionRequestProjection(stored, expected, record.generation)
    if projection = invalid then return invalid
    projection.generation = record.generation
    return projection
end function

function PorticoPlaybackResultEnvelope(controller as object, projection as object) as dynamic
    if controller.envelopeMode <> true then return invalid
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if scope = invalid or scope.viewerGeneration <> controller.viewerGeneration or controller.activeOperationSequence < 1 then return invalid
    if controller.publicationSequence >= 2147483646 then return invalid
    controller.publicationSequence = controller.publicationSequence + 1
    return {
        version: 1,
        domain: "playback",
        viewerGeneration: controller.viewerGeneration,
        viewerScope: scope,
        operationSequence: controller.activeOperationSequence,
        publicationSequence: controller.publicationSequence,
        projection: projection
    }
end function

function PorticoPlaybackInterruptedByEnvelope(controller as object) as boolean
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return false
    generation = PorticoViewerScopePositiveInteger(envelope.viewerGeneration)
    sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    if generation <> controller.viewerGeneration then return true
    return sequence > controller.activeOperationSequence
end function

function PorticoPlaybackAllowedRequest(controller as object, method as string, path as string) as object
    if controller.envelopeMode <> true then return {ok: true, path: path}
    if controller.operationContract = invalid then return {ok: false, code: "operation_contract_unavailable"}
    safeMethod = UCase(PorticoCoreSafeText(method, 10))
    safePath = PorticoPlaybackSafeApiPath(path)
    if safePath = "" then return {ok: false, code: "operation_not_allowed"}
    basePath = Mid(safePath, 5)
    queryAt = Instr(1, basePath, "?")
    if queryAt > 0 then basePath = Left(basePath, queryAt - 1)
    operationId = PorticoPlaybackOperationId(safeMethod, basePath)
    if operationId = "" then return {ok: false, code: "operation_not_allowed"}
    operation = PorticoOperationContractFind(controller.operationContract, "server", operationId)
    if operation = invalid or operation.method <> safeMethod then return {ok: false, code: "operation_not_allowed"}
    return {ok: true, path: safePath, operationId: operationId}
end function

function PorticoPlaybackOperationId(method as string, path as string) as string
    exact = {
        "POST /playback-sessions": "postPlaybackSessions",
        "POST /playback/active": "postPlaybackActive",
        "POST /playback/next": "postPlaybackNext",
        "POST /playback/queue": "postPlaybackQueue",
        "POST /live-tv/play": "postLiveTvPlay"
    }
    direct = exact[method + " " + path]
    if direct <> invalid then return direct
    parts = path.Tokenize("/")
    if parts.Count() = 2 and parts[0] = "playback-sessions"
        if method = "PATCH" then return "patchPlaybackSessionsSessionId"
        if method = "DELETE" then return "deletePlaybackSessionsSessionId"
    end if
    if parts.Count() = 3 and parts[0] = "playback-sessions"
        if parts[2] = "media-grant" and method = "POST" then return "postPlaybackSessionsSessionIdMediaGrant"
        if parts[2] = "renegotiate" and method = "POST" then return "renegotiatePlaybackSession"
        if parts[2] = "prepare-next" and method = "POST" then return "postPlaybackSessionsSessionIdPrepareNext"
        if parts[2] = "handoff" and method = "POST" then return "postPlaybackSessionsSessionIdHandoff"
        if parts[2] = "queue"
            if method = "GET" then return "getPlaybackSessionsSessionIdQueue"
            if method = "PATCH" then return "patchPlaybackSessionsSessionIdQueue"
        end if
        if parts[2] = "command"
            if method = "GET" then return "getPlaybackSessionsSessionIdCommand"
            if method = "POST" then return "postPlaybackSessionsSessionIdCommand"
        end if
    end if
    if parts.Count() = 3 and parts[0] = "dvr" and parts[1] = "recordings" and method = "POST" then return "postDvrRecordingsIdPlayback"
    if parts.Count() = 3 and parts[0] = "library-channels" and parts[2] = "tune" and method = "POST" then return "tuneLibraryChannel"
    return ""
end function

function PorticoPlaybackSafeApiPath(value as dynamic) as string
    if value = invalid then return ""
    path = value.ToStr().Trim()
    if Len(path) < 6 or Len(path) > 2048 or Left(path, 5) <> "/api/" then return ""
    if Instr(1, path, "..") > 0 or Instr(1, path, "\\") > 0 or Instr(1, path, "#") > 0 then return ""
    if Instr(1, path, Chr(0)) > 0 or Instr(1, path, Chr(10)) > 0 or Instr(1, path, Chr(13)) > 0 or Instr(1, path, " ") > 0 then return ""
    return path
end function
