function PorticoLocalAuthOpenDiscoverySocket() as dynamic
    port = CreateObject("roMessagePort")
    socket = CreateObject("roDatagramSocket")
    group = CreateObject("roSocketAddress")
    bind = CreateObject("roSocketAddress")
    destination = CreateObject("roSocketAddress")
    if port = invalid or socket = invalid or group = invalid or bind = invalid or destination = invalid then return invalid
    socket.SetMessagePort(port)
    socket.SetReuseAddr(true)
    bind.SetPort(5353)
    if not socket.SetAddress(bind) then return invalid
    group.SetHostName("224.0.0.251")
    group.SetPort(5353)
    if not socket.JoinGroup(group) then return invalid
    destination.SetHostName("224.0.0.251")
    destination.SetPort(5353)
    if not socket.SetSendToAddress(destination) then return invalid
    socket.SetMulticastTTL(1)
    socket.SetMulticastLoop(false)
    socket.NotifyReadable(true)
    return {socket: socket, port: port, group: group}
end function

function PorticoLocalAuthDNSQuery() as object
    bytes = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]
    labels = ["_portico", "_tcp", "local"]
    for each label in labels
        bytes.Push(Len(label))
        for position = 1 to Len(label)
            bytes.Push(Asc(Mid(label, position, 1)))
        end for
    end for
    bytes.Push(0)
    bytes.Push(0)
    bytes.Push(12)
    bytes.Push(0)
    bytes.Push(1)
    result = CreateObject("roByteArray")
    if result = invalid then return invalid
    for each value in bytes
        result.Push(value)
    end for
    return result
end function

sub PorticoLocalAuthMergeDNSPacket(controller as object, packet as object)
    parsed = PorticoLocalAuthParseDNSPacket(packet)
    if parsed = invalid then return
    now = controller.clock.TotalSeconds()
    byName = controller.dnsByName
    for each record in parsed
        current = byName[record.name]
        ' mDNS is untrusted LAN input. Keep the long-lived discovery indexes
        ' bounded even when a peer continuously advertises unique names.
        if current = invalid and byName.Count() >= 256 then continue for
        if current = invalid then current = {ptr: "", target: "", port: 0, txt: {}, addresses: [], ttl: 120}
        if record.type = 12
            current.ptr = record.ptr
            if record.name = "_portico._tcp.local" and record.ptr <> ""
                if controller.dnsInstances[record.ptr] = true or controller.dnsInstances.Count() < 64 then controller.dnsInstances[record.ptr] = true
            end if
        else if record.type = 33
            current.target = record.target
            current.port = record.port
        else if record.type = 16
            current.txt = record.txt
        else if record.type = 1 and record.address <> ""
            addressSeen = false
            for each existingAddress in current.addresses
                if existingAddress = record.address then addressSeen = true
            end for
            if not addressSeen and current.addresses.Count() < 8 then current.addresses.Push(record.address)
        end if
        if record.ttl > 0 and record.ttl < current.ttl then current.ttl = record.ttl
        byName[record.name] = current
    end for
    for each instanceName in controller.dnsInstances
        instance = byName[instanceName]
        if instance <> invalid and instance.target <> "" and instance.port >= 1 and instance.port <= 65535
            txt = instance.txt
            if txt <> invalid and txt.txtversion = "1" and LCase(txt.scheme) = "http"
                fingerprint = PorticoLocalAuthFingerprint(txt.fingerprint)
                serverId = PorticoLocalAuthSafeId(txt.serverid)
                rawServerId = ""
                if txt.serverid <> invalid then rawServerId = txt.serverid.ToStr().Trim()
                if fingerprint <> "" and (rawServerId = "" or serverId <> "")
                    name = PorticoLocalAuthSafeLabel(txt.name, PorticoLocalAuthInstanceLabel(instanceName), 80)
                    targetRecord = byName[instance.target]
                    addresses = []
                    if targetRecord <> invalid and targetRecord.addresses <> invalid then addresses = targetRecord.addresses
                    if addresses.Count() > 0
                        address = PorticoLocalAuthPrivateIPv4(addresses[0])
                        if address <> ""
                            ttl = instance.ttl
                            if ttl < 15 then ttl = 15
                            if ttl > 600 then ttl = 600
                            key = PorticoLocalAuthFingerprintKey(fingerprint)
                            if controller.candidates[key] <> invalid or controller.candidates.Count() < 64
                                controller.candidates[key] = {
                                    key: key,
                                    name: name,
                                    serverId: serverId,
                                    fingerprint: fingerprint,
                                    route: "http://" + address + ":" + instance.port.ToStr(),
                                    expiresAt: now + ttl
                                }
                            end if
                        end if
                    end if
                end if
            end if
        end if
    end for
    PorticoLocalAuthRebuildServerProjection(controller)
