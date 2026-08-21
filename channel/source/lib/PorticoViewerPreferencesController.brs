function PorticoViewerPreferencesController(scene as object, port as object) as object
    task = CreateObject("roSGNode", "PorticoViewerPreferencesTask")
    if task <> invalid
        task.ObserveField("projection", port)
        task.control = "RUN"
    end if
    return {scene: scene, task: task, commandSequence: 0, scope: invalid, installationId: "", online: false, signOutIssued: false}
end function

sub PorticoViewerPreferencesControllerActivate(controller as object, scopeValue as dynamic, installationIdValue as dynamic, online as boolean)
    scope = PorticoViewerScopeNormalize(scopeValue)
    installationId = PorticoProfilesSafeId(installationIdValue)
    if scope = invalid or installationId = ""
        PorticoViewerPreferencesControllerCancel(controller)
        return
    end if
    controller.scope = scope
    controller.installationId = installationId
    controller.online = online
    controller.signOutIssued = false
    PorticoViewerPreferencesControllerCommand(controller, "viewer-state", {
        viewerScope: scope,
        authority: scope.authority,
        accountId: scope.accountId,
        serverId: scope.serverId,
        profileId: scope.profileId,
        installationId: installationId,
        online: online
    })
end sub

sub PorticoViewerPreferencesControllerCancel(controller as object)
    controller.scope = invalid
    controller.installationId = ""
    controller.online = false
    if controller.signOutIssued <> true then PorticoViewerPreferencesControllerCommand(controller, "cancel", {})
    PorticoMainMergeRuntimeState(controller.scene, {preferencesStatus: "idle", preferenceRevisions: {}, viewerPreferences: invalid, preferenceHistoryStatus: "idle", preferenceHistoryResultMessageId: "", automaticProfileTrustStatus: "idle", preferenceErrorMessageId: ""})
end sub

sub PorticoViewerPreferencesControllerSignOut(controller as object)
    controller.scope = invalid
    controller.installationId = ""
    controller.online = false
    controller.signOutIssued = true
    PorticoViewerPreferencesControllerCommand(controller, "sign-out", {})
    PorticoMainMergeRuntimeState(controller.scene, {preferencesStatus: "idle", preferenceRevisions: {}, viewerPreferences: invalid, preferenceHistoryStatus: "idle", automaticProfileTrustStatus: "idle"})
end sub

function PorticoViewerPreferencesControllerHandleProjection(controller as object, event as object, viewerController = invalid as dynamic) as object
    if controller.task = invalid or event.GetField() <> "projection" then return {handled: false}
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return {handled: false}
    projection = event.GetData()
    if projection = invalid or Type(projection) <> "roAssociativeArray" or controller.scope = invalid then return {handled: true, accepted: false}
    if viewerController = invalid or not PorticoViewerRuntimeAccepting(viewerController.runtime) then return {handled: true, accepted: false}
    if not PorticoViewerScopeEquals(PorticoViewerRuntimeControllerCurrentScope(viewerController), controller.scope) then return {handled: true, accepted: false}
    if PorticoHttpInteger(projection.viewerGeneration, 0) <> controller.scope.viewerGeneration then return {handled: true, accepted: false}
    status = LCase(PorticoHttpScalarString(projection.status, "error"))
    if status <> "idle" and status <> "loading" and status <> "ready" and status <> "saving" and status <> "conflict" and status <> "error" then status = "error"
    values = invalid
    revisions = {}
    if projection.values <> invalid and Type(projection.values) = "roAssociativeArray" then values = projection.values
    if projection.revisions <> invalid and Type(projection.revisions) = "roAssociativeArray" then revisions = projection.revisions
    historyStatus = LCase(PorticoHttpScalarString(projection.historyStatus, "idle"))
    if historyStatus <> "idle" and historyStatus <> "clearing" and historyStatus <> "cleared" and historyStatus <> "error" then historyStatus = "error"
    automaticTrustStatus = LCase(PorticoHttpScalarString(projection.automaticTrustStatus, "idle"))
    if automaticTrustStatus <> "idle" and automaticTrustStatus <> "saving" and automaticTrustStatus <> "ready" and automaticTrustStatus <> "storage-error" and automaticTrustStatus <> "error" then automaticTrustStatus = "error"
    PorticoMainMergeRuntimeState(controller.scene, {
        preferencesStatus: status,
        preferenceRevisions: revisions,
        viewerPreferences: values,
        preferenceHistoryStatus: historyStatus,
        preferenceHistoryResultMessageId: PorticoHttpSafeIdentifier(projection.historyResultMessageId, ""),
        automaticProfileTrustStatus: automaticTrustStatus,
        preferenceErrorMessageId: PorticoHttpSafeIdentifier(projection.errorMessageId, "")
    })
    return {handled: true, accepted: true}
