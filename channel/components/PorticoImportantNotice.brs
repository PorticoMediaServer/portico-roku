sub init()
    m.icon = m.top.findNode("icon")
    m.title = m.top.findNode("title")
    m.body = m.top.findNode("body")
    m.dismiss = m.top.findNode("dismiss")
    m.title.font = PorticoFont("600", 21)
    m.title.color = "#F4F7FA"
    m.body.font = PorticoFont("400", 17)
    m.body.color = "#C7D0D8"
    language = PorticoProductLanguageLoad()
    m.language = invalid
    if language.ok then m.language = language.value
    dismissLabel = "Dismiss"
    if m.language <> invalid
        copy = PorticoProductLanguageMessage(m.language, "action.dismiss", "action.dismiss", {})
        if copy.ok and PorticoCoreSafeText(copy.text, 80) <> "" then dismissLabel = PorticoCoreSafeText(copy.text, 80)
    end if
    m.dismiss.model = {label: dismissLabel, iconId: "action.confirm", width: 232}
    m.sequence = 0
    m.top.focusable = true
    render()
end sub

sub render()
    model = m.top.viewState
    visible = model <> invalid and Type(model) = "roAssociativeArray" and PorticoImportantNoticeId(model.id) <> ""
    m.top.visible = visible
    if not visible then return
    m.title.text = PorticoImportantNoticeText(model.title, 120)
    m.body.text = PorticoImportantNoticeText(model.body, 1000)
    iconId = PorticoCoreSafeIdentifier(model.iconId, 120)
    if iconId = "" then iconId = "status.warning"
    iconManifest = invalid
    if m.language <> invalid then iconManifest = m.language.iconManifest
    m.icon.uri = PorticoIconResolverUri(iconManifest, iconId, "default")
    m.dismiss.focused = m.top.focused
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press or not m.top.visible or not m.top.focused then return false
    if key = "OK"
        model = m.top.viewState
        id = ""
        revision = 0
        if model <> invalid and Type(model) = "roAssociativeArray"
            id = PorticoImportantNoticeId(model.id)
            revision = PorticoImportantNoticeInteger(model.revision, 0)
        end if
        if id = "" then return true
        m.sequence = m.sequence + 1
        activationKind = "dismiss-notification"
        if model.dismissKind <> invalid
            requestedKind = LCase(PorticoImportantNoticeText(model.dismissKind, 64))
            if requestedKind = "dismiss-saved-mutation-error" then activationKind = requestedKind
        end if
        m.top.activation = {sequence: m.sequence, kind: activationKind, notificationId: id, expectedRevision: revision}
        return true
    end if
    return false
end function

function PorticoImportantNoticeId(value as dynamic) as string
    text = PorticoImportantNoticeText(value, 128)
    if text = "" then return ""
    for position = 1 to Len(text)
        code = Asc(Mid(text, position, 1))
        if code < 32 or code = 127 then return ""
    end for
    return text
end function

function PorticoImportantNoticeText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    result = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(result) > maximum then result = Left(result, maximum)
    return result
end function

function PorticoImportantNoticeInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    kind = LCase(Type(value))
    if kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" then return fallback
    result = Int(value)
    if result < 0 then return fallback
    return result
end function
