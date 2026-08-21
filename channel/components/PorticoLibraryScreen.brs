sub init()
    m.libraryTitle = m.top.findNode("libraryTitle")
    m.serverLabel = m.top.findNode("serverLabel")
    m.availabilityLabel = m.top.findNode("availabilityLabel")
    m.resultCount = m.top.findNode("resultCount")
    m.contentViewport = m.top.findNode("contentViewport")
    m.contentCanvas = m.top.findNode("contentCanvas")
    m.skeletonGrid = m.top.findNode("skeletonGrid")
    m.stateGroup = m.top.findNode("stateGroup")
    m.stateIconBed = m.top.findNode("stateIconBed")
    m.stateIcon = m.top.findNode("stateIcon")
    m.stateTitle = m.top.findNode("stateTitle")
    m.stateMessages = [m.top.findNode("stateMessage0"), m.top.findNode("stateMessage1"), m.top.findNode("stateMessage2")]
    m.retryAction = m.top.findNode("retryAction")
    m.loadMoreAction = m.top.findNode("loadMoreAction")
    m.quickActions = m.top.findNode("quickActions")
    m.alphabetIndexRail = m.top.findNode("alphabetIndexRail")
    m.filterOverlay = m.top.findNode("filterOverlay")
    m.filterOverlay.ObserveField("activation", "filterOverlayActivationChanged")
    m.tabs = []
    m.toolbarActions = []
    m.sectionTitles = []
    m.cards = []
    m.listRows = []
    m.tiles = []
    for index = 0 to 5
        m.tabs.push(m.top.findNode("tab" + index.ToStr()))
    end for
    for index = 0 to 3
        m.toolbarActions.push(m.top.findNode("toolbar" + index.ToStr()))
    end for
    for index = 0 to 2
        title = m.top.findNode("sectionTitle" + index.ToStr())
        title.font = PorticoFont("600", 30)
        title.color = "#F4F7FA"
        m.sectionTitles.push(title)
    end for
    for index = 0 to 20
        m.cards.push(m.top.findNode("card" + index.ToStr()))
    end for
    for index = 0 to 11
        m.listRows.push(m.top.findNode("list" + index.ToStr()))
        m.tiles.push(m.top.findNode("tile" + index.ToStr()))
    end for

    m.libraryTitle.font = PorticoFont("700", 36)
    m.libraryTitle.color = "#F4F7FA"
    m.serverLabel.font = PorticoFont("500", 18)
    m.serverLabel.color = "#8F9BA6"
    m.resultCount.font = PorticoFont("500", 18)
    m.resultCount.color = "#8F9BA6"
    m.availabilityLabel.font = PorticoFont("600", 18)
    m.availabilityLabel.color = "#E3B341"
    m.stateTitle.font = PorticoFont("600", 30)
    m.stateTitle.color = "#F4F7FA"
    for each line in m.stateMessages
        line.font = PorticoFont("400", 20)
        line.color = "#8F9BA6"
    end for
    m.stateIconBed.uri = "pkg:/images/ui/state-icon-bed.png"
    m.stateIcon.uri = PorticoIconResolverPackageUri("status.warning", "rail")
    buildSkeletons()

    m.top.focusable = true
    m.activationSequence = 0
    m.focusTargets = []
    m.focusIndex = 0
    m.focusKey = ""
    m.contentScroll = 0
    m.hasViewState = false
    m.quickActionsOpen = false
    m.quickActionIndex = 0
    m.quickActionTarget = invalid
    m.screenAuthority = PorticoScreenAuthorityCreate("library")
    for index = 0 to 25
        label = m.alphabetIndexRail.CreateChild("Label")
        label.text = Chr(65 + index)
        label.translation = [0, index * 22]
        label.width = 32
        label.height = 22
        label.horizAlign = "center"
        label.font = PorticoFont("600", 15)
        label.color = "#64717D"
        label.opacity = 0.66
    end for
end sub

sub buildSkeletons()
    for index = 0 to 13
        group = m.top.findNode("skeleton" + index.ToStr())
        column = index mod 7
        row = Int(index / 7)
        group.translation = [column * 238, row * 425]
        PorticoRectangle(group, [6, 6], 202, 321, "#151F29")
        PorticoRectangle(group, [6, 340], 158, 22, "#151F29")
    end for
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid then return
    PorticoScreenAuthorityFence(m.screenAuthority, PorticoLibrarySafeInteger(state.viewerGeneration, 0))
    previousKey = m.focusKey
    if not m.hasViewState and state.focusKey <> invalid then previousKey = state.focusKey.ToStr()
    m.hasViewState = true
    renderLibrary(previousKey)
