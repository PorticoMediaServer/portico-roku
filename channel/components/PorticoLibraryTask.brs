sub init()
    m.top.functionName = "PorticoLibraryRun"
end sub

sub PorticoLibraryRun()
    controller = {
        lastCommandSequence: 0,
        serverStatus: "not-connected",
        serverId: "",
        serverName: "",
        sessionGeneration: 0,
        cacheBinding: "",
        reconnectRequestedGeneration: -1,
        requestedLibraryId: "",
        libraries: [],
        library: invalid,
        capabilities: invalid,
        selectedTabId: "",
        selectedFacetId: "",
        selectedResourceId: "",
        selectedResourceTitle: "",
        filterUnplayed: false,
        appliedFilters: [],
        draftFilters: [],
        filterDraftOpen: false,
        selectedSortIndex: -1,
        selectedSortDirection: "",
        seekPrefix: "",
        pivotPreferences: {},
        cursorHistory: {},
        savedViewStatus: "idle",
        activeSavedViewId: "",
        viewMode: "grid",
        facetQueries: {},
        page: invalid,
        windowOffset: 0,
        status: "idle",
        requestKind: "",
        quietRefresh: false,
        quietWindowOffset: 0
    }
    PorticoDiscoveryTaskAdopt(controller, PorticoDiscoveryTaskState("library"))
    PorticoBrowsePrepareArtworkDirectory("library")
    PorticoLibraryPublish(controller, false)
    while true
        PorticoLibraryHandleCommand(controller)
        PorticoLibraryTick(controller)
        Sleep(250)
    end while
end sub

sub PorticoLibraryHandleCommand(controller as object)
    command = invalid
    envelope = m.top.commandEnvelope
    if envelope <> invalid and Type(envelope) = "roAssociativeArray"
        previousGeneration = controller.viewerGeneration
        command = PorticoDiscoveryAcceptCommand(controller, envelope, "library")
        if command <> invalid and previousGeneration <> controller.viewerGeneration
            PorticoLibraryResetRuntime(controller)
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
        PorticoLibraryApplyServerState(controller, command)
    else if kind = "open-library"
        PorticoLibraryOpenRequested(controller, PorticoBrowseSafeId(command.libraryId))
    else if kind = "select-tab"
        PorticoLibrarySelectTab(controller, PorticoBrowseSafeId(command.tabId))
    else if kind = "select-facet"
        PorticoLibrarySelectFacet(controller, PorticoBrowseSafeId(command.facetId))
    else if kind = "select-resource"
        PorticoLibrarySelectResource(controller, PorticoBrowseSafeId(command.resourceId))
    else if kind = "select-library"
        PorticoLibraryOpenRequested(controller, PorticoBrowseSafeId(command.libraryId))
    else if kind = "clear-selection"
        controller.selectedFacetId = ""
        controller.selectedResourceId = ""
        controller.selectedResourceTitle = ""
        controller.windowOffset = 0
        controller.savedViewStatus = "idle"
        if controller.library <> invalid and controller.selectedTabId <> "" and controller.serverStatus = "online"
            controller.status = "loading"
            controller.requestKind = "page"
            PorticoLibraryPublish(controller, false)
        end if
    else if kind = "toggle-filter" or kind = "open-library-filters"
        controller.draftFilters = PorticoBrowseClone(controller.appliedFilters)
        controller.filterDraftOpen = true
        PorticoLibraryPublish(controller, false)
    else if kind = "update-library-filter-draft"
        PorticoLibraryUpdateFilterDraft(controller, command)
    else if kind = "apply-library-filters"
        PorticoLibraryUpdateFilterDraft(controller, command)
        PorticoLibraryApplyFilterDraft(controller)
    else if kind = "cancel-library-filters"
        controller.draftFilters = []
        controller.filterDraftOpen = false
        PorticoLibraryPublish(controller, false)
    else if kind = "cycle-sort"
        PorticoLibraryCycleSort(controller)
    else if kind = "toggle-sort-direction"
        PorticoLibraryToggleSortDirection(controller)
    else if kind = "alphabet-seek"
        PorticoLibraryAlphabetSeek(controller, command.prefix)
    else if kind = "save-library-view"
        PorticoLibrarySaveView(controller, command.title)
    else if kind = "launch-saved-view"
        PorticoLibraryLaunchSavedView(controller, command.savedViewId)
    else if kind = "toggle-view"
        if controller.viewMode = "grid" then controller.viewMode = "list" else controller.viewMode = "grid"
        controller.savedViewStatus = "idle"
        controller.windowOffset = 0
        if controller.page <> invalid and (controller.page.presentation = "grid" or controller.page.presentation = "list") then controller.page.presentation = controller.viewMode
        PorticoLibraryPublish(controller, false)
    else if kind = "load-more"
        PorticoLibraryRequestMore(controller)
    else if kind = "retry-library"
        if controller.serverStatus = "online"
            controller.status = "loading"
            if controller.library = invalid then controller.requestKind = "catalog" else controller.requestKind = "page"
            PorticoLibraryPublish(controller, false)
        end if
    else if kind = "quiet-refresh-library"
        if controller.serverStatus = "online" and controller.library <> invalid and controller.capabilities <> invalid
            controller.quietRefresh = true
            controller.quietWindowOffset = controller.windowOffset
            controller.requestKind = "page"
        end if
    else if kind = "sync-media-state"
        PorticoLibrarySynchronizeMediaState(controller, command.mediaId, command.family, command.value = true)
    else if kind = "invalidate-saved-resources"
        PorticoLibraryInvalidateSavedResources(controller)
    else if kind = "invalidate-dvr-schedule"
        PorticoLibraryInvalidateDvrSchedule(controller)
    end if
end sub

sub PorticoLibraryUpdateFilterDraft(controller as object, command as object)
    if not controller.filterDraftOpen or controller.capabilities = invalid then return
    fieldId = PorticoBrowseSafeId(command.fieldId)
    operatorId = PorticoBrowseSafeId(command.operatorId)
    value = PorticoBrowseSafeText(command.value, 200)
    field = PorticoLibraryFindField(controller.capabilities.fields, fieldId)
    if field = invalid or not PorticoBrowseArrayHasText(field.operators, operatorId) or value = "" then return
    predicate = {field: fieldId, operator: operatorId, value: value}
    replaced = false
    for index = 0 to controller.draftFilters.count() - 1
        if controller.draftFilters[index].field = fieldId
            controller.draftFilters[index] = predicate
            replaced = true
        end if
    end for
    if not replaced and controller.draftFilters.count() < controller.capabilities.queryLimits.maximumClauses then controller.draftFilters.push(predicate)
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryApplyFilterDraft(controller as object)
    if not controller.filterDraftOpen then return
    controller.appliedFilters = PorticoBrowseClone(controller.draftFilters)
    controller.filterDraftOpen = false
    controller.savedViewStatus = "idle"
    controller.seekPrefix = ""
    PorticoLibraryRememberPivot(controller)
    PorticoLibraryRestartPage(controller)
