sub init()
    m.horizonScrim = m.top.findNode("horizonScrim")
    m.wordmark = m.top.findNode("wordmark")
    m.status = m.top.findNode("status")
    m.titleLines = [m.top.findNode("title0"), m.top.findNode("title1")]
    m.bodyLines = [m.top.findNode("body0"), m.top.findNode("body1"), m.top.findNode("body2")]
    m.actions = [m.top.findNode("action0"), m.top.findNode("action1"), m.top.findNode("action2")]
    m.detailDivider = m.top.findNode("detailDivider")
    m.detailLines = [m.top.findNode("detail0"), m.top.findNode("detail1"), m.top.findNode("detail2")]

    m.horizonScrim.uri = "pkg:/images/ui/hero-vertical-home.png"
    m.wordmark.uri = "pkg:/images/brand/portico-wordmark.png"
    m.status.font = PorticoFont("600", 21)
    m.status.vertAlign = "top"
    for each line in m.titleLines
        line.font = PorticoFont("700", 52)
        line.color = "#F4F7FA"
        line.vertAlign = "top"
        line.visible = false
    end for
    for each line in m.bodyLines
        line.font = PorticoFont("400", 23)
        line.color = "#C7D0D8"
        line.vertAlign = "top"
        line.visible = false
    end for
    for each action in m.actions
        action.visible = false
    end for
    for each line in m.detailLines
        line.font = PorticoFont("400", 19)
        line.color = "#8F9BA6"
        line.vertAlign = "top"
        line.visible = false
    end for
    m.detailDivider.visible = false
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or state.model = invalid then return
    model = state.model
    focusedAction = 0
    if state.focusedAction <> invalid then focusedAction = state.focusedAction

    statusColor = "#8F9BA6"
    if model.statusTone = "warning" then statusColor = "#D7A34D"
    if model.statusTone = "danger" then statusColor = "#ED5B67"
    if model.statusTone = "account" then statusColor = "#70BCE8"
    if model.statusTone = "healthy" then statusColor = "#62C9A7"
    m.status.text = model.status
    m.status.color = statusColor

    titleLines = PorticoBreakText(model.title, 1100, 52, "700", 2)
    applyLines(m.titleLines, titleLines, 191, 62)

    bodyY = 273
    if titleLines.count() > 1 then bodyY = 335
    bodyLines = PorticoBreakText(model.body, 1020, 23, "400", 3)
    applyLines(m.bodyLines, bodyLines, bodyY, 32)

    actionY = bodyY + (bodyLines.count() * 32) + 30
    x = 0
    for index = 0 to m.actions.count() - 1
        button = m.actions[index]
        button.visible = false
        if model.actions <> invalid and index < model.actions.count()
            actionModel = model.actions[index]
            width = 214
            if actionModel.width <> invalid then width = actionModel.width
            button.model = {label: actionModel.label, iconId: actionModel.iconId, primary: index = 0, width: width}
            button.focused = index = focusedAction
            button.translation = [x, actionY]
            button.visible = true
            x = x + width + 12
        end if
    end for

    m.detailDivider.visible = false
    applyLines(m.detailLines, [], 0, 28)
    if model.detail <> invalid and model.detail <> ""
        dividerY = actionY + 106
        if model.actions = invalid or model.actions.count() = 0 then dividerY = actionY + 42
        m.detailDivider.translation = [0, dividerY]
        m.detailDivider.visible = true
        detailLines = PorticoBreakText(model.detail, 1180, 19, "400", 3)
        applyLines(m.detailLines, detailLines, dividerY + 31, 28)
    end if
end sub

sub applyLines(nodes as object, values as object, y as integer, pitch as integer)
    for index = 0 to nodes.count() - 1
        node = nodes[index]
        node.visible = false
        node.text = ""
        if values <> invalid and index < values.count()
            node.text = values[index]
            node.translation = [0, y + (index * pitch)]
            node.visible = true
        end if
    end for
end sub
