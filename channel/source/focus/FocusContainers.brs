function PorticoFocusContainerCreate(containerId as string, semanticIds = invalid as dynamic) as object
    container = {id: containerId, ids: [], index: 0}
    PorticoFocusContainerReplace(container, semanticIds)
    return container
end function

sub PorticoFocusContainerReplace(container as dynamic, semanticIds as dynamic)
    if container = invalid then return
    previous = PorticoFocusContainerCurrent(container)
    container.ids = []
    if semanticIds <> invalid and GetInterface(semanticIds, "ifArray") <> invalid
        for each value in semanticIds
            id = value.ToStr()
            if id <> "" and container.ids.Count() < 512 then container.ids.Push(id)
        end for
    end if
    container.index = 0
    if previous <> ""
        for index = 0 to container.ids.Count() - 1
            if container.ids[index] = previous then container.index = index
        end for
    end if
end sub

function PorticoFocusContainerMove(container as dynamic, delta as integer) as string
    if container = invalid or container.ids.Count() = 0 then return ""
    nextIndex = container.index + delta
    if nextIndex < 0 then nextIndex = 0
    if nextIndex >= container.ids.Count() then nextIndex = container.ids.Count() - 1
    container.index = nextIndex
    return container.ids[container.index]
end function

function PorticoFocusContainerCurrent(container as dynamic) as string
    if container = invalid or container.ids = invalid or container.ids.Count() = 0 then return ""
    if container.index < 0 or container.index >= container.ids.Count() then return ""
    return container.ids[container.index]
end function
