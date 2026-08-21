sub init()
    m.top.functionName = "PorticoLiveTvRun"
end sub

sub PorticoLiveTvRun()
    controller = {
        lastCommandSequence: 0,
        serverId: "",
        serverName: "Portico Server",
        serverStatus: "not-connected",
        reconnectRequestedGeneration: -1,
        selectedTab: "guide",
        selectedSourceId: "",
        selectedProgramId: "",
        selectedLibraryChannelId: "",
        sourceSelectionRequired: false,
        sources: [],
        guide: invalid,
        channelPageModel: invalid,
        libraryChannels: invalid,
        dvr: invalid,
        dvrAuthorized: false,
        status: "idle",
        message: invalid,
        mutationMessage: invalid,
        dvrCollectionState: {recordings: "idle", rules: "idle", schedule: "idle"},
        dayOffset: 0,
        windowOffsetMinutes: 0,
        windowSeconds: 10800,
        guideFilter: "all",
        guideGroup: "",
        guideQuery: "",
        channelPage: 0,
        dvrPage: 0,
        libraryPage: 0,
        serverClock: {epoch: 0, timer: invalid},
        cacheState: "none",
        quietRefresh: false
    }
    PorticoChannelsTaskAdopt(controller, PorticoChannelsTaskState())
    PorticoBrowsePrepareArtworkDirectory("channels")
    PorticoLiveTvPublish(controller, false)
    while true
        PorticoLiveTvHandleCommand(controller)
        Sleep(250)
    end while
end sub

sub PorticoLiveTvHandleCommand(controller as object)
    command = invalid
    if m.top.commandEnvelope <> invalid
        previousGeneration = controller.viewerGeneration
        command = PorticoChannelsAcceptCommand(controller, m.top.commandEnvelope)
        if command <> invalid and previousGeneration > 0 and previousGeneration <> controller.viewerGeneration then PorticoLiveTvFence(controller)
    else if not controller.envelopeMode
        legacy = m.top.command
        if legacy <> invalid and Type(legacy) = "roAssociativeArray"
            sequence = PorticoHttpInteger(legacy.sequence, 0)
            if sequence > controller.lastCommandSequence
                controller.lastCommandSequence = sequence
                command = legacy
            end if
        end if
    end if
    if command = invalid then return
    kind = LCase(PorticoHttpScalarString(command.kind, ""))
    if kind = "viewer-fence"
        PorticoLiveTvFence(controller)
    else if kind = "server-state"
        PorticoLiveTvApplyServerState(controller, command)
    else if kind = "select-source"
        PorticoLiveTvSelectSource(controller, command.sourceId)
    else if kind = "select-tab"
        PorticoLiveTvSelectTab(controller, command.tabId)
    else if kind = "select-program"
        PorticoLiveTvSelectProgram(controller, command.programId)
        PorticoLiveTvPublish(controller, false)
    else if kind = "open-guide-program"
        ' The Channels grid is a shortcut into the Guide, matching the
        ' television reference client. Make selection + tab change one Task
        ' command so a latest-value mailbox cannot drop either half.
        controller.selectedProgramId = PorticoViewerScopeOpaqueId(command.programId, 160)
        controller.selectedTab = "guide"
        if controller.guide = invalid
            PorticoLiveTvLoadGuide(controller, "")
        else
            PorticoLiveTvSelectProgram(controller, controller.selectedProgramId)
            PorticoLiveTvPublish(controller, false)
        end if
    else if kind = "select-library-channel"
        controller.selectedLibraryChannelId = PorticoViewerScopeOpaqueId(command.channelId, 128)
        PorticoLiveTvSelectLibraryChannel(controller)
        PorticoLiveTvPublish(controller, false)
    else if kind = "set-guide-day"
        PorticoLiveTvSetGuideDay(controller, command.dayOffset)
    else if kind = "shift-guide-window"
        PorticoLiveTvShiftGuideWindow(controller, command.deltaMinutes)
    else if kind = "set-guide-filter"
        PorticoLiveTvSetGuideFilter(controller, command.filterId)
    else if kind = "set-guide-group"
        PorticoLiveTvSetGuideGroup(controller, command.group)
    else if kind = "set-guide-query"
        PorticoLiveTvSetGuideQuery(controller, command.query)
    else if kind = "page-channels"
        PorticoLiveTvChangePage(controller, PorticoHttpInteger(command.delta, 0))
    else if kind = "load-more-guide" or kind = "load-more-channels" or kind = "load-more-library-channels" or kind = "load-more-dvr" or kind = "load-more-dvr-recordings" or kind = "load-more-dvr-rules" or kind = "load-more-dvr-schedule"
        PorticoLiveTvLoadMore(controller, kind)
    else if kind = "record-program"
        PorticoLiveTvRecordProgram(controller, command.programId, false)
    else if kind = "record-series"
        PorticoLiveTvRecordProgram(controller, command.programId, true)
    else if kind = "toggle-dvr-rule"
        PorticoLiveTvToggleRule(controller, command.ruleId)
    else if kind = "delete-dvr-rule"
        PorticoLiveTvDeleteRule(controller, command.ruleId)
    else if kind = "cancel-dvr-recording" or kind = "delete-dvr-recording"
        PorticoLiveTvDeleteRecording(controller, command.recordingId)
    else if kind = "retry-channels"
        PorticoLiveTvRetry(controller)
    else if kind = "quiet-refresh-channels"
        if controller.serverStatus = "online"
            controller.quietRefresh = true
            PorticoLiveTvRetry(controller)
        end if
    end if
end sub

sub PorticoLiveTvFence(controller as object)
    controller.serverId = ""
    controller.serverStatus = "not-connected"
    controller.selectedSourceId = ""
    controller.selectedProgramId = ""
    controller.selectedLibraryChannelId = ""
    controller.sources = []
    controller.guide = invalid
    controller.channelPageModel = invalid
    controller.libraryChannels = invalid
    controller.dvr = invalid
    controller.dvrAuthorized = false
    controller.status = "idle"
    controller.message = invalid
    controller.mutationMessage = invalid
    PorticoLiveTvPublish(controller, false)
end sub

sub PorticoLiveTvApplyServerState(controller as object, command as object)
    requestedServerId = PorticoViewerScopeOpaqueId(command.selectedServerId, 128)
    if controller.envelopeMode
        scope = PorticoViewerScopeNormalize(controller.viewerScope)
        if scope = invalid or requestedServerId <> scope.serverId then return
    end if
    changed = requestedServerId <> controller.serverId
    controller.serverId = requestedServerId
    controller.serverName = PorticoCoreSafeText(command.selectedServerName, 100)
    if controller.serverName = "" then controller.serverName = "Portico Server"
    controller.serverStatus = LCase(PorticoHttpScalarString(command.serverStatus, "not-connected"))
    if changed
        controller.selectedSourceId = ""
        controller.selectedProgramId = ""
        controller.selectedLibraryChannelId = ""
        controller.sources = []
        controller.guide = invalid
        controller.channelPageModel = invalid
        controller.libraryChannels = invalid
        controller.dvr = invalid
        controller.dvrAuthorized = false
        controller.dayOffset = 0
        controller.windowOffsetMinutes = 0
        controller.guideFilter = "all"
        controller.guideGroup = ""
        controller.guideQuery = ""
        controller.cacheState = "none"
    end if
    if controller.serverId = "" or controller.serverStatus = "not-connected"
        controller.status = "idle"
        PorticoLiveTvPublish(controller, false)
    else if controller.serverStatus = "online"
        PorticoLiveTvBootstrap(controller)
    else
        PorticoLiveTvRestoreCached(controller)
    end if
