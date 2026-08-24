sub init()
    m.top.functionName = "PorticoServerCatalogRun"
end sub

sub PorticoServerCatalogRun()
    clock = CreateObject("roTimespan")
    clock.Mark()
    controller = {
        clock: clock,
        lastCommandSequence: 0,
        accountStateInitialized: false,
        accountSignedIn: false,
        accountUserId: "",
        hostedStatus: "unknown",
        credentialGeneration: 0,
        refreshRequestedGeneration: -1,
        servers: [],
        selectedServerId: "",
        durableSelectedServerId: "",
        serverListStatus: "signed-out",
        serverStatus: "not-connected",
        nextLoadAtSeconds: 2147483647,
        loadFailures: 0,
        hostedCompatibility: "unknown",
        hostedCompatibilityCheckedAtSeconds: -1
    }
    PorticoServerCatalogPublish(controller, false)

    while true
        PorticoServerCatalogHandleCommand(controller)
        PorticoServerCatalogTick(controller)
        Sleep(100)
    end while
end sub

sub PorticoServerCatalogHandleCommand(controller as object)
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return
    sequence = PorticoHttpInteger(command.sequence, 0)
    if sequence <= controller.lastCommandSequence then return
    controller.lastCommandSequence = sequence
    kind = PorticoHttpScalarString(command.kind, "")

    if kind = "account-state"
        PorticoServerCatalogApplyAccountState(controller, command)
    else if kind = "refresh-servers"
        if controller.accountSignedIn
            controller.nextLoadAtSeconds = PorticoServerCatalogNowSeconds(controller)
            if controller.servers.count() = 0 then controller.serverListStatus = "loading"
            PorticoServerCatalogPublish(controller, false)
        end if
    else if kind = "select-server"
        PorticoServerCatalogSelect(controller, command.serverId)
    end if
end sub

sub PorticoServerCatalogApplyAccountState(controller as object, command as object)
    signedIn = command.accountSignedIn = true
    hostedStatus = PorticoHttpScalarString(command.hostedStatus, "unknown")
    if hostedStatus <> "online" and hostedStatus <> "offline" and hostedStatus <> "throttled" and hostedStatus <> "incompatible" then hostedStatus = "unknown"

    if not signedIn
        if controller.accountStateInitialized and not controller.accountSignedIn then return
        PorticoServerCatalogReset(controller)
        controller.accountStateInitialized = true
        controller.hostedStatus = hostedStatus
        PorticoSecureRegistryClear("account-server-catalog")
        PorticoServerCatalogPublish(controller, false)
        return
    end if

    credentials = PorticoServerCatalogCredentials()
    if credentials = invalid
        controller.accountStateInitialized = true
        controller.accountSignedIn = false
        controller.hostedStatus = hostedStatus
        controller.serverListStatus = "signed-out"
        controller.nextLoadAtSeconds = 2147483647
        PorticoServerCatalogPublish(controller, false)
        return
    end if

    accountChanged = controller.accountUserId <> credentials.accountUserId
    generationChanged = controller.credentialGeneration <> credentials.generation
    stateChanged = not controller.accountStateInitialized or accountChanged or generationChanged or not controller.accountSignedIn or controller.hostedStatus <> hostedStatus
    if not stateChanged then return
    controller.accountStateInitialized = true
    controller.accountSignedIn = true
    controller.accountUserId = credentials.accountUserId
    controller.credentialGeneration = credentials.generation
    controller.hostedStatus = hostedStatus
    if generationChanged then controller.refreshRequestedGeneration = -1

    if accountChanged
        controller.servers = []
        controller.selectedServerId = ""
        controller.durableSelectedServerId = ""
        controller.serverStatus = "not-connected"
        PorticoServerCatalogRestore(controller)
    end if

    if hostedStatus = "incompatible"
        controller.serverListStatus = "incompatible"
        controller.nextLoadAtSeconds = 2147483647
        PorticoServerCatalogPublish(controller, false)
        return
    end if

    if controller.servers.count() > 0
        controller.serverListStatus = "stale"
    else
        controller.serverListStatus = "loading"
    end if
    controller.nextLoadAtSeconds = PorticoServerCatalogNowSeconds(controller)
    PorticoServerCatalogPublish(controller, false)
end sub

