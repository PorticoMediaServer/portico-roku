function PorticoProfileController(scene as object, port as object) as object
    task = CreateObject("roSGNode", "PorticoProfileTask")
    if task <> invalid
        task.ObserveField("projection", port)
        task.control = "RUN"
    end if
    return {
        scene: scene,
        task: task,
        commandSequence: 0,
        viewerGeneration: 0,
        contextKey: "",
        context: invalid,
        directory: invalid,
        decisionAppliedGeneration: 0,
        forceAskGeneration: -1,
        pendingProfileId: "",
        handoffId: "",
        localHandoffId: "",
        localActivation: invalid,
        stagingOverActive: false,
        contextTeardownBlockedKey: ""
    }
end function

function PorticoProfileBootstrapContext(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    authority = LCase(PorticoProfilesSafeText(value.authority, 16))
    if authority <> "hosted" and authority <> "local" then return invalid
    accountId = PorticoProfilesSafeId(value.accountId)
    serverId = PorticoProfilesSafeId(value.serverId)
    installationId = PorticoProfilesSafeId(value.installationId)
    if accountId = "" or serverId = "" then return invalid
    if value.provenByCredentialTask <> true then return invalid
    return {authority: authority, accountId: accountId, serverId: serverId, installationId: installationId}
end function

function PorticoProfileControllerSynchronize(controller as object, viewerController as object, bootstrapContextValue as dynamic, teardownReady = false as boolean) as object
    context = PorticoProfileBootstrapContext(bootstrapContextValue)
    nextKey = PorticoProfileControllerContextKey(context)
    if nextKey = controller.contextKey then return {changed: false, available: context <> invalid}

    previousKey = controller.contextKey
    alreadyExternallyFenced = not PorticoViewerRuntimeAccepting(viewerController.runtime) and viewerController.runtime.transition = invalid and viewerController.runtime.generationSequence > controller.viewerGeneration
    needsFence = PorticoViewerRuntimeAccepting(viewerController.runtime) or viewerController.runtime.transition <> invalid or (previousKey <> "" and not alreadyExternallyFenced)
    if needsFence
        if not teardownReady then return {changed: false, available: controller.context <> invalid, code: "profile_context_teardown_required"}
    end if

    if needsFence
        fence = PorticoViewerRuntimeControllerFence(viewerController, "profile-context-changed")
        if not fence.ok then return {changed: true, available: false, code: fence.code}
        nextViewerGeneration = fence.generation
    else
        ' Startup is already fenced. Preserve its generation so one-shot Local
        ' Auth handoffs created during sign-in remain exactly generation-bound.
        nextViewerGeneration = viewerController.runtime.generationSequence
    end if

    controller.contextKey = nextKey
    controller.context = context
    controller.directory = invalid
    controller.decisionAppliedGeneration = 0
    controller.pendingProfileId = ""
    controller.handoffId = ""
    controller.localHandoffId = ""
    controller.localActivation = invalid
    controller.stagingOverActive = false
    controller.viewerGeneration = nextViewerGeneration

    if context = invalid
        PorticoProfileControllerCommand(controller, "sign-out", {})
        PorticoMainMergeRuntimeState(controller.scene, {
            profileDirectoryStatus: "idle",
            profileDirectory: [],
            viewerStatus: "unavailable"
        })
        return {changed: true, available: false, code: "profile_context_unavailable"}
    end if
    PorticoMainMergeRuntimeState(controller.scene, {
        profileDirectoryStatus: "loading",
        profileDirectory: [],
        viewerStatus: "selecting-profile",
        viewerTransitionReason: "profile-selection-required"
    })
    if context.authority = "local"
        ' Local directory loading is owned by LocalAuthTask. It will arrive as a
        ' private one-shot handoff and must never be fetched by Hosted ProfileTask.
        return {changed: true, available: true, code: "awaiting_local_profile_handoff"}
    end if
    PorticoProfileControllerCommand(controller, "viewer-state", {
        signedIn: true,
        authority: context.authority,
        accountId: context.accountId,
        serverId: context.serverId,
        installationId: context.installationId
    })
    return {changed: true, available: true, code: "ok"}
end function

function PorticoProfileControllerHandleActivation(controller as object, activation as dynamic) as boolean
    if controller.task = invalid or activation = invalid or Type(activation) <> "roAssociativeArray" then return false
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    if kind = "cancel-profile-selection"
        controller.stagingOverActive = false
        controller.localActivation = invalid
        controller.localHandoffId = ""
        controller.pendingProfileId = ""
        PorticoProfileControllerCommand(controller, "clear-selection", {})
        return true
    end if
    if kind = "retry-profile-directory"
        if controller.context <> invalid and controller.context.authority = "hosted" then PorticoProfileControllerCommand(controller, "load-directory", {})
        return true
    end if
    if kind <> "select-profile" or controller.context = invalid then return false
    profileId = PorticoProfilesSafeId(activation.profileId)
    if profileId = "" or PorticoProfilesFind(controller.directory, profileId) = invalid then return true
    controller.pendingProfileId = profileId
    payload = {profileId: profileId}
    sealedPin = PorticoProfilesSafeText(activation.sealedPin, 8192)
    if sealedPin <> "" then payload.sealedPin = sealedPin
    if controller.context.authority = "local"
        if controller.localHandoffId <> ""
            controller.localActivation = {
                handoffId: controller.localHandoffId,
                profileId: profileId,
                viewerGeneration: controller.viewerGeneration,
                sealedPin: sealedPin
            }
            nextViewerStatus = "activation-required"
            nextAcceptingWrites = false
            if controller.stagingOverActive
                nextViewerStatus = "active"
                nextAcceptingWrites = true
            end if
            PorticoMainMergeRuntimeState(controller.scene, {
                profileDirectoryStatus: "authorizing",
                viewerStatus: nextViewerStatus,
                viewerAcceptingWrites: nextAcceptingWrites
            })
        end if
        sealedPin = ""
        payload = invalid
        return true
    end if
    PorticoProfileControllerCommand(controller, "select-profile", payload)
    sealedPin = ""
    return true
end function

' Local account authentication returns a one-shot handoff from its credential-
' owning Task. Keep that handoff and the directory in Main-memory only: neither
' the handoff identifier nor the eventual sealed PIN may enter runtimeState.
function PorticoProfileControllerAdoptLocalHandoff(controller as object, handoff as dynamic) as object
    if controller.context = invalid or controller.context.authority <> "local" then return {accepted: false, code: "local_context_unavailable"}
    if handoff = invalid or Type(handoff) <> "roAssociativeArray" then return {accepted: false, code: "local_handoff_invalid"}
    generation = PorticoHttpInteger(handoff.viewerGeneration, 0)
    handoffId = PorticoProfilesSafeId(handoff.handoffId)
    if generation <> controller.viewerGeneration or handoffId = "" then return {accepted: false, code: "local_handoff_scope_mismatch"}
    directory = PorticoProfileControllerSafeDirectory(handoff.directory, controller.context)
    if directory = invalid then return {accepted: false, code: "local_profile_directory_invalid"}

    controller.localHandoffId = handoffId
    controller.localActivation = invalid
    controller.directory = directory
    controller.decisionAppliedGeneration = controller.viewerGeneration
    safeProfiles = PorticoProfileControllerCopyProfiles(directory.profiles)
    nextViewerStatus = "selecting-profile"
    nextAcceptingWrites = false
    if controller.stagingOverActive
        nextViewerStatus = "active"
        nextAcceptingWrites = true
    end if
    PorticoMainMergeRuntimeState(controller.scene, {
        profileDirectoryStatus: "ready",
        profileDirectory: safeProfiles,
        viewerStatus: nextViewerStatus,
        viewerAcceptingWrites: nextAcceptingWrites,
        viewerTransitionReason: "profile-selection-required"
    })

    decision = PorticoProfileControllerSelectionDecision(controller, directory)
    if decision.kind = "open"
        controller.pendingProfileId = decision.profile.id
        controller.localActivation = {
            handoffId: controller.localHandoffId,
            profileId: decision.profile.id,
            viewerGeneration: controller.viewerGeneration,
            sealedPin: ""
        }
        authorizingViewerStatus = "activation-required"
        if controller.stagingOverActive then authorizingViewerStatus = "active"
        PorticoMainMergeRuntimeState(controller.scene, {profileDirectoryStatus: "authorizing", viewerStatus: authorizingViewerStatus})
    end if
    return {accepted: true, code: "ok"}
end function

function PorticoProfileControllerTakeLocalActivation(controller as object) as dynamic
    request = controller.localActivation
    controller.localActivation = invalid
    if request = invalid or Type(request) <> "roAssociativeArray" then return invalid
    if controller.context = invalid or controller.context.authority <> "local" then return invalid
    if PorticoProfilesSafeId(request.handoffId) = "" or PorticoProfilesSafeId(request.profileId) = "" then return invalid
    if PorticoHttpInteger(request.viewerGeneration, 0) <> controller.viewerGeneration then return invalid
    return request
end function

function PorticoProfileControllerHandleProjection(controller as object, event as object) as object
    if controller.task = invalid or event.GetField() <> "projection" then return {handled: false}
    sourceNode = event.GetRoSGNode()
    if sourceNode = invalid or not sourceNode.IsSameNode(controller.task) then return {handled: false}
    projection = event.GetData()
    if projection = invalid or Type(projection) <> "roAssociativeArray" then return {handled: true, accepted: false, code: "profile_projection_invalid"}
    if PorticoHttpInteger(projection.viewerGeneration, 0) <> controller.viewerGeneration then return {handled: true, accepted: false, code: "viewer_generation_mismatch"}
    if controller.context = invalid then return {handled: true, accepted: false, code: "profile_context_unavailable"}
    if controller.context.authority <> "hosted" then return {handled: true, accepted: false, code: "hosted_projection_in_local_context"}

    status = LCase(PorticoHttpScalarString(projection.status, "error"))
    safeStatus = status
    allowedStatuses = {idle: true, "awaiting-directory": true, loading: true, ready: true, "pin-required": true, authorizing: true, "selection-authorized": true, error: true}
    if allowedStatuses[safeStatus] <> true then safeStatus = "error"
    publicStatus = safeStatus
    viewerStatus = "selecting-profile"
    if safeStatus = "selection-authorized"
        viewerStatus = "activation-required"
    else if safeStatus = "error"
        viewerStatus = "profile-error"
    end if
    viewerAcceptingWrites = false
    if controller.stagingOverActive
        ' Loading, PIN entry and candidate authorization are presentation state,
        ' not proof that the currently published viewer has become invalid.
        viewerStatus = "active"
        viewerAcceptingWrites = true
    end if

    if projection.directory <> invalid
        directory = PorticoProfileControllerSafeDirectory(projection.directory, controller.context)
        if directory = invalid then return {handled: true, accepted: false, code: "profile_directory_invalid"}
        controller.directory = directory
    end if
    safeProfiles = []
    directoryRevision = 0
    if controller.directory <> invalid
        safeProfiles = PorticoProfileControllerCopyProfiles(controller.directory.profiles)
        directoryRevision = PorticoProfilesInteger(controller.directory.revision, 0)
    end if
    PorticoMainMergeRuntimeState(controller.scene, {
        profileDirectoryStatus: publicStatus,
        profileDirectory: safeProfiles,
        profileDirectoryRevision: directoryRevision,
        viewerStatus: viewerStatus,
        viewerAcceptingWrites: viewerAcceptingWrites,
        viewerTransitionReason: PorticoHttpScalarString(projection.errorMessageId, "")
    })

    if safeStatus = "ready" and controller.directory <> invalid and controller.decisionAppliedGeneration <> controller.viewerGeneration
        controller.decisionAppliedGeneration = controller.viewerGeneration
        decision = PorticoProfileControllerSelectionDecision(controller, controller.directory)
        if decision.kind = "open"
            controller.pendingProfileId = decision.profile.id
            PorticoProfileControllerCommand(controller, "select-profile", {profileId: decision.profile.id})
        end if
    end if
    if safeStatus = "selection-authorized"
        handoffId = PorticoProfilesSafeId(projection.handoffId)
        if projection.handoffReady <> true or handoffId = "" or controller.pendingProfileId = "" then return {handled: true, accepted: false, code: "selection_handoff_missing"}
        controller.handoffId = handoffId
        return {handled: true, accepted: true, code: "selection_authorized", activationRequired: true, handoffId: handoffId, profileId: controller.pendingProfileId, viewerGeneration: controller.viewerGeneration}
    end if
    return {handled: true, accepted: true, code: "ok", activationRequired: false}
end function

function PorticoProfileControllerSelectionDecision(controller as object, directory as dynamic) as object
    if controller.context = invalid then return {kind: "unavailable"}
    if controller.forceAskGeneration = controller.viewerGeneration then return {kind: "select", profiles: directory.profiles}
    launch = PorticoViewerPreferencesReadLaunch(controller.context.authority, controller.context.accountId, controller.context.serverId, controller.context.installationId)
    mode = "ask"
    lastProfileId = ""
    trust = invalid
    if launch <> invalid
        mode = launch.profileSelection
        lastProfileId = launch.lastProfileId
        trust = launch.trust
    end if
    decision = PorticoProfilesSelectionDecision(directory, mode, lastProfileId, trust)
    ' A stored trust is never substituted for a selection assertion or Local
    ' Auth PIN. Locked profiles reopen automatically only through an exact,
    ' still-current native session whose server redeems that trust.
    if decision.kind = "open" and decision.profile.hasPIN then return {kind: "select", profiles: directory.profiles}
    return decision
end function

function PorticoProfileControllerCopyProfiles(values as dynamic) as object
    result = []
    if values = invalid or GetInterface(values, "ifArray") = invalid then return result
    for each source in values
        if result.Count() >= 8 then exit for
        capabilities = {liveTV: false, dvr: false, watchWithFriends: false, feedback: false}
        if source.capabilities <> invalid and Type(source.capabilities) = "roAssociativeArray"
            for each key in capabilities
                capabilities[key] = source.capabilities[key] = true
            end for
        end if
        result.Push({id: source.id, name: source.name, isPrimary: source.isPrimary, isAccountAdmin: source.isAccountAdmin, hasPIN: source.hasPIN, pinRevision: source.pinRevision, sortOrder: source.sortOrder, capabilities: capabilities})
    end for
    return result
end function

function PorticoProfileControllerSafeDirectory(value as dynamic, context as object) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.profiles = invalid or GetInterface(value.profiles, "ifArray") = invalid then return invalid
    if value.profiles.Count() < 1 or value.profiles.Count() > 8 then return invalid
    revision = PorticoProfilesInteger(value.revision, 0)
    if context.authority = "hosted" and revision < 1 then return invalid
    profiles = []
    ids = {}
    primaryCount = 0
    for each source in value.profiles
        if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
        id = PorticoProfilesSafeId(source.id)
        name = PorticoProfilesSafeText(source.name, 80)
        pinRevision = PorticoProfilesInteger(source.pinRevision, -1)
        sortOrder = PorticoProfilesInteger(source.sortOrder, -1)
        if id = "" or name = "" or pinRevision < 0 or sortOrder < 0 or ids[id] = true then return invalid
        ids[id] = true
        isPrimary = source.isPrimary = true
        isAccountAdmin = source.isAccountAdmin = true
        if isPrimary <> isAccountAdmin then return invalid
        if isPrimary then primaryCount = primaryCount + 1
        capabilities = {liveTV: false, dvr: false, watchWithFriends: false, feedback: false}
        if source.capabilities <> invalid and Type(source.capabilities) = "roAssociativeArray"
            for each key in capabilities
                if Type(source.capabilities[key]) = "Boolean" or Type(source.capabilities[key]) = "roBoolean" then capabilities[key] = source.capabilities[key] = true
            end for
        end if
        profiles.Push({id: id, name: name, isPrimary: isPrimary, isAccountAdmin: isAccountAdmin, hasPIN: source.hasPIN = true, pinRevision: pinRevision, sortOrder: sortOrder, capabilities: capabilities})
    end for
    if primaryCount <> 1 then return invalid
    profiles.SortBy("sortOrder")
    return {authority: context.authority, accountId: context.accountId, serverId: context.serverId, revision: revision, profilesAllowed: value.profilesAllowed <> false, profiles: profiles}
end function

sub PorticoProfileControllerCommand(controller as object, kind as string, payload as dynamic)
    if controller.task = invalid then return
    controller.commandSequence = controller.commandSequence + 1
    command = {sequence: controller.commandSequence, kind: kind, viewerGeneration: controller.viewerGeneration}
    if payload <> invalid and Type(payload) = "roAssociativeArray"
        for each key in payload
            command[key] = payload[key]
        end for
    end if
    controller.task.command = command
end sub

function PorticoProfileControllerContextKey(context as dynamic) as string
    if context = invalid then return ""
    return context.authority + "|" + context.accountId + "|" + context.serverId
end function

function PorticoProfileControllerTakeHandoff(controller as object) as dynamic
    if controller.handoffId = "" or controller.pendingProfileId = "" or controller.context = invalid then return invalid
    if controller.context.authority <> "hosted" then return invalid
    result = {
        handoffId: controller.handoffId,
        profileId: controller.pendingProfileId,
        viewerGeneration: controller.viewerGeneration,
        authority: controller.context.authority,
        accountId: controller.context.accountId,
        serverId: controller.context.serverId,
        installationId: controller.context.installationId
    }
    controller.handoffId = ""
    return result
end function
