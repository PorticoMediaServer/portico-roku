sub init()
    m.scrim = m.top.FindNode("scrim")
    m.panelSurface = m.top.FindNode("panelSurface")
    m.context = m.top.FindNode("context")
    m.title = m.top.FindNode("title")
    m.body = m.top.FindNode("body")
    m.status = m.top.FindNode("status")
    m.backAction = m.top.FindNode("backAction")
    m.closeAction = m.top.FindNode("closeAction")
    m.scrim.uri = "pkg:/images/ui/overlay-scrim.png"
    m.panelSurface.uri = "pkg:/images/ui/server-panel-5.png"
    m.context.font = PorticoFont("500", 17)
    m.context.color = "#8F9BA6"
    m.title.font = PorticoFont("600", 32)
    m.title.color = "#F4F7FA"
    m.status.font = PorticoFont("500", 18)
    m.status.color = "#8F9BA6"
    m.backAction.model = {iconId: "navigation.back"}
    m.closeAction.model = {iconId: "action.close"}
    loadedIcons = PorticoIconResolverLoad()
    m.iconManifest = invalid
    if loadedIcons.ok then m.iconManifest = loadedIcons.value
    m.top.focusable = true
    m.mode = "menu"
    m.focusedIndex = 0
    m.menu = []
    m.targets = []
    m.rating = 0
    m.activationSequence = 0
    m.wasOpen = false
    m.headerFocus = ""
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or Type(state) <> "roAssociativeArray" then state = {}
    isOpen = state.open = true
    if isOpen and not m.wasOpen
        m.mode = "menu"
        m.focusedIndex = 0
        m.headerFocus = ""
    end if
    m.wasOpen = isOpen
    model = state.model
    if model = invalid or Type(model) <> "roAssociativeArray" then model = {}
    m.model = model
    m.mediaId = DetailMoreId(model.id)
    m.context.text = DetailMoreText(model.title, "Media", 100)
    more = model.moreActions
    if more = invalid or Type(more) <> "roAssociativeArray" then more = {}
    m.more = more
    m.menu = DetailMoreMenu(more.menu)
    m.rating = DetailMoreRating(more.rating)
    m.targets = DetailMoreTargets(model.targets)
    targetKind = LCase(DetailMoreText(model.targetKind, "", 16))
    if (targetKind = "playlist" or targetKind = "collection") and (m.mode = "playlist" or m.mode = "collection") then m.mode = targetKind
    DetailMoreClampFocus()
    DetailMoreRender()
end sub

sub DetailMoreRender()
    m.body.RemoveChildrenIndex(m.body.GetChildCount(), 0)
    showBack = m.mode <> "menu"
    if not showBack and m.headerFocus = "back" then m.headerFocus = "close"
    m.backAction.visible = showBack
    m.backAction.focused = m.headerFocus = "back"
    m.closeAction.focused = m.headerFocus = "close"
    titleX = 28
    titleWidth = 580
    if showBack
        titleX = 104
        titleWidth = 500
    end if
    m.context.translation = [titleX, 25]
    m.context.width = titleWidth
    m.title.translation = [titleX, 52]
    m.title.width = titleWidth
    m.title.text = DetailMoreTitle()
    status = LCase(DetailMoreText(m.model.moreActionStatus, "idle", 20))
    message = DetailMoreText(m.model.moreActionMessage, "", 120)
    m.status.text = message
    m.status.color = "#8F9BA6"
    if status = "working"
        m.status.text = "Saving…"
        m.status.color = "#70BCE8"
    else if status = "error"
        m.status.color = "#ED5B67"
    else if status = "success"
        m.status.color = "#62C9A7"
    end if
    if m.mode = "rating"
        DetailMoreRenderRating()
    else if m.mode = "playlist" or m.mode = "collection"
        DetailMoreRenderTargets()
    else
        DetailMoreRenderMenu()
    end if
end sub

