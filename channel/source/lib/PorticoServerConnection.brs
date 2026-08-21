function PorticoServerConnectionController(scene as object, port as object) as object
    task = CreateObject("roSGNode", "PorticoServerConnectionTask")
    if task = invalid then return {scene: scene, task: invalid, commandSequence: 0, pendingScopeAssertion: invalid, bootstrapContext: invalid, restoreContext: invalid, accountSignedIn: false}
    task.ObserveField("projection", port)
    task.control = "RUN"
    return {scene: scene, task: task, commandSequence: 0, pendingScopeAssertion: invalid, bootstrapContext: invalid, restoreContext: invalid, accountSignedIn: false}
end function

sub PorticoServerConnectionInitialize(controller as object, viewerGeneration as integer)
    if viewerGeneration < 1 then return
    PorticoServerConnectionBridgeSend(controller, "initialize", {
        viewerGeneration: viewerGeneration,
        accountSignedIn: controller.accountSignedIn = true
    })
end sub

sub PorticoServerConnectionHandleActivation(controller as object, activation as dynamic, runtimeState as dynamic)
    if not PorticoServerConnectionBridgeAA(activation) then return
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    if kind = "retry-server"
        PorticoServerConnectionBridgeSend(controller, "retry-server", invalid)
    end if
end sub

sub PorticoServerConnectionAccountStateChanged(controller as object, state as dynamic)
    if controller.task = invalid or not PorticoServerConnectionBridgeAA(state) then return
    accountStatus = LCase(PorticoHttpScalarString(state.accountStatus, "signed-out"))
    signedIn = accountStatus = "signed-in" or accountStatus = "refreshing" or accountStatus = "hosted-unavailable"
    controller.accountSignedIn = signedIn
    if not signedIn then controller.bootstrapContext = invalid
    PorticoServerConnectionBridgeSend(controller, "account-state", {
        accountSignedIn: signedIn,
        viewerGeneration: PorticoHttpInteger(state.viewerGeneration, 0)
    })
end sub

sub PorticoServerConnectionPrepareHostedContext(controller as object, serverId as dynamic, viewerGeneration as integer)
    controller.bootstrapContext = invalid
    controller.restoreContext = invalid
    PorticoServerConnectionBridgeSend(controller, "prepare-hosted-context", {
        serverId: PorticoServerConnectionBridgeOpaqueId(serverId),
        viewerGeneration: viewerGeneration,
        accountSignedIn: controller.accountSignedIn = true
    })
end sub

sub PorticoServerConnectionActivateHostedProfile(controller as object, request as dynamic)
    if not PorticoServerConnectionBridgeAA(request) then return
    PorticoServerConnectionBridgeSend(controller, "activate-hosted-profile", {
        handoffId: PorticoServerConnectionBridgeOpaqueId(request.handoffId),
        accountId: PorticoServerConnectionBridgeOpaqueId(request.accountId),
        serverId: PorticoServerConnectionBridgeOpaqueId(request.serverId),
        profileId: PorticoServerConnectionBridgeOpaqueId(request.profileId),
        installationId: PorticoServerConnectionBridgeOpaqueId(request.installationId),
        viewerGeneration: PorticoHttpInteger(request.viewerGeneration, 0)
    })
end sub

sub PorticoServerConnectionActivateLocalProfile(controller as object, request as dynamic)
    if not PorticoServerConnectionBridgeAA(request) then return
    PorticoServerConnectionBridgeSend(controller, "activate-local-profile", {
        handoffId: PorticoServerConnectionBridgeOpaqueId(request.handoffId),
        profileId: PorticoServerConnectionBridgeOpaqueId(request.profileId),
        sealedPin: PorticoServerConnectionBridgeSealed(request.sealedPin),
        viewerGeneration: PorticoHttpInteger(request.viewerGeneration, 0)
    })
end sub

sub PorticoServerConnectionFenceViewer(controller as object, viewerGeneration as integer)
    controller.pendingScopeAssertion = invalid
    controller.bootstrapContext = invalid
    controller.restoreContext = invalid
    PorticoServerConnectionBridgeSend(controller, "fence-viewer", {viewerGeneration: viewerGeneration})
end sub

' Compatibility wrapper for the current reconnect coordinator. Server and
' identity inputs are intentionally ignored; activation owns exact scope.
sub PorticoServerConnectionCommand(controller as object, kind as string, serverId as string, serverName as string)
    if kind = "retry-server" then PorticoServerConnectionBridgeSend(controller, "retry-server", invalid)
end sub

sub PorticoServerConnectionBridgeSend(controller as object, kind as string, extras as dynamic)
    if controller.task = invalid then return
    allowed = {
        "initialize": true, "account-state": true, "prepare-hosted-context": true, "activate-hosted-profile": true,
        "activate-local-profile": true, "retry-server": true, "fence-viewer": true
    }
    if allowed[kind] <> true then return
    controller.commandSequence = controller.commandSequence + 1
    command = {sequence: controller.commandSequence, kind: kind}
    if PorticoServerConnectionBridgeAA(extras)
        for each key in extras
            command[key] = extras[key]
        end for
    end if
    controller.task.command = command
end sub

