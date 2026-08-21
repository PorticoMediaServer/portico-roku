sub init()
    m.surface = m.top.findNode("surface")
    m.label = m.top.findNode("label")
    m.rule = m.top.findNode("rule")
    m.label.font = PorticoFont("600", 22)
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    m.top.focusable = true
    selected = model.selected = true
    m.label.text = Left(model.label.ToStr(), 22)
    m.label.color = "#8F9BA6"
    if selected or m.top.focused then m.label.color = "#F4F7FA"
    m.rule.visible = selected
    if m.top.focused
        m.surface.uri = "pkg:/images/ui/browse-tab-focus.png"
    else
        m.surface.uri = "pkg:/images/ui/browse-tab-idle.png"
    end if
end sub
