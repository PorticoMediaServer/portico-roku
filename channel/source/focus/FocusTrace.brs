function PorticoFocusTraceCreate(limit = 64 as integer) as object
    if limit < 1 then limit = 1
    return {events: [], limit: limit, sequence: 0}
end function

sub PorticoFocusTraceRecord(trace as dynamic, kind as string, routeEpoch as integer, semanticId as string)
    if trace = invalid or kind = "" then return
    trace.sequence = trace.sequence + 1
    trace.events.Push({sequence: trace.sequence, kind: kind, routeEpoch: routeEpoch, semanticId: semanticId})
    while trace.events.Count() > trace.limit
        trace.events.Shift()
    end while
end sub
