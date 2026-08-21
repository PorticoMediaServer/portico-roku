sub init()
    m.composition = m.top.findNode("composition")
    m.language = invalid
    loaded = PorticoProductLanguageLoad()
    if loaded.ok then m.language = loaded.value
    m.focusNodes = {}
    m.focusWindows = {}
end sub

sub render()
    model = m.top.model
    m.composition.removeChildrenIndex(m.composition.getChildCount(), 0)
    if model = invalid or Type(model) <> "roAssociativeArray" then return
    m.focusNodes = {}
    m.focusWindows = {}
    m.sectionPositions = {}
    renderDetailHero(model)
    y = 610
    seasons = detailArray(model.seasons)
    if seasons.count() > 0
        m.sectionPositions.detailSeason = y
        y = renderDetailSeasonSelector(model, seasons, y)
    end if
    episodes = detailArray(model.episodes)
    if episodes.count() > 0
        m.sectionPositions.detailEpisodes = y
        episodeTitle = "Episodes"
        if seasons.count() > 0 then episodeTitle = ""
        y = renderDetailMediaRow(episodeTitle, episodes, y, "detailEpisodes", m.top.focusedEpisode)
    else if seasons.count() > 0
        y = renderDetailEpisodeState(model, y)
    end if
    people = detailArray(model.people)
    if people.count() > 0
        m.sectionPositions.detailPeople = y
        y = renderDetailPeople(people, y)
    end if
    personResults = detailArray(model.personResults)
    personStatus = LCase(detailText(model.personStatus, 24))
    if detailText(model.selectedPersonName, 100) <> ""
        m.sectionPositions.detailPersonResults = y
        y = renderPersonResults(model, personResults, personStatus, y)
    end if
    relationships = detailArray(model.relationships)
    for rowIndex = 0 to relationships.count() - 1
        row = relationships[rowIndex]
        if row <> invalid and Type(row) = "roAssociativeArray" and detailArray(row.items).count() > 0
            key = "detailRelationship" + rowIndex.ToStr()
            m.sectionPositions[key] = y
            focusedIndex = -1
            if m.top.focusArea = key then focusedIndex = m.top.focusedRelationshipItem
            y = renderDetailMediaRow(detailText(row.title, 80), detailArray(row.items), y, key, focusedIndex)
        end if
    end for
    facts = detailArray(model.facts)
    m.sectionPositions.detailFacts = y
    y = renderVersionsInformation(facts, y)
    applyDetailScroll(y)
    updateFocus()
end sub

sub detailRegisterFocus(area as string, index as integer, node as object)
    entries = m.focusNodes[area]
    if entries = invalid then entries = []
    entries.push({ index: index, node: node })
    m.focusNodes[area] = entries
end sub

sub updateFocus()
    if m.focusNodes = invalid then return
    detailRebindFocusedWindows()
    m.top.focusable = true
    if m.top.focusArea = "detailFacts"
        m.top.accessibilityLabel = "Versions and media information"
        m.top.setFocus(true)
    end if
    for each area in m.focusNodes
        target = -1
        if area = "detailActions" then target = m.top.focusedAction
        if area = "detailSeason" then target = 0
        if area = "detailEpisodes" then target = m.top.focusedEpisode
        if area = "detailPeople" then target = m.top.focusedPerson
        if area = "detailPersonResults" then target = m.top.focusedPersonResult
        if Left(area, 18) = "detailRelationship" then target = m.top.focusedRelationshipItem
        for each entry in m.focusNodes[area]
            isFocused = m.top.focusArea = area and entry.index = target
            if entry.node.HasField("focused") then entry.node.focused = isFocused
            entry.node.setFocus(isFocused)
        end for
    end for
    applyDetailScroll(99999)
    publishDetailSemanticFocus()
end sub

