function PorticoSignedOutGateModel(runtimeState as dynamic, requestedMode = "landing" as string) as object
    runtime = runtimeState
    if runtime = invalid or Type(runtime) <> "roAssociativeArray" then runtime = {}
    mode = LCase(PorticoSignedOutGateText(requestedMode, "landing", 24))

    if mode = "local"
        localStatus = LCase(PorticoSignedOutGateText(runtime.localAuthStatus, "unavailable", 32))
        localMessage = PorticoSignedOutGateText(runtime.localAuthMessage, "", 240)
        if localStatus = "error" or localStatus = "offline" or localStatus = "unavailable"
            if localMessage = "" then localMessage = "No reachable Portico server was found on this local network."
            return {
                state: "local-error",
                message: localMessage,
                actions: [
                    {id: "back-auth-landing", label: "Back", primary: false}
                ]
            }
        end if
        return {
            state: "local-loading",
            message: localMessage,
            actions: [
                {id: "back-auth-landing", label: "Back", primary: false}
            ]
        }
    end if

    accountStatus = LCase(PorticoSignedOutGateText(runtime.accountStatus, "signed-out", 40))
    accountSignInError = PorticoSignedOutGateText(runtime.accountSignInError, "", 180)
    accountActions = [
        {id: "account-login", label: "Username or email", primary: false},
        {id: "account-password", label: "Password", primary: false},
        {id: "account-submit", label: "Sign In", primary: true},
        {id: "start-local-auth", label: "Sign in directly to a server", primary: false}
    ]
    if mode = "account" or accountStatus = "authorizing"
        code = PorticoSignedOutGateCode(runtime.authorizationUserCode)
        verificationUri = PorticoSignedOutGateText(runtime.verificationDisplayUri, "", 160)
        if accountStatus = "authorizing" and code <> "" and verificationUri <> ""
            return {
                state: "account-code",
                code: code,
                verificationDisplayUri: verificationUri,
                accountSignInError: accountSignInError,
                actions: accountActions
            }
        end if
        if accountStatus = "authorization-denied"
            return PorticoSignedOutGateAccountError("Sign-in wasn't approved", "You can request a new code when you're ready.", accountSignInError, true)
        else if accountStatus = "authorization-expired"
            return PorticoSignedOutGateAccountError("Refreshing your sign-in code", "The previous code expired. Portico will create a new one automatically.", accountSignInError)
        else if accountStatus = "authorization-interrupted"
            return PorticoSignedOutGateAccountError("Refreshing your sign-in code", "That attempt ended before approval. Portico will create a new code automatically.", accountSignInError)
        else if accountStatus = "authorization-unavailable" and LCase(PorticoSignedOutGateText(runtime.hostedStatus, "unknown", 32)) = "incompatible"
            return {
                state: "account-error",
                title: "Update required",
                message: "Portico needs to be updated before you can sign in.",
                accountSignInError: accountSignInError,
                actions: accountActions
            }
        else if accountStatus = "authorization-unavailable" or accountStatus = "account-expired"
            message = PorticoSignedOutGateText(runtime.accountError, "Portico couldn't start account sign-in.", 240)
            return PorticoSignedOutGateAccountError("Sign-in unavailable", message, accountSignInError)
        end if
        hostedStatus = LCase(PorticoSignedOutGateText(runtime.hostedStatus, "unknown", 32))
        loadingTitle = "Quick connect"
        loadingMessage = "Preparing your sign-in code…"
        if hostedStatus = "offline"
            loadingTitle = "Waiting for a connection"
            loadingMessage = "This TV appears to be offline. Portico will try again automatically."
        else if hostedStatus = "online"
            loadingTitle = "Portico Account is unavailable"
            loadingMessage = "The service isn't responding normally. Portico will try again automatically."
        end if
        return {
            state: "account-loading",
            title: loadingTitle,
            message: loadingMessage,
            accountSignInError: accountSignInError,
            actions: accountActions
        }
    end if

    return {
        state: "account-loading",
        accountSignInError: accountSignInError,
        actions: accountActions
    }
end function

function PorticoSignedOutGateAccountError(title as string, message as string, accountSignInError = "" as string, manualRestart = false as boolean) as object
    actions = [
        {id: "account-login", label: "Username or email", primary: false},
        {id: "account-password", label: "Password", primary: false},
        {id: "account-submit", label: "Sign In", primary: true},
        {id: "start-local-auth", label: "Sign in directly to a server", primary: false}
    ]
    if manualRestart
        actions = [
            {id: "start-account-setup", label: "Request New Code", primary: true},
            {id: "account-login", label: "Username or email", primary: false},
            {id: "account-password", label: "Password", primary: false},
            {id: "account-submit", label: "Sign In", primary: true},
            {id: "start-local-auth", label: "Sign in directly to a server", primary: false}
        ]
    end if
    return {
        state: "account-error",
        title: title,
        message: message,
        accountSignInError: accountSignInError,
        actions: actions
    }
end function

function PorticoSignedOutGateCode(value as dynamic) as string
    normalized = UCase(PorticoSignedOutGateText(value, "", 9))
    if Len(normalized) <> 9 or Mid(normalized, 5, 1) <> "-" then return ""
    allowed = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    for position = 1 to Len(normalized)
        glyph = Mid(normalized, position, 1)
        if position = 5
            if glyph <> "-" then return ""
        else if Instr(1, allowed, glyph) = 0
            return ""
        end if
    end for
    return normalized
end function

function PorticoSignedOutGateText(value as dynamic, fallback as string, maximum as integer) as string
    normalized = fallback
    if value <> invalid then normalized = value.ToStr()
    normalized = normalized.Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then normalized = fallback
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function