function DetailMoreTitle() as string
    if m.mode = "rating" then return "Your rating"
    if m.mode = "playlist" then return "Add to playlist"
    if m.mode = "collection" then return "Add to collection"
    return "More actions"
end function

sub DetailMoreRenderMenu()
    firstVisible = DetailMoreFirstVisible(m.menu.Count(), 7)
    for index = firstVisible to m.menu.Count() - 1
        visibleIndex = index - firstVisible
        if visibleIndex >= 7 then exit for
        item = m.menu[index]
        DetailMoreRenderRow(item.label, item.description, item.iconId, item.selected = true, m.headerFocus = "" and index = m.focusedIndex, visibleIndex * 86)
    end for
end sub

sub DetailMoreRenderTargets()
    targetStatus = LCase(DetailMoreText(m.model.targetsStatus, "idle", 20))
    if targetStatus = "loading"
        DetailMoreRenderMessage("Loading " + DetailMoreKindPlural() + "…", "#C7D0D8")
        return
    else if targetStatus = "error"
        DetailMoreRenderMessage("Your " + DetailMoreKindPlural() + " couldn’t be loaded.", "#ED5B67")
        return
    end if
    itemCount = m.targets.Count()
    if m.mode = "collection" then itemCount = itemCount + 1
    if itemCount = 0
        DetailMoreRenderMessage("No playlists are available yet.", "#8F9BA6")
        return
    end if
    firstVisible = DetailMoreFirstVisible(itemCount, 7)
    for index = firstVisible to itemCount - 1
        visibleIndex = index - firstVisible
        if visibleIndex >= 7 then exit for
        if index < m.targets.Count()
            target = m.targets[index]
            DetailMoreRenderRow(target.title, target.meta, DetailMoreKindIcon(), false, m.headerFocus = "" and index = m.focusedIndex, visibleIndex * 86)
        else
            DetailMoreRenderRow("Create a " + m.mode, "", "plus", false, m.headerFocus = "" and index = m.focusedIndex, visibleIndex * 86)
        end if
    end for
end sub

sub DetailMoreRenderRating()
    score = "—"
    if m.focusedIndex >= 0 and m.focusedIndex < 10 then score = (m.focusedIndex + 1).ToStr()
    scoreLabel = PorticoLabel(m.body, score, [0, 2], 664, 60, 48, "700", "#F4F7FA")
    scoreLabel.horizAlign = "center"
    scaleLabel = PorticoLabel(m.body, "out of 10", [0, 58], 664, 28, 19, "400", "#8F9BA6")
    scaleLabel.horizAlign = "center"
    for index = 0 to 9
        row = Int(index / 5)
        column = index mod 5
        x = 107 + column * 92
        y = 110 + row * 82
        focused = m.headerFocus = "" and index = m.focusedIndex
        selected = index + 1 = m.rating
        surface = m.body.CreateChild("Poster")
        surface.translation = [x, y]
        surface.width = 72
        surface.height = 64
        surface.loadWidth = 104
        surface.loadHeight = 56
        surface.loadDisplayMode = "scaleToFill"
        surface.uri = "pkg:/images/ui/search-key-idle.png"
        if focused then surface.uri = "pkg:/images/ui/search-key-focus.png"
        color = "#C7D0D8"
        if selected then color = "#70BCE8"
        label = PorticoLabel(m.body, (index + 1).ToStr(), [x, y], 72, 64, 23, "600", color)
        label.horizAlign = "center"
        label.vertAlign = "center"
    end for
    if m.rating > 0 then DetailMoreRenderRow("Clear rating", "", "x", false, m.headerFocus = "" and m.focusedIndex = 10, 300)
end sub

sub DetailMoreRenderMessage(message as string, color as string)
    lines = PorticoBreakText(message, 620, 21, "400", 3)
    PorticoRenderLines(m.body, lines, [22, 42], 620, 30, 21, "400", color)
    if m.mode = "collection" then DetailMoreRenderRow("Create a collection", "", "plus", false, m.focusedIndex = 0, 220)
