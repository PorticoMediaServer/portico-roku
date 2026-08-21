function PorticoViewerRuntimeCreate() as object
    return {
        version: 1,
        activeScope: invalid,
        generationSequence: 1,
        transitionSequence: 0,
        transition: invalid,
        acceptingProjections: false,
        commandSequences: {},
        resultSequences: {},
        lastFailureCode: ""
    }
end function

function PorticoViewerRuntimeBeginTransition(runtime as dynamic, candidateValue as dynamic, requiredAcknowledgements = invalid as dynamic) as object
    if not PorticoViewerRuntimeValid(runtime) then return {ok: false, code: "runtime_invalid"}
    if runtime.transition <> invalid then return {ok: false, code: "transition_in_progress"}
    candidate = PorticoViewerScopeCandidate(candidateValue)
    if candidate = invalid then return {ok: false, code: "viewer_scope_invalid"}
    if runtime.generationSequence >= 2147483646 then return {ok: false, code: "viewer_generation_exhausted"}

    runtime.generationSequence = runtime.generationSequence + 1
    runtime.transitionSequence = runtime.transitionSequence + 1
    candidate.viewerGeneration = runtime.generationSequence
    runtime.acceptingProjections = false
    runtime.commandSequences = {}
    runtime.resultSequences = {}

    acknowledgements = PorticoViewerRuntimeAcknowledgements(requiredAcknowledgements)
    runtime.transition = {
        id: runtime.transitionSequence,
        status: "fenced",
        candidateScope: candidate,
        previousScope: PorticoViewerRuntimeCloneScope(runtime.activeScope),
        acknowledgements: acknowledgements,
        failureCode: ""
    }
    return {ok: true, code: "ok", transitionId: runtime.transitionSequence, candidateScope: PorticoViewerRuntimeCloneScope(candidate)}
end function

function PorticoViewerRuntimeAcknowledge(runtime as dynamic, transitionId as dynamic, ownerValue as dynamic, success as boolean) as object
    transition = PorticoViewerRuntimeTransition(runtime, transitionId)
    if transition = invalid then return {ok: false, code: "transition_not_current"}
    owner = PorticoViewerRuntimeToken(ownerValue, 64)
    if owner = "" or transition.acknowledgements[owner] = invalid then return {ok: false, code: "acknowledgement_unknown"}
    if transition.acknowledgements[owner] = "complete" then return {ok: true, code: "already_acknowledged"}
    if not success
        transition.acknowledgements[owner] = "failed"
        transition.status = "failed"
        transition.failureCode = "transition_teardown_failed"
        runtime.lastFailureCode = transition.failureCode
        return {ok: false, code: transition.failureCode}
    end if
    transition.acknowledgements[owner] = "complete"
    if PorticoViewerRuntimeAcknowledgementsComplete(transition.acknowledgements) then transition.status = "activation-ready"
    return {ok: true, code: "ok", ready: transition.status = "activation-ready"}
end function

function PorticoViewerRuntimeCanPublish(runtime as dynamic, transitionId as dynamic) as boolean
    transition = PorticoViewerRuntimeTransition(runtime, transitionId)
    if transition = invalid or transition.status <> "activation-ready" then return false
    return PorticoViewerRuntimeAcknowledgementsComplete(transition.acknowledgements)
end function

function PorticoViewerRuntimePublish(runtime as dynamic, transitionId as dynamic, credentialScopeValue as dynamic, profileScopeValue as dynamic) as object
    transition = PorticoViewerRuntimeTransition(runtime, transitionId)
    if transition = invalid then return {ok: false, code: "transition_not_current"}
    if not PorticoViewerRuntimeCanPublish(runtime, transitionId) then return {ok: false, code: "transition_not_ready"}

    credentialScope = PorticoViewerScopeNormalize(credentialScopeValue)
    profileScope = PorticoViewerScopeNormalize(profileScopeValue)
    candidateScope = transition.candidateScope
    if credentialScope = invalid or profileScope = invalid then return {ok: false, code: "scope_assertion_invalid"}
    if not PorticoViewerScopeEquals(candidateScope, credentialScope) or not PorticoViewerScopeEquals(candidateScope, profileScope)
        transition.status = "failed"
        transition.failureCode = "scope_assertion_mismatch"
        runtime.lastFailureCode = transition.failureCode
        return {ok: false, code: transition.failureCode}
    end if

    runtime.activeScope = PorticoViewerRuntimeCloneScope(candidateScope)
    runtime.transition = invalid
    runtime.acceptingProjections = true
    runtime.lastFailureCode = ""
    return {ok: true, code: "ok", activeScope: PorticoViewerRuntimeCloneScope(runtime.activeScope)}