end sub

sub PorticoLiveTvBootstrap(controller as object)
    PorticoLiveTvBeginRefresh(controller)
    result = PorticoChannelsRequest(controller, "getLiveTv", {}, {}, "")
    if result.interrupted then return
    if not result.ok
        if result.status = 403 or result.status = 404
            controller.sources = []
            controller.selectedSourceId = ""
            controller.sourceSelectionRequired = false
            controller.selectedTab = "library-channels"
            if PorticoChannelsOperationAvailable(controller, "getLibraryChannelsGuide")
                PorticoLiveTvLoadLibraryChannels(controller, "")
            else
                controller.status = "empty"
                controller.message = PorticoChannelsCopy(controller, "live-tv.empty", "live-tv.empty", {})
                PorticoLiveTvPublish(controller, false)
            end if
            return
        end if
        PorticoLiveTvFail(controller, result, "live-tv.load-failed", {featureName: "Channels"})
        return
    end if
    sources = PorticoLiveTvSourcesModel(result.data)
    previousSource = controller.selectedSourceId
    controller.sources = sources
    controller.selectedSourceId = ""
    for each source in sources
        if source.id = previousSource then controller.selectedSourceId = source.id
    end for
    if sources.Count() = 1 then controller.selectedSourceId = sources[0].id
    controller.sourceSelectionRequired = sources.Count() > 1 and controller.selectedSourceId = ""
    if controller.sourceSelectionRequired
        controller.status = "choose-source"
        ' Source-choice copy is rendered locally until Product Language exposes a
        ' canonical source-selection message. Do not mislabel this state as empty.
        controller.message = invalid
        PorticoLiveTvPublish(controller, false)
        return
    end if
    if controller.selectedSourceId <> ""
        PorticoLiveTvProbeDvr(controller)
        if controller.selectedTab = "library-channels" then PorticoLiveTvLoadLibraryChannels(controller, "") else PorticoLiveTvLoadGuide(controller, "")
    else
        controller.selectedTab = "library-channels"
        PorticoLiveTvLoadLibraryChannels(controller, "")
    end if
end sub

sub PorticoLiveTvBeginRefresh(controller as object)
    if controller.quietRefresh then return
    if controller.guide <> invalid or controller.libraryChannels <> invalid or controller.dvr <> invalid
        controller.status = "refreshing"
    else
        controller.status = "loading"
    end if
    controller.message = invalid
    controller.mutationMessage = invalid
    PorticoLiveTvPublish(controller, false)
end sub

sub PorticoLiveTvSelectSource(controller as object, rawSourceId as dynamic)
    sourceId = PorticoViewerScopeOpaqueId(rawSourceId, 128)
    found = false
    for each source in controller.sources
        if source.id = sourceId then found = true
    end for
    if not found then return
    if sourceId <> controller.selectedSourceId
        controller.selectedSourceId = sourceId
        controller.selectedProgramId = ""
        controller.guide = invalid
        controller.channelPageModel = invalid
        controller.dvr = invalid
        controller.dvrAuthorized = false
        controller.channelPage = 0
        controller.dvrPage = 0
        controller.dayOffset = 0
        controller.windowOffsetMinutes = 0
        controller.guideGroup = ""
        controller.guideQuery = ""
    end if
    controller.sourceSelectionRequired = false
    controller.selectedTab = "guide"
    if controller.serverStatus = "online"
        PorticoLiveTvProbeDvr(controller)
        PorticoLiveTvLoadGuide(controller, "")
    else
        PorticoLiveTvRestoreCached(controller)
    end if
end sub

sub PorticoLiveTvSelectTab(controller as object, rawTabId as dynamic)
    tabId = LCase(PorticoCoreSafeIdentifier(rawTabId, 40))
    if tabId <> "guide" and tabId <> "channels" and tabId <> "dvr" and tabId <> "library-channels" then return
    if tabId <> "library-channels" and controller.selectedSourceId = "" then return
    if tabId = "dvr" and not controller.dvrAuthorized then return
    controller.selectedTab = tabId
    controller.message = invalid
    controller.mutationMessage = invalid
    if controller.serverStatus <> "online"
        PorticoLiveTvRestoreCached(controller)
        return
    end if
    if tabId = "library-channels"
        PorticoLiveTvLoadLibraryChannels(controller, "")
    else if tabId = "dvr"
        PorticoLiveTvLoadDvr(controller, "", "", "")
    else if tabId = "channels"
        PorticoLiveTvLoadChannels(controller, "")
    else
        PorticoLiveTvLoadGuide(controller, "")
    end if
end sub

sub PorticoLiveTvProbeDvr(controller as object)
    controller.dvrAuthorized = false
    if controller.selectedSourceId = "" or not PorticoChannelsOperationAvailable(controller, "getDVRStatus") then return
    result = PorticoChannelsRequest(controller, "getDVRStatus", {}, {sourceId: controller.selectedSourceId}, "")
    if result.interrupted then return
    if result.ok
        controller.dvrAuthorized = true
        if controller.dvr = invalid then controller.dvr = PorticoLiveTvDvrModel(invalid, invalid, invalid, result.data)
    end if
end sub

sub PorticoLiveTvLoadGuide(controller as object, cursor as string)
    if controller.selectedSourceId = "" then return
    PorticoLiveTvBeginRefresh(controller)
    fromEpoch = PorticoLiveTvGuideWindowStart(controller)
    query = {from: PorticoLiveTvIso(fromEpoch), hours: 4, limit: 100, count: "exact"}
    if cursor <> "" then query.cursor = cursor
    if controller.guideQuery <> "" then query.query = controller.guideQuery
    if controller.guideFilter <> "all" then query.filter = controller.guideFilter
    if controller.guideGroup <> "" then query.group = controller.guideGroup
    result = PorticoChannelsRequest(controller, "getLiveTvSourcesSourceIdGuide", {sourceId: controller.selectedSourceId}, query, "")
    if result.interrupted then return
    if not result.ok
        PorticoLiveTvLoadGuideWithoutSchedule(controller, fromEpoch)
        return
    end if
    jobs = []
    model = PorticoLiveTvGuideModel(result.data, controller.selectedProgramId, fromEpoch, controller.windowSeconds, controller.serverClock, jobs)
    if model = invalid
        PorticoLiveTvLoadGuideWithoutSchedule(controller, fromEpoch)
        return
    end if
    if cursor <> "" and controller.guide <> invalid
        PorticoLiveTvAppendGuide(controller.guide, model)
        controller.channelPage = controller.channelPage + 1
    else
        controller.guide = model
    end if
    if controller.guide.selectedProgram <> invalid then controller.selectedProgramId = controller.guide.selectedProgram.id
    controller.status = "ready"
    if controller.guide.channels.Count() = 0 then controller.status = "empty"
    controller.message = invalid
    controller.cacheState = "fresh"
    controller.quietRefresh = false
    PorticoLiveTvCacheWorkspace(controller)
    PorticoLiveTvPublish(controller, false)
    PorticoLiveTvMaterializeArtwork(controller, jobs)
