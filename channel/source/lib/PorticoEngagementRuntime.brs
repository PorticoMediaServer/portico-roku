function PorticoEngagementTaskState() as object
    return {
        envelopeMode: false,
        viewerScope: invalid,
        viewerGeneration: 0,
        activeOperationSequence: 0,
        publicationSequence: 0,
        operationContract: invalid
    }
end function

sub PorticoEngagementTaskAdopt(target as object, state as object)
    for each key in state
        target[key] = state[key]
    end for
end sub

function PorticoEngagementAcceptCommand(controller as object, envelope as dynamic) as dynamic
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" or envelope.version <> 1 then return invalid
    if LCase(PorticoCoreSafeIdentifier(envelope.domain, 64)) <> "engagement" then return invalid
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
    accepted.viewerGeneration = generation
    return accepted
end function

function PorticoEngagementSession(controller as object) as dynamic
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

function PorticoEngagementOperation(controller as object, operationId as string, inputs = invalid as dynamic) as object
    if controller.operationContract = invalid then return {ok: false, code: "operation_contract_unavailable"}
    return PorticoOperationContractResolvePath(controller.operationContract, "server", operationId, inputs)
end function

function PorticoEngagementSupportsNotificationLongPoll(operationContract as dynamic) as boolean
    if operationContract = invalid or Type(operationContract) <> "roAssociativeArray" or GetInterface(operationContract.operations, "ifArray") = invalid then return false
    for each operation in operationContract.operations
        if operation <> invalid and Type(operation) = "roAssociativeArray" and operation.operationId = "pollViewerNotificationInvalidations" and operation.service = "server" and operation.method = "GET" and operation.path = "/notifications/events/poll" and PorticoOperationContractRecordAllowed(operation) then return true
    end for
    return false
end function

function PorticoEngagementResultEnvelope(controller as object, projection as object) as dynamic
    scope = PorticoViewerScopeNormalize(controller.viewerScope)
    if not controller.envelopeMode or scope = invalid or controller.activeOperationSequence < 1 then return invalid
    if controller.publicationSequence >= 2147483646 then return invalid
    controller.publicationSequence = controller.publicationSequence + 1
    return {
        version: 1,
        domain: "engagement",
        viewerScope: scope,
        viewerGeneration: controller.viewerGeneration,
        operationSequence: controller.activeOperationSequence,
        publicationSequence: controller.publicationSequence,
        projection: projection
    }
end function

function PorticoEngagementInterrupted(controller as object) as boolean
    envelope = m.top.commandEnvelope
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" then return false
    if PorticoViewerScopePositiveInteger(envelope.viewerGeneration) <> controller.viewerGeneration then return true
    return PorticoViewerScopePositiveInteger(envelope.operationSequence) > controller.activeOperationSequence
end function