sub publishDetailSemanticFocus()
    model = m.top.model
    if model = invalid then return
    semanticId = "detail.unavailable"
    area = m.top.focusArea
    if area = "detailActions"
        actions = detailUiActionIds(model)
        if m.top.focusedAction >= 0 and m.top.focusedAction < actions.Count() then semanticId = "detail.action." + actions[m.top.focusedAction]
    else if area = "detailEpisodes"
        episodes = detailArray(model.episodes)
        if m.top.focusedEpisode >= 0 and m.top.focusedEpisode < episodes.Count() then semanticId = "detail.episode." + detailText(episodes[m.top.focusedEpisode].id, 128)
    else if area = "detailPeople"
        people = detailArray(model.people)
        if m.top.focusedPerson >= 0 and m.top.focusedPerson < people.Count() then semanticId = "detail.person." + detailText(people[m.top.focusedPerson].id, 128)
    else if area = "detailPersonResults"
        items = detailArray(model.personResults)
        if m.top.focusedPersonResult >= 0 and m.top.focusedPersonResult < items.Count() then semanticId = "detail.person-result." + detailText(items[m.top.focusedPersonResult].id, 128)
    else if area = "detailFacts"
        semanticId = "detail.facts"
    else if area = "detailSeason"
        seasonId = detailText(model.selectedSeasonId, 128)
        if seasonId = "" then seasonId = "current"
        semanticId = "detail.season." + seasonId
    else if Left(area, 18) = "detailRelationship"
        relationships = detailArray(model.relationships)
        rowIndex = m.top.focusedRelationshipRow
        if rowIndex >= 0 and rowIndex < relationships.Count()
            items = detailArray(relationships[rowIndex].items)
            relationshipId = detailText(relationships[rowIndex].id, 128)
            if relationshipId = "" then relationshipId = rowIndex.ToStr()
            if m.top.focusedRelationshipItem >= 0 and m.top.focusedRelationshipItem < items.Count() then semanticId = "detail.relationship." + relationshipId + ".item." + detailText(items[m.top.focusedRelationshipItem].id, 128)
        end if
    end if
    m.top.focusSemanticId = semanticId
end sub

sub detailRebindFocusedWindows()
    if m.focusWindows = invalid then return
    for each area in m.focusWindows
        target = -1
        if area = "detailEpisodes" then target = m.top.focusedEpisode
        if area = "detailPeople" then target = m.top.focusedPerson
        if area = "detailPersonResults" then target = m.top.focusedPersonResult
        if Left(area, 18) = "detailRelationship" then target = m.top.focusedRelationshipItem
        window = m.focusWindows[area]
        if target >= 0 and target < window.items.count()
            lastIndex = window.first + window.nodes.count() - 1
            if target < window.first or target > lastIndex
                first = target - window.leading
                if first < 0 then first = 0
                maximumFirst = window.items.count() - window.nodes.count()
                if maximumFirst < 0 then maximumFirst = 0
                if first > maximumFirst then first = maximumFirst
                window.first = first
                entries = []
                x = 0
                for slotIndex = 0 to window.nodes.count() - 1
                    logicalIndex = first + slotIndex
                    node = window.nodes[slotIndex]
                    if window.kind = "media"
                        shape = detailShape(window.items[logicalIndex])
                        cardWidth = 214
                        pitch = 232
                        if shape = "landscape"
                            cardWidth = 320
                            pitch = 338
                        end if
                        node.shape = shape
                        node.model = window.items[logicalIndex]
                        node.translation = [x, window.y]
                        node.visible = x + cardWidth <= 1712
                        x = x + pitch
                    else
                        detailBindPersonSlot(node, window.items[logicalIndex])
                    end if
                    if node.visible then entries.push({index: logicalIndex, node: node})
                end for
                m.focusNodes[area] = entries
                m.focusWindows[area] = window
            end if
        end if
    end for
end sub

