sub init()
    m.top.functionName = "PorticoSearchRun"
end sub

sub PorticoSearchRun()
    controller = {
        lastCommandSequence: 0,
        serverStatus: "not-connected",
        serverId: "",
        sessionGeneration: 0,
        reconnectRequestedGeneration: -1,
        query: "",
        queryRevision: 0,
        submittedQuery: "",
        status: "idle",
        groups: [],
        productContract: invalid,
        contractStatus: "idle",
        selectedGroupId: "",
        selectedSortId: "relevance",
        selectedDirection: "desc",
        selectedLibraryIds: [],
        selectedEntityKinds: [],
        recentQueries: [],
        historyStatus: "idle",
        historyRequested: false,
        clearHistoryRequested: false,
        cursorHistory: {},
        searchRequested: false,
        paginationGroupId: "",
        debounceTimer: invalid,
        quietRefresh: false
    }
    PorticoDiscoveryTaskAdopt(controller, PorticoDiscoveryTaskState("search"))
    PorticoBrowsePrepareArtworkDirectory("search")
    PorticoSearchPublish(controller, false)
    while true
        PorticoSearchHandleCommand(controller)
        PorticoSearchTick(controller)
        Sleep(250)
    end while
end sub

sub PorticoSearchHandleCommand(controller as object)
    command = invalid
    envelope = m.top.commandEnvelope
    if envelope <> invalid and Type(envelope) = "roAssociativeArray"
        previousGeneration = controller.viewerGeneration
        command = PorticoDiscoveryAcceptCommand(controller, envelope, "search")
        if command <> invalid and previousGeneration <> controller.viewerGeneration
            controller.groups = []
            controller.query = ""
            controller.queryRevision = 0
            controller.submittedQuery = ""
            controller.productContract = invalid
            controller.contractStatus = "idle"
            controller.selectedGroupId = ""
            controller.selectedSortId = "relevance"
            controller.selectedDirection = "desc"
            controller.selectedLibraryIds = []
            controller.selectedEntityKinds = []
            controller.recentQueries = []
            controller.historyStatus = "idle"
            controller.historyRequested = false
            controller.clearHistoryRequested = false
            controller.cursorHistory = {}
            controller.searchRequested = false
            controller.paginationGroupId = ""
            controller.debounceTimer = invalid
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
        PorticoSearchApplyServerState(controller, command)
    else if kind = "query-changed" or kind = "clear-search"
        PorticoSearchApplyQuery(controller, command, false)
    else if kind = "submit-search" or kind = "retry-search"
        PorticoSearchApplyQuery(controller, command, true)
    else if kind = "quiet-refresh-search"
        if controller.serverStatus = "online" and controller.contractStatus = "ready" and Len(controller.query.Trim()) >= 2
            controller.quietRefresh = true
            controller.searchRequested = true
        end if
    else if kind = "load-more"
        PorticoSearchRequestMore(controller, PorticoBrowseSearchGroupId(command.groupId))
    else if kind = "select-search-group"
        PorticoSearchSelectGroup(controller, command.groupId)
    else if kind = "cycle-search-sort"
        PorticoSearchCycleSort(controller)
    else if kind = "toggle-search-direction"
        PorticoSearchToggleDirection(controller)
    else if kind = "select-recent-search"
        PorticoSearchApplyRecent(controller, command.query)
    else if kind = "clear-search-history"
        if controller.serverStatus = "online"
            controller.clearHistoryRequested = true
            controller.historyStatus = "loading"
            PorticoSearchPublish(controller, false)
        end if
    else if kind = "sync-media-state"
        PorticoSearchSynchronizeMediaState(controller, command.mediaId, command.family, command.value = true)
    end if
end sub

sub PorticoSearchSelectGroup(controller as object, rawGroupId as dynamic)
    groupId = PorticoBrowseSearchGroupId(rawGroupId)
    if groupId <> "" and not PorticoSearchContractHasGroup(controller.productContract, groupId) then return
    controller.selectedGroupId = groupId
    controller.selectedSortId = PorticoSearchDefaultSort(controller.productContract, groupId)
    controller.selectedDirection = "desc"
    PorticoSearchRestart(controller)
end sub

