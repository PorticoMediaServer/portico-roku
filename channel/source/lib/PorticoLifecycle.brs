function PorticoLifecycleController(args as dynamic) as object
    stored = PorticoLifecycleReadNavigation()
    pendingRecord = PorticoLifecycleReadPendingDeepLink()
    pendingLaunch = PorticoLifecycleParseDeepLink(args)
    pendingFromStorage = false
    persistAtStartup = false
    registryCorrupt = stored.storageError = true or pendingRecord.storageError = true
    if pendingRecord.expired = true and not registryCorrupt
        if not PorticoSecureRegistryClear("pending-deep-link") then registryCorrupt = true
    end if
    if pendingLaunch = invalid and not registryCorrupt and pendingRecord.request <> invalid
        pendingLaunch = pendingRecord.request
        pendingFromStorage = true
    end if
    if pendingLaunch = invalid and not registryCorrupt and stored.route <> ""
        pendingLaunch = {
            kind: "route",
            route: stored.route,
            selectedServerId: stored.selectedServerId,
            origin: "restore"
        }
        persistAtStartup = true
    end if
    controller = {
        pendingLaunch: pendingLaunch,
        pendingRestore: invalid,
        pendingIntentId: pendingRecord.intentId,
        deliveryId: "",
        deliveryKind: "",
        deliveryInFlight: false,
        deliveryAttempts: 0,
        deliveryAcknowledgedId: "",
        registryCorrupt: registryCorrupt,
        requestSequence: 0,
        intentSequence: 0,
        serverPickerRequested: false,
        launchComplete: false,
        appDialogOpen: false,
        awaitingLaunchSurface: "",
        lastSignedIn: false,
        lastPersistedRoute: stored.route,
        lastPersistedServerId: stored.selectedServerId
    }
    if not pendingFromStorage and not registryCorrupt and pendingLaunch <> invalid and (PorticoLifecycleParseDeepLink(args) <> invalid or persistAtStartup)
        if not PorticoLifecyclePersistPendingDeepLink(controller, pendingLaunch) then controller.registryCorrupt = true
    end if
    return controller
end function

sub PorticoLifecycleAcceptInput(controller as object, inputInfo as dynamic)
    request = PorticoLifecycleParseDeepLink(inputInfo)
    if request = invalid then return
    if controller.registryCorrupt then return
    if PorticoLifecyclePersistPendingDeepLink(controller, request)
        controller.pendingRestore = invalid
        controller.serverPickerRequested = false
    end if
end sub

sub PorticoLifecycleUpdateBeacons(controller as object, scene as object, activation as dynamic)
    if controller = invalid or scene = invalid then return
    state = scene.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" then return

    signedIn = PorticoLifecycleSignedIn(state)
    if controller.lastSignedIn and not signedIn then PorticoLifecycleClearNavigation(controller)
    controller.lastSignedIn = signedIn
    if controller.launchComplete then return

    if not signedIn
        if not controller.appDialogOpen and PorticoLifecycleAccountStateSettled(state)
            scene.signalBeacon("AppDialogInitiate")
            controller.appDialogOpen = true
        end if
        return
    end if

    if controller.appDialogOpen
        scene.signalBeacon("AppDialogComplete")
        controller.appDialogOpen = false
    end if
    if controller.pendingLaunch <> invalid
        ' A semantic deep link can remain queued while an already-published
        ' viewer is offline. The usable offline shell is still the completed
        ' launch surface; keep the destination queued for reconnect without
        ' withholding Roku's launch-complete beacon indefinitely.
        pendingKind = LCase(PorticoLifecycleText(controller.pendingLaunch.kind, "", 32))
        serverStatus = LCase(PorticoLifecycleText(state.serverStatus, "", 40))
        if PorticoLifecycleViewerActive(state) and pendingKind <> "route" and serverStatus <> "online"
            PorticoLifecycleCompleteLaunch(controller, scene)
        end if
        return
    end if
    if controller.pendingRestore <> invalid then return

    if controller.awaitingLaunchSurface = "player"
        if activation <> invalid and Type(activation) = "roAssociativeArray"
            kind = LCase(PorticoLifecycleText(activation.kind, "", 32))
            playerState = LCase(PorticoLifecycleText(activation.state, "", 32))
            if kind = "player-state" and (playerState = "playing" or playerState = "paused")
                PorticoLifecycleCompleteLaunch(controller, scene)
                return
            end if
        end if
        playback = state.playbackViewState
        if playback <> invalid and Type(playback) = "roAssociativeArray"
            status = LCase(PorticoLifecycleText(playback.playbackStatus, "", 32))
            if status = "error" or status = "offline" or status = "ended" then PorticoLifecycleCompleteLaunch(controller, scene)
        end if
        return
    end if

    if controller.awaitingLaunchSurface = "detail"
        status = LCase(PorticoLifecycleText(state.detailStatus, "", 32))
        if status = "ready" or status = "stale" or status = "not-found" or status = "permission-removed" or status = "incompatible" or status = "unavailable" or status = "error"
            PorticoLifecycleCompleteLaunch(controller, scene)
        end if
        return
    end if

    PorticoLifecycleCompleteLaunch(controller, scene)
