function PorticoApplicationEventsTaskState() as object
    return {
        envelopeMode: false,
        viewerScope: invalid,
        viewerGeneration: 0,
        activeOperationSequence: 0,
        publicationSequence: 0,
        operationContract: invalid
    }
end function

sub PorticoApplicationEventsTaskAdopt(target as object, state as object)
    for each key in state
        target[key] = state[key]
    end for
end sub

function PorticoApplicationEventsAcceptCommand(controller as object, envelope as dynamic) as dynamic
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" or envelope.version <> 1 then return invalid
    if LCase(PorticoCoreSafeIdentifier(envelope.domain, 64)) <> "application-events" then return invalid
    scope = PorticoViewerScopeNormalize(envelope.viewerScope)
    generation = PorticoViewerScopePositiveInteger(envelope.viewerGeneration)
    sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    command = envelope.command
    if scope = invalid or generation <> scope.viewerGeneration or sequence < 1 or command = invalid or Type(command) <> "roAssociativeArray" then return invalid
    current = PorticoViewerScopeNormalize(controller.viewerScope)
    changed = current = invalid or not PorticoViewerScopeEquals(current, scope)
    if controller.envelopeMode
        if generation < controller.viewerGeneration then return invalid
        if generation = controller.viewerGeneration and changed then return invalid
        if generation = controller.viewerGeneration and sequence <= controller.activeOperationSequence then return invalid
    end if
    loaded = PorticoOperationContractLoad()
    if not loaded.ok then return invalid
    controller.envelopeMode = true
    controller.viewerScope = scope
    controller.viewerGeneration = generation
    controller.activeOperationSequence = sequence
    controller.publicationSequence = 0
    controller.operationContract = loaded.value
    accepted = {}
    for each key in command
        accepted[key] = command[key]
    end for
    return accepted
end function

function PorticoApplicationEventsSession(controller as object) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if scope = invalid or scope.viewerGeneration <> controller.viewerGeneration then return invalid
    record = PorticoSecureRegistryRead("server-session")
    if not record.ok or record.payload = invalid then return invalid
    stored = PorticoServerSessionStored(record.payload)
    if stored = invalid then return invalid
    actual = PorticoServerSessionScope(stored, scope.viewerGeneration)
    if actual = invalid or not PorticoViewerScopeEquals(actual, scope) then return invalid
    return PorticoServerSessionRequestProjection(stored, scope, record.generation)
end function

function PorticoApplicationEventsOperation(controller as object, operationId as string) as object
    if controller.operationContract = invalid then return {ok: false, code: "operation_contract_unavailable"}
    return PorticoOperationContractResolvePath(controller.operationContract, "server", operationId, {})
end function

function PorticoApplicationEventsPollOperationAllowed(operation as dynamic) as boolean
    return operation <> invalid and Type(operation) = "roAssociativeArray" and operation.ok and operation.method = "GET" and operation.path = "/events/poll"
end function

function PorticoApplicationEventsResultEnvelope(controller as object, projection as object) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if not controller.envelopeMode or scope = invalid or controller.activeOperationSequence < 1 then return invalid
    if controller.publicationSequence >= 2147483646 then return invalid
    controller.publicationSequence = controller.publicationSequence + 1
    return {
        version: 1,
        domain: "application-events",
        viewerScope: scope,
        viewerGeneration: controller.viewerGeneration,
        operationSequence: controller.activeOperationSequence,
        publicationSequence: controller.publicationSequence,
        projection: projection
    }
end function

function PorticoApplicationEventsInterrupted(controller as object) as boolean
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return false
    if PorticoViewerScopePositiveInteger(envelope.viewerGeneration) <> controller.viewerGeneration then return true
    return PorticoViewerScopePositiveInteger(envelope.operationSequence) > controller.activeOperationSequence
end function

