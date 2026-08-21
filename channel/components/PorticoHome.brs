sub init()
    m.hero = m.top.findNode("hero")
    m.rows = m.top.findNode("rows")
    m.availability = m.top.findNode("availability")
    loaded = PorticoProductLanguageLoad()
    m.language = invalid
    if loaded.ok then m.language = loaded.value
    m.rowGroups = []
    for slotIndex = 0 to 2
        rowGroup = CreateObject("roSGNode", "PorticoHomeShelf")
        rowGroup.visible = false
        m.rows.appendChild(rowGroup)
        m.rowGroups.push(rowGroup)
    end for
    m.heroActions = []
    m.heroSignature = ""
    m.availabilitySignature = ""
end sub

sub render()
    model = m.top.model
    if model = invalid or Type(model) <> "roAssociativeArray" then return
    rows = homeRows(model)
    focusedIndices = homeFocusedIndices(m.top.focusedIndices, rows.count())
    heroModel = homeHeroForFocus(model, rows, focusedIndices)
    hasHero = heroModel <> invalid
    scrollY = homeScrollOffset(rows, hasHero)
    m.hero.translation = [0, scrollY]
    m.rows.translation = [0, scrollY]
    nextHeroSignature = homeHeroSignature(heroModel)
    if nextHeroSignature <> m.heroSignature
        m.hero.removeChildrenIndex(m.hero.getChildCount(), 0)
        m.heroActions = []
        if hasHero
            renderHomeHero(heroModel)
        else
            renderEmptyHomeHero()
        end if
        m.heroSignature = nextHeroSignature
    end if
    updateHomeActionFocus()
    nextAvailabilitySignature = homeModelText(model.availabilityStatus, "current")
    if nextAvailabilitySignature <> m.availabilitySignature
        m.availability.removeChildrenIndex(m.availability.getChildCount(), 0)
        renderHomeAvailability(model)
        m.availabilitySignature = nextAvailabilitySignature
    end if
    y = 430
    firstVisibleRow = m.top.focusedRow - 1
    if firstVisibleRow < 0 then firstVisibleRow = 0
    lastVisibleRow = firstVisibleRow + 2
    if lastVisibleRow >= rows.count() then lastVisibleRow = rows.count() - 1
    for slotIndex = 0 to 2
        rowGroup = m.rowGroups[slotIndex]
        rowIndex = firstVisibleRow + slotIndex
        if rowIndex > lastVisibleRow
            rowGroup.visible = false
        else
            row = rows[rowIndex]
            rowGroup.translation = [0, y + (slotIndex * 455)]
            items = homeModelCards(row.items)
            if items.count() > 0
                rowGroup.visible = true
                rowGroup.model = row
                rowGroup.compensation = m.top.compensation
                rowGroup.focused = m.top.focusArea = "homeRows" and rowIndex = m.top.focusedRow
                rowGroup.focusedIndex = focusedIndices[rowIndex]
            else
                rowGroup.visible = false
            end if
        end if
    end for
    publishHomeSemanticFocus(heroModel, rows, focusedIndices)
end sub

sub publishHomeSemanticFocus(heroModel as dynamic, rows as object, focusedIndices as object)
    semanticId = "home.unavailable"
    if m.top.focusArea = "homeActions"
        actions = []
        if heroModel <> invalid then actions = homeUiActionIds(heroModel)
        if m.top.focusedAction >= 0 and m.top.focusedAction < actions.Count() then semanticId = "home.action." + actions[m.top.focusedAction]
    else if m.top.focusArea = "homeRows" and m.top.focusedRow >= 0 and m.top.focusedRow < rows.Count()
        row = rows[m.top.focusedRow]
        items = homeModelCards(row.items)
        itemIndex = focusedIndices[m.top.focusedRow]
        if itemIndex >= 0 and itemIndex < items.Count() then semanticId = "home.row." + homeModelText(row.id, "unknown") + ".item." + homeModelText(items[itemIndex].id, "unknown")
    end if
    m.top.focusSemanticId = semanticId
