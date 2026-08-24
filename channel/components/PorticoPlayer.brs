sub init()
    video = m.top.findNode("video")
    rateResetTimer = m.top.findNode("rateResetTimer")
    trickplayHideTimer = m.top.findNode("trickplayHideTimer")
    chromeHideTimer = m.top.findNode("chromeHideTimer")
    m.playerController = PorticoPlayerControllerCreate(video, rateResetTimer, trickplayHideTimer, chromeHideTimer)
    m.playerPresenter = PorticoPlayerPresenterCreate()
    m.scrim = m.top.findNode("scrim")
    m.identity = m.top.findNode("identity")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.watchGroupBanner = m.top.findNode("watchGroupBanner")
    m.watchGroupTitle = m.top.findNode("watchGroupTitle")
    m.watchGroupMeta = m.top.findNode("watchGroupMeta")
    m.centerStatus = m.top.findNode("centerStatus")
    m.spinner = m.top.findNode("spinner")
    m.spinnerAnimation = m.top.findNode("spinnerAnimation")
    m.centerStatusLabel = m.top.findNode("centerStatusLabel")
    m.trickplayPreview = m.top.findNode("trickplayPreview")
    m.trickplayImage = m.top.findNode("trickplayImage")
    m.trickplayTime = m.top.findNode("trickplayTime")
    m.transportContainer = m.top.findNode("transportContainer")
    m.elapsed = m.top.findNode("elapsed")
    m.durationLabel = m.top.findNode("duration")
    m.progressTrack = m.top.findNode("progressTrack")
    m.progressFill = m.top.findNode("progressFill")
    m.chapterMarkers = m.top.findNode("chapterMarkers")
    m.chapterMarkerNodes = []
    for index = 0 to 47
        marker = CreateObject("roSGNode", "Rectangle")
        if marker <> invalid
            marker.width = 2
            marker.height = 12
            marker.color = "#F4F7FA"
            marker.opacity = 0.66
            marker.visible = false
            m.chapterMarkers.appendChild(marker)
            m.chapterMarkerNodes.push(marker)
        end if
    end for
    m.transportDock = m.top.findNode("transportDock")
    m.controls = [m.top.findNode("previous"), m.top.findNode("back"), m.top.findNode("playPause"), m.top.findNode("forward"), m.top.findNode("next")]
    m.utilityContainer = m.top.findNode("utilityContainer")
    m.dockButtons = [m.top.findNode("volumeDock"), m.top.findNode("subtitlesDock"), m.top.findNode("qualityDock"), m.top.findNode("speedDock"), m.top.findNode("sleepDock"), m.top.findNode("queueDock")]
    m.panelContainer = m.top.findNode("panelContainer")
    m.panelContainerSurface = m.top.findNode("utilityPanelSurface")
    m.panelContainerAccent = m.top.findNode("utilityPanelAccent")
    m.utilityTitle = m.top.findNode("utilityTitle")
    m.utilityStatus = m.top.findNode("utilityStatus")
    m.utilityRows = []
    for index = 0 to 7
        m.utilityRows.push(m.top.findNode("utilityRow" + index.ToStr()))
    end for
    m.endedPanel = m.top.findNode("endedPanel")
    m.endedTitle = m.top.findNode("endedTitle")
    m.endedBody = m.top.findNode("endedBody")
    m.endedAction = m.top.findNode("endedAction")
    m.overlaySecondaryAction = m.top.findNode("overlaySecondaryAction")
    m.errorPanel = m.top.findNode("errorPanel")
    m.errorTitle = m.top.findNode("errorTitle")
    m.errorBodyLines = [m.top.findNode("errorBody0"), m.top.findNode("errorBody1")]
    m.errorAction = m.top.findNode("errorAction")

    m.scrim.uri = "pkg:/images/ui/player-overlay-scrim.png"
    m.spinner.uri = "pkg:/images/ui/player-spinner.png"
    m.transportDock.uri = "pkg:/images/ui/player-transport-dock.png"
    m.endedPanel.findNode("endedPanelBed").uri = "pkg:/images/ui/player-ended-panel.png"
    m.errorPanel.findNode("errorPanelBed").uri = "pkg:/images/ui/player-error-panel.png"

    m.title.font = PorticoFont("600", 28)
    m.title.color = "#F4F7FA"
    m.title.vertAlign = "top"
    m.meta.font = PorticoFont("400", 19)
    m.meta.color = "#8F9BA6"
    m.meta.vertAlign = "top"
    m.watchGroupTitle.font = PorticoFont("600", 22)
    m.watchGroupTitle.color = "#F4F7FA"
    m.watchGroupMeta.font = PorticoFont("400", 17)
    m.watchGroupMeta.color = "#8F9BA6"
    m.centerStatusLabel.font = PorticoFont("600", 26)
    m.centerStatusLabel.color = "#F4F7FA"
    m.centerStatusLabel.vertAlign = "top"
    m.trickplayTime.font = PorticoFont("600", 19)
    m.trickplayTime.color = "#F4F7FA"
    for each timeLabel in [m.elapsed, m.durationLabel]
        timeLabel.font = PorticoFont("500", 18)
        timeLabel.color = "#C7D0D8"
        timeLabel.vertAlign = "top"
    end for
    m.endedTitle.font = PorticoFont("700", 38)
    m.endedTitle.color = "#F4F7FA"
    m.endedTitle.vertAlign = "top"
    m.endedBody.font = PorticoFont("400", 22)
    m.endedBody.color = "#C7D0D8"
    m.endedBody.vertAlign = "top"
    m.errorTitle.font = PorticoFont("700", 38)
    m.errorTitle.color = "#F4F7FA"
    m.errorTitle.vertAlign = "top"
    for each line in m.errorBodyLines
        line.font = PorticoFont("400", 22)
        line.color = "#C7D0D8"
        line.vertAlign = "top"
    end for
    m.utilityTitle.font = PorticoFont("600", 26)
    m.utilityTitle.color = "#F4F7FA"
    m.utilityStatus.font = PorticoFont("500", 17)
    m.utilityStatus.color = "#8F9BA6"

    loadedLanguage = PorticoProductLanguageLoad()
    m.language = invalid
    if loadedLanguage.ok then m.language = loadedLanguage.value

    m.endedAction.model = { label: PorticoPlayerActionLabel("action.replay", "Replay"), iconId: "playback.replay", primary: true, width: 222 }
    m.overlaySecondaryAction.visible = false
    m.errorAction.model = { label: PorticoPlayerActionLabel("action.back-to-details", "Back to details"), iconId: "navigation.back", primary: true, width: 230 }
    m.endedAction.focused = true
    m.overlaySecondaryAction.focused = false
    m.errorAction.focused = true

    m.playerController.video.enableUI = false
    m.playerController.video.enableTrickPlay = false
    m.playerController.video.notificationInterval = 1
    m.playerController.video.observeField("state", "onVideoStateChanged")
    m.playerController.video.observeField("position", "onVideoPositionChanged")
    m.playerController.video.observeField("duration", "onVideoDurationChanged")
    m.playerController.timers.rateReset.observeField("fire", "onRateResetTimer")
    m.playerController.timers.trickplayHide.observeField("fire", "onTrickplayHideTimer")
    m.playerController.timers.chromeHide.observeField("fire", "onChromeHideTimer")

    m.playerController.model = invalid
    m.playerController.playbackGeneration = 0
    m.playerController.sourceGeneration = 0
    m.playerController.eventSequence = 0
    m.playerPresenter.focusedControl = 2
    m.playerPresenter.focusArea = "transport"
    m.playerPresenter.focusedDock = 0
    m.playerPresenter.panelKind = ""
    m.playerPresenter.panelIndex = 0
    m.playerPresenter.panelOffset = 0
    m.playerPresenter.dockTargets = []
    m.playerPresenter.panelTargets = []
    m.playerController.nativeState = "none"
    m.playerController.positionSeconds = 0
    m.playerController.durationSeconds = 0
    m.playerController.completedGeneration = -1
    m.playerController.stopEventEmitted = false
    m.playerController.renewalRequestedSourceGeneration = -1
    m.playerController.localStatusOverride = ""
    m.playerController.pendingInitialSeekSeconds = 0
    m.playerController.sourceRecoveryAttempts = 0
    m.playerController.privateContent = invalid
    m.playerController.lastSegmentDirectiveId = ""
    m.playerPresenter.focusedOverlayAction = 0
    m.playerPresenter.overlayKind = ""
    m.playerController.watchGroup = invalid
    m.playerController.pendingWatchLoadPaused = false
    m.playerController.pendingWatchLoadMediaId = ""
    m.playerController.pauseAfterInitialStart = false
    m.trickplayModel = invalid
    m.lastTrickplaySignature = ""
    m.playerController.lastRemoteDirectiveSequence = 0
    m.playerPresenter.chromeVisible = true
    m.top.focusable = true
    PorticoPlayerRender()
