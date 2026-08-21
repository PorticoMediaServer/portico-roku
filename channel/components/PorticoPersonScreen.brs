sub init()
    m.identity = m.top.findNode("identity")
    m.portraitFrame = m.top.findNode("portraitFrame")
    m.personName = m.top.findNode("personName")
    m.personRoles = m.top.findNode("personRoles")
    m.creditsTitle = m.top.findNode("creditsTitle")
    m.credits = m.top.findNode("credits")
    m.state = m.top.findNode("state")
    m.stateTitle = m.top.findNode("stateTitle")
    m.stateBody = m.top.findNode("stateBody")
    m.retry = m.top.findNode("retry")
    m.loadMore = m.top.findNode("loadMore")
    m.personName.font = PorticoFont("700", 48)
    m.personName.color = "#F4F7FA"
    m.personRoles.font = PorticoFont("500", 20)
    m.personRoles.color = "#8F9BA6"
    m.creditsTitle.font = PorticoFont("600", 30)
    m.creditsTitle.color = "#F4F7FA"
    m.stateTitle.font = PorticoFont("600", 30)
    m.stateTitle.color = "#F4F7FA"
    m.stateBody.font = PorticoFont("400", 20)
    m.stateBody.color = "#8F9BA6"
    loaded = PorticoProductLanguageLoad()
    m.language = invalid
    if loaded.ok then m.language = loaded.value
    m.cards = []
    for index = 0 to 6
        card = CreateObject("roSGNode", "PorticoMediaCard")
        card.translation = [index * 232, 0]
        card.visible = false
        m.credits.appendChild(card)
        m.cards.push(card)
    end for
    m.focusIndex = 0
    m.personId = ""
    m.activationSequence = 0
    m.top.focusable = true
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or Type(state) <> "roAssociativeArray" then return
    personId = personText(state.personId, "", 128)
    if personId <> m.personId
        m.personId = personId
        m.focusIndex = 0
    end if
    m.personName.text = personText(state.name, "", 100)
    roles = []
    if state.roles <> invalid and GetInterface(state.roles, "ifArray") <> invalid then roles = state.roles
    roleLabels = []
    for each rawRole in roles
        role = personText(rawRole, "", 48)
        if role <> "" and roleLabels.count() < 8 then roleLabels.push(role)
    end for
    m.personRoles.text = personJoin(roleLabels, "  ·  ")
    m.creditsTitle.text = personCopyText("media.people-credits", "Credits")
    renderPortrait(personText(state.image, "", 512))
    for each card in m.cards
        card.visible = false
        card.focused = false
    end for
    items = []
    if state.items <> invalid and GetInterface(state.items, "ifArray") <> invalid then items = state.items
    status = LCase(personText(state.status, "loading", 24))
    hasMore = status = "ready" and state.hasMore = true
    maximum = items.count() - 1
    if hasMore then maximum = items.count()
    if status = "error" or status = "offline"
        m.focusIndex = -1
    else if maximum >= 0
        if m.focusIndex < 0 then m.focusIndex = 0
        if m.focusIndex > maximum then m.focusIndex = maximum
    else
        m.focusIndex = 0
    end if
    firstVisible = m.focusIndex - 3
    if firstVisible < 0 then firstVisible = 0
    if firstVisible + m.cards.count() > items.count() then firstVisible = items.count() - m.cards.count()
    if firstVisible < 0 then firstVisible = 0
    for index = firstVisible to items.count() - 1
        visibleIndex = index - firstVisible
        if visibleIndex >= m.cards.count() then exit for
        m.cards[visibleIndex].model = items[index]
        m.cards[visibleIndex].visible = true
        m.cards[visibleIndex].focused = m.focusIndex = index
    end for
    m.state.visible = status = "loading" or status = "error" or status = "offline" or status = "empty"
    m.retry.visible = false
    m.retry.focused = false
    if status = "loading"
        renderPersonMessage("media.detail-loading")
    else if status = "empty"
        renderPersonMessage("search.people-empty")
    else if status = "error" or status = "offline"
        id = personText(state.messageId, "media.search-failed", 120)
        renderPersonMessage(id)
        m.retry.model = {label: personCopyText("action.retry", "Try again"), iconId: "action.retry", primary: true, width: 190}
        m.retry.visible = true
        m.retry.focused = m.focusIndex = -1
    end if
    m.loadMore.visible = hasMore
    m.loadMore.model = {label: personCopyText("action.load-more", "Load more"), iconId: "action.add", primary: false, width: 210}
    m.loadMore.focused = m.focusIndex = items.count()
    publishPersonFocus(items)
