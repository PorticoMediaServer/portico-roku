sub init()
    m.surface = m.top.findNode("surface")
    m.fallbackBed = m.top.findNode("fallbackBed")
    m.artwork = m.top.findNode("artwork")
    m.artworkCorners = m.top.findNode("artworkCorners")
    m.fallbackIcon = m.top.findNode("fallbackIcon")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.summary = [m.top.findNode("summary0"), m.top.findNode("summary1")]
    m.title.font = PorticoFont("600", 24)
    m.title.color = "#F4F7FA"
    m.meta.font = PorticoFont("500", 18)
    m.meta.color = "#378EC3"
    for each line in m.summary
        line.font = PorticoFont("400", 19)
        line.color = "#8F9BA6"
    end for
    m.fallbackIcon.uri = PorticoIconResolverPackageUri("status.artwork-unavailable", "rail")
    m.hasArtworkUri = false
    m.artwork.observeField("loadStatus", "onArtworkLoadStatus")
end sub

sub onArtworkLoadStatus()
    updateArtworkState()
end sub

sub updateArtworkState()
    failed = m.artwork.loadStatus = "failed"
    m.artwork.visible = m.hasArtworkUri and not failed
    m.fallbackIcon.visible = not m.hasArtworkUri or failed
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    m.top.focusable = true
    if m.top.focused
        m.surface.uri = "pkg:/images/ui/search-result-focus.png"
        m.artworkCorners.uri = "pkg:/images/ui/search-result-artwork-corners-focus.png"
        m.fallbackBed.color = "#151F29"
    else
        m.surface.uri = "pkg:/images/ui/search-result-idle.png"
        m.artworkCorners.uri = "pkg:/images/ui/search-result-artwork-corners.png"
        m.fallbackBed.color = "#0A1017"
    end if
    m.title.text = Left(model.title.ToStr(), 100)
    m.meta.text = ""
    if model.meta <> invalid then m.meta.text = Left(model.meta.ToStr(), 120)
    summaryValue = ""
    if model.summary <> invalid then summaryValue = model.summary.ToStr()
    lines = PorticoBreakText(summaryValue, 690, 19, "400", 2)
    for index = 0 to m.summary.count() - 1
        m.summary[index].visible = index < lines.count()
        m.summary[index].text = ""
        if index < lines.count() then m.summary[index].text = lines[index]
    end for
    m.hasArtworkUri = model.poster <> invalid and model.poster.ToStr() <> ""
    if m.hasArtworkUri then m.artwork.uri = model.poster.ToStr() else m.artwork.uri = ""
    updateArtworkState()
end sub