end sub

sub applyRemotePlaybackDirective()
    directive = m.top.remotePlaybackDirective
    if directive = invalid or Type(directive) <> "roAssociativeArray" then return
    generation = PorticoViewerScopePositiveInteger(directive.playbackGeneration)
    sequence = PorticoViewerScopePositiveInteger(directive.sequence)
    if generation < 1 or generation <> m.playerController.playbackGeneration or sequence <= m.playerController.lastRemoteDirectiveSequence then return
    kind = LCase(PorticoCoreSafeIdentifier(directive.kind, 16))
    if kind <> "play" and kind <> "pause" and kind <> "seek" then return
    m.playerController.lastRemoteDirectiveSequence = sequence
    if kind = "play"
        PorticoPlayerApplyWatchPause(false)
    else if kind = "pause"
        PorticoPlayerApplyWatchPause(true)
    else
        position = PorticoPlayerBoundedSeconds(directive.positionSeconds, -1)
        if position < 0 then return
        m.playerController.applyingWatchSync = true
        PorticoPlayerApplySeek(position)
        m.playerController.applyingWatchSync = false
        PorticoPlayerApplyWatchPause(directive.paused = true)
    end if
end sub

sub applyWatchGroupState()
    state = m.top.watchGroupState
    if state = invalid or Type(state) <> "roAssociativeArray" or state.group = invalid
        m.playerController.watchGroup = invalid
    else
        m.playerController.watchGroup = state
    end if
    PorticoPlayerRender()
end sub

sub applyPrivateContent()
    candidate = m.top.privateContent
    if candidate = invalid
        m.playerController.privateContent = invalid
        PorticoPlayerStopVideo()
        if m.playerController.video <> invalid then m.playerController.video.content = invalid
        return
    end if
    if Type(candidate) <> "roSGNode" then return
    playbackGeneration = PorticoHttpInteger(candidate.porticoPlaybackGeneration, 0)
    sourceGeneration = PorticoHttpInteger(candidate.porticoSourceGeneration, 0)
    if playbackGeneration < m.playerController.playbackGeneration or sourceGeneration < m.playerController.sourceGeneration then return
    m.playerController.privateContent = candidate
    if m.playerController.model <> invalid and playbackGeneration = m.playerController.model.playbackGeneration and sourceGeneration = m.playerController.model.sourceGeneration and sourceGeneration > m.playerController.sourceGeneration
        PorticoPlayerInstallSource(m.playerController.model)
        PorticoPlayerRender()
    end if
end sub

sub applyViewState()
    model = PorticoPlayerSafeModel(m.top.viewState)
    if model = invalid then return
    if not PorticoPlayerControllerAccepts(m.playerController, model.playbackGeneration, model.sourceGeneration) then return

    generationChanged = model.playbackGeneration > m.playerController.playbackGeneration
    if generationChanged
        PorticoPlayerControllerCancelActivation(m.playerController)
        PorticoPlayerStopVideo()
        m.playerController.playbackGeneration = model.playbackGeneration
        m.playerController.lastRemoteDirectiveSequence = 0
        m.playerController.sourceGeneration = 0
        PorticoPlayerControllerResetActivation(m.playerController)
        m.playerController.positionSeconds = 0
        m.playerController.durationSeconds = 0
        m.playerController.nativeState = "none"
        m.playerController.completedGeneration = -1
        m.playerController.stopEventEmitted = false
        m.playerController.renewalRequestedSourceGeneration = -1
        m.playerController.localStatusOverride = ""
        m.playerController.pendingInitialSeekSeconds = 0
        m.playerController.sourceRecoveryAttempts = 0
        m.playerPresenter.focusedControl = 2
        m.playerPresenter.focusArea = "transport"
        m.playerPresenter.focusedDock = 0
        m.playerPresenter.panelKind = ""
        m.playerPresenter.panelIndex = 0
        m.playerPresenter.panelOffset = 0
        m.trickplayModel = invalid
        m.lastTrickplaySignature = ""
        m.playerController.timers.trickplayHide.control = "stop"
        m.playerController.lastSegmentDirectiveId = ""
        m.playerPresenter.focusedOverlayAction = 0
        m.playerPresenter.overlayKind = ""
    end if

    sourceGenerationChanged = not generationChanged and model.sourceGeneration > m.playerController.sourceGeneration
    if sourceGenerationChanged
        ' A newer projection must fence the old private URL immediately. Keep
        ' the controller generation unchanged until matching private content
        ' arrives so onPrivateContentChanged can install the replacement.
        PorticoPlayerStopVideo()
        if m.playerController.video <> invalid then m.playerController.video.content = invalid
        if m.playerController.privateContent <> invalid
            privatePlaybackGeneration = PorticoHttpInteger(m.playerController.privateContent.porticoPlaybackGeneration, 0)
            privateSourceGeneration = PorticoHttpInteger(m.playerController.privateContent.porticoSourceGeneration, 0)
            if privatePlaybackGeneration <> model.playbackGeneration or privateSourceGeneration <> model.sourceGeneration
                m.playerController.privateContent = invalid
            end if
        end if
        m.playerController.nativeState = "buffering"
        m.playerController.localStatusOverride = "buffering"
    end if

    m.playerController.model = model
    if model.source <> invalid and model.sourceGeneration > m.playerController.sourceGeneration
        if m.playerController.privateContent <> invalid and PorticoHttpInteger(m.playerController.privateContent.porticoPlaybackGeneration, 0) = model.playbackGeneration and PorticoHttpInteger(m.playerController.privateContent.porticoSourceGeneration, 0) = model.sourceGeneration
            PorticoPlayerInstallSource(model)
        end if
    end if
    if model.playbackStatus = "error" or model.playbackStatus = "offline"
        PorticoPlayerStopVideo()
        m.playerController.localStatusOverride = ""
    else if model.playbackStatus = "ended"
        m.playerController.localStatusOverride = "ended"
    end if
    if model.playbackStatus = "idle" or model.playbackStatus = "error" or model.playbackStatus = "ended"
        m.playerController.pendingWatchLoadPaused = false
        m.playerController.pendingWatchLoadMediaId = ""
        m.playerController.privateContent = invalid
        if m.playerController.video <> invalid then m.playerController.video.content = invalid
    end if
    PorticoPlayerApplyModelRate(model.playbackRate)
    PorticoPlayerApplySegmentDirective(model.segmentDirective)
    PorticoPlayerApplyTrickplayPreview(model.trickplayPreview)
    PorticoPlayerRender()
end sub

sub PorticoPlayerApplyTrickplayPreview(preview as dynamic)
    if preview = invalid
        m.trickplayModel = invalid
        m.trickplayPreview.visible = false
        return
    end if
    signature = preview.status + "|" + preview.playbackGeneration.ToStr() + "|" + preview.sourceGeneration.ToStr() + "|" + preview.tileIndex.ToStr() + "|" + preview.uri
    if signature = m.lastTrickplaySignature then return
    m.lastTrickplaySignature = signature
    m.trickplayModel = preview
    m.trickplayTime.text = PorticoPlayerFormatTime(preview.positionSeconds)
    m.trickplayImage.uri = preview.uri
    m.trickplayImage.visible = preview.status = "ready" and preview.uri <> ""
    m.trickplayPreview.visible = preview.status = "loading" or preview.status = "ready"
    if preview.status = "ready"
        m.playerController.timers.trickplayHide.control = "stop"
        m.playerController.timers.trickplayHide.control = "start"
    else if preview.status = "unavailable"
        m.trickplayPreview.visible = false
    end if
end sub

sub onTrickplayHideTimer()
    m.trickplayPreview.visible = false
    m.trickplayModel = invalid
    if m.playerController.playbackGeneration > 0 then PorticoPlayerEmit("trickplay-dismiss", {})
end sub

sub applyWatchSyncDirective()
    directive = m.top.watchSyncDirective
    if directive = invalid or Type(directive) <> "roAssociativeArray" then return
    kind = LCase(PorticoPlayerSafeLabel(directive.type, 20))
    if kind = "load"
        mediaId = PorticoPlaybackBridgeSafeId(directive.mediaId)
        if mediaId <> ""
            m.playerController.pendingWatchLoadPaused = directive.paused = true
            m.playerController.pendingWatchLoadMediaId = mediaId
            PorticoPlayerEmit("watch-load", {targetId: mediaId, positionSeconds: PorticoPlayerBoundedSeconds(directive.positionSeconds, 0), paused: directive.paused = true})
        end if
    else if kind = "seek"
        m.playerController.applyingWatchSync = true
        PorticoPlayerApplySeek(PorticoPlayerBoundedSeconds(directive.positionSeconds, m.playerController.positionSeconds))
        m.playerController.applyingWatchSync = false
        PorticoPlayerApplyWatchPause(directive.paused = true)
    else if kind = "pause"
        PorticoPlayerApplyWatchPause(true)
    else if kind = "play"
        PorticoPlayerApplyWatchPause(false)
    else if kind = "rate"
        if m.playerController.video.HasField("playbackRate")
            PorticoPlayerApplyModelRate(directive.playbackRate)
            m.playerController.timers.rateReset.control = "start"
        else if directive.driftSeconds <> invalid
            m.playerController.applyingWatchSync = true
            PorticoPlayerApplySeek(Int(m.playerController.positionSeconds + directive.driftSeconds))
            m.playerController.applyingWatchSync = false
        end if
    end if
