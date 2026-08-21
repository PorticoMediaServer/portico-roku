function PorticoContentHomeFromResponse(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    if data.rows = invalid or GetInterface(data.rows, "ifArray") = invalid then return invalid

    visibleRows = []
    artworkJobs = []
    examinedRows = 0
    for each rawRow in data.rows
        examinedRows = examinedRows + 1
        if examinedRows > 64 then exit for
        if visibleRows.count() >= 32 then exit for
        if rawRow <> invalid and Type(rawRow) = "roAssociativeArray"
            row = PorticoContentRowFromResponse(rawRow, artworkJobs)
            if row <> invalid then visibleRows.push(row)
        end if
    end for

    continueRow = invalid
    secondaryRow = invalid
    for each row in visibleRows
        if continueRow = invalid and PorticoContentIsContinueRow(row)
            continueRow = row
        else if secondaryRow = invalid
            secondaryRow = row
        end if
    end for
    if continueRow = invalid and visibleRows.count() > 0 then secondaryRow = visibleRows[0]

    continueItems = []
    hero = invalid
    if continueRow <> invalid
        continueItems = continueRow.items
        if continueRow.heroes.count() > 0 then hero = continueRow.heroes[0]
    end if
    recentItems = []
    recentTitle = "Recently Added"
    if secondaryRow <> invalid
        recentItems = secondaryRow.items
        recentTitle = secondaryRow.title
    end if

    rows = []
    for each row in visibleRows
        rows.push({
            id: row.id,
            title: row.title,
            explanation: row.explanation,
            items: row.items,
            hasMore: row.hasMore,
            nextCursor: row.nextCursor,
            kind: row.kind,
            libraryId: row.libraryId,
            policyState: row.policyState,
            required: row.required,
            hideable: row.hideable,
            reorderable: row.reorderable,
            defaultVisible: row.defaultVisible,
            endpoint: row.endpoint,
            loadStatus: row.loadStatus,
            errorMessageId: row.errorMessageId
        })
    end for
    model = {
        pivots: PorticoContentSafeLabels(data.pivots, 8, 48),
        rows: rows,
        continueWatching: continueItems,
        continueWatchingTitle: "Continue Watching",
        recentlyAdded: recentItems,
        recentlyAddedTitle: recentTitle
    }
    if continueRow <> invalid then model.continueWatchingTitle = continueRow.title
    if hero <> invalid then model.hero = hero
    return { model: model, artworkJobs: artworkJobs }
end function

function PorticoContentPersonDetailFromResponse(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    person = data.person
    credits = data.credits
    if person = invalid or Type(person) <> "roAssociativeArray" or credits = invalid or GetInterface(credits, "ifArray") = invalid then return invalid
    id = PorticoContentSafeId(person.id)
    name = PorticoContentSafeText(person.name, 100)
    if id = "" or name = "" then return invalid
    roles = PorticoContentSafeLabels(person.roles, 12, 48)
    artworkJobs = []
    items = []
    for each rawItem in credits
        if items.count() >= 100 then exit for
        normalized = PorticoContentMediaPresentation(rawItem, false)
        if normalized <> invalid and not PorticoContentContainsId(items, normalized.card.id)
            normalized.card.kind = normalized.hero.kind
            items.push(normalized.card)
            if normalized.posterSource <> "" then artworkJobs.push({target: normalized.card, field: "poster", source: normalized.posterSource, key: id + "-credit-" + normalized.card.id, width: 200, height: 300})
        end if
    end for
    page = {hasMore: false, nextCursor: ""}
    if data.pageInfo <> invalid and Type(data.pageInfo) = "roAssociativeArray"
        page.nextCursor = PorticoContentSafeCursor(data.pageInfo.nextCursor)
        page.hasMore = data.pageInfo.hasMore = true and page.nextCursor <> ""
    end if
    return {
        model: {id: id, name: name, roles: roles, image: "", items: items, hasMore: page.hasMore, nextCursor: page.nextCursor},
        imageSource: PorticoContentSafeText(person.imageUrl, 512),
        artworkJobs: artworkJobs
    }
end function

function PorticoContentRowFromResponse(source as dynamic, artworkJobs as object, maximumItems = 24 as integer) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoContentSafeId(source.id)
    title = PorticoContentSafeText(source.title, 80)
    if id = "" or title = "" then return invalid
    items = []
    heroes = []
    continueContext = PorticoContentIsContinueSource(source)
    if source.items <> invalid and GetInterface(source.items, "ifArray") <> invalid
        for each rawItem in source.items
            if items.count() >= maximumItems then exit for
            normalized = PorticoContentMediaPresentation(rawItem, continueContext)
            if normalized <> invalid
                if continueContext then normalized.card.hero = normalized.hero
                items.push(normalized.card)
                heroes.push(normalized.hero)
                if normalized.posterSource <> ""
                    artworkJobs.push({ target: normalized.card, field: "poster", source: normalized.posterSource, key: normalized.card.id + "-poster", width: 404, height: 642 })
                end if
                if continueContext and normalized.backdropSource <> ""
                    artworkJobs.push({ target: normalized.hero, field: "backdrop", source: normalized.backdropSource, key: normalized.card.id + "-backdrop", width: 1784, height: 430 })
                end if
            end if
        end for
    end if
    return {
        id: id,
        title: title,
        explanation: PorticoContentSafeText(source.explanation, 240),
        defaultVisible: source.defaultVisible = true,
        kind: LCase(PorticoContentSafeText(source.kind, 48)),
        libraryId: PorticoContentSafeId(source.libraryId),
        policyState: LCase(PorticoContentSafeText(source.policyState, 48)),
        sourceType: LCase(PorticoContentSafeText(source.type, 48)),
        endpoint: PorticoContentSafeText(source.endpoint, 300),
        required: source.required = true,
        hideable: source.hideable = true,
        reorderable: source.reorderable = true,
        critical: source.critical = true,
        controls: PorticoContentSafeLabels(source.controls, 8, 24),
        loadStatus: PorticoContentHomeRowInitialStatus(source),
        errorMessageId: "",
        hasMore: source.hasMore = true and PorticoContentSafeCursor(source.nextCursor) <> "",
        nextCursor: PorticoContentSafeCursor(source.nextCursor),
        items: items,
        heroes: heroes
    }
end function

function PorticoContentHomeRowInitialStatus(source as object) as string
    if source.items <> invalid and GetInterface(source.items, "ifArray") <> invalid then return "ready"
    if PorticoContentSafeText(source.endpoint, 300) <> "" or source.cursorCapable = true then return "loading"
    return "empty"
end function

function PorticoContentMediaPresentation(source as dynamic, continueContext as boolean) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoContentSafeId(source.id)
    title = PorticoContentSafeText(source.title, 140)
    kind = PorticoContentMediaKind(source.type)
    if id = "" or title = "" or kind = "" then return invalid

    cardTitle = title
    if continueContext and kind = "episode"
        seriesTitle = PorticoContentSafeText(source.grandparentTitle, 140)
        if seriesTitle = "" then seriesTitle = PorticoContentSafeText(source.parentTitle, 140)
        if seriesTitle <> "" then cardTitle = seriesTitle
    end if
    cardMeta = PorticoContentCardMeta(source, continueContext)
    card = { id: id, title: cardTitle, meta: cardMeta, kind: kind, actions: PorticoContentSafeActions(source.actions) }
    progress = PorticoContentProgress(source)
    if progress <> invalid then card.progress = progress

    playbackMediaId = id
    if source.playbackTarget <> invalid and Type(source.playbackTarget) = "roAssociativeArray"
        candidatePlaybackId = PorticoContentSafeId(source.playbackTarget.id)
        if candidatePlaybackId <> "" then playbackMediaId = candidatePlaybackId
    end if
    watchlisted = false
    favorite = false
    watched = false
    if source.state <> invalid and Type(source.state) = "roAssociativeArray"
        watchlisted = source.state.watchlisted = true
        favorite = source.state.favorite = true
        watched = source.state.watched = true
    end if
    hero = {
        id: id,
        playbackMediaId: playbackMediaId,
        kind: kind,
        playbackKind: PorticoContentPlaybackKind(kind, source.actions),
        title: cardTitle,
        meta: PorticoContentHeroMeta(source),
        summary: PorticoContentSafeText(source.summary, 560),
        watchlisted: watchlisted,
        favorite: favorite,
        watched: watched,
        rating: PorticoContentRating(source.state),
        reaction: PorticoContentReaction(source.state),
        actions: PorticoContentSafeActions(source.actions),
        uiActions: PorticoContentHomeUiActions(source.actions)
    }
    if progress <> invalid then hero.progress = progress
    return {
        card: card,
        hero: hero,
        posterSource: PorticoContentImageSource(source, "poster"),
        backdropSource: PorticoContentImageSource(source, "backdrop")
    }
end function

function PorticoContentHomeUiActions(actions as dynamic) as object
    result = []
    safeActions = PorticoContentSafeActions(actions)
    if PorticoContentHasAction(safeActions, "play") or PorticoContentHasAction(safeActions, "live.play") then result.push("play")
    if PorticoContentHasActionFamily(safeActions, "watchlist") then result.push("saved-toggle")
    result.push("open-detail")
    if PorticoContentHasActionFamily(safeActions, "favorite") then result.push("favorite-toggle")
    return result
end function

function PorticoContentPlaybackKind(kind as string, actions as dynamic) as string
    safeActions = PorticoContentSafeActions(actions)
    if kind = "live-channel" or kind = "live-program" or PorticoContentHasAction(safeActions, "live.play") then return "live"
    return "vod"
end function

function PorticoContentDetailFromResponse(data as dynamic) as dynamic
    presentation = PorticoContentMediaPresentation(data, false)
    if presentation = invalid then return invalid
    model = presentation.hero
    model.parent = PorticoContentSafeText(data.parentTitle, 140)
    model.title = PorticoContentSafeText(data.title, 140)
    model.meta = PorticoContentDetailMeta(data)
    model.summary = PorticoContentSafeText(data.summary, 720)
    model.uiActions = PorticoContentDetailUiActions(model.actions)
    model.episodes = []
    model.seasons = PorticoContentSeasons(data.children)
    model.selectedSeasonId = PorticoContentInitialSeasonId(data, model.seasons)
    model.episodesStatus = "idle"
    model.episodesHasMore = false
    model.episodesNextCursor = ""
    model.people = PorticoContentPeople(data.people)
    model.relationships = []
    model.facts = PorticoContentMediaFacts(data)
    model.moreActions = PorticoContentMoreActions(model.actions, model.rating, model.reaction, false, "")
    if model.moreActions.menu.count() > 0 then model.uiActions.push("more")
    model.targetKind = ""
    model.targetsStatus = "idle"
    model.targets = []
    model.moreActionStatus = "idle"
    model.moreActionMessage = ""
    model.selectedPersonId = ""
    model.personStatus = "idle"
    model.personResults = []
    artworkJobs = []
    if presentation.backdropSource <> ""
        artworkJobs.push({ target: model, field: "backdrop", source: presentation.backdropSource, key: model.id + "-detail-backdrop", width: 1784, height: 570 })
    end if
    for personIndex = 0 to model.people.count() - 1
        person = model.people[personIndex]
        if person.imageSource <> invalid and person.imageSource <> ""
            artworkJobs.push({ target: person, field: "image", source: person.imageSource, key: model.id + "-person-" + personIndex.ToStr(), width: 240, height: 240 })
            person.Delete("imageSource")
        end if
    end for

    episodeSources = []
    if model.seasons.count() = 0 then episodeSources = PorticoContentEpisodeSources(data)
    for each rawEpisode in episodeSources
        if model.episodes.count() >= 12 then exit for
        episodePresentation = PorticoContentMediaPresentation(rawEpisode, false)
        if episodePresentation <> invalid
            episode = episodePresentation.card
            model.episodes.push(episode)
            source = PorticoContentImageSource(rawEpisode, "thumb")
            if source = "" then source = PorticoContentImageSource(rawEpisode, "backdrop")
            if source <> "" then artworkJobs.push({ target: episode, field: "artwork", source: source, key: episode.id + "-episode", width: 616, height: 360 })
        end if
    end for
    PorticoContentAppendRelationships(model.relationships, data.extras, "extra", artworkJobs)
    PorticoContentAppendRelationships(model.relationships, data.recommendationRows, "recommendation", artworkJobs)
    return { model: model, artworkJobs: artworkJobs }
end function

function PorticoContentSeasons(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each rawSeason in source
        if result.count() >= 100 then exit for
        if rawSeason <> invalid and Type(rawSeason) = "roAssociativeArray" and PorticoContentMediaKind(rawSeason.type) = "season"
            id = PorticoContentSafeId(rawSeason.id)
            title = PorticoContentSafeText(rawSeason.title, 100)
            if id <> "" and title <> "" then result.push({id: id, title: title, kind: "season", meta: PorticoContentEpisodeLabel(rawSeason), actions: []})
        end if
    end for
    return result
end function

function PorticoContentInitialSeasonId(data as dynamic, seasons as object) as string
    if seasons.count() = 0 then return ""
    requested = ""
    if data <> invalid and Type(data) = "roAssociativeArray" and data.playbackTarget <> invalid and Type(data.playbackTarget) = "roAssociativeArray"
        requested = PorticoContentSafeId(data.playbackTarget.parentId)
    end if
    if requested <> ""
        for each season in seasons
            if season.id = requested then return requested
        end for
    end if
    return seasons[0].id
end function

function PorticoContentEpisodesPageFromResponse(data as dynamic, artworkJobs as object) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    items = []
    for each rawEpisode in data.items
        if items.count() >= 100 then exit for
        if rawEpisode <> invalid and Type(rawEpisode) = "roAssociativeArray" and PorticoContentMediaKind(rawEpisode.type) = "episode"
            normalized = PorticoContentMediaPresentation(rawEpisode, false)
            if normalized <> invalid and not PorticoContentContainsId(items, normalized.card.id)
                episode = normalized.card
                items.push(episode)
                source = PorticoContentImageSource(rawEpisode, "thumb")
                if source = "" then source = PorticoContentImageSource(rawEpisode, "backdrop")
                if source <> "" then artworkJobs.push({target: episode, field: "artwork", source: source, key: episode.id + "-episode", width: 616, height: 360})
            end if
        end if
    end for
    nextCursor = ""
    hasMore = false
    if data.pageInfo <> invalid and Type(data.pageInfo) = "roAssociativeArray"
        nextCursor = PorticoContentSafeCursor(data.pageInfo.nextCursor)
        hasMore = data.pageInfo.hasMore = true and nextCursor <> ""
    end if
    return {items: items, hasMore: hasMore, nextCursor: nextCursor}
end function

function PorticoContentMoreActions(actions as dynamic, rating as integer, reaction as string, queueAvailable as boolean, queueCurrentMediaId as string) as object
    safeActions = PorticoContentSafeActions(actions)
    menu = []
    if PorticoContentHasAction(safeActions, "queue.add") and queueAvailable
        menu.push({ id: "queue-play-next", label: "Play Next", description: "Place this title immediately after what is playing", iconId: "action.add-to-list" })
        menu.push({ id: "queue-append", label: "Add to Queue", description: "Place this title at the end of the active queue", iconId: "playback.queue" })
    end if
    if PorticoContentHasAction(safeActions, "playlist.add") then menu.push({ id: "open-playlist-targets", label: "Add to Playlist", description: "Choose an ordered playlist", iconId: "media.playlist" })
    if PorticoContentHasAction(safeActions, "collection.add") then menu.push({ id: "open-collection-targets", label: "Add to Collection", description: "Choose or create a collection", iconId: "library.saved" })
    if PorticoContentHasAction(safeActions, "rating.set")
        description = "Help tune recommendations for this account"
        if rating > 0 then description = "Currently " + rating.ToStr() + " out of 10"
        menu.push({ id: "open-rating", label: "Rate", description: description, iconId: "action.rate", selected: rating > 0 })
    end if
    if PorticoContentHasAction(safeActions, "reaction.set")
        menu.push({ id: "reaction-like", label: PorticoContentReactionLabel("like", reaction), iconId: "action.like", selected: reaction = "like" })
        menu.push({ id: "reaction-dislike", label: PorticoContentReactionLabel("dislike", reaction), iconId: "action.dislike", selected: reaction = "dislike" })
    end if
    return { menu: menu, rating: rating, reaction: reaction, queueAvailable: queueAvailable, queueCurrentMediaId: queueCurrentMediaId }
end function

function PorticoContentReactionLabel(kind as string, current as string) as string
    if kind = "like" and current = "like" then return "Remove Like"
    if kind = "dislike" and current = "dislike" then return "Remove Dislike"
    if kind = "like" then return "Like"
    return "Dislike"
end function

function PorticoContentRating(state as dynamic) as integer
    if state = invalid or Type(state) <> "roAssociativeArray" then return 0
    rating = PorticoHttpInteger(state.rating, 0)
    if rating < 0 or rating > 10 then return 0
    return rating
end function

function PorticoContentReaction(state as dynamic) as string
    if state = invalid or Type(state) <> "roAssociativeArray" then return ""
    reaction = LCase(PorticoContentSafeText(state.reaction, 12))
    if reaction = "like" or reaction = "dislike" then return reaction
    return ""
end function

function PorticoContentSavedTargetsFromResponse(data as dynamic, kind as string) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    result = []
    for each source in data.items
        if result.count() >= 100 then exit for
        if source <> invalid and Type(source) = "roAssociativeArray" and source.canEdit = true
            id = PorticoContentSafeId(source.id)
            title = PorticoContentSafeText(source.title, 140)
            if id <> "" and title <> ""
                itemCount = PorticoHttpInteger(source.itemCount, 0)
                visibility = LCase(PorticoContentSafeText(source.visibility, 16))
                if visibility <> "server" then visibility = "private"
                meta = itemCount.ToStr() + " items  " + Chr(183) + "  " + UCase(Left(visibility, 1)) + Mid(visibility, 2)
                result.push({ id: id, title: title, meta: meta, itemCount: itemCount, visibility: visibility, updatedAt: PorticoContentSafeText(source.updatedAt, 64), canEdit: true, kind: kind })
            end if
        end if
    end for
    return result
end function

sub PorticoContentAppendRelationships(target as object, source as dynamic, prefix as string, artworkJobs as object)
    if source = invalid or GetInterface(source, "ifArray") = invalid then return
    for each rawRow in source
        if target.count() >= 6 then return
        if rawRow <> invalid and Type(rawRow) = "roAssociativeArray" and rawRow.items <> invalid and GetInterface(rawRow.items, "ifArray") <> invalid
            title = PorticoContentSafeText(rawRow.title, 80)
            if title = "" then title = PorticoContentSafeText(rawRow.label, 80)
            if title <> ""
                items = []
                for each rawItem in rawRow.items
                    if items.count() >= 24 then exit for
                    normalized = PorticoContentMediaPresentation(rawItem, false)
                    if normalized <> invalid
                        items.push(normalized.card)
                        if normalized.posterSource <> ""
                            artworkJobs.push({ target: normalized.card, field: "poster", source: normalized.posterSource, key: prefix + "-" + normalized.card.id, width: 404, height: 642 })
                        end if
                    end if
                end for
                if items.count() > 0 then target.push({ id: prefix + "-" + target.count().ToStr(), title: title, items: items })
            end if
        end if
    end for
end sub

function PorticoContentEpisodeSources(data as dynamic) as object
    direct = []
    nested = []
    if data = invalid or data.children = invalid or GetInterface(data.children, "ifArray") = invalid then return direct
    for each child in data.children
        if child <> invalid and Type(child) = "roAssociativeArray"
            if PorticoContentMediaKind(child.type) = "episode"
                direct.push(child)
            else if child.children <> invalid and GetInterface(child.children, "ifArray") <> invalid
                for each grandchild in child.children
                    if grandchild <> invalid and Type(grandchild) = "roAssociativeArray" and PorticoContentMediaKind(grandchild.type) = "episode" then nested.push(grandchild)
                end for
            end if
        end if
    end for
    if direct.count() > 0 then return direct
    return nested
end function

function PorticoContentPeople(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    index = 0
    for each rawPerson in source
        if result.count() >= 20 then exit for
        if rawPerson <> invalid and Type(rawPerson) = "roAssociativeArray"
            name = PorticoContentSafeText(rawPerson.name, 100)
            role = PorticoContentSafeText(rawPerson.role, 80)
            if name <> "" and role <> ""
                personId = PorticoContentSafeId(rawPerson.id)
                if personId = "" then personId = "person-" + index.ToStr()
                person = { id: personId, name: name, role: role }
                character = PorticoContentSafeText(rawPerson.character, 100)
                if character <> "" then person.character = character
                imageSource = PorticoContentSafeServerResourcePath(rawPerson.imageUrl)
                if imageSource <> "" then person.imageSource = imageSource
                cachedImage = PorticoContentSafeLocalUri(rawPerson.image)
                if cachedImage <> "" then person.image = cachedImage
                result.push(person)
                index = index + 1
            end if
        end if
    end for
    return result
end function

function PorticoContentSafeLocalUri(value as dynamic) as string
    text = PorticoContentSafeText(value, 512)
    if Left(text, 5) = "tmp:/" or Left(text, 5) = "pkg:/" then return text
    return ""
end function

function PorticoContentDetailUiActions(actions as dynamic) as object
    result = []
    safeActions = PorticoContentSafeActions(actions)
    if PorticoContentHasAction(safeActions, "play") or PorticoContentHasAction(safeActions, "live.play") then result.push("play")
    if PorticoContentHasActionFamily(safeActions, "watchlist") then result.push("saved-toggle")
    if PorticoContentHasActionFamily(safeActions, "favorite") then result.push("favorite-toggle")
    if PorticoContentHasActionFamily(safeActions, "watched") then result.push("watched-toggle")
    return result
end function

function PorticoContentHasAction(actions as object, expected as string) as boolean
    for each action in actions
        if action = expected then return true
    end for
    return false
end function

function PorticoContentHasActionFamily(actions as object, family as string) as boolean
    prefix = family + "."
    for each action in actions
        if Left(action, Len(prefix)) = prefix then return true
    end for
    return false
end function

function PorticoContentMediaFacts(source as dynamic) as object
    result = []
    if source = invalid or Type(source) <> "roAssociativeArray" then return result
    video = invalid
    audio = invalid
    subtitleCount = 0
    if source.streams <> invalid and GetInterface(source.streams, "ifArray") <> invalid
        for each stream in source.streams
            if stream <> invalid and Type(stream) = "roAssociativeArray"
                kind = LCase(PorticoContentSafeText(stream.kind, 16))
                if kind = "video" and video = invalid then video = stream
                if kind = "audio" and audio = invalid then audio = stream
                if kind = "subtitle" then subtitleCount = subtitleCount + 1
            end if
        end for
    end if
    if video <> invalid
        parts = []
        codec = UCase(PorticoContentSafeText(video.codec, 24))
        if codec <> "" then parts.push(codec)
        width = PorticoHttpInteger(video.width, 0)
        height = PorticoHttpInteger(video.height, 0)
        if width > 0 and height > 0 then parts.push(width.ToStr() + " x " + height.ToStr())
        value = PorticoContentJoinMeta(parts)
        if value <> "" then result.push({ label: "Video", value: value })
    end if
    if audio <> invalid
        parts = []
        codec = UCase(PorticoContentSafeText(audio.codec, 24))
        if codec <> "" then parts.push(codec)
        channels = PorticoHttpInteger(audio.channels, 0)
        if channels > 0 then parts.push(channels.ToStr() + " channels")
        language = PorticoContentSafeText(audio.language, 32)
        if language <> "" then parts.push(language)
        value = PorticoContentJoinMeta(parts)
        if value <> "" then result.push({ label: "Audio", value: value })
    end if
    subtitleValue = "None"
    if subtitleCount > 0 then subtitleValue = subtitleCount.ToStr() + " available"
    result.push({ label: "Subtitles", value: subtitleValue })
    edition = PorticoContentSafeText(source.edition, 80)
    if edition <> "" then result.push({ label: "Edition", value: edition })
    versionCount = 0
    versionNames = []
    if source.optimizedVersions <> invalid and GetInterface(source.optimizedVersions, "ifArray") <> invalid
        for each version in source.optimizedVersions
            if versionCount >= 8 then exit for
            if version <> invalid and Type(version) = "roAssociativeArray"
                label = PorticoContentSafeText(version.profileName, 48)
                if label = "" then label = PorticoContentSafeText(version.profile, 48)
                if label <> "" then versionNames.push(label)
                versionCount = versionCount + 1
            end if
        end for
    end if
    if versionCount > 0 then result.push({ label: "Versions", value: PorticoContentJoinList(versionNames, 3) })
    return result
end function

function PorticoContentJoinList(values as object, maximum as integer) as string
    result = ""
    for index = 0 to values.count() - 1
        if index >= maximum then exit for
        if result <> "" then result = result + ", "
        result = result + values[index]
    end for
    if values.count() > maximum then result = result + " +" + (values.count() - maximum).ToStr()
    return result
end function

function PorticoContentPersonMediaFromResponse(data as dynamic) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" or data.items = invalid or GetInterface(data.items, "ifArray") = invalid then return invalid
    items = []
    artworkJobs = []
    for each rawItem in data.items
        if items.count() >= 50 then exit for
        normalized = PorticoContentMediaPresentation(rawItem, false)
        if normalized <> invalid and not PorticoContentContainsId(items, normalized.card.id)
            items.push(normalized.card)
            if normalized.posterSource <> "" then artworkJobs.push({ target: normalized.card, field: "poster", source: normalized.posterSource, key: "person-result-" + normalized.card.id, width: 404, height: 642 })
        end if
    end for
    return { items: items, artworkJobs: artworkJobs }
end function

function PorticoContentContainsId(items as object, id as string) as boolean
    for each item in items
        if item.id = id then return true
    end for
    return false
end function

function PorticoContentCachedHome(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    continueItems = PorticoContentCachedCards(source.continueWatching, 12)
    recentItems = PorticoContentCachedCards(source.recentlyAdded, 12)
    model = {
        pivots: PorticoContentSafeLabels(source.pivots, 8, 48),
        rows: [],
        continueWatching: continueItems,
        continueWatchingTitle: PorticoContentSafeText(source.continueWatchingTitle, 80),
        recentlyAdded: recentItems,
        recentlyAddedTitle: PorticoContentSafeText(source.recentlyAddedTitle, 80)
    }
    if model.continueWatchingTitle = "" then model.continueWatchingTitle = "Continue Watching"
    if model.recentlyAddedTitle = "" then model.recentlyAddedTitle = "Recently Added"
    hero = PorticoContentCachedHero(source.hero)
    if hero <> invalid then model.hero = hero
    if source.rows <> invalid and GetInterface(source.rows, "ifArray") <> invalid
        for each rawRow in source.rows
            if model.rows.count() >= 32 then exit for
            if rawRow <> invalid and Type(rawRow) = "roAssociativeArray"
                rowId = PorticoContentSafeId(rawRow.id)
                rowTitle = PorticoContentSafeText(rawRow.title, 80)
                rowItems = PorticoContentCachedCards(rawRow.items, 12)
                if rowId <> "" and rowTitle <> "" and (rowItems.count() > 0 or rawRow.required = true)
                    cursor = PorticoContentSafeCursor(rawRow.nextCursor)
                    model.rows.push({
                        id: rowId,
                        title: rowTitle,
                        explanation: PorticoContentSafeText(rawRow.explanation, 240),
                        items: rowItems,
                        hasMore: rawRow.hasMore = true and cursor <> "",
                        nextCursor: cursor,
                        kind: LCase(PorticoContentSafeText(rawRow.kind, 48)),
                        libraryId: PorticoContentSafeId(rawRow.libraryId),
                        policyState: LCase(PorticoContentSafeText(rawRow.policyState, 48)),
                        required: rawRow.required = true,
                        hideable: rawRow.hideable = true,
                        reorderable: rawRow.reorderable = true,
                        defaultVisible: rawRow.defaultVisible = true,
                        endpoint: "",
                        loadStatus: "ready",
                        errorMessageId: ""
                    })
                    if rowItems.count() = 0 then model.rows[model.rows.count() - 1].loadStatus = "empty"
                end if
            end if
        end for
    end if
    if model.rows.count() = 0
        if continueItems.count() > 0 then model.rows.push({ id: "continue", title: model.continueWatchingTitle, items: continueItems, hasMore: false, nextCursor: "" })
        if recentItems.count() > 0 then model.rows.push({ id: "recent", title: model.recentlyAddedTitle, items: recentItems, hasMore: false, nextCursor: "" })
    end if
    return model
end function

function PorticoContentCachedDetail(source as dynamic) as dynamic
    hero = PorticoContentCachedHero(source)
    if hero = invalid then return invalid
    hero.parent = PorticoContentSafeText(source.parent, 140)
    hero.episodes = PorticoContentCachedCards(source.episodes, 100)
    hero.seasons = PorticoContentCachedCards(source.seasons, 100)
    hero.selectedSeasonId = PorticoContentSafeId(source.selectedSeasonId)
    hero.episodesStatus = "ready"
    hero.episodesHasMore = false
    hero.episodesNextCursor = ""
    hero.people = PorticoContentPeople(source.people)
    hero.facts = PorticoContentCachedFacts(source.facts)
    hero.relationships = []
    if source.relationships <> invalid and GetInterface(source.relationships, "ifArray") <> invalid
        for each rawRow in source.relationships
            if hero.relationships.count() >= 6 then exit for
            if rawRow <> invalid and Type(rawRow) = "roAssociativeArray"
                title = PorticoContentSafeText(rawRow.title, 80)
                items = PorticoContentCachedCards(rawRow.items, 12)
                if title <> "" and items.count() > 0 then hero.relationships.push({ id: "cached-" + hero.relationships.count().ToStr(), title: title, items: items })
            end if
        end for
    end if
    return hero
end function

function PorticoContentCachedCards(source as dynamic, maximum as integer) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each rawCard in source
        if result.count() >= maximum then exit for
        if rawCard <> invalid and Type(rawCard) = "roAssociativeArray"
            id = PorticoContentSafeId(rawCard.id)
            title = PorticoContentSafeText(rawCard.title, 140)
            if id <> "" and title <> ""
                card = { id: id, title: title, meta: PorticoContentSafeText(rawCard.meta, 140), kind: PorticoContentMediaKind(rawCard.kind), actions: PorticoContentSafeActions(rawCard.actions) }
                if rawCard.hero <> invalid
                    cachedHero = PorticoContentCachedHero(rawCard.hero)
                    if cachedHero <> invalid then card.hero = cachedHero
                end if
                progress = PorticoContentBoundedProgress(rawCard.progress)
                if progress <> invalid then card.progress = progress
                result.push(card)
            end if
        end if
    end for
    return result
end function

function PorticoContentCachedHero(source as dynamic) as dynamic
    if source = invalid or Type(source) <> "roAssociativeArray" then return invalid
    id = PorticoContentSafeId(source.id)
    title = PorticoContentSafeText(source.title, 140)
    if id = "" or title = "" then return invalid
    playbackMediaId = PorticoContentSafeId(source.playbackMediaId)
    if playbackMediaId = "" then playbackMediaId = id
    hero = {
        id: id,
        playbackMediaId: playbackMediaId,
        kind: PorticoContentMediaKind(source.kind),
        playbackKind: "vod",
        title: title,
        meta: PorticoContentSafeText(source.meta, 180),
        summary: PorticoContentSafeText(source.summary, 720),
        watchlisted: source.watchlisted = true,
        favorite: source.favorite = true,
        watched: source.watched = true,
        rating: PorticoHttpInteger(source.rating, 0),
        reaction: PorticoContentReaction({ reaction: source.reaction }),
        actions: PorticoContentSafeActions(source.actions),
        uiActions: PorticoContentSafeUiActions(source.uiActions)
    }
    cachedPlaybackKind = LCase(PorticoContentSafeText(source.playbackKind, 16))
    if cachedPlaybackKind = "live" or hero.kind = "live-channel" or hero.kind = "live-program" or PorticoContentHasAction(hero.actions, "live.play") then hero.playbackKind = "live"
    progress = PorticoContentBoundedProgress(source.progress)
    if progress <> invalid then hero.progress = progress
    hero.moreActions = PorticoContentMoreActions(hero.actions, hero.rating, hero.reaction, false, "")
    return hero
end function

function PorticoContentSafeUiActions(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    ' Contract-gated client flows are intentionally not restored from offline cache.
    allowed = { "open-detail": true, play: true, "saved-toggle": true, "favorite-toggle": true, "watched-toggle": true, more: true }
    seen = {}
    for each rawAction in source
        action = LCase(PorticoContentSafeText(rawAction, 48))
        if allowed[action] = true and seen[action] <> true
            seen[action] = true
            result.push(action)
        end if
        if result.count() >= 8 then exit for
    end for
    return result
end function

function PorticoContentCachedFacts(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each rawFact in source
        if result.count() >= 8 then exit for
        if rawFact <> invalid and Type(rawFact) = "roAssociativeArray"
            label = PorticoContentSafeText(rawFact.label, 40)
            value = PorticoContentSafeText(rawFact.value, 160)
            if label <> "" and value <> "" then result.push({ label: label, value: value })
        end if
    end for
    return result
end function

function PorticoContentSafeActions(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    allowed = {
        "play": true, "play.from-beginning": true, "live.play": true, "watchlist.add": true, "watchlist.remove": true,
        "favorite.add": true, "favorite.remove": true, "watched.set": true,
        "watched.mark": true, "watched.unmark": true,
        "reaction.set": true, "rating.set": true, "collection.add": true,
        "playlist.add": true, "queue.add": true, "watch-with-friends.start": true,
        "feedback.report-problem": true, "feedback.request-higher-quality": true
    }
    seen = {}
    for each rawAction in source
        action = LCase(PorticoContentSafeText(rawAction, 48))
        if allowed[action] = true and seen[action] <> true
            seen[action] = true
            result.push(action)
        end if
        if result.count() >= 24 then exit for
    end for
    return result
end function

function PorticoContentIsContinueSource(source as object) as boolean
    id = LCase(PorticoContentSafeText(source.id, 48))
    kind = LCase(PorticoContentSafeText(source.kind, 48))
    policy = LCase(PorticoContentSafeText(source.policyState, 48))
    sourceType = LCase(PorticoContentSafeText(source.type, 48))
    return id = "continue" or kind = "continue" or policy = "continue" or sourceType = "continue"
end function

function PorticoContentIsContinueRow(row as object) as boolean
    return row.id = "continue" or row.kind = "continue" or row.policyState = "continue" or row.sourceType = "continue"
end function

function PorticoContentMediaKind(value as dynamic) as string
    kind = LCase(PorticoContentSafeText(value, 48)).Replace("_", "-")
    allowed = {
        movie: true, show: true, season: true, episode: true, person: true, collection: true,
        artist: true, album: true, track: true, author: true, book: true, chapter: true,
        recording: true, "live-channel": true, "live-program": true
    }
    if kind = "tv" or kind = "tv-show" or kind = "series" then return "show"
    if kind = "audiobook" then return "book"
    if allowed[kind] = true then return kind
    return "collection"
end function

function PorticoContentCardMeta(source as object, continueContext as boolean) as string
    if continueContext and PorticoContentMediaKind(source.type) = "episode"
        episodeTitle = PorticoContentSafeText(source.title, 140)
        if episodeTitle <> "" then return episodeTitle
    end if
    subtitle = PorticoContentSafeText(source.tagline, 140)
    if subtitle = "" then subtitle = PorticoContentEpisodeLabel(source)
    if subtitle = "" then subtitle = PorticoContentSafeText(source.subtitle, 140)
    if subtitle = "" and source.year <> invalid
        year = PorticoHttpInteger(source.year, 0)
        if year >= 1800 and year <= 2200 then subtitle = year.ToStr()
    end if
    return subtitle
end function

function PorticoContentHeroMeta(source as object) as string
    parts = []
    kind = PorticoContentMediaKind(source.type)
    kindLabel = PorticoContentKindLabel(kind)
    if kindLabel <> "" then parts.push(kindLabel)
    year = PorticoHttpInteger(source.year, 0)
    if year >= 1800 and year <= 2200 then parts.push(year.ToStr())
    rating = PorticoContentSafeText(source.contentRating, 24)
    if rating <> "" then parts.push(rating)
    duration = PorticoContentDuration(source.durationSeconds)
    if duration <> "" then parts.push(duration)
    return PorticoContentJoinMeta(parts)
end function

function PorticoContentDetailMeta(source as object) as string
    parts = []
    episode = PorticoContentEpisodeLabel(source)
    if episode <> "" then parts.push(episode)
    year = PorticoHttpInteger(source.year, 0)
    if year >= 1800 and year <= 2200 then parts.push(year.ToStr())
    duration = PorticoContentDuration(source.durationSeconds)
    if duration <> "" then parts.push(duration)
    rating = PorticoContentSafeText(source.contentRating, 24)
    if rating <> "" then parts.push(rating)
    if source.genres <> invalid and GetInterface(source.genres, "ifArray") <> invalid and source.genres.count() > 0
        genre = PorticoContentSafeText(source.genres[0], 48)
        if genre <> "" then parts.push(genre)
    end if
    return PorticoContentJoinMeta(parts)
end function

function PorticoContentEpisodeLabel(source as object) as string
    season = PorticoHttpInteger(source.seasonNumber, 0)
    if season <= 0 then season = PorticoHttpInteger(source.indexNumber, 0)
    episode = PorticoHttpInteger(source.episodeNumber, 0)
    if season > 0 and episode > 0 then return "S" + season.ToStr() + " E" + episode.ToStr()
    if episode > 0 then return "E" + episode.ToStr()
    return ""
end function

function PorticoContentDuration(value as dynamic) as string
    seconds = PorticoHttpInteger(value, 0)
    if seconds <= 0 then return ""
    minutes = Int((seconds + 30) / 60)
    hours = Int(minutes / 60)
    remainder = minutes - (hours * 60)
    if hours <= 0 then return minutes.ToStr() + "m"
    if remainder = 0 then return hours.ToStr() + "h"
    return hours.ToStr() + "h " + remainder.ToStr() + "m"
end function

function PorticoContentKindLabel(kind as string) as string
    if kind = "show" or kind = "season" or kind = "episode" then return "TV Show"
    if kind = "movie" then return "Movie"
    if kind = "recording" then return "Recording"
    if kind = "live-channel" or kind = "live-program" then return "Live TV"
    if kind = "book" or kind = "chapter" or kind = "author" then return "Audiobook"
    if kind = "album" or kind = "track" or kind = "artist" then return "Music"
    return ""
end function

function PorticoContentProgress(source as object) as dynamic
    if source.state = invalid or Type(source.state) <> "roAssociativeArray" then return invalid
    if source.state.watched = true then return invalid
    progressSeconds = PorticoHttpInteger(source.state.progressSeconds, 0)
    durationSeconds = PorticoHttpInteger(source.durationSeconds, 0)
    if progressSeconds <= 0 or durationSeconds <= 0 then return invalid
    return PorticoContentBoundedProgress((progressSeconds * 100.0) / durationSeconds)
end function

function PorticoContentBoundedProgress(value as dynamic) as dynamic
    if value = invalid then return invalid
    progress = Int(Val(value.ToStr()))
    if progress <= 0 then return invalid
    if progress > 100 then progress = 100
    return progress
end function

function PorticoContentImageSource(source as object, kind as string) as string
    if source.images = invalid or Type(source.images) <> "roAssociativeArray" then return ""
    value = source.images[kind]
    if kind = "backdrop" and (value = invalid or value.ToStr() = "") then value = source.images.thumb
    if kind = "backdrop" and (value = invalid or value.ToStr() = "") then value = source.images.poster
    return PorticoContentSafeServerResourcePath(value)
end function

function PorticoContentSafeServerResourcePath(value as dynamic) as string
    if value = invalid then return ""
    path = value.ToStr().Trim()
    if Len(path) < 6 or Len(path) > 2048 or Left(path, 5) <> "/api/" then return ""
    if Instr(1, path, Chr(10)) > 0 or Instr(1, path, Chr(13)) > 0 or Instr(1, path, Chr(9)) > 0 or Instr(1, path, " ") > 0 then return ""
    if Instr(1, path, "#") > 0 or Instr(1, path, "@") > 0 then return ""
    route = path
    queryStart = Instr(1, route, "?")
    if queryStart > 0 then route = Left(route, queryStart - 1)
    lowerRoute = LCase(route)
    if Instr(1, route, "..") > 0 or Instr(1, route, "\") > 0 or Instr(1, route, "//") > 0 then return ""
    if Instr(1, lowerRoute, "%2e") > 0 or Instr(1, lowerRoute, "%2f") > 0 or Instr(1, lowerRoute, "%5c") > 0 then return ""
    return path
end function

function PorticoContentSafeId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoContentSafeCursor(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 512 then return ""
    if Instr(1, normalized, Chr(0)) > 0 or Instr(1, normalized, Chr(10)) > 0 or Instr(1, normalized, Chr(13)) > 0 or Instr(1, normalized, Chr(9)) > 0 then return ""
    return normalized
end function

function PorticoContentSafeText(value as dynamic, maximumLength as integer) as string
    if value = invalid then return ""
    normalized = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(normalized) > maximumLength then normalized = Left(normalized, maximumLength)
    return normalized
end function

function PorticoContentSafeLabels(source as dynamic, maximumCount as integer, maximumLength as integer) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each rawValue in source
        value = PorticoContentSafeText(rawValue, maximumLength)
        if value <> "" then result.push(value)
        if result.count() >= maximumCount then exit for
    end for
    return result
end function

function PorticoContentJoinMeta(parts as object) as string
    result = ""
    separator = "  " + Chr(183) + "  "
    for each part in parts
        if result <> "" then result = result + separator
        result = result + part
    end for
    return result
end function
