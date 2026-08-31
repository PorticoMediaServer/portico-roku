sub init()
    m.top.functionName = "PorticoPlaybackRun"
end sub

sub PorticoPlaybackRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    controller = {
        clock: clock,
        lastCommandSequence: 0,
        serverId: "",
        serverStatus: "not-connected",
        serverSession: invalid,
        playback: invalid,
        playbackGeneration: 0,
        sourceGeneration: 0,
        status: "idle",
        errorCode: "",
        playerState: "paused",
        positionSeconds: 0,
        durationSeconds: 0,
        nextHeartbeatAtSeconds: 0,
        heartbeatScheduled: false,
        nextGrantRenewalAtSeconds: 0,
        grantRenewalScheduled: false,
        grantRenewalFailures: 0,
        reconnectRequestedSessionGeneration: -1,
        sourceRecoveryPending: false,
        sourceRecoveryAttempts: 0,
        sourceRecoveryStableSince: 0,
        preferences: PorticoPlaybackPreferencesRead(),
        lastTargetKind: "vod",
        lastTargetId: "",
        automaticAdvances: 0,
        lastMeaningfulInteractionAt: 0,
        preparedNext: invalid,
        postplayPhase: "inactive",
        postplayDeadlineAt: 0,
        lastPublishedPostplayCountdown: -1,
        stillWatchingRequired: false,
        preparedHandoffStarted: false,
        playbackRate: 1.0,
        sleepTimerMode: "off",
        sleepTimerDeadlineAt: 0,
        dismissedSegmentIds: {},
        segmentDirective: invalid,
        watchAuthority: "independent",
        remoteStopMessage: ""
    }
    controller.trickplayPreview = invalid
    controller.trickplayCache = {}
    controller.trickplayCacheOrder = []
    controller.progressPort = CreateObject("roMessagePort")
    controller.progressRequest = invalid
    controller.progressPending = invalid
    controller.pendingStart = invalid
    controller.pendingMutation = invalid
    controller.pendingMutationRestored = false
    controller.lastPublishedContentSourceGeneration = 0
    controller.lastMeaningfulInteractionAt = clock.TotalSeconds()
    PorticoPlaybackTaskAdopt(controller, PorticoPlaybackTaskState())
    PorticoPlaybackPublish(controller, false)
    while true
        PorticoPlaybackHandleCommand(controller)
        PorticoPlaybackPollProgress(controller)
        PorticoPlaybackTick(controller)
        Sleep(100)
    end while
end sub

sub PorticoPlaybackHandleCommand(controller as object)
    command = invalid
    envelope = m.top.commandEnvelope
    if envelope <> invalid and Type(envelope) = "roAssociativeArray"
        incomingScope = PorticoViewerScopeNormalize(envelope.viewerScope)
        if controller.envelopeMode and incomingScope <> invalid and not PorticoViewerScopeEquals(controller.viewerScope, incomingScope)
            ' Fence the old source before adopting any identity from a new viewer.
            PorticoPlaybackStageTransitionTerminal(controller, false)
            controller.pendingMutation = invalid
            controller.pendingMutationRestored = false
            controller.serverSession = invalid
            controller.serverId = ""
            controller.serverStatus = "not-connected"
        end if
        command = PorticoPlaybackAcceptCommand(controller, envelope)
    else if controller.envelopeMode <> true
        command = m.top.command
    end if
    if command = invalid or Type(command) <> "roAssociativeArray" then return
    sequence = PorticoHttpInteger(command.sequence, 0)
    if sequence <= controller.lastCommandSequence then return
    controller.lastCommandSequence = sequence
    kind = LCase(PorticoHttpScalarString(command.kind, ""))

    if controller.pendingMutation <> invalid and kind <> "viewer-fence" and kind <> "transition-fence" and kind <> "viewer-state" and kind <> "server-state"
        PorticoPlaybackDispatchPendingMutation(controller)
        return
    end if

    if kind = "viewer-fence"
        PorticoPlaybackStageTransitionTerminal(controller, false)
        controller.pendingMutation = invalid
        controller.pendingMutationRestored = false
        controller.serverSession = invalid
        controller.status = "idle"
        controller.errorCode = ""
        PorticoPlaybackPublish(controller, false)
    else if kind = "transition-fence"
        PorticoPlaybackApplyTransitionFence(controller)
    else if kind = "viewer-state"
        if command.preferences <> invalid and Type(command.preferences) = "roAssociativeArray" then controller.preferences = PorticoPlaybackPreferencesFromViewer(command.preferences)
        PorticoPlaybackApplyServerState(controller, command)
    else if kind = "server-state"
        PorticoPlaybackApplyServerState(controller, command)
    else if kind = "start"
        PorticoPlaybackStart(controller, command)
    else if kind = "player-state"
        PorticoPlaybackPlayerState(controller, command, false)
    else if kind = "seek"
        PorticoPlaybackPlayerState(controller, command, true)
    else if kind = "seek-trickplay"
        if PorticoPlaybackCommandOwnsActive(controller, command)
            PorticoPlaybackPlayerState(controller, command, true)
            if not PorticoPlaybackInterrupted(controller) then PorticoPlaybackLoadTrickplayPreview(controller, command)
        end if
    else if kind = "completed"
        PorticoPlaybackComplete(controller, command)
    else if kind = "next"
        if controller.watchAuthority = "independent" and PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackAdvanceNext(controller, false, PorticoPlaybackSafeId(command.targetId))
    else if kind = "remote-next"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackAdvanceNext(controller, false, "")
    else if kind = "previous" or kind = "remote-previous"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackAdvancePrevious(controller)
    else if kind = "remote-stop"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackRemoteStop(controller, command.message)
    else if kind = "replay"
        if controller.watchAuthority = "independent"
            if controller.playback <> invalid and controller.playback.isLive <> true
                PorticoPlaybackHandoffEntry(controller, controller.playback.currentQueueEntryId, "stopped", 0)
            else if controller.lastTargetId <> ""
                ' A session that already has a durable completion receipt has no
                ' remaining handoff authority. Replay is a fresh zero-position start.
                PorticoPlaybackStart(controller, {selectedServerId: controller.serverId, targetKind: controller.lastTargetKind, targetId: controller.lastTargetId, startSeconds: 0})
            end if
        end if
    else if kind = "select-quality"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackSelectQuality(controller, PorticoPlaybackSafeId(command.targetId))
    else if kind = "select-audio"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackSelectAudio(controller, PorticoPlaybackSafeId(command.targetId))
    else if kind = "select-subtitle"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackSelectSubtitle(controller, PorticoPlaybackSafeId(command.targetId), command.off = true)
    else if kind = "set-playback-preference"
        if controller.envelopeMode
            controller.preferences = PorticoPlaybackPreferencesTransientUpdate(controller.preferences, PorticoHttpScalarString(command.preferenceKey, ""), command.preferenceValue)
        else
            controller.preferences = PorticoPlaybackPreferencesUpdate(PorticoHttpScalarString(command.preferenceKey, ""), command.preferenceValue)
        end if
        PorticoPlaybackPublish(controller, false)
    else if kind = "viewer-preferences"
        controller.preferences = PorticoPlaybackPreferencesFromViewer(command.preferences)
        PorticoPlaybackPublish(controller, false)
    else if kind = "watch-authority"
        authority = LCase(PorticoCoreSafeText(command.authority, 16))
        if authority <> "host" and authority <> "participant" then authority = "independent"
        controller.watchAuthority = authority
        if authority = "participant" then controller.postplayPhase = "manual"
        PorticoPlaybackPublish(controller, false)
    else if kind = "play-now"
        if controller.watchAuthority <> "participant" then PorticoPlaybackHandoffPrepared(controller)
    else if kind = "cancel-autoplay"
        PorticoPlaybackCancelPostplay(controller)
    else if kind = "confirm-still-watching"
        controller.automaticAdvances = 0
        controller.lastMeaningfulInteractionAt = controller.clock.TotalSeconds()
        controller.stillWatchingRequired = false
        if controller.watchAuthority <> "participant" then PorticoPlaybackHandoffPrepared(controller)
    else if kind = "dismiss-segment"
        segmentId = PorticoPlaybackSafeId(command.segmentId)
        if segmentId <> "" then controller.dismissedSegmentIds[segmentId] = true
        controller.segmentDirective = invalid
        PorticoPlaybackPublish(controller, false)
    else if kind = "skip-segment"
        PorticoPlaybackSkipSegment(controller, PorticoPlaybackSafeId(command.segmentId))
    else if kind = "set-speed"
        PorticoPlaybackSetSpeed(controller, command.speed)
    else if kind = "set-sleep-timer"
        PorticoPlaybackSetSleepTimer(controller, command.mode)
    else if kind = "trickplay-preview"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackLoadTrickplayPreview(controller, command)
    else if kind = "trickplay-dismiss"
        if PorticoPlaybackCommandOwnsActive(controller, command)
            controller.trickplayPreview = invalid
            PorticoPlaybackPublish(controller, false)
        end if
    else if kind = "queue-append" or kind = "queue-play-next" or kind = "queue-remove" or kind = "queue-reorder" or kind = "queue-shuffle" or kind = "queue-clear" or kind = "set-repeat-mode"
        PorticoPlaybackQueueMutation(controller, kind, command)
    else if kind = "reload-playback-preferences"
        controller.preferences = PorticoPlaybackPreferencesProjection()
        PorticoPlaybackPublish(controller, false)
    else if kind = "renew-grant"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackRenewGrant(controller, true)
    else if kind = "source-error"
        if PorticoPlaybackCommandOwnsActive(controller, command) then PorticoPlaybackRecoverSource(controller)
    else if kind = "stop"
        commandGeneration = PorticoHttpInteger(command.playbackGeneration, -1)
        if PorticoPlaybackCommandOwnsActive(controller, command) or (controller.playback = invalid and commandGeneration = controller.playbackGeneration)
            PorticoPlaybackStopActive(controller, true)
        end if
    else if kind = "cancel"
        PorticoPlaybackStopActive(controller, true)
    end if
end sub

sub PorticoPlaybackApplyServerState(controller as object, command as object)
    serverId = PorticoPlaybackSafeId(command.selectedServerId)
    serverStatus = LCase(PorticoHttpScalarString(command.serverStatus, "not-connected"))
    allowed = { online: true, connecting: true, offline: true, blocked: true, "identity-mismatch": true, incompatible: true, "permission-removed": true, "not-connected": true }
    if allowed[serverStatus] <> true then serverStatus = "not-connected"
    selectionChanged = serverId <> controller.serverId
    terminal = serverStatus = "permission-removed" or serverStatus = "identity-mismatch" or serverStatus = "incompatible" or serverStatus = "not-connected"
    if controller.playback <> invalid and (selectionChanged or terminal) then PorticoPlaybackStopActive(controller, true)
    controller.serverId = serverId
    controller.serverStatus = serverStatus
    controller.serverSession = invalid
    if controller.playback <> invalid and serverStatus = "online" and controller.sourceRecoveryPending
        controller.serverSession = PorticoPlaybackSessionForController(controller)
        if controller.serverSession <> invalid then PorticoPlaybackRenewGrant(controller, true)
    end if
    if serverStatus = "online"
        PorticoPlaybackRestorePendingMutation(controller)
        if controller.pendingMutation <> invalid then PorticoPlaybackDispatchPendingMutation(controller)
    end if
    if controller.playback = invalid and controller.status <> "error"
        if serverId = ""
            controller.status = "idle"
            controller.errorCode = ""
        else if serverStatus = "offline"
            controller.status = "offline"
            controller.errorCode = "server-offline"
        end if
        PorticoPlaybackPublish(controller, false)
    end if
end sub

