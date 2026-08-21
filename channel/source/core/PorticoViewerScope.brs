function PorticoViewerScopeNormalize(value as dynamic, generation = invalid as dynamic) as dynamic
    if value = invalid or GetInterface(value, "ifAssociativeArray") = invalid then return invalid

    authority = LCase(PorticoViewerScopeString(value.authority, 32))
    accountId = PorticoViewerScopeOpaqueId(value.accountId, 128)
    serverId = PorticoViewerScopeOpaqueId(value.serverId, 128)
    profileId = PorticoViewerScopeOpaqueId(value.profileId, 128)
    authorizationRevision = PorticoViewerScopeOpaqueId(value.authorizationRevision, 128)

    viewerGeneration = PorticoViewerScopePositiveInteger(value.viewerGeneration)
    if generation <> invalid then viewerGeneration = PorticoViewerScopePositiveInteger(generation)

    if authority <> "hosted" and authority <> "local" then return invalid
    if accountId = "" or serverId = "" or profileId = "" or authorizationRevision = "" or viewerGeneration < 1 then return invalid

    return {
        version: 1,
        authority: authority,
        accountId: accountId,
        serverId: serverId,
        profileId: profileId,
        authorizationRevision: authorizationRevision,
        viewerGeneration: viewerGeneration
    }
end function

function PorticoViewerScopeCandidate(value as dynamic) as dynamic
    if value = invalid or GetInterface(value, "ifAssociativeArray") = invalid then return invalid
    candidate = {}
    for each key in value
        candidate[key] = value[key]
    end for
    candidate.viewerGeneration = 1
    normalized = PorticoViewerScopeNormalize(candidate)
    if normalized = invalid then return invalid
    normalized.viewerGeneration = 0
    return normalized
end function

function PorticoViewerScopeWithGeneration(candidate as dynamic, generation as dynamic) as dynamic
    normalizedCandidate = PorticoViewerScopeCandidate(candidate)
    normalizedGeneration = PorticoViewerScopePositiveInteger(generation)
    if normalizedCandidate = invalid or normalizedGeneration < 1 then return invalid
    normalizedCandidate.viewerGeneration = normalizedGeneration
    return normalizedCandidate
end function

function PorticoViewerScopeEquals(leftValue as dynamic, rightValue as dynamic) as boolean
    leftScope = PorticoViewerScopeNormalize(leftValue)
    rightScope = PorticoViewerScopeNormalize(rightValue)
    if leftScope = invalid or rightScope = invalid then return false
    return PorticoViewerScopeCanonicalIdentity(leftScope, true) = PorticoViewerScopeCanonicalIdentity(rightScope, true)
end function

function PorticoViewerScopeOwnerEquals(leftValue as dynamic, rightValue as dynamic) as boolean
    leftScope = PorticoViewerScopeNormalize(leftValue)
    rightScope = PorticoViewerScopeNormalize(rightValue)
    if leftScope = invalid or rightScope = invalid then return false
    return PorticoViewerScopeCanonicalIdentity(leftScope, false) = PorticoViewerScopeCanonicalIdentity(rightScope, false)
end function

function PorticoViewerScopeAuthorizationEquals(leftValue as dynamic, rightValue as dynamic) as boolean
    leftScope = PorticoViewerScopeNormalize(leftValue)
    rightScope = PorticoViewerScopeNormalize(rightValue)
    if leftScope = invalid or rightScope = invalid then return false
    return leftScope.authority = rightScope.authority and leftScope.accountId = rightScope.accountId and leftScope.serverId = rightScope.serverId and leftScope.profileId = rightScope.profileId and leftScope.authorizationRevision = rightScope.authorizationRevision
end function

function PorticoViewerScopeCanonicalIdentity(scope as object, includeGeneration as boolean) as string
    values = [
        scope.authority,
        scope.accountId,
        scope.serverId,
        scope.profileId,
        scope.authorizationRevision
    ]
    if includeGeneration then values.Push(scope.viewerGeneration.ToStr())
    encoded = ""
    for each value in values
        text = value.ToStr()
        encoded = encoded + Len(text).ToStr() + ":" + text
    end for
    return encoded
end function

function PorticoViewerScopeOpaqueId(value as dynamic, maximumLength as integer) as string
    normalized = PorticoViewerScopeString(value, maximumLength + 1)
    if Len(normalized) < 1 or Len(normalized) > maximumLength then return ""
    for position = 1 to Len(normalized)
        code = Asc(Mid(normalized, position, 1))
        if code < 32 or code = 127 then return ""
    end for
    return normalized
end function

function PorticoViewerScopeString(value as dynamic, maximumLength as integer) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    raw = value.ToStr()
    if Len(raw) > maximumLength + 16 then return ""
    for position = 1 to Len(raw)
        code = Asc(Mid(raw, position, 1))
        if code < 32 or code = 127 then return ""
    end for
    normalized = raw.Trim()
    if normalized = "" or Len(normalized) > maximumLength then return ""
    return normalized
end function

function PorticoViewerScopePositiveInteger(value as dynamic) as integer
    if value = invalid then return 0
    valueType = LCase(Type(value))
    if valueType <> "integer" and valueType <> "roint" and valueType <> "longinteger" and valueType <> "rolonginteger" then return 0
    normalized = Int(value)
    if normalized < 1 then return 0
    return normalized
end function
