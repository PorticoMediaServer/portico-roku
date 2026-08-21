function PorticoChannelsTaskState() as object
    loadedLanguage = PorticoProductLanguageLoad()
    language = invalid
    if loadedLanguage.ok then language = loadedLanguage.value
    return {
        envelopeMode: false,
        viewerScope: invalid,
        viewerGeneration: 0,
        activeOperationSequence: 0,
        publicationSequence: 0,
        productContractRevision: "",
        operationContract: invalid,
        activeCommandKind: "",
        language: language
    }
end function

sub PorticoChannelsTaskAdopt(target as object, source as object)
    for each key in source
        target[key] = source[key]
    end for
end sub

function PorticoChannelsAcceptCommand(controller as object, envelope as dynamic) as dynamic
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" or envelope.version <> 1 then return invalid
    if LCase(PorticoCoreSafeIdentifier(envelope.domain, 64)) <> "channels" then return invalid
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

    contract = PorticoOperationContractLoad()
    if not contract.ok then return invalid
    if changedViewer or generation <> controller.viewerGeneration
        controller.viewerScope = scope
        controller.viewerGeneration = generation
        controller.activeOperationSequence = 0
        controller.lastCommandSequence = 0
    end if
    controller.envelopeMode = true
    controller.operationContract = contract.value
    controller.productContractRevision = revision
    controller.activeOperationSequence = sequence
    controller.lastCommandSequence = sequence
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

function PorticoChannelsSession(controller as object, requireAccess = true as boolean) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if scope = invalid or scope.viewerGeneration <> controller.viewerGeneration then return invalid
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid or record.payload.signedOut = true then return invalid
    session = PorticoServerSessionStored(record.payload)
    if session = invalid then return invalid
    actual = PorticoServerSessionScope(session, scope.viewerGeneration)
    if actual = invalid or not PorticoViewerScopeEquals(actual, scope) then return invalid
    projection = PorticoServerSessionRequestProjection(session, scope, record.generation)
    if projection = invalid then return invalid
    projection.generation = record.generation
    return projection
end function

function PorticoChannelsOperationAvailable(controller as object, operationId as string) as boolean
    if controller.operationContract = invalid then return false
    return PorticoOperationContractFind(controller.operationContract, "server", operationId) <> invalid
end function

function PorticoChannelsOperationPath(controller as object, operationId as string, inputs = invalid as dynamic, query = invalid as dynamic) as object
    if controller.operationContract = invalid then return {ok: false, code: "operation_contract_unavailable", path: "", method: ""}
    resolved = PorticoOperationContractResolvePath(controller.operationContract, "server", operationId, inputs)
    if not resolved.ok then return resolved
    suffix = PorticoChannelsQuery(query)
    if suffix = invalid then return {ok: false, code: "operation_query_invalid", path: "", method: ""}
    resolved.path = "/api" + resolved.path + suffix
    if PorticoBrowseSafeApiPath(resolved.path) = "" then return {ok: false, code: "operation_path_invalid", path: "", method: ""}
    return resolved
end function

function PorticoChannelsQuery(values as dynamic) as dynamic
    if values = invalid then return ""
    if Type(values) <> "roAssociativeArray" or values.Count() > 24 then return invalid
    keys = values.Keys()
    if keys = invalid then return invalid
    keys.Sort()
    parts = []
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return invalid
    for each rawKey in keys
        key = PorticoCoreSafeIdentifier(rawKey, 64)
        if key = "" or key <> rawKey then return invalid
        value = values[key]
        if value <> invalid
            valueType = LCase(Type(value))
            scalar = ""
            if valueType = "string" or valueType = "rostring"
                scalar = PorticoCoreSafeText(value, 512)
                if scalar <> value.ToStr() then return invalid
            else if valueType = "boolean" or valueType = "roboolean"
                if value then scalar = "true" else scalar = "false"
            else if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger"
                scalar = value.ToStr()
            else
                return invalid
            end if
            parts.Push(transfer.Escape(key) + "=" + transfer.Escape(scalar))
        end if
    end for
    if parts.Count() = 0 then return ""
    return "?" + parts.Join("&")
