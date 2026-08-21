function PorticoServerCatalogController(scene as object, port as object) as object
    task = CreateObject("roSGNode", "PorticoServerCatalogTask")
    if task = invalid then return { scene: scene, task: invalid, commandSequence: 0 }
    task.ObserveField("projection", port)
    task.control = "RUN"
    return { scene: scene, task: task, commandSequence: 0 }
end function

sub PorticoServerCatalogHandleActivation(controller as object, activation as dynamic)
    if activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = PorticoHttpScalarString(activation.kind, "")
    if kind = "refresh-servers"
        PorticoServerCatalogCommand(controller, kind, "")
    else if kind = "select-server"
        PorticoServerCatalogCommand(controller, kind, activation.targetId)
    end if
end sub

sub PorticoServerCatalogHandleNodeEvent(controller as object, event as object)
    if controller.task = invalid or event.GetField() <> "projection" then return
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return
    projection = PorticoServerCatalogProjection(event.GetData())
    if projection = invalid then return

    current = controller.scene.runtimeState
    nextState = {}
    if current <> invalid and Type(current) = "roAssociativeArray"
        for each key in current
            nextState[key] = current[key]
        end for
    end if
    refreshRequired = projection.accountRefreshRequired = true
    projection.Delete("accountRefreshRequired")
    for each key in projection
        if projection[key] = invalid
            nextState.Delete(key)
        else
            nextState[key] = projection[key]
        end if
    end for
    controller.scene.runtimeState = nextState
    if refreshRequired then controller.scene.accountRefreshRequested = true
end sub

sub PorticoServerCatalogAccountStateChanged(controller as object, state as dynamic)
    if state = invalid or Type(state) <> "roAssociativeArray" then return
    accountStatus = PorticoHttpScalarString(state.accountStatus, "signed-out")
    signedIn = accountStatus = "signed-in" or accountStatus = "refreshing" or accountStatus = "hosted-unavailable"
    PorticoServerCatalogAccountCommand(controller, signedIn, PorticoHttpScalarString(state.hostedStatus, "unknown"))
end sub

sub PorticoServerCatalogAccountCommand(controller as object, signedIn as boolean, hostedStatus as string)
    if controller.task = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    controller.task.command = {
        sequence: controller.commandSequence,
        kind: "account-state",
        accountSignedIn: signedIn,
        hostedStatus: hostedStatus
    }
end sub

sub PorticoServerCatalogCommand(controller as object, kind as string, serverId as dynamic)
    if controller.task = invalid then return
    allowed = { "refresh-servers": true, "select-server": true }
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = { sequence: controller.commandSequence, kind: kind }
    if kind = "select-server" then command.serverId = PorticoServerCatalogBridgeSafeId(serverId)
    controller.task.command = command
end sub

function PorticoServerCatalogProjection(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    allowed = {
        serverListStatus: true,
        availableServers: true,
        selectedServerId: true,
        selectedServerName: true,
        serverStatus: true,
        accountRefreshRequired: true
    }
    projection = {}
    for each key in source
        if allowed[key] = true then projection[key] = source[key]
    end for
    return projection
end function

function PorticoServerCatalogBridgeSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function
