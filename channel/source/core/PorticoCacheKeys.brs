function PorticoRokuQueryContractRevision() as string
    ' Bump only when Roku query canonicalization or cached response shape changes.
    ' This is intentionally separate from the live Product Contract revision.
    return "portico-roku-query-v1"
end function

function PorticoCacheScopePrefix(scopeValue as dynamic, contractRevisionValue as dynamic) as string
    scope = PorticoViewerScopeNormalize(scopeValue)
    contractRevision = PorticoViewerScopeOpaqueId(contractRevisionValue, 128)
    if scope = invalid or contractRevision = "" then return ""
    scopePart = PorticoCacheSafeComponent(PorticoViewerScopeCanonicalIdentity(scope, false))
    contractPart = PorticoCacheSafeComponent(contractRevision)
    if scopePart = "" or contractPart = "" then return ""
    return "portico.viewer.v1." + Len(scopePart).ToStr() + "." + scopePart + "." + Len(contractPart).ToStr() + "." + contractPart
end function

function PorticoCacheEphemeralPrefix(scopeValue as dynamic, contractRevisionValue as dynamic) as string
    scope = PorticoViewerScopeNormalize(scopeValue)
    contractRevision = PorticoViewerScopeOpaqueId(contractRevisionValue, 128)
    if scope = invalid or contractRevision = "" then return ""
    scopePart = PorticoCacheSafeComponent(PorticoViewerScopeCanonicalIdentity(scope, true))
    contractPart = PorticoCacheSafeComponent(contractRevision)
    if scopePart = "" or contractPart = "" then return ""
    return "portico.ephemeral.v1." + Len(scopePart).ToStr() + "." + scopePart + "." + Len(contractPart).ToStr() + "." + contractPart
end function

function PorticoCacheKey(scopeValue as dynamic, contractRevisionValue as dynamic, semanticResource as dynamic, queryOrView = "" as dynamic) as string
    prefix = PorticoCacheScopePrefix(scopeValue, contractRevisionValue)
    resource = PorticoCacheKeyPart(semanticResource, 240, false)
    query = PorticoCacheKeyPart(queryOrView, 512, true)
    if prefix = "" or resource = "" or query = invalid then return ""
    return PorticoCacheAppendParts(prefix, resource, query)
end function

function PorticoCacheEphemeralKey(scopeValue as dynamic, contractRevisionValue as dynamic, semanticResource as dynamic, queryOrView = "" as dynamic) as string
    prefix = PorticoCacheEphemeralPrefix(scopeValue, contractRevisionValue)
    resource = PorticoCacheKeyPart(semanticResource, 240, false)
    query = PorticoCacheKeyPart(queryOrView, 512, true)
    if prefix = "" or resource = "" or query = invalid then return ""
    return PorticoCacheAppendParts(prefix, resource, query)
end function

function PorticoInstallationScopedKey(scopeValue as dynamic, installationIdValue as dynamic, semanticResource as dynamic, queryOrView = "" as dynamic) as string
    scope = PorticoViewerScopeNormalize(scopeValue)
    installationId = PorticoViewerScopeOpaqueId(installationIdValue, 128)
    resource = PorticoCacheKeyPart(semanticResource, 240, false)
    query = PorticoCacheKeyPart(queryOrView, 512, true)
    if scope = invalid or installationId = "" or resource = invalid or query = invalid then return ""
    scopePart = PorticoCacheSafeComponent(PorticoViewerScopeCanonicalIdentity(scope, false))
    installationPart = PorticoCacheSafeComponent(installationId)
    if scopePart = "" or installationPart = "" then return ""
    prefix = "portico.installation.v1." + Len(scopePart).ToStr() + "." + scopePart + "." + Len(installationPart).ToStr() + "." + installationPart
    return PorticoCacheAppendParts(prefix, resource, query)
end function

function PorticoCacheAppendParts(prefix as string, resource as string, query as string) as string
    resourcePart = PorticoCacheSafeComponent(resource)
    queryPart = PorticoCacheSafeComponent(query)
    if resourcePart = "" then return ""
    return prefix + "." + Len(resourcePart).ToStr() + "." + resourcePart + "." + Len(queryPart).ToStr() + "." + queryPart
end function

function PorticoCacheSafeComponent(value as string) as string
    if value = "" then return ""
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return ""
    return transfer.Escape(value)
end function

function PorticoCacheKeyPart(value as dynamic, maximumLength as integer, allowEmpty as boolean) as dynamic
    if value = invalid
        if allowEmpty then return ""
        return invalid
    end if
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return invalid
    raw = value.ToStr()
    if Len(raw) > maximumLength + 16 then return invalid
    for position = 1 to Len(raw)
        code = Asc(Mid(raw, position, 1))
        if code < 32 or code = 127 then return invalid
    end for
    normalized = raw.Trim()
    if Len(normalized) > maximumLength then return invalid
    if normalized = "" and not allowEmpty then return invalid
    return normalized
end function
