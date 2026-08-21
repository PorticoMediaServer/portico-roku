sub init()
    m.wordmark = m.top.FindNode("wordmark")
    m.title = m.top.FindNode("title")
    m.messages = [m.top.FindNode("message0"), m.top.FindNode("message1")]
    m.identity = m.top.FindNode("identity")
    m.fingerprint = m.top.FindNode("fingerprint")
    m.loading = m.top.FindNode("loading")
    m.actions = []
    for index = 0 to 6
        m.actions.Push(m.top.FindNode("action" + index.ToStr()))
    end for
    m.wordmark.uri = "pkg:/images/brand/portico-wordmark.png"
    m.title.font = PorticoFont("700", 48)
    m.title.color = "#F4F7FA"
    for each label in m.messages
        label.font = PorticoFont("400", 24)
        label.color = "#C7D0D8"
    end for
    m.identity.font = PorticoFont("600", 22)
    m.identity.color = "#F4F7FA"
    m.fingerprint.font = PorticoFont("600", 25)
    m.fingerprint.color = "#70BCE8"
    m.loading.font = PorticoFont("600", 38)
    m.loading.color = "#70BCE8"
    m.loading.text = "•••"
    m.top.focusable = true
    m.focusedAction = 0
    m.actionModels = []
    m.activationSequence = 0
    m.login = ""
    m.password = ""
    m.manualAddress = ""
    m.dialogPurpose = ""
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or Type(state) <> "roAssociativeArray" then state = {}
    m.stateName = LCase(PorticoLocalAuthScreenText(state.localAuthStatus, "idle", 40))
    if m.stateName = "signed-out" or m.stateName = "authenticated"
        m.login = ""
        m.password = ""
        m.manualAddress = ""
    end if
    selectedKey = PorticoLocalAuthScreenId(state.selectedLocalServerId)
    if m.selectedKey <> invalid and m.selectedKey <> "" and selectedKey <> "" and selectedKey <> m.selectedKey
        m.login = ""
        m.password = ""
    end if
    if selectedKey <> "" then m.selectedKey = selectedKey
    model = PorticoLocalAuthScreenModel(state, m.login <> "", m.password <> "", m.manualAddress <> "")
    renderLocalAuth(model)
end sub

sub renderLocalAuth(model as object)
    m.title.text = model.title
    PorticoLocalAuthScreenLines(m.messages, PorticoBreakText(model.message, 1040, 24, "400", 2))
    m.identity.text = model.identity
    m.identity.visible = model.identity <> ""
    m.fingerprint.text = model.fingerprint
    m.fingerprint.visible = model.fingerprint <> ""
    m.loading.visible = model.loading = true
    m.actionModels = model.actions
    if m.focusedAction < 0 then m.focusedAction = 0
    if m.focusedAction >= m.actionModels.Count() then m.focusedAction = m.actionModels.Count() - 1
    if m.focusedAction < 0 then m.focusedAction = 0
    for index = 0 to m.actions.Count() - 1
        node = m.actions[index]
        node.visible = false
        node.focused = false
        if index < m.actionModels.Count()
            node.model = m.actionModels[index]
            node.focused = index = m.focusedAction
            node.visible = true
        end if
    end for
    publishLocalFocus()
end sub

