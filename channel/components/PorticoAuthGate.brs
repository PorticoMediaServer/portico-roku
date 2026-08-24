sub init()
    m.wordmark = m.top.findNode("wordmark")
    m.eyebrow = m.top.findNode("eyebrow")
    m.title = m.top.findNode("title")
    m.messages = [m.top.findNode("message0"), m.top.findNode("message1")]
    m.verificationUri = m.top.findNode("verificationUri")
    m.codeGroup = m.top.findNode("codeGroup")
    m.codeCharacters = []
    for index = 0 to 8
        character = m.top.findNode("code" + index.ToStr())
        character.font = PorticoFont("700", 96)
        character.color = "#F4F7FA"
        m.codeCharacters.push(character)
    end for
    m.details = [m.top.findNode("detail0"), m.top.findNode("detail1")]
    m.loadingDots = m.top.findNode("loadingDots")
    m.accountTitle = m.top.findNode("accountTitle")
    m.accountMessage = m.top.findNode("accountMessage")
    m.accountOr = m.top.findNode("accountOr")
    m.accountError = m.top.findNode("accountError")
    m.legalNotice = m.top.findNode("legalNotice")
    m.legalUrls = m.top.findNode("legalUrls")
    m.actionsGroup = m.top.findNode("actions")
    m.actions = [m.top.findNode("action0"), m.top.findNode("action1"), m.top.findNode("action2"), m.top.findNode("action3"), m.top.findNode("action4")]

    m.wordmark.uri = "pkg:/images/brand/portico-wordmark.png"
    m.eyebrow.font = PorticoFont("600", 18)
    m.eyebrow.color = "#70BCE8"
    m.title.font = PorticoFont("700", 44)
    m.title.color = "#F4F7FA"
    for each line in m.messages
        line.font = PorticoFont("400", 24)
        line.color = "#C7D0D8"
    end for
    m.verificationUri.font = PorticoFont("600", 30)
    m.verificationUri.color = "#70BCE8"
    for each line in m.details
        line.font = PorticoFont("400", 22)
        line.color = "#8F9BA6"
    end for
    m.loadingDots.font = PorticoFont("600", 38)
    m.loadingDots.color = "#70BCE8"
    m.loadingDots.text = "•••"
    m.accountTitle.font = PorticoFont("700", 42)
    m.accountTitle.color = "#F4F7FA"
    m.accountTitle.text = "Portico Account"
    m.accountMessage.font = PorticoFont("400", 24)
    m.accountMessage.color = "#C7D0D8"
    m.accountMessage.text = "Sign in with your username or email and password."
    m.accountOr.font = PorticoFont("500", 20)
    m.accountOr.color = "#8F9BA6"
    m.accountOr.text = "or"
    m.accountError.font = PorticoFont("500", 20)
    m.accountError.color = "#FF5C77"
    m.legalNotice.font = PorticoFont("400", 18)
    m.legalNotice.color = "#8F9BA6"
    m.legalNotice.text = "By continuing, you agree to Portico's terms and privacy policy."
    m.legalUrls.font = PorticoFont("500", 18)
    m.legalUrls.color = "#70BCE8"
    m.legalUrls.text = "Terms: getportico.tv/terms  •  Privacy: getportico.tv/privacy"

    m.top.focusable = true
    m.focusedAction = 0
    m.activationSequence = 0
    m.stateName = "landing"
    m.actionModels = []
    m.login = ""
    m.password = ""
    m.dialogPurpose = ""
    m.keyboardDialog = invalid
end sub

sub applyViewState()
    model = m.top.viewState
    if model = invalid then return
    m.stateName = PorticoAuthGateState(model.state)
    if model.focusedAction <> invalid then m.focusedAction = PorticoAuthGateInteger(model.focusedAction, m.focusedAction)
    renderAuthGate(model)
end sub