sub PorticoSearchCycleSort(controller as object)
    sorts = PorticoSearchContractSorts(controller.productContract, controller.selectedGroupId)
    if sorts.count() = 0 then return
    current = -1
    for index = 0 to sorts.count() - 1
        if sorts[index].id = controller.selectedSortId then current = index
    end for
    nextIndex = current + 1
    if nextIndex >= sorts.count() then nextIndex = 0
    controller.selectedSortId = sorts[nextIndex].id
    PorticoSearchRestart(controller)
end sub

sub PorticoSearchToggleDirection(controller as object)
    if controller.selectedDirection = "asc" then controller.selectedDirection = "desc" else controller.selectedDirection = "asc"
    PorticoSearchRestart(controller)
end sub

sub PorticoSearchApplyRecent(controller as object, rawQuery as dynamic)
    query = PorticoBrowseSafeText(rawQuery, 120).Trim()
    if Len(query) < 2 then return
    controller.queryRevision = controller.queryRevision + 1
    controller.query = query
    PorticoSearchRestart(controller)
end sub

sub PorticoSearchRestart(controller as object)
    controller.paginationGroupId = ""
    controller.groups = []
    controller.cursorHistory = {}
    controller.submittedQuery = ""
    controller.searchRequested = false
    controller.debounceTimer = invalid
    if Len(controller.query.Trim()) < 2
        controller.status = "idle"
    else if controller.serverStatus = "online" and controller.contractStatus = "ready"
        controller.status = "loading"
        controller.searchRequested = true
    else
        controller.status = "error"
    end if
    PorticoSearchPublish(controller, false)
end sub

sub PorticoSearchSynchronizeMediaState(controller as object, rawMediaId as dynamic, rawFamily as dynamic, value as boolean)
    mediaId = PorticoBrowseSafeId(rawMediaId)
    family = LCase(PorticoBrowseSafeText(rawFamily, 16))
    if mediaId = "" or (family <> "watchlist" and family <> "favorite" and family <> "watched") then return
    PorticoBrowsePatchMediaState(controller.groups, mediaId, family, value, 0)
    PorticoSearchPublish(controller, false)
end sub

sub PorticoSearchApplyServerState(controller as object, command as object)
    serverId = PorticoBrowseSafeId(command.selectedServerId)
    status = LCase(PorticoHttpScalarString(command.serverStatus, "not-connected"))
    allowed = { online: true, connecting: true, offline: true, blocked: true, "identity-mismatch": true, incompatible: true, "permission-removed": true, selected: true, "not-connected": true }
    if allowed[status] <> true then status = "not-connected"
    changedServer = serverId <> controller.serverId
    controller.serverId = serverId
    controller.serverStatus = status
    if changedServer
        controller.groups = []
        controller.submittedQuery = ""
        controller.sessionGeneration = 0
        controller.reconnectRequestedGeneration = -1
        controller.productContract = invalid
        controller.contractStatus = "idle"
        controller.recentQueries = []
        controller.historyStatus = "idle"
        controller.cursorHistory = {}
    end if
    controller.searchRequested = false
    controller.paginationGroupId = ""
    controller.debounceTimer = invalid
    if serverId = "" or status = "not-connected"
        controller.groups = []
        controller.status = "idle"
    else if Len(controller.query.Trim()) < 2
        controller.status = "idle"
    else if status = "online"
        controller.status = "loading"
        if controller.contractStatus = "ready" then controller.searchRequested = true
    else
        controller.groups = []
        controller.status = "error"
    end if
    if serverId <> "" and status = "online" and controller.contractStatus <> "ready" then controller.contractStatus = "loading"
    if serverId <> "" and status = "online" and controller.historyStatus = "idle"
        controller.historyStatus = "loading"
        controller.historyRequested = true
    end if
    PorticoSearchPublish(controller, false)
end sub