end sub

' Channel discovery and schedule discovery are deliberately independent. A
' missing or temporarily unavailable EPG must never take the channel guide
' with it: materialize a stable, empty schedule grid from the channel endpoint
' and let a later refresh replace it with real programme cells in place.
sub PorticoLiveTvLoadGuideWithoutSchedule(controller as object, fromEpoch as longinteger)
    query = {limit: 100, count: "exact"}
    if controller.guideQuery <> "" then query.query = controller.guideQuery
    if controller.guideFilter = "favorites" then query.favoritesOnly = true
    if controller.guideGroup <> "" then query.group = controller.guideGroup
    result = PorticoChannelsRequest(controller, "getLiveTvSourcesSourceIdChannels", {sourceId: controller.selectedSourceId}, query, "")
    if result.interrupted then return
    if not result.ok
        PorticoLiveTvFail(controller, result, "live-tv.load-failed", {featureName: "Channels"})
        return
    end if
    jobs = []
    page = PorticoLiveTvChannelPageModel(result.data, invalid, jobs)
    if page = invalid
        PorticoLiveTvFail(controller, PorticoBrowseHttpFailure(0, false, "invalid_response"), "live-tv.load-failed", {featureName: "Channels"})
        return
    end if
    controller.guide = {
        channels: page.channels,
        selectedProgram: invalid,
        capabilities: {},
        channelGroups: page.groups,
        serverNowEpoch: PorticoLiveTvServerNow(controller.serverClock),
        timelineStartEpoch: fromEpoch,
        timelineEndEpoch: fromEpoch + controller.windowSeconds,
        pageInfo: page.pageInfo
    }
    controller.status = "ready"
    if controller.guide.channels.Count() = 0 then controller.status = "empty"
    controller.message = invalid
    controller.cacheState = "fresh"
    controller.quietRefresh = false
    PorticoLiveTvCacheWorkspace(controller)
    PorticoLiveTvPublish(controller, false)
    PorticoLiveTvMaterializeArtwork(controller, jobs)
end sub

sub PorticoLiveTvLoadChannels(controller as object, cursor as string)
    if controller.selectedSourceId = "" then return
    PorticoLiveTvBeginRefresh(controller)
    query = {limit: 100, count: "exact"}
    if cursor <> "" then query.cursor = cursor
    if controller.guideQuery <> "" then query.query = controller.guideQuery
    if controller.guideFilter = "favorites" then query.favoritesOnly = true
    if controller.guideGroup <> "" then query.group = controller.guideGroup
    result = PorticoChannelsRequest(controller, "getLiveTvSourcesSourceIdChannels", {sourceId: controller.selectedSourceId}, query, "")
    if result.interrupted then return
    if not result.ok
        PorticoLiveTvFail(controller, result, "live-tv.load-failed", {featureName: "Channels"})
        return
    end if
    jobs = []
    model = PorticoLiveTvChannelPageModel(result.data, controller.guide, jobs)
    if model = invalid
        PorticoLiveTvFail(controller, PorticoBrowseHttpFailure(0, false, "invalid_response"), "live-tv.load-failed", {featureName: "Channels"})
        return
    end if
    if cursor <> "" and controller.channelPageModel <> invalid
        PorticoLiveTvAppendChannels(controller.channelPageModel.channels, model.channels)
        controller.channelPageModel.pageInfo = model.pageInfo
        controller.channelPage = controller.channelPage + 1
    else
        controller.channelPageModel = model
    end if
    controller.status = "ready"
    if controller.channelPageModel.channels.Count() = 0 then controller.status = "empty"
    controller.message = invalid
    controller.cacheState = "fresh"
    controller.quietRefresh = false
    PorticoLiveTvCacheWorkspace(controller)
    PorticoLiveTvPublish(controller, false)
    PorticoLiveTvMaterializeArtwork(controller, jobs)
end sub

sub PorticoLiveTvLoadLibraryChannels(controller as object, cursor as string)
    if not PorticoChannelsOperationAvailable(controller, "getLibraryChannelsGuide")
        controller.status = "unavailable"
        controller.message = PorticoChannelsCopy(controller, "library-channel.load-failed", "library-channel.load-failed", {})
        PorticoLiveTvPublish(controller, false)
        return
    end if
    PorticoLiveTvBeginRefresh(controller)
    fromEpoch = PorticoLiveTvLibraryDayStart(controller)
    query = {from: PorticoLiveTvIso(fromEpoch), to: PorticoLiveTvIso(fromEpoch + 86400), limit: 100}
    if cursor <> "" then query.cursor = cursor
    result = PorticoChannelsRequest(controller, "getLibraryChannelsGuide", {}, query, "")
    if result.interrupted then return
    if not result.ok
        PorticoLiveTvFail(controller, result, "library-channel.load-failed", {})
        return
    end if
    jobs = []
    model = PorticoLiveTvLibraryChannelsModel(result.data, controller.selectedLibraryChannelId, controller.serverClock, fromEpoch, 86400, jobs)
    if model = invalid
        PorticoLiveTvFail(controller, PorticoBrowseHttpFailure(0, false, "invalid_response"), "library-channel.load-failed", {})
        return
    end if
    if cursor <> "" and controller.libraryChannels <> invalid
        PorticoLiveTvAppendChannels(controller.libraryChannels.channels, model.channels)
        PorticoLiveTvAppendLibraryPrograms(controller.libraryChannels.channels, model.channels)
        controller.libraryChannels.pageInfo = model.pageInfo
        controller.libraryPage = controller.libraryPage + 1
    else
        controller.libraryChannels = model
    end if
    if controller.libraryChannels.selectedChannel <> invalid then controller.selectedLibraryChannelId = controller.libraryChannels.selectedChannel.id
    controller.status = "ready"
    if controller.libraryChannels.channels.Count() = 0 then controller.status = "empty"
    controller.message = invalid
    controller.cacheState = "fresh"
    controller.quietRefresh = false
    PorticoLiveTvCacheWorkspace(controller)
    PorticoLiveTvPublish(controller, false)
    PorticoLiveTvMaterializeArtwork(controller, jobs)
end sub

