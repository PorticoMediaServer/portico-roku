function PorticoHttpNormalizeRequest(rawRequest as dynamic) as object
    limits = PorticoHttpLimits()
    source = rawRequest
    if not PorticoHttpIsAssociativeArray(source) then source = {}

    requestId = PorticoHttpNewRequestId()
    method = UCase(PorticoHttpScalarString(source.method, "GET"))
    timeoutMs = PorticoHttpInteger(source.timeoutMs, limits.defaultTimeoutMs)
    if timeoutMs < limits.minimumTimeoutMs then timeoutMs = limits.minimumTimeoutMs
    if timeoutMs > limits.maximumTimeoutMs then timeoutMs = limits.maximumTimeoutMs

    body = PorticoHttpBodyString(source.body)
    headers = PorticoHttpNormalizeHeaders(source.headers, requestId, body <> "")

    return {
        operationId: PorticoHttpSafeIdentifier(source.operationId, requestId),
        generationId: PorticoHttpSafeIdentifier(source.generationId, "0"),
        requestId: requestId,
        method: method,
        url: PorticoHttpScalarString(source.url, ""),
        headers: headers,
        body: body,
        responsePath: PorticoHttpResponsePath(requestId),
        timeoutMs: timeoutMs,
        expectJson: PorticoHttpBoolean(source.expectJson, true),
        allowInsecureLan: PorticoHttpBoolean(source.allowInsecureLan, false)
    }
end function

function PorticoHttpValidateRequest(request as object) as object
    return PorticoHttpValidateRequestWithPolicy(request, false)
end function

function PorticoHttpValidatePrivateRequest(request as object) as object
    return PorticoHttpValidateRequestWithPolicy(request, true)
end function