end sub

sub renderLibrary(previousKey as string)
    state = m.top.viewState
    if state = invalid then return
    resetLibraryNodes()
    m.libraryTitle.text = "Library"
    if state.libraryName <> invalid and PorticoLibrarySafeText(state.libraryName, 80) <> "" then m.libraryTitle.text = PorticoLibrarySafeText(state.libraryName, 80)
    m.serverLabel.text = PorticoLibrarySafeText(state.serverName, 100)
    renderLibraryAvailability(state.availabilityStatus)
    buildTabs(state.tabs)
    buildToolbar(state.actions, state.resultCount, state.resultLabel)
    buildAlphabetIndexRail(state.alphabetSeek)
    m.contentOriginY = 196
    if state.actions <> invalid and GetInterface(state.actions, "ifArray") <> invalid and state.actions.count() > 0 then m.contentOriginY = 282
    m.contentViewport.translation = [0, m.contentOriginY]
    m.skeletonGrid.translation = [0, m.contentOriginY]
    m.stateGroup.translation = [0, m.contentOriginY]
    m.alphabetIndexRail.translation = [1680, m.contentOriginY + 8]
    m.filterOverlay.visible = state.filterDescriptor <> invalid and state.filterDescriptor.open = true
    if m.filterOverlay.visible
        if m.screenAuthority.modalInvokerId = "" then PorticoScreenAuthorityOpenModal(m.screenAuthority, m.focusKey)
        m.filterOverlay.viewState = state.filterDescriptor
        m.filterOverlay.setFocus(true)
    end if

    status = LCase(PorticoLibrarySafeText(state.status, 24))
    if (status = "refreshing" or status = "stale") and state.presentation <> invalid then status = "ready"
    if status <> "loading" and status <> "ready" and status <> "empty" and status <> "error" then status = "loading"
    m.contentViewport.visible = false
    m.skeletonGrid.visible = false
    m.stateGroup.visible = false
    m.retryAction.visible = false
    if status = "loading"
        m.skeletonGrid.visible = true
    else if status = "error"
        title = PorticoLibrarySafeText(state.title, 80)
        if title = "" then title = "Library couldn't load"
        message = PorticoLibrarySafeText(state.message, 260)
        if message = "" then message = "Try again in a moment."
        actionLabel = PorticoLibrarySafeText(state.actionLabel, 30)
        if actionLabel = "" then actionLabel = "Try again"
        actionKind = PorticoLibrarySafeText(state.actionKind, 40)
        if actionKind = "" then actionKind = "retry-library"
        renderLibraryState(title, message, actionLabel, actionKind)
    else if status = "empty"
        title = PorticoLibrarySafeText(state.title, 80)
        if title = "" then title = m.libraryTitle.text + " is empty"
        renderLibraryState(title, PorticoLibrarySafeText(state.message, 260), PorticoLibrarySafeText(state.actionLabel, 30), PorticoLibrarySafeText(state.actionKind, 40))
    else
        m.contentViewport.visible = true
        presentation = LCase(PorticoLibrarySafeText(state.presentation, 24))
        if presentation = "shelves"
            buildShelves(state.rows)
        else if presentation = "list"
            buildList(state.items, false)
        else if presentation = "facets"
            buildFacets(state.sections)
        else if presentation = "resources"
            buildResources(state.items, true, state.libraryHub = true)
        else if presentation = "schedule"
            buildList(state.items, true)
        else
            buildGrid(state.items)
        end if
        if state.hasMore = true then buildLoadMore(state)
        if not libraryHasContent(state, presentation)
            m.contentViewport.visible = false
            renderLibraryState(PorticoLibraryEmptyTitle(state), PorticoLibrarySafeText(state.message, 260), PorticoLibrarySafeText(state.actionLabel, 30), PorticoLibrarySafeText(state.actionKind, 40))
        end if
    end if
    restoreLibraryFocus(previousKey)
    updateLibraryFocus()
    renderLibraryQuickActions()
end sub