end sub

sub PorticoLifecycleCompleteLaunch(controller as object, scene as object)
    if controller.launchComplete then return
    scene.signalBeacon("AppLaunchComplete")
    controller.launchComplete = true
    controller.awaitingLaunchSurface = ""
end sub

sub PorticoLifecycleReconcile(controller as object, scene as object)
    if controller = invalid or scene = invalid then return
    state = scene.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" then return
    if controller.registryCorrupt then return
    if not PorticoLifecycleSignedIn(state) then return

    if controller.pendingLaunch <> invalid
        request = controller.pendingLaunch
        expected = {}
        if PorticoLifecycleSafeId(request.selectedServerId) <> "" then expected.serverId = PorticoLifecycleSafeId(request.selectedServerId)
        if PorticoLifecycleSafeId(request.profileId) <> "" then expected.profileId = PorticoLifecycleSafeId(request.profileId)
        gate = PorticoLifecycleViewerPublicationGate(state, expected)
        if gate.kind = "fail-closed"
            controller.registryCorrupt = true
            return
        end if
        if gate.kind <> "ready"
            if gate.gate = "server" and PorticoLifecycleSafeId(state.selectedServerId) = "" and not controller.serverPickerRequested and PorticoLifecycleServerListSettled(state)
                if PorticoLifecycleDispatch(controller, scene, {kind: "route", route: "server-selection", origin: "deep-link"}, state, "gate")
                    controller.serverPickerRequested = true
                end if
            end if
            return
        end if
        if request.kind = "route"
            PorticoLifecycleDispatch(controller, scene, request, state, "intent")
            return
        end if
        PorticoLifecycleDispatch(controller, scene, request, state, "intent")
        controller.serverPickerRequested = false
        return
    end if

    if controller.pendingRestore = invalid then return
    request = controller.pendingRestore
    route = PorticoLifecycleSafeRoute(request.route)
    if route = "" then route = "home"
    if Left(route, 8) = "library/"
        boundServerId = PorticoLifecycleSafeId(request.selectedServerId)
        selectedServerId = PorticoLifecycleSafeId(state.selectedServerId)
        if selectedServerId = "" then return
        if boundServerId = "" or boundServerId <> selectedServerId then route = "library"
    end if
    PorticoLifecycleDispatch(controller, scene, {kind: "route", route: route, origin: "restore"}, state, "intent")
end sub

sub PorticoLifecycleRememberActivation(controller as object, activation as dynamic, state as dynamic)
    if controller = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = LCase(PorticoLifecycleText(activation.kind, "", 48))
    if kind = "sign-out-account" or kind = "sign-out-local"
        PorticoLifecycleClearNavigation(controller)
        return
    end if
    if kind <> "route" then return
    PorticoLifecycleRememberRoute(controller, activation.route, state)
end sub

sub PorticoLifecycleRememberPage(controller as object, page as dynamic, state as dynamic)
    PorticoLifecycleRememberRoute(controller, page, state)
end sub

