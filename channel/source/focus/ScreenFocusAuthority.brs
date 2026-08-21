' Route-local bridge over the shared TV focus/activation primitives.
function PorticoScreenAuthorityCreate(scope as string) as object
    return {
        scope: scope,
        viewerEpoch: 0,
        routeEpoch: 1,
        container: PorticoFocusContainerCreate(scope, []),
        containers: {},
        containerOrder: [],
        neighbors: {},
        activeContainerId: "",
        modalContainerId: "",
        modalPreviousContainerId: "",
        memory: PorticoFocusMemoryCreate(32),
        transactions: PorticoActivationTransactionsCreate(),
        trace: PorticoFocusTraceCreate(32),
        modalInvokerId: ""
    }
end function

sub PorticoScreenAuthorityFence(authority as dynamic, viewerEpoch as integer)
    if authority = invalid then return
    if authority.viewerEpoch = viewerEpoch then return
    authority.viewerEpoch = viewerEpoch
    authority.routeEpoch = authority.routeEpoch + 1
    PorticoFocusMemoryFence(authority.memory, viewerEpoch)
    PorticoActivationRelease(authority.transactions)
    authority.modalInvokerId = ""
    authority.modalContainerId = ""
    authority.modalPreviousContainerId = ""
end sub

sub PorticoScreenAuthorityTargets(authority as dynamic, semanticIds as dynamic)
    if authority = invalid then return
    PorticoFocusContainerReplace(authority.container, semanticIds)
    grouped = {}
    order = []
    if semanticIds <> invalid and GetInterface(semanticIds, "ifArray") <> invalid
        for each value in semanticIds
            semanticId = value.ToStr()
            containerId = PorticoScreenAuthoritySemanticContainer(authority, semanticId)
            if grouped[containerId] = invalid
                grouped[containerId] = []
                order.Push(containerId)
            end if
            grouped[containerId].Push(semanticId)
        end for
    end if
    previousContainers = authority.containers
    authority.containers = {}
    authority.containerOrder = order
    authority.neighbors = {}
    for index = 0 to order.Count() - 1
        containerId = order[index]
        container = invalid
        if previousContainers <> invalid then container = previousContainers[containerId]
        if container = invalid then container = PorticoFocusContainerCreate(containerId, grouped[containerId]) else PorticoFocusContainerReplace(container, grouped[containerId])
        authority.containers[containerId] = container
        if index > 0 then authority.neighbors[containerId + "|up"] = order[index - 1]
        if index + 1 < order.Count() then authority.neighbors[containerId + "|down"] = order[index + 1]
    end for
    if authority.activeContainerId = "" or authority.containers[authority.activeContainerId] = invalid
        authority.activeContainerId = ""
        if order.Count() > 0 then authority.activeContainerId = order[0]
    end if
end sub

' Explicit graph configuration is used at screen/container boundaries. Replacing a
' container preserves its semantic item when possible and chooses a deterministic
' first remaining item when the remembered item was removed or virtualized away.
sub PorticoScreenAuthoritySetContainer(authority as dynamic, containerId as string, semanticIds as dynamic)
    if authority = invalid or containerId = "" then return
    container = authority.containers[containerId]
    if container = invalid
        container = PorticoFocusContainerCreate(containerId, semanticIds)
        authority.containers[containerId] = container
        authority.containerOrder.Push(containerId)
    else
        PorticoFocusContainerReplace(container, semanticIds)
    end if
    if authority.activeContainerId = "" and PorticoFocusContainerCurrent(container) <> "" then authority.activeContainerId = containerId
end sub

sub PorticoScreenAuthoritySetNeighbor(authority as dynamic, containerId as string, direction as string, neighborId as string)
    if authority = invalid or containerId = "" or direction = "" then return
    authority.neighbors[containerId + "|" + LCase(direction)] = neighborId
end sub