sub resetLibraryNodes()
    m.focusTargets = []
    for each node in m.tabs
        node.visible = false
        node.focused = false
    end for
    for each node in m.toolbarActions
        node.visible = false
        node.focused = false
    end for
    for each node in m.sectionTitles
        node.visible = false
        node.text = ""
    end for
    for each node in m.cards
        node.visible = false
        node.focused = false
    end for
    for each node in m.listRows
        node.visible = false
        node.focused = false
    end for
    for each node in m.tiles
        node.visible = false
        node.focused = false
    end for
    m.loadMoreAction.visible = false
    m.loadMoreAction.focused = false
    m.resultCount.text = ""
    m.alphabetIndexRail.visible = false
end sub

sub buildAlphabetIndexRail(source as dynamic)
    if source = invalid or Type(source) <> "roAssociativeArray" or source.available <> true then return
    m.alphabetIndexRail.visible = true
end sub

sub filterOverlayActivationChanged()
    action = m.filterOverlay.activation
    if action = invalid or Type(action) <> "roAssociativeArray" then return
    m.activationSequence = m.activationSequence + 1
    forwarded = {sequence: m.activationSequence, kind: action.kind}
    for each key in action
        if key <> "sequence" and key <> "kind" then forwarded[key] = action[key]
    end for
    m.top.activation = forwarded
    if action.kind = "cancel-library-filters" or action.kind = "apply-library-filters" then PorticoScreenAuthorityCloseModal(m.screenAuthority, m.focusKey)
end sub

sub buildTabs(source as dynamic)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    for index = 0 to source.count() - 1
        if index >= m.tabs.count() then exit for
        raw = source[index]
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoLibrarySafeId(raw.id)
            label = PorticoLibrarySafeText(raw.label, 48)
            if id <> "" and label <> ""
                node = m.tabs[index]
                node.model = {id: id, label: label, selected: raw.selected = true}
                node.translation = [index * 180, 0]
                node.visible = true
                m.focusTargets.push({key: "tab:" + id, kind: "select-tab", id: id, x: index * 180, y: 102, width: 168, height: 68, node: node, content: false, selected: raw.selected = true})
            end if
        end if
    end for
end sub

sub buildToolbar(source as dynamic, resultCount as dynamic, resultLabel as dynamic)
    m.resultCount.text = PorticoLibraryResultCount(resultCount, resultLabel)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    x = 0
    visibleIndex = 0
    for each raw in source
        if visibleIndex >= m.toolbarActions.count() then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoLibrarySafeId(raw.id)
            label = PorticoLibrarySafeText(raw.label, 64)
            if id <> "" and label <> ""
                width = 210
                if raw.width <> invalid then width = PorticoLibrarySafeInteger(raw.width, 210)
                if width < 150 then width = 150
                if width > 360 then width = 360
                node = m.toolbarActions[visibleIndex]
                node.model = {id: id, label: label, iconId: PorticoLibraryIcon(raw.iconId), selected: raw.selected = true, width: width}
                node.translation = [x, 0]
                node.visible = true
                m.focusTargets.push({key: "action:" + id, kind: id, id: id, x: x, y: 192, width: width, height: 64, node: node, content: false})
                x = x + width + 12
                visibleIndex = visibleIndex + 1
            end if
        end if
    end for
end sub

sub buildGrid(source as dynamic)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    nodeIndex = 0
    for each raw in source
        if nodeIndex >= m.cards.count() then exit for
        model = PorticoLibraryCardModel(raw)
        if model <> invalid
            column = nodeIndex mod 7
            row = Int(nodeIndex / 7)
            x = column * 238
            y = row * 425
            node = m.cards[nodeIndex]
            node.model = model
            node.shape = PorticoLibraryShape(raw.shape)
            node.translation = [x, y]
            node.visible = true
            m.focusTargets.push({key: "media:" + model.id, kind: "open-detail", id: model.id, x: x, y: m.contentOriginY + y, contentY: y, width: 214, height: 395, node: node, content: true, model: model})
            nodeIndex = nodeIndex + 1
        end if
    end for
    m.contentBottom = Int((nodeIndex + 6) / 7) * 425
end sub

sub buildList(source as dynamic, schedule as boolean)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    nodeIndex = 0
    for each raw in source
        if nodeIndex >= m.listRows.count() then exit for
        model = PorticoLibraryListModel(raw)
        if model <> invalid
            y = nodeIndex * 170
            node = m.listRows[nodeIndex]
            node.model = model
            if schedule then node.rowKind = "schedule" else node.rowKind = "media"
            node.translation = [0, y]
            node.visible = true
            if not schedule
                m.focusTargets.push({key: "media:" + model.id, kind: "open-detail", id: model.id, x: 0, y: m.contentOriginY + y, contentY: y, width: 1712, height: 158, node: node, content: true, model: model})
            end if
            nodeIndex = nodeIndex + 1
        end if
    end for
    m.contentBottom = nodeIndex * 170
