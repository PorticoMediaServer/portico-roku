sub init()
    m.screenTitle = m.top.findNode("screenTitle")
    m.serverLabel = m.top.findNode("serverLabel")
    m.availabilityLabel = m.top.findNode("availabilityLabel")
    m.sourceControls = m.top.findNode("sourceControls")
    m.sourceLabel = m.top.findNode("sourceLabel")
    m.sourceButtons = [m.top.findNode("source0"), m.top.findNode("source1"), m.top.findNode("source2"), m.top.findNode("source3")]
    m.sourceMore = m.top.findNode("sourceMore")
    m.tabsGroup = m.top.findNode("tabs")
    m.tabs = [m.top.findNode("tab0"), m.top.findNode("tab1"), m.top.findNode("tab2"), m.top.findNode("tab3")]
    m.pageLabel = m.top.findNode("pageLabel")
    m.previousPage = m.top.findNode("previousPage")
    m.nextPage = m.top.findNode("nextPage")
    m.guideControls = m.top.findNode("guideControls")
    m.previousDay = m.top.findNode("previousDay")
    m.nextDay = m.top.findNode("nextDay")
    m.previousTime = m.top.findNode("previousTime")
    m.nextTime = m.top.findNode("nextTime")
    m.guideFilter = m.top.findNode("guideFilter")
    m.guideGroup = m.top.findNode("guideGroup")
    m.guideSearch = m.top.findNode("guideSearch")
    m.guideSurface = m.top.findNode("guideSurface")
    m.heroTitle = m.top.findNode("heroTitle")
    m.heroMeta = m.top.findNode("heroMeta")
    m.liveLabel = m.top.findNode("liveLabel")
    m.watchLive = m.top.findNode("watchLive")
    m.recordProgram = m.top.findNode("recordProgram")
    m.recordSeries = m.top.findNode("recordSeries")
    m.recordStatus = m.top.findNode("recordStatus")
    m.guideCanvas = m.top.findNode("guideCanvas")
    m.nowMarker = m.top.findNode("nowMarker")
    m.channelGroups = []
    m.channelLogos = []
    m.channelMarks = []
    m.channelNames = []
    m.channelNumbers = []
    m.programs = []
    m.channelLogoUris = []
    for index = 0 to 4
        m.channelGroups.push(m.top.findNode("channel" + index.ToStr()))
        m.channelLogos.push(m.top.findNode("logo" + index.ToStr()))
        m.channelLogoUris.push("")
        m.channelMarks.push(m.top.findNode("mark" + index.ToStr()))
        m.channelNames.push(m.top.findNode("channelName" + index.ToStr()))
        m.channelNumbers.push(m.top.findNode("channelNumber" + index.ToStr()))
        m.channelLogos[index].observeField("loadStatus", "channelLogoStatusChanged")
    end for
    for index = 0 to 29
        m.programs.push(m.top.findNode("program" + index.ToStr()))
    end for
    m.channelGrid = m.top.findNode("channelGrid")
    m.channelTiles = []
    for index = 0 to 8
        m.channelTiles.push(m.top.findNode("channelTile" + index.ToStr()))
    end for
    m.dvrSurface = m.top.findNode("dvrSurface")
    m.dvrTitle = m.top.findNode("dvrTitle")
    m.dvrMeta = m.top.findNode("dvrMeta")
    m.dvrSections = [m.top.findNode("dvrSection0"), m.top.findNode("dvrSection1"), m.top.findNode("dvrSection2"), m.top.findNode("dvrSection3")]
    m.recordingsCanvas = m.top.findNode("recordingsCanvas")
    m.recordingRows = []
    for index = 0 to 3
        m.recordingRows.push(m.top.findNode("recording" + index.ToStr()))
    end for
    m.consumerRows = []
    for index = 0 to 3
        m.consumerRows.push(m.top.findNode("consumer" + index.ToStr()))
    end for
    m.loadingSurface = m.top.findNode("loadingSurface")
    m.stateSurface = m.top.findNode("stateSurface")
    m.stateTitle = m.top.findNode("stateTitle")
    m.stateMessages = [m.top.findNode("stateMessage0"), m.top.findNode("stateMessage1"), m.top.findNode("stateMessage2")]
    m.retryAction = m.top.findNode("retryAction")

    m.screenTitle.font = PorticoFont("700", 48)
    m.screenTitle.color = "#F4F7FA"
    m.serverLabel.font = PorticoFont("500", 18)
    m.serverLabel.color = "#8F9BA6"
    m.availabilityLabel.font = PorticoFont("600", 18)
    m.availabilityLabel.color = "#E3B341"
    m.pageLabel.font = PorticoFont("500", 18)
    m.pageLabel.color = "#8F9BA6"
    m.sourceLabel.font = PorticoFont("600", 18)
    m.sourceLabel.color = "#8F9BA6"
    m.sourceLabel.text = "SOURCE"
    m.liveLabel.font = PorticoFont("600", 16)
    m.liveLabel.color = "#E3B341"
    m.heroTitle.font = PorticoFont("700", 38)
    m.heroTitle.color = "#F4F7FA"
    m.heroMeta.font = PorticoFont("500", 20)
    m.heroMeta.color = "#C7D0D8"
    m.recordStatus.font = PorticoFont("500", 18)
    m.recordStatus.color = "#70BCE8"
    m.guideLabels = [m.top.findNode("todayLabel"), m.top.findNode("nowLabel"), m.top.findNode("hourOneLabel"), m.top.findNode("hourTwoLabel")]
    for each node in m.guideLabels
        node.font = PorticoFont("500", 18)
        node.color = "#8F9BA6"
    end for
    for index = 0 to m.channelNames.count() - 1
        m.channelNames[index].font = PorticoFont("600", 17)
        m.channelNames[index].color = "#F4F7FA"
        m.channelNumbers[index].font = PorticoFont("500", 15)
        m.channelNumbers[index].color = "#8F9BA6"
        m.channelMarks[index].font = PorticoFont("700", 17)
        m.channelMarks[index].color = "#F4F7FA"
    end for
    m.dvrTitle.font = PorticoFont("600", 24)
    m.dvrTitle.color = "#F4F7FA"
    m.dvrMeta.font = PorticoFont("500", 18)
    m.dvrMeta.color = "#C7D0D8"
    m.top.findNode("dvrIcon").uri = PorticoIconResolverPackageUri("playback.record", "default")
    m.stateTitle.font = PorticoFont("600", 30)
    m.stateTitle.color = "#F4F7FA"
    for each node in m.stateMessages
        node.font = PorticoFont("400", 20)
        node.color = "#8F9BA6"
    end for
    m.top.findNode("stateIconBed").uri = "pkg:/images/ui/state-icon-bed.png"
    m.top.findNode("stateIcon").uri = PorticoIconResolverPackageUri("status.warning", "rail")

    m.top.focusable = true
    m.focusTargets = []
    m.focusIndex = -1
    m.focusKey = ""
    m.guideScroll = 0
    m.pendingDestructiveKey = ""
    m.recordingScroll = 0
    m.activationSequence = 0
    m.pageSignature = ""
    m.expandedRecordingId = ""
    m.sourceOffset = 0
    m.dvrSection = "recordings"
    m.currentState = invalid
    m.guideSearchDialog = invalid
    m.screenAuthority = PorticoScreenAuthorityCreate("channels")
