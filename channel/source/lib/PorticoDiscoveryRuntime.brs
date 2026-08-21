function PorticoDiscoveryTaskState(domain as string) as object
    return {
        discoveryDomain: domain,
        envelopeMode: false,
        viewerScope: invalid,
        viewerGeneration: 0,
        activeOperationSequence: 0,
        publicationSequence: 0,
        productContractRevision: "",
        operationContract: invalid,
        activeCommandKind: ""
    }
end function

sub PorticoDiscoveryTaskAdopt(target as object, state as object)
    for each key in state
        target[key] = state[key]
    end for
end sub

function PorticoDiscoveryAcceptCommand(controller as object, envelope as dynamic, expectedDomain as string) as dynamic
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" or envelope.version <> 1 then return invalid
    if LCase(PorticoCoreSafeIdentifier(envelope.domain, 64)) <> expectedDomain then return invalid
    scope = PorticoViewerScopeNormalize(envelope.viewerScope)
    generation = PorticoViewerScopePositiveInteger(envelope.viewerGeneration)
    sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    command = envelope.command
    if scope = invalid or generation < 1 or sequence < 1 or command = invalid or Type(command) <> "roAssociativeArray" then return invalid
    if generation <> scope.viewerGeneration then return invalid
    revision = PorticoViewerScopeOpaqueId(command.productContractRevision, 128)
    if revision = "" then return invalid

    currentScope = PorticoViewerScopeNormalize(controller.viewerScope)
    changedViewer = currentScope = invalid or not PorticoViewerScopeEquals(currentScope, scope)
    if controller.envelopeMode
        if generation < controller.viewerGeneration then return invalid
        if generation = controller.viewerGeneration and changedViewer then return invalid
        if generation = controller.viewerGeneration and sequence <= controller.activeOperationSequence then return invalid
    end if

    if changedViewer or generation <> controller.viewerGeneration
        controller.viewerScope = scope
        controller.viewerGeneration = generation
        controller.activeOperationSequence = 0
        controller.lastCommandSequence = 0
    end if
    loaded = PorticoOperationContractLoad()
    if not loaded.ok then return invalid
    controller.operationContract = loaded.value
    controller.envelopeMode = true
    controller.productContractRevision = revision
    controller.activeOperationSequence = sequence
    controller.publicationSequence = 0
    controller.activeCommandKind = LCase(PorticoCoreSafeIdentifier(command.kind, 80))

    accepted = {}
    for each key in command
        accepted[key] = command[key]
    end for
    accepted.sequence = sequence
    accepted.viewerGeneration = generation
    return accepted
end function

function PorticoDiscoverySessionForController(controller as object) as dynamic
    if controller.envelopeMode <> true then return PorticoBrowseSessionForServer(controller.serverId)
    bound = PorticoDiscoveryCacheSessionForController(controller)
    if bound = invalid then return invalid
    expected = bound.viewerScope
    value = bound.session
    projection = PorticoServerSessionRequestProjection(value, expected, bound.recordGeneration)
    if projection = invalid then return invalid
    projection.generation = bound.recordGeneration
    return projection
end function

function PorticoDiscoveryCacheSessionForController(controller as object) as dynamic
    expected = PorticoViewerScopeNormalize(controller.viewerScope)
    if expected = invalid or expected.viewerGeneration <> controller.viewerGeneration then return invalid
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid or record.payload.signedOut = true then return invalid
    value = PorticoServerSessionStored(record.payload)
    if value = invalid then return invalid
    actual = PorticoServerSessionScope(value, expected.viewerGeneration)
    if actual = invalid or not PorticoViewerScopeEquals(actual, expected) then return invalid
    return {session: value, viewerScope: expected, recordGeneration: record.generation}
end function

function PorticoDiscoveryCacheKey(controller as object, resource as string, parameters = "" as dynamic) as string
    if controller.envelopeMode <> true then return controller.cacheBinding
    if PorticoDiscoveryCacheSessionForController(controller) = invalid then return ""
    canonical = parameters
    if Type(parameters) = "roAssociativeArray" then canonical = PorticoDiscoveryCanonicalParameters(parameters)
    if canonical = invalid then return ""
    return PorticoCacheKey(controller.viewerScope, controller.productContractRevision, resource, canonical)
end function