sub renderDetailHero(model as object)
    PorticoRectangle(m.composition, [0, 0], 1784, 570, "#0A1017")
    if model.backdrop <> invalid and model.backdrop.ToStr() <> "" then PorticoPoster(m.composition, model.backdrop, [0, 0], 1784, 570, "scaleToZoom")
    PorticoPoster(m.composition, "pkg:/images/ui/hero-vertical-strong.png", [0, 0], 1784, 570)
    PorticoPoster(m.composition, "pkg:/images/ui/hero-horizontal.png", [0, 0], 1784, 570)
    renderDetailAvailability(model)
    titleLines = PorticoBreakText(model.title, 1002, 52, "700", 2)
    summaryLines = PorticoBreakText(model.summary, 900, 23, "400", 2)
    if titleLines.count() = 0 then titleLines = [""]
    if summaryLines.count() = 0 then summaryLines = [""]
    dependentShift = (titleLines.count() - 1) * 60
    metaY = 286 + dependentShift
    summaryY = 328 + dependentShift
    progressY = 410 + dependentShift
    actionsY = 440 + dependentShift
    PorticoLabel(m.composition, model.parent, [0, 181], 1002, 28, 21, "600", "#70BCE8")
    PorticoRenderLines(m.composition, titleLines, [0, 217], 1002, 60, 52, "700", "#F4F7FA")
    PorticoLabel(m.composition, model.meta, [0, metaY], 1002, 29, 22, "600", "#C7D0D8")
    PorticoRenderLines(m.composition, summaryLines, [0, summaryY], 900, 32, 23, "400", "#C7D0D8")
    if model.progress <> invalid and model.progress > 0
        progress = model.progress
        if progress > 100 then progress = 100
        PorticoRectangle(m.composition, [0, progressY], 700, 6, "#F4F7FA", 0.28)
        PorticoRectangle(m.composition, [0, progressY], Int(700 * progress / 100.0), 6, "#70BCE8")
    end if
    actionIds = detailUiActionIds(model)
    actionX = 0
    for index = 0 to actionIds.count() - 1
        action = actionIds[index]
        if action = "play"
            button = m.composition.CreateChild("PorticoButton")
            button.translation = [actionX, actionsY]
            label = "Play"
            if model.progress <> invalid then label = "Resume"
            button.model = { label: label, iconId: "playback.play", primary: true, width: 166 }
            button.focused = m.top.focusArea = "detailActions" and m.top.focusedAction = index
            detailRegisterFocus("detailActions", index, button)
            actionX = actionX + 178
        else if action = "play.from-beginning"
            contractAction = detailContractAction(model, action)
            label = "Play from beginning"
            if contractAction <> invalid and detailText(contractAction.label, 80) <> "" then label = detailText(contractAction.label, 80)
            button = m.composition.CreateChild("PorticoButton")
            button.translation = [actionX, actionsY]
            button.model = {label: label, iconId: "playback.replay", primary: false, width: 268}
            button.focused = m.top.focusArea = "detailActions" and m.top.focusedAction = index
            detailRegisterFocus("detailActions", index, button)
            actionX = actionX + 280
        else if action = "watch-with-friends.start"
            contractAction = detailContractAction(model, action)
            label = "Watch With Friends"
            if contractAction <> invalid and detailText(contractAction.label, 80) <> "" then label = detailText(contractAction.label, 80)
            button = m.composition.CreateChild("PorticoButton")
            button.translation = [actionX, actionsY]
            button.model = {label: label, iconId: "account.user", primary: false, width: 286}
            button.focused = m.top.focusArea = "detailActions" and m.top.focusedAction = index
            detailRegisterFocus("detailActions", index, button)
            actionX = actionX + 298
        else if action = "feedback.report-problem" or action = "feedback.request-higher-quality"
            contractAction = detailContractAction(model, action)
            label = "Report a problem"
            icon = "status.warning"
            width = 244
            if action = "feedback.request-higher-quality"
                label = "Request higher quality"
                icon = "action.optimize"
                width = 286
            end if
            if contractAction <> invalid and detailText(contractAction.label, 80) <> "" then label = detailText(contractAction.label, 80)
            button = m.composition.CreateChild("PorticoButton")
            button.translation = [actionX, actionsY]
            button.model = {label: label, iconId: icon, primary: false, width: width}
            button.focused = m.top.focusArea = "detailActions" and m.top.focusedAction = index
            detailRegisterFocus("detailActions", index, button)
            actionX = actionX + width + 12
        else
            button = m.composition.CreateChild("PorticoIconButton")
            button.translation = [actionX, actionsY]
            icon = "action.watchlist"
            selected = false
            if action = "saved-toggle"
                selected = model.watchlisted = true
            else if action = "favorite-toggle"
                icon = "action.favorite"
                selected = model.favorite = true
            else if action = "watched-toggle"
                icon = "action.mark-watched"
                selected = model.watched = true
            else if action = "more"
                icon = "action.customize"
            end if
            button.model = { iconId: icon, selected: selected }
            button.focused = m.top.focusArea = "detailActions" and m.top.focusedAction = index
            detailRegisterFocus("detailActions", index, button)
            actionX = actionX + 76
        end if
    end for