end sub

sub channelLogoStatusChanged()
    for index = 0 to m.channelLogos.count() - 1
        hasUri = m.channelLogoUris[index] <> ""
        failed = m.channelLogos[index].loadStatus = "failed"
        m.channelLogos[index].visible = hasUri and not failed
        m.channelMarks[index].visible = not hasUri or failed
    end for
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid then return
    PorticoScreenAuthorityFence(m.screenAuthority, PorticoChannelsInteger(state.viewerGeneration, 0))
    m.currentState = state
    previousKey = m.focusKey
    selectedTab = LCase(PorticoChannelsSafeText(state.selectedTab, 20))
    pageIndex = PorticoChannelsInteger(state.pageIndex, 0)
    nextPageSignature = selectedTab + ":" + pageIndex.ToStr() + ":" + PorticoChannelsSafeText(state.selectedSourceId, 128) + ":" + m.dvrSection
    if m.pageSignature <> "" and nextPageSignature <> m.pageSignature
        if selectedTab = "dvr" then m.recordingScroll = 0 else m.guideScroll = 0
        m.expandedRecordingId = ""
        m.pendingDestructiveKey = ""
    end if
    m.pageSignature = nextPageSignature
    resetChannelsScreen()
    m.screenTitle.text = "Channels"
    server = PorticoChannelsSafeText(state.serverName, 100)
    source = PorticoChannelsSafeText(state.sourceName, 100)
    if source <> ""
        if server <> "" then server = server + "  ·  " + source else server = source
    end if
    m.serverLabel.text = server
    renderChannelsAvailability(state.serverStatus)
    buildSourceControls(state)
    buildChannelTabs(state.tabs)
    buildGuideControls(state)
    buildChannelPaging(state)
    status = LCase(PorticoChannelsSafeText(state.status, 24))
    if status = "loading"
        m.loadingSurface.visible = true
    else if status = "ready" or status = "refreshing" or status = "stale" or status = "working"
        if state.libraryChannels = true
            renderLibraryChannels(state)
        else if selectedTab = "channels"
            renderChannelGrid(state)
        else if selectedTab = "dvr"
            renderDvr(state)
        else
            renderGuide(state)
        end if
    else if status = "choose-source"
        renderMessageState("Choose a source", "Select the Live TV source you want to watch.", false)
    else if status = "empty"
        renderEmptyState(state)
    else if status = "error" or status = "offline" or status = "unavailable"
        renderProductState(state, true)
    else
        renderProductState(state, false)
    end if
    restoreChannelsFocus(previousKey)
    updateChannelsFocus()
end sub

sub renderChannelsAvailability(value as dynamic)
    status = LCase(PorticoChannelsSafeText(value, 32))
    m.availabilityLabel.text = ""
    m.availabilityLabel.visible = false
    if status = "offline"
        m.availabilityLabel.text = "OFFLINE"
        m.availabilityLabel.visible = true
    else if status = "connecting"
        m.availabilityLabel.text = "CONNECTING"
        m.availabilityLabel.visible = true
    else if status = "blocked" or status = "identity-mismatch" or status = "incompatible" or status = "permission-removed"
        m.availabilityLabel.text = "UNAVAILABLE"
        m.availabilityLabel.visible = true
    end if
end sub

sub resetChannelsScreen()
    m.focusTargets = []
    m.sourceControls.visible = false
    m.sourceMore.visible = false
    for each node in m.sourceButtons
        node.visible = false
        node.focused = false
    end for
    m.tabsGroup.translation = [0,102]
    m.guideControls.visible = false
    for each node in [m.previousDay, m.nextDay, m.previousTime, m.nextTime, m.guideFilter, m.guideGroup, m.guideSearch]
        node.visible = false
        node.focused = false
    end for
    m.guideSurface.translation = [0,0]
    m.channelGrid.translation = [0,190]
    m.dvrSurface.translation = [0,190]
    m.loadingSurface.translation = [0,220]
    m.stateSurface.translation = [0,250]
    m.guideSurface.visible = false
    m.channelGrid.visible = false
    m.dvrSurface.visible = false
    m.loadingSurface.visible = false
    m.stateSurface.visible = false
    m.retryAction.visible = false
    m.watchLive.visible = false
    m.recordProgram.visible = false
    m.recordSeries.visible = false
    m.recordStatus.visible = false
    m.pageLabel.visible = false
    m.previousPage.visible = false
    m.previousPage.focused = false
    m.nextPage.visible = false
    m.nextPage.focused = false
    for each node in m.tabs
        node.visible = false
        node.focused = false
    end for
    for each node in m.channelGroups
        node.visible = false
    end for
    for each node in m.programs
        node.visible = false
        node.focused = false
    end for
    for each node in m.channelTiles
        node.visible = false
        node.focused = false
    end for
    for each node in m.recordingRows
        node.visible = false
        node.focused = false
    end for
    for each node in m.consumerRows
        node.visible = false
        node.focused = false
        node.actionOneFocused = false
        node.actionTwoFocused = false
    end for
    for each node in m.dvrSections
        node.visible = false
        node.focused = false
    end for
end sub

sub buildSourceControls(state as object)
    sources = state.sources
    if sources = invalid or GetInterface(sources, "ifArray") = invalid or sources.Count() < 2 then return
    m.sourceControls.visible = true
    m.tabsGroup.translation = [0,146]
    PorticoChannelsShiftSurfaces(50)
    selectedId = PorticoChannelsSafeText(state.selectedSourceId, 128)
    if m.sourceOffset >= sources.Count() then m.sourceOffset = 0
    if selectedId <> ""
        for index = 0 to sources.Count() - 1
            if PorticoChannelsSafeText(sources[index].id, 128) = selectedId and (index < m.sourceOffset or index >= m.sourceOffset + 4) then m.sourceOffset = Int(index / 4) * 4
        end for
    end if
    visibleCount = 0
    for index = 0 to m.sourceButtons.Count() - 1
        sourceIndex = m.sourceOffset + index
        if sourceIndex < sources.Count()
            source = sources[sourceIndex]
            id = PorticoChannelsSafeText(source.id, 128)
            label = PorticoChannelsSafeText(source.name, 72)
            if id <> "" and label <> ""
                node = m.sourceButtons[index]
                node.model = {label: label, iconId: "media.live-tv", primary: id = selectedId, width: 248}
                node.visible = true
                m.focusTargets.Push({key: "source:" + id, kind: "select-source", id: id, x: 122 + (index * 260), y: 76, width: 248, height: 64, node: node, content: "", selected: id = selectedId})
                visibleCount = visibleCount + 1
            end if
        end if
    end for
    if sources.Count() > 4
        m.sourceMore.model = {label: "More", iconId: "navigation.disclosure", primary: false, width: 196}
        m.sourceMore.visible = true
        m.focusTargets.Push({key: "source:more", kind: "more-sources", id: "more", x: 1162, y: 76, width: 196, height: 64, node: m.sourceMore, content: ""})
    end if
