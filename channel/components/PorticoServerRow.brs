sub init()
    m.surface = m.top.findNode("surface")
    m.selectionIndicator = m.top.findNode("selectionIndicator")
    m.actionIcon = m.top.findNode("actionIcon")
    m.name = m.top.findNode("name")
    m.detail = m.top.findNode("detail")
    m.availability = m.top.findNode("availability")
    m.trailingIcon = m.top.findNode("trailingIcon")

    m.name.font = PorticoFont("600", 22)
    m.name.color = "#F4F7FA"
    m.detail.font = PorticoFont("400", 17)
    m.detail.color = "#8F9BA6"
    m.availability.font = PorticoFont("600", 17)
    m.availability.color = "#C7D0D8"
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or state.model = invalid then return
    model = state.model
    focused = false
    if state.focused <> invalid then focused = state.focused = true
    selected = false
    if model.selected <> invalid then selected = model.selected = true
    kind = "server"
    if model.kind <> invalid then kind = model.kind.ToStr()

    surfaceState = "idle"
    if selected then surfaceState = "selected"
    if focused
        surfaceState = "focus"
        if selected then surfaceState = "selected-focus"
    end if
    m.surface.uri = "pkg:/images/ui/server-row-" + surfaceState + ".png"

    m.name.text = model.name
    m.name.color = "#F4F7FA"
    if selected then m.name.color = "#70BCE8"
    m.detail.text = ""
    if model.detail <> invalid then m.detail.text = model.detail
    m.availability.text = ""
    if model.availabilityLabel <> invalid then m.availability.text = model.availabilityLabel
    m.availability.color = "#C7D0D8"
    if model.availabilityTone = "healthy" then m.availability.color = "#62C9A7"
    if model.availabilityTone = "warning" then m.availability.color = "#D7A34D"
    if model.availabilityTone = "account" then m.availability.color = "#70BCE8"

    m.selectionIndicator.visible = kind = "server"
    m.actionIcon.visible = kind = "action"
    m.trailingIcon.visible = kind = "action"
    if kind = "server"
        indicatorState = ""
        if selected then indicatorState = "-selected"
        if focused
            indicatorState = "-focus"
            if selected then indicatorState = "-selected-focus"
        end if
        m.selectionIndicator.uri = "pkg:/images/ui/server-radio" + indicatorState + ".png"
    else
        icon = "account.user"
        if model.iconId <> invalid then icon = model.iconId.ToStr()
        m.actionIcon.uri = PorticoIconResolverPackageUri(icon, "rail")
        m.trailingIcon.uri = PorticoIconResolverPackageUri("navigation.disclosure", "rail")
        m.name.translation = [62, 0]
        m.name.height = 82
        m.name.vertAlign = "center"
        m.detail.visible = false
        m.availability.visible = false
    end if

    if kind = "server"
        m.name.translation = [62, 11]
        m.name.height = 29
        m.name.vertAlign = "top"
        m.detail.visible = true
        m.availability.visible = true
    end if
end sub