sub PorticoLiveTvLoadDvr(controller as object, recordingsCursor as string, rulesCursor as string, scheduleCursor as string, appendKind = "" as string)
    if not controller.dvrAuthorized then return
    if appendKind <> ""
        cursor = recordingsCursor
        if appendKind = "rules" then cursor = rulesCursor
        if appendKind = "schedule" then cursor = scheduleCursor
        PorticoLiveTvLoadDvrCollection(controller, appendKind, cursor)
        return
    end if
    PorticoLiveTvBeginRefresh(controller)
    recordingsQuery = {limit: 100, count: "exact"}
    if recordingsCursor <> "" then recordingsQuery.cursor = recordingsCursor
    recordings = PorticoChannelsRequest(controller, "getDvrRecordings", {}, recordingsQuery, "")
    if recordings.interrupted then return
    if not recordings.ok
        if appendKind = "recordings"
            controller.dvrCollectionState.recordings = "error"
            controller.mutationMessage = PorticoChannelsFailureCopy(controller, recordings, "dvr.unavailable", {})
            PorticoLiveTvPublish(controller, recordings.status = 401)
            return
        end if
        PorticoLiveTvFail(controller, recordings, "dvr.unavailable", {})
        return
    end if
    rulesQuery = {limit: 100, count: "exact"}
    if rulesCursor <> "" then rulesQuery.cursor = rulesCursor
    rules = PorticoChannelsRequest(controller, "getDvrRules", {}, rulesQuery, "")
    if rules.interrupted then return
    if not rules.ok
        if appendKind = "rules"
            controller.dvrCollectionState.rules = "error"
            controller.mutationMessage = PorticoChannelsFailureCopy(controller, rules, "dvr.unavailable", {})
            PorticoLiveTvPublish(controller, rules.status = 401)
            return
        end if
        PorticoLiveTvFail(controller, rules, "dvr.unavailable", {})
        return
    end if
    scheduleQuery = {limit: 100}
    if scheduleCursor <> "" then scheduleQuery.cursor = scheduleCursor
    schedule = PorticoChannelsRequest(controller, "getDvrSchedule", {}, scheduleQuery, "")
    if schedule.interrupted then return
    if not schedule.ok
        if appendKind = "schedule"
            controller.dvrCollectionState.schedule = "error"
            controller.mutationMessage = PorticoChannelsFailureCopy(controller, schedule, "dvr.unavailable", {})
            PorticoLiveTvPublish(controller, schedule.status = 401)
            return
        end if
        PorticoLiveTvFail(controller, schedule, "dvr.unavailable", {})
        return
    end if
    status = PorticoChannelsRequest(controller, "getDVRStatus", {}, {sourceId: controller.selectedSourceId}, "")
    if status.interrupted then return
    if not status.ok
        PorticoLiveTvFail(controller, status, "dvr.unavailable", {})
        return
    end if
    model = PorticoLiveTvDvrModel(recordings.data, rules.data, schedule.data, status.data)
    if appendKind <> "" and controller.dvr <> invalid
        if appendKind = "recordings"
            PorticoLiveTvAppendRecordings(controller.dvr.recordings, model.recordings)
            controller.dvr.recordingPageInfo = model.recordingPageInfo
        else if appendKind = "rules"
            PorticoLiveTvAppendRules(controller.dvr.rules, model.rules)
            controller.dvr.rulesPageInfo = model.rulesPageInfo
        else if appendKind = "schedule"
            PorticoLiveTvAppendRecordings(controller.dvr.schedule, model.schedule)
            controller.dvr.schedulePageInfo = model.schedulePageInfo
        end if
        controller.dvr.conflicts = model.conflicts
        controller.dvr.capabilities = model.capabilities
        controller.dvrPage = controller.dvrPage + 1
        controller.dvrCollectionState[appendKind] = "ready"
    else
        controller.dvr = model
        controller.dvrCollectionState = {recordings: "ready", rules: "ready", schedule: "ready"}
    end if
    controller.status = "ready"
    controller.message = invalid
    controller.cacheState = "fresh"
    controller.quietRefresh = false
    PorticoLiveTvCacheWorkspace(controller)
    PorticoLiveTvPublish(controller, false)
end sub

sub PorticoLiveTvLoadDvrCollection(controller as object, kind as string, cursor as string)
    if controller.dvr = invalid or not controller.dvrAuthorized then return
    operationId = ""
    query = {limit: 100}
    if kind = "recordings"
        operationId = "getDvrRecordings"
        query.count = "exact"
    else if kind = "rules"
        operationId = "getDvrRules"
        query.count = "exact"
    else if kind = "schedule"
        operationId = "getDvrSchedule"
    else
        return
    end if
    if cursor <> "" then query.cursor = cursor
    controller.dvrCollectionState[kind] = "loading"
    PorticoLiveTvPublish(controller, false)
    result = PorticoChannelsRequest(controller, operationId, {}, query, "")
    if result.interrupted then return
    if not result.ok
        controller.dvrCollectionState[kind] = "error"
        controller.mutationMessage = PorticoChannelsFailureCopy(controller, result, "dvr.unavailable", {})
        PorticoLiveTvPublish(controller, result.status = 401)
        return
    end if
    model = invalid
    if kind = "recordings"
        model = PorticoLiveTvDvrModel(result.data, invalid, invalid, invalid)
        PorticoLiveTvAppendRecordings(controller.dvr.recordings, model.recordings)
        controller.dvr.recordingPageInfo = model.recordingPageInfo
    else if kind = "rules"
        model = PorticoLiveTvDvrModel(invalid, result.data, invalid, invalid)
        PorticoLiveTvAppendRules(controller.dvr.rules, model.rules)
        controller.dvr.rulesPageInfo = model.rulesPageInfo
    else
        model = PorticoLiveTvDvrModel(invalid, invalid, result.data, invalid)
        PorticoLiveTvAppendRecordings(controller.dvr.schedule, model.schedule)
        controller.dvr.schedulePageInfo = model.schedulePageInfo
    end if
    controller.dvrPage = controller.dvrPage + 1
    controller.dvrCollectionState[kind] = "ready"
    controller.status = "ready"
    controller.cacheState = "fresh"
    controller.quietRefresh = false
    PorticoLiveTvCacheWorkspace(controller)
    PorticoLiveTvPublish(controller, false)
end sub

sub PorticoLiveTvLoadMore(controller as object, kind as string)
    if controller.serverStatus <> "online" then return
    if kind = "load-more-guide" and controller.guide <> invalid and controller.guide.pageInfo.hasMore
        PorticoLiveTvLoadGuide(controller, controller.guide.pageInfo.nextCursor)
    else if kind = "load-more-channels" and controller.channelPageModel <> invalid and controller.channelPageModel.pageInfo.hasMore
        PorticoLiveTvLoadChannels(controller, controller.channelPageModel.pageInfo.nextCursor)
    else if kind = "load-more-library-channels" and controller.libraryChannels <> invalid and controller.libraryChannels.pageInfo.hasMore
        PorticoLiveTvLoadLibraryChannels(controller, controller.libraryChannels.pageInfo.nextCursor)
    else if (kind = "load-more-dvr" or kind = "load-more-dvr-recordings") and controller.dvr <> invalid and controller.dvr.recordingPageInfo.hasMore
        PorticoLiveTvLoadDvrCollection(controller, "recordings", controller.dvr.recordingPageInfo.nextCursor)
    else if kind = "load-more-dvr-rules" and controller.dvr <> invalid and controller.dvr.rulesPageInfo.hasMore
        PorticoLiveTvLoadDvrCollection(controller, "rules", controller.dvr.rulesPageInfo.nextCursor)
    else if kind = "load-more-dvr-schedule" and controller.dvr <> invalid and controller.dvr.schedulePageInfo.hasMore
        PorticoLiveTvLoadDvrCollection(controller, "schedule", controller.dvr.schedulePageInfo.nextCursor)
    end if
