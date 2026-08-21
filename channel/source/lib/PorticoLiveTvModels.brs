function PorticoLiveTvSourcesModel(source as dynamic) as object
    result = []
    if source = invalid or Type(source) <> "roAssociativeArray" or source.items = invalid or GetInterface(source.items, "ifArray") = invalid then return result
    for each raw in source.items
        if result.Count() >= 32 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray" and raw.enabled = true
            id = PorticoViewerScopeOpaqueId(raw.id, 128)
            name = PorticoCoreSafeText(raw.name, 100)
            if id <> "" and name <> ""
                result.Push({
                    id: id,
                    name: name,
                    type: PorticoCoreSafeIdentifier(raw.type, 32),
                    channelCount: PorticoLiveTvInteger(raw.channelCount, 0, 0, 1000000),
                    programCount: PorticoLiveTvInteger(raw.programCount, 0, 0, 10000000),
                    sortOrder: PorticoLiveTvInteger(raw.sortOrder, 0, -1000000, 1000000),
                    actions: PorticoLiveTvActions(raw.actions)
                })
            end if
        end if
    end for
    return result
end function

function PorticoLiveTvGuideModel(source as dynamic, selectedProgramId as string, windowStartEpoch as longinteger, windowSeconds as integer, serverClock as object, artworkJobs as object) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    if source.channels = invalid or GetInterface(source.channels, "ifArray") = invalid then return invalid
    if source.programs = invalid or GetInterface(source.programs, "ifArray") = invalid then return invalid
    if windowSeconds < 1800 or windowSeconds > 86400 then return invalid
    responseEpoch = PorticoLiveTvEpoch(source.serverTime)
    if responseEpoch > 0
        serverClock.epoch = responseEpoch
        serverClock.timer = CreateObject("roTimespan")
        if serverClock.timer <> invalid then serverClock.timer.Mark()
    end if
    nowEpoch = PorticoLiveTvServerNow(serverClock)
    channels = []
    programsByChannel = {}
    programIndex = {}
    for each rawProgram in source.programs
        if programIndex.Count() >= 500 then exit for
        program = PorticoLiveTvProgram(rawProgram, nowEpoch, windowStartEpoch, windowSeconds, false)
        if program <> invalid
            programIndex[program.id] = program
            bucket = programsByChannel[program.channelId]
            if bucket = invalid then bucket = []
            if bucket.Count() < 64 then bucket.Push(program)
            programsByChannel[program.channelId] = bucket
        end if
    end for
    for each rawChannel in source.channels
        if channels.Count() >= 250 then exit for
        channel = PorticoLiveTvChannel(rawChannel, programsByChannel, artworkJobs)
        if channel <> invalid then channels.Push(channel)
    end for
    selected = programIndex[selectedProgramId]
    if selected = invalid then selected = PorticoLiveTvCurrentProgramFromChannels(channels)
    if selected = invalid then selected = PorticoLiveTvFirstProgram(channels)
    PorticoLiveTvAttachSelectedChannel(selected, channels)
    pageInfo = PorticoLiveTvPageInfo(source.pageInfo)
    groups = PorticoLiveTvStringList(source.channelGroups, 64, 80)
    return {
        channels: channels,
        selectedProgram: selected,
        capabilities: PorticoLiveTvCapabilities(source.capabilities),
        channelGroups: groups,
        serverNowEpoch: nowEpoch,
        timelineStartEpoch: windowStartEpoch,
        timelineEndEpoch: windowStartEpoch + windowSeconds,
        pageInfo: pageInfo
    }
end function

function PorticoLiveTvChannelPageModel(source as dynamic, guide as dynamic, artworkJobs as object) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" or source.items = invalid or GetInterface(source.items, "ifArray") = invalid then return invalid
    programsByChannel = {}
    if guide <> invalid and Type(guide) = "roAssociativeArray"
        for each channel in guide.channels
            programsByChannel[channel.id] = channel.programs
        end for
    end if
    channels = []
    for each raw in source.items
        if channels.Count() >= 250 then exit for
        channel = PorticoLiveTvChannel(raw, programsByChannel, artworkJobs)
        if channel <> invalid then channels.Push(channel)
    end for
    return {channels: channels, groups: PorticoLiveTvStringList(source.groups, 64, 80), pageInfo: PorticoLiveTvPageInfo(source.pageInfo)}
end function

