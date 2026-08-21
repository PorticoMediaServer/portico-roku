sub init()
    m.scrim = m.top.findNode("scrim")
    m.panelSurface = m.top.findNode("panelSurface")
    m.title = m.top.findNode("title")
    m.closeAction = m.top.findNode("closeAction")
    m.avatar = m.top.findNode("avatar")
    m.avatarText = m.top.findNode("avatarText")
    m.accountName = m.top.findNode("accountName")
    m.accountDetail = m.top.findNode("accountDetail")
    m.catalogState = m.top.findNode("catalogState")
    m.catalogStatus = m.top.findNode("catalogStatus")
    m.catalogBody = m.top.findNode("catalogBody")
    m.actionRule = m.top.findNode("actionRule")
    m.rows = []
    for index = 0 to 5
        row = m.top.findNode("serverRow" + index.ToStr())
        row.visible = false
        m.rows.push(row)
    end for
    m.actions = [m.top.findNode("refreshAction"), m.top.findNode("accountAction")]

    m.scrim.uri = "pkg:/images/ui/overlay-scrim.png"
    m.avatar.uri = "pkg:/images/ui/server-avatar.png"
    m.title.font = PorticoFont("600", 30)
    m.title.color = "#F4F7FA"
    m.title.text = "Profile and server"
    m.avatarText.font = PorticoFont("700", 17)
    m.avatarText.color = "#F4F7FA"
    m.accountName.font = PorticoFont("600", 25)
    m.accountName.color = "#F4F7FA"
    m.accountDetail.font = PorticoFont("400", 18)
    m.accountDetail.color = "#8F9BA6"
    m.catalogStatus.font = PorticoFont("600", 17)
    m.catalogBody.font = PorticoFont("400", 18)
    m.catalogBody.color = "#C7D0D8"
    m.closeAction.model = {iconId: "action.close", selected: false}
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or state.model = invalid then return
    model = state.model
    servers = model.servers
    if servers = invalid then servers = []
    offset = 0
    if state.offset <> invalid then offset = state.offset
    focusedIndex = 0
    if state.focusedIndex <> invalid then focusedIndex = state.focusedIndex
    focusArea = "serverList"
    if state.focusArea <> invalid then focusArea = state.focusArea
    focusedAction = 0
    if state.focusedAction <> invalid then focusedAction = state.focusedAction

    displayName = "Portico Account"
    if model.accountDisplayName <> invalid and model.accountDisplayName <> ""
        displayName = Left(model.accountDisplayName.ToStr(), 72)
    end if
    accountDetail = "No server selected"
    if model.accountDetail <> invalid and model.accountDetail <> ""
        accountDetail = Left(model.accountDetail.ToStr(), 96)
    end if
    m.avatarText.text = PorticoServerInitials(displayName)
    m.accountName.text = displayName
    m.accountDetail.text = accountDetail
    m.closeAction.focused = focusArea = "serverClose"

    visibleRows = servers.count()
    if visibleRows > m.rows.count() then visibleRows = m.rows.count()
    contentSlots = visibleRows
    if contentSlots < 1 then contentSlots = 1

    catalogState = model.catalogState
    m.catalogState.visible = catalogState <> invalid and visibleRows = 0
    if m.catalogState.visible
        m.catalogStatus.text = catalogState.status
        m.catalogStatus.color = "#8F9BA6"
        if catalogState.statusTone = "warning" then m.catalogStatus.color = "#D7A34D"
        if catalogState.statusTone = "danger" then m.catalogStatus.color = "#ED5B67"
        if catalogState.statusTone = "account" then m.catalogStatus.color = "#70BCE8"
        if catalogState.statusTone = "healthy" then m.catalogStatus.color = "#62C9A7"
        m.catalogBody.text = catalogState.body
    end if

    actions = model.actions
    if actions = invalid then actions = []
    visibleActions = actions.count()
    if visibleActions > m.actions.count() then visibleActions = m.actions.count()
    panelHeight = 218 + (contentSlots * 82) + (visibleActions * 82)
    m.panelSurface.height = panelHeight
    m.panelSurface.loadHeight = panelHeight
    if visibleRows = 0 and visibleActions = 1
        m.panelSurface.uri = "pkg:/images/ui/server-panel-compact.png"
    else
        m.panelSurface.uri = "pkg:/images/ui/server-panel-" + contentSlots.ToStr() + ".png"
    end if

    for rowIndex = 0 to m.rows.count() - 1
        row = m.rows[rowIndex]
        sourceIndex = offset + rowIndex
        row.visible = false
        if sourceIndex < servers.count()
            row.viewState = {
                model: servers[sourceIndex],
                focused: focusArea = "serverList" and sourceIndex = focusedIndex
            }
            row.visible = true
        end if
    end for

    actionRuleY = 198 + (contentSlots * 82)
    actionStartY = actionRuleY + 10
    m.actionRule.translation = [22, actionRuleY]
    m.actions[0].translation = [10, actionStartY]
    m.actions[1].translation = [10, actionStartY + 82]
    for actionIndex = 0 to m.actions.count() - 1
        action = m.actions[actionIndex]
        action.visible = false
        if actionIndex < visibleActions
            action.viewState = {
                model: actions[actionIndex],
                focused: focusArea = "serverActions" and actionIndex = focusedAction
            }
            action.visible = true
        end if
    end for
end sub

function PorticoServerInitials(displayName as string) as string
    normalized = displayName.Trim()
    if normalized = "" then return "P"
    firstInitial = UCase(Left(normalized, 1))
    lastSpaceIndex = 0
    for position = 1 to Len(normalized)
        if Mid(normalized, position, 1) = " " then lastSpaceIndex = position
    end for
    if lastSpaceIndex <= 0 then return UCase(Left(normalized, 2))
    remainder = Mid(normalized, lastSpaceIndex + 1).Trim()
    if remainder = "" then return firstInitial
    return firstInitial + UCase(Left(remainder, 1))
end function