end function

function PorticoViewerRuntimeFailTransition(runtime as dynamic, transitionId as dynamic, failureCodeValue as dynamic, restorePrevious = false as boolean) as object
    transition = PorticoViewerRuntimeTransition(runtime, transitionId)
    if transition = invalid then return {ok: false, code: "transition_not_current"}
    failureCode = PorticoViewerRuntimeToken(failureCodeValue, 80)
    if failureCode = "" then failureCode = "viewer_transition_failed"
    previousScope = PorticoViewerRuntimeCloneScope(transition.previousScope)

    runtime.transition = invalid
    runtime.acceptingProjections = false
    runtime.activeScope = invalid
    runtime.commandSequences = {}
    runtime.resultSequences = {}
    runtime.lastFailureCode = failureCode

    if restorePrevious and previousScope <> invalid
        if runtime.generationSequence >= 2147483646 then return {ok: false, code: "viewer_generation_exhausted", restored: false}
        runtime.generationSequence = runtime.generationSequence + 1
        previousScope.viewerGeneration = runtime.generationSequence
        runtime.activeScope = previousScope
        runtime.acceptingProjections = true
        return {ok: false, code: failureCode, restored: true, activeScope: PorticoViewerRuntimeCloneScope(previousScope)}
    end if
    return {ok: false, code: failureCode, restored: false}
end function

function PorticoViewerRuntimeFence(runtime as dynamic, reasonValue = "viewer_fenced" as dynamic) as object
    if not PorticoViewerRuntimeValid(runtime) then return {ok: false, code: "runtime_invalid"}
    if runtime.generationSequence >= 2147483646 then return {ok: false, code: "viewer_generation_exhausted"}
    runtime.generationSequence = runtime.generationSequence + 1
    runtime.transition = invalid
    runtime.activeScope = invalid
    runtime.acceptingProjections = false
    runtime.commandSequences = {}
    runtime.resultSequences = {}
    runtime.lastFailureCode = PorticoViewerRuntimeToken(reasonValue, 80)
    return {ok: true, code: "ok", generation: runtime.generationSequence}
end function

function PorticoViewerRuntimeCommandEnvelope(runtime as dynamic, domainValue as dynamic, commandValue as dynamic) as dynamic
    if not PorticoViewerRuntimeAccepting(runtime) then return invalid
    domain = PorticoViewerRuntimeToken(domainValue, 64)
    if domain = "" or commandValue = invalid or GetInterface(commandValue, "ifAssociativeArray") = invalid then return invalid
    sequence = 1
    if runtime.commandSequences[domain] <> invalid then sequence = runtime.commandSequences[domain] + 1
    if sequence < 1 or sequence >= 2147483647 then return invalid
    runtime.commandSequences[domain] = sequence
    return {
        version: 1,
        domain: domain,
        viewerGeneration: runtime.activeScope.viewerGeneration,
        viewerScope: PorticoViewerRuntimeCloneScope(runtime.activeScope),
        operationSequence: sequence,
        command: commandValue
    }
end function

