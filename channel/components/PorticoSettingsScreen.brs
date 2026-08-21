sub init()
    m.scrollContent = m.top.findNode("scrollContent")
    m.title = m.top.findNode("title")
    m.accountLabel = m.top.findNode("accountLabel")
    m.groupLabels = [m.top.findNode("accountGroup"), m.top.findNode("playbackGroup"), m.top.findNode("privacyGroup")]
    m.rows = []
    for index = 0 to 14
        m.rows.Push(m.top.findNode("row" + index.ToStr()))
    end for
    m.feedback = m.top.findNode("feedbackOverlay")
    m.security = m.top.findNode("securityOverlay")
    m.choiceModal = m.top.findNode("choiceModal")
    m.modalScrim = m.top.findNode("modalScrim")
    m.modalPanel = m.top.findNode("modalPanel")
    m.modalTitle = m.top.findNode("modalTitle")
    m.modalBody = m.top.findNode("modalBody")
    m.choiceRows = [m.top.findNode("choice0"), m.top.findNode("choice1"), m.top.findNode("choice2"), m.top.findNode("choice3")]
    m.feedback.ObserveField("activation", "feedbackActivationChanged")
    m.security.ObserveField("activation", "securityActivationChanged")
    loadedLanguage = PorticoProductLanguageLoad()
    m.language = invalid
    if loadedLanguage.ok then m.language = loadedLanguage.value
    m.title.font = PorticoFont("700", 48)
    m.title.color = "#F4F7FA"
    m.accountLabel.font = PorticoFont("500", 19)
    m.accountLabel.color = "#8F9BA6"
    for each groupLabel in m.groupLabels
        groupLabel.font = PorticoFont("600", 19)
        groupLabel.color = "#8F9BA6"
    end for
    m.modalTitle.font = PorticoFont("600", 32)
    m.modalTitle.color = "#F4F7FA"
    m.modalBody.font = PorticoFont("400", 18)
    m.modalBody.color = "#C7D0D8"
    m.modalScrim.uri = "pkg:/images/ui/overlay-scrim.png"
    m.modalPanel.uri = "pkg:/images/ui/settings-modal.png"
    m.runtime = {}
    m.model = PorticoSettingsModel(m.runtime, m.language)
    m.visibleRows = []
    m.rowPositions = {}
    m.focusPosition = 0
    m.focusArea = "rows"
    m.scrollOffset = 0
    m.choiceKind = ""
    m.choiceOptions = []
    m.choiceFocus = 0
    m.activationSequence = 0
    m.hasFocus = true
    m.initialFocusApplied = false
    m.screenAuthority = PorticoScreenAuthorityCreate("settings")
    m.top.focusable = true
    PorticoSettingsRebuildLayout()
    PorticoSettingsRender()
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid then return
    runtime = state
    if state.runtime <> invalid and Type(state.runtime) = "roAssociativeArray" then runtime = state.runtime
    if runtime = invalid or Type(runtime) <> "roAssociativeArray" then runtime = {}
    m.runtime = runtime
    PorticoScreenAuthorityFence(m.screenAuthority, PorticoHttpInteger(runtime.viewerGeneration, 0))
    if Type(state.focused) = "Boolean" or Type(state.focused) = "roBoolean" then m.hasFocus = state.focused = true
    m.model = PorticoSettingsModel(m.runtime, m.language)
    PorticoSettingsRebuildLayout()
    PorticoSettingsKeepFocusVisible()
    PorticoSettingsRender()
end sub

