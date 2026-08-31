sub init()
    m.top.functionName = "PorticoContentRun"
end sub

sub PorticoContentRun()
    controller = {
        lastCommandSequence: 0,
        serverStatus: "not-connected",
        serverId: "",
        sessionGeneration: 0,
        cacheBinding: "",
        reconnectRequestedGeneration: -1,
        homeStatus: "idle",
        homeModel: invalid,
        cachedHomeModel: invalid,
        homeLoadRequested: false,
        detailStatus: "idle",
        detailMediaId: "",
        detailModel: invalid,
        cachedDetailId: "",
        cachedDetailModel: invalid,
        detailLoadRequested: false,
        requestedSeasonId: "",
        requestedEpisodeId: "",
        selectedSeasonId: "",
        episodeLoadRequested: false,
        episodeAppendRequested: false,
        episodeCursorHistory: {},
        productContract: invalid,
        productContractStatus: "idle",
        generatedProductContract: invalid,
        productLanguage: invalid,
        selectedPersonId: "",
        selectedPersonName: "",
        personStatus: "idle",
        personResults: [],
        personModel: invalid,
        personCursorHistory: {},
        personLoadRequested: false,
        homeRowLoadId: "",
        homeRowHydrationQueue: [],
        homeRowCursorHistory: {},
        homeRowOrder: [],
        hiddenHomeRowIds: [],
        targetKind: "",
        targetsStatus: "idle",
        targets: [],
        moreActionStatus: "idle",
        moreActionMessage: "",
        activeQueueSessionId: "",
        activeQueueRevision: 0,
        savedResourcesRevision: 0,
        contentInvalidations: [],
        nonInterruptibleRequest: false,
        artworkAccess: {},
        artworkAccessCounter: 0
    }
    PorticoDiscoveryTaskAdopt(controller, PorticoDiscoveryTaskState("content"))
    generated = PorticoProductContractLoad()
    if generated.ok then controller.generatedProductContract = generated.value
    language = PorticoProductLanguageLoad()
    if language.ok then controller.productLanguage = language.value
    PorticoContentPrepareArtworkDirectory()
    PorticoContentTrimArtwork(controller, "")
    PorticoContentPublish(controller, false)
    while true
        PorticoContentHandleCommand(controller)
        PorticoContentTick(controller)
        Sleep(250)
    end while
end sub

sub PorticoContentHandleCommand(controller as object)
    command = invalid
    envelope = m.top.commandEnvelope
    if envelope <> invalid and Type(envelope) = "roAssociativeArray"
        previousGeneration = controller.viewerGeneration
        command = PorticoDiscoveryAcceptCommand(controller, envelope, "content")
        if command <> invalid and previousGeneration <> controller.viewerGeneration
            ' Artwork files are server/resource/version scoped and are only
            ' attached to a newly authorized response model. Keep the bounded
            ' cache across viewer generations to avoid a cold-image storm.
            PorticoContentResetRuntime(controller)
        end if
    end if
    if command = invalid
        if controller.envelopeMode then return
        command = m.top.command
    end if
    if command = invalid or Type(command) <> "roAssociativeArray" then return
    sequence = PorticoHttpInteger(command.sequence, 0)
    if sequence <= controller.lastCommandSequence then return
    controller.lastCommandSequence = sequence
    kind = PorticoHttpScalarString(command.kind, "")
    controller.contentInvalidations = []

    if kind = "server-state"
        PorticoContentApplyServerState(controller, command)
    else if kind = "refresh-home"
        if controller.serverId <> ""
            controller.homeLoadRequested = true
            if controller.homeModel = invalid then controller.homeStatus = "loading" else controller.homeStatus = "refreshing"
            PorticoContentPublish(controller, false)
        end if
    else if kind = "refresh-content"
        if controller.serverId <> ""
            if command.refreshHome = true
                controller.homeLoadRequested = true
                if controller.homeModel = invalid then controller.homeStatus = "loading" else controller.homeStatus = "refreshing"
            end if
            detailId = PorticoViewerScopeOpaqueId(command.detailMediaId, 128)
            if detailId <> "" then PorticoContentRequestDetail(controller, detailId)
            PorticoContentPublish(controller, false)
        end if
    else if kind = "quiet-refresh-content"
        ' Keep the current projection and its ready/stale status visible. Only
        ' the completed authoritative replacement is published.
        if controller.serverId <> ""
            if command.refreshHome = true then controller.homeLoadRequested = true
            detailId = PorticoViewerScopeOpaqueId(command.detailMediaId, 128)
            if detailId <> "" and detailId = controller.detailMediaId then controller.detailLoadRequested = true
        end if
    else if kind = "open-detail"
        PorticoContentRequestDetail(controller, command.mediaId, command.seasonId, command.episodeId)
    else if kind = "select-detail-season"
        PorticoContentSelectSeason(controller, command.seasonId)
    else if kind = "load-more-detail-episodes"
        if controller.detailModel <> invalid and controller.detailModel.episodesHasMore = true and controller.serverStatus = "online"
            controller.episodeAppendRequested = true
            controller.episodeLoadRequested = true
            controller.detailModel.episodesStatus = "refreshing"
            PorticoContentPublish(controller, false)
        end if
    else if kind = "retry-detail-episodes"
        if controller.selectedSeasonId <> "" and controller.serverStatus = "online"
            controller.episodeAppendRequested = controller.detailModel <> invalid and controller.detailModel.episodes.count() > 0
            controller.episodeLoadRequested = true
            if controller.detailModel <> invalid then controller.detailModel.episodesStatus = "loading"
            PorticoContentPublish(controller, false)
        end if
    else if kind = "select-person"
        PorticoContentRequestPerson(controller, command.personId, command.personName)
    else if kind = "retry-person"
        if controller.selectedPersonId <> "" and controller.serverStatus = "online"
            controller.personStatus = "loading"
            controller.personLoadRequested = true
            PorticoContentPublish(controller, false)
        end if
    else if kind = "load-more-person"
        if controller.personModel <> invalid and controller.personModel.hasMore = true and controller.serverStatus = "online"
            controller.personStatus = "refreshing"
            controller.personLoadRequested = true
            PorticoContentPublish(controller, false)
        end if
    else if kind = "load-more-home-row"
        rowId = PorticoContentSafeId(command.rowId)
        row = PorticoContentFindHomeRow(controller.homeModel, rowId)
        if row <> invalid and row.hasMore = true and row.nextCursor <> "" and controller.serverStatus = "online"
            controller.homeRowLoadId = rowId
            PorticoContentPublish(controller, false)
        end if
    else if kind = "viewer-preferences"
        PorticoContentApplyViewerPreferences(controller, command)
    else if kind = "open-detail-targets"
        PorticoContentLoadTargets(controller, command.targetKind)
    else if kind = "add-detail-target"
        PorticoContentAddToTarget(controller, command.targetKind, command.savedTargetId)
    else if kind = "create-detail-target"
        PorticoContentCreateTarget(controller, command.targetKind, command.title)
    else if kind = "set-detail-rating"
        PorticoContentSetRating(controller, command.rating)
    else if kind = "set-detail-reaction"
        PorticoContentSetReaction(controller, command.reaction)
    else if kind = "detail-queue"
        PorticoContentMutateQueue(controller, command.position)
    else if kind = "sync-media-state"
        PorticoContentSynchronizeMediaState(controller, command.mediaId, command.family, command.value = true)
    else if kind = "invalidate-playback-state"
        PorticoContentInvalidatePlaybackState(controller)
    end if
end sub

sub PorticoContentApplyViewerPreferences(controller as object, command as object)
    controller.homeRowOrder = PorticoContentSafeIdArray(command.homeRowOrder, 64)
    controller.hiddenHomeRowIds = PorticoContentSafeIdArray(command.hiddenHomeRowIds, 64)
    if controller.homeModel <> invalid then PorticoContentPublish(controller, false)
end sub

function PorticoContentSafeIdArray(source as dynamic, maximum as integer) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= maximum then exit for
        value = PorticoContentSafeId(raw)
        if value <> "" and not PorticoContentArrayContainsText(result, value) then result.push(value)
    end for
    return result
end function

