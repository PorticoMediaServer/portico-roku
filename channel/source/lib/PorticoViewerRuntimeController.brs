function PorticoViewerRuntimeController(scene as dynamic) as object
    return {
        scene: scene,
        runtime: PorticoViewerRuntimeCreate(),
        transitionReason: "startup"
    }
end function

function PorticoViewerRuntimeControllerInitialState(controller as dynamic) as object
    generation = 1
    if controller <> invalid and controller.runtime <> invalid then generation = controller.runtime.generationSequence
    return {
        viewerStatus: "unavailable",
        viewerGeneration: generation,
        viewerAcceptingWrites: false,
        viewerTransitionReason: "startup"
    }
end function

function PorticoViewerRuntimeControllerStartTransition(controller as dynamic, candidateScope as dynamic, reasonValue as dynamic, requiredAcknowledgements = invalid as dynamic) as object
    if not PorticoViewerRuntimeControllerValid(controller) then return {ok: false, code: "controller_invalid"}
    reason = PorticoViewerRuntimeToken(reasonValue, 80)
    if reason = "" then reason = "viewer-transition"
    result = PorticoViewerRuntimeBeginTransition(controller.runtime, candidateScope, requiredAcknowledgements)
    if not result.ok then return result
    controller.transitionReason = reason
    PorticoViewerRuntimeControllerMerge(controller, PorticoViewerRuntimeControllerViewerOwnedClearPatch({
        viewerStatus: "transitioning",
        viewerGeneration: result.candidateScope.viewerGeneration,
        viewerAcceptingWrites: false,
        viewerTransitionReason: reason
    }))
    return result
end function

function PorticoViewerRuntimeControllerAcknowledge(controller as dynamic, transitionId as dynamic, owner as dynamic, success as boolean) as object
    if not PorticoViewerRuntimeControllerValid(controller) then return {ok: false, code: "controller_invalid"}
    result = PorticoViewerRuntimeAcknowledge(controller.runtime, transitionId, owner, success)
    if not result.ok
        PorticoViewerRuntimeControllerMerge(controller, {
            viewerStatus: "transition-failed",
            viewerAcceptingWrites: false,
            viewerTransitionReason: result.code
        })
    end if
    return result
end function

function PorticoViewerRuntimeControllerPublish(controller as dynamic, transitionId as dynamic, credentialScope as dynamic, profileScope as dynamic, profileProjection = invalid as dynamic) as object
    if not PorticoViewerRuntimeControllerValid(controller) then return {ok: false, code: "controller_invalid"}
    result = PorticoViewerRuntimePublish(controller.runtime, transitionId, credentialScope, profileScope)
    if not result.ok
        PorticoViewerRuntimeControllerMerge(controller, {
            viewerStatus: "transition-failed",
            viewerAcceptingWrites: false,
            viewerTransitionReason: result.code
        })
        return result
    end if

    selectedProfileName = ""
    if profileProjection <> invalid and GetInterface(profileProjection, "ifAssociativeArray") <> invalid
        selectedProfileName = PorticoViewerRuntimeControllerLabel(profileProjection.name, 120)
    end if
    PorticoViewerRuntimeControllerMerge(controller, {
        viewerStatus: "active",
        viewerGeneration: result.activeScope.viewerGeneration,
        viewerAcceptingWrites: true,
        viewerTransitionReason: "",
        selectedProfileId: result.activeScope.profileId,
        selectedProfileName: selectedProfileName
    })
    return result
end function

function PorticoViewerRuntimeControllerRejectTransition(controller as dynamic, transitionId as dynamic, failureCode as dynamic, restorePrevious = false as boolean) as object
    if not PorticoViewerRuntimeControllerValid(controller) then return {ok: false, code: "controller_invalid"}
    result = PorticoViewerRuntimeFailTransition(controller.runtime, transitionId, failureCode, restorePrevious)
    state = PorticoViewerRuntimeControllerViewerOwnedClearPatch({
        viewerStatus: "unavailable",
        viewerGeneration: controller.runtime.generationSequence,
        viewerAcceptingWrites: false,
        viewerTransitionReason: result.code
    })
    if result.restored = true
        state.viewerStatus = "active"
        state.viewerAcceptingWrites = true
        state.selectedProfileId = result.activeScope.profileId
    end if
    PorticoViewerRuntimeControllerMerge(controller, state)
    return result
end function