end function

function PorticoChannelsRequest(controller as object, operationId as string, inputs as dynamic, query as dynamic, body as dynamic) as object
    session = PorticoChannelsSession(controller, true)
    if session = invalid then return PorticoBrowseHttpFailure(401, false, "server_session_required")
    resolved = PorticoChannelsOperationPath(controller, operationId, inputs, query)
    if not resolved.ok then return PorticoBrowseHttpFailure(0, false, resolved.code)
    request = PorticoHttpNormalizeRequest({
        method: resolved.method,
        url: session.apiBaseUrl + resolved.path,
        body: body,
        headers: {Authorization: "Bearer " + session.accessToken},
        timeoutMs: 18000,
        expectJson: true,
        allowInsecureLan: session.allowInsecureLan = true
    })
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
        if PorticoChannelsInterrupted(controller)
            transfer.AsyncCancel()
            return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "interrupted"}
        end if
        event = Wait(125, port)
        if event <> invalid and Type(event) = "roUrlEvent" and event.GetSourceIdentity() = identity
            currentSession = PorticoChannelsSession(controller, true)
            if PorticoChannelsInterrupted(controller) or currentSession = invalid or currentSession.generation <> session.generation then return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid, code: "session_fenced"}
            status = event.GetResponseCode()
            responseBody = event.GetString()
            data = invalid
            if responseBody <> "" and Len(responseBody) <= 1048576 then data = ParseJson(responseBody)
            responseBody = ""
            if status >= 200 and status < 300
                if data = invalid and status <> 204 then return PorticoBrowseHttpFailure(status, false, "invalid_response")
                return {interrupted: false, ok: true, status: status, retryable: false, data: data, code: ""}
            end if
            retryable = status = 408 or status = 429 or status >= 500
            return {interrupted: false, ok: false, status: status, retryable: retryable, data: data, code: "request_failed"}
        end if
    end while
    transfer.AsyncCancel()
    return PorticoBrowseHttpFailure(0, true, "timeout")
end function

function PorticoChannelsInterrupted(controller as object) as boolean
    if controller.envelopeMode
        envelope = m.top.commandEnvelope
        if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return false
        generation = PorticoViewerScopePositiveInteger(envelope.viewerGeneration)
        sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
        if generation <> controller.viewerGeneration then return true
        return sequence > controller.activeOperationSequence
    end if
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return false
    return PorticoHttpInteger(command.sequence, 0) > controller.lastCommandSequence
end function

function PorticoChannelsCacheKey(controller as object, resource as string, parameters = invalid as dynamic) as string
    if PorticoChannelsSession(controller, false) = invalid then return ""
    canonical = PorticoChannelsCanonicalParameters(parameters)
    if canonical = invalid then return ""
    return PorticoCacheKey(controller.viewerScope, controller.productContractRevision, resource, canonical)
end function

function PorticoChannelsCanonicalParameters(values as dynamic) as dynamic
    if values = invalid then return ""
    if Type(values) <> "roAssociativeArray" or values.Count() > 32 then return invalid
    keys = values.Keys()
    if keys = invalid then return invalid
    keys.Sort()
    result = "p1"
    for each rawKey in keys
        key = PorticoCoreSafeIdentifier(rawKey, 80)
        if key = "" or key <> rawKey then return invalid
        value = values[key]
        prefix = "n"
        scalar = ""
        valueType = LCase(Type(value))
        if value <> invalid
            if valueType = "string" or valueType = "rostring"
                prefix = "s"
                scalar = PorticoCoreSafeText(value, 512)
                if scalar <> value.ToStr() then return invalid
            else if valueType = "boolean" or valueType = "roboolean"
                prefix = "b"
                if value then scalar = "1" else scalar = "0"
            else if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger"
                prefix = "i"
                scalar = value.ToStr()
            else
                return invalid
            end if
        end if
        result = result + Len(key).ToStr() + ":" + key + prefix + Len(scalar).ToStr() + ":" + scalar
        if Len(result) > 2048 then return invalid
    end for
    return result
