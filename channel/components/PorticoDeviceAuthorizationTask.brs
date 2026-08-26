sub init()
    m.top.functionName = "PorticoDeviceAuthorizationRun"
end sub

sub PorticoDeviceAuthorizationRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    controller = {
        clock: clock,
        lastCommandSequence: 0,
        authorizationRequested: false,
        authorizationActive: false,
        renewalPending: false,
        pending: invalid,
        credentials: invalid,
        installationId: PorticoInstallationId(),
        nextAuthorizationAtSeconds: 0,
        authorizationFailures: 0,
        authorizationStartedAtSeconds: -1,
        nextRefreshAtSeconds: 0,
        refreshScheduled: false,
        refreshFailures: 0,
        credentialGeneration: 0,
        last401RefreshGeneration: -1,
        hostedCompatibility: "unknown",
        hostedFailureKind: "unknown",
        hostedCompatibilityCheckedAtSeconds: -1,
        deauthorizationPending: invalid,
        terminalPending: invalid,
        nextDurabilityRetryAtSeconds: 0
    }
    PorticoAuthorizationTaskRestore(controller)

    while true
        PorticoAuthorizationTaskHandleCommand(controller)
        PorticoAuthorizationTaskTick(controller)
        Sleep(100)
    end while
end sub

sub PorticoAuthorizationTaskRestore(controller as object)
    accountRecord = PorticoSecureRegistryRead("account-credentials")
    if not accountRecord.ok
        PorticoAuthorizationTaskPublish("authorization-unavailable", "unknown")
        return
    end if
    if accountRecord.payload = invalid
        PorticoAuthorizationTaskPublish("signed-out", "unknown")
        return
    end if
    if accountRecord.payload.signedOut = true
        PorticoSecureRegistryClear("pending-account-authorization")
        PorticoAuthorizationTaskPublish("signed-out", "unknown")
        return
    end if

    state = PorticoAuthorizationTaskCredentialState(accountRecord.payload)
    if state = "valid" or state = "refresh-only"
        controller.credentials = accountRecord.payload
        controller.credentialGeneration = accountRecord.generation
        PorticoSecureRegistryClear("pending-account-authorization")
        if state = "valid"
            PorticoAuthorizationTaskPublishAccount(controller, "signed-in", "unknown")
            PorticoAuthorizationTaskScheduleRefresh(controller)
        else
            PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", "offline")
            controller.nextRefreshAtSeconds = PorticoAuthorizationTaskNowSeconds(controller)
            controller.refreshScheduled = true
        end if
        return
    end if

    displayName = PorticoAuthorizationTaskDisplayNameFromCredentials(accountRecord.payload)
    if state = "expired"
        PorticoAuthorizationTaskDeauthorize(controller, "account-expired", displayName)
    else
        PorticoAuthorizationTaskDeauthorize(controller, "signed-out", "")
    end if
end sub

sub PorticoAuthorizationTaskHandleCommand(controller as object)
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return
    sequence = PorticoHttpInteger(command.sequence, 0)
    if sequence <= controller.lastCommandSequence then return
    controller.lastCommandSequence = sequence
    kind = PorticoHttpScalarString(command.kind, "")

    if kind = "start-account-setup"
        PorticoAuthorizationTaskStart(controller)
    else if kind = "sign-in-account"
        PorticoAuthorizationTaskSignIn(controller, command.sealedCredentials)
    else if kind = "pause-account-setup"
        PorticoAuthorizationTaskPause(controller)
    else if kind = "sign-out-account"
        PorticoAuthorizationTaskSignOut(controller)
    else if kind = "refresh-account-after-401"
        if controller.credentials <> invalid and controller.last401RefreshGeneration <> controller.credentialGeneration
            controller.last401RefreshGeneration = controller.credentialGeneration
            controller.nextRefreshAtSeconds = PorticoAuthorizationTaskNowSeconds(controller)
            controller.refreshScheduled = true
        end if
    end if
end sub

sub PorticoAuthorizationTaskSignIn(controller as object, sealed as dynamic)
    submitted = PorticoAuthorizationTaskOpenSealedCredentials(sealed)
    if submitted = invalid
        PorticoAuthorizationTaskPublishDirectSignIn("error", "Enter your username or email and password.")
        return
    end if
    login = PorticoHttpScalarString(submitted.login, "").Trim()
    password = PorticoHttpScalarString(submitted.password, "")
    submitted.login = ""
    submitted.password = ""
    if login = "" or Len(login) > 320 or password = "" or Len(password) > 72
        login = ""
        password = ""
        PorticoAuthorizationTaskPublishDirectSignIn("error", "Enter your username or email and password.")
        return
    end if
    controller.authorizationActive = false
    PorticoAuthorizationTaskPublishDirectSignIn("working", "")
    result = PorticoAuthorizationTaskHttp(controller, {
        method: "POST",
        url: "https://api.getportico.tv/api/auth/sessions",
        body: {
            login: login,
            password: password,
            installationId: controller.installationId,
            deviceName: "Portico Roku",
            devicePlatform: "Roku"
        },
        headers: {},
        timeoutMs: 15000,
        expectJson: true
    }, false)
    login = ""
    password = ""
    if result.interrupted then return
    if not result.ok
        code = LCase(PorticoAuthorizationTaskProblemCode(result))
        message = "Portico couldn't sign in. Try again."
        if code = "mfa_required"
            message = "This account uses MFA. Use Quick Connect to sign in securely."
        else if result.status = 401 or code = "invalid_credentials"
            message = "The username or password was not accepted."
        else if result.retryable or result.status = 0
            message = "Portico Account services are unavailable. Try again."
        else if result.problem <> invalid
            detail = PorticoHttpSafeMessage(result.problem.detail, "")
            if detail <> "" then message = detail
        end if
        PorticoAuthorizationTaskPublishDirectSignIn("error", message)
        return
    end if
    credentials = result.data
    if PorticoAuthorizationTaskCredentialState(credentials) <> "valid"
        PorticoAuthorizationTaskPublishDirectSignIn("error", "Portico couldn't verify the new session. Try again.")
        return
    end if
    committed = PorticoSecureRegistryCommit("account-credentials", credentials)
    if not committed.ok
        PorticoAuthorizationTaskPublishDirectSignIn("error", "Portico couldn't save this sign-in. Try again.")
        return
    end if
    PorticoSecureRegistryClear("pending-account-authorization")
    controller.pending = invalid
    controller.credentials = credentials
    controller.authorizationFailures = 0
    controller.refreshFailures = 0
    controller.credentialGeneration = committed.generation
    controller.last401RefreshGeneration = -1
    PorticoAuthorizationTaskPublishDirectSignIn("idle", "")
    PorticoAuthorizationTaskPublishAccount(controller, "signed-in", "online")
    PorticoAuthorizationTaskScheduleRefresh(controller)
end sub

