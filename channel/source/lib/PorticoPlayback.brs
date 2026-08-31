function PorticoPlaybackController(port as object, viewerController = invalid as dynamic) as object
    task = CreateObject("roSGNode", "PorticoPlaybackTask")
    if task = invalid then return { task: invalid, commandSequence: 0, serverSignature: "", identity: {title: "", meta: ""} }
    task.ObserveField("projection", port)
    task.ObserveField("projectionEnvelope", port)
    task.ObserveField("contentNode", port)
    task.ObserveField("eventState", port)
    task.control = "RUN"
    return { task: task, viewerController: viewerController, envelopeMode: viewerController <> invalid, commandSequence: 0, serverSignature: "", identity: {title: "", meta: ""} }
end function

sub PorticoPlaybackSetIdentity(controller as object, identity as dynamic)
    if controller = invalid then return
    title = ""
    meta = ""
    if identity <> invalid and Type(identity) = "roAssociativeArray"
        title = PorticoCoreSafeText(identity.title, 240)
        meta = PorticoCoreSafeText(identity.meta, 240)
    end if
    controller.identity = {title: title, meta: meta}
end sub

function PorticoPlaybackIdentity(controller as dynamic) as object
    if controller = invalid or controller.identity = invalid or Type(controller.identity) <> "roAssociativeArray" then return {title: "", meta: ""}
    return {title: PorticoCoreSafeText(controller.identity.title, 240), meta: PorticoCoreSafeText(controller.identity.meta, 240)}
end function

function PorticoPlaybackViewerCommand(controller as object, viewerController as object, values as object) as boolean
    if controller = invalid or controller.task = invalid or viewerController = invalid then return false
    command = {}
    for each key in values
        if key <> "sequence" then command[key] = values[key]
    end for
    envelope = PorticoViewerRuntimeControllerCommand(viewerController, "playback", command)
    if envelope = invalid then return false
    controller.viewerController = viewerController
    controller.envelopeMode = true
    controller.task.command = {sequence: envelope.operationSequence, kind: "viewer-fence"}
    controller.task.commandEnvelope = envelope
    return true
end function

sub PorticoPlaybackAssignCommand(controller as object, command as object)
    if controller.envelopeMode
        PorticoPlaybackViewerCommand(controller, controller.viewerController, command)
    else
        controller.task.command = command
    end if
end sub