end sub

function renderDetailSeasonSelector(model as object, seasons as object, y as integer) as integer
    PorticoLabel(m.composition, detailProductText("media.episodes-title", "Episodes", {}), [0, y], 1200, 38, 30, "600", "#F4F7FA")
    selected = invalid
    selectedId = detailText(model.selectedSeasonId, 100)
    for each season in seasons
        if detailText(season.id, 100) = selectedId then selected = season
    end for
    if selected = invalid then selected = seasons[0]
    selector = m.composition.CreateChild("PorticoButton")
    selector.translation = [0, y + 52]
    selector.model = {label: detailText(selected.title, 100), iconId: "navigation.expand", primary: false, width: 410}
    selector.focused = m.top.focusArea = "detailSeason"
    detailRegisterFocus("detailSeason", 0, selector)
    return y + 144
end function

function renderDetailEpisodeState(model as object, y as integer) as integer
    status = LCase(detailText(model.episodesStatus, 24))
    message = detailProductText("media.empty-season", "No episodes are available for this season.", {})
    color = "#8F9BA6"
    if status = "loading" or status = "refreshing"
        message = detailProductTitle("state.loading", "Loading")
    else if status = "error" or status = "offline"
        message = detailProductText("media.children-unavailable-title", "Episodes aren't available", {section: detailProductText("media.episodes-title", "Episodes", {})})
        if status = "offline" then message = "Connect to the server to load episodes."
        color = "#E3B341"
    end if
    PorticoLabel(m.composition, message, [0, y + 10], 1000, 32, 21, "400", color)
    return y + 86
end function

function detailProductText(messageId as string, fallback as string, variables as object) as string
    if m.language = invalid then return fallback
    message = PorticoProductLanguageMessage(m.language, messageId, messageId, variables)
    if message.text <> "" then return message.text
    if message.title <> "" then return message.title
    if message.body <> "" then return message.body
    return fallback
end function

function detailProductTitle(messageId as string, fallback as string) as string
    if m.language = invalid then return fallback
    message = PorticoProductLanguageMessage(m.language, messageId, messageId, {})
    if message.title <> "" then return message.title
    if message.text <> "" then return message.text
    return fallback
end function

function renderDetailMediaRow(titleText as string, items as object, y as integer, focusArea as string, focusedIndex as integer) as integer
    headingOffset = 0
    if m.top.compensation <> invalid then headingOffset = m.top.compensation.sectionHeadingY
    PorticoLabel(m.composition, titleText, [0, y + headingOffset], 1200, 38, 30, "600", "#F4F7FA")
    firstVisible = 0
    if focusedIndex >= 5 then firstVisible = focusedIndex - 4
    x = 0
    nodes = []
    for index = firstVisible to items.count() - 1
        shape = detailShape(items[index])
        cardWidth = 214
        pitch = 232
        if shape = "landscape"
            cardWidth = 320
            pitch = 338
        end if
        if x + cardWidth > 1712 then exit for
        card = CreateObject("roSGNode", "PorticoMediaCard")
        card.translation = [x, y + 52]
        card.shape = shape
        card.model = items[index]
        card.compensation = m.top.compensation
        card.focused = m.top.focusArea = focusArea and index = focusedIndex
        detailRegisterFocus(focusArea, index, card)
        m.composition.appendChild(card)
        nodes.push(card)
        x = x + pitch
    end for
    ' Once focus crosses the current viewport, anchor it in the first fixed slot.
    ' This guarantees the logical target remains visible for mixed card shapes.
    m.focusWindows[focusArea] = {kind: "media", items: items, nodes: nodes, first: firstVisible, leading: 0, y: y + 52}
    return y + 455
