function PorticoSignedDocumentKeySet(source as dynamic) as object
    if source = invalid or Type(source) <> "roAssociativeArray" then return { ok: false, code: "invalid_key_set", keys: {} }
    if source.schemaVersion <> 1 then return { ok: false, code: "unsupported_key_set", keys: {} }
    activeKeyId = PorticoSignedDocumentSafeKeyId(source.activeKeyId)
    if activeKeyId = "" or source.keys = invalid or GetInterface(source.keys, "ifArray") = invalid then return { ok: false, code: "invalid_key_set", keys: {} }

    trusted = {}
    activeFound = false
    for each record in source.keys
        if record = invalid or Type(record) <> "roAssociativeArray" then return { ok: false, code: "invalid_key_set", keys: {} }
        keyId = PorticoSignedDocumentSafeKeyId(record.keyId)
        algorithm = LCase(PorticoSignedDocumentScalarString(record.algorithm))
        state = LCase(PorticoSignedDocumentScalarString(record.state))
        if keyId = "" or algorithm <> "ed25519" or (state <> "active" and state <> "verification") then return { ok: false, code: "invalid_key_set", keys: {} }
        if trusted[keyId] <> invalid then return { ok: false, code: "duplicate_key", keys: {} }
        publicKey = PorticoSignedDocumentBase64(record.publicKeyB64, false)
        if publicKey = invalid or publicKey.Count() <> 32 then return { ok: false, code: "invalid_public_key", keys: {} }
        trusted[keyId] = record.publicKeyB64.ToStr()
        if keyId = activeKeyId and state = "active" then activeFound = true
    end for
    if not activeFound then return { ok: false, code: "active_key_missing", keys: {} }
    return { ok: true, code: "", keys: trusted }
end function

function PorticoSignedDocumentVerifyRoute(document as dynamic, expectedServerId as string, trustedKeys as object) as object
    if document = invalid or Type(document) <> "roAssociativeArray" then return { ok: false, code: "invalid_route_document" }
    if document.documentVersion <> 1 then return { ok: false, code: "unsupported_route_document" }
    if PorticoSignedDocumentScalarString(document.audience) <> "portico-media-server" then return { ok: false, code: "wrong_audience" }
    if PorticoSignedDocumentScalarString(document.serverId) <> expectedServerId then return { ok: false, code: "server_identity_mismatch" }
    if LCase(PorticoSignedDocumentScalarString(document.signatureAlgorithm)) <> "ed25519" then return { ok: false, code: "unsupported_signature" }
    if document.routes = invalid or GetInterface(document.routes, "ifArray") = invalid then return { ok: false, code: "invalid_routes" }
    if document.authModes = invalid or GetInterface(document.authModes, "ifArray") = invalid then return { ok: false, code: "invalid_auth_modes" }
    if PorticoSignedDocumentRouteGeneration(document) = "" then return { ok: false, code: "route_generation_missing" }

    issuedRemaining = PorticoSignedDocumentSecondsUntil(document.issuedAt)
    expiresRemaining = PorticoSignedDocumentSecondsUntil(document.expiresAt)
    if issuedRemaining = invalid or expiresRemaining = invalid then return { ok: false, code: "invalid_validity_window" }
    validitySeconds = expiresRemaining - issuedRemaining
    if validitySeconds <= 0 or validitySeconds > 600 then return { ok: false, code: "invalid_validity_window" }
    if issuedRemaining > 60 then return { ok: false, code: "not_yet_valid" }
    if expiresRemaining < -60 then return { ok: false, code: "expired_route_document" }

    keyId = PorticoSignedDocumentSafeKeyId(document.signatureKeyId)
    if keyId = "" or trustedKeys = invalid or trustedKeys[keyId] = invalid then return { ok: false, code: "untrusted_signing_key" }
    signature = PorticoSignedDocumentBase64(document.signature, true)
    if signature = invalid or signature.Count() <> 64 then return { ok: false, code: "invalid_signature_encoding" }
    publicKey = PorticoSignedDocumentBase64(trustedKeys[keyId], false)
    if publicKey = invalid or publicKey.Count() <> 32 then return { ok: false, code: "invalid_public_key" }

    canonical = PorticoSignedDocumentCanonicalRoute(document)
    if canonical = "" then return { ok: false, code: "canonicalization_failed" }
    message = CreateObject("roByteArray")
    if message = invalid then return { ok: false, code: "crypto_unavailable" }
    message.FromAsciiString(canonical)

    verification = PorticoSignedDocumentEd25519Verify(publicKey, message, signature)
    if verification < 0 then return { ok: false, code: "crypto_unavailable" }
    if verification <> 1 then return { ok: false, code: "invalid_signature" }
    return { ok: true, code: "" }
