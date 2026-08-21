sub init()
    m.title = m.top.findNode("title")
    m.querySurface = m.top.findNode("querySurface")
    m.searchIcon = m.top.findNode("searchIcon")
    m.queryText = m.top.findNode("queryText")
    m.clearAction = m.top.findNode("clearAction")
    m.keyboard = m.top.findNode("keyboard")
    m.keyboardSurface = m.top.findNode("keyboardSurface")
    m.searchControls = m.top.findNode("searchControls")
    m.groupControl = m.top.findNode("groupControl")
    m.sortControl = m.top.findNode("sortControl")
    m.directionControl = m.top.findNode("directionControl")
    m.resultsViewport = m.top.findNode("resultsViewport")
    m.resultsCanvas = m.top.findNode("resultsCanvas")
    m.resultsTitle = m.top.findNode("resultsTitle")
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.stateGroup = m.top.findNode("stateGroup")
    m.stateIconBed = m.top.findNode("stateIconBed")
    m.stateIcon = m.top.findNode("stateIcon")
    m.stateTitle = m.top.findNode("stateTitle")
    m.stateMessages = [m.top.findNode("stateMessage0"), m.top.findNode("stateMessage1"), m.top.findNode("stateMessage2")]
    m.retryAction = m.top.findNode("retryAction")
    m.quickActions = m.top.findNode("quickActions")
    m.recentGroup = m.top.findNode("recentGroup")
    m.recentTitle = m.top.findNode("recentTitle")
    m.clearHistory = m.top.findNode("clearHistory")
    m.recentActions = []
    for index = 0 to 4
        m.recentActions.push(m.top.findNode("recent" + index.ToStr()))
    end for
    m.groupTitles = []
    m.results = []
    m.moreActions = []
    m.keys = []
    for index = 0 to 5
        m.groupTitles.push(m.top.findNode("groupTitle" + index.ToStr()))
        m.moreActions.push(m.top.findNode("more" + index.ToStr()))
    end for
    for index = 0 to 23
        m.results.push(m.top.findNode("result" + index.ToStr()))
    end for
    for index = 0 to 39
        keyNode = m.top.findNode("key" + index.ToStr())
        keyNode.translation = [22 + ((index mod 10) * 112), 20 + (Int(index / 10) * 64)]
        m.keys.push(keyNode)
    end for

    m.title.font = PorticoFont("700", 48)
    m.title.color = "#F4F7FA"
    loadedLanguage = PorticoProductLanguageLoad()
    m.language = invalid
    if loadedLanguage.ok then m.language = loadedLanguage.value
    m.title.text = PorticoSearchCopyText("search.start-title", "Search")
    m.queryText.font = PorticoFont("400", 24)
    m.resultsTitle.font = PorticoFont("600", 30)
    m.resultsTitle.color = "#F4F7FA"
    m.loadingLabel.font = PorticoFont("600", 30)
    m.loadingLabel.color = "#F4F7FA"
    m.recentTitle.font = PorticoFont("600", 30)
    m.recentTitle.color = "#F4F7FA"
    for each groupTitle in m.groupTitles
        groupTitle.font = PorticoFont("600", 30)
        groupTitle.color = "#F4F7FA"
    end for
    m.stateTitle.font = PorticoFont("600", 30)
    m.stateTitle.color = "#F4F7FA"
    for each line in m.stateMessages
        line.font = PorticoFont("400", 20)
        line.color = "#8F9BA6"
    end for
    m.searchIcon.uri = PorticoIconResolverPackageUri("navigation.search", "rail")
    m.keyboardSurface.uri = "pkg:/images/ui/search-keyboard-panel.png"
    m.stateIconBed.uri = "pkg:/images/ui/state-icon-bed.png"
    m.stateIcon.uri = PorticoIconResolverPackageUri("status.warning", "rail")
    m.clearAction.model = {iconId: "action.close", selected: false}
    m.keyModels = PorticoSearchKeyboardModels()
    for index = 0 to m.keys.count() - 1
        m.keys[index].model = m.keyModels[index]
    end for

    m.top.focusable = true
    m.focusArea = "query"
    m.focusIndex = 0
    m.keyboardIndex = 0
    m.keyboardVisible = false
    m.query = ""
    m.queryRevision = 0
    m.confirmClearHistory = false
    m.activationSequence = 0
    m.resultsScroll = 0
    m.resultTargets = []
    m.quickActionsOpen = false
    m.quickActionIndex = 0
    m.quickActionTarget = invalid
    m.controlIndex = 0
    m.recentIndex = 0
    m.keyboardReturnArea = "query"
    m.keyboardReturnIndex = 0
    m.hasViewState = false
    m.screenAuthority = PorticoScreenAuthorityCreate("search")