function PorticoDiscoveryCanonicalParameters(values as dynamic) as dynamic
    if values = invalid then return ""
    if Type(values) <> "roAssociativeArray" then return invalid
    if values.Count() > 32 then return invalid
    keys = values.Keys()
    if keys = invalid then return invalid
    keys.Sort()
    encoded = "p1"
    for each rawKey in keys
        key = PorticoCoreSafeIdentifier(rawKey, 80)
        if key = "" or key <> rawKey then return invalid
        value = values[key]
        valueType = Type(value)
        prefix = ""
        scalar = ""
        if value = invalid
            prefix = "n"
        else if valueType = "String" or valueType = "roString"
            prefix = "s"
            scalar = PorticoCoreSafeText(value, 512)
            if scalar <> value.ToStr() then return invalid
        else if valueType = "Boolean" or valueType = "roBoolean"
            prefix = "b"
            if value then scalar = "1" else scalar = "0"
        else if valueType = "Integer" or valueType = "roInt" or valueType = "LongInteger" or valueType = "roLongInteger"
            prefix = "i"
            scalar = value.ToStr()
        else
            return invalid
        end if
        encoded = encoded + Len(key).ToStr() + ":" + key + prefix + Len(scalar).ToStr() + ":" + scalar
        if Len(encoded) > 2048 then return invalid
    end for
    return encoded
end function

function PorticoDiscoveryCacheMatches(controller as object, payload as dynamic, resource as string, parameters = "" as dynamic) as boolean
    if controller.envelopeMode <> true then return payload <> invalid and payload.version = 1 and payload.cacheBinding = controller.cacheBinding
    if payload = invalid or Type(payload) <> "roAssociativeArray" or payload.version <> 2 then return false
    expected = PorticoDiscoveryCacheKey(controller, resource, parameters)
    return expected <> "" and PorticoCoreSafeText(payload.viewerCacheKey, 2048) = expected
end function

function PorticoDiscoveryCacheEnvelope(controller as object, resource as string, parameters as dynamic, values as object) as dynamic
    if controller.envelopeMode <> true then return values
    cacheKey = PorticoDiscoveryCacheKey(controller, resource, parameters)
    if cacheKey = "" then return invalid
    result = {version: 2, viewerCacheKey: cacheKey}
    for each key in values
        if key <> "version" and key <> "cacheBinding" and key <> "serverId" then result[key] = values[key]
    end for
    return result
end function

function PorticoDiscoveryCacheRead(recordType as string, controller as object, resource as string, parameters as dynamic) as dynamic
    record = PorticoSecureRegistryRead(recordType)
    if not record.ok or record.payload = invalid then return invalid
    if controller.envelopeMode <> true then return record.payload
    key = PorticoDiscoveryCacheKey(controller, resource, parameters)
    store = record.payload
    if key = "" or store = invalid or Type(store) <> "roAssociativeArray" or store.version <> 3 or store.purpose <> "viewer-scoped-discovery-cache" then return invalid
    entries = store.entries
    if entries = invalid or GetInterface(entries, "ifArray") = invalid then return invalid
    for each entry in entries
        if entry <> invalid and Type(entry) = "roAssociativeArray" and PorticoCoreSafeText(entry.key, 2048) = key and entry.payload <> invalid and Type(entry.payload) = "roAssociativeArray" then return entry.payload
    end for
    return invalid
end function

function PorticoDiscoveryCacheCommit(recordType as string, controller as object, resource as string, parameters as dynamic, payload as object) as boolean
    if controller.envelopeMode <> true then return PorticoSecureRegistryCommit(recordType, payload).ok
    key = PorticoDiscoveryCacheKey(controller, resource, parameters)
    if key = "" then return false
    entries = []
    existing = PorticoSecureRegistryRead(recordType)
    if existing.ok and existing.payload <> invalid and existing.payload.version = 3 and existing.payload.purpose = "viewer-scoped-discovery-cache" and GetInterface(existing.payload.entries, "ifArray") <> invalid
        for index = existing.payload.entries.Count() - 1 to 0 step -1
            entry = existing.payload.entries[index]
            if entries.Count() >= 3 then exit for
            if entry <> invalid and Type(entry) = "roAssociativeArray" and PorticoCoreSafeText(entry.key, 2048) <> "" and entry.key <> key and entry.payload <> invalid and Type(entry.payload) = "roAssociativeArray" then entries.Push(entry)
        end for
    end if
    entries.Push({key: key, payload: payload})
    return PorticoSecureRegistryCommit(recordType, {version: 3, purpose: "viewer-scoped-discovery-cache", entries: entries}).ok
end function