end sub

sub DetailMoreRenderRow(labelText as string, metaText as string, iconName as string, selected as boolean, focused as boolean, y as integer)
    surface = m.body.CreateChild("Poster")
    surface.translation = [0, y]
    surface.width = 680
    surface.height = 84
    surface.loadWidth = 680
    surface.loadHeight = 84
    surface.loadDisplayMode = "scaleToFill"
    surface.uri = "pkg:/images/ui/settings-choice-idle.png"
    if selected then surface.uri = "pkg:/images/ui/settings-choice-selected.png"
    if focused then surface.uri = "pkg:/images/ui/settings-choice-focus.png"
    icon = m.body.CreateChild("Poster")
    icon.translation = [20, y + 28]
    icon.width = 28
    icon.height = 28
    icon.loadWidth = 64
    icon.loadHeight = 64
    icon.loadDisplayMode = "scaleToFit"
    iconState = "rail"
    if focused then iconState = "focused" else if selected then iconState = "selected"
    icon.uri = PorticoIconResolverUri(m.iconManifest, DetailMoreIcon(iconName), iconState)
    if metaText = ""
        label = PorticoLabel(m.body, labelText, [66, y], 570, 84, 23, "600", "#F4F7FA")
        label.vertAlign = "center"
    else
        PorticoLabel(m.body, labelText, [66, y + 12], 570, 30, 23, "600", "#F4F7FA")
        PorticoLabel(m.body, metaText, [66, y + 47], 570, 24, 17, "400", "#8F9BA6")
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if LCase(DetailMoreText(m.model.moreActionStatus, "idle", 20)) = "working" then return true
    if key = "back"
        if m.mode = "menu"
            DetailMoreEmit("close-detail-more", {})
        else
            m.mode = "menu"
            m.focusedIndex = 0
            DetailMoreRender()
        end if
        return true
    end if
    if m.headerFocus <> ""
        if key = "left" and m.mode <> "menu"
            m.headerFocus = "back"
        else if key = "right"
            m.headerFocus = "close"
        else if key = "down"
            m.headerFocus = ""
        else if key = "OK"
            if m.headerFocus = "back"
                m.mode = "menu"
                m.focusedIndex = 0
                m.headerFocus = ""
            else
                DetailMoreEmit("close-detail-more", {})
            end if
        end if
        DetailMoreRender()
        return true
    end if
    if key = "up"
        atTop = m.focusedIndex = 0
        if m.mode = "rating" then atTop = m.focusedIndex >= 0 and m.focusedIndex < 5
        if atTop
            if m.mode = "menu" then m.headerFocus = "close" else m.headerFocus = "back"
            DetailMoreRender()
            return true
        end if
    end if
    if m.mode = "rating" then return DetailMoreRatingKey(key)
    count = m.menu.Count()
    if m.mode = "playlist" then count = m.targets.Count()
    if m.mode = "collection" then count = m.targets.Count() + 1
    if key = "up"
        if m.focusedIndex > 0 then m.focusedIndex = m.focusedIndex - 1
    else if key = "down"
        if m.focusedIndex < count - 1 then m.focusedIndex = m.focusedIndex + 1
    else if key = "OK"
        DetailMoreActivate()
        return true
    else if key = "left" or key = "right"
        return true
    else
        return false
    end if
    DetailMoreRender()
    return true
end function

