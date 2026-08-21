sub init()
    m.top.functionName = "PorticoSavedRun"
end sub

sub PorticoSavedRun()
    controller = {
        lastCommandSequence: 0,
        serverId: "",
        serverName: "",
        serverStatus: "not-connected",
        sessionGeneration: 0,
        cacheBinding: "",
        reconnectRequestedGeneration: -1,
        selectedTabId: "watchlist",
        selectedResourceId: "",
        selectedResourceTitle: "",
        page: invalid,
        windowOffset: 0,
        status: "idle",
        requestKind: "",
        cursorHistory: {},
        mutationQueue: [],
        mutationResult: invalid,
        nonInterruptibleRequest: false,
        quietRefresh: false,
        quietWindowOffset: 0
    }
    PorticoDiscoveryTaskAdopt(controller, PorticoDiscoveryTaskState("saved"))
    PorticoBrowsePrepareArtworkDirectory("saved")
    PorticoSavedPublish(controller, false)
    while true
        PorticoSavedHandleCommand(controller)
        PorticoSavedTick(controller)
        Sleep(250)
    end while
end sub

sub PorticoSavedHandleCommand(controller as object)
    command = invalid
    envelope = m.top.commandEnvelope
    if envelope <> invalid and Type(envelope) = "roAssociativeArray"
        previousGeneration = controller.viewerGeneration
        command = PorticoDiscoveryAcceptCommand(controller, envelope, "saved")
        if command <> invalid and previousGeneration <> controller.viewerGeneration
            PorticoSavedReset(controller)
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
    kind = LCase(PorticoHttpScalarString(command.kind, ""))
    if kind = "server-state"
        PorticoSavedApplyServerState(controller, command)
    else if kind = "open-saved"
        if controller.serverStatus = "online"
            controller.status = "loading"
            controller.requestKind = "page"
            PorticoSavedPublish(controller, false)
        end if
    else if kind = "select-saved-tab"
        PorticoSavedSelectTab(controller, command.tabId)
    else if kind = "select-saved-resource"
        PorticoSavedSelectResource(controller, command.resourceId, command.resourceTitle)
    else if kind = "close-saved-resource"
        PorticoSavedCloseResource(controller)
    else if kind = "load-more-saved"
        PorticoSavedLoadMore(controller)
    else if kind = "retry-saved"
        if controller.serverStatus = "online"
            controller.status = "loading"
            controller.requestKind = "page"
            PorticoSavedPublish(controller, false)
        end if
    else if kind = "quiet-refresh-saved"
        if controller.serverStatus = "online" and controller.page <> invalid
            controller.quietRefresh = true
            controller.quietWindowOffset = controller.windowOffset
            controller.requestKind = "page"
        end if
    else if kind = "mutate-media-state"
        PorticoSavedQueueMutation(controller, command)
    else if kind = "invalidate-saved-resources"
        PorticoDiscoveryCacheRemoveViewer("saved-cache", controller)
        if controller.serverStatus = "online"
            controller.status = "loading"
            controller.requestKind = "page"
            PorticoSavedPublish(controller, false)
        end if
    end if
end sub

sub PorticoSavedApplyServerState(controller as object, command as object)
    serverId = PorticoBrowseSafeId(command.selectedServerId)
    status = LCase(PorticoHttpScalarString(command.serverStatus, "not-connected"))
    allowed = { online: true, connecting: true, offline: true, blocked: true, "identity-mismatch": true, incompatible: true, "permission-removed": true, selected: true, "not-connected": true }
    if allowed[status] <> true then status = "not-connected"
    changedServer = serverId <> controller.serverId
    if changedServer
        PorticoSavedReset(controller)
    end if
    controller.serverId = serverId
    controller.serverName = PorticoBrowseSafeText(command.selectedServerName, 100)
    controller.serverStatus = status
    if serverId = "" or status = "not-connected"
        PorticoDiscoveryCacheRemoveViewer("saved-cache", controller)
        PorticoSavedReset(controller)
        controller.serverId = ""
        controller.serverName = ""
        controller.serverStatus = "not-connected"
    else
        if controller.page = invalid then PorticoSavedRestoreCache(controller)
        if status = "online"
            controller.status = "loading"
            controller.requestKind = "page"
        else if status = "permission-removed" or status = "identity-mismatch" or status = "incompatible"
            PorticoDiscoveryCacheRemoveViewer("saved-cache", controller)
            controller.page = invalid
            controller.status = "error"
        else if controller.page <> invalid
            controller.status = "stale"
        else
            controller.status = "error"
        end if
    end if
    PorticoSavedPublish(controller, false)