end sub

sub PorticoPlayerApplyWatchPause(paused as boolean)
    if paused
        if LCase(m.playerController.video.state) = "playing" then m.playerController.video.control = "pause"
        m.playerController.nativeState = "paused"
    else
        if LCase(m.playerController.video.state) = "paused" then m.playerController.video.control = "resume" else m.playerController.video.control = "play"
        m.playerController.nativeState = "playing"
    end if
    m.playerController.localStatusOverride = m.playerController.nativeState
    PorticoPlayerRender()
end sub

sub onRateResetTimer()
    rate = 1.0
    if m.playerController.model <> invalid then rate = m.playerController.model.playbackRate
    PorticoPlayerApplyModelRate(rate)
end sub

sub PorticoPlayerApplyModelRate(value as dynamic)
    rate = PorticoPlaybackPreferenceSpeed(value, 1.0)
    if m.playerController.video <> invalid and m.playerController.video.HasField("playbackRate") then m.playerController.video.playbackRate = rate
end sub

sub PorticoPlayerApplySegmentDirective(directive as dynamic)
    if directive = invalid or Type(directive) <> "roAssociativeArray" then return
    id = PorticoPlaybackBridgeSafeId(directive.id)
    if id = "" or id = m.playerController.lastSegmentDirectiveId then return
    m.playerController.lastSegmentDirectiveId = id
    if directive.type = "seek"
        PorticoPlayerSeekTo(PorticoPlayerBoundedSeconds(directive.positionSeconds, m.playerController.positionSeconds))
    end if
end sub

sub PorticoPlayerInstallSource(model as object)
    content = m.playerController.privateContent
    if content = invalid
        return
    end if
    PorticoPlayerStopVideo()
    startSeconds = model.source.resumePositionSeconds
    if startSeconds < 0 then startSeconds = 0
    subtitleTracks = []
    selectedSubtitleTrack = ""
    for each stream in model.source.subtitleStreams
        if stream.sourceUrl <> ""
            description = stream.displayTitle
            if description = "" then description = stream.language
            subtitleTracks.push({TrackName: stream.sourceUrl, Description: description, Language: PorticoPlayerCaptionLanguage(stream.language)})
            if stream.id = model.source.selectedSubtitleStreamId then selectedSubtitleTrack = stream.sourceUrl
        end if
    end for
    content.SubtitleTracks = subtitleTracks
    if selectedSubtitleTrack <> "" then content.SubtitleConfig = {TrackName: selectedSubtitleTrack}
    if selectedSubtitleTrack <> ""
        m.playerController.video.globalCaptionMode = "On"
    else
        m.playerController.video.globalCaptionMode = "Off"
    end if
    m.playerController.video.content = content
    if selectedSubtitleTrack <> "" then m.playerController.video.subtitleTrack = selectedSubtitleTrack
    m.playerController.sourceGeneration = model.sourceGeneration
    m.playerController.positionSeconds = startSeconds
    m.playerController.durationSeconds = model.source.durationSeconds
    m.playerController.pendingInitialSeekSeconds = startSeconds
    m.playerController.pauseAfterInitialStart = m.playerController.pendingWatchLoadPaused and m.playerController.pendingWatchLoadMediaId = model.source.mediaId
    m.playerController.pendingWatchLoadPaused = false
    m.playerController.pendingWatchLoadMediaId = ""
    m.playerController.nativeState = "buffering"
    m.playerController.localStatusOverride = "buffering"
    m.playerController.renewalRequestedSourceGeneration = -1
    m.playerController.video.control = "play"
    ' PorticoPlayer owns remote input; Video is deliberately never the focus
    ' owner because its native key handling bypasses our panel/chrome contract.
    m.top.setFocus(true)
end sub

sub PorticoPlayerStopVideo()
    if m.playerController.video = invalid then return
    state = LCase(m.playerController.video.state)
    if state <> "none" and state <> "stopped" then m.playerController.video.control = "stop"
end sub

sub onVideoStateChanged()
    if m.playerController.model = invalid or m.playerController.playbackGeneration < 1 then return
    state = LCase(m.playerController.video.state)
    if state = "playing" or state = "paused" or state = "buffering"
        m.playerController.nativeState = state
        m.playerController.localStatusOverride = state
        if state = "playing" and m.playerController.pendingInitialSeekSeconds > 0
            initialSeek = m.playerController.pendingInitialSeekSeconds
            m.playerController.pendingInitialSeekSeconds = 0
            m.playerController.video.seek = initialSeek
            m.playerController.positionSeconds = initialSeek
            PorticoPlayerEmitState(true)
        end if
        if state = "playing" and m.playerController.pauseAfterInitialStart
            m.playerController.pauseAfterInitialStart = false
            m.playerController.video.control = "pause"
            m.playerController.nativeState = "paused"
            m.playerController.localStatusOverride = "paused"
            PorticoPlayerEmitState(false)
        end if
        PorticoPlayerEmitState(false)
        if state = "playing"
            PorticoPlayerRevealChrome()
        else
            m.playerController.timers.chromeHide.control = "stop"
            m.playerPresenter.chromeVisible = true
        end if
    else if state = "finished"
        if PorticoPlayerIsLive()
            m.playerController.nativeState = "buffering"
            m.playerController.localStatusOverride = "reconnecting"
            if m.playerController.sourceRecoveryAttempts >= 2
                PorticoPlayerEmit("source-error", {})
            else if m.playerController.renewalRequestedSourceGeneration <> m.playerController.sourceGeneration
                m.playerController.renewalRequestedSourceGeneration = m.playerController.sourceGeneration
                m.playerController.sourceRecoveryAttempts = m.playerController.sourceRecoveryAttempts + 1
                PorticoPlayerEmit("renew-grant", {})
            end if
        else
            m.playerController.nativeState = "paused"
            m.playerController.localStatusOverride = "ended"
            if m.playerController.completedGeneration <> m.playerController.playbackGeneration
                m.playerController.completedGeneration = m.playerController.playbackGeneration
                PorticoPlayerEmit("completed", { positionSeconds: m.playerController.durationSeconds, durationSeconds: m.playerController.durationSeconds })
            end if
        end if
    else if state = "error"
        m.playerController.nativeState = "buffering"
        m.playerController.localStatusOverride = "reconnecting"
        if m.playerController.sourceRecoveryAttempts >= 2
            PorticoPlayerEmit("source-error", {})
        else if m.playerController.renewalRequestedSourceGeneration <> m.playerController.sourceGeneration
            m.playerController.renewalRequestedSourceGeneration = m.playerController.sourceGeneration
            m.playerController.sourceRecoveryAttempts = m.playerController.sourceRecoveryAttempts + 1
            PorticoPlayerEmit("renew-grant", {})
        end if
    end if
    PorticoPlayerRender()
end sub

sub onVideoPositionChanged()
    if m.playerController.model = invalid or m.playerController.playbackGeneration < 1 then return
    m.playerController.positionSeconds = PorticoPlayerBoundedSeconds(m.playerController.video.position, m.playerController.positionSeconds)
    if m.playerController.durationSeconds > 0 and m.playerController.positionSeconds > m.playerController.durationSeconds then m.playerController.positionSeconds = m.playerController.durationSeconds
    PorticoPlayerUpdateProgress()
    if m.playerController.nativeState = "playing" or m.playerController.nativeState = "paused" or m.playerController.nativeState = "buffering" then PorticoPlayerEmitState(false)
end sub

sub onVideoDurationChanged()
    duration = PorticoPlayerBoundedSeconds(m.playerController.video.duration, m.playerController.durationSeconds)
    if duration > 0 then m.playerController.durationSeconds = duration
    PorticoPlayerUpdateProgress()
end sub

sub PorticoPlayerEmitState(seekEvent as boolean)
    state = m.playerController.nativeState
    if state <> "playing" and state <> "paused" and state <> "buffering" then state = "paused"
    kind = "player-state"
    if seekEvent then kind = "seek"
    PorticoPlayerEmit(kind, {
        state: state,
        positionSeconds: m.playerController.positionSeconds,
        durationSeconds: m.playerController.durationSeconds
    })
end sub

