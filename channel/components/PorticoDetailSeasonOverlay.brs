sub init()
    m.title = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.rows = []
    for index = 0 to 7
        m.rows.Push(m.top.findNode("row" + index.ToStr()))
    end for
    m.title.font = PorticoFont("700", 38)
    m.title.color = "#F4F7FA"
    m.subtitle.font = PorticoFont("400", 18)
    m.subtitle.color = "#8F9BA6"
    loaded = PorticoProductLanguageLoad()
    m.language = invalid
    if loaded.ok then m.language = loaded.value
    m.seasons = []
    m.focusIndex = 0
    m.windowOffset = 0
    m.sequence = 0
    m.top.focusable = true
    PorticoSeasonOverlayRender()
end sub

sub applyViewState()
    state = m.top.viewState
    m.seasons = []
    selectedId = ""
    if state <> invalid and Type(state) = "roAssociativeArray"
        selectedId = PorticoSeasonOverlayId(state.selectedSeasonId)
        if state.seasons <> invalid and GetInterface(state.seasons, "ifArray") <> invalid
            for each raw in state.seasons
                season = PorticoSeasonOverlaySeason(raw)
                if season <> invalid and m.seasons.Count() < 100
                    season.selected = season.id = selectedId
                    m.seasons.Push(season)
                end if
            end for
        end if
    end if
    m.focusIndex = 0
    for index = 0 to m.seasons.Count() - 1
        if m.seasons[index].id = selectedId then m.focusIndex = index
    end for
    PorticoSeasonOverlayClampWindow()
    PorticoSeasonOverlayRender()
end sub

sub PorticoSeasonOverlayRender()
    m.title.text = PorticoSeasonOverlayCopy("media.seasons-title", "Seasons")
    m.subtitle.text = PorticoSeasonOverlayCopy("media.season-selector-label", "Season")
    for rowIndex = 0 to m.rows.Count() - 1
        seasonIndex = m.windowOffset + rowIndex
        row = m.rows[rowIndex]
        row.visible = seasonIndex < m.seasons.Count()
        if row.visible
            season = m.seasons[seasonIndex]
            row.model = {label: season.title, iconId: "navigation.disclosure", primary: season.selected, width: 716}
            row.focused = seasonIndex = m.focusIndex
        end if
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back"
        PorticoSeasonOverlayEmit("close-detail-seasons", "")
        return true
    else if key = "up"
        if m.focusIndex > 0 then m.focusIndex = m.focusIndex - 1
    else if key = "down"
        if m.focusIndex < m.seasons.Count() - 1 then m.focusIndex = m.focusIndex + 1
    else if key = "OK"
        if m.focusIndex >= 0 and m.focusIndex < m.seasons.Count() then PorticoSeasonOverlayEmit("select-detail-season", m.seasons[m.focusIndex].id)
        return true
    else
        return false
    end if
    PorticoSeasonOverlayClampWindow()
    PorticoSeasonOverlayRender()
    return true
end function

sub PorticoSeasonOverlayClampWindow()
    if m.focusIndex < m.windowOffset then m.windowOffset = m.focusIndex
    if m.focusIndex >= m.windowOffset + 8 then m.windowOffset = m.focusIndex - 7
    maximum = m.seasons.Count() - 8
    if maximum < 0 then maximum = 0
    if m.windowOffset > maximum then m.windowOffset = maximum
    if m.windowOffset < 0 then m.windowOffset = 0
end sub

sub PorticoSeasonOverlayEmit(kind as string, targetId as string)
    m.sequence = m.sequence + 1
    m.top.activation = {sequence: m.sequence, kind: kind, targetId: targetId}
end sub

function PorticoSeasonOverlaySeason(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    id = PorticoSeasonOverlayId(value.id)
    title = PorticoCoreSafeText(value.title, 100)
    if id = "" or title = "" then return invalid
    return {id: id, title: title, selected: value.selected = true}
end function

function PorticoSeasonOverlayId(value as dynamic) as string
    id = PorticoCoreSafeText(value, 128)
    if id = "" then return ""
    for position = 1 to Len(id)
        code = Asc(Mid(id, position, 1))
        if code < 32 or code = 127 then return ""
    end for
    return id
end function

function PorticoSeasonOverlayCopy(messageId as string, fallback as string) as string
    if m.language = invalid then return fallback
    message = PorticoProductLanguageMessage(m.language, messageId, messageId, {})
    if message.ok and message.text <> "" then return message.text
    return fallback
end function
