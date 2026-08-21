function PorticoPlaybackEventsExactKeys(value as dynamic, allowed as object, maximum as integer) as boolean
    if value = invalid or GetInterface(value, "ifAssociativeArray") = invalid or value.Count() > maximum then return false
    for each key in value
        if allowed[key] <> true then return false
    end for
    return true
end function

function PorticoPlaybackEventsPrivateReceiver(value as dynamic, expectedId = "" as string) as dynamic
    allowed = {id: true, name: true, code: true, app: true, platform: true, supportedCommands: true, command: true, createdAt: true, lastSeenAt: true}
    if not PorticoPlaybackEventsExactKeys(value, allowed, 9) or value.Count() < 7 then return invalid
    id = PorticoViewerScopeOpaqueId(value.id, 128)
    if id = "" or (expectedId <> "" and id <> expectedId) then return invalid
    name = PorticoPlaybackEventsText(value.name, 160, false)
    code = PorticoPlaybackEventsReceiverCode(value.code)
    createdAt = PorticoEventTransportServerTime(value.createdAt)
    lastSeenAt = PorticoEventTransportServerTime(value.lastSeenAt)
    if name = "" or code = "" or createdAt = "" or lastSeenAt = "" then return invalid
    if value.app <> invalid and PorticoPlaybackEventsText(value.app, 80, false) = "" then return invalid
    if value.platform <> invalid and PorticoPlaybackEventsText(value.platform, 80, false) = "" then return invalid
    if value.supportedCommands = invalid or GetInterface(value.supportedCommands, "ifArray") = invalid or value.supportedCommands.Count() <> 1 then return invalid
    if value.supportedCommands[0] <> "load" then return invalid
    command = PorticoPlaybackEventsPrivateCommand(value.command, true, true)
    if command = invalid then return invalid
    return {id: id, code: code, command: command}
end function

function PorticoPlaybackEventsPrivateCommand(value as dynamic, allowEmpty as boolean, receiverOnly as boolean) as dynamic
    allowed = {id: true, action: true, mediaId: true, positionSeconds: true, message: true, issuedByProfileId: true, issuedAt: true}
    if not PorticoPlaybackEventsExactKeys(value, allowed, 7) then return invalid
    if value.Count() = 0
        if allowEmpty then return {empty: true}
        return invalid
    end if
    id = PorticoViewerScopeOpaqueId(value.id, 128)
    action = LCase(PorticoCoreSafeIdentifier(value.action, 16))
    actions = {play: true, pause: true, seek: true, stop: true, load: true, next: true, previous: true}
    if id = "" or actions[action] <> true or (receiverOnly and action <> "load") then return invalid
    mediaId = ""
    if value.mediaId <> invalid
        mediaId = PorticoViewerScopeOpaqueId(value.mediaId, 128)
        if mediaId = "" then return invalid
    end if
    position = invalid
    if value.positionSeconds <> invalid
        position = PorticoPlaybackEventsNonNegativeInteger(value.positionSeconds)
        if position = invalid then return invalid
    end if
    message = ""
    if value.message <> invalid
        messageType = LCase(Type(value.message))
        if messageType <> "string" and messageType <> "rostring" then return invalid
        message = PorticoPlaybackEventsText(value.message, 500, true)
        if Len(value.message.ToStr()) > 500 then return invalid
        if action <> "stop" then return invalid
    end if
    if value.issuedByProfileId <> invalid and PorticoViewerScopeOpaqueId(value.issuedByProfileId, 128) = "" then return invalid
    if value.issuedAt <> invalid and PorticoEventTransportServerTime(value.issuedAt) = "" then return invalid
    if action = "load" and mediaId = "" then return invalid
    if action = "seek" and position = invalid then return invalid
    directive = {kind: action}
    if mediaId <> "" then directive.mediaId = mediaId
    if position <> invalid then directive.positionSeconds = position
    if action = "stop" and message <> "" then directive.message = message
    return {empty: false, id: id, action: action, directive: directive}
end function

function PorticoPlaybackEventsReceiverCode(value as dynamic) as string
    if value = invalid then return ""
    kind = LCase(Type(value))
    if kind <> "string" and kind <> "rostring" then return ""
    raw = value.ToStr()
    code = UCase(raw)
    ' This is a private playback-receiver discovery token, not the device-auth
    ' code shown to viewers. OpenAPI only promises a string; accept a bounded
    ' safe token while current canonical six-character values remain covered.
    if raw <> code or Len(code) < 1 or Len(code) > 32 then return ""
    allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    for index = 1 to Len(code)
        if Instr(1, allowed, Mid(code, index, 1)) = 0 then return ""
    end for
    return code
end function

function PorticoPlaybackEventsText(value as dynamic, maximum as integer, allowEmpty as boolean) as string
    if value = invalid then return ""
    kind = LCase(Type(value))
    if kind <> "string" and kind <> "rostring" then return ""
    result = value.ToStr()
    if Len(result) > maximum then return ""
    for index = 1 to Len(result)
        code = Asc(Mid(result, index, 1))
        if code < 32 or code = 127 then return ""
    end for
    if not allowEmpty and result.Trim() = "" then return ""
    return result
end function

function PorticoPlaybackEventsNonNegativeInteger(value as dynamic) as dynamic
    kind = LCase(Type(value))
    if kind <> "integer" and kind <> "roint" and kind <> "longinteger" and kind <> "rolonginteger" then return invalid
    result = Int(value)
    if result < 0 or result >= 2147480000 then return invalid
    return result
end function

function PorticoPlaybackEventsCommandSeen(controller as object, commandId as string) as boolean
    if commandId = "" then return true
    for each prior in controller.commandIds
        if prior = commandId then return true
    end for
    return false
end function

sub PorticoPlaybackEventsRememberCommand(controller as object, commandId as string)
    if commandId = "" or PorticoPlaybackEventsCommandSeen(controller, commandId) then return
    controller.commandIds.Push(commandId)
    while controller.commandIds.Count() > 1024
        controller.commandIds.Shift()
    end while
end sub