sub PorticoPlayerEmit(kind as string, fields as object)
    if m.playerController.playbackGeneration < 1 and kind <> "stop" and kind <> "watch-load" then return
    if kind = "stop"
        if m.playerController.stopEventEmitted then return
        m.playerController.stopEventEmitted = true
        PorticoPlayerStopVideo()
    end if
    m.playerController.eventSequence = m.playerController.eventSequence + 1
    event = {
        sequence: m.playerController.eventSequence,
        kind: kind,
        playbackGeneration: m.playerController.playbackGeneration,
        sourceGeneration: m.playerController.sourceGeneration
    }
    for each key in fields
        event[key] = fields[key]
    end for
    m.top.playerEvent = event
end sub

sub PorticoPlayerRender()
    status = PorticoPlayerEffectiveStatus()
    hasModel = m.playerController.model <> invalid
    title = ""
    meta = ""
    if hasModel
        title = m.playerController.model.title
        meta = m.playerController.model.meta
    end if
    m.title.text = title
    m.meta.text = meta
    chromeRequired = status <> "playing" or m.playerPresenter.focusArea = "panel" or m.playerPresenter.focusArea = "utility"
    if chromeRequired then m.playerPresenter.chromeVisible = true
    m.scrim.visible = m.playerPresenter.chromeVisible
    m.identity.visible = m.playerPresenter.chromeVisible and (title <> "" or meta <> "")
    PorticoPlayerRenderWatchGroup()

    spinnerLabel = ""
    if status = "preparing" or status = "ready"
        spinnerLabel = PorticoPlayerMessage("playback.preparing", "Preparing playback", {}).title
    else if status = "buffering"
        spinnerLabel = PorticoPlayerMessage("playback.buffering", "Buffering", {}).title
    else if status = "reconnecting"
        spinnerLabel = PorticoPlayerMessage("playback.reconnecting", "Reconnecting", {}).title
    else if status = "stopping"
        spinnerLabel = PorticoPlayerActionLabel("action.close-player", "Closing playback")
    end if
    m.centerStatus.visible = spinnerLabel <> ""
    m.centerStatusLabel.text = spinnerLabel
    if spinnerLabel <> "" and not PorticoPlayerReducedMotion()
        m.spinnerAnimation.control = "start"
    else
        m.spinnerAnimation.control = "stop"
        m.spinner.rotation = 0
    end if

    controlsVisible = m.playerPresenter.chromeVisible and (status = "playing" or status = "paused" or status = "buffering" or status = "reconnecting")
    m.transportContainer.visible = controlsVisible
    segmentPrompt = hasModel and m.playerController.model.segmentDirective <> invalid and m.playerController.model.segmentDirective.type = "prompt"
    m.endedPanel.visible = status = "ended" or status = "postplay" or segmentPrompt
    if not m.endedPanel.visible then m.playerPresenter.overlayKind = ""
    m.errorPanel.visible = status = "error" or status = "offline"

    if controlsVisible
        PorticoPlayerUpdateControls()
        PorticoPlayerUpdateProgress()
        PorticoPlayerBuildUtilities()
    else
        m.utilityContainer.visible = false
        m.panelContainer.visible = false
    end if
    if m.endedPanel.visible
        PorticoPlayerRenderOverlay(status, segmentPrompt)
    end if
    if m.errorPanel.visible
        failure = PorticoPlayerFailureCopy(m.playerController.model.playbackErrorCode)
        if m.playerController.model.remoteStopMessage <> "" then failure.body = m.playerController.model.remoteStopMessage
        m.errorTitle.text = failure.title
        lines = PorticoBreakText(failure.body, 624, 22, "400", 2)
        for index = 0 to m.errorBodyLines.count() - 1
            line = m.errorBodyLines[index]
            line.visible = index < lines.count()
            if index < lines.count() then line.text = lines[index] else line.text = ""
        end for
    end if
    PorticoPlayerPublishFocusState()
end sub

sub PorticoPlayerRevealChrome()
    m.playerPresenter.chromeVisible = true
    status = PorticoPlayerEffectiveStatus()
    if status = "playing" and m.playerPresenter.focusArea = "transport"
        m.playerController.timers.chromeHide.control = "stop"
        m.playerController.timers.chromeHide.control = "start"
    else
        m.playerController.timers.chromeHide.control = "stop"
    end if
end sub

sub onChromeHideTimer()
    if PorticoPlayerEffectiveStatus() <> "playing" or m.playerPresenter.focusArea <> "transport" then return
    m.playerPresenter.chromeVisible = false
    PorticoPlayerRender()
end sub

sub PorticoPlayerRenderWatchGroup()
    m.watchGroupBanner.visible = m.playerPresenter.chromeVisible and m.playerController.watchGroup <> invalid and m.playerController.watchGroup.group <> invalid
    if not m.watchGroupBanner.visible then return
    group = m.playerController.watchGroup.group
    m.watchGroupTitle.text = group.name
    roleId = "watch-with-friends.role-participant"
    if group.permissions.isHost = true
        roleId = "watch-with-friends.role-host"
    else if group.permissions.canControl = true
        roleId = "watch-with-friends.role-shared"
    end if
    connection = PorticoPlayerText("watch-with-friends.connected-count", group.members.Count().ToStr() + " watching", {count: group.members.Count().ToStr()})
    role = PorticoPlayerText(roleId, "Host controls playback", {})
    if m.playerController.watchGroup.status = "reconnecting" then connection = PorticoPlayerMessage("watch-with-friends.reconnecting", "Reconnecting", {}).title
    if m.playerController.watchGroup.status = "offline" or m.playerController.watchGroup.status = "error" then connection = PorticoPlayerMessage("watch-with-friends.unavailable", "Group unavailable", {}).title
    m.watchGroupMeta.text = connection + " · " + role
end sub

sub PorticoPlayerRenderOverlay(status as string, segmentPrompt as boolean)
    primaryId = "action.replay"
    primaryFallback = "Replay"
    secondaryId = "action.cancel"
    secondaryFallback = "Cancel"
    copy = PorticoPlayerMessage("playback.complete", "You're all caught up", {})
    m.playerPresenter.overlayKind = "ended"
    if segmentPrompt
        segment = m.playerController.model.segmentDirective.segmentType
        if segment = "" then segment = "segment"
        primaryId = "action.skip-segment"
        primaryFallback = "Skip " + segment
        secondaryId = "action.dismiss-skip-prompt"
        secondaryFallback = "Dismiss"
        copy = {title: PorticoPlayerActionLabelWithVariables("action.skip-segment", "Skip " + segment, {segment: segment}), body: ""}
        m.playerPresenter.overlayKind = "segment"
    else if status = "postplay"
        primaryId = "action.play-now"
        primaryFallback = "Play now"
        secondaryId = "action.cancel"
        secondaryFallback = "Cancel"
        if m.playerController.model.postplay.phase = "still-watching"
            primaryId = "action.still-watching"
            primaryFallback = "I'm still watching"
            copy = PorticoPlayerMessage("playback.still-watching", "Still watching?", {})
            m.playerPresenter.overlayKind = "still-watching"
        else
            variables = {}
            if m.playerController.model.postplay.countdownSeconds > 0
                variables.seconds = m.playerController.model.postplay.countdownSeconds.ToStr()
                unit = "seconds"
                if m.playerController.model.postplay.countdownSeconds = 1 then unit = "second"
                variables.unit = unit
                copy = PorticoPlayerMessage("playback.up-next-countdown", "Up next", variables)
            else
                copy = PorticoPlayerMessage("playback.up-next-ready", "Up next", {})
            end if
            if m.playerController.model.postplay.next <> invalid and m.playerController.model.postplay.next.title <> ""
                if copy.body = ""
                    copy.body = m.playerController.model.postplay.next.title
                else
                    copy.body = copy.body + " · " + m.playerController.model.postplay.next.title
                end if
            end if
            m.playerPresenter.overlayKind = "postplay"
        end if
    end if
    m.endedTitle.text = copy.title
    m.endedBody.text = copy.body
    primaryLabel = PorticoPlayerActionLabel(primaryId, primaryFallback)
    if segmentPrompt then primaryLabel = PorticoPlayerActionLabelWithVariables(primaryId, primaryFallback, {segment: m.playerController.model.segmentDirective.segmentType})
    m.endedAction.model = {label: primaryLabel, iconId: "playback.play", primary: true, width: 222}
    m.overlaySecondaryAction.model = {label: PorticoPlayerActionLabelWithVariables(secondaryId, secondaryFallback, {segment: "segment"}), iconId: "action.cancel", primary: false, width: 222}
    m.overlaySecondaryAction.visible = m.playerPresenter.overlayKind <> "ended"
    m.endedAction.focused = m.playerPresenter.focusedOverlayAction = 0
    m.overlaySecondaryAction.focused = m.overlaySecondaryAction.visible and m.playerPresenter.focusedOverlayAction = 1
