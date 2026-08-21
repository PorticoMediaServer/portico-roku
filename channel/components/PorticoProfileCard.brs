sub init()
    m.surface = m.top.findNode("surface")
    m.focusSurface = m.top.findNode("focusSurface")
    m.avatar = m.top.findNode("avatar")
    m.fallback = m.top.findNode("fallback")
    m.name = m.top.findNode("name")
    m.detail = m.top.findNode("detail")
    m.focusSurface.uri = "pkg:/images/ui/square-card-focus.png"
    m.fallback.uri = PorticoIconResolverPackageUri("account.profile", "rail")
    m.name.font = PorticoFont("600", 24)
    m.name.color = "#F4F7FA"
    m.detail.font = PorticoFont("400", 17)
    m.detail.color = "#8F9BA6"
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or state.model = invalid then return
    profile = state.model
    focused = state.focused = true
    m.focusSurface.visible = focused
    m.surface.color = "#121921"
    if focused then m.surface.color = "#18232D"
    m.name.text = Left(profile.name.ToStr(), 80)
    m.detail.text = ""
    if profile.hasPIN = true then m.detail.text = "PIN required"
    m.top.accessibilityLabel = m.name.text
    if m.detail.text <> "" then m.top.accessibilityLabel = m.top.accessibilityLabel + ", " + m.detail.text
    m.top.focusable = true
    if focused then m.top.setFocus(true)
    m.avatar.uri = ""
    m.avatar.visible = false
    m.fallback.visible = true
end sub