function PorticoServerConnectionHandleNodeEvent(controller as object, event as object) as boolean
    if controller.task = invalid or event.GetField() <> "projection" then return false
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return false
    source = event.GetData()
    if not PorticoServerConnectionBridgeAA(source) then return false
    if source.scopeAssertionReady = true
        assertionId = PorticoServerConnectionBridgeOpaqueId(source.scopeAssertionId)
        activationSequence = PorticoHttpInteger(source.activationSequence, 0)
        viewerGeneration = PorticoHttpInteger(source.viewerGeneration, 0)
        if assertionId <> "" and activationSequence > 0 and viewerGeneration > 0
            controller.pendingScopeAssertion = {
                assertionId: assertionId,
                activationSequence: activationSequence,
                viewerGeneration: viewerGeneration
            }
        end if
    else
        controller.pendingScopeAssertion = invalid
    end if
    privateContext = source.privateBootstrapContext
    if PorticoServerConnectionBridgeAA(privateContext) and privateContext.provenByCredentialTask = true
        authority = LCase(PorticoHttpScalarString(privateContext.authority, ""))
        if authority <> "hosted" and authority <> "local" then authority = ""
        context = {
            authority: authority,
            accountId: PorticoServerConnectionBridgeOpaqueId(privateContext.accountId),
            serverId: PorticoServerConnectionBridgeOpaqueId(privateContext.serverId),
            installationId: PorticoServerConnectionBridgeOpaqueId(privateContext.installationId),
            provenByCredentialTask: true
        }
        if context.authority <> "" and context.accountId <> "" and context.serverId <> "" then controller.bootstrapContext = context
        if privateContext.restored = true
            profileId = PorticoServerConnectionBridgeOpaqueId(privateContext.profileId)
            profileName = PorticoServerConnectionBridgeLabel(privateContext.profileName, "Profile", 80)
            if profileId <> "" and context.authority <> "" and context.accountId <> "" and context.serverId <> ""
                controller.restoreContext = {
                    authority: context.authority,
                    accountId: context.accountId,
                    serverId: context.serverId,
                    installationId: context.installationId,
                    profileId: profileId,
                    profileName: profileName,
                    provenByCredentialTask: true,
                    restored: true
                }
            end if
        end if
    end if
    allowed = {
        serverStatus: true,
        serverErrorCode: true,
        serverMessageId: true,
        selectedServerName: true,
        activeProfileName: true,
        navigationSnapshotVerified: true,
        libraryItems: true,
        productContractStatus: true,
        productContractRevision: true,
        authorizationRevision: true,
        routeGeneration: true,
        eventCapabilities: true
    }
    current = controller.scene.runtimeState
    nextState = {}
    if PorticoServerConnectionBridgeAA(current)
        for each key in current
            nextState[key] = current[key]
        end for
    end if
    if LCase(PorticoHttpScalarString(source.productContractStatus, "idle")) <> "ready" then nextState.Delete("eventCapabilities")
    for each key in source
        if allowed[key] = true
            if key = "eventCapabilities"
                capabilities = PorticoServerConnectionBridgeEventCapabilities(source[key])
                if capabilities <> invalid then nextState[key] = capabilities
            else
                nextState[key] = source[key]
            end if
        end if
    end for
    if source.profileActivationFailed = true
        nextState.profileDirectoryStatus = "error"
        nextState.viewerStatus = "active"
        nextState.viewerAcceptingWrites = true
        nextState.viewerTransitionReason = "auth.profile-selection-failed"
    end if
    controller.scene.runtimeState = nextState
    return source.accountRefreshRequired = true
end function

function PorticoServerConnectionBridgeEventCapabilities(value as dynamic) as dynamic
    capabilities = PorticoEventTransportCapabilities(value)
    if value = invalid or GetInterface(value, "ifAssociativeArray") = invalid then return invalid
    if value.eventTransports = invalid or GetInterface(value.eventTransports, "ifArray") = invalid then return invalid
    transports = []
    seen = {}
    for each raw in value.eventTransports
        transport = LCase(PorticoCoreSafeIdentifier(raw, 32))
        if (transport <> "sse" and transport <> "long-poll") or seen[transport] = true then return invalid
        seen[transport] = true
        transports.Push(transport)
    end for
    result = {eventTransports: transports}
    if seen["long-poll"] = true
        result.longPoll = {
            defaultWaitSeconds: capabilities.defaultWaitSeconds,
            maximumWaitSeconds: capabilities.maximumWaitSeconds,
            maximumConcurrentStreams: capabilities.maximumConcurrentStreams
        }
    end if
    return result
end function

function PorticoServerConnectionTakeScopeAssertion(controller as object) as dynamic
    pending = controller.pendingScopeAssertion
    controller.pendingScopeAssertion = invalid
    if not PorticoServerConnectionBridgeAA(pending) then return invalid
    return PorticoServerSessionScopeAssertionConsume(pending.assertionId, pending.activationSequence, pending.viewerGeneration)
end function

function PorticoServerConnectionRestoredContext(controller as object) as dynamic
    value = controller.restoreContext
    if not PorticoServerConnectionBridgeAA(value) or value.restored <> true or value.provenByCredentialTask <> true then return invalid
    result = {}
    for each key in value
        result[key] = value[key]
    end for
    return result
end function

sub PorticoServerConnectionClearRestoredContext(controller as object)
    controller.restoreContext = invalid
end sub

function PorticoServerConnectionBridgeAA(value as dynamic) as boolean
    return value <> invalid and Type(value) = "roAssociativeArray"
end function

function PorticoServerConnectionBridgeOpaqueId(value as dynamic) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    raw = value.ToStr()
    if Len(raw) < 1 or Len(raw) > 128 then return ""
    for position = 1 to Len(raw)
        code = Asc(Mid(raw, position, 1))
        if code < 32 or code = 127 then return ""
    end for
    return raw.Trim()
end function

function PorticoServerConnectionBridgeSealed(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 8 or Len(normalized) > 8192 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/="
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoServerConnectionBridgeLabel(value as dynamic, fallback as string, maximumLength as integer) as string
    normalized = fallback
    if value <> invalid then normalized = value.ToStr()
    normalized = normalized.Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then normalized = fallback
    if Len(normalized) > maximumLength then normalized = Left(normalized, maximumLength)
    return normalized
end function