end sub

sub buildShelves(source as dynamic)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    y = 0
    cardIndex = 0
    sectionIndex = 0
    for each rawRow in source
        if sectionIndex >= m.sectionTitles.count() or cardIndex >= m.cards.count() then exit for
        if rawRow <> invalid and Type(rawRow) = "roAssociativeArray"
            items = rawRow.items
            if items = invalid or GetInterface(items, "ifArray") = invalid then items = []
            if items.count() > 0
                shape = PorticoLibraryShape(rawRow.shape)
                title = m.sectionTitles[sectionIndex]
                title.text = PorticoLibrarySafeText(rawRow.title, 80)
                title.translation = [0, y]
                title.visible = true
                cardY = y + 54
                pitch = 232
                maximum = 7
                cardHeight = 395
                if shape = "landscape"
                    pitch = 338
                    maximum = 5
                    cardHeight = 248
                else if shape = "square"
                    cardHeight = 288
                end if
                itemIndex = 0
                for each raw in items
                    if itemIndex >= maximum or cardIndex >= m.cards.count() then exit for
                    model = PorticoLibraryCardModel(raw)
                    if model <> invalid
                        x = itemIndex * pitch
                        node = m.cards[cardIndex]
                        node.model = model
                        node.shape = shape
                        node.translation = [x, cardY]
                        node.visible = true
                        cardWidth = 214
                        if shape = "landscape" then cardWidth = 320
                occurrenceKey = "media:" + PorticoLibrarySafeText(rawRow.id, 80) + ":" + cardIndex.ToStr() + ":" + model.id
                m.focusTargets.push({key: occurrenceKey, kind: "open-detail", id: model.id, x: x, y: m.contentOriginY + cardY, contentY: cardY, width: cardWidth, height: cardHeight, node: node, content: true, model: model})
                        cardIndex = cardIndex + 1
                        itemIndex = itemIndex + 1
                    end if
                end for
                y = cardY + cardHeight + 42
                sectionIndex = sectionIndex + 1
            end if
        end if
    end for
    m.contentBottom = y
end sub

sub buildFacets(source as dynamic)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    y = 0
    tileIndex = 0
    sectionIndex = 0
    for each rawSection in source
        if sectionIndex >= m.sectionTitles.count() or tileIndex >= m.tiles.count() then exit for
        if rawSection <> invalid and Type(rawSection) = "roAssociativeArray"
            items = rawSection.items
            if items = invalid or GetInterface(items, "ifArray") = invalid then items = []
            if items.count() > 0
                title = m.sectionTitles[sectionIndex]
                title.text = PorticoLibrarySafeText(rawSection.title, 80)
                title.translation = [0, y]
                title.visible = true
                itemIndex = 0
                for each raw in items
                    if itemIndex >= 6 or tileIndex >= m.tiles.count() then exit for
                    model = PorticoLibraryTileModel(raw)
                    if model <> invalid
                        x = itemIndex * 266
                        tileY = y + 54
                        node = m.tiles[tileIndex]
                        node.model = model
                        node.tileKind = "facet"
                        node.translation = [x, tileY]
                        node.visible = true
                        m.focusTargets.push({key: "facet:" + model.id, kind: "select-facet", id: model.id, x: x, y: m.contentOriginY + tileY, contentY: tileY, width: 250, height: 150, node: node, content: true})
                        tileIndex = tileIndex + 1
                        itemIndex = itemIndex + 1
                    end if
                end for
                y = y + 246
                sectionIndex = sectionIndex + 1
            end if
        end if
    end for
    m.contentBottom = y
end sub

sub buildResources(source as dynamic, actionable as boolean, libraryHub = false as boolean)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    nodeIndex = 0
    for each raw in source
        if nodeIndex >= m.tiles.count() then exit for
        model = PorticoLibraryTileModel(raw)
        if model <> invalid
            column = nodeIndex mod 2
            row = Int(nodeIndex / 2)
            x = column * 864
            y = row * 160
            node = m.tiles[nodeIndex]
            node.model = model
            node.tileKind = "resource"
            node.translation = [x, y]
            node.visible = true
            if actionable
                targetKind = "select-resource"
                if libraryHub then targetKind = "select-library"
                m.focusTargets.push({key: "resource:" + model.id, kind: targetKind, id: model.id, x: x, y: m.contentOriginY + y, contentY: y, width: 848, height: 144, node: node, content: true})
            end if
            nodeIndex = nodeIndex + 1
        end if
    end for
    m.contentBottom = Int((nodeIndex + 1) / 2) * 160