function PorticoAuthorizationTaskOpenSealedCredentials(value as dynamic) as dynamic
    if value = invalid then return invalid
    encoded = value.ToStr().Trim()
    if Len(encoded) < 8 or Len(encoded) > 8192 then return invalid
    encrypted = CreateObject("roByteArray")
    crypto = CreateObject("roDeviceCrypto")
    if encrypted = invalid or crypto = invalid then return invalid
    encrypted.FromBase64String(encoded)
    if encrypted.Count() = 0 then return invalid
    plaintext = crypto.Decrypt(encrypted, "channel")
    if plaintext = invalid then return invalid
    result = ParseJson(plaintext.ToAsciiString())
    plaintext.Clear()
    if result = invalid or Type(result) <> "roAssociativeArray" then return invalid
    return result
end function

sub PorticoAuthorizationTaskPublishDirectSignIn(status as string, message as string)
    m.top.projection = {
        accountSignInStatus: status,
        accountSignInError: PorticoHttpSafeMessage(message, "")
    }
end sub

sub PorticoAuthorizationTaskStart(controller as object)
    controller.authorizationRequested = true
    if controller.authorizationActive then return
    if controller.deauthorizationPending <> invalid or controller.terminalPending <> invalid then return
    credentialState = PorticoAuthorizationTaskCredentialState(controller.credentials)
    if credentialState = "valid"
        PorticoAuthorizationTaskPublishAccount(controller, "signed-in", "unknown")
        PorticoAuthorizationTaskScheduleRefresh(controller)
        return
    else if credentialState = "refresh-only"
        PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", "offline")
        controller.nextRefreshAtSeconds = PorticoAuthorizationTaskNowSeconds(controller)
        controller.refreshScheduled = true
        return
    end if
    controller.authorizationActive = true
    controller.authorizationStartedAtSeconds = PorticoAuthorizationTaskNowSeconds(controller)
    controller.renewalPending = false
    controller.authorizationFailures = 0
    controller.nextAuthorizationAtSeconds = 0
    pendingRecord = PorticoSecureRegistryRead("pending-account-authorization")
    if not pendingRecord.ok
        controller.authorizationActive = false
        PorticoAuthorizationTaskPublish("authorization-unavailable", "unknown")
        return
    end if
    controller.pending = pendingRecord.payload

    if controller.pending <> invalid
        if controller.pending.redemptionStarted = true and PorticoAuthorizationTaskRedemptionRecoveryIsOpen(controller.pending)
            PorticoAuthorizationTaskPublish("authorizing", "connecting")
            controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller)
            return
        end if
        if PorticoAuthorizationTaskPendingIsReusable(controller.pending)
            PorticoAuthorizationTaskPublishPending(controller)
            controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + PorticoAuthorizationTaskInterval(controller.pending.interval)
            PorticoAuthorizationTaskMarkRenewalIfDue(controller)
            return
        end if
        if not PorticoSecureRegistryClear("pending-account-authorization")
            controller.authorizationActive = false
            PorticoAuthorizationTaskPublish("authorization-unavailable", "unknown")
            return
        end if
        controller.pending = invalid
    end if

    PorticoAuthorizationTaskPublish("authorizing", "connecting")
    controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller)
end sub

sub PorticoAuthorizationTaskPause(controller as object)
    controller.authorizationRequested = false
    if not controller.authorizationActive then return
    controller.authorizationActive = false
    if controller.deauthorizationPending <> invalid
        PorticoAuthorizationTaskPublish("authorization-unavailable", "unknown", controller.deauthorizationPending.displayName)
        return
    end if
    if controller.terminalPending <> invalid
        PorticoAuthorizationTaskPublish("authorization-unavailable", "online")
        return
    end if
    if controller.credentials <> invalid
        PorticoAuthorizationTaskPublishAccount(controller, "signed-in", "unknown")
    else
        PorticoAuthorizationTaskPublish("signed-out", "unknown")
    end if
end sub

sub PorticoAuthorizationTaskTick(controller as object)
    nowSeconds = PorticoAuthorizationTaskNowSeconds(controller)
    if controller.deauthorizationPending <> invalid and nowSeconds >= controller.nextDurabilityRetryAtSeconds
        pending = controller.deauthorizationPending
        PorticoAuthorizationTaskDeauthorize(controller, pending.accountStatus, pending.displayName)
        return
    end if
    if controller.terminalPending <> invalid and nowSeconds >= controller.nextDurabilityRetryAtSeconds
        pending = controller.terminalPending
        PorticoAuthorizationTaskTerminal(controller, pending.terminalCode, pending.accountStatus)
        return
    end if
    if controller.authorizationActive and nowSeconds >= controller.nextAuthorizationAtSeconds
        if controller.pending = invalid
            PorticoAuthorizationTaskCreate(controller, false)
        else if controller.pending.redemptionStarted = true
            PorticoAuthorizationTaskRedeem(controller)
        else if controller.renewalPending
            PorticoAuthorizationTaskCreate(controller, true)
        else
            PorticoAuthorizationTaskPoll(controller)
        end if
        return
    end if

    if controller.credentials <> invalid
        credentialState = PorticoAuthorizationTaskCredentialState(controller.credentials)
        if credentialState = "expired" or credentialState = "invalid"
            displayName = PorticoAuthorizationTaskDisplayNameFromCredentials(controller.credentials)
            PorticoAuthorizationTaskDeauthorize(controller, "account-expired", displayName)
        else if controller.refreshScheduled and nowSeconds >= controller.nextRefreshAtSeconds
            PorticoAuthorizationTaskRefresh(controller)
        end if
    end if
end sub