end sub

sub PorticoSavedSelectTab(controller as object, rawId as dynamic)
    tabId = LCase(PorticoBrowseSafeId(rawId))
    if not PorticoSavedTabValid(tabId) or tabId = controller.selectedTabId then return
    controller.selectedTabId = tabId
    controller.selectedResourceId = ""
    controller.selectedResourceTitle = ""
    controller.page = invalid
    controller.windowOffset = 0
    controller.cursorHistory = {}
    PorticoSavedRestoreContextCache(controller)
    if controller.serverStatus = "online"
        if controller.page = invalid then controller.status = "loading" else controller.status = "stale"
        controller.requestKind = "page"
    else if controller.page = invalid
        controller.status = "error"
    end if
    PorticoSavedPublish(controller, false)
end sub

sub PorticoSavedSelectResource(controller as object, rawId as dynamic, rawTitle as dynamic)
    if controller.selectedTabId = "watchlist" or controller.selectedTabId = "favorites" then return
    resourceId = PorticoBrowseSafeId(rawId)
    if resourceId = "" then return
    controller.selectedResourceId = resourceId
    controller.selectedResourceTitle = PorticoBrowseSafeText(rawTitle, 140)
    controller.page = invalid
    controller.windowOffset = 0
    controller.cursorHistory = {}
    PorticoSavedRestoreContextCache(controller)
    if controller.serverStatus = "online"
        if controller.page = invalid then controller.status = "loading" else controller.status = "stale"
        controller.requestKind = "page"
    else if controller.page = invalid
        controller.status = "error"
    end if
    PorticoSavedPublish(controller, false)
end sub

sub PorticoSavedCloseResource(controller as object)
    if controller.selectedResourceId = "" then return
    controller.selectedResourceId = ""
    controller.selectedResourceTitle = ""
    controller.page = invalid
    controller.windowOffset = 0
    controller.cursorHistory = {}
    PorticoSavedRestoreContextCache(controller)
    if controller.serverStatus = "online"
        if controller.page = invalid then controller.status = "loading" else controller.status = "stale"
        controller.requestKind = "page"
    else if controller.page = invalid
        controller.status = "error"
    end if
    PorticoSavedPublish(controller, false)
end sub

sub PorticoSavedLoadMore(controller as object)
    if controller.page = invalid or controller.status <> "ready" then return
    windowSize = PorticoSavedWindowSize(controller)
    if controller.windowOffset + windowSize < controller.page.items.count()
        controller.windowOffset = controller.windowOffset + windowSize
        PorticoSavedPublish(controller, false)
    else if controller.page.hasMore = true and controller.page.nextCursor <> "" and controller.serverStatus = "online"
        controller.status = "loading"
        controller.requestKind = "more"
        PorticoSavedPublish(controller, false)
    end if
end sub

sub PorticoSavedQueueMutation(controller as object, command as object)
    mediaId = PorticoBrowseSafeId(command.mediaId)
    family = LCase(PorticoBrowseSafeText(command.family, 16))
    token = PorticoBrowseSafeId(command.token)
    if mediaId = "" or token = "" or (family <> "watchlist" and family <> "favorite" and family <> "watched") then return
    controller.mutationQueue.push({ mediaId: mediaId, family: family, value: command.value = true, token: token })
end sub

sub PorticoSavedTick(controller as object)
    if controller.mutationQueue.count() > 0
        mutation = controller.mutationQueue.shift()
        PorticoSavedRunMutation(controller, mutation)
        return
    end if
    if controller.serverStatus <> "online" or controller.requestKind = "" then return
    kind = controller.requestKind
    controller.requestKind = ""
    PorticoSavedLoadPage(controller, kind = "more")
end sub