function PorticoViewerRuntimeControllerFence(controller as dynamic, reasonValue as dynamic) as object
    if not PorticoViewerRuntimeControllerValid(controller) then return {ok: false, code: "controller_invalid"}
    result = PorticoViewerRuntimeFence(controller.runtime, reasonValue)
    if not result.ok then return result
    reason = PorticoViewerRuntimeToken(reasonValue, 80)
    if reason = "" then reason = "viewer-fenced"
    controller.transitionReason = reason
    PorticoViewerRuntimeControllerMerge(controller, PorticoViewerRuntimeControllerViewerOwnedClearPatch({
        viewerStatus: "unavailable",
        viewerGeneration: result.generation,
        viewerAcceptingWrites: false,
        viewerTransitionReason: reason
    }))
    return result
end function

function PorticoViewerRuntimeControllerCommand(controller as dynamic, domain as dynamic, command as dynamic) as dynamic
    if not PorticoViewerRuntimeControllerValid(controller) then return invalid
    return PorticoViewerRuntimeCommandEnvelope(controller.runtime, domain, command)
end function

function PorticoViewerRuntimeControllerAcceptProjection(controller as dynamic, envelope as dynamic, allowedFields = invalid as dynamic) as object
    if not PorticoViewerRuntimeControllerValid(controller) then return {accepted: false, code: "controller_invalid"}
    if envelope = invalid or GetInterface(envelope, "ifAssociativeArray") = invalid then return {accepted: false, code: "projection_envelope_invalid"}
    if envelope.projection = invalid or GetInterface(envelope.projection, "ifAssociativeArray") = invalid then return {accepted: false, code: "projection_invalid"}
    if allowedFields = invalid then return PorticoViewerRuntimeAcceptProjection(controller.runtime, envelope)
    if GetInterface(allowedFields, "ifAssociativeArray") = invalid then return {accepted: false, code: "projection_allowlist_invalid"}

    safeProjection = {}
    for each key in envelope.projection
        if allowedFields[key] = true then safeProjection[key] = envelope.projection[key]
    end for
    safeEnvelope = {
        version: envelope.version,
        domain: envelope.domain,
        viewerGeneration: envelope.viewerGeneration,
        viewerScope: envelope.viewerScope,
        operationSequence: envelope.operationSequence,
        projection: safeProjection
    }
    if envelope.publicationSequence <> invalid then safeEnvelope.publicationSequence = envelope.publicationSequence
    accepted = PorticoViewerRuntimeAcceptProjection(controller.runtime, safeEnvelope)
    if not accepted.accepted then return accepted
    PorticoViewerRuntimeControllerMerge(controller, safeProjection)
    accepted.projection = safeProjection
    return accepted
end function

function PorticoViewerRuntimeControllerCurrentScope(controller as dynamic) as dynamic
    if not PorticoViewerRuntimeControllerValid(controller) then return invalid
    return PorticoViewerRuntimeCloneScope(controller.runtime.activeScope)
end function

function PorticoViewerRuntimeControllerViewerOwnedClearPatch(overrides = invalid as dynamic) as object
    state = {
        selectedProfileId: "",
        selectedProfileName: "",
        preferencesStatus: "idle",
        viewerPreferences: invalid,
        preferenceRevisions: {},
        navigationSnapshotVerified: false,
        libraryItems: [],
        homeStatus: "idle",
        homeModel: invalid,
        detailStatus: "idle",
        detailMediaId: "",
        detailModel: invalid,
        searchViewState: {status: "idle", query: "", queryRevision: 0, groups: []},
        personViewState: invalid,
        libraryViewState: invalid,
        savedViewState: invalid,
        savedMutationResolution: invalid,
        savedMutationError: invalid,
        channelsViewState: invalid,
        playbackViewState: invalid,
        watchWithFriendsViewState: invalid,
        notificationsViewState: invalid,
        engagementViewState: invalid
    }
    if overrides <> invalid and GetInterface(overrides, "ifAssociativeArray") <> invalid
        for each key in overrides
            state[key] = overrides[key]
        end for
    end if
    return state
end function

sub PorticoViewerRuntimeControllerMerge(controller as dynamic, patch as dynamic)
    if controller = invalid or controller.scene = invalid or patch = invalid or GetInterface(patch, "ifAssociativeArray") = invalid then return
    current = controller.scene.runtimeState
    nextState = {}
    if current <> invalid and GetInterface(current, "ifAssociativeArray") <> invalid
        for each key in current
            nextState[key] = current[key]
        end for
    end if
    for each key in patch
        nextState[key] = patch[key]
    end for
    controller.scene.runtimeState = nextState
end sub

function PorticoViewerRuntimeControllerValid(controller as dynamic) as boolean
    return controller <> invalid and GetInterface(controller, "ifAssociativeArray") <> invalid and PorticoViewerRuntimeValid(controller.runtime)
end function

function PorticoViewerRuntimeControllerLabel(value as dynamic, maximumLength as integer) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    label = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(label) > maximumLength then label = Left(label, maximumLength)
    return label
end function