end function

function renderDetailPeople(people as object, y as integer) as integer
    headingOffset = 0
    if m.top.compensation <> invalid then headingOffset = m.top.compensation.sectionHeadingY
    PorticoLabel(m.composition, "Cast & Crew", [0, y + headingOffset], 1200, 38, 30, "600", "#F4F7FA")
    firstVisible = 0
    if m.top.focusedPerson >= 9 then firstVisible = m.top.focusedPerson - 8
    nodes = []
    for index = firstVisible to people.count() - 1
        visibleIndex = index - firstVisible
        if visibleIndex >= 9 then exit for
        person = people[index]
        x = visibleIndex * 192
        group = m.composition.CreateChild("Group")
        group.translation = [x, y + 56]
        group.focusable = true
        focused = m.top.focusArea = "detailPeople" and index = m.top.focusedPerson
        selected = detailPersonSelected(person)
        surfaceColor = "#070B10"
        borderColor = "#C5DAEB"
        borderOpacity = 0.0
        if selected
            surfaceColor = "#0A1017"
            borderColor = "#378EC3"
            borderOpacity = 0.46
        end if
        if focused
            surfaceColor = "#151F29"
            borderColor = "#EAF6FF"
            borderOpacity = 1.0
        end if
        PorticoRectangle(group, [0, 0], 170, 232, surfaceColor)
        PorticoRectangle(group, [0, 0], 170, 2, borderColor, borderOpacity)
        PorticoRectangle(group, [0, 230], 170, 2, borderColor, borderOpacity)
        PorticoRectangle(group, [0, 2], 2, 228, borderColor, borderOpacity)
        PorticoRectangle(group, [168, 2], 2, 228, borderColor, borderOpacity)
        if person.image <> invalid and person.image.ToStr() <> ""
            mask = group.CreateChild("MaskGroup")
            mask.translation = [13, 7]
            mask.maskUri = "pkg:/images/ui/settings-avatar.png"
            mask.maskSize = [144, 144]
            PorticoPoster(mask, person.image, [0, 0], 144, 144, "scaleToZoom")
        else
            avatar = PorticoPoster(group, "pkg:/images/ui/settings-avatar.png", [13, 7], 144, 144, "scaleToFit")
            avatar.blendColor = "#1A2632"
            initials = detailInitials(person.name)
            label = PorticoLabel(group, initials, [13, 51], 144, 50, 30, "700", "#70BCE8")
            label.horizAlign = "center"
        end if
        nameLines = PorticoBreakText(person.name, 156, 19, "600", 1)
        nameText = ""
        if nameLines.count() > 0 then nameText = nameLines[0]
        nameLabel = PorticoLabel(group, nameText, [7, 163], 156, 27, 19, "600", "#F4F7FA")
        nameLabel.horizAlign = "center"
        role = detailText(person.character, 80)
        if role = "" then role = detailText(person.role, 80)
        group.accessibilityLabel = detailText(person.name, 100)
        if role <> "" then group.accessibilityLabel = group.accessibilityLabel + ", " + role
        detailRegisterFocus("detailPeople", index, group)
        roleLines = PorticoBreakText(role, 156, 16, "400", 1)
        roleText = ""
        if roleLines.count() > 0 then roleText = roleLines[0]
        roleLabel = PorticoLabel(group, roleText, [7, 194], 156, 24, 16, "400", "#8F9BA6")
        roleLabel.horizAlign = "center"
        group.AddField("porticoName", "node", false)
        group.AddField("porticoRole", "node", false)
        group.porticoName = nameLabel
        group.porticoRole = roleLabel
        nodes.push(group)
    end for
    m.focusWindows.detailPeople = {kind: "person", items: people, nodes: nodes, first: firstVisible, leading: 8}
    return y + 270