function PorticoViewerRuntimeAcceptProjection(runtime as dynamic, envelope as dynamic) as object
    if not PorticoViewerRuntimeAccepting(runtime) then return {accepted: false, code: "viewer_not_active"}
    if envelope = invalid or GetInterface(envelope, "ifAssociativeArray") = invalid then return {accepted: false, code: "projection_envelope_invalid"}
    if envelope.version <> 1 then return {accepted: false, code: "projection_envelope_incompatible"}
    if PorticoViewerScopePositiveInteger(envelope.viewerGeneration) <> runtime.activeScope.viewerGeneration then return {accepted: false, code: "viewer_generation_mismatch"}
    if not PorticoViewerScopeEquals(envelope.viewerScope, runtime.activeScope) then return {accepted: false, code: "viewer_scope_mismatch"}

    domain = PorticoViewerRuntimeToken(envelope.domain, 64)
    sequence = PorticoViewerScopePositiveInteger(envelope.operationSequence)
    if domain = "" or sequence < 1 then return {accepted: false, code: "operation_identity_invalid"}
    if runtime.commandSequences[domain] = invalid then return {accepted: false, code: "operation_not_issued"}
    if sequence <> runtime.commandSequences[domain] then return {accepted: false, code: "projection_not_latest"}

    ' One issued operation may produce a bounded sequence of authoritative
    ' snapshots (for example loading -> final, playback state, or group sync).
    ' Legacy/final-only producers omit publicationSequence and therefore use 1.
    publicationSequence = 1
    if envelope.publicationSequence <> invalid
        publicationSequence = PorticoViewerScopePositiveInteger(envelope.publicationSequence)
        if publicationSequence < 1 then return {accepted: false, code: "publication_identity_invalid"}
    end if
    previous = runtime.resultSequences[domain]
    if previous <> invalid
        if GetInterface(previous, "ifAssociativeArray") <> invalid
            previousOperation = PorticoViewerScopePositiveInteger(previous.operationSequence)
            previousPublication = PorticoViewerScopePositiveInteger(previous.publicationSequence)
            if sequence < previousOperation then return {accepted: false, code: "projection_not_latest"}
            if sequence = previousOperation and publicationSequence <= previousPublication then return {accepted: false, code: "projection_not_latest"}
        else
            ' Read compatibility for a runtime created before publication
            ' sequencing was introduced in this process.
            previousOperation = PorticoViewerScopePositiveInteger(previous)
            if sequence < previousOperation or (sequence = previousOperation and publicationSequence <= 1)
                return {accepted: false, code: "projection_not_latest"}
            end if
        end if
    end if

    runtime.resultSequences[domain] = {operationSequence: sequence, publicationSequence: publicationSequence}
    return {accepted: true, code: "ok", domain: domain, operationSequence: sequence, publicationSequence: publicationSequence, projection: envelope.projection}
end function

function PorticoViewerRuntimeAccepting(runtime as dynamic) as boolean
    if not PorticoViewerRuntimeValid(runtime) then return false
    if not runtime.acceptingProjections or runtime.transition <> invalid or runtime.activeScope = invalid then return false
    return PorticoViewerScopeNormalize(runtime.activeScope) <> invalid
end function

function PorticoViewerRuntimeTransition(runtime as dynamic, transitionId as dynamic) as dynamic
    if not PorticoViewerRuntimeValid(runtime) or runtime.transition = invalid then return invalid
    normalizedId = PorticoViewerScopePositiveInteger(transitionId)
    if normalizedId < 1 or runtime.transition.id <> normalizedId then return invalid
    return runtime.transition
end function

function PorticoViewerRuntimeAcknowledgements(values as dynamic) as object
    acknowledgements = {}
    if values <> invalid and GetInterface(values, "ifArray") <> invalid
        for each value in values
            owner = PorticoViewerRuntimeToken(value, 64)
            if owner <> "" then acknowledgements[owner] = "pending"
        end for
    end if
    if acknowledgements.Count() = 0
        acknowledgements.tasks = "pending"
        acknowledgements.playback = "pending"
        acknowledgements["watch-with-friends"] = "pending"
        acknowledgements.presentation = "pending"
    end if
    return acknowledgements
end function

function PorticoViewerRuntimeAcknowledgementsComplete(acknowledgements as dynamic) as boolean
    if acknowledgements = invalid or GetInterface(acknowledgements, "ifAssociativeArray") = invalid or acknowledgements.Count() = 0 then return false
    for each owner in acknowledgements
        if acknowledgements[owner] <> "complete" then return false
    end for
    return true
end function

function PorticoViewerRuntimeCloneScope(scopeValue as dynamic) as dynamic
    scope = PorticoViewerScopeNormalize(scopeValue)
    if scope = invalid then return invalid
    clone = {}
    for each key in scope
        clone[key] = scope[key]
    end for
    return clone
end function

function PorticoViewerRuntimeValid(runtime as dynamic) as boolean
    return runtime <> invalid and GetInterface(runtime, "ifAssociativeArray") <> invalid and runtime.version = 1
end function

function PorticoViewerRuntimeToken(value as dynamic, maximumLength as integer) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" then return ""
    normalized = LCase(value.ToStr().Trim())
    if normalized = "" or Len(normalized) > maximumLength then return ""
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function