sub PorticoSearchApplyQuery(controller as object, command as object, immediate as boolean)
    revision = PorticoHttpInteger(command.queryRevision, 0)
    if revision < controller.queryRevision then return
    controller.queryRevision = revision
    controller.query = PorticoBrowseSafeText(command.query, 120)
    controller.paginationGroupId = ""
    controller.groups = []
    controller.cursorHistory = {}
    controller.submittedQuery = ""
    controller.searchRequested = false
    controller.debounceTimer = invalid
    if Len(controller.query.Trim()) < 2
        controller.status = "idle"
    else if controller.serverId = "" or controller.serverStatus <> "online"
        controller.status = "error"
    else
        controller.status = "loading"
        if immediate
            controller.searchRequested = true
        else
            controller.debounceTimer = CreateObject("roTimespan")
            controller.debounceTimer.Mark()
        end if
    end if
    PorticoSearchPublish(controller, false)
end sub

sub PorticoSearchRequestMore(controller as object, groupId as string)
    if groupId = "" or controller.status <> "ready" then return
    group = PorticoSearchFindGroup(controller.groups, groupId)
    if group = invalid then return
    nextOffset = PorticoHttpInteger(group.windowOffset, 0) + 4
    if nextOffset < group.items.count()
        group.windowOffset = nextOffset
        PorticoSearchPublish(controller, false)
    else if group.hasMore = true and group.nextCursor <> "" and controller.serverStatus = "online"
        controller.paginationGroupId = groupId
        PorticoSearchPublish(controller, false)
    end if
end sub

sub PorticoSearchTick(controller as object)
    if controller.serverStatus <> "online" then return
    if controller.contractStatus = "loading"
        PorticoSearchLoadContract(controller)
        return
    end if
    if controller.clearHistoryRequested
        PorticoSearchClearHistory(controller)
        return
    end if
    if controller.historyRequested
        PorticoSearchLoadHistory(controller)
        return
    end if
    if controller.debounceTimer <> invalid and controller.debounceTimer.TotalMilliseconds() >= 300
        controller.debounceTimer = invalid
        controller.searchRequested = true
    end if
    if controller.paginationGroupId <> ""
        PorticoSearchLoadMore(controller)
    else if controller.searchRequested
        PorticoSearchLoad(controller)
    end if
end sub

sub PorticoSearchLoadContract(controller as object)
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid
        controller.contractStatus = "error"
        PorticoSearchFailed(controller, invalid, true)
        return
    end if
    result = PorticoDiscoveryRequest(controller, session, "GET", "/api/product-contract", "")
    if result.interrupted then return
    if not result.ok or not PorticoProductContractValidateLive(result.data).ok
        controller.contractStatus = "error"
        controller.status = "error"
        PorticoSearchPublish(controller, result.status = 401)
        return
    end if
    controller.productContract = result.data
    controller.contractStatus = "ready"
    if controller.selectedSortId = "" then controller.selectedSortId = PorticoSearchDefaultSort(controller.productContract, controller.selectedGroupId)
    if Len(controller.query.Trim()) >= 2
        controller.status = "loading"
        controller.searchRequested = true
    end if
    PorticoSearchPublish(controller, false)
end sub

sub PorticoSearchLoadHistory(controller as object)
    controller.historyRequested = false
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid
        controller.historyStatus = "unavailable"
        PorticoSearchPublish(controller, true)
        return
    end if
    result = PorticoDiscoveryRequest(controller, session, "GET", "/api/search/history", "")
    if result.interrupted
        controller.historyRequested = true
        return
    end if
    if not result.ok
        controller.historyStatus = "unavailable"
        PorticoSearchPublish(controller, result.status = 401)
        return
    end if
    controller.recentQueries = PorticoSearchHistoryQueries(result.data)
    controller.historyStatus = "ready"
    PorticoSearchPublish(controller, false)
end sub

sub PorticoSearchClearHistory(controller as object)
    controller.clearHistoryRequested = false
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid
        controller.historyStatus = "unavailable"
        PorticoSearchPublish(controller, true)
        return
    end if
    result = PorticoDiscoveryRequest(controller, session, "DELETE", "/api/search/history", "")
    if result.interrupted
        controller.clearHistoryRequested = true
        return
    end if
    if result.ok
        controller.recentQueries = []
        controller.historyStatus = "ready"
    else
        controller.historyStatus = "unavailable"
    end if
    PorticoSearchPublish(controller, result.status = 401)
end sub

