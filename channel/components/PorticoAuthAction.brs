sub init()
    m.surface = m.top.findNode("surface")
    m.label = m.top.findNode("label")
    m.label.font = PorticoFont("600", 24)
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    primary = model.primary = true
    actionId = ""
    if model.id <> invalid then actionId = model.id.ToStr()
    isField = actionId = "account-login" or actionId = "account-password"
    isTertiary = actionId = "start-local-auth"
    m.label.translation = [0, 0]
    m.label.width = 560
    m.label.horizAlign = "center"
    m.label.font = PorticoFont("600", 24)
    if isField
        if m.top.focused
            m.surface.uri = "pkg:/images/ui/auth-field-focus.png"
        else
            m.surface.uri = "pkg:/images/ui/auth-field-idle.png"
        end if
        m.label.translation = [24, 0]
        m.label.width = 512
        m.label.horizAlign = "left"
        m.label.font = PorticoFont("400", 23)
        m.label.color = "#C7D0D8"
    else if primary
        if m.top.focused
            m.surface.uri = "pkg:/images/ui/auth-action-primary-focus.png"
        else
            m.surface.uri = "pkg:/images/ui/auth-action-primary.png"
        end if
        m.label.color = "#070B10"
    else if isTertiary
        if m.top.focused
            m.surface.uri = "pkg:/images/ui/auth-action-tertiary-focus.png"
        else
            m.surface.uri = "pkg:/images/ui/auth-action-tertiary.png"
        end if
        m.label.font = PorticoFont("600", 22)
        m.label.color = "#70BCE8"
    else
        if m.top.focused
            m.surface.uri = "pkg:/images/ui/auth-action-secondary-focus.png"
        else
            m.surface.uri = "pkg:/images/ui/auth-action-secondary.png"
        end if
        m.label.color = "#F4F7FA"
    end if
    m.label.text = PorticoAuthActionText(model.label, 52)
end sub

function PorticoAuthActionText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function