end sub

function PorticoLocalAuthParseDNSPacket(packet as object) as dynamic
    if packet = invalid or packet.Count() < 12 then return invalid
    questionCount = PorticoLocalAuthDNSU16(packet, 4)
    answerCount = PorticoLocalAuthDNSU16(packet, 6)
    authorityCount = PorticoLocalAuthDNSU16(packet, 8)
    additionalCount = PorticoLocalAuthDNSU16(packet, 10)
    if questionCount < 0 or questionCount > 32 then return invalid
    totalRecords = answerCount + authorityCount + additionalCount
    if totalRecords < 0 or totalRecords > 256 then return invalid
    cursor = {offset: 12}
    for index = 0 to questionCount - 1
        nameResult = PorticoLocalAuthDNSName(packet, cursor.offset, 0)
        if nameResult = invalid then return invalid
        cursor.offset = nameResult.nextOffset + 4
        if cursor.offset > packet.Count() then return invalid
    end for
    result = []
    for index = 0 to totalRecords - 1
        nameResult = PorticoLocalAuthDNSName(packet, cursor.offset, 0)
        if nameResult = invalid then return invalid
        cursor.offset = nameResult.nextOffset
        if cursor.offset + 10 > packet.Count() then return invalid
        recordType = PorticoLocalAuthDNSU16(packet, cursor.offset)
        ttl = PorticoLocalAuthDNSU32(packet, cursor.offset + 4)
        dataLength = PorticoLocalAuthDNSU16(packet, cursor.offset + 8)
        dataOffset = cursor.offset + 10
        if dataLength < 0 or dataOffset + dataLength > packet.Count() then return invalid
        record = {name: LCase(nameResult.name), type: recordType, ttl: ttl, ptr: "", target: "", port: 0, txt: {}, address: ""}
        if recordType = 12
            value = PorticoLocalAuthDNSName(packet, dataOffset, 0)
            if value <> invalid then record.ptr = LCase(value.name)
        else if recordType = 33 and dataLength >= 6
            record.port = PorticoLocalAuthDNSU16(packet, dataOffset + 4)
            value = PorticoLocalAuthDNSName(packet, dataOffset + 6, 0)
            if value <> invalid then record.target = LCase(value.name)
        else if recordType = 16
            record.txt = PorticoLocalAuthDNSTXT(packet, dataOffset, dataLength)
        else if recordType = 1 and dataLength = 4
            record.address = PorticoLocalAuthDNSByte(packet, dataOffset).ToStr() + "." + PorticoLocalAuthDNSByte(packet, dataOffset + 1).ToStr() + "." + PorticoLocalAuthDNSByte(packet, dataOffset + 2).ToStr() + "." + PorticoLocalAuthDNSByte(packet, dataOffset + 3).ToStr()
        end if
        result.Push(record)
        cursor.offset = dataOffset + dataLength
    end for
    return result
end function