sub PorticoPlaybackStart(controller as object, command as object)
    targetKind = LCase(PorticoHttpScalarString(command.targetKind, "vod"))
    if targetKind <> "vod" and targetKind <> "live" and targetKind <> "dvr" and targetKind <> "library-channel" then return
    targetId = PorticoPlaybackSafeId(command.targetId)
    if targetId = "" then targetId = PorticoPlaybackSafeId(command.mediaId)
    requestedServerId = PorticoPlaybackSafeId(command.selectedServerId)
    if targetId = "" or requestedServerId = "" or requestedServerId <> controller.serverId then return
    if controller.serverId = "" or controller.serverStatus <> "online"
        if controller.playback = invalid then PorticoPlaybackFail(controller, "server-offline", false)
        return
    end if
    session = PorticoPlaybackSessionForController(controller)
    if session = invalid
        if controller.playback <> invalid
            controller.errorCode = "server-session-required"
            PorticoPlaybackPublish(controller, true)
        else
            PorticoPlaybackFail(controller, "server-session-required", true)
        end if
        return
    end if
    controller.serverSession = session
    startSeconds = invalid
    if command.startSeconds <> invalid then startSeconds = PorticoPlaybackBoundedSeconds(command.startSeconds, 0)
    profile = PorticoPlaybackClientProfileForPreferences(controller.preferences)
    body = PorticoPlaybackStartBodyWithIntent(targetId, startSeconds, PorticoPlaybackPortableIntent(controller.preferences, profile), profile)
    requestPath = "/api/playback-sessions"
    if targetKind = "live"
        requestPath = "/api/live-tv/play"
        body.channelId = targetId
        body.Delete("mediaId")
        body.Delete("startSeconds")
        body.Delete("repeatMode")
    else if targetKind = "dvr"
        requestPath = "/api/dvr/recordings/" + targetId + "/playback"
        body.Delete("mediaId")
        body.Delete("repeatMode")
    else if targetKind = "library-channel"
        requestPath = "/api/library-channels/" + targetId + "/tune"
        body = {
            clientInstanceId: PorticoInstallationId(),
            clientProfile: profile,
            intent: PorticoPlaybackPortableIntent(controller.preferences, profile)
        }
    end if
    if body.clientInstanceId = "" then body.Delete("clientInstanceId")

    if controller.playback <> invalid
        active = controller.playback
        terminalRequest = PorticoPlaybackTerminalRequest(controller, active, "stopped")
        if terminalRequest = invalid then return
        replacement = {
            sourceSessionId: active.sessionId,
            requestId: terminalRequest.requestId,
            previousTerminal: terminalRequest.terminal,
            expectedQueueRevision: active.queueRevision,
            expectedPlaybackRevision: active.playbackRevision
        }
        body.replacement = replacement
        mutation = PorticoPlaybackPendingReplacement(controller, active, requestPath, body, targetKind, targetId, terminalRequest)
        if not PorticoPlaybackPersistPendingMutation(controller, mutation)
            controller.status = controller.playerState
            controller.errorCode = "playback-terminal-storage-unavailable"
            PorticoPlaybackPublish(controller, false)
            return
        end if
        controller.pendingMutation = mutation
        controller.heartbeatScheduled = false
        controller.status = controller.playerState
        controller.errorCode = ""
        PorticoPlaybackPublish(controller, false)
        PorticoPlaybackDispatchPendingMutation(controller)
        return
    end if

    controller.lastTargetKind = targetKind
    controller.lastTargetId = targetId
    controller.playbackGeneration = controller.playbackGeneration + 1
    controller.status = "preparing"
    controller.errorCode = ""
    controller.positionSeconds = 0
    controller.durationSeconds = 0
    PorticoPlaybackResetAutomation(controller, true)
    PorticoPlaybackPublish(controller, false)
    result = PorticoPlaybackAuthenticatedRequest(controller, {
        method: "POST",
        path: requestPath,
        body: body,
        timeoutMs: 20000,
        expectJson: true,
        interruptible: true
    })
    if result.interrupted then return
    if not result.ok
        PorticoPlaybackHandleStartFailure(controller, result)
        return
    end if
    playbackDocument = result.data
    if targetKind = "library-channel"
        if playbackDocument = invalid or Type(playbackDocument) <> "roAssociativeArray" or playbackDocument.playback = invalid
            PorticoPlaybackFail(controller, "playback-response-incompatible", false)
            return
        end if
        playbackDocument = playbackDocument.playback
    end if
    playback = PorticoPlaybackFromResponse(playbackDocument, controller.serverSession)
    if playback = invalid
        authority = PorticoPlaybackAuthorityFromResponse(playbackDocument)
        if authority <> invalid
            PorticoPlaybackBeginTerminal(controller, authority, "stopped", "error", "playback-response-incompatible", "")
        else
            PorticoPlaybackFail(controller, "playback-response-incompatible", false)
        end if
        return
    end if
    playback.targetKind = targetKind
    preflight = PorticoPlaybackPreflightSource(controller, playback)
    if not preflight.ok
        failureCode = "playback-source-unavailable"
        if preflight.interrupted then failureCode = "playback-cancelled"
        controller.positionSeconds = playback.resumePositionSeconds
        controller.durationSeconds = playback.durationSeconds
        PorticoPlaybackBeginTerminal(controller, playback, "stopped", "error", failureCode, "")
        return
    end if
    controller.playback = playback
    controller.playerState = "paused"
    controller.positionSeconds = playback.resumePositionSeconds
    controller.durationSeconds = playback.durationSeconds
    controller.sourceGeneration = controller.sourceGeneration + 1
    controller.status = "ready"
    controller.errorCode = ""
    controller.reconnectRequestedSessionGeneration = -1
    controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
    controller.heartbeatScheduled = true
    controller.grantRenewalFailures = 0
    controller.sourceRecoveryPending = false
    controller.sourceRecoveryAttempts = 0
    controller.sourceRecoveryStableSince = 0
    PorticoPlaybackScheduleGrantRenewal(controller)
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackHandleStartFailure(controller as object, result as object)
    if result.status = 401 or result.missingSession = true
        PorticoPlaybackFail(controller, "server-session-required", true)
    else if result.status = 403
        PorticoPlaybackFail(controller, "playback-not-permitted", false)
    else if result.status = 404
        PorticoPlaybackFail(controller, "media-unavailable", false)
    else if result.status = 409 or result.status = 422
        PorticoPlaybackFail(controller, "playback-option-unavailable", false)
    else
        PorticoPlaybackFail(controller, "server-offline", false)
    end if
end sub

sub PorticoPlaybackPlayerState(controller as object, command as object, seekEvent as boolean)
    if not PorticoPlaybackCommandOwnsActive(controller, command) then return
    state = LCase(PorticoHttpScalarString(command.state, ""))
    allowed = { playing: true, paused: true, buffering: true }
    if allowed[state] <> true then return
    previousState = controller.playerState
    controller.playerState = state
    controller.positionSeconds = PorticoPlaybackClampToTimeline(controller.playback, command.positionSeconds, controller.positionSeconds)
    if controller.playback.isLive = true
        controller.durationSeconds = 0
    else
        controller.durationSeconds = PorticoPlaybackBoundedSeconds(command.durationSeconds, controller.durationSeconds)
        if controller.playback.durationSeconds > 0 and controller.durationSeconds = 0 then controller.durationSeconds = controller.playback.durationSeconds
    end if
    controller.status = state
    controller.errorCode = ""
    if seekEvent or state <> previousState
        controller.lastMeaningfulInteractionAt = controller.clock.TotalSeconds()
        controller.automaticAdvances = 0
    end if
    if state = "playing" and controller.sourceRecoveryAttempts > 0 and controller.sourceRecoveryPending <> true and controller.sourceRecoveryStableSince = 0
        controller.sourceRecoveryStableSince = controller.clock.TotalSeconds()
    end if
    PorticoPlaybackEvaluateSegment(controller)
    immediate = seekEvent or state <> previousState
    if immediate
        PorticoPlaybackSendProgress(controller)
        controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
        controller.heartbeatScheduled = true
    else if not controller.heartbeatScheduled
        controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
        controller.heartbeatScheduled = true
    end if
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackComplete(controller as object, command as object)
    if not PorticoPlaybackCommandOwnsActive(controller, command) then return
    controller.playerState = "paused"
    controller.positionSeconds = PorticoPlaybackClampToTimeline(controller.playback, command.positionSeconds, controller.positionSeconds)
    if controller.playback.isLive = true
        controller.durationSeconds = 0
    else
        controller.durationSeconds = PorticoPlaybackBoundedSeconds(command.durationSeconds, controller.durationSeconds)
        if controller.durationSeconds > 0 then controller.positionSeconds = controller.durationSeconds
    end if
    if controller.sleepTimerMode = "end-of-item"
        PorticoPlaybackBeginTerminal(controller, controller.playback, "completed", "ended", "", "")
        return
    end if
    if controller.watchAuthority = "independent" and controller.playback <> invalid and controller.preferences.autoplayNext = true and controller.playback.isLive <> true and controller.playback.queue.count() > 0
        if PorticoPlaybackBeginPostplay(controller) then return
    end if
    PorticoPlaybackBeginTerminal(controller, controller.playback, "completed", "ended", "", "")
end sub

function PorticoPlaybackAdvanceNext(controller as object, autoplay as boolean, targetEntryId as string, allowHistorical = false as boolean) as boolean
    if controller.playback = invalid or controller.playback.isLive = true then return false
    if not allowHistorical and controller.playback.queue.count() = 0 then return false
    if controller.preparedNext <> invalid and targetEntryId = "" then return PorticoPlaybackHandoffPrepared(controller)
    active = controller.playback
    if targetEntryId = "" and active.queue.Count() > 0 then targetEntryId = active.queue[0].entryId
    if targetEntryId = "" then return false
    if not allowHistorical
        allowedTarget = false
        for each queued in active.queue
            if queued.entryId = targetEntryId then allowedTarget = true
        end for
        if not allowedTarget then return false
    end if
    nextProfile = PorticoPlaybackClientProfileForPreferences(controller.preferences)
    prepareBody = {entryId: targetEntryId, clientProfile: nextProfile, intent: PorticoPlaybackPortableIntent(controller.preferences, nextProfile)}
    prepare = PorticoPlaybackAuthenticatedRequest(controller, {method: "POST", path: "/api/playback-sessions/" + active.sessionId + "/prepare-next", body: prepareBody, timeoutMs: 20000, expectJson: true, interruptible: true})
    if prepare.interrupted then return false
    if not prepare.ok or prepare.data = invalid or Type(prepare.data) <> "roAssociativeArray" then return PorticoPlaybackNextFailed(controller, autoplay)
    preparedId = PorticoPlaybackSafeId(prepare.data.preparedSessionId)
    preparedQueueRevision = PorticoPlaybackBoundedSeconds(prepare.data.queueRevision, -1)
    preparedPlaybackRevision = PorticoPlaybackBoundedSeconds(prepare.data.playbackRevision, -1)
    if preparedId = "" or preparedQueueRevision < 0 or preparedPlaybackRevision < 0 then return PorticoPlaybackNextFailed(controller, autoplay)
    prepared = {sessionId: preparedId, entryId: targetEntryId, queueRevision: preparedQueueRevision, playbackRevision: preparedPlaybackRevision}
    disposition = "stopped"
    if autoplay then disposition = "completed"
    return PorticoPlaybackCommitHandoff(controller, prepared, disposition, invalid, autoplay)
end function

function PorticoPlaybackAdvancePrevious(controller as object) as boolean
    if controller.playback = invalid or controller.playback.isLive = true then return false
    active = controller.playback
    result = PorticoPlaybackAuthenticatedRequest(controller, {
        method: "GET", path: "/api/playback-sessions/" + active.sessionId + "/queue",
        body: "", timeoutMs: 10000, expectJson: true, interruptible: true
    })
    if result.interrupted or not result.ok or result.data = invalid or Type(result.data) <> "roAssociativeArray" then return false
    data = result.data
    if PorticoPlaybackSafeId(data.sessionId) <> active.sessionId or data.history = invalid or GetInterface(data.history, "ifArray") = invalid or data.history.Count() < 1 or data.history.Count() > 500 then return false
    previousEntryId = ""
    history = PorticoPlaybackQueueHistory(data.history)
    if history.Count() < 1 then return false
    for index = 0 to history.Count() - 1
        item = history[index]
        if item.entryId <> active.currentQueueEntryId
            previousEntryId = item.entryId
            exit for
        end if
    end for
    if previousEntryId = "" then return false
    return PorticoPlaybackAdvanceNext(controller, false, previousEntryId, true)
end function

function PorticoPlaybackHandoffEntry(controller as object, entryId as string, disposition as string, startSeconds = invalid as dynamic) as boolean
    if controller.playback = invalid or entryId = "" then return false
    direct = {sessionId: "", entryId: entryId, queueRevision: controller.playback.queueRevision, playbackRevision: controller.playback.playbackRevision}
    return PorticoPlaybackCommitHandoff(controller, direct, disposition, startSeconds, false)
end function

function PorticoPlaybackCommitHandoff(controller as object, prepared as object, disposition as string, startSeconds as dynamic, autoplay as boolean) as boolean
    if controller.playback = invalid or controller.pendingMutation <> invalid then return false
    activeSessionId = controller.playback.sessionId
    terminalRequest = PorticoPlaybackTerminalRequest(controller, controller.playback, disposition)
    if terminalRequest = invalid then return false
    profile = PorticoPlaybackClientProfileForPreferences(controller.preferences)
    body = {
        requestId: terminalRequest.requestId,
        entryId: prepared.entryId,
        previousTerminal: terminalRequest.terminal,
        clientProfile: profile,
        intent: PorticoPlaybackPortableIntent(controller.preferences, profile)
    }
    if prepared.sessionId <> "" then body.preparedSessionId = prepared.sessionId
    if prepared.queueRevision >= 0 then body.expectedQueueRevision = prepared.queueRevision
    if prepared.playbackRevision >= 0 then body.expectedPlaybackRevision = prepared.playbackRevision
    if startSeconds <> invalid then body.startSeconds = PorticoPlaybackBoundedSeconds(startSeconds, 0)
    mutation = PorticoPlaybackPendingMutation(controller, "handoff", activeSessionId, body, terminalRequest, "", "", "", autoplay)
    if not PorticoPlaybackPersistPendingMutation(controller, mutation)
        controller.status = "error"
        controller.errorCode = "playback-terminal-storage-unavailable"
        PorticoPlaybackPublish(controller, false)
        return false
    end if
    controller.pendingMutation = mutation
    controller.heartbeatScheduled = false
    controller.preparedNext = invalid
    controller.preparedHandoffStarted = true
    PorticoPlaybackDispatchPendingMutation(controller)
    return controller.pendingMutation = invalid and controller.playback <> invalid and controller.playback.sessionId <> activeSessionId
end function

function PorticoPlaybackNextFailed(controller as object, autoplay as boolean) as boolean
    if not autoplay and controller.playback <> invalid
        controller.status = controller.playerState
        controller.errorCode = "next-playback-unavailable"
        PorticoPlaybackPublish(controller, false)
    end if
    return false
end function