sub PorticoAuthorizationTaskCreate(controller as object, preservePending as boolean)
    if preservePending and not PorticoAuthorizationTaskPendingIsReusable(controller.pending)
        controller.renewalPending = false
        PorticoAuthorizationTaskRenewExpiredSession(controller)
        return
    end if
    if not PorticoAuthorizationTaskEnsureHostedCompatibility(controller, true, false)
        if controller.hostedCompatibility = "incompatible"
            if preservePending
                PorticoAuthorizationTaskScheduleReplacementRetry(controller, "incompatible")
            else
                controller.authorizationActive = false
                PorticoAuthorizationTaskPublish("authorization-unavailable", "incompatible")
            end if
        else
            hostedStatus = "online"
            if controller.hostedFailureKind = "offline" then hostedStatus = "offline"
            if preservePending
                PorticoAuthorizationTaskScheduleReplacementRetry(controller, hostedStatus)
            else
                PorticoAuthorizationTaskPublish("authorizing", PorticoAuthorizationTaskDelayedHostedStatus(controller, hostedStatus))
                PorticoAuthorizationTaskScheduleCreationRetry(controller, invalid)
            end if
        end if
        return
    end if
    createBody = {
        deviceName: "Portico Roku",
        platform: "Roku",
        appVersion: PorticoAuthorizationTaskAppVersion()
    }
    ' The device secret owns this authorization. Installation identity is only
    ' optional display/continuity metadata and may be absent or later rotate.
    if controller.installationId <> "" then createBody.installationId = controller.installationId
    result = PorticoAuthorizationTaskHttp(controller, {
        method: "POST",
        url: "https://api.getportico.tv/api/device-authorization/sessions",
        body: createBody,
        headers: {},
        timeoutMs: 15000,
        expectJson: true
    }, true)
    if result.interrupted then return
    if not result.ok
        if result.retryable or result.status = 0
            hostedStatus = "online"
            if result.status = 0 then hostedStatus = "offline"
            if preservePending
                PorticoAuthorizationTaskScheduleReplacementRetry(controller, hostedStatus)
            else
                PorticoAuthorizationTaskPublish("authorizing", PorticoAuthorizationTaskDelayedHostedStatus(controller, hostedStatus))
                PorticoAuthorizationTaskScheduleCreationRetry(controller, result.retryAfterSeconds)
            end if
        else
            if preservePending
                PorticoAuthorizationTaskScheduleReplacementRetry(controller, "online")
            else
                controller.authorizationActive = false
                PorticoAuthorizationTaskPublish("authorization-unavailable", "online")
            end if
        end if
        return
    end if

    pending = PorticoAuthorizationTaskPendingFromCreate(result.data)
    if pending = invalid
        if preservePending
            PorticoAuthorizationTaskScheduleReplacementRetry(controller, "online")
        else
            controller.authorizationActive = false
            PorticoAuthorizationTaskPublish("authorization-unavailable", "online")
        end if
        return
    end if
    committed = PorticoSecureRegistryCommit("pending-account-authorization", pending)
    if not committed.ok
        if preservePending
            PorticoAuthorizationTaskScheduleReplacementRetry(controller, "online")
        else
            controller.authorizationActive = false
            PorticoAuthorizationTaskPublish("authorization-unavailable", "online")
        end if
        return
    end if
    controller.pending = pending
    controller.authorizationStartedAtSeconds = -1
    controller.renewalPending = false
    controller.authorizationFailures = 0
    PorticoAuthorizationTaskPublishPending(controller)
    controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + pending.interval
end sub

function PorticoAuthorizationTaskDelayedHostedStatus(controller as object, hostedStatus as string) as string
    if hostedStatus = "incompatible" then return hostedStatus
    startedAt = PorticoHttpInteger(controller.authorizationStartedAtSeconds, -1)
    if startedAt < 0 then return "connecting"
    if PorticoAuthorizationTaskNowSeconds(controller) - startedAt < 8 then return "connecting"
    return hostedStatus
end function

sub PorticoAuthorizationTaskPoll(controller as object)
    remaining = PorticoAuthorizationTaskSecondsUntil(controller.pending.expiresAt)
    if remaining = invalid or remaining <= 0
        PorticoAuthorizationTaskRenewExpiredSession(controller)
        return
    end if
    if not PorticoAuthorizationTaskEnsureHostedCompatibility(controller, true, true)
        controller.authorizationActive = false
        return
    end if
    result = PorticoAuthorizationTaskHttp(controller, {
        method: "GET",
        url: "https://api.getportico.tv/api/device-authorization/sessions/" + controller.pending.authorizationSessionId,
        body: "",
        headers: { "X-Portico-Device-Code": controller.pending.deviceCode },
        timeoutMs: 15000,
        expectJson: true
    }, true)
    if result.interrupted then return
    if result.ok
        PorticoAuthorizationTaskHandleApproved(controller, result.data)
        return
    end if

    problemCode = PorticoAuthorizationTaskProblemCode(result)
    if problemCode = "authorization_pending"
        controller.authorizationFailures = 0
        interval = PorticoAuthorizationTaskInterval(controller.pending.interval)
        if result.retryAfterSeconds <> invalid and result.retryAfterSeconds > interval then interval = result.retryAfterSeconds
        if interval <> controller.pending.interval
            controller.pending.interval = interval
            if not PorticoSecureRegistryCommit("pending-account-authorization", controller.pending).ok
                controller.authorizationActive = false
                PorticoAuthorizationTaskPublish("authorization-unavailable", "online")
                return
            end if
        end if
        controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + interval
        PorticoAuthorizationTaskMarkRenewalIfDue(controller)
    else if problemCode = "slow_down"
        controller.authorizationFailures = 0
        interval = PorticoAuthorizationTaskInterval(controller.pending.interval) + 5
        if result.retryAfterSeconds <> invalid and result.retryAfterSeconds > interval then interval = result.retryAfterSeconds
        controller.pending.interval = interval
        if not PorticoSecureRegistryCommit("pending-account-authorization", controller.pending).ok
            controller.authorizationActive = false
            PorticoAuthorizationTaskPublish("authorization-unavailable", "online")
            return
        end if
        controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + interval
        PorticoAuthorizationTaskMarkRenewalIfDue(controller)
    else if problemCode = "access_denied"
        PorticoAuthorizationTaskTerminal(controller, problemCode, "authorization-denied")
    else if problemCode = "expired_token"
        PorticoAuthorizationTaskRenewExpiredSession(controller)
    else if result.retryable
        PorticoAuthorizationTaskScheduleAuthorizationRetry(controller, result.retryAfterSeconds)
    else
        PorticoAuthorizationTaskTerminal(controller, "authorization_failed", "authorization-interrupted")
    end if
end sub

sub PorticoAuthorizationTaskRenewExpiredSession(controller as object)
    if not PorticoSecureRegistryClear("pending-account-authorization")
        PorticoAuthorizationTaskTerminal(controller, "expired_token", "authorization-expired")
        return
    end if
    controller.pending = invalid
    controller.renewalPending = false
    controller.authorizationActive = true
    controller.authorizationFailures = 0
    controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + 5
    PorticoAuthorizationTaskPublish("authorizing", "connecting")
end sub

sub PorticoAuthorizationTaskHandleApproved(controller as object, data as dynamic)
    if not PorticoAuthorizationTaskApprovedIsValid(data, controller.pending)
        PorticoAuthorizationTaskTerminal(controller, "invalid_approval_response", "authorization-interrupted")
        return
    end if
    interval = PorticoAuthorizationTaskInterval(data.interval)
    if interval > controller.pending.interval then controller.pending.interval = interval
    controller.pending.redemptionStarted = true
    controller.renewalPending = false
    controller.pending.redemptionStartedAt = PorticoAuthorizationTaskUTCNowString()
    if controller.pending.redemptionStartedAt = "" or not PorticoSecureRegistryCommit("pending-account-authorization", controller.pending).ok
        controller.authorizationActive = false
        PorticoAuthorizationTaskPublish("authorization-interrupted", "online")
        return
    end if
    PorticoAuthorizationTaskPublish("authorizing", "connecting")
    controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller)
end sub