function PorticoLiveTvChannel(raw as dynamic, programsByChannel as object, artworkJobs as object) as dynamic
    if raw = invalid or Type(raw) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(raw.id, 128)
    name = PorticoCoreSafeText(raw.name, 100)
    if id = "" or name = "" or raw.hidden = true or raw.enabled = false then return invalid
    mark = PorticoLiveTvMark(name)
    result = {
        id: id,
        sourceId: PorticoViewerScopeOpaqueId(raw.sourceId, 128),
        name: name,
        number: PorticoCoreSafeText(raw.number, 16),
        group: PorticoCoreSafeText(raw.groupTitle, 80),
        mark: mark,
        favorite: raw.favorite = true,
        actions: PorticoLiveTvActions(raw.actions),
        programs: []
    }
    bucket = programsByChannel[id]
    if bucket <> invalid then result.programs = bucket
    logo = PorticoBrowseSafeServerResourcePath(raw.logoUrl)
    if logo <> ""
        artworkJobs.Push({key: "live-channel-" + PorticoLiveTvArtworkKey(id), source: logo, width: 96, height: 96, target: result, field: "logo"})
    end if
    return result
end function

function PorticoLiveTvProgram(raw as dynamic, nowEpoch as longinteger, windowStartEpoch as longinteger, windowSeconds as integer, libraryChannel as boolean) as dynamic
    if raw = invalid or Type(raw) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(raw.id, 160)
    channelId = PorticoViewerScopeOpaqueId(raw.channelId, 128)
    title = PorticoCoreSafeText(raw.title, 140)
    startAt = PorticoCoreSafeText(raw.startAt, 40)
    endAt = PorticoCoreSafeText(raw.endAt, 40)
    if libraryChannel
        startAt = PorticoCoreSafeText(raw.startsAt, 40)
        endAt = PorticoCoreSafeText(raw.endsAt, 40)
        if title = ""
            kind = PorticoCoreSafeIdentifier(raw.kind, 24)
            if kind = "slate" then title = "Programming resumes soon" else title = "Program unavailable"
        end if
    end if
    startEpoch = PorticoLiveTvEpoch(startAt)
    endEpoch = PorticoLiveTvEpoch(endAt)
    if id = "" or channelId = "" or title = "" or startEpoch < 1 or endEpoch <= startEpoch then return invalid
    live = nowEpoch >= startEpoch and nowEpoch < endEpoch
    leftRatio = 0.0
    widthRatio = 0.0
    if windowSeconds > 0
        visibleStart = startEpoch
        if visibleStart < windowStartEpoch then visibleStart = windowStartEpoch
        visibleEnd = endEpoch
        windowEnd = windowStartEpoch + windowSeconds
        if visibleEnd > windowEnd then visibleEnd = windowEnd
        leftRatio = (visibleStart - windowStartEpoch) / windowSeconds
        widthRatio = (visibleEnd - visibleStart) / windowSeconds
        if widthRatio < 0.0 then widthRatio = 0.0
    end if
    return {
        id: id,
        channelId: channelId,
        title: title,
        subtitle: PorticoCoreSafeText(raw.subtitle, 160),
        category: PorticoCoreSafeText(raw.category, 80),
        description: PorticoCoreSafeText(raw.description, 500),
        startAt: startAt,
        endAt: endAt,
        startEpoch: startEpoch,
        endEpoch: endEpoch,
        durationSeconds: endEpoch - startEpoch,
        timelineLeftRatio: leftRatio,
        timelineWidthRatio: widthRatio,
        timeLabel: PorticoLiveTvTimeRange(startAt, endAt),
        live: live,
        isNew: raw.isNew = true,
        availability: PorticoCoreSafeIdentifier(raw.availability, 32),
        sourceType: PorticoCoreSafeIdentifier(raw.sourceType, 32),
        actions: PorticoLiveTvActions(raw.actions)
    }
end function