end sub

sub buildGuideControls(state as object)
    selectedTab = LCase(PorticoChannelsSafeText(state.selectedTab, 40))
    if selectedTab = "dvr" or selectedTab = "" then return
    m.guideControls.visible = true
    if m.sourceControls.visible then m.guideControls.translation = [0,224] else m.guideControls.translation = [0,180]
    PorticoChannelsShiftSurfaces(72)
    dayOffset = PorticoChannelsInteger(state.dayOffset, 0)
    if dayOffset > 0
        m.previousDay.model = {label: "Previous day", iconId: "navigation.back", primary: false, width: 176}
        m.previousDay.visible = true
        m.focusTargets.Push({key: "guide:previous-day", kind: "set-guide-day", id: (dayOffset - 1).ToStr(), x: 0, y: m.guideControls.translation[1], width: 176, height: 64, node: m.previousDay, content: ""})
    end if
    if dayOffset < 6
        m.nextDay.model = {label: "Next day", iconId: "navigation.disclosure", primary: false, width: 176}
        m.nextDay.visible = true
        m.focusTargets.Push({key: "guide:next-day", kind: "set-guide-day", id: (dayOffset + 1).ToStr(), x: 184, y: m.guideControls.translation[1], width: 176, height: 64, node: m.nextDay, content: ""})
    end if
    if selectedTab = "library-channels" then return
    windowOffset = PorticoChannelsInteger(state.windowOffsetMinutes, 0)
    if windowOffset > 0
        m.previousTime.model = {label: "Earlier", iconId: "navigation.back", primary: false, width: 176}
        m.previousTime.visible = true
        m.focusTargets.Push({key: "guide:earlier", kind: "shift-guide-window", id: "earlier", delta: -120, x: 368, y: m.guideControls.translation[1], width: 176, height: 64, node: m.previousTime, content: ""})
    end if
    m.nextTime.model = {label: "Later", iconId: "navigation.disclosure", primary: false, width: 176}
    m.nextTime.visible = true
    m.focusTargets.Push({key: "guide:later", kind: "shift-guide-window", id: "later", delta: 120, x: 552, y: m.guideControls.translation[1], width: 176, height: 64, node: m.nextTime, content: ""})
    filterLabel = PorticoChannelsSelectedLabel(state.guideFilters, "All")
    m.guideFilter.model = {label: "Filter: " + filterLabel, iconId: "action.customize", primary: false, width: 230}
    m.guideFilter.visible = true
    m.focusTargets.Push({key: "guide:filter", kind: "cycle-guide-filter", id: PorticoChannelsSafeText(state.guideFilter, 24), x: 736, y: m.guideControls.translation[1], width: 230, height: 64, node: m.guideFilter, content: ""})
    selectedGroup = PorticoChannelsSafeText(state.guideGroup, 80)
    groupOptions = state.guideGroups
    showGroup = selectedGroup <> ""
    if groupOptions <> invalid and GetInterface(groupOptions, "ifArray") <> invalid and groupOptions.Count() > 2 then showGroup = true
    searchX = 974
    if showGroup
        groupLabel = PorticoChannelsSelectedLabel(groupOptions, "All groups")
        m.guideGroup.model = {label: groupLabel, iconId: "view.list", primary: false, width: 282}
        m.guideGroup.visible = true
        m.focusTargets.Push({key: "guide:group", kind: "cycle-guide-group", id: selectedGroup, x: 974, y: m.guideControls.translation[1], width: 282, height: 64, node: m.guideGroup, content: ""})
        searchX = 1264
    end if
    query = PorticoChannelsSafeText(state.guideQuery, 120)
    searchLabel = "Search"
    if query <> "" then searchLabel = "Search: " + query
    m.guideSearch.model = {label: searchLabel, iconId: "navigation.search", primary: false, width: 380}
    m.guideSearch.visible = true
    m.guideSearch.translation = [searchX, 0]
    m.focusTargets.Push({key: "guide:search", kind: "open-guide-search", id: "search", x: searchX, y: m.guideControls.translation[1], width: 380, height: 64, node: m.guideSearch, content: ""})
end sub

sub PorticoChannelsShiftSurfaces(delta as integer)
    m.guideSurface.translation = [0, m.guideSurface.translation[1] + delta]
    m.channelGrid.translation = [0, m.channelGrid.translation[1] + delta]
    m.dvrSurface.translation = [0, m.dvrSurface.translation[1] + delta]
    m.loadingSurface.translation = [0, m.loadingSurface.translation[1] + delta]
    m.stateSurface.translation = [0, m.stateSurface.translation[1] + delta]
end sub

function PorticoChannelsSelectedLabel(options as dynamic, fallback as string) as string
    if options <> invalid and GetInterface(options, "ifArray") <> invalid
        for each option in options
            if option <> invalid and Type(option) = "roAssociativeArray" and option.selected = true
                label = PorticoChannelsSafeText(option.label, 80)
                if label <> "" then return label
            end if
        end for
    end if
    return fallback
end function

sub buildChannelPaging(state as object)
    total = PorticoChannelsInteger(state.totalItems, 0)
    pageSize = PorticoChannelsInteger(state.pageSize, 0)
    pageIndex = PorticoChannelsInteger(state.pageIndex, 0)
    hasMore = state.hasMore = true
    selectedTab = LCase(PorticoChannelsSafeText(state.selectedTab, 40))
    if selectedTab = "dvr"
        pageSize = 4
        collection = state.recordings
        if m.dvrSection = "rules" then collection = state.rules
        if m.dvrSection = "schedule" then collection = state.schedule
        if m.dvrSection = "conflicts" then collection = state.conflicts
        if collection <> invalid and GetInterface(collection, "ifArray") <> invalid then total = collection.count()
        counts = state.dvrCounts
        if counts <> invalid and Type(counts) = "roAssociativeArray" then total = PorticoChannelsInteger(counts[m.dvrSection], total)
        hasBySection = state.dvrHasMore
        if hasBySection <> invalid and Type(hasBySection) = "roAssociativeArray" then hasMore = hasBySection[m.dvrSection] = true else hasMore = false
    end if
    if (total <= pageSize and not hasMore) or pageSize < 1 then return
    startItem = (pageIndex * pageSize) + 1
    endItem = startItem + pageSize - 1
    if endItem > total then endItem = total
    m.pageLabel.text = startItem.ToStr() + "–" + endItem.ToStr() + " of " + total.ToStr()
    pagingY = m.tabsGroup.translation[1] + 2
    m.pageLabel.translation = [1030,pagingY + 15]
    m.previousPage.translation = [1300,pagingY]
    m.nextPage.translation = [1484,pagingY]
    m.pageLabel.visible = true
    if pageIndex > 0
        m.previousPage.model = {label: "Previous", iconId: "navigation.back", primary: false, width: 170}
        m.previousPage.visible = true
        m.focusTargets.push({key: "page:previous", kind: "page-channels", id: "previous", delta: -1, x: 1300, y: pagingY, width: 170, height: 64, node: m.previousPage, content: ""})
    end if
    if endItem < total or hasMore
        nextKind = "page-channels"
        if endItem >= total and hasMore
            if selectedTab = "guide" then nextKind = "load-more-guide"
            if selectedTab = "channels" then nextKind = "load-more-channels"
            if selectedTab = "dvr" then nextKind = "load-more-dvr"
            if selectedTab = "dvr"
                nextKind = "load-more-dvr-" + m.dvrSection
                hasBySection = state.dvrHasMore
                if hasBySection <> invalid and Type(hasBySection) = "roAssociativeArray" then hasMore = hasBySection[m.dvrSection] = true
            end if
            if selectedTab = "library-channels" then nextKind = "load-more-library-channels"
        end if
        m.nextPage.model = {label: "Next", iconId: "navigation.disclosure", primary: false, width: 170}
        m.nextPage.visible = true
        m.focusTargets.push({key: "page:next", kind: nextKind, id: "next", delta: 1, x: 1484, y: pagingY, width: 170, height: 64, node: m.nextPage, content: ""})
    end if
