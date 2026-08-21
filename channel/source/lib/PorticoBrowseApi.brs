function PorticoBrowseSessionForServer(serverId as string) as dynamic
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid then return invalid
    session = record.payload
    if session.version <> 1 or PorticoBrowseSafeId(session.serverId) <> serverId then return invalid
    apiBaseUrl = PorticoBrowseSecureBaseUrl(session.apiBaseUrl)
    accessToken = PorticoHttpScalarString(session.accessToken, "")
    if apiBaseUrl = "" or not PorticoHttpServerAccessTokenValid(accessToken) then return invalid
    accountUserId = PorticoBrowseSafeId(session.accountUserId)
    accountDeviceId = PorticoBrowseSafeId(session.accountDeviceId)
    membershipId = PorticoBrowseSafeId(session.membershipId)
    if accountUserId = "" or accountDeviceId = "" or membershipId = "" then return invalid
    remaining = PorticoSignedDocumentSecondsUntil(session.accessExpiresAt)
    if remaining = invalid or remaining <= 0 then return invalid
    return {
        apiBaseUrl: apiBaseUrl,
        accessToken: accessToken,
        generation: record.generation,
        cacheBinding: accountUserId + "|" + accountDeviceId + "|" + membershipId
    }
end function

function PorticoBrowseSecureBaseUrl(value as dynamic) as string
    if value = invalid then return ""
    url = value.ToStr().Trim()
    if Len(url) < 12 or Len(url) > 2048 or Left(LCase(url), 8) <> "https://" then return ""
    if Instr(1, url, Chr(10)) > 0 or Instr(1, url, Chr(13)) > 0 or Instr(1, url, Chr(9)) > 0 or Instr(1, url, " ") > 0 then return ""
    if Instr(9, url, "@") > 0 or Instr(9, url, "?") > 0 or Instr(9, url, "#") > 0 then return ""
    while Right(url, 1) = "/"
        url = Left(url, Len(url) - 1)
    end while
    if Instr(9, url, "/") > 0 then return ""
    return url
end function