function PorticoLiveTvLibraryChannelsModel(source as dynamic, selectedChannelId as string, serverClock as object, windowStartEpoch as longinteger, windowSeconds as integer, artworkJobs as object) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" or source.channels = invalid or GetInterface(source.channels, "ifArray") = invalid or source.programs = invalid or GetInterface(source.programs, "ifArray") = invalid then return invalid
    responseEpoch = PorticoLiveTvEpoch(source.serverTime)
    if responseEpoch > 0
        serverClock.epoch = responseEpoch
        serverClock.timer = CreateObject("roTimespan")
        if serverClock.timer <> invalid then serverClock.timer.Mark()
    end if
    nowEpoch = PorticoLiveTvServerNow(serverClock)
    programsByChannel = {}
    for each rawProgram in source.programs
        program = PorticoLiveTvProgram(rawProgram, nowEpoch, windowStartEpoch, windowSeconds, true)
        if program <> invalid
            bucket = programsByChannel[program.channelId]
            if bucket = invalid then bucket = []
            if bucket.Count() < 64 then bucket.Push(program)
            programsByChannel[program.channelId] = bucket
        end if
    end for
    channels = []
    selectedChannel = invalid
    for each raw in source.channels
        if channels.Count() >= 250 then exit for
        if raw <> invalid and Type(raw) = "roAssociativeArray"
            id = PorticoViewerScopeOpaqueId(raw.id, 128)
            name = PorticoCoreSafeText(raw.name, 100)
            if id <> "" and name <> ""
                channel = {
                    id: id,
                    name: name,
                    description: PorticoCoreSafeText(raw.description, 220),
                    mark: PorticoLiveTvMark(name),
                    actions: PorticoLiveTvActions(raw.actions),
                    programs: []
                }
                bucket = programsByChannel[id]
                if bucket <> invalid then channel.programs = bucket
                logo = PorticoBrowseSafeServerResourcePath(raw.logoUrl)
                if logo <> ""
                    artworkJobs.Push({key: "library-channel-" + PorticoLiveTvArtworkKey(id), source: logo, width: 96, height: 96, target: channel, field: "logo"})
                end if
                channels.Push(channel)
                if id = selectedChannelId then selectedChannel = channel
            end if
        end if
    end for
    if selectedChannel = invalid and channels.Count() > 0 then selectedChannel = channels[0]
    return {
        channels: channels,
        selectedChannel: selectedChannel,
        serverNowEpoch: nowEpoch,
        timelineStartEpoch: windowStartEpoch,
        timelineEndEpoch: windowStartEpoch + windowSeconds,
        pageInfo: PorticoLiveTvPageInfo(source.pageInfo)
    }
end function

function PorticoLiveTvDvrModel(recordingsSource as dynamic, rulesSource as dynamic, scheduleSource as dynamic, statusSource as dynamic) as object
    recordings = []
    if recordingsSource <> invalid and Type(recordingsSource) = "roAssociativeArray" and recordingsSource.items <> invalid and GetInterface(recordingsSource.items, "ifArray") <> invalid
        for each raw in recordingsSource.items
            if recordings.Count() >= 200 then exit for
            recording = PorticoLiveTvRecording(raw)
            if recording <> invalid then recordings.Push(recording)
        end for
    end if
    rules = []
    if rulesSource <> invalid and Type(rulesSource) = "roAssociativeArray" and rulesSource.items <> invalid and GetInterface(rulesSource.items, "ifArray") <> invalid
        for each raw in rulesSource.items
            if rules.Count() >= 100 then exit for
            rule = PorticoLiveTvRule(raw)
            if rule <> invalid then rules.Push(rule)
        end for
    end if
    schedule = []
    if scheduleSource <> invalid and Type(scheduleSource) = "roAssociativeArray" and scheduleSource.items <> invalid and GetInterface(scheduleSource.items, "ifArray") <> invalid
        for each raw in scheduleSource.items
            if schedule.Count() >= 200 then exit for
            entry = PorticoLiveTvRecording(raw)
            if entry <> invalid then schedule.Push(entry)
        end for
    end if
    capabilities = {actions: [], canScheduleRecordings: false, canCreateOwnRules: false, canEditOwnRules: false, canDeleteOwnRules: false}
    conflicts = []
    generatedAt = ""
    if statusSource <> invalid and Type(statusSource) = "roAssociativeArray"
        generatedAt = PorticoCoreSafeText(statusSource.generatedAt, 40)
        if statusSource.capabilities <> invalid and Type(statusSource.capabilities) = "roAssociativeArray"
            rawCapabilities = statusSource.capabilities
            capabilities = {
                actions: PorticoLiveTvActions(rawCapabilities.actions),
                canScheduleRecordings: rawCapabilities.canScheduleRecordings = true,
                canCreateOwnRules: rawCapabilities.canCreateOwnRules = true,
                canEditOwnRules: rawCapabilities.canEditOwnRules = true,
                canDeleteOwnRules: rawCapabilities.canDeleteOwnRules = true
            }
        end if
        if statusSource.conflicts <> invalid and GetInterface(statusSource.conflicts, "ifArray") <> invalid
            for each rawConflict in statusSource.conflicts
                if conflicts.Count() >= 32 then exit for
                conflict = PorticoLiveTvConflict(rawConflict)
                if conflict <> invalid then conflicts.Push(conflict)
            end for
        end if
    end if
    return {
        recordings: recordings,
        rules: rules,
        schedule: schedule,
        conflicts: conflicts,
        capabilities: capabilities,
        generatedAt: generatedAt,
        recordingPageInfo: PorticoLiveTvPageInfoFromSource(recordingsSource),
        rulesPageInfo: PorticoLiveTvPageInfoFromSource(rulesSource),
        schedulePageInfo: PorticoLiveTvPageInfoFromSource(scheduleSource)
    }