function PorticoContentArrayContainsText(values as object, expected as string) as boolean
    for each value in values
        if value = expected then return true
    end for
    return false
end function

sub PorticoContentInvalidatePlaybackState(controller as object)
    PorticoDiscoveryCacheRemoveViewer("content-cache", controller)
    if controller.serverStatus <> "online" then return
    controller.homeLoadRequested = true
    if controller.homeModel = invalid then controller.homeStatus = "loading" else controller.homeStatus = "refreshing"
    if controller.detailMediaId <> ""
        controller.detailLoadRequested = true
        if controller.detailModel = invalid then controller.detailStatus = "loading" else controller.detailStatus = "refreshing"
    end if
    PorticoContentPublish(controller, false)
end sub

sub PorticoContentSynchronizeMediaState(controller as object, rawMediaId as dynamic, rawFamily as dynamic, value as boolean)
    mediaId = PorticoContentSafeId(rawMediaId)
    family = LCase(PorticoContentSafeText(rawFamily, 16))
    if mediaId = "" or (family <> "watchlist" and family <> "favorite" and family <> "watched") then return
    PorticoContentPatchMediaState(controller.homeModel, mediaId, family, value, 0)
    PorticoContentPatchMediaState(controller.cachedHomeModel, mediaId, family, value, 0)
    PorticoContentPatchMediaState(controller.detailModel, mediaId, family, value, 0)
    PorticoContentPatchMediaState(controller.cachedDetailModel, mediaId, family, value, 0)
    PorticoContentPersistCache(controller)
    PorticoContentPublish(controller, false)
end sub

sub PorticoContentPatchMediaState(target as dynamic, mediaId as string, family as string, value as boolean, depth as integer)
    if target = invalid or depth > 10 then return
    if Type(target) = "roAssociativeArray"
        if PorticoContentSafeId(target.id) = mediaId
            if family = "watchlist" then target.watchlisted = value
            if family = "favorite" then target.favorite = value
            if family = "watched" then target.watched = value
            if target.state <> invalid and Type(target.state) = "roAssociativeArray"
                if family = "watchlist" then target.state.watchlisted = value
                if family = "favorite" then target.state.favorite = value
                if family = "watched" then target.state.watched = value
            end if
            if target.actions <> invalid
                supportsFamily = PorticoContentHasActionFamily(target.actions, family)
                if family = "watched" then supportsFamily = PorticoContentHasAction(target.actions, "watched.set")
                if supportsFamily then target.actions = PorticoContentActionsAfterState(target.actions, family, value)
            end if
        end if
        for each key in target
            PorticoContentPatchMediaState(target[key], mediaId, family, value, depth + 1)
        end for
    else if GetInterface(target, "ifArray") <> invalid
        for each item in target
            PorticoContentPatchMediaState(item, mediaId, family, value, depth + 1)
        end for
    end if
end sub

function PorticoContentActionsAfterState(source as dynamic, family as string, value as boolean) as object
    result = []
    if source <> invalid and GetInterface(source, "ifArray") <> invalid
        for each rawAction in source
            action = LCase(PorticoContentSafeText(rawAction, 48))
            if Left(action, Len(family) + 1) <> family + "." then result.push(action)
        end for
    end if
    if family = "watched"
        result.push("watched.set")
    else
        suffix = "add"
        if value then suffix = "remove"
        result.push(family + "." + suffix)
    end if
    return PorticoContentSafeActions(result)
end function

sub PorticoContentApplyServerState(controller as object, command as object)
    controller.homeRowOrder = PorticoContentSafeIdArray(command.homeRowOrder, 64)
    controller.hiddenHomeRowIds = PorticoContentSafeIdArray(command.hiddenHomeRowIds, 64)
    serverId = PorticoContentSafeId(command.selectedServerId)
    status = LCase(PorticoHttpScalarString(command.serverStatus, "not-connected"))
    allowed = { online: true, connecting: true, offline: true, blocked: true, "identity-mismatch": true, incompatible: true, "permission-removed": true, selected: true, "not-connected": true }
    if allowed[status] <> true then status = "not-connected"
    selectionChanged = serverId <> controller.serverId
    statusChanged = status <> controller.serverStatus
    if not selectionChanged and not statusChanged then return

    if selectionChanged
        ' Server ID participates in every cache key, so a server transition does
        ' not require destructive cache clearing. Incremental LRU pruning keeps
        ' disk use bounded without forcing the next screen to redownload art.
        PorticoContentResetRuntime(controller)
        controller.serverId = serverId
        controller.reconnectRequestedGeneration = -1
    end if
    controller.serverStatus = status

    if serverId <> "" and controller.homeModel = invalid then PorticoContentRestoreCache(controller)

    if serverId = "" or status = "not-connected"
        PorticoDiscoveryCacheRemoveViewer("content-cache", controller)
        PorticoContentResetRuntime(controller)
        controller.serverId = ""
    else if status = "online"
        controller.homeLoadRequested = true
        if controller.homeModel = invalid then controller.homeStatus = "loading" else controller.homeStatus = "refreshing"
        if controller.detailMediaId <> "" then controller.detailLoadRequested = true
    else if status = "permission-removed" or status = "identity-mismatch" or status = "incompatible"
        PorticoDiscoveryCacheRemoveViewer("content-cache", controller)
        controller.homeModel = invalid
        controller.cachedHomeModel = invalid
        controller.detailModel = invalid
        controller.cachedDetailModel = invalid
        controller.homeStatus = "unavailable"
        controller.detailStatus = "unavailable"
        controller.homeLoadRequested = false
        controller.detailLoadRequested = false
    else
        if controller.homeModel <> invalid then controller.homeStatus = "stale" else controller.homeStatus = "offline"
        if controller.detailModel <> invalid then controller.detailStatus = "stale" else if controller.detailMediaId <> "" then controller.detailStatus = "offline"
    end if
    PorticoContentPublish(controller, false)
end sub

sub PorticoContentRequestDetail(controller as object, rawMediaId as dynamic, rawSeasonId = invalid as dynamic, rawEpisodeId = invalid as dynamic)
    mediaId = PorticoContentSafeId(rawMediaId)
    if mediaId = "" or controller.serverId = "" then return
    changed = mediaId <> controller.detailMediaId
    controller.detailMediaId = mediaId
    controller.requestedSeasonId = PorticoContentSafeId(rawSeasonId)
    controller.requestedEpisodeId = PorticoContentSafeId(rawEpisodeId)
    if changed
        controller.detailModel = invalid
        PorticoContentResetPerson(controller)
        PorticoContentResetDetailActions(controller)
        if controller.cachedDetailId = mediaId and controller.cachedDetailModel <> invalid then controller.detailModel = PorticoContentClone(controller.cachedDetailModel)
    end if
    if controller.serverStatus = "online"
        controller.detailLoadRequested = true
        if controller.detailModel = invalid then controller.detailStatus = "loading" else controller.detailStatus = "refreshing"
    else if controller.detailModel <> invalid
        controller.detailStatus = "stale"
    else
        controller.detailStatus = "offline"
    end if
    PorticoContentPublish(controller, false)
end sub

sub PorticoContentSelectSeason(controller as object, rawSeasonId as dynamic)
    if controller.detailModel = invalid or controller.detailModel.seasons = invalid or GetInterface(controller.detailModel.seasons, "ifArray") = invalid then return
    seasonId = PorticoContentSafeId(rawSeasonId)
    found = false
    for each season in controller.detailModel.seasons
        if season.id = seasonId then found = true
    end for
    if not found or seasonId = controller.selectedSeasonId then return
    controller.selectedSeasonId = seasonId
    controller.requestedEpisodeId = ""
    controller.detailModel.selectedSeasonId = seasonId
    controller.detailModel.episodes = []
    controller.detailModel.episodesStatus = "loading"
    controller.detailModel.episodesHasMore = false
    controller.detailModel.episodesNextCursor = ""
    controller.episodeCursorHistory = {}
    controller.episodeAppendRequested = false
    controller.episodeLoadRequested = controller.serverStatus = "online"
    PorticoContentPublish(controller, false)
end sub