end sub

function PorticoPlayerEffectiveStatus() as string
    if m.playerController.model = invalid then return "idle"
    if m.playerController.model.playbackStatus = "error" or m.playerController.model.playbackStatus = "offline" or m.playerController.model.playbackStatus = "postplay" or m.playerController.model.playbackStatus = "ended" then return m.playerController.model.playbackStatus
    if m.playerController.localStatusOverride <> "" then return m.playerController.localStatusOverride
    return m.playerController.model.playbackStatus
end function

sub PorticoPlayerUpdateControls()
    if m.playerPresenter.focusedControl < 0 then m.playerPresenter.focusedControl = 0
    if m.playerPresenter.focusedControl > 4 then m.playerPresenter.focusedControl = 4
    playing = m.playerController.nativeState = "playing"
    isLive = PorticoPlayerIsLive()
    canSeek = PorticoPlayerCanSeek()
    canPause = PorticoPlayerCanPause()
    canControl = PorticoPlayerCanControl()
    hasNext = m.playerController.model.source.queue.count() > 0
    if not canSeek and (m.playerPresenter.focusedControl = 0 or m.playerPresenter.focusedControl = 1 or m.playerPresenter.focusedControl = 3) then m.playerPresenter.focusedControl = 2
    models = [
        {iconId: "playback.previous", main: false, disabled: isLive or not canControl},
        {iconId: "playback.seek-back", main: false, disabled: not canSeek or not canControl},
        {iconId: "playback.play", main: true, disabled: not canPause or not canControl},
        {iconId: "playback.seek-forward", main: false, disabled: not canSeek or not canControl},
        {iconId: "playback.next", main: false, disabled: isLive or not hasNext or not canControl}
    ]
    if playing then models[2].iconId = "playback.pause"
    m.transportDock.translation = [807, 75]
    m.transportDock.width = 368
    m.transportDock.loadWidth = 368
    for index = 0 to m.controls.count() - 1
        m.controls[index].model = models[index]
        m.controls[index].visible = true
        m.controls[index].focused = m.playerPresenter.focusArea = "transport" and index = m.playerPresenter.focusedControl
    end for
end sub

sub PorticoPlayerUpdateProgress()
    if PorticoPlayerIsLive()
        m.elapsed.text = "LIVE"
        m.durationLabel.text = ""
        m.progressTrack.visible = false
        m.progressFill.visible = false
        PorticoPlayerUpdateChapterMarkers(false)
        return
    end if
    m.progressTrack.visible = true
    m.progressFill.visible = true
    m.elapsed.text = PorticoPlayerFormatTime(m.playerController.positionSeconds)
    m.durationLabel.text = PorticoPlayerFormatTime(m.playerController.durationSeconds)
    fillWidth = 0
    if m.playerController.durationSeconds > 0
        progress = m.playerController.positionSeconds / m.playerController.durationSeconds
        if progress < 0 then progress = 0
        if progress > 1 then progress = 1
        fillWidth = Int(1776.0 * progress)
    end if
    m.progressFill.width = fillWidth
    PorticoPlayerUpdateChapterMarkers(true)
end sub

sub PorticoPlayerUpdateChapterMarkers(visible as boolean)
    for each marker in m.chapterMarkerNodes
        marker.visible = false
    end for
    if not visible or m.playerController.model = invalid or m.playerController.model.source = invalid or m.playerController.durationSeconds <= 0 then return
    chapters = m.playerController.model.source.chapters
    if chapters = invalid or GetInterface(chapters, "ifArray") = invalid then return
    count = chapters.count()
    if count > m.chapterMarkerNodes.count() then count = m.chapterMarkerNodes.count()
    for index = 0 to count - 1
        seconds = PorticoPlayerBoundedSeconds(chapters[index].startSeconds, -1)
        if seconds > 0 and seconds < m.playerController.durationSeconds
            marker = m.chapterMarkerNodes[index]
            marker.translation = [Int(1776.0 * (seconds / m.playerController.durationSeconds)), 0]
            marker.visible = true
        end if
    end for
end sub

sub PorticoPlayerBuildUtilities()
    source = m.playerController.model.source
    m.playerPresenter.dockTargets = []
    allowQuality = not PorticoPlayerIsLive() and source.streamFormat = "hls" and source.qualities.count() > 1
    allowStreams = not PorticoPlayerIsLive() and source.targetKind = "vod"
    if m.playerController.video.HasField("volume") then m.playerPresenter.dockTargets.push({kind: "volume", iconId: "playback.volume"})
    if allowStreams and (source.audioStreams.count() > 1 or source.subtitleStreams.count() > 0) then m.playerPresenter.dockTargets.push({kind: "subtitles", iconId: "playback.captions"})
    if allowQuality then m.playerPresenter.dockTargets.push({kind: "quality", iconId: "playback.quality"})
    if not PorticoPlayerIsLive() and m.playerController.video.HasField("playbackRate") then m.playerPresenter.dockTargets.push({kind: "speed", iconId: "playback.speed"})
    if not PorticoPlayerIsLive() then m.playerPresenter.dockTargets.push({kind: "sleep", iconId: "metadata.time"})
    if not PorticoPlayerIsLive() and source.queue.count() > 0 then m.playerPresenter.dockTargets.push({kind: "queue", iconId: "playback.queue"})
    if m.playerPresenter.focusedDock >= m.playerPresenter.dockTargets.count() then m.playerPresenter.focusedDock = m.playerPresenter.dockTargets.count() - 1
    if m.playerPresenter.focusedDock < 0 then m.playerPresenter.focusedDock = 0
    for index = 0 to m.dockButtons.count() - 1
        node = m.dockButtons[index]
        node.visible = index < m.playerPresenter.dockTargets.count()
        if node.visible
            target = m.playerPresenter.dockTargets[index]
            node.model = {iconId: target.iconId, selected: m.playerPresenter.panelKind = target.kind}
            node.focused = m.playerPresenter.focusArea = "utility" and index = m.playerPresenter.focusedDock
        end if
    end for
    dockWidth = 0
    if m.playerPresenter.dockTargets.count() > 0 then dockWidth = (m.playerPresenter.dockTargets.count() * 64) + ((m.playerPresenter.dockTargets.count() - 1) * 8)
    m.utilityContainer.translation = [1848 - dockWidth, 974]
    m.utilityContainer.visible = m.playerPresenter.dockTargets.count() > 0
    PorticoPlayerBuildPanel()
end sub