sub PorticoLifecycleRememberRoute(controller as object, rawRoute as dynamic, state as dynamic)
    if controller = invalid then return
    route = PorticoLifecycleSafeRoute(rawRoute)
    if route = "" or route = "server-selection" then return
    selectedServerId = ""
    if Left(route, 8) = "library/" and state <> invalid and Type(state) = "roAssociativeArray"
        selectedServerId = PorticoLifecycleSafeId(state.selectedServerId)
        if selectedServerId = "" then route = "library"
    end if
    if route = controller.lastPersistedRoute and selectedServerId = controller.lastPersistedServerId then return
    if PorticoLifecycleWriteNavigation(route, selectedServerId)
        controller.lastPersistedRoute = route
        controller.lastPersistedServerId = selectedServerId
    end if
end sub

sub PorticoLifecycleClearNavigation(controller as object)
    if not PorticoSecureRegistryClear("navigation") then controller.registryCorrupt = true
    controller.lastPersistedRoute = ""
    controller.lastPersistedServerId = ""
    controller.pendingRestore = invalid
end sub

function PorticoLifecycleParseDeepLink(args as dynamic) as dynamic
    if args = invalid or Type(args) <> "roAssociativeArray" then return invalid
    rawURL = PorticoLifecycleArgument(args, ["url", "uri", "link", "deep-link", "deeplink"])
    if rawURL <> invalid
        parsedURL = PorticoLifecycleParsePorticoURL(rawURL)
        if parsedURL <> invalid then return parsedURL
        return {kind: "route", route: "home", origin: "invalid-deep-link"}
    end if
    rawContentId = PorticoLifecycleArgument(args, ["contentid", "content-id"])
    rawMediaType = PorticoLifecycleArgument(args, ["mediatype", "media-type"])
    if rawContentId = invalid and rawMediaType = invalid then return invalid

    ' Some Roku launch integrations provide an application link as contentId.
    ' Treat it as a URL only when it uses an explicitly approved Portico origin.
    contentText = PorticoLifecycleText(rawContentId, "", 2048)
    lowerContent = LCase(contentText)
    if Left(lowerContent, 10) = "portico://" or Left(lowerContent, 8) = "https://"
        parsedURL = PorticoLifecycleParsePorticoURL(contentText)
        if parsedURL <> invalid then return parsedURL
        return {kind: "route", route: "home", origin: "invalid-deep-link"}
    end if

    contentId = PorticoLifecycleSafeId(rawContentId)
    mediaType = LCase(PorticoLifecycleText(rawMediaType, "", 32)).Replace("-", "")
    if contentId = "" or mediaType = "" then return {kind: "route", route: "home", origin: "invalid-deep-link"}
    if mediaType = "season"
        return {kind: "open-detail", targetId: contentId, mediaType: mediaType, origin: "deep-link"}
    end if
    if mediaType = "movie" or mediaType = "episode" or mediaType = "series" or mediaType = "shortformvideo" or mediaType = "tvspecial"
        return {kind: "play", targetId: contentId, mediaType: mediaType, origin: "deep-link"}
    end if
    return {kind: "route", route: "home", origin: "invalid-deep-link"}
end function