end sub

sub buildChannelTabs(source as dynamic)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    tabX = 0
    for index = 0 to source.count() - 1
        if index >= m.tabs.count() then exit for
        raw = source[index]
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoChannelsSafeId(raw.id)
            label = PorticoChannelsSafeText(raw.label, 40)
            if id <> "" and label <> ""
                node = m.tabs[index]
                node.model = {id: id, label: label, selected: raw.selected = true}
                tabWidth = 180
                if id = "library-channels" then tabWidth = 270
                node.translation = [tabX, 0]
                node.visible = true
                m.focusTargets.push({key: "tab:" + id, kind: "select-channel-tab", id: id, x: tabX, y: m.tabsGroup.translation[1], width: tabWidth - 12, height: 68, node: node, selected: raw.selected = true, content: ""})
                tabX = tabX + tabWidth
            end if
        end if
    end for
end sub

sub renderGuide(state as object)
    channels = state.channels
    selected = state.selectedProgram
    if channels = invalid or GetInterface(channels, "ifArray") = invalid or channels.count() = 0
        renderMessageState("No channels available", "This source has not provided any visible channels.", true)
        return
    end if
    m.guideSurface.visible = true
    timelineLabels = state.timelineLabels
    if timelineLabels <> invalid and GetInterface(timelineLabels, "ifArray") <> invalid
        m.guideLabels[0].text = "Channels"
        for index = 1 to m.guideLabels.Count() - 1
            sourceIndex = index - 1
            if sourceIndex < timelineLabels.Count() then m.guideLabels[index].text = PorticoChannelsSafeText(timelineLabels[sourceIndex], 24)
        end for
    end if
    nowRatio = PorticoChannelsNumber(state.nowMarkerRatio, -1.0)
    m.nowMarker.visible = nowRatio >= 0.0 and nowRatio <= 1.0
    if m.nowMarker.visible then m.nowMarker.translation = [232 + Int(nowRatio * 1480), 0]
    channelName = ""
    if selected = invalid
        m.liveLabel.text = "GUIDE"
        m.heroTitle.text = "Live TV"
        m.heroMeta.text = "Schedule data is not available yet. Channels remain ready to watch."
    else
        m.liveLabel.text = "●  LIVE NOW"
        if selected.live <> true then m.liveLabel.text = PorticoChannelsSafeText(selected.timeLabel, 30)
        m.heroTitle.text = PorticoChannelsSafeText(selected.title, 140)
        subtitle = PorticoChannelsSafeText(selected.subtitle, 140)
        if subtitle = "" then subtitle = "Live programming"
        channelName = PorticoChannelsSafeText(selected.channelName, 100)
        if channelName <> "" then subtitle = subtitle + "  ·  " + channelName
        m.heroMeta.text = subtitle
        if PorticoChannelsHasAction(selected.channelActions, "live.play") or PorticoChannelsHasAction(selected.channelActions, "play")
            m.watchLive.model = {label: "Watch Live", iconId: "playback.play", primary: true, width: 180}
            m.watchLive.visible = true
            m.focusTargets.push({key: "action:watch-live", kind: "play-live", id: PorticoChannelsSafeId(selected.channelId), title: PorticoChannelsSafeText(selected.title, 140), meta: channelName, x: 32, y: 407 + m.guideSurface.translation[1], width: 180, height: 64, node: m.watchLive, content: ""})
        end if
    end if
    if selected <> invalid
        if selected.recording <> true and PorticoChannelsHasAction(selected.actions, "dvr.record")
            m.recordProgram.model = {label: "Record", iconId: "playback.record", primary: false, width: 166}
            m.recordProgram.visible = true
            x = 224
            if not m.watchLive.visible then x = 32
            m.recordProgram.translation = [x,217]
            m.focusTargets.push({key: "action:record", kind: "record-program", id: PorticoChannelsSafeId(selected.id), x: x, y: 407 + m.guideSurface.translation[1], width: 166, height: 64, node: m.recordProgram, content: ""})
        end if
        if PorticoChannelsHasAction(selected.actions, "dvr.record-series")
            m.recordSeries.model = {label: "Record Series", iconId: "playback.record", primary: false, width: 176}
            m.recordSeries.visible = true
            x = 402
            if not m.watchLive.visible then x = 210
            if not m.recordProgram.visible then x = 224
            if not m.watchLive.visible and not m.recordProgram.visible then x = 32
            m.recordSeries.translation = [x,217]
            m.focusTargets.push({key: "action:record-series", kind: "record-series", id: PorticoChannelsSafeId(selected.id), x: x, y: 407 + m.guideSurface.translation[1], width: 176, height: 64, node: m.recordSeries, content: ""})
        end if
    end if
    mutationMessage = PorticoChannelsMessageText(state.mutationMessage, 160)
    if mutationMessage <> ""
        m.recordStatus.text = mutationMessage
        m.recordStatus.visible = true
        if LCase(PorticoChannelsSafeText(state.mutationTone, 20)) = "danger" then m.recordStatus.color = "#ED5B67" else m.recordStatus.color = "#70BCE8"
    end if

    programNodeIndex = 0
    channelIndex = 0
    for each channel in channels
        if channelIndex >= m.channelGroups.count() then exit for
        rowY = channelIndex * 112
        group = m.channelGroups[channelIndex]
        group.translation = [0, rowY]
        group.visible = true
        logo = ""
        if channel.logo <> invalid then logo = channel.logo.ToStr()
        m.channelLogos[channelIndex].uri = logo
        m.channelLogoUris[channelIndex] = logo
        m.channelLogos[channelIndex].visible = logo <> ""
        m.channelMarks[channelIndex].visible = logo = ""
        m.channelMarks[channelIndex].text = PorticoChannelsSafeText(channel.mark, 3)
        m.channelNames[channelIndex].text = PorticoChannelsSafeText(channel.name, 60)
        m.channelNumbers[channelIndex].text = PorticoChannelsSafeText(channel.number, 16)
        rawPrograms = channel.programs
        hasPrograms = false
        if rawPrograms <> invalid and GetInterface(rawPrograms, "ifArray") <> invalid
            hasPrograms = rawPrograms.Count() > 0
        end if
        if hasPrograms
            for each program in rawPrograms
                if programNodeIndex >= m.programs.count() then exit for
                leftRatio = PorticoChannelsNumber(program.timelineLeftRatio, -1.0)
                widthRatio = PorticoChannelsNumber(program.timelineWidthRatio, 0.0)
                if leftRatio >= 0.0 and leftRatio <= 1.0 and widthRatio > 0.0
                node = m.programs[programNodeIndex]
                timelineWidth = PorticoChannelsGuideTimelineWidth()
                x = PorticoChannelsGuideTimelineX() + Int(leftRatio * timelineWidth)
                cellWidth = Int(widthRatio * timelineWidth) - PorticoChannelsGuideCellGap()
                if cellWidth < 24 then cellWidth = 24
                if cellWidth > timelineWidth then cellWidth = timelineWidth
                node.translation = [x, rowY]
                node.cellWidth = cellWidth
                node.model = program
                node.selected = false
                if selected <> invalid then node.selected = PorticoChannelsSafeId(program.id) = PorticoChannelsSafeId(selected.id)
                node.visible = true
                m.focusTargets.push({key: "program:" + PorticoChannelsSafeId(program.id), kind: "select-program", id: PorticoChannelsSafeId(program.id), x: x, y: 586 + m.guideSurface.translation[1] + rowY, contentY: rowY, width: cellWidth, height: 104, node: node, content: "guide"})
                programNodeIndex = programNodeIndex + 1
                end if
            end for
        else if programNodeIndex < m.programs.count()
            ' Empty EPG rows remain real, focusable guide rows rather than
            ' collapsing the grid or replacing it with a blocking message.
            node = m.programs[programNodeIndex]
            node.translation = [232, rowY]
            node.cellWidth = 620
            node.model = {title: "No schedule data", subtitle: PorticoChannelsSafeText(channel.name, 100), live: false}
            node.selected = false
            node.visible = true
            m.focusTargets.push({key: "channel:" + PorticoChannelsSafeId(channel.id), kind: "play-live", id: PorticoChannelsSafeId(channel.id), title: PorticoChannelsSafeText(channel.name, 100), meta: "No schedule data", x: 232, y: 586 + m.guideSurface.translation[1] + rowY, contentY: rowY, width: 620, height: 104, node: node, content: "guide"})
            programNodeIndex = programNodeIndex + 1
        end if
        channelIndex = channelIndex + 1
    end for