end sub

sub PorticoLiveTvRecordProgram(controller as object, rawProgramId as dynamic, series as boolean)
    if controller.guide = invalid or controller.selectedSourceId = "" or controller.serverStatus <> "online" then return
    programId = PorticoViewerScopeOpaqueId(rawProgramId, 160)
    target = PorticoLiveTvFindProgram(controller.guide.channels, programId)
    if target = invalid then return
    action = "dvr.record"
    operationId = "postDvrRecordings"
    body = {sourceId: controller.selectedSourceId, channelId: target.channelId, programId: target.id, title: target.title, startsAt: target.startAt, endsAt: target.endAt}
    if series
        action = "dvr.record-series"
        operationId = "postDvrRules"
        body = {sourceId: controller.selectedSourceId, channelId: target.channelId, programId: target.id, title: target.title, matchType: "series"}
    end if
    if not PorticoLiveTvHasAction(target.actions, action) or not controller.dvrAuthorized or not PorticoChannelsOperationAvailable(controller, operationId) then return
    controller.status = "working"
    PorticoLiveTvPublish(controller, false)
    result = PorticoChannelsRequest(controller, operationId, {}, {}, body)
    if result.interrupted
        controller.status = "ready"
        controller.mutationMessage = {title: "Recording wasn't scheduled", body: "Try again."}
        PorticoLiveTvPublish(controller, false)
        return
    end if
    if not result.ok
        controller.status = "ready"
        controller.mutationMessage = PorticoChannelsFailureCopy(controller, result, "live-tv.action-failed", {actionName: "schedule this recording"})
        if result.status = 409 then PorticoLiveTvLoadDvr(controller, "", "", "") else PorticoLiveTvPublish(controller, result.status = 401)
        return
    end if
    controller.status = "ready"
    actionLabel = "Recording scheduled"
    if series then actionLabel = "Series recording scheduled"
    controller.mutationMessage = {title: actionLabel, body: actionLabel}
    PorticoLiveTvLoadDvr(controller, "", "", "")
end sub

sub PorticoLiveTvToggleRule(controller as object, rawRuleId as dynamic)
    rule = PorticoLiveTvFindRule(controller, rawRuleId)
    if rule = invalid or not rule.canToggle or not PorticoChannelsOperationAvailable(controller, "patchDvrRulesId") then return
    result = PorticoChannelsRequest(controller, "patchDvrRulesId", {id: rule.id}, {}, {expectedRevision: rule.revision, enabled: not rule.enabled})
    if result.interrupted
        controller.mutationMessage = {title: "Recording rule wasn't updated", body: "Try again."}
        PorticoLiveTvPublish(controller, false)
        return
    end if
    if not result.ok
        controller.mutationMessage = PorticoChannelsFailureCopy(controller, result, "live-tv.action-failed", {actionName: "update that recording rule"})
        if result.status = 409 then PorticoLiveTvLoadDvr(controller, "", "", "") else PorticoLiveTvPublish(controller, result.status = 401)
        return
    end if
    controller.mutationMessage = {title: "Recording rule updated", body: "Recording rule updated"}
    PorticoLiveTvLoadDvr(controller, "", "", "")
end sub

sub PorticoLiveTvDeleteRule(controller as object, rawRuleId as dynamic)
    rule = PorticoLiveTvFindRule(controller, rawRuleId)
    if rule = invalid or not rule.canDelete or not PorticoChannelsOperationAvailable(controller, "deleteDvrRulesId") then return
    result = PorticoChannelsRequest(controller, "deleteDvrRulesId", {id: rule.id}, {}, "")
    if result.interrupted
        controller.mutationMessage = {title: "Recording rule wasn't deleted", body: "Try again."}
        PorticoLiveTvPublish(controller, false)
        return
    end if
    if not result.ok
        controller.mutationMessage = PorticoChannelsFailureCopy(controller, result, "live-tv.action-failed", {actionName: "delete that recording rule"})
        if result.status = 409 then PorticoLiveTvLoadDvr(controller, "", "", "") else PorticoLiveTvPublish(controller, result.status = 401)
        return
    end if
    controller.mutationMessage = {title: "Recording rule deleted", body: "Recording rule deleted"}
    PorticoLiveTvLoadDvr(controller, "", "", "")
end sub

sub PorticoLiveTvDeleteRecording(controller as object, rawRecordingId as dynamic)
    recording = PorticoLiveTvFindRecording(controller, rawRecordingId)
    if recording = invalid or (not recording.cancellable and not recording.deletable) or not PorticoChannelsOperationAvailable(controller, "deleteDvrRecordingsId") then return
    result = PorticoChannelsRequest(controller, "deleteDvrRecordingsId", {id: recording.id}, {}, "")
    if result.interrupted
        controller.mutationMessage = {title: "Recording wasn't changed", body: "Try again."}
        PorticoLiveTvPublish(controller, false)
        return
    end if
    if not result.ok
        controller.mutationMessage = PorticoChannelsFailureCopy(controller, result, "live-tv.action-failed", {actionName: "change that recording"})
        if result.status = 409 then PorticoLiveTvLoadDvr(controller, "", "", "") else PorticoLiveTvPublish(controller, result.status = 401)
        return
    end if
    successCopy = "Recording deleted"
    if recording.cancellable and not recording.deletable then successCopy = "Recording cancelled"
    controller.mutationMessage = {title: successCopy, body: successCopy}
    PorticoLiveTvLoadDvr(controller, "", "", "")
end sub

sub PorticoLiveTvSetGuideDay(controller as object, rawOffset as dynamic)
    offset = PorticoHttpInteger(rawOffset, 0)
    if offset < 0 or offset > 6 then return
    controller.dayOffset = offset
    controller.windowOffsetMinutes = 0
    controller.selectedProgramId = ""
    if controller.selectedTab = "library-channels" then PorticoLiveTvLoadLibraryChannels(controller, "") else PorticoLiveTvLoadGuide(controller, "")
end sub

sub PorticoLiveTvShiftGuideWindow(controller as object, rawDelta as dynamic)
    delta = PorticoHttpInteger(rawDelta, 0)
    if delta <> -120 and delta <> 120 then return
    nextOffset = controller.windowOffsetMinutes + delta
    if nextOffset < 0 then nextOffset = 0
    if nextOffset > 1260 then nextOffset = 1260
    if nextOffset = controller.windowOffsetMinutes then return
    controller.windowOffsetMinutes = nextOffset
    controller.selectedProgramId = ""
    PorticoLiveTvLoadGuide(controller, "")