sub PorticoContentRequestPerson(controller as object, rawId as dynamic, rawName as dynamic)
    personId = PorticoContentSafeId(rawId)
    personName = PorticoContentSafeText(rawName, 100)
    if personId = "" then return
    controller.selectedPersonId = personId
    controller.selectedPersonName = personName
    controller.personResults = []
    controller.personModel = invalid
    controller.personCursorHistory = {}
    if controller.serverStatus = "online"
        controller.personStatus = "loading"
        controller.personLoadRequested = true
    else
        controller.personStatus = "offline"
        controller.personLoadRequested = false
    end if
    PorticoContentPublish(controller, false)
end sub

sub PorticoContentResetPerson(controller as object)
    controller.selectedPersonId = ""
    controller.selectedPersonName = ""
    controller.personStatus = "idle"
    controller.personResults = []
    controller.personModel = invalid
    controller.personCursorHistory = {}
    controller.personLoadRequested = false
end sub

sub PorticoContentResetDetailActions(controller as object)
    controller.targetKind = ""
    controller.targetsStatus = "idle"
    controller.targets = []
    controller.moreActionStatus = "idle"
    controller.moreActionMessage = ""
    controller.activeQueueSessionId = ""
    controller.activeQueueRevision = 0
end sub

sub PorticoContentResetRuntime(controller as object)
    controller.sessionGeneration = 0
    controller.cacheBinding = ""
    controller.homeStatus = "idle"
    controller.homeModel = invalid
    controller.cachedHomeModel = invalid
    controller.homeLoadRequested = false
    controller.detailStatus = "idle"
    controller.detailMediaId = ""
    controller.detailModel = invalid
    controller.cachedDetailId = ""
    controller.cachedDetailModel = invalid
    controller.detailLoadRequested = false
    controller.requestedSeasonId = ""
    controller.requestedEpisodeId = ""
    controller.selectedSeasonId = ""
    controller.episodeLoadRequested = false
    controller.episodeAppendRequested = false
    controller.episodeCursorHistory = {}
    controller.productContract = invalid
    controller.productContractStatus = "idle"
    PorticoContentResetPerson(controller)
    controller.homeRowLoadId = ""
    controller.homeRowHydrationQueue = []
    controller.homeRowCursorHistory = {}
    PorticoContentResetDetailActions(controller)
end sub

sub PorticoContentTick(controller as object)
    if controller.serverStatus <> "online" then return
    if controller.detailLoadRequested
        if PorticoContentLoadDetail(controller) then controller.detailLoadRequested = false
        return
    end if
    if controller.episodeLoadRequested
        if PorticoContentLoadEpisodes(controller) then controller.episodeLoadRequested = false
        return
    end if
    if controller.personLoadRequested
        if PorticoContentLoadPerson(controller) then controller.personLoadRequested = false
        return
    end if
    if controller.homeRowLoadId = "" and controller.homeRowHydrationQueue.count() > 0
        controller.homeRowLoadId = controller.homeRowHydrationQueue.shift()
    end if
    if controller.homeRowLoadId <> ""
        if PorticoContentLoadHomeRow(controller, controller.homeRowLoadId) then controller.homeRowLoadId = ""
        return
    end if
    if controller.homeLoadRequested
        if PorticoContentLoadHome(controller) then controller.homeLoadRequested = false
    end if
end sub

function PorticoContentLoadHome(controller as object) as boolean
    session = PorticoContentSessionForController(controller)
    if session = invalid
        PorticoContentHomeFailed(controller, invalid, true)
        return true
    end if
    controller.sessionGeneration = session.generation
    controller.cacheBinding = session.cacheBinding
    result = PorticoContentGet(controller, session, "/api/home")
    if result.interrupted then return false
    if not result.ok
        PorticoContentHomeFailed(controller, result, false)
        return true
    end if
    normalized = PorticoContentHomeFromResponse(result.data)
    if normalized = invalid
        controller.homeStatus = "incompatible"
        PorticoContentPublish(controller, false)
        return true
    end if

    controller.homeModel = normalized.model
    controller.homeRowHydrationQueue = []
    controller.homeRowCursorHistory = {}
    for each row in controller.homeModel.rows
        if row.loadStatus = "loading" then controller.homeRowHydrationQueue.push(row.id)
    end for
    controller.cachedHomeModel = PorticoContentCachedHome(normalized.model)
    controller.homeStatus = "ready"
    controller.reconnectRequestedGeneration = -1
    PorticoContentPersistCache(controller)
    ' Publish descriptors immediately; each row hydrates independently and later
    ' publications preserve already successful rows.
    PorticoContentPublish(controller, false)
    PorticoContentMaterializeArtwork(controller, session, normalized.artworkJobs)
    PorticoContentPublish(controller, false)
    return true
end function

function PorticoContentLoadHomeRow(controller as object, rowId as string) as boolean
    row = PorticoContentFindHomeRow(controller.homeModel, rowId)
    if row = invalid then return true
    initialHydration = row.loadStatus = "loading" and row.items.count() = 0
    if not initialHydration and row.nextCursor = "" then return true
    session = PorticoContentSessionForController(controller)
    if session = invalid
        row.loadStatus = "unavailable"
        row.errorMessageId = "home.row-unavailable"
        PorticoContentPublish(controller, true)
        return true
    end if
    path = "/api/home/rows/" + rowId + "?limit=50"
    if not initialHydration
        rawCursor = PorticoContentSafeCursor(row.nextCursor)
        cursorKey = rowId + "|" + rawCursor
        if rawCursor = "" or controller.homeRowCursorHistory[cursorKey] = true
            row.hasMore = false
            row.nextCursor = ""
            row.loadStatus = "partial"
            row.errorMessageId = "home.row-partial"
            PorticoContentPublish(controller, false)
            return true
        end if
        controller.homeRowCursorHistory[cursorKey] = true
        cursor = PorticoContentUrlEncode(rawCursor)
        if cursor = "" then return true
        path = path + "&cursor=" + cursor
    end if
    result = PorticoContentGet(controller, session, path)
    if result.interrupted then return false
    if not result.ok
        if row.items.count() > 0
            row.loadStatus = "partial"
            row.errorMessageId = "home.row-partial"
        else
            row.loadStatus = "unavailable"
            row.errorMessageId = "home.row-unavailable"
        end if
        PorticoContentPublish(controller, result.status = 401)
        return true
    end if
    artworkJobs = []
    incoming = PorticoContentRowFromResponse(result.data, artworkJobs, 50)
    if incoming = invalid or incoming.id <> rowId
        row.loadStatus = "unavailable"
        row.errorMessageId = "home.row-unavailable"
        PorticoContentPublish(controller, false)
        return true
    end if
    for each item in incoming.items
        if row.items.count() >= 100 then exit for
        if not PorticoContentContainsId(row.items, item.id) then row.items.push(item)
    end for
    row.hasMore = incoming.hasMore
    row.nextCursor = incoming.nextCursor
    row.loadStatus = "ready"
    row.errorMessageId = ""
    if row.items.count() = 0 then row.loadStatus = "empty"
    if PorticoContentIsContinueRow(row)
        controller.homeModel.continueWatching = row.items
    end if
    controller.cachedHomeModel = PorticoContentCachedHome(controller.homeModel)
    PorticoContentPersistCache(controller)
    PorticoContentPublish(controller, false)
    PorticoContentMaterializeArtwork(controller, session, artworkJobs)
    PorticoContentPublish(controller, false)
    return true
end function

function PorticoContentFindHomeRow(home as dynamic, rowId as string) as dynamic
    if home = invalid or Type(home) <> "roAssociativeArray" or home.rows = invalid or GetInterface(home.rows, "ifArray") = invalid then return invalid
    for each row in home.rows
        if row.id = rowId then return row
    end for
    return invalid
end function