end sub

function PorticoSearchKeyboardModels() as object
    values = [
        "A","B","C","D","E","F","G","H","I","J",
        "K","L","M","N","O","P","Q","R","S","T",
        "U","V","W","X","Y","Z","0","1","2","3",
        "4","5","6","7","8","9","SPACE","DEL","CLEAR","SEARCH"
    ]
    models = []
    for each value in values
        action = "character"
        keyValue = value
        if value = "SPACE"
            action = "space"
            keyValue = " "
        else if value = "DEL"
            action = "delete"
            keyValue = ""
        else if value = "CLEAR"
            action = "clear"
            keyValue = ""
        else if value = "SEARCH"
            action = "submit"
            keyValue = ""
        end if
        models.push({label: value, action: action, value: keyValue})
    end for
    return models
end function

sub applyViewState()
    state = m.top.viewState
    if state = invalid then return
    PorticoScreenAuthorityFence(m.screenAuthority, PorticoSearchSafeInteger(state.viewerGeneration, 0))
    incomingRevision = 0
    if state.queryRevision <> invalid then incomingRevision = PorticoSearchSafeInteger(state.queryRevision, 0)
    if not m.hasViewState or incomingRevision >= m.queryRevision
        if state.query <> invalid then m.query = PorticoSearchSafeText(state.query, 120)
        m.queryRevision = incomingRevision
    end if
    if not m.hasViewState
        if state.focusArea <> invalid then m.focusArea = state.focusArea.ToStr()
        if state.focusIndex <> invalid then m.focusIndex = PorticoSearchSafeInteger(state.focusIndex, 0)
        if state.keyboardIndex <> invalid then m.keyboardIndex = PorticoSearchSafeInteger(state.keyboardIndex, 0)
    end if
    m.hasViewState = true
    renderSearch()
end sub

sub renderSearch()
    state = m.top.viewState
    if state = invalid then return
    status = LCase(PorticoSearchSafeText(state.status, 24))
    if status <> "loading" and status <> "ready" and status <> "empty" and status <> "error" then status = "idle"
    if Len(m.query.Trim()) < 2 then status = "idle"

    fieldFocused = m.focusArea = "query" or m.focusArea = "clear"
    if fieldFocused
        m.querySurface.uri = "pkg:/images/ui/search-field-focus.png"
    else
        m.querySurface.uri = "pkg:/images/ui/search-field-idle.png"
    end if
    if m.query = ""
        m.queryText.text = PorticoSearchCopyText("search.start-title", "Search")
        m.queryText.color = "#687581"
    else
        m.queryText.text = m.query
        m.queryText.color = "#F4F7FA"
    end if
    m.clearAction.visible = m.query <> ""
    m.clearAction.focused = m.focusArea = "clear"
    m.keyboard.visible = m.keyboardVisible
    m.searchControls.visible = not m.keyboardVisible
    renderSearchControls(state)
    m.resultsViewport.visible = false
    m.loadingLabel.visible = false
    m.stateGroup.visible = false
    m.retryAction.visible = false
    m.recentGroup.visible = false
    if m.keyboardVisible
        renderKeyboard()
        publishFocus()
        return
    end if

    if status = "loading"
        m.loadingLabel.text = PorticoSearchCopyText("search.loading", "Searching")
        m.loadingLabel.visible = true
    else if status = "ready"
        buildResults(state)
        if m.resultTargets.count() > 0
            m.resultsViewport.visible = true
        else
            renderStateFromMessage("search.no-results", "")
        end if
    else if status = "error"
        messageId = PorticoSearchSafeText(state.messageId, 120)
        if messageId = "" then messageId = "search.load-failed"
        renderStateFromMessage(messageId, PorticoSearchCopyText("action.retry", "Try again"))
    else if status = "empty"
        renderStateFromMessage("search.no-results", "")
    else
        if not renderRecentSearches(state) then renderStateFromMessage("search.start-title", "")
    end if
    renderSearchQuickActions()
    publishFocus()
end sub

