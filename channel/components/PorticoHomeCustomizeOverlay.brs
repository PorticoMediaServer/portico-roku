sub init()
    m.panel = m.top.findNode("panel")
    m.title = m.top.findNode("title")
    m.body = m.top.findNode("body")
    m.rows = m.top.findNode("rows")
    m.moveUp = m.top.findNode("moveUp")
    m.moveDown = m.top.findNode("moveDown")
    m.visibility = m.top.findNode("visibility")
    m.reset = m.top.findNode("reset")
    m.save = m.top.findNode("save")
    m.cancel = m.top.findNode("cancel")
    m.panel.uri = "pkg:/images/ui/settings-modal.png"
    m.title.font = PorticoFont("700", 42)
    m.title.color = "#F4F7FA"
    m.body.font = PorticoFont("400", 20)
    m.body.color = "#8F9BA6"
    loaded = PorticoProductLanguageLoad()
    m.language = invalid
    if loaded.ok then m.language = loaded.value
    m.focusArea = "rows"
    m.rowIndex = 0
    m.actionIndex = 0
    m.sequence = 0
    m.rowsModel = []
    m.order = []
    m.hidden = []
    m.top.focusable = true
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or Type(state) <> "roAssociativeArray" then return
    if state.rows <> invalid and GetInterface(state.rows, "ifArray") <> invalid
        m.rowsModel = ParseJson(FormatJson(state.rows))
        m.order = homeCustomizeStringArray(state.rowOrder)
        m.hidden = homeCustomizeStringArray(state.hiddenRowIds)
        m.expectedRevision = homeCustomizeInteger(state.expectedRevision, -1)
        homeCustomizeNormalizeOrder()
    end if
    m.title.text = homeCustomizeCopyText("home.customize-title", "Customize Home")
    m.body.text = homeCustomizeCopyBody("home.customize-body", "Choose which rows appear and the order they use.")
    renderHomeCustomize()
end sub

sub homeCustomizeNormalizeOrder()
    ordered = []
    used = {}
    for each id in m.order
        if homeCustomizeFindRow(id) <> invalid and used[id] <> true
            ordered.push(id)
            used[id] = true
        end if
    end for
    for each row in m.rowsModel
        if used[row.id] <> true
            ordered.push(row.id)
            used[row.id] = true
        end if
    end for
    m.order = ordered
end sub

sub renderHomeCustomize()
    m.rows.removeChildrenIndex(m.rows.getChildCount(), 0)
    if m.rowIndex < 0 then m.rowIndex = 0
    if m.rowIndex >= m.order.count() then m.rowIndex = m.order.count() - 1
    first = 0
    if m.rowIndex > 5 then first = m.rowIndex - 5
    for index = first to m.order.count() - 1
        visible = index - first
        if visible >= 6 then exit for
        row = homeCustomizeFindRow(m.order[index])
        if row <> invalid
            focused = m.focusArea = "rows" and index = m.rowIndex
            surface = "#111923"
            border = "#24313D"
            if focused
                surface = "#151F29"
                border = "#EAF6FF"
            end if
            group = m.rows.CreateChild("Group")
            group.translation = [0, visible * 70]
            PorticoRectangle(group, [0, 0], 996, 60, surface)
            PorticoRectangle(group, [0, 0], 996, 2, border)
            PorticoLabel(group, row.title, [20, 9], 700, 40, 22, "600", "#F4F7FA")
            stateLabel = homeCustomizeCopyText("home.row-shown", "Shown")
            if row.required = true then stateLabel = homeCustomizeCopyText("home.row-always-shown", "Always shown") else if homeCustomizeContains(m.hidden, row.id) then stateLabel = homeCustomizeCopyText("home.row-hidden", "Hidden")
            status = PorticoLabel(group, stateLabel, [746, 12], 226, 36, 18, "500", "#8F9BA6")
            status.horizAlign = "right"
        end if
    end for
    actions = [m.moveUp, m.moveDown, m.visibility, m.reset, m.save, m.cancel]
    labels = ["Move Up", "Move Down", "Hide", "Reset", "Save", "Cancel"]
    ids = ["move-up", "move-down", "visibility", "reset", "save", "cancel"]
    row = homeCustomizeSelectedRow()
    if row <> invalid and homeCustomizeContains(m.hidden, row.id) then labels[2] = "Show"
    widths = [190, 210, 240, 180, 200, 190]
    icons = ["navigation.move-up", "navigation.move-down", "status.artwork-unavailable", "action.reset", "action.confirm", "action.cancel"]
    for index = 0 to actions.count() - 1
        actions[index].model = {id: ids[index], label: labels[index], iconId: icons[index], primary: index = 4, width: widths[index]}
        actions[index].focused = m.focusArea = "actions" and m.actionIndex = index
    end for
    canMove = row <> invalid and row.reorderable = true
    m.moveUp.visible = canMove
    m.moveDown.visible = canMove
    m.visibility.visible = row <> invalid and row.hideable = true and row.required <> true
    m.visibleActionIndices = []
    for index = 0 to actions.count() - 1
        if actions[index].visible then m.visibleActionIndices.push(index)
    end for
    if m.visibleActionIndices.count() > 0 and not homeCustomizeContainsIndex(m.visibleActionIndices, m.actionIndex) then m.actionIndex = m.visibleActionIndices[0]
    for index = 0 to actions.count() - 1
        actions[index].focused = m.focusArea = "actions" and m.actionIndex = index and actions[index].visible
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back"
        emitHomeCustomize("cancel-home-customization")
        return true
    end if
    if m.focusArea = "rows"
        if key = "up" and m.rowIndex > 0
            m.rowIndex = m.rowIndex - 1
        else if key = "down" and m.rowIndex < m.order.count() - 1
            m.rowIndex = m.rowIndex + 1
        else if key = "down" or key = "OK"
            m.focusArea = "actions"
            renderHomeCustomize()
            if m.visibleActionIndices.count() > 0 then m.actionIndex = m.visibleActionIndices[0]
        end if
    else
        actionPosition = homeCustomizeIndexOf(m.visibleActionIndices, m.actionIndex)
        if key = "left" and actionPosition > 0
            m.actionIndex = m.visibleActionIndices[actionPosition - 1]
        else if key = "right" and actionPosition >= 0 and actionPosition < m.visibleActionIndices.count() - 1
            m.actionIndex = m.visibleActionIndices[actionPosition + 1]
        else if key = "up"
            m.focusArea = "rows"
        else if key = "OK"
            activateHomeCustomizeAction()
        end if
    end if
    renderHomeCustomize()
    return true