end sub

function PorticoChannelsGuideTimelineX() as integer
    return 232
end function

function PorticoChannelsGuideTimelineWidth() as integer
    return 1480
end function

function PorticoChannelsGuideCellGap() as integer
    return 6
end function

sub renderChannelGrid(state as object)
    channels = state.channels
    if channels = invalid or GetInterface(channels, "ifArray") = invalid or channels.count() = 0
        renderMessageState("No channels available", "This source has not provided any visible channels.", true)
        return
    end if
    m.channelGrid.visible = true
    index = 0
    for each channel in channels
        if index >= m.channelTiles.count() then exit for
        now = PorticoChannelsCurrentProgram(channel.programs)
        programId = ""
        nowTitle = "No guide data"
        if now <> invalid
            programId = PorticoChannelsSafeId(now.id)
            nowTitle = PorticoChannelsSafeText(now.title, 100)
        end if
        column = index mod 2
        row = Int(index / 2)
        x = column * 864
        y = row * 132
        node = m.channelTiles[index]
        node.translation = [x,y]
        node.model = {title: PorticoChannelsSafeText(channel.name, 100), number: PorticoChannelsSafeText(channel.number, 16), mark: PorticoChannelsSafeText(channel.mark, 3), logo: PorticoChannelsSafeText(channel.logo, 300), now: nowTitle}
        node.visible = true
        targetId = programId
        targetKind = "open-guide-program"
        actionable = targetId <> ""
        if targetId = ""
            targetId = PorticoChannelsSafeId(channel.id)
            targetKind = "play-live"
            actionable = PorticoChannelsHasAction(channel.actions, "live.play") or PorticoChannelsHasAction(channel.actions, "play")
        end if
        if actionable then m.focusTargets.push({key: "channel:" + PorticoChannelsSafeId(channel.id), kind: targetKind, id: targetId, title: nowTitle, meta: PorticoChannelsSafeText(channel.name, 100), x: x, y: m.channelGrid.translation[1] + y, width: 848, height: 118, node: node, content: ""})
        index = index + 1
    end for
end sub

sub renderLibraryChannels(state as object)
    channels = state.channels
    if channels = invalid or GetInterface(channels, "ifArray") = invalid or channels.Count() = 0
        renderProductState(state, true)
        return
    end if
    m.channelGrid.visible = true
    index = 0
    for each channel in channels
        if index >= m.channelTiles.Count() then exit for
        now = PorticoChannelsCurrentProgram(channel.programs)
        nowTitle = PorticoChannelsSafeText(channel.description, 120)
        if now <> invalid then nowTitle = PorticoChannelsSafeText(now.title, 120)
        column = index mod 2
        row = Int(index / 2)
        x = column * 864
        y = row * 132
        node = m.channelTiles[index]
        node.translation = [x,y]
        node.model = {title: PorticoChannelsSafeText(channel.name, 100), number: "", mark: PorticoChannelsSafeText(channel.mark, 3), logo: PorticoChannelsSafeText(channel.logo, 300), now: nowTitle}
        node.visible = true
        channelId = PorticoChannelsSafeId(channel.id)
        if channelId <> "" and (PorticoChannelsHasAction(channel.actions, "play") or PorticoChannelsHasAction(channel.actions, "live.play"))
            m.focusTargets.Push({key: "library-channel:" + channelId, kind: "play-library-channel", id: channelId, title: nowTitle, meta: PorticoChannelsSafeText(channel.name, 100), x: x, y: m.channelGrid.translation[1] + y, width: 848, height: 118, node: node, content: ""})
        end if
        index = index + 1
    end for
end sub