end sub

function homeHeroSignature(heroModel as dynamic) as string
    if heroModel = invalid or Type(heroModel) <> "roAssociativeArray" then return "none"
    return homeModelText(heroModel.id, "") + "|" + homeModelText(heroModel.title, "") + "|" + homeModelText(heroModel.meta, "") + "|" + homeModelText(heroModel.summary, "") + "|" + homeModelText(heroModel.backdrop, "") + "|" + homeModelText(heroModel.progress, "") + "|" + homeModelText(heroModel.watchlisted, "") + "|" + homeModelText(heroModel.favorite, "")
end function

sub updateHomeActionFocus()
    for index = 0 to m.heroActions.count() - 1
        m.heroActions[index].focused = m.top.focusArea = "homeActions" and m.top.focusedAction = index
    end for
end sub

function homeRows(model as object) as object
    result = []
    if model.rows <> invalid and GetInterface(model.rows, "ifArray") <> invalid
        for each row in model.rows
            ' PorticoContentModels already enforces the authoritative 32-row
            ' safety bound. Do not apply a smaller presentation-only cap here:
            ' it would silently discard valid user/server-customized slots.
            if result.count() >= 32 then exit for
            if row <> invalid and Type(row) = "roAssociativeArray" and homeModelCards(row.items).count() > 0 then result.push(row)
        end for
    end if
    if result.count() = 0
        continueItems = homeModelCards(model.continueWatching)
        recentItems = homeModelCards(model.recentlyAdded)
        if continueItems.count() > 0 then result.push({ id: "continue", title: homeModelText(model.continueWatchingTitle, "Continue Watching"), items: continueItems, hasMore: false })
        if recentItems.count() > 0 then result.push({ id: "recent", title: homeModelText(model.recentlyAddedTitle, "Recently Added"), items: recentItems, hasMore: false })
    end if
    return result
end function

function homeFocusedIndices(source as dynamic, count as integer) as object
    result = []
    for index = 0 to count - 1
        value = 0
        if source <> invalid and GetInterface(source, "ifArray") <> invalid and index < source.count() then value = source[index]
        if value < 0 then value = 0
        result.push(value)
    end for
    return result
end function

function homeHeroForFocus(model as object, rows as object, indices as object) as dynamic
    heroModel = invalid
    if model.hero <> invalid and Type(model.hero) = "roAssociativeArray" then heroModel = model.hero
    continueIndex = homeContinueRowIndex(rows)
    if continueIndex >= 0 and m.top.focusedRow = continueIndex and continueIndex < indices.count()
        items = homeModelCards(rows[continueIndex].items)
        index = indices[continueIndex]
        if index >= 0 and index < items.count() and items[index].hero <> invalid then heroModel = items[index].hero
    end if
    return heroModel
end function

function homeContinueRowIndex(rows as object) as integer
    for index = 0 to rows.count() - 1
        row = rows[index]
        id = LCase(homeModelText(row.id, ""))
        kind = LCase(homeModelText(row.kind, ""))
        policy = LCase(homeModelText(row.policyState, ""))
        if id = "continue" or kind = "continue" or policy = "continue" then return index
    end for
    return -1
end function

function homeScrollOffset(rows as object, hasHero as boolean) as integer
    ' Rows are windowed around focusedRow, so the active three-row window is
    ' already anchored to the safe-area origin and needs no full-list offset.
    return 0
end function

sub renderHomeAvailability(model as object)
    if model.availabilityStatus = invalid or model.availabilityStatus = "current" then return
    label = "OFFLINE"
    if model.availabilityStatus = "refresh-failed" then label = "COULDN'T REFRESH"
    status = PorticoLabel(m.availability, label, [1420, 34], 320, 28, 18, "600", "#E3B341")
    status.horizAlign = "right"
end sub