function PorticoLifecycleParsePorticoURL(value as dynamic) as dynamic
    raw = PorticoLifecycleText(value, "", 2048)
    if raw = "" or Instr(1, raw, Chr(0)) > 0 or Instr(1, raw, Chr(10)) > 0 or Instr(1, raw, Chr(13)) > 0 then return invalid
    lower = LCase(raw)
    path = ""
    if Left(lower, 10) = "portico://"
        path = Mid(raw, 11)
    else if Left(lower, 8) = "https://"
        authorityStart = 9
        pathAt = Instr(authorityStart, raw, "/")
        authority = ""
        if pathAt > 0
            authority = Mid(raw, authorityStart, pathAt - authorityStart)
            path = Mid(raw, pathAt + 1)
        else
            authority = Mid(raw, authorityStart)
        end if
        normalizedAuthority = LCase(authority)
        if normalizedAuthority <> "app.getportico.tv" and normalizedAuthority <> "web.getportico.tv" then return invalid
        if Instr(1, authority, "@") > 0 or Instr(1, authority, ":") > 0 then return invalid
    else
        return invalid
    end if

    queryAt = Instr(1, path, "?")
    fragmentAt = Instr(1, path, "#")
    endAt = 0
    if queryAt > 0 then endAt = queryAt
    if fragmentAt > 0 and (endAt = 0 or fragmentAt < endAt) then endAt = fragmentAt
    if endAt > 0 then path = Left(path, endAt - 1)
    while Left(path, 1) = "/"
        path = Mid(path, 2)
    end while
    segments = path.Tokenize("/")
    if segments.Count() < 1 then return invalid
    destination = LCase(PorticoLifecycleText(segments[0], "", 32))
    if destination = "media" or destination = "play"
        if segments.Count() <> 2 then return invalid
        mediaId = PorticoLifecycleDecodedId(segments[1])
        if mediaId = "" then return invalid
        if destination = "play" then return {kind: "play", targetId: mediaId, mediaType: "", origin: "deep-link"}
        return {kind: "open-detail", targetId: mediaId, mediaType: "", origin: "deep-link"}
    end if
    if segments.Count() <> 1 and not ((destination = "settings" or destination = "account") and segments.Count() = 2) then return invalid
    if destination = "channels" then return {kind: "route", route: "channels", origin: "deep-link"}
    if destination = "settings" or destination = "account" then return {kind: "route", route: "settings", origin: "deep-link"}
    if destination = "notifications" then return {kind: "route", route: "home", origin: "deep-link", showImportantNotice: true}
    return invalid
end function

function PorticoLifecycleDecodedId(value as dynamic) as string
    encoded = PorticoLifecycleText(value, "", 512)
    if encoded = "" or Instr(1, encoded, "+") > 0 then return ""
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return ""
    decoded = transfer.Unescape(encoded)
    return PorticoLifecycleSafeId(decoded)
end function

function PorticoLifecycleArgument(args as object, acceptedNames as object) as dynamic
    for each key in args
        normalizedKey = LCase(key.ToStr()).Replace("_", "-")
        for each accepted in acceptedNames
            if normalizedKey = accepted then return args[key]
        end for
    end for
    return invalid
end function

function PorticoLifecycleDispatch(controller as object, scene as object, source as object, state = invalid as dynamic, deliveryKind = "intent" as string) as boolean
    if controller.deliveryInFlight then return false
    kind = LCase(PorticoLifecycleText(source.kind, "", 32))
    allowedKinds = {route: true, "open-detail": true, play: true}
    if allowedKinds[kind] <> true then return false
    controller.requestSequence = controller.requestSequence + 1
    request = {sequence: controller.requestSequence, kind: kind, contractRevision: "v1", ackRequired: true}
    if kind = "route"
        route = PorticoLifecycleSafeRoute(source.route)
        if route = "" then route = "home"
        request.route = route
    else
        targetId = PorticoLifecycleSafeId(source.targetId)
        if targetId = "" then return false
        request.targetId = targetId
        request.mediaType = LCase(PorticoLifecycleText(source.mediaType, "", 32))
    end if
    request.origin = PorticoLifecycleText(source.origin, "lifecycle", 32)
    if deliveryKind = "intent"
        request.intentId = PorticoLifecycleSafeId(controller.pendingIntentId)
        if request.intentId = "" then return false
        request.deliveryId = request.intentId
    else
        request.deliveryId = "gate-" + controller.requestSequence.ToStr()
        request.gateDelivery = deliveryKind
    end if
    if state <> invalid and Type(state) = "roAssociativeArray"
        request.viewerGeneration = PorticoLifecycleInteger(state.viewerGeneration, 0)
        request.serverId = PorticoLifecycleSafeId(state.selectedServerId)
        request.profileId = PorticoLifecycleSafeId(state.selectedProfileId)
    end if
    if request.origin = "deep-link"
        if kind = "play" then controller.awaitingLaunchSurface = "player"
        if kind = "open-detail" then controller.awaitingLaunchSurface = "detail"
    end if
    controller.deliveryId = request.deliveryId
    controller.deliveryKind = deliveryKind
    controller.deliveryInFlight = true
    controller.deliveryAttempts = controller.deliveryAttempts + 1
    if deliveryKind = "intent" and not PorticoLifecyclePersistDelivery(controller, request)
        controller.registryCorrupt = true
        controller.deliveryInFlight = false
        return false
    end if
    scene.externalRequest = request
    return true