function PorticoApplicationEventParse(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    if value.Count() < 4 or value.Count() > 7 then return invalid
    allowedKeys = {id: true, type: true, tags: true, createdAt: true, resource: true, resourceId: true, fields: true}
    for each key in value
        if allowedKeys[key] <> true then return invalid
    end for
    id = PorticoApplicationEventPositiveLong(value.id)
    eventType = LCase(PorticoCoreSafeIdentifier(value.type, 80))
    createdAt = PorticoApplicationEventTimestamp(value.createdAt)
    if id = invalid or eventType = "" or createdAt = "" then return invalid
    if value.tags = invalid or GetInterface(value.tags, "ifArray") = invalid or value.tags.Count() > 128 then return invalid
    tags = []
    seen = {}
    for each rawTag in value.tags
        tag = LCase(PorticoCoreSafeIdentifier(rawTag, 80))
        if tag = "" or seen[tag] = true then return invalid
        seen[tag] = true
        tags.Push(tag)
    end for
    resource = ""
    if value.resource <> invalid
        resource = LCase(PorticoCoreSafeIdentifier(value.resource, 80))
        if resource = "" then return invalid
    end if
    resourceId = ""
    if value.resourceId <> invalid
        resourceId = PorticoViewerScopeOpaqueId(value.resourceId, 128)
        if resourceId = "" then return invalid
    end if
    if value.fields <> invalid and not PorticoApplicationEventFieldsValid(value.fields) then return invalid
    return {id: id, type: eventType, tags: tags, resource: resource, resourceId: resourceId, createdAt: createdAt}
end function

function PorticoApplicationEventPositiveLong(value as dynamic) as dynamic
    if value = invalid then return invalid
    valueType = LCase(Type(value))
    if valueType <> "integer" and valueType <> "roint" and valueType <> "longinteger" and valueType <> "rolonginteger" then return invalid
    if value < 1 then return invalid
    return value
end function

function PorticoApplicationEventTimestamp(value as dynamic) as string
    if value = invalid or (Type(value) <> "String" and Type(value) <> "roString") then return ""
    timestamp = value.ToStr()
    if Len(timestamp) < 20 or Len(timestamp) > 64 or timestamp <> timestamp.Trim() then return ""
    date = CreateObject("roDateTime")
    if date = invalid or not date.FromISO8601String(timestamp) then return ""
    return timestamp
end function

function PorticoApplicationEventFieldsValid(value as dynamic) as boolean
    if value = invalid or Type(value) <> "roAssociativeArray" or value.Count() > 64 then return false
    for each key in value
        if PorticoCoreSafeIdentifier(key, 80) = "" then return false
        fieldValue = value[key]
        if fieldValue = invalid or (Type(fieldValue) <> "String" and Type(fieldValue) <> "roString") then return false
        if Len(fieldValue.ToStr()) > 512 or PorticoCoreSafeText(fieldValue, 512) <> fieldValue.ToStr().Trim() then return false
    end for
    return true
end function

function PorticoApplicationEventDirectives(events as dynamic, lastEventId as dynamic) as object
    result = {ok: false, lastEventId: lastEventId, domains: [], resourceIds: [], broadRequired: false}
    if events = invalid or GetInterface(events, "ifArray") = invalid or events.Count() > 100 then return result
    domains = {}
    resourceIds = {}
    highest = lastEventId
    previousBatchId = invalid
    for each rawEvent in events
        eventValue = PorticoApplicationEventParse(rawEvent)
        if eventValue = invalid then return result
        if previousBatchId <> invalid and eventValue.id < previousBatchId then return result
        previousBatchId = eventValue.id
        if eventValue.id > highest
            highest = eventValue.id
            if eventValue.type = "data.changed"
                mappedCount = domains.Count()
                if not PorticoApplicationEventMapTags(eventValue.tags, domains) then domains["_unknown"] = true
                if eventValue.resource <> "" and not PorticoApplicationEventMapTag(eventValue.resource, domains) then domains["_unknown"] = true
                if domains.Count() = mappedCount then domains["_unknown"] = true
                if eventValue.resourceId <> "" then resourceIds[eventValue.resourceId] = true
            else
                domains["_unknown"] = true
            end if
        end if
    end for
    orderedDomains = []
    for each domain in PorticoApplicationEventDomainOrder()
        if domains[domain] = true then orderedDomains.Push(domain)
    end for
    orderedIds = []
    for each resourceId in resourceIds
        if orderedIds.Count() < 100 then orderedIds.Push(resourceId)
    end for
    return {ok: true, lastEventId: highest, domains: orderedDomains, resourceIds: orderedIds, broadRequired: domains["_unknown"] = true or domains["_broad"] = true}
end function

function PorticoApplicationEventMapTags(tags as object, domains as object) as boolean
    known = true
    for each tag in tags
        if not PorticoApplicationEventMapTag(tag, domains) then known = false
    end for
    return known
end function

function PorticoApplicationEventMapTag(tagValue as dynamic, domains as object) as boolean
    tag = LCase(PorticoCoreSafeIdentifier(tagValue, 80))
    if tag = "database" or tag = "background"
        for each domain in PorticoApplicationEventDomainOrder()
            domains[domain] = true
        end for
    else if tag = "media" or tag = "metadata" or tag = "library" or tag = "libraries" or tag = "library-items" or tag = "new-media" or tag = "browse" or tag = "audiobook-entities" or tag = "categories"
        for each domain in ["home", "detail", "search", "library", "saved"]
            domains[domain] = true
        end for
    else if tag = "home"
        domains.home = true
    else if tag = "search"
        domains.search = true
    else if tag = "playlists"
        domains.home = true
        domains.library = true
        domains.saved = true
    else if tag = "favorites" or tag = "watchlist" or tag = "watched" or tag = "history"
        domains.home = true
        domains.detail = true
        domains.saved = true
    else if tag = "media-state"
        domains.detail = true
        domains.saved = true
    else if tag = "playback" or tag = "playback-progress" or tag = "progress" or tag = "resume"
        ' Progress affects Continue Watching and media state, not unrelated
        ' settings/profile surfaces. The Task coalesces native write frequency.
        for each domain in ["home", "detail", "library", "saved"]
            domains[domain] = true
        end for
    else if tag = "dvr" or tag = "live-tv" or tag = "library-channels"
        for each domain in ["home", "library", "channels"]
            domains[domain] = true
        end for
    else if tag = "viewer_preference_documents" or tag = "settings" or tag = "display-preferences"
        for each domain in ["home", "library", "settings"]
            domains[domain] = true
        end for
    else if tag = "profiles" or tag = "users" or tag = "account" or tag = "profile_account_authentications" or tag = "local_profile_pin_credentials" or tag = "automatic_profile_selection_trusts"
        domains.profile = true
        domains.settings = true
    else if tag = "downloads" or tag = "jobs"
        domains.library = true
    else
        return false
    end if
    return true
end function

function PorticoApplicationEventsCapabilityProjection(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    if value.Count() < 1 or value.Count() > 2 then return invalid
    if value.eventTransports = invalid or GetInterface(value.eventTransports, "ifArray") = invalid or value.eventTransports.Count() < 1 or value.eventTransports.Count() > 2 then return invalid
    transports = []
    seen = {}
    for each raw in value.eventTransports
        transport = LCase(PorticoCoreSafeIdentifier(raw, 9))
        if (transport <> "sse" and transport <> "long-poll") or seen[transport] = true then return invalid
        seen[transport] = true
        transports.Push(transport)
    end for
    if value.longPoll = invalid or Type(value.longPoll) <> "roAssociativeArray" or value.longPoll.Count() <> 3 then return invalid
    if value.longPoll.defaultWaitSeconds <> 20 or value.longPoll.maximumWaitSeconds <> 25 or value.longPoll.maximumConcurrentStreams <> 4 then return invalid
    return {eventTransports: transports, longPoll: {defaultWaitSeconds: 20, maximumWaitSeconds: 25, maximumConcurrentStreams: 4}}
end function

function PorticoApplicationEventDomainOrder() as object
    return ["home", "detail", "search", "library", "saved", "channels", "settings", "profile"]
end function

function PorticoApplicationEventsAllDomains() as object
    result = []
    for each domain in PorticoApplicationEventDomainOrder()
        result.Push(domain)
    end for
    return result
end function