sub renderSearchControls(state as object)
    controls = state.controls
    if controls = invalid or Type(controls) <> "roAssociativeArray"
        m.searchControls.visible = false
        return
    end if
    groupLabel = "All"
    groups = controls.groups
    if groups <> invalid and GetInterface(groups, "ifArray") <> invalid
        for each item in groups
            if item <> invalid and Type(item) = "roAssociativeArray" and item.selected = true then groupLabel = PorticoSearchSafeText(item.label, 40)
        end for
    end if
    sortLabel = "Relevance"
    sorts = controls.sorts
    if sorts <> invalid and GetInterface(sorts, "ifArray") <> invalid
        for each item in sorts
            if item <> invalid and Type(item) = "roAssociativeArray" and item.selected = true then sortLabel = PorticoSearchSafeText(item.label, 40)
        end for
    end if
    direction = PorticoSearchSafeText(controls.direction, 8)
    directionLabel = PorticoSearchCopyText("search.order-descending", "Descending")
    if direction = "asc" then directionLabel = PorticoSearchCopyText("search.order-ascending", "Ascending")
    m.groupControl.model = {label: groupLabel, iconId: "view.list", primary: false, width: 280}
    m.sortControl.model = {label: sortLabel, iconId: "action.sort", primary: false, width: 280}
    m.directionControl.model = {label: directionLabel, iconId: "action.sort", primary: false, width: 310}
    m.groupControl.focused = m.focusArea = "controls" and m.controlIndex = 0
    m.sortControl.focused = m.focusArea = "controls" and m.controlIndex = 1
    m.directionControl.focused = m.focusArea = "controls" and m.controlIndex = 2
end sub

function renderRecentSearches(state as object) as boolean
    queries = state.recentQueries
    if queries = invalid or GetInterface(queries, "ifArray") = invalid or queries.count() = 0 then return false
    m.stateGroup.visible = false
    m.recentGroup.visible = true
    m.recentTitle.text = PorticoSearchCopyText("search.recent-title", "Recent searches")
    for index = 0 to m.recentActions.count() - 1
        node = m.recentActions[index]
        node.visible = index < queries.count()
        if index < queries.count()
            query = PorticoSearchSafeText(queries[index], 120)
            node.model = {label: query, iconId: "navigation.search", primary: false, width: 276}
            node.focused = m.focusArea = "recent" and m.recentIndex = index
        end if
    end for
    clearLabel = PorticoSearchCopyText("action.clear", "Clear")
    if m.confirmClearHistory then clearLabel = "Press OK to confirm"
    m.clearHistory.model = {label: clearLabel, iconId: "action.close", primary: m.confirmClearHistory, width: 240}
    m.clearHistory.visible = true
    m.clearHistory.focused = m.focusArea = "recent-clear"
    return true
end function

sub renderStateFromMessage(messageId as string, actionLabel as string)
    copy = PorticoSearchCopy(messageId, "search.load-failed")
    title = copy.title
    if title = "" then title = copy.text
    renderState(title, copy.body, actionLabel)
end sub

sub renderKeyboard()
    if m.keyboardIndex < 0 then m.keyboardIndex = 0
    if m.keyboardIndex >= m.keys.count() then m.keyboardIndex = m.keys.count() - 1
    for index = 0 to m.keys.count() - 1
        m.keys[index].focused = m.focusArea = "keyboard" and index = m.keyboardIndex
    end for
end sub

sub resetResultNodes()
    for each title in m.groupTitles
        title.visible = false
        title.text = ""
    end for
    for each result in m.results
        result.visible = false
        result.focused = false
    end for
    for each action in m.moreActions
        action.visible = false
        action.focused = false
    end for
    m.resultTargets = []
end sub