sub PorticoSearchLoad(controller as object)
    controller.searchRequested = false
    preservedOffsets = {}
    if controller.quietRefresh
        for each currentGroup in controller.groups
            if currentGroup <> invalid and Type(currentGroup) = "roAssociativeArray" then preservedOffsets[currentGroup.id] = PorticoHttpInteger(currentGroup.windowOffset, 0)
        end for
    end if
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid
        PorticoSearchFailed(controller, invalid, true)
        return
    end if
    controller.sessionGeneration = session.generation
    query = controller.query.Trim()
    body = PorticoSearchRequestBody(controller, query, "", "")
    result = PorticoDiscoveryRequest(controller, session, "POST", "/api/search", body)
    if result.interrupted then return
    if not result.ok
        PorticoSearchFailed(controller, result, false)
        return
    end if
    normalized = PorticoBrowseSearchResponse(result.data)
    if normalized = invalid or LCase(normalized.query) <> LCase(query)
        if controller.quietRefresh and controller.groups.Count() > 0
            controller.status = "ready"
        else
            controller.groups = []
            controller.status = "error"
        end if
        controller.quietRefresh = false
        PorticoSearchPublish(controller, false)
        return
    end if
    controller.groups = PorticoSearchContractOrderGroups(controller.productContract, normalized.groups)
    controller.cursorHistory = {}
    for each group in controller.groups
        if preservedOffsets[group.id] <> invalid then group.windowOffset = preservedOffsets[group.id]
        group.status = "ready"
        group.errorMessageId = ""
        if group.items.count() = 0 then group.status = "empty"
        if group.nextCursor <> "" then PorticoSearchRememberCursor(controller, group.id, group.nextCursor)
    end for
    controller.submittedQuery = query
    if controller.groups.count() > 0 then controller.status = "ready" else controller.status = "empty"
    controller.reconnectRequestedGeneration = -1
    controller.quietRefresh = false
    controller.historyRequested = true
    PorticoSearchPublish(controller, false)
    PorticoBrowseMaterializeArtwork(controller, session, "search", normalized.artworkJobs)
    PorticoSearchPublish(controller, false)
end sub

sub PorticoSearchLoadMore(controller as object)
    groupId = controller.paginationGroupId
    controller.paginationGroupId = ""
    group = PorticoSearchFindGroup(controller.groups, groupId)
    if group = invalid or group.nextCursor = ""
        controller.status = "ready"
        PorticoSearchPublish(controller, false)
        return
    end if
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid
        PorticoSearchFailed(controller, invalid, true)
        return
    end if
    controller.sessionGeneration = session.generation
    cursor = group.nextCursor
    if PorticoSearchCursorSeen(controller, groupId, cursor, true)
        group.hasMore = false
        group.nextCursor = ""
        group.status = "ready"
        group.errorMessageId = ""
        controller.status = "ready"
        PorticoSearchPublish(controller, false)
        return
    end if
    body = PorticoSearchRequestBody(controller, controller.submittedQuery, groupId, cursor)
    result = PorticoDiscoveryRequest(controller, session, "POST", "/api/search", body)
    if result.interrupted then return
    if not result.ok
        ' A page failure belongs to its group. Healthy groups and already loaded
        ' results remain usable.
        group.status = "error"
        group.errorMessageId = "search.more-failed"
        controller.status = "ready"
        PorticoSearchPublish(controller, result.status = 401)
        return
    end if
    normalized = PorticoBrowseSearchResponse(result.data)
    incoming = invalid
    if normalized <> invalid then incoming = PorticoSearchFindGroup(normalized.groups, groupId)
    if incoming = invalid
        group.hasMore = false
        group.nextCursor = ""
        group.status = "empty"
    else
        previousCount = group.items.count()
        for each item in incoming.items
            if not PorticoBrowseContainsId(group.items, item.id) then group.items.push(item)
        end for
        group.hasMore = incoming.hasMore
        group.nextCursor = incoming.nextCursor
        group.status = "ready"
        group.errorMessageId = ""
        if group.nextCursor <> "" and PorticoSearchCursorSeen(controller, groupId, group.nextCursor, false)
            group.hasMore = false
            group.nextCursor = ""
            group.errorMessageId = "search.more-failed"
        end if
        if group.items.count() > previousCount then group.windowOffset = previousCount
        PorticoSearchPublish(controller, false)
        PorticoBrowseMaterializeArtwork(controller, session, "search", normalized.artworkJobs)
    end if
    controller.status = "ready"
    PorticoSearchPublish(controller, false)