function PorticoLocalAuthScreenModel(state as object, hasLogin as boolean, hasPassword as boolean, hasAddress as boolean) as object
    status = LCase(PorticoLocalAuthScreenText(state.localAuthStatus, "idle", 40))
    message = PorticoLocalAuthScreenText(state.localAuthMessage, "", 240)
    selectedName = PorticoLocalAuthScreenText(state.selectedLocalServerName, "", 80)
    if selectedName = "" and PorticoLocalAuthScreenId(state.selectedLocalServerId) <> "" then selectedName = "Portico Server"
    address = PorticoLocalAuthScreenText(state.selectedLocalServerAddress, "", 120)
    fingerprint = PorticoLocalAuthScreenText(state.selectedLocalServerFingerprintDisplay, "", 40)
    back = {id: "local-back", label: "Back", primary: false}
    manual = {id: "local-manual", label: "Enter Server Address", primary: false}
    if hasAddress then manual.label = "Change Server Address"
    retry = {id: "local-discover", label: "Search Again", primary: true}
    if status = "discovering"
        return {title: "Server Only Authentication", message: "Looking for Portico servers on this network…", identity: "", fingerprint: "", loading: true, actions: [manual, back]}
    else if status = "servers"
        actions = []
        servers = state.nearbyServers
        if servers <> invalid and GetInterface(servers, "ifArray") <> invalid
            for each server in servers
                if actions.Count() >= 4 then exit for
                id = PorticoLocalAuthScreenId(server.id)
                name = PorticoLocalAuthScreenText(server.name, "Portico Server", 80)
                if id <> "" then actions.Push({id: "local-server-" + id, targetId: id, label: name, primary: actions.Count() = 0})
            end for
        end if
        actions.Push(manual)
        actions.Push(retry)
        actions.Push(back)
        return {title: "Server Only Authentication", message: "Choose your Portico Server.", identity: "", fingerprint: "", loading: false, actions: actions}
    else if status = "checking-server" or status = "restoring" or status = "signing-in"
        title = "Connecting"
        if status = "signing-in" then title = "Signing in"
        return {title: title, message: message, identity: selectedName, fingerprint: "", loading: true, actions: [back]}
    else if status = "confirm-trust"
        identity = selectedName
        if address <> "" then identity = identity + "  ·  " + address
        return {title: "Confirm Server", message: message, identity: identity, fingerprint: fingerprint, loading: false, actions: [{id: "local-confirm-trust", label: "Trust This Server", primary: true}, back]}
    else if status = "credentials" or status = "credentials-error"
        loginLabel = "Username or Email"
        if hasLogin then loginLabel = "Change Username or Email"
        passwordLabel = "Password"
        if hasPassword then passwordLabel = "Change Password"
        actions = [{id: "local-login", label: loginLabel, primary: false}, {id: "local-password", label: passwordLabel, primary: false}]
        if hasLogin and hasPassword then actions.Push({id: "local-submit", label: "Sign In", primary: true})
        actions.Push(back)
        if message = "" then message = "Sign in with a local profile on " + selectedName + "."
        return {title: "Server Only Authentication", message: message, identity: selectedName, fingerprint: "", loading: false, actions: actions}
    else if status = "idle" or status = "signed-out"
        return {title: "Server Only Authentication", message: "Connect directly to a Portico Server with a local profile.", identity: "", fingerprint: "", loading: false, actions: [{id: "local-discover", label: "Find Nearby Servers", primary: true}, manual, back]}
    else if status = "authenticated"
        return {title: "Connected", message: "", identity: PorticoLocalAuthScreenText(state.localAuthServerName, "Portico Server", 80), fingerprint: "", loading: false, actions: []}
    end if
    if message = "" then message = "Portico couldn't authenticate with this server."
    if state.localAuthHasSession = true
        return {title: PorticoLocalAuthScreenErrorTitle(status), message: message, identity: selectedName, fingerprint: "", loading: false, actions: [{id: "local-retry-session", label: "Try Again", primary: true}, back]}
    end if
    return {title: PorticoLocalAuthScreenErrorTitle(status), message: message, identity: selectedName, fingerprint: "", loading: false, actions: [retry, manual, back]}
end function

function PorticoLocalAuthScreenErrorTitle(status as string) as string
    if status = "identity-error" or status = "identity-changed" then return "Server Identity Changed"
    if status = "server-incompatible" then return "Update Required"
    if status = "local-auth-disabled" then return "Server Only Authentication Unavailable"
    if status = "secure-route-required" or status = "secure-route-unavailable" then return "Secure Connection Required"
    if status = "storage-error" then return "Sign-in Not Saved"
    if status = "session-expired" then return "Sign In Again"
    if status = "no-servers" then return "No Servers Found"
    return "Server Unavailable"
end function

sub openLocalKeyboard(purpose as string)
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    if dialog = invalid then return
    m.dialogPurpose = purpose
    dialog.buttons = ["Continue", "Cancel"]
    if purpose = "address"
        dialog.title = "Server Address"
        dialog.message = ["Enter the HTTPS address of your Portico Server."]
        dialog.keyboardDomain = "generic"
        dialog.text = m.manualAddress
        dialog.textEditBox.maxTextLength = 320
    else if purpose = "login"
        dialog.title = "Username or Email"
        dialog.keyboardDomain = "email"
        dialog.text = m.login
        dialog.textEditBox.maxTextLength = 320
    else
        dialog.title = "Password"
        dialog.keyboardDomain = "password"
        dialog.text = ""
        dialog.textEditBox.maxTextLength = 72
        dialog.textEditBox.secureMode = true
    end if
    dialog.ObserveFieldScoped("buttonSelected", "onLocalKeyboardButton")
    m.keyboardDialog = dialog
    m.top.GetScene().dialog = dialog
end sub