sub PorticoSavedLoadPage(controller as object, append as boolean)
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid
        PorticoSavedFailed(controller, invalid, true)
        return
    end if
    controller.sessionGeneration = session.generation
    controller.cacheBinding = session.cacheBinding
    cursor = ""
    if append and controller.page <> invalid then cursor = PorticoBrowseSafeCursor(controller.page.nextCursor)
    if append and cursor = ""
        controller.status = "ready"
        PorticoSavedPublish(controller, false)
        return
    end if
    if append and cursor <> ""
        cursorKey = PorticoSavedContextKey(controller) + "|" + cursor
        if controller.cursorHistory[cursorKey] = true
            controller.page.hasMore = false
            controller.page.nextCursor = ""
            controller.status = "stale"
            PorticoSavedPublish(controller, false)
            return
        end if
        if controller.cursorHistory.count() >= 512 then controller.cursorHistory = {}
        controller.cursorHistory[cursorKey] = true
    end if
    result = invalid
    artworkJobs = []
    normalized = invalid
    tabId = controller.selectedTabId
    if controller.selectedResourceId <> ""
        if tabId = "saved-views"
            body = { limit: 50 }
            if cursor <> "" then body.cursor = cursor
            result = PorticoDiscoveryRequest(controller, session, "POST", "/api/saved-views/" + controller.selectedResourceId + "/browse", body)
        else
            path = "/api/" + tabId + "/" + controller.selectedResourceId + "/items?limit=50"
            if cursor <> "" then path = path + "&cursor=" + PorticoBrowseUrlEncode(cursor)
            result = PorticoDiscoveryRequest(controller, session, "GET", path, "")
        end if
        if result.ok then normalized = PorticoSavedNormalizeMediaPage(result.data, tabId, artworkJobs)
    else
        path = "/api/" + tabId + "?limit=50"
        if cursor <> "" then path = path + "&cursor=" + PorticoBrowseUrlEncode(cursor)
        result = PorticoDiscoveryRequest(controller, session, "GET", path, "")
        if result.ok
            if tabId = "watchlist" or tabId = "favorites"
                normalized = PorticoSavedNormalizeMediaPage(result.data, tabId, artworkJobs)
            else
                normalized = PorticoSavedNormalizeResourcePage(result.data, tabId)
            end if
        end if
    end if
    if result = invalid or result.interrupted then return
    if not result.ok
        PorticoSavedFailed(controller, result, false)
        return
    end if
    if normalized = invalid
        if controller.quietRefresh and controller.page <> invalid then controller.status = "stale" else controller.status = "error"
        controller.quietRefresh = false
        PorticoSavedPublish(controller, false)
        return
    end if
    if append and controller.page <> invalid
        previousCount = controller.page.items.count()
        PorticoSavedMergeUnique(controller.page.items, normalized.items, PorticoSavedBufferMaximum(controller))
        controller.page.hasMore = normalized.hasMore
        controller.page.nextCursor = normalized.nextCursor
        if controller.page.items.count() > previousCount then controller.windowOffset = previousCount
    else
        controller.page = normalized
        if controller.quietRefresh then controller.windowOffset = controller.quietWindowOffset else controller.windowOffset = 0
        controller.cursorHistory = {}
    end if
    if controller.page.items.count() > 0 then controller.status = "ready" else controller.status = "empty"
    controller.reconnectRequestedGeneration = -1
    controller.quietRefresh = false
    PorticoSavedPersistCache(controller)
    PorticoSavedPublish(controller, false)
    PorticoBrowseMaterializeArtwork(controller, session, "saved", artworkJobs)
    PorticoSavedPublish(controller, false)
end sub

sub PorticoSavedRunMutation(controller as object, mutation as object)
    result = invalid
    if controller.serverStatus = "online"
        session = PorticoDiscoverySessionForController(controller)
        if session <> invalid
            body = {}
            bodyKey = mutation.family
            if mutation.family = "watchlist" then bodyKey = "watchlisted"
            body[bodyKey] = mutation.value
            controller.nonInterruptibleRequest = true
            result = PorticoDiscoveryRequest(controller, session, "POST", "/api/media/" + mutation.mediaId + "/" + mutation.family, body)
            controller.nonInterruptibleRequest = false
        end if
    end if
    succeeded = result <> invalid and result.ok = true
    status = 0
    if result <> invalid then status = result.status
    controller.mutationResult = { token: mutation.token, mediaId: mutation.mediaId, family: mutation.family, value: mutation.value, succeeded: succeeded, status: status, conflict: status = 409, invalidations: ["home", "detail:" + mutation.mediaId, "search", "library", "saved"] }
    if succeeded
        PorticoSavedApplyMutationToPage(controller, mutation)
        PorticoSavedPersistCache(controller)
        if controller.serverStatus = "online" then controller.requestKind = "page"
    else if status = 409 and controller.serverStatus = "online"
        ' A conflict means the optimistic state is stale. Reload the active Saved
        ' scope immediately so the rollback is followed by authoritative state.
        controller.status = "loading"
        controller.requestKind = "page"
    end if
    reconnect = status = 401 or result = invalid
    PorticoSavedPublish(controller, reconnect)
    controller.mutationResult = invalid