function DetailMoreRatingKey(key as string) as boolean
    maximum = 9
    if m.rating > 0 then maximum = 10
    if key = "left"
        if m.focusedIndex > 0 and m.focusedIndex < 10 then m.focusedIndex = m.focusedIndex - 1
    else if key = "right"
        if m.focusedIndex < 9 then m.focusedIndex = m.focusedIndex + 1
    else if key = "up"
        if m.focusedIndex = 10
            m.focusedIndex = 5
        else if m.focusedIndex >= 5
            m.focusedIndex = m.focusedIndex - 5
        end if
    else if key = "down"
        if m.focusedIndex < 5
            m.focusedIndex = m.focusedIndex + 5
        else if m.rating > 0
            m.focusedIndex = 10
        end if
    else if key = "OK"
        rating = m.focusedIndex + 1
        if m.focusedIndex = 10 then rating = 0
        DetailMoreEmit("set-detail-rating", {targetId: m.mediaId, rating: rating})
        return true
    else
        return false
    end if
    if m.focusedIndex > maximum then m.focusedIndex = maximum
    DetailMoreRender()
    return true
end function

sub DetailMoreActivate()
    if m.mode = "playlist" or m.mode = "collection"
        if m.focusedIndex < m.targets.Count()
            target = m.targets[m.focusedIndex]
            DetailMoreEmit("add-detail-target", {targetKind: m.mode, savedTargetId: target.id, targetId: m.mediaId})
        else if m.mode = "collection"
            DetailMoreOpenKeyboard()
        end if
        return
    end if
    if m.focusedIndex < 0 or m.focusedIndex >= m.menu.Count() then return
    item = m.menu[m.focusedIndex]
    if item.id = "queue-play-next"
        DetailMoreEmit("detail-queue", {position: "play_next", targetId: m.mediaId})
    else if item.id = "queue-append"
        DetailMoreEmit("detail-queue", {position: "append", targetId: m.mediaId})
    else if item.id = "open-playlist-targets" or item.id = "open-collection-targets"
        m.mode = "playlist"
        if item.id = "open-collection-targets" then m.mode = "collection"
        m.focusedIndex = 0
        DetailMoreEmit("open-detail-targets", {targetKind: m.mode, targetId: m.mediaId})
        DetailMoreRender()
    else if item.id = "open-rating"
        m.mode = "rating"
        m.focusedIndex = m.rating - 1
        if m.focusedIndex < 0 then m.focusedIndex = 0
        DetailMoreRender()
    else if item.id = "reaction-like" or item.id = "reaction-dislike"
        requested = "like"
        if item.id = "reaction-dislike" then requested = "dislike"
        current = LCase(DetailMoreText(m.more.reaction, "", 16))
        if current = requested then requested = ""
        DetailMoreEmit("set-detail-reaction", {targetId: m.mediaId, reaction: requested})
    end if
end sub

sub DetailMoreOpenKeyboard()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    if dialog = invalid then return
    dialog.title = "New " + m.mode
    dialog.message = ["Enter a name."]
    dialog.buttons = ["Create", "Cancel"]
    dialog.textEditBox.maxTextLength = 160
    dialog.ObserveFieldScoped("buttonSelected", "DetailMoreKeyboardSelected")
    m.keyboardDialog = dialog
    m.top.GetScene().dialog = dialog
end sub

sub DetailMoreKeyboardSelected()
    dialog = m.keyboardDialog
    if dialog = invalid then return
    accepted = dialog.buttonSelected = 0
    title = DetailMoreText(dialog.text, "", 160)
    dialog.text = ""
    dialog.UnobserveFieldScoped("buttonSelected")
    m.top.GetScene().dialog = invalid
    m.keyboardDialog = invalid
    if accepted and title <> "" then DetailMoreEmit("create-detail-target", {targetKind: m.mode, title: title, targetId: m.mediaId})
end sub

sub DetailMoreEmit(kind as string, fields as object)
    m.activationSequence = m.activationSequence + 1
    event = {sequence: m.activationSequence, kind: kind, page: "detail-more"}
    for each key in fields
        event[key] = fields[key]
    end for
    m.top.activation = event
end sub

sub DetailMoreClampFocus()
    count = m.menu.Count()
    if m.mode = "rating"
        count = 10
        if m.rating > 0 then count = 11
    else if m.mode = "playlist"
        count = m.targets.Count()
    else if m.mode = "collection"
        count = m.targets.Count() + 1
    end if
    if m.focusedIndex < 0 then m.focusedIndex = 0
    if m.focusedIndex >= count then m.focusedIndex = count - 1
    if m.focusedIndex < 0 then m.focusedIndex = 0