sub onLocalKeyboardButton()
    dialog = m.keyboardDialog
    if dialog = invalid then return
    accepted = dialog.buttonSelected = 0
    value = dialog.text
    dialog.text = ""
    dialog.UnobserveFieldScoped("buttonSelected")
    m.top.GetScene().dialog = invalid
    m.keyboardDialog = invalid
    if accepted
        if m.dialogPurpose = "address"
            m.manualAddress = PorticoLocalAuthScreenSecret(value, 320)
            if m.manualAddress <> "" then emitLocalActivation("local-manual-address", {address: m.manualAddress})
        else if m.dialogPurpose = "login"
            m.login = PorticoLocalAuthScreenSecret(value, 320).Trim()
            applyViewState()
        else if m.dialogPurpose = "password"
            m.password = PorticoLocalAuthScreenSecret(value, 72)
            applyViewState()
        end if
    end if
    value = ""
    m.dialogPurpose = ""
end sub

sub activateLocalAction(action as object)
    id = action.id
    if Left(id, 13) = "local-server-"
        emitLocalActivation("local-select-server", {serverKey: action.targetId})
    else if id = "local-manual"
        openLocalKeyboard("address")
    else if id = "local-login"
        openLocalKeyboard("login")
    else if id = "local-password"
        openLocalKeyboard("password")
    else if id = "local-submit"
        sealed = PorticoLocalAuthScreenSeal({login: m.login, password: m.password})
        m.password = ""
        if sealed <> "" then emitLocalActivation("local-submit-credentials", {sealedCredentials: sealed})
        applyViewState()
    else if id = "local-back"
        m.login = ""
        m.password = ""
        m.manualAddress = ""
        emitLocalActivation(id, invalid)
    else
        emitLocalActivation(id, invalid)
    end if
end sub

sub emitLocalActivation(kind as string, extra as dynamic)
    m.activationSequence = m.activationSequence + 1
    event = {sequence: m.activationSequence, kind: kind}
    if extra <> invalid and Type(extra) = "roAssociativeArray"
        for each key in extra
            event[key] = extra[key]
        end for
    end if
    m.top.activation = event
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "up"
        if m.focusedAction > 0 then m.focusedAction = m.focusedAction - 1
    else if key = "down"
        if m.focusedAction + 1 < m.actionModels.Count() then m.focusedAction = m.focusedAction + 1
    else if key = "OK"
        if m.focusedAction >= 0 and m.focusedAction < m.actionModels.Count() then activateLocalAction(m.actionModels[m.focusedAction])
        return true
    else if key = "back"
        emitLocalActivation("local-back", invalid)
        return true
    else if key = "left" or key = "right"
        return true
    else
        return false
    end if
    for index = 0 to m.actions.Count() - 1
        m.actions[index].focused = index = m.focusedAction and index < m.actionModels.Count()
    end for
    publishLocalFocus()
    return true
end function

sub publishLocalFocus()
    actionId = ""
    if m.focusedAction >= 0 and m.focusedAction < m.actionModels.Count() then actionId = m.actionModels[m.focusedAction].id
    m.top.focusState = {state: m.stateName, focusedAction: m.focusedAction, actionId: actionId}
end sub

function PorticoLocalAuthScreenSeal(value as object) as string
    plaintext = CreateObject("roByteArray")
    crypto = CreateObject("roDeviceCrypto")
    if plaintext = invalid or crypto = invalid then return ""
    plaintext.FromAsciiString(FormatJson(value))
    encrypted = crypto.Encrypt(plaintext, "channel")
    plaintext.Clear()
    if encrypted = invalid then return ""
    return encrypted.ToBase64String()
end function

sub PorticoLocalAuthScreenLines(nodes as object, values as object)
    for index = 0 to nodes.Count() - 1
        nodes[index].text = ""
        nodes[index].visible = false
        if index < values.Count()
            nodes[index].text = values[index]
            nodes[index].visible = true
        end if
    end for
end sub

function PorticoLocalAuthScreenText(value as dynamic, fallback as string, maximum as integer) as string
    normalized = fallback
    if value <> invalid then normalized = value.ToStr()
    normalized = normalized.Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then normalized = fallback
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function

function PorticoLocalAuthScreenSecret(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    normalized = value.ToStr()
    if Len(normalized) > maximum or Instr(1, normalized, Chr(0)) > 0 or Instr(1, normalized, Chr(10)) > 0 or Instr(1, normalized, Chr(13)) > 0 then return ""
    return normalized
end function

function PorticoLocalAuthScreenId(value as dynamic) as string
    normalized = PorticoLocalAuthScreenText(value, "", 64)
    if normalized = "" then return ""
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function