sub PorticoSettingsRebuildLayout()
    currentId = ""
    if m.visibleRows.Count() > 0 and m.focusPosition < m.visibleRows.Count() then currentId = m.model.rows[m.visibleRows[m.focusPosition]].id
    m.visibleRows = []
    m.rowPositions = {}
    sectionY = {account: -1, playback: -1, privacy: -1}
    y = 34
    previousSection = ""
    for index = 0 to m.model.rows.Count() - 1
        row = m.model.rows[index]
        if row.visible <> false
            section = row.section
            if section <> previousSection and section <> "account-action"
                if previousSection <> "" then y = y + 34
                sectionY[section] = y - 34
                previousSection = section
            else if section = "account-action" and previousSection <> "account-action"
                y = y + 38
                previousSection = section
            end if
            if row.actionable <> false then m.visibleRows.Push(index)
            m.rowPositions[index.ToStr()] = y
            m.rows[index].translation = [0, y]
            y = y + 102
        end if
    end for
    m.groupLabels[0].text = PorticoSettingsCopy(m.language, "settings.section.account", "Account")
    m.groupLabels[1].text = PorticoSettingsCopy(m.language, "settings.section.playback", "Playback")
    m.groupLabels[2].text = PorticoSettingsCopy(m.language, "preferences.visibility-title", "History and visibility")
    m.groupLabels[0].translation = [0, sectionY.account]
    m.groupLabels[1].translation = [0, sectionY.playback]
    m.groupLabels[2].translation = [0, sectionY.privacy]
    m.contentHeight = y + 30
    if currentId <> ""
        for position = 0 to m.visibleRows.Count() - 1
            if m.model.rows[m.visibleRows[position]].id = currentId then m.focusPosition = position
        end for
    end if
    if m.focusPosition >= m.visibleRows.Count() then m.focusPosition = m.visibleRows.Count() - 1
    if m.focusPosition < 0 then m.focusPosition = 0
    if not m.initialFocusApplied and m.visibleRows.Count() > 0
        for position = 0 to m.visibleRows.Count() - 1
            if m.model.rows[m.visibleRows[position]].id = "profile" then m.focusPosition = position
        end for
        m.initialFocusApplied = true
    end if
    semanticIds = []
    for each rowIndex in m.visibleRows
        semanticIds.Push("settings.row." + m.model.rows[rowIndex].id)
    end for
    PorticoScreenAuthorityTargets(m.screenAuthority, semanticIds)
end sub

sub PorticoSettingsRender()
    m.title.text = PorticoSettingsCopy(m.language, "settings.title", "Settings")
    m.accountLabel.text = m.model.accountLabel
    engagement = m.model.engagement
    for index = 0 to m.rows.Count() - 1
        visible = index < m.model.rows.Count() and m.model.rows[index].visible <> false
        m.rows[index].visible = visible
        if visible
            focused = false
            if m.visibleRows.Count() > 0 then focused = m.hasFocus and m.focusArea = "rows" and index = m.visibleRows[m.focusPosition]
            m.rows[index].viewState = {model: m.model.rows[index], focused: focused}
            if focused then PorticoScreenAuthorityFocused(m.screenAuthority, "settings.row." + m.model.rows[index].id)
        end if
    end for
    topOffset = 166
    m.scrollContent.translation = [0, topOffset - m.scrollOffset]
    PorticoSettingsRenderModal()
    feedbackState = {open: m.choiceKind = "feedback", feedbackCapabilities: m.model.feedbackCapabilities, feedbackStatus: "idle", initialKind: "general", context: {}}
    if engagement <> invalid and Type(engagement) = "roAssociativeArray"
        feedbackState.feedbackStatus = engagement.feedbackStatus
        feedbackState.feedbackReceipt = engagement.feedbackReceipt
    end if
    m.feedback.viewState = feedbackState
    m.security.open = m.choiceKind = "security"
    m.top.modalOpen = m.choiceKind <> ""
    if m.choiceKind = "feedback" then m.feedback.setFocus(true)
    if m.choiceKind = "security" then m.security.setFocus(true)
end sub