function PorticoPlaybackSelectQuality(controller as object, selectionKey as string) as boolean
    if controller.playback = invalid or controller.playback.isLive = true or controller.playback.streamFormat <> "hls" then return false
    selection = PorticoPlaybackQualitySelectionFor(controller.playback, selectionKey)
    if selection = invalid then return false
    if PorticoPlaybackRenegotiateSelection(controller, selection, controller.playback.selectedAudioStreamId, controller.playback.selectedSubtitleStreamId, controller.playback.selectedSubtitleMode) then return true
    PorticoPlaybackSelectionFailed(controller)
    return false
end function

function PorticoPlaybackQualitySelectionFor(playback as object, selectionKey as string) as dynamic
    if selectionKey = "" then return invalid
    for each offer in playback.qualityOffers.offers
        if offer.kind = "automatic" and selectionKey = "automatic" then return {mode: "automatic"}
        if offer.selectionId = selectionKey
            if offer.kind = "automatic" then return {mode: "automatic"}
            return {mode: "explicit", selectionId: offer.selectionId, qualityOfferRevision: playback.qualityOffers.offerRevision}
        end if
    end for
    return invalid
end function

sub PorticoPlaybackSelectAudio(controller as object, audioId as string)
    if controller.playback = invalid or controller.playback.isLive = true or controller.playback.targetKind <> "vod" then return
    found = false
    for each stream in controller.playback.audioStreams
        if stream.id = audioId then found = true
    end for
    if not found or audioId = controller.playback.selectedAudioStreamId then return
    if not PorticoPlaybackRenegotiateSelection(controller, invalid, audioId, controller.playback.selectedSubtitleStreamId, controller.playback.selectedSubtitleMode)
        PorticoPlaybackSelectionFailed(controller)
    end if
end sub

sub PorticoPlaybackSelectSubtitle(controller as object, subtitleId as string, off as boolean)
    if controller.playback = invalid or controller.playback.isLive = true or controller.playback.targetKind <> "vod" then return
    if off
        if not PorticoPlaybackRenegotiateSelection(controller, invalid, controller.playback.selectedAudioStreamId, "", "off")
            PorticoPlaybackSelectionFailed(controller)
        end if
        return
    end if
    target = invalid
    for each stream in controller.playback.subtitleStreams
        if stream.id = subtitleId then target = stream
    end for
    if target = invalid then return
    mode = "text"
    if target.sourceUrl = "" then mode = "burn_in"
    if not PorticoPlaybackRenegotiateSelection(controller, invalid, controller.playback.selectedAudioStreamId, subtitleId, mode)
        PorticoPlaybackSelectionFailed(controller)
    end if
end sub

function PorticoPlaybackRenegotiateSelection(controller as object, qualitySelection as dynamic, audioId as string, subtitleId as string, subtitleMode as string) as boolean
    if controller.playback = invalid then return false
    active = controller.playback
    normalizedMode = LCase(subtitleMode)
    if normalizedMode <> "off" and normalizedMode <> "text" and normalizedMode <> "burn_in" then return false
    if normalizedMode = "off" then subtitleId = ""
    profile = PorticoPlaybackClientProfileForPreferences(controller.preferences)
    body = {
        requestId: PorticoPlaybackRenegotiationRequestId(controller),
        expectedRevision: active.playbackRevision,
        clientProfile: profile,
        subtitleMode: normalizedMode
    }
    if qualitySelection <> invalid then body.quality = qualitySelection
    if audioId <> "" then body.audioStreamId = audioId
    if subtitleId <> "" then body.subtitleStreamId = subtitleId
    result = PorticoPlaybackAuthenticatedRequest(controller, {
        method: "POST",
        path: "/api/playback-sessions/" + active.sessionId + "/renegotiate",
        body: body,
        timeoutMs: 20000,
        expectJson: true,
        interruptible: true
    })
    if result.interrupted or not result.ok then return false
    replacement = PorticoPlaybackFromResponse(result.data, controller.serverSession)
    if replacement = invalid or replacement.sessionId <> active.sessionId or replacement.queueRevision <> active.queueRevision or replacement.playbackRevision < active.playbackRevision then return false
    preflight = PorticoPlaybackPreflightSource(controller, replacement)
    if not preflight.ok then return false
    replacement.targetKind = active.targetKind
    replacement.queue = active.queue
    replacement.repeatMode = active.repeatMode
    replacement.nextEventSequence = active.nextEventSequence
    replacement.resumePositionSeconds = controller.positionSeconds
    controller.playback = replacement
    controller.durationSeconds = replacement.durationSeconds
    controller.sourceGeneration = controller.sourceGeneration + 1
    controller.status = controller.playerState
    controller.errorCode = ""
    controller.grantRenewalFailures = 0
    controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
    controller.heartbeatScheduled = true
    PorticoPlaybackScheduleGrantRenewal(controller)
    PorticoPlaybackPublish(controller, false)
    return true
end function

function PorticoPlaybackRenegotiationRequestId(controller as object) as string
    if controller.playback = invalid then return "roku-renegotiation"
    return "roku-" + controller.playback.sessionId + "-" + controller.playback.playbackRevision.ToStr() + "-" + controller.clock.TotalMilliseconds().ToStr()
end function

sub PorticoPlaybackSelectionFailed(controller as object)
    if controller.playback = invalid then return
    controller.status = controller.playerState
    controller.errorCode = "playback-option-unavailable"
    PorticoPlaybackPublish(controller, false)
end sub

function PorticoPlaybackBeginPostplay(controller as object) as boolean
    if controller.playback = invalid or controller.preparedNext <> invalid or controller.playback.queue.Count() = 0 then return false
    active = controller.playback
    nextEntryId = active.queue[0].entryId
    if nextEntryId = "" then return false
    nextProfile = PorticoPlaybackClientProfileForPreferences(controller.preferences)
    prepareBody = {entryId: nextEntryId, clientProfile: nextProfile, intent: PorticoPlaybackPortableIntent(controller.preferences, nextProfile)}
    result = PorticoPlaybackAuthenticatedRequest(controller, {
        method: "POST",
        path: "/api/playback-sessions/" + active.sessionId + "/prepare-next",
        body: prepareBody,
        timeoutMs: 20000,
        expectJson: true,
        interruptible: true
    })
    if result.interrupted or not result.ok or result.data = invalid or Type(result.data) <> "roAssociativeArray" then return false
    preparedId = PorticoPlaybackSafeId(result.data.preparedSessionId)
    expiresAt = PorticoHttpScalarString(result.data.expiresAt, "")
    expiresIn = PorticoSignedDocumentSecondsUntil(expiresAt)
    preparedPlayback = invalid
    if result.data.playback <> invalid then preparedPlayback = PorticoPlaybackFromResponse(result.data.playback, controller.serverSession)
    preparedQueueRevision = PorticoPlaybackBoundedSeconds(result.data.queueRevision, -1)
    preparedPlaybackRevision = PorticoPlaybackBoundedSeconds(result.data.playbackRevision, -1)
    if preparedId = "" or expiresIn = invalid or expiresIn <= 2 or preparedPlayback = invalid or preparedQueueRevision < 0 or preparedPlaybackRevision < 0 then return false
    preparedPlayback.targetKind = "vod"
    controller.preparedNext = {sessionId: preparedId, entryId: nextEntryId, expiresAt: expiresAt, playback: preparedPlayback, queueRevision: preparedQueueRevision, playbackRevision: preparedPlaybackRevision}
    controller.preparedHandoffStarted = false
    controller.playerState = "paused"
    controller.status = "postplay"
    controller.errorCode = ""
    controller.postplayPhase = "manual"
    controller.postplayDeadlineAt = 0
    controller.stillWatchingRequired = false
    if controller.watchAuthority <> "participant"
        inactiveFor = controller.clock.TotalSeconds() - controller.lastMeaningfulInteractionAt
        threshold = controller.preferences.passoutAfterEpisodes
        if controller.preferences.passoutProtection and (controller.automaticAdvances >= threshold or inactiveFor >= 7200)
            controller.stillWatchingRequired = true
            controller.postplayPhase = "still-watching"
        else if controller.preferences.upNextCountdownSeconds > 0
            delay = controller.preferences.upNextCountdownSeconds
            if delay > expiresIn - 2 then delay = expiresIn - 2
            if delay > 0
                controller.postplayPhase = "countdown"
                controller.postplayDeadlineAt = controller.clock.TotalSeconds() + delay
            end if
        end if
    end if
    PorticoPlaybackPublish(controller, false)
    return true
end function

function PorticoPlaybackHandoffPrepared(controller as object) as boolean
    if controller.playback = invalid or controller.preparedNext = invalid or controller.preparedHandoffStarted then return false
    remaining = PorticoSignedDocumentSecondsUntil(controller.preparedNext.expiresAt)
    if remaining = invalid or remaining <= 1
        PorticoPlaybackCancelPostplay(controller)
        return false
    end if
    prepared = controller.preparedNext
    return PorticoPlaybackCommitHandoff(controller, prepared, "completed", invalid, true)
end function

sub PorticoPlaybackCancelPostplay(controller as object)
    ' Prepared capabilities are not playback sessions. Discard locally and let
    ' the short server-issued capability expire.
    controller.preparedNext = invalid
    controller.preparedHandoffStarted = false
    controller.postplayPhase = "cancelled"
    controller.postplayDeadlineAt = 0
    controller.stillWatchingRequired = false
    if controller.playback <> invalid
        PorticoPlaybackBeginTerminal(controller, controller.playback, "completed", "ended", "", "")
        return
    end if
    PorticoPlaybackResetActive(controller)
    controller.status = "ended"
    controller.errorCode = ""
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackResetAutomation(controller as object, meaningfulInteraction as boolean)
    ' Preparation is a capability, not an active playback session.
    controller.preparedNext = invalid
    controller.preparedHandoffStarted = false
    controller.postplayPhase = "inactive"
    controller.postplayDeadlineAt = 0
    controller.stillWatchingRequired = false
    controller.dismissedSegmentIds = {}
    controller.segmentDirective = invalid
    if meaningfulInteraction
        controller.automaticAdvances = 0
        controller.lastMeaningfulInteractionAt = controller.clock.TotalSeconds()
    end if
end sub

sub PorticoPlaybackEvaluateSegment(controller as object)
    if controller.playback = invalid or controller.playback.isLive then return
    active = invalid
    for each segment in controller.playback.segments
        if controller.dismissedSegmentIds[segment.id] <> true and controller.positionSeconds >= segment.startSeconds and controller.positionSeconds < segment.endSeconds then active = segment
    end for
    if active = invalid
        controller.segmentDirective = invalid
        return
    end if
    behavior = controller.preferences.introSkip
    if active.type = "credits" then behavior = controller.preferences.creditsSkip
    if behavior = "off"
        controller.dismissedSegmentIds[active.id] = true
        controller.segmentDirective = invalid
    else if behavior = "automatic" and active.automaticSafe and controller.watchAuthority <> "participant"
        controller.dismissedSegmentIds[active.id] = true
        controller.segmentDirective = {type: "seek", id: active.id, positionSeconds: active.endSeconds}
    else
        controller.segmentDirective = {type: "prompt", id: active.id, segmentType: active.type, positionSeconds: active.endSeconds}
    end if
end sub

sub PorticoPlaybackSkipSegment(controller as object, segmentId as string)
    if controller.playback = invalid or segmentId = "" or controller.watchAuthority = "participant" then return
    for each segment in controller.playback.segments
        if segment.id = segmentId
            controller.dismissedSegmentIds[segment.id] = true
            controller.segmentDirective = {type: "seek", id: segment.id, positionSeconds: segment.endSeconds}
            controller.lastMeaningfulInteractionAt = controller.clock.TotalSeconds()
            controller.automaticAdvances = 0
            PorticoPlaybackPublish(controller, false)
            return
        end if
    end for
end sub

sub PorticoPlaybackSetSpeed(controller as object, value as dynamic)
    if controller.playback = invalid or controller.playback.isLive then return
    speed = PorticoPlaybackPreferenceSpeed(value, -1.0)
    if speed < 0 then return
    mediaType = controller.playback.mediaType
    if mediaType <> "audiobook" and mediaType <> "book" and mediaType <> "track" and mediaType <> "music" then return
    controller.playbackRate = speed
    controller.lastMeaningfulInteractionAt = controller.clock.TotalSeconds()
    controller.automaticAdvances = 0
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackSetSleepTimer(controller as object, modeValue as dynamic)
    if controller.playback = invalid then return
    mode = LCase(PorticoCoreSafeText(modeValue, 24))
    allowed = {off: true, "end-of-item": true, "15": true, "30": true, "45": true, "60": true}
    if allowed[mode] <> true then return
    controller.sleepTimerMode = mode
    controller.sleepTimerDeadlineAt = 0
    if mode <> "off" and mode <> "end-of-item" then controller.sleepTimerDeadlineAt = controller.clock.TotalSeconds() + (Int(Val(mode)) * 60)
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackQueueMutation(controller as object, kind as string, command as object)
    if controller.playback = invalid or controller.watchAuthority <> "independent" then return
    action = ""
    if kind = "queue-append" then action = "append"
    if kind = "queue-play-next" then action = "play_next"
    if kind = "queue-remove" then action = "remove"
    if kind = "queue-reorder" then action = "reorder"
    if kind = "queue-shuffle" then action = "shuffle"
    if kind = "queue-clear" then action = "clear"
    if kind = "set-repeat-mode" then action = "set_repeat"
    if action = "" then return
    body = {expectedRevision: controller.playback.queueRevision, idempotencyKey: PorticoHttpNewRequestId(), action: action}
    mediaId = PorticoPlaybackSafeId(command.mediaId)
    if action = "append" or action = "play_next"
        if mediaId = "" then return
        body.mediaId = mediaId
    else if action = "remove"
        entryId = PorticoPlaybackSafeId(command.entryId)
        if entryId = "" then return
        body.entryId = entryId
    else if action = "reorder"
        entryId = PorticoPlaybackSafeId(command.entryId)
        destinationEntryId = PorticoPlaybackSafeId(command.destinationEntryId)
        placement = LCase(PorticoCoreSafeText(command.placement, 8))
        if entryId = "" or destinationEntryId = "" or entryId = destinationEntryId or (placement <> "before" and placement <> "after") then return
        body.entryId = entryId
        body.destinationEntryId = destinationEntryId
        body.placement = placement
    else if action = "set_repeat"
        repeatMode = LCase(PorticoCoreSafeText(command.repeatMode, 8))
        if repeatMode <> "off" and repeatMode <> "one" and repeatMode <> "all" then return
        body.repeatMode = repeatMode
    end if
    result = PorticoPlaybackAuthenticatedRequest(controller, {
        method: "PATCH",
        path: "/api/playback-sessions/" + controller.playback.sessionId + "/queue",
        body: body,
        timeoutMs: 12000,
        expectJson: true,
        interruptible: true
    })
    if result.interrupted then return
    if not result.ok
        if result.status = 409
            PorticoPlaybackRefreshQueue(controller)
        else
            controller.errorCode = "playback-queue-update-failed"
            PorticoPlaybackPublish(controller, false)
        end if
        return
    end if
    PorticoPlaybackAdoptQueueResponse(controller, result.data)
