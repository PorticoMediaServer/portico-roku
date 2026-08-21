sub init()
    m.surface = m.top.findNode("surface")
    m.selection = m.top.findNode("selection")
    m.icon = m.top.findNode("icon")
    m.label = m.top.findNode("label")
    loadedIcons = PorticoIconResolverLoad()
    m.iconManifest = invalid
    if loadedIcons.ok then m.iconManifest = loadedIcons.value
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    width = 64
    if m.top.expanded then width = 264

    m.top.focusable = true
    m.surface.width = width
    m.surface.loadWidth = width
    if m.top.focused
        m.surface.uri = "pkg:/images/ui/rail-focus-collapsed.png"
        if m.top.expanded then m.surface.uri = "pkg:/images/ui/rail-focus-expanded.png"
    else if model.selected = true
        m.surface.uri = "pkg:/images/ui/rail-selected-collapsed.png"
        if m.top.expanded then m.surface.uri = "pkg:/images/ui/rail-selected-expanded.png"
    else
        m.surface.uri = ""
    end if

    m.selection.visible = model.selected = true
    iconState = "rail"
    if model.selected = true then iconState = "selected"
    if m.top.focused then iconState = "focused"
    m.icon.opacity = 1.0
    m.icon.uri = PorticoIconResolverUri(m.iconManifest, model.iconId, iconState)
    m.label.text = model.label
    m.label.font = PorticoFont("600", 21)
    m.label.color = "#F4F7FA"
    m.label.visible = m.top.expanded
end sub