sub PorticoSettingsKeepFocusVisible()
    if m.visibleRows.Count() = 0 then return
    rowIndex = m.visibleRows[m.focusPosition]
    topOffset = 166
    top = topOffset + m.rowPositions[rowIndex.ToStr()] - m.scrollOffset
    bottom = top + 94
    if bottom > 1034 then m.scrollOffset = m.scrollOffset + (bottom - 1034)
    if top < topOffset then m.scrollOffset = m.scrollOffset - (topOffset - top)
    if m.scrollOffset < 0 then m.scrollOffset = 0
    maximum = m.contentHeight - (1080 - topOffset)
    if maximum < 0 then maximum = 0
    if m.scrollOffset > maximum then m.scrollOffset = maximum
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        PorticoScreenAuthorityRelease(m.screenAuthority, key)
        return false
    end if
    if m.choiceKind = "feedback" or m.choiceKind = "security" then return false
    if m.choiceKind <> "" then return PorticoSettingsModalKey(key)
    if key = "up"
        if m.focusPosition > 0
            currentIndex = m.visibleRows[m.focusPosition]
            targetIndex = m.visibleRows[m.focusPosition - 1]
            currentId = "settings.row." + m.model.rows[currentIndex].id
            targetId = "settings.row." + m.model.rows[targetIndex].id
            if PorticoScreenAuthorityAcceptMove(m.screenAuthority, "up", currentId, targetId) then m.focusPosition = m.focusPosition - 1
        end if
        PorticoSettingsKeepFocusVisible()
        PorticoSettingsRender()
        return true
    else if key = "down"
        if m.focusPosition < m.visibleRows.Count() - 1
            currentIndex = m.visibleRows[m.focusPosition]
            targetIndex = m.visibleRows[m.focusPosition + 1]
            currentId = "settings.row." + m.model.rows[currentIndex].id
            targetId = "settings.row." + m.model.rows[targetIndex].id
            if PorticoScreenAuthorityAcceptMove(m.screenAuthority, "down", currentId, targetId) then m.focusPosition = m.focusPosition + 1
        end if
        PorticoSettingsKeepFocusVisible()
        PorticoSettingsRender()
        return true
    else if key = "OK"
        if m.visibleRows.Count() > 0
            rowIndex = m.visibleRows[m.focusPosition]
            if not PorticoScreenAuthorityBeginOK(m.screenAuthority, "settings.row." + m.model.rows[rowIndex].id) then return true
            PorticoSettingsActivate(rowIndex)
        end if
        return true
    end if
    return false
end function

sub PorticoSettingsActivate(rowIndex as integer)
    row = m.model.rows[rowIndex]
    if row.actionable = false then return
    id = row.id
    if id = "preference-state"
        PorticoSettingsEmit("retry-preferences", {})
    else if id = "profile"
        PorticoSettingsEmit("open-profile", {})
    else if id = "server"
        PorticoSettingsEmit(m.model.serverAction, {})
    else if id = "automatic-profile"
        PorticoSettingsEmit("set-automatic-profile", {enabled: not m.model.automaticProfile})
    else if id = "account-security"
        PorticoScreenAuthorityOpenModal(m.screenAuthority, "settings.row." + id)
        m.choiceKind = "security"
    else if id = "feedback"
        PorticoScreenAuthorityOpenModal(m.screenAuthority, "settings.row." + id)
        m.choiceKind = "feedback"
    else if id = "autoplay-next"
        PorticoSettingsPatchPlayback({autoplayNext: not m.model.preferences.profileServer.playback.autoplayNext})
    else if id = "pause-history"
        PorticoSettingsEmit("set-viewer-preference", {scopeType: "profile-server", changes: {privacy: {pauseWatchHistory: not m.model.preferences.profileServer.privacy.pauseWatchHistory}}})
    else if id = "up-next"
        PorticoSettingsOpenChoice("up-next")
    else if id = "seek-interval"
        PorticoSettingsOpenChoice("seek")
    else if id = "preferred-audio"
        PorticoSettingsOpenChoice("audio")
    else if id = "preferred-subtitles"
        PorticoSettingsOpenChoice("subtitles")
    else if id = "clear-watch-history"
        PorticoSettingsOpenChoice("confirm-watch-history")
    else if id = "clear-search-history"
        PorticoSettingsOpenChoice("confirm-search-history")
    else if id = "sign-out"
        PorticoSettingsEmit("sign-out-account", {})
    end if
    PorticoSettingsRender()
end sub