end sub

sub buildLoadMore(state as object)
    y = m.contentBottom + 20
    label = PorticoLibrarySafeText(state.loadMoreLabel, 40)
    if label = "" then label = "Load more"
    m.loadMoreAction.model = {label: label, iconId: "action.add", primary: false, width: 210}
    m.loadMoreAction.translation = [0, y]
    m.loadMoreAction.visible = true
    m.focusTargets.push({key: "action:load-more", kind: "load-more", id: "load-more", x: 0, y: m.contentOriginY + y, contentY: y, width: 210, height: 64, node: m.loadMoreAction, content: true})
    m.contentBottom = y + 84
end sub

sub renderLibraryState(title as string, message as string, actionLabel as string, actionKind as string)
    m.stateGroup.visible = true
    m.stateTitle.text = title
    lines = PorticoBreakText(message, 640, 20, "400", 3)
    for index = 0 to m.stateMessages.count() - 1
        m.stateMessages[index].visible = index < lines.count()
        m.stateMessages[index].text = ""
        if index < lines.count() then m.stateMessages[index].text = lines[index]
    end for
    if actionLabel <> ""
        if actionKind = "" then actionKind = "retry-library"
        m.retryAction.model = {label: actionLabel, iconId: "action.retry", primary: true, width: 190}
        m.retryAction.visible = true
        m.focusTargets.push({key: "state:" + actionKind, kind: actionKind, id: actionKind, x: 773, y: 636, width: 190, height: 64, node: m.retryAction, content: false})
    end if
end sub

function libraryHasContent(state as object, presentation as string) as boolean
    if presentation = "facets"
        if state.sections = invalid or GetInterface(state.sections, "ifArray") = invalid then return false
        for each section in state.sections
            if section <> invalid and section.items <> invalid and GetInterface(section.items, "ifArray") <> invalid and section.items.count() > 0 then return true
        end for
        return false
    end if
    if presentation = "shelves"
        if state.rows = invalid or GetInterface(state.rows, "ifArray") = invalid then return false
        for each row in state.rows
            if row <> invalid and row.items <> invalid and GetInterface(row.items, "ifArray") <> invalid and row.items.count() > 0 then return true
        end for
        return false
    end if
    return state.items <> invalid and GetInterface(state.items, "ifArray") <> invalid and state.items.count() > 0
end function

sub restoreLibraryFocus(previousKey as string)
    semanticIds = []
    for each target in m.focusTargets
        semanticIds.Push(target.key)
    end for
    PorticoScreenAuthorityTargets(m.screenAuthority, semanticIds)
    previousKey = PorticoScreenAuthorityResolve(m.screenAuthority, previousKey, "")
    m.focusIndex = -1
    if previousKey <> ""
        for index = 0 to m.focusTargets.count() - 1
            if m.focusTargets[index].key = previousKey
                m.focusIndex = index
                exit for
            end if
        end for
    end if
    if m.focusIndex < 0
        for index = 0 to m.focusTargets.count() - 1
            target = m.focusTargets[index]
            if target.kind = "select-tab" and target.selected = true
                m.focusIndex = index
                exit for
            end if
        end for
    end if
    if m.focusIndex < 0 and m.focusTargets.count() > 0 then m.focusIndex = 0
end sub

sub updateLibraryFocus()
    semanticIds = []
    for each focusTarget in m.focusTargets
        semanticIds.Push(focusTarget.key)
    end for
    PorticoScreenAuthorityTargets(m.screenAuthority, semanticIds)
    for index = 0 to m.focusTargets.count() - 1
        m.focusTargets[index].node.focused = index = m.focusIndex
    end for
    m.focusKey = ""
    if m.focusIndex >= 0 and m.focusIndex < m.focusTargets.count()
        target = m.focusTargets[m.focusIndex]
        m.focusKey = target.key
        PorticoScreenAuthorityFocused(m.screenAuthority, m.focusKey)
        if target.content = true
            top = target.contentY - m.contentScroll
            bottom = top + target.height
            if bottom > 760 then m.contentScroll = m.contentScroll + (bottom - 760)
            if top < 0 then m.contentScroll = m.contentScroll + top
            if m.contentScroll < 0 then m.contentScroll = 0
        end if
    end if
    m.contentCanvas.translation = [0, -m.contentScroll]
    m.top.focusState = {key: m.focusKey, index: m.focusIndex, contentOffset: m.contentScroll}