sub renderDvr(state as object)
    m.dvrSurface.visible = true
    m.dvrTitle.text = "DVR"
    m.dvrMeta.text = PorticoChannelsSafeText(state.dvrStatusSummary, 180)
    mutationText = PorticoChannelsMessageText(state.mutationMessage, 180)
    if mutationText <> "" then m.dvrMeta.text = mutationText
    sections = [{id: "recordings", label: "Recordings"}, {id: "schedule", label: "Schedule"}, {id: "rules", label: "Rules"}, {id: "conflicts", label: "Conflicts"}]
    for index = 0 to sections.Count() - 1
        section = sections[index]
        node = m.dvrSections[index]
        node.model = {id: section.id, label: section.label, selected: section.id = m.dvrSection}
        node.visible = true
        m.focusTargets.Push({key: "dvr-section:" + section.id, kind: "select-dvr-section", id: section.id, x: index * 210, y: m.dvrSurface.translation[1] + 108, width: 198, height: 68, node: node, selected: section.id = m.dvrSection, content: ""})
    end for
    if m.dvrSection = "schedule"
        renderDvrSchedule(state.schedule)
    else if m.dvrSection = "rules"
        renderDvrRules(state.rules)
    else if m.dvrSection = "conflicts"
        renderDvrConflicts(state.conflicts)
    else
        renderDvrRecordings(state.recordings, state.sourceName)
    end if
end sub

sub renderDvrRecordings(recordings as dynamic, sourceName as dynamic)
    models = []
    if recordings <> invalid and GetInterface(recordings, "ifArray") <> invalid
        for each recording in recordings
            actions = []
            if recording.playable = true then actions.Push({kind: "play-dvr", label: "Play", iconId: "playback.play"})
            if recording.cancellable = true then actions.Push({kind: "cancel-dvr-recording", label: "Cancel", iconId: "action.cancel"})
            if recording.deletable = true then actions.Push({kind: "delete-dvr-recording", label: "Delete", iconId: "action.delete"})
            models.Push({id: recording.id, title: recording.title, meta: recording.meta, statusLabel: PorticoChannelsStatusLabel(recording.status), actions: actions})
        end for
    end if
    renderDvrConsumerRows(models, "dvr-recording")
end sub

sub renderDvrSchedule(schedule as dynamic)
    models = []
    if schedule <> invalid and GetInterface(schedule, "ifArray") <> invalid
        for each recording in schedule
            actions = []
            if recording.cancellable = true then actions.Push({kind: "cancel-dvr-recording", label: "Cancel", iconId: "action.cancel"})
            models.Push({id: recording.id, title: recording.title, meta: recording.meta, statusLabel: PorticoChannelsStatusLabel(recording.status), actions: actions})
        end for
    end if
    renderDvrConsumerRows(models, "dvr-schedule")
end sub

sub renderDvrRules(rules as dynamic)
    models = []
    if rules <> invalid and GetInterface(rules, "ifArray") <> invalid
        for each rule in rules
            actions = []
            if rule.canToggle = true
                label = "Enable"
                if rule.enabled = true then label = "Pause"
                actions.Push({kind: "toggle-dvr-rule", label: label, iconId: "navigation.settings"})
            end if
            if rule.canDelete = true then actions.Push({kind: "delete-dvr-rule", label: "Delete", iconId: "action.delete"})
            meta = "Program"
            if rule.matchType = "series" then meta = "Series"
            if rule.retentionDays > 0 then meta = meta + "  ·  Keep " + rule.retentionDays.ToStr() + " days"
            statusLabel = "Paused"
            if rule.enabled = true then statusLabel = "Enabled"
            models.Push({id: rule.id, title: rule.title, meta: meta, statusLabel: statusLabel, actions: actions})
        end for
    end if
    renderDvrConsumerRows(models, "dvr-rule")
end sub

sub renderDvrConflicts(conflicts as dynamic)
    models = []
    if conflicts <> invalid and GetInterface(conflicts, "ifArray") <> invalid
        for each conflict in conflicts
            models.Push({id: conflict.id, title: conflict.title, meta: conflict.body, statusLabel: "Conflict", actions: []})
        end for
    end if
    renderDvrConsumerRows(models, "dvr-conflict")
end sub

sub renderDvrConsumerRows(models as object, keyPrefix as string)
    if models.Count() = 0
        m.dvrMeta.text = PorticoChannelsDvrEmptyLabel(m.dvrSection)
        return
    end if
    for index = 0 to models.Count() - 1
        if index >= m.consumerRows.Count() then exit for
        model = models[index]
        node = m.consumerRows[index]
        actionOneLabel = ""
        actionTwoLabel = ""
        if model.actions.Count() > 0 then actionOneLabel = model.actions[0].label
        if model.actions.Count() > 1 then actionTwoLabel = model.actions[1].label
        actionOneIcon = ""
        actionTwoIcon = ""
        if model.actions.Count() > 0 then actionOneIcon = model.actions[0].iconId
        if model.actions.Count() > 1 then actionTwoIcon = model.actions[1].iconId
        node.model = {title: model.title, meta: model.meta, statusLabel: model.statusLabel, actionOneLabel: actionOneLabel, actionTwoLabel: actionTwoLabel, actionOneIcon: actionOneIcon, actionTwoIcon: actionTwoIcon}
        node.translation = [0,index * 116]
        node.visible = true
        m.focusTargets.Push({key: keyPrefix + ":" + model.id, kind: "dvr-row", id: model.id, x: 0, y: m.dvrSurface.translation[1] + 186 + (index * 116), width: 1280, height: 108, node: node, content: "dvr", contentY: index * 116})
        if model.actions.Count() > 0 then m.focusTargets.Push({key: keyPrefix + ":action1:" + model.id, kind: model.actions[0].kind, id: model.id, title: model.title, meta: model.meta, x: 1324, y: m.dvrSurface.translation[1] + 208 + (index * 116), width: 176, height: 64, node: node, content: "dvr", contentY: index * 116, focusField: "consumer-action-one"})
        if model.actions.Count() > 1 then m.focusTargets.Push({key: keyPrefix + ":action2:" + model.id, kind: model.actions[1].kind, id: model.id, title: model.title, meta: model.meta, x: 1514, y: m.dvrSurface.translation[1] + 208 + (index * 116), width: 176, height: 64, node: node, content: "dvr", contentY: index * 116, focusField: "consumer-action-two"})
    end for
end sub

sub renderEmptyState(state as object)
    if state.message <> invalid
        renderProductState(state, true)
    else if state.libraryChannels = true
        renderMessageState("No Library Channels", "No Library Channels are available to this profile.", true)
    else if PorticoChannelsSafeText(state.sourceName, 100) = ""
        renderMessageState("No Live TV channels", "No Live TV channels are available to this profile.", true)
    else if LCase(PorticoChannelsSafeText(state.selectedTab, 20)) = "dvr"
        renderMessageState("No DVR recordings yet", "Completed recordings from this server will appear here.", true)
    else
        renderMessageState("No guide data", "Programme listings are not available for this source.", true)
    end if
end sub

