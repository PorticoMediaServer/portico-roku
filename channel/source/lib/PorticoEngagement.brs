function PorticoEngagementController(port as object, viewerController as object) as object
    task = CreateObject("roSGNode", "PorticoEngagementTask")
    if task = invalid then return {task: invalid, port: port, viewerController: viewerController, taskFenced: true}
    task.ObserveField("projectionEnvelope", port)
    task.control = "RUN"
    return {task: task, port: port, viewerController: viewerController, taskFenced: false, serverSignature: ""}
end function

function PorticoEngagementStartTask(controller as object) as boolean
    if controller = invalid or controller.port = invalid then return false
    if controller.task <> invalid then return true
    task = CreateObject("roSGNode", "PorticoEngagementTask")
    if task = invalid then return false
    task.ObserveField("projectionEnvelope", controller.port)
    task.control = "RUN"
    controller.task = task
    controller.taskFenced = false
    return true
end function

function PorticoEngagementViewerCommand(controller as object, values as object) as boolean
    if controller = invalid or controller.task = invalid or controller.viewerController = invalid then return false
    envelope = PorticoViewerRuntimeControllerCommand(controller.viewerController, "engagement", values)
    if envelope = invalid then return false
    controller.task.commandEnvelope = envelope
    return true
end function

function PorticoEngagementViewerStateChanged(controller as object, state as dynamic, capabilities = invalid as dynamic) as boolean
    if controller = invalid or controller.viewerController = invalid or not PorticoViewerRuntimeAccepting(controller.viewerController.runtime) then return false
    if not PorticoEngagementStartTask(controller) then return false
    scope = PorticoViewerRuntimeControllerCurrentScope(controller.viewerController)
    if scope = invalid or state = invalid or Type(state) <> "roAssociativeArray" then return false
    if PorticoViewerScopeOpaqueId(state.selectedServerId, 128) <> scope.serverId then return false
    serverStatus = LCase(PorticoHttpScalarString(state.serverStatus, "not-connected"))
    capabilitySignature = "bounded"
    normalizedCapabilities = PorticoEventTransportCapabilities(capabilities)
    if normalizedCapabilities.longPollAdvertised then capabilitySignature = "long-poll|" + normalizedCapabilities.defaultWaitSeconds.ToStr() + "|" + normalizedCapabilities.maximumWaitSeconds.ToStr() + "|" + normalizedCapabilities.maximumConcurrentStreams.ToStr()
    signature = scope.serverId + "|" + scope.viewerGeneration.ToStr() + "|" + serverStatus + "|" + capabilitySignature
    if controller.serverSignature = signature then return true
    projectedCapabilities = {}
    if capabilities <> invalid and Type(capabilities) = "roAssociativeArray" then projectedCapabilities = capabilities
    issued = PorticoEngagementViewerCommand(controller, {kind: "server-state", serverStatus: serverStatus, capabilities: projectedCapabilities})
    if issued then controller.serverSignature = signature
    return issued
end function

function PorticoEngagementRefresh(controller as object) as boolean
    return PorticoEngagementViewerCommand(controller, {kind: "refresh"})
end function

function PorticoEngagementDismissNotice(controller as object, noticeId as dynamic, revision as dynamic) as boolean
    id = PorticoViewerScopeOpaqueId(noticeId, 128)
    expected = PorticoHttpInteger(revision, -1)
    if id = "" or expected < 0 then return false
    return PorticoEngagementViewerCommand(controller, {kind: "dismiss-notification", notificationId: id, expectedRevision: expected})
end function

function PorticoEngagementSubmitFeedback(controller as object, kind as dynamic, category as dynamic, context = invalid as dynamic) as boolean
    command = {kind: "submit-feedback", feedbackKind: LCase(PorticoCoreSafeText(kind, 24)), category: LCase(PorticoCoreSafeText(category, 48))}
    if context <> invalid and Type(context) = "roAssociativeArray"
        mediaId = PorticoViewerScopeOpaqueId(context.mediaId, 128)
        playbackSessionId = PorticoViewerScopeOpaqueId(context.playbackSessionId, 128)
        if mediaId <> "" then command.mediaId = mediaId
        if playbackSessionId <> "" then command.playbackSessionId = playbackSessionId
    end if
    return PorticoEngagementViewerCommand(controller, command)