sub PorticoAuthorizationTaskRedeem(controller as object)
    if not PorticoAuthorizationTaskRedemptionRecoveryIsOpen(controller.pending)
        PorticoAuthorizationTaskTerminal(controller, "redemption_recovery_expired", "authorization-interrupted")
        return
    end if
    if not PorticoAuthorizationTaskEnsureHostedCompatibility(controller, false, true)
        controller.authorizationActive = false
        return
    end if
    result = PorticoAuthorizationTaskHttp(controller, {
        method: "POST",
        url: "https://api.getportico.tv/api/device-authorization/sessions/" + controller.pending.authorizationSessionId + "/redeem",
        body: "",
        headers: { "X-Portico-Device-Code": controller.pending.deviceCode },
        timeoutMs: 15000,
        expectJson: true
    }, false)
    if result.interrupted then return
    if not result.ok
        problemCode = PorticoAuthorizationTaskProblemCode(result)
        if problemCode = "access_denied" or problemCode = "expired_token"
            PorticoAuthorizationTaskTerminal(controller, problemCode, "authorization-interrupted")
        else if result.retryable
            PorticoAuthorizationTaskScheduleAuthorizationRetry(controller, result.retryAfterSeconds)
            PorticoAuthorizationTaskPublish("authorizing", "offline")
        else
            PorticoAuthorizationTaskTerminal(controller, "redemption_failed", "authorization-interrupted")
        end if
        return
    end if

    credentials = PorticoAuthorizationTaskRedeemedCredentials(result.data)
    if credentials = invalid
        controller.authorizationActive = false
        PorticoAuthorizationTaskPublish("authorization-interrupted", "online")
        return
    end if
    committed = PorticoSecureRegistryCommit("account-credentials", credentials)
    if not committed.ok
        controller.authorizationActive = false
        PorticoAuthorizationTaskPublish("authorization-interrupted", "online")
        return
    end if
    PorticoSecureRegistryClear("pending-account-authorization")
    controller.pending = invalid
    controller.renewalPending = false
    controller.credentials = credentials
    controller.authorizationActive = false
    controller.authorizationFailures = 0
    controller.refreshFailures = 0
    controller.credentialGeneration = committed.generation
    controller.last401RefreshGeneration = -1
    PorticoAuthorizationTaskPublishAccount(controller, "signed-in", "online")
    PorticoAuthorizationTaskScheduleRefresh(controller)
end sub

sub PorticoAuthorizationTaskRefresh(controller as object)
    state = PorticoAuthorizationTaskCredentialState(controller.credentials)
    if state = "expired" or state = "invalid"
        displayName = PorticoAuthorizationTaskDisplayNameFromCredentials(controller.credentials)
        PorticoAuthorizationTaskDeauthorize(controller, "account-expired", displayName)
        return
    end if
    if not PorticoAuthorizationTaskEnsureHostedCompatibility(controller, false, true)
        PorticoAuthorizationTaskScheduleRefreshRetry(controller, invalid)
        return
    end if
    previous = controller.credentials
    rotation = PorticoAuthorizationTaskPendingRotation(previous)
    if rotation = invalid
        PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", "offline")
        PorticoAuthorizationTaskScheduleRefreshRetry(controller, invalid)
        return
    end if
    result = PorticoAuthorizationTaskHttp(controller, {
        method: "POST",
        url: "https://api.getportico.tv/api/auth/sessions/refresh",
        body: { refreshToken: previous.refreshToken, rotationKey: rotation.rotationKey },
        headers: {},
        timeoutMs: 15000,
        expectJson: true
    }, false)
    if result.interrupted then return
    if result.ok
        replacement = PorticoAuthorizationTaskRefreshCredentials(result.data, previous)
        if replacement = invalid
            PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", "offline")
            PorticoAuthorizationTaskScheduleRefreshRetry(controller, invalid)
            return
        end if
        committed = PorticoSecureRegistryCommit("account-credentials", replacement)
        if not committed.ok
            PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", "offline")
            PorticoAuthorizationTaskScheduleRefreshRetry(controller, invalid)
            return
        end if
        controller.credentials = replacement
        controller.credentialGeneration = committed.generation
        PorticoSecureRegistryClear("account-refresh-rotation")
        controller.refreshFailures = 0
        PorticoAuthorizationTaskPublishAccount(controller, "signed-in", "online")
        PorticoAuthorizationTaskScheduleRefresh(controller)
        return
    end if

    problemCode = PorticoAuthorizationTaskProblemCode(result)
    if PorticoAuthorizationTaskRefreshFailureIsTerminal(problemCode)
        PorticoSecureRegistryClear("account-refresh-rotation")
        displayName = PorticoAuthorizationTaskDisplayNameFromCredentials(previous)
        PorticoAuthorizationTaskDeauthorize(controller, "account-expired", displayName)
    else
        PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", "offline")
        PorticoAuthorizationTaskScheduleRefreshRetry(controller, result.retryAfterSeconds)
    end if
end sub

function PorticoAuthorizationTaskPendingRotation(credentials as dynamic) as dynamic
    if credentials = invalid or Type(credentials) <> "roAssociativeArray" then return invalid
    refreshToken = PorticoHttpScalarString(credentials.refreshToken, "")
    if refreshToken = "" then return invalid
    existing = PorticoSecureRegistryRead("account-refresh-rotation")
    if existing.ok and existing.payload <> invalid and Type(existing.payload) = "roAssociativeArray"
        if existing.payload.refreshToken = refreshToken and Len(PorticoHttpScalarString(existing.payload.rotationKey, "")) >= 43 then return existing.payload
    end if
    rotationKey = PorticoSecureRegistryRotationKey()
    if rotationKey = "" then return invalid
    pending = {version: 1, purpose: "crash-safe-refresh-rotation", refreshToken: refreshToken, rotationKey: rotationKey}
    if not PorticoSecureRegistryCommit("account-refresh-rotation", pending).ok then return invalid
    return pending
end function

function PorticoAuthorizationTaskRefreshFailureIsTerminal(problemCode as dynamic) as boolean
    code = LCase(PorticoHttpScalarString(problemCode, ""))
    return code = "invalid_refresh_token" or code = "refresh_token_reuse" or code = "account_revoked" or code = "session_revoked"
end function