end function

function PorticoChannelsCacheRead(controller as object, resource as string, parameters = invalid as dynamic) as dynamic
    key = PorticoChannelsCacheKey(controller, resource, parameters)
    if key = "" then return invalid
    record = PorticoSecureRegistryRead("channels-cache")
    if not record.ok or record.payload = invalid or record.payload.version <> 1 or record.payload.purpose <> "viewer-scoped-channels-cache" then return invalid
    entries = record.payload.entries
    if entries = invalid or GetInterface(entries, "ifArray") = invalid then return invalid
    for each entry in entries
        if entry <> invalid and Type(entry) = "roAssociativeArray" and PorticoCoreSafeText(entry.key, 2048) = key and entry.payload <> invalid and Type(entry.payload) = "roAssociativeArray" then return entry.payload
    end for
    return invalid
end function

function PorticoChannelsCacheCommit(controller as object, resource as string, parameters as dynamic, payload as object) as boolean
    key = PorticoChannelsCacheKey(controller, resource, parameters)
    if key = "" then return false
    entries = []
    record = PorticoSecureRegistryRead("channels-cache")
    if record.ok and record.payload <> invalid and record.payload.version = 1 and record.payload.purpose = "viewer-scoped-channels-cache" and GetInterface(record.payload.entries, "ifArray") <> invalid
        for index = record.payload.entries.Count() - 1 to 0 step -1
            entry = record.payload.entries[index]
            ' Keep the complete viewer-scoped cache bounded to five entries,
            ' including the entry appended below.
            if entries.Count() >= 4 then exit for
            if entry <> invalid and Type(entry) = "roAssociativeArray" and PorticoCoreSafeText(entry.key, 2048) <> "" and entry.key <> key and entry.payload <> invalid and Type(entry.payload) = "roAssociativeArray" then entries.Push(entry)
        end for
    end if
    entries.Push({key: key, payload: payload})
    return PorticoSecureRegistryCommit("channels-cache", {version: 1, purpose: "viewer-scoped-channels-cache", entries: entries}).ok
end function

function PorticoChannelsResultEnvelope(controller as object, projection as object) as dynamic
    if controller.envelopeMode <> true then return invalid
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if scope = invalid or controller.activeOperationSequence < 1 then return invalid
    if controller.publicationSequence >= 2147483646 then return invalid
    controller.publicationSequence = controller.publicationSequence + 1
    return {
        version: 1,
        domain: "channels",
        viewerGeneration: controller.viewerGeneration,
        viewerScope: scope,
        operationSequence: controller.activeOperationSequence,
        publicationSequence: controller.publicationSequence,
        projection: projection
    }
end function

function PorticoChannelsCopy(controller as object, messageId as dynamic, fallbackId as string, variables = invalid as dynamic) as object
    if controller.language = invalid then return PorticoProductLanguageEmergencyMessage("product_language_unavailable")
    return PorticoProductLanguageMessage(controller.language, messageId, fallbackId, variables)
end function

function PorticoChannelsFailureCopy(controller as object, result as dynamic, fallbackId as string, variables = invalid as dynamic) as object
    problem = {}
    if result <> invalid and Type(result) = "roAssociativeArray"
        problem.status = result.status
        if result.data <> invalid and Type(result.data) = "roAssociativeArray"
            problem.code = result.data.code
            problem.messageId = result.data.messageId
            problem.details = result.data.details
        end if
    end if
    copy = PorticoProductLanguageResolveProblem(controller.language, problem, variables)
    if copy.id = "problem.request-failed" then copy = PorticoChannelsCopy(controller, fallbackId, fallbackId, variables)
    return copy
end function