end sub

sub PorticoSearchFailed(controller as object, result as dynamic, missingSession as boolean)
    status = 0
    if result <> invalid then status = result.status
    if controller.quietRefresh and controller.groups.Count() > 0
        controller.status = "ready"
    else
        controller.groups = []
        controller.status = "error"
    end if
    controller.quietRefresh = false
    reconnect = missingSession or status = 401
    requestReconnect = false
    if reconnect and controller.reconnectRequestedGeneration <> controller.sessionGeneration
        controller.reconnectRequestedGeneration = controller.sessionGeneration
        requestReconnect = true
    end if
    PorticoSearchPublish(controller, requestReconnect)
end sub

function PorticoSearchFindGroup(groups as dynamic, groupId as string) as dynamic
    if groups = invalid or GetInterface(groups, "ifArray") = invalid then return invalid
    for each group in groups
        if group <> invalid and Type(group) = "roAssociativeArray" and group.id = groupId then return group
    end for
    return invalid
end function

sub PorticoSearchPublish(controller as object, serverReconnectRequired as boolean)
    viewState = {
        status: controller.status,
        query: controller.query,
        queryRevision: controller.queryRevision,
        submittedQuery: controller.submittedQuery,
        groups: PorticoBrowseSearchProjection(controller.groups),
        controls: PorticoSearchControlProjection(controller),
        recentQueries: PorticoSearchCloneStrings(controller.recentQueries, 12, 120),
        historyStatus: controller.historyStatus,
        messageId: PorticoSearchStateMessageId(controller)
    }
    projection = { searchViewState: viewState, searchServerReconnectRequired: serverReconnectRequired }
    if not controller.envelopeMode then m.top.projection = projection
    envelope = PorticoDiscoveryResultEnvelope(controller, projection)
    if envelope <> invalid then m.top.projectionEnvelope = envelope
end sub

function PorticoSearchRequestBody(controller as object, query as string, groupId as string, cursor as string) as object
    body = {query: query, limit: 12, sort: controller.selectedSortId, direction: controller.selectedDirection}
    if groupId <> "" then body.group = groupId else if controller.selectedGroupId <> "" then body.group = controller.selectedGroupId
    if cursor <> "" then body.cursor = cursor
    if controller.selectedLibraryIds.count() > 0 then body.libraryIds = PorticoSearchCloneStrings(controller.selectedLibraryIds, 32, 128)
    if controller.selectedEntityKinds.count() > 0 then body.entityKinds = PorticoSearchCloneStrings(controller.selectedEntityKinds, 32, 80)
    return body
end function

function PorticoSearchContractGroups(contract as dynamic) as object
    result = []
    if not PorticoProductContractValidateLive(contract).ok then return result
    if contract.search.groups = invalid or GetInterface(contract.search.groups, "ifArray") = invalid then return result
    order = contract.search.groupOrder
    if order = invalid or GetInterface(order, "ifArray") = invalid then order = []
    for each rawId in order
        id = PorticoBrowseSearchGroupId(rawId)
        for each rawGroup in contract.search.groups
            if rawGroup <> invalid and Type(rawGroup) = "roAssociativeArray" and PorticoBrowseSearchGroupId(rawGroup.id) = id
                title = PorticoBrowseSafeText(rawGroup.title, 80)
                if id <> "" and title <> "" then result.push({id: id, title: title, sorts: PorticoSearchSafeSortIds(rawGroup.sorts)})
            end if
        end for
    end for
    return result
end function

function PorticoSearchSafeSortIds(values as dynamic) as object
    result = []
    if values = invalid or GetInterface(values, "ifArray") = invalid then return result
    for each raw in values
        id = PorticoBrowseSafeId(raw)
        if id <> "" and not PorticoBrowseArrayHasText(result, id) then result.push(id)
    end for
    return result
end function