function PorticoEngagementNotificationPage(value as dynamic, scope as object, language as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    revision = PorticoEngagementInteger(value.revision, -1)
    unread = PorticoEngagementInteger(value.unreadCount, -1)
    if revision < 0 or unread < 0 or not PorticoEngagementRecipientMatches(value.recipient, scope) then return invalid
    if value.items = invalid or GetInterface(value.items, "ifArray") = invalid then return invalid
    important = invalid
    for each raw in value.items
        item = PorticoEngagementNotification(raw, scope, language)
        if item <> invalid and item.unread and (item.severity = "warning" or item.severity = "error")
            important = item
            exit for
        end if
    end for
    return {revision: revision, unreadCount: unread, recipient: PorticoEngagementRecipient(value.recipient), important: important}
end function

function PorticoEngagementNotification(value as dynamic, scope as object, language as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or not PorticoEngagementRecipientMatches(value.recipient, scope) then return invalid
    id = PorticoViewerScopeOpaqueId(value.id, 128)
    severity = LCase(PorticoCoreSafeText(value.severity, 24))
    if id = "" or (severity <> "warning" and severity <> "error" and severity <> "informational" and severity <> "success") then return invalid
    title = ""
    body = ""
    if value.content <> invalid and Type(value.content) = "roAssociativeArray"
        title = PorticoCoreSafeText(value.content.title, 120)
        body = PorticoCoreSafeText(value.content.body, 1000)
    end if
    message = PorticoProductLanguageMessage(language, value.messageId, "notification.fallback-title", value.interpolation)
    if title = "" then title = PorticoCoreSafeText(message.title, 120)
    if title = "" then title = PorticoCoreSafeText(message.text, 120)
    if body = "" then body = PorticoCoreSafeText(message.body, 1000)
    if body = "" then body = PorticoCoreSafeText(message.text, 1000)
    if title = "" then title = "Notification"
    iconId = PorticoProductLanguageKnownIconId(language, value.iconId)
    return {id: id, severity: severity, title: title, body: body, unread: value.readAt = invalid, iconId: iconId}
end function

function PorticoEngagementRecipient(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    authority = LCase(PorticoCoreSafeText(value.authority, 16))
    audience = LCase(PorticoCoreSafeText(value.audience, 24))
    accountId = PorticoViewerScopeOpaqueId(value.accountId, 128)
    serverId = PorticoViewerScopeOpaqueId(value.serverId, 128)
    profileId = PorticoViewerScopeOpaqueId(value.profileId, 128)
    if (authority <> "hosted" and authority <> "local") or accountId = "" or serverId = "" then return invalid
    if audience <> "profile" then return invalid
    if profileId = "" then return invalid
    return {authority: authority, accountId: accountId, serverId: serverId, audience: audience, profileId: profileId}
end function

function PorticoEngagementRecipientMatches(value as dynamic, scope as object) as boolean
    recipient = PorticoEngagementRecipient(value)
    if recipient = invalid then return false
    return recipient.authority = scope.authority and recipient.accountId = scope.accountId and recipient.serverId = scope.serverId and recipient.profileId = scope.profileId
end function

function PorticoEngagementFeedbackCapabilities(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> "v1" then return invalid
    if Type(value.enabled) <> "Boolean" and Type(value.enabled) <> "roBoolean" then return invalid
    if value.allowedKinds = invalid or GetInterface(value.allowedKinds, "ifArray") = invalid then return invalid
    allowed = {general: true, playback: true, media: true, quality: true}
    kinds = []
    seen = {}
    for each raw in value.allowedKinds
        kind = LCase(PorticoCoreSafeText(raw, 24))
        if allowed[kind] <> true or seen[kind] = true then return invalid
        seen[kind] = true
        kinds.Push(kind)
    end for
    if PorticoEngagementInteger(value.messageMaxLength, 0) <> 1000 then return invalid
    retention = PorticoEngagementInteger(value.retentionDays, 0)
    if retention < 7 or retention > 730 then return invalid
    return {enabled: value.enabled = true, allowedKinds: kinds, retentionDays: retention}
end function

function PorticoEngagementFeedbackSubmission(command as object, capabilities as dynamic, appVersion as string) as dynamic
    if capabilities = invalid or capabilities.enabled <> true then return invalid
    kind = LCase(PorticoCoreSafeText(command.feedbackKind, 24))
    found = false
    for each allowedKind in capabilities.allowedKinds
        if allowedKind = kind then found = true
    end for
    if not found then return invalid
    category = LCase(PorticoCoreSafeText(command.category, 48))
    categories = {"wont-play": true, buffering: true, "playback-stopped": true, "wrong-video": true, "wrong-audio": true, "wrong-subtitles": true, "incorrect-media-information": true, "higher-quality-request": true, other: true}
    if categories[category] <> true then return invalid
    context = {deviceClass: "television", platform: "roku", appVersion: PorticoCoreSafeText(appVersion, 64)}
    if context.appVersion = "" then return invalid
    mediaId = PorticoViewerScopeOpaqueId(command.mediaId, 128)
    playbackSessionId = PorticoViewerScopeOpaqueId(command.playbackSessionId, 128)
    if mediaId <> "" then context.mediaId = mediaId
    if playbackSessionId <> "" then context.playbackSessionId = playbackSessionId
    ' Television feedback is deliberately categorical; no arbitrary viewer text.
    return {version: "v1", kind: kind, category: category, message: "", context: context}
end function

function PorticoEngagementFeedbackReceipt(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(value.id, 128)
    status = LCase(PorticoCoreSafeText(value.status, 16))
    allowed = {new: true, read: true, resolved: true, dismissed: true}
    submittedAt = PorticoCoreSafeText(value.submittedAt, 64)
    if id = "" or allowed[status] <> true or submittedAt = "" then return invalid
    return {id: id, status: status, submittedAt: submittedAt, duplicate: PorticoViewerScopeOpaqueId(value.duplicateOfId, 128) <> ""}
end function

function PorticoEngagementInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    kind = LCase(Type(value))
    if kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" then return fallback
    result = Int(value)
    if result < 0 or result >= 2147480000 then return fallback
    return result
end function
