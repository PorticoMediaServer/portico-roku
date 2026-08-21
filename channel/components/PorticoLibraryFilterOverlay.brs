sub init()
    m.panel = m.top.findNode("panel")
    m.title = m.top.findNode("title")
    m.body = m.top.findNode("body")
    m.field = m.top.findNode("field")
    m.operator = m.top.findNode("operator")
    m.value = m.top.findNode("value")
    m.summary = m.top.findNode("summary")
    m.apply = m.top.findNode("apply")
    m.cancel = m.top.findNode("cancel")
    m.panel.uri = "pkg:/images/ui/settings-modal.png"
    m.title.font = PorticoFont("700", 42)
    m.title.color = "#F4F7FA"
    m.body.font = PorticoFont("400", 20)
    m.body.color = "#8F9BA6"
    m.summary.font = PorticoFont("500", 18)
    m.summary.color = "#8F9BA6"
    loaded = PorticoProductLanguageLoad()
    m.language = invalid
    if loaded.ok then m.language = loaded.value
    m.fields = []
    m.draft = []
    m.fieldIndex = 0
    m.operatorIndex = 0
    m.valueIndex = 0
    m.focusIndex = 0
    m.sequence = 0
    m.top.focusable = true
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or Type(state) <> "roAssociativeArray" then return
    if state.fields <> invalid and GetInterface(state.fields, "ifArray") <> invalid then m.fields = state.fields
    if state.draft <> invalid and GetInterface(state.draft, "ifArray") <> invalid then m.draft = ParseJson(FormatJson(state.draft))
    if m.fieldIndex >= m.fields.count() then m.fieldIndex = 0
    m.title.text = filterCopyText("library.filters-title", "Filters")
    m.body.text = filterCopyBody("library.filters-body", "Choose a field, condition, and value.")
    renderFilterOverlay()
end sub

sub renderFilterOverlay()
    descriptor = filterSelectedField()
    if descriptor = invalid
        m.focusIndex = 4
        m.field.model = {label: filterCopyText("library.conditions-empty", "No filters available"), iconId: "action.customize", width: 720}
        m.operator.visible = false
        m.value.visible = false
        m.apply.visible = false
        m.cancel.model = {label: filterCopyText("action.cancel", "Cancel"), iconId: "action.cancel", width: 190}
        m.cancel.focused = true
        return
    end if
    if m.focusIndex < 0 or m.focusIndex > 4 then m.focusIndex = 0
    m.operator.visible = true
    m.value.visible = true
    m.apply.visible = true
    operators = descriptor.operators
    values = descriptor.allowedValues
    if operators.count() = 0 then operators = ["equals"]
    if values.count() = 0 then values = ["true", "false"]
    if m.operatorIndex >= operators.count() then m.operatorIndex = 0
    if m.valueIndex >= values.count() then m.valueIndex = 0
    m.field.model = {label: descriptor.label, iconId: "action.customize", width: 720}
    m.operator.model = {label: filterOperatorLabel(operators[m.operatorIndex]), iconId: "navigation.disclosure", width: 720}
    m.value.model = {label: values[m.valueIndex], iconId: "navigation.disclosure", width: 720}
    m.apply.model = {label: filterCopyText("action.apply", "Apply"), iconId: "action.confirm", primary: true, width: 200}
    m.cancel.model = {label: filterCopyText("action.cancel", "Cancel"), iconId: "action.cancel", width: 190}
    controls = [m.field, m.operator, m.value, m.apply, m.cancel]
    for index = 0 to controls.count() - 1
        controls[index].focused = index = m.focusIndex
    end for
    m.summary.text = m.draft.count().ToStr() + " " + filterCopyText("library.filter-conditions-suffix", "conditions")
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back"
        emitFilter("cancel-library-filters", invalid)
        return true
    end if
    if filterSelectedField() = invalid
        m.focusIndex = 4
        if key = "OK" then emitFilter("cancel-library-filters", invalid)
        renderFilterOverlay()
        return true
    end if
    if key = "up" and m.focusIndex > 0
        m.focusIndex = m.focusIndex - 1
    else if key = "down" and m.focusIndex < 4
        m.focusIndex = m.focusIndex + 1
    else if key = "left" or key = "right" or key = "OK"
        direction = 1
        if key = "left" then direction = -1
        if m.focusIndex = 0
            m.fieldIndex = filterWrap(m.fieldIndex + direction, m.fields.count())
            m.operatorIndex = 0
            m.valueIndex = 0
        else if m.focusIndex = 1
            field = filterSelectedField()
            m.operatorIndex = filterWrap(m.operatorIndex + direction, field.operators.count())
        else if m.focusIndex = 2
            field = filterSelectedField()
            values = field.allowedValues
            if values.count() = 0 then values = ["true", "false"]
            m.valueIndex = filterWrap(m.valueIndex + direction, values.count())
            filterUpdateDraft()
        else if m.focusIndex = 3 and key = "OK"
            predicate = filterCurrentPredicate()
            filterRememberPredicate(predicate)
            emitFilter("apply-library-filters", predicate)
            return true
        else if m.focusIndex = 4 and key = "OK"
            emitFilter("cancel-library-filters", invalid)
            return true
        end if
    end if
    renderFilterOverlay()
    return true
end function

sub filterUpdateDraft()
    predicate = filterCurrentPredicate()
    if predicate = invalid then return
    filterRememberPredicate(predicate)
    emitFilter("update-library-filter-draft", predicate)
end sub

function filterCurrentPredicate() as dynamic
    field = filterSelectedField()
    if field = invalid then return invalid
    operators = field.operators
    values = field.allowedValues
    if operators.count() = 0 then operators = ["equals"]
    if values.count() = 0 then values = ["true", "false"]
    return {field: field.id, operator: operators[m.operatorIndex], value: values[m.valueIndex]}
end function

sub filterRememberPredicate(predicate as dynamic)
    if predicate = invalid or Type(predicate) <> "roAssociativeArray" then return
    replaced = false
    for index = 0 to m.draft.count() - 1
        if m.draft[index].field = predicate.field
            m.draft[index] = predicate
            replaced = true
        end if
    end for
    if not replaced then m.draft.push(predicate)
end sub

sub emitFilter(kind as string, predicate as dynamic)
    m.sequence = m.sequence + 1
    activation = {sequence: m.sequence, kind: kind}
    if predicate <> invalid
        activation.fieldId = predicate.field
        activation.operatorId = predicate.operator
        activation.value = predicate.value
    end if
    m.top.activation = activation
end sub

function filterSelectedField() as dynamic
    if m.fieldIndex < 0 or m.fieldIndex >= m.fields.count() then return invalid
    return m.fields[m.fieldIndex]
end function

function filterWrap(value as integer, count as integer) as integer
    if count <= 0 then return 0
    if value < 0 then return count - 1
    if value >= count then return 0
    return value
end function

function filterOperatorLabel(value as string) as string
    if value = "equals" then return "Is"
    if value = "notEquals" then return "Is not"
    if value = "contains" then return "Contains"
    return value
end function

function filterCopyText(messageId as string, fallback as string) as string
    if m.language = invalid then return fallback
    copy = PorticoProductLanguageMessage(m.language, messageId, messageId, {})
    value = copy.text
    if value = "" then value = copy.title
    if value = "" then value = fallback
    return value
end function

function filterCopyBody(messageId as string, fallback as string) as string
    if m.language = invalid then return fallback
    copy = PorticoProductLanguageMessage(m.language, messageId, messageId, {})
    if copy.body <> "" then return copy.body
    return fallback
end function