sub PorticoAuthorizationTaskSignOut(controller as object)
    refreshToken = ""
    if controller.credentials <> invalid and controller.credentials.refreshToken <> invalid
        refreshToken = controller.credentials.refreshToken.ToStr()
    end if
    tombstone = {
        version: 1,
        signedOut: true,
        signedOutAt: PorticoAuthorizationTaskUTCNowString()
    }
    committed = PorticoSecureRegistryCommit("account-credentials", tombstone)
    durable = committed.ok
    if not durable then durable = PorticoSecureRegistryClear("account-credentials")
    if not durable
        PorticoAuthorizationTaskPublish("authorization-unavailable", "unknown")
        return
    end if

    PorticoSecureRegistryClear("pending-account-authorization")
    controller.authorizationActive = false
    controller.pending = invalid
    controller.renewalPending = false
    controller.credentials = invalid
    controller.credentialGeneration = 0
    controller.nextRefreshAtSeconds = 0
    controller.refreshScheduled = false
    controller.last401RefreshGeneration = -1
    controller.deauthorizationPending = invalid
    controller.terminalPending = invalid
    PorticoSecureRegistryClear("account-refresh-rotation")
    PorticoAuthorizationTaskPublish("signed-out", "unknown")

    if refreshToken <> ""
        if not PorticoAuthorizationTaskEnsureHostedCompatibility(controller, false, false) then return
        PorticoAuthorizationTaskHttp(controller, {
            method: "POST",
            url: "https://api.getportico.tv/api/auth/sessions/revoke",
            body: { refreshToken: refreshToken },
            headers: {},
            timeoutMs: 8000,
            expectJson: true
        }, false)
    end if
end sub

function PorticoAuthorizationTaskEnsureHostedCompatibility(controller as object, interruptOnPause as boolean, publishFailure as boolean) as boolean
    nowSeconds = PorticoAuthorizationTaskNowSeconds(controller)
    if controller.hostedCompatibilityCheckedAtSeconds >= 0 and nowSeconds - controller.hostedCompatibilityCheckedAtSeconds < 300
        if controller.hostedCompatibility = "compatible" then return true
        if controller.hostedCompatibility = "incompatible"
            if publishFailure
                if controller.credentials <> invalid
                    PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", "incompatible")
                else
                    PorticoAuthorizationTaskPublish("authorization-unavailable", "incompatible")
                end if
            end if
            return false
        end if
    end if

    result = PorticoAuthorizationTaskHttp(controller, {
        method: "GET",
        url: "https://api.getportico.tv/api/system",
        body: "",
        headers: {},
        timeoutMs: 10000,
        expectJson: true
    }, interruptOnPause)
    if result.interrupted then return false
    if not result.ok
        controller.hostedCompatibility = "unknown"
        controller.hostedFailureKind = "service"
        if result.status = 0 then controller.hostedFailureKind = "offline"
        controller.hostedCompatibilityCheckedAtSeconds = -1
        if publishFailure
            hostedStatus = "online"
            if controller.hostedFailureKind = "offline" then hostedStatus = "offline"
            if controller.credentials <> invalid
                PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", hostedStatus)
            else
                PorticoAuthorizationTaskPublish("authorization-unavailable", hostedStatus)
            end if
        end if
        return false
    end if
    if not PorticoAuthorizationTaskHostedSystemIsCompatible(result.data)
        controller.hostedCompatibility = "incompatible"
        controller.hostedCompatibilityCheckedAtSeconds = nowSeconds
        if publishFailure
            if controller.credentials <> invalid
                PorticoAuthorizationTaskPublishAccount(controller, "hosted-unavailable", "incompatible")
            else
                PorticoAuthorizationTaskPublish("authorization-unavailable", "incompatible")
            end if
        end if
        return false
    end if
    controller.hostedCompatibility = "compatible"
    controller.hostedFailureKind = "none"
    controller.hostedCompatibilityCheckedAtSeconds = nowSeconds
    return true
end function

function PorticoAuthorizationTaskHostedSystemIsCompatible(data as dynamic) as boolean
    if data = invalid or Type(data) <> "roAssociativeArray" then return false
    if data.name = invalid or data.name.ToStr() <> "Portico" then return false
    if data.status = invalid or data.status.ToStr() <> "ok" then return false
    if data.apiVersion = invalid or data.apiVersion.ToStr() <> "v1" then return false
    return true
end function

sub PorticoAuthorizationTaskDeauthorize(controller as object, accountStatus as string, displayName as string)
    tombstone = {
        version: 1,
        signedOut: true,
        signedOutAt: PorticoAuthorizationTaskUTCNowString()
    }
    committed = PorticoSecureRegistryCommit("account-credentials", tombstone)
    durable = committed.ok
    if not durable then durable = PorticoSecureRegistryClear("account-credentials")
    if not durable
        controller.authorizationActive = false
        controller.deauthorizationPending = { accountStatus: accountStatus, displayName: displayName }
        controller.nextDurabilityRetryAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + 5
        controller.nextRefreshAtSeconds = 0
        controller.refreshScheduled = false
        PorticoAuthorizationTaskPublish("authorization-unavailable", "unknown", displayName)
        return
    end if

    PorticoSecureRegistryClear("pending-account-authorization")
    controller.authorizationActive = false
    controller.deauthorizationPending = invalid
    controller.pending = invalid
    controller.credentials = invalid
    controller.credentialGeneration = 0
    controller.nextRefreshAtSeconds = 0
    controller.refreshScheduled = false
    controller.last401RefreshGeneration = -1
    PorticoSecureRegistryClear("account-refresh-rotation")
    PorticoAuthorizationTaskPublish(accountStatus, "unknown", displayName)
end sub

sub PorticoAuthorizationTaskTerminal(controller as object, terminalCode as string, accountStatus as string)
    controller.renewalPending = false
    selfHealing = accountStatus = "authorization-expired" or accountStatus = "authorization-interrupted"
    if controller.pending <> invalid
        terminalPending = {}
        for each key in controller.pending
            terminalPending[key] = controller.pending[key]
        end for
        terminalPending.terminalCode = terminalCode
        committed = PorticoSecureRegistryCommit("pending-account-authorization", terminalPending)
        durable = committed.ok
        if not durable then durable = PorticoSecureRegistryClear("pending-account-authorization")
        if not durable
            controller.authorizationActive = false
            controller.pending = terminalPending
            controller.terminalPending = { terminalCode: terminalCode, accountStatus: accountStatus }
            controller.nextDurabilityRetryAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + 5
            PorticoAuthorizationTaskPublish("authorization-unavailable", "online")
            return
        end if
        if committed.ok
            controller.pending = terminalPending
        else
            controller.pending = invalid
        end if
    end if
    controller.authorizationActive = false
    controller.terminalPending = invalid
    if selfHealing
        if controller.pending <> invalid and not PorticoSecureRegistryClear("pending-account-authorization")
            controller.terminalPending = { terminalCode: terminalCode, accountStatus: accountStatus }
            controller.nextDurabilityRetryAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + 5
            if controller.authorizationRequested
                PorticoAuthorizationTaskPublish("authorizing", "connecting")
            else
                PorticoAuthorizationTaskPublish("signed-out", "unknown")
            end if
            return
        end if
        controller.pending = invalid
        controller.authorizationFailures = 0
        if not controller.authorizationRequested
            PorticoAuthorizationTaskPublish("signed-out", "unknown")
            return
        end if
        controller.authorizationActive = true
        controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + 5
        PorticoAuthorizationTaskPublish("authorizing", "connecting")
        return
    end if
    PorticoAuthorizationTaskPublish(accountStatus, "online")
end sub

