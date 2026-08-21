function PorticoLocalAuthController(scene as object, port as object) as object
    task = CreateObject("roSGNode", "PorticoLocalAuthTask")
    if task = invalid then return {scene: scene, task: invalid, commandSequence: 0, viewerGeneration: 0, profileHandoff: invalid, bootstrapContext: invalid}
    task.ObserveField("projection", port)
    task.control = "RUN"
    return {scene: scene, task: task, commandSequence: 0, viewerGeneration: 0, profileHandoff: invalid, bootstrapContext: invalid}
end function

sub PorticoLocalAuthViewerStateChanged(controller as object, viewerGeneration as integer)
    if controller.task = invalid or viewerGeneration < 1 then return
    controller.profileHandoff = invalid
    controller.bootstrapContext = invalid
    controller.viewerGeneration = viewerGeneration
    PorticoLocalAuthBridgeCommand(controller, "viewer-state", {viewerGeneration: viewerGeneration})
end sub

' An explicit profile switch must mint a fresh one-shot Local Auth handoff. The
' current profile-bound native session is not account/profile-selection authority.
sub PorticoLocalAuthPrepareProfileSwitch(controller as object, viewerGeneration as integer)
    if controller.task = invalid or viewerGeneration < 1 then return
    controller.profileHandoff = invalid
    controller.bootstrapContext = invalid
    controller.viewerGeneration = viewerGeneration
    PorticoLocalAuthBridgeCommand(controller, "prepare-profile-switch", {viewerGeneration: viewerGeneration})
end sub

sub PorticoLocalAuthHandleActivation(controller as object, activation as dynamic)
    if controller.task = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    if kind = "start-local-auth"
        state = controller.scene.runtimeState
        if state <> invalid and Type(state) = "roAssociativeArray" and state.localAuthHasSession = true
            PorticoLocalAuthBridgeCommand(controller, "retry-session", invalid)
        else
            PorticoLocalAuthBridgeCommand(controller, "start-discovery", invalid)
        end if
    else if kind = "local-discover"
        PorticoLocalAuthBridgeCommand(controller, "start-discovery", invalid)
    else if kind = "start-account-setup"
        state = controller.scene.runtimeState
        authMode = ""
        if state <> invalid and Type(state) = "roAssociativeArray" then authMode = LCase(PorticoHttpScalarString(state.authMode, ""))
        if Left(authMode, 5) = "local"
            if state.localAuthHasSession = true
                PorticoLocalAuthBridgeCommand(controller, "sign-out", invalid)
            else
                PorticoLocalAuthBridgeCommand(controller, "cancel", invalid)
            end if
        end if
    else if kind = "local-select-server"
        PorticoLocalAuthBridgeCommand(controller, "select-server", {serverKey: PorticoLocalAuthBridgeSafeId(activation.serverKey)})
    else if kind = "local-manual-address"
        PorticoLocalAuthBridgeCommand(controller, "manual-address", {address: PorticoLocalAuthBridgeSafeAddress(activation.address)})
    else if kind = "local-confirm-trust"
        PorticoLocalAuthBridgeCommand(controller, "confirm-trust", invalid)
    else if kind = "local-submit-credentials"
        PorticoLocalAuthBridgeCommand(controller, "submit-credentials", {sealedCredentials: PorticoLocalAuthBridgeSealed(activation.sealedCredentials)})
    else if kind = "local-retry-session"
        PorticoLocalAuthBridgeCommand(controller, "retry-session", invalid)
    else if kind = "sign-out-local" or kind = "sign-out-account"
        state = controller.scene.runtimeState
        if kind = "sign-out-local" or (state <> invalid and Type(state) = "roAssociativeArray" and state.authMode = "local")
            PorticoLocalAuthBridgeCommand(controller, "sign-out", invalid)
        end if
    else if kind = "local-back" or kind = "back-auth-landing"
        PorticoLocalAuthBridgeCommand(controller, "stop-discovery", invalid)
    end if
end sub

sub PorticoLocalAuthBridgeCommand(controller as object, kind as string, extras as dynamic)
    if controller.task = invalid then return
    allowed = {"viewer-state": true, "prepare-profile-switch": true, "start-discovery": true, "stop-discovery": true, "select-server": true, "manual-address": true, "confirm-trust": true, "submit-credentials": true, "retry-session": true, "sign-out": true, "cancel": true}
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = {sequence: controller.commandSequence, kind: kind, viewerGeneration: controller.viewerGeneration}
    if extras <> invalid and Type(extras) = "roAssociativeArray"
        for each key in extras
            command[key] = extras[key]
        end for
    end if
    controller.task.command = command
end sub