function PorticoSearchContractHasGroup(contract as dynamic, groupId as string) as boolean
    for each group in PorticoSearchContractGroups(contract)
        if group.id = groupId then return true
    end for
    return false
end function

function PorticoSearchContractSorts(contract as dynamic, groupId as string) as object
    ids = []
    groups = PorticoSearchContractGroups(contract)
    if groupId <> ""
        for each group in groups
            if group.id = groupId then ids = group.sorts
        end for
    else
        ids = ["relevance", "title", "releaseYear", "dateAdded"]
    end if
    labels = {relevance: "Relevance", title: "Title", releaseYear: "Release year", dateAdded: "Date added"}
    result = []
    for each id in ids
        if labels[id] <> invalid then result.push({id: id, label: labels[id]})
    end for
    return result
end function

function PorticoSearchDefaultSort(contract as dynamic, groupId as string) as string
    sorts = PorticoSearchContractSorts(contract, groupId)
    if sorts.count() > 0 then return sorts[0].id
    return "relevance"
end function

function PorticoSearchContractOrderGroups(contract as dynamic, source as object) as object
    result = []
    contractGroups = PorticoSearchContractGroups(contract)
    for each descriptor in contractGroups
        group = PorticoSearchFindGroup(source, descriptor.id)
        if group <> invalid
            group.title = descriptor.title
            result.push(group)
        end if
    end for
    return result
end function

function PorticoSearchControlProjection(controller as object) as object
    groups = [{id: "", label: "All", selected: controller.selectedGroupId = ""}]
    for each group in PorticoSearchContractGroups(controller.productContract)
        groups.push({id: group.id, label: group.title, selected: group.id = controller.selectedGroupId})
    end for
    sorts = []
    for each sort in PorticoSearchContractSorts(controller.productContract, controller.selectedGroupId)
        sorts.push({id: sort.id, label: sort.label, selected: sort.id = controller.selectedSortId})
    end for
    return {
        groups: groups,
        sorts: sorts,
        selectedGroupId: controller.selectedGroupId,
        selectedSortId: controller.selectedSortId,
        direction: controller.selectedDirection
    }
end function

function PorticoSearchHistoryQueries(data as dynamic) as object
    result = []
    if data = invalid or Type(data) <> "roAssociativeArray" then return result
    values = data.items
    if values = invalid then values = data.queries
    if values = invalid or GetInterface(values, "ifArray") = invalid then return result
    for each raw in values
        query = ""
        if raw <> invalid and Type(raw) = "roAssociativeArray" then query = PorticoBrowseSafeText(raw.query, 120) else query = PorticoBrowseSafeText(raw, 120)
        if query <> "" and not PorticoBrowseArrayHasText(result, query) and result.count() < 12 then result.push(query)
    end for
    return result
end function

function PorticoSearchCloneStrings(values as dynamic, maximum as integer, maximumLength as integer) as object
    result = []
    if values = invalid or GetInterface(values, "ifArray") = invalid then return result
    for each raw in values
        if result.count() >= maximum then exit for
        value = PorticoBrowseSafeText(raw, maximumLength)
        if value <> "" then result.push(value)
    end for
    return result
end function

function PorticoSearchCursorSeen(controller as object, groupId as string, cursor as string, remember as boolean) as boolean
    if cursor = "" then return false
    key = groupId + "|" + cursor
    seen = controller.cursorHistory[key] = true
    if remember and not seen
        if controller.cursorHistory.count() >= 256 then controller.cursorHistory = {}
        controller.cursorHistory[key] = true
    end if
    return seen
end function

sub PorticoSearchRememberCursor(controller as object, groupId as string, cursor as string)
    PorticoSearchCursorSeen(controller, groupId, cursor, true)
end sub

function PorticoSearchStateMessageId(controller as object) as string
    if controller.contractStatus = "error" then return "search.load-failed"
    if controller.status = "loading" then return "search.loading"
    if controller.status = "empty" then return "search.no-results"
    if controller.status = "error"
        if controller.serverStatus <> "online" then return "search.offline"
        return "search.load-failed"
    end if
    if controller.status = "idle"
        if controller.recentQueries.count() > 0 then return "search.recent-title"
        return "search.start-title"
    end if
    return ""
end function