sub PorticoPlayerBuildPanel()
    m.playerPresenter.panelTargets = []
    for each row in m.utilityRows
        row.visible = false
        row.focused = false
    end for
    if m.playerPresenter.panelKind = ""
        m.panelContainer.visible = false
        return
    end if
    source = m.playerController.model.source
    m.utilityTitle.text = PorticoPlayerPanelTitle(m.playerPresenter.panelKind)
    m.utilityStatus.text = ""
    if m.playerPresenter.panelKind = "volume"
        currentVolume = 100
        if m.playerController.video.HasField("volume") then currentVolume = Int(m.playerController.video.volume)
        for each volume in [0, 25, 50, 75, 100]
            label = volume.ToStr() + "%"
            if volume = 0 then label = "Muted"
            m.playerPresenter.panelTargets.push({kind: "set-volume", id: volume.ToStr(), label: label, volume: volume, selected: currentVolume = volume})
        end for
    else if m.playerPresenter.panelKind = "quality"
        hasAutomatic = false
        for each item in source.qualities
            if LCase(item.id.ToStr()) = "automatic" then hasAutomatic = true
        end for
        if not hasAutomatic then m.playerPresenter.panelTargets.push({kind: "select-quality", id: "automatic", label: "Automatic", selected: source.selectedQualityId = "" or LCase(source.selectedQualityId) = "automatic"})
        for each item in source.qualities
            m.playerPresenter.panelTargets.push({kind: "select-quality", id: item.id, label: item.label, selected: item.id = source.selectedQualityId})
        end for
    else if m.playerPresenter.panelKind = "subtitles"
        for each item in source.audioStreams
            label = item.displayTitle
            if label = "" then label = item.language
            m.playerPresenter.panelTargets.push({kind: "select-audio", id: item.id, label: "Audio · " + label, selected: item.id = source.selectedAudioStreamId})
        end for
        if source.subtitleStreams.count() > 0
            m.playerPresenter.panelTargets.push({kind: "subtitle-off", id: "", label: "Subtitles · Off", selected: source.selectedSubtitleStreamId = ""})
            for each item in source.subtitleStreams
                label = item.displayTitle
                if label = "" then label = item.language
                m.playerPresenter.panelTargets.push({kind: "select-subtitle", id: item.id, label: "Subtitles · " + label, selected: item.id = source.selectedSubtitleStreamId})
            end for
        end if
    else if m.playerPresenter.panelKind = "queue"
        for index = 0 to source.queue.count() - 1
            item = source.queue[index]
            prefix = "Then"
            if index = 0 then prefix = "Up next"
            m.playerPresenter.panelTargets.push({kind: "next", id: item.id, label: prefix + " · " + item.title, selected: false})
        end for
    else if m.playerPresenter.panelKind = "speed"
        speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        for each speed in speeds
            label = speed.ToStr() + "×"
            if speed = 1.0 then label = PorticoPlayerMessage("playback.speed-normal", "Normal speed", {}).text
            m.playerPresenter.panelTargets.push({kind: "set-speed", id: speed.ToStr(), label: label, speed: speed, selected: m.playerController.model.playbackRate = speed})
        end for
    else if m.playerPresenter.panelKind = "sleep"
        m.playerPresenter.panelTargets.push({kind: "set-sleep-timer", id: "off", label: PorticoPlayerMessage("playback.sleep-off", "Sleep timer off", {}).text, mode: "off", selected: m.playerController.model.sleepTimerMode = "off"})
        for each minutes in [15, 30, 45, 60]
            messageId = "playback.sleep-" + minutes.ToStr() + "-minutes"
            m.playerPresenter.panelTargets.push({kind: "set-sleep-timer", id: minutes.ToStr(), label: PorticoPlayerMessage(messageId, minutes.ToStr() + " minutes", {}).text, mode: minutes.ToStr(), selected: m.playerController.model.sleepTimerMode = minutes.ToStr()})
        end for
        m.playerPresenter.panelTargets.push({kind: "set-sleep-timer", id: "end-of-item", label: PorticoPlayerMessage("playback.sleep-end", "End of item", {}).text, mode: "end-of-item", selected: m.playerController.model.sleepTimerMode = "end-of-item"})
    end if
    if m.playerPresenter.panelIndex >= m.playerPresenter.panelTargets.count() then m.playerPresenter.panelIndex = m.playerPresenter.panelTargets.count() - 1
    if m.playerPresenter.panelIndex < 0 then m.playerPresenter.panelIndex = 0
    pageSize = m.utilityRows.count()
    if m.playerPresenter.panelOffset > m.playerPresenter.panelIndex then m.playerPresenter.panelOffset = m.playerPresenter.panelIndex
    if m.playerPresenter.panelIndex >= m.playerPresenter.panelOffset + pageSize then m.playerPresenter.panelOffset = m.playerPresenter.panelIndex - pageSize + 1
    maximumOffset = m.playerPresenter.panelTargets.count() - pageSize
    if maximumOffset < 0 then maximumOffset = 0
    if m.playerPresenter.panelOffset > maximumOffset then m.playerPresenter.panelOffset = maximumOffset
    if m.playerPresenter.panelOffset < 0 then m.playerPresenter.panelOffset = 0
    visibleCount = m.playerPresenter.panelTargets.count()
    if visibleCount > pageSize then visibleCount = pageSize
    for rowIndex = 0 to visibleCount - 1
        targetIndex = m.playerPresenter.panelOffset + rowIndex
        target = m.playerPresenter.panelTargets[targetIndex]
        row = m.utilityRows[rowIndex]
        row.model = {label: target.label, iconId: "navigation.disclosure", primary: target.selected = true, width: 384}
        row.focused = m.playerPresenter.focusArea = "panel" and targetIndex = m.playerPresenter.panelIndex
        row.visible = true
    end for
    if m.playerPresenter.panelTargets.count() > pageSize
        firstVisible = m.playerPresenter.panelOffset + 1
        lastVisible = m.playerPresenter.panelOffset + visibleCount
        m.utilityStatus.text = firstVisible.ToStr() + "-" + lastVisible.ToStr() + " of " + m.playerPresenter.panelTargets.count().ToStr()
    end if
    panelHeight = 100 + (visibleCount * 70)
    if panelHeight < 170 then panelHeight = 170
    if panelHeight > 660 then panelHeight = 660
    m.panelContainer.translation = [1428, 974 - panelHeight]
    m.panelContainerSurface.height = panelHeight
    m.panelContainerAccent.height = panelHeight
    m.panelContainer.visible = true
end sub

function PorticoPlayerReducedMotion() as boolean
    if m.playerController.model = invalid or m.playerController.model.preferences = invalid then return false
    preferences = m.playerController.model.preferences
    return preferences.reducedMotion = true or preferences.reduceMotion = true or preferences.animationsEnabled = false
end function

function PorticoPlayerOnOff(value as boolean) as string
    if value then return "On"
    return "Off"
end function

function PorticoPlayerPanelTitle(kind as string) as string
    if kind = "volume" then return "Volume"
    if kind = "subtitles" then return "Subtitles"
    if kind = "quality" then return "Playback quality"
    if kind = "speed" then return "Speed"
    if kind = "sleep" then return "Sleep"
    return "Queue"
end function

function PorticoPlayerBackAction(overlayVisible as boolean) as string
    return PorticoPlayerPresenterBackAction(m.playerPresenter, overlayVisible)
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        if key = "OK" or key = "play" then PorticoPlayerControllerReleaseActivation(m.playerController, key)
        return false
    end if
    if key = "OK" or key = "play"
        intentId = PorticoPlayerPresenterSemanticId(m.playerPresenter) + ".activate"
        if not PorticoPlayerControllerBeginActivation(m.playerController, key, intentId) then return true
        if not PorticoPlayerControllerCommitActivation(m.playerController) then return true
        PorticoPlayerControllerCompleteActivation(m.playerController)
    end if
    status = PorticoPlayerEffectiveStatus()
    overlayVisible = m.endedPanel.visible and (m.playerPresenter.overlayKind = "segment" or m.playerPresenter.overlayKind = "postplay" or m.playerPresenter.overlayKind = "still-watching" or m.playerPresenter.overlayKind = "ended")
    controlsAvailable = status = "playing" or status = "paused" or status = "buffering" or status = "reconnecting"
    if key = "play" and controlsAvailable and not overlayVisible
        PorticoPlayerTogglePlayback()
        return true
    end if
    if key = "back" and overlayVisible and PorticoPlayerBackAction(true) = "close-overlay"
        m.playerPresenter.focusedOverlayAction = 1
        PorticoPlayerActivateOverlay()
        return true
    end if
    if not m.playerPresenter.chromeVisible
        PorticoPlayerRevealChrome()
        PorticoPlayerRender()
        return true
    end if
    PorticoPlayerRevealChrome()
    if overlayVisible
        if key = "left" or key = "right"
            if m.playerPresenter.focusedOverlayAction = 0 then m.playerPresenter.focusedOverlayAction = 1 else m.playerPresenter.focusedOverlayAction = 0
            PorticoPlayerRender()
            return true
        else if key = "OK"
            PorticoPlayerActivateOverlay()
            return true
        end if
        return true
    end if
    if key = "back"
        action = PorticoPlayerBackAction(false)
        if action = "close-panel"
            PorticoPlayerPresenterMoveBoundary(m.playerPresenter, "left")
            m.playerPresenter.panelKind = ""
            m.playerPresenter.focusArea = "utility"
            PorticoPlayerRender()
            return true
        else if action = "close-utility"
            PorticoPlayerPresenterMoveBoundary(m.playerPresenter, "down")
            m.playerPresenter.focusArea = "transport"
            PorticoPlayerRender()
            return true
        end if
        PorticoPlayerRequestExit("back")
        return true
    end if
    if status = "error" or status = "offline"
        if key = "OK"
            PorticoPlayerRequestExit("error-action")
            return true
        end if
        return false
    end if
    controlsVisible = controlsAvailable
    if not controlsVisible then return false
    if PorticoPlayerIsLive() and m.playerPresenter.focusArea = "transport"
        m.playerPresenter.focusedControl = 2
        if key = "OK" or key = "play"
            PorticoPlayerTogglePlayback()
            return true
        end if
        if key = "left" or key = "right" or key = "rewind" or key = "fastforward" then return true
    end if
    if m.playerPresenter.focusArea = "panel"
        if key = "up"
            if m.playerPresenter.panelIndex > 0 then m.playerPresenter.panelIndex = m.playerPresenter.panelIndex - 1
        else if key = "down"
            if m.playerPresenter.panelIndex < m.playerPresenter.panelTargets.count() - 1 then m.playerPresenter.panelIndex = m.playerPresenter.panelIndex + 1
        else if key = "left"
            PorticoPlayerPresenterMoveBoundary(m.playerPresenter, "left")
            m.playerPresenter.panelKind = ""
            m.playerPresenter.focusArea = "utility"
        else if key = "OK"
            PorticoPlayerActivatePanelRow()
        else
            return false
        end if
        PorticoPlayerRender()
        return true
    else if m.playerPresenter.focusArea = "utility"
        if key = "left"
            if m.playerPresenter.focusedDock > 0
                m.playerPresenter.focusedDock = m.playerPresenter.focusedDock - 1
            else
                PorticoPlayerPresenterMoveBoundary(m.playerPresenter, "left")
                m.playerPresenter.focusArea = "transport"
            end if
        else if key = "right"
            if m.playerPresenter.focusedDock < m.playerPresenter.dockTargets.count() - 1 then m.playerPresenter.focusedDock = m.playerPresenter.focusedDock + 1
        else if key = "down"
            PorticoPlayerPresenterMoveBoundary(m.playerPresenter, "down")
            m.playerPresenter.focusArea = "transport"
        else if key = "up"
            return true
        else if key = "OK"
            if m.playerPresenter.focusedDock < m.playerPresenter.dockTargets.count()
                PorticoPlayerPresenterMoveBoundary(m.playerPresenter, "up")
                m.playerPresenter.panelKind = m.playerPresenter.dockTargets[m.playerPresenter.focusedDock].kind
                m.playerPresenter.panelIndex = 0
                m.playerPresenter.panelOffset = 0
                m.playerPresenter.focusArea = "panel"
            end if
        else
            return false
        end if
        PorticoPlayerRender()
        return true
    end if
    if key = "left"
        if m.playerPresenter.focusedControl > 0 then m.playerPresenter.focusedControl = m.playerPresenter.focusedControl - 1
        PorticoPlayerUpdateControls()
        return true
    else if key = "right"
        maximumControl = 4
        if m.playerPresenter.focusedControl < maximumControl
            m.playerPresenter.focusedControl = m.playerPresenter.focusedControl + 1
        else if m.playerPresenter.dockTargets.count() > 0
            PorticoPlayerPresenterMoveBoundary(m.playerPresenter, "right")
            m.playerPresenter.focusArea = "utility"
        end if
        PorticoPlayerUpdateControls()
        PorticoPlayerBuildUtilities()
        return true
    else if key = "up"
        if m.playerPresenter.dockTargets.count() > 0
            PorticoPlayerPresenterMoveBoundary(m.playerPresenter, "up")
            m.playerPresenter.focusArea = "utility"
        end if
        PorticoPlayerRender()
        return true
    else if key = "OK"
        PorticoPlayerActivateFocusedControl()
        return true
    else if key = "play"
        PorticoPlayerTogglePlayback()
        return true
    else if key = "rewind"
        PorticoPlayerSeekBy(-PorticoPlayerSeekInterval())
        return true
    else if key = "fastforward"
        PorticoPlayerSeekBy(PorticoPlayerSeekInterval())
        return true
    end if
    return false
