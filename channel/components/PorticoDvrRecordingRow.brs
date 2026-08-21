sub init()
    m.headerFocus = m.top.FindNode("headerFocus")
    m.headerSurface = m.top.FindNode("headerSurface")
    m.title = m.top.FindNode("title")
    m.meta = m.top.FindNode("meta")
    m.detailsLabel = m.top.FindNode("detailsLabel")
    m.chevron = m.top.FindNode("chevron")
    m.details = m.top.FindNode("details")
    m.durationLabel = m.top.FindNode("durationLabel")
    m.durationValue = m.top.FindNode("durationValue")
    m.sourceLabel = m.top.FindNode("sourceLabel")
    m.sourceValue = m.top.FindNode("sourceValue")
    m.playbackLabel = m.top.FindNode("playbackLabel")
    m.playbackValue = m.top.FindNode("playbackValue")
    m.playAction = m.top.FindNode("playAction")

    m.title.font = PorticoFont("600", 24)
    m.title.color = "#F4F7FA"
    m.meta.font = PorticoFont("400", 18)
    m.meta.color = "#8F9BA6"
    m.detailsLabel.font = PorticoFont("500", 18)
    m.detailsLabel.color = "#378EC3"
    for each node in [m.durationLabel, m.sourceLabel, m.playbackLabel]
        node.font = PorticoFont("500", 16)
        node.color = "#8F9BA6"
    end for
    for each node in [m.durationValue, m.sourceValue, m.playbackValue]
        node.font = PorticoFont("500", 19)
        node.color = "#C7D0D8"
    end for
    m.durationLabel.text = "Duration"
    m.sourceLabel.text = "Source"
    m.playbackLabel.text = "Playback"
    m.playAction.model = {label: "Play recording", iconId: "playback.play", primary: true, width: 280}
end sub

sub render()
    model = m.top.model
    if model = invalid or Type(model) <> "roAssociativeArray" then return
    m.top.focusable = true
    m.headerFocus.visible = m.top.focused
    if m.top.focused then m.headerSurface.color = "#151F29" else m.headerSurface.color = "#0A1017"
    m.title.text = PorticoDvrRowText(model.title, 140)
    m.meta.text = PorticoDvrRowText(model.meta, 180)
    m.detailsLabel.text = "Details"
    m.chevron.uri = PorticoIconResolverPackageUri("navigation.expand", "rail")
    if m.top.expanded then m.chevron.uri = PorticoIconResolverPackageUri("navigation.collapse", "rail")
    m.details.visible = m.top.expanded
    m.durationValue.text = PorticoDvrRowText(model.durationLabel, 40)
    if m.durationValue.text = "" then m.durationValue.text = "Unavailable"
    m.sourceValue.text = PorticoDvrRowText(m.top.sourceName, 100)
    if m.sourceValue.text = "" then m.sourceValue.text = "Portico Server"
    playable = model.playable = true
    m.playAction.visible = m.top.expanded and playable
    m.playAction.focused = m.top.playFocused
    m.playbackLabel.visible = not playable
    m.playbackValue.visible = not playable
    if playable
        m.playbackValue.text = ""
    else
        m.playbackValue.text = "Unavailable"
    end if
end sub

function PorticoDvrRowText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    text = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Trim()
    if Len(text) > maximum then text = Left(text, maximum)
    return text
end function