sub buildResults(state as object)
    resetResultNodes()
    submittedQuery = m.query.Trim()
    if state.submittedQuery <> invalid then submittedQuery = PorticoSearchSafeText(state.submittedQuery, 120)
    m.resultsTitle.text = "Results for " + Chr(34) + submittedQuery + Chr(34)
    m.resultsTitle.translation = [0, 0]
    groups = state.groups
    if groups = invalid or GetInterface(groups, "ifArray") = invalid then groups = []
    y = 58
    resultNodeIndex = 0
    groupNodeIndex = 0
    for each group in groups
        if groupNodeIndex >= m.groupTitles.count() or resultNodeIndex >= m.results.count() then exit for
        if group <> invalid and Type(group) = "roAssociativeArray"
            items = group.items
            if items = invalid or GetInterface(items, "ifArray") = invalid then items = []
            groupId = PorticoSearchSafeId(group.id)
            groupLabel = PorticoSearchSafeText(group.title, 80)
            if groupId <> "" and groupLabel <> ""
                groupTitle = m.groupTitles[groupNodeIndex]
                groupStatus = LCase(PorticoSearchSafeText(group.status, 24))
                groupTitle.text = groupLabel
                if groupStatus = "error" then groupTitle.text = groupLabel + "  ·  " + PorticoSearchCopyText("search.group-unavailable", "Unavailable")
                if groupStatus = "empty" then groupTitle.text = groupLabel + "  ·  " + PorticoSearchCopyText("search.filtered-empty", "No results")
                groupTitle.translation = [0, y]
                groupTitle.visible = true
                y = y + 52
                itemInGroup = 0
                for each item in items
                    if itemInGroup >= 4 or resultNodeIndex >= m.results.count() then exit for
                    if item <> invalid and Type(item) = "roAssociativeArray"
                        normalized = PorticoSearchResultModel(item)
                    else
                        normalized = invalid
                    end if
                    if normalized <> invalid
                        column = itemInGroup mod 2
                        row = Int(itemInGroup / 2)
                        x = column * 858
                        itemY = y + (row * 186)
                        node = m.results[resultNodeIndex]
                        node.model = normalized
                        node.translation = [x, itemY]
                        node.visible = true
                        target = {kind: "result", id: normalized.id, groupId: groupId, x: x, y: itemY, width: 846, height: 174, node: node, model: normalized}
                        m.resultTargets.push(target)
                        resultNodeIndex = resultNodeIndex + 1
                        itemInGroup = itemInGroup + 1
                    end if
                end for
                rows = Int((itemInGroup + 1) / 2)
                y = y + (rows * 186)
                if group.hasMore = true and groupNodeIndex < m.moreActions.count()
                    action = m.moreActions[groupNodeIndex]
                    groupTitleValue = PorticoSearchSafeText(groupLabel, 50)
                    action.model = {label: "More " + LCase(groupTitleValue), iconId: "action.add", primary: false, width: 270}
                    action.translation = [0, y]
                    action.visible = true
                    m.resultTargets.push({kind: "more", id: groupId, groupId: groupId, x: 0, y: y, width: 270, height: 64, node: action})
                    y = y + 80
                end if
                y = y + 28
                groupNodeIndex = groupNodeIndex + 1
            end if
        end if
    end for
    if m.focusIndex < 0 then m.focusIndex = 0
    if m.focusIndex >= m.resultTargets.count() then m.focusIndex = m.resultTargets.count() - 1
    for index = 0 to m.resultTargets.count() - 1
        m.resultTargets[index].node.focused = m.focusArea = "results" and index = m.focusIndex
    end for
    updateResultsScroll()
end sub

function PorticoSearchResultModel(source as object) as dynamic
    id = PorticoSearchSafeId(source.id)
    title = PorticoSearchSafeText(source.title, 100)
    if id = "" or title = "" then return invalid
    return {
        id: id,
        title: title,
        meta: PorticoSearchSafeText(source.meta, 120),
        summary: PorticoSearchSafeText(source.summary, 240),
        kind: PorticoSearchSafeText(source.kind, 40),
        destination: PorticoSearchSafeText(source.destination, 40),
        poster: PorticoSearchSafeUri(source.poster),
        actions: source.actions,
        watchlisted: source.watchlisted = true,
        favorite: source.favorite = true,
        watched: source.watched = true
    }
end function

sub renderSearchQuickActions()
    m.quickActions.visible = false
    if not m.quickActionsOpen or m.quickActionTarget = invalid then return
    panel = PorticoMediaQuickActionsModel(m.quickActionTarget)
    if panel.actions.count() = 0
        m.quickActionsOpen = false
        m.quickActionTarget = invalid
        return
    end if
    if m.quickActionIndex >= panel.actions.count() then m.quickActionIndex = panel.actions.count() - 1
    if m.quickActionIndex < 0 then m.quickActionIndex = 0
    m.quickActions.model = panel
    m.quickActions.focusedAction = m.quickActionIndex
    m.quickActions.visible = true
end sub

sub openSearchQuickActions()
    if m.focusArea <> "results" or m.focusIndex < 0 or m.focusIndex >= m.resultTargets.count() then return
    target = m.resultTargets[m.focusIndex]
    if target.kind <> "result" or PorticoMediaQuickActionIds(target.model).count() = 0 then return
    PorticoScreenAuthorityOpenModal(m.screenAuthority, PorticoSearchSemanticFocusId())
    m.quickActionTarget = target.model
    m.quickActionIndex = 0
    m.quickActionsOpen = true
