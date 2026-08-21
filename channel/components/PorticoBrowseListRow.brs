sub init()
    m.surface = m.top.findNode("surface")
    m.fallbackBed = m.top.findNode("fallbackBed")
    m.artwork = m.top.findNode("artwork")
    m.fallbackIcon = m.top.findNode("fallbackIcon")
    m.artworkCorners = m.top.findNode("artworkCorners")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.summary = [m.top.findNode("summary0"), m.top.findNode("summary1")]
    m.status = m.top.findNode("status")
    m.title.font = PorticoFont("600", 25)
    m.title.color = "#F4F7FA"
    m.meta.font = PorticoFont("500", 18)
    m.meta.color = "#8F9BA6"
    for each line in m.summary
        line.font = PorticoFont("400", 19)
        line.color = "#C7D0D8"
    end for
    m.status.font = PorticoFont("600", 18)
    m.status.color = "#70BCE8"
    m.fallbackIcon.uri = PorticoIconResolverPackageUri("status.artwork-unavailable", "rail")
    m.hasArtworkUri = false
    m.artwork.observeField("loadStatus", "onArtworkLoadStatus")
end sub

sub onArtworkLoadStatus()
    updateArtworkState()
end sub

sub updateArtworkState()
    failed = m.artwork.loadStatus = "failed"
    m.artwork.visible = m.hasArtworkUri and not failed and m.top.rowKind <> "schedule"
    m.fallbackIcon.visible = (not m.hasArtworkUri or failed) and m.top.rowKind <> "schedule"
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    schedule = m.top.rowKind = "schedule"
    m.top.focusable = not schedule
    if m.top.focused and not schedule
        m.surface.uri = "pkg:/images/ui/browse-list-focus.png"
        m.artworkCorners.uri = "pkg:/images/ui/browse-list-artwork-corners-focus.png"
        m.fallbackBed.color = "#151F29"
    else
        m.surface.uri = "pkg:/images/ui/browse-list-idle.png"
        m.artworkCorners.uri = "pkg:/images/ui/browse-list-artwork-corners.png"
        m.fallbackBed.color = "#0A1017"
    end if

    copyX = 265
    copyWidth = 1190
    if schedule
        copyX = 20
        copyWidth = 1370
    end if
    m.fallbackBed.visible = not schedule
    m.artworkCorners.visible = not schedule
    m.title.translation = [copyX, 18]
    m.title.width = copyWidth
    m.meta.translation = [copyX, 55]
    m.meta.width = copyWidth
    for index = 0 to m.summary.count() - 1
        m.summary[index].translation = [copyX, 91 + (index * 27)]
        m.summary[index].width = copyWidth
    end for
    m.title.text = Left(model.title.ToStr(), 120)
    m.meta.text = ""
    if model.meta <> invalid then m.meta.text = Left(model.meta.ToStr(), 160)
    summaryValue = ""
    if model.summary <> invalid then summaryValue = model.summary.ToStr()
    lines = PorticoBreakText(summaryValue, copyWidth, 19, "400", 2)
    for index = 0 to m.summary.count() - 1
        m.summary[index].visible = index < lines.count()
        m.summary[index].text = ""
        if index < lines.count() then m.summary[index].text = lines[index]
    end for
    m.status.visible = schedule and model.status <> invalid
    m.status.text = ""
    if m.status.visible then m.status.text = Left(model.status.ToStr(), 24)
    if model.statusTone = "danger" then m.status.color = "#ED5B67" else m.status.color = "#70BCE8"

    artworkUri = model.artwork
    if artworkUri = invalid then artworkUri = model.backdrop
    m.hasArtworkUri = artworkUri <> invalid and artworkUri.ToStr() <> ""
    if m.hasArtworkUri then m.artwork.uri = artworkUri.ToStr() else m.artwork.uri = ""
    updateArtworkState()
end sub