end sub

sub PorticoLibraryToggleSortDirection(controller as object)
    sorts = PorticoLibraryAvailableSorts(controller)
    if controller.selectedSortIndex < 0 or controller.selectedSortIndex >= sorts.count() then return
    selected = sorts[controller.selectedSortIndex]
    if not PorticoBrowseArrayHasText(selected.directions, "asc") or not PorticoBrowseArrayHasText(selected.directions, "desc") then return
    if controller.selectedSortDirection = "asc" then controller.selectedSortDirection = "desc" else controller.selectedSortDirection = "asc"
    controller.savedViewStatus = "idle"
    controller.seekPrefix = ""
    PorticoLibraryRememberPivot(controller)
    PorticoLibraryRestartPage(controller)
end sub

sub PorticoLibraryAlphabetSeek(controller as object, rawPrefix as dynamic)
    prefix = UCase(PorticoBrowseSafeText(rawPrefix, 1))
    if prefix <> "#" and Instr(1, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", prefix) = 0 then return
    controller.seekPrefix = prefix
    controller.savedViewStatus = "idle"
    PorticoLibraryRememberPivot(controller)
    PorticoLibraryRestartPage(controller)
end sub

sub PorticoLibraryRestartPage(controller as object)
    controller.page = invalid
    controller.windowOffset = 0
    controller.cursorHistory = {}
    if controller.serverStatus = "online"
        controller.status = "loading"
        controller.requestKind = "page"
    else
        controller.status = "error"
    end if
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibrarySaveView(controller as object, rawTitle as dynamic)
    if controller.library = invalid or controller.capabilities = invalid or not PorticoBrowseArrayHasText(controller.capabilities.actions, "saved-view.create") then return
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid then return
    title = PorticoBrowseSafeText(rawTitle, 100)
    pivot = PorticoLibraryFindPivot(controller.capabilities.pivots, controller.selectedTabId)
    if pivot = invalid then return
    if title = "" then title = controller.library.name + " · " + pivot.label
    body = {title: title, libraryId: controller.library.id, pivot: pivot.id, presentation: {fields: pivot.presentationFields}, sort: []}
    if controller.appliedFilters.count() = 1 then body.query = PorticoBrowseClone(controller.appliedFilters[0])
    if controller.appliedFilters.count() > 1 then body.query = {all: PorticoBrowseClone(controller.appliedFilters)}
    sorts = PorticoLibraryAvailableSorts(controller)
    if controller.selectedSortIndex >= 0 and controller.selectedSortIndex < sorts.count()
        sort = sorts[controller.selectedSortIndex]
        direction = controller.selectedSortDirection
        if direction = "" then direction = sort.direction
        body.sort = [{field: sort.id, direction: direction}]
    else
        body.sort = PorticoBrowseClone(pivot.defaultSort)
    end if
    controller.savedViewStatus = "saving"
    PorticoLibraryPublish(controller, false)
    result = PorticoDiscoveryRequest(controller, session, "POST", "/api/saved-views", body)
    if result.interrupted then return
    if result.ok then controller.savedViewStatus = "saved" else controller.savedViewStatus = "error"
    PorticoLibraryPublish(controller, result.status = 401)
end sub

sub PorticoLibraryLaunchSavedView(controller as object, rawId as dynamic)
    id = PorticoBrowseSafeId(rawId)
    if id = "" then return
    controller.activeSavedViewId = id
    controller.savedViewStatus = "idle"
    controller.selectedResourceId = ""
    controller.selectedFacetId = ""
    controller.page = invalid
    controller.windowOffset = 0
    controller.cursorHistory = {}
    controller.status = "loading"
    controller.requestKind = "page"
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryInvalidateSavedResources(controller as object)
    PorticoDiscoveryCacheRemoveViewer("library-cache", controller)
    if controller.serverStatus <> "online" or controller.library = invalid then return
    pivot = PorticoLibraryFindPivot(controller.capabilities.pivots, controller.selectedTabId)
    if pivot = invalid or (pivot.id <> "collections" and pivot.id <> "playlists") then return
    controller.page = invalid
    controller.windowOffset = 0
    controller.status = "loading"
    controller.requestKind = "page"
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryInvalidateDvrSchedule(controller as object)
    PorticoDiscoveryCacheRemoveViewer("library-cache", controller)
    if controller.serverStatus <> "online" or controller.library = invalid or controller.selectedTabId <> "schedule" then return
    controller.page = invalid
    controller.windowOffset = 0
    controller.status = "loading"
    controller.requestKind = "page"
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibrarySynchronizeMediaState(controller as object, rawMediaId as dynamic, rawFamily as dynamic, value as boolean)
    mediaId = PorticoBrowseSafeId(rawMediaId)
    family = LCase(PorticoBrowseSafeText(rawFamily, 16))
    if mediaId = "" or (family <> "watchlist" and family <> "favorite" and family <> "watched") then return
    PorticoBrowsePatchMediaState(controller.page, mediaId, family, value, 0)
    PorticoLibraryPersistCache(controller)
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryApplyServerState(controller as object, command as object)
    serverId = PorticoBrowseSafeId(command.selectedServerId)
    status = LCase(PorticoHttpScalarString(command.serverStatus, "not-connected"))
    allowed = { online: true, connecting: true, offline: true, blocked: true, "identity-mismatch": true, incompatible: true, "permission-removed": true, selected: true, "not-connected": true }
    if allowed[status] <> true then status = "not-connected"
    changedServer = serverId <> controller.serverId
    controller.serverId = serverId
    controller.serverName = PorticoBrowseSafeText(command.selectedServerName, 100)
    controller.serverStatus = status
    controller.requestKind = ""
    if changedServer
        PorticoLibraryResetRuntime(controller)
        controller.serverId = serverId
        controller.serverName = PorticoBrowseSafeText(command.selectedServerName, 100)
        controller.serverStatus = status
    end if
    if serverId = "" or status = "not-connected"
        PorticoDiscoveryCacheRemoveViewer("library-cache", controller)
        PorticoLibraryResetRuntime(controller)
        controller.serverId = ""
        controller.serverName = ""
    else
        if controller.page = invalid then PorticoLibraryRestoreCache(controller)
        if status = "online"
            controller.status = "loading"
            controller.requestKind = "catalog"
        else if status = "permission-removed" or status = "identity-mismatch" or status = "incompatible"
            PorticoDiscoveryCacheRemoveViewer("library-cache", controller)
            controller.page = invalid
            controller.status = "error"
        else if controller.page <> invalid
            controller.status = "stale"
        else
            controller.status = "error"
        end if
    end if
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryOpenRequested(controller as object, libraryId as string)
    if libraryId <> controller.requestedLibraryId
        controller.requestedLibraryId = libraryId
        controller.library = invalid
        controller.capabilities = invalid
        controller.selectedTabId = ""
        controller.selectedFacetId = ""
        controller.selectedResourceId = ""
        controller.selectedResourceTitle = ""
        controller.filterUnplayed = false
        controller.selectedSortIndex = -1
        controller.viewMode = "grid"
        controller.facetQueries = {}
        controller.page = invalid
        controller.windowOffset = 0
        controller.activeSavedViewId = ""
        controller.savedViewStatus = "idle"
    end if
    if controller.serverStatus = "online"
        controller.status = "loading"
        controller.requestKind = "catalog"
    else if controller.page <> invalid
        controller.status = "stale"
    else
        controller.status = "error"
    end if
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibrarySelectTab(controller as object, tabId as string)
    PorticoLibraryRememberPivot(controller)
    if controller.capabilities = invalid or PorticoLibraryFindPivot(controller.capabilities.pivots, tabId) = invalid then return
    controller.selectedTabId = tabId
    controller.selectedFacetId = ""
    controller.selectedResourceId = ""
    controller.selectedResourceTitle = ""
    controller.filterUnplayed = false
    controller.appliedFilters = []
    controller.draftFilters = []
    controller.filterDraftOpen = false
    controller.selectedSortIndex = -1
    controller.selectedSortDirection = ""
    controller.seekPrefix = ""
    controller.viewMode = "grid"
    controller.facetQueries = {}
    controller.page = invalid
    controller.windowOffset = 0
    controller.cursorHistory = {}
    controller.activeSavedViewId = ""
    controller.savedViewStatus = "idle"
    PorticoLibraryRestorePivot(controller)
    if controller.serverStatus = "online"
        controller.status = "loading"
        controller.requestKind = "page"
    else
        controller.status = "error"
    end if
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryToggleFilter(controller as object)
    if not PorticoLibraryCanFilter(controller) then return
    controller.filterUnplayed = not controller.filterUnplayed
    controller.page = invalid
    controller.windowOffset = 0
    controller.status = "loading"
    controller.requestKind = "page"
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryCycleSort(controller as object)
    sorts = PorticoLibraryAvailableSorts(controller)
    if sorts.count() = 0 then return
    controller.selectedSortIndex = controller.selectedSortIndex + 1
    if controller.selectedSortIndex >= sorts.count() then controller.selectedSortIndex = -1
    controller.selectedSortDirection = ""
    controller.savedViewStatus = "idle"
    if controller.selectedSortIndex >= 0 then controller.selectedSortDirection = sorts[controller.selectedSortIndex].direction
    controller.seekPrefix = ""
    PorticoLibraryRememberPivot(controller)
    controller.page = invalid
    controller.windowOffset = 0
    controller.status = "loading"
    controller.requestKind = "page"
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibrarySelectResource(controller as object, resourceId as string)
    if resourceId = "" or controller.page = invalid or controller.serverStatus <> "online" then return
    if controller.selectedTabId <> "collections" and controller.selectedTabId <> "playlists" then return
    title = ""
    if controller.page.items <> invalid and GetInterface(controller.page.items, "ifArray") <> invalid
        for each item in controller.page.items
            if item <> invalid and item.id = resourceId
                title = PorticoBrowseSafeText(item.title, 140)
                exit for
            end if
        end for
    end if
    controller.selectedResourceId = resourceId
    controller.savedViewStatus = "idle"
    controller.activeSavedViewId = ""
    controller.selectedResourceTitle = title
    controller.selectedFacetId = ""
    controller.page = invalid
    controller.windowOffset = 0
    controller.status = "loading"
    controller.requestKind = "page"
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibrarySelectFacet(controller as object, facetId as string)
    query = controller.facetQueries[facetId]
    if query = invalid or controller.serverStatus <> "online" then return
    controller.selectedFacetId = facetId
    controller.savedViewStatus = "idle"
    controller.activeSavedViewId = ""
    controller.selectedResourceId = ""
    controller.selectedResourceTitle = ""
    controller.filterUnplayed = false
    controller.selectedSortIndex = -1
    controller.viewMode = "grid"
    controller.page = invalid
    controller.windowOffset = 0
    controller.status = "loading"
    controller.requestKind = "page"
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryRequestMore(controller as object)
    if controller.page = invalid or controller.status <> "ready" then return
    bufferedCount = PorticoLibraryPageCount(controller.page)
    currentWindow = PorticoLibraryPageWindow(controller.page, controller.windowOffset)
    visibleCount = PorticoLibraryWindowVisibleCount(currentWindow, controller.page.presentation)
    if visibleCount > 0 and controller.windowOffset + visibleCount < bufferedCount
        controller.windowOffset = controller.windowOffset + visibleCount
        PorticoLibraryPublish(controller, false)
    else if controller.page.hasMore = true and controller.page.nextCursor <> "" and controller.serverStatus = "online"
        controller.status = "loading"
        controller.requestKind = "more"
        PorticoLibraryPublish(controller, false)
    end if
end sub

sub PorticoLibraryTick(controller as object)
    if controller.serverStatus <> "online" or controller.requestKind = "" then return
    requestKind = controller.requestKind
    controller.requestKind = ""
    if requestKind = "catalog"
        PorticoLibraryLoadCatalog(controller)
    else
        PorticoLibraryLoadPage(controller, requestKind = "more")
    end if
end sub

sub PorticoLibraryLoadCatalog(controller as object)
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid
        PorticoLibraryFailed(controller, invalid, true)
        return
    end if
    controller.sessionGeneration = session.generation
    controller.cacheBinding = session.cacheBinding
    result = PorticoDiscoveryRequest(controller, session, "GET", "/api/libraries", "")
    if result.interrupted then return
    if not result.ok
        PorticoLibraryFailed(controller, result, false)
        return
    end if
    libraries = PorticoBrowseLibraryCatalog(result.data)
    if libraries = invalid or libraries.count() = 0
        controller.libraries = []
        controller.library = invalid
        controller.page = invalid
        controller.status = "empty"
        PorticoLibraryPublish(controller, false)
        return
    end if
    controller.libraries = libraries
    if controller.requestedLibraryId = ""
        controller.library = invalid
        controller.page = invalid
        controller.status = "ready"
        PorticoLibraryPublish(controller, false)
        return
    end if
    library = PorticoLibraryFindLibrary(libraries, controller.requestedLibraryId)
    if library = invalid then library = libraries[0]
    controller.library = library
    controller.requestedLibraryId = library.id
    capabilitiesResult = PorticoDiscoveryRequest(controller, session, "GET", "/api/libraries/" + library.id + "/browse-capabilities", "")
    if capabilitiesResult.interrupted then return
    if not capabilitiesResult.ok
        PorticoLibraryFailed(controller, capabilitiesResult, false)
        return
    end if
    capabilities = PorticoBrowseLibraryCapabilities(capabilitiesResult.data)
    if capabilities = invalid
        controller.status = "error"
        controller.page = invalid
        PorticoLibraryPublish(controller, false)
        return
    end if
    controller.capabilities = capabilities
    if PorticoLibraryFindPivot(capabilities.pivots, controller.selectedTabId) = invalid
        controller.selectedTabId = PorticoLibraryDefaultPivot(capabilities.pivots)
    end if
    controller.selectedFacetId = ""
    controller.selectedResourceId = ""
    controller.selectedResourceTitle = ""
    controller.facetQueries = {}
    controller.windowOffset = 0
    controller.requestKind = "page"
end sub

sub PorticoLibraryLoadPage(controller as object, append as boolean)
    if controller.library = invalid or controller.capabilities = invalid then return
    session = PorticoDiscoverySessionForController(controller)
    if session = invalid
        PorticoLibraryFailed(controller, invalid, true)
        return
    end if
    controller.sessionGeneration = session.generation
    controller.cacheBinding = session.cacheBinding
    pivot = PorticoLibraryFindPivot(controller.capabilities.pivots, controller.selectedTabId)
    if pivot = invalid
        controller.status = "error"
        PorticoLibraryPublish(controller, false)
        return
    end if
    cursor = ""
    if append and controller.page <> invalid then cursor = PorticoBrowseSafeCursor(controller.page.nextCursor)
    if append and cursor <> ""
        cursorKey = controller.selectedTabId + "|" + cursor
        if controller.cursorHistory[cursorKey] = true
            controller.page.hasMore = false
            controller.page.nextCursor = ""
            controller.status = "stale"
            PorticoLibraryPublish(controller, false)
            return
        end if
        if controller.cursorHistory.count() >= 512 then controller.cursorHistory = {}
        controller.cursorHistory[cursorKey] = true
    end if
    artworkJobs = []
    normalized = invalid
    result = invalid
    if controller.activeSavedViewId <> ""
        path = "/api/saved-views/" + controller.activeSavedViewId + "/browse"
        body = {limit: 50}
        if cursor <> "" then body.cursor = cursor
        result = PorticoDiscoveryRequest(controller, session, "POST", path, body)
        if result.ok then normalized = PorticoBrowseLibraryPageFromBrowse(result.data, artworkJobs)
    else if controller.selectedResourceId <> "" and (pivot.id = "collections" or pivot.id = "playlists")
        path = "/api/" + pivot.id + "/" + controller.selectedResourceId + "/items?limit=50"
        if cursor <> "" then path = path + "&cursor=" + PorticoBrowseUrlEncode(cursor)
        result = PorticoDiscoveryRequest(controller, session, "GET", path, "")
        if result.ok then normalized = PorticoBrowseSavedResourceItems(result.data, pivot.id = "playlists", artworkJobs)
    else if controller.selectedFacetId <> ""
        contentPivot = PorticoLibraryBrowsablePivot(controller.capabilities.pivots)
        query = controller.facetQueries[controller.selectedFacetId]
        if contentPivot <> invalid and query <> invalid
            body = { pivot: contentPivot.id, limit: 50, query: query }
            if cursor <> "" then body.cursor = cursor
            PorticoLibraryApplyBrowseOptions(controller, body, contentPivot, false)
            result = PorticoDiscoveryRequest(controller, session, "POST", "/api/libraries/" + controller.library.id + "/browse", body)
            if result.ok then normalized = PorticoBrowseLibraryPageFromBrowse(result.data, artworkJobs)
        end if
    else if pivot.id = "discover"
        result = PorticoDiscoveryRequest(controller, session, "GET", "/api/libraries/" + controller.library.id + "/discover?limit=200", "")
        if result.ok then normalized = PorticoBrowseLibraryPageFromDiscover(result.data, artworkJobs)
    else if pivot.id = "categories" or pivot.id = "genres"
        result = PorticoDiscoveryRequest(controller, session, "GET", "/api/libraries/" + controller.library.id + "/categories", "")
        if result.ok then normalized = PorticoBrowseLibraryFacets(result.data, pivot.id)
    else if pivot.id = "authors" or pivot.id = "series"
        path = "/api/libraries/" + controller.library.id + "/" + pivot.id + "?limit=100"
        if cursor <> "" then path = path + "&cursor=" + PorticoBrowseUrlEncode(cursor)
        result = PorticoDiscoveryRequest(controller, session, "GET", path, "")
        if result.ok then normalized = PorticoBrowseLibraryFacets(result.data, pivot.id)
    else if pivot.id = "collections" or pivot.id = "playlists"
        path = "/api/" + pivot.id + "?limit=50&libraryId=" + PorticoBrowseUrlEncode(controller.library.id)
        if cursor <> "" then path = path + "&cursor=" + PorticoBrowseUrlEncode(cursor)
        result = PorticoDiscoveryRequest(controller, session, "GET", path, "")
        if result.ok
            resourceKind = "collection"
            if pivot.id = "playlists" then resourceKind = "playlist"
            normalized = PorticoBrowseSavedResources(result.data, resourceKind)
        end if
    else if pivot.id = "schedule"
        path = "/api/dvr/schedule?limit=50"
        if cursor <> "" then path = path + "&cursor=" + PorticoBrowseUrlEncode(cursor)
        result = PorticoDiscoveryRequest(controller, session, "GET", path, "")
        if result.ok then normalized = PorticoBrowseDvrSchedule(result.data)
    else if pivot.browseSupported = true
        body = { pivot: pivot.id, limit: 50 }
        if cursor <> "" then body.cursor = cursor
        PorticoLibraryApplyBrowseOptions(controller, body, pivot, true)
        result = PorticoDiscoveryRequest(controller, session, "POST", "/api/libraries/" + controller.library.id + "/browse", body)
        if result.ok then normalized = PorticoBrowseLibraryPageFromBrowse(result.data, artworkJobs)
    end if
    if result = invalid
        if controller.quietRefresh and controller.page <> invalid then controller.status = "stale" else controller.status = "error"
        controller.quietRefresh = false
        PorticoLibraryPublish(controller, false)
        return
    end if
    if result.interrupted then return
    if not result.ok
        PorticoLibraryFailed(controller, result, false)
        return
    end if
    if normalized = invalid
        if controller.quietRefresh and controller.page <> invalid then controller.status = "stale" else controller.status = "error"
        controller.quietRefresh = false
        PorticoLibraryPublish(controller, false)
        return
    end if
    if append and controller.page <> invalid
        previousCount = PorticoLibraryPageCount(controller.page)
        PorticoLibraryMergePage(controller.page, normalized)
        if PorticoLibraryPageCount(controller.page) > previousCount then controller.windowOffset = previousCount
    else
        controller.page = normalized
        if controller.quietRefresh then controller.windowOffset = controller.quietWindowOffset else controller.windowOffset = 0
        controller.cursorHistory = {}
    end if
    if PorticoLibraryCanChooseView(controller) and (controller.page.presentation = "grid" or controller.page.presentation = "list") then controller.page.presentation = controller.viewMode
    if normalized.queries <> invalid
        for each facetId in normalized.queries
            controller.facetQueries[facetId] = normalized.queries[facetId]
        end for
    end if
    if PorticoLibraryPageCount(controller.page) > 0 then controller.status = "ready" else controller.status = "empty"
    controller.reconnectRequestedGeneration = -1
    controller.quietRefresh = false
    PorticoLibraryPersistCache(controller)
    ' Publish verified metadata and stable card geometry before artwork I/O.
    PorticoLibraryPublish(controller, false)
    PorticoBrowseMaterializeArtwork(controller, session, "library", artworkJobs)
    PorticoLibraryPublish(controller, false)
end sub

sub PorticoLibraryMergePage(target as object, incoming as object)
    if (target.presentation = "grid" or target.presentation = "list" or target.presentation = "resources" or target.presentation = "schedule") and incoming.items <> invalid
        for each item in incoming.items
            if not PorticoBrowseContainsId(target.items, item.id) then target.items.push(item)
        end for
    else if target.presentation = "facets" and incoming.sections <> invalid
        for each incomingSection in incoming.sections
            targetSection = PorticoLibraryFindSection(target.sections, incomingSection.id)
            if targetSection = invalid
                target.sections.push(incomingSection)
            else
                for each item in incomingSection.items
                    if not PorticoBrowseContainsId(targetSection.items, item.id) then targetSection.items.push(item)
                end for
            end if
        end for
    end if
    target.hasMore = incoming.hasMore
    target.nextCursor = incoming.nextCursor
    if incoming.resultCount > target.resultCount then target.resultCount = incoming.resultCount
end sub

sub PorticoLibraryFailed(controller as object, result as dynamic, missingSession as boolean)
    status = 0
    if result <> invalid then status = result.status
    if status = 403 or status = 404
        PorticoDiscoveryCacheRemoveViewer("library-cache", controller)
        controller.page = invalid
        controller.status = "error"
    else if controller.page <> invalid
        controller.status = "stale"
    else
        controller.status = "error"
    end if
    reconnect = missingSession or status = 401
    requestReconnect = false
    if reconnect and controller.reconnectRequestedGeneration <> controller.sessionGeneration
        controller.reconnectRequestedGeneration = controller.sessionGeneration
        requestReconnect = true
    end if
    controller.quietRefresh = false
    PorticoLibraryPublish(controller, requestReconnect)
end sub

sub PorticoLibraryResetRuntime(controller as object)
    controller.sessionGeneration = 0
    controller.cacheBinding = ""
    controller.reconnectRequestedGeneration = -1
    controller.quietRefresh = false
    controller.quietWindowOffset = 0
    controller.requestedLibraryId = ""
    controller.libraries = []
    controller.library = invalid
    controller.capabilities = invalid
    controller.selectedTabId = ""
    controller.selectedFacetId = ""
    controller.selectedResourceId = ""
    controller.selectedResourceTitle = ""
    controller.filterUnplayed = false
    controller.appliedFilters = []
    controller.draftFilters = []
    controller.filterDraftOpen = false
    controller.selectedSortIndex = -1
    controller.selectedSortDirection = ""
    controller.seekPrefix = ""
    controller.viewMode = "grid"
    controller.facetQueries = {}
    controller.pivotPreferences = {}
    controller.cursorHistory = {}
    controller.savedViewStatus = "idle"
    controller.activeSavedViewId = ""
    controller.page = invalid
    controller.windowOffset = 0
    controller.status = "idle"
    controller.requestKind = ""
end sub

sub PorticoLibraryRestoreCache(controller as object)
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
    parameters = PorticoDiscoveryCanonicalParameters({view: "last-view"})
    if parameters = invalid then return
    payload = PorticoDiscoveryCacheRead("library-cache", controller, "library", parameters)
    if payload = invalid then return
    if not controller.envelopeMode
        if payload.version <> 1 or PorticoBrowseSafeId(payload.serverId) <> controller.serverId or payload.cacheBinding <> controller.cacheBinding then return
    end if
    viewState = PorticoBrowseLibraryCacheView(payload.viewState)
    if viewState = invalid then return
    controller.requestedLibraryId = PorticoBrowseSafeId(payload.libraryId)
    controller.page = { cachedViewState: viewState, presentation: PorticoBrowseSafeText(viewState.presentation, 24), hasMore: false, nextCursor: "" }
    controller.status = "stale"
end sub

sub PorticoLibraryPersistCache(controller as object)
    if controller.serverId = "" or controller.cacheBinding = "" or controller.page = invalid then return
    viewState = PorticoLibraryViewState(controller)
    cached = PorticoBrowseLibraryCacheView(viewState)
    if cached = invalid then return
    parameters = PorticoDiscoveryCanonicalParameters({view: "last-view"})
    if parameters = invalid then return
    PorticoDiscoveryCacheCommit("library-cache", controller, "library", parameters, { version: 1, serverId: controller.serverId, cacheBinding: controller.cacheBinding, libraryId: controller.requestedLibraryId, viewState: cached })
end sub

sub PorticoLibraryPublish(controller as object, serverReconnectRequired as boolean)
    viewState = PorticoLibraryViewState(controller)
    projection = { libraryViewState: viewState, libraryServerReconnectRequired: serverReconnectRequired }
    if not controller.envelopeMode then m.top.projection = projection
    envelope = PorticoDiscoveryResultEnvelope(controller, projection)
    if envelope <> invalid then m.top.projectionEnvelope = envelope
end sub

function PorticoLibraryViewState(controller as object) as object
    if controller.page <> invalid and controller.page.cachedViewState <> invalid
        viewState = PorticoBrowseClone(controller.page.cachedViewState)
        viewState.serverName = controller.serverName
    else
        viewState = {
            status: "loading",
            libraryName: "Library",
            serverName: controller.serverName,
            presentation: "grid",
            tabs: [],
            actions: [],
            items: [],
            hasMore: false
        }
        if controller.library <> invalid then viewState.libraryName = controller.library.name
        if controller.library = invalid and controller.libraries.count() > 0
            viewState.status = "ready"
            viewState.libraryName = "All libraries"
            viewState.presentation = "resources"
            viewState.libraryHub = true
            viewState.items = []
            for each candidate in controller.libraries
                viewState.items.push({id: candidate.id, title: candidate.name, meta: candidate.kind, summary: candidate.count.ToStr() + " items"})
            end for
            viewState.resultCount = viewState.items.count()
        end if
        if controller.capabilities <> invalid then viewState.tabs = PorticoLibraryTabs(controller.capabilities.pivots, controller.selectedTabId)
        if controller.page <> invalid
            window = PorticoLibraryPageWindow(controller.page, controller.windowOffset)
            for each key in window
                viewState[key] = window[key]
            end for
        end if
    end if
    if controller.status = "stale"
        viewState.status = "ready"
        if controller.serverStatus = "online" then viewState.availabilityStatus = "refresh-failed" else viewState.availabilityStatus = "offline"
    else if controller.status = "loading"
        viewState.status = "loading"
        viewState.availabilityStatus = "current"
    else if controller.status = "idle"
        viewState.status = "error"
        viewState.availabilityStatus = "current"
        viewState.title = "Choose a server"
        viewState.message = "Connect to a Portico Server to browse its libraries."
        viewState.actionLabel = "Choose Server"
        viewState.actionKind = "open-server-selection"
    else if controller.status = "ready"
        viewState.status = "ready"
        viewState.availabilityStatus = "current"
    else if controller.status = "empty"
        viewState.status = "empty"
        viewState.availabilityStatus = "current"
        viewState.title = "Nothing here yet"
        viewState.message = "This library does not have content in this view."
        if controller.selectedResourceTitle <> ""
            viewState.title = controller.selectedResourceTitle + " is empty"
            viewState.message = "No visible media is available here."
        end if
    else
        viewState.status = "error"
        viewState.availabilityStatus = "current"
        viewState.title = "Library couldn't load"
        viewState.message = "Check the server connection and try again."
        viewState.actionLabel = "Try again"
        viewState.actionKind = "retry-library"
    end if
    if controller.selectedFacetId <> "" or controller.selectedResourceId <> ""
        label = "All"
        if controller.selectedResourceTitle <> "" then label = "All " + LCase(PorticoBrowseSafeText(controller.selectedTabId, 24))
        viewState.actions = [{ id: "clear-selection", label: label, iconId: "navigation.back", selected: true, width: 190 }]
        if controller.selectedResourceTitle <> "" then viewState.libraryName = controller.selectedResourceTitle
    end if
    if controller.capabilities <> invalid
        viewState.filterDescriptor = {
            open: controller.filterDraftOpen,
            fields: PorticoLibraryFilterFields(controller),
            draft: PorticoBrowseClone(controller.draftFilters),
            applied: PorticoBrowseClone(controller.appliedFilters),
            maximumClauses: controller.capabilities.queryLimits.maximumClauses
        }
        viewState.alphabetSeek = PorticoLibraryAlphabetProjection(controller)
        viewState.selectedSortDirection = controller.selectedSortDirection
        viewState.savedViewStatus = controller.savedViewStatus
    end if
    viewState.resultLabel = PorticoLibraryResultLabel(controller.selectedTabId)
    PorticoLibraryAppendToolbarActions(controller, viewState)
    if (viewState.presentation = "grid" or viewState.presentation = "list") and PorticoLibraryCanChooseView(controller) then viewState.presentation = controller.viewMode
    return viewState
end function

function PorticoLibraryResultLabel(rawTabId as dynamic) as string
    tabId = LCase(PorticoBrowseSafeId(rawTabId))
    if tabId = "movies" then return "movie"
    if tabId = "shows" then return "show"
    if tabId = "albums" then return "album"
    if tabId = "artists" then return "artist"
    if tabId = "tracks" or tabId = "songs" then return "song"
    if tabId = "episodes" then return "episode"
    if tabId = "seasons" then return "season"
    if tabId = "audiobooks" or tabId = "books" then return "audiobook"
    if tabId = "collections" then return "collection"
    if tabId = "playlists" then return "playlist"
    return "item"
end function

sub PorticoLibraryAppendToolbarActions(controller as object, viewState as object)
    if viewState.actions = invalid or GetInterface(viewState.actions, "ifArray") = invalid then viewState.actions = []
    if controller.selectedTabId = "discover" or controller.selectedTabId = "categories" or controller.selectedTabId = "genres" or controller.selectedTabId = "authors" or controller.selectedTabId = "series" or controller.selectedTabId = "collections" or controller.selectedTabId = "playlists" or controller.selectedTabId = "schedule" then return
    if PorticoLibraryCanFilter(controller) and viewState.actions.count() < 4
        label = "Filter"
        if controller.appliedFilters.count() > 0 then label = "Filter (" + controller.appliedFilters.count().ToStr() + ")"
        viewState.actions.push({id: "open-library-filters", label: label, iconId: "action.customize", selected: controller.appliedFilters.count() > 0, width: 180})
    end if
    sorts = PorticoLibraryAvailableSorts(controller)
    if sorts.count() > 0 and viewState.actions.count() < 4
        label = "Sort: Default"
        if controller.selectedSortIndex >= 0 and controller.selectedSortIndex < sorts.count() then label = "Sort: " + sorts[controller.selectedSortIndex].label
        viewState.actions.push({id: "cycle-sort", label: label, iconId: "action.sort", selected: controller.selectedSortIndex >= 0, width: 250})
    end if
    if PorticoLibraryCanChooseView(controller) and viewState.actions.count() < 4
        icon = "view.grid"
        label = "Grid"
        if controller.viewMode = "list"
            icon = "view.list"
            label = "List"
        end if
        viewState.actions.push({id: "toggle-view", label: label, iconId: icon, selected: false, width: 160})
    end if
    if controller.capabilities <> invalid and PorticoBrowseArrayHasText(controller.capabilities.actions, "saved-view.create") and viewState.actions.count() < 4
        saveLabel = "Save View"
        if controller.savedViewStatus = "saving" then saveLabel = "Saving…"
        if controller.savedViewStatus = "saved" then saveLabel = "Saved"
        if controller.savedViewStatus = "error" then saveLabel = "Try Saving Again"
        viewState.actions.push({id: "save-library-view", label: saveLabel, iconId: "action.add", selected: controller.savedViewStatus = "saved", width: 220})
    end if
end sub

function PorticoLibraryFilterFields(controller as object) as object
    result = []
    if controller.capabilities = invalid then return result
    pivot = PorticoLibraryFindPivot(controller.capabilities.pivots, controller.selectedTabId)
    for each field in controller.capabilities.fields
        applicable = field.applicableKinds.count() = 0
        if not applicable and pivot <> invalid
            for each kind in pivot.entityKinds
                if PorticoBrowseArrayHasText(field.applicableKinds, kind) then applicable = true
            end for
        end if
        if applicable and (field.complexity = "quick" or field.complexity = "standard") and result.count() < 24 then result.push(PorticoBrowseClone(field))
    end for
    return result
end function

function PorticoLibraryAlphabetProjection(controller as object) as object
    available = false
    sorts = PorticoLibraryAvailableSorts(controller)
    if controller.selectedSortIndex >= 0 and controller.selectedSortIndex < sorts.count()
        sort = sorts[controller.selectedSortIndex]
        direction = controller.selectedSortDirection
        if direction = "" then direction = sort.direction
        available = direction = "asc" and (sort.id = "title" or sort.id = "sortTitle")
    end if
    return {available: available, selected: controller.seekPrefix, prefixes: ["#","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]}
end function

sub PorticoLibraryApplyBrowseOptions(controller as object, body as object, pivot as object, allowFilter as boolean)
    sorts = PorticoLibraryAvailableSorts(controller)
    if controller.selectedSortIndex >= 0 and controller.selectedSortIndex < sorts.count()
        selected = sorts[controller.selectedSortIndex]
        body.sort = [{field: selected.id, direction: selected.direction}]
        if controller.selectedSortDirection <> "" then body.sort[0].direction = controller.selectedSortDirection
    else if pivot.defaultSort <> invalid and pivot.defaultSort.count() > 0
        body.sort = pivot.defaultSort
    end if
    if allowFilter and controller.appliedFilters.count() > 0
        if controller.appliedFilters.count() = 1
            body.query = PorticoBrowseClone(controller.appliedFilters[0])
        else
            body.query = {all: PorticoBrowseClone(controller.appliedFilters)}
        end if
    else if allowFilter and controller.filterUnplayed and PorticoLibraryCanFilter(controller)
        body.query = {field: "playState", operator: "equals", value: "unplayed"}
    end if
    if controller.seekPrefix <> "" and body.sort <> invalid and body.sort.count() > 0 and body.sort[0].direction = "asc" and (body.sort[0].field = "title" or body.sort[0].field = "sortTitle") then body.seek = {prefix: controller.seekPrefix}
end sub

function PorticoLibraryCanFilter(controller as object) as boolean
    if controller.capabilities = invalid or (controller.capabilities.canFilterUnplayed <> true and controller.capabilities.fields.count() = 0) then return false
    pivot = PorticoLibraryFindPivot(controller.capabilities.pivots, controller.selectedTabId)
    return pivot <> invalid and pivot.browseSupported = true
end function

function PorticoLibraryFindField(fields as dynamic, id as string) as dynamic
    if fields = invalid or GetInterface(fields, "ifArray") = invalid then return invalid
    for each field in fields
        if field.id = id then return field
    end for
    return invalid
end function

sub PorticoLibraryRememberPivot(controller as object)
    if controller.selectedTabId = "" then return
    controller.pivotPreferences[controller.selectedTabId] = {
        filters: PorticoBrowseClone(controller.appliedFilters), sortIndex: controller.selectedSortIndex,
        sortDirection: controller.selectedSortDirection, viewMode: controller.viewMode, seekPrefix: controller.seekPrefix
    }
end sub

sub PorticoLibraryRestorePivot(controller as object)
    preference = controller.pivotPreferences[controller.selectedTabId]
    if preference = invalid or Type(preference) <> "roAssociativeArray" then return
    controller.appliedFilters = PorticoBrowseClone(preference.filters)
    controller.selectedSortIndex = PorticoHttpInteger(preference.sortIndex, -1)
    controller.selectedSortDirection = PorticoBrowseSafeText(preference.sortDirection, 8)
    controller.viewMode = PorticoBrowseSafeText(preference.viewMode, 16)
    controller.seekPrefix = PorticoBrowseSafeText(preference.seekPrefix, 1)
end sub

function PorticoLibraryCanChooseView(controller as object) as boolean
    pivot = invalid
    if controller.capabilities <> invalid then pivot = PorticoLibraryFindPivot(controller.capabilities.pivots, controller.selectedTabId)
    if pivot = invalid or pivot.supportedViews = invalid then return false
    return PorticoBrowseArrayHasText(pivot.supportedViews, "grid") and PorticoBrowseArrayHasText(pivot.supportedViews, "list")
end function

function PorticoLibraryAvailableSorts(controller as object) as object
    result = []
    if controller.capabilities = invalid or controller.capabilities.sorts = invalid then return result
    pivot = PorticoLibraryFindPivot(controller.capabilities.pivots, controller.selectedTabId)
    if pivot = invalid then return result
    for each sort in controller.capabilities.sorts
        applicable = sort.applicableKinds = invalid or sort.applicableKinds.count() = 0
        if not applicable and pivot.entityKinds <> invalid
            for each kind in pivot.entityKinds
                if PorticoBrowseArrayHasText(sort.applicableKinds, kind) then applicable = true
            end for
        end if
        if applicable then result.push(sort)
    end for
    return result
end function

function PorticoLibraryPageWindow(page as object, offset as integer) as object
    if offset < 0 then offset = 0
    result = { presentation: page.presentation, resultCount: page.resultCount, hasMore: false, loadMoreLabel: "Load more" }
    bufferedCount = PorticoLibraryPageCount(page)
    windowSize = PorticoLibraryWindowSize(page.presentation)
    if page.presentation = "grid"
        result.items = PorticoLibraryArrayWindow(page.items, offset, windowSize)
    else if page.presentation = "list"
        result.items = PorticoLibraryArrayWindow(page.items, offset, windowSize)
    else if page.presentation = "facets"
        result.sections = PorticoLibrarySectionWindow(page.sections, offset, windowSize)
    else if page.presentation = "shelves"
        result.rows = PorticoLibraryRowsWindow(page.rows, offset)
    else if page.presentation = "resources" or page.presentation = "schedule"
        result.items = PorticoLibraryArrayWindow(page.items, offset, windowSize)
    end if
    visibleCount = PorticoLibraryWindowVisibleCount(result, page.presentation)
    result.hasMore = offset + visibleCount < bufferedCount or page.hasMore = true
    return result
end function

function PorticoLibraryTabs(pivots as object, selectedId as string) as object
    tabs = []
    for each pivot in pivots
        if tabs.count() >= 6 then exit for
        tabs.push({ id: pivot.id, label: pivot.label, selected: pivot.id = selectedId })
    end for
    return tabs
end function

function PorticoLibraryArrayWindow(items as dynamic, offset as integer, maximum as integer) as object
    result = []
    if items = invalid or GetInterface(items, "ifArray") = invalid then return result
    lastIndex = offset + maximum - 1
    if lastIndex >= items.count() then lastIndex = items.count() - 1
    for index = offset to lastIndex
        if index >= 0 and index < items.count() then result.push(PorticoBrowseClone(items[index]))
    end for
    return result
end function

function PorticoLibrarySectionWindow(sections as dynamic, offset as integer, maximum as integer) as object
    result = []
    if sections = invalid or GetInterface(sections, "ifArray") = invalid then return result
    skipped = 0
    remaining = maximum
    for each section in sections
        if remaining <= 0 then exit for
        projectedItems = []
        for each item in section.items
            if skipped < offset
                skipped = skipped + 1
            else if remaining > 0
                projectedItems.push(PorticoBrowseClone(item))
                remaining = remaining - 1
            end if
        end for
        if projectedItems.count() > 0 then result.push({ id: section.id, title: section.title, items: projectedItems })
    end for
    return result
end function

function PorticoLibraryRowsWindow(rows as dynamic, offset as integer) as object
    result = []
    if rows = invalid or GetInterface(rows, "ifArray") = invalid then return result
    skipped = 0
    visibleCount = 0
    for each row in rows
        if visibleCount >= 21 then exit for
        maximum = 7
        if row.shape = "landscape" then maximum = 5
        items = []
        for each item in row.items
            if skipped < offset
                skipped = skipped + 1
            else if items.count() < maximum and visibleCount + items.count() < 21
                items.push(PorticoBrowseClone(item))
            end if
        end for
        if items.count() > 0
            result.push({ id: row.id, title: row.title, shape: row.shape, items: items })
            visibleCount = visibleCount + items.count()
        end if
    end for
    return result
end function

function PorticoLibraryPageCount(page as dynamic) as integer
    if page = invalid or Type(page) <> "roAssociativeArray" then return 0
    if page.items <> invalid and GetInterface(page.items, "ifArray") <> invalid then return page.items.count()
    total = 0
    if page.sections <> invalid and GetInterface(page.sections, "ifArray") <> invalid
        for each section in page.sections
            if section.items <> invalid and GetInterface(section.items, "ifArray") <> invalid then total = total + section.items.count()
        end for
    else if page.rows <> invalid and GetInterface(page.rows, "ifArray") <> invalid
        for each row in page.rows
            if row.items <> invalid and GetInterface(row.items, "ifArray") <> invalid then total = total + row.items.count()
        end for
    end if
    return total
end function

function PorticoLibraryWindowSize(presentation as string) as integer
    if presentation = "facets" then return 12
    if presentation = "resources" or presentation = "schedule" or presentation = "list" then return 12
    return 21
end function

function PorticoLibraryWindowVisibleCount(window as dynamic, presentation as string) as integer
    if window = invalid or Type(window) <> "roAssociativeArray" then return 0
    if presentation = "facets"
        total = 0
        if window.sections <> invalid and GetInterface(window.sections, "ifArray") <> invalid
            for each section in window.sections
                if section.items <> invalid and GetInterface(section.items, "ifArray") <> invalid then total = total + section.items.count()
            end for
        end if
        return total
    end if
    if presentation = "shelves"
        total = 0
        if window.rows <> invalid and GetInterface(window.rows, "ifArray") <> invalid
            for each row in window.rows
                if row.items <> invalid and GetInterface(row.items, "ifArray") <> invalid then total = total + row.items.count()
            end for
        end if
        return total
    end if
    if window.items <> invalid and GetInterface(window.items, "ifArray") <> invalid then return window.items.count()
    return 0
end function

function PorticoLibraryFindLibrary(libraries as object, id as string) as dynamic
    for each library in libraries
        if library.id = id then return library
    end for
    return invalid
end function

function PorticoLibraryFindPivot(pivots as object, id as string) as dynamic
    for each pivot in pivots
        if pivot.id = id then return pivot
    end for
    return invalid
end function

function PorticoLibraryDefaultPivot(pivots as object) as string
    if PorticoLibraryFindPivot(pivots, "discover") <> invalid then return "discover"
    if pivots.count() > 0 then return pivots[0].id
    return ""
end function

function PorticoLibraryBrowsablePivot(pivots as object) as dynamic
    for each pivot in pivots
        if pivot.browseSupported = true and pivot.id <> "discover" then return pivot
    end for
    return invalid
end function

function PorticoLibraryFindSection(sections as object, id as string) as dynamic
    for each section in sections
        if section.id = id then return section
    end for
    return invalid
end function