sub renderProductState(state as object, retry as boolean)
    message = state.message
    title = "Portico couldn't complete this request"
    body = "Please try again."
    if message <> invalid and Type(message) = "roAssociativeArray"
        safeTitle = PorticoChannelsSafeText(message.title, 160)
        safeBody = PorticoChannelsSafeText(message.body, 500)
        if safeTitle <> "" then title = safeTitle
        if safeBody <> "" then body = safeBody
        iconId = PorticoChannelsSafeText(message.iconId, 120)
        if iconId <> "" then m.top.findNode("stateIcon").uri = PorticoIconResolverPackageUri(iconId, "rail")
    end if
    renderMessageState(title, body, retry)
end sub

sub renderMessageState(title as string, message as string, retry as boolean)
    m.guideSurface.visible = false
    m.channelGrid.visible = false
    m.dvrSurface.visible = false
    m.stateSurface.visible = true
    m.stateTitle.text = title
    lines = PorticoBreakText(message, 640, 20, "400", 3)
    for index = 0 to m.stateMessages.count() - 1
        node = m.stateMessages[index]
        node.visible = index < lines.count()
        node.text = ""
        if index < lines.count() then node.text = lines[index]
    end for
    if retry
        m.retryAction.model = {label: "Try again", iconId: "action.retry", primary: true, width: 190}
        m.retryAction.visible = true
        m.focusTargets.push({key: "state:retry", kind: "retry-channels", id: "retry", x: 761, y: 536, width: 190, height: 64, node: m.retryAction, content: ""})
    end if
end sub

sub restoreChannelsFocus(previousKey as string)
    semanticIds = []
    for each target in m.focusTargets
        semanticIds.Push(target.key)
    end for
    PorticoScreenAuthorityTargets(m.screenAuthority, semanticIds)
    previousKey = PorticoScreenAuthorityResolve(m.screenAuthority, previousKey, "")
    m.focusIndex = -1
    if previousKey <> ""
        for index = 0 to m.focusTargets.count() - 1
            if m.focusTargets[index].key = previousKey
                m.focusIndex = index
                exit for
            end if
        end for
    end if
    if m.focusIndex < 0
        for index = 0 to m.focusTargets.count() - 1
            if m.focusTargets[index].kind = "select-channel-tab" and m.focusTargets[index].selected = true
                m.focusIndex = index
                exit for
            end if
        end for
    end if
    if m.focusIndex < 0 and m.focusTargets.count() > 0 then m.focusIndex = 0
end sub

sub updateChannelsFocus()
    semanticIds = []
    for each focusTarget in m.focusTargets
        semanticIds.Push(focusTarget.key)
    end for
    PorticoScreenAuthorityTargets(m.screenAuthority, semanticIds)
    for each row in m.recordingRows
        row.focused = false
        row.playFocused = false
    end for
    for each row in m.consumerRows
        row.focused = false
        row.actionOneFocused = false
        row.actionTwoFocused = false
    end for
    for index = 0 to m.focusTargets.count() - 1
        target = m.focusTargets[index]
        if target.focusField = "play"
            target.node.playFocused = index = m.focusIndex
        else if target.focusField = "consumer-action-one"
            target.node.actionOneFocused = index = m.focusIndex
        else if target.focusField = "consumer-action-two"
            target.node.actionTwoFocused = index = m.focusIndex
        else
            target.node.focused = index = m.focusIndex
        end if
    end for
    m.focusKey = ""
    if m.focusIndex >= 0 and m.focusIndex < m.focusTargets.count()
        target = m.focusTargets[m.focusIndex]
        m.focusKey = target.key
        if m.pendingDestructiveKey <> "" and m.pendingDestructiveKey <> m.focusKey then m.pendingDestructiveKey = ""
        PorticoScreenAuthorityFocused(m.screenAuthority, m.focusKey)
        if target.content = "guide"
            top = target.contentY - m.guideScroll
            if top < 0 then m.guideScroll = m.guideScroll + top
            if top + target.height > 310 then m.guideScroll = m.guideScroll + ((top + target.height) - 310)
            if m.guideScroll < 0 then m.guideScroll = 0
        else if target.content = "dvr"
            top = target.contentY - m.recordingScroll
            if top < 0 then m.recordingScroll = m.recordingScroll + top
            if top + target.height > 540 then m.recordingScroll = m.recordingScroll + ((top + target.height) - 540)
            if m.recordingScroll < 0 then m.recordingScroll = 0
        end if
    end if
    m.guideCanvas.translation = [0, -m.guideScroll]
    m.recordingsCanvas.translation = [0, -m.recordingScroll]
    m.top.focusState = {key: m.focusKey, index: m.focusIndex, guideOffset: m.guideScroll, recordingOffset: m.recordingScroll}
end sub

function moveChannelsFocus(horizontal as integer, vertical as integer) as boolean
    if m.focusIndex < 0 or m.focusIndex >= m.focusTargets.count() then return false
    current = m.focusTargets[m.focusIndex]
    currentY = PorticoChannelsVisibleY(current)
    bestIndex = -1
    bestScore = 2147483647
    for index = 0 to m.focusTargets.count() - 1
        if index <> m.focusIndex
            candidate = m.focusTargets[index]
            deltaX = candidate.x - current.x
            deltaY = PorticoChannelsVisibleY(candidate) - currentY
            acceptable = false
            primary = 0
            secondary = 0
            if horizontal < 0 and deltaX < 0
                acceptable = true
                primary = -deltaX
                secondary = Abs(deltaY)
            else if horizontal > 0 and deltaX > 0
                acceptable = true
                primary = deltaX
                secondary = Abs(deltaY)
            else if vertical < 0 and deltaY < 0
                acceptable = true
                primary = -deltaY
                secondary = Abs(deltaX)
            else if vertical > 0 and deltaY > 0
                acceptable = true
                primary = deltaY
                secondary = Abs(deltaX)
            end if
            if acceptable
                score = (primary * 10) + secondary
                if score < bestScore
                    bestScore = score
                    bestIndex = index
                end if
            end if
        end if
    end for
    if bestIndex >= 0
        direction = "down"
        if horizontal < 0 then direction = "left"
        if horizontal > 0 then direction = "right"
        if vertical < 0 then direction = "up"
        if not PorticoScreenAuthorityAcceptMove(m.screenAuthority, direction, current.key, m.focusTargets[bestIndex].key) then return false
        m.focusIndex = bestIndex
        return true
    end if
    return false
end function

function PorticoChannelsVisibleY(target as object) as integer
    if target.content = "guide" then return target.y - m.guideScroll
    if target.content = "dvr" then return target.y - m.recordingScroll
    return target.y
end function