end sub

function moveLibraryFocus(horizontal as integer, vertical as integer) as boolean
    if m.focusIndex < 0 or m.focusIndex >= m.focusTargets.count() then return false
    current = m.focusTargets[m.focusIndex]
    currentY = current.y
    if current.content = true then currentY = currentY - m.contentScroll
    bestIndex = -1
    bestScore = 2147483647
    for index = 0 to m.focusTargets.count() - 1
        if index <> m.focusIndex
            candidate = m.focusTargets[index]
            candidateY = candidate.y
            if candidate.content = true then candidateY = candidateY - m.contentScroll
            deltaX = candidate.x - current.x
            deltaY = candidateY - currentY
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
        direction = "down"
        if horizontal < 0 then direction = "left"
        if horizontal > 0 then direction = "right"
        if vertical < 0 then direction = "up"
        if not PorticoScreenAuthorityAcceptMove(m.screenAuthority, direction, current.key, m.focusTargets[bestIndex].key) then return false
        m.focusIndex = bestIndex
        return true
    end if
    return false
end function

sub emitLibraryActivation(target as object)
    PorticoScreenAuthorityCommitOK(m.screenAuthority)
    m.activationSequence = m.activationSequence + 1
    m.top.activation = {sequence: m.activationSequence, kind: target.kind, targetId: target.id, focusKey: target.key}
end sub

sub renderLibraryQuickActions()
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

sub openLibraryQuickActions()
    if m.focusIndex < 0 or m.focusIndex >= m.focusTargets.count() then return
    target = m.focusTargets[m.focusIndex]
    if target.model = invalid or PorticoMediaQuickActionIds(target.model).count() = 0 then return
    m.quickActionTarget = target.model
    PorticoScreenAuthorityOpenModal(m.screenAuthority, target.key)
    m.quickActionIndex = 0
    m.quickActionsOpen = true
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        PorticoScreenAuthorityRelease(m.screenAuthority, key)
        return false
    end if
    if key = "back" and m.quickActionsOpen
        m.quickActionsOpen = false
        m.quickActionTarget = invalid
        restoredId = PorticoScreenAuthorityCloseModal(m.screenAuthority, m.focusKey)
        PorticoScreenAuthorityFocused(m.screenAuthority, restoredId)
        renderLibraryQuickActions()
        return true
    end if
    if key = "options"
        if m.focusIndex >= 0 and m.focusIndex < m.focusTargets.count() and m.focusTargets[m.focusIndex].kind = "cycle-sort"
            emitLibraryActivation({kind: "toggle-sort-direction", id: "sort-direction", key: m.focusTargets[m.focusIndex].key})
            return true
        end if
        if m.quickActionsOpen
            m.quickActionsOpen = false
            m.quickActionTarget = invalid
            PorticoScreenAuthorityCloseModal(m.screenAuthority, m.focusKey)
        else
            openLibraryQuickActions()
        end if
        renderLibraryQuickActions()
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
                semanticId = "library." + m.quickActions.focusSemanticId + "." + m.quickActionTarget.id
                if not PorticoScreenAuthorityBeginOK(m.screenAuthority, semanticId) then return true
                emitLibraryActivation({ kind: actions[m.quickActionIndex], id: m.quickActionTarget.id, key: "media:" + m.quickActionTarget.id })
                m.quickActionsOpen = false
                m.quickActionTarget = invalid
                PorticoScreenAuthorityCloseModal(m.screenAuthority, m.focusKey)
            end if
        else
            return true
        end if
        renderLibraryQuickActions()
        return true
    end if
    moved = false
    if key = "left"
        moved = moveLibraryFocus(-1, 0)
        if not moved then return false
    else if key = "right"
        moved = moveLibraryFocus(1, 0)
    else if key = "up"
        moved = moveLibraryFocus(0, -1)
        if not moved then return true
    else if key = "down"
        moved = moveLibraryFocus(0, 1)
    else if key = "OK"
        if m.focusIndex >= 0 and m.focusIndex < m.focusTargets.count()
            target = m.focusTargets[m.focusIndex]
            if not PorticoScreenAuthorityBeginOK(m.screenAuthority, target.key) then return true
            emitLibraryActivation(target)
        end if
        return true
    else if key = "back"
        return false
    else
        return false
    end if
    updateLibraryFocus()
    return true