sub PorticoServerCatalogReset(controller as object)
    controller.accountSignedIn = false
    controller.accountUserId = ""
    controller.credentialGeneration = 0
    controller.refreshRequestedGeneration = -1
    controller.servers = []
    controller.selectedServerId = ""
    controller.durableSelectedServerId = ""
    controller.serverListStatus = "signed-out"
    controller.serverStatus = "not-connected"
    controller.nextLoadAtSeconds = 2147483647
    controller.loadFailures = 0
    controller.hostedCompatibility = "unknown"
    controller.hostedCompatibilityCheckedAtSeconds = -1
end sub

sub PorticoServerCatalogTick(controller as object)
    if not controller.accountSignedIn then return
    if PorticoServerCatalogNowSeconds(controller) < controller.nextLoadAtSeconds then return
    controller.nextLoadAtSeconds = 2147483647
    PorticoServerCatalogLoad(controller)
end sub

sub PorticoServerCatalogLoad(controller as object)
    compatibility = PorticoServerCatalogEnsureHostedCompatibility(controller)
    if compatibility = "interrupted"
        PorticoServerCatalogRescheduleInterruptedLoad(controller)
        return
    end if
    if compatibility = "incompatible"
        controller.serverListStatus = "incompatible"
        controller.nextLoadAtSeconds = 2147483647
        PorticoServerCatalogPublish(controller, false)
        return
    end if
    if compatibility <> "compatible"
        PorticoServerCatalogLoadFailed(controller, invalid)
        return
    end if

    credentials = PorticoServerCatalogCredentials()
    if credentials = invalid or credentials.accountUserId <> controller.accountUserId
        PorticoServerCatalogReset(controller)
        PorticoServerCatalogPublish(controller, false)
        return
    end if
    controller.credentialGeneration = credentials.generation

    servers = []
    seenServerIds = {}
    seenCursors = {}
    cursor = ""
    pageCount = 0

    while servers.count() < PorticoServerCatalogMaximumServers()
        url = "https://api.getportico.tv/api/account/servers?limit=100"
        if cursor <> "" then url = url + "&cursor=" + cursor
        result = PorticoServerCatalogHttp(controller, {
            method: "GET",
            url: url,
            body: "",
            headers: { Authorization: "Bearer " + credentials.accessToken },
            timeoutMs: 15000,
            expectJson: true
        })
        if result.interrupted
            PorticoServerCatalogRescheduleInterruptedLoad(controller)
            return
        end if
        if not result.ok
            PorticoServerCatalogHandleLoadFailure(controller, result)
            return
        end if

        page = PorticoServerCatalogPageFromResponse(result.data)
        if page = invalid
            PorticoServerCatalogLoadFailed(controller, invalid)
            return
        end if
        for each server in page.servers
            if seenServerIds[server.id] <> true
                seenServerIds[server.id] = true
                servers.push(server)
            end if
            if servers.count() >= PorticoServerCatalogMaximumServers() then exit for
        end for

        pageCount = pageCount + 1
        if servers.count() >= PorticoServerCatalogMaximumServers() or not page.hasMore then exit while
        if page.nextCursor = "" or seenCursors[page.nextCursor] = true
            PorticoServerCatalogLoadFailed(controller, invalid)
            return
        end if
        seenCursors[page.nextCursor] = true
        cursor = page.nextCursor
        if pageCount >= PorticoServerCatalogMaximumPages()
            PorticoServerCatalogLoadFailed(controller, invalid)
            return
        end if
    end while

    controller.servers = servers
    PorticoServerCatalogReconcileSelection(controller)
    persisted = PorticoServerCatalogPersist(controller)
    if persisted.ok
        controller.durableSelectedServerId = controller.selectedServerId
    else
        PorticoServerCatalogRestoreDurableSelection(controller)
    end if
    controller.serverListStatus = "ready"
    controller.loadFailures = 0
    controller.refreshRequestedGeneration = -1
    ' The directory is a Hosted control-plane feature, not a presence feed.
    ' Reload it only when account state changes or the user explicitly refreshes;
    ' normal browsing and playback stay on the selected Portico Server.
    controller.nextLoadAtSeconds = 2147483647
    PorticoServerCatalogPublish(controller, false)
end sub

sub PorticoServerCatalogHandleLoadFailure(controller as object, result as object)
    if result.status = 401
        requestRefresh = controller.refreshRequestedGeneration <> controller.credentialGeneration
        controller.refreshRequestedGeneration = controller.credentialGeneration
        PorticoServerCatalogLoadFailed(controller, result.retryAfterSeconds)
        PorticoServerCatalogPublish(controller, requestRefresh)
    else if result.status = 403
        controller.serverListStatus = "denied"
        controller.nextLoadAtSeconds = 2147483647
        PorticoServerCatalogPublish(controller, false)
    else
        PorticoServerCatalogLoadFailed(controller, result.retryAfterSeconds)
    end if