sub PorticoSettingsOpenChoice(kind as string)
    invokerId = "settings.row.unavailable"
    if m.visibleRows.Count() > 0 then invokerId = "settings.row." + m.model.rows[m.visibleRows[m.focusPosition]].id
    PorticoScreenAuthorityOpenModal(m.screenAuthority, invokerId)
    m.choiceKind = kind
    m.choiceOptions = []
    selected = ""
    playback = m.model.preferences.profileServer.playback
    if kind = "seek"
        m.choiceOptions = [{id: "10", label: PorticoSettingsSeconds(m.language, 10), value: 10}, {id: "15", label: PorticoSettingsSeconds(m.language, 15), value: 15}, {id: "30", label: PorticoSettingsSeconds(m.language, 30), value: 30}]
        selected = playback.skipForwardSeconds.ToStr()
    else if kind = "up-next"
        m.choiceOptions = [{id: "0", label: PorticoSettingsSeconds(m.language, 0), value: 0}, {id: "5", label: PorticoSettingsSeconds(m.language, 5), value: 5}, {id: "10", label: PorticoSettingsSeconds(m.language, 10), value: 10}, {id: "15", label: PorticoSettingsSeconds(m.language, 15), value: 15}]
        selected = playback.upNextCountdownSeconds.ToStr()
    else if kind = "audio"
        m.choiceOptions = PorticoSettingsLanguageOptions(false)
        selected = "original"
        if playback.preferredAudioLanguages.Count() > 0 then selected = playback.preferredAudioLanguages[0]
    else if kind = "subtitles"
        m.choiceOptions = PorticoSettingsLanguageOptions(true)
        selected = "off"
        if playback.subtitlesEnabled and playback.preferredSubtitleLanguages.Count() > 0 then selected = playback.preferredSubtitleLanguages[0]
    else
        m.choiceOptions = [{id: "confirm", label: PorticoSettingsCopy(m.language, "action.clear-history", "Clear"), value: true}, {id: "cancel", label: PorticoSettingsCopy(m.language, "action.close", "Close"), value: false}]
    end if
    m.choiceFocus = 0
    if kind = "confirm-watch-history" or kind = "confirm-search-history" then m.choiceFocus = 1
    for index = 0 to m.choiceOptions.Count() - 1
        if m.choiceOptions[index].id = selected then m.choiceFocus = index
    end for
end sub

function PorticoSettingsLanguageOptions(subtitles as boolean) as object
    first = "original"
    if subtitles then first = "off"
    return [
        {id: first, label: PorticoSettingsLanguageLabel(m.language, first, subtitles), value: first},
        {id: "en", label: PorticoSettingsLanguageLabel(m.language, "en", subtitles), value: "en"},
        {id: "fr", label: PorticoSettingsLanguageLabel(m.language, "fr", subtitles), value: "fr"},
        {id: "es", label: PorticoSettingsLanguageLabel(m.language, "es", subtitles), value: "es"}
    ]
end function

function PorticoSettingsModalKey(key as string) as boolean
    if key = "back"
        PorticoSettingsCloseModal()
        return true
    else if key = "up"
        if m.choiceFocus > 0 then m.choiceFocus = m.choiceFocus - 1
    else if key = "down"
        if m.choiceFocus < m.choiceOptions.Count() - 1 then m.choiceFocus = m.choiceFocus + 1
    else if key = "OK"
        option = m.choiceOptions[m.choiceFocus]
        kind = m.choiceKind
        if not PorticoScreenAuthorityBeginOK(m.screenAuthority, "settings.modal." + kind + "." + m.choiceRows[m.choiceFocus].semanticId) then return true
        if kind = "seek" then PorticoSettingsPatchPlayback({skipBackSeconds: option.value, skipForwardSeconds: option.value})
        if kind = "up-next" then PorticoSettingsPatchPlayback({upNextCountdownSeconds: option.value})
        if kind = "audio"
            values = []
            if option.value <> "original" then values = [option.value]
            PorticoSettingsPatchPlayback({preferredAudioLanguages: values})
        end if
        if kind = "subtitles"
            values = []
            enabled = option.value <> "off"
            if enabled then values = [option.value]
            PorticoSettingsPatchPlayback({subtitlesEnabled: enabled, preferredSubtitleLanguages: values})
        end if
        if kind = "confirm-watch-history" and option.value = true then PorticoSettingsEmit("clear-watch-history", {})
        if kind = "confirm-search-history" and option.value = true then PorticoSettingsEmit("clear-search-history", {})
        PorticoSettingsCloseModal()
        return true
    end if
    PorticoSettingsRenderModal()
    return true
