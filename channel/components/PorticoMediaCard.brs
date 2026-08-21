sub init()
    m.surface = m.top.findNode("surface")
    m.fallbackBed = m.top.findNode("fallbackBed")
    m.artwork = m.top.findNode("artwork")
    m.artworkCorners = m.top.findNode("artworkCorners")
    m.fallbackIcon = m.top.findNode("fallbackIcon")
    m.progressTrack = m.top.findNode("progressTrack")
    m.progressValue = m.top.findNode("progressValue")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.hasArtworkUri = false
    m.artwork.observeField("loadStatus", "onArtworkLoadStatus")
end sub

sub onArtworkLoadStatus()
    updateArtworkState()
end sub

sub updateArtworkState()
    loadFailed = m.artwork.loadStatus = "failed"
    m.fallbackBed.visible = true
    m.fallbackIcon.visible = not m.hasArtworkUri or loadFailed
    m.artwork.visible = m.hasArtworkUri and not loadFailed
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    semantic = model.title.ToStr()
    if model.meta <> invalid and model.meta.ToStr() <> "" then semantic = semantic + ", " + model.meta.ToStr()
    m.top.accessibilityLabel = semantic
    if m.top.focused then m.top.setFocus(true)
    landscape = m.top.shape = "landscape"

    outerWidth = 214
    cardHeight = 395
    artWidth = 202
    artHeight = 321
    if landscape
        outerWidth = 320
        cardHeight = 248
        artWidth = 308
        artHeight = 180
    end if

    m.top.focusable = true
    m.surface.width = outerWidth
    m.surface.height = cardHeight
    m.surface.loadWidth = outerWidth
    m.surface.loadHeight = cardHeight
    if m.top.focused
        m.surface.uri = "pkg:/images/ui/poster-card-focus.png"
        if landscape then m.surface.uri = "pkg:/images/ui/landscape-card-focus.png"
    else
        m.surface.uri = ""
    end if

    artworkUri = invalid
    if landscape
        artworkUri = model.artwork
    else
        artworkUri = model.poster
    end if
    m.artwork.width = artWidth
    m.artwork.height = artHeight
    m.artwork.loadWidth = artWidth
    m.artwork.loadHeight = artHeight
    m.artwork.loadDisplayMode = "scaleToZoom"
    m.hasArtworkUri = false
    if artworkUri <> invalid
        m.hasArtworkUri = true
        m.artwork.uri = artworkUri
    else
        m.artwork.uri = ""
    end if
    m.fallbackBed.width = artWidth
    m.fallbackBed.height = artHeight
    m.fallbackIcon.translation = [6 + Int((artWidth - 40) / 2), 6 + Int((artHeight - 40) / 2)]
    m.fallbackIcon.width = 40
    m.fallbackIcon.height = 40
    m.fallbackIcon.loadWidth = 40
    m.fallbackIcon.loadHeight = 40
    m.fallbackIcon.uri = PorticoIconResolverPackageUri("status.artwork-unavailable", "rail")
    m.artworkCorners.width = artWidth
    m.artworkCorners.height = artHeight
    m.artworkCorners.loadWidth = artWidth
    m.artworkCorners.loadHeight = artHeight
    cornerAsset = "poster-artwork-corners"
    if landscape then cornerAsset = "landscape-artwork-corners"
    if m.top.focused then cornerAsset = cornerAsset + "-focus"
    m.artworkCorners.uri = "pkg:/images/ui/" + cornerAsset + ".png"
    updateArtworkState()

    progressY = artHeight - 3
    m.progressTrack.translation = [11, progressY]
    m.progressTrack.width = artWidth - 10
    m.progressTrack.height = 4
    m.progressTrack.visible = model.progress <> invalid
    m.progressValue.translation = [11, progressY]
    progressWidth = 0
    if model.progress <> invalid
        progressWidth = Int((artWidth - 10) * (model.progress / 100.0))
        if progressWidth < 2 and model.progress > 0 then progressWidth = 2
    end if
    m.progressValue.width = progressWidth
    m.progressValue.height = 4
    m.progressValue.visible = model.progress <> invalid

    copyCompensation = 0
    if m.top.compensation <> invalid then copyCompensation = m.top.compensation.cardCopyY
    titleY = artHeight + 17 + copyCompensation
    metaY = artHeight + 45 + copyCompensation
    m.title.text = model.title
    m.title.translation = [6, titleY]
    m.title.width = artWidth
    m.title.height = 26
    m.title.font = PorticoFont("600", 21)
    m.title.color = "#F4F7FA"
    m.title.maxLines = 1
    m.meta.text = model.meta
    m.meta.translation = [6, metaY]
    m.meta.width = artWidth
    m.meta.height = 23
    m.meta.font = PorticoFont("400", 18)
    m.meta.color = "#8F9BA6"
    m.meta.maxLines = 1
end sub