end function

function PorticoLiveTvRecording(raw as dynamic) as dynamic
    if raw = invalid or Type(raw) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(raw.id, 128)
    title = PorticoCoreSafeText(raw.title, 140)
    status = PorticoCoreSafeIdentifier(raw.status, 32)
    revision = PorticoLiveTvInteger(raw.revision, 0, 0, 2147483646)
    if id = "" or title = "" or revision < 1 then return invalid
    actions = PorticoLiveTvActions(raw.actions)
    return {
        id: id,
        title: title,
        sourceId: PorticoViewerScopeOpaqueId(raw.sourceId, 128),
        channelId: PorticoViewerScopeOpaqueId(raw.channelId, 128),
        ruleId: PorticoViewerScopeOpaqueId(raw.ruleId, 128),
        status: status,
        startsAt: PorticoCoreSafeText(raw.startsAt, 40),
        endsAt: PorticoCoreSafeText(raw.endsAt, 40),
        meta: PorticoLiveTvDateLabel(raw.startsAt) + "  ·  " + PorticoLiveTvBytes(raw.sizeBytes),
        durationLabel: PorticoLiveTvDurationLabel(raw.startsAt, raw.endsAt),
        sizeBytes: PorticoLiveTvInteger64(raw.sizeBytes),
        revision: revision,
        priority: PorticoLiveTvInteger(raw.priority, 0, -1000000, 1000000),
        failureMessageId: PorticoCoreSafeIdentifier(raw.failureMessageId, 120),
        actions: actions,
        playable: status = "complete" and (PorticoLiveTvHasAction(actions, "dvr.play") or PorticoLiveTvHasAction(actions, "play")),
        cancellable: (status = "scheduled" or status = "running") and PorticoLiveTvHasAction(actions, "dvr.cancel"),
        deletable: status = "complete" and PorticoLiveTvHasAction(actions, "dvr.delete")
    }
end function

function PorticoLiveTvRule(raw as dynamic) as dynamic
    if raw = invalid or Type(raw) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(raw.id, 128)
    sourceId = PorticoViewerScopeOpaqueId(raw.sourceId, 128)
    title = PorticoCoreSafeText(raw.title, 140)
    revision = PorticoLiveTvInteger(raw.revision, 0, 0, 2147483646)
    matchType = PorticoCoreSafeIdentifier(raw.matchType, 20)
    if id = "" or sourceId = "" or title = "" or revision < 1 or (matchType <> "single" and matchType <> "series") then return invalid
    actions = PorticoLiveTvActions(raw.actions)
    return {
        id: id,
        sourceId: sourceId,
        channelId: PorticoViewerScopeOpaqueId(raw.channelId, 128),
        programId: PorticoViewerScopeOpaqueId(raw.programId, 160),
        title: title,
        matchType: matchType,
        enabled: raw.enabled = true,
        startPaddingMinutes: PorticoLiveTvInteger(raw.startPaddingMinutes, 0, 0, 180),
        endPaddingMinutes: PorticoLiveTvInteger(raw.endPaddingMinutes, 0, 0, 180),
        retentionDays: PorticoLiveTvInteger(raw.retentionDays, 0, 0, 36500),
        maxRecordingsPerSeries: PorticoLiveTvInteger(raw.maxRecordingsPerSeries, 0, 0, 10000),
        priority: PorticoLiveTvInteger(raw.priority, 0, -1000000, 1000000),
        revision: revision,
        actions: actions,
        canToggle: PorticoLiveTvHasAction(actions, "dvr.enable") or PorticoLiveTvHasAction(actions, "dvr.disable"),
        canDelete: PorticoLiveTvHasAction(actions, "dvr.delete")
    }