sub renderHomeHero(heroModel as object)
    titleLines = PorticoBreakText(heroModel.title, 910, 66, "700", 2)
    summaryLines = PorticoBreakText(heroModel.summary, 820, 23, "400", 2)
    if titleLines.count() = 0 then titleLines = [""]
    if summaryLines.count() = 0 then summaryLines = [""]
    PorticoRectangle(m.hero, [0, 0], 1784, 430, "#0A1017")
    if heroModel.backdrop <> invalid and heroModel.backdrop.ToStr() <> "" then PorticoPoster(m.hero, heroModel.backdrop, [0, 0], 1784, 430, "scaleToZoom")
    PorticoPoster(m.hero, "pkg:/images/ui/hero-vertical-home.png", [0, 0], 1784, 430)
    PorticoPoster(m.hero, "pkg:/images/ui/hero-horizontal.png", [0, 0], 1784, 430)
    actionsY = 316
    summaryY = actionsY - 24 - (summaryLines.count() * 32)
    metaY = summaryY - 41
    titleY = metaY - 10 - (69 + ((titleLines.count() - 1) * 72))
    titleCompensation = 0
    if m.top.compensation <> invalid then titleCompensation = m.top.compensation.homeTitleY
    PorticoRenderLines(m.hero, titleLines, [0, titleY + titleCompensation], 910, 72, 66, "700", "#F4F7FA")
    PorticoLabel(m.hero, heroModel.meta, [0, metaY], 910, 29, 22, "600", "#C7D0D8")
    PorticoRenderLines(m.hero, summaryLines, [0, summaryY], 820, 32, 23, "400", "#C7D0D8")
    actionIds = homeUiActionIds(heroModel)
    actionX = 0
    for index = 0 to actionIds.count() - 1
        action = actionIds[index]
        if action = "play"
            button = m.hero.CreateChild("PorticoButton")
            button.translation = [actionX, actionsY]
            label = "Play"
            if heroModel.progress <> invalid then label = "Resume"
            button.model = { label: label, iconId: "playback.play", primary: true, width: 166 }
            button.focused = m.top.focusArea = "homeActions" and m.top.focusedAction = index
            m.heroActions.push(button)
            actionX = actionX + 178
        else
            button = m.hero.CreateChild("PorticoIconButton")
            button.translation = [actionX, actionsY]
            icon = "metadata.info"
            selected = false
            if action = "saved-toggle"
                icon = "action.watchlist"
                selected = heroModel.watchlisted = true
            else if action = "favorite-toggle"
                icon = "action.favorite"
                selected = heroModel.favorite = true
            end if
            button.model = { iconId: icon, selected: selected }
            button.focused = m.top.focusArea = "homeActions" and m.top.focusedAction = index
            m.heroActions.push(button)
            actionX = actionX + 76
        end if
    end for
end sub

sub renderEmptyHomeHero()
    PorticoRectangle(m.hero, [0, 0], 1784, 430, "#0A1017")
    message = ["You haven't watched anything yet.", "What will you watch first?"]
    PorticoRenderLines(m.hero, message, [0, 292], 860, 43, 34, "600", "#C7D0D8")
end sub

function homeUiActionIds(heroModel as object) as object
    if heroModel.uiActions = invalid or GetInterface(heroModel.uiActions, "ifArray") = invalid then return []
    result = []
    allowed = { play: true, "saved-toggle": true, "open-detail": true, "favorite-toggle": true }
    for each rawAction in heroModel.uiActions
        action = LCase(rawAction.ToStr())
        if allowed[action] = true and result.count() < 4 then result.push(action)
    end for
    return result
end function

function homeModelCards(value as dynamic) as object
    if value <> invalid and GetInterface(value, "ifArray") <> invalid then return value
    return []
end function

function homeModelText(value as dynamic, fallback as string) as string
    if value = invalid or value.ToStr().Trim() = "" then return fallback
    return value.ToStr()
end function

function homeCopyText(messageId as string, fallback as string) as string
    if m.language = invalid then return fallback
    copy = PorticoProductLanguageMessage(m.language, messageId, messageId, {})
    value = copy.text
    if value = "" then value = copy.title
    if value = "" then value = copy.body
    if value = "" then value = fallback
    return value
end function