sub PorticoLocalAuthHandleNodeEvent(controller as object, event as object)
    if controller.task = invalid or event.GetField() <> "projection" then return
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return
    source = event.GetData()
    if source = invalid or Type(source) <> "roAssociativeArray" then return
    if source.localProfileSelectionRequired <> true
        controller.profileHandoff = invalid
        controller.bootstrapContext = invalid
    end if
    privateHandoff = source.privateProfileHandoff
    if source.localProfileSelectionRequired = true and privateHandoff <> invalid and Type(privateHandoff) = "roAssociativeArray"
        privateContext = privateHandoff.bootstrapContext
        controller.profileHandoff = {
            handoffId: PorticoLocalAuthBridgeOpaqueId(privateHandoff.handoffId),
            viewerGeneration: PorticoHttpInteger(privateHandoff.viewerGeneration, 0),
            directory: privateHandoff.directory
        }
        if privateContext <> invalid and Type(privateContext) = "roAssociativeArray" and privateContext.provenByCredentialTask = true
            controller.bootstrapContext = {
                authority: "local",
                accountId: PorticoLocalAuthBridgeOpaqueId(privateContext.accountId),
                serverId: PorticoLocalAuthBridgeOpaqueId(privateContext.serverId),
                installationId: PorticoLocalAuthBridgeOpaqueId(privateContext.installationId),
                provenByCredentialTask: true
            }
        end if
    end if
    allowed = {
        localAuthStatus: true,
        localAuthMessage: true,
        localAuthMessageId: true,
        nearbyServers: true,
        selectedLocalServerName: true,
        selectedLocalServerId: true,
        selectedLocalServerFingerprintDisplay: true,
        selectedLocalServerAddress: true,
        localAuthSignedIn: true,
        localAuthHasSession: true,
        localAuthDisplayName: true,
        localAuthServerName: true,
        localAuthServerId: true,
        serverStatus: true,
        navigationSnapshotVerified: true,
        libraryItems: true
    }
    current = controller.scene.runtimeState
    nextState = {}
    currentAuthMode = ""
    if current <> invalid and Type(current) = "roAssociativeArray"
        currentAuthMode = LCase(PorticoHttpScalarString(current.authMode, ""))
        for each key in current
            nextState[key] = current[key]
        end for
    end if
    if source.localProfileSelectionRequired <> true then nextState.Delete("localProfileSelectionRequired")
    ownsSharedServerState = Left(currentAuthMode, 5) = "local"
    for each key in source
        sharedServerField = key = "serverStatus" or key = "navigationSnapshotVerified" or key = "libraryItems"
        if allowed[key] = true and (not sharedServerField or ownsSharedServerState) then nextState[key] = source[key]
    end for
    if source.localProfileSelectionRequired = true and controller.bootstrapContext <> invalid
        nextState.authMode = "local-provisional"
        nextState.accountStatus = "signed-in"
        nextState.localProfileSelectionRequired = true
        nextState.serverStatus = "not-connected"
        nextState.navigationSnapshotVerified = false
        nextState.libraryItems = []
    else if source.localAuthSignedIn = true and ownsSharedServerState
        nextState.authMode = "local"
        nextState.accountStatus = "signed-in"
        nextState.accountDisplayName = PorticoLocalAuthBridgeLabel(source.localAuthDisplayName, "", 80)
        nextState.selectedServerId = PorticoLocalAuthBridgeSafeId(source.localAuthServerId)
        nextState.selectedServerName = PorticoLocalAuthBridgeLabel(source.localAuthServerName, "Portico Server", 80)
        nextState.serverListStatus = "ready"
        nextState.serverStatus = "online"
        nextState.navigationSnapshotVerified = source.navigationSnapshotVerified = true
        if source.libraryItems <> invalid and GetInterface(source.libraryItems, "ifArray") <> invalid
            nextState.libraryItems = source.libraryItems
        else
            nextState.libraryItems = []
        end if
        nextState.availableServers = [{id: nextState.selectedServerId, name: nextState.selectedServerName, status: "online"}]
    else if Left(currentAuthMode, 5) = "local" and (source.localAuthStatus = "signed-out" or source.localAuthStatus = "session-expired")
        nextState.authMode = "none"
        nextState.accountStatus = "signed-out"
        nextState.accountDisplayName = ""
        nextState.selectedServerId = ""
        nextState.selectedServerName = "Portico Server"
        nextState.serverListStatus = "signed-out"
        nextState.serverStatus = "not-connected"
        nextState.navigationSnapshotVerified = false
        nextState.libraryItems = []
        nextState.availableServers = []
    end if
    controller.scene.runtimeState = nextState
end sub

function PorticoLocalAuthTakeProfileHandoff(controller as object) as dynamic
    handoff = controller.profileHandoff
    controller.profileHandoff = invalid
    if handoff = invalid or Type(handoff) <> "roAssociativeArray" then return invalid
    if handoff.handoffId = "" or handoff.viewerGeneration < 1 or handoff.directory = invalid then return invalid
    return handoff
end function

function PorticoLocalAuthBridgeOpaqueId(value as dynamic) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    for position = 1 to Len(normalized)
        code = Asc(Mid(normalized, position, 1))
        if code < 32 or code = 127 then return ""
    end for
    return normalized
end function

function PorticoLocalAuthBridgeSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoLocalAuthBridgeSafeAddress(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 4 or Len(normalized) > 320 then return ""
    if Instr(1, normalized, Chr(0)) > 0 or Instr(1, normalized, Chr(10)) > 0 or Instr(1, normalized, Chr(13)) > 0 or Instr(1, normalized, Chr(9)) > 0 or Instr(1, normalized, " ") > 0 then return ""
    return normalized
end function

function PorticoLocalAuthBridgeSealed(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 8 or Len(normalized) > 8192 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/="
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoLocalAuthBridgeLabel(value as dynamic, fallback as string, maximum as integer) as string
    normalized = fallback
    if value <> invalid then normalized = value.ToStr()
    normalized = normalized.Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then normalized = fallback
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function
