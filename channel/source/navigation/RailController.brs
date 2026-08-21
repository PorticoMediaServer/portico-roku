function PorticoRailControllerCreate(selectedSemanticId = "route.home" as string) as object
    return {expanded: false, openedByRootBack: false, selectedSemanticId: selectedSemanticId, focusedSemanticId: selectedSemanticId, returnFocusId: ""}
end function

sub PorticoRailOpen(controller as dynamic, returnFocusId as string, openedByRootBack = false as boolean)
    if controller = invalid then return
    controller.expanded = true
    controller.openedByRootBack = openedByRootBack
    controller.returnFocusId = returnFocusId
    controller.focusedSemanticId = controller.selectedSemanticId
end sub

function PorticoRailClose(controller as dynamic) as string
    if controller = invalid then return ""
    target = controller.returnFocusId
    controller.expanded = false
    controller.openedByRootBack = false
    return target
end function

sub PorticoRailSelect(controller as dynamic, semanticId as string)
    if controller = invalid or semanticId = "" then return
    controller.selectedSemanticId = semanticId
    controller.focusedSemanticId = semanticId
end sub