end sub

function PorticoSearchSafeInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" or valueType = "float" or valueType = "rofloat" or valueType = "double" or valueType = "rodouble" then return Int(value)
    if valueType = "string" or valueType = "rostring"
        normalized = value.Trim()
        if normalized <> "" then return Int(Val(normalized))
    end if
    return fallback
end function

sub updateResultsScroll()
    if m.focusArea <> "results" or m.resultTargets.count() = 0
        m.resultsCanvas.translation = [0, -m.resultsScroll]
        return
    end if
    target = m.resultTargets[m.focusIndex]
    top = target.y - m.resultsScroll
    bottom = top + target.height
    if bottom > 820 then m.resultsScroll = m.resultsScroll + (bottom - 820)
    if top < 58 then m.resultsScroll = m.resultsScroll - (58 - top)
    if m.resultsScroll < 0 then m.resultsScroll = 0
    m.resultsCanvas.translation = [0, -m.resultsScroll]
end sub

sub renderState(title as string, message as string, actionLabel as string)
    m.stateGroup.visible = true
    m.stateTitle.text = title
    lines = PorticoBreakText(message, 640, 20, "400", 3)
    for index = 0 to m.stateMessages.count() - 1
        m.stateMessages[index].visible = index < lines.count()
        m.stateMessages[index].text = ""
        if index < lines.count() then m.stateMessages[index].text = lines[index]
    end for
    if actionLabel <> ""
        m.retryAction.model = {label: actionLabel, iconId: "action.retry", primary: true, width: 190}
        m.retryAction.focused = m.focusArea = "retry"
        m.retryAction.visible = true
    end if
end sub

sub publishFocus()
    semanticId = PorticoSearchSemanticFocusId()
    semanticIds = ["search.query"]
    if m.query <> "" then semanticIds.Push("search.action.clear")
    for each keyModel in m.keyModels
        semanticIds.Push("search.keyboard." + LCase(keyModel.value))
    end for
    semanticIds.Push("search.control.group")
    semanticIds.Push("search.control.sort")
    semanticIds.Push("search.control.direction")
    if m.retryAction.visible then semanticIds.Push("search.action.retry")
    recentCount = 0
    if m.top.viewState <> invalid and m.top.viewState.recentQueries <> invalid then recentCount = m.top.viewState.recentQueries.Count()
    for index = 0 to recentCount - 1
        semanticIds.Push("search.recent.slot." + index.ToStr())
    end for
    if recentCount > 0 then semanticIds.Push("search.action.clear-history")
    for each target in m.resultTargets
        if target.kind = "more" then semanticIds.Push("search.group." + target.groupId + ".more") else semanticIds.Push("search.result." + target.id)
    end for
    PorticoScreenAuthorityTargets(m.screenAuthority, semanticIds)
    PorticoScreenAuthorityFocused(m.screenAuthority, semanticId)
    m.top.focusState = {
        area: m.focusArea,
        index: m.focusIndex,
        keyboardIndex: m.keyboardIndex,
        keyboardVisible: m.keyboardVisible,
        resultsOffset: m.resultsScroll
    }
end sub

function PorticoSearchSemanticFocusId() as string
    if m.focusArea = "query" then return "search.query"
    if m.focusArea = "clear" then return "search.action.clear"
    if m.focusArea = "keyboard" and m.keyboardIndex >= 0 and m.keyboardIndex < m.keyModels.Count() then return "search.keyboard." + LCase(m.keyModels[m.keyboardIndex].value)
    if m.focusArea = "controls"
        ids = ["group", "sort", "direction"]
        if m.controlIndex >= 0 and m.controlIndex < ids.Count() then return "search.control." + ids[m.controlIndex]
    end if
    if m.focusArea = "retry" then return "search.action.retry"
    if m.focusArea = "recent" then return "search.recent.slot." + m.recentIndex.ToStr()
    if m.focusArea = "recent-clear" then return "search.action.clear-history"
    if m.focusArea = "results" and m.focusIndex >= 0 and m.focusIndex < m.resultTargets.Count()
        target = m.resultTargets[m.focusIndex]
        if target.kind = "more" then return "search.group." + target.groupId + ".more"
        return "search.result." + target.id
    end if
    if m.quickActionsOpen and m.quickActionTarget <> invalid then return "search.quick-action." + m.quickActionTarget.id + "." + m.quickActionIndex.ToStr()
    return "search.unavailable"