end sub

sub PorticoSavedApplyMutationToPage(controller as object, mutation as object)
    if controller.page = invalid or controller.page.items = invalid then return
    remove = (controller.selectedTabId = "watchlist" and mutation.family = "watchlist" and not mutation.value) or (controller.selectedTabId = "favorites" and mutation.family = "favorite" and not mutation.value)
    for index = controller.page.items.count() - 1 to 0 step -1
        item = controller.page.items[index]
        if item.id = mutation.mediaId
            if remove
                controller.page.items.delete(index)
            else
                if mutation.family = "watchlist" then item.watchlisted = mutation.value
                if mutation.family = "favorite" then item.favorite = mutation.value
                if mutation.family = "watched" then item.watched = mutation.value
                item.actions = PorticoSavedActionsAfterMutation(item.actions, mutation.family, mutation.value)
                item.uiActions = PorticoSavedUiActions(item.actions)
            end if
        end if
    end for
    if controller.page.items.count() = 0 then controller.status = "empty"
end sub

sub PorticoSavedFailed(controller as object, result as dynamic, missingSession as boolean)
    status = 0
    if result <> invalid then status = result.status
    if status = 403 or status = 404
        PorticoDiscoveryCacheRemoveViewer("saved-cache", controller)
        controller.page = invalid
        controller.status = "error"
    else if controller.page <> invalid
        controller.status = "stale"
    else
        controller.status = "error"
    end if
    requestReconnect = false
    if (missingSession or status = 401) and controller.reconnectRequestedGeneration <> controller.sessionGeneration
        controller.reconnectRequestedGeneration = controller.sessionGeneration
        requestReconnect = true
    end if
    controller.quietRefresh = false
    PorticoSavedPublish(controller, requestReconnect)
end sub

sub PorticoSavedReset(controller as object)
    controller.sessionGeneration = 0
    controller.cacheBinding = ""
    controller.reconnectRequestedGeneration = -1
    controller.quietRefresh = false
    controller.quietWindowOffset = 0
    controller.selectedTabId = "watchlist"
    controller.selectedResourceId = ""
    controller.selectedResourceTitle = ""
    controller.page = invalid
    controller.windowOffset = 0
    controller.status = "idle"
    controller.requestKind = ""
    controller.cursorHistory = {}
    controller.mutationQueue = []
    controller.mutationResult = invalid
end sub

sub PorticoSavedRestoreCache(controller as object)
    if controller.envelopeMode
        bound = PorticoDiscoveryCacheSessionForController(controller)
        if bound = invalid then return
        controller.sessionGeneration = bound.recordGeneration
        controller.cacheBinding = PorticoViewerScopeCanonicalIdentity(bound.viewerScope, false)
    else
        session = PorticoDiscoverySessionForController(controller)
        if session = invalid then return
        controller.sessionGeneration = session.generation
        controller.cacheBinding = session.cacheBinding
    end if
    PorticoSavedRestoreContextCache(controller)
end sub

sub PorticoSavedRestoreContextCache(controller as object)
    if controller.cacheBinding = "" then return
    parameters = PorticoSavedCacheParameters(controller)
    if parameters = invalid then return
    payload = PorticoDiscoveryCacheRead("saved-cache", controller, "saved", parameters)
    if payload = invalid then return
    if not controller.envelopeMode
        if payload.version <> 1 or PorticoBrowseSafeId(payload.serverId) <> controller.serverId or payload.cacheBinding <> controller.cacheBinding then return
    end if
    view = PorticoSavedCacheView(payload.viewState)
    if view = invalid then return
    if view.selectedTabId <> controller.selectedTabId or view.selectedResourceId <> controller.selectedResourceId then return
    if controller.selectedResourceTitle = "" then controller.selectedResourceTitle = view.selectedResourceTitle
    controller.page = { items: view.items, hasMore: false, nextCursor: "", total: view.resultCount }
    controller.status = "stale"
end sub

sub PorticoSavedPersistCache(controller as object)
    if controller.serverId = "" or controller.cacheBinding = "" or controller.page = invalid then return
    cached = PorticoSavedCacheView(PorticoSavedViewState(controller))
    if cached = invalid then return
    parameters = PorticoSavedCacheParameters(controller)
    if parameters = invalid then return
    PorticoDiscoveryCacheCommit("saved-cache", controller, "saved", parameters, { version: 1, serverId: controller.serverId, cacheBinding: controller.cacheBinding, viewState: cached })