end sub

sub PorticoLiveTvSetGuideFilter(controller as object, rawFilter as dynamic)
    filterId = LCase(PorticoCoreSafeIdentifier(rawFilter, 24))
    allowed = {all: true, favorites: true, sports: true, news: true, movies: true}
    if allowed[filterId] <> true then return
    controller.guideFilter = filterId
    controller.selectedProgramId = ""
    if controller.selectedTab = "channels" then PorticoLiveTvLoadChannels(controller, "") else PorticoLiveTvLoadGuide(controller, "")
end sub

sub PorticoLiveTvSetGuideGroup(controller as object, rawGroup as dynamic)
    group = PorticoCoreSafeText(rawGroup, 80)
    if group <> ""
        found = false
        if controller.guide <> invalid
            for each candidate in controller.guide.channelGroups
                if candidate = group then found = true
            end for
        end if
        if not found then return
    end if
    controller.guideGroup = group
    controller.selectedProgramId = ""
    if controller.selectedTab = "channels" then PorticoLiveTvLoadChannels(controller, "") else PorticoLiveTvLoadGuide(controller, "")
end sub

sub PorticoLiveTvSetGuideQuery(controller as object, rawQuery as dynamic)
    query = PorticoCoreSafeText(rawQuery, 120)
    controller.guideQuery = query
    controller.selectedProgramId = ""
    if controller.selectedTab = "channels" then PorticoLiveTvLoadChannels(controller, "") else PorticoLiveTvLoadGuide(controller, "")
end sub

sub PorticoLiveTvChangePage(controller as object, delta as integer)
    if delta <> -1 and delta <> 1 then return
    total = 0
    pageSize = 5
    currentPage = controller.channelPage
    if controller.selectedTab = "dvr"
        pageSize = 4
        currentPage = controller.dvrPage
        if controller.dvr <> invalid then total = controller.dvr.recordings.Count()
    else if controller.selectedTab = "library-channels"
        pageSize = 5
        currentPage = controller.libraryPage
        if controller.libraryChannels <> invalid then total = controller.libraryChannels.channels.Count()
    else if controller.selectedTab = "channels"
        pageSize = 8
        if controller.channelPageModel <> invalid then total = controller.channelPageModel.channels.Count()
    else
        if controller.guide <> invalid then total = controller.guide.channels.Count()
    end if
    maximum = 0
    if total > 0 then maximum = Int((total - 1) / pageSize)
    nextPage = currentPage + delta
    if nextPage < 0 then nextPage = 0
    if nextPage > maximum then nextPage = maximum
    if controller.selectedTab = "dvr" then controller.dvrPage = nextPage else if controller.selectedTab = "library-channels" then controller.libraryPage = nextPage else controller.channelPage = nextPage
    PorticoLiveTvPublish(controller, false)
end sub

sub PorticoLiveTvSelectProgram(controller as object, rawProgramId as dynamic)
    if controller.guide = invalid then return
    programId = PorticoViewerScopeOpaqueId(rawProgramId, 160)
    target = PorticoLiveTvFindProgram(controller.guide.channels, programId)
    if target = invalid then return
    controller.selectedProgramId = programId
    controller.guide.selectedProgram = target
    PorticoLiveTvAttachSelectedChannel(target, controller.guide.channels)
end sub

sub PorticoLiveTvSelectLibraryChannel(controller as object)
    if controller.libraryChannels = invalid then return
    controller.libraryChannels.selectedChannel = invalid
    for each channel in controller.libraryChannels.channels
        if channel.id = controller.selectedLibraryChannelId then controller.libraryChannels.selectedChannel = channel
    end for
end sub

sub PorticoLiveTvRetry(controller as object)
    if controller.serverStatus <> "online"
        PorticoLiveTvRestoreCached(controller)
    else if controller.sources.Count() = 0
        PorticoLiveTvBootstrap(controller)
    else if controller.selectedTab = "library-channels"
        PorticoLiveTvLoadLibraryChannels(controller, "")
    else if controller.selectedTab = "dvr"
        PorticoLiveTvLoadDvr(controller, "", "", "")
    else if controller.selectedTab = "channels"
        PorticoLiveTvLoadChannels(controller, "")
    else
        PorticoLiveTvLoadGuide(controller, "")
    end if
end sub

sub PorticoLiveTvFail(controller as object, result as dynamic, fallbackId as string, variables as object)
    reconnect = false
    if result <> invalid and result.status = 401
        reconnect = controller.reconnectRequestedGeneration <> controller.viewerGeneration
        controller.reconnectRequestedGeneration = controller.viewerGeneration
    end if
    if controller.guide <> invalid or controller.channelPageModel <> invalid or controller.libraryChannels <> invalid or controller.dvr <> invalid
        controller.status = "stale"
        controller.cacheState = "stale"
    else
        controller.status = "error"
    end if
    controller.message = PorticoChannelsFailureCopy(controller, result, fallbackId, variables)
    controller.quietRefresh = false
    PorticoLiveTvPublish(controller, reconnect)
end sub

sub PorticoLiveTvRestoreCached(controller as object)
    cached = PorticoChannelsCacheRead(controller, "channels-workspace", {})
    if cached <> invalid
        controller.sources = cached.sources
        controller.selectedSourceId = PorticoViewerScopeOpaqueId(cached.selectedSourceId, 128)
        controller.selectedTab = PorticoCoreSafeIdentifier(cached.selectedTab, 40)
        controller.guide = cached.guide
        controller.channelPageModel = cached.channelPageModel
        controller.libraryChannels = cached.libraryChannels
        controller.dvr = cached.dvr
        controller.dvrAuthorized = cached.dvrAuthorized = true
        controller.dayOffset = PorticoHttpInteger(cached.dayOffset, 0)
        controller.windowOffsetMinutes = PorticoHttpInteger(cached.windowOffsetMinutes, 0)
        controller.guideFilter = PorticoCoreSafeIdentifier(cached.guideFilter, 24)
        controller.guideGroup = PorticoCoreSafeText(cached.guideGroup, 80)
        controller.guideQuery = PorticoCoreSafeText(cached.guideQuery, 120)
        controller.status = "stale"
        controller.cacheState = "offline"
        controller.message = PorticoChannelsCopy(controller, "live-tv.offline", "live-tv.offline", {})
    else
        controller.status = "offline"
        controller.cacheState = "none"
        controller.message = PorticoChannelsCopy(controller, "live-tv.offline", "live-tv.offline", {})
    end if
    PorticoLiveTvPublish(controller, false)
end sub