sub PorticoDiscoveryCacheRemoveViewer(recordType as string, controller as object)
    if controller.envelopeMode <> true
        PorticoSecureRegistryClear(recordType)
        return
    end if
    prefix = PorticoCacheScopePrefix(controller.viewerScope, controller.productContractRevision)
    if prefix = "" then return
    record = PorticoSecureRegistryRead(recordType)
    if not record.ok or record.payload = invalid or record.payload.version <> 3 or GetInterface(record.payload.entries, "ifArray") = invalid then return
    kept = []
    for each entry in record.payload.entries
        key = ""
        if entry <> invalid and Type(entry) = "roAssociativeArray" then key = PorticoCoreSafeText(entry.key, 2048)
        if key <> "" and Left(key, Len(prefix) + 1) <> prefix + "." then kept.Push(entry)
    end for
    if kept.Count() = 0
        PorticoSecureRegistryClear(recordType)
    else
        PorticoSecureRegistryCommit(recordType, {version: 3, purpose: "viewer-scoped-discovery-cache", entries: kept})
    end if
end sub

function PorticoDiscoveryResultEnvelope(controller as object, projection as object) as dynamic
    if controller.envelopeMode <> true then return invalid
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if scope = invalid or controller.activeOperationSequence < 1 then return invalid
    nextPublication = PorticoViewerScopePositiveInteger(controller.publicationSequence) + 1
    if nextPublication < 1 or nextPublication >= 2147483647 then return invalid
    controller.publicationSequence = nextPublication
    return {
        version: 1,
        domain: controller.discoveryDomain,
        viewerGeneration: controller.viewerGeneration,
        viewerScope: scope,
        operationSequence: controller.activeOperationSequence,
        publicationSequence: nextPublication,
        projection: projection
    }
end function

function PorticoDiscoveryInterrupted(controller as object) as boolean
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return false
    generation = PorticoViewerScopePositiveInteger(envelope.viewerGeneration)
    sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    if generation <> controller.viewerGeneration then return true
    return sequence > controller.activeOperationSequence
end function

function PorticoDiscoveryViewerInterrupted(controller as object) as boolean
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return false
    incoming = PorticoViewerScopeNormalize(envelope.viewerScope)
    current = PorticoViewerScopeNormalize(controller.viewerScope)
    if incoming = invalid or current = invalid then return true
    return not PorticoViewerScopeEquals(incoming, current)
end function

function PorticoDiscoverySessionStillCurrent(controller as object, expected as dynamic) as boolean
    current = PorticoDiscoverySessionForController(controller)
    return current <> invalid and expected <> invalid and current.generation = expected.generation and PorticoViewerScopeEquals(current.viewerScope, expected.viewerScope)
end function

function PorticoDiscoveryAllowedRequest(controller as object, method as string, path as string) as object
    if controller.envelopeMode <> true then return {ok: true, path: path}
    if controller.operationContract = invalid then return {ok: false, code: "operation_contract_unavailable"}
    safeMethod = UCase(PorticoCoreSafeText(method, 10))
    safePath = PorticoBrowseSafeApiPath(path)
    if safePath = "" or Left(safePath, 5) <> "/api/" then return {ok: false, code: "operation_not_allowed"}
    basePath = Mid(safePath, 5)
    queryAt = Instr(1, basePath, "?")
    if queryAt > 0 then basePath = Left(basePath, queryAt - 1)
    operationId = PorticoDiscoveryOperationId(safeMethod, basePath)
    if operationId = "" then return {ok: false, code: "operation_not_allowed"}
    operation = PorticoOperationContractFind(controller.operationContract, "server", operationId)
    if operation = invalid or operation.method <> safeMethod then return {ok: false, code: "operation_not_allowed"}
    return {ok: true, path: safePath, operationId: operationId}
end function

