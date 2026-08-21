function PorticoDeviceAuthorizationController(scene as object, port as object) as object
    task = CreateObject("roSGNode", "PorticoDeviceAuthorizationTask")
    if task = invalid then return { scene: scene, task: invalid, commandSequence: 0 }
    task.ObserveField("projection", port)
    task.control = "RUN"
    return { scene: scene, task: task, commandSequence: 0 }
end function

sub PorticoDeviceAuthorizationHandleActivation(controller as object, activation as dynamic)
    if activation = invalid or Type(activation) <> "roAssociativeArray" then return
    if activation.kind = invalid then return
    kind = activation.kind.ToStr()
    if kind = "start-account-setup"
        PorticoDeviceAuthorizationCommand(controller, "start-account-setup")
    else if kind = "sign-in-account"
        PorticoDeviceAuthorizationCommand(controller, "sign-in-account", {sealedCredentials: activation.sealedCredentials})
    else if kind = "start-local-auth"
        PorticoDeviceAuthorizationCommand(controller, "pause-account-setup")
    else if kind = "pause-account-setup"
        PorticoDeviceAuthorizationCommand(controller, "pause-account-setup")
    else if kind = "sign-out-account"
        PorticoDeviceAuthorizationCommand(controller, "sign-out-account")
    end if
end sub

sub PorticoDeviceAuthorizationPause(controller as object)
    PorticoDeviceAuthorizationCommand(controller, "pause-account-setup")
end sub

sub PorticoDeviceAuthorizationRequestRefresh(controller as object)
    PorticoDeviceAuthorizationCommand(controller, "refresh-account-after-401")
end sub

sub PorticoDeviceAuthorizationHandleNodeEvent(controller as object, event as object)
    if controller.task = invalid or event.GetField() <> "projection" then return
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return
    projection = PorticoDeviceAuthorizationProjection(event.GetData())
    if projection = invalid then return

    current = controller.scene.runtimeState
    nextState = {}
    if current <> invalid and Type(current) = "roAssociativeArray"
        for each key in current
            nextState[key] = current[key]
        end for
    end if
    for each key in projection
        if projection[key] = invalid
            nextState.Delete(key)
        else
            nextState[key] = projection[key]
        end if
    end for
    controller.scene.runtimeState = nextState
end sub

sub PorticoDeviceAuthorizationCommand(controller as object, kind as string, extra = invalid as dynamic)
    if controller.task = invalid then return
    allowed = {
        "start-account-setup": true,
        "sign-in-account": true,
        "pause-account-setup": true,
        "sign-out-account": true,
        "refresh-account-after-401": true
    }
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = { sequence: controller.commandSequence, kind: kind }
    if extra <> invalid and Type(extra) = "roAssociativeArray"
        for each key in extra
            command[key] = extra[key]
        end for
    end if
    controller.task.command = command
end sub

function PorticoDeviceAuthorizationProjection(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    allowed = {
        accountStatus: true,
        hostedStatus: true,
        accountDisplayName: true,
        authorizationUserCode: true,
        verificationDisplayUri: true,
        accountSignInStatus: true,
        accountSignInError: true,
        credentialsDurable: true
    }
    projection = {}
    for each key in source
        if allowed[key] = true then projection[key] = source[key]
    end for
    return projection
end function