sub PorticoAuthorizationTaskScheduleAuthorizationRetry(controller as object, retryAfter as dynamic)
    if controller.pending = invalid
        controller.authorizationActive = false
        PorticoAuthorizationTaskPublish("authorization-unavailable", "offline")
        return
    end if
    controller.authorizationFailures = controller.authorizationFailures + 1
    delay = 5
    if retryAfter <> invalid and retryAfter > delay then delay = retryAfter
    controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + delay
    PorticoAuthorizationTaskMarkRenewalIfDue(controller)
end sub

sub PorticoAuthorizationTaskScheduleReplacementRetry(controller as object, hostedStatus as string)
    controller.renewalPending = false
    if not PorticoAuthorizationTaskPendingIsReusable(controller.pending)
        PorticoAuthorizationTaskRenewExpiredSession(controller)
        return
    end if
    PorticoAuthorizationTaskPublishPending(controller, hostedStatus)
    controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + 5
    if hostedStatus = "incompatible" then controller.renewalPending = true
end sub

sub PorticoAuthorizationTaskMarkRenewalIfDue(controller as object)
    if controller.pending = invalid then return
    remaining = PorticoAuthorizationTaskSecondsUntil(controller.pending.expiresAt)
    if remaining = invalid or remaining <= 0 then return
    nowSeconds = PorticoAuthorizationTaskNowSeconds(controller)
    renewalAtSeconds = nowSeconds
    if remaining > 30 then renewalAtSeconds = nowSeconds + remaining - 30
    ' A large Hosted retry interval must not carry the old display past its
    ' renewal boundary. Wake for replacement without issuing an early poll.
    if controller.nextAuthorizationAtSeconds >= renewalAtSeconds
        controller.nextAuthorizationAtSeconds = renewalAtSeconds
        controller.renewalPending = true
    end if
end sub

sub PorticoAuthorizationTaskScheduleCreationRetry(controller as object, retryAfter as dynamic)
    controller.authorizationFailures = controller.authorizationFailures + 1
    delay = 5
    if retryAfter <> invalid and retryAfter > delay then delay = retryAfter
    controller.nextAuthorizationAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + delay
end sub

sub PorticoAuthorizationTaskScheduleRefresh(controller as object)
    remaining = PorticoAuthorizationTaskSecondsUntil(controller.credentials.accessExpiresAt)
    if remaining = invalid
        controller.nextRefreshAtSeconds = PorticoAuthorizationTaskNowSeconds(controller)
        controller.refreshScheduled = true
        return
    end if
    delay = remaining - 300
    if delay < 5 then delay = 5
    controller.nextRefreshAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + delay
    controller.refreshScheduled = true
end sub

sub PorticoAuthorizationTaskScheduleRefreshRetry(controller as object, retryAfter as dynamic)
    controller.refreshFailures = controller.refreshFailures + 1
    exponent = controller.refreshFailures
    if exponent > 5 then exponent = 5
    delay = 5
    for index = 1 to exponent
        delay = delay * 2
    end for
    if delay > 300 then delay = 300
    if retryAfter <> invalid and retryAfter > delay then delay = retryAfter
    controller.nextRefreshAtSeconds = PorticoAuthorizationTaskNowSeconds(controller) + delay
    controller.refreshScheduled = true
end sub

sub PorticoAuthorizationTaskPublishPending(controller as object, hostedStatus = "online" as string)
    displayUri = PorticoAuthorizationTaskVerificationDisplayUri(controller.pending.verificationUri)
    PorticoAuthorizationTaskPublish("authorizing", hostedStatus, "", controller.pending.userCode, displayUri)
end sub

sub PorticoAuthorizationTaskPublishAccount(controller as object, accountStatus as string, hostedStatus as string)
    displayName = PorticoAuthorizationTaskDisplayNameFromCredentials(controller.credentials)
    PorticoAuthorizationTaskPublish(accountStatus, hostedStatus, displayName, "", "", controller.credentials <> invalid)
end sub

sub PorticoAuthorizationTaskPublish(accountStatus as string, hostedStatus as string, accountDisplayName = "" as string, authorizationUserCode = "" as string, verificationDisplayUri = "" as string, credentialsDurable = false as boolean)
    m.top.projection = {
        accountStatus: accountStatus,
        hostedStatus: hostedStatus,
        accountDisplayName: accountDisplayName,
        authorizationUserCode: authorizationUserCode,
        verificationDisplayUri: verificationDisplayUri,
        credentialsDurable: credentialsDurable
    }
end sub

