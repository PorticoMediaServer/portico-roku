sub init()
    m.title = m.top.findNode("title")
    m.body = m.top.findNode("body")
    m.link = m.top.findNode("link")
    m.privacy = m.top.findNode("privacy")
    m.done = m.top.findNode("done")
    m.title.font = PorticoFont("700", 40)
    m.title.color = "#F4F7FA"
    m.body.font = PorticoFont("400", 21)
    m.body.color = "#C7D0D8"
    m.link.font = PorticoFont("700", 28)
    m.link.color = "#F4F7FA"
    m.privacy.font = PorticoFont("400", 17)
    m.privacy.color = "#8F9BA6"
    m.title.text = "Continue on another device"
    m.body.text = "Open this secure link on a phone or computer, then sign in to manage your password, two-factor authentication, and devices."
    m.link.text = "app.getportico.tv/settings/account"
    m.privacy.text = "Your Portico Account credentials stay private."
    m.done.model = {label: "Done", iconId: "action.confirm", width: 232, primary: true}
    m.sequence = 0
    m.top.focusable = true
    render()
end sub

sub render()
    m.top.visible = m.top.open
    m.done.focused = m.top.open
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press or not m.top.open then return false
    if key = "OK" or key = "back"
        m.sequence = m.sequence + 1
        m.top.activation = {sequence: m.sequence, kind: "close-account-security"}
        return true
    end if
    return true
end function