end sub

sub PorticoServerCatalogRescheduleInterruptedLoad(controller as object)
    if not controller.accountSignedIn or controller.hostedStatus = "incompatible" then return
    controller.nextLoadAtSeconds = PorticoServerCatalogNowSeconds(controller)
end sub

function PorticoServerCatalogEnsureHostedCompatibility(controller as object) as string
    nowSeconds = PorticoServerCatalogNowSeconds(controller)
    if controller.hostedCompatibilityCheckedAtSeconds >= 0 and nowSeconds - controller.hostedCompatibilityCheckedAtSeconds < 300
        return controller.hostedCompatibility
    end if

    result = PorticoServerCatalogHttp(controller, {
        method: "GET",
        url: "https://api.getportico.tv/api/system",
        body: "",
        headers: {},
        timeoutMs: 10000,
        expectJson: true
    })
    if result.interrupted then return "interrupted"
    if not result.ok
        controller.hostedCompatibility = "unknown"
        controller.hostedCompatibilityCheckedAtSeconds = -1
        return "offline"
    end if
    if not PorticoServerCatalogHostedSystemIsCompatible(result.data)
        controller.hostedCompatibility = "incompatible"
        controller.hostedCompatibilityCheckedAtSeconds = nowSeconds
        return "incompatible"
    end if
    controller.hostedCompatibility = "compatible"
    controller.hostedCompatibilityCheckedAtSeconds = nowSeconds
    return "compatible"
end function

function PorticoServerCatalogHostedSystemIsCompatible(data as dynamic) as boolean
    if data = invalid or Type(data) <> "roAssociativeArray" then return false
    if data.name = invalid or data.name.ToStr() <> "Portico" then return false
    if data.status = invalid or data.status.ToStr() <> "ok" then return false
    if data.apiVersion = invalid or data.apiVersion.ToStr() <> "v1" then return false
    return true
end function

sub PorticoServerCatalogLoadFailed(controller as object, retryAfter as dynamic)
    controller.loadFailures = controller.loadFailures + 1
    if controller.servers.count() > 0
        controller.serverListStatus = "stale"
    else
        controller.serverListStatus = "offline"
    end if
    delay = 15
    exponent = controller.loadFailures
    if exponent > 5 then exponent = 5
    for index = 1 to exponent
        delay = delay * 2
    end for
    if delay > 300 then delay = 300
    if retryAfter <> invalid and retryAfter > delay then delay = retryAfter
    controller.nextLoadAtSeconds = PorticoServerCatalogNowSeconds(controller) + delay
    PorticoServerCatalogPublish(controller, false)
end sub

sub PorticoServerCatalogSelect(controller as object, rawServerId as dynamic)
    if not controller.accountSignedIn then return
    serverId = PorticoServerCatalogSafeId(rawServerId)
    if serverId = "" then return
    selected = invalid
    for each server in controller.servers
        if server.id = serverId
            selected = server
            exit for
        end if
    end for
    if selected = invalid then return
    controller.selectedServerId = serverId
    controller.serverStatus = "selected"
    committed = PorticoServerCatalogPersist(controller)
    if committed.ok
        controller.durableSelectedServerId = controller.selectedServerId
    else
        PorticoServerCatalogRestoreDurableSelection(controller)
    end if
    PorticoServerCatalogPublish(controller, false)
end sub

sub PorticoServerCatalogReconcileSelection(controller as object)
    selectedExists = false
    for each server in controller.servers
        if server.id = controller.selectedServerId then selectedExists = true
    end for
    if not selectedExists then controller.selectedServerId = ""
    if controller.selectedServerId = "" and controller.servers.count() = 1 then controller.selectedServerId = controller.servers[0].id
    if controller.selectedServerId = ""
        controller.serverStatus = "not-connected"
    else
        controller.serverStatus = "selected"
    end if
end sub

sub PorticoServerCatalogRestoreDurableSelection(controller as object)
    controller.selectedServerId = ""
    for each server in controller.servers
        if server.id = controller.durableSelectedServerId
            controller.selectedServerId = controller.durableSelectedServerId
            exit for
        end if
    end for
    if controller.selectedServerId = ""
        controller.serverStatus = "not-connected"
    else
        controller.serverStatus = "selected"
    end if
