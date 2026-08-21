sub init()
    m.surface = m.top.findNode("surface")
    m.fallbackBed = m.top.findNode("fallbackBed")
    m.artwork = m.top.findNode("artwork")
    m.progressTrack = m.top.findNode("progressTrack")
    m.progressValue = m.top.findNode("progressValue")
    m.artworkCorners = m.top.findNode("artworkCorners")
    m.fallbackIcon = m.top.findNode("fallbackIcon")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
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
    semantic = model.title.ToStr()
    if model.meta <> invalid and model.meta.ToStr() <> "" then semantic = semantic + ", " + model.meta.ToStr()
    m.top.accessibilityLabel = semantic
    if m.top.focused then m.top.setFocus(true)
    shape = LCase(m.top.shape)
    outerWidth = 214
    outerHeight = 395
    artWidth = 202
    artHeight = 321
    artworkField = "poster"
    assetPrefix = "poster"
    if shape = "landscape"
        outerWidth = 320
        outerHeight = 248
        artWidth = 308
        artHeight = 180
        artworkField = "artwork"
        assetPrefix = "landscape"
    else if shape = "square"
        outerHeight = 288
        artHeight = 202
        artworkField = "poster"
        assetPrefix = "square"
    end if

    m.top.focusable = true
    m.surface.width = outerWidth
    m.surface.height = outerHeight
    m.surface.loadWidth = outerWidth
    m.surface.loadHeight = outerHeight
    if m.top.focused
        if shape = "square"
            m.surface.uri = "pkg:/images/ui/square-card-focus.png"
        else
            m.surface.uri = "pkg:/images/ui/" + assetPrefix + "-card-focus.png"
        end if
    else
        m.surface.uri = ""
    end if

    artworkUri = model[artworkField]
    if artworkUri = invalid and artworkField = "artwork" then artworkUri = model.poster
    m.artwork.width = artWidth
    m.artwork.height = artHeight
    m.artwork.loadWidth = artWidth
    m.artwork.loadHeight = artHeight
    m.fallbackBed.width = artWidth
    m.fallbackBed.height = artHeight
    m.hasArtworkUri = artworkUri <> invalid and artworkUri.ToStr() <> ""
    if m.hasArtworkUri then m.artwork.uri = artworkUri.ToStr() else m.artwork.uri = ""
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
    cornerAsset = assetPrefix + "-artwork-corners"
    if m.top.focused then cornerAsset = cornerAsset + "-focus"
    m.artworkCorners.uri = "pkg:/images/ui/" + cornerAsset + ".png"
    updateArtworkState()

    progressY = artHeight - 3
    m.progressTrack.translation = [11, progressY]
    m.progressTrack.width = artWidth - 10
    m.progressTrack.height = 4
    m.progressValue.translation = [11, progressY]
    progress = invalid
    if model.progress <> invalid then progress = model.progress
    m.progressTrack.visible = progress <> invalid
    m.progressValue.visible = progress <> invalid
    progressWidth = 0
    if progress <> invalid
        progressWidth = Int((artWidth - 10) * (progress / 100.0))
        if progressWidth < 2 and progress > 0 then progressWidth = 2
        if progressWidth > artWidth - 10 then progressWidth = artWidth - 10
    end if
    m.progressValue.width = progressWidth
    m.progressValue.height = 4

    m.title.text = Left(model.title.ToStr(), 100)
    m.title.translation = [6, artHeight + 17]
    m.title.width = artWidth
    m.title.height = 26
    m.title.font = PorticoFont("600", 21)
    m.title.color = "#F4F7FA"
    m.title.maxLines = 1
    m.meta.text = ""
    if model.meta <> invalid then m.meta.text = Left(model.meta.ToStr(), 100)
    m.meta.translation = [6, artHeight + 45]
    m.meta.width = artWidth
    m.meta.height = 23
    m.meta.font = PorticoFont("400", 18)
    m.meta.color = "#8F9BA6"
    m.meta.maxLines = 1
end sub
