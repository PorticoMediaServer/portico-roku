sub init()
    m.surface = m.top.findNode("surface")
    m.icon = m.top.findNode("icon")
    m.label = m.top.findNode("label")
    m.description = m.top.findNode("description")
    m.valueGroup = m.top.findNode("valueGroup")
    m.value = m.top.findNode("value")
    m.chevron = m.top.findNode("chevron")
    m.toggle = m.top.findNode("toggle")

    m.label.font = PorticoFont("600", 22)
    m.label.color = "#F4F7FA"
    m.label.vertAlign = "top"
    m.description.font = PorticoFont("400", 17)
    m.description.color = "#8F9BA6"
    m.description.vertAlign = "top"
    m.value.font = PorticoFont("500", 19)
    m.value.color = "#C7D0D8"
    loadedIcons = PorticoIconResolverLoad()
    m.iconManifest = invalid
    if loadedIcons.ok then m.iconManifest = loadedIcons.value
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or state.model = invalid then return
    model = state.model
    focused = state.focused = true
    actionable = model.actionable <> false
    kind = "action"
    if model.kind <> invalid then kind = LCase(model.kind.ToStr())

    m.surface.uri = "pkg:/images/ui/settings-row-idle.png"
    if focused and actionable then m.surface.uri = "pkg:/images/ui/settings-row-focus.png"

    iconState = "rail"
    if focused and actionable then iconState = "focused"
    if not actionable then iconState = "disabled"
    m.icon.uri = PorticoIconResolverUri(m.iconManifest, model.iconId, iconState)

    m.label.text = PorticoSettingsRowText(model.label, "", 72)
    m.description.text = PorticoSettingsRowText(model.description, "", 150)
    m.value.text = PorticoSettingsRowText(model.value, "", 44)
    semantic = m.label.text
    if m.value.text <> "" then semantic = semantic + ", " + m.value.text
    if kind = "toggle"
        if model.checked = true then semantic = semantic + ", on" else semantic = semantic + ", off"
    end if
    if not actionable and kind = "information" then semantic = semantic + ", read only"
    if not actionable and kind <> "information" then semantic = semantic + ", unavailable"
    m.top.accessibilityLabel = semantic
    m.top.focusable = actionable
    if focused and actionable then m.top.setFocus(true)
    m.valueGroup.visible = kind <> "toggle"
    m.chevron.visible = kind = "action" and actionable
    disclosureState = "rail"
    if focused and actionable then disclosureState = "focused"
    m.chevron.uri = PorticoIconResolverUri(m.iconManifest, "navigation.disclosure", disclosureState)
    m.toggle.visible = kind = "toggle"
    if kind = "toggle"
        toggleState = "off"
        if model.checked = true then toggleState = "on"
        m.toggle.uri = "pkg:/images/ui/settings-toggle-" + toggleState + ".png"
    end if

    m.label.color = "#F4F7FA"
    m.description.color = "#8F9BA6"
    m.value.color = "#C7D0D8"
    if not actionable
        m.icon.opacity = 0.72
        m.label.color = "#C7D0D8"
        m.value.color = "#8F9BA6"
    else
        m.icon.opacity = 1.0
    end if
end sub

function PorticoSettingsRowText(value as dynamic, fallback as string, maximum as integer) as string
    if value = invalid then return fallback
    result = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if result = "" then result = fallback
    if Len(result) > maximum then result = Left(result, maximum)
    return result
end function
