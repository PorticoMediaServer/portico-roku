sub init()
    m.surface = m.top.findNode("surface")
    m.icon = m.top.findNode("icon")
    m.label = m.top.findNode("label")
    m.label.font = PorticoFont("600", 21)
    loadedIcons = PorticoIconResolverLoad()
    m.iconManifest = invalid
    if loadedIcons.ok then m.iconManifest = loadedIcons.value
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    width = 210
    if model.width <> invalid then width = model.width
    if width < 150 then width = 150
    if width > 360 then width = 360
    selected = model.selected = true
    m.top.focusable = true
    m.surface.width = width
    m.surface.loadWidth = width
    if m.top.focused
        m.surface.uri = "pkg:/images/ui/browse-action-focus.png"
    else if selected
        m.surface.uri = "pkg:/images/ui/browse-action-selected.png"
    else
        m.surface.uri = "pkg:/images/ui/browse-action-idle.png"
    end if
    iconState = "rail"
    if selected then iconState = "selected"
    if m.top.focused then iconState = "focused"
    m.icon.uri = PorticoIconResolverUri(m.iconManifest, model.iconId, iconState)
    m.label.text = Left(model.label.ToStr(), 36)
    m.label.width = width - 70
    m.label.color = "#F4F7FA"
    if selected then m.label.color = "#70BCE8"
end sub