end function

sub PorticoPlayerActivateOverlay()
    primary = m.playerPresenter.focusedOverlayAction = 0
    if m.playerPresenter.overlayKind = "segment"
        segmentId = ""
        if m.playerController.model <> invalid and m.playerController.model.segmentDirective <> invalid then segmentId = m.playerController.model.segmentDirective.id
        if primary
            PorticoPlayerEmit("skip-segment", {segmentId: segmentId})
        else
            PorticoPlayerEmit("dismiss-segment", {segmentId: segmentId})
        end if
    else if m.playerPresenter.overlayKind = "postplay"
        if primary then PorticoPlayerEmit("play-now", {}) else PorticoPlayerEmit("cancel-autoplay", {})
    else if m.playerPresenter.overlayKind = "still-watching"
        if primary then PorticoPlayerEmit("confirm-still-watching", {}) else PorticoPlayerEmit("cancel-autoplay", {})
    else if m.playerPresenter.overlayKind = "ended"
        if primary
            PorticoPlayerEmit("replay", {})
        else
            PorticoPlayerRequestExit("ended-close")
        end if
    end if
end sub

sub PorticoPlayerRequestExit(reason as string)
    safeReason = PorticoPlayerSafeLabel(reason, 32)
    if safeReason = "" then safeReason = "back"
    if PorticoPlayerControllerIsAudio(m.playerController)
        PorticoPlayerEmit("exit-browsing", {exitRequested: true, keepPlayback: true, exitReason: safeReason, positionSeconds: m.playerController.positionSeconds, durationSeconds: m.playerController.durationSeconds})
        return
    end if
    PorticoPlayerEmit("stop", {exitRequested: true, exitReason: safeReason, positionSeconds: m.playerController.positionSeconds, durationSeconds: m.playerController.durationSeconds})
end sub

function PorticoPlayerIsLive() as boolean
    return m.playerController.model <> invalid and m.playerController.model.source <> invalid and m.playerController.model.source.isLive = true
end function

function PorticoPlayerCanControl() as boolean
    return m.playerController.model = invalid or m.playerController.model.watchAuthority <> "participant"
end function

function PorticoPlayerCanPause() as boolean
    return m.playerController.model <> invalid and m.playerController.model.source <> invalid and m.playerController.model.source.canPause = true
end function

function PorticoPlayerCanSeek() as boolean
    return m.playerController.model <> invalid and m.playerController.model.source <> invalid and m.playerController.model.source.canSeek = true
end function

sub PorticoPlayerActivateFocusedControl()
    if not PorticoPlayerCanControl() then return
    if m.playerPresenter.focusedControl = 0
        PorticoPlayerEmit("previous", {targetId: ""})
    else if m.playerPresenter.focusedControl = 1
        PorticoPlayerSeekBy(-PorticoPlayerSeekInterval())
    else if m.playerPresenter.focusedControl = 2
        PorticoPlayerTogglePlayback()
    else if m.playerPresenter.focusedControl = 3
        PorticoPlayerSeekBy(PorticoPlayerSeekInterval())
    else if m.playerPresenter.focusedControl = 4
        if m.playerController.model <> invalid and m.playerController.model.watchAuthority = "host"
            PorticoPlayerEmit("watch-control", {action: "next"})
        else
            PorticoPlayerEmit("next", {targetId: ""})
        end if
    end if
end sub

sub PorticoPlayerActivatePanelRow()
    if m.playerPresenter.panelIndex < 0 or m.playerPresenter.panelIndex >= m.playerPresenter.panelTargets.count() then return
    target = m.playerPresenter.panelTargets[m.playerPresenter.panelIndex]
    if target.kind = "set-volume"
        if m.playerController.video.HasField("volume") then m.playerController.video.volume = target.volume
    else if target.kind = "set-speed"
        PorticoPlayerEmit("set-speed", {speed: target.speed})
    else if target.kind = "set-sleep-timer"
        PorticoPlayerEmit("set-sleep-timer", {mode: target.mode})
    else if target.kind = "subtitle-off"
        PorticoPlayerEmit("select-subtitle", {targetId: "", off: true})
    else
        PorticoPlayerEmit(target.kind, {targetId: target.id})
    end if
    m.playerPresenter.panelKind = ""
    m.playerPresenter.focusArea = "transport"
end sub

function PorticoPlayerSeekInterval() as integer
    if m.playerController.model <> invalid and m.playerController.model.preferences <> invalid
        value = PorticoHttpInteger(m.playerController.model.preferences.seekIntervalSeconds, 10)
        if value = 10 or value = 15 or value = 30 then return value
    end if
    return 10
end function

sub PorticoPlayerTogglePlayback()
    if not PorticoPlayerCanControl() or not PorticoPlayerCanPause() then return
    watchHost = m.playerController.model <> invalid and m.playerController.model.watchAuthority = "host"
    if m.playerController.nativeState = "playing"
        m.playerController.video.control = "pause"
        m.playerController.nativeState = "paused"
    else
        if LCase(m.playerController.video.state) = "paused" then m.playerController.video.control = "resume" else m.playerController.video.control = "play"
        m.playerController.nativeState = "playing"
    end if
    m.playerController.localStatusOverride = m.playerController.nativeState
    if watchHost
        action = "play"
        if m.playerController.nativeState = "paused" then action = "pause"
        PorticoPlayerEmit("watch-control", {action: action, positionSeconds: m.playerController.positionSeconds})
    end if
    PorticoPlayerEmitState(false)
    PorticoPlayerRender()
end sub

sub PorticoPlayerSeekBy(deltaSeconds as integer)
    if not PorticoPlayerCanControl() or not PorticoPlayerCanSeek() then return
    target = m.playerController.positionSeconds + deltaSeconds
    minimum = 0
    maximum = m.playerController.durationSeconds
    if m.playerController.model <> invalid and m.playerController.model.source <> invalid
        minimum = Int(m.playerController.model.source.seekableStartSeconds)
        if m.playerController.model.source.seekableEndSeconds > minimum then maximum = Int(m.playerController.model.source.seekableEndSeconds)
    end if
    if target < minimum then target = minimum
    if maximum > 0 and target > maximum then target = maximum
    if PorticoPlayerHasTrickplay()
        PorticoPlayerApplySeek(target, false, false)
        eventKind = "seek-trickplay"
        if m.playerController.model <> invalid and m.playerController.model.watchAuthority = "host" then eventKind = "watch-seek-trickplay"
        PorticoPlayerRequestTrickplay(target, eventKind)
    else
        PorticoPlayerSeekTo(target)
    end if
