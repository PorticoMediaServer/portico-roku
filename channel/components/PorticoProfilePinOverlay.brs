sub init()
    m.title = m.top.findNode("title")
    m.dots = m.top.findNode("dots")
    m.error = m.top.findNode("error")
    m.keys = []
    for index = 0 to 11
        key = m.top.findNode("key" + index.ToStr())
        label = (index + 1).ToStr()
        if index = 9 then label = "Clear"
        if index = 10 then label = "0"
        if index = 11 then label = "Delete"
        key.model = {label: label}
        m.keys.Push(key)
    end for
    m.title.font = PorticoFont("700", 38)
    m.title.color = "#F4F7FA"
    m.dots.font = PorticoFont("600", 38)
    m.dots.color = "#70BCE8"
    m.error.font = PorticoFont("400", 19)
    m.error.color = "#E98A92"
    m.top.focusable = true
    m.index = 0
    m.pin = ""
    m.sequence = 0
    loadedLanguage = PorticoProductLanguageLoad()
    m.language = invalid
    if loadedLanguage.ok then m.language = loadedLanguage.value
    applyFocus()
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid then return
    profileName = "This profile"
    if state.profileName <> invalid then profileName = Left(state.profileName.ToStr(), 60)
    m.title.text = "Enter the profile PIN"
    if m.language <> invalid
        copy = PorticoProductLanguageMessage(m.language, "auth.profile-pin-required", "auth.profile-pin-required", {profileName: profileName})
        if copy.title <> "" then m.title.text = copy.title
    end if
    m.error.text = ""
    if state.errorMessageId <> invalid and m.language <> invalid
        errorCopy = PorticoProductLanguageMessage(m.language, state.errorMessageId, "auth.profile-selection-failed", {profileName: profileName})
        if errorCopy.body <> "" then m.error.text = errorCopy.body
    end if
end sub

sub applyFocus()
    for index = 0 to m.keys.Count() - 1
        m.keys[index].focused = index = m.index
    end for
    dots = ""
    for index = 1 to Len(m.pin)
        dots = dots + "•"
    end for
    m.dots.text = dots
end sub

sub emit(kind as string, includePin as boolean)
    m.sequence = m.sequence + 1
    event = {sequence: m.sequence, kind: kind}
    if includePin then m.pendingPin = m.pin
    m.top.activation = event
    if includePin then m.pin = ""
    applyFocus()
end sub

function consumePin() as string
    value = ""
    if m.pendingPin <> invalid then value = m.pendingPin
    m.pendingPin = ""
    return value
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    row = Int(m.index / 3)
    column = m.index mod 3
    if key = "left" and column > 0 then m.index = m.index - 1
    if key = "right" and column < 2 then m.index = m.index + 1
    if key = "up" and row > 0 then m.index = m.index - 3
    if key = "down" and row < 3 then m.index = m.index + 3
    if key = "back"
        emit("cancel-profile-pin", false)
        return true
    end if
    if key = "OK"
        if m.index <= 8 and Len(m.pin) < 4 then m.pin = m.pin + (m.index + 1).ToStr()
        if m.index = 9 then m.pin = ""
        if m.index = 10 and Len(m.pin) < 4 then m.pin = m.pin + "0"
        if m.index = 11 and Len(m.pin) > 0 then m.pin = Left(m.pin, Len(m.pin) - 1)
        if Len(m.pin) = 4 then emit("submit-profile-pin", true)
    end if
    applyFocus()
    return true
end function