end function

function PorticoSignedDocumentRouteGeneration(document as dynamic) as string
    if document = invalid or Type(document) <> "roAssociativeArray" then return ""
    endpoint = PorticoSignedDocumentPositiveRevision(document.endpointGeneration)
    if endpoint <> "" then return endpoint
    if document.routes = invalid or GetInterface(document.routes, "ifArray") = invalid then return ""
    highest = 0
    for each route in document.routes
        if route <> invalid and Type(route) = "roAssociativeArray"
            candidate = PorticoSignedDocumentPositiveRevision(route.generation)
            if candidate <> "" and Int(Val(candidate)) > highest then highest = Int(Val(candidate))
        end if
    end for
    if highest < 1 then return ""
    return highest.ToStr()
end function

function PorticoSignedDocumentPositiveRevision(value as dynamic) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "integer" and valueType <> "longinteger" and valueType <> "float" and valueType <> "double" and valueType <> "roint" and valueType <> "rolonginteger" and valueType <> "rofloat" and valueType <> "rodouble" then return ""
    numeric = Val(value.ToStr())
    if numeric < 1 or Int(numeric) <> numeric then return ""
    return Int(numeric).ToStr()
end function

function PorticoSignedDocumentEd25519Verify(rawPublicKey as object, message as object, signature as object) as integer
    dsa = CreateObject("roDsa")
    if dsa = invalid then return -1
    if not dsa.SetDigestAlgorithm("sha512") then return -1
    if not dsa.SetSignAlgorithm("Ed25519") then return -1

    der = CreateObject("roByteArray")
    if der = invalid then return -1
    der.FromHexString("302A300506032B6570032100")
    der.Append(rawPublicKey)
    encoded = der.ToBase64String()
    if encoded = "" then return -1
    pem = "-----BEGIN PUBLIC KEY-----" + Chr(10)
    offset = 1
    while offset <= Len(encoded)
        pem = pem + Mid(encoded, offset, 64) + Chr(10)
        offset = offset + 64
    end while
    pem = pem + "-----END PUBLIC KEY-----" + Chr(10)
    keyPath = "tmp:/portico-hosted-route-key.pem"
    if not WriteAsciiFile(keyPath, pem) then return -1
    loaded = dsa.SetPublicKey(keyPath)
    DeleteFile(keyPath)
    if loaded <> 1 then return -1
    return dsa.Verify(message, signature)
end function

function PorticoSignedDocumentCanonicalRoute(document as object) as string
    encoded = PorticoSignedDocumentCanonicalJSON(document, true)
    if encoded = "" or Instr(1, encoded, Chr(0)) > 0 then return ""
    return "portico-signed-document:route-document:v1" + Chr(10) + encoded
end function

function PorticoSignedDocumentCanonicalJSON(value as dynamic, omitSignature as boolean, depth = 0 as integer, budget = invalid as dynamic) as string
    ' Route documents are untrusted until this canonical form verifies. Bound
    ' recursive work so a hostile JSON shape cannot exhaust a Roku Task before
    ' the signature check rejects it.
    if budget = invalid then budget = {remaining: 4096}
    if depth > 16 or budget.remaining < 1 then return Chr(0)
    budget.remaining = budget.remaining - 1
    if value = invalid then return "null"
    valueType = Type(value)
    if valueType = "Boolean" or valueType = "roBoolean"
        if value then return "true"
        return "false"
    end if
    if valueType = "String" or valueType = "roString" then return PorticoSignedDocumentJSONString(value.ToStr())
    if valueType = "Integer" or valueType = "LongInteger" or valueType = "Float" or valueType = "Double" or valueType = "roInt" or valueType = "roLongInteger" or valueType = "roFloat" or valueType = "roDouble"
        return value.ToStr()
    end if
    if GetInterface(value, "ifArray") <> invalid
        parts = []
        for each item in value
            part = PorticoSignedDocumentCanonicalJSON(item, false, depth + 1, budget)
            if Instr(1, part, Chr(0)) > 0 then return Chr(0)
            parts.push(part)
        end for
        return "[" + parts.Join(",") + "]"
    end if
    if valueType = "roAssociativeArray"
        keys = []
        for each key in value
            if not (omitSignature and key = "signature") then keys.push(key.ToStr())
        end for
        PorticoSignedDocumentSortKeys(keys)
        parts = []
        for each key in keys
            part = PorticoSignedDocumentCanonicalJSON(value[key], false, depth + 1, budget)
            if Instr(1, part, Chr(0)) > 0 then return Chr(0)
            parts.push(PorticoSignedDocumentJSONString(key) + ":" + part)
        end for
        return "{" + parts.Join(",") + "}"
    end if
    return Chr(0)
