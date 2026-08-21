sub PorticoBrowsePatchMediaState(target as dynamic, mediaId as string, family as string, value as boolean, depth as integer)
    if target = invalid or depth > 10 then return
    if Type(target) = "roAssociativeArray"
        if PorticoBrowseSafeId(target.id) = mediaId
            if family = "watchlist" then target.watchlisted = value
            if family = "favorite" then target.favorite = value
            if family = "watched" then target.watched = value
            if target.state <> invalid and Type(target.state) = "roAssociativeArray"
                if family = "watchlist" then target.state.watchlisted = value
                if family = "favorite" then target.state.favorite = value
                if family = "watched" then target.state.watched = value
            end if
            if target.actions <> invalid and GetInterface(target.actions, "ifArray") <> invalid
                if PorticoBrowseActionFamilySupported(target.actions, family) then target.actions = PorticoBrowseActionsAfterMediaState(target.actions, family, value)
            end if
            if target.serverActions <> invalid and GetInterface(target.serverActions, "ifArray") <> invalid
                if PorticoBrowseActionFamilySupported(target.serverActions, family) then target.serverActions = PorticoBrowseActionsAfterMediaState(target.serverActions, family, value)
            end if
            if target.uiActions <> invalid then target.uiActions = PorticoBrowseMediaUiActions(target.actions)
        end if
        for each key in target
            PorticoBrowsePatchMediaState(target[key], mediaId, family, value, depth + 1)
        end for
    else if GetInterface(target, "ifArray") <> invalid
        for each item in target
            PorticoBrowsePatchMediaState(item, mediaId, family, value, depth + 1)
        end for
    end if
end sub

function PorticoBrowseActionFamilySupported(actions as dynamic, family as string) as boolean
    if actions = invalid or GetInterface(actions, "ifArray") = invalid then return false
    for each rawAction in actions
        action = LCase(PorticoBrowseSafeText(rawAction, 48))
        if family = "watched" and action = "watched.set" then return true
        if Left(action, Len(family) + 1) = family + "." then return true
    end for
    return false
end function

function PorticoBrowseMediaUiActions(actions as dynamic) as object
    result = []
    if actions = invalid or GetInterface(actions, "ifArray") = invalid then return result
    allowed = { play: true, "live.play": true, "watchlist.add": true, "watchlist.remove": true, "favorite.add": true, "favorite.remove": true, "watched.set": true }
    for each rawAction in actions
        action = LCase(PorticoBrowseSafeText(rawAction, 48))
        if allowed[action] = true and result.count() < 7 then result.push(action)
    end for
    return result
end function

function PorticoBrowseActionsAfterMediaState(actions as dynamic, family as string, value as boolean) as object
    result = []
    if actions <> invalid and GetInterface(actions, "ifArray") <> invalid
        for each rawAction in actions
            action = LCase(PorticoBrowseSafeText(rawAction, 48))
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
    return result
end function

