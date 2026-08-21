function PorticoBackCoordinatorCreate() as object
    return {sequence: 0}
end function

' Priority is modal/panel, route history, root rail reveal, then channel exit.
function PorticoBackResolve(coordinator as dynamic, context as object) as object
    coordinator.sequence = coordinator.sequence + 1
    if context.overlayId <> invalid and context.overlayId <> "" then return {kind: "close-overlay", targetId: context.overlayId, sequence: coordinator.sequence}
    if context.panelId <> invalid and context.panelId <> "" then return {kind: "close-panel", targetId: context.panelId, sequence: coordinator.sequence}
    if context.railExpanded = true
        if context.railOpenedByRootBack = true then return {kind: "exit-channel", targetId: "navigation.root", sequence: coordinator.sequence}
        return {kind: "close-rail", targetId: "navigation.rail", sequence: coordinator.sequence}
    end if
    if context.hasHistory = true then return {kind: "route-back", targetId: "navigation.history", sequence: coordinator.sequence}
    return {kind: "open-rail", targetId: "navigation.rail", sequence: coordinator.sequence}
end function