end sub

function PorticoSavedCacheParameters(controller as object) as dynamic
    return PorticoDiscoveryCanonicalParameters({tab: controller.selectedTabId, resource: controller.selectedResourceId})
end function

function PorticoSavedContextKey(controller as object) as string
    return controller.selectedTabId + "|" + controller.selectedResourceId
end function

sub PorticoSavedPublish(controller as object, reconnectRequired as boolean)
    projection = { savedViewState: PorticoSavedViewState(controller), savedServerReconnectRequired: reconnectRequired }
    if controller.mutationResult <> invalid then projection.savedMutationResult = controller.mutationResult
    if not controller.envelopeMode then m.top.projection = projection
    envelope = PorticoDiscoveryResultEnvelope(controller, projection)
    if envelope <> invalid then m.top.projectionEnvelope = envelope
end sub

function PorticoSavedViewState(controller as object) as object
    view = {
        status: "loading",
        libraryName: "Saved",
        serverName: controller.serverName,
        selectedTabId: controller.selectedTabId,
        selectedResourceId: controller.selectedResourceId,
        selectedResourceTitle: controller.selectedResourceTitle,
        presentation: "grid",
        tabs: PorticoSavedTabs(controller.selectedTabId),
        actions: [],
        items: [],
        resultCount: 0,
        hasMore: false,
        loadMoreLabel: "Load more",
        sharingAllowed: false
    }
    if controller.selectedResourceId = ""
        if controller.selectedTabId = "playlists" or controller.selectedTabId = "collections" or controller.selectedTabId = "saved-views" then view.presentation = "resources"
    else
        view.actions = [{ id: "close-saved-resource", label: "All " + LCase(PorticoSavedTabLabel(controller.selectedTabId)), iconId: "navigation.back", selected: true, width: 260 }]
        if controller.selectedResourceTitle <> "" then view.libraryName = controller.selectedResourceTitle
    end if
    if controller.page <> invalid
        windowSize = PorticoSavedWindowSize(controller)
        view.items = PorticoSavedMediaWindow(controller.page, controller.windowOffset, windowSize)
        view.resultCount = controller.page.total
        if view.resultCount <= 0 then view.resultCount = controller.page.items.count()
        view.hasMore = controller.windowOffset + view.items.count() < controller.page.items.count() or controller.page.hasMore = true
    end if
    if controller.status = "ready"
        view.status = "ready"
        view.availabilityStatus = "current"
    else if controller.status = "stale"
        view.status = "ready"
        if controller.serverStatus = "online" then view.availabilityStatus = "refresh-failed" else view.availabilityStatus = "offline"
    else if controller.status = "empty"
        view.status = "empty"
        view.availabilityStatus = "current"
        PorticoSavedEmptyCopy(view, controller)
    else if controller.status = "idle" or controller.serverId = ""
        view.status = "error"
        view.availabilityStatus = "current"
        view.title = "Choose a server"
        view.message = "Connect to a Portico Server to view saved media."
        view.actionLabel = "Choose Server"
        view.actionKind = "open-server-selection"
    else if controller.status = "loading"
        view.status = "loading"
        view.availabilityStatus = "current"
    else
        view.status = "error"
        view.availabilityStatus = "current"
        view.title = "Saved couldn't load"
        view.message = "Check the server connection and try again."
        view.actionLabel = "Try again"
        view.actionKind = "retry-saved"
    end if
    return view
end function

sub PorticoSavedEmptyCopy(view as object, controller as object)
    if controller.selectedResourceId <> ""
        title = controller.selectedResourceTitle
        if title = "" then title = "This saved list"
        view.title = title + " is empty"
        view.message = "Media added to " + title + " appears here."
    else
        label = LCase(PorticoSavedTabLabel(controller.selectedTabId))
        view.title = "No " + label + " yet"
        if controller.selectedTabId = "watchlist" or controller.selectedTabId = "favorites"
            view.message = "Media added to " + label + " appears here."
        else
            view.message = "Your " + label + " will appear here."
        end if
    end if
end sub

function PorticoSavedWindowSize(controller as object) as integer
    if controller.selectedResourceId = "" and controller.selectedTabId <> "watchlist" and controller.selectedTabId <> "favorites" then return 6
    return 14
end function

function PorticoSavedBufferMaximum(controller as object) as integer
    if controller.selectedResourceId = "" and controller.selectedTabId <> "watchlist" and controller.selectedTabId <> "favorites" then return 100
    return 200
end function
