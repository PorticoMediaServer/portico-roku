function PorticoRouteNormalize(value as dynamic) as string
    if value = invalid then return ""
    route = LCase(value.ToStr().Replace(Chr(0), "").Trim())
    allowed = {home: true, search: true, library: true, channels: true, saved: true, profile: true, settings: true, "server-selection": true}
    if allowed[route] = true then return route
    if Left(route, 8) = "library/"
        id = Mid(route, 9)
        if id <> "" and Len(id) <= 128
            for position = 1 to Len(id)
                if Instr(1, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-", Mid(id, position, 1)) = 0 then return ""
            end for
            return "library/" + id
        end if
    end if
    return ""
end function
