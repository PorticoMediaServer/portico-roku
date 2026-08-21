' Portico TV navigation authority. State is data-only so no SceneGraph node or
' credential can escape a mounted route.
function PorticoNavigationStoreCreate(rootRoute as string, viewerEpoch = 0 as integer) as object
    route = PorticoNavigationRouteId(rootRoute)
    if route = "" then route = "home"
    return {
        contractRevision: "tv-navigation-focus-v1",
        viewerEpoch: viewerEpoch,
        routeEpoch: 1,
        current: {route: route, semanticId: "route." + route, snapshot: invalid},
        history: [],
        limit: 32
    }
end function

function PorticoNavigationRouteId(value as dynamic) as string
    if value = invalid then return ""
    route = LCase(value.ToStr().Trim())
    if route = "" or Len(route) > 192 then return ""
    return route
end function

function PorticoNavigationCurrent(store as dynamic) as dynamic
    if store = invalid or Type(store) <> "roAssociativeArray" then return invalid
    return store.current
end function

function PorticoNavigationTransition(store as dynamic, route as string, snapshot as dynamic, mode = "push" as string, expectedViewerEpoch = -1 as integer, expectedRouteEpoch = -1 as integer) as boolean
    if store = invalid or Type(store) <> "roAssociativeArray" then return false
    nextRoute = PorticoNavigationRouteId(route)
    if nextRoute = "" then return false
    if expectedViewerEpoch >= 0 and store.viewerEpoch <> expectedViewerEpoch then return false
    if expectedRouteEpoch >= 0 and store.routeEpoch <> expectedRouteEpoch then return false

    transitionMode = LCase(mode)
    if transitionMode = "push"
        if store.current <> invalid then store.history.Push(store.current)
    else if transitionMode = "primary"
        store.history = []
    else if transitionMode <> "replace"
        return false
    end if
    while store.history.Count() > store.limit
        store.history.Shift()
    end while
    store.routeEpoch = store.routeEpoch + 1
    store.current = {route: nextRoute, semanticId: "route." + nextRoute, snapshot: snapshot}
    return true
end function

function PorticoNavigationBack(store as dynamic) as dynamic
    if store = invalid or store.history = invalid or store.history.Count() = 0 then return invalid
    destination = store.history.Pop()
    store.routeEpoch = store.routeEpoch + 1
    store.current = destination
    return destination
end function

sub PorticoNavigationResetViewer(store as dynamic, viewerEpoch as integer, rootRoute = "home" as string)
    if store = invalid then return
    store.viewerEpoch = viewerEpoch
    store.routeEpoch = store.routeEpoch + 1
    store.history = []
    route = PorticoNavigationRouteId(rootRoute)
    if route = "" then route = "home"
    store.current = {route: route, semanticId: "route." + route, snapshot: invalid}
end sub