function PorticoScreenAuthoritySemanticContainer(authority as dynamic, semanticId as string) as string
    if authority = invalid then return ""
    prefix = authority.scope + "."
    if Left(semanticId, Len(prefix)) <> prefix
        colon = Instr(1, semanticId, ":")
        if colon > 1 then return authority.scope + "." + Left(semanticId, colon - 1)
        return authority.scope
    end if
    remainder = Mid(semanticId, Len(prefix) + 1)
    separator = Instr(1, remainder, ".")
    if separator <= 0 then return authority.scope + "." + remainder
    return authority.scope + "." + Left(remainder, separator - 1)
end function

function PorticoScreenAuthorityContainerForId(authority as dynamic, semanticId as string) as string
    if authority = invalid then return ""
    for each containerId in authority.containerOrder
        container = authority.containers[containerId]
        if container <> invalid
            for each candidate in container.ids
                if candidate = semanticId then return containerId
            end for
        end if
    end for
    return ""
end function

' Screen-local geometry chooses the candidate. The authority validates every
' cross-container boundary and records the discovered named edge.
function PorticoScreenAuthorityAcceptMove(authority as dynamic, direction as string, currentId as string, targetId as string) as boolean
    if authority = invalid or currentId = "" or targetId = "" then return false
    fromId = PorticoScreenAuthorityContainerForId(authority, currentId)
    toId = PorticoScreenAuthorityContainerForId(authority, targetId)
    if fromId = "" or toId = "" then return false
    if fromId = toId
        PorticoScreenAuthorityFocused(authority, targetId)
        return true
    end if
    PorticoScreenAuthoritySetNeighbor(authority, fromId, direction, toId)
    resolved = PorticoScreenAuthorityMoveBoundary(authority, direction, currentId)
    if resolved = "" then return false
    ' Enter the local geometry's chosen item, not merely the container's prior item.
    PorticoScreenAuthorityFocused(authority, targetId)
    return true
end function

function PorticoScreenAuthorityContains(authority as dynamic, semanticId as string) as boolean
    if authority = invalid or semanticId = "" then return false
    for each containerId in authority.containerOrder
        container = authority.containers[containerId]
        if container <> invalid
            for each candidate in container.ids
                if candidate = semanticId then return true
            end for
        end if
    end for
    return false
end function

function PorticoScreenAuthorityResolve(authority as dynamic, preferredId as string, fallbackId as string) as string
    if authority = invalid then return fallbackId
    target = preferredId
    if not PorticoScreenAuthorityContains(authority, target) then target = fallbackId
    if not PorticoScreenAuthorityContains(authority, target)
        target = ""
        active = authority.containers[authority.activeContainerId]
        if active <> invalid then target = PorticoFocusContainerCurrent(active)
    end if
    if target = ""
        for each containerId in authority.containerOrder
            target = PorticoFocusContainerCurrent(authority.containers[containerId])
            if target <> "" then exit for
        end for
    end if
    if target <> "" then PorticoScreenAuthorityFocused(authority, target)
    return target
end function

' Local movement remains screen-specific. This function owns only a boundary
' crossing and therefore does not become a coordinate engine.
function PorticoScreenAuthorityMoveBoundary(authority as dynamic, direction as string, currentId as string) as string
    if authority = invalid then return ""
    PorticoScreenAuthorityFocused(authority, currentId)
    fromId = authority.activeContainerId
    if authority.modalContainerId <> "" then fromId = authority.modalContainerId
    nextId = authority.neighbors[fromId + "|" + LCase(direction)]
    if nextId = invalid or nextId = "" then return ""
    if authority.modalContainerId <> "" and nextId <> authority.modalContainerId then return ""
    container = authority.containers[nextId]
    if container = invalid then return ""
    target = PorticoFocusContainerCurrent(container)
    if target = "" then return ""
    authority.activeContainerId = nextId
    PorticoScreenAuthorityFocused(authority, target)
    PorticoFocusTraceRecord(authority.trace, "boundary-" + LCase(direction), authority.routeEpoch, target)
    return target
end function