function PorticoBrowseRequest(controller as object, session as object, method as string, path as string, body as dynamic) as object
    safePath = PorticoBrowseSafeApiPath(path)
    if safePath = "" then return PorticoBrowseHttpFailure(0, false, "invalid_path")
    request = PorticoHttpNormalizeRequest({
        method: method,
        url: session.apiBaseUrl + safePath,
        body: body,
        headers: { Authorization: "Bearer " + session.accessToken },
        timeoutMs: 15000,
        expectJson: true
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
    if request.method = "GET"
        started = transfer.AsyncGetToString()
    else if request.method = "POST"
        started = transfer.AsyncPostFromString(request.body)
    end if
    if not started then return PorticoBrowseHttpFailure(0, true, "transport_error")
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoBrowseInterrupted(controller)
            transfer.AsyncCancel()
            return { interrupted: true, ok: false, status: 0, retryable: false, data: invalid }
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            status = message.GetResponseCode()
            classification = PorticoHttpClassifyStatus(status)
            if classification.classification <> "success" then return { interrupted: false, ok: false, status: status, retryable: classification.retryable, data: invalid }
            payload = message.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoBrowseHttpFailure(status, false, "response_too_large")
            parsed = PorticoHttpParseJson(payload)
            if not parsed.ok then return PorticoBrowseHttpFailure(status, false, "parse_error")
            return { interrupted: false, ok: true, status: status, retryable: false, data: parsed.value }
        end if
    end while
    transfer.AsyncCancel()
    return PorticoBrowseHttpFailure(0, true, "timeout")
end function

function PorticoBrowseHttpFailure(status as integer, retryable as boolean, code as string) as object
    return { interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: code }
end function

function PorticoBrowseInterrupted(controller as object) as boolean
    if controller.nonInterruptibleRequest = true then return false
    command = m.top.command
    if command = invalid or Type(command) <> "roAssociativeArray" then return false
    return PorticoHttpInteger(command.sequence, 0) > controller.lastCommandSequence
end function

sub PorticoBrowsePrepareArtworkDirectory(namespace as string)
    safeNamespace = PorticoBrowseSafeArtworkKey(namespace)
    if safeNamespace <> "" then CreateDirectory("tmp:/portico-" + safeNamespace)
end sub

sub PorticoBrowseClearArtworkDirectory(namespace as string)
    safeNamespace = PorticoBrowseSafeArtworkKey(namespace)
    if safeNamespace = "" then return
    directory = "tmp:/portico-" + safeNamespace
    files = ListDir(directory)
    if files <> invalid
        for each filename in files
            DeleteFile(directory + "/" + filename)
        end for
    end if
    CreateDirectory(directory)
end sub

sub PorticoBrowseMaterializeArtwork(controller as object, session as object, namespace as string, jobs as object)
    if controller.artworkAccess = invalid or Type(controller.artworkAccess) <> "roAssociativeArray" then controller.artworkAccess = {}
    if controller.artworkAccessCounter = invalid then controller.artworkAccessCounter = 0
    completed = {}
    attempted = 0
    budget = CreateObject("roTimespan")
    budget.Mark()
    for each job in jobs
        if attempted >= 64 or budget.TotalSeconds() >= 20 then return
        if PorticoBrowseInterrupted(controller) then return
        sourceDigest = PorticoBrowseArtworkDigest(job.source + "|" + job.width.ToStr() + "x" + job.height.ToStr())
        cacheKey = PorticoBrowseSafeArtworkKey(controller.serverId + "-" + job.key + "-" + sourceDigest)
        if cacheKey <> ""
            dedupeKey = job.source + "|" + job.width.ToStr() + "x" + job.height.ToStr()
            uri = completed[dedupeKey]
            if uri = invalid
                attempted = attempted + 1
                uri = PorticoBrowseDownloadArtwork(controller, session, namespace, job.source, cacheKey, job.width, job.height)
                completed[dedupeKey] = uri
            end if
            if uri <> invalid and uri <> "" then job.target[job.field] = uri
        end if
    end for
end sub

function PorticoBrowseDownloadArtwork(controller as object, session as object, namespace as string, source as string, cacheKey as string, width as integer, height as integer) as string
    path = PorticoBrowseSafeServerResourcePath(source)
    safeNamespace = PorticoBrowseSafeArtworkKey(namespace)
    if path = "" or safeNamespace = "" then return ""
    separator = "?"
    if Instr(1, path, "?") > 0 then separator = "&"
    request = PorticoHttpNormalizeRequest({
        method: "GET",
        url: session.apiBaseUrl + path + separator + "width=" + width.ToStr() + "&height=" + height.ToStr(),
        body: "",
        headers: { Authorization: "Bearer " + session.accessToken },
        timeoutMs: 5000,
        expectJson: false
    })
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return ""
    directory = "tmp:/portico-" + safeNamespace
    for each extension in ["jpg", "png", "gif"]
        cachedPath = directory + "/" + cacheKey + "." + extension
        if PorticoHttpFileWithinLimit(cachedPath, PorticoHttpLimits().maximumArtworkBytes)
            PorticoBrowseTouchArtwork(controller, cachedPath)
            return cachedPath
        end if
    end for
    tempPath = directory + "/" + cacheKey + ".part"
    DeleteFile(tempPath)
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid then return ""
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest("GET")
    transfer.EnableEncodings(true)
    if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return ""
    if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return ""
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then return ""
    end for
    if not transfer.AsyncGetToFile(tempPath) then return ""
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        if PorticoBrowseInterrupted(controller)
            transfer.AsyncCancel()
            DeleteFile(tempPath)
            return ""
        end if
        message = Wait(100, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            if message.GetResponseCode() < 200 or message.GetResponseCode() >= 300
                DeleteFile(tempPath)
                return ""
            end if
            headers = PorticoHttpResponseHeaders(message.GetResponseHeadersArray())
            contentType = LCase(PorticoHttpScalarString(headers["content-type"], ""))
            extension = ""
            if Left(contentType, 10) = "image/jpeg" then extension = "jpg"
            if Left(contentType, 9) = "image/png" then extension = "png"
            if Left(contentType, 9) = "image/gif" then extension = "gif"
            if extension = ""
                DeleteFile(tempPath)
                return ""
            end if
            if not PorticoHttpFileWithinLimit(tempPath, PorticoHttpLimits().maximumArtworkBytes)
                DeleteFile(tempPath)
                return ""
            end if
            finalPath = directory + "/" + cacheKey + "." + extension
            DeleteFile(finalPath)
            if not MoveFile(tempPath, finalPath)
                DeleteFile(tempPath)
                return ""
            end if
            PorticoBrowseTouchArtwork(controller, finalPath)
            PorticoBrowseTrimArtwork(controller, safeNamespace, finalPath)
            return finalPath
        end if
    end while
    transfer.AsyncCancel()
    DeleteFile(tempPath)
    return ""
end function

function PorticoBrowseArtworkDigest(value as string) as string
    digest = CreateObject("roEVPDigest")
    bytes = CreateObject("roByteArray")
    if digest = invalid or bytes = invalid or not digest.Setup("sha256") then return "source"
    bytes.FromAsciiString(value)
    digest.Process(bytes)
    bytes.Clear()
    hashBytes = digest.Final()
    if hashBytes = invalid then return "source"
    result = LCase(Left(hashBytes.ToHexString(), 20))
    hashBytes.Clear()
    return result
end function

sub PorticoBrowseTouchArtwork(controller as object, path as string)
    if controller.artworkAccess = invalid or Type(controller.artworkAccess) <> "roAssociativeArray" then controller.artworkAccess = {}
    if controller.artworkAccessCounter = invalid then controller.artworkAccessCounter = 0
    controller.artworkAccessCounter = controller.artworkAccessCounter + 1
    if controller.artworkAccessCounter > 2000000000
        controller.artworkAccess = {}
        controller.artworkAccessCounter = 1
    end if
    controller.artworkAccess[path] = controller.artworkAccessCounter
end sub

sub PorticoBrowseTrimArtwork(controller as object, namespace as string, protectedPath as string)
    directory = "tmp:/portico-" + namespace
    files = ListDir(directory)
    if files = invalid then return
    fileSystem = CreateObject("roFileSystem")
    if fileSystem = invalid then return
    candidates = []
    totalBytes = 0
    for each filename in files
        path = directory + "/" + filename
        if Right(LCase(filename), 5) = ".part"
            DeleteFile(path)
        else
            metadata = fileSystem.Stat(path)
            if metadata <> invalid and Type(metadata) = "roAssociativeArray" and metadata.type = "file"
                size = PorticoHttpInteger(metadata.size, 0)
                totalBytes = totalBytes + size
                access = 0
                if controller.artworkAccess <> invalid and controller.artworkAccess[path] <> invalid then access = PorticoHttpInteger(controller.artworkAccess[path], 0)
                candidates.Push({path: path, size: size, access: access})
            end if
        end if
    end for
    ' Enough room for several fully populated poster rows and common channel
    ' art, while remaining deliberately bounded on constrained Roku storage.
    while candidates.Count() > 192 or totalBytes > 134217728
        oldestIndex = -1
        oldestAccess = 2147483647
        for index = 0 to candidates.Count() - 1
            candidate = candidates[index]
            if candidate.path <> protectedPath and candidate.access < oldestAccess
                oldestIndex = index
                oldestAccess = candidate.access
            end if
        end for
        if oldestIndex < 0 then exit while
        removed = candidates[oldestIndex]
        DeleteFile(removed.path)
        totalBytes = totalBytes - removed.size
        if controller.artworkAccess <> invalid then controller.artworkAccess.Delete(removed.path)
        candidates.Delete(oldestIndex)
    end while
end sub

function PorticoBrowseSafeArtworkKey(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr()
    if Len(normalized) < 1 or Len(normalized) > 240 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoBrowseSafeApiPath(value as dynamic) as string
    if value = invalid then return ""
    path = value.ToStr().Trim()
    if Len(path) < 6 or Len(path) > 4096 or Left(path, 5) <> "/api/" then return ""
    if Instr(1, path, Chr(10)) > 0 or Instr(1, path, Chr(13)) > 0 or Instr(1, path, Chr(9)) > 0 or Instr(1, path, " ") > 0 then return ""
    if Instr(1, path, "#") > 0 or Instr(1, path, "@") > 0 then return ""
    route = path
    queryStart = Instr(1, route, "?")
    if queryStart > 0 then route = Left(route, queryStart - 1)
    lowerRoute = LCase(route)
    if Instr(1, route, "..") > 0 or Instr(1, route, "\") > 0 or Instr(1, route, "//") > 0 then return ""
    if Instr(1, lowerRoute, "%2e") > 0 or Instr(1, lowerRoute, "%2f") > 0 or Instr(1, lowerRoute, "%5c") > 0 then return ""
    return path
end function

function PorticoBrowseUrlEncode(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr()
    if Len(normalized) > 4096 then return ""
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return ""
    return transfer.Escape(normalized)
end function