end function

function PorticoLifecycleReadNavigation() as object
    fallback = {route: "", selectedServerId: "", storageError: false}
    record = PorticoSecureRegistryRead("navigation")
    if not record.ok
        if record.code = "not_found" then return fallback
        fallback.storageError = true
        return fallback
    end if
    if record.code = "not_found" then return fallback
    parsed = record.payload
    if parsed = invalid or Type(parsed) <> "roAssociativeArray" or parsed.version <> 1 or parsed.contractRevision <> "v1"
        fallback.storageError = true
        return fallback
    end if
    route = PorticoLifecycleSafeRoute(parsed.route)
    if route = "" or route = "server-selection"
        fallback.storageError = true
        return fallback
    end if
    selectedServerId = ""
    if Left(route, 8) = "library/" then selectedServerId = PorticoLifecycleSafeId(parsed.selectedServerId)
    return {route: route, selectedServerId: selectedServerId, storageError: false}
end function

function PorticoLifecycleWriteNavigation(route as string, selectedServerId as string) as boolean
    payload = {version: 1, contractRevision: "v1", route: route, selectedServerId: selectedServerId}
    committed = PorticoSecureRegistryCommit("navigation", payload)
    return committed.ok
end function

function PorticoLifecycleReadPendingDeepLink() as object
    result = {request: invalid, intentId: "", storageError: false, expired: false}
    record = PorticoSecureRegistryRead("pending-deep-link")
    if not record.ok
        if record.code = "not_found" then return result
        result.storageError = true
        return result
    end if
    if record.code = "not_found" then return result
    payload = record.payload
    if payload = invalid or Type(payload) <> "roAssociativeArray" or payload.version <> 1 or payload.purpose <> "deep-link-intent" or payload.contractRevision <> "v1"
        result.storageError = true
        return result
    end if
    intentId = PorticoLifecycleSafeId(payload.intentId)
    if intentId = "" or payload.request = invalid or Type(payload.request) <> "roAssociativeArray"
        result.storageError = true
        return result
    end if
    expiresAt = PorticoLifecycleInteger(payload.expiresAt, 0)
    if expiresAt < 1
        result.storageError = true
        return result
    end if
    if PorticoLifecycleNowSeconds() > expiresAt
        result.intentId = intentId
        result.expired = true
        return result
    end if
    request = payload.request
    if LCase(PorticoLifecycleText(request.kind, "", 32)) <> "route" and LCase(PorticoLifecycleText(request.kind, "", 32)) <> "play" and LCase(PorticoLifecycleText(request.kind, "", 32)) <> "open-detail"
        result.storageError = true
        return result
    end if
    request.intentId = intentId
    result.request = request
    result.intentId = intentId
    return result
end function

function PorticoLifecyclePersistPendingDeepLink(controller as object, request as dynamic) as boolean
    if controller.registryCorrupt or request = invalid or Type(request) <> "roAssociativeArray" then return false
    kind = LCase(PorticoLifecycleText(request.kind, "", 32))
    if kind <> "route" and kind <> "play" and kind <> "open-detail" then return false
    if controller.pendingIntentId = ""
        controller.intentSequence = controller.intentSequence + 1
        controller.pendingIntentId = "intent-" + controller.intentSequence.ToStr()
    end if
    request.intentId = controller.pendingIntentId
    nowSeconds = PorticoLifecycleNowSeconds()
    if nowSeconds < 1 then nowSeconds = 1
    payload = {
        version: 1, purpose: "deep-link-intent", contractRevision: "v1", intentId: controller.pendingIntentId,
        request: request, createdAt: nowSeconds, expiresAt: nowSeconds + 600, deliveryState: "pending", attempts: 0
    }
    committed = PorticoSecureRegistryCommit("pending-deep-link", payload)
    if not committed.ok then return false
    controller.pendingLaunch = request
    controller.deliveryInFlight = false
    controller.deliveryId = ""
    controller.deliveryKind = ""
    controller.deliveryAttempts = 0
    return true
end function