end sub

sub PorticoPlaybackRefreshQueue(controller as object)
    if controller.playback = invalid then return
    result = PorticoPlaybackAuthenticatedRequest(controller, {
        method: "GET", path: "/api/playback-sessions/" + controller.playback.sessionId + "/queue",
        body: "", timeoutMs: 10000, expectJson: true, interruptible: true
    })
    if result.interrupted then return
    if not result.ok
        controller.errorCode = "playback-queue-refresh-failed"
        PorticoPlaybackPublish(controller, false)
        return
    end if
    PorticoPlaybackAdoptQueueResponse(controller, result.data)
end sub

sub PorticoPlaybackAdoptQueueResponse(controller as object, data as dynamic)
    if data = invalid or Type(data) <> "roAssociativeArray" or controller.playback = invalid then return
    if PorticoPlaybackSafeId(data.sessionId) <> controller.playback.sessionId then return
    revision = PorticoPlaybackBoundedSeconds(data.revision, -1)
    if revision < controller.playback.queueRevision then return
    queue = PorticoPlaybackQueue(data.items)
    current = PorticoPlaybackQueue([data.current])
    if current.Count() <> 1 then return
    repeatMode = LCase(PorticoCoreSafeText(data.repeatMode, 8))
    if repeatMode <> "off" and repeatMode <> "one" and repeatMode <> "all" then return
    controller.playback.queue = queue
    controller.playback.currentQueueEntryId = current[0].entryId
    controller.playback.queueRevision = revision
    controller.playback.repeatMode = repeatMode
    controller.errorCode = ""
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackTick(controller as object)
    if controller.pendingMutation <> invalid
        PorticoPlaybackDispatchPendingMutation(controller)
        return
    end if
    if controller.playback = invalid then return
    nowSeconds = controller.clock.TotalSeconds()
    if controller.sourceRecoveryAttempts > 0 and controller.sourceRecoveryPending <> true and controller.sourceRecoveryStableSince > 0 and nowSeconds - controller.sourceRecoveryStableSince >= 15
        controller.sourceRecoveryAttempts = 0
        controller.sourceRecoveryStableSince = 0
    end if
    if controller.postplayPhase = "countdown" and controller.postplayDeadlineAt > 0
        remaining = controller.postplayDeadlineAt - nowSeconds
        if remaining < 0 then remaining = 0
        if remaining <> controller.lastPublishedPostplayCountdown
            controller.lastPublishedPostplayCountdown = remaining
            PorticoPlaybackPublish(controller, false)
        end if
    end if
    if controller.postplayPhase = "countdown" and controller.postplayDeadlineAt > 0 and nowSeconds >= controller.postplayDeadlineAt
        controller.postplayDeadlineAt = 0
        if controller.watchAuthority <> "participant" then PorticoPlaybackHandoffPrepared(controller)
        return
    end if
    if controller.sleepTimerDeadlineAt > 0 and nowSeconds >= controller.sleepTimerDeadlineAt
        PorticoPlaybackStopActive(controller, true)
        return
    end if
    if controller.grantRenewalScheduled and nowSeconds >= controller.nextGrantRenewalAtSeconds
        PorticoPlaybackRenewGrant(controller, false)
        return
    end if
    if controller.heartbeatScheduled and nowSeconds >= controller.nextHeartbeatAtSeconds
        PorticoPlaybackSendProgress(controller)
        controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
        controller.heartbeatScheduled = true
    end if
end sub

sub PorticoPlaybackSendProgress(controller as object)
    if controller.playback = invalid or controller.pendingMutation <> invalid then return
    state = controller.playerState
    if state <> "playing" and state <> "paused" and state <> "buffering" then state = "paused"
    controller.progressPending = {
        recordedAt: PorticoPlaybackUTCNowString(),
        progressSeconds: controller.positionSeconds,
        positionSeconds: controller.positionSeconds,
        durationSeconds: controller.durationSeconds,
        state: state,
        isPlaying: state = "playing"
    }
    PorticoPlaybackDispatchProgress(controller)
end sub

sub PorticoPlaybackDispatchProgress(controller as object)
    if controller.playback = invalid or controller.pendingMutation <> invalid or controller.progressPending = invalid or controller.progressRequest <> invalid then return
    session = PorticoPlaybackCurrentServerSession(controller)
    if session = invalid
        controller.progressPending = invalid
        PorticoPlaybackRequestReconnect(controller)
        return
    end if
    sequence = controller.playback.nextEventSequence
    if sequence < 1 then sequence = 1
    controller.playback.nextEventSequence = sequence + 1
    pending = controller.progressPending
    controller.progressPending = invalid
    body = {
        generation: controller.playback.sessionGeneration,
        eventSequence: sequence,
        recordedAt: pending.recordedAt,
        progressSeconds: pending.progressSeconds,
        positionSeconds: pending.positionSeconds,
        durationSeconds: pending.durationSeconds,
        state: pending.state,
        isPlaying: pending.isPlaying
    }
    request = PorticoHttpNormalizeRequest({
        method: "PATCH",
        url: session.apiBaseUrl + "/api/playback-sessions/" + controller.playback.sessionId,
        body: body,
        headers: {Authorization: "Bearer " + session.accessToken},
        timeoutMs: 10000,
        expectJson: true,
        allowInsecureLan: session.allowInsecureLan = true
    })
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok
        PorticoPlaybackProgressFailure(controller, 0, validation.code)
        return
    end if
    if controller.progressPort = invalid then controller.progressPort = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid or controller.progressPort = invalid
        PorticoPlaybackProgressFailure(controller, 0, "transport_error")
        return
    end if
    transfer.SetMessagePort(controller.progressPort)
    transfer.SetUrl(request.url)
    transfer.SetRequest("PATCH")
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if Left(LCase(request.url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") or not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true)
            PorticoPlaybackProgressFailure(controller, 0, "transport_error")
            return
        end if
    end if
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName])
            PorticoPlaybackProgressFailure(controller, 0, "invalid_header")
            return
        end if
    end for
    if not transfer.AsyncPostFromString(request.body)
        PorticoPlaybackProgressFailure(controller, 0, "transport_error")
        return
    end if
    controller.progressRequest = {
        transfer: transfer,
        identity: transfer.GetIdentity(),
        body: request.body,
        sessionId: controller.playback.sessionId,
        playbackGeneration: controller.playbackGeneration,
        sessionGeneration: session.generation,
        eventSequence: sequence,
        deadlineAt: controller.clock.TotalSeconds() + 10,
        retried: false
    }
end sub

sub PorticoPlaybackPollProgress(controller as object)
    if controller.progressRequest = invalid or controller.progressPort = invalid then return
    if controller.progressRequest.deadlineAt > 0 and controller.clock.TotalSeconds() >= controller.progressRequest.deadlineAt
        controller.progressRequest.transfer.AsyncCancel()
        controller.progressRequest = invalid
        PorticoPlaybackProgressFailure(controller, 0, "timeout")
        return
    end if
    for index = 1 to 4
        message = controller.progressPort.GetMessage()
        if message = invalid then exit for
        request = controller.progressRequest
        if Type(message) <> "roUrlEvent" or message.GetSourceIdentity() <> request.identity then exit for
        controller.progressRequest = invalid
        status = message.GetResponseCode()
        if status = 401 and not request.retried
            replacement = PorticoPlaybackSessionForController(controller)
            if replacement <> invalid and replacement.generation > request.sessionGeneration and replacement.accessToken <> ""
                controller.serverSession = replacement
                PorticoPlaybackReplayProgress(controller, request.body, replacement, request.eventSequence)
                return
            end if
        end if
        if status < 0
            PorticoPlaybackProgressFailure(controller, status, "transport_error")
            return
        end if
        classification = PorticoHttpClassifyStatus(status)
        if classification.classification <> "success"
            PorticoPlaybackProgressFailure(controller, status, classification.classification)
            return
        end if
        payload = message.GetString()
        if Len(payload) > PorticoHttpLimits().maximumResponseBytes
            PorticoPlaybackProgressFailure(controller, status, "response_too_large")
            return
        end if
        parsed = PorticoHttpParseJson(payload)
        if not parsed.ok or not PorticoPlaybackAdoptProgressAcknowledgement(controller, request, parsed.value)
            PorticoPlaybackProgressFailure(controller, status, "progress-response-incompatible")
            return
        end if
        controller.errorCode = ""
        PorticoPlaybackDispatchProgress(controller)
        return
    end for
end sub

sub PorticoPlaybackReplayProgress(controller as object, body as string, session as object, eventSequence = 0 as integer)
    request = PorticoHttpNormalizeRequest({method: "PATCH", url: session.apiBaseUrl + "/api/playback-sessions/" + controller.playback.sessionId, body: body, headers: {Authorization: "Bearer " + session.accessToken}, timeoutMs: 10000, expectJson: true, allowInsecureLan: session.allowInsecureLan = true})
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok
        PorticoPlaybackProgressFailure(controller, 0, validation.code)
        return
    end if
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid
        PorticoPlaybackProgressFailure(controller, 0, "transport_error")
        return
    end if
    transfer.SetMessagePort(controller.progressPort)
    transfer.SetUrl(request.url)
    transfer.SetRequest("PATCH")
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if Left(LCase(request.url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") or not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true)
            PorticoPlaybackProgressFailure(controller, 0, "transport_error")
            return
        end if
    end if
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName])
            PorticoPlaybackProgressFailure(controller, 0, "invalid_header")
            return
        end if
    end for
    if not transfer.AsyncPostFromString(request.body)
        PorticoPlaybackProgressFailure(controller, 0, "transport_error")
        return
    end if
    controller.progressRequest = {transfer: transfer, identity: transfer.GetIdentity(), body: request.body, eventSequence: eventSequence, sessionId: controller.playback.sessionId, playbackGeneration: controller.playbackGeneration, sessionGeneration: session.generation, deadlineAt: controller.clock.TotalSeconds() + 10, retried: true}
end sub

function PorticoPlaybackAdoptProgressAcknowledgement(controller as object, request as object, acknowledgement as dynamic) as boolean
    if controller.playback = invalid then return false
    if request.sessionId <> controller.playback.sessionId or request.playbackGeneration <> controller.playbackGeneration then return true
    if acknowledgement = invalid or Type(acknowledgement) <> "roAssociativeArray" then return false
    if not PorticoPlaybackIsBoolean(acknowledgement.accepted) or not PorticoPlaybackIsBoolean(acknowledgement.duplicate) or not PorticoPlaybackIsBoolean(acknowledgement.stale) then return false
    if acknowledgement.accepted <> true and acknowledgement.duplicate <> true and acknowledgement.stale <> true then return false
    highest = PorticoHttpInteger(acknowledgement.highestEventSequence, 0)
    if highest < 0 or highest >= 2147480000 then return false
    if request.eventSequence > 0 and highest < request.eventSequence then return false
    if highest >= controller.playback.nextEventSequence then controller.playback.nextEventSequence = highest + 1
    grantSemantics = LCase(PorticoHttpScalarString(acknowledgement.grantSemantics, ""))
    if grantSemantics <> "" and grantSemantics <> "extension" and grantSemantics <> "rotation" then return false
    grantExpiry = PorticoHttpScalarString(acknowledgement.mediaGrantExpiresAt, "")
    if grantExpiry <> ""
        grantRemaining = PorticoSignedDocumentSecondsUntil(grantExpiry)
        if grantRemaining = invalid or grantRemaining <= 0 then return false
        controller.playback.grantExpiresAt = grantExpiry
        PorticoPlaybackScheduleGrantRenewal(controller)
    end if
    return true
end function

sub PorticoPlaybackProgressFailure(controller as object, status as integer, code as string)
    if controller.pendingMutation <> invalid and controller.pendingMutation.kind = "replacement"
        controller.errorCode = "playback-terminal-delayed"
        PorticoPlaybackPublish(controller, status = 401)
        return
    end if
    if status = 401
        PorticoPlaybackRequestReconnect(controller)
    else if status = 403 or status = 404
        PorticoPlaybackFail(controller, "playback-session-ended", false)
    else
        controller.errorCode = "progress-report-delayed"
        if code = "progress-response-incompatible" then controller.errorCode = code
        PorticoPlaybackPublish(controller, false)
    end if
    PorticoPlaybackDispatchProgress(controller)