sub PorticoLiveTvCacheWorkspace(controller as object)
    PorticoChannelsCacheCommit(controller, "channels-workspace", {}, {
        sources: controller.sources,
        selectedSourceId: controller.selectedSourceId,
        selectedTab: controller.selectedTab,
        guide: controller.guide,
        channelPageModel: controller.channelPageModel,
        libraryChannels: controller.libraryChannels,
        dvr: controller.dvr,
        dvrAuthorized: controller.dvrAuthorized,
        dayOffset: controller.dayOffset,
        windowOffsetMinutes: controller.windowOffsetMinutes,
        guideFilter: controller.guideFilter,
        guideGroup: controller.guideGroup,
        guideQuery: controller.guideQuery
    })
end sub

sub PorticoLiveTvMaterializeArtwork(controller as object, jobs as object)
    session = PorticoChannelsSession(controller, true)
    if session = invalid or jobs.Count() = 0 then return
    visible = []
    for each job in jobs
        if visible.Count() >= 16 then exit for
        visible.Push(job)
    end for
    PorticoBrowseMaterializeArtwork(controller, session, "channels", visible)
    PorticoLiveTvPublish(controller, false)
end sub

sub PorticoLiveTvPublish(controller as object, reconnectRequired as boolean)
    view = PorticoLiveTvProjection(controller)
    projection = {channelsViewState: view, channelsServerReconnectRequired: reconnectRequired}
    if controller.envelopeMode
        envelope = PorticoChannelsResultEnvelope(controller, projection)
        if envelope <> invalid then m.top.projectionEnvelope = envelope
    else
        m.top.projection = projection
    end if
end sub

function PorticoLiveTvProjection(controller as object) as object
    tabs = []
    if controller.selectedSourceId <> ""
        tabs.Push({id: "guide", label: "Guide", selected: controller.selectedTab = "guide"})
        tabs.Push({id: "channels", label: "Channels", selected: controller.selectedTab = "channels"})
        if controller.dvrAuthorized then tabs.Push({id: "dvr", label: "DVR", selected: controller.selectedTab = "dvr"})
    end if
    if PorticoChannelsOperationAvailable(controller, "getLibraryChannelsGuide") then tabs.Push({id: "library-channels", label: "Library Channels", selected: controller.selectedTab = "library-channels"})
    sourceName = ""
    for each source in controller.sources
        source.selected = source.id = controller.selectedSourceId
        if source.selected then sourceName = source.name
    end for
    view = {
        status: controller.status,
        serverStatus: controller.serverStatus,
        serverName: controller.serverName,
        cacheState: controller.cacheState,
        sources: controller.sources,
        sourceSelectionRequired: controller.sourceSelectionRequired,
        selectedSourceId: controller.selectedSourceId,
        sourceName: sourceName,
        selectedTab: controller.selectedTab,
        tabs: tabs,
        dayOffset: controller.dayOffset,
        dayOptions: PorticoLiveTvDayOptions(controller.dayOffset),
        windowOffsetMinutes: controller.windowOffsetMinutes,
        guideFilter: controller.guideFilter,
        guideFilters: PorticoLiveTvFilterOptions(controller.guideFilter),
        guideGroup: controller.guideGroup,
        guideQuery: controller.guideQuery,
        mutationMessage: controller.mutationMessage,
        message: controller.message,
        dvrAuthorized: controller.dvrAuthorized
    }
    if controller.selectedTab = "library-channels" and controller.libraryChannels <> invalid
        total = controller.libraryChannels.channels.Count()
        view.channels = PorticoLiveTvSlice(controller.libraryChannels.channels, controller.libraryPage * 5, 5)
        view.libraryChannels = true
        view.selectedLibraryChannel = controller.libraryChannels.selectedChannel
        view.serverNowEpoch = PorticoLiveTvServerNow(controller.serverClock)
        view.timelineStartEpoch = controller.libraryChannels.timelineStartEpoch
        view.timelineEndEpoch = controller.libraryChannels.timelineEndEpoch
        view.pageIndex = controller.libraryPage
        view.pageSize = 5
        view.totalItems = total
        view.hasMore = controller.libraryChannels.pageInfo.hasMore
    else if controller.selectedTab = "dvr" and controller.dvr <> invalid
        total = controller.dvr.recordings.Count()
        view.recordings = PorticoLiveTvSlice(controller.dvr.recordings, controller.dvrPage * 4, 4)
        view.rules = controller.dvr.rules
        view.schedule = controller.dvr.schedule
        view.conflicts = PorticoLiveTvConflictCopy(controller, controller.dvr.conflicts)
        view.dvrCapabilities = controller.dvr.capabilities
        view.dvrStatusSummary = PorticoLiveTvDvrSummary(controller, controller.dvr)
        view.pageIndex = controller.dvrPage
        view.pageSize = 4
        view.totalItems = total
        view.hasMore = controller.dvr.recordingPageInfo.hasMore
        view.dvrHasMore = {recordings: controller.dvr.recordingPageInfo.hasMore, rules: controller.dvr.rulesPageInfo.hasMore, schedule: controller.dvr.schedulePageInfo.hasMore}
        view.dvrCounts = {recordings: controller.dvr.recordings.count(), rules: controller.dvr.rules.count(), schedule: controller.dvr.schedule.count(), conflicts: controller.dvr.conflicts.count()}
        view.dvrCollectionState = controller.dvrCollectionState
    else if controller.selectedTab = "channels" and controller.channelPageModel <> invalid
        total = controller.channelPageModel.channels.Count()
        view.channels = PorticoLiveTvSlice(controller.channelPageModel.channels, controller.channelPage * 8, 8)
        view.guideGroups = PorticoLiveTvGuideGroupOptions(controller)
        view.pageIndex = controller.channelPage
        view.pageSize = 8
        view.totalItems = total
        view.hasMore = controller.channelPageModel.pageInfo.hasMore
    else if controller.guide <> invalid
        nowEpoch = PorticoLiveTvServerNow(controller.serverClock)
        PorticoLiveTvRefreshProgramLiveState(controller.guide.channels, nowEpoch)
        if controller.guide.selectedProgram <> invalid then controller.guide.selectedProgram.live = controller.guide.selectedProgram.startEpoch <= nowEpoch and controller.guide.selectedProgram.endEpoch > nowEpoch
        total = controller.guide.channels.Count()
        view.channels = PorticoLiveTvSlice(controller.guide.channels, controller.channelPage * 5, 5)
        view.selectedProgram = controller.guide.selectedProgram
        view.capabilities = controller.guide.capabilities
        view.guideGroups = PorticoLiveTvGuideGroupOptions(controller)
        view.serverNowEpoch = nowEpoch
        view.timelineStartEpoch = controller.guide.timelineStartEpoch
        view.timelineEndEpoch = controller.guide.timelineEndEpoch
        view.timelineLabels = PorticoLiveTvTimelineLabels(controller.guide.timelineStartEpoch, controller.windowSeconds)
        view.nowMarkerRatio = PorticoLiveTvNowRatio(nowEpoch, controller.guide.timelineStartEpoch, controller.windowSeconds)
        view.pageIndex = controller.channelPage
        view.pageSize = 5
        view.totalItems = total
        view.hasMore = controller.guide.pageInfo.hasMore
    end if
    return view