end function

sub detailBindPersonSlot(group as object, person as object)
    nameLines = PorticoBreakText(person.name, 156, 19, "600", 1)
    nameText = ""
    if nameLines.count() > 0 then nameText = nameLines[0]
    role = detailText(person.character, 80)
    if role = "" then role = detailText(person.role, 80)
    group.porticoName.text = nameText
    roleLines = PorticoBreakText(role, 156, 16, "400", 1)
    roleText = ""
    if roleLines.count() > 0 then roleText = roleLines[0]
    group.porticoRole.text = roleText
    group.accessibilityLabel = detailText(person.name, 100)
    if role <> "" then group.accessibilityLabel = group.accessibilityLabel + ", " + role
end sub

function detailPersonSelected(person as dynamic) as boolean
    if person = invalid or Type(person) <> "roAssociativeArray" then return false
    model = m.top.model
    if model = invalid or Type(model) <> "roAssociativeArray" then return false
    return detailText(person.id, 100) <> "" and detailText(person.id, 100) = detailText(model.selectedPersonId, 100)
end function

function renderPersonResults(model as object, items as object, status as string, y as integer) as integer
    name = detailText(model.selectedPersonName, 100)
    title = "Featuring " + name
    if status = "loading"
        PorticoLabel(m.composition, title, [0, y], 1200, 38, 30, "600", "#F4F7FA")
        PorticoLabel(m.composition, "Loading titles...", [0, y + 56], 900, 30, 21, "400", "#8F9BA6")
        return y + 130
    else if status = "error" or status = "offline"
        PorticoLabel(m.composition, title, [0, y], 1200, 38, 30, "600", "#F4F7FA")
        message = "Titles couldn't load."
        if status = "offline" then message = "Connect to the server to load titles."
        PorticoLabel(m.composition, message, [0, y + 56], 900, 30, 21, "400", "#E3B341")
        retry = m.composition.CreateChild("PorticoButton")
        retry.translation = [0, y + 96]
        retry.model = {label: "Try Again", iconId: "action.retry", primary: false, width: 190}
        retry.focused = m.top.focusArea = "detailPersonResults"
        return y + 180
    else if status = "empty"
        PorticoLabel(m.composition, title, [0, y], 1200, 38, 30, "600", "#F4F7FA")
        PorticoLabel(m.composition, "No other accessible titles found.", [0, y + 56], 900, 30, 21, "400", "#8F9BA6")
        return y + 130
    end if
    return renderDetailMediaRow(title, items, y, "detailPersonResults", m.top.focusedPersonResult)
end function