end sub

function PorticoPlaybackTerminalRequest(controller as object, playback as object, disposition as string) as dynamic
    if playback = invalid or (disposition <> "stopped" and disposition <> "completed") then return invalid
    generation = PorticoPlaybackBoundedSeconds(playback.sessionGeneration, 0)
    sequence = PorticoPlaybackBoundedSeconds(playback.nextEventSequence, 0)
    recordedAt = PorticoPlaybackUTCNowString()
    if generation < 1 or sequence < 1 or recordedAt = "" then return invalid
    positionSeconds = PorticoPlaybackClampToTimeline(playback, controller.positionSeconds, 0)
    durationSeconds = PorticoPlaybackBoundedSeconds(controller.durationSeconds, PorticoPlaybackBoundedSeconds(playback.durationSeconds, 0))
    if disposition = "completed"
        if durationSeconds < 1 then return invalid
        positionSeconds = durationSeconds
    end if
    requestId = PorticoHttpNewRequestId()
    if Len(requestId) < 8 then return invalid
    playback.nextEventSequence = sequence + 1
    return {
        requestId: requestId,
        terminal: {
            disposition: disposition,
            generation: generation,
            eventSequence: sequence,
            recordedAt: recordedAt,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        }
    }
end function

function PorticoPlaybackPendingReplacement(controller as object, playback as object, path as string, body as object, targetKind as string, targetId as string, terminalRequest as object) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    safePath = PorticoPlaybackReplacementPath(targetKind, targetId)
    if scope = invalid or playback = invalid or safePath = "" or path <> safePath then return invalid
    encodedBody = FormatJson(body)
    if encodedBody = "" then return invalid
    return {
        version: 1,
        purpose: "playback-ordered-mutation",
        kind: "replacement",
        viewerScope: scope,
        sessionId: playback.sessionId,
        path: safePath,
        body: encodedBody,
        requestId: terminalRequest.requestId,
        terminal: terminalRequest.terminal,
        disposition: "stopped",
        targetKind: targetKind,
        targetId: targetId,
        attempts: 0,
        nextRetryAt: controller.clock.TotalSeconds()
    }
end function

function PorticoPlaybackReplacementPath(targetKind as string, targetId as string) as string
    safeId = PorticoPlaybackSafeId(targetId)
    if safeId = "" or safeId <> targetId then return ""
    if targetKind = "vod" then return "/api/playback-sessions"
    if targetKind = "live" then return "/api/live-tv/play"
    if targetKind = "dvr" then return "/api/dvr/recordings/" + safeId + "/playback"
    if targetKind = "library-channel" then return "/api/library-channels/" + safeId + "/tune"
    return ""
end function

function PorticoPlaybackPendingMutation(controller as object, kind as string, sessionId as string, body as object, terminalRequest as object, finalStatus as string, finalError as string, remoteMessage as string, autoplay as boolean) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if scope = invalid or sessionId = "" or (kind <> "terminal" and kind <> "handoff") then return invalid
    path = "/api/playback-sessions/" + sessionId
    if kind = "handoff" then path = path + "/handoff"
    encodedBody = FormatJson(body)
    if encodedBody = "" then return invalid
    return {
        version: 1,
        purpose: "playback-ordered-mutation",
        kind: kind,
        viewerScope: scope,
        sessionId: sessionId,
        path: path,
        body: encodedBody,
        requestId: terminalRequest.requestId,
        terminal: terminalRequest.terminal,
        disposition: terminalRequest.terminal.disposition,
        finalStatus: finalStatus,
        finalError: finalError,
        remoteMessage: remoteMessage,
        autoplay: autoplay,
        attempts: 0,
        nextRetryAt: controller.clock.TotalSeconds()
    }
end function

function PorticoPlaybackPersistPendingMutation(controller as object, mutation as dynamic) as boolean
    if mutation = invalid or Type(mutation) <> "roAssociativeArray" then return false
    return PorticoSecureRegistryCommit("playback-mutation", mutation).ok
end function

sub PorticoPlaybackRestorePendingMutation(controller as object)
    if controller.pendingMutation <> invalid or controller.pendingMutationRestored then return
    controller.pendingMutationRestored = true
    record = PorticoSecureRegistryRead("playback-mutation")
    if not record.ok
        controller.errorCode = "playback-terminal-storage-unavailable"
        return
    end if
    if record.payload = invalid then return
    pending = record.payload
    scope = PorticoViewerScopeNormalize(pending.viewerScope)
    currentScope = PorticoViewerScopeNormalize(controller.viewerScope)
    kind = LCase(PorticoCoreSafeText(pending.kind, 16))
    sessionId = PorticoPlaybackSafeId(pending.sessionId)
    requestId = PorticoPlaybackSafeRequestId(pending.requestId)
    body = PorticoHttpScalarString(pending.body, "")
    if pending.version <> 1 or pending.purpose <> "playback-ordered-mutation" or scope = invalid or currentScope = invalid or not PorticoViewerScopeAuthorizationEquals(scope, currentScope) then return
    if (kind <> "terminal" and kind <> "handoff" and kind <> "replacement") or sessionId = "" or requestId = "" or Len(body) < 2 or Len(body) > PorticoHttpLimits().maximumBodyBytes
        controller.errorCode = "playback-terminal-storage-unavailable"
        return
    end if
    parsedBody = PorticoHttpParseJson(body)
    if not parsedBody.ok or parsedBody.value = invalid or Type(parsedBody.value) <> "roAssociativeArray"
        controller.errorCode = "playback-terminal-storage-unavailable"
        return
    end if
    parsedRequestId = PorticoPlaybackSafeRequestId(parsedBody.value.requestId)
    if kind = "replacement" and parsedBody.value.replacement <> invalid then parsedRequestId = PorticoPlaybackSafeRequestId(parsedBody.value.replacement.requestId)
    if parsedRequestId <> requestId
        controller.errorCode = "playback-terminal-storage-unavailable"
        return
    end if
    bodyTerminal = parsedBody.value.terminal
    if kind = "handoff" then bodyTerminal = parsedBody.value.previousTerminal
    if kind = "replacement"
        targetKind = LCase(PorticoCoreSafeText(pending.targetKind, 32))
        targetId = PorticoPlaybackSafeId(pending.targetId)
        committedReplacementSessionId = ""
        if pending.committedReplacementSessionId <> invalid
            committedReplacementSessionId = PorticoPlaybackSafeId(pending.committedReplacementSessionId)
            if committedReplacementSessionId = ""
                controller.errorCode = "playback-terminal-storage-unavailable"
                return
            end if
        end if
        restoredPath = PorticoPlaybackReplacementPath(targetKind, targetId)
        envelope = parsedBody.value.replacement
        if restoredPath = "" or envelope = invalid or Type(envelope) <> "roAssociativeArray" or PorticoPlaybackSafeId(envelope.sourceSessionId) <> sessionId or PorticoPlaybackSafeRequestId(envelope.requestId) <> requestId
            controller.errorCode = "playback-terminal-storage-unavailable"
            return
        end if
        if PorticoPlaybackBoundedSeconds(envelope.expectedQueueRevision, -1) < 0 or PorticoPlaybackBoundedSeconds(envelope.expectedPlaybackRevision, -1) < 0
            controller.errorCode = "playback-terminal-storage-unavailable"
            return
        end if
        targetMatches = true
        if targetKind = "vod" and PorticoPlaybackSafeId(parsedBody.value.mediaId) <> targetId then targetMatches = false
        if targetKind = "live" and PorticoPlaybackSafeId(parsedBody.value.channelId) <> targetId then targetMatches = false
        if not targetMatches
            controller.errorCode = "playback-terminal-storage-unavailable"
            return
        end if
        bodyTerminal = envelope.previousTerminal
        pending.targetKind = targetKind
        pending.targetId = targetId
        pending.path = restoredPath
        if committedReplacementSessionId <> "" then pending.committedReplacementSessionId = committedReplacementSessionId
    end if
    if not PorticoPlaybackTerminalEventsEqual(pending.terminal, bodyTerminal)
        controller.errorCode = "playback-terminal-storage-unavailable"
        return
    end if
    pending.kind = kind
    pending.sessionId = sessionId
    pending.requestId = requestId
    if kind <> "replacement"
        pending.path = "/api/playback-sessions/" + sessionId
        if kind = "handoff" then pending.path = pending.path + "/handoff"
    end if
    pending.attempts = 0
    pending.nextRetryAt = controller.clock.TotalSeconds()
    controller.pendingMutation = pending
end sub

function PorticoPlaybackSafeRequestId(value as dynamic) as string
    id = PorticoCoreSafeText(value, 128)
    if Len(id) < 8 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"
    for index = 1 to Len(id)
        if Instr(1, allowed, Mid(id, index, 1)) = 0 then return ""
    end for
    return id
end function

function PorticoPlaybackBeginTerminal(controller as object, playback as object, disposition as string, finalStatus as string, finalError as string, remoteMessage as string) as boolean
    if playback = invalid or controller.pendingMutation <> invalid then return false
    terminalRequest = PorticoPlaybackTerminalRequest(controller, playback, disposition)
    if terminalRequest = invalid then return false
    mutation = PorticoPlaybackPendingMutation(controller, "terminal", playback.sessionId, terminalRequest, terminalRequest, finalStatus, finalError, remoteMessage, false)
    if not PorticoPlaybackPersistPendingMutation(controller, mutation)
        controller.status = "error"
        controller.errorCode = "playback-terminal-storage-unavailable"
        PorticoPlaybackPublish(controller, false)
        return false
    end if
    controller.pendingMutation = mutation
    controller.heartbeatScheduled = false
    controller.status = "stopping"
    PorticoPlaybackPublish(controller, false)
    PorticoPlaybackDispatchPendingMutation(controller)
    return controller.pendingMutation = invalid
end function

sub PorticoPlaybackDispatchPendingMutation(controller as object)
    pending = controller.pendingMutation
    if pending = invalid or controller.clock.TotalSeconds() < pending.nextRetryAt then return
    if pending.kind = "replacement"
        committedReplacementSessionId = PorticoPlaybackSafeId(pending.committedReplacementSessionId)
        if committedReplacementSessionId <> ""
            PorticoPlaybackRestoreCommittedReplacement(controller, pending, committedReplacementSessionId)
            return
        end if
    end if
    method = "POST"
    if pending.kind = "terminal" then method = "DELETE"
    result = PorticoPlaybackAuthenticatedRequest(controller, {
        method: method,
        path: pending.path,
        body: pending.body,
        timeoutMs: 20000,
        expectJson: true,
        interruptible: false
    })
    if result.ok
        if pending.kind = "terminal"
            if PorticoPlaybackTerminalAcknowledgementMatches(pending, result.data)
                PorticoPlaybackAcceptTerminalMutation(controller, pending)
                return
            end if
        else if pending.kind = "handoff"
            replacement = PorticoPlaybackFromResponse(result.data, PorticoPlaybackCurrentServerSession(controller))
            if replacement <> invalid
                PorticoPlaybackAcceptHandoffMutation(controller, pending, replacement)
                return
            end if
        else
            playbackDocument = result.data
            if pending.targetKind = "library-channel" and playbackDocument <> invalid and Type(playbackDocument) = "roAssociativeArray" then playbackDocument = playbackDocument.playback
            replacement = PorticoPlaybackFromResponse(playbackDocument, PorticoPlaybackCurrentServerSession(controller))
            if replacement <> invalid
                PorticoPlaybackAcceptRouteReplacement(controller, pending, replacement)
                return
            end if
        end if
        PorticoPlaybackScheduleMutationRetry(controller, "playback-response-incompatible", false)
        return
    end if
    if pending.kind = "replacement" and result.serverCode = "playback_replacement_committed_restore_required"
        replacementSessionId = PorticoPlaybackSafeId(result.details.replacementSessionId)
        if replacementSessionId <> ""
            pending.committedReplacementSessionId = replacementSessionId
            if not PorticoPlaybackPersistPendingMutation(controller, pending)
                pending.Delete("committedReplacementSessionId")
                PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-storage-unavailable", false)
                return
            end if
            PorticoPlaybackRestoreCommittedReplacement(controller, pending, replacementSessionId)
            return
        end if
    end if
    if pending.kind = "replacement" and result.serverCode = "replacement_source_inactive"
        PorticoPlaybackDiscardInactiveReplacementSource(controller)
        return
    end if
    if pending.kind = "replacement" and PorticoPlaybackReplacementDefinitivelyRejected(result)
        PorticoPlaybackRejectRouteReplacement(controller)
        return
    end if
    if pending.kind = "handoff" and PorticoPlaybackMutationDefinitivelyRejected(result)
        if pending.disposition = "completed"
            PorticoPlaybackFallbackCompletedTerminal(controller, pending)
        else
            PorticoPlaybackRejectExplicitHandoff(controller)
        end if
        return
    end if
    PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-delayed", result.missingSession = true or result.status = 401)
end sub

sub PorticoPlaybackDiscardInactiveReplacementSource(controller as object)
    ' The authenticated Server has proved that the proposed source no longer
    ' owns playback. Fence it immediately; no terminal receipt may be invented.
    PorticoPlaybackDropProgress(controller)
    PorticoPlaybackResetActive(controller)
    controller.status = "error"
    controller.errorCode = "playback-source-inactive"
    if not PorticoPlaybackClearPendingMutation(controller)
        PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-storage-unavailable", false)
        return
    end if
    PorticoPlaybackPublish(controller, false)
