function PorticoMediaQuickActionIds(model as dynamic) as object
    result = []
    if model = invalid or Type(model) <> "roAssociativeArray" then return result
    actions = model.actions
    if actions = invalid or GetInterface(actions, "ifArray") = invalid then return result
    hasWatchlist = false
    hasFavorite = false
    hasWatched = false
    for each rawAction in actions
        action = LCase(rawAction.ToStr())
        if action = "watchlist.add" or action = "watchlist.remove" then hasWatchlist = true
        if action = "favorite.add" or action = "favorite.remove" then hasFavorite = true
        if action = "watched.set" then hasWatched = true
    end for
    if hasWatchlist then result.push("saved-toggle")
    if hasFavorite then result.push("favorite-toggle")
    if hasWatched then result.push("watched-toggle")
    return result
end function

function PorticoMediaQuickActionsModel(model as dynamic) as object
    result = { title: "", actions: [] }
    if model = invalid or Type(model) <> "roAssociativeArray" then return result
    result.title = Left(model.title.ToStr(), 80)
    ids = PorticoMediaQuickActionIds(model)
    for each id in ids
        if id = "saved-toggle"
            selected = model.watchlisted = true
            label = "Add to Saved"
            if selected then label = "Remove from Saved"
            result.actions.push({ id: id, label: label, iconId: "action.watchlist", selected: selected, width: 360 })
        else if id = "favorite-toggle"
            selected = model.favorite = true
            label = "Favorite"
            if selected then label = "Remove Favorite"
            result.actions.push({ id: id, label: label, iconId: "action.favorite", selected: selected, width: 360 })
        else if id = "watched-toggle"
            selected = model.watched = true
            label = "Mark as Watched"
            if selected then label = "Mark as Unwatched"
            result.actions.push({ id: id, label: label, iconId: "action.mark-watched", selected: selected, width: 360 })
        end if
    end for
    return result
end function