end function

sub emitSearchActivation(kind as string, targetId as string)
    PorticoScreenAuthorityCommitOK(m.screenAuthority)
    m.activationSequence = m.activationSequence + 1
    m.top.activation = {
        sequence: m.activationSequence,
        kind: kind,
        targetId: targetId,
        query: m.query,
        queryRevision: m.queryRevision
    }
end sub

sub queryChanged(kind as string)
    m.queryRevision = m.queryRevision + 1
    emitSearchActivation(kind, "search")
end sub

function PorticoSearchMoveResult(horizontal as integer, vertical as integer) as boolean
    if m.resultTargets.count() = 0 then return false
    current = m.resultTargets[m.focusIndex]
    bestIndex = -1
    bestScore = 2147483647
    for index = 0 to m.resultTargets.count() - 1
        if index <> m.focusIndex
            candidate = m.resultTargets[index]
            deltaX = candidate.x - current.x
            deltaY = candidate.y - current.y
            acceptable = false
            primary = 0
            secondary = 0
            if horizontal < 0 and deltaX < 0
                acceptable = true
                primary = -deltaX
                secondary = Abs(deltaY)
            else if horizontal > 0 and deltaX > 0
                acceptable = true
                primary = deltaX
                secondary = Abs(deltaY)
            else if vertical < 0 and deltaY < 0
                acceptable = true
                primary = -deltaY
                secondary = Abs(deltaX)
            else if vertical > 0 and deltaY > 0
                acceptable = true
                primary = deltaY
                secondary = Abs(deltaX)
            end if
            if acceptable
                score = (primary * 10) + secondary
                if score < bestScore
                    bestScore = score
                    bestIndex = index
                end if
            end if
        end if
    end for
    if bestIndex >= 0
        m.focusIndex = bestIndex
        return true
    end if
    return false
end function

sub activateKeyboardKey()
    model = m.keyModels[m.keyboardIndex]
    if model.action = "character" or model.action = "space"
        if Len(m.query) < 120
            m.query = m.query + model.value
            queryChanged("query-changed")
        end if
    else if model.action = "delete"
        if Len(m.query) > 0
            m.query = Left(m.query, Len(m.query) - 1)
            queryChanged("query-changed")
        end if
    else if model.action = "clear"
        if m.query <> ""
            m.query = ""
            queryChanged("clear-search")
        end if
    else if model.action = "submit"
        if Len(m.query.Trim()) >= 2
            m.keyboardVisible = false
            m.focusArea = m.keyboardReturnArea
            m.focusIndex = m.keyboardReturnIndex
            emitSearchActivation("submit-search", "search")
        end if
    end if
end sub

sub cycleSearchGroup()
    state = m.top.viewState
    if state = invalid or state.controls = invalid or state.controls.groups = invalid then return
    groups = state.controls.groups
    if GetInterface(groups, "ifArray") = invalid or groups.count() = 0 then return
    current = -1
    for index = 0 to groups.count() - 1
        if groups[index].selected = true then current = index
    end for
    nextIndex = current + 1
    if nextIndex >= groups.count() then nextIndex = 0
    emitSearchActivation("select-search-group", PorticoSearchSafeId(groups[nextIndex].id))
end sub