end function

function PorticoLiveTvGuideWindowStart(controller as object) as longinteger
    nowEpoch = PorticoLiveTvServerNow(controller.serverClock)
    if nowEpoch < 1
        clock = CreateObject("roDateTime")
        if clock <> invalid then nowEpoch = clock.AsSeconds()
    end if
    dayStart = PorticoLiveTvDayStartEpoch(nowEpoch, controller.dayOffset)
    if controller.dayOffset = 0 and controller.windowOffsetMinutes = 0
        rounded = Int(nowEpoch / 1800) * 1800
        if rounded > dayStart then return rounded
    end if
    return dayStart + (controller.windowOffsetMinutes * 60)
end function

function PorticoLiveTvLibraryDayStart(controller as object) as longinteger
    nowEpoch = PorticoLiveTvServerNow(controller.serverClock)
    if nowEpoch < 1
        clock = CreateObject("roDateTime")
        if clock <> invalid then nowEpoch = clock.AsSeconds()
    end if
    return PorticoLiveTvDayStartEpoch(nowEpoch, controller.dayOffset)
end function

function PorticoLiveTvFindProgram(channels as object, programId as string) as dynamic
    if programId = "" then return invalid
    for each channel in channels
        for each program in channel.programs
            if program.id = programId then return program
        end for
    end for
    return invalid
end function

function PorticoLiveTvFindRule(controller as object, rawId as dynamic) as dynamic
    if controller.dvr = invalid then return invalid
    id = PorticoViewerScopeOpaqueId(rawId, 128)
    for each rule in controller.dvr.rules
        if rule.id = id then return rule
    end for
    return invalid
end function

function PorticoLiveTvFindRecording(controller as object, rawId as dynamic) as dynamic
    if controller.dvr = invalid then return invalid
    id = PorticoViewerScopeOpaqueId(rawId, 128)
    for each recording in controller.dvr.recordings
        if recording.id = id then return recording
    end for
    return invalid
end function

sub PorticoLiveTvAppendGuide(target as object, page as object)
    PorticoLiveTvAppendChannels(target.channels, page.channels)
    target.pageInfo = page.pageInfo
    target.channelGroups = page.channelGroups
    target.serverNowEpoch = page.serverNowEpoch
end sub

sub PorticoLiveTvAppendChannels(target as object, source as object)
    seen = {}
    for each existing in target
        seen[existing.id] = true
    end for
    for each item in source
        if target.Count() >= 250 then exit for
        if seen[item.id] <> true
            seen[item.id] = true
            target.Push(item)
        end if
    end for
end sub

sub PorticoLiveTvAppendLibraryPrograms(targetChannels as object, sourceChannels as object)
    byId = {}
    for each channel in targetChannels
        byId[channel.id] = channel
    end for
    for each incoming in sourceChannels
        target = byId[incoming.id]
        if target <> invalid then PorticoLiveTvAppendPrograms(target.programs, incoming.programs)
    end for
end sub

sub PorticoLiveTvAppendPrograms(target as object, source as object)
    seen = {}
    for each existing in target
        seen[existing.id] = true
    end for
    for each item in source
        if target.Count() >= 64 then exit for
        if seen[item.id] <> true
            seen[item.id] = true
            target.Push(item)
        end if
    end for
end sub

sub PorticoLiveTvAppendRecordings(target as object, source as object)
    PorticoLiveTvAppendChannels(target, source)
end sub

sub PorticoLiveTvAppendRules(target as object, source as object)
    PorticoLiveTvAppendChannels(target, source)
end sub

sub PorticoLiveTvRefreshProgramLiveState(channels as object, nowEpoch as longinteger)
    for each channel in channels
        for each program in channel.programs
            program.live = program.startEpoch <= nowEpoch and program.endEpoch > nowEpoch
        end for
    end for
end sub

function PorticoLiveTvConflictCopy(controller as object, conflicts as object) as object
    result = []
    for each conflict in conflicts
        copy = PorticoChannelsCopy(controller, conflict.messageId, "dvr.conflict", {demand: conflict.demand.ToStr(), capacity: conflict.capacity.ToStr()})
        result.Push({id: conflict.id, title: copy.title, body: copy.body, demand: conflict.demand, capacity: conflict.capacity, startsAt: conflict.startsAt, endsAt: conflict.endsAt, actions: conflict.actions})
    end for
    return result
end function

function PorticoLiveTvDvrSummary(controller as object, dvr as object) as string
    if dvr.conflicts.Count() > 0 then return dvr.conflicts.Count().ToStr() + " recording conflicts"
    if dvr.capabilities.canScheduleRecordings or PorticoLiveTvHasAction(dvr.capabilities.actions, "dvr.rule.create") then return "DVR ready"
    return "Recordings available"
end function

function PorticoLiveTvDayOptions(selected as integer) as object
    result = []
    labels = ["Today", "Tomorrow", "Day 3", "Day 4", "Day 5", "Day 6", "Day 7"]
    for index = 0 to labels.Count() - 1
        result.Push({id: index.ToStr(), label: labels[index], selected: index = selected})
    end for
    return result
end function

function PorticoLiveTvFilterOptions(selected as string) as object
    result = []
    values = [{id: "all", label: "All"}, {id: "favorites", label: "Favorites"}, {id: "sports", label: "Sports"}, {id: "news", label: "News"}, {id: "movies", label: "Movies"}]
    for each value in values
        value.selected = value.id = selected
        result.Push(value)
    end for
    return result
end function

function PorticoLiveTvGuideGroupOptions(controller as object) as object
    result = [{id: "", label: "All groups", selected: controller.guideGroup = ""}]
    if controller.guide <> invalid
        for each group in controller.guide.channelGroups
            result.Push({id: group, label: group, selected: controller.guideGroup = group})
        end for
    end if
    return result
end function

function PorticoLiveTvTimelineLabels(startEpoch as longinteger, windowSeconds as integer) as object
    result = []
    tickSeconds = Int(windowSeconds / 3)
    for index = 0 to 3
        text = PorticoLiveTvIso(startEpoch + (index * tickSeconds))
        label = ""
        if Len(text) >= 16 then label = Mid(text, 12, 5)
        result.Push(label)
    end for
    return result
end function

function PorticoLiveTvNowRatio(nowEpoch as longinteger, startEpoch as longinteger, windowSeconds as integer) as double
    if windowSeconds < 1 or nowEpoch < startEpoch or nowEpoch > startEpoch + windowSeconds then return -1.0
    return (nowEpoch - startEpoch) / windowSeconds
end function

function PorticoLiveTvSlice(source as dynamic, startIndex as integer, pageSize as integer) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid or pageSize < 1 then return result
    if startIndex < 0 then startIndex = 0
    lastIndex = startIndex + pageSize - 1
    if lastIndex >= source.Count() then lastIndex = source.Count() - 1
    if startIndex > lastIndex then return result
    for index = startIndex to lastIndex
        result.Push(source[index])
    end for
    return result
end function
