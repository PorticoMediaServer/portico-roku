sub init()
    m.focusBorder = m.top.FindNode("focusBorder")
    m.surface = m.top.FindNode("surface")
    m.title = m.top.FindNode("title")
    m.meta = m.top.FindNode("meta")
    m.status = m.top.FindNode("status")
    m.actionOne = m.top.FindNode("actionOne")
    m.actionTwo = m.top.FindNode("actionTwo")
    m.title.font = PorticoFont("600", 23)
    m.title.color = "#F4F7FA"
    m.meta.font = PorticoFont("400", 18)
    m.meta.color = "#8F9BA6"
    m.status.font = PorticoFont("500", 17)
    m.status.color = "#C7D0D8"
end sub

sub render()
    model = m.top.model
    if model = invalid or Type(model) <> "roAssociativeArray" then return
    m.focusBorder.visible = m.top.focused
    if m.top.focused then m.surface.color = "#151F29" else m.surface.color = "#0A1017"
    m.title.text = PorticoDvrConsumerText(model.title, 140)
    m.meta.text = PorticoDvrConsumerText(model.meta, 180)
    m.status.text = PorticoDvrConsumerText(model.statusLabel, 48)
    semantic = m.title.text
    if m.meta.text <> "" then semantic = semantic + ", " + m.meta.text
    if m.status.text <> "" then semantic = semantic + ", " + m.status.text
    m.top.accessibilityLabel = semantic
    m.top.focusable = true
    if m.top.focused then m.top.setFocus(true)
    actionOneLabel = PorticoDvrConsumerText(model.actionOneLabel, 32)
    actionTwoLabel = PorticoDvrConsumerText(model.actionTwoLabel, 32)
    m.actionOne.visible = actionOneLabel <> ""
    m.actionTwo.visible = actionTwoLabel <> ""
    actionOneIcon = PorticoDvrConsumerText(model.actionOneIcon, 32)
    actionTwoIcon = PorticoDvrConsumerText(model.actionTwoIcon, 32)
    if actionOneIcon = "" then actionOneIcon = "status.icon-mapping-missing"
    if actionTwoIcon = "" then actionTwoIcon = "status.icon-mapping-missing"
    m.actionOne.model = {label: actionOneLabel, iconId: actionOneIcon, primary: false, width: 176}
    m.actionTwo.model = {label: actionTwoLabel, iconId: actionTwoIcon, primary: false, width: 176}
    m.actionOne.focused = m.top.actionOneFocused
    m.actionTwo.focused = m.top.actionTwoFocused
    if not m.actionTwo.visible then m.actionOne.translation = [1514,22] else m.actionOne.translation = [1324,22]
end sub

function PorticoDvrConsumerText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    text = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Trim()
    if Len(text) > maximum then text = Left(text, maximum)
    return text
end function