end sub

function PorticoPlaybackReplacementDefinitivelyRejected(result as object) as boolean
    if result.interrupted or result.retryable or result.status = 401 or result.status = 404 or result.status = 408 then return false
    if result.status < 400 or result.status >= 500 then return false
    ambiguousCodes = {playback_terminal_request_conflict: true, playback_stopping: true, handoff_in_progress: true, prepared_handoff_in_progress: true}
    return ambiguousCodes[LCase(PorticoCoreSafeText(result.serverCode, 80))] <> true
end function

sub PorticoPlaybackRestoreCommittedReplacement(controller as object, pending as object, replacementSessionId as string)
    profile = PorticoPlaybackClientProfileForPreferences(controller.preferences)
    body = {clientInstanceId: PorticoInstallationId(), clientProfile: profile}
    if body.clientInstanceId = "" then body.Delete("clientInstanceId")
    result = PorticoPlaybackAuthenticatedRequest(controller, {method: "POST", path: "/api/playback/active", body: body, timeoutMs: 20000, expectJson: true, interruptible: false})
    if not result.ok or result.data = invalid or Type(result.data) <> "roAssociativeArray" or result.data.active <> true
        PorticoPlaybackScheduleMutationRetry(controller, "playback-replacement-restore-delayed", result.status = 401)
        return
    end if
    restored = PorticoPlaybackFromResponse(result.data.playback, PorticoPlaybackCurrentServerSession(controller))
    if restored = invalid or restored.sessionId <> replacementSessionId
        PorticoPlaybackScheduleMutationRetry(controller, "playback-response-incompatible", false)
        return
    end if
    PorticoPlaybackAcceptRouteReplacement(controller, pending, restored)
end sub

function PorticoPlaybackMutationDefinitivelyRejected(result as object) as boolean
    if result.interrupted or result.retryable then return false
    serverCode = LCase(PorticoCoreSafeText(result.serverCode, 80))
    definitiveNonCommitCodes = {
        handoff_request_id_invalid: true,
        previous_terminal_required: true,
        invalid_playback_disposition: true,
        invalid_playback_terminal_authority: true,
        invalid_recorded_at: true,
        invalid_playback_terminal_position: true,
        invalid_start_seconds: true,
        prepared_handoff_not_found: true,
        prepared_handoff_expired: true,
        prepared_handoff_scope_mismatch: true,
        prepared_handoff_entry_mismatch: true,
        handoff_not_supported: true,
        queue_entry_required: true,
        handoff_queue_revision_conflict: true,
        handoff_queue_entry_changed: true,
        handoff_playback_revision_conflict: true,
        playback_generation_stale: true,
        playback_event_sequence_stale: true
    }
    return definitiveNonCommitCodes[serverCode] = true
end function

sub PorticoPlaybackScheduleMutationRetry(controller as object, code as string, reconnectRequired as boolean)
    if controller.pendingMutation = invalid then return
    controller.pendingMutation.attempts = PorticoHttpInteger(controller.pendingMutation.attempts, 0) + 1
    exponent = controller.pendingMutation.attempts - 1
    if exponent > 4 then exponent = 4
    delaySeconds = 2 ^ exponent
    if delaySeconds > 30 then delaySeconds = 30
    controller.pendingMutation.nextRetryAt = controller.clock.TotalSeconds() + delaySeconds
    controller.errorCode = code
    PorticoPlaybackPublish(controller, reconnectRequired)
end sub

function PorticoPlaybackTerminalAcknowledgementMatches(pending as object, acknowledgement as dynamic) as boolean
    if acknowledgement = invalid or Type(acknowledgement) <> "roAssociativeArray" then return false
    if acknowledgement.accepted <> true or not PorticoPlaybackIsBoolean(acknowledgement.duplicate) then return false
    if PorticoPlaybackSafeRequestId(acknowledgement.requestId) <> pending.requestId or PorticoPlaybackSafeId(acknowledgement.sessionId) <> pending.sessionId then return false
    return PorticoPlaybackTerminalEventsEqual(pending.terminal, acknowledgement.terminal)
end function

function PorticoPlaybackTerminalEventsEqual(expected as dynamic, actual as dynamic) as boolean
    if expected = invalid or actual = invalid or Type(expected) <> "roAssociativeArray" or Type(actual) <> "roAssociativeArray" then return false
    if LCase(PorticoCoreSafeText(actual.disposition, 16)) <> expected.disposition then return false
    if PorticoHttpInteger(actual.generation, -1) <> expected.generation or PorticoHttpInteger(actual.eventSequence, -1) <> expected.eventSequence then return false
    if PorticoHttpScalarString(actual.recordedAt, "") <> expected.recordedAt then return false
    if PorticoPlaybackBoundedSeconds(actual.positionSeconds, -1) <> expected.positionSeconds then return false
    return PorticoPlaybackBoundedSeconds(actual.durationSeconds, -1) = expected.durationSeconds
end function

function PorticoPlaybackClearPendingMutation(controller as object) as boolean
    if not PorticoSecureRegistryClear("playback-mutation") then return false
    controller.pendingMutation = invalid
    return true
end function

sub PorticoPlaybackAcceptTerminalMutation(controller as object, pending as object)
    PorticoPlaybackDropProgress(controller)
    if not PorticoPlaybackClearPendingMutation(controller)
        PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-storage-unavailable", false)
        return
    end if
    pendingStart = controller.pendingStart
    PorticoPlaybackResetActive(controller)
    controller.status = pending.finalStatus
    if controller.status = "" then controller.status = "idle"
    controller.errorCode = pending.finalError
    controller.remoteStopMessage = pending.remoteMessage
    PorticoPlaybackPublish(controller, false)
    if pendingStart <> invalid then PorticoPlaybackStart(controller, pendingStart)
end sub

sub PorticoPlaybackAcceptHandoffMutation(controller as object, pending as object, replacement as object)
    PorticoPlaybackDropProgress(controller)
    if not PorticoPlaybackClearPendingMutation(controller)
        PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-storage-unavailable", false)
        return
    end if
    replacement.targetKind = "vod"
    preflight = PorticoPlaybackPreflightSource(controller, replacement)
    if not preflight.ok
        controller.playback = replacement
        controller.positionSeconds = replacement.resumePositionSeconds
        controller.durationSeconds = replacement.durationSeconds
        controller.preparedHandoffStarted = false
        PorticoPlaybackBeginTerminal(controller, replacement, "stopped", "error", "playback-source-unavailable", "")
        return
    end if
    PorticoPlaybackAdoptHandoffReplacement(controller, replacement, pending.autoplay = true)
end sub

sub PorticoPlaybackAcceptRouteReplacement(controller as object, pending as object, replacement as object)
    PorticoPlaybackDropProgress(controller)
    if not PorticoPlaybackClearPendingMutation(controller)
        PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-storage-unavailable", false)
        return
    end if
    replacement.targetKind = pending.targetKind
    preflight = PorticoPlaybackPreflightSource(controller, replacement)
    if not preflight.ok
        controller.playback = replacement
        controller.positionSeconds = replacement.resumePositionSeconds
        controller.durationSeconds = replacement.durationSeconds
        PorticoPlaybackBeginTerminal(controller, replacement, "stopped", "error", "playback-source-unavailable", "")
        return
    end if
    PorticoPlaybackAdoptRouteReplacement(controller, replacement, pending.targetKind, pending.targetId)
end sub

sub PorticoPlaybackAdoptRouteReplacement(controller as object, replacement as object, targetKind as string, targetId as string)
    controller.playback = replacement
    controller.lastTargetKind = targetKind
    controller.lastTargetId = targetId
    controller.playbackGeneration = controller.playbackGeneration + 1
    controller.sourceGeneration = controller.sourceGeneration + 1
    controller.playerState = "paused"
    controller.positionSeconds = replacement.resumePositionSeconds
    controller.durationSeconds = replacement.durationSeconds
    controller.status = "ready"
    controller.errorCode = ""
    controller.reconnectRequestedSessionGeneration = -1
    controller.grantRenewalFailures = 0
    controller.sourceRecoveryPending = false
    controller.sourceRecoveryAttempts = 0
    controller.sourceRecoveryStableSince = 0
    controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
    controller.heartbeatScheduled = true
    PorticoPlaybackResetAutomation(controller, true)
    PorticoPlaybackScheduleGrantRenewal(controller)
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackRejectRouteReplacement(controller as object)
    pending = controller.pendingMutation
    retained = invalid
    if controller.playback = invalid and pending <> invalid
        profile = PorticoPlaybackClientProfileForPreferences(controller.preferences)
        body = {clientInstanceId: PorticoInstallationId(), clientProfile: profile}
        if body.clientInstanceId = "" then body.Delete("clientInstanceId")
        restore = PorticoPlaybackAuthenticatedRequest(controller, {method: "POST", path: "/api/playback/active", body: body, timeoutMs: 20000, expectJson: true, interruptible: false})
        if restore.ok and restore.data <> invalid and Type(restore.data) = "roAssociativeArray" and restore.data.active = true
            candidate = PorticoPlaybackFromResponse(restore.data.playback, PorticoPlaybackCurrentServerSession(controller))
            if candidate <> invalid and candidate.sessionId = pending.sessionId then retained = candidate
        end if
    end if
    if not PorticoPlaybackClearPendingMutation(controller)
        PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-storage-unavailable", false)
        return
    end if
    if retained <> invalid
        retainedKind = "vod"
        if retained.isLive = true then retainedKind = "live"
        retained.targetKind = retainedKind
        preflight = PorticoPlaybackPreflightSource(controller, retained)
        if preflight.ok
            PorticoPlaybackAdoptRouteReplacement(controller, retained, retainedKind, retained.mediaId)
            controller.errorCode = "playback-replacement-rejected"
            PorticoPlaybackPublish(controller, false)
            return
        end if
    end if
    controller.status = controller.playerState
    controller.errorCode = "playback-replacement-rejected"
    controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
    controller.heartbeatScheduled = true
    PorticoPlaybackScheduleGrantRenewal(controller)
    PorticoPlaybackPublish(controller, false)
    PorticoPlaybackDispatchProgress(controller)
end sub

sub PorticoPlaybackAdoptHandoffReplacement(controller as object, replacement as object, autoplay as boolean)
    controller.playback = replacement
    controller.lastTargetKind = "vod"
    controller.lastTargetId = replacement.mediaId
    controller.playbackGeneration = controller.playbackGeneration + 1
    controller.sourceGeneration = controller.sourceGeneration + 1
    controller.playerState = "paused"
    controller.positionSeconds = replacement.resumePositionSeconds
    controller.durationSeconds = replacement.durationSeconds
    controller.status = "ready"
    controller.errorCode = ""
    if autoplay then controller.automaticAdvances = controller.automaticAdvances + 1
    controller.preparedNext = invalid
    controller.preparedHandoffStarted = false
    controller.postplayPhase = "inactive"
    controller.postplayDeadlineAt = 0
    controller.stillWatchingRequired = false
    controller.dismissedSegmentIds = {}
    controller.segmentDirective = invalid
    controller.reconnectRequestedSessionGeneration = -1
    controller.grantRenewalFailures = 0
    controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
    controller.heartbeatScheduled = true
    PorticoPlaybackScheduleGrantRenewal(controller)
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackFallbackCompletedTerminal(controller as object, handoff as object)
    requestId = PorticoPlaybackSafeRequestId(PorticoHttpNewRequestId())
    if requestId = ""
        PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-delayed", false)
        return
    end if
    body = {requestId: requestId, terminal: handoff.terminal}
    replacement = PorticoPlaybackPendingMutation(controller, "terminal", handoff.sessionId, body, {requestId: requestId, terminal: handoff.terminal}, "ended", "next-playback-unavailable", "", false)
    if not PorticoPlaybackPersistPendingMutation(controller, replacement)
        PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-storage-unavailable", false)
        return
    end if
    controller.pendingMutation = replacement
    controller.preparedNext = invalid
    controller.preparedHandoffStarted = false
    PorticoPlaybackDispatchPendingMutation(controller)
end sub

sub PorticoPlaybackRejectExplicitHandoff(controller as object)
    if not PorticoPlaybackClearPendingMutation(controller)
        PorticoPlaybackScheduleMutationRetry(controller, "playback-terminal-storage-unavailable", false)
        return
    end if
    controller.preparedNext = invalid
    controller.preparedHandoffStarted = false
    controller.postplayPhase = "manual"
    controller.status = controller.playerState
    controller.errorCode = "next-playback-unavailable"
    controller.nextHeartbeatAtSeconds = controller.clock.TotalSeconds() + 10
    controller.heartbeatScheduled = true
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackDropProgress(controller as object)
    if controller.progressRequest <> invalid and controller.progressRequest.transfer <> invalid then controller.progressRequest.transfer.AsyncCancel()
    controller.progressRequest = invalid
    controller.progressPending = invalid
    m.top.contentNode = invalid
end sub