function PorticoAuthorizationTaskHttp(controller as object, rawRequest as object, interruptOnPause as boolean) as object
    request = PorticoHttpNormalizeRequest(rawRequest)
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoAuthorizationTaskHttpFailure(0, false, validation.code)

    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoAuthorizationTaskHttpFailure(0, true, "transport_error")
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if Left(LCase(request.url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoAuthorizationTaskHttpFailure(0, true, "transport_error")
        if not transfer.EnablePeerVerification(true) then return PorticoAuthorizationTaskHttpFailure(0, true, "transport_error")
        if not transfer.EnableHostVerification(true) then return PorticoAuthorizationTaskHttpFailure(0, true, "transport_error")
    end if
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return PorticoAuthorizationTaskHttpFailure(0, false, "invalid_header")
    end for
    issued = PorticoAuthorizationTaskIssueTransfer(transfer, request.method, request.body)
    if not issued then return PorticoAuthorizationTaskHttpFailure(0, true, "transport_error")

    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoAuthorizationTaskInterruptRequested(controller, interruptOnPause)
            transfer.AsyncCancel()
            return { interrupted: true, ok: false, status: 0, retryable: false, retryAfterSeconds: invalid, data: invalid, problem: invalid }
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            return PorticoAuthorizationTaskHttpResult(request, message)
        end if
    end while
    transfer.AsyncCancel()
    return PorticoAuthorizationTaskHttpFailure(0, true, "timeout")
end function

function PorticoAuthorizationTaskInterruptRequested(controller as object, interruptOnPause as boolean) as boolean
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return false
    sequence = PorticoHttpInteger(command.sequence, 0)
    if sequence <= controller.lastCommandSequence then return false
    kind = PorticoHttpScalarString(command.kind, "")
    if kind = "sign-out-account" then return true
    if kind = "sign-in-account" then return true
    return interruptOnPause and kind = "pause-account-setup"
end function

function PorticoAuthorizationTaskIssueTransfer(transfer as object, method as string, body as string) as boolean
    if method = "HEAD" then return transfer.AsyncHead()
    if body <> "" or method = "POST" or method = "PUT" or method = "PATCH" then return transfer.AsyncPostFromString(body)
    return transfer.AsyncGetToString()
end function

function PorticoAuthorizationTaskHttpResult(request as object, event as object) as object
    status = event.GetResponseCode()
    if status < 0 then return PorticoAuthorizationTaskHttpFailure(status, true, "transport_error")
    headers = PorticoHttpResponseHeaders(event.GetResponseHeadersArray())
    retryAfter = PorticoAuthorizationTaskRetryAfterSeconds(headers)
    classification = PorticoHttpClassifyStatus(status)
    payload = event.GetString()
    if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoAuthorizationTaskHttpFailure(status, false, "response_too_large")
    parsed = PorticoHttpParseJson(payload)
    if classification.classification = "success"
        if request.expectJson and not parsed.ok then return PorticoAuthorizationTaskHttpFailure(status, false, "parse_error")
        return { interrupted: false, ok: true, status: status, retryable: false, retryAfterSeconds: retryAfter, data: parsed.value, problem: invalid }
    end if
    payload = invalid
    if parsed.ok then payload = parsed.value
    problem = PorticoHttpNormalizeProblem(status, payload, headers, request.requestId, classification.classification)
    return { interrupted: false, ok: false, status: status, retryable: classification.retryable, retryAfterSeconds: retryAfter, data: invalid, problem: problem }
end function

function PorticoAuthorizationTaskRetryAfterSeconds(headers as object) as dynamic
    value = PorticoHttpScalarString(headers["retry-after"], "").Trim()
    if value = "" then return invalid
    for position = 1 to Len(value)
        if Instr(1, "0123456789", Mid(value, position, 1)) = 0 then return invalid
    end for
    seconds = Int(Val(value))
    if seconds < 0 then return invalid
    if seconds > 86400 then seconds = 86400
    return seconds
end function

function PorticoAuthorizationTaskHttpFailure(status as integer, retryable as boolean, code as string) as object
    return {
        interrupted: false,
        ok: false,
        status: status,
        retryable: retryable,
        retryAfterSeconds: invalid,
        data: invalid,
        problem: { code: code }
    }
end function

function PorticoAuthorizationTaskProblemCode(result as object) as string
    if result.problem = invalid or result.problem.code = invalid then return ""
    return result.problem.code.ToStr()
end function

function PorticoAuthorizationTaskPendingFromCreate(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    if data.status = invalid or data.status.ToStr() <> "pending" then return invalid
    if not PorticoAuthorizationTaskSessionIdIsValid(data.authorizationSessionId) then return invalid
    if not PorticoAuthorizationTaskDeviceCodeIsValid(data.deviceCode) then return invalid
    if not PorticoAuthorizationTaskUserCodeIsValid(data.userCode) then return invalid
    if PorticoAuthorizationTaskVerificationDisplayUri(data.verificationUri) = "" then return invalid
    if not PorticoAuthorizationTaskPendingLifetimeIsValid(data.expiresAt) then return invalid
    return {
        version: 1,
        authorizationSessionId: data.authorizationSessionId.ToStr(),
        deviceCode: data.deviceCode.ToStr(),
        userCode: data.userCode.ToStr(),
        verificationUri: data.verificationUri.ToStr(),
        expiresAt: data.expiresAt.ToStr(),
        interval: PorticoAuthorizationTaskInterval(data.interval),
        terminalCode: "",
        redemptionStarted: false,
        redemptionStartedAt: ""
    }
end function

function PorticoAuthorizationTaskPendingIsReusable(pending as dynamic) as boolean
    if pending = invalid or Type(pending) <> "roAssociativeArray" then return false
    if pending.version <> 1 then return false
    if pending.redemptionStarted = true then return false
    if pending.terminalCode <> invalid and pending.terminalCode.ToStr() <> "" then return false
    if not PorticoAuthorizationTaskSessionIdIsValid(pending.authorizationSessionId) then return false
    if not PorticoAuthorizationTaskDeviceCodeIsValid(pending.deviceCode) then return false
    if not PorticoAuthorizationTaskUserCodeIsValid(pending.userCode) then return false
    if PorticoAuthorizationTaskVerificationDisplayUri(pending.verificationUri) = "" then return false
    return PorticoAuthorizationTaskUTCIsFuture(pending.expiresAt)
end function

function PorticoAuthorizationTaskApprovedIsValid(data as dynamic, pending as dynamic) as boolean
    if data = invalid or pending = invalid or Type(data) <> "roAssociativeArray" then return false
    if data.status = invalid or data.status.ToStr() <> "approved" then return false
    if data.authorizationSessionId = invalid or data.authorizationSessionId.ToStr() <> pending.authorizationSessionId then return false
    return PorticoAuthorizationTaskUTCIsFuture(data.expiresAt)
end function

function PorticoAuthorizationTaskRedeemedCredentials(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    if data.status = invalid or data.status.ToStr() <> "redeemed" then return invalid
    if PorticoAuthorizationTaskCredentialState(data.accountCredentials) <> "valid" then return invalid
    return data.accountCredentials
end function

function PorticoAuthorizationTaskRefreshCredentials(data as dynamic, previous as object) as dynamic
    if PorticoAuthorizationTaskCredentialState(data) <> "valid" then return invalid
    if data.user.id.ToStr() <> previous.user.id.ToStr() then return invalid
    if data.device.id.ToStr() <> previous.device.id.ToStr() then return invalid
    if data.device.userId.ToStr() <> previous.device.userId.ToStr() then return invalid
    return data
end function

function PorticoAuthorizationTaskCredentialState(credentials as dynamic) as string
    if credentials = invalid or Type(credentials) <> "roAssociativeArray" then return "invalid"
    if credentials.signedOut = true then return "signed-out"
    if credentials.tokenType = invalid or LCase(credentials.tokenType.ToStr()) <> "bearer" then return "invalid"
    if credentials.accessToken = invalid or Left(credentials.accessToken.ToStr(), 8) <> "ptc_acc_" then return "invalid"
    if Len(credentials.accessToken.ToStr()) < 16 or Len(credentials.accessToken.ToStr()) > 4096 then return "invalid"
    if credentials.refreshToken = invalid or Left(credentials.refreshToken.ToStr(), 8) <> "ptc_rft_" then return "invalid"
    if Len(credentials.refreshToken.ToStr()) < 16 or Len(credentials.refreshToken.ToStr()) > 4096 then return "invalid"
    if credentials.user = invalid or Type(credentials.user) <> "roAssociativeArray" then return "invalid"
    if credentials.device = invalid or Type(credentials.device) <> "roAssociativeArray" then return "invalid"
    if credentials.user.id = invalid or credentials.user.id.ToStr() = "" or Len(credentials.user.id.ToStr()) > 128 then return "invalid"
    if credentials.user.displayName = invalid or credentials.user.displayName.ToStr() = "" or Len(credentials.user.displayName.ToStr()) > 512 then return "invalid"
    if credentials.device.id = invalid or credentials.device.id.ToStr() = "" or Len(credentials.device.id.ToStr()) > 128 then return "invalid"
    if credentials.device.userId = invalid or credentials.device.userId.ToStr() <> credentials.user.id.ToStr() then return "invalid"
    accessRemaining = PorticoAuthorizationTaskSecondsUntil(credentials.accessExpiresAt)
    refreshRemaining = PorticoAuthorizationTaskSecondsUntil(credentials.refreshExpiresAt)
    if accessRemaining = invalid or refreshRemaining = invalid then return "invalid"
    if refreshRemaining <= accessRemaining then return "invalid"
    if refreshRemaining <= 0 then return "expired"
    if accessRemaining <= 0 then return "refresh-only"
    return "valid"
end function

function PorticoAuthorizationTaskSessionIdIsValid(value as dynamic) as boolean
    if value = invalid then return false
    normalized = value.ToStr()
    if Len(normalized) < 1 or Len(normalized) > 128 then return false
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return false
    end for
    return true
end function

function PorticoAuthorizationTaskDeviceCodeIsValid(value as dynamic) as boolean
    if value = invalid then return false
    normalized = value.ToStr()
    if Len(normalized) <> 43 then return false
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return false
    end for
    return true
end function

function PorticoAuthorizationTaskUserCodeIsValid(value as dynamic) as boolean
    if value = invalid then return false
    normalized = value.ToStr()
    if Len(normalized) <> 9 or Mid(normalized, 5, 1) <> "-" then return false
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    for position = 1 to Len(normalized)
        if position <> 5 and Instr(1, alphabet, Mid(normalized, position, 1)) = 0 then return false
    end for
    return true
end function

function PorticoAuthorizationTaskVerificationDisplayUri(value as dynamic) as string
    if value = invalid then return ""
    if value.ToStr().Trim() <> "https://web.getportico.tv/authorize-device" then return ""
    return "web.getportico.tv/authorize-device"
end function

function PorticoAuthorizationTaskPendingLifetimeIsValid(value as dynamic) as boolean
    remaining = PorticoAuthorizationTaskSecondsUntil(value)
    if remaining = invalid then return false
    ' Hosted's generic device ticket contract is ten minutes. Allow bounded
    ' transport and clock skew without accepting the retired short lifetime.
    return remaining >= 540 and remaining <= 630
end function

function PorticoAuthorizationTaskInterval(value as dynamic) as integer
    interval = 5
    if value <> invalid then interval = Int(Val(value.ToStr()))
    if interval < 5 then interval = 5
    if interval > 300 then interval = 300
    return interval
end function

function PorticoAuthorizationTaskUTCNormalize(value as dynamic) as string
    if value = invalid then return ""
    source = value.ToStr().Trim()
    if Len(source) < 20 then return ""
    if Mid(source, 5, 1) <> "-" or Mid(source, 8, 1) <> "-" or Mid(source, 11, 1) <> "T" then return ""
    if Mid(source, 14, 1) <> ":" or Mid(source, 17, 1) <> ":" then return ""
    for each position in [1, 2, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18, 19]
        if Instr(1, "0123456789", Mid(source, position, 1)) = 0 then return ""
    end for
    year = Int(Val(Left(source, 4)))
    month = Int(Val(Mid(source, 6, 2)))
    day = Int(Val(Mid(source, 9, 2)))
    hour = Int(Val(Mid(source, 12, 2)))
    minute = Int(Val(Mid(source, 15, 2)))
    second = Int(Val(Mid(source, 18, 2)))
    if year < 2000 or year > 2100 or month < 1 or month > 12 then return ""
    if day < 1 or day > PorticoAuthorizationTaskDaysInMonth(year, month) then return ""
    if hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 59 then return ""

    suffixStart = 20
    fraction = ""
    if Mid(source, suffixStart, 1) = "."
        fractionStart = suffixStart + 1
        suffixStart = fractionStart
        while suffixStart <= Len(source) and Instr(1, "0123456789", Mid(source, suffixStart, 1)) > 0
            suffixStart = suffixStart + 1
        end while
        fraction = Mid(source, fractionStart, suffixStart - fractionStart)
        if Len(fraction) < 1 or Len(fraction) > 9 then return ""
    end if
    suffix = Mid(source, suffixStart)
    if suffix <> "Z" and suffix <> "z" and suffix <> "+00:00" and suffix <> "+0000" then return ""
    normalized = Left(source, 19)
    if fraction <> ""
        while Len(fraction) < 3
            fraction = fraction + "0"
        end while
        normalized = normalized + "." + Left(fraction, 3)
    end if
    return normalized
end function

function PorticoAuthorizationTaskDaysInMonth(year as integer, month as integer) as integer
    if month = 2
        leap = (year mod 4 = 0 and year mod 100 <> 0) or year mod 400 = 0
        if leap then return 29
        return 28
    end if
    if month = 4 or month = 6 or month = 9 or month = 11 then return 30
    return 31
end function

function PorticoAuthorizationTaskSecondsUntil(value as dynamic) as dynamic
    normalized = PorticoAuthorizationTaskUTCNormalize(value)
    if normalized = "" then return invalid
    timespan = CreateObject("roTimespan")
    if timespan = invalid then return invalid
    return timespan.GetSecondsToISO8601Date(normalized)
end function

function PorticoAuthorizationTaskUTCIsFuture(value as dynamic) as boolean
    remaining = PorticoAuthorizationTaskSecondsUntil(value)
    if remaining = invalid then return false
    return remaining > 0
end function

function PorticoAuthorizationTaskUTCNowString() as string
    now = CreateObject("roDateTime")
    if now = invalid then return ""
    normalized = PorticoAuthorizationTaskUTCNormalize(now.ToISOString())
    if normalized = "" then return ""
    return normalized + "Z"
end function

function PorticoAuthorizationTaskRedemptionRecoveryIsOpen(pending as dynamic) as boolean
    if pending = invalid or pending.redemptionStarted <> true then return false
    if pending.terminalCode <> invalid and pending.terminalCode.ToStr() <> "" then return false
    remaining = PorticoAuthorizationTaskSecondsUntil(pending.redemptionStartedAt)
    if remaining = invalid then return false
    elapsed = -remaining
    return elapsed >= 0 and elapsed < 300
end function

function PorticoAuthorizationTaskDisplayNameFromCredentials(credentials as dynamic) as string
    if credentials = invalid or credentials.user = invalid then return "Your Portico Account"
    return PorticoAuthorizationTaskSafeDisplayName(credentials.user.displayName)
end function

function PorticoAuthorizationTaskSafeDisplayName(value as dynamic) as string
    if value = invalid then return "Your Portico Account"
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then return "Your Portico Account"
    if Len(normalized) > 80 then normalized = Left(normalized, 80)
    return normalized
end function

function PorticoAuthorizationTaskNowSeconds(controller as object) as integer
    return controller.clock.TotalSeconds()
end function

function PorticoAuthorizationTaskAppVersion() as string
    appInfo = CreateObject("roAppInfo")
    if appInfo <> invalid
        version = appInfo.GetVersion()
        if version <> invalid and version.ToStr().Trim() <> "" then return Left(version.ToStr().Trim(), 80)
    end if
    return "0.2.0"
end function