function PorticoContentLoadPerson(controller as object) as boolean
    if controller.selectedPersonId = "" then return true
    session = PorticoContentSessionForController(controller)
    if session = invalid
        controller.personStatus = "offline"
        PorticoContentPublish(controller, true)
        return true
    end if
    encodedId = PorticoContentUrlEncode(controller.selectedPersonId)
    if encodedId = ""
        controller.personStatus = "error"
        PorticoContentPublish(controller, false)
        return true
    end if
    path = "/api/people/" + encodedId + "?limit=50"
    append = controller.personModel <> invalid and controller.personStatus = "refreshing" and controller.personModel.nextCursor <> ""
    cursor = ""
    if append
        cursor = PorticoContentSafeCursor(controller.personModel.nextCursor)
        if cursor = "" or controller.personCursorHistory[cursor] = true
            controller.personModel.hasMore = false
            controller.personModel.nextCursor = ""
            controller.personStatus = "ready"
            PorticoContentPublish(controller, false)
            return true
        end if
        controller.personCursorHistory[cursor] = true
        path = path + "&cursor=" + PorticoContentUrlEncode(cursor)
    end if
    result = PorticoContentGet(controller, session, path)
    if result.interrupted then return false
    if not result.ok
        controller.personStatus = "error"
        PorticoContentPublish(controller, result.status = 401)
        return true
    end if
    normalized = PorticoContentPersonDetailFromResponse(result.data)
    if normalized = invalid
        controller.personStatus = "error"
        PorticoContentPublish(controller, false)
        return true
    end if
    if append and controller.personModel <> invalid
        for each item in normalized.model.items
            if not PorticoContentContainsId(controller.personModel.items, item.id) then controller.personModel.items.push(item)
        end for
        controller.personModel.hasMore = normalized.model.hasMore
        controller.personModel.nextCursor = normalized.model.nextCursor
    else
        controller.personModel = normalized.model
        if normalized.imageSource <> "" then normalized.artworkJobs.push({target: controller.personModel, field: "image", source: normalized.imageSource, key: controller.selectedPersonId + "-person", width: 240, height: 240})
    end if
    controller.selectedPersonName = controller.personModel.name
    controller.personResults = controller.personModel.items
    if controller.personResults.count() > 0 then controller.personStatus = "ready" else controller.personStatus = "empty"
    PorticoContentPublish(controller, false)
    PorticoContentMaterializeArtwork(controller, session, normalized.artworkJobs)
    PorticoContentPublish(controller, false)
    return true
end function

function PorticoContentUrlEncode(value as string) as string
    if Len(value) < 1 or Len(value) > 512 then return ""
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return ""
    return transfer.Escape(value)
end function

function PorticoContentLoadDetail(controller as object) as boolean
    mediaId = controller.detailMediaId
    if mediaId = "" then return true
    session = PorticoContentSessionForController(controller)
    if session = invalid
        PorticoContentDetailFailed(controller, invalid, true)
        return true
    end if
    controller.sessionGeneration = session.generation
    controller.cacheBinding = session.cacheBinding
    if not PorticoContentEnsureProductContract(controller, session) then return false
    result = PorticoContentGet(controller, session, "/api/media/" + mediaId + "?includeRecommendations=true")
    if result.interrupted then return false
    if not result.ok
        PorticoContentDetailFailed(controller, result, false)
        return true
    end if
    normalized = PorticoContentDetailFromResponse(result.data)
    if normalized = invalid or normalized.model.id <> mediaId
        controller.detailStatus = "incompatible"
        PorticoContentPublish(controller, false)
        return true
    end if

    controller.detailModel = normalized.model
    PorticoContentApplyContractActions(controller.detailModel, controller.generatedProductContract, controller.productContract, controller.productLanguage)
    controller.selectedSeasonId = PorticoContentSelectInitialSeason(controller.detailModel.seasons, controller.requestedSeasonId, controller.detailModel.selectedSeasonId)
    controller.detailModel.selectedSeasonId = controller.selectedSeasonId
    controller.episodeCursorHistory = {}
    controller.episodeAppendRequested = false
    controller.episodeLoadRequested = controller.selectedSeasonId <> ""
    if controller.episodeLoadRequested then controller.detailModel.episodesStatus = "loading" else if controller.detailModel.episodes.count() > 0 then controller.detailModel.episodesStatus = "ready" else controller.detailModel.episodesStatus = "empty"
    PorticoContentRefreshQueueAvailability(controller, session)
    controller.cachedDetailId = mediaId
    controller.cachedDetailModel = PorticoContentCachedDetail(normalized.model)
    controller.detailStatus = "ready"
    controller.reconnectRequestedGeneration = -1
    PorticoContentPersistCache(controller)
    PorticoContentPublish(controller, false)
    PorticoContentMaterializeArtwork(controller, session, normalized.artworkJobs)
    PorticoContentPublish(controller, false)
    return true
end function

function PorticoContentEnsureProductContract(controller as object, session as object) as boolean
    if controller.productContractStatus = "ready" then return true
    controller.productContractStatus = "loading"
    result = PorticoContentGet(controller, session, "/api/product-contract")
    if result.interrupted
        controller.productContractStatus = "idle"
        return false
    end if
    if result.ok and PorticoProductContractValidateLive(result.data).ok
        controller.productContract = result.data
        controller.productContractStatus = "ready"
    else
        controller.productContract = invalid
        controller.productContractStatus = "error"
        if result.status = 401 then PorticoContentPublish(controller, true)
    end if
    return true
end function

sub PorticoContentApplyContractActions(model as object, generated as dynamic, liveContract as dynamic, language as dynamic)
    model.contractActions = []
    if generated = invalid or liveContract = invalid or language = invalid then return
    model.contractActions = PorticoProductContractConsumerActions(generated, liveContract, model.actions, "television", language)
    baseActions = model.uiActions
    model.uiActions = []
    if PorticoContentHasAction(baseActions, "play") then model.uiActions.push("play")
    if PorticoContentContractActionPresent(model.contractActions, "play.from-beginning") then model.uiActions.push("play.from-beginning")
    if PorticoContentHasAction(baseActions, "saved-toggle") then model.uiActions.push("saved-toggle")
    if PorticoContentHasAction(baseActions, "favorite-toggle") then model.uiActions.push("favorite-toggle")
    if PorticoContentHasAction(baseActions, "watched-toggle") then model.uiActions.push("watched-toggle")
    for each action in model.contractActions
        if action.id = "watch-with-friends.start" or action.id = "feedback.report-problem" or action.id = "feedback.request-higher-quality"
            model.uiActions.push(action.id)
        end if
    end for
    if PorticoContentHasAction(baseActions, "more") then model.uiActions.push("more")
end sub

function PorticoContentContractActionPresent(actions as dynamic, expected as string) as boolean
    if actions = invalid or GetInterface(actions, "ifArray") = invalid then return false
    for each action in actions
        if action <> invalid and Type(action) = "roAssociativeArray" and action.id = expected then return true
    end for
    return false
end function

function PorticoContentSelectInitialSeason(seasons as dynamic, requested as dynamic, fallback as dynamic) as string
    if seasons = invalid or GetInterface(seasons, "ifArray") = invalid or seasons.count() = 0 then return ""
    preferred = PorticoContentSafeId(requested)
    if preferred = "" then preferred = PorticoContentSafeId(fallback)
    if preferred <> ""
        for each season in seasons
            if season.id = preferred then return preferred
        end for
    end if
    return seasons[0].id
end function

