sub init()
    m.focusBorder = m.top.findNode("focusBorder")
    m.surface = m.top.findNode("surface")
    m.liveRule = m.top.findNode("liveRule")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.title.font = PorticoFont("600", 20)
    m.title.color = "#F4F7FA"
    m.meta.font = PorticoFont("400", 17)
    m.meta.color = "#8F9BA6"
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    width = m.top.cellWidth
    if width < 280 then width = 280
    if width > 620 then width = 620
    m.top.focusable = true
    m.focusBorder.width = width
    m.surface.width = width - 6
    m.title.width = width - 44
    m.meta.width = width - 44
    live = model.live = true
    m.liveRule.visible = live
    if m.top.focused
        m.focusBorder.visible = true
        m.surface.color = "#192633"
    else
        m.focusBorder.visible = false
        if m.top.selected
            m.surface.color = "#17222D"
        else if live
            m.surface.color = "#131E28"
        else
            m.surface.color = "#0D151D"
        end if
    end if
    m.title.text = Left(model.title.ToStr(), 90)
    meta = "Up next"
    if model.subtitle <> invalid and model.subtitle.ToStr() <> "" then meta = model.subtitle.ToStr()
    if live then meta = "Live now"
    m.meta.text = Left(meta, 100)
    m.top.accessibilityLabel = m.title.text + ", " + m.meta.text
    if m.top.focused then m.top.setFocus(true)
end sub