end sub

function DetailMoreFirstVisible(count as integer, visibleCount as integer) as integer
    first = 0
    if m.focusedIndex >= visibleCount then first = m.focusedIndex - visibleCount + 1
    maximum = count - visibleCount
    if maximum < 0 then maximum = 0
    if first > maximum then first = maximum
    return first
end function

function DetailMoreMenu(value as dynamic) as object
    result = []
    if value = invalid or GetInterface(value, "ifArray") = invalid then return result
    allowed = {"queue-play-next": true, "queue-append": true, "open-playlist-targets": true, "open-collection-targets": true, "open-rating": true, "reaction-like": true, "reaction-dislike": true}
    for each source in value
        if result.Count() >= 12 then exit for
        if source <> invalid and Type(source) = "roAssociativeArray"
            id = LCase(DetailMoreText(source.id, "", 48))
            label = DetailMoreText(source.label, "", 80)
            if allowed[id] = true and label <> "" then result.Push({id: id, label: label, description: DetailMoreText(source.description, "", 120), iconId: DetailMoreMenuIcon(id, source.iconId), selected: source.selected = true})
        end if
    end for
    return result
end function

function DetailMoreMenuIcon(id as string, sourceIcon as dynamic) as string
    if id = "queue-play-next" then return "action.add-to-list"
    if id = "queue-append" then return "playback.queue"
    if id = "open-playlist-targets" then return "media.playlist"
    if id = "open-collection-targets" then return "library.saved"
    if id = "open-rating" then return "action.rate"
    if id = "reaction-like" then return "action.like"
    if id = "reaction-dislike" then return "action.dislike"
    return "status.icon-mapping-missing"
end function

function DetailMoreTargets(value as dynamic) as object
    result = []
    if value = invalid or GetInterface(value, "ifArray") = invalid then return result
    for each source in value
        if result.Count() >= 50 then exit for
        if source <> invalid and Type(source) = "roAssociativeArray" and source.canEdit = true
            id = DetailMoreId(source.id)
            title = DetailMoreText(source.title, "", 100)
            if id <> "" and title <> ""
                count = PorticoHttpInteger(source.itemCount, 0)
                meta = DetailMoreText(source.meta, "", 100)
                if meta = ""
                    meta = count.ToStr() + " items"
                    if count = 1 then meta = "1 item"
                end if
                result.Push({id: id, title: title, meta: meta})
            end if
        end if
    end for
    return result
end function

function DetailMoreRating(value as dynamic) as integer
    rating = PorticoHttpInteger(value, 0)
    if rating < 0 or rating > 10 then return 0
    return rating
end function

function DetailMoreKindPlural() as string
    if m.mode = "playlist" then return "playlists"
    return "collections"
end function

function DetailMoreKindIcon() as string
    if m.mode = "playlist" then return "media.playlist"
    return "library.saved"
end function

function DetailMoreIcon(value as dynamic) as string
    iconId = LCase(DetailMoreText(value, "status.icon-mapping-missing", 120))
    if m.iconManifest <> invalid and m.iconManifest.semanticToMaster[iconId] <> invalid then return iconId
    return "status.icon-mapping-missing"
end function

function DetailMoreId(value as dynamic) as string
    id = DetailMoreText(value, "", 128)
    if id = "" then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for index = 1 to Len(id)
        if Instr(1, allowed, Mid(id, index, 1)) = 0 then return ""
    end for
    return id
end function

function DetailMoreText(value as dynamic, fallback as string, maximum as integer) as string
    result = fallback
    if value <> invalid then result = value.ToStr()
    result = result.Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if result = "" then result = fallback
    if Len(result) > maximum then result = Left(result, maximum)
    return result
end function