function PorticoContentLoadEpisodes(controller as object) as boolean
    if controller.detailModel = invalid or controller.selectedSeasonId = "" then return true
    session = PorticoContentSessionForController(controller)
    if session = invalid
        controller.detailModel.episodesStatus = "offline"
        PorticoContentPublish(controller, true)
        return true
    end if
    append = controller.episodeAppendRequested
    cursor = ""
    if append then cursor = PorticoContentSafeCursor(controller.detailModel.episodesNextCursor)
    if append and cursor = ""
        controller.detailModel.episodesHasMore = false
        controller.detailModel.episodesStatus = "ready"
        PorticoContentPublish(controller, false)
        return true
    end if
    if cursor <> ""
        cursorKey = controller.selectedSeasonId + "|" + cursor
        if controller.episodeCursorHistory[cursorKey] = true
            controller.detailModel.episodesHasMore = false
            controller.detailModel.episodesNextCursor = ""
            controller.detailModel.episodesStatus = "partial"
            PorticoContentPublish(controller, false)
            return true
        end if
        if controller.episodeCursorHistory.count() >= 256 then controller.episodeCursorHistory = {}
        controller.episodeCursorHistory[cursorKey] = true
    end if
    path = "/api/media/" + controller.selectedSeasonId + "/children?limit=100"
    if cursor <> ""
        encodedCursor = PorticoContentUrlEncode(cursor)
        if encodedCursor = ""
            controller.detailModel.episodesHasMore = false
            controller.detailModel.episodesNextCursor = ""
            controller.detailModel.episodesStatus = "partial"
            PorticoContentPublish(controller, false)
            return true
        end if
        path = path + "&cursor=" + encodedCursor
    end if
    result = PorticoContentGet(controller, session, path)
    if result.interrupted then return false
    if not result.ok
        if controller.detailModel.episodes.count() > 0 then controller.detailModel.episodesStatus = "partial" else controller.detailModel.episodesStatus = "error"
        PorticoContentPublish(controller, result.status = 401)
        return true
    end if
    artworkJobs = []
    page = PorticoContentEpisodesPageFromResponse(result.data, artworkJobs)
    if page = invalid
        if controller.detailModel.episodes.count() > 0 then controller.detailModel.episodesStatus = "partial" else controller.detailModel.episodesStatus = "error"
        PorticoContentPublish(controller, false)
        return true
    end if
    if not append then controller.detailModel.episodes = []
    for each episode in page.items
        if controller.detailModel.episodes.count() >= 400 then exit for
        if not PorticoContentContainsId(controller.detailModel.episodes, episode.id) then controller.detailModel.episodes.push(episode)
    end for
    controller.detailModel.episodesHasMore = page.hasMore and controller.detailModel.episodes.count() < 400
    controller.detailModel.episodesNextCursor = page.nextCursor
    if controller.detailModel.episodes.count() > 0 then controller.detailModel.episodesStatus = "ready" else controller.detailModel.episodesStatus = "empty"
    controller.episodeAppendRequested = false
    deepLinkFound = controller.requestedEpisodeId = "" or PorticoContentContainsId(controller.detailModel.episodes, controller.requestedEpisodeId)
    if not deepLinkFound and controller.detailModel.episodesHasMore
        controller.episodeAppendRequested = true
        controller.episodeLoadRequested = true
        controller.detailModel.episodesStatus = "refreshing"
    else
        controller.requestedEpisodeId = ""
    end if
    controller.cachedDetailId = controller.detailMediaId
    controller.cachedDetailModel = PorticoContentCachedDetail(controller.detailModel)
    PorticoContentPersistCache(controller)
    PorticoContentPublish(controller, false)
    PorticoContentMaterializeArtwork(controller, session, artworkJobs)
    PorticoContentPublish(controller, false)
    return not controller.episodeLoadRequested
end function

sub PorticoContentRefreshQueueAvailability(controller as object, session as object)
    if controller.detailModel = invalid or not PorticoContentHasAction(controller.detailModel.actions, "queue.add") then return
    controller.activeQueueSessionId = ""
    controller.activeQueueRevision = 0
    controller.detailModel.moreActions = PorticoContentMoreActions(controller.detailModel.actions, controller.detailModel.rating, controller.detailModel.reaction, false, "")
    body = { clientInstanceId: PorticoInstallationId(), clientProfile: PorticoPlaybackClientProfile() }
    restore = PorticoContentRequest(controller, session, "POST", "/api/playback/active", body)
    if not restore.ok or restore.data = invalid or restore.data.active <> true or restore.data.playback = invalid then return
    sessionId = PorticoContentSafeId(restore.data.playback.sessionId)
    if sessionId = "" then return
    queue = PorticoContentGet(controller, session, "/api/playback-sessions/" + sessionId + "/queue")
    if not queue.ok or queue.data = invalid or queue.data.canMutate <> true or queue.data.current = invalid then return
    currentId = PorticoContentSafeId(queue.data.current.id)
    available = currentId <> "" and currentId <> controller.detailModel.id
    controller.activeQueueSessionId = sessionId
    controller.activeQueueRevision = PorticoHttpInteger(queue.data.revision, 0)
    controller.detailModel.moreActions = PorticoContentMoreActions(controller.detailModel.actions, controller.detailModel.rating, controller.detailModel.reaction, available, currentId)
    if controller.detailModel.moreActions.menu.count() > 0 and not PorticoContentHasAction(controller.detailModel.uiActions, "more") then controller.detailModel.uiActions.push("more")
end sub

sub PorticoContentLoadTargets(controller as object, rawKind as dynamic)
    if controller.detailModel = invalid then return
    kind = LCase(PorticoContentSafeText(rawKind, 16))
    capability = kind + ".add"
    if (kind <> "playlist" and kind <> "collection") or not PorticoContentHasAction(controller.detailModel.actions, capability) then return
    if controller.serverStatus <> "online"
        controller.targetKind = kind
        controller.targetsStatus = "error"
        controller.targets = []
        PorticoContentMoreUnavailable(controller, "Connect to the server to load your " + kind + "s.")
        return
    end if
    controller.targetKind = kind
    controller.targetsStatus = "loading"
    controller.targets = []
    controller.moreActionStatus = "idle"
    controller.moreActionMessage = ""
    PorticoContentPublish(controller, false)
    session = PorticoContentSessionForController(controller)
    if session = invalid
        controller.targetsStatus = "error"
        PorticoContentPublish(controller, true)
        return
    end if
    result = PorticoContentGet(controller, session, "/api/" + kind + "s?limit=100")
    if result.ok then controller.targets = PorticoContentSavedTargetsFromResponse(result.data, kind)
    if not result.ok or controller.targets = invalid
        controller.targets = []
        controller.targetsStatus = "error"
    else if controller.targets.count() = 0
        controller.targetsStatus = "empty"
    else
        controller.targetsStatus = "ready"
    end if
    PorticoContentPublish(controller, result.status = 401)
end sub

sub PorticoContentAddToTarget(controller as object, rawKind as dynamic, rawTargetId as dynamic)
    kind = LCase(PorticoContentSafeText(rawKind, 16))
    targetId = PorticoContentSafeId(rawTargetId)
    target = PorticoContentFindTarget(controller.targets, targetId)
    if controller.detailModel = invalid or target = invalid or target.canEdit <> true or kind <> controller.targetKind then return
    session = PorticoContentSessionForController(controller)
    if session = invalid
        PorticoContentMoreUnavailable(controller, "Reconnect to the server and try again.")
        return
    end if
    controller.moreActionStatus = "working"
    controller.moreActionMessage = ""
    PorticoContentPublish(controller, false)
    body = { addMediaIds: [controller.detailModel.id] }
    if target.updatedAt <> "" then body.expectedUpdatedAt = target.updatedAt
    suffix = "/memberships:batch"
    if kind = "playlist" then suffix = "/items:batch"
    result = PorticoContentMutationRequest(controller, session, "POST", "/api/" + kind + "s/" + targetId + suffix, body)
    if result.ok
        controller.contentInvalidations = ["saved", "library", "detail:" + controller.detailModel.id]
        controller.savedResourcesRevision = controller.savedResourcesRevision + 1
        PorticoDiscoveryCacheRemoveViewer("saved-cache", controller)
        PorticoDiscoveryCacheRemoveViewer("library-cache", controller)
        controller.moreActionStatus = "success"
        controller.moreActionMessage = "Added to " + target.title + "."
        PorticoContentLoadTargets(controller, kind)
        controller.moreActionStatus = "success"
        controller.moreActionMessage = "Added to " + target.title + "."
    else
        controller.moreActionStatus = "error"
        controller.moreActionMessage = "That title couldn't be added."
    end if
    PorticoContentPublish(controller, result.status = 401)
end sub