function PorticoLocalAuthDNSName(packet as object, offset as integer, depth as integer) as dynamic
    if depth > 12 or offset < 0 or offset >= packet.Count() then return invalid
    labels = []
    cursor = offset
    nextOffset = -1
    consumed = 0
    while cursor < packet.Count() and consumed < 256
        length = PorticoLocalAuthDNSByte(packet, cursor)
        if length = 0
            cursor = cursor + 1
            if nextOffset < 0 then nextOffset = cursor
            exit while
        end if
        if (length and 192) = 192
            if cursor + 1 >= packet.Count() then return invalid
            pointer = ((length and 63) * 256) + PorticoLocalAuthDNSByte(packet, cursor + 1)
            nested = PorticoLocalAuthDNSName(packet, pointer, depth + 1)
            if nested = invalid then return invalid
            if nested.name <> "" then labels.Push(nested.name)
            if nextOffset < 0 then nextOffset = cursor + 2
            exit while
        end if
        if length < 1 or length > 63 or cursor + 1 + length > packet.Count() then return invalid
        label = PorticoLocalAuthDNSAscii(packet, cursor + 1, length)
        if not PorticoLocalAuthDNSLabelValid(label) then return invalid
        labels.Push(label)
        cursor = cursor + 1 + length
        consumed = consumed + 1 + length
    end while
    if nextOffset < 0 then return invalid
    return {name: PorticoLocalAuthJoin(labels, "."), nextOffset: nextOffset}
end function

function PorticoLocalAuthDNSTXT(packet as object, offset as integer, length as integer) as object
    result = {}
    cursor = offset
    limit = offset + length
    count = 0
    while cursor < limit and count < 32
        itemLength = PorticoLocalAuthDNSByte(packet, cursor)
        cursor = cursor + 1
        if itemLength < 1 or cursor + itemLength > limit then return {}
        item = PorticoLocalAuthDNSAscii(packet, cursor, itemLength)
        separator = Instr(1, item, "=")
        if separator > 1
            key = LCase(Left(item, separator - 1)).Trim()
            value = Mid(item, separator + 1).Trim()
            if PorticoLocalAuthTXTKeyValid(key) and result[key] = invalid then result[key] = value
        end if
        cursor = cursor + itemLength
        count = count + 1
    end while
    return result
end function

sub PorticoLocalAuthExpireCandidates(controller as object)
    now = controller.clock.TotalSeconds()
    changed = false
    for each key in controller.candidates
        if controller.candidates[key].expiresAt <= now
            controller.candidates.Delete(key)
            changed = true
        end if
    end for
    if changed then PorticoLocalAuthRebuildServerProjection(controller)
end sub

sub PorticoLocalAuthRebuildServerProjection(controller as object)
    result = []
    for each key in controller.candidates
        source = controller.candidates[key]
        result.Push({
            id: key,
            name: PorticoLocalAuthSafeLabel(source.name, "Portico Server", 80)
        })
    end for
    result.SortBy("name")
    if result.Count() > 20
        bounded = []
        for index = 0 to 19
            bounded.Push(result[index])
        end for
        result = bounded
    end if
    controller.servers = result
    if result.Count() > 0 and (controller.status = "discovering" or controller.status = "no-servers")
        controller.status = "servers"
        controller.message = ""
    end if
    PorticoLocalAuthPublish(controller)
end sub

function PorticoLocalAuthIdentityFromHealth(baseUrl as string, data as dynamic, routeType as string) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    if LCase(PorticoHttpScalarString(data.status, "")) <> "ok" then return invalid
    fingerprint = PorticoLocalAuthFingerprint(data.serverPublicKeyFingerprint)
    if fingerprint = "" then return invalid
    serverId = PorticoLocalAuthSafeId(data.serverId)
    name = PorticoLocalAuthHostname(data.assignedHostname)
    if name = "" then name = "Portico Server"
    routeKey = PorticoLocalAuthFingerprintKey(fingerprint)
    if routeKey = "" then return invalid
    return {apiBaseUrl: baseUrl, fingerprint: fingerprint, serverId: serverId, name: name, routeType: routeType, routeGeneration: "local-" + routeKey}
end function