sub renderAuthGate(model as object)
    defaults = PorticoAuthGateDefaults(m.stateName)
    eyebrow = PorticoAuthGateText(model.eyebrow, 48)
    if eyebrow = "" then eyebrow = defaults.eyebrow
    title = PorticoAuthGateText(model.title, 80)
    if title = "" then title = defaults.title
    message = PorticoAuthGateText(model.message, 240)
    if message = "" then message = defaults.message
    detail = PorticoAuthGateText(model.detail, 240)
    if detail = "" then detail = defaults.detail

    m.eyebrow.text = eyebrow
    m.eyebrow.visible = eyebrow <> ""
    m.title.text = title
    PorticoAuthGateApplyLines(m.messages, PorticoBreakText(message, 620, 27, "400", 2))
    m.verificationUri.text = PorticoAuthGateText(model.verificationDisplayUri, 160)
    m.verificationUri.visible = m.stateName = "account-code" and m.verificationUri.text <> ""
    code = PorticoAuthGateText(model.code, 9)
    renderAuthCode(code)
    PorticoAuthGateApplyLines(m.details, PorticoBreakText(detail, 620, 23, "400", 2))
    m.loadingDots.visible = m.stateName = "account-loading" or m.stateName = "local-loading"
    m.accountError.text = PorticoAuthGateText(model.accountSignInError, 180)
    m.accountError.visible = m.accountError.text <> ""

    sourceActions = model.actions
    if sourceActions = invalid or GetInterface(sourceActions, "ifArray") = invalid then sourceActions = defaults.actions
    m.actionModels = PorticoAuthGateActions(sourceActions)
    m.accountOr.visible = false
    if m.focusedAction < 0 then m.focusedAction = 0
    if m.focusedAction >= m.actionModels.count() then m.focusedAction = m.actionModels.count() - 1
    for index = 0 to m.actions.count() - 1
        node = m.actions[index]
        node.visible = false
        node.focused = false
        if index < m.actionModels.count()
            actionModel = m.actionModels[index]
            if actionModel.id = "account-login" and m.login <> "" then actionModel.label = m.login
            if actionModel.id = "account-password" and m.password <> "" then actionModel.label = "Password entered"
            node.model = actionModel
            node.focused = index = m.focusedAction
            if actionModel.id = "start-account-setup"
                node.translation = [240, 752]
            else if actionModel.id = "account-login"
                node.translation = [1120, 470]
            else if actionModel.id = "account-password"
                node.translation = [1120, 558]
            else if actionModel.id = "account-submit"
                node.translation = [1120, 646]
            else if actionModel.id = "start-local-auth"
                node.translation = [1120, 788]
                m.accountOr.visible = true
            else
                rightIndex = index
                if m.actionModels[0].id = "start-account-setup" then rightIndex = index - 1
                node.translation = [1120, 470 + (rightIndex * 88)]
            end if
            node.visible = true
        end if
    end for
    m.actionsGroup.translation = [0, 0]
    publishAuthGateFocus()
end sub

sub renderAuthCode(code as string)
    if m.stateName <> "account-code" then code = ""
    totalWidth = 0
    widths = []
    for index = 0 to m.codeCharacters.count() - 1
        node = m.codeCharacters[index]
        node.text = ""
        node.visible = false
        if index < Len(code)
            glyph = Mid(code, index + 1, 1)
            width = PorticoTextWidth(glyph, "700", 96) + 8
            widths.push(width)
            totalWidth = totalWidth + width
        end if
    end for
    x = 200 + Int((640 - totalWidth) / 2)
    for index = 0 to widths.count() - 1
        node = m.codeCharacters[index]
        node.text = Mid(code, index + 1, 1)
        node.translation = [x, 0]
        node.visible = true
        x = x + widths[index]
    end for
    m.codeGroup.visible = code <> ""
end sub

sub emitAuthGateActivation(action as object)
    m.activationSequence = m.activationSequence + 1
    m.top.activation = {sequence: m.activationSequence, kind: action.id, targetId: action.id, state: m.stateName}
end sub

sub openAccountKeyboard(purpose as string)
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    if dialog = invalid then return
    m.dialogPurpose = purpose
    dialog.buttons = ["Continue", "Cancel"]
    if purpose = "login"
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
    dialog.ObserveFieldScoped("buttonSelected", "onAccountKeyboardButton")
    m.keyboardDialog = dialog
    m.top.GetScene().dialog = dialog
end sub

sub onAccountKeyboardButton()
    dialog = m.keyboardDialog
    if dialog = invalid then return
    accepted = dialog.buttonSelected = 0
    value = dialog.text
    dialog.text = ""
    dialog.UnobserveFieldScoped("buttonSelected")
    m.top.GetScene().dialog = invalid
    m.keyboardDialog = invalid
    if accepted
        if m.dialogPurpose = "login"
            m.login = PorticoAuthGateSecret(value, 320).Trim()
        else
            m.password = PorticoAuthGateSecret(value, 72)
        end if
        renderAuthGate(m.top.viewState)
    end if
    value = ""
    m.dialogPurpose = ""
end sub

sub activateAuthGateAction(action as object)
    if action.id = "account-login"
        openAccountKeyboard("login")
    else if action.id = "account-password"
        openAccountKeyboard("password")
    else if action.id = "account-submit"
        if m.login = "" or m.password = "" then return
        sealed = PorticoAuthGateSeal({login: m.login, password: m.password})
        m.password = ""
        if sealed <> ""
            m.activationSequence = m.activationSequence + 1
            m.top.activation = {sequence: m.activationSequence, kind: "sign-in-account", sealedCredentials: sealed, state: m.stateName}
        end if
        renderAuthGate(m.top.viewState)
    else
        emitAuthGateActivation(action)
    end if
end sub

