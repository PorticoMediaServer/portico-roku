sub init()
    m.surface = m.top.findNode("surface")
    m.label = m.top.findNode("label")
    m.label.font = PorticoFont("600", 19)
    m.label.color = "#C7D0D8"
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    m.top.accessibilityLabel = model.label.ToStr()
    if m.top.focused then m.top.setFocus(true)
    m.top.focusable = true
    m.label.text = Left(model.label.ToStr(), 10)
    if Len(m.label.text) > 2
        m.label.font = PorticoFont("600", 16)
    else
        m.label.font = PorticoFont("600", 19)
    end if
    m.label.color = "#C7D0D8"
    if m.top.focused then m.label.color = "#F4F7FA"
    if m.top.focused
        m.surface.uri = "pkg:/images/ui/search-key-focus.png"
    else
        m.surface.uri = "pkg:/images/ui/search-key-idle.png"
    end if
end sub
