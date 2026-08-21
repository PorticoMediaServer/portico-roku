sub init()
    m.surface = m.top.findNode("surface")
    m.icon = m.top.findNode("icon")
    loadedIcons = PorticoIconResolverLoad()
    m.iconManifest = invalid
    if loadedIcons.ok then m.iconManifest = loadedIcons.value
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    semantic = PorticoIconButtonLabel(model.iconId)
    if model.label <> invalid and model.label.ToStr() <> "" then semantic = model.label.ToStr()
    if model.selected = true then semantic = semantic + ", selected"
    m.top.accessibilityLabel = semantic
    if m.top.focused then m.top.setFocus(true)
    m.top.focusable = true
    selected = model.selected = true
    surfaceUri = "pkg:/images/ui/icon-button.png"
    if selected then surfaceUri = "pkg:/images/ui/icon-button-selected.png"
    if m.top.focused
        surfaceUri = "pkg:/images/ui/icon-button-focus.png"
        if selected then surfaceUri = "pkg:/images/ui/icon-button-selected-focus.png"
    end if
    m.surface.loadWidth = 64
    m.surface.loadHeight = 64
    m.surface.loadDisplayMode = "scaleToFill"
    m.surface.uri = surfaceUri

    iconState = "default"
    if selected then iconState = "selected"
    if m.top.focused then iconState = "focused"
    m.icon.width = 29
    m.icon.height = 29
    m.icon.loadWidth = 29
    m.icon.loadHeight = 29
    m.icon.loadDisplayMode = "scaleToFit"
    m.icon.uri = PorticoIconResolverUri(m.iconManifest, model.iconId, iconState)
end sub

function PorticoIconButtonLabel(value as dynamic) as string
    icon = LCase(value.ToStr())
    if icon = "action.watchlist" then return "Saved"
    if icon = "action.favorite" then return "Favorite"
    if icon = "metadata.info" then return "More information"
    if icon = "action.mark-watched" then return "Watched"
    if icon = "playback.captions" then return "Audio and subtitles"
    if icon = "navigation.settings" then return "Settings"
    if icon = "action.customize" then return "More actions"
    if icon = "playback.queue" then return "Queue"
    return icon
end function