end function

sub PorticoSettingsPatchPlayback(changes as object)
    PorticoSettingsEmit("set-viewer-preference", {scopeType: "profile-server", changes: {playback: changes}})
end sub

sub PorticoSettingsCloseModal()
    restoredId = PorticoScreenAuthorityCloseModal(m.screenAuthority, "settings.row.profile")
    m.choiceKind = ""
    m.choiceOptions = []
    m.choiceFocus = 0
    m.top.modalOpen = false
    m.top.setFocus(true)
    PorticoScreenAuthorityFocused(m.screenAuthority, restoredId)
    PorticoSettingsRender()
end sub

sub PorticoSettingsRenderModal()
    standard = m.choiceKind <> "" and m.choiceKind <> "feedback" and m.choiceKind <> "security"
    m.choiceModal.visible = standard
    if not standard then return
    title = PorticoSettingsCopy(m.language, "preferences.personal-playback-subtitles-label", "Preferred subtitles")
    body = ""
    if m.choiceKind = "seek" then title = PorticoSettingsCopy(m.language, "preferences.seek-interval-label", "Skip interval")
    if m.choiceKind = "up-next" then title = PorticoSettingsCopy(m.language, "preferences.up-next-label", "Up Next countdown")
    if m.choiceKind = "audio" then title = PorticoSettingsCopy(m.language, "preferences.personal-playback-audio-label", "Preferred audio")
    if m.choiceKind = "confirm-watch-history"
        title = PorticoSettingsCopy(m.language, "preferences.history-clear-label", "Clear watch history")
        body = PorticoSettingsCopy(m.language, "preferences.history-clear-confirmation", "Deletes plays and resume positions for this account. This cannot be undone.")
    end if
    if m.choiceKind = "confirm-search-history"
        title = PorticoSettingsCopy(m.language, "preferences.search-history-title", "Search history")
        body = "Clear the recent searches saved for this profile?"
    end if
    m.modalTitle.text = title
    m.modalBody.text = body
    for index = 0 to m.choiceRows.Count() - 1
        row = m.choiceRows[index]
        row.visible = index < m.choiceOptions.Count()
        if index < m.choiceOptions.Count()
            option = m.choiceOptions[index]
            selected = false
            if m.choiceKind = "seek" then selected = option.value = m.model.preferences.profileServer.playback.skipForwardSeconds
            if m.choiceKind = "up-next" then selected = option.value = m.model.preferences.profileServer.playback.upNextCountdownSeconds
            row.viewState = {model: {id: option.id, label: option.label, selected: selected}, focused: index = m.choiceFocus}
        end if
    end for
end sub

sub feedbackActivationChanged()
    action = m.feedback.activation
    if action = invalid or Type(action) <> "roAssociativeArray" then return
    if LCase(PorticoCoreSafeText(action.kind, 48)) = "close-feedback"
        PorticoSettingsCloseModal()
    else
        fields = {}
        for each key in action
            if key <> "sequence" then fields[key] = action[key]
        end for
        PorticoSettingsEmit(fields.kind, fields)
    end if
end sub

sub securityActivationChanged()
    action = m.security.activation
    if action <> invalid and LCase(PorticoCoreSafeText(action.kind, 48)) = "close-account-security" then PorticoSettingsCloseModal()
end sub

sub PorticoSettingsEmit(kind as string, fields as object)
    PorticoScreenAuthorityCommitOK(m.screenAuthority)
    m.activationSequence = m.activationSequence + 1
    activation = {sequence: m.activationSequence, kind: kind, page: "settings"}
    for each key in fields
        if key <> "kind" and key <> "sequence" then activation[key] = fields[key]
    end for
    m.top.activation = activation
end sub