end function

function PorticoLiveTvConflict(raw as dynamic) as dynamic
    if raw = invalid or Type(raw) <> "roAssociativeArray" then return invalid
    id = PorticoViewerScopeOpaqueId(raw.id, 128)
    messageId = PorticoCoreSafeIdentifier(raw.messageId, 120)
    demand = PorticoLiveTvInteger(raw.demand, 0, 0, 1000)
    capacity = PorticoLiveTvInteger(raw.capacity, 0, 0, 1000)
    if id = "" or messageId = "" or demand < 1 then return invalid
    return {id: id, messageId: messageId, reason: PorticoCoreSafeText(raw.reason, 180), demand: demand, capacity: capacity, startsAt: PorticoCoreSafeText(raw.startsAt, 40), endsAt: PorticoCoreSafeText(raw.endsAt, 40), actions: PorticoLiveTvActions(raw.actions)}
end function

function PorticoLiveTvCapabilities(raw as dynamic) as object
    if raw = invalid or Type(raw) <> "roAssociativeArray" then return {canPlay: false, canRecord: false, canManageRules: false, canFavorite: false}
    return {canPlay: raw.canPlay = true, canRecord: raw.canScheduleRecordings = true, canManageRules: raw.canManageRecordingRules = true, canFavorite: raw.canFavoriteChannels = true}
end function

function PorticoLiveTvActions(raw as dynamic) as object
    result = []
    if raw = invalid or GetInterface(raw, "ifArray") = invalid then return result
    allowed = {
        "live.play": true, play: true, "favorite.add": true, "favorite.remove": true,
        "dvr.record": true, "dvr.record-series": true, "dvr.play": true,
        "dvr.cancel": true, "dvr.delete": true, "dvr.edit": true,
        "dvr.enable": true, "dvr.disable": true, "dvr.rule.create": true
    }
    seen = {}
    for each rawValue in raw
        action = LCase(PorticoCoreSafeIdentifier(rawValue, 80))
        if allowed[action] = true and seen[action] <> true
            seen[action] = true
            result.Push(action)
        end if
    end for
    return result
end function

function PorticoLiveTvHasAction(actions as dynamic, expected as string) as boolean
    if actions = invalid or GetInterface(actions, "ifArray") = invalid then return false
    for each action in actions
        if action = expected then return true
    end for
    return false
end function

function PorticoLiveTvServerNow(clock as dynamic) as longinteger
    if clock = invalid or Type(clock) <> "roAssociativeArray" then return 0
    epoch = PorticoLiveTvInteger64(clock.epoch)
    if epoch < 1 then return 0
    if clock.timer <> invalid then epoch = epoch + clock.timer.TotalSeconds()
    return epoch
end function

function PorticoLiveTvEpoch(value as dynamic) as longinteger
    text = PorticoCoreSafeText(value, 40)
    if text = "" then return 0
    dateTime = CreateObject("roDateTime")
    if dateTime = invalid or not dateTime.FromISO8601String(text) then return 0
    return dateTime.AsSeconds()
end function

function PorticoLiveTvIso(epoch as longinteger) as string
    if epoch < 1 then return ""
    dateTime = CreateObject("roDateTime")
    if dateTime = invalid then return ""
    dateTime.FromSeconds(epoch)
    return dateTime.ToISOString()
end function

function PorticoLiveTvDayStartEpoch(serverNowEpoch as longinteger, dayOffset as integer) as longinteger
    if serverNowEpoch < 1 then return 0
    text = PorticoLiveTvIso(serverNowEpoch)
    if Len(text) < 10 then return 0
    start = PorticoLiveTvEpoch(Left(text, 10) + "T00:00:00Z")
    return start + (dayOffset * 86400)
end function

function PorticoLiveTvTimeRange(startValue as dynamic, endValue as dynamic) as string
    startsAt = PorticoCoreSafeText(startValue, 40)
    endsAt = PorticoCoreSafeText(endValue, 40)
    if Len(startsAt) < 16 or Len(endsAt) < 16 then return ""
    return Mid(startsAt, 12, 5) + "–" + Mid(endsAt, 12, 5)
end function