end sub

function PorticoPlayerHasTrickplay() as boolean
    if m.playerController.model = invalid or m.playerController.model.source = invalid or m.playerController.model.source.isLive = true then return false
    sets = m.playerController.model.source.trickplaySets
    if sets = invalid or sets.Count() = 0 then return false
    for each trickplaySet in sets
        if trickplaySet.stale <> true then return true
    end for
    return false
end function

sub PorticoPlayerRequestTrickplay(positionSeconds as integer, eventKind as string)
    m.trickplayTime.text = PorticoPlayerFormatTime(positionSeconds)
    m.trickplayImage.uri = ""
    m.trickplayImage.visible = false
    m.trickplayPreview.visible = true
    PorticoPlayerEmit(eventKind, {action: "seek", state: m.playerController.nativeState, positionSeconds: positionSeconds, durationSeconds: m.playerController.durationSeconds})
end sub

sub PorticoPlayerSeekTo(seconds as integer)
    if not PorticoPlayerCanControl() or not PorticoPlayerCanSeek() then return
    PorticoPlayerApplySeek(seconds)
end sub

sub PorticoPlayerApplySeek(seconds as integer, emitState = true as boolean, emitWatchControl = true as boolean)
    minimum = 0
    maximum = m.playerController.durationSeconds
    if m.playerController.model <> invalid and m.playerController.model.source <> invalid
        minimum = Int(m.playerController.model.source.seekableStartSeconds)
        if m.playerController.model.source.seekableEndSeconds > minimum then maximum = Int(m.playerController.model.source.seekableEndSeconds)
    end if
    if seconds < minimum then seconds = minimum
    if maximum > 0 and seconds > maximum then seconds = maximum
    m.playerController.positionSeconds = seconds
    m.playerController.video.seek = seconds
    if emitState then PorticoPlayerEmitState(true)
    if emitWatchControl and m.playerController.applyingWatchSync <> true and m.playerController.model <> invalid and m.playerController.model.watchAuthority = "host" then PorticoPlayerEmit("watch-control", {action: "seek", positionSeconds: seconds})
    PorticoPlayerUpdateProgress()
end sub

function PorticoPlayerSafeModel(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    projection = PorticoPlaybackBridgeProjection(value)
    if projection = invalid then return invalid
    generation = projection.playbackGeneration
    sourceGeneration = projection.sourceGeneration
    if generation < 0 or sourceGeneration < 0 then return invalid
    title = ""
    meta = ""
    if projection.source <> invalid
        title = PorticoPlayerSafeLabel(projection.source.title, 180)
        meta = PorticoPlayerSafeLabel(projection.source.subtitle, 180)
    end if
    identity = value.identity
    if identity <> invalid and Type(identity) = "roAssociativeArray"
        identityTitle = PorticoPlayerSafeLabel(identity.title, 180)
        identityMeta = PorticoPlayerSafeLabel(identity.meta, 180)
        if identityTitle <> "" then title = identityTitle
        if identityMeta <> "" then meta = identityMeta
    end if
    return {
        playbackStatus: projection.playbackStatus,
        playbackErrorCode: projection.playbackErrorCode,
        playbackGeneration: generation,
        sourceGeneration: sourceGeneration,
        source: projection.source,
        title: title,
        meta: meta,
        preferences: projection.preferences,
        playbackRate: projection.playbackRate,
        sleepTimerMode: projection.sleepTimerMode,
        postplay: projection.postplay,
        segmentDirective: projection.segmentDirective,
        watchAuthority: projection.watchAuthority,
        trickplayPreview: projection.trickplayPreview,
        remoteStopMessage: projection.remoteStopMessage
    }
end function

function PorticoPlayerSafeLabel(value as dynamic, maximumLength as integer) as string
    if value = invalid then return ""
    label = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(label) > maximumLength then label = Left(label, maximumLength)
    return label
end function

function PorticoPlayerCaptionLanguage(value as dynamic) as string
    language = LCase(PorticoPlayerSafeLabel(value, 32).Replace("_", "-"))
    separator = Instr(1, language, "-")
    if separator > 0 then language = Left(language, separator - 1)
    if language = "en" or language = "eng" then return "eng"
    if language = "fr" or language = "fra" or language = "fre" then return "fre"
    if language = "es" or language = "spa" then return "spa"
    if Len(language) = 3 then return language
    return "und"
end function

function PorticoPlayerBoundedSeconds(value as dynamic, fallback as integer) as integer
    seconds = PorticoHttpInteger(value, fallback)
    if seconds < 0 then return fallback
    if seconds > 2147480000 then return 2147480000
    return seconds
end function

function PorticoPlayerFormatTime(value as dynamic) as string
    seconds = PorticoPlayerBoundedSeconds(value, 0)
    hours = Int(seconds / 3600)
    minutes = Int((seconds mod 3600) / 60)
    remainder = seconds mod 60
    minuteText = minutes.ToStr()
    if hours > 0 and minutes < 10 then minuteText = "0" + minuteText
    secondText = remainder.ToStr()
    if remainder < 10 then secondText = "0" + secondText
    if hours > 0 then return hours.ToStr() + ":" + minuteText + ":" + secondText
    return minutes.ToStr() + ":" + secondText
end function

function PorticoPlayerFailureCopy(code as string) as object
    messageId = "playback.failed"
    if code = "server-offline" then messageId = "problem.server-unavailable"
    if code = "next-playback-unavailable" then messageId = "playback.up-next-failed"
    if code = "playback-not-permitted" then messageId = "problem.forbidden"
    if code = "media-unavailable" or code = "playback-option-unavailable" or code = "playback-response-incompatible" then messageId = "playback.unavailable"
    if code = "playback-source-unavailable" then messageId = "playback.source-failed"
    if code = "media-grant-expired" or code = "grant-response-incompatible" then messageId = "playback.interruption-resume-failed"
    if code = "playback-remote-stopped" then messageId = "playback.remote-stopped"
    return PorticoPlayerMessage(messageId, "Playback unavailable", {})
end function

function PorticoPlayerLyricLines(value as dynamic) as object
    lines = []
    if value = invalid then return lines
    normalized = value.ToStr().Replace(Chr(13), "")
    for each raw in normalized.Tokenize(Chr(10))
        if lines.Count() >= 100 then exit for
        line = PorticoPlayerSafeLabel(raw, 140)
        if line <> "" then lines.Push(line)
    end for
    return lines
end function

sub PorticoPlayerPublishFocusState()
    generation = m.playerController.playbackGeneration
    state = {
        playbackGeneration: generation,
        area: m.playerPresenter.focusArea,
        semanticId: PorticoPlayerPresenterSemanticId(m.playerPresenter),
        transportIndex: m.playerPresenter.focusedControl,
        dockIndex: m.playerPresenter.focusedDock,
        panelKind: m.playerPresenter.panelKind,
        panelIndex: m.playerPresenter.panelIndex,
        overlayKind: m.playerPresenter.overlayKind,
        overlayIndex: m.playerPresenter.focusedOverlayAction
    }
    signature = generation.ToStr() + "|" + state.area + "|" + state.transportIndex.ToStr() + "|" + state.dockIndex.ToStr() + "|" + state.panelKind + "|" + state.panelIndex.ToStr() + "|" + state.overlayKind + "|" + state.overlayIndex.ToStr()
    if signature = m.lastFocusSignature then return
    m.lastFocusSignature = signature
    m.top.focusState = state
end sub

function PorticoPlayerMessage(messageId as string, fallbackTitle as string, variables as object) as object
    if m.language <> invalid
        message = PorticoProductLanguageMessage(m.language, messageId, "playback.failed", variables)
        if message.ok then return message
    end if
    return {title: fallbackTitle, body: "", text: ""}
end function

function PorticoPlayerActionLabel(messageId as string, fallback as string) as string
    return PorticoPlayerActionLabelWithVariables(messageId, fallback, {})
end function

function PorticoPlayerActionLabelWithVariables(messageId as string, fallback as string, variables as object) as string
    if m.language <> invalid
        message = PorticoProductLanguageMessage(m.language, messageId, "action.close-player", variables)
        if message.ok and message.text <> "" then return message.text
    end if
    return fallback
end function

function PorticoPlayerText(messageId as string, fallback as string, variables as object) as string
    if m.language <> invalid
        message = PorticoProductLanguageMessage(m.language, messageId, "watch-with-friends.title", variables)
        if message.ok
            if message.text <> "" then return message.text
            if message.title <> "" then return message.title
            if message.body <> "" then return message.body
        end if
    end if
    return fallback
end function
