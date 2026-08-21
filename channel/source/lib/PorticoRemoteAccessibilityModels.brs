function PorticoRemoteSemanticActions() as object
    return ["move", "select", "back", "play-pause", "seek", "context-menu", "info", "dismiss"]
end function

function PorticoRemoteMapKey(platform as string, key as string) as dynamic
    normalizedPlatform = LCase(platform)
    normalizedKey = LCase(key)
    if normalizedPlatform = "roku"
        mapping = {up: "move", down: "move", left: "move", right: "move", select: "select", back: "back", play: "play-pause", replay: "seek", info: "info", options: "context-menu"}
    else if normalizedPlatform = "tvos"
        mapping = {up: "move", down: "move", left: "move", right: "move", select: "select", menu: "back", playpause: "play-pause", longpressselect: "context-menu", play: "play-pause"}
    else
        return invalid
    end if
    if mapping[normalizedKey] = invalid then return invalid
    return mapping[normalizedKey]
end function

function PorticoRemoteBackDecision(state as dynamic) as object
    if state = invalid or GetInterface(state, "ifAssociativeArray") = invalid then state = {}
    overlays = 0
    if state.utilityOverlayCount <> invalid then overlays = Int(state.utilityOverlayCount)
    if overlays > 0 then return {action: "close-top-utility-overlay", finalEvent: invalid}
    panels = 0
    if state.modalOrPanelCount <> invalid then panels = Int(state.modalOrPanelCount)
    if panels > 0 then return {action: "close-modal-or-panel", finalEvent: invalid}
    if state.playerActive = true then return {action: "exit-player-to-previous-route", finalEvent: "stop"}
    if state.routeDepth <> invalid and Int(state.routeDepth) > 0 then return {action: "navigate-to-previous-route", finalEvent: invalid}
    return {action: "remain-at-root", finalEvent: invalid}
end function
