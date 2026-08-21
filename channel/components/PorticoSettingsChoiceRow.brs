sub init()
    m.surface = m.top.findNode("surface")
    m.label = m.top.findNode("label")
    m.radio = m.top.findNode("radio")
    m.label.font = PorticoFont("500", 23)
    m.label.color = "#F4F7FA"
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or state.model = invalid then return
    if state.model.id <> invalid then m.top.semanticId = "settings.choice." + state.model.id.ToStr()
    selected = state.model.selected = true
    focused = state.focused = true
    surfaceState = "idle"
    if selected then surfaceState = "selected"
    if focused then surfaceState = "focus"
    m.surface.uri = "pkg:/images/ui/settings-choice-" + surfaceState + ".png"
    m.label.text = PorticoSettingsChoiceText(state.model.label)
    radioState = ""
    if selected then radioState = "-selected"
    if focused
        radioState = "-focus"
        if selected then radioState = "-selected-focus"
    end if
    m.radio.uri = "pkg:/images/ui/server-radio" + radioState + ".png"
end sub

function PorticoSettingsChoiceText(value as dynamic) as string
    if value = invalid then return ""
    result = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Trim()
    if Len(result) > 60 then result = Left(result, 60)
    return result
end function