function PorticoLifecyclePersistDelivery(controller as object, request as object) as boolean
    record = PorticoSecureRegistryRead("pending-deep-link")
    if not record.ok or record.payload = invalid then return false
    payload = record.payload
    payload.deliveryState = "in-flight"
    payload.deliveryId = request.deliveryId
    payload.attempts = controller.deliveryAttempts
    committed = PorticoSecureRegistryCommit("pending-deep-link", payload)
    return committed.ok
end function

function PorticoLifecycleNowSeconds() as integer
    clock = CreateObject("roDateTime")
    if clock = invalid then return 0
    return clock.AsSeconds()
end function

function PorticoLifecycleSafeRoute(value as dynamic) as string
    return PorticoRouteNormalize(PorticoLifecycleText(value, "", 160))
end function

function PorticoLifecycleSafeId(value as dynamic) as string
    result = PorticoLifecycleText(value, "", 128)
    if Len(result) < 1 or Len(result) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(result)
        if Instr(1, allowed, Mid(result, position, 1)) = 0 then return ""
    end for
    return result
end function

function PorticoLifecycleText(value as dynamic, fallback as string, maximum as integer) as string
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" and valueType <> "integer" and valueType <> "roint" and valueType <> "longinteger" and valueType <> "rolonginteger" and valueType <> "float" and valueType <> "rofloat" and valueType <> "double" and valueType <> "rodouble" then return fallback
    result = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if result = "" then result = fallback
    if Len(result) > maximum then result = Left(result, maximum)
    return result
end function

function PorticoLifecycleSignedIn(state as object) as boolean
    status = LCase(PorticoLifecycleText(state.accountStatus, "signed-out", 32))
    if status = "signed-in" or status = "refreshing" or status = "hosted-unavailable" then return true
    return Left(LCase(PorticoLifecycleText(state.authMode, "", 32)), 5) = "local" and state.localAuthSignedIn = true
end function

function PorticoLifecycleViewerActive(state as object) as boolean
    return PorticoLifecycleViewerPublicationGate(state, invalid).kind = "ready"
end function

function PorticoLifecycleViewerPublicationGate(state as object, expected = invalid as dynamic) as object
    if state = invalid or Type(state) <> "roAssociativeArray" or state.registryCorrupt = true then return {kind: "fail-closed", gate: "registry"}
    if not PorticoLifecycleSignedIn(state) then return {kind: "defer", gate: "account"}

    isLocal = Left(LCase(PorticoLifecycleText(state.authMode, "", 32)), 5) = "local"
    if isLocal
        if state.localAuthSignedIn <> true then return {kind: "defer", gate: "account"}
    else
        accountRecord = PorticoSecureRegistryRead("account-credentials")
        if not accountRecord.ok
            if accountRecord.code = "not_found" then return {kind: "defer", gate: "account"}
            return {kind: "fail-closed", gate: "registry"}
        end if
        if accountRecord.code = "not_found" or accountRecord.payload = invalid or accountRecord.payload.signedOut = true then return {kind: "defer", gate: "account"}
        accountToken = PorticoLifecycleText(accountRecord.payload.accessToken, "", 4096)
        if Left(accountToken, 8) <> "ptc_acc_" or Len(accountToken) < 16 then return {kind: "fail-closed", gate: "registry"}
    end if

    selectedServerId = PorticoLifecycleSafeId(state.selectedServerId)
    if selectedServerId = "" or LCase(PorticoLifecycleText(state.serverStatus, "", 40)) <> "online" then return {kind: "defer", gate: "server"}
    sessionRecord = PorticoSecureRegistryRead("server-session")
    if not sessionRecord.ok
        if sessionRecord.code = "not_found" then return {kind: "defer", gate: "server"}
        return {kind: "fail-closed", gate: "registry"}
    end if
    if sessionRecord.code = "not_found" or sessionRecord.payload = invalid then return {kind: "defer", gate: "server"}
    session = PorticoServerSessionStored(sessionRecord.payload)
    if session = invalid then return {kind: "fail-closed", gate: "registry"}
    if session.serverId <> selectedServerId then return {kind: "defer", gate: "server"}
    if PorticoLifecycleSafeId(state.routeGeneration) <> "" and PorticoLifecycleSafeId(state.routeGeneration) <> session.routeGeneration then return {kind: "defer", gate: "server"}
    if PorticoLifecycleSafeId(state.authorizationRevision) <> "" and PorticoLifecycleSafeId(state.authorizationRevision) <> session.authorizationRevision then return {kind: "defer", gate: "profile"}

    selectedProfileId = PorticoLifecycleSafeId(state.selectedProfileId)
    if selectedProfileId = "" then return {kind: "defer", gate: "profile"}
    if session.profileId <> selectedProfileId then return {kind: "defer", gate: "profile"}
    if state.viewerAcceptingWrites <> true or LCase(PorticoLifecycleText(state.viewerStatus, "", 32)) <> "active" then return {kind: "defer", gate: "profile"}
    viewerGeneration = PorticoLifecycleInteger(state.viewerGeneration, 0)
    if viewerGeneration < 1 then return {kind: "defer", gate: "profile"}
    scope = PorticoServerSessionScope(session, viewerGeneration)
    if scope = invalid then return {kind: "fail-closed", gate: "registry"}
    if expected <> invalid and Type(expected) = "roAssociativeArray"
        if PorticoLifecycleSafeId(expected.serverId) <> "" and PorticoLifecycleSafeId(expected.serverId) <> scope.serverId then return {kind: "defer", gate: "server"}
        if PorticoLifecycleSafeId(expected.profileId) <> "" and PorticoLifecycleSafeId(expected.profileId) <> scope.profileId then return {kind: "defer", gate: "profile"}
        if PorticoLifecycleSafeId(expected.authorizationRevision) <> "" and PorticoLifecycleSafeId(expected.authorizationRevision) <> scope.authorizationRevision then return {kind: "defer", gate: "profile"}
    end if
    return {kind: "ready", scope: scope, routeGeneration: session.routeGeneration, authorizationRevision: session.authorizationRevision}