function PorticoScreenAuthorityReveal(authority as dynamic, semanticId as string, firstVisible as integer, lastVisible as integer) as object
    result = {semanticId: "", index: -1, reveal: false, firstVisible: firstVisible, lastVisible: lastVisible}
    if authority = invalid then return result
    for each containerId in authority.containerOrder
        container = authority.containers[containerId]
        if container <> invalid
            for index = 0 to container.ids.Count() - 1
                if container.ids[index] = semanticId
                    result.semanticId = semanticId
                    result.index = index
                    result.reveal = index < firstVisible or index > lastVisible
                    return result
                end if
            end for
        end if
    end for
    result.semanticId = PorticoScreenAuthorityResolve(authority, semanticId, "")
    return result
end function

sub PorticoScreenAuthorityFocused(authority as dynamic, semanticId as string)
    if authority = invalid or semanticId = "" then return
    for each containerId in authority.containerOrder
        container = authority.containers[containerId]
        if container <> invalid
            for index = 0 to container.ids.Count() - 1
                if container.ids[index] = semanticId
                    container.index = index
                    authority.activeContainerId = containerId
                    exit for
                end if
            end for
        end if
    end for
    PorticoFocusRemember(authority.memory, authority.scope, semanticId, authority.viewerEpoch)
    PorticoFocusTraceRecord(authority.trace, "focus", authority.routeEpoch, semanticId)
end sub

function PorticoScreenAuthorityBeginOK(authority as dynamic, semanticId as string) as boolean
    if authority = invalid or semanticId = "" then return false
    transaction = PorticoActivationBegin(authority.transactions, semanticId, "ok", authority.viewerEpoch, authority.routeEpoch)
    if transaction = invalid then return false
    PorticoScreenAuthorityFocused(authority, semanticId)
    return true
end function

function PorticoScreenAuthorityCommitOK(authority as dynamic) as boolean
    if authority = invalid or authority.transactions.active = invalid then return false
    transaction = authority.transactions.active
    if not PorticoActivationMarkCommitting(authority.transactions, transaction, authority.viewerEpoch, authority.routeEpoch) then return false
    return PorticoActivationCommit(authority.transactions, transaction, authority.viewerEpoch, authority.routeEpoch)
end function

sub PorticoScreenAuthorityRelease(authority as dynamic, key as string)
    if authority = invalid then return
    if key = "OK" then PorticoActivationRelease(authority.transactions)
end sub

sub PorticoScreenAuthorityOpenModal(authority as dynamic, invokerId as string)
    if authority = invalid then return
    authority.modalInvokerId = invokerId
    if authority.modalContainerId = "" then authority.modalPreviousContainerId = authority.activeContainerId
    modalId = authority.scope + ".modal"
    PorticoScreenAuthoritySetContainer(authority, modalId, [modalId])
    authority.modalContainerId = modalId
    authority.activeContainerId = modalId
    authority.routeEpoch = authority.routeEpoch + 1
    PorticoFocusTraceRecord(authority.trace, "modal-open", authority.routeEpoch, invokerId)
end sub

sub PorticoScreenAuthorityTrapModal(authority as dynamic, containerId as string, semanticIds as dynamic, invokerId as string)
    if authority = invalid then return
    PorticoScreenAuthorityOpenModal(authority, invokerId)
    PorticoScreenAuthoritySetContainer(authority, containerId, semanticIds)
    authority.modalContainerId = containerId
    authority.activeContainerId = containerId
end sub

function PorticoScreenAuthorityCloseModal(authority as dynamic, fallbackId as string) as string
    if authority = invalid then return fallbackId
    target = authority.modalInvokerId
    if target = "" then target = fallbackId
    authority.modalInvokerId = ""
    authority.modalContainerId = ""
    if authority.modalPreviousContainerId <> "" and authority.containers[authority.modalPreviousContainerId] <> invalid then authority.activeContainerId = authority.modalPreviousContainerId
    authority.modalPreviousContainerId = ""
    authority.routeEpoch = authority.routeEpoch + 1
    PorticoFocusTraceRecord(authority.trace, "modal-close", authority.routeEpoch, target)
    return target
end function