sub publishAuthGateFocus()
    actionId = ""
    if m.focusedAction >= 0 and m.focusedAction < m.actionModels.count() then actionId = m.actionModels[m.focusedAction].id
    m.top.focusState = {state: m.stateName, focusedAction: m.focusedAction, actionId: actionId}
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "up"
        if m.focusedAction > 0 then m.focusedAction = m.focusedAction - 1
    else if key = "down"
        if m.focusedAction + 1 < m.actionModels.count() then m.focusedAction = m.focusedAction + 1
    else if key = "OK"
        if m.focusedAction >= 0 and m.focusedAction < m.actionModels.count() then activateAuthGateAction(m.actionModels[m.focusedAction])
        return true
    else if key = "back"
        if m.stateName <> "landing"
            emitAuthGateActivation({id: "back-auth-landing"})
            return true
        end if
        return false
    else if key = "left" or key = "right"
        return true
    else
        return false
    end if
    for index = 0 to m.actions.count() - 1
        m.actions[index].focused = index = m.focusedAction and index < m.actionModels.count()
    end for
    publishAuthGateFocus()
    return true
end function

function PorticoAuthGateDefaults(stateName as string) as object
    if stateName = "account-loading"
        return {eyebrow: "", title: "Quick connect", message: "Preparing your sign-in code…", detail: "", actions: [{id: "account-login", label: "Username or email", primary: false}, {id: "account-password", label: "Password", primary: false}, {id: "account-submit", label: "Sign In", primary: true}, {id: "start-local-auth", label: "Sign in directly to a server", primary: false}]}
    else if stateName = "account-code"
        return {eyebrow: "", title: "Quick connect", message: "Open Portico on your phone and enter this code.", detail: "", actions: [{id: "account-login", label: "Username or email", primary: false}, {id: "account-password", label: "Password", primary: false}, {id: "account-submit", label: "Sign In", primary: true}, {id: "start-local-auth", label: "Sign in directly to a server", primary: false}]}
    else if stateName = "account-error"
        return {eyebrow: "", title: "Quick connect unavailable", message: "Portico couldn't create a quick-connect code.", detail: "", actions: [{id: "account-login", label: "Username or email", primary: false}, {id: "account-password", label: "Password", primary: false}, {id: "account-submit", label: "Sign In", primary: true}, {id: "start-local-auth", label: "Sign in directly to a server", primary: false}]}
    else if stateName = "local-loading"
        return {eyebrow: "DIRECT SERVER", title: "Looking for your server", message: "Searching the local network for Portico servers…", detail: "", actions: [{id: "back-auth-landing", label: "Back", primary: false}]}
    else if stateName = "local-error"
        return {eyebrow: "DIRECT SERVER", title: "Server unavailable", message: "No reachable Portico server was found on this local network.", detail: "", actions: [{id: "back-auth-landing", label: "Back", primary: false}]}
    else if stateName = "local"
        return {eyebrow: "DIRECT SERVER", title: "Direct server sign-in", message: "Connect using your server address and server credentials. No Portico Account is used.", detail: "", actions: [{id: "back-auth-landing", label: "Back", primary: false}]}
    end if
    return {eyebrow: "", title: "Quick connect", message: "Preparing your sign-in code…", detail: "", actions: [{id: "account-login", label: "Username or email", primary: false}, {id: "account-password", label: "Password", primary: false}, {id: "account-submit", label: "Sign In", primary: true}, {id: "start-local-auth", label: "Sign in directly to a server", primary: false}]}
end function

function PorticoAuthGateActions(source as object) as object
    result = []
    for each raw in source
        if result.count() >= 5 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoAuthGateId(raw.id)
            label = PorticoAuthGateText(raw.label, 52)
            if id <> "" and label <> "" then result.push({id: id, label: label, primary: raw.primary = true})
        end if
    end for
    return result
end function

function PorticoAuthGateSecret(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), "").Replace(Chr(13), "")
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function

function PorticoAuthGateSeal(value as object) as string
    plaintext = CreateObject("roByteArray")
    crypto = CreateObject("roDeviceCrypto")
    if plaintext = invalid or crypto = invalid then return ""
    plaintext.FromAsciiString(FormatJson(value))
    encrypted = crypto.Encrypt(plaintext, "channel")
    plaintext.Clear()
    if encrypted = invalid then return ""
    return encrypted.ToBase64String()
end function

sub PorticoAuthGateApplyLines(nodes as object, values as object)
    for index = 0 to nodes.count() - 1
        nodes[index].text = ""
        nodes[index].visible = false
        if index < values.count()
            nodes[index].text = values[index]
            nodes[index].visible = true
        end if
    end for
end sub

function PorticoAuthGateState(value as dynamic) as string
    stateName = LCase(PorticoAuthGateText(value, 32))
    allowed = {landing: true, "account-loading": true, "account-code": true, "account-error": true, local: true, "local-loading": true, "local-error": true}
    if allowed[stateName] = true then return stateName
    return "landing"
end function

function PorticoAuthGateId(value as dynamic) as string
    normalized = PorticoAuthGateText(value, 64)
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoAuthGateText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function

function PorticoAuthGateInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" or valueType = "float" or valueType = "rofloat" or valueType = "double" or valueType = "rodouble" then return Int(value)
    return fallback
end function