end function

' Stable Main integration point for Settings activations. Main may forward every
' activation here; unknown actions are ignored without side effects.
function PorticoViewerPreferencesControllerHandleActivation(controller as object, activation as dynamic) as boolean
    if controller = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return false
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    if kind = "retry-preferences"
        if controller.task = invalid or controller.scope = invalid or not controller.online then return true
        PorticoViewerPreferencesControllerCommand(controller, "reload", {})
        return true
    end if
    if kind = "quiet-retry-preferences"
        if controller.task = invalid or controller.scope = invalid or not controller.online then return true
        PorticoViewerPreferencesControllerCommand(controller, "quiet-reload", {})
        return true
    end if
    if kind = "set-automatic-profile"
        if controller.task = invalid or controller.scope = invalid or not controller.online then return true
        enabled = activation.enabled = true
        PorticoViewerPreferencesControllerCommand(controller, "automatic-profile", {enabled: enabled})
        return true
    end if
    if kind = "clear-watch-history"
        if controller.task = invalid or controller.scope = invalid or not controller.online then return true
        PorticoViewerPreferencesControllerCommand(controller, "clear-watch-history", {})
        return true
    end if
    if kind <> "set-viewer-preference" then return false
    scopeType = LCase(PorticoHttpScalarString(activation.scopeType, "profile-server"))
    revisions = controller.scene.runtimeState.preferenceRevisions
    expectedRevision = -1
    if revisions <> invalid and Type(revisions) = "roAssociativeArray"
        if scopeType = "profile-server" then expectedRevision = PorticoHttpInteger(revisions.profileServer, -1)
        if scopeType = "profile-device-class" then expectedRevision = PorticoHttpInteger(revisions.profileDeviceClass, -1)
        if scopeType = "account-server-installation" then expectedRevision = PorticoHttpInteger(revisions.accountServerInstallation, -1)
    end if
    changes = PorticoViewerPreferencesSafePatch(scopeType, activation.changes)
    if changes = invalid then return true
    PorticoViewerPreferencesControllerPatch(controller, scopeType, expectedRevision, changes)
    return true
end function

function PorticoViewerPreferencesControllerPatch(controller as object, scopeType as string, expectedRevision as integer, changes as dynamic) as boolean
    if controller = invalid or controller.task = invalid or controller.scope = invalid or not controller.online then return false
    normalizedScope = LCase(scopeType)
    if normalizedScope <> "profile-server" and normalizedScope <> "profile-device-class" and normalizedScope <> "account-server-installation" then return false
    if expectedRevision < 0 or changes = invalid or Type(changes) <> "roAssociativeArray" then return false
    PorticoViewerPreferencesControllerCommand(controller, "patch", {scopeType: normalizedScope, expectedRevision: expectedRevision, changes: changes})
    return true
end function

sub PorticoViewerPreferencesControllerCommand(controller as object, kind as string, payload as dynamic)
    if controller.task = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    generation = 0
    if controller.scope <> invalid then generation = controller.scope.viewerGeneration
    command = {sequence: controller.commandSequence, kind: kind, viewerGeneration: generation}
    if payload <> invalid and Type(payload) = "roAssociativeArray"
        for each key in payload
            command[key] = payload[key]
        end for
    end if
    controller.task.command = command
end sub