end function

function homeCustomizeContainsIndex(values as object, target as integer) as boolean
    return homeCustomizeIndexOf(values, target) >= 0
end function

function homeCustomizeIndexOf(values as object, target as integer) as integer
    for index = 0 to values.count() - 1
        if values[index] = target then return index
    end for
    return -1
end function

function homeCustomizeInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "longinteger" or valueType = "roint" or valueType = "rointeger" or valueType = "rolonginteger" then return value
    return fallback
end function

sub activateHomeCustomizeAction()
    row = homeCustomizeSelectedRow()
    if m.actionIndex = 0 and row <> invalid and row.reorderable = true and m.rowIndex > 0
        previous = m.order[m.rowIndex - 1]
        m.order[m.rowIndex - 1] = m.order[m.rowIndex]
        m.order[m.rowIndex] = previous
        m.rowIndex = m.rowIndex - 1
    else if m.actionIndex = 1 and row <> invalid and row.reorderable = true and m.rowIndex < m.order.count() - 1
        nextValue = m.order[m.rowIndex + 1]
        m.order[m.rowIndex + 1] = m.order[m.rowIndex]
        m.order[m.rowIndex] = nextValue
        m.rowIndex = m.rowIndex + 1
    else if m.actionIndex = 2 and row <> invalid and row.hideable = true and row.required <> true
        if homeCustomizeContains(m.hidden, row.id) then homeCustomizeRemove(m.hidden, row.id) else m.hidden.push(row.id)
    else if m.actionIndex = 3
        m.order = []
        m.hidden = []
        for each candidate in m.rowsModel
            m.order.push(candidate.id)
        end for
        m.rowIndex = 0
    else if m.actionIndex = 4
        m.sequence = m.sequence + 1
        m.top.activation = {sequence: m.sequence, kind: "save-home-customization", rowOrder: ParseJson(FormatJson(m.order)), hiddenRowIds: ParseJson(FormatJson(m.hidden)), expectedRevision: m.expectedRevision}
    else if m.actionIndex = 5
        emitHomeCustomize("cancel-home-customization")
    end if
end sub

sub emitHomeCustomize(kind as string)
    m.sequence = m.sequence + 1
    m.top.activation = {sequence: m.sequence, kind: kind}
end sub

function homeCustomizeSelectedRow() as dynamic
    if m.rowIndex < 0 or m.rowIndex >= m.order.count() then return invalid
    return homeCustomizeFindRow(m.order[m.rowIndex])
end function

function homeCustomizeFindRow(id as string) as dynamic
    for each row in m.rowsModel
        if row.id = id then return row
    end for
    return invalid
end function

function homeCustomizeContains(values as object, expected as string) as boolean
    for each value in values
        if value = expected then return true
    end for
    return false
end function

sub homeCustomizeRemove(values as object, expected as string)
    for index = values.count() - 1 to 0 step -1
        if values[index] = expected then values.delete(index)
    end for
end sub

function homeCustomizeStringArray(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each raw in source
        value = raw.ToStr()
        if value <> "" and not homeCustomizeContains(result, value) then result.push(value)
    end for
    return result
end function

function homeCustomizeCopyText(messageId as string, fallback as string) as string
    if m.language = invalid then return fallback
    copy = PorticoProductLanguageMessage(m.language, messageId, messageId, {})
    value = copy.text
    if value = "" then value = copy.title
    if value = "" then value = fallback
    return value
end function

function homeCustomizeCopyBody(messageId as string, fallback as string) as string
    if m.language = invalid then return fallback
    copy = PorticoProductLanguageMessage(m.language, messageId, messageId, {})
    if copy.body <> "" then return copy.body
    return fallback
end function