end sub

sub renderPortrait(uri as string)
    m.portraitFrame.removeChildrenIndex(m.portraitFrame.getChildCount(), 0)
    bed = PorticoPoster(m.portraitFrame, "pkg:/images/ui/settings-avatar.png", [0, 0], 152, 152, "scaleToFit")
    bed.blendColor = "#1A2632"
    if Left(uri, 5) = "tmp:/" or Left(uri, 5) = "pkg:/"
        mask = m.portraitFrame.CreateChild("MaskGroup")
        mask.translation = [4, 4]
        mask.maskUri = "pkg:/images/ui/settings-avatar.png"
        mask.maskSize = [144, 144]
        PorticoPoster(mask, uri, [0, 0], 144, 144, "scaleToZoom")
    else
        initials = personInitials(m.personName.text)
        label = PorticoLabel(m.portraitFrame, initials, [0, 42], 152, 64, 46, "700", "#C7D0D8")
        label.horizAlign = "center"
    end if
end sub

sub renderPersonMessage(messageId as string)
    copy = personCopy(messageId, "problem.request-failed")
    m.stateTitle.text = copy.title
    if m.stateTitle.text = "" then m.stateTitle.text = copy.text
    m.stateBody.text = copy.body
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    state = m.top.viewState
    if state = invalid then return false
    items = []
    if state.items <> invalid and GetInterface(state.items, "ifArray") <> invalid then items = state.items
    status = LCase(personText(state.status, "loading", 24))
    maximum = items.count() - 1
    if status = "ready" and state.hasMore = true then maximum = items.count()
    if m.retry.visible then maximum = -1
    if key = "left"
        if m.focusIndex > 0 then m.focusIndex = m.focusIndex - 1 else return false
    else if key = "right"
        if m.focusIndex < maximum then m.focusIndex = m.focusIndex + 1
    else if key = "OK"
        m.activationSequence = m.activationSequence + 1
        if m.focusIndex = -1
            m.top.activation = {sequence: m.activationSequence, kind: "retry-person", targetId: personText(state.personId, "", 128)}
        else if m.focusIndex = items.count() and state.hasMore = true
            m.top.activation = {sequence: m.activationSequence, kind: "load-more-person", targetId: personText(state.personId, "", 128)}
        else if m.focusIndex >= 0 and m.focusIndex < items.count()
            m.top.activation = {sequence: m.activationSequence, kind: "open-detail", targetId: personText(items[m.focusIndex].id, "", 128)}
        end if
        return true
    else if key = "back"
        return false
    else
        return true
    end if
    applyViewState()
    return true
end function

sub publishPersonFocus(items as object)
    key = ""
    if m.focusIndex >= 0 and m.focusIndex < items.count() then key = "media:" + personText(items[m.focusIndex].id, "", 128)
    if m.focusIndex = items.count() then key = "load-more"
    if m.focusIndex = -1 then key = "retry"
    m.top.focusState = {key: key, index: m.focusIndex}
end sub

function personCopy(messageId as string, fallbackId as string) as object
    if m.language = invalid then return {title: "", body: "", text: ""}
    return PorticoProductLanguageMessage(m.language, messageId, fallbackId, {})
end function

function personCopyText(messageId as string, fallback as string) as string
    copy = personCopy(messageId, messageId)
    value = copy.text
    if value = "" then value = copy.title
    if value = "" then value = fallback
    return value
end function

function personText(value as dynamic, fallback as string, maximum as integer) as string
    if value = invalid then return fallback
    result = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Trim()
    if result = "" then result = fallback
    if Len(result) > maximum then result = Left(result, maximum)
    return result
end function

function personJoin(values as object, separator as string) as string
    result = ""
    for each value in values
        if result <> "" then result = result + separator
        result = result + value
    end for
    return result
end function

function personInitials(name as string) as string
    result = ""
    for each part in name.Tokenize(" ")
        if part <> "" and Len(result) < 2 then result = result + UCase(Left(part, 1))
    end for
    return result
end function