sub emitChannelsActivation(target as object)
    PorticoScreenAuthorityCommitOK(m.screenAuthority)
    m.activationSequence = m.activationSequence + 1
    activation = {sequence: m.activationSequence, kind: target.kind, targetId: target.id, focusKey: target.key}
    if target.title <> invalid then activation.title = target.title
    if target.meta <> invalid then activation.meta = target.meta
    if target.delta <> invalid then activation.delta = target.delta
    m.top.activation = activation
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        PorticoScreenAuthorityRelease(m.screenAuthority, key)
        return false
    end if
    moved = false
    if key = "left"
        moved = moveChannelsFocus(-1, 0)
        if not moved then return false
    else if key = "right"
        moved = moveChannelsFocus(1, 0)
    else if key = "up"
        moved = moveChannelsFocus(0, -1)
        if not moved then return true
    else if key = "down"
        moved = moveChannelsFocus(0, 1)
    else if key = "OK"
        if m.focusIndex >= 0 and m.focusIndex < m.focusTargets.count()
            target = m.focusTargets[m.focusIndex]
            if not PorticoScreenAuthorityBeginOK(m.screenAuthority, target.key) then return true
            destructive = target.kind = "cancel-dvr-recording" or target.kind = "delete-dvr-recording" or target.kind = "delete-dvr-rule"
            if destructive and m.pendingDestructiveKey <> target.key
                m.pendingDestructiveKey = target.key
                m.dvrMeta.text = "Press OK again to confirm " + LCase(PorticoChannelsSafeText(target.title, 100))
                return true
            end if
            if destructive then m.pendingDestructiveKey = ""
            if target.kind = "toggle-recording-details"
                if m.expandedRecordingId = target.id then m.expandedRecordingId = "" else m.expandedRecordingId = target.id
                applyViewState()
            else if target.kind = "more-sources"
                sources = m.currentState.sources
                if sources <> invalid and GetInterface(sources, "ifArray") <> invalid and sources.Count() > 4
                    m.sourceOffset = m.sourceOffset + 4
                    if m.sourceOffset >= sources.Count() then m.sourceOffset = 0
                    applyViewState()
                end if
            else if target.kind = "select-dvr-section"
                m.dvrSection = target.id
                applyViewState()
            else if target.kind = "cycle-guide-filter"
                emitNextGuideOption("set-guide-filter", m.currentState.guideFilters, m.currentState.guideFilter)
            else if target.kind = "cycle-guide-group"
                emitNextGuideOption("set-guide-group", m.currentState.guideGroups, m.currentState.guideGroup)
            else if target.kind = "open-guide-search"
                openGuideSearch()
            else if target.kind = "dvr-row"
                return true
            else
                emitChannelsActivation(target)
            end if
        end if
        return true
    else if key = "back"
        return false
    else
        return false
    end if
    updateChannelsFocus()
    if moved and m.focusIndex >= 0 and m.focusIndex < m.focusTargets.count()
        target = m.focusTargets[m.focusIndex]
        if target.kind = "select-program" and target.content = "guide" then emitChannelsActivation(target)
    end if
    return true
end function

sub emitNextGuideOption(kind as string, options as dynamic, selectedValue as dynamic)
    if options = invalid or GetInterface(options, "ifArray") = invalid or options.Count() = 0 then return
    selected = PorticoChannelsSafeText(selectedValue, 80)
    nextIndex = 0
    for index = 0 to options.Count() - 1
        if PorticoChannelsSafeText(options[index].id, 80) = selected then nextIndex = index + 1
    end for
    if nextIndex >= options.Count() then nextIndex = 0
    id = PorticoChannelsSafeText(options[nextIndex].id, 80)
    m.activationSequence = m.activationSequence + 1
    m.top.activation = {sequence: m.activationSequence, kind: kind, targetId: id, focusKey: m.focusKey}
end sub

sub openGuideSearch()
    scene = m.top.GetScene()
    if scene = invalid then return
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    if dialog = invalid then return
    dialog.title = "Search guide"
    dialog.text = PorticoChannelsSafeText(m.currentState.guideQuery, 120)
    dialog.buttons = ["Search", "Cancel"]
    dialog.ObserveField("buttonSelected", "guideSearchButtonSelected")
    m.guideSearchDialog = dialog
    PorticoScreenAuthorityOpenModal(m.screenAuthority, "guide:search")
    scene.dialog = dialog
end sub

sub guideSearchButtonSelected()
    dialog = m.guideSearchDialog
    if dialog = invalid then return
    selected = dialog.buttonSelected
    query = PorticoChannelsSafeText(dialog.text, 120)
    scene = m.top.GetScene()
    if scene <> invalid then scene.dialog = invalid
    m.guideSearchDialog = invalid
    restoredId = PorticoScreenAuthorityCloseModal(m.screenAuthority, "guide:search")
    PorticoScreenAuthorityFocused(m.screenAuthority, restoredId)
    if selected = 0
        m.activationSequence = m.activationSequence + 1
        m.top.activation = {sequence: m.activationSequence, kind: "set-guide-query", query: query, focusKey: "guide:search"}
    end if
end sub

function PorticoChannelsCurrentProgram(source as dynamic) as dynamic
    if source = invalid or GetInterface(source, "ifArray") = invalid then return invalid
    fallback = invalid
    for each program in source
        if fallback = invalid then fallback = program
        if program <> invalid and program.live = true then return program
    end for
    return fallback
end function

function PorticoChannelsSafeText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    text = value.ToStr().Trim()
    text = text.Replace(Chr(10), " ").Replace(Chr(13), " ")
    if Len(text) > maximum then text = Left(text, maximum)
    return text
end function

function PorticoChannelsSafeId(value as dynamic) as string
    text = PorticoChannelsSafeText(value, 160)
    if text = "" then return ""
    for index = 1 to Len(text)
        code = Asc(Mid(text, index, 1))
        if code < 32 or code = 127 then return ""
    end for
    return text
end function

function PorticoChannelsInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" or valueType = "float" or valueType = "rofloat" or valueType = "double" or valueType = "rodouble" then return Int(value)
    return fallback
end function

function PorticoChannelsHasAction(actions as dynamic, expected as string) as boolean
    if actions = invalid or GetInterface(actions, "ifArray") = invalid then return false
    for each action in actions
        if action <> invalid and LCase(action.ToStr()) = expected then return true
    end for
    return false
end function

function PorticoChannelsNumber(value as dynamic, fallback as double) as double
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" or valueType = "float" or valueType = "rofloat" or valueType = "double" or valueType = "rodouble" then return value
    return fallback
end function

function PorticoChannelsMessageText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    if Type(value) = "roAssociativeArray"
        text = PorticoChannelsSafeText(value.text, maximum)
        if text = "" then text = PorticoChannelsSafeText(value.title, maximum)
        return text
    end if
    return PorticoChannelsSafeText(value, maximum)
end function

function PorticoChannelsStatusLabel(value as dynamic) as string
    status = LCase(PorticoChannelsSafeText(value, 32))
    if status = "scheduled" then return "Scheduled"
    if status = "running" then return "Recording"
    if status = "complete" then return "Ready"
    if status = "failed" then return "Failed"
    return ""
end function

function PorticoChannelsDvrEmptyLabel(section as string) as string
    if section = "schedule" then return "Nothing is scheduled"
    if section = "rules" then return "No recording rules"
    if section = "conflicts" then return "No DVR issues"
    return "No recordings yet"
end function
