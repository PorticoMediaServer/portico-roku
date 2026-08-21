sub init()
    m.surface = m.top.findNode("surface")
    m.icon = m.top.findNode("icon")
    m.label = m.top.findNode("label")
    loadedIcons = PorticoIconResolverLoad()
    m.iconManifest = invalid
    if loadedIcons.ok then m.iconManifest = loadedIcons.value
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    m.top.accessibilityLabel = model.label.ToStr()
    if model.disabled = true then m.top.accessibilityLabel = m.top.accessibilityLabel + ", unavailable"
    if m.top.focused then m.top.setFocus(true)

    width = 166
    if model.width <> invalid then width = model.width
    primary = model.primary = true

    m.top.focusable = true
    m.surface.width = width
    m.surface.height = 64
    m.surface.loadWidth = width
    m.surface.loadHeight = 64
    surfaceUri = "pkg:/images/ui/button-dark.png"
    if primary
        surfaceUri = "pkg:/images/ui/button-primary.png"
        if m.top.focused then surfaceUri = "pkg:/images/ui/button-primary-focus.png"
    else if m.top.focused
        surfaceUri = "pkg:/images/ui/button-dark-focus.png"
    end if
    m.surface.uri = surfaceUri

    iconState = "default"
    if primary then iconState = "dark-background"
    if m.top.focused then iconState = "focused"
    if model.disabled = true then iconState = "disabled"
    m.icon.translation = [22, 19]
    m.icon.width = 26
    m.icon.height = 26
    m.icon.loadWidth = 26
    m.icon.loadHeight = 26
    m.icon.uri = PorticoIconResolverUri(m.iconManifest, model.iconId, iconState)

    m.label.text = model.label
    m.label.translation = [60, 0]
    m.label.width = width - 78
    m.label.height = 64
    m.label.font = PorticoFont("600", 21)
    m.label.color = "#F4F7FA"
    if primary then m.label.color = "#070B10"
end sub