sub PorticoContentCreateTarget(controller as object, rawKind as dynamic, rawTitle as dynamic)
    kind = LCase(PorticoContentSafeText(rawKind, 16))
    title = PorticoContentSafeText(rawTitle, 160)
    ' The v1 operation contract exposes collection creation but not playlist
    ' creation. Keep the unsupported television control absent instead of sending
    ' an uncontracted request.
    if controller.detailModel = invalid or title = "" or kind <> "collection" or not PorticoContentHasAction(controller.detailModel.actions, "collection.add") then return
    session = PorticoContentSessionForController(controller)
    if session = invalid
        PorticoContentMoreUnavailable(controller, "Reconnect to the server and try again.")
        return
    end if
    controller.moreActionStatus = "working"
    controller.moreActionMessage = ""
    PorticoContentPublish(controller, false)
    result = PorticoContentMutationRequest(controller, session, "POST", "/api/" + kind + "s", { mediaIds: [controller.detailModel.id], title: title, visibility: "private" })
    if result.ok
        controller.contentInvalidations = ["saved", "library", "detail:" + controller.detailModel.id]
        controller.savedResourcesRevision = controller.savedResourcesRevision + 1
        PorticoDiscoveryCacheRemoveViewer("saved-cache", controller)
        PorticoDiscoveryCacheRemoveViewer("library-cache", controller)
        controller.moreActionStatus = "success"
        controller.moreActionMessage = "Created " + title + " and added this title."
        PorticoContentLoadTargets(controller, kind)
        controller.moreActionStatus = "success"
        controller.moreActionMessage = "Created " + title + " and added this title."
    else
        controller.moreActionStatus = "error"
        controller.moreActionMessage = "That " + kind + " couldn't be created."
    end if
    PorticoContentPublish(controller, result.status = 401)
end sub

sub PorticoContentSetRating(controller as object, rawRating as dynamic)
    rating = PorticoHttpInteger(rawRating, -1)
    if controller.detailModel = invalid or rating < 0 or rating > 10 or not PorticoContentHasAction(controller.detailModel.actions, "rating.set") then return
    PorticoContentRunStateMutation(controller, "rating", rating)
end sub

sub PorticoContentSetReaction(controller as object, rawReaction as dynamic)
    reaction = LCase(PorticoContentSafeText(rawReaction, 12))
    if reaction <> "like" and reaction <> "dislike" and reaction <> "" then return
    if controller.detailModel = invalid or not PorticoContentHasAction(controller.detailModel.actions, "reaction.set") then return
    PorticoContentRunStateMutation(controller, "reaction", reaction)
end sub

sub PorticoContentRunStateMutation(controller as object, family as string, value as dynamic)
    session = PorticoContentSessionForController(controller)
    if session = invalid
        PorticoContentMoreUnavailable(controller, "Reconnect to the server and try again.")
        return
    end if
    controller.moreActionStatus = "working"
    controller.moreActionMessage = ""
    PorticoContentPublish(controller, false)
    body = {}
    body[family] = value
    result = PorticoContentMutationRequest(controller, session, "POST", "/api/media/" + controller.detailModel.id + "/" + family, body)
    if result.ok
        controller.contentInvalidations = ["home", "detail:" + controller.detailModel.id, "search", "library", "saved"]
        if family = "rating" then controller.detailModel.rating = value else controller.detailModel.reaction = value
        if controller.cachedDetailId = controller.detailModel.id and controller.cachedDetailModel <> invalid
            if family = "rating" then controller.cachedDetailModel.rating = value else controller.cachedDetailModel.reaction = value
            PorticoContentPersistCache(controller)
        end if
        controller.detailModel.moreActions = PorticoContentMoreActions(controller.detailModel.actions, controller.detailModel.rating, controller.detailModel.reaction, controller.detailModel.moreActions.queueAvailable = true, PorticoContentSafeId(controller.detailModel.moreActions.queueCurrentMediaId))
        controller.moreActionStatus = "success"
        if family = "rating"
            if value = 0 then controller.moreActionMessage = "Rating cleared." else controller.moreActionMessage = "Rated " + value.ToStr() + " out of 10."
        else
            if value = "" then controller.moreActionMessage = "Reaction removed." else controller.moreActionMessage = UCase(Left(value, 1)) + Mid(value, 2) + " saved."
        end if
    else
        controller.moreActionStatus = "error"
        controller.moreActionMessage = "That change couldn't be saved."
    end if
    PorticoContentPublish(controller, result.status = 401)
end sub

sub PorticoContentMutateQueue(controller as object, rawPosition as dynamic)
    position = LCase(PorticoContentSafeText(rawPosition, 16))
    if position <> "play_next" and position <> "append" then return
    if controller.detailModel = invalid or not PorticoContentHasAction(controller.detailModel.actions, "queue.add") then return
    session = PorticoContentSessionForController(controller)
    if session = invalid
        PorticoContentMoreUnavailable(controller, "Reconnect to the server and try again.")
        return
    end if
    PorticoContentRefreshQueueAvailability(controller, session)
    if controller.activeQueueSessionId = "" or controller.detailModel.moreActions.queueAvailable <> true
        controller.moreActionStatus = "error"
        controller.moreActionMessage = "Start playback on this Roku before adding another title to its queue."
        PorticoContentPublish(controller, false)
        return
    end if
    controller.moreActionStatus = "working"
    controller.moreActionMessage = ""
    PorticoContentPublish(controller, false)
    body = { action: position, expectedRevision: controller.activeQueueRevision, idempotencyKey: PorticoHttpNewRequestId(), mediaId: controller.detailModel.id }
    result = PorticoContentMutationRequest(controller, session, "PATCH", "/api/playback-sessions/" + controller.activeQueueSessionId + "/queue", body)
    if result.ok
        controller.contentInvalidations = ["playback.queue"]
        controller.activeQueueRevision = PorticoHttpInteger(result.data.revision, controller.activeQueueRevision)
        controller.moreActionStatus = "success"
        if position = "play_next" then controller.moreActionMessage = "This title will play next." else controller.moreActionMessage = "Added to the active queue."
    else
        controller.moreActionStatus = "error"
        controller.moreActionMessage = "The active queue couldn't be changed."
    end if
    PorticoContentPublish(controller, result.status = 401)
end sub

sub PorticoContentMoreUnavailable(controller as object, message as string)
    controller.moreActionStatus = "error"
    controller.moreActionMessage = message
    PorticoContentPublish(controller, true)
end sub

function PorticoContentFindTarget(targets as object, id as string) as dynamic
    for each target in targets
        if target.id = id then return target
    end for
    return invalid
end function

sub PorticoContentHomeFailed(controller as object, result as dynamic, missingSession as boolean)
    status = 0
    if result <> invalid then status = result.status
    reconnect = missingSession or status = 401
    if status = 403
        PorticoDiscoveryCacheRemoveViewer("content-cache", controller)
        controller.homeModel = invalid
        controller.cachedHomeModel = invalid
        controller.homeStatus = "permission-removed"
    else if status = 404 or status = 422
        controller.homeStatus = "incompatible"
    else if controller.homeModel <> invalid
        controller.homeStatus = "stale"
    else
        controller.homeStatus = "offline"
    end if
    requestReconnect = false
    if reconnect and controller.reconnectRequestedGeneration <> controller.sessionGeneration
        controller.reconnectRequestedGeneration = controller.sessionGeneration
        requestReconnect = true
    end if
    PorticoContentPublish(controller, requestReconnect)
end sub

sub PorticoContentDetailFailed(controller as object, result as dynamic, missingSession as boolean)
    status = 0
    if result <> invalid then status = result.status
    reconnect = missingSession or status = 401
    if status = 403 or status = 404
        if controller.cachedDetailId = controller.detailMediaId
            controller.cachedDetailId = ""
            controller.cachedDetailModel = invalid
            PorticoContentPersistCache(controller)
        end if
        controller.detailModel = invalid
        if status = 404 then controller.detailStatus = "not-found" else controller.detailStatus = "permission-removed"
    else if status = 422
        controller.detailStatus = "incompatible"
    else if controller.detailModel <> invalid
        controller.detailStatus = "stale"
    else
        controller.detailStatus = "offline"
    end if
    requestReconnect = false
    if reconnect and controller.reconnectRequestedGeneration <> controller.sessionGeneration
        controller.reconnectRequestedGeneration = controller.sessionGeneration
        requestReconnect = true
    end if
    PorticoContentPublish(controller, requestReconnect)
end sub

