sub init()
    m.wordmark = m.top.findNode("wordmark")
    m.title = m.top.findNode("title")
    m.message = m.top.findNode("message")
    m.cardsGroup = m.top.findNode("cards")
    m.cards = []
    for index = 0 to 7
        m.cards.Push(m.top.findNode("card" + index.ToStr()))
    end for
    m.pinOverlay = m.top.findNode("pinOverlay")
    m.pinOverlay.ObserveField("activation", "onPinActivation")
    m.wordmark.uri = "pkg:/images/brand/portico-wordmark.png"
    m.title.font = PorticoFont("700", 48)
    m.title.color = "#F4F7FA"
    m.message.font = PorticoFont("400", 22)
    m.message.color = "#8F9BA6"
    m.top.focusable = true
    m.index = 0
    m.profiles = []
    m.sequence = 0
    m.screenAuthority = PorticoScreenAuthorityCreate("profile-selection")
    loadedLanguage = PorticoProductLanguageLoad()
    m.language = invalid
    if loadedLanguage.ok then m.language = loadedLanguage.value
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid then return
    PorticoScreenAuthorityFence(m.screenAuthority, PorticoProfilesInteger(state.viewerGeneration, 0))
    m.title.text = "Who's watching?"
    m.message.text = "Choose a profile to continue."
    if m.language <> invalid
        copy = PorticoProductLanguageMessage(m.language, "auth.profile-selection-required", "auth.profile-selection-required", {})
        if copy.title <> "" then m.title.text = copy.title
        if copy.body <> "" then m.message.text = copy.body
    end if
    m.profiles = []
    if state.profiles <> invalid and GetInterface(state.profiles, "ifArray") <> invalid then m.profiles = state.profiles
    if m.profiles.Count() > 8
        bounded = []
        for index = 0 to 7
            bounded.Push(m.profiles[index])
        end for
        m.profiles = bounded
    end if
    if m.index >= m.profiles.Count() then m.index = 0
    semanticIds = []
    for each profile in m.profiles
        semanticIds.Push("profile.card." + profile.id)
    end for
    PorticoScreenAuthorityTargets(m.screenAuthority, semanticIds)
    if m.pinOverlay.visible and m.index < m.profiles.count()
        m.pinOverlay.viewState = {profileName: m.profiles[m.index].name, errorMessageId: state.errorMessageId}
    end if
    for index = 0 to 7
        m.cards[index].visible = index < m.profiles.Count()
        if index < m.profiles.Count() then m.cards[index].viewState = {model: m.profiles[index], focused: index = m.index and not m.pinOverlay.visible}
    end for
    totalWidth = m.profiles.Count() * 214 + (m.profiles.Count() - 1) * 18
    if totalWidth < 0 then totalWidth = 0
    m.cardsGroup.translation = [Int((1920 - totalWidth) / 2), 410]
end sub

sub emit(kind as string, profileId as string, sealedPin = "" as string)
    PorticoScreenAuthorityCommitOK(m.screenAuthority)
    m.sequence = m.sequence + 1
    event = {sequence: m.sequence, kind: kind, profileId: profileId}
    if sealedPin <> "" then event.sealedPin = sealedPin
    m.top.activation = event
end sub

sub onPinActivation()
    event = m.pinOverlay.activation
    if event = invalid then return
    if event.kind = "cancel-profile-pin"
        m.pinOverlay.visible = false
        fallbackId = "profile.card.unavailable"
        if m.index < m.profiles.Count() then fallbackId = "profile.card." + m.profiles[m.index].id
        restoredId = PorticoScreenAuthorityCloseModal(m.screenAuthority, fallbackId)
        PorticoScreenAuthorityFocused(m.screenAuthority, restoredId)
        applyViewState()
        m.top.setFocus(true)
    else if event.kind = "submit-profile-pin"
        profileId = ""
        if m.index < m.profiles.Count() then profileId = m.profiles[m.index].id
        pin = m.pinOverlay.callFunc("consumePin")
        generation = 0
        if m.top.viewState <> invalid then generation = PorticoProfilesInteger(m.top.viewState.viewerGeneration, 0)
        sealedPin = PorticoProfilesSealPin(pin, profileId, generation)
        pin = ""
        if sealedPin <> "" then emit("select-profile", profileId, sealedPin)
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        PorticoScreenAuthorityRelease(m.screenAuthority, key)
        return false
    end if
    if m.pinOverlay.visible then return true
    if key = "left" and m.index > 0
        currentId = "profile.card." + m.profiles[m.index].id
        targetId = "profile.card." + m.profiles[m.index - 1].id
        if PorticoScreenAuthorityAcceptMove(m.screenAuthority, "left", currentId, targetId) then m.index = m.index - 1
    end if
    if key = "right" and m.index + 1 < m.profiles.Count()
        currentId = "profile.card." + m.profiles[m.index].id
        targetId = "profile.card." + m.profiles[m.index + 1].id
        if PorticoScreenAuthorityAcceptMove(m.screenAuthority, "right", currentId, targetId) then m.index = m.index + 1
    end if
    if key = "OK" and m.index < m.profiles.Count()
        profile = m.profiles[m.index]
        semanticId = "profile.card." + profile.id
        if not PorticoScreenAuthorityBeginOK(m.screenAuthority, semanticId) then return true
        if profile.hasPIN = true
            PorticoScreenAuthorityOpenModal(m.screenAuthority, semanticId)
            m.pinOverlay.viewState = {profileName: profile.name, errorMessageId: ""}
            m.pinOverlay.visible = true
            m.pinOverlay.setFocus(true)
        else
            emit("select-profile", profile.id)
        end if
    end if
    if key = "back"
        emit("cancel-profile-selection", "")
        return true
    end if
    applyViewState()
    return true
end function