end function

function PorticoSignedDocumentJSONString(value as string) as string
    ' Hosted uses Go encoding/json with HTML escaping disabled. Roku's
    ' DontEscape flag preserves UTF-8, while Go still escapes the two Unicode
    ' line separators for safe cross-runtime canonical bytes.
    encoded = FormatJson(value, &h0001)
    unicodeLineSeparator = Chr(&hE2) + Chr(&h80) + Chr(&hA8)
    unicodeParagraphSeparator = Chr(&hE2) + Chr(&h80) + Chr(&hA9)
    return encoded.Replace(unicodeLineSeparator, "\u2028").Replace(unicodeParagraphSeparator, "\u2029")
end function

sub PorticoSignedDocumentSortKeys(keys as object)
    if keys.Count() < 2 then return
    for index = 1 to keys.Count() - 1
        candidate = keys[index]
        cursor = index - 1
        while cursor >= 0 and PorticoSignedDocumentLexicalLess(candidate, keys[cursor])
            keys[cursor + 1] = keys[cursor]
            cursor = cursor - 1
        end while
        keys[cursor + 1] = candidate
    end for
end sub

function PorticoSignedDocumentLexicalLess(leftValue as string, rightValue as string) as boolean
    shared = Len(leftValue)
    if Len(rightValue) < shared then shared = Len(rightValue)
    for index = 1 to shared
        leftCode = Asc(Mid(leftValue, index, 1))
        rightCode = Asc(Mid(rightValue, index, 1))
        if leftCode < rightCode then return true
        if leftCode > rightCode then return false
    end for
    return Len(leftValue) < Len(rightValue)
end function

function PorticoSignedDocumentBase64(value as dynamic, urlSafe as boolean) as dynamic
    if value = invalid then return invalid
    encoded = value.ToStr().Trim()
    if encoded = "" or Len(encoded) > 8192 then return invalid
    if urlSafe
        encoded = encoded.Replace("-", "+").Replace("_", "/")
    end if
    remainder = Len(encoded) mod 4
    if remainder = 1 then return invalid
    if remainder = 2 then encoded = encoded + "=="
    if remainder = 3 then encoded = encoded + "="
    decoded = CreateObject("roByteArray")
    if decoded = invalid then return invalid
    decoded.FromBase64String(encoded)
    if decoded.Count() = 0 then return invalid
    return decoded
end function

function PorticoSignedDocumentSafeKeyId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 3 or Len(normalized) > 80 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoSignedDocumentScalarString(value as dynamic) as string
    if value = invalid then return ""
    valueType = Type(value)
    if valueType <> "String" and valueType <> "roString" then return ""
    return value.ToStr()
end function

function PorticoSignedDocumentSecondsUntil(value as dynamic) as dynamic
    normalized = PorticoSignedDocumentUTCNormalize(value)
    if normalized = "" then return invalid
    clock = CreateObject("roTimespan")
    if clock = invalid then return invalid
    return clock.GetSecondsToISO8601Date(normalized)
end function

function PorticoSignedDocumentUTCNormalize(value as dynamic) as string
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
    if day < 1 or day > PorticoSignedDocumentDaysInMonth(year, month) then return ""
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

function PorticoSignedDocumentDaysInMonth(year as integer, month as integer) as integer
    if month = 2
        leap = (year mod 4 = 0 and year mod 100 <> 0) or year mod 400 = 0
        if leap then return 29
        return 28
    end if
    if month = 4 or month = 6 or month = 9 or month = 11 then return 30
    return 31
end function