end sub

sub PorticoServerCatalogRestore(controller as object)
    record = PorticoSecureRegistryRead("account-server-catalog")
    if not record.ok or record.payload = invalid then return
    payload = record.payload
    if payload.version <> 1 then return
    if PorticoServerCatalogSafeId(payload.accountUserId) <> controller.accountUserId then return
    if payload.servers = invalid or GetInterface(payload.servers, "ifArray") = invalid then return
    restored = []
    for each rawServer in payload.servers
        server = PorticoServerCatalogSanitizeServer(rawServer)
        if server <> invalid then restored.push(server)
        if restored.count() >= PorticoServerCatalogMaximumCachedServers() then exit for
    end for
    controller.servers = restored
    controller.selectedServerId = PorticoServerCatalogSafeId(payload.selectedServerId)
    PorticoServerCatalogReconcileSelection(controller)
    controller.durableSelectedServerId = controller.selectedServerId
end sub

function PorticoServerCatalogPersist(controller as object) as object
    if controller.accountUserId = "" then return { ok: false, code: "missing_account", generation: 0 }
    return PorticoSecureRegistryCommit("account-server-catalog", {
        version: 1,
        accountUserId: controller.accountUserId,
        selectedServerId: controller.selectedServerId,
        cachedAt: PorticoServerCatalogUTCNowString(),
        servers: PorticoServerCatalogServersForCache(controller)
    })
end function

function PorticoServerCatalogServersForCache(controller as object) as object
    cached = []
    selected = invalid
    for each server in controller.servers
        if server.id = controller.selectedServerId then selected = server
        if cached.count() < PorticoServerCatalogMaximumCachedServers() then cached.push(server)
    end for
    if selected <> invalid and cached.count() > 0
        selectedCached = false
        for each server in cached
            if server.id = selected.id then selectedCached = true
        end for
        if not selectedCached then cached[PorticoServerCatalogMaximumCachedServers() - 1] = selected
    end if
    return cached
end function

function PorticoServerCatalogCredentials() as dynamic
    record = PorticoSecureRegistryRead("account-credentials")
    if not record.ok or record.payload = invalid then return invalid
    payload = record.payload
    if payload.signedOut = true then return invalid
    if payload.accessToken = invalid or Left(payload.accessToken.ToStr(), 8) <> "ptc_acc_" then return invalid
    if Len(payload.accessToken.ToStr()) < 16 or Len(payload.accessToken.ToStr()) > 4096 then return invalid
    if payload.user = invalid or Type(payload.user) <> "roAssociativeArray" then return invalid
    accountUserId = PorticoServerCatalogSafeId(payload.user.id)
    if accountUserId = "" then return invalid
    return { accessToken: payload.accessToken.ToStr(), accountUserId: accountUserId, generation: record.generation }
end function

