sub init()
    m.title = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.status = m.top.findNode("status")
    m.section = m.top.findNode("section")
    m.close = m.top.findNode("close")
    m.rows = []
    for index = 0 to 6
        m.rows.Push(m.top.findNode("row" + index.ToStr()))
    end for
    m.title.font = PorticoFont("700", 36)
    m.title.color = "#F4F7FA"
    m.subtitle.font = PorticoFont("400", 20)
    m.subtitle.color = "#8F9BA6"
    m.status.font = PorticoFont("500", 18)
    m.status.color = "#D5A84C"
    m.section.font = PorticoFont("600", 23)
    m.section.color = "#F4F7FA"
    loaded = PorticoProductLanguageLoad()
    m.language = invalid
    if loaded.ok then m.language = loaded.value
    m.model = invalid
    m.contextModel = {}
    m.targets = []
    m.focusIndex = 0
    m.sequence = 0
    m.close.model = {iconId: "action.close"}
    m.top.focusable = true
    PorticoWatchOverlayRender()
end sub

sub applyViewState()
    value = m.top.viewState
    m.model = invalid
    if value <> invalid and Type(value) = "roAssociativeArray"
        status = LCase(PorticoCoreSafeText(value.status, 32))
        allowed = {idle: true, loading: true, ready: true, active: true, working: true, reconnecting: true, offline: true, error: true}
        if allowed[status] = true and GetInterface(value.groups, "ifArray") <> invalid then m.model = value
    end if
    PorticoWatchOverlayRender()
end sub

sub applyContext()
    value = m.top.context
    if value = invalid or Type(value) <> "roAssociativeArray" then value = {}
    m.contextModel = {
        mediaId: PorticoViewerScopeOpaqueId(value.mediaId, 128),
        mediaTitle: PorticoCoreSafeText(value.mediaTitle, 180)
    }
    PorticoWatchOverlayRender()
end sub

sub PorticoWatchOverlayRender()
    m.title.text = PorticoWatchOverlayText("watch-with-friends.title", "Watch With Friends", {})
    m.subtitle.text = PorticoWatchOverlayText("watch-with-friends.description", "Watch in sync with people on this server.", {})
    m.status.text = ""
    m.targets = [{kind: "close", label: PorticoWatchOverlayText("action.close", "Close", {}), iconId: "action.close"}]
    state = m.model
    if state = invalid
        m.status.text = PorticoWatchOverlayTitle("watch-with-friends.unavailable", "Unavailable")
        m.section.text = ""
    else if state.group <> invalid
        group = state.group
        m.section.text = group.name
        roleId = "watch-with-friends.role-participant"
        if group.permissions.isHost then roleId = "watch-with-friends.role-host"
        connected = PorticoWatchOverlayText("watch-with-friends.connected-count", group.members.Count().ToStr() + " watching", {count: group.members.Count().ToStr()})
        m.status.text = connected + " · " + PorticoWatchOverlayText(roleId, "Host controls playback", {})
        m.targets.Push({kind: "leave-group", groupId: group.id, label: PorticoWatchOverlayText("action.leave-group", "Leave", {}), iconId: "action.close"})
        if group.permissions.isHost then m.targets.Push({kind: "end-group", groupId: group.id, label: PorticoWatchOverlayText("action.close", "End group", {}), iconId: "action.close"})
    else
        m.section.text = PorticoWatchOverlayText("watch-with-friends.active-groups", "Active groups", {})
        if m.contextModel.mediaId <> ""
            m.targets.Push({kind: "create-group", mediaId: m.contextModel.mediaId, mediaTitle: m.contextModel.mediaTitle, label: PorticoWatchOverlayText("action.start-watch-group", "Start a new group", {}), iconId: "account.user"})
        end if
        if state.status = "loading" or state.status = "working"
            m.status.text = PorticoWatchOverlayTitle("playback.preparing", "Loading")
        else if state.status = "reconnecting"
            m.status.text = PorticoWatchOverlayTitle("watch-with-friends.reconnecting", "Reconnecting")
        else if state.status = "offline" or state.status = "error"
            m.status.text = PorticoWatchOverlayTitle("watch-with-friends.unavailable", "Unavailable")
        end if
        for each group in state.groups
            if m.targets.Count() >= 8 then exit for
            people = PorticoWatchOverlayText("watch-with-friends.connected-count", group.members.Count().ToStr() + " watching", {count: group.members.Count().ToStr()})
            m.targets.Push({kind: "join-group", groupId: group.id, label: group.name + " · " + people, iconId: "account.user"})
        end for
        if state.groups.Count() = 0 and m.status.text = "" then m.status.text = PorticoWatchOverlayTitle("watch-with-friends.no-active-groups", "No active groups")
    end if
    if m.focusIndex >= m.targets.Count() then m.focusIndex = m.targets.Count() - 1
    if m.focusIndex < 0 then m.focusIndex = 0
    m.close.focused = m.focusIndex = 0
    for index = 0 to m.rows.Count() - 1
        row = m.rows[index]
        targetIndex = index + 1
        row.visible = targetIndex < m.targets.Count()
        if row.visible
            target = m.targets[targetIndex]
            row.model = {label: target.label, iconId: target.iconId, primary: target.kind = "create-group", width: 884}
            row.focused = m.focusIndex = targetIndex
        end if
    end for
    PorticoWatchOverlayPublishFocus()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back"
        PorticoWatchOverlayEmit({kind: "close"})
        return true
    else if key = "up"
        if m.focusIndex > 0 then m.focusIndex = m.focusIndex - 1
    else if key = "down"
        if m.focusIndex < m.targets.Count() - 1 then m.focusIndex = m.focusIndex + 1
    else if key = "OK"
        if m.focusIndex >= 0 and m.focusIndex < m.targets.Count() then PorticoWatchOverlayEmit(m.targets[m.focusIndex])
        return true
    else
        return false
    end if
    PorticoWatchOverlayRender()
    return true
end function

sub PorticoWatchOverlayEmit(target as object)
    m.sequence = m.sequence + 1
    action = {sequence: m.sequence, kind: target.kind}
    for each key in ["groupId", "mediaId", "mediaTitle"]
        if target[key] <> invalid then action[key] = target[key]
    end for
    if target.kind = "create-group"
        action.name = PorticoWatchOverlayText("watch-with-friends.group-name", target.mediaTitle, {title: target.mediaTitle})
    end if
    m.top.action = action
end sub

sub PorticoWatchOverlayPublishFocus()
    m.top.focusState = {area: "watch-with-friends", index: m.focusIndex, targetCount: m.targets.Count()}
end sub

function PorticoWatchOverlayText(messageId as string, fallback as string, variables as object) as string
    if m.language <> invalid
        message = PorticoProductLanguageMessage(m.language, messageId, "watch-with-friends.title", variables)
        if message.ok
            if message.text <> "" then return message.text
            if message.title <> "" then return message.title
            if message.body <> "" then return message.body
        end if
    end if
    return fallback
end function

function PorticoWatchOverlayTitle(messageId as string, fallback as string) as string
    if m.language <> invalid
        message = PorticoProductLanguageMessage(m.language, messageId, "watch-with-friends.unavailable", {})
        if message.ok and message.title <> "" then return message.title
    end if
    return fallback
end function