function PorticoContentSessionForController(controller as object) as dynamic
    if controller.envelopeMode then return PorticoDiscoverySessionForController(controller)
    serverId = controller.serverId
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid then return invalid
    session = record.payload
    if session.version <> 1 or PorticoContentSafeId(session.serverId) <> serverId then return invalid
    apiBaseUrl = PorticoContentSecureBaseUrl(session.apiBaseUrl)
    accessToken = PorticoHttpScalarString(session.accessToken, "")
    if apiBaseUrl = "" or not PorticoHttpServerAccessTokenValid(accessToken) then return invalid
    accountUserId = PorticoContentSafeId(session.accountUserId)
    accountDeviceId = PorticoContentSafeId(session.accountDeviceId)
    membershipId = PorticoContentSafeId(session.membershipId)
    if accountUserId = "" or accountDeviceId = "" or membershipId = "" then return invalid
    remaining = PorticoSignedDocumentSecondsUntil(session.accessExpiresAt)
    if remaining = invalid or remaining <= 0 then return invalid
    return {
        apiBaseUrl: apiBaseUrl,
        accessToken: accessToken,
        generation: record.generation,
        cacheBinding: accountUserId + "|" + accountDeviceId + "|" + membershipId
    }
end function

function PorticoContentSecureBaseUrl(value as dynamic) as string
    if value = invalid then return ""
    url = value.ToStr().Trim()
    if Len(url) < 12 or Len(url) > 2048 or Left(LCase(url), 8) <> "https://" then return ""
    if Instr(1, url, Chr(0)) > 0 or Instr(1, url, Chr(10)) > 0 or Instr(1, url, Chr(13)) > 0 or Instr(1, url, Chr(9)) > 0 or Instr(1, url, " ") > 0 or Instr(1, url, "\") > 0 then return ""
    if Instr(9, url, "@") > 0 or Instr(9, url, "?") > 0 or Instr(9, url, "#") > 0 then return ""
    while Right(url, 1) = "/"
        url = Left(url, Len(url) - 1)
    end while
    if Instr(9, url, "/") > 0 then return ""
    return url
end function

function PorticoContentGet(controller as object, session as object, path as string) as object
    return PorticoContentRequest(controller, session, "GET", path, "")
end function

function PorticoContentMutationRequest(controller as object, session as object, method as string, path as string, body as dynamic) as object
    controller.nonInterruptibleRequest = true
    result = PorticoContentRequest(controller, session, method, path, body)
    controller.nonInterruptibleRequest = false
    return result
end function

function PorticoContentRequest(controller as object, session as object, method as string, path as string, body as dynamic) as object
    return PorticoDiscoveryRequest(controller, session, method, path, body)
end function

function PorticoContentHttpFailure(status as integer, retryable as boolean, code as string) as object
    return { interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: code }
end function

function PorticoContentInterrupted(controller as object) as boolean
    if controller.envelopeMode then return PorticoDiscoveryInterrupted(controller)
    if controller.nonInterruptibleRequest = true then return false
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return false
    return PorticoHttpInteger(command.sequence, 0) > controller.lastCommandSequence
end function

sub PorticoContentMaterializeArtwork(controller as object, session as object, jobs as object)
    completed = {}
    attempted = 0
    budget = CreateObject("roTimespan")
    budget.Mark()
    for each job in jobs
        if attempted >= 64 or budget.TotalSeconds() >= 20 then return
        if PorticoContentInterrupted(controller) then return
        sourceDigest = PorticoBrowseArtworkDigest(job.source + "|" + job.width.ToStr() + "x" + job.height.ToStr())
        cacheKey = PorticoContentSafeArtworkKey(controller.serverId + "-" + job.key + "-" + sourceDigest)
        if cacheKey <> ""
            dedupeKey = job.source + "|" + job.width.ToStr() + "x" + job.height.ToStr()
            uri = completed[dedupeKey]
            if uri = invalid
                attempted = attempted + 1
                uri = PorticoContentDownloadArtwork(controller, session, job.source, cacheKey, job.width, job.height)
                completed[dedupeKey] = uri
            end if
            if uri <> invalid and uri <> "" then job.target[job.field] = uri
        end if
    end for
end sub

function PorticoContentDownloadArtwork(controller as object, session as object, source as string, cacheKey as string, width as integer, height as integer) as string
    path = PorticoContentSafeServerResourcePath(source)
    if path = "" then return ""
    separator = "?"
    if Instr(1, path, "?") > 0 then separator = "&"
    url = session.apiBaseUrl + path + separator + "width=" + width.ToStr() + "&height=" + height.ToStr()
    request = PorticoHttpNormalizeRequest({ method: "GET", url: url, body: "", headers: { Authorization: "Bearer " + session.accessToken }, timeoutMs: 5000, expectJson: false, allowInsecureLan: session.allowInsecureLan = true })
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return ""
    for each extension in ["jpg", "png", "gif"]
        cachedPath = "tmp:/portico-content/" + cacheKey + "." + extension
        if PorticoHttpFileWithinLimit(cachedPath, PorticoHttpLimits().maximumArtworkBytes)
            PorticoContentTouchArtwork(controller, cachedPath)
            return cachedPath
        end if
    end for
    tempPath = "tmp:/portico-content/" + cacheKey + ".part"
    DeleteFile(tempPath)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return ""
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest("GET")
    transfer.EnableEncodings(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return ""
    if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return ""
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return ""
    end for
    if not transfer.AsyncGetToFile(tempPath) then return ""
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoContentInterrupted(controller)
            transfer.AsyncCancel()
            DeleteFile(tempPath)
            return ""
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            if message.GetResponseCode() < 200 or message.GetResponseCode() >= 300
                DeleteFile(tempPath)
                return ""
            end if
            headers = PorticoHttpResponseHeaders(message.GetResponseHeadersArray())
            contentType = LCase(PorticoHttpScalarString(headers["content-type"], ""))
            extension = ""
            if Left(contentType, 10) = "image/jpeg" then extension = "jpg"
            if Left(contentType, 9) = "image/png" then extension = "png"
            if Left(contentType, 9) = "image/gif" then extension = "gif"
            if extension = ""
                DeleteFile(tempPath)
                return ""
            end if
            if not PorticoHttpFileWithinLimit(tempPath, PorticoHttpLimits().maximumArtworkBytes)
                DeleteFile(tempPath)
                return ""
            end if
            finalPath = "tmp:/portico-content/" + cacheKey + "." + extension
            DeleteFile(finalPath)
            if not MoveFile(tempPath, finalPath)
                DeleteFile(tempPath)
                return ""
            end if
            PorticoContentTouchArtwork(controller, finalPath)
            PorticoContentTrimArtwork(controller, finalPath)
            return finalPath
        end if
    end while
    transfer.AsyncCancel()
    DeleteFile(tempPath)
    return ""
end function

function PorticoContentSafeArtworkKey(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr()
    if Len(normalized) < 1 or Len(normalized) > 240 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

sub PorticoContentPrepareArtworkDirectory()
    CreateDirectory("tmp:/portico-content")
end sub

sub PorticoContentTouchArtwork(controller as object, path as string)
    if controller.artworkAccess = invalid or Type(controller.artworkAccess) <> "roAssociativeArray" then controller.artworkAccess = {}
    controller.artworkAccessCounter = PorticoHttpInteger(controller.artworkAccessCounter, 0) + 1
    if controller.artworkAccessCounter > 2000000000
        controller.artworkAccess = {}
        controller.artworkAccessCounter = 1
    end if
    controller.artworkAccess[path] = controller.artworkAccessCounter
end sub

sub PorticoContentTrimArtwork(controller as object, protectedPath as string)
    directory = "tmp:/portico-content"
    files = ListDir(directory)
    if files = invalid then return
    fileSystem = CreateObject("roFileSystem")
    if fileSystem = invalid then return
    candidates = []
    totalBytes = 0
    for each filename in files
        path = directory + "/" + filename
        if Right(LCase(filename), 5) = ".part"
            DeleteFile(path)
        else
            metadata = fileSystem.Stat(path)
            if metadata <> invalid and Type(metadata) = "roAssociativeArray" and metadata.type = "file"
                size = PorticoHttpInteger(metadata.size, 0)
                totalBytes = totalBytes + size
                access = 0
                if controller.artworkAccess <> invalid and controller.artworkAccess[path] <> invalid then access = PorticoHttpInteger(controller.artworkAccess[path], 0)
                candidates.Push({path: path, size: size, access: access})
            end if
        end if
    end for
    while candidates.Count() > 96 or totalBytes > 100663296
        oldestIndex = -1
        oldestAccess = 2147483647
        for index = 0 to candidates.Count() - 1
            candidate = candidates[index]
            if candidate.path <> protectedPath and candidate.access < oldestAccess
                oldestIndex = index
                oldestAccess = candidate.access
            end if
        end for
        if oldestIndex < 0 then exit while
        removed = candidates[oldestIndex]
        DeleteFile(removed.path)
        totalBytes = totalBytes - removed.size
        if controller.artworkAccess <> invalid then controller.artworkAccess.Delete(removed.path)
        candidates.Delete(oldestIndex)
    end while
end sub

sub PorticoContentClearArtworkDirectory(controller as object)
    files = ListDir("tmp:/portico-content")
    if files <> invalid
        for each filename in files
            DeleteFile("tmp:/portico-content/" + filename)
        end for
    end if
    CreateDirectory("tmp:/portico-content")
    controller.artworkAccess = {}
    controller.artworkAccessCounter = 0
end sub

sub PorticoContentRestoreCache(controller as object)
    if controller.envelopeMode
        bound = PorticoDiscoveryCacheSessionForController(controller)
        if bound = invalid then return
        controller.sessionGeneration = bound.recordGeneration
        controller.cacheBinding = PorticoViewerScopeCanonicalIdentity(bound.viewerScope, false)
    else
        session = PorticoContentSessionForController(controller)
        if session = invalid then return
        controller.sessionGeneration = session.generation
        controller.cacheBinding = session.cacheBinding
    end if
    payload = PorticoDiscoveryCacheRead("content-cache", controller, "content", "home-and-detail")
    if payload = invalid then return
    if not controller.envelopeMode
        if payload.version <> 1 or PorticoContentSafeId(payload.serverId) <> controller.serverId or payload.cacheBinding <> controller.cacheBinding then return
    end if
    home = PorticoContentCachedHome(payload.home)
    if home <> invalid
        controller.cachedHomeModel = home
        controller.homeModel = PorticoContentClone(home)
        controller.homeStatus = "stale"
    end if
    detailId = PorticoContentSafeId(payload.detailId)
    detail = PorticoContentCachedDetail(payload.detail)
    if detailId <> "" and detail <> invalid and detail.id = detailId
        controller.cachedDetailId = detailId
        controller.cachedDetailModel = detail
    end if
end sub

sub PorticoContentPersistCache(controller as object)
    if controller.serverId = "" or controller.cacheBinding = "" then return
    payload = { version: 1, serverId: controller.serverId, cacheBinding: controller.cacheBinding, cachedAt: PorticoContentUTCNowString() }
    if controller.cachedHomeModel <> invalid then payload.home = controller.cachedHomeModel
    if controller.cachedDetailId <> "" and controller.cachedDetailModel <> invalid
        payload.detailId = controller.cachedDetailId
        payload.detail = controller.cachedDetailModel
    end if
    PorticoDiscoveryCacheCommit("content-cache", controller, "content", "home-and-detail", payload)
end sub

function PorticoContentClone(value as dynamic) as dynamic
    if value = invalid then return invalid
    return ParseJson(FormatJson(value))
end function

function PorticoContentUTCNowString() as string
    now = CreateObject("roDateTime")
    if now = invalid then return ""
    return now.ToISOString()
end function

sub PorticoContentPublish(controller as object, serverReconnectRequired as boolean)
    projection = {
        contentServerId: controller.serverId,
        homeStatus: controller.homeStatus,
        detailStatus: controller.detailStatus,
        detailMediaId: controller.detailMediaId,
        savedResourcesRevision: controller.savedResourcesRevision,
        contentInvalidations: controller.contentInvalidations,
        serverReconnectRequired: serverReconnectRequired
    }
    if controller.homeModel <> invalid
        homeModel = PorticoContentHomePreferenceProjection(controller, controller.homeModel)
        homeModel.availabilityStatus = PorticoContentAvailabilityStatus(controller.homeStatus, controller.serverStatus)
        projection.homeModel = homeModel
    end if
    if controller.detailModel <> invalid
        detailModel = PorticoContentClone(controller.detailModel)
        detailModel.availabilityStatus = PorticoContentAvailabilityStatus(controller.detailStatus, controller.serverStatus)
        detailModel.selectedPersonId = controller.selectedPersonId
        detailModel.selectedPersonName = controller.selectedPersonName
        detailModel.personStatus = controller.personStatus
        detailModel.personResults = PorticoContentClone(controller.personResults)
        detailModel.targetKind = controller.targetKind
        detailModel.targetsStatus = controller.targetsStatus
        detailModel.targets = PorticoContentClone(controller.targets)
        detailModel.moreActionStatus = controller.moreActionStatus
        detailModel.moreActionMessage = controller.moreActionMessage
        projection.detailModel = detailModel
    end if
    if controller.selectedPersonId <> ""
        personViewState = {
            status: controller.personStatus,
            personId: controller.selectedPersonId,
            name: controller.selectedPersonName,
            roles: [],
            image: "",
            items: PorticoContentClone(controller.personResults),
            hasMore: false,
            messageId: ""
        }
        if controller.personModel <> invalid
            personViewState.name = controller.personModel.name
            personViewState.roles = PorticoContentClone(controller.personModel.roles)
            personViewState.image = controller.personModel.image
            personViewState.hasMore = controller.personModel.hasMore = true
        end if
        if controller.personStatus = "error" then personViewState.messageId = "media.search-failed"
        if controller.personStatus = "offline" then personViewState.messageId = "media.detail-offline"
        if controller.personStatus = "empty" then personViewState.messageId = "search.people-empty"
        projection.personViewState = personViewState
    end if
    if not controller.envelopeMode then m.top.projection = projection
    envelope = PorticoDiscoveryResultEnvelope(controller, projection)
    if envelope <> invalid then m.top.projectionEnvelope = envelope
end sub

function PorticoContentHomePreferenceProjection(controller as object, source as object) as object
    model = PorticoContentClone(source)
    if model = invalid or model.rows = invalid then return model
    ordered = []
    used = {}
    for each rowId in controller.homeRowOrder
        row = PorticoContentFindHomeRow(model, rowId)
        if row <> invalid and not PorticoContentHomeRowHidden(controller, row)
            ordered.push(row)
            used[row.id] = true
        end if
    end for
    for each row in model.rows
        if used[row.id] <> true and not PorticoContentHomeRowHidden(controller, row)
            preferred = row.defaultVisible = true or row.required = true or PorticoContentArrayContainsText(controller.homeRowOrder, row.id)
            if preferred then ordered.push(row)
        end if
    end for
    model.rows = ordered
    model.homeCustomization = {
        rowOrder: PorticoContentClone(controller.homeRowOrder),
        hiddenRowIds: PorticoContentClone(controller.hiddenHomeRowIds),
        availableRows: PorticoContentHomeCustomizationRows(source.rows)
    }
    return model
end function

function PorticoContentHomeRowHidden(controller as object, row as object) as boolean
    if row.required = true then return false
    return PorticoContentArrayContainsText(controller.hiddenHomeRowIds, row.id)
end function

function PorticoContentHomeCustomizationRows(rows as dynamic) as object
    result = []
    if rows = invalid or GetInterface(rows, "ifArray") = invalid then return result
    for each row in rows
        if result.count() >= 32 then exit for
        if row <> invalid and Type(row) = "roAssociativeArray"
            result.push({id: row.id, title: row.title, required: row.required = true, hideable: row.hideable = true, reorderable: row.reorderable = true, defaultVisible: row.defaultVisible = true})
        end if
    end for
    return result
end function

function PorticoContentAvailabilityStatus(contentStatus as string, serverStatus as string) as string
    if contentStatus = "stale"
        if serverStatus = "online" then return "refresh-failed"
        return "offline"
    end if
    return "current"
end function