function PorticoLiveTvDurationLabel(startValue as dynamic, endValue as dynamic) as string
    startEpoch = PorticoLiveTvEpoch(startValue)
    endEpoch = PorticoLiveTvEpoch(endValue)
    if startEpoch < 1 or endEpoch <= startEpoch then return ""
    minutes = Int(((endEpoch - startEpoch) + 30) / 60)
    if minutes < 1 then minutes = 1
    return minutes.ToStr() + " min"
end function

function PorticoLiveTvDateLabel(value as dynamic) as string
    text = PorticoCoreSafeText(value, 40)
    if Len(text) >= 10 then return Left(text, 10)
    return "Recorded"
end function

function PorticoLiveTvBytes(value as dynamic) as string
    bytes = PorticoLiveTvInteger64(value)
    if bytes <= 0 then return "Size unavailable"
    gigabyte = 1073741824.0
    if bytes >= gigabyte then return Str(Int(((bytes / gigabyte) * 10) + 0.5) / 10).Trim() + " GB"
    return Str(Int(bytes / 1048576)).Trim() + " MB"
end function

function PorticoLiveTvPageInfoFromSource(source as dynamic) as object
    if source = invalid or Type(source) <> "roAssociativeArray" then return {hasMore: false, nextCursor: "", total: 0}
    return PorticoLiveTvPageInfo(source.pageInfo)
end function

function PorticoLiveTvPageInfo(raw as dynamic) as object
    if raw = invalid or Type(raw) <> "roAssociativeArray" then return {hasMore: false, nextCursor: "", total: 0}
    cursor = PorticoCoreSafeText(raw.nextCursor, 2048)
    total = PorticoLiveTvInteger(raw.total, 0, 0, 10000000)
    return {hasMore: raw.hasMore = true and cursor <> "", nextCursor: cursor, total: total}
end function

function PorticoLiveTvStringList(raw as dynamic, maximumCount as integer, maximumLength as integer) as object
    result = []
    seen = {}
    if raw = invalid or GetInterface(raw, "ifArray") = invalid then return result
    for each value in raw
        if result.Count() >= maximumCount then exit for
        text = PorticoCoreSafeText(value, maximumLength)
        if text <> "" and seen[text] <> true
            seen[text] = true
            result.Push(text)
        end if
    end for
    return result
end function

sub PorticoLiveTvAttachSelectedChannel(selected as dynamic, channels as object)
    if selected = invalid then return
    for each channel in channels
        if channel.id = selected.channelId
            selected.channelName = channel.name
            selected.channelActions = channel.actions
            return
        end if
    end for
end sub

function PorticoLiveTvCurrentProgramFromChannels(channels as object) as dynamic
    for each channel in channels
        for each program in channel.programs
            if program.live = true then return program
        end for
    end for
    return invalid
end function

function PorticoLiveTvFirstProgram(channels as object) as dynamic
    for each channel in channels
        if channel.programs.Count() > 0 then return channel.programs[0]
    end for
    return invalid
end function

function PorticoLiveTvMark(name as string) as string
    mark = ""
    words = name.Tokenize(" ")
    for each word in words
        if word <> "" and Len(mark) < 2 then mark = mark + Left(word, 1)
    end for
    if mark = "" then mark = Left(name, 2)
    return UCase(mark)
end function

function PorticoLiveTvArtworkKey(value as string) as string
    result = ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    for position = 1 to Len(value)
        character = Mid(value, position, 1)
        if Instr(1, allowed, character) > 0 then result = result + character
        if Len(result) >= 96 then exit for
    end for
    if result = "" then result = "channel"
    return result
end function

function PorticoLiveTvInteger(value as dynamic, fallback as integer, minimum as integer, maximum as integer) as integer
    valueType = LCase(Type(value))
    if value = invalid or (valueType <> "integer" and valueType <> "roint" and valueType <> "longinteger" and valueType <> "rolonginteger" and valueType <> "float" and valueType <> "rofloat" and valueType <> "double" and valueType <> "rodouble") then return fallback
    result = Int(value)
    if result < minimum then return minimum
    if result > maximum then return maximum
    return result
end function

function PorticoLiveTvInteger64(value as dynamic) as longinteger
    valueType = LCase(Type(value))
    if value = invalid or (valueType <> "integer" and valueType <> "roint" and valueType <> "longinteger" and valueType <> "rolonginteger" and valueType <> "float" and valueType <> "rofloat" and valueType <> "double" and valueType <> "rodouble") then return 0
    if value < 0 then return 0
    return value
end function