sub activateRecent(index as integer)
    state = m.top.viewState
    if state = invalid or state.recentQueries = invalid or GetInterface(state.recentQueries, "ifArray") = invalid then return
    if index < 0 or index >= state.recentQueries.count() then return
    m.query = PorticoSearchSafeText(state.recentQueries[index], 120)
    m.queryRevision = m.queryRevision + 1
    emitSearchActivation("select-recent-search", "search")
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        PorticoScreenAuthorityRelease(m.screenAuthority, key)
        return false
    end if
    if key = "back"
        if m.confirmClearHistory
            m.confirmClearHistory = false
            PorticoScreenAuthorityCloseModal(m.screenAuthority, "search.action.clear-history")
            renderSearch()
            return true
        end if
        if m.quickActionsOpen
            m.quickActionsOpen = false
            m.quickActionTarget = invalid
            PorticoScreenAuthorityCloseModal(m.screenAuthority, "search.query")
            renderSearch()
            return true
        end if
        if m.keyboardVisible
            m.keyboardVisible = false
            m.focusArea = m.keyboardReturnArea
            m.focusIndex = m.keyboardReturnIndex
            restoredId = PorticoScreenAuthorityCloseModal(m.screenAuthority, "search.query")
            PorticoScreenAuthorityFocused(m.screenAuthority, restoredId)
            renderSearch()
            return true
        end if
        return false
    end if

    if key = "options"
        if m.quickActionsOpen
            m.quickActionsOpen = false
            m.quickActionTarget = invalid
        else
            openSearchQuickActions()
        end if
        renderSearch()
        return true
    end if

    if m.quickActionsOpen
        actions = PorticoMediaQuickActionIds(m.quickActionTarget)
        if key = "up"
            if m.quickActionIndex > 0 then m.quickActionIndex = m.quickActionIndex - 1
        else if key = "down"
            if m.quickActionIndex < actions.count() - 1 then m.quickActionIndex = m.quickActionIndex + 1
        else if key = "OK"
            if m.quickActionIndex >= 0 and m.quickActionIndex < actions.count()
                semanticId = "search." + m.quickActions.focusSemanticId + "." + m.quickActionTarget.id
                if not PorticoScreenAuthorityBeginOK(m.screenAuthority, semanticId) then return true
                emitSearchActivation(actions[m.quickActionIndex], m.quickActionTarget.id)
                m.quickActionsOpen = false
                m.quickActionTarget = invalid
                PorticoScreenAuthorityCloseModal(m.screenAuthority, "search.query")
            end if
        else
            return true
        end if
        renderSearch()
        return true
    end if

    previousArea = m.focusArea
    previousFocusIndex = m.focusIndex
    previousKeyboardIndex = m.keyboardIndex
    previousControlIndex = m.controlIndex
    previousRecentIndex = m.recentIndex
    previousSemanticId = PorticoSearchSemanticFocusId()

    if key = "left"
        if m.focusArea = "query" then return false
        if m.focusArea = "clear"
            m.focusArea = "query"
        else if m.focusArea = "keyboard"
            if (m.keyboardIndex mod 10) > 0 then m.keyboardIndex = m.keyboardIndex - 1
        else if m.focusArea = "controls"
            if m.controlIndex > 0 then m.controlIndex = m.controlIndex - 1 else return false
        else if m.focusArea = "recent"
            if m.recentIndex > 0 then m.recentIndex = m.recentIndex - 1 else return false
        else if m.focusArea = "recent-clear"
            return false
        else if m.focusArea = "results"
            if not PorticoSearchMoveResult(-1, 0) then return false
        end if
    else if key = "right"
        if m.focusArea = "query"
            if m.query <> "" then m.focusArea = "clear"
        else if m.focusArea = "clear"
            return true
        else if m.focusArea = "keyboard"
            if (m.keyboardIndex mod 10) < 9 then m.keyboardIndex = m.keyboardIndex + 1
        else if m.focusArea = "controls"
            if m.controlIndex < 2 then m.controlIndex = m.controlIndex + 1
        else if m.focusArea = "recent"
            recentCount = 0
            if m.top.viewState.recentQueries <> invalid then recentCount = m.top.viewState.recentQueries.count()
            if m.recentIndex < recentCount - 1 and m.recentIndex < 4 then m.recentIndex = m.recentIndex + 1
        else if m.focusArea = "results"
            PorticoSearchMoveResult(1, 0)
        end if
    else if key = "down"
        if m.focusArea = "query" or m.focusArea = "clear"
            if m.keyboardVisible
                m.focusArea = "keyboard"
            else if m.searchControls.visible
                m.focusArea = "controls"
            else if m.retryAction.visible
                m.focusArea = "retry"
            else if m.resultTargets.count() > 0
                m.focusArea = "results"
                m.focusIndex = 0
            end if
        else if m.focusArea = "keyboard"
            if m.keyboardIndex < 30 then m.keyboardIndex = m.keyboardIndex + 10
        else if m.focusArea = "controls"
            if m.retryAction.visible
                m.focusArea = "retry"
            else if m.recentGroup.visible
                m.focusArea = "recent"
                m.recentIndex = 0
            else if m.resultTargets.count() > 0
                m.focusArea = "results"
                m.focusIndex = 0
            end if
        else if m.focusArea = "recent"
            m.focusArea = "recent-clear"
        else if m.focusArea = "results"
            PorticoSearchMoveResult(0, 1)
        end if
    else if key = "up"
        if m.focusArea = "keyboard"
            if m.keyboardIndex >= 10
                m.keyboardIndex = m.keyboardIndex - 10
            else
                m.focusArea = "query"
            end if
        else if m.focusArea = "retry"
            if m.searchControls.visible then m.focusArea = "controls" else m.focusArea = "query"
        else if m.focusArea = "controls"
            m.focusArea = "query"
        else if m.focusArea = "recent"
            if m.searchControls.visible then m.focusArea = "controls" else m.focusArea = "query"
        else if m.focusArea = "recent-clear"
            m.focusArea = "recent"
        else if m.focusArea = "results"
            if not PorticoSearchMoveResult(0, -1) then m.focusArea = "query"
        end if
    else if key = "OK"
        if not PorticoScreenAuthorityBeginOK(m.screenAuthority, PorticoSearchSemanticFocusId()) then return true
        if m.focusArea = "query"
            m.keyboardReturnArea = "query"
            m.keyboardReturnIndex = m.focusIndex
            m.keyboardVisible = true
            PorticoScreenAuthorityOpenModal(m.screenAuthority, "search.query")
            m.focusArea = "keyboard"
        else if m.focusArea = "clear"
            m.query = ""
            m.focusArea = "query"
            queryChanged("clear-search")
        else if m.focusArea = "keyboard"
            activateKeyboardKey()
        else if m.focusArea = "retry"
            emitSearchActivation("retry-search", "search")
        else if m.focusArea = "controls"
            if m.controlIndex = 0
                cycleSearchGroup()
            else if m.controlIndex = 1
                emitSearchActivation("cycle-search-sort", "search")
            else
                emitSearchActivation("toggle-search-direction", "search")
            end if
        else if m.focusArea = "recent"
            activateRecent(m.recentIndex)
        else if m.focusArea = "recent-clear"
            if m.confirmClearHistory
                m.confirmClearHistory = false
                emitSearchActivation("clear-search-history", "search")
                PorticoScreenAuthorityCloseModal(m.screenAuthority, "search.action.clear-history")
            else
                m.confirmClearHistory = true
                PorticoScreenAuthorityOpenModal(m.screenAuthority, "search.action.clear-history")
            end if
        else if m.focusArea = "results" and m.focusIndex >= 0 and m.focusIndex < m.resultTargets.count()
            target = m.resultTargets[m.focusIndex]
            if target.kind = "more"
                emitSearchActivation("load-more", target.groupId)
            else if target.model.destination = "person" or target.model.kind = "person"
                m.activationSequence = m.activationSequence + 1
                m.top.activation = {sequence: m.activationSequence, kind: "select-person", targetId: target.id, personName: target.model.title, query: m.query, queryRevision: m.queryRevision}
            else if target.model.destination = "live" or target.model.kind = "live-channel"
                m.activationSequence = m.activationSequence + 1
                m.top.activation = {sequence: m.activationSequence, kind: "play-live", targetId: target.id, title: target.model.title, meta: target.model.meta, query: m.query, queryRevision: m.queryRevision}
            else
                emitSearchActivation("open-detail", target.id)
            end if
        end if
    else
        return false
    end if
    if key = "left" or key = "right" or key = "up" or key = "down"
        nextSemanticId = PorticoSearchSemanticFocusId()
        if nextSemanticId <> previousSemanticId and not PorticoScreenAuthorityAcceptMove(m.screenAuthority, key, previousSemanticId, nextSemanticId)
            m.focusArea = previousArea
            m.focusIndex = previousFocusIndex
            m.keyboardIndex = previousKeyboardIndex
            m.controlIndex = previousControlIndex
            m.recentIndex = previousRecentIndex
        end if
    end if
    renderSearch()
    return true
end function

function PorticoSearchSafeText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function

function PorticoSearchSafeId(value as dynamic) as string
    normalized = PorticoSearchSafeText(value, 128)
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoSearchSafeUri(value as dynamic) as string
    normalized = PorticoSearchSafeText(value, 512)
    if Left(normalized, 5) = "pkg:/" or Left(normalized, 5) = "tmp:/" then return normalized
    return ""
end function

function PorticoSearchCopy(messageId as string, fallbackId as string) as object
    if m.language = invalid then return {title: "", body: "", text: ""}
    return PorticoProductLanguageMessage(m.language, messageId, fallbackId, {})
end function

function PorticoSearchCopyText(messageId as string, fallback as string) as string
    copy = PorticoSearchCopy(messageId, messageId)
    value = copy.text
    if value = "" then value = copy.title
    if value = "" then value = fallback
    return value
end function
