function PorticoPlayerPresenterCreate() as object
    return {
        focusArea: "transport",
        focusedControl: 2,
        focusedDock: 0,
        panelKind: "",
        panelIndex: 0,
        panelOffset: 0,
        dockTargets: [],
        panelTargets: [],
        focusedOverlayAction: 0,
        overlayKind: "",
        chromeVisible: true,
        lastIntentId: "",
        focusAuthority: PorticoScreenAuthorityCreate("player")
    }
end function

function PorticoPlayerPresenterSemanticId(presenter as object) as string
    PorticoPlayerPresenterRefreshFocusGraph(presenter)
    semanticId = ""
    if presenter.focusArea = "panel"
        if presenter.panelIndex >= 0 and presenter.panelIndex < presenter.panelTargets.Count()
            target = presenter.panelTargets[presenter.panelIndex]
            targetId = presenter.panelIndex.ToStr()
            if target.id <> invalid and target.id.ToStr() <> "" then targetId = target.id.ToStr()
            semanticId = "player.panel." + presenter.panelKind + "." + targetId
        end if
    else if presenter.focusArea = "utility"
        if presenter.focusedDock >= 0 and presenter.focusedDock < presenter.dockTargets.Count() then semanticId = "player.utility." + presenter.dockTargets[presenter.focusedDock].kind
    else
        controlIds = ["previous", "seek-back", "play-pause", "seek-forward", "next"]
        if presenter.focusedControl >= 0 and presenter.focusedControl < controlIds.Count() then semanticId = "player.transport." + controlIds[presenter.focusedControl]
    end if
    if semanticId = "" then semanticId = "player.unavailable"
    PorticoScreenAuthorityFocused(presenter.focusAuthority, semanticId)
    return semanticId
end function

sub PorticoPlayerPresenterRefreshFocusGraph(presenter as dynamic)
    if presenter = invalid or presenter.focusAuthority = invalid then return
    transportIds = ["player.transport.previous", "player.transport.seek-back", "player.transport.play-pause", "player.transport.seek-forward", "player.transport.next"]
    utilityIds = []
    for each target in presenter.dockTargets
        utilityIds.Push("player.utility." + target.kind)
    end for
    panelIds = []
    for index = 0 to presenter.panelTargets.Count() - 1
        target = presenter.panelTargets[index]
        targetId = index.ToStr()
        if target.id <> invalid and target.id.ToStr() <> "" then targetId = target.id.ToStr()
        panelIds.Push("player.panel." + presenter.panelKind + "." + targetId)
    end for
    PorticoScreenAuthoritySetContainer(presenter.focusAuthority, "player.transport", transportIds)
    PorticoScreenAuthoritySetContainer(presenter.focusAuthority, "player.utility", utilityIds)
    PorticoScreenAuthoritySetContainer(presenter.focusAuthority, "player.panel", panelIds)
    PorticoScreenAuthoritySetNeighbor(presenter.focusAuthority, "player.transport", "right", "player.utility")
    PorticoScreenAuthoritySetNeighbor(presenter.focusAuthority, "player.transport", "up", "player.utility")
    PorticoScreenAuthoritySetNeighbor(presenter.focusAuthority, "player.utility", "left", "player.transport")
    PorticoScreenAuthoritySetNeighbor(presenter.focusAuthority, "player.utility", "down", "player.transport")
    PorticoScreenAuthoritySetNeighbor(presenter.focusAuthority, "player.utility", "up", "player.panel")
    PorticoScreenAuthoritySetNeighbor(presenter.focusAuthority, "player.panel", "left", "player.utility")
    PorticoScreenAuthoritySetNeighbor(presenter.focusAuthority, "player.panel", "down", "player.utility")
end sub

function PorticoPlayerPresenterMoveBoundary(presenter as dynamic, direction as string) as string
    currentId = PorticoPlayerPresenterSemanticId(presenter)
    return PorticoScreenAuthorityMoveBoundary(presenter.focusAuthority, direction, currentId)
end function

function PorticoPlayerPresenterBackAction(presenter as object, overlayVisible as boolean) as string
    if overlayVisible then return "close-overlay"
    if presenter.focusArea = "panel" then return "close-panel"
    if presenter.focusArea = "utility" then return "close-utility"
    return "exit"
end function