function PorticoServerCatalogPageFromResponse(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    if data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    if data.pageInfo = invalid or Type(data.pageInfo) <> "roAssociativeArray" then return invalid
    if Type(data.pageInfo.hasMore) <> "Boolean" then return invalid
    servers = []
    seen = {}
    for each rawServer in data.items
        server = PorticoServerCatalogSanitizeServer(rawServer)
        if server <> invalid and seen[server.id] <> true
            seen[server.id] = true
            servers.push(server)
        end if
        if servers.count() >= 100 then exit for
    end for
    hasMore = data.pageInfo.hasMore = true
    nextCursor = ""
    if data.pageInfo.nextCursor <> invalid
        nextCursor = PorticoServerCatalogSafeCursor(data.pageInfo.nextCursor)
        if nextCursor = "" and hasMore then return invalid
    else if hasMore
        return invalid
    end if
    return { servers: servers, hasMore: hasMore, nextCursor: nextCursor }
end function

function PorticoServerCatalogSafeCursor(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 2048 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoServerCatalogMaximumServers() as integer
    return 500
end function

function PorticoServerCatalogMaximumPages() as integer
    return 5
end function

function PorticoServerCatalogMaximumCachedServers() as integer
    return 100
end function

function PorticoServerCatalogSanitizeServer(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoServerCatalogSafeId(source.id)
    name = PorticoServerCatalogSafeLabel(source.name, "Portico Server", 80)
    if id = "" or name = "" then return invalid
    authMode = LCase(PorticoHttpScalarString(source.preferredAuthMode, "portico"))
    if authMode <> "local" then authMode = "portico"
    availability = LCase(PorticoHttpScalarString(source.availabilityState, "unknown"))
    allowedAvailability = { reported_online: true, offline: true, remote_access_disabled: true, unknown: true }
    if allowedAvailability[availability] <> true then availability = "unknown"
    return {
        id: id,
        name: name,
        preferredAuthMode: authMode,
        remoteAccessEnabled: source.remoteAccessEnabled = true,
        availabilityState: availability
    }
end function

function PorticoServerCatalogSelectedName(controller as object) as string
    for each server in controller.servers
        if server.id = controller.selectedServerId then return server.name
    end for
    return "Portico Server"
end function

sub PorticoServerCatalogPublish(controller as object, accountRefreshRequired as boolean)
    m.top.projection = {
        serverListStatus: controller.serverListStatus,
        availableServers: controller.servers,
        selectedServerId: controller.selectedServerId,
        selectedServerName: PorticoServerCatalogSelectedName(controller),
        serverStatus: controller.serverStatus,
        accountRefreshRequired: accountRefreshRequired
    }
end sub

function PorticoServerCatalogSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoServerCatalogSafeLabel(value as dynamic, fallback as string, maximumLength as integer) as string
    if value = invalid then return fallback
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then return fallback
    if Len(normalized) > maximumLength then normalized = Left(normalized, maximumLength)
    return normalized
end function

function PorticoServerCatalogNowSeconds(controller as object) as integer
    return controller.clock.TotalSeconds()
end function

function PorticoServerCatalogUTCNowString() as string
    now = CreateObject("roDateTime")
    if now = invalid then return ""
    return now.ToISOString()
end function

function PorticoServerCatalogHttp(controller as object, rawRequest as object) as object
    request = PorticoHttpNormalizeRequest(rawRequest)
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoServerCatalogHttpFailure(0, false, validation.code)

    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoServerCatalogHttpFailure(0, true, "transport_error")
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoServerCatalogHttpFailure(0, true, "transport_error")
    if not transfer.EnablePeerVerification(true) then return PorticoServerCatalogHttpFailure(0, true, "transport_error")
    if not transfer.EnableHostVerification(true) then return PorticoServerCatalogHttpFailure(0, true, "transport_error")
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return PorticoServerCatalogHttpFailure(0, false, "invalid_header")
    end for
    if not transfer.AsyncGetToString() then return PorticoServerCatalogHttpFailure(0, true, "transport_error")

    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoServerCatalogInterruptRequested(controller)
            transfer.AsyncCancel()
            return { interrupted: true, ok: false, status: 0, retryable: false, retryAfterSeconds: invalid, data: invalid }
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            return PorticoServerCatalogHttpResult(request, message)
        end if
    end while
    transfer.AsyncCancel()
    return PorticoServerCatalogHttpFailure(0, true, "timeout")
end function

function PorticoServerCatalogInterruptRequested(controller as object) as boolean
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return false
    return PorticoHttpInteger(command.sequence, 0) > controller.lastCommandSequence
end function

function PorticoServerCatalogHttpResult(request as object, event as object) as object
    status = event.GetResponseCode()
    if status < 0 then return PorticoServerCatalogHttpFailure(status, true, "transport_error")
    headers = PorticoHttpResponseHeaders(event.GetResponseHeadersArray())
    retryAfter = PorticoServerCatalogRetryAfterSeconds(headers)
    classification = PorticoHttpClassifyStatus(status)
    payload = event.GetString()
    if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoServerCatalogHttpFailure(status, false, "response_too_large")
    parsed = PorticoHttpParseJson(payload)
    if classification.classification = "success"
        if request.expectJson and not parsed.ok then return PorticoServerCatalogHttpFailure(status, false, "parse_error")
        return { interrupted: false, ok: true, status: status, retryable: false, retryAfterSeconds: retryAfter, data: parsed.value }
    end if
    return { interrupted: false, ok: false, status: status, retryable: classification.retryable, retryAfterSeconds: retryAfter, data: invalid }
end function

function PorticoServerCatalogRetryAfterSeconds(headers as object) as dynamic
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

function PorticoServerCatalogHttpFailure(status as integer, retryable as boolean, code as string) as object
    return { interrupted: false, ok: false, status: status, retryable: retryable, retryAfterSeconds: invalid, data: invalid, code: code }
end function