function renderVersionsInformation(facts as object, y as integer) as integer
    focused = m.top.focusArea = "detailFacts"
    PorticoRectangle(m.composition, [0, y], 1712, 1, "#C7D0D8", 0.12)
    if focused then PorticoRectangle(m.composition, [0, y + 1], 1712, 90, "#151F29")
    labelColor = "#F4F7FA"
    if focused then labelColor = "#EAF6FF"
    PorticoLabel(m.composition, "Versions & media information", [0, y + 27], 1540, 36, 24, "600", labelColor)
    chevron = "chevron-down"
    if m.top.factsOpen then chevron = "chevron-up"
    semanticId = "navigation.expand"
    if chevron = "chevron-up" then semanticId = "navigation.collapse"
    icon = PorticoPoster(m.composition, PorticoIconResolverPackageUri(semanticId, "rail"), [1660, y + 31], 26, 26, "scaleToFit")
    if focused then icon.blendColor = "#EAF6FF"
    PorticoRectangle(m.composition, [0, y + 91], 1712, 1, "#C7D0D8", 0.12)
    if not m.top.factsOpen then return y + 92

    if facts.count() = 0
        PorticoLabel(m.composition, "No technical media information is available for this item.", [0, y + 122], 1200, 30, 20, "400", "#8F9BA6")
        return y + 190
    end if

    gridY = y + 112
    PorticoRectangle(m.composition, [0, gridY], 1712, 116, "#0A1017")
    cellWidth = Int(1712 / facts.count())
    for index = 0 to facts.count() - 1
        fact = facts[index]
        cellX = index * cellWidth
        if index > 0 then PorticoRectangle(m.composition, [cellX, gridY + 18], 1, 80, "#C7D0D8", 0.12)
        labelNode = PorticoLabel(m.composition, fact.label, [cellX + 20, gridY + 20], cellWidth - 40, 24, 17, "500", "#8F9BA6")
        labelNode.horizAlign = "center"
        valueNode = PorticoLabel(m.composition, fact.value, [cellX + 20, gridY + 56], cellWidth - 40, 34, 22, "600", "#F4F7FA")
        valueNode.horizAlign = "center"
    end for
    return y + 248
end function

sub applyDetailScroll(contentBottom as integer)
    area = m.top.focusArea
    targetY = m.sectionPositions[area]
    offset = 0
    if targetY <> invalid and targetY > 610 then offset = targetY - 610
    maximum = contentBottom - 900
    if maximum < 0 then maximum = 0
    if offset > maximum then offset = maximum
    m.composition.translation = [0, -offset]
end sub

sub renderDetailAvailability(model as object)
    if model.availabilityStatus = invalid or model.availabilityStatus = "current" then return
    label = "OFFLINE"
    if model.availabilityStatus = "refresh-failed" then label = "COULDN'T REFRESH"
    status = PorticoLabel(m.composition, label, [1420, 34], 320, 28, 18, "600", "#E3B341")
    status.horizAlign = "right"
end sub

function detailUiActionIds(model as object) as object
    if model.uiActions = invalid or GetInterface(model.uiActions, "ifArray") = invalid then return []
    result = []
    allowed = { play: true, "play.from-beginning": true, "saved-toggle": true, "favorite-toggle": true, "watched-toggle": true, "watch-with-friends.start": true, "feedback.report-problem": true, "feedback.request-higher-quality": true, more: true }
    for each rawAction in model.uiActions
        action = LCase(rawAction.ToStr())
        if allowed[action] = true and result.count() < 9 then result.push(action)
    end for
    return result
end function

function detailContractAction(model as object, expectedId as string) as dynamic
    actions = detailArray(model.contractActions)
    for each action in actions
        if action <> invalid and Type(action) = "roAssociativeArray" and detailText(action.id, 100) = expectedId then return action
    end for
    return invalid
end function

function detailArray(value as dynamic) as object
    if value <> invalid and GetInterface(value, "ifArray") <> invalid then return value
    return []
end function

function detailText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    text = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Trim()
    if Len(text) > maximum then text = Left(text, maximum)
    return text
end function

function detailShape(item as dynamic) as string
    if item = invalid or Type(item) <> "roAssociativeArray" then return "poster"
    kind = LCase(detailText(item.kind, 32))
    if kind = "episode" or kind = "recording" or kind = "live-channel" or kind = "live-program" then return "landscape"
    if kind = "artist" or kind = "album" or kind = "track" or kind = "author" or kind = "book" then return "square"
    return "poster"
end function

function detailInitials(value as dynamic) as string
    name = detailText(value, 100)
    if name = "" then return "?"
    parts = name.Tokenize(" ")
    result = ""
    for each part in parts
        if part <> "" and Len(result) < 2 then result = result + UCase(Left(part, 1))
    end for
    return result
end function
