function PorticoSavedTabs(selectedId as string) as object
    definitions = [
        { id: "watchlist", label: "Watchlist" },
        { id: "favorites", label: "Favorites" },
        { id: "playlists", label: "Playlists" },
        { id: "collections", label: "Collections" },
        { id: "saved-views", label: "Saved views" }
    ]
    result = []
    for each definition in definitions
        result.push({ id: definition.id, label: definition.label, selected: definition.id = selectedId })
    end for
    return result
end function

function PorticoSavedTabValid(value as dynamic) as boolean
    id = LCase(PorticoBrowseSafeId(value))
    return id = "watchlist" or id = "favorites" or id = "playlists" or id = "collections" or id = "saved-views"
end function

function PorticoSavedTabLabel(id as string) as string
    if id = "favorites" then return "Favorites"
    if id = "playlists" then return "Playlists"
    if id = "collections" then return "Collections"
    if id = "saved-views" then return "Saved views"
    return "Watchlist"
end function

function PorticoSavedNormalizeMediaPage(data as dynamic, sourceKind as string, artworkJobs as object) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    items = []
    for each rawItem in data.items
        if items.count() >= 200 then exit for
        source = rawItem
        if sourceKind = "playlists" and rawItem <> invalid and Type(rawItem) = "roAssociativeArray" then source = rawItem.media
        normalized = PorticoSavedMedia(source)
        if normalized <> invalid and not PorticoBrowseContainsId(items, normalized.model.id)
            items.push(normalized.model)
            if normalized.artworkSource <> ""
                width = 404
                height = 642
                if normalized.model.shape = "square"
                    height = 404
                else if normalized.model.shape = "landscape"
                    width = 616
                    height = 360
                end if
                artworkJobs.push({ target: normalized.model, field: "poster", source: normalized.artworkSource, key: sourceKind + "-" + normalized.model.id, width: width, height: height })
            end if
        end if
    end for
    pageInfo = PorticoBrowsePageInfo(data.pageInfo)
    return { items: items, hasMore: pageInfo.hasMore, nextCursor: pageInfo.nextCursor, total: pageInfo.total }
end function

