function PorticoDiagnosticsVersion() as integer
    return 1
end function

function PorticoDiagnosticsAllowedFields() as object
    return {buildVersion: true, buildChannel: true, platform: true, deviceClass: true, routeId: true, viewerGeneration: true, playbackGeneration: true, requestId: true, taskKind: true, eventKind: true, classification: true, retryAttempt: true, occurredAt: true}
end function

function PorticoDiagnosticsPrivateFields() as object
    return {accesstoken: true, refreshtoken: true, mediagrant: true, password: true, pin: true, accountemail: true, profilename: true, mediatitle: true, mediaid: true, serverorigin: true, url: true, headers: true, filesystempath: true, rawerror: true}
end function

function PorticoDiagnosticsSanitize(value as dynamic) as dynamic
    if value = invalid or GetInterface(value, "ifAssociativeArray") = invalid then return invalid
    allowed = PorticoDiagnosticsAllowedFields()
    private = PorticoDiagnosticsPrivateFields()
    result = {}
    for each key in value
        normalizedKey = LCase(key)
        if private[normalizedKey] = true then return invalid
        if allowed[key] <> true then continue for
        safe = PorticoDiagnosticsSafeValue(value[key], 160)
        if safe = invalid then return invalid
        result[key] = safe
    end for
    if result.eventKind = invalid or result.occurredAt = invalid then return invalid
    return result
end function

function PorticoDiagnosticsSafeValue(value as dynamic, maximum as integer) as dynamic
    if value = invalid then return invalid
    kind = LCase(Type(value))
    if kind <> "string" and kind <> "rostring" and kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" then return invalid
    result = value.ToStr().Trim()
    if result = "" or Len(result) > maximum then return invalid
    lower = LCase(result)
    for each marker in ["bearer ", "access_token", "refresh_token", "media_grant", "password", "secret", "private key", "https://", "http://"]
        if Instr(1, lower, marker) > 0 then return invalid
    end for
    return result
end function