function PorticoLocalAuthSystemCompatible(controller as object, baseUrl as string) as boolean
    response = PorticoLocalAuthRequest(controller, "GET", baseUrl + "/api/system", invalid, invalid, 7000)
    if response.interrupted then return false
    if not response.ok
        controller.status = "server-unavailable"
        controller.message = "The Portico Server could not be reached."
        PorticoLocalAuthPublish(controller)
        return false
    end if
    data = response.data
    if data = invalid or Type(data) <> "roAssociativeArray" or data.name <> "Portico" or data.apiVersion <> "v1"
        controller.status = "server-incompatible"
        controller.message = "Update Portico Server before using this Roku."
        PorticoLocalAuthPublish(controller)
        return false
    end if
    capabilities = PorticoLocalAuthRequest(controller, "GET", baseUrl + "/api/auth/capabilities", invalid, invalid, 7000)
    if not capabilities.ok or capabilities.data = invalid or capabilities.data.localCredentialsEnabled <> true
        controller.status = "local-auth-disabled"
        controller.message = "Server Only Authentication is not enabled on this server."
        PorticoLocalAuthPublish(controller)
        return false
    end if
    return true
end function

function PorticoLocalAuthSessionFromCredentials(selected as object, data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or LCase(PorticoHttpScalarString(data.tokenType, "")) <> "bearer" then return invalid
    access = PorticoHttpScalarString(data.accessToken, "")
    refresh = PorticoHttpScalarString(data.refreshToken, "")
    if not PorticoLocalAuthAccessTokenValid(access) or not PorticoLocalAuthRefreshTokenValid(refresh) then return invalid
    accessRemaining = PorticoSignedDocumentSecondsUntil(data.accessExpiresAt)
    refreshRemaining = PorticoSignedDocumentSecondsUntil(data.refreshExpiresAt)
    if accessRemaining = invalid or accessRemaining <= 0 or refreshRemaining = invalid or refreshRemaining <= accessRemaining then return invalid
    user = data.user
    device = data.device
    if user = invalid or Type(user) <> "roAssociativeArray" or device = invalid or Type(device) <> "roAssociativeArray" then return invalid
    userId = PorticoLocalAuthSafeId(user.id)
    deviceId = PorticoLocalAuthSafeId(device.id)
    if userId = "" or deviceId = "" then return invalid
    if PorticoLocalAuthSafeId(device.userId) <> userId then return invalid
    serverId = PorticoLocalAuthSafeId(data.serverId)
    if serverId = "" then serverId = PorticoLocalAuthSafeId(selected.serverId)
    if selected.serverId <> "" and serverId <> selected.serverId then return invalid
    if serverId = "" then serverId = "local." + PorticoLocalAuthFingerprintKey(selected.fingerprint)
    routeGeneration = PorticoLocalAuthSafeId(selected.routeGeneration)
    if routeGeneration = "" then routeGeneration = "local-" + PorticoLocalAuthFingerprintKey(selected.fingerprint)
    if routeGeneration = "" then return invalid
    return {
        version: 1,
        authMode: "local",
        serverId: serverId,
        serverName: PorticoLocalAuthSafeLabel(data.serverFriendlyName, selected.name, 80),
        apiBaseUrl: selected.apiBaseUrl,
        routeType: selected.routeType,
        serverPublicKeyFingerprint: selected.fingerprint,
        routeGeneration: routeGeneration,
        accountUserId: userId,
        accountDeviceId: deviceId,
        accountDisplayName: PorticoLocalAuthSafeLabel(user.displayName, PorticoLocalAuthSafeLabel(user.username, "", 80), 80),
        membershipId: "local." + userId,
        accessToken: access,
        refreshToken: refresh,
        accessExpiresAt: PorticoHttpScalarString(data.accessExpiresAt, ""),
        refreshExpiresAt: PorticoHttpScalarString(data.refreshExpiresAt, "")
    }
end function

function PorticoLocalAuthStoredSession(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> 1 or value.authMode <> "local" then return invalid
    if PorticoLocalAuthSecureBaseUrl(value.apiBaseUrl) = "" then return invalid
    if PorticoLocalAuthSafeId(value.serverId) = "" or PorticoLocalAuthFingerprint(value.serverPublicKeyFingerprint) = "" or PorticoLocalAuthSafeId(value.routeGeneration) = "" then return invalid
    if PorticoLocalAuthSafeId(value.accountUserId) = "" or PorticoLocalAuthSafeId(value.accountDeviceId) = "" then return invalid
    if not PorticoLocalAuthAccessTokenValid(PorticoHttpScalarString(value.accessToken, "")) then return invalid
    if not PorticoLocalAuthRefreshTokenValid(PorticoHttpScalarString(value.refreshToken, "")) then return invalid
    if PorticoSignedDocumentSecondsUntil(value.refreshExpiresAt) <= 0 then return invalid
    return value
end function

function PorticoLocalAuthPersistTrust(selected as object) as boolean
    record = PorticoSecureRegistryRead("local-auth-trust")
    pins = []
    if record.ok and record.payload <> invalid and record.payload.pins <> invalid and GetInterface(record.payload.pins, "ifArray") <> invalid
        for each pin in record.payload.pins
            if pins.Count() >= 15 then exit for
            if pin <> invalid and Type(pin) = "roAssociativeArray" and PorticoLocalAuthSecureBaseUrl(pin.apiBaseUrl) <> "" and PorticoLocalAuthFingerprint(pin.fingerprint) <> "" and pin.apiBaseUrl <> selected.apiBaseUrl
                pins.Push(pin)
            end if
        end for
    end if
    pins.Push({apiBaseUrl: selected.apiBaseUrl, serverId: PorticoLocalAuthSafeId(selected.serverId), fingerprint: selected.fingerprint, name: PorticoLocalAuthSafeLabel(selected.name, "Portico Server", 80)})
    committed = PorticoSecureRegistryCommit("local-auth-trust", {version: 1, pins: pins})
    return committed.ok
end function

function PorticoLocalAuthTrustPin(baseUrl as string) as dynamic
    record = PorticoSecureRegistryRead("local-auth-trust")
    if not record.ok or record.payload = invalid or record.payload.pins = invalid or GetInterface(record.payload.pins, "ifArray") = invalid then return invalid
    for each pin in record.payload.pins
        if pin <> invalid and Type(pin) = "roAssociativeArray" and pin.apiBaseUrl = baseUrl and PorticoLocalAuthFingerprint(pin.fingerprint) <> "" then return pin
    end for
    return invalid
end function

function PorticoLocalAuthOpenSealedCredentials(value as dynamic) as dynamic
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

function PorticoLocalAuthRequest(controller as object, method as string, url as string, body = invalid as dynamic, headers = invalid as dynamic, timeoutMs = 10000 as integer, allowInsecureHint = false as boolean) as object
    requestHeaders = {}
    if headers <> invalid and Type(headers) = "roAssociativeArray"
        for each key in headers
            requestHeaders[key] = headers[key]
        end for
    end if
    request = PorticoHttpNormalizeRequest({method: method, url: url, body: body, headers: requestHeaders, timeoutMs: timeoutMs, expectJson: true, allowInsecureLan: allowInsecureHint})
    validation = PorticoHttpValidatePrivateRequest(request)
    if not validation.ok then return PorticoLocalAuthFailure(0, false, validation.code)
    transfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    if transfer = invalid or port = invalid then return PorticoLocalAuthFailure(0, true, "transport_error")
    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    if Left(LCase(request.url), 8) = "https://"
        if not transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then return PorticoLocalAuthFailure(0, true, "transport_error")
        if not transfer.EnablePeerVerification(true) or not transfer.EnableHostVerification(true) then return PorticoLocalAuthFailure(0, true, "transport_error")
    else if not allowInsecureHint
        return PorticoLocalAuthFailure(0, false, "insecure_url")
    end if
    for each key in request.headers
        if not transfer.AddHeader(key, request.headers[key]) then return PorticoLocalAuthFailure(0, false, "invalid_header")
    end for
    started = false
    if request.method = "POST"
        started = transfer.AsyncPostFromString(request.body)
    else
        started = transfer.AsyncGetToString()
    end if
    if not started then return PorticoLocalAuthFailure(0, true, "transport_error")
    timer = CreateObject("roTimespan")
    timer.Mark()
    identity = transfer.GetIdentity()
    while timer.TotalMilliseconds() < request.timeoutMs
        command = m.top.command
        if command <> invalid and Type(command) = "roAssociativeArray" and PorticoHttpInteger(command.sequence, 0) > controller.lastCommandSequence
            transfer.AsyncCancel()
            return {interrupted: true, ok: false, status: 0, retryable: false, data: invalid}
        end if
        message = Wait(75, port)
        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = identity
            status = message.GetResponseCode()
            classification = PorticoHttpClassifyStatus(status)
            payload = message.GetString()
            if Len(payload) > PorticoHttpLimits().maximumResponseBytes then return PorticoLocalAuthFailure(status, false, "response_too_large")
            parsed = PorticoHttpParseJson(payload)
            if classification.classification = "success" and parsed.ok then return {interrupted: false, ok: true, status: status, retryable: false, data: parsed.value}
            failure = PorticoLocalAuthFailure(status, classification.retryable, "request_failed")
            if parsed.ok and parsed.value <> invalid and Type(parsed.value) = "roAssociativeArray" then failure.problem = parsed.value
            return failure
        end if
    end while
    transfer.AsyncCancel()
    return PorticoLocalAuthFailure(0, true, "timeout")
end function

function PorticoLocalAuthFailure(status as integer, retryable as boolean, code as string) as object
    return {interrupted: false, ok: false, status: status, retryable: retryable, data: invalid, code: code}
end function

function PorticoLocalAuthSecureBaseUrl(value as dynamic) as string
    if value = invalid then return ""
    url = value.ToStr().Trim()
    if url = "" then return ""
    if Left(LCase(url), 8) <> "https://" then url = "https://" + url
    if Len(url) < 12 or Len(url) > 2048 then return ""
    if Instr(1, url, Chr(0)) > 0 or Instr(1, url, Chr(10)) > 0 or Instr(1, url, Chr(13)) > 0 or Instr(1, url, Chr(9)) > 0 or Instr(1, url, " ") > 0 or Instr(1, url, "\") > 0 then return ""
    if Instr(9, url, "@") > 0 or Instr(9, url, "?") > 0 or Instr(9, url, "#") > 0 then return ""
    while Right(url, 1) = "/"
        url = Left(url, Len(url) - 1)
    end while
    if Instr(9, url, "/") > 0 then return ""
    return url
end function

function PorticoLocalAuthDisplayOrigin(value as dynamic) as string
    url = PorticoLocalAuthSecureBaseUrl(value)
    if url = "" then return ""
    if Len(url) > 100 then return Left(url, 100)
    return url
end function

function PorticoLocalAuthHostname(value as dynamic) as string
    if value = invalid then return ""
    host = LCase(value.ToStr().Trim())
    if Len(host) < 4 or Len(host) > 253 or Left(host, 1) = "." or Right(host, 1) = "." or Instr(1, host, "..") > 0 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789.-"
    for position = 1 to Len(host)
        if Instr(1, allowed, Mid(host, position, 1)) = 0 then return ""
    end for
    return host
end function

function PorticoLocalAuthPrivateIPv4(value as dynamic) as string
    if value = invalid then return ""
    address = value.ToStr().Trim()
    parts = address.Split(".")
    if parts.Count() <> 4 then return ""
    numbers = []
    for each part in parts
        if part = "" then return ""
        number = Int(Val(part))
        if number < 0 or number > 255 or number.ToStr() <> part then return ""
        numbers.Push(number)
    end for
    if numbers[0] = 10 then return address
    if numbers[0] = 192 and numbers[1] = 168 then return address
    if numbers[0] = 172 and numbers[1] >= 16 and numbers[1] <= 31 then return address
    if numbers[0] = 169 and numbers[1] = 254 then return address
    return ""
end function

function PorticoLocalAuthFingerprint(value as dynamic) as string
    if value = invalid then return ""
    fingerprint = value.ToStr().Trim()
    if Len(fingerprint) <> 50 or Left(fingerprint, 7) <> "sha256:" then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
    for position = 8 to 50
        if Instr(1, allowed, Mid(fingerprint, position, 1)) = 0 then return ""
    end for
    return fingerprint
end function

function PorticoLocalAuthFingerprintKey(fingerprint as string) as string
    normalized = PorticoLocalAuthFingerprint(fingerprint)
    if normalized = "" then return ""
    return LCase(Mid(normalized, 8, 24))
end function

function PorticoLocalAuthFingerprintDisplay(fingerprint as string) as string
    normalized = PorticoLocalAuthFingerprint(fingerprint)
    if normalized = "" then return ""
    token = UCase(Mid(normalized, 8, 16))
    return Left(token, 4) + " " + Mid(token, 5, 4) + " " + Mid(token, 9, 4) + " " + Mid(token, 13, 4)
end function

function PorticoLocalAuthAccessTokenValid(value as string) as boolean
    return Left(value, 8) = "ptc_loc_" and Len(value) >= 24 and Len(value) <= 4096
end function

function PorticoLocalAuthRefreshTokenValid(value as string) as boolean
    return Left(value, 8) = "ptc_lrf_" and Len(value) >= 24 and Len(value) <= 4096
end function

function PorticoLocalAuthSecret(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    result = value.ToStr()
    if Len(result) > maximum then return ""
    if Instr(1, result, Chr(0)) > 0 or Instr(1, result, Chr(10)) > 0 or Instr(1, result, Chr(13)) > 0 then return ""
    return result
end function

function PorticoLocalAuthSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoLocalAuthSafeLabel(value as dynamic, fallback as string, maximum as integer) as string
    normalized = fallback
    if value <> invalid then normalized = value.ToStr()
    normalized = normalized.Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then normalized = fallback
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function

function PorticoLocalAuthDeviceName() as string
    info = CreateObject("roDeviceInfo")
    if info <> invalid
        name = PorticoLocalAuthSafeLabel(info.GetFriendlyName(), "", 80)
        if name <> "" then return "Portico on " + name
    end if
    return "Portico Roku"
end function

function PorticoLocalAuthDNSByte(packet as object, offset as integer) as integer
    if packet = invalid or offset < 0 or offset >= packet.Count() then return 0
    return packet[offset]
end function

function PorticoLocalAuthDNSU16(packet as object, offset as integer) as integer
    return PorticoLocalAuthDNSByte(packet, offset) * 256 + PorticoLocalAuthDNSByte(packet, offset + 1)
end function

function PorticoLocalAuthDNSU32(packet as object, offset as integer) as integer
    high = PorticoLocalAuthDNSU16(packet, offset)
    low = PorticoLocalAuthDNSU16(packet, offset + 2)
    if high > 32767 then return 2147483647
    return high * 65536 + low
end function

function PorticoLocalAuthDNSAscii(packet as object, offset as integer, length as integer) as string
    if packet = invalid or offset < 0 or length < 0 or offset + length > packet.Count() then return ""
    bytes = packet.Slice(offset, offset + length)
    if bytes = invalid then return ""
    value = bytes.ToAsciiString()
    if Len(value) = 0 and length > 0 then return ""
    for position = 0 to length - 1
        code = packet[offset + position]
        if code < 32 or code = 127 then return ""
    end for
    return value
end function

function PorticoLocalAuthDNSLabelValid(value as string) as boolean
    if value = "" or Len(value) > 63 then return false
    for position = 1 to Len(value)
        code = Asc(Mid(value, position, 1))
        if code < 32 or code = 127 then return false
    end for
    return true
end function

function PorticoLocalAuthTXTKeyValid(value as string) as boolean
    if value = "" or Len(value) > 32 then return false
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789"
    for position = 1 to Len(value)
        if Instr(1, allowed, Mid(value, position, 1)) = 0 then return false
    end for
    return true
end function

function PorticoLocalAuthJoin(values as object, separator as string) as string
    result = ""
    for each value in values
        if result <> "" then result = result + separator
        result = result + value
    end for
    return result
end function

function PorticoLocalAuthInstanceLabel(value as string) as string
    suffix = "._portico._tcp.local"
    if Right(LCase(value), Len(suffix)) = suffix then return Left(value, Len(value) - Len(suffix))
    return value
end function

' This projection helper lives with the Local Auth library because discovery
' parsing invokes it and Roku compiles library source independently from the
' credential-owning Task script. It is executed only in that Task's scope.
sub PorticoLocalAuthPublish(controller as object)
    selectedName = ""
    selectedServerId = ""
    selectedFingerprintDisplay = ""
    selectedBaseUrl = ""
    if controller.selected <> invalid
        selectedName = PorticoLocalAuthSafeLabel(controller.selected.name, "Portico Server", 80)
        selectedServerId = PorticoLocalAuthSafeId(controller.selected.serverId)
        selectedFingerprintDisplay = PorticoLocalAuthFingerprintDisplay(controller.selected.fingerprint)
        selectedBaseUrl = PorticoLocalAuthDisplayOrigin(controller.selected.apiBaseUrl)
    end if
    displayName = ""
    authenticatedServerName = ""
    authenticatedServerId = ""
    if controller.session <> invalid
        displayName = PorticoLocalAuthSafeLabel(controller.session.accountDisplayName, "", 80)
        authenticatedServerName = PorticoLocalAuthSafeLabel(controller.session.serverName, "Portico Server", 80)
        authenticatedServerId = PorticoLocalAuthSafeId(controller.session.serverId)
    end if
    projectedServerStatus = "not-connected"
    if controller.status = "authenticated"
        projectedServerStatus = "online"
    else if controller.session <> invalid and controller.status = "restoring"
        projectedServerStatus = "connecting"
    else if controller.session <> invalid
        projectedServerStatus = "offline"
    end if
    projection = {
        localAuthStatus: controller.status,
        localAuthMessage: PorticoLocalAuthSafeLabel(controller.message, "", 240),
        localAuthMessageId: PorticoLocalAuthMessageId(controller.status),
        nearbyServers: controller.servers,
        selectedLocalServerName: selectedName,
        selectedLocalServerId: selectedServerId,
        selectedLocalServerFingerprintDisplay: selectedFingerprintDisplay,
        selectedLocalServerAddress: selectedBaseUrl,
        localAuthSignedIn: controller.status = "authenticated",
        localAuthHasSession: controller.session <> invalid,
        localAuthDisplayName: displayName,
        localAuthServerName: authenticatedServerName,
        localAuthServerId: authenticatedServerId,
        serverStatus: projectedServerStatus,
        navigationSnapshotVerified: controller.navigationVerified,
        libraryItems: controller.libraryItems
    }
    if controller.localProfileDirectory <> invalid and controller.localProfileHandoffId <> "" and controller.localProfileInstallationId <> ""
        projection.localProfileSelectionRequired = true
        ' Credential-Task-proven private handoff. The bridge captures this
        ' atomically and never merges it into Scene/runtimeState.
        projection.privateProfileHandoff = {
            handoffId: controller.localProfileHandoffId,
            viewerGeneration: controller.viewerGeneration,
            directory: controller.localProfileDirectory,
            bootstrapContext: {
                authority: "local",
                accountId: controller.localProfileDirectory.accountId,
                serverId: controller.localProfileDirectory.serverId,
                installationId: controller.localProfileInstallationId,
                provenByCredentialTask: true
            }
        }
    end if
    m.top.projection = projection
end sub

function PorticoLocalAuthMessageId(status as string) as string
    normalized = LCase(status)
    if normalized = "credentials-error" then return "auth.invalid-credentials"
    if normalized = "profile-selection-required" then return "auth.profile-selection-required"
    if normalized = "server-unavailable" or normalized = "no-servers" or normalized = "discovery-unavailable" then return "problem.server-unavailable"
    if normalized = "identity-error" or normalized = "manual-address-error" then return "problem.connection-failed"
    if normalized = "storage-error" or normalized = "session-error" then return "problem.request-failed"
    return ""
end function