sub PorticoPlaybackRenewGrant(controller as object, userInitiated as boolean)
    if controller.playback = invalid then return
    controller.grantRenewalScheduled = false
    if userInitiated then controller.grantRenewalFailures = 0
    result = PorticoPlaybackAuthenticatedRequest(controller, {
        method: "POST",
        path: "/api/playback-sessions/" + controller.playback.sessionId + "/media-grant",
        body: "",
        timeoutMs: 12000,
        expectJson: true,
        interruptible: true
    })
    if result.interrupted then return
    if not result.ok
        if result.status = 401 or result.missingSession = true
            PorticoPlaybackRequestReconnect(controller)
            return
        end if
        if (result.status = 403 or result.status = 404) and controller.sourceRecoveryPending
            ' Route re-resolution has already completed. A missing or forbidden
            ' sealed playback session cannot be reconstructed by the client.
            PorticoPlaybackFatalActive(controller, "playback-source-unavailable")
            return
        else if result.status = 403 or result.status = 404
            PorticoPlaybackFail(controller, "playback-session-ended", false)
            return
        end if
        remaining = PorticoSignedDocumentSecondsUntil(controller.playback.grantExpiresAt)
        if remaining = invalid or remaining <= 0
            PorticoPlaybackFatalActive(controller, "media-grant-expired")
            return
        end if
        controller.grantRenewalFailures = controller.grantRenewalFailures + 1
        if controller.grantRenewalFailures > 5 then controller.grantRenewalFailures = 5
        retrySeconds = 5 * (2 ^ (controller.grantRenewalFailures - 1))
        if retrySeconds > 60 then retrySeconds = 60
        if retrySeconds >= remaining then retrySeconds = remaining - 1
        if retrySeconds < 1 then retrySeconds = 1
        controller.nextGrantRenewalAtSeconds = controller.clock.TotalSeconds() + retrySeconds
        controller.grantRenewalScheduled = true
        controller.errorCode = "grant-renewal-delayed"
        PorticoPlaybackPublish(controller, false)
        return
    end if
    grant = PorticoPlaybackGrantFromResponse(result.data, controller.serverSession.apiBaseUrl, controller.playback.sourcePath, controller.serverSession.allowInsecureLan = true)
    if grant = invalid
        PorticoPlaybackFatalActive(controller, "grant-response-incompatible")
        return
    end if
    grantReplaced = grant.token <> controller.playback.grantToken
    controller.playback.grantToken = grant.token
    controller.playback.grantExpiresAt = grant.expiresAt
    controller.playback.resumePositionSeconds = controller.positionSeconds
    ' A native player can exhaust a URL even when the server renews the same
    ' opaque grant. An explicit recovery renewal always republishes the source.
    if grantReplaced or userInitiated or controller.sourceRecoveryPending then controller.sourceGeneration = controller.sourceGeneration + 1
    controller.grantRenewalFailures = 0
    controller.sourceRecoveryPending = false
    controller.errorCode = ""
    PorticoPlaybackScheduleGrantRenewal(controller)
    PorticoPlaybackPublish(controller, false)
end sub

sub PorticoPlaybackRecoverSource(controller as object)
    if controller.playback = invalid then return
    controller.sourceRecoveryAttempts = controller.sourceRecoveryAttempts + 1
    controller.sourceRecoveryPending = true
    if controller.sourceRecoveryAttempts = 1
        ' First exhaust route re-resolution while retaining the active playback
        ' session, grant and position. Main asks ServerConnection to rediscover
        ' and reverify every signed route before this Task renews on the new host.
        PorticoPlaybackRequestReconnect(controller)
        return
    end if
    ' Roku has no authority to invent a new quality or rebuild a session from
    ' partial remembered fields. After route re-resolution and grant renewal,
    ' the active sealed tuple either works or fails explicitly.
    PorticoPlaybackFatalActive(controller, "playback-source-unavailable")
end sub

sub PorticoPlaybackScheduleGrantRenewal(controller as object)
    controller.grantRenewalScheduled = false
    if controller.playback = invalid then return
    expiry = PorticoHttpScalarString(controller.playback.grantExpiresAt, "")
    remaining = PorticoSignedDocumentSecondsUntil(expiry)
    if remaining = invalid then return
    delaySeconds = remaining - 60
    if remaining <= 5
        delaySeconds = 1
    else if delaySeconds < 5
        delaySeconds = 5
    end if
    controller.nextGrantRenewalAtSeconds = controller.clock.TotalSeconds() + delaySeconds
    controller.grantRenewalScheduled = true
end sub

sub PorticoPlaybackLoadTrickplayPreview(controller as object, command as object)
    if controller.playback = invalid or controller.playback.isLive = true then return
    positionSeconds = PorticoPlaybackBoundedSeconds(command.positionSeconds, -1)
    if positionSeconds < 0 then return
    trickplaySet = PorticoPlaybackUsableTrickplaySet(controller.playback.trickplaySets)
    if trickplaySet = invalid
        controller.trickplayPreview = invalid
        PorticoPlaybackPublish(controller, false)
        return
    end if
    tileIndex = Int(positionSeconds / trickplaySet.intervalSeconds)
    if tileIndex < 0 then tileIndex = 0
    if tileIndex >= trickplaySet.tileCount then tileIndex = trickplaySet.tileCount - 1
    tilePosition = tileIndex * trickplaySet.intervalSeconds
    cacheKey = trickplaySet.id + "-" + tileIndex.ToStr()
    cached = controller.trickplayCache[cacheKey]
    if cached <> invalid and PorticoHttpFileWithinLimit(cached.uri, PorticoHttpLimits().maximumArtworkBytes)
        PorticoPlaybackTouchTrickplayCache(controller, cacheKey)
        controller.trickplayPreview = PorticoPlaybackTrickplayProjection(controller, trickplaySet, tileIndex, tilePosition, "ready", cached.uri)
        PorticoPlaybackPublish(controller, false)
        return
    end if

    controller.trickplayPreview = PorticoPlaybackTrickplayProjection(controller, trickplaySet, tileIndex, tilePosition, "loading", "")
    PorticoPlaybackPublish(controller, false)
    uri = PorticoPlaybackDownloadTrickplayTile(controller, trickplaySet, tileIndex)
    if PorticoPlaybackInterrupted(controller) then return
    if uri = ""
        controller.trickplayPreview = PorticoPlaybackTrickplayProjection(controller, trickplaySet, tileIndex, tilePosition, "unavailable", "")
        PorticoPlaybackPublish(controller, false)
        return
    end if
    controller.trickplayCache[cacheKey] = {uri: uri}
    PorticoPlaybackTouchTrickplayCache(controller, cacheKey)
    PorticoPlaybackTrimTrickplayCache(controller, 12)
    controller.trickplayPreview = PorticoPlaybackTrickplayProjection(controller, trickplaySet, tileIndex, tilePosition, "ready", uri)
    PorticoPlaybackPublish(controller, false)
end sub

function PorticoPlaybackUsableTrickplaySet(values as dynamic) as dynamic
    if values = invalid or GetInterface(values, "ifArray") = invalid then return invalid
    for each value in values
        if value <> invalid and Type(value) = "roAssociativeArray" and value.stale <> true and value.id <> "" and value.tileCount > 0 and value.intervalSeconds > 0 then return value
    end for
    return invalid
end function

function PorticoPlaybackTrickplayProjection(controller as object, trickplaySet as object, tileIndex as integer, positionSeconds as integer, status as string, uri as string) as object
    return {
        status: status,
        playbackGeneration: controller.playbackGeneration,
        sourceGeneration: controller.sourceGeneration,
        setId: trickplaySet.id,
        tileIndex: tileIndex,
        positionSeconds: positionSeconds,
        tileWidth: trickplaySet.tileWidth,
        tileHeight: trickplaySet.tileHeight,
        uri: uri
    }
end function