function PorticoBrowseSearchResponse(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.groups = invalid or GetInterface(data.groups, "ifArray") = invalid then return invalid
    groups = []
    artworkJobs = []
    for each rawGroup in data.groups
        if groups.count() >= 6 then exit for
        group = PorticoBrowseSearchGroup(rawGroup, artworkJobs)
        ' Empty groups are authoritative independent states. Dropping them made
        ' one empty result family indistinguishable from a missing/failed family.
        if group <> invalid then groups.push(group)
    end for
    return { query: PorticoBrowseSafeText(data.query, 120), groups: groups, artworkJobs: artworkJobs }
end function

function PorticoBrowseSearchGroup(source as dynamic, artworkJobs as object) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" or source.items = invalid or GetInterface(source.items, "ifArray") = invalid then return invalid
    groupId = PorticoBrowseSearchGroupId(source.id)
    title = PorticoBrowseSafeText(source.title, 80)
    if groupId = "" or title = "" then return invalid
    items = []
    for each rawItem in source.items
        if items.count() >= 50 then exit for
        item = PorticoBrowseMediaItem(rawItem)
        if item <> invalid and not PorticoBrowseContainsId(items, item.model.id)
            items.push(item.model)
            if item.posterSource <> "" then artworkJobs.push({ target: item.model, field: "poster", source: item.posterSource, key: groupId + "-" + item.model.id, width: 200, height: 300 })
        end if
    end for
    cursor = PorticoBrowseSafeCursor(source.nextCursor)
    return { id: groupId, title: title, items: items, hasMore: source.hasMore = true and cursor <> "", nextCursor: cursor, windowOffset: 0 }
end function

function PorticoBrowseSearchProjection(groups as dynamic) as object
    projected = []
    if groups = invalid or GetInterface(groups, "ifArray") = invalid then return projected
    for each group in groups
        if projected.count() >= 4 then exit for
        if group <> invalid and Type(group) = "roAssociativeArray"
            offset = PorticoHttpInteger(group.windowOffset, 0)
            if offset < 0 then offset = 0
            items = []
            if group.items <> invalid and GetInterface(group.items, "ifArray") <> invalid
                lastIndex = offset + 3
                if lastIndex >= group.items.count() then lastIndex = group.items.count() - 1
                for index = offset to lastIndex
                    if index >= 0 and index < group.items.count() then items.push(PorticoBrowseClone(group.items[index]))
                end for
            end if
            hasBuffered = offset + items.count() < group.items.count()
            projectedGroup = { id: group.id, title: group.title, items: items, hasMore: hasBuffered or group.hasMore = true }
            if group.status <> invalid then projectedGroup.status = PorticoBrowseSafeText(group.status, 24)
            if group.errorMessageId <> invalid then projectedGroup.errorMessageId = PorticoBrowseSafeText(group.errorMessageId, 120)
            projected.push(projectedGroup)
        end if
    end for
    return projected
end function

function PorticoBrowseLibraryCatalog(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    items = []
    for each rawLibrary in data.items
        if items.count() >= 32 then exit for
        if rawLibrary <> invalid and Type(rawLibrary) = "roAssociativeArray"
            id = PorticoBrowseSafeId(rawLibrary.id)
            name = PorticoBrowseSafeText(rawLibrary.name, 80)
            kind = PorticoBrowseLibraryKind(rawLibrary.type)
            if id <> "" and name <> "" and kind <> "" and not PorticoBrowseContainsId(items, id)
                count = PorticoHttpInteger(rawLibrary.count, 0)
                if count < 0 then count = 0
                items.push({ id: id, name: name, kind: kind, count: count })
            end if
        end if
    end for
    return items
end function

function PorticoBrowseLibraryCapabilities(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.pivots = invalid or GetInterface(data.pivots, "ifArray") = invalid then return invalid
    pivots = []
    for each rawPivot in data.pivots
        if pivots.count() >= 12 then exit for
        pivot = PorticoBrowseLibraryPivot(rawPivot)
        if pivot <> invalid and not PorticoBrowseContainsId(pivots, pivot.id) then pivots.push(pivot)
    end for
    if pivots.count() = 0 then return invalid
    sorts = []
    if data.sorts <> invalid and GetInterface(data.sorts, "ifArray") <> invalid
        for each rawSort in data.sorts
            if sorts.count() >= 20 then exit for
            normalized = PorticoBrowseSortCapability(rawSort)
            if normalized <> invalid then sorts.push(normalized)
        end for
    end if
    canFilterUnplayed = false
    fields = []
    if data.fields <> invalid and GetInterface(data.fields, "ifArray") <> invalid
        for each field in data.fields
            normalizedField = PorticoBrowseFieldCapability(field)
            if normalizedField <> invalid and fields.count() < 64 then fields.push(normalizedField)
            if field <> invalid and Type(field) = "roAssociativeArray" and PorticoBrowseSafeId(field.id) = "playState"
                hasEquals = PorticoBrowseArrayHasText(field.operators, "equals")
                hasUnplayed = PorticoBrowseArrayHasText(field.allowedValues, "unplayed")
                if hasEquals and hasUnplayed then canFilterUnplayed = true
            end if
        end for
    end if
    limits = {maximumClauses: 8, maximumDepth: 3, maximumBytes: 8192}
    if data.queryLimits <> invalid and Type(data.queryLimits) = "roAssociativeArray"
        limits.maximumClauses = PorticoHttpInteger(data.queryLimits.maximumClauses, 8)
        limits.maximumDepth = PorticoHttpInteger(data.queryLimits.maximumDepth, 3)
        limits.maximumBytes = PorticoHttpInteger(data.queryLimits.maximumBytes, 8192)
    end if
    return { pivots: pivots, sorts: sorts, fields: fields, queryLimits: limits, canFilterUnplayed: canFilterUnplayed, actions: PorticoBrowseSafeIds(data.actions, 32, 80) }
end function

function PorticoBrowseFieldCapability(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoBrowseSafeId(source.id)
    label = PorticoBrowseSafeText(source.label, 64)
    complexity = LCase(PorticoBrowseSafeText(source.complexity, 16))
    controlHint = LCase(PorticoBrowseSafeText(source.controlHint, 32))
    valueType = LCase(PorticoBrowseSafeText(source.valueType, 32))
    if id = "" or label = "" then return invalid
    if complexity <> "quick" and complexity <> "standard" and complexity <> "advanced" then return invalid
    allowedHints = {toggle: true, select: true, "number-range": true, "date-range": true, "facet-multi-select": true, text: true}
    if allowedHints[controlHint] <> true then return invalid
    operators = PorticoBrowseSafeIds(source.operators, 24, 64)
    if operators.count() = 0 then return invalid
    values = PorticoContentSafeLabels(source.allowedValues, 128, 100)
    kinds = PorticoBrowseSafeIds(source.applicableKinds, 64, 80)
    return {id: id, label: label, complexity: complexity, controlHint: controlHint, valueType: valueType, operators: operators, allowedValues: values, applicableKinds: kinds, cost: LCase(PorticoBrowseSafeText(source.cost, 24))}
end function

function PorticoBrowseSafeIds(source as dynamic, maximum as integer, maximumLength as integer) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        if result.count() >= maximum then exit for
        id = PorticoBrowseSafeId(raw)
        if id <> "" and not PorticoBrowseArrayHasText(result, id) then result.push(id)
    end for
    return result
end function

function PorticoBrowseLibraryPivot(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoBrowseSafeId(source.id)
    label = PorticoBrowseSafeText(source.label, 48)
    if id = "" or label = "" then return invalid
    endpointTabs = { discover: true, categories: true, genres: true, authors: true, series: true, collections: true, playlists: true, schedule: true }
    if source.browseSupported <> true and endpointTabs[id] <> true then return invalid
    defaultSort = []
    if source.defaultSort <> invalid and GetInterface(source.defaultSort, "ifArray") <> invalid
        for each rawSort in source.defaultSort
            if defaultSort.count() >= 3 then exit for
            if rawSort <> invalid and Type(rawSort) = "roAssociativeArray"
                field = PorticoBrowseSafeId(rawSort.field)
                direction = LCase(PorticoBrowseSafeText(rawSort.direction, 8))
                if field <> "" and (direction = "asc" or direction = "desc") then defaultSort.push({ field: field, direction: direction })
            end if
        end for
    end if
    supportedViews = []
    if source.supportedViews <> invalid and GetInterface(source.supportedViews, "ifArray") <> invalid
        for each rawView in source.supportedViews
            view = LCase(PorticoBrowseSafeText(rawView, 24))
            if (view = "grid" or view = "list") and not PorticoBrowseArrayHasText(supportedViews, view) then supportedViews.push(view)
        end for
    end if
    entityKinds = []
    if source.entityKinds <> invalid and GetInterface(source.entityKinds, "ifArray") <> invalid
        for each rawKind in source.entityKinds
            kind = PorticoBrowseSafeId(rawKind)
            if kind <> "" then entityKinds.push(kind)
        end for
    end if
    return { id: id, label: label, browseSupported: source.browseSupported = true, defaultSort: defaultSort, supportedViews: supportedViews, entityKinds: entityKinds, presentationFields: PorticoBrowseSafeIds(source.presentationFields, 32, 80) }
end function

function PorticoBrowseSortCapability(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoBrowseSafeId(source.id)
    label = PorticoBrowseSafeText(source.label, 48)
    direction = LCase(PorticoBrowseSafeText(source.defaultDirection, 8))
    if id = "" or label = "" or (direction <> "asc" and direction <> "desc") then return invalid
    kinds = []
    if source.applicableKinds <> invalid and GetInterface(source.applicableKinds, "ifArray") <> invalid
        for each rawKind in source.applicableKinds
            kind = PorticoBrowseSafeId(rawKind)
            if kind <> "" then kinds.push(kind)
        end for
    end if
    directions = []
    if source.directions <> invalid and GetInterface(source.directions, "ifArray") <> invalid
        for each rawDirection in source.directions
            candidate = LCase(PorticoBrowseSafeText(rawDirection, 8))
            if (candidate = "asc" or candidate = "desc") and not PorticoBrowseArrayHasText(directions, candidate) then directions.push(candidate)
        end for
    end if
    if directions.count() = 0 then directions.push(direction)
    return {id: id, label: label, direction: direction, directions: directions, expensive: source.expensive = true, applicableKinds: kinds}
end function

function PorticoBrowseArrayHasText(source as dynamic, expected as string) as boolean
    if source = invalid or GetInterface(source, "ifArray") = invalid then return false
    for each value in source
        if value <> invalid and LCase(value.ToStr()) = LCase(expected) then return true
    end for
    return false
end function

function PorticoBrowseLibraryPageFromBrowse(data as dynamic, artworkJobs as object) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    items = []
    hasLandscape = false
    for each rawItem in data.items
        if items.count() >= 200 then exit for
        item = PorticoBrowseMediaCard(rawItem)
        if item <> invalid and not PorticoBrowseContainsId(items, item.model.id)
            items.push(item.model)
            if item.model.shape = "landscape" then hasLandscape = true
            if item.artworkSource <> ""
                width = 404
                height = 642
                if item.model.shape = "square"
                    width = 404
                    height = 404
                else if item.model.shape = "landscape"
                    width = 616
                    height = 360
                end if
                artworkJobs.push({ target: item.model, field: "poster", source: item.artworkSource, key: "library-" + item.model.id, width: width, height: height })
                artworkJobs.push({ target: item.model, field: "artwork", source: item.artworkSource, key: "library-" + item.model.id, width: width, height: height })
            end if
        end if
    end for
    page = PorticoBrowsePageInfo(data.pageInfo)
    presentation = "grid"
    if hasLandscape then presentation = "list"
    return { presentation: presentation, items: items, resultCount: page.total, hasMore: page.hasMore, nextCursor: page.nextCursor }
end function

function PorticoBrowseSavedResources(data as dynamic, resourceKind as string) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    items = []
    for each raw in data.items
        if items.count() >= 200 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoBrowseSafeId(raw.id)
            title = PorticoBrowseSafeText(raw.title, 140)
            if title = "" then title = PorticoBrowseSafeText(raw.name, 140)
            if id <> "" and title <> ""
                count = PorticoHttpInteger(raw.itemCount, -1)
                metaParts = []
                if count >= 0
                    label = " items"
                    if count = 1 then label = " item"
                    metaParts.push(count.ToStr() + label)
                end if
                visibility = PorticoBrowseSafeText(raw.visibility, 40)
                if visibility <> "" then metaParts.push(visibility)
                summary = PorticoBrowseSafeText(raw.summary, 240)
                if summary = "" then summary = PorticoBrowseSafeText(raw.description, 240)
                items.push({id: id, title: title, meta: PorticoBrowseJoin(metaParts), summary: summary, resourceKind: resourceKind})
            end if
        end if
    end for
    page = PorticoBrowsePageInfo(data.pageInfo)
    return {presentation: "resources", items: items, resultCount: page.total, hasMore: page.hasMore, nextCursor: page.nextCursor}
end function

function PorticoBrowseSavedResourceItems(data as dynamic, playlistEntries as boolean, artworkJobs as object) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    normalizedData = {items: [], pageInfo: data.pageInfo}
    for each raw in data.items
        candidate = raw
        if playlistEntries and raw <> invalid and Type(raw) = "roAssociativeArray" then candidate = raw.media
        if candidate <> invalid then normalizedData.items.push(candidate)
    end for
    return PorticoBrowseLibraryPageFromBrowse(normalizedData, artworkJobs)
end function

function PorticoBrowseDvrSchedule(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    items = []
    for each raw in data.items
        if items.count() >= 200 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoBrowseSafeId(raw.id)
            title = PorticoBrowseSafeText(raw.title, 140)
            if id <> "" and title <> ""
                status = PorticoBrowseSafeText(raw.status, 32)
                tone = ""
                lowerStatus = LCase(status)
                if lowerStatus = "failed" or lowerStatus = "cancelled" then tone = "danger"
                metaParts = []
                startsAt = PorticoBrowseSafeText(raw.startsAt, 40)
                if startsAt <> "" then metaParts.push(PorticoBrowseDateTimeLabel(startsAt))
                channelName = PorticoBrowseSafeText(raw.channelName, 100)
                if channelName <> "" then metaParts.push(channelName)
                items.push({id: id, title: title, meta: PorticoBrowseJoin(metaParts), summary: PorticoBrowseSafeText(raw.subtitle, 220), status: status, statusTone: tone})
            end if
        end if
    end for
    page = PorticoBrowsePageInfo(data.pageInfo)
    return {presentation: "schedule", items: items, resultCount: page.total, hasMore: page.hasMore, nextCursor: page.nextCursor}
end function

function PorticoBrowseDateTimeLabel(value as string) as string
    if Len(value) < 16 then return value
    return Left(value, 10) + "  ·  " + Mid(value, 12, 5)
end function

function PorticoBrowseLibraryPageFromDiscover(data as dynamic, artworkJobs as object) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    rows = []
    if data.rows <> invalid and GetInterface(data.rows, "ifArray") <> invalid
        for each rawRow in data.rows
            if rows.count() >= 8 then exit for
            row = PorticoBrowseDiscoveryRow(rawRow, artworkJobs)
            if row <> invalid and row.items.count() > 0 then rows.push(row)
        end for
    end if
    if rows.count() = 0 and data.items <> invalid and GetInterface(data.items, "ifArray") <> invalid
        items = []
        for each suggestion in data.items
            if items.count() >= 24 then exit for
            if suggestion <> invalid and Type(suggestion) = "roAssociativeArray"
                item = PorticoBrowseMediaItem(suggestion.item)
                if item <> invalid and not PorticoBrowseContainsId(items, item.model.id)
                    items.push(item.model)
                    if item.posterSource <> "" then artworkJobs.push({ target: item.model, field: "poster", source: item.posterSource, key: "discover-" + item.model.id, width: 404, height: 642 })
                end if
            end if
        end for
        if items.count() > 0 then rows.push({ id: "suggestions", title: "Suggestions", shape: "poster", items: items })
    end if
    total = 0
    for each row in rows
        total = total + row.items.count()
    end for
    return { presentation: "shelves", rows: rows, resultCount: total, hasMore: false, nextCursor: "" }
end function

function PorticoBrowseDiscoveryRow(source as dynamic, artworkJobs as object) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" or source.items = invalid or GetInterface(source.items, "ifArray") = invalid then return invalid
    id = PorticoBrowseSafeId(source.id)
    title = PorticoBrowseSafeText(source.title, 80)
    if id = "" or title = "" then return invalid
    shape = PorticoBrowseShape(source.type)
    items = []
    for each rawItem in source.items
        if items.count() >= 24 then exit for
        item = PorticoBrowseMediaItem(rawItem)
        if item <> invalid and not PorticoBrowseContainsId(items, item.model.id)
            item.model.shape = shape
            items.push(item.model)
            artworkSource = ""
            if rawItem <> invalid and Type(rawItem) = "roAssociativeArray" then artworkSource = PorticoBrowseImageSource(rawItem.images, shape)
            if artworkSource <> ""
                width = 404
                height = 642
                if shape = "square"
                    height = 404
                else if shape = "landscape"
                    width = 616
                    height = 360
                end if
                artworkJobs.push({ target: item.model, field: "poster", source: artworkSource, key: id + "-" + item.model.id, width: width, height: height })
                artworkJobs.push({ target: item.model, field: "artwork", source: artworkSource, key: id + "-" + item.model.id, width: width, height: height })
            end if
        end if
    end for
    return { id: id, title: title, shape: shape, items: items }
end function

function PorticoBrowseLibraryFacets(data as dynamic, tabId as string) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    sectionsById = {}
    sectionOrder = []
    queries = {}
    for each rawFacet in data.items
        if queries.count() >= 200 then exit for
        facet = invalid
        if tabId <> "genres" or (rawFacet <> invalid and Type(rawFacet) = "roAssociativeArray" and LCase(PorticoBrowseSafeText(rawFacet.group, 48)) = "genre")
            facet = PorticoBrowseFacet(rawFacet, tabId)
        end if
        if facet <> invalid and queries[facet.id] = invalid
            queries[facet.id] = facet.query
            section = sectionsById[facet.groupId]
            if section = invalid
                section = { id: facet.groupId, title: facet.groupTitle, items: [] }
                sectionsById[facet.groupId] = section
                sectionOrder.push(facet.groupId)
            end if
            if section.items.count() < 100 then section.items.push(facet.model)
        end if
    end for
    sections = []
    for each sectionId in sectionOrder
        section = sectionsById[sectionId]
        if section <> invalid and section.items.count() > 0 then sections.push(section)
    end for
    page = PorticoBrowsePageInfo(data.pageInfo)
    if data.pageInfo = invalid
        page.hasMore = false
        page.nextCursor = ""
        page.total = queries.count()
    end if
    return { presentation: "facets", sections: sections, queries: queries, resultCount: page.total, hasMore: page.hasMore, nextCursor: page.nextCursor }
end function

function PorticoBrowseFacet(source as dynamic, tabId as string) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoBrowseSafeId(source.id)
    title = PorticoBrowseSafeText(source.name, 100)
    if id = "" or title = "" then return invalid
    filter = PorticoBrowseSafeText(source.filter, 300)
    groupId = PorticoBrowseSafeId(source.group)
    if groupId = "" and tabId = "authors" then groupId = "author"
    if groupId = "" and tabId = "series" then groupId = "series"
    if groupId = "" then groupId = tabId
    query = PorticoBrowseFacetQuery(filter, groupId)
    if query = invalid then return invalid
    count = PorticoHttpInteger(source.count, 0)
    if count < 0 then count = 0
    meta = ""
    if count > 0 then meta = count.ToStr() + " items"
    return {
        id: id,
        groupId: groupId,
        groupTitle: PorticoBrowseFacetGroupTitle(groupId),
        query: query,
        model: { id: id, title: title, meta: meta, summary: PorticoBrowseSafeText(source.description, 240) }
    }
end function

function PorticoBrowseFacetQuery(filter as string, fallbackField as string) as dynamic
    separator = Instr(1, filter, ":")
    field = fallbackField
    rawValue = filter
    if separator > 1
        field = Left(filter, separator - 1)
        rawValue = Mid(filter, separator + 1)
    end if
    if field = "rating" then field = "contentRating"
    if field = "label" then field = "tag"
    field = PorticoBrowseSafeId(field)
    value = PorticoBrowseSafeText(rawValue, 200)
    if field = "" or value = "" then return invalid
    operator = "equals"
    if field = "genre" or field = "tag" then operator = "contains"
    if (field = "year" or field = "decade") and PorticoBrowseIsUnsignedInteger(value) then value = Int(Val(value))
    return { field: field, operator: operator, value: value }
end function

function PorticoBrowseMediaItem(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoBrowseSafeId(source.id)
    title = PorticoBrowseSafeText(source.title, 140)
    if id = "" or title = "" then return invalid
    kind = PorticoBrowseMediaKind(source.type)
    model = {
        id: id,
        title: title,
        kind: kind,
        destination: PorticoBrowseDestinationForKind(kind),
        meta: PorticoBrowseSearchMeta(source),
        summary: PorticoBrowseSafeText(source.summary, 360),
        shape: PorticoBrowseShape(kind),
        actions: PorticoContentSafeActions(source.actions),
        watchlisted: source.state <> invalid and Type(source.state) = "roAssociativeArray" and source.state.watchlisted = true,
        favorite: source.state <> invalid and Type(source.state) = "roAssociativeArray" and source.state.favorite = true,
        watched: source.state <> invalid and Type(source.state) = "roAssociativeArray" and source.state.watched = true
    }
    progress = PorticoBrowseProgress(source.state, source.durationSeconds)
    if progress <> invalid then model.progress = progress
    return { model: model, posterSource: PorticoBrowseImageSource(source.images, kind) }
end function

function PorticoBrowseDestinationForKind(kind as string) as string
    if kind = "person" then return "person"
    if kind = "live-channel" or kind = "live-program" then return "live"
    return "detail"
end function

function PorticoBrowseMediaCard(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoBrowseSafeId(source.id)
    title = PorticoBrowseSafeText(source.title, 140)
    if id = "" or title = "" then return invalid
    kind = PorticoBrowseMediaKind(source.entityKind)
    summary = ""
    if source.fields <> invalid and Type(source.fields) = "roAssociativeArray" then summary = PorticoBrowseSafeText(source.fields.summary, 360)
    model = {
        id: id,
        title: title,
        kind: kind,
        destination: PorticoBrowseDestinationForKind(kind),
        meta: PorticoBrowseMediaMeta(source),
        summary: summary,
        shape: PorticoBrowseShape(kind),
        actions: PorticoContentSafeActions(source.actions),
        watchlisted: source.userState <> invalid and Type(source.userState) = "roAssociativeArray" and source.userState.watchlisted = true,
        favorite: source.userState <> invalid and Type(source.userState) = "roAssociativeArray" and source.userState.favorite = true,
        watched: source.userState <> invalid and Type(source.userState) = "roAssociativeArray" and source.userState.watched = true
    }
    progress = PorticoBrowseProgress(source.userState, source.durationSeconds)
    if progress <> invalid then model.progress = progress
    return { model: model, artworkSource: PorticoBrowseImageSource(source.artwork, kind) }
end function

function PorticoBrowseMediaMeta(source as object) as string
    parts = []
    subtitle = PorticoBrowseSafeText(source.subtitle, 100)
    if subtitle = "" then subtitle = PorticoBrowseSafeText(source.tagline, 100)
    if subtitle <> "" then parts.push(subtitle)
    year = PorticoHttpInteger(source.year, 0)
    if year >= 1800 and year <= 2200 then parts.push(year.ToStr())
    duration = PorticoBrowseDuration(source.durationSeconds)
    if duration <> "" then parts.push(duration)
    return PorticoBrowseJoin(parts)
end function

function PorticoBrowseSearchMeta(source as object) as string
    parts = []
    year = PorticoHttpInteger(source.year, 0)
    if year >= 1800 and year <= 2200 then parts.push(year.ToStr())
    kindLabel = PorticoBrowseKindLabel(PorticoBrowseMediaKind(source.type))
    if kindLabel <> "" then parts.push(kindLabel)
    duration = PorticoBrowseDuration(source.durationSeconds)
    if duration <> "" then parts.push(duration)
    parentTitle = PorticoBrowseSafeText(source.parentTitle, 100)
    if parentTitle = "" then parentTitle = PorticoBrowseSafeText(source.grandparentTitle, 100)
    if parentTitle <> "" then parts.push(parentTitle)
    return PorticoBrowseJoin(parts)
end function

function PorticoBrowseProgress(state as dynamic, durationValue as dynamic) as dynamic
    if state = invalid or Type(state) <> "roAssociativeArray" or state.watched = true then return invalid
    progress = PorticoHttpInteger(state.progressSeconds, 0)
    duration = PorticoHttpInteger(durationValue, 0)
    if progress <= 0 or duration <= 0 then return invalid
    value = Int((progress * 100.0) / duration)
    if value <= 0 then return invalid
    if value > 100 then value = 100
    return value
end function

function PorticoBrowseImageSource(images as dynamic, kind as string) as string
    if images = invalid or Type(images) <> "roAssociativeArray" then return ""
    value = images.poster
    if PorticoBrowseShape(kind) = "landscape" then value = images.backdrop
    if value = invalid or value.ToStr() = "" then value = images.thumb
    if value = invalid or value.ToStr() = "" then value = images.poster
    return PorticoBrowseSafeServerResourcePath(value)
end function

function PorticoBrowsePageInfo(source as dynamic) as object
    result = { hasMore: false, nextCursor: "", total: 0 }
    if source = invalid or Type(source) <> "roAssociativeArray" then return result
    cursor = PorticoBrowseSafeCursor(source.nextCursor)
    result.hasMore = source.hasMore = true and cursor <> ""
    result.nextCursor = cursor
    result.total = PorticoHttpInteger(source.total, 0)
    if result.total < 0 then result.total = 0
    return result
end function

function PorticoBrowseLibraryCacheView(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    presentation = LCase(PorticoBrowseSafeText(source.presentation, 24))
    allowedPresentations = { grid: true, list: true, shelves: true, facets: true, resources: true, schedule: true }
    if allowedPresentations[presentation] <> true then presentation = "grid"
    cached = {
        status: "ready",
        libraryName: PorticoBrowseSafeText(source.libraryName, 80),
        serverName: PorticoBrowseSafeText(source.serverName, 100),
        presentation: presentation,
        resultCount: PorticoHttpInteger(source.resultCount, 0),
        tabs: PorticoBrowseCachedTabs(source.tabs),
        actions: [],
        hasMore: false
    }
    if cached.resultCount < 0 then cached.resultCount = 0
    if presentation = "shelves"
        cached.rows = PorticoBrowseCachedRows(source.rows)
    else if presentation = "facets"
        cached.sections = PorticoBrowseCachedSections(source.sections)
    else
        cached.items = PorticoBrowseCachedItems(source.items, 21)
    end if
    return cached
end function

function PorticoBrowseCachedTabs(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each rawTab in source
        if result.count() >= 6 then exit for
        if rawTab <> invalid and Type(rawTab) = "roAssociativeArray"
            id = PorticoBrowseSafeId(rawTab.id)
            label = PorticoBrowseSafeText(rawTab.label, 48)
            if id <> "" and label <> "" then result.push({ id: id, label: label, selected: rawTab.selected = true })
        end if
    end for
    return result
end function

function PorticoBrowseCachedItems(source as dynamic, maximum as integer) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each rawItem in source
        if result.count() >= maximum then exit for
        if rawItem <> invalid and Type(rawItem) = "roAssociativeArray"
            id = PorticoBrowseSafeId(rawItem.id)
            title = PorticoBrowseSafeText(rawItem.title, 140)
            if id <> "" and title <> ""
                item = { id: id, title: title, meta: PorticoBrowseSafeText(rawItem.meta, 140), summary: PorticoBrowseSafeText(rawItem.summary, 360), shape: PorticoBrowseShape(rawItem.shape) }
                progress = PorticoHttpInteger(rawItem.progress, 0)
                if progress > 0
                    if progress > 100 then progress = 100
                    item.progress = progress
                end if
                result.push(item)
            end if
        end if
    end for
    return result
end function

function PorticoBrowseCachedRows(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each rawRow in source
        if result.count() >= 3 then exit for
        if rawRow <> invalid and Type(rawRow) = "roAssociativeArray"
            id = PorticoBrowseSafeId(rawRow.id)
            title = PorticoBrowseSafeText(rawRow.title, 80)
            items = PorticoBrowseCachedItems(rawRow.items, 7)
            if id <> "" and title <> "" and items.count() > 0 then result.push({ id: id, title: title, shape: PorticoBrowseShape(rawRow.shape), items: items })
        end if
    end for
    return result
end function

function PorticoBrowseCachedSections(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each rawSection in source
        if result.count() >= 3 then exit for
        if rawSection <> invalid and Type(rawSection) = "roAssociativeArray"
            id = PorticoBrowseSafeId(rawSection.id)
            title = PorticoBrowseSafeText(rawSection.title, 80)
            items = PorticoBrowseCachedItems(rawSection.items, 12)
            if id <> "" and title <> "" and items.count() > 0 then result.push({ id: id, title: title, items: items })
        end if
    end for
    return result
end function

sub PorticoBrowseStripArtwork(value as dynamic)
    if value = invalid then return
    if Type(value) = "roAssociativeArray"
        value.Delete("poster")
        value.Delete("artwork")
        value.Delete("backdrop")
        for each key in value
            PorticoBrowseStripArtwork(value[key])
        end for
    else if GetInterface(value, "ifArray") <> invalid
        for each item in value
            PorticoBrowseStripArtwork(item)
        end for
    end if
end sub

function PorticoBrowseClone(value as dynamic) as dynamic
    if value = invalid then return invalid
    return ParseJson(FormatJson(value))
end function

function PorticoBrowseSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoBrowseSafeCursor(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 4096 then return ""
    if Instr(1, normalized, Chr(0)) > 0 or Instr(1, normalized, Chr(10)) > 0 or Instr(1, normalized, Chr(13)) > 0 or Instr(1, normalized, Chr(9)) > 0 then return ""
    return normalized
end function

function PorticoBrowseSafeText(value as dynamic, maximumLength as integer) as string
    if value = invalid then return ""
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(normalized) > maximumLength then normalized = Left(normalized, maximumLength)
    return normalized
end function

function PorticoBrowseSafeServerResourcePath(value as dynamic) as string
    return PorticoBrowseSafeApiPath(value)
end function

function PorticoBrowseSearchGroupId(value as dynamic) as string
    id = LCase(PorticoBrowseSafeId(value))
    allowed = { movies: true, shows: true, episodes: true, music: true, audiobooks: true, "live-tv": true }
    if allowed[id] = true then return id
    return ""
end function

function PorticoBrowseLibraryKind(value as dynamic) as string
    kind = LCase(PorticoBrowseSafeText(value, 32))
    allowed = { movie: true, show: true, anime: true, music: true, audiobook: true, "recorded-tv": true }
    if allowed[kind] = true then return kind
    return ""
end function

function PorticoBrowseMediaKind(value as dynamic) as string
    kind = LCase(PorticoBrowseSafeText(value, 48)).Replace("_", "-")
    if kind = "series" then return "show"
    if kind = "audiobook-series" then return "collection"
    if kind = "audiobook" then return "book"
    return kind
end function

function PorticoBrowseKindLabel(kind as string) as string
    if kind = "movie" then return "Movie"
    if kind = "show" then return "TV Show"
    if kind = "season" then return "Season"
    if kind = "episode" then return "Episode"
    if kind = "artist" then return "Artist"
    if kind = "album" then return "Album"
    if kind = "track" then return "Track"
    if kind = "author" then return "Author"
    if kind = "book" then return "Audiobook"
    if kind = "chapter" then return "Chapter"
    if kind = "recording" then return "Recording"
    if kind = "live-channel" then return "Channel"
    if kind = "live-program" then return "Live TV"
    return ""
end function

function PorticoBrowseIsUnsignedInteger(value as string) as boolean
    if value = "" then return false
    allowed = "0123456789"
    for position = 1 to Len(value)
        if Instr(1, allowed, Mid(value, position, 1)) = 0 then return false
    end for
    return true
end function

function PorticoBrowseShape(value as dynamic) as string
    kind = PorticoBrowseMediaKind(value)
    if kind = "square" or kind = "artist" or kind = "album" or kind = "track" or kind = "author" or kind = "book" or kind = "chapter" then return "square"
    if kind = "landscape" or kind = "episode" or kind = "recording" or kind = "live-channel" or kind = "live-program" then return "landscape"
    return "poster"
end function

function PorticoBrowseContainsId(items as object, id as string) as boolean
    for each item in items
        if item <> invalid and Type(item) = "roAssociativeArray" and item.id = id then return true
    end for
    return false
end function

function PorticoBrowseDuration(value as dynamic) as string
    seconds = PorticoHttpInteger(value, 0)
    if seconds <= 0 then return ""
    minutes = Int((seconds + 30) / 60)
    hours = Int(minutes / 60)
    remainder = minutes - (hours * 60)
    if hours <= 0 then return minutes.ToStr() + "m"
    if remainder = 0 then return hours.ToStr() + "h"
    return hours.ToStr() + "h " + remainder.ToStr() + "m"
end function

function PorticoBrowseJoin(parts as object) as string
    result = ""
    separator = "  " + Chr(183) + "  "
    for each part in parts
        if result <> "" then result = result + separator
        result = result + part
    end for
    return result
end function

function PorticoBrowseFacetGroupTitle(id as string) as string
    labels = { genre: "Genres", style: "Styles", year: "Years", decade: "Decades", contentRating: "Ratings", studio: "Studios", artist: "Artists", albumArtist: "Album Artists", tag: "Tags", author: "Authors", narrator: "Narrators", series: "Series", show: "Shows", season: "Seasons", network: "Networks", country: "Countries" }
    label = labels[id]
    if label <> invalid then return label
    if id = "" then return "Categories"
    return UCase(Left(id, 1)) + Mid(id, 2)
end function