function PorticoPlaybackViewerStateChanged(controller as object, viewerController as object, state as dynamic) as boolean
    scope = PorticoViewerRuntimeControllerCurrentScope(viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    command = {
        kind: "viewer-state",
        selectedServerId: scope.serverId,
        serverStatus: LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    }
    if state.viewerPreferences <> invalid and Type(state.viewerPreferences) = "roAssociativeArray" then command.preferences = state.viewerPreferences
    return PorticoPlaybackViewerCommand(controller, viewerController, command)
end function

function PorticoPlaybackViewerPreferencesChanged(controller as object, preferencesProjection as dynamic) as boolean
    if preferencesProjection = invalid or Type(preferencesProjection) <> "roAssociativeArray" then return false
    values = preferencesProjection.values
    if values = invalid or Type(values) <> "roAssociativeArray" then return false
    return PorticoPlaybackViewerCommand(controller, controller.viewerController, {kind: "viewer-preferences", preferences: values})
end function

function PorticoPlaybackWatchAuthorityChanged(controller as object, authority as dynamic) as boolean
    normalized = LCase(PorticoCoreSafeText(authority, 16))
    if normalized <> "host" and normalized <> "participant" then normalized = "independent"
    return PorticoPlaybackViewerCommand(controller, controller.viewerController, {kind: "watch-authority", authority: normalized})
end function

function PorticoPlaybackAutomationCommand(controller as object, kind as string, values = invalid as dynamic) as boolean
    allowed = {"play-now": true, "cancel-autoplay": true, "confirm-still-watching": true, "dismiss-segment": true, "skip-segment": true, "set-speed": true, "set-sleep-timer": true, "trickplay-preview": true, "trickplay-dismiss": true}
    if allowed[kind] <> true then return false
    command = {kind: kind}
    if values <> invalid and Type(values) = "roAssociativeArray"
        if values.segmentId <> invalid then command.segmentId = values.segmentId
        if values.speed <> invalid then command.speed = values.speed
        if values.mode <> invalid then command.mode = values.mode
        if values.playbackGeneration <> invalid then command.playbackGeneration = values.playbackGeneration
        if values.positionSeconds <> invalid then command.positionSeconds = values.positionSeconds
    end if
    return PorticoPlaybackViewerCommand(controller, controller.viewerController, command)
end function

function PorticoPlaybackQueueCommand(controller as object, kind as string, values = invalid as dynamic) as boolean
    allowed = {"queue-append": true, "queue-play-next": true, "queue-remove": true, "queue-reorder": true, "queue-shuffle": true, "queue-clear": true, "set-repeat-mode": true}
    if allowed[kind] <> true then return false
    command = {kind: kind}
    if values <> invalid and Type(values) = "roAssociativeArray"
        for each key in ["mediaId", "entryId", "destinationEntryId", "placement", "repeatMode"]
            if values[key] <> invalid then command[key] = values[key]
        end for
    end if
    return PorticoPlaybackViewerCommand(controller, controller.viewerController, command)
end function

sub PorticoPlaybackServerStateChanged(controller as object, state as dynamic)
    if controller.task = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return
    serverId = PorticoPlaybackBridgeSafeId(state.selectedServerId)
    serverStatus = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    signature = serverId + "|" + serverStatus
    if signature = controller.serverSignature then return
    controller.serverSignature = signature
    controller.commandSequence = controller.commandSequence + 1
    PorticoPlaybackAssignCommand(controller, {
        sequence: controller.commandSequence,
        kind: "server-state",
        selectedServerId: serverId,
        serverStatus: serverStatus
    })
end sub

sub PorticoPlaybackStartCommand(controller as object, serverId as string, mediaId as string, startSeconds as dynamic)
    PorticoPlaybackStartTargetCommand(controller, serverId, "vod", mediaId, startSeconds)
end sub

function PorticoPlaybackStartTargetCommand(controller as object, serverId as string, targetKind as string, targetId as string, startSeconds as dynamic) as boolean
    if controller = invalid or controller.task = invalid then return false
    safeServerId = PorticoPlaybackBridgeSafeId(serverId)
    safeTargetId = PorticoPlaybackBridgeSafeId(targetId)
    normalizedKind = LCase(targetKind)
    if normalizedKind <> "vod" and normalizedKind <> "live" and normalizedKind <> "dvr" and normalizedKind <> "library-channel" then return false
    if safeServerId = "" or safeTargetId = "" then return false
    controller.commandSequence = controller.commandSequence + 1
    command = {
        sequence: controller.commandSequence,
        kind: "start",
        selectedServerId: safeServerId,
        targetKind: normalizedKind,
        targetId: safeTargetId,
        mediaId: safeTargetId
    }
    if startSeconds <> invalid
        boundedStart = PorticoHttpInteger(startSeconds, 0)
        if boundedStart < 0 then boundedStart = 0
        command.startSeconds = boundedStart
    end if
    if controller.envelopeMode
        return PorticoPlaybackViewerCommand(controller, controller.viewerController, command)
    end if
    controller.task.command = command
    return true
end function

function PorticoPlaybackHandlePlayerEvent(controller as object, eventValue as dynamic) as object
    if controller = invalid or controller.task = invalid or eventValue = invalid or Type(eventValue) <> "roAssociativeArray" then return {handled: false}
    kind = LCase(PorticoHttpScalarString(eventValue.kind, ""))
    generation = PorticoHttpInteger(eventValue.playbackGeneration, 0)
    if kind = "player-state" or kind = "seek"
        PorticoPlaybackPlayerStateCommand(controller, generation, PorticoHttpScalarString(eventValue.state, "paused"), PorticoHttpInteger(eventValue.positionSeconds, 0), PorticoHttpInteger(eventValue.durationSeconds, 0), kind = "seek")
    else if kind = "completed"
        PorticoPlaybackCompletedCommand(controller, generation, PorticoHttpInteger(eventValue.positionSeconds, 0), PorticoHttpInteger(eventValue.durationSeconds, 0))
    else if kind = "next" or kind = "replay" or kind = "select-quality" or kind = "select-audio" or kind = "select-subtitle" or kind = "subtitle-off"
        PorticoPlaybackOptionCommand(controller, kind, generation, PorticoHttpScalarString(eventValue.targetId, ""))
    else if kind = "set-playback-preference"
        PorticoPlaybackPreferenceCommand(controller, PorticoHttpScalarString(eventValue.preferenceKey, ""), eventValue.preferenceValue)
    else if kind = "renew-grant"
        PorticoPlaybackRenewGrantCommand(controller, generation)
    else if kind = "source-error"
        PorticoPlaybackSourceErrorCommand(controller, generation)
    else if kind = "stop"
        PorticoPlaybackStopCommand(controller, generation)
    else if kind = "seek-trickplay"
        return {handled: PorticoPlaybackSeekTrickplayCommand(controller, eventValue, true)}
    else if kind = "watch-seek-trickplay"
        return {handled: PorticoPlaybackSeekTrickplayCommand(controller, eventValue, false)}
    else if kind = "play-now" or kind = "cancel-autoplay" or kind = "confirm-still-watching" or kind = "dismiss-segment" or kind = "skip-segment" or kind = "set-speed" or kind = "set-sleep-timer" or kind = "trickplay-preview" or kind = "trickplay-dismiss"
        values = {}
        for each key in ["segmentId", "speed", "mode", "playbackGeneration", "positionSeconds"]
            if eventValue[key] <> invalid then values[key] = eventValue[key]
        end for
        return {handled: PorticoPlaybackAutomationCommand(controller, kind, values)}
    else if kind = "watch-load"
        targetId = PorticoPlaybackBridgeSafeId(eventValue.targetId)
        if targetId = "" then return {handled: true, watchLoad: invalid}
        return {handled: true, watchLoad: {targetId: targetId, positionSeconds: PorticoHttpInteger(eventValue.positionSeconds, 0), paused: eventValue.paused = true}}
    else
        return {handled: false}
    end if
    return {handled: true}
end function

sub PorticoPlaybackPlayerStateCommand(controller as object, playbackGeneration as integer, state as string, positionSeconds as integer, durationSeconds as integer, seekEvent as boolean)
    if controller.task = invalid or playbackGeneration < 1 then return
    normalizedState = LCase(state)
    allowed = { playing: true, paused: true, buffering: true }
    if allowed[normalizedState] <> true then return
    if positionSeconds < 0 then positionSeconds = 0
    if durationSeconds < 0 then durationSeconds = 0
    kind = "player-state"
    if seekEvent then kind = "seek"
    controller.commandSequence = controller.commandSequence + 1
    PorticoPlaybackAssignCommand(controller, {
        sequence: controller.commandSequence,
        kind: kind,
        playbackGeneration: playbackGeneration,
        state: normalizedState,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds
    })
end sub

function PorticoPlaybackSeekTrickplayCommand(controller as object, eventValue as object, applySeek as boolean) as boolean
    generation = PorticoHttpInteger(eventValue.playbackGeneration, 0)
    if controller = invalid or controller.task = invalid or generation < 1 then return false
    state = LCase(PorticoHttpScalarString(eventValue.state, "paused"))
    if state <> "playing" and state <> "paused" and state <> "buffering" then state = "paused"
    command = {
        kind: "trickplay-preview",
        playbackGeneration: generation,
        positionSeconds: PorticoHttpInteger(eventValue.positionSeconds, 0)
    }
    if applySeek
        command.kind = "seek-trickplay"
        command.state = state
        command.durationSeconds = PorticoHttpInteger(eventValue.durationSeconds, 0)
    end if
    return PorticoPlaybackViewerCommand(controller, controller.viewerController, command)
end function

sub PorticoPlaybackCompletedCommand(controller as object, playbackGeneration as integer, positionSeconds as integer, durationSeconds as integer)
    if controller.task = invalid or playbackGeneration < 1 then return
    if positionSeconds < 0 then positionSeconds = 0
    if durationSeconds < 0 then durationSeconds = 0
    controller.commandSequence = controller.commandSequence + 1
    PorticoPlaybackAssignCommand(controller, {
        sequence: controller.commandSequence,
        kind: "completed",
        playbackGeneration: playbackGeneration,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds
    })
end sub

sub PorticoPlaybackOptionCommand(controller as object, kind as string, playbackGeneration as integer, targetId as string)
    if controller.task = invalid or playbackGeneration < 1 then return
    allowed = {next: true, replay: true, "select-quality": true, "select-audio": true, "select-subtitle": true, "subtitle-off": true}
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = {sequence: controller.commandSequence, kind: kind, playbackGeneration: playbackGeneration, targetId: PorticoPlaybackBridgeSafeId(targetId)}
    if kind = "subtitle-off"
        command.kind = "select-subtitle"
        command.off = true
    end if
    PorticoPlaybackAssignCommand(controller, command)
end sub

function PorticoPlaybackRemoteNextCommand(controller as object, playbackGeneration as integer) as boolean
    if controller = invalid or controller.task = invalid or playbackGeneration < 1 then return false
    return PorticoPlaybackViewerCommand(controller, controller.viewerController, {kind: "remote-next", playbackGeneration: playbackGeneration})
end function

function PorticoPlaybackRemotePreviousCommand(controller as object, playbackGeneration as integer) as boolean
    if controller = invalid or controller.task = invalid or playbackGeneration < 1 then return false
    return PorticoPlaybackViewerCommand(controller, controller.viewerController, {kind: "remote-previous", playbackGeneration: playbackGeneration})
end function

function PorticoPlaybackRemoteStopCommand(controller as object, playbackGeneration as integer, messageValue as dynamic) as boolean
    if controller = invalid or controller.task = invalid or playbackGeneration < 1 then return false
    message = PorticoCoreSafeText(messageValue, 500)
    return PorticoPlaybackViewerCommand(controller, controller.viewerController, {kind: "remote-stop", playbackGeneration: playbackGeneration, message: message})
end function

sub PorticoPlaybackPreferenceCommand(controller as object, key as string, value as dynamic)
    if controller.task = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    PorticoPlaybackAssignCommand(controller, {sequence: controller.commandSequence, kind: "set-playback-preference", preferenceKey: key, preferenceValue: value})
end sub

sub PorticoPlaybackPreferencesChangedCommand(controller as object)
    if controller.task = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    PorticoPlaybackAssignCommand(controller, {sequence: controller.commandSequence, kind: "reload-playback-preferences"})
end sub

sub PorticoPlaybackRenewGrantCommand(controller as object, playbackGeneration as integer)
    PorticoPlaybackLifecycleCommand(controller, "renew-grant", playbackGeneration)
end sub

sub PorticoPlaybackSourceErrorCommand(controller as object, playbackGeneration as integer)
    PorticoPlaybackLifecycleCommand(controller, "source-error", playbackGeneration)
end sub

sub PorticoPlaybackStopCommand(controller as object, playbackGeneration as integer)
    if controller.task = invalid then return
    if playbackGeneration < 1
        controller.commandSequence = controller.commandSequence + 1
        PorticoPlaybackAssignCommand(controller, { sequence: controller.commandSequence, kind: "cancel" })
        return
    end if
    PorticoPlaybackLifecycleCommand(controller, "stop", playbackGeneration)
end sub

sub PorticoPlaybackCancelCommand(controller as object)
    if controller.task = invalid then return
    PorticoPlaybackSetIdentity(controller, invalid)
    controller.commandSequence = controller.commandSequence + 1
    PorticoPlaybackAssignCommand(controller, { sequence: controller.commandSequence, kind: "cancel" })
end sub

function PorticoPlaybackTransitionFence(controller as object) as boolean
    if controller = invalid or controller.task = invalid then return false
    PorticoPlaybackSetIdentity(controller, invalid)
    if controller.envelopeMode
        return PorticoPlaybackViewerCommand(controller, controller.viewerController, {kind: "transition-fence"})
    end if
    controller.commandSequence = controller.commandSequence + 1
    controller.task.command = {sequence: controller.commandSequence, kind: "transition-fence"}
    return true
end function

function PorticoPlaybackShutdown(controller as object, port as object, timeoutMs as integer) as boolean
    if controller.task = invalid then return true
    if timeoutMs < 500 then timeoutMs = 500
    if timeoutMs > 5000 then timeoutMs = 5000
    PorticoPlaybackCancelCommand(controller)
    timer = CreateObject("roTimespan")
    timer.Mark()
    while timer.TotalMilliseconds() < timeoutMs
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roSGNodeEvent" and (message.GetField() = "projection" or message.GetField() = "projectionEnvelope")
            sourceNode = message.GetRoSGNode()
            if sourceNode <> invalid and sourceNode.IsSameNode(controller.task)
                data = message.GetData()
                if message.GetField() = "projectionEnvelope" and data <> invalid then data = data.projection
                projection = PorticoPlaybackBridgeProjection(data)
                if projection <> invalid and projection.playbackStatus = "idle"
                    controller.task.control = "STOP"
                    return true
                end if
            end if
        end if
    end while
    controller.task.control = "STOP"
    return false
end function

sub PorticoPlaybackLifecycleCommand(controller as object, kind as string, playbackGeneration as integer)
    if controller.task = invalid or playbackGeneration < 1 then return
    if kind <> "renew-grant" and kind <> "source-error" and kind <> "stop" then return
    controller.commandSequence = controller.commandSequence + 1
    PorticoPlaybackAssignCommand(controller, { sequence: controller.commandSequence, kind: kind, playbackGeneration: playbackGeneration })
end sub

function PorticoPlaybackHandleNodeEvent(controller as object, event as object) as object
    if controller.task = invalid then return { handled: false, reconnectRequired: false, projection: invalid }
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return { handled: false, reconnectRequired: false, projection: invalid }
    if event.GetField() = "eventState"
        return {handled: true, reconnectRequired: false, projection: invalid, privateEventStateChanged: true, privateEventState: PorticoPlaybackPrivateEventState(controller, event.GetData())}
    end if
    if event.GetField() = "contentNode"
        return {handled: true, reconnectRequired: false, projection: invalid, privateContentChanged: true, privateContent: PorticoPlaybackPrivateContentFromNode(controller, event.GetData())}
    end if
    rawProjection = invalid
    if event.GetField() = "projectionEnvelope"
        if controller.viewerController = invalid then return { handled: true, reconnectRequired: false, projection: invalid }
        envelope = event.GetData()
        accepted = PorticoViewerRuntimeAcceptProjection(controller.viewerController.runtime, envelope)
        if not accepted.accepted then return { handled: true, reconnectRequired: false, projection: invalid }
        rawProjection = envelope.projection
    else if event.GetField() = "projection" and controller.envelopeMode <> true
        rawProjection = event.GetData()
    else
        return { handled: false, reconnectRequired: false, projection: invalid }
    end if
    projection = PorticoPlaybackBridgeProjection(rawProjection)
    if projection = invalid then return { handled: true, reconnectRequired: false, projection: invalid }
    reconnect = projection.serverReconnectRequired = true
    projection.Delete("serverReconnectRequired")
    return { handled: true, reconnectRequired: reconnect, projection: projection }
end function

function PorticoPlaybackPrivateEventState(controller as object, value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.Count() <> 4 then return invalid
    scope = PorticoViewerRuntimeControllerCurrentScope(controller.viewerController)
    if scope = invalid or PorticoViewerScopePositiveInteger(value.viewerGeneration) <> scope.viewerGeneration then return invalid
    generation = PorticoHttpInteger(value.playbackGeneration, 0)
    if generation < 0 then return invalid
    if value.active <> true
        if PorticoCoreSafeText(value.sessionId, 128) <> "" then return invalid
        return {active: false, viewerGeneration: scope.viewerGeneration, playbackGeneration: generation}
    end if
    sessionId = PorticoViewerScopeOpaqueId(value.sessionId, 128)
    if sessionId = "" or generation < 1 then return invalid
    return {active: true, viewerGeneration: scope.viewerGeneration, playbackGeneration: generation, sessionId: sessionId}
end function

function PorticoPlaybackTakePrivateContent(controller as object) as dynamic
    if controller = invalid or controller.task = invalid then return invalid
    return PorticoPlaybackPrivateContentFromNode(controller, controller.task.contentNode)
end function

function PorticoPlaybackPrivateContentFromNode(controller as object, node as dynamic) as dynamic
    if node = invalid or Type(node) <> "roSGNode" then return invalid
    scope = PorticoViewerRuntimeControllerCurrentScope(controller.viewerController)
    if scope = invalid then return invalid
    playbackGeneration = PorticoHttpInteger(node.porticoPlaybackGeneration, 0)
    sourceGeneration = PorticoHttpInteger(node.porticoSourceGeneration, 0)
    viewerGeneration = PorticoHttpInteger(node.porticoViewerGeneration, 0)
    if playbackGeneration < 1 or sourceGeneration < 1 then return invalid
    if viewerGeneration <> scope.viewerGeneration then return invalid
    return node
end function

function PorticoPlaybackBridgeProjection(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    status = LCase(PorticoHttpScalarString(source.playbackStatus, ""))
    statuses = { idle: true, preparing: true, ready: true, playing: true, paused: true, buffering: true, stopping: true, postplay: true, ended: true, offline: true, error: true }
    if statuses[status] <> true then return invalid
    generation = PorticoHttpInteger(source.playbackGeneration, 0)
    sourceGeneration = PorticoHttpInteger(source.sourceGeneration, 0)
    if generation < 0 or sourceGeneration < 0 then return invalid
    projection = {
        playbackStatus: status,
        playbackErrorCode: PorticoPlaybackBridgeSafeCode(source.playbackErrorCode),
        playbackGeneration: generation,
        sourceGeneration: sourceGeneration,
        serverReconnectRequired: source.serverReconnectRequired = true,
        preferences: PorticoPlaybackBridgePreferences(source.preferences),
        playbackRate: PorticoPlaybackPreferenceSpeed(source.playbackRate, 1.0),
        sleepTimerMode: PorticoPlaybackBridgeSafeLabel(source.sleepTimerMode, "off", 24),
        postplay: PorticoPlaybackBridgePostplay(source.postplay),
        segmentDirective: PorticoPlaybackBridgeSegmentDirective(source.segmentDirective),
        watchAuthority: PorticoPlaybackBridgeAuthority(source.watchAuthority),
        remoteStopMessage: PorticoCoreSafeText(source.remoteStopMessage, 500)
    }
    if source.source <> invalid
        safeSource = PorticoPlaybackBridgeSource(source.source)
        if safeSource = invalid then return invalid
        projection.source = safeSource
    end if
    projection.trickplayPreview = PorticoPlaybackBridgeTrickplayPreview(source.trickplayPreview, generation, sourceGeneration)
    return projection
end function

function PorticoPlaybackBridgePreferences(source as dynamic) as object
    if source = invalid or Type(source) <> "roAssociativeArray" then return {autoplayNext: true, seekIntervalSeconds: 10, preferredAudioLanguage: "original", preferredSubtitleLanguage: "off", preferredSubtitleMode: "off"}
    seek = PorticoHttpInteger(source.seekIntervalSeconds, 10)
    if seek <> 10 and seek <> 15 and seek <> 30 then seek = 10
    audio = LCase(PorticoPlaybackBridgeSafeLabel(source.preferredAudioLanguage, "original", 16))
    if audio <> "original" and audio <> "en" and audio <> "fr" and audio <> "es" then audio = "original"
    subtitles = LCase(PorticoPlaybackBridgeSafeLabel(source.preferredSubtitleLanguage, "off", 16))
    if subtitles <> "off" and subtitles <> "en" and subtitles <> "fr" and subtitles <> "es" then subtitles = "off"
    subtitleMode = LCase(PorticoPlaybackBridgeSafeLabel(source.preferredSubtitleMode, "", 16))
    if subtitleMode <> "off" and subtitleMode <> "text" and subtitleMode <> "burn_in"
        if subtitles = "off" then subtitleMode = "off" else subtitleMode = "text"
    end if
    countdown = PorticoHttpInteger(source.upNextCountdownSeconds, 10)
    if countdown <> 0 and countdown <> 5 and countdown <> 10 and countdown <> 15 then countdown = 10
    return {autoplayNext: source.autoplayNext <> false, upNextCountdownSeconds: countdown, seekIntervalSeconds: seek, preferredAudioLanguage: audio, preferredSubtitleLanguage: subtitles, preferredSubtitleMode: subtitleMode}
end function

function PorticoPlaybackBridgeAuthority(value as dynamic) as string
    authority = LCase(PorticoPlaybackBridgeSafeLabel(value, "independent", 16))
    if authority <> "host" and authority <> "participant" then authority = "independent"
    return authority
end function

function PorticoPlaybackBridgePostplay(value as dynamic) as object
    result = {phase: "inactive", deadlineAtSeconds: 0, countdownSeconds: 0, stillWatchingRequired: false, automaticAdvances: 0}
    if value = invalid or Type(value) <> "roAssociativeArray" then return result
    phase = LCase(PorticoPlaybackBridgeSafeLabel(value.phase, "inactive", 24))
    allowed = {inactive: true, manual: true, countdown: true, cancelled: true, "still-watching": true}
    if allowed[phase] <> true then phase = "inactive"
    result.phase = phase
    result.deadlineAtSeconds = PorticoHttpInteger(value.deadlineAtSeconds, 0)
    result.countdownSeconds = PorticoHttpInteger(value.countdownSeconds, 0)
    result.stillWatchingRequired = value.stillWatchingRequired = true
    result.automaticAdvances = PorticoHttpInteger(value.automaticAdvances, 0)
    if value.next <> invalid and Type(value.next) = "roAssociativeArray"
        result.next = {
            mediaId: PorticoPlaybackBridgeSafeId(value.next.mediaId),
            title: PorticoPlaybackBridgeSafeLabel(value.next.title, "", 180),
            subtitle: PorticoPlaybackBridgeSafeLabel(value.next.subtitle, "", 120),
            expiresAt: PorticoPlaybackBridgeSafeLabel(value.next.expiresAt, "", 64)
        }
    end if
    return result
end function

function PorticoPlaybackBridgeSegmentDirective(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    kind = LCase(PorticoPlaybackBridgeSafeLabel(value.type, "", 16))
    if kind <> "seek" and kind <> "prompt" then return invalid
    id = PorticoPlaybackBridgeSafeId(value.id)
    position = PorticoHttpInteger(value.positionSeconds, -1)
    if id = "" or position < 0 then return invalid
    return {type: kind, id: id, segmentType: LCase(PorticoPlaybackBridgeSafeLabel(value.segmentType, "", 16)), positionSeconds: position}
end function

function PorticoPlaybackBridgeSource(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    url = PorticoHttpScalarString(source.url, "").Trim()
    lower = LCase(url)
    if Len(url) < 20 or Len(url) > 4096 or (Left(lower, 8) <> "https://" and (Left(lower, 7) <> "http://" or not PorticoHttpUrlAllowed(url, true))) then return invalid
    if PorticoPlaybackBridgeCredentialQueryUnsafe(lower) then return invalid
    if Instr(1, url, "#") > 0 or Instr(1, url, Chr(0)) > 0 or Instr(1, url, Chr(10)) > 0 or Instr(1, url, Chr(13)) > 0 or Instr(1, url, Chr(9)) > 0 or Instr(1, url, " ") > 0 or Instr(1, url, "\") > 0 then return invalid
    streamFormat = LCase(PorticoHttpScalarString(source.streamFormat, ""))
    if streamFormat <> "hls" and streamFormat <> "mp4" then return invalid
    durationSeconds = PorticoHttpInteger(source.durationSeconds, 0)
    resumePositionSeconds = PorticoHttpInteger(source.resumePositionSeconds, 0)
    if durationSeconds < 0 or resumePositionSeconds < 0 then return invalid
    timelineType = LCase(PorticoPlaybackBridgeSafeLabel(source.timelineType, "", 8))
    if timelineType <> "vod" and timelineType <> "live" then
        if source.isLive = true then timelineType = "live" else timelineType = "vod"
    end if
    return {
        url: url,
        streamFormat: streamFormat,
        title: PorticoPlaybackBridgeSafeLabel(source.title, "", 180),
        subtitle: PorticoPlaybackBridgeSafeLabel(source.subtitle, "", 120),
        durationSeconds: durationSeconds,
        resumePositionSeconds: resumePositionSeconds,
        isLive: source.isLive = true,
        mediaId: PorticoPlaybackBridgeSafeId(source.mediaId),
        mediaType: LCase(PorticoPlaybackBridgeSafeLabel(source.mediaType, "video", 40)),
        decision: source.decision,
        sessionGeneration: PorticoHttpInteger(source.sessionGeneration, 0),
        queueRevision: PorticoHttpInteger(source.queueRevision, 0),
        playbackRevision: PorticoHttpInteger(source.playbackRevision, 0),
        currentQueueEntryId: PorticoPlaybackBridgeSafeId(source.currentQueueEntryId),
        repeatMode: LCase(PorticoPlaybackBridgeSafeLabel(source.repeatMode, "off", 8)),
        timelineType: timelineType,
        canPause: source.canPause = true,
        canSeek: source.canSeek = true,
        seekableStartSeconds: PorticoPlaybackBridgeNumber(source.seekableStartSeconds, 0.0),
        seekableEndSeconds: PorticoPlaybackBridgeNumber(source.seekableEndSeconds, 0.0),
        liveEdgeSeconds: PorticoPlaybackBridgeNumber(source.liveEdgeSeconds, 0.0),
        qualityOffers: PorticoPlaybackBridgeQualityOffers(source.qualityOffers),
        qualitySelection: PorticoPlaybackBridgeQualitySelection(source.qualitySelection),
        audioStreams: PorticoPlaybackBridgeOptions(source.audioStreams, "audio"),
        subtitleStreams: PorticoPlaybackBridgeOptions(source.subtitleStreams, "subtitle"),
        chapters: PorticoPlaybackBridgeChapters(source.chapters),
        segments: PorticoPlaybackBridgeSegments(source.segments),
        trickplaySets: PorticoPlaybackBridgeTrickplaySets(source.trickplaySets),
        lyrics: PorticoPlaybackBridgeSafeLabel(source.lyrics, "", 12000),
        queue: PorticoPlaybackBridgeQueue(source.queue),
        selectedAudioStreamId: PorticoPlaybackBridgeSafeId(source.selectedAudioStreamId),
        selectedSubtitleStreamId: PorticoPlaybackBridgeSafeId(source.selectedSubtitleStreamId),
        selectedSubtitleMode: PorticoPlaybackBridgeSubtitleMode(source.selectedSubtitleMode),
        selectedVersionId: PorticoPlaybackBridgeSafeId(source.selectedVersionId),
        targetKind: PorticoPlaybackBridgeTargetKind(source.targetKind)
    }
end function

function PorticoPlaybackBridgeQualityOffers(source as dynamic) as object
    result = {offerRevision: "", offers: []}
    if source = invalid or Type(source) <> "roAssociativeArray" then return result
    result.offerRevision = PorticoPlaybackBridgeSafeId(source.offerRevision)
    if source.offers = invalid or GetInterface(source.offers, "ifArray") = invalid then return result
    for each raw in source.offers
        if result.offers.Count() >= 24 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            selectionId = PorticoPlaybackBridgeSafeId(raw.selectionId)
            label = PorticoPlaybackBridgeSafeLabel(raw.label, "", 100)
            kind = LCase(PorticoPlaybackBridgeSafeLabel(raw.kind, "", 16))
            if selectionId <> "" and label <> "" and (kind = "automatic" or kind = "original" or kind = "fixed")
                result.offers.Push({selectionId: selectionId, label: label, kind: kind})
            end if
        end if
    end for
    return result
end function

function PorticoPlaybackBridgeQualitySelection(source as dynamic) as object
    if source = invalid or Type(source) <> "roAssociativeArray" then return {mode: "automatic"}
    mode = LCase(PorticoPlaybackBridgeSafeLabel(source.mode, "automatic", 16))
    if mode = "explicit"
        return {mode: "explicit", selectionId: PorticoPlaybackBridgeSafeId(source.selectionId), qualityOfferRevision: PorticoPlaybackBridgeSafeId(source.qualityOfferRevision)}
    end if
    return {mode: "automatic"}
end function

function PorticoPlaybackBridgeSubtitleMode(value as dynamic) as string
    mode = LCase(PorticoPlaybackBridgeSafeLabel(value, "off", 16))
    if mode <> "off" and mode <> "text" and mode <> "burn_in" then mode = "off"
    return mode
end function

function PorticoPlaybackBridgeNumber(value as dynamic, fallback as float) as float
    kind = LCase(Type(value))
    if kind <> "float" and kind <> "rofloat" and kind <> "double" and kind <> "rodouble" and kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" then return fallback
    number = value * 1.0
    if number < 0 or number > 2147480000 then return fallback
    return number
end function

function PorticoPlaybackBridgeTrickplaySets(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.Count() >= 8 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackBridgeSafeId(raw.id)
            tileCount = PorticoHttpInteger(raw.tileCount, 0)
            intervalSeconds = PorticoHttpInteger(raw.intervalSeconds, 0)
            if id <> "" and tileCount > 0 and tileCount <= 100000 and intervalSeconds > 0 and intervalSeconds <= 3600
                result.Push({id: id, tileCount: tileCount, intervalSeconds: intervalSeconds, stale: raw.stale = true})
            end if
        end if
    end for
    return result
end function

function PorticoPlaybackBridgeTrickplayPreview(value as dynamic, playbackGeneration as integer, sourceGeneration as integer) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    status = LCase(PorticoPlaybackBridgeSafeLabel(value.status, "", 16))
    if status <> "loading" and status <> "ready" and status <> "unavailable" then return invalid
    if PorticoHttpInteger(value.playbackGeneration, 0) <> playbackGeneration or PorticoHttpInteger(value.sourceGeneration, 0) <> sourceGeneration then return invalid
    uri = PorticoHttpScalarString(value.uri, "")
    if status = "ready"
        prefix = "tmp:/portico-trickplay-v"
        if Len(uri) > 512 or Left(uri, Len(prefix)) <> prefix or Right(LCase(uri), 4) <> ".jpg" or Instr(1, uri, "..") > 0 then return invalid
        if Instr(1, uri, Chr(0)) > 0 or Instr(1, uri, Chr(10)) > 0 or Instr(1, uri, Chr(13)) > 0 or Instr(1, uri, " ") > 0 or Instr(1, uri, "?") > 0 or Instr(1, uri, "#") > 0 then return invalid
    else
        uri = ""
    end if
    tileIndex = PorticoHttpInteger(value.tileIndex, -1)
    positionSeconds = PorticoHttpInteger(value.positionSeconds, -1)
    if tileIndex < 0 or positionSeconds < 0 then return invalid
    return {status: status, playbackGeneration: playbackGeneration, sourceGeneration: sourceGeneration, setId: PorticoPlaybackBridgeSafeId(value.setId), tileIndex: tileIndex, positionSeconds: positionSeconds, uri: uri}
end function

function PorticoPlaybackBridgeSegments(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.Count() >= 96 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackBridgeSafeId(raw.id)
            kind = LCase(PorticoPlaybackBridgeSafeLabel(raw.type, "", 16))
            startSeconds = PorticoHttpInteger(raw.startSeconds, -1)
            endSeconds = PorticoHttpInteger(raw.endSeconds, -1)
            if id <> "" and (kind = "intro" or kind = "credits") and startSeconds >= 0 and endSeconds > startSeconds then result.Push({id: id, type: kind, startSeconds: startSeconds, endSeconds: endSeconds, automaticSafe: raw.automaticSafe = true})
        end if
    end for
    return result
end function

function PorticoPlaybackBridgeTargetKind(value as dynamic) as string
    kind = LCase(PorticoPlaybackBridgeSafeLabel(value, "vod", 20))
    if kind <> "vod" and kind <> "live" and kind <> "dvr" and kind <> "library-channel" then kind = "vod"
    return kind
end function

function PorticoPlaybackBridgeOptions(source as dynamic, kind as string) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= 24 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoPlaybackBridgeSafeId(raw.id)
            if id <> ""
                option = {id: id, label: PorticoPlaybackBridgeSafeLabel(raw.label, "", 100), displayTitle: PorticoPlaybackBridgeSafeLabel(raw.displayTitle, "", 100), language: PorticoPlaybackBridgeSafeLabel(raw.language, "", 32), codec: PorticoPlaybackBridgeSafeLabel(raw.codec, "", 24)}
                if kind = "subtitle" then option.sourceUrl = PorticoPlaybackBridgeSubtitleUrl(raw.sourceUrl)
                result.push(option)
            end if
        end if
    end for
    return result
end function

function PorticoPlaybackBridgeChapters(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= 48 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            seconds = PorticoHttpInteger(raw.startSeconds, -1)
            if seconds >= 0 then result.push({id: PorticoPlaybackBridgeSafeId(raw.id), title: PorticoPlaybackBridgeSafeLabel(raw.title, "", 100), startSeconds: seconds})
        end if
    end for
    return result
end function

function PorticoPlaybackBridgeQueue(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= 50 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            entryId = PorticoPlaybackBridgeSafeId(raw.entryId)
            mediaId = PorticoPlaybackBridgeSafeId(raw.mediaId)
            title = PorticoPlaybackBridgeSafeLabel(raw.title, "", 140)
            if entryId <> "" and mediaId <> "" and title <> "" then result.push({entryId: entryId, mediaId: mediaId, title: title, subtitle: PorticoPlaybackBridgeSafeLabel(raw.subtitle, "", 100)})
        end if
    end for
    return result
end function

function PorticoPlaybackBridgeSubtitlePath(value as dynamic) as string
    if value = invalid then return ""
    path = value.ToStr().Trim()
    if path = "" or Len(path) > 2048 or Left(path, 1) <> "/" or Left(path, 2) = "//" then return ""
    if Instr(1, path, Chr(0)) > 0 or Instr(1, path, Chr(10)) > 0 or Instr(1, path, Chr(13)) > 0 or Instr(1, path, " ") > 0 then return ""
    return path
end function

function PorticoPlaybackBridgeSubtitleUrl(value as dynamic) as string
    if value = invalid then return ""
    url = value.ToStr().Trim()
    lower = LCase(url)
    if Len(url) < 20 or Len(url) > 4096 or Left(lower, 8) <> "https://" then return ""
    if PorticoPlaybackBridgeCredentialQueryUnsafe(lower) then return ""
    if Instr(1, url, "#") > 0 or Instr(1, url, Chr(0)) > 0 or Instr(1, url, Chr(10)) > 0 or Instr(1, url, Chr(13)) > 0 or Instr(1, url, " ") > 0 then return ""
    return url
end function

function PorticoPlaybackBridgeAccessTokenQueryMarker() as string
    return "access" + Chr(95) + "token="
end function

function PorticoPlaybackBridgeCompactAccessTokenQueryMarker() as string
    return "access" + "token="
end function

function PorticoPlaybackBridgeCredentialQueryUnsafe(lower as string) as boolean
    markers = ["media_grant=", "download_grant=", "access_token=", "accesstoken=", "media%5fgrant=", "download%5fgrant=", "access%5ftoken="]
    for each marker in markers
        if Instr(1, lower, marker) > 0 then return true
    end for
    return false
end function

function PorticoPlaybackContentNode(source as dynamic) as dynamic
    safe = PorticoPlaybackBridgeSource(source)
    if safe = invalid then return invalid
    content = CreateObject("roSGNode", "ContentNode")
    if content = invalid then return invalid
    content.url = safe.url
    content.streamFormat = safe.streamFormat
    content.title = safe.title
    return content
end function

function PorticoPlaybackBridgeSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoPlaybackBridgeSafeCode(value as dynamic) as string
    if value = invalid then return ""
    normalized = LCase(value.ToStr().Trim())
    if Len(normalized) > 100 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoPlaybackBridgeSafeLabel(value as dynamic, fallback as string, maximumLength as integer) as string
    if value = invalid then return fallback
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then return fallback
    if Len(normalized) > maximumLength then normalized = Left(normalized, maximumLength)
    return normalized
end function
