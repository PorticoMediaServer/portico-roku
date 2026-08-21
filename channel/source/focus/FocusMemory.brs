function PorticoFocusMemoryCreate(limit = 128 as integer) as object
    if limit < 1 then limit = 1
    return {entries: {}, order: [], limit: limit, viewerEpoch: -1}
end function

sub PorticoFocusMemoryFence(memory as dynamic, viewerEpoch as integer)
    if memory = invalid then return
    if memory.viewerEpoch = viewerEpoch then return
    memory.viewerEpoch = viewerEpoch
    memory.entries = {}
    memory.order = []
end sub

sub PorticoFocusRemember(memory as dynamic, routeScope as string, semanticId as string, viewerEpoch as integer)
    if memory = invalid or routeScope = "" or semanticId = "" then return
    PorticoFocusMemoryFence(memory, viewerEpoch)
    memory.entries[routeScope] = semanticId
    nextOrder = []
    for each key in memory.order
        if key <> routeScope then nextOrder.Push(key)
    end for
    nextOrder.Push(routeScope)
    memory.order = nextOrder
    while memory.order.Count() > memory.limit
        oldest = memory.order.Shift()
        memory.entries.Delete(oldest)
    end while
end sub

function PorticoFocusRecall(memory as dynamic, routeScope as string, viewerEpoch as integer) as string
    if memory = invalid then return ""
    PorticoFocusMemoryFence(memory, viewerEpoch)
    value = memory.entries[routeScope]
    if value = invalid then return ""
    return value.ToStr()
end function