function PorticoDiscoveryOperationId(method as string, path as string) as string
    exact = {
        "GET /home": "getHome", "GET /libraries": "getLibraries", "POST /search": "postSearch",
        "GET /product-contract": "getProductContract", "GET /search/history": "getSearchHistory",
        "DELETE /search/history": "deleteSearchHistory",
        "GET /people/media": "getPeopleMedia", "POST /playback/active": "postPlaybackActive",
        "GET /playlists": "getPlaylists", "GET /collections": "getCollections",
        "POST /collections": "postCollections", "GET /watchlist": "getWatchlist",
        "GET /favorites": "getFavorites", "GET /saved-views": "getSavedViews",
        "POST /saved-views": "postSavedViews",
        "GET /dvr/schedule": "getDvrSchedule"
    }
    direct = exact[method + " " + path]
    if direct <> invalid then return direct
    parts = path.Tokenize("/")
    if parts.Count() = 2 and parts[0] = "media" and method = "GET" then return "getMediaId"
    if parts.Count() = 3 and parts[0] = "media" and parts[2] = "children" and method = "GET" then return "getMediaChildren"
    if parts.Count() = 2 and parts[0] = "people" and method = "GET" then return "getPersonDetail"
    if parts.Count() = 3 and parts[0] = "home" and parts[1] = "rows" and method = "GET" then return "getHomeRowsId"
    if parts.Count() = 3 and parts[0] = "libraries" and method = "GET" and parts[2] = "discover" then return "getLibraryDiscover"
    if parts.Count() = 3 and parts[0] = "libraries" and method = "GET" and parts[2] = "categories" then return "getLibrariesIdCategories"
    if parts.Count() = 3 and parts[0] = "libraries" and method = "GET" and parts[2] = "authors" then return "getLibrariesIdAuthors"
    if parts.Count() = 3 and parts[0] = "libraries" and method = "GET" and parts[2] = "series" then return "getLibrariesIdSeries"
    if parts.Count() = 3 and parts[0] = "libraries" and method = "GET" and parts[2] = "browse-capabilities" then return "getLibraryBrowseCapabilities"
    if parts.Count() = 3 and parts[0] = "libraries" and method = "POST" and parts[2] = "browse" then return "browseLibrary"
    if parts.Count() = 3 and parts[0] = "playlists" and method = "GET" and parts[2] = "items" then return "getPlaylistsPlaylistIdItems"
    if parts.Count() = 3 and parts[0] = "collections" and method = "GET" and parts[2] = "items" then return "getCollectionsCollectionIdItems"
    if parts.Count() = 3 and parts[0] = "saved-views" and method = "POST" and parts[2] = "browse" then return "postSavedViewsSavedViewIdBrowse"
    if parts.Count() = 3 and parts[0] = "media" and method = "POST"
        if parts[2] = "watchlist" then return "postMediaIdWatchlist"
        if parts[2] = "favorite" then return "postMediaIdFavorite"
        if parts[2] = "watched" then return "postMediaIdWatched"
        if parts[2] = "rating" then return "postMediaIdRating"
        if parts[2] = "reaction" then return "postMediaIdReaction"
    end if
    if parts.Count() = 3 and parts[0] = "playback-sessions" and parts[2] = "queue"
        if method = "GET" then return "getPlaybackSessionsSessionIdQueue"
        if method = "PATCH" then return "patchPlaybackSessionsSessionIdQueue"
    end if
    if parts.Count() = 3 and parts[0] = "collections" and parts[2] = "memberships:batch" and method = "POST" then return "postCollectionsCollectionIdMembershipsBatch"
    if parts.Count() = 3 and parts[0] = "playlists" and parts[2] = "items:batch" and method = "POST" then return "postPlaylistsPlaylistIdItemsBatch"
    return ""
end function

function PorticoDiscoveryRequest(controller as object, session as object, method as string, path as string, body as dynamic) as object
    allowed = PorticoDiscoveryAllowedRequest(controller, method, path)
    if not allowed.ok then return PorticoBrowseHttpFailure(0, false, allowed.code)
    request = PorticoHttpNormalizeRequest({method: method, url: session.apiBaseUrl + allowed.path, body: body, headers: {Authorization: "Bearer " + session.accessToken}, timeoutMs: 15000, expectJson: true, allowInsecureLan: session.allowInsecureLan = true})
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoBrowseHttpFailure(0, false, validation.code)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return PorticoBrowseHttpFailure(0, true, "transport_error")
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoBrowseHttpFailure(0, true, "transport_error")
    if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return PorticoBrowseHttpFailure(0, true, "transport_error")
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return PorticoBrowseHttpFailure(0, false, "invalid_header")
    end for
    started = false
    if request.method = "GET" then started = transfer.AsyncGetToString()
    if request.method = "POST" or request.method = "PATCH" or request.method = "DELETE" then started = transfer.AsyncPostFromString(request.body)
    if not started then return PorticoBrowseHttpFailure(0, true, "transport_error")
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        interrupted = PorticoDiscoveryInterrupted(controller)
        if interrupted and (controller.nonInterruptibleRequest <> true or PorticoDiscoveryViewerInterrupted(controller))
            transfer.AsyncCancel()
            return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid}
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            if PorticoDiscoveryInterrupted(controller) or not PorticoDiscoverySessionStillCurrent(controller, session) then return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid}
            status = message.GetResponseCode()
            classification = PorticoHttpClassifyStatus(status)
            if classification.classification <> "success" then return {interrupted: false, ok: false, status: status, retryable: classification.retryable, data: invalid}
            payload = message.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoBrowseHttpFailure(status, false, "response_too_large")
            parsed = PorticoHttpParseJson(payload)
            if not parsed.ok then return PorticoBrowseHttpFailure(status, false, "parse_error")
            return {interrupted: false, ok: true, status: status, retryable: false, data: parsed.value}
        end if
    end while
    transfer.AsyncCancel()
    return PorticoBrowseHttpFailure(0, true, "timeout")
end function