function PorticoHttpValidateRequestWithPolicy(request as object, allowSensitiveMaterial as boolean) as object
    limits = PorticoHttpLimits()
    methods = PorticoHttpSupportedMethods()

    if request.url = "" then return { ok: false, code: "url_required", message: "A request URL is required." }
    if Len(request.url) > limits.maximumUrlLength then return { ok: false, code: "url_too_long", message: "The request URL is too long." }
    if Instr(1, request.url, Chr(0)) > 0 or Instr(1, request.url, Chr(10)) > 0 or Instr(1, request.url, Chr(13)) > 0 or Instr(1, request.url, "\") > 0
        return { ok: false, code: "invalid_url", message: "The request URL is not valid." }
    end if
    if request.url.Trim() <> request.url or Instr(1, request.url, Chr(9)) > 0 or Instr(1, request.url, " ") > 0
        return { ok: false, code: "invalid_url", message: "The request URL is not valid." }
    end if
    if not PorticoHttpUrlAllowed(request.url, request.allowInsecureLan)
        return { ok: false, code: "insecure_url", message: "The request URL is not allowed." }
    end if
    if methods[request.method] <> true
        return { ok: false, code: "method_not_supported", message: "The request method is not supported." }
    end if
    if Len(request.body) > limits.maximumBodyBytes
        return { ok: false, code: "body_too_large", message: "The request body is too large." }
    end if

    headerCount = 0
    for each headerName in request.headers
        headerCount = headerCount + 1
        headerValue = request.headers[headerName]
        if not allowSensitiveMaterial and PorticoHttpHeaderIsSensitive(LCase(headerName))
            return { ok: false, code: "sensitive_header_not_allowed", message: "Sensitive authentication headers require a credential-owning Task." }
        end if
        if Len(headerName) = 0 or Len(headerName) > limits.maximumHeaderNameLength
            return { ok: false, code: "invalid_header", message: "A request header is not valid." }
        end if
        if Len(headerValue) > limits.maximumHeaderValueLength
            return { ok: false, code: "invalid_header", message: "A request header is not valid." }
        end if
        if Instr(1, headerName, Chr(10)) > 0 or Instr(1, headerName, Chr(13)) > 0 or Instr(1, headerName, ":") > 0
            return { ok: false, code: "invalid_header", message: "A request header is not valid." }
        end if
        if Instr(1, headerValue, Chr(10)) > 0 or Instr(1, headerValue, Chr(13)) > 0
            return { ok: false, code: "invalid_header", message: "A request header is not valid." }
        end if
    end for
    if headerCount > limits.maximumHeaderCount
        return { ok: false, code: "too_many_headers", message: "The request has too many headers." }
    end if
    if not allowSensitiveMaterial and PorticoHttpBodyContainsCredential(request.body)
        return { ok: false, code: "sensitive_body_not_allowed", message: "Credential-bearing request bodies require a credential-owning Task." }
    end if

    return { ok: true, code: "", message: "" }
end function

function PorticoHttpBodyContainsCredential(body as string) as boolean
    lower = LCase(body)
    sensitiveKeys = [
        Chr(34) + "authorization" + Chr(34),
        Chr(34) + "accesstoken" + Chr(34),
        Chr(34) + "access_token" + Chr(34),
        Chr(34) + "refreshtoken" + Chr(34),
        Chr(34) + "refresh_token" + Chr(34),
        Chr(34) + "devicecode" + Chr(34),
        Chr(34) + "device_code" + Chr(34),
        Chr(34) + "clientsecret" + Chr(34),
        Chr(34) + "client_secret" + Chr(34),
        Chr(34) + "apikey" + Chr(34),
        Chr(34) + "api_key" + Chr(34),
        Chr(34) + "password" + Chr(34),
        Chr(34) + "credential" + Chr(34),
        Chr(34) + "credentials" + Chr(34)
    ]
    for each key in sensitiveKeys
        if Instr(1, lower, key) > 0 then return true
    end for
    return false
end function

function PorticoHttpNewRequestId() as string
    deviceInfo = CreateObject("roDeviceInfo")
    if deviceInfo <> invalid
        requestId = deviceInfo.GetRandomUUID()
        if requestId <> invalid and Len(requestId.Trim()) > 0 then return requestId.Trim()
    end if

    clock = CreateObject("roDateTime")
    timer = CreateObject("roTimespan")
    return "req-" + clock.AsSeconds().ToStr() + "-" + timer.TotalMilliseconds().ToStr()
end function

function PorticoHttpServerAccessTokenValid(value as dynamic) as boolean
    token = PorticoHttpScalarString(value, "")
    prefix = Left(token, 8)
    return (prefix = "ptc_clt_" or prefix = "ptc_loc_") and Len(token) >= 16 and Len(token) <= 4096
end function

function PorticoHttpServerRefreshTokenValid(value as dynamic) as boolean
    token = PorticoHttpScalarString(value, "")
    prefix = Left(token, 8)
    return (prefix = "ptc_rft_" or prefix = "ptc_lrf_") and Len(token) >= 16 and Len(token) <= 4096
end function

function PorticoHttpNormalizeHeaders(rawHeaders as dynamic, requestId as string, hasBody as boolean) as object
    headers = {}
    if PorticoHttpIsAssociativeArray(rawHeaders)
        for each rawName in rawHeaders
            name = PorticoHttpScalarString(rawName, "").Trim()
            value = PorticoHttpScalarString(rawHeaders[rawName], "")
            if name <> "" and LCase(name) <> "x-request-id" then headers[name] = value
        end for
    end if

    headers["X-Request-ID"] = requestId
    if not PorticoHttpHasHeader(headers, "accept")
        headers["Accept"] = "application/json, application/problem+json"
    end if
    if hasBody and not PorticoHttpHasHeader(headers, "content-type")
        headers["Content-Type"] = "application/json"
    end if
    return headers
end function

function PorticoHttpHasHeader(headers as object, targetName as string) as boolean
    normalizedTarget = LCase(targetName)
    for each headerName in headers
        if LCase(headerName) = normalizedTarget then return true
    end for
    return false
end function

function PorticoHttpBodyString(value as dynamic) as string
    if value = invalid then return ""
    if PorticoHttpIsString(value) then return value
    if PorticoHttpIsAssociativeArray(value) or PorticoHttpIsArray(value) then return FormatJson(value)
    return PorticoHttpScalarString(value, "")
end function

function PorticoHttpFileWithinLimit(path as string, maximumBytes as integer) as boolean
    if path = "" or maximumBytes < 1 then return false
    fileSystem = CreateObject("roFileSystem")
    if fileSystem = invalid then return false
    metadata = fileSystem.Stat(path)
    if metadata = invalid or Type(metadata) <> "roAssociativeArray" or metadata.type <> "file" then return false
    size = PorticoHttpInteger(metadata.size, -1)
    return size > 0 and size <= maximumBytes
end function

function PorticoHttpFileSize(path as string) as integer
    if path = "" then return -1
    fileSystem = CreateObject("roFileSystem")
    if fileSystem = invalid then return -1
    metadata = fileSystem.Stat(path)
    if not PorticoHttpIsAssociativeArray(metadata) or metadata.type <> "file" then return -1
    return PorticoHttpInteger(metadata.size, -1)
end function

function PorticoHttpResponsePath(requestId as string) as string
    safeId = PorticoHttpSafeIdentifier(requestId, "request")
    if safeId = "" then safeId = "request"
    return "tmp:/portico-http-" + safeId + ".body"
end function

function PorticoHttpResponseContentLength(headers as dynamic) as dynamic
    if not PorticoHttpIsAssociativeArray(headers) then return invalid
    raw = PorticoHttpScalarString(headers["content-length"], "").Trim()
    if raw = "" then return invalid
    for position = 1 to Len(raw)
        if Instr(1, "0123456789", Mid(raw, position, 1)) = 0 then return invalid
    end for
    value = Int(Val(raw))
    if value < 0 or value > 2147483647 then return invalid
    return value
end function

function PorticoHttpResponseBudget(headers as dynamic) as object
    limits = PorticoHttpLimits()
    if not PorticoHttpIsAssociativeArray(headers) then headers = {}
    declared = PorticoHttpResponseContentLength(headers)
    transferEncoding = LCase(PorticoHttpScalarString(headers["transfer-encoding"], ""))
    chunked = Instr(1, transferEncoding, "chunked") > 0
    if declared <> invalid and transferEncoding = ""
        return {
            ok: declared <= limits.maximumResponseBytes,
            trustedLength: true,
            declaredLength: declared,
            materializationLimit: limits.maximumResponseBytes,
            chunked: chunked
        }
    end if

    ' A missing, malformed, or transfer-encoded length is not proof of a small body. Keep
    ' the fallback below the normal endpoint budget so an uncooperative peer
    ' cannot consume the entire response allowance before classification.
    conservativeLimit = Int(limits.maximumResponseBytes / 2)
    return {
        ok: true,
        trustedLength: false,
        declaredLength: invalid,
        materializationLimit: conservativeLimit,
        chunked: chunked
    }
end function

function PorticoHttpParseJson(body as string) as object
    normalized = body.Trim()
    if normalized = "" then return { ok: true, empty: true, value: invalid }
    parsed = ParseJson(normalized)
    if parsed = invalid and normalized <> "null" then return { ok: false, empty: false, value: invalid }
    return { ok: true, empty: false, value: parsed }
end function

function PorticoHttpIsJsonContentType(headers as object) as boolean
    contentType = LCase(PorticoHttpScalarString(headers["content-type"], ""))
    return Instr(1, contentType, "application/json") > 0 or Instr(1, contentType, "application/problem+json") > 0 or Instr(1, contentType, "+json") > 0
end function

function PorticoHttpResponseHeaders(headerArray as dynamic) as object
    result = {}
    if not PorticoHttpIsArray(headerArray) then return result

    for each headerRecord in headerArray
        if PorticoHttpIsAssociativeArray(headerRecord)
            for each rawName in headerRecord
                name = LCase(PorticoHttpScalarString(rawName, "").Trim())
                if PorticoHttpResponseHeaderAllowed(name)
                    value = PorticoHttpSanitizeHeaderValue(headerRecord[rawName])
                    if value <> "" then result[name] = value
                end if
            end for
        end if
    end for
    return result
end function

function PorticoHttpResponseHeaderAllowed(name as string) as boolean
    allowed = {
        "cache-control": true,
        "content-length": true,
        "content-type": true,
        "etag": true,
        "last-modified": true,
        "retry-after": true,
        "transfer-encoding": true,
        "x-request-id": true,
        "x-ratelimit-limit": true,
        "x-ratelimit-remaining": true,
        "x-ratelimit-reset": true
    }
    return allowed[name] = true
end function

function PorticoHttpSanitizeHeaderValue(value as dynamic) as string
    normalized = PorticoHttpScalarString(value, "")
    normalized = normalized.Replace(Chr(10), "").Replace(Chr(13), "")
    if Len(normalized) > 512 then normalized = Left(normalized, 512)
    return normalized.Trim()
end function

function PorticoHttpNormalizeProblem(status as integer, payload as dynamic, responseHeaders as object, requestId as string, classification as string) as object
    source = payload
    if not PorticoHttpIsAssociativeArray(source) then source = {}

    fallbackCode = PorticoHttpFallbackProblemCode(classification)
    fallbackMessage = PorticoHttpFallbackMessage(classification)
    code = PorticoHttpSafeIdentifier(source.code, fallbackCode)
    title = PorticoHttpSafeMessage(source.title, "")
    detail = PorticoHttpSafeMessage(source.detail, "")
    if detail = "" then detail = PorticoHttpSafeMessage(source.message, "")
    if detail = "" then detail = title
    if detail = "" then detail = fallbackMessage

    serverRequestId = PorticoHttpSafeIdentifier(source.requestId, "")
    if serverRequestId = "" then serverRequestId = PorticoHttpSafeIdentifier(responseHeaders["x-request-id"], "")
    if serverRequestId = "" then serverRequestId = requestId

    problemType = PorticoHttpSafeProblemUri(source.type)
    instance = PorticoHttpSafeProblemUri(source.instance)

    return {
        type: problemType,
        title: title,
        status: status,
        code: code,
        detail: detail,
        instance: instance,
        requestId: serverRequestId
    }
end function

function PorticoHttpSafeMessage(value as dynamic, fallback as string) as string
    limits = PorticoHttpLimits()
    normalized = PorticoHttpScalarString(value, "")
    normalized = normalized.Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ")
    normalized = normalized.Trim()
    if normalized = "" then return fallback

    lower = LCase(normalized)
    sensitiveMarkers = [
        "authorization",
        "device_code",
        "device-code",
        "polling secret",
        "bearer ",
        "access_token",
        "access-token",
        "refresh_token",
        "refresh-token",
        "client_secret",
        "client-secret",
        "api_key",
        "api-key",
        "password",
        "x-portico-csrf",
        "x-portico-device-code",
        "media-grant",
        "grant="
    ]
    for each marker in sensitiveMarkers
        if Instr(1, lower, marker) > 0 then return fallback
    end for

    if Instr(1, lower, "http://") > 0 or Instr(1, lower, "https://") > 0 then return fallback
    if Instr(1, lower, Chr(47) + "users" + Chr(47)) > 0 or Instr(1, lower, "pkg:/") > 0 or Instr(1, lower, "tmp:/") > 0 or Instr(1, lower, "cachefs:/") > 0 then return fallback
    if Len(normalized) > limits.maximumSafeMessageLength then normalized = Left(normalized, limits.maximumSafeMessageLength)
    return normalized
end function

function PorticoHttpRedactHeaders(headers as dynamic) as object
    redacted = {}
    if not PorticoHttpIsAssociativeArray(headers) then return redacted

    for each rawName in headers
        name = PorticoHttpScalarString(rawName, "")
        lower = LCase(name)
        if PorticoHttpHeaderIsSensitive(lower)
            redacted[name] = "[REDACTED]"
        else
            redacted[name] = PorticoHttpSanitizeHeaderValue(headers[rawName])
        end if
    end for
    return redacted
end function

function PorticoHttpHeaderIsSensitive(lowerName as string) as boolean
    sensitive = {
        authorization: true,
        cookie: true,
        "proxy-authorization": true,
        "set-cookie": true,
        "x-api-key": true,
        "x-portico-csrf": true,
        "x-portico-device-code": true
    }
    return sensitive[lowerName] = true
end function

function PorticoHttpRedactUrl(url as string) as string
    safe = url
    queryPosition = Instr(1, safe, "?")
    fragmentPosition = Instr(1, safe, "#")
    cutPosition = 0
    if queryPosition > 0 then cutPosition = queryPosition
    if fragmentPosition > 0 and (cutPosition = 0 or fragmentPosition < cutPosition) then cutPosition = fragmentPosition
    if cutPosition > 0 then safe = Left(safe, cutPosition - 1)

    schemePosition = Instr(1, safe, "://")
    if schemePosition > 0
        authorityStart = schemePosition + 3
        pathPosition = Instr(authorityStart, safe, "/")
        atPosition = Instr(authorityStart, safe, "@")
        if atPosition > 0 and (pathPosition = 0 or atPosition < pathPosition)
            safe = Left(safe, authorityStart - 1) + Mid(safe, atPosition + 1)
        end if
    end if
    return safe
end function

function PorticoHttpUrlAllowed(url as string, allowInsecureLan as boolean) as boolean
    lower = LCase(url.Trim())
    host = PorticoHttpUrlHost(lower)
    if host = "" or PorticoHttpUrlContainsUserInfo(lower) then return false
    if Left(lower, 8) = "https://" then return true
    if not allowInsecureLan or Left(lower, 7) <> "http://" then return false
    return PorticoHttpIsLanHost(host)
end function

function PorticoHttpUrlHost(url as string) as string
    authority = PorticoHttpUrlAuthority(url)
    if authority = "" then return ""
    atPosition = Instr(1, authority, "@")
    if atPosition > 0 then authority = Mid(authority, atPosition + 1)

    if Left(authority, 1) = "["
        bracketPosition = Instr(1, authority, "]")
        if bracketPosition > 0 then return Mid(authority, 2, bracketPosition - 2)
    end if

    colonPosition = Instr(1, authority, ":")
    if colonPosition > 0 then authority = Left(authority, colonPosition - 1)
    return authority
end function

function PorticoHttpUrlContainsUserInfo(url as string) as boolean
    authority = PorticoHttpUrlAuthority(url)
    return Instr(1, authority, "@") > 0
end function

function PorticoHttpUrlAuthority(url as string) as string
    schemePosition = Instr(1, url, "://")
    if schemePosition = 0 then return ""
    authority = Mid(url, schemePosition + 3)
    endPosition = 0
    for each delimiter in ["/", "?", "#"]
        position = Instr(1, authority, delimiter)
        if position > 0 and (endPosition = 0 or position < endPosition) then endPosition = position
    end for
    if endPosition > 0 then authority = Left(authority, endPosition - 1)
    return authority
end function

function PorticoHttpIsLanHost(host as string) as boolean
    if host = "localhost" or host = "::1" then return true
    if Len(host) >= 6 and Right(host, 6) = ".local" then return true

    lower = LCase(host)
    if Left(lower, 2) = "fc" or Left(lower, 2) = "fd" or Left(lower, 4) = "fe80" then return true

    parts = host.Tokenize(".")
    if parts.Count() <> 4 then return false
    for each part in parts
        if part = "" then return false
        number = Val(part)
        if number < 0 or number > 255 or number.ToStr() <> part then return false
    end for

    first = Val(parts[0])
    second = Val(parts[1])
    if first = 10 or first = 127 then return true
    if first = 169 and second = 254 then return true
    if first = 172 and second >= 16 and second <= 31 then return true
    if first = 192 and second = 168 then return true
    return false
end function

function PorticoHttpSafeProblemUri(value as dynamic) as string
    uri = PorticoHttpScalarString(value, "")
    if uri = "" then return ""
    safe = PorticoHttpRedactUrl(uri)
    if Len(safe) > 512 then safe = Left(safe, 512)
    return safe
end function

function PorticoHttpSafeIdentifier(value as dynamic, fallback as string) as string
    limits = PorticoHttpLimits()
    normalized = PorticoHttpScalarString(value, "").Trim()
    if normalized = "" then return fallback
    if Len(normalized) > limits.maximumIdentifierLength then normalized = Left(normalized, limits.maximumIdentifierLength)

    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return fallback
    end for
    return normalized
end function

function PorticoHttpScalarString(value as dynamic, fallback as string) as string
    if value = invalid then return fallback
    if PorticoHttpIsString(value) then return value
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" or valueType = "float" or valueType = "rofloat" or valueType = "double" or valueType = "rodouble" or valueType = "boolean" or valueType = "roboolean"
        return value.ToStr()
    end if
    return fallback
end function

function PorticoHttpInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" or valueType = "float" or valueType = "rofloat" or valueType = "double" or valueType = "rodouble" then return Int(value)
    if PorticoHttpIsString(value) and value.Trim() <> "" then return Int(Val(value))
    return fallback
end function

function PorticoHttpBoolean(value as dynamic, fallback as boolean) as boolean
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "boolean" or valueType = "roboolean" then return value
    return fallback
end function

function PorticoHttpIsString(value as dynamic) as boolean
    valueType = LCase(Type(value))
    return valueType = "string" or valueType = "rostring"
end function

function PorticoHttpIsAssociativeArray(value as dynamic) as boolean
    if value = invalid then return false
    return GetInterface(value, "ifAssociativeArray") <> invalid
end function

function PorticoHttpIsArray(value as dynamic) as boolean
    if value = invalid then return false
    return GetInterface(value, "ifArray") <> invalid
end function