function PorticoSavedMedia(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    if source.entityKind <> invalid
        normalized = PorticoBrowseMediaCard(source)
        if normalized = invalid then return invalid
        state = source.userState
        actions = PorticoContentSafeActions(source.actions)
        normalized.model.actions = actions
        normalized.model.watchlisted = state <> invalid and Type(state) = "roAssociativeArray" and state.watchlisted = true
        normalized.model.favorite = state <> invalid and Type(state) = "roAssociativeArray" and state.favorite = true
        normalized.model.watched = state <> invalid and Type(state) = "roAssociativeArray" and state.watched = true
        normalized.model.uiActions = PorticoSavedUiActions(actions)
        return { model: normalized.model, artworkSource: normalized.artworkSource }
    end if
    presentation = PorticoContentMediaPresentation(source, false)
    if presentation = invalid then return invalid
    model = presentation.card
    state = source.state
    model.watchlisted = state <> invalid and Type(state) = "roAssociativeArray" and state.watchlisted = true
    model.favorite = state <> invalid and Type(state) = "roAssociativeArray" and state.favorite = true
    model.watched = state <> invalid and Type(state) = "roAssociativeArray" and state.watched = true
    model.uiActions = PorticoSavedUiActions(model.actions)
    return { model: model, artworkSource: presentation.posterSource }
end function

function PorticoSavedUiActions(actions as dynamic) as object
    result = []
    if actions = invalid or GetInterface(actions, "ifArray") = invalid then return result
    allowed = { play: true, "live.play": true, "watchlist.add": true, "watchlist.remove": true, "favorite.add": true, "favorite.remove": true, "watched.set": true, "watched.mark": true, "watched.unmark": true }
    for each rawAction in actions
        action = LCase(PorticoBrowseSafeText(rawAction, 48))
        if allowed[action] = true and result.count() < 7 then result.push(action)
    end for
    return result
end function

function PorticoSavedActionsAfterMutation(source as dynamic, family as string, value as boolean) as object
    result = []
    if source <> invalid and GetInterface(source, "ifArray") <> invalid
        for each action in source
            text = LCase(PorticoBrowseSafeText(action, 48))
            if Left(text, Len(family) + 1) <> family + "." then result.push(text)
        end for
    end if
    if family = "watchlist" or family = "favorite"
        suffix = "add"
        if value then suffix = "remove"
        result.push(family + "." + suffix)
    else if family = "watched"
        result.push("watched.set")
    end if
    return result
end function

function PorticoSavedNormalizeResourcePage(data as dynamic, sourceKind as string) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    resources = []
    for each source in data.items
        if resources.count() >= 100 then exit for
        resource = PorticoSavedResource(source, sourceKind)
        if resource <> invalid and not PorticoBrowseContainsId(resources, resource.id) then resources.push(resource)
    end for
    pageInfo = PorticoBrowsePageInfo(data.pageInfo)
    return { items: resources, hasMore: pageInfo.hasMore, nextCursor: pageInfo.nextCursor, total: pageInfo.total }
end function

function PorticoSavedResource(source as dynamic, sourceKind as string) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoBrowseSafeId(source.id)
    title = PorticoBrowseSafeText(source.title, 140)
    if id = "" or title = "" then return invalid
    itemCount = PorticoHttpInteger(source.itemCount, -1)
    visibility = LCase(PorticoBrowseSafeText(source.visibility, 20))
    if visibility <> "private" and visibility <> "server" then visibility = ""
    metaParts = []
    if itemCount >= 0
        suffix = " items"
        if itemCount = 1 then suffix = " item"
        metaParts.push(itemCount.ToStr() + suffix)
    else if sourceKind = "saved-views"
        libraryName = PorticoBrowseSafeText(source.libraryName, 80)
        if libraryName <> "" then metaParts.push(libraryName)
        presentation = LCase(PorticoBrowseSafeText(source.presentation, 24))
        if presentation <> "" then metaParts.push(PorticoSavedPresentationLabel(presentation))
    end if
    if visibility <> "" then metaParts.push(UCase(Left(visibility, 1)) + Mid(visibility, 2))
    summary = PorticoBrowseSafeText(source.summary, 360)
    if summary = "" and sourceKind = "saved-views" and source.isPinned = true then summary = "Pinned view"
    return {
        id: id,
        title: title,
        meta: PorticoBrowseJoin(metaParts),
        summary: summary,
        count: itemCount,
        kind: sourceKind,
        shape: "resource",
        visibility: visibility,
        revision: PorticoHttpInteger(source.revision, 0),
        canEdit: source.canEdit = true,
        sharingAllowed: false
    }
end function

function PorticoSavedPresentationLabel(value as string) as string
    if value = "shelves" then return "Shelves"
    if value = "list" then return "List"
    if value = "facets" then return "Categories"
    if value = "schedule" then return "Schedule"
    return "Grid"
end function

sub PorticoSavedMergeUnique(target as object, incoming as object, maximum as integer)
    for each item in incoming
        if target.count() >= maximum then return
        if item <> invalid and Type(item) = "roAssociativeArray" and not PorticoBrowseContainsId(target, item.id) then target.push(item)
    end for
end sub

function PorticoSavedMediaWindow(page as dynamic, offset as integer, maximum as integer) as object
    result = []
    if page = invalid or page.items = invalid then return result
    if offset < 0 then offset = 0
    lastIndex = offset + maximum - 1
    if lastIndex >= page.items.count() then lastIndex = page.items.count() - 1
    for index = offset to lastIndex
        if index >= 0 and index < page.items.count() then result.push(PorticoBrowseClone(page.items[index]))
    end for
    return result
end function

function PorticoSavedCacheView(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    selectedTabId = LCase(PorticoBrowseSafeId(source.selectedTabId))
    if not PorticoSavedTabValid(selectedTabId) then selectedTabId = "watchlist"
    selectedResourceId = PorticoBrowseSafeId(source.selectedResourceId)
    presentation = LCase(PorticoBrowseSafeText(source.presentation, 24))
    if presentation <> "grid" and presentation <> "resources" then presentation = "grid"
    cached = {
        status: "ready",
        libraryName: "Saved",
        serverName: PorticoBrowseSafeText(source.serverName, 100),
        selectedTabId: selectedTabId,
        selectedResourceId: selectedResourceId,
        selectedResourceTitle: PorticoBrowseSafeText(source.selectedResourceTitle, 140),
        presentation: presentation,
        resultCount: PorticoHttpInteger(source.resultCount, 0),
        tabs: PorticoSavedTabs(selectedTabId),
        actions: [],
        items: PorticoBrowseCachedItems(source.items, 21),
        hasMore: false
    }
    return cached
end function