end function

function PorticoLifecycleAcknowledgeDispatch(controller as object, value as dynamic) as boolean
    if controller = invalid or value = invalid or Type(value) <> "roAssociativeArray" then return false
    deliveryId = PorticoLifecycleSafeId(value.deliveryId)
    if deliveryId = "" then return false
    if controller.deliveryAcknowledgedId = deliveryId then return true
    if not controller.deliveryInFlight or controller.deliveryId <> deliveryId then return false
    if value.deliveryOk = false or value.acknowledged = false
        controller.deliveryInFlight = false
        record = PorticoSecureRegistryRead("pending-deep-link")
        if record.ok and record.payload <> invalid
            record.payload.deliveryState = "pending"
            PorticoSecureRegistryCommit("pending-deep-link", record.payload)
        end if
        return false
    end if
    if controller.deliveryKind = "gate"
        controller.deliveryAcknowledgedId = deliveryId
        controller.deliveryInFlight = false
        controller.deliveryId = ""
        controller.deliveryKind = ""
        return true
    end if
    if controller.pendingIntentId <> deliveryId then return false
    if not PorticoSecureRegistryClear("pending-deep-link")
        controller.registryCorrupt = true
        return false
    end if
    controller.deliveryAcknowledgedId = deliveryId
    controller.deliveryInFlight = false
    controller.deliveryId = ""
    controller.deliveryKind = ""
    controller.pendingIntentId = ""
    controller.pendingLaunch = invalid
    controller.pendingRestore = invalid
    return true
end function

function PorticoLifecycleInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    kind = LCase(Type(value))
    if kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" and kind <> "float" and kind <> "rofloat" and kind <> "double" and kind <> "rodouble" then return fallback
    return Int(value)
end function

function PorticoLifecycleAccountStateSettled(state as object) as boolean
    status = LCase(PorticoLifecycleText(state.accountStatus, "signed-out", 32))
    if status <> "signed-out" then return true
    hostedStatus = LCase(PorticoLifecycleText(state.hostedStatus, "unknown", 32))
    authMode = LCase(PorticoLifecycleText(state.authMode, "", 32))
    return hostedStatus <> "unknown" or authMode = "none" or authMode = "local-pending"
end function

function PorticoLifecycleServerListSettled(state as object) as boolean
    status = LCase(PorticoLifecycleText(state.serverListStatus, "unknown", 32))
    return status = "ready" or status = "stale" or status = "offline" or status = "denied" or status = "incompatible"
end function