end function

function PorticoLibraryCardModel(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoLibrarySafeId(source.id)
    title = PorticoLibrarySafeText(source.title, 100)
    if id = "" or title = "" then return invalid
    model = {
        id: id,
        title: title,
        meta: PorticoLibrarySafeText(source.meta, 100),
        poster: PorticoLibrarySafeUri(source.poster),
        artwork: PorticoLibrarySafeUri(source.artwork),
        actions: source.actions,
        watchlisted: source.watchlisted = true,
        favorite: source.favorite = true,
        watched: source.watched = true
    }
    if source.progress <> invalid
        progress = PorticoLibrarySafeInteger(source.progress, 0)
        if progress < 0 then progress = 0
        if progress > 100 then progress = 100
        model.progress = progress
    end if
    return model
end function

function PorticoLibraryListModel(source as dynamic) as dynamic
    model = PorticoLibraryCardModel(source)
    if model = invalid then return invalid
    model.summary = PorticoLibrarySafeText(source.summary, 300)
    model.backdrop = PorticoLibrarySafeUri(source.backdrop)
    model.status = PorticoLibrarySafeText(source.status, 30)
    model.statusTone = PorticoLibrarySafeText(source.statusTone, 20)
    return model
end function

function PorticoLibraryTileModel(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoLibrarySafeId(source.id)
    title = PorticoLibrarySafeText(source.title, 100)
    if id = "" or title = "" then return invalid
    return {id: id, title: title, meta: PorticoLibrarySafeText(source.meta, 80), summary: PorticoLibrarySafeText(source.summary, 240)}
end function

function PorticoLibraryShape(value as dynamic) as string
    shape = LCase(PorticoLibrarySafeText(value, 20))
    if shape = "landscape" or shape = "square" then return shape
    return "poster"
end function

function PorticoLibraryIcon(value as dynamic) as string
    iconId = LCase(PorticoLibrarySafeText(value, 120))
    allowed = {"navigation.back": true, "action.customize": true, "action.sort": true, "view.grid": true, "view.list": true, "navigation.search": true, "action.add": true, "action.retry": true, "metadata.info": true}
    if allowed[iconId] = true then return iconId
    return "status.icon-mapping-missing"
end function

sub renderLibraryAvailability(value as dynamic)
    status = LCase(PorticoLibrarySafeText(value, 24))
    m.availabilityLabel.text = ""
    m.availabilityLabel.visible = false
    if status = "offline"
        m.availabilityLabel.text = "OFFLINE"
        m.availabilityLabel.visible = true
    else if status = "refresh-failed"
        m.availabilityLabel.text = "COULDN'T REFRESH"
        m.availabilityLabel.visible = true
    end if
end sub

function PorticoLibrarySafeInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" or valueType = "float" or valueType = "rofloat" or valueType = "double" or valueType = "rodouble" then return Int(value)
    if valueType = "string" or valueType = "rostring"
        normalized = value.Trim()
        if normalized <> "" then return Int(Val(normalized))
    end if
    return fallback
end function

function PorticoLibraryResultCount(value as dynamic, rawLabel as dynamic) as string
    if value = invalid then return ""
    count = PorticoLibrarySafeInteger(value, 0)
    if count < 0 then count = 0
    label = LCase(PorticoLibrarySafeText(rawLabel, 32))
    if label = "" then label = "item"
    if count <> 1 then label = label + "s"
    return count.ToStr() + " " + label
end function

function PorticoLibraryEmptyTitle(state as object) as string
    title = PorticoLibrarySafeText(state.title, 80)
    if title <> "" then return title
    return m.libraryTitle.text + " is empty"
end function

function PorticoLibrarySafeText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function

function PorticoLibrarySafeId(value as dynamic) as string
    normalized = PorticoLibrarySafeText(value, 128)
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoLibrarySafeUri(value as dynamic) as string
    normalized = PorticoLibrarySafeText(value, 512)
    if Left(normalized, 5) = "pkg:/" or Left(normalized, 5) = "tmp:/" then return normalized
    return ""
end function
