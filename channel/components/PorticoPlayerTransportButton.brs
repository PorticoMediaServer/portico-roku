sub init()
    m.surface = m.top.findNode("surface")
    m.icon = m.top.findNode("icon")
    m.top.focusable = true
    loadedIcons = PorticoIconResolverLoad()
    m.iconManifest = invalid
    if loadedIcons.ok then m.iconManifest = loadedIcons.value
end sub

sub render()
    model = m.top.model
    if model = invalid or Type(model) <> "roAssociativeArray"
        m.top.visible = false
        return
    end if
    iconId = PorticoPlayerTransportIcon(model.iconId)
    if iconId = ""
        m.top.visible = false
        return
    end if

    main = model.main = true
    m.top.opacity = 1.0
    if model.disabled = true then m.top.opacity = 0.35
    semantic = PorticoPlayerTransportLabel(iconId)
    if model.disabled = true then semantic = semantic + ", unavailable"
    m.top.accessibilityLabel = semantic
    if m.top.focused then m.top.setFocus(true)
    size = 60
    iconSize = 28
    surfaceName = "player-transport-idle.png"
    if m.top.focused then surfaceName = "player-transport-focus.png"
    if main
        size = 78
        iconSize = 34
        surfaceName = "player-transport-main.png"
        if m.top.focused then surfaceName = "player-transport-main-focus.png"
    end if

    m.top.visible = true
    m.surface.width = size
    m.surface.height = size
    m.surface.loadWidth = size
    m.surface.loadHeight = size
    m.surface.uri = "pkg:/images/ui/" + surfaceName

    iconInset = Int((size - iconSize) / 2)
    m.icon.translation = [iconInset, iconInset]
    m.icon.width = iconSize
    m.icon.height = iconSize
    m.icon.loadWidth = iconSize
    m.icon.loadHeight = iconSize
    iconState = "default"
    if m.top.focused then iconState = "focused"
    if model.disabled = true then iconState = "disabled"
    m.icon.uri = PorticoIconResolverUri(m.iconManifest, iconId, iconState)
end sub

function PorticoPlayerTransportIcon(value as dynamic) as string
    if value = invalid then return ""
    iconId = LCase(value.ToStr().Trim())
    allowed = {"playback.previous": true, "playback.seek-back": true, "playback.play": true, "playback.pause": true, "playback.seek-forward": true, "playback.next": true}
    if allowed[iconId] <> true then return ""
    return iconId
end function

function PorticoPlayerTransportLabel(iconName as string) as string
    if iconName = "playback.previous" then return "Previous"
    if iconName = "playback.seek-back" then return "Rewind"
    if iconName = "playback.play" then return "Play"
    if iconName = "playback.pause" then return "Pause"
    if iconName = "playback.seek-forward" then return "Fast forward"
    if iconName = "playback.next" then return "Next"
    return "Playback control"
end function