function PorticoPlaybackDownloadTrickplayTile(controller as object, trickplaySet as object, tileIndex as integer) as string
    if controller.operationContract = invalid or controller.playback = invalid then return ""
    operation = PorticoOperationContractResolvePath(controller.operationContract, "server", "getMediaIdTrickplaySetIdTilesTileIndexJpg", {
        id: controller.playback.mediaId,
        setId: trickplaySet.id,
        tileIndex: tileIndex.ToStr()
    })
    if not operation.ok or operation.method <> "GET" then return ""
    session = PorticoPlaybackSessionForController(controller)
    if session = invalid then return ""
    request = PorticoHttpNormalizeRequest({
        method: "GET",
        url: session.apiBaseUrl + "/api" + operation.path,
        body: "",
        headers: {Authorization: "Bearer " + session.accessToken},
        timeoutMs: 6000,
        expectJson: false,
        allowInsecureLan: session.allowInsecureLan = true
    })
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return ""
    safeSetId = PorticoPlaybackSafeId(trickplaySet.id)
    if safeSetId = "" then return ""
    prefix = "tmp:/portico-trickplay-v" + controller.viewerGeneration.ToStr() + "-p" + controller.playbackGeneration.ToStr() + "-s" + controller.sourceGeneration.ToStr() + "-" + safeSetId + "-" + tileIndex.ToStr()
    tempPath = prefix + ".part"
    finalPath = prefix + ".jpg"
    DeleteFile(tempPath)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return ""
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest("GET")
    if Left(LCase(request.url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return ""
        if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return ""
    end if
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return ""
    end for
    if not transfer.AsyncGetToFile(tempPath) then return ""
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoPlaybackInterrupted(controller)
            transfer.AsyncCancel()
            DeleteFile(tempPath)
            return ""
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            if message.GetResponseCode() <> 200
                DeleteFile(tempPath)
                return ""
            end if
            headers = PorticoHttpResponseHeaders(message.GetResponseHeadersArray())
            contentType = LCase(PorticoHttpScalarString(headers["content-type"], ""))
            if Left(contentType, 10) <> "image/jpeg" or not PorticoHttpFileWithinLimit(tempPath, PorticoHttpLimits().maximumArtworkBytes)
                DeleteFile(tempPath)
                return ""
            end if
            DeleteFile(finalPath)
            if not MoveFile(tempPath, finalPath)
                DeleteFile(tempPath)
                return ""
            end if
            return finalPath
        end if
    end while
    transfer.AsyncCancel()
    DeleteFile(tempPath)
    return ""
end function

sub PorticoPlaybackTouchTrickplayCache(controller as object, cacheKey as string)
    if controller.trickplayCacheOrder.Count() > 0
        for index = controller.trickplayCacheOrder.Count() - 1 to 0 step -1
            if controller.trickplayCacheOrder[index] = cacheKey then controller.trickplayCacheOrder.Delete(index)
        end for
    end if
    controller.trickplayCacheOrder.Push(cacheKey)
end sub

sub PorticoPlaybackTrimTrickplayCache(controller as object, maximumEntries as integer)
    while controller.trickplayCacheOrder.Count() > maximumEntries
        cacheKey = controller.trickplayCacheOrder[0]
        controller.trickplayCacheOrder.Delete(0)
        cached = controller.trickplayCache[cacheKey]
        if cached <> invalid and cached.uri <> "" then DeleteFile(cached.uri)
        controller.trickplayCache.Delete(cacheKey)
    end while
end sub

sub PorticoPlaybackClearTrickplayCache(controller as object)
    if controller.trickplayCache <> invalid
        for each cacheKey in controller.trickplayCache
            cached = controller.trickplayCache[cacheKey]
            if cached <> invalid and cached.uri <> "" then DeleteFile(cached.uri)
        end for
    end if
    controller.trickplayCache = {}
    controller.trickplayCacheOrder = []
    controller.trickplayPreview = invalid
end sub

function PorticoPlaybackStopActive(controller as object, reportFinalProgress as boolean) as boolean
    if controller.playback = invalid
        PorticoPlaybackResetActive(controller)
        controller.status = "idle"
        controller.errorCode = ""
        PorticoPlaybackPublish(controller, false)
        return true
    end if
    active = controller.playback
    return PorticoPlaybackBeginTerminal(controller, active, "stopped", "idle", "", "")
end function

sub PorticoPlaybackRemoteStop(controller as object, rawMessage as dynamic)
    if controller.playback = invalid then return
    message = PorticoCoreSafeText(rawMessage, 500)
    finalStatus = "idle"
    finalError = ""
    if message <> ""
        finalStatus = "error"
        finalError = "playback-remote-stopped"
    end if
    PorticoPlaybackBeginTerminal(controller, controller.playback, "stopped", finalStatus, finalError, message)
end sub

sub PorticoPlaybackApplyTransitionFence(controller as object)
    controller.watchAuthority = "independent"
    PorticoPlaybackStageTransitionTerminal(controller, true)
end sub

sub PorticoPlaybackStageTransitionTerminal(controller as object, dispatch as boolean)
    storageFailure = false
    if controller.playback <> invalid and controller.pendingMutation = invalid
        terminalRequest = PorticoPlaybackTerminalRequest(controller, controller.playback, "stopped")
        if terminalRequest <> invalid
            mutation = PorticoPlaybackPendingMutation(controller, "terminal", controller.playback.sessionId, terminalRequest, terminalRequest, "idle", "", "", false)
            if PorticoPlaybackPersistPendingMutation(controller, mutation)
                controller.pendingMutation = mutation
            else
                storageFailure = true
            end if
        else
            storageFailure = true
        end if
    end if
    ' Private media authority is revoked locally at the viewer boundary. The
    ' exact persisted terminal remains independently retryable.
    PorticoPlaybackResetActive(controller)
    controller.status = "idle"
    controller.errorCode = ""
    if storageFailure
        controller.status = "error"
        controller.errorCode = "playback-terminal-storage-unavailable"
    end if
    PorticoPlaybackPublish(controller, false)
    if dispatch and controller.pendingMutation <> invalid then PorticoPlaybackDispatchPendingMutation(controller)
end sub

sub PorticoPlaybackResetActive(controller as object)
    if controller.progressRequest <> invalid and controller.progressRequest.transfer <> invalid then controller.progressRequest.transfer.AsyncCancel()
    controller.progressRequest = invalid
    controller.progressPending = invalid
    controller.pendingStart = invalid
    if controller.preparedNext <> invalid then controller.preparedNext = invalid
    controller.playback = invalid
    controller.playerState = "paused"
    controller.positionSeconds = 0
    controller.durationSeconds = 0
    controller.heartbeatScheduled = false
    controller.nextHeartbeatAtSeconds = 0
    controller.grantRenewalScheduled = false
    controller.nextGrantRenewalAtSeconds = 0
    controller.grantRenewalFailures = 0
    controller.postplayPhase = "inactive"
    controller.postplayDeadlineAt = 0
    controller.stillWatchingRequired = false
    controller.segmentDirective = invalid
    controller.playbackRate = 1.0
    controller.sleepTimerMode = "off"
    controller.sleepTimerDeadlineAt = 0
    controller.remoteStopMessage = ""
    PorticoPlaybackClearTrickplayCache(controller)
    m.top.contentNode = invalid
end sub

sub PorticoPlaybackFail(controller as object, code as string, reconnectRequired as boolean)
    PorticoPlaybackResetActive(controller)
    controller.status = "error"
    controller.errorCode = code
    PorticoPlaybackPublish(controller, reconnectRequired)
end sub

sub PorticoPlaybackFatalActive(controller as object, code as string)
    if controller.playback = invalid
        PorticoPlaybackFail(controller, code, false)
        return
    end if
    PorticoPlaybackBeginTerminal(controller, controller.playback, "stopped", "error", code, "")
end sub

sub PorticoPlaybackRequestReconnect(controller as object)
    generation = 0
    if controller.serverSession <> invalid then generation = controller.serverSession.generation
    request = generation <> controller.reconnectRequestedSessionGeneration
    controller.reconnectRequestedSessionGeneration = generation
    controller.errorCode = "server-session-required"
    PorticoPlaybackPublish(controller, request)
end sub

function PorticoPlaybackCommandOwnsActive(controller as object, command as object) as boolean
    if controller.playback = invalid then return false
    if PorticoHttpInteger(command.playbackGeneration, -1) <> controller.playbackGeneration then return false
    if command.sourceGeneration = invalid then return true
    sourceGeneration = PorticoHttpInteger(command.sourceGeneration, -1)
    if sourceGeneration < 0 then return false
    return sourceGeneration = controller.sourceGeneration
end function

function PorticoPlaybackPreflightSource(controller as object, playback as object) as object
    if playback.streamFormat <> "hls" then return {ok: true, interrupted: false, status: 200}
    expectedPrefix = controller.serverSession.apiBaseUrl + "/api/"
    if Left(playback.sourceUrl, Len(expectedPrefix)) <> expectedPrefix then return {ok: false, interrupted: false, status: 0}
    overall = CreateObject("roTimespan")
    overall.Mark()
    while overall.TotalMilliseconds() < 30000
        attempt = PorticoPlaybackPreflightAttempt(controller, playback.sourceUrl, playback.grantToken)
        if attempt.ok or attempt.interrupted then return attempt
        if attempt.status <> 202 and attempt.status <> 429 and attempt.status <> 503 then return attempt
        delaySeconds = attempt.retryAfterSeconds
        if delaySeconds < 1 then delaySeconds = 1
        if delaySeconds > 5 then delaySeconds = 5
        delay = CreateObject("roTimespan")
        delay.Mark()
        while delay.TotalSeconds() < delaySeconds
            if PorticoPlaybackInterrupted(controller) then return {ok: false, interrupted: true, status: 0}
            Sleep(100)
        end while
    end while
    return {ok: false, interrupted: false, status: 0}
end function

function PorticoPlaybackPreflightAttempt(controller as object, url as string, mediaGrant as string) as object
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return {ok: false, interrupted: false, status: 0, retryAfterSeconds: 1}
    transfer.SetMessagePort(port)
    transfer.SetUrl(url)
    transfer.SetRequest("GET")
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    token = PorticoPlaybackGrantToken(mediaGrant)
    if token = "" or not transfer.AddHeader("Authorization", "PorticoMedia " + token) then return {ok: false, interrupted: false, status: 0, retryAfterSeconds: 1}
    if Left(LCase(url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return {ok: false, interrupted: false, status: 0, retryAfterSeconds: 1}
        if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return {ok: false, interrupted: false, status: 0, retryAfterSeconds: 1}
    end if
    if not transfer.AsyncGetToString() then return {ok: false, interrupted: false, status: 0, retryAfterSeconds: 1}
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < 10000
        if PorticoPlaybackInterrupted(controller)
            transfer.AsyncCancel()
            return {ok: false, interrupted: true, status: 0, retryAfterSeconds: 1}
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            status = message.GetResponseCode()
            retryAfter = 1
            headers = PorticoHttpResponseHeaders(message.GetResponseHeadersArray())
            if headers <> invalid and Type(headers) = "roAssociativeArray" then retryAfter = PorticoHttpInteger(headers["retry-after"], 1)
            if status <> 200 then return {ok: false, interrupted: false, status: status, retryAfterSeconds: retryAfter}
            payload = message.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return {ok: false, interrupted: false, status: status, retryAfterSeconds: 1}
            if Left(payload.Trim(), 7) <> "#EXTM3U" then return {ok: false, interrupted: false, status: status, retryAfterSeconds: 1}
            return {ok: true, interrupted: false, status: status, retryAfterSeconds: 0}
        end if
    end while
    transfer.AsyncCancel()
    return {ok: false, interrupted: false, status: 0, retryAfterSeconds: 1}
end function

function PorticoPlaybackAuthenticatedRequest(controller as object, rawRequest as object) as object
    session = PorticoPlaybackCurrentServerSession(controller)
    if session = invalid then return PorticoPlaybackHttpFailure(0, false, "server_session_required", true)
    result = PorticoPlaybackHttp(controller, session, rawRequest)
    if result.interrupted or result.status <> 401 then return result
    replacement = PorticoPlaybackSessionForController(controller)
    if replacement = invalid or replacement.generation <= session.generation or replacement.accessToken = session.accessToken then return result
    controller.serverSession = replacement
    return PorticoPlaybackHttp(controller, replacement, rawRequest)
end function

function PorticoPlaybackCurrentServerSession(controller as object) as dynamic
    replacement = PorticoPlaybackSessionForController(controller)
    if replacement = invalid then return invalid
    if controller.serverSession = invalid or replacement.generation >= controller.serverSession.generation
        controller.serverSession = replacement
    end if
    return controller.serverSession
end function

function PorticoPlaybackHttp(controller as object, session as object, rawRequest as object) as object
    allowed = PorticoPlaybackAllowedRequest(controller, rawRequest.method, rawRequest.path)
    if not allowed.ok then return PorticoPlaybackHttpFailure(0, false, allowed.code, false)
    request = PorticoHttpNormalizeRequest({
        method: rawRequest.method,
        url: session.apiBaseUrl + allowed.path,
        body: rawRequest.body,
        headers: { Authorization: "Bearer " + session.accessToken },
        timeoutMs: rawRequest.timeoutMs,
        expectJson: rawRequest.expectJson,
        allowInsecureLan: session.allowInsecureLan = true
    })
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoPlaybackHttpFailure(0, false, validation.code, false)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoPlaybackHttpFailure(0, true, "transport_error", false)
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if Left(LCase(request.url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoPlaybackHttpFailure(0, true, "transport_error", false)
        if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return PorticoPlaybackHttpFailure(0, true, "transport_error", false)
    end if
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return PorticoPlaybackHttpFailure(0, false, "invalid_header", false)
    end for
    if request.method = "GET"
        issued = transfer.AsyncGetToString()
    else
        issued = transfer.AsyncPostFromString(request.body)
    end if
    if not issued then return PorticoPlaybackHttpFailure(0, true, "transport_error", false)
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    interruptible = false
    if rawRequest.interruptible = true then interruptible = true
    while timer.TotalMilliseconds() < request.timeoutMs
        if interruptible and PorticoPlaybackInterrupted(controller)
            transfer.AsyncCancel()
            return { interrupted: true, ok: false, status: 0, retryable: false, data: invalid, missingSession: false }
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            status = message.GetResponseCode()
            if status < 0 then return PorticoPlaybackHttpFailure(status, true, "transport_error", false)
            payload = message.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoPlaybackHttpFailure(status, false, "response_too_large", false)
            classification = PorticoHttpClassifyStatus(status)
            if classification.classification <> "success"
                failure = PorticoPlaybackHttpFailure(status, classification.retryable, classification.classification, false)
                parsedError = PorticoHttpParseJson(payload)
                if parsedError.ok and parsedError.value <> invalid and Type(parsedError.value) = "roAssociativeArray"
                    failure.serverCode = LCase(PorticoCoreSafeText(parsedError.value.code, 80))
                    if parsedError.value.details <> invalid and Type(parsedError.value.details) = "roAssociativeArray"
                        replacementSessionId = PorticoPlaybackSafeId(parsedError.value.details.replacementSessionId)
                        if replacementSessionId <> "" then failure.details.replacementSessionId = replacementSessionId
                    end if
                end if
                return failure
            end if
            parsed = PorticoHttpParseJson(payload)
            if request.expectJson and not parsed.ok then return PorticoPlaybackHttpFailure(status, false, "parse_error", false)
            return { interrupted: false, ok: true, status: status, retryable: false, data: parsed.value, missingSession: false }
        end if
    end while
    transfer.AsyncCancel()
    return PorticoPlaybackHttpFailure(0, true, "timeout", false)
end function

function PorticoPlaybackHttpFailure(status as integer, retryable as boolean, code as string, missingSession as boolean) as object
    return { interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: code, serverCode: "", details: {}, missingSession: missingSession }
end function

function PorticoPlaybackInterrupted(controller as object) as boolean
    if controller.envelopeMode then return PorticoPlaybackInterruptedByEnvelope(controller)
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return false
    if PorticoHttpInteger(command.sequence, 0) <= controller.lastCommandSequence then return false
    kind = LCase(PorticoHttpScalarString(command.kind, ""))
    interrupts = {
        "server-state": true,
        "transition-fence": true,
        start: true,
        completed: true,
        next: true,
        replay: true,
        "select-quality": true,
        "select-audio": true,
        "select-subtitle": true,
        "seek-trickplay": true,
        "trickplay-preview": true,
        "trickplay-dismiss": true,
        "renew-grant": true,
        "source-error": true,
        stop: true,
        cancel: true
    }
    return interrupts[kind] = true
end function

function PorticoPlaybackUTCNowString() as string
    now = CreateObject("roDateTime")
    if now = invalid then return ""
    return now.ToISOString()
end function

function PorticoPlaybackIsBoolean(value as dynamic) as boolean
    valueType = LCase(Type(value))
    return valueType = "boolean" or valueType = "roboolean"
end function

sub PorticoPlaybackPublish(controller as object, reconnectRequired as boolean)
    if controller.suppressPublication = true then return
    eventState = {
        active: controller.playback <> invalid,
        viewerGeneration: controller.viewerGeneration,
        playbackGeneration: controller.playbackGeneration,
        sessionId: ""
    }
    if controller.playback <> invalid then eventState.sessionId = controller.playback.sessionId
    m.top.eventState = eventState
    projection = {
        playbackStatus: controller.status,
        playbackErrorCode: controller.errorCode,
        playbackGeneration: controller.playbackGeneration,
        sourceGeneration: controller.sourceGeneration,
        serverReconnectRequired: reconnectRequired,
        preferences: controller.preferences,
        playbackRate: controller.playbackRate,
        sleepTimerMode: controller.sleepTimerMode,
        postplay: {
            phase: controller.postplayPhase,
            deadlineAtSeconds: controller.postplayDeadlineAt,
            countdownSeconds: PorticoPlaybackPostplayCountdown(controller),
            stillWatchingRequired: controller.stillWatchingRequired,
            automaticAdvances: controller.automaticAdvances
        },
        segmentDirective: controller.segmentDirective,
        watchAuthority: controller.watchAuthority,
        remoteStopMessage: controller.remoteStopMessage
    }
    if controller.trickplayPreview <> invalid then projection.trickplayPreview = controller.trickplayPreview
    if controller.playback <> invalid then projection.source = PorticoPlaybackProjectionSource(controller.playback)
    if controller.playback <> invalid and controller.sourceGeneration > controller.lastPublishedContentSourceGeneration
        viewerGeneration = 0
        if controller.viewerScope <> invalid then viewerGeneration = PorticoHttpInteger(controller.viewerScope.viewerGeneration, 0)
        privateContent = PorticoPlaybackPrivateContentNode(controller.playback, controller.playbackGeneration, controller.sourceGeneration, viewerGeneration)
        if privateContent <> invalid
            controller.lastPublishedContentSourceGeneration = controller.sourceGeneration
            m.top.contentNode = privateContent
        end if
    end if
    if controller.preparedNext <> invalid and controller.preparedNext.playback <> invalid
        projection.postplay.next = {
            mediaId: controller.preparedNext.playback.mediaId,
            title: controller.preparedNext.playback.title,
            subtitle: controller.preparedNext.playback.subtitle,
            expiresAt: controller.preparedNext.expiresAt
        }
    end if
    if controller.envelopeMode
        envelope = PorticoPlaybackResultEnvelope(controller, projection)
        if envelope <> invalid then m.top.projectionEnvelope = envelope
    else
        m.top.projection = projection
    end if
end sub

function PorticoPlaybackPostplayCountdown(controller as object) as integer
    if controller.postplayPhase <> "countdown" or controller.postplayDeadlineAt <= 0 then return 0
    remaining = controller.postplayDeadlineAt - controller.clock.TotalSeconds()
    if remaining < 0 then return 0
    return remaining
end function