end function

function PorticoEngagementCancel(controller as object) as boolean
    if controller = invalid then return false
    if controller.task = invalid
        controller.taskFenced = true
        return true
    end if
    if controller.viewerController = invalid or not PorticoViewerRuntimeAccepting(controller.viewerController.runtime)
        controller.serverSignature = ""
        controller.task.control = "STOP"
        controller.task = invalid
        controller.taskFenced = true
        return true
    end if
    result = PorticoEngagementViewerCommand(controller, {kind: "cancel"})
    if result then controller.serverSignature = ""
    return result
end function

function PorticoEngagementHandleNodeEvent(controller as object, event as object) as object
    if controller = invalid or controller.task = invalid or event.GetField() <> "projectionEnvelope" then return {handled: false, projection: invalid}
    source = event.GetRoSGNode()
    if source = invalid or not source.IsSameNode(controller.task) then return {handled: false, projection: invalid}
    envelope = event.GetData()
    accepted = PorticoViewerRuntimeAcceptProjection(controller.viewerController.runtime, envelope)
    if not accepted.accepted then return {handled: true, projection: invalid}
    return {handled: true, projection: PorticoEngagementProjection(envelope.projection)}
end function

function PorticoEngagementProjection(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    notificationStatus = LCase(PorticoCoreSafeText(value.notificationStatus, 24))
    feedbackStatus = LCase(PorticoCoreSafeText(value.feedbackStatus, 24))
    notificationStates = {idle: true, loading: true, refreshing: true, ready: true, saving: true, stale: true, offline: true, error: true}
    feedbackStates = {idle: true, loading: true, ready: true, sending: true, sent: true, offline: true, error: true}
    if notificationStates[notificationStatus] <> true or feedbackStates[feedbackStatus] <> true then return invalid
    unread = PorticoHttpInteger(value.unreadCount, 0)
    revision = PorticoHttpInteger(value.notificationRevision, 0)
    if unread < 0 or revision < 0 then return invalid
    projection = {
        notificationStatus: notificationStatus,
        feedbackStatus: feedbackStatus,
        errorCode: PorticoCoreSafeIdentifier(value.errorCode, 80),
        unreadCount: unread,
        notificationRevision: revision,
        importantNotice: PorticoEngagementNoticeProjection(value.importantNotice),
        feedbackCapabilities: PorticoEngagementCapabilitiesProjection(value.feedbackCapabilities),
        feedbackReceipt: PorticoEngagementReceiptProjection(value.feedbackReceipt)
    }
    return projection
end function

function PorticoEngagementNoticeProjection(value as dynamic) as dynamic
    if value = invalid then return invalid
    if Type(value) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(value.id, 128)
    severity = LCase(PorticoCoreSafeText(value.severity, 24))
    if id = "" or (severity <> "warning" and severity <> "error") then return invalid
    title = PorticoCoreSafeText(value.title, 120)
    if title = "" then return invalid
    iconId = PorticoCoreSafeIdentifier(value.iconId, 120)
    if iconId = "" then
        if severity = "error" then iconId = "status.error" else iconId = "status.warning"
    end if
    return {id: id, severity: severity, title: title, body: PorticoCoreSafeText(value.body, 1000), iconId: iconId}
end function

function PorticoEngagementCapabilitiesProjection(value as dynamic) as dynamic
    if value = invalid then return invalid
    if Type(value) <> "roAssociativeArray" or value.allowedKinds = invalid or GetInterface(value.allowedKinds, "ifArray") = invalid then return invalid
    result = {enabled: value.enabled = true, allowedKinds: []}
    allowed = {general: true, playback: true, media: true, quality: true}
    for each raw in value.allowedKinds
        kind = LCase(PorticoCoreSafeText(raw, 24))
        if allowed[kind] = true then result.allowedKinds.Push(kind)
    end for
    return result
end function

function PorticoEngagementReceiptProjection(value as dynamic) as dynamic
    if value = invalid then return invalid
    if Type(value) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(value.id, 128)
    status = LCase(PorticoCoreSafeText(value.status, 16))
    allowed = {new: true, read: true, resolved: true, dismissed: true}
    if id = "" or allowed[status] <> true then return invalid
    return {id: id, status: status, duplicate: value.duplicate = true}
end function
