sub init()
    m.surface = m.top.findNode("surface")
    m.focusBorder = m.top.findNode("focusBorder")
    m.logo = m.top.findNode("logo")
    m.mark = m.top.findNode("mark")
    m.title = m.top.findNode("title")
    m.now = m.top.findNode("now")
    m.number = m.top.findNode("number")
    m.mark.font = PorticoFont("700", 22)
    m.mark.color = "#F4F7FA"
    m.title.font = PorticoFont("600", 24)
    m.title.color = "#F4F7FA"
    m.now.font = PorticoFont("500", 18)
    m.now.color = "#C7D0D8"
    m.number.font = PorticoFont("400", 16)
    m.number.color = "#8F9BA6"
    m.hasLogoUri = false
    m.logo.observeField("loadStatus", "onChannelCardLogoStatus")
end sub

sub onChannelCardLogoStatus()
    updateChannelCardLogo()
end sub

sub updateChannelCardLogo()
    failed = m.logo.loadStatus = "failed"
    m.logo.visible = m.hasLogoUri and not failed
    m.mark.visible = not m.hasLogoUri or failed
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    m.top.focusable = true
    m.focusBorder.visible = m.top.focused
    if m.top.focused then m.surface.color = "#151F29" else m.surface.color = "#0A1017"
    logo = ""
    if model.logo <> invalid then logo = model.logo.ToStr()
    m.logo.uri = logo
    m.hasLogoUri = logo <> ""
    m.mark.text = ""
    if model.mark <> invalid then m.mark.text = Left(model.mark.ToStr(), 3)
    m.title.text = Left(model.title.ToStr(), 80)
    m.now.text = "No guide data"
    if model.now <> invalid and model.now.ToStr() <> "" then m.now.text = Left(model.now.ToStr(), 100)
    m.number.text = ""
    if model.number <> invalid then m.number.text = Left(model.number.ToStr(), 24)
    updateChannelCardLogo()
end sub
