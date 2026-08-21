sub init()
    m.title = m.top.findNode("title")
    m.summarySurface = m.top.findNode("summarySurface")
    m.avatar = m.top.findNode("avatar")
    m.initial = m.top.findNode("initial")
    m.displayName = m.top.findNode("displayName")
    m.authLabel = m.top.findNode("authLabel")
    m.serverStatus = m.top.findNode("serverStatus")
    m.accountGroup = m.top.findNode("accountGroup")
    m.rows = [m.top.findNode("row0"), m.top.findNode("row1"), m.top.findNode("row2"), m.top.findNode("row3")]
    loadedLanguage = PorticoProductLanguageLoad()
    m.language = invalid
    if loadedLanguage.ok then m.language = loadedLanguage.value

    m.title.font = PorticoFont("700", 48)
    m.title.color = "#F4F7FA"
    m.title.vertAlign = "top"
    m.initial.font = PorticoFont("700", 24)
    m.initial.color = "#F4F7FA"
    m.displayName.font = PorticoFont("600", 25)
    m.displayName.color = "#F4F7FA"
    m.displayName.vertAlign = "top"
    m.authLabel.font = PorticoFont("500", 18)
    m.authLabel.color = "#70BCE8"
    m.authLabel.vertAlign = "top"
    m.serverStatus.font = PorticoFont("400", 19)
    m.serverStatus.color = "#8F9BA6"
    m.serverStatus.vertAlign = "top"
    m.accountGroup.font = PorticoFont("600", 19)
    m.accountGroup.color = "#8F9BA6"
    m.accountGroup.vertAlign = "top"

    m.avatar.uri = "pkg:/images/ui/settings-avatar.png"
    m.accountGroup.text = "Account"
    m.title.text = "Profile and server"
    m.runtime = {}
    m.model = PorticoProfileModel(m.runtime, m.language)
    m.focusedRow = 0
    m.activationSequence = 0
    m.hasFocus = true
    m.screenAuthority = PorticoScreenAuthorityCreate("profile")
    m.top.focusable = true
    PorticoProfileRender()
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
    if state.focusedRow <> invalid
        requested = PorticoHttpInteger(state.focusedRow, m.focusedRow)
        if requested >= 0 and requested < m.rows.count() then m.focusedRow = requested
    end if
    m.model = PorticoProfileModel(m.runtime, m.language)
    PorticoProfileRender()
end sub

sub PorticoProfileRender()
    m.initial.text = m.model.initial
    m.displayName.text = m.model.displayName
    m.authLabel.text = m.model.authLabel
    m.serverStatus.text = m.model.statusDetail
    if m.model.connectionTone = "healthy" then m.serverStatus.color = "#62C9A7" else m.serverStatus.color = "#8F9BA6"
    if m.model.connectionTone = "danger" then m.serverStatus.color = "#ED5B67"
    if m.model.connectionTone = "warning" then m.serverStatus.color = "#D7A34D"
    for index = 0 to m.rows.count() - 1
        m.rows[index].viewState = {model: m.model.rows[index], focused: m.hasFocus and index = m.focusedRow}
    end for
    semanticIds = []
    for each row in m.model.rows
        semanticIds.Push("profile.row." + row.id)
    end for
    PorticoScreenAuthorityTargets(m.screenAuthority, semanticIds)
    if m.focusedRow >= 0 and m.focusedRow < m.model.rows.Count() then PorticoScreenAuthorityFocused(m.screenAuthority, "profile.row." + m.model.rows[m.focusedRow].id)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        PorticoScreenAuthorityRelease(m.screenAuthority, key)
        return false
    end if
    if key = "up"
        if m.focusedRow > 0
            currentId = "profile.row." + m.model.rows[m.focusedRow].id
            targetId = "profile.row." + m.model.rows[m.focusedRow - 1].id
            if PorticoScreenAuthorityAcceptMove(m.screenAuthority, "up", currentId, targetId) then m.focusedRow = m.focusedRow - 1
        end if
        PorticoProfileRender()
        return true
    else if key = "down"
        if m.focusedRow < m.rows.count() - 1
            currentId = "profile.row." + m.model.rows[m.focusedRow].id
            targetId = "profile.row." + m.model.rows[m.focusedRow + 1].id
            if PorticoScreenAuthorityAcceptMove(m.screenAuthority, "down", currentId, targetId) then m.focusedRow = m.focusedRow + 1
        end if
        PorticoProfileRender()
        return true
    else if key = "OK"
        semanticId = "profile.row." + m.model.rows[m.focusedRow].id
        if not PorticoScreenAuthorityBeginOK(m.screenAuthority, semanticId) then return true
        if m.focusedRow = 0
            PorticoProfileEmit(m.model.serverAction)
        else if m.focusedRow = 1
            PorticoProfileEmit("switch-profile")
        else if m.focusedRow = 2
            PorticoProfileEmit("open-settings")
        else
            PorticoProfileEmit("sign-out-account")
        end if
        return true
    end if
    return false
end function

sub PorticoProfileEmit(kind as string)
    PorticoScreenAuthorityCommitOK(m.screenAuthority)
    m.activationSequence = m.activationSequence + 1
    m.top.activation = {sequence: m.activationSequence, kind: kind, page: "profile"}
end sub
