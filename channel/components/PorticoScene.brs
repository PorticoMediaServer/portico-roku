sub init()
    m.designRoot = m.top.findNode("designRoot")
    m.projector = m.top.findNode("projector")
    m.content = m.top.findNode("content")
    m.stateScreen = m.top.findNode("stateScreen")
    m.railLayer = m.top.findNode("railLayer")
    m.rail = m.top.findNode("rail")
    m.homeScreen = invalid
    m.detailScreen = invalid
    m.searchScreen = invalid
    m.personScreen = invalid
    m.libraryScreen = invalid
    m.savedScreen = invalid
    m.channelsScreen = invalid
    m.profileScreen = invalid
    m.settingsScreen = invalid
    m.playerScreen = invalid
    m.detailMoreScreen = invalid
    m.homeCustomizeOverlay = invalid
    m.detailSeasonOverlay = invalid
    m.watchWithFriendsOverlay = invalid
    m.globalImportantNotice = invalid
    m.globalFeedbackOverlay = invalid
    m.serverSelectionScreen = invalid
    m.profileSelectionScreen = invalid
    m.authGate = invalid
    m.localAuthScreen = invalid
    m.layout = invalid
    m.surfaceGeneration = 0
    m.lifecycleGeneration = 1

    m.railExpanded = false
    m.focusArea = "homeActions"
    m.homeFocusedAction = 0
    m.homeFocusedRow = 0
    m.homeFocusedIndices = []
    m.homeFocusedRowId = ""
    m.homeFocusedItemIds = {}
    m.homeHeroIndex = 0
    m.detailFocusedAction = 0
    m.focusedEpisode = 0
    m.detailFocusedPerson = 0
    m.detailFocusedPersonResult = 0
    m.detailFocusedRelationshipRow = 0
    m.detailFocusedRelationshipItem = 0
    m.detailFactsOpen = false
    m.detailMoreOpen = false
    m.homeCustomizeOpen = false
    m.detailSeasonOpen = false
    m.watchWithFriendsOpen = false
    m.watchWithFriendsContext = {mediaId: "", mediaTitle: ""}
    m.feedbackOpen = false
    m.feedbackInitialKind = "general"
    m.feedbackContext = {}
    m.overlayInvokerFocusId = ""
    m.globalNoticeFocused = false
    m.globalNoticePreviousFocus = ""
    m.lastFocusedNoticeKey = ""
    m.pendingDismissNoticeKey = ""
    m.focusedRailIndex = 0
    m.selectedRailIndex = 0
    m.focusBeforeRail = "homeActions"
    m.activationSequence = 0
    m.lastExternalRequestSequence = 0
    m.lastExternalRequestDeliveryId = ""
    m.lastPlaybackPresentationSequence = 0
    m.routeFocusedAction = 0
    m.serverFocusedIndex = 0
    m.serverListOffset = 0
    m.serverPickerWaitingForList = false
    m.navigationStore = PorticoNavigationStoreCreate("home", 0)
    PorticoSceneSyncNavigationAliases()
    m.activationTransactions = PorticoActivationTransactionsCreate()
    m.backCoordinator = PorticoBackCoordinatorCreate()
    m.railController = PorticoRailControllerCreate("route.home")
    m.focusMemory = PorticoFocusMemoryCreate(128)
    m.focusTrace = PorticoFocusTraceCreate(64)
    m.sceneFocusContainer = PorticoFocusContainerCreate("scene.current", ["home.focus.homeActions"])
    m.screenAuthority = PorticoScreenAuthorityCreate("scene")
    m.libraryItems = []
    m.signedOutGateMode = "landing"
    m.lastAccountSignedIn = false
    m.lastViewerPublished = false
    m.lastPublishedViewerGeneration = 0
    m.profileGateVisible = false
    loadedLanguage = PorticoProductLanguageLoad()
    m.productLanguage = invalid
    if loadedLanguage.ok then m.productLanguage = loadedLanguage.value
    m.playbackIdentity = {title: "", meta: ""}
    m.top.setFocus(true)
end sub

sub PorticoSceneRefreshFocusGraph()
    if m.screenAuthority = invalid then return
    PorticoScreenAuthorityFence(m.screenAuthority, m.navigationStore.viewerEpoch)
    railIds = []
    for index = 0 to railItemCount() - 1
        railItem = railItemAt(index)
        if railItem <> invalid then railIds.Push("rail." + safeRuntimeLabel(railItem.id, railItem.route, 192))
    end for
    contentId = PorticoSceneSemanticFocusId()
    if m.focusArea = "rail"
        remembered = PorticoFocusRecall(m.focusMemory, m.route, m.navigationStore.viewerEpoch)
        if remembered <> "" then contentId = remembered
    end if
    PorticoScreenAuthoritySetContainer(m.screenAuthority, "scene.rail", railIds)
    PorticoScreenAuthoritySetContainer(m.screenAuthority, "scene.content", [contentId])
    PorticoScreenAuthoritySetNeighbor(m.screenAuthority, "scene.content", "left", "scene.rail")
    PorticoScreenAuthoritySetNeighbor(m.screenAuthority, "scene.rail", "right", "scene.content")
    if m.focusArea = "rail"
        PorticoScreenAuthorityFocused(m.screenAuthority, PorticoSceneSemanticFocusId())
    else
        PorticoScreenAuthorityFocused(m.screenAuthority, contentId)
    end if
end sub

' Compatibility fields are render-only aliases. PorticoNavigationStore is the
' sole writer for destination and history state.
sub PorticoSceneSyncNavigationAliases()
    destination = PorticoNavigationCurrent(m.navigationStore)
    if destination = invalid then return
    m.route = destination.route
    m.page = destination.route
end sub

function PorticoSceneCreateSurface(componentName as string, nodeId as string, parent as dynamic, activationHandler = "" as string, secondaryField = "" as string, secondaryHandler = "" as string) as dynamic
    if parent = invalid then return invalid
    existing = m.top.findNode(nodeId)
    if existing <> invalid then return existing
    node = CreateObject("roSGNode", componentName)
    if node = invalid then return invalid
    node.id = nodeId
    node.visible = false
    parent.appendChild(node)
    if activationHandler <> "" then node.ObserveField("activation", activationHandler)
    if secondaryField <> "" and secondaryHandler <> "" then node.ObserveField(secondaryField, secondaryHandler)
    m.surfaceGeneration = m.surfaceGeneration + 1
    return node
end function

sub PorticoSceneEnsureBaseNodes()
    if m.designRoot = invalid then m.designRoot = m.top.findNode("designRoot")
    if m.projector = invalid then m.projector = m.top.findNode("projector")
    if m.content = invalid then m.content = m.top.findNode("content")
    if m.railLayer = invalid then m.railLayer = m.top.findNode("railLayer")
    if m.rail = invalid then m.rail = m.top.findNode("rail")
    if m.stateScreen = invalid then m.stateScreen = m.top.findNode("stateScreen")
end sub

function PorticoSceneEnsureRouteSurface(route as string) as dynamic
    normalized = route
    if Left(normalized, 8) = "library/" then normalized = "library"
    if normalized = "home"
        if m.homeScreen = invalid then m.homeScreen = PorticoSceneCreateSurface("PorticoHome", "homeScreen", m.content)
        if m.homeScreen <> invalid and m.contract <> invalid then m.homeScreen.compensation = m.contract.rokuCompensation
        return m.homeScreen
    else if normalized = "detail"
        if m.detailScreen = invalid then m.detailScreen = PorticoSceneCreateSurface("PorticoDetail", "detailScreen", m.content)
        if m.detailScreen <> invalid and m.contract <> invalid then m.detailScreen.compensation = m.contract.rokuCompensation
        return m.detailScreen
    else if normalized = "search"
        if m.searchScreen = invalid then m.searchScreen = PorticoSceneCreateSurface("PorticoSearchScreen", "searchScreen", m.content, "searchActivationChanged")
        return m.searchScreen
    else if normalized = "person"
        if m.personScreen = invalid then m.personScreen = PorticoSceneCreateSurface("PorticoPersonScreen", "personScreen", m.content, "personActivationChanged")
        return m.personScreen
    else if normalized = "library"
        if m.libraryScreen = invalid then m.libraryScreen = PorticoSceneCreateSurface("PorticoLibraryScreen", "libraryScreen", m.content, "libraryActivationChanged")
        return m.libraryScreen
    else if normalized = "saved"
        if m.savedScreen = invalid then m.savedScreen = PorticoSceneCreateSurface("PorticoSavedScreen", "savedScreen", m.content, "savedActivationChanged")
        return m.savedScreen
    else if normalized = "channels"
        if m.channelsScreen = invalid then m.channelsScreen = PorticoSceneCreateSurface("PorticoChannelsScreen", "channelsScreen", m.content, "channelsActivationChanged")
        return m.channelsScreen
    else if normalized = "profile"
        if m.profileScreen = invalid then m.profileScreen = PorticoSceneCreateSurface("PorticoProfileScreen", "profileScreen", m.content, "profileActivationChanged")
        return m.profileScreen
    else if normalized = "settings"
        if m.settingsScreen = invalid then m.settingsScreen = PorticoSceneCreateSurface("PorticoSettingsScreen", "settingsScreen", m.content, "settingsActivationChanged", "modalOpen", "settingsModalChanged")
        return m.settingsScreen
    end if
    return invalid
end function

function PorticoSceneEnsureOverlaySurface(kind as string) as dynamic
    if m.designRoot = invalid then return invalid
    if kind = "server-selection"
        if m.serverSelectionScreen = invalid then m.serverSelectionScreen = PorticoSceneCreateSurface("PorticoServerSelection", "serverSelectionScreen", m.designRoot)
        return m.serverSelectionScreen
    else if kind = "profile-selection"
        if m.profileSelectionScreen = invalid then m.profileSelectionScreen = PorticoSceneCreateSurface("PorticoProfileSelectionScreen", "profileSelectionScreen", m.designRoot, "profileSelectionActivationChanged")
        return m.profileSelectionScreen
    else if kind = "auth-gate"
        if m.authGate = invalid then m.authGate = PorticoSceneCreateSurface("PorticoAuthGate", "authGate", m.designRoot, "authGateActivationChanged")
        return m.authGate
    else if kind = "local-auth"
        if m.localAuthScreen = invalid then m.localAuthScreen = PorticoSceneCreateSurface("PorticoLocalAuthScreen", "localAuthScreen", m.designRoot, "localAuthActivationChanged")
        return m.localAuthScreen
    else if kind = "player"
        if m.playerScreen = invalid then m.playerScreen = PorticoSceneCreateSurface("PorticoPlayer", "playerScreen", m.designRoot, "playerEventChanged")
        return m.playerScreen
    else if kind = "detail-more"
        if m.detailMoreScreen = invalid then m.detailMoreScreen = PorticoSceneCreateSurface("PorticoDetailMoreScreen", "detailMoreScreen", m.designRoot, "detailMoreActivationChanged")
        return m.detailMoreScreen
    else if kind = "home-customize"
        if m.homeCustomizeOverlay = invalid then m.homeCustomizeOverlay = PorticoSceneCreateSurface("PorticoHomeCustomizeOverlay", "homeCustomizeOverlay", m.designRoot, "homeCustomizeActivationChanged")
        return m.homeCustomizeOverlay
    else if kind = "detail-season"
        if m.detailSeasonOverlay = invalid then m.detailSeasonOverlay = PorticoSceneCreateSurface("PorticoDetailSeasonOverlay", "detailSeasonOverlay", m.designRoot, "detailSeasonActivationChanged")
        return m.detailSeasonOverlay
    else if kind = "watch-with-friends"
        if m.watchWithFriendsOverlay = invalid then m.watchWithFriendsOverlay = PorticoSceneCreateSurface("PorticoWatchWithFriendsOverlay", "watchWithFriendsOverlay", m.designRoot, "", "action", "watchWithFriendsActionChanged")
        return m.watchWithFriendsOverlay
    else if kind = "important-notice"
        if m.globalImportantNotice = invalid then m.globalImportantNotice = PorticoSceneCreateSurface("PorticoImportantNotice", "globalImportantNotice", m.designRoot, "globalImportantNoticeActivationChanged")
        return m.globalImportantNotice
    else if kind = "feedback"
        if m.globalFeedbackOverlay = invalid then m.globalFeedbackOverlay = PorticoSceneCreateSurface("PorticoFeedbackOverlay", "globalFeedbackOverlay", m.designRoot, "globalFeedbackActivationChanged")
        return m.globalFeedbackOverlay
    end if
    return invalid
end function

sub PorticoSceneSetVisible(node as dynamic, visible as boolean)
    if node <> invalid then node.visible = visible
end sub

function PorticoSceneIsVisible(node as dynamic) as boolean
    return node <> invalid and node.visible = true
end function

sub PorticoSceneReleaseNode(node as dynamic, parent as dynamic)
    if node = invalid or parent = invalid then return
    node.visible = false
    if node = m.playerScreen
        node.privateContent = invalid
        node.watchGroupState = invalid
        node.watchSyncDirective = invalid
        node.remotePlaybackDirective = invalid
    end if
    parent.removeChild(node)
end sub

sub PorticoSceneReleaseInactiveRouteSurfaces(activeRoute as string)
    normalized = activeRoute
    if Left(normalized, 8) = "library/" then normalized = "library"
    if normalized <> "home" and m.homeScreen <> invalid
        PorticoSceneReleaseNode(m.homeScreen, m.content)
        m.homeScreen = invalid
    end if
    if normalized <> "detail" and m.detailScreen <> invalid
        PorticoSceneReleaseNode(m.detailScreen, m.content)
        m.detailScreen = invalid
    end if
    if normalized <> "search" and m.searchScreen <> invalid
        PorticoSceneReleaseNode(m.searchScreen, m.content)
        m.searchScreen = invalid
    end if
    if normalized <> "person" and m.personScreen <> invalid
        PorticoSceneReleaseNode(m.personScreen, m.content)
        m.personScreen = invalid
    end if
    if normalized <> "library" and m.libraryScreen <> invalid
        PorticoSceneReleaseNode(m.libraryScreen, m.content)
        m.libraryScreen = invalid
    end if
    if normalized <> "saved" and m.savedScreen <> invalid
        PorticoSceneReleaseNode(m.savedScreen, m.content)
        m.savedScreen = invalid
    end if
    if normalized <> "channels" and m.channelsScreen <> invalid
        PorticoSceneReleaseNode(m.channelsScreen, m.content)
        m.channelsScreen = invalid
    end if
    if normalized <> "profile" and m.profileScreen <> invalid
        PorticoSceneReleaseNode(m.profileScreen, m.content)
        m.profileScreen = invalid
    end if
    if normalized <> "settings" and m.settingsScreen <> invalid
        PorticoSceneReleaseNode(m.settingsScreen, m.content)
        m.settingsScreen = invalid
    end if
end sub

sub PorticoSceneReleaseClosedOverlays()
    if not m.feedbackOpen and m.globalFeedbackOverlay <> invalid
        PorticoSceneReleaseNode(m.globalFeedbackOverlay, m.designRoot)
        m.globalFeedbackOverlay = invalid
    end if
    if not m.watchWithFriendsOpen and m.watchWithFriendsOverlay <> invalid
        PorticoSceneReleaseNode(m.watchWithFriendsOverlay, m.designRoot)
        m.watchWithFriendsOverlay = invalid
    end if
    if not m.detailSeasonOpen and m.detailSeasonOverlay <> invalid
        PorticoSceneReleaseNode(m.detailSeasonOverlay, m.designRoot)
        m.detailSeasonOverlay = invalid
    end if
    if not m.detailMoreOpen and m.detailMoreScreen <> invalid
        PorticoSceneReleaseNode(m.detailMoreScreen, m.designRoot)
        m.detailMoreScreen = invalid
    end if
    if not m.homeCustomizeOpen and m.homeCustomizeOverlay <> invalid
        PorticoSceneReleaseNode(m.homeCustomizeOverlay, m.designRoot)
        m.homeCustomizeOverlay = invalid
    end if
    if not m.globalNoticeFocused and m.globalImportantNotice <> invalid and not PorticoSceneIsVisible(m.globalImportantNotice)
        PorticoSceneReleaseNode(m.globalImportantNotice, m.designRoot)
        m.globalImportantNotice = invalid
    end if
    if m.route <> "player" and m.playerScreen <> invalid
        PorticoSceneReleaseNode(m.playerScreen, m.designRoot)
        m.playerScreen = invalid
    end if
end sub

' Private presentation-only handoff used after Main has successfully enqueued a
' remotely requested load. It never emits an activation, so opening Player cannot
' feed back into playback startup or acknowledge a command twice.
sub playbackPresentationCommandChanged()
    if m.contract = invalid then return
    command = m.top.playbackPresentationCommand
    if command = invalid or Type(command) <> "roAssociativeArray" then return
    allowed = {sequence: true, kind: true, viewerGeneration: true, identity: true}
    for each key in command
        if allowed[key] <> true then return
    end for
    if command.Count() <> 4 then return
    sequence = PorticoSceneSafeInteger(command.sequence, 0)
    if sequence <= m.lastPlaybackPresentationSequence then return
    if LCase(safeRuntimeLabel(command.kind, "", 32)) <> "open-player" then return
    state = m.top.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" then return
    generation = PorticoSceneSafeInteger(command.viewerGeneration, 0)
    if generation <= 0 or generation <> PorticoSceneSafeInteger(state.viewerGeneration, 0) then return
    if not accountIsSignedIn() or not activeViewerPublished() then return
    identity = command.identity
    if identity = invalid or Type(identity) <> "roAssociativeArray" or identity.Count() <> 2 then return
    if identity.title = invalid or identity.meta = invalid then return
    for each key in identity
        if key <> "title" and key <> "meta" then return
    end for

    m.lastPlaybackPresentationSequence = sequence
    if m.route <> "player" then pushRoute("player", -1, m.focusArea)
    m.playbackIdentity = {
        title: safeRuntimeLabel(identity.title, "", 240),
        meta: safeRuntimeLabel(identity.meta, "", 240)
    }
    PorticoSceneSyncNavigationAliases()
    m.focusArea = "player"
    m.railExpanded = false
    m.detailMoreOpen = false
    m.homeCustomizeOpen = false
    m.detailSeasonOpen = false
    m.watchWithFriendsOpen = false
    renderScene()
end sub

sub externalRequestChanged()
    if m.contract = invalid then return
    request = m.top.externalRequest
    if not PorticoSceneValidateExternalRequest(request)
        PorticoScenePublishExternalRequestAcknowledgement(request, false, "invalid-request")
        return
    end if

    sequence = PorticoSceneSafeInteger(request.sequence, 0)
    deliveryId = PorticoSceneSafeDispatchIdentifier(request.deliveryId, 128)
    if sequence <= m.lastExternalRequestSequence
        if sequence = m.lastExternalRequestSequence and deliveryId = m.lastExternalRequestDeliveryId
            PorticoScenePublishExternalRequestAcknowledgement(request, true, "already-consumed")
        else
            PorticoScenePublishExternalRequestAcknowledgement(request, false, "stale-sequence")
        end if
        return
    end if
    m.lastExternalRequestSequence = sequence
    m.lastExternalRequestDeliveryId = deliveryId
    kind = LCase(safeRuntimeLabel(request.kind, "", 32))
    if kind = "route"
        route = PorticoSceneNormalizeExternalRoute(request.route)
        if route = "server-selection"
            selectPrimaryRoute("home", railIndexForRoute("home"))
            openInternalRoute("server-selection")
        else if route = "home" or route = "search" or route = "library" or route = "channels" or route = "saved" or route = "profile" or route = "settings" or Left(route, 8) = "library/"
            routeIndex = railIndexForRoute(route)
            if Left(route, 8) = "library/" and routeIndex < 0
                route = "library"
                routeIndex = railIndexForRoute(route)
            end if
            selectPrimaryRoute(route, routeIndex)
        else
            PorticoScenePublishExternalRequestAcknowledgement(request, false, "unsupported-route")
            return
        end if
    else if kind = "open-detail"
        selectPrimaryRoute("home", railIndexForRoute("home"))
        openDetailFromBrowse(request.targetId)
    else if kind = "play"
        selectPrimaryRoute("home", railIndexForRoute("home"))
        openPlayback("play", request.targetId, "", "")
    else
        PorticoScenePublishExternalRequestAcknowledgement(request, false, "unsupported-kind")
        return
    end if
    renderScene()
    PorticoScenePublishExternalRequestAcknowledgement(request, true, "consumed")
end sub

function PorticoSceneExternalRequestAllowedPayloadKeys() as object
    return {
        sequence: true,
        kind: true,
        contractRevision: true,
        ackRequired: true,
        deliveryId: true,
        intentId: true,
        gateDelivery: true,
        route: true,
        targetId: true,
        mediaType: true,
        origin: true,
        viewerGeneration: true,
        lifecycleGeneration: true,
        serverId: true,
        profileId: true,
        showImportantNotice: true
    }
end function

function PorticoSceneValidateExternalRequest(request as dynamic) as boolean
    if request = invalid or Type(request) <> "roAssociativeArray" then return false

    allowedPayloadKeys = PorticoSceneExternalRequestAllowedPayloadKeys()
    for each key in request
        if PorticoScenePrivateDispatchKey(key) then return false
        if allowedPayloadKeys[key] <> true then return false
    end for

    sequence = PorticoSceneSafeInteger(request.sequence, 0)
    if sequence < 1 then return false
    kind = LCase(safeRuntimeLabel(request.kind, "", 32))
    if kind <> "route" and kind <> "open-detail" and kind <> "play" then return false
    if safeRuntimeLabel(request.contractRevision, "", 16) <> "v1" then return false

    ackType = LCase(Type(request.ackRequired))
    if ackType <> "boolean" and ackType <> "roboolean" then return false
    if request.ackRequired <> true then return false
    if not PorticoSceneExternalRequestAcknowledgementAvailable() then return false

    deliveryId = PorticoSceneSafeDispatchIdentifier(request.deliveryId, 128)
    if deliveryId = "" then return false
    if request.intentId <> invalid
        intentId = PorticoSceneSafeDispatchIdentifier(request.intentId, 128)
        if intentId = "" or intentId <> deliveryId then return false
    end if

    if kind = "route"
        if PorticoSceneNormalizeExternalRoute(request.route) = "" then return false
    else
        if safeRuntimeLabel(request.targetId, "", 256) = "" then return false
    end if

    if request.viewerGeneration <> invalid
        viewerGeneration = PorticoSceneSafeInteger(request.viewerGeneration, 0)
        if viewerGeneration < 1 or viewerGeneration <> PorticoSceneCurrentViewerGeneration() then return false
    end if
    if request.lifecycleGeneration <> invalid
        lifecycleGeneration = PorticoSceneSafeInteger(request.lifecycleGeneration, -1)
        if lifecycleGeneration < 0 or lifecycleGeneration <> PorticoSceneCurrentLifecycleGeneration() then return false
    end if
    if request.serverId <> invalid and PorticoSceneSafeDispatchIdentifier(request.serverId, 128) = "" then return false
    if request.profileId <> invalid and PorticoSceneSafeDispatchIdentifier(request.profileId, 128) = "" then return false
    if request.showImportantNotice <> invalid
        noticeType = LCase(Type(request.showImportantNotice))
        if noticeType <> "boolean" and noticeType <> "roboolean" then return false
    end if
    return true
end function

function PorticoSceneNormalizeExternalRoute(value as dynamic) as string
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

function PorticoSceneExternalRequestAcknowledgementAvailable() as boolean
    return m.top <> invalid and m.top.HasField("externalRequestAcknowledgement")
end function

sub PorticoScenePublishExternalRequestAcknowledgement(request as dynamic, deliveryOk as boolean, code as string)
    if not PorticoSceneExternalRequestAcknowledgementAvailable() then return
    if request = invalid or Type(request) <> "roAssociativeArray" then return
    deliveryId = PorticoSceneSafeDispatchIdentifier(request.deliveryId, 128)
    if deliveryId = "" then return
    m.top.externalRequestAcknowledgement = {
        contractRevision: "v1",
        sequence: PorticoSceneSafeInteger(request.sequence, 0),
        deliveryId: deliveryId,
        deliveryOk: deliveryOk,
        acknowledged: deliveryOk,
        code: safeRuntimeLabel(code, "invalid-request", 32)
    }
end sub

function PorticoScenePrivateDispatchKey(value as dynamic) as boolean
    key = LCase(safeRuntimeLabel(value, "", 96))
    compact = key.Replace("-", "").Replace("_", "").Replace(".", "").Replace(" ", "")
    if Instr(1, compact, "authorization") > 0 then return true
    if Instr(1, compact, "password") > 0 then return true
    if Instr(1, compact, "token") > 0 then return true
    if Instr(1, compact, "grant") > 0 then return true
    if Instr(1, compact, "secret") > 0 then return true
    if Instr(1, compact, "header") > 0 then return true
    if Instr(1, compact, "session") > 0 then return true
    if Instr(1, compact, "apikey") > 0 then return true
    return false
end function

function PorticoSceneSafeDispatchIdentifier(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    valueType = LCase(Type(value))
    if valueType <> "string" and valueType <> "rostring" and valueType <> "integer" and valueType <> "roint" and valueType <> "longinteger" and valueType <> "rolonginteger" then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > maximum then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoSceneCurrentViewerGeneration() as integer
    state = m.top.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" then return 0
    return PorticoSceneSafeInteger(state.viewerGeneration, 0)
end function

function PorticoSceneCurrentLifecycleGeneration() as integer
    generation = PorticoSceneSafeInteger(m.lifecycleGeneration, 0)
    if generation > 0 then return generation
    state = m.top.runtimeState
    if state <> invalid and Type(state) = "roAssociativeArray" then return PorticoSceneSafeInteger(state.lifecycleGeneration, 0)
    return 0
end function

sub build()
    contract = m.top.visualContract
    if contract = invalid then return
    m.contract = contract
    PorticoSceneEnsureBaseNodes()
    m.layout = PorticoSceneApplyGeometry(contract)
    refreshRuntimeLibraries()

    if not PorticoSceneVisualFixtureEnabled() then m.focusArea = "routeActions"
    reconcileRuntimeNavigation("")
    renderScene()
    if m.top.externalRequest <> invalid then externalRequestChanged()
end sub

sub fixtureModeChanged()
    if m.contract = invalid then return
    if m.route = "home"
        if PorticoSceneVisualFixtureEnabled() and m.focusArea = "routeActions"
            m.focusArea = "homeActions"
        else if not PorticoSceneVisualFixtureEnabled() and (m.focusArea = "homeActions" or m.focusArea = "homeRows")
            m.focusArea = "routeActions"
        end if
    end if
    reconcileContentFocus()
    renderScene()
end sub

function PorticoSceneVisualFixtureEnabled() as boolean
    #if visual_fixture
    return m.top.visualFixtureMode = true
    #else
    return false
    #end if
end function

sub runtimeChanged()
    if m.contract = invalid then return
    signedIn = accountIsSignedIn()
    viewerPublished = activeViewerPublished()
    viewerGeneration = 0
    if m.top.runtimeState <> invalid and Type(m.top.runtimeState) = "roAssociativeArray" then viewerGeneration = PorticoSceneSafeInteger(m.top.runtimeState.viewerGeneration, 0)
    viewerChanged = viewerPublished and m.lastPublishedViewerGeneration > 0 and viewerGeneration <> m.lastPublishedViewerGeneration
    navigationViewerChanged = viewerPublished and viewerGeneration <> m.navigationStore.viewerEpoch
    lifecycleChanged = (m.lastViewerPublished and not viewerPublished) or viewerChanged or (m.lastAccountSignedIn and not signedIn)
    if lifecycleChanged then m.lifecycleGeneration = m.lifecycleGeneration + 1
    if (m.lastViewerPublished and not viewerPublished) or viewerChanged or navigationViewerChanged
        PorticoNavigationResetViewer(m.navigationStore, viewerGeneration, "home")
        PorticoFocusMemoryFence(m.focusMemory, viewerGeneration)
        PorticoActivationRelease(m.activationTransactions)
        resetViewerPresentation()
    end if
    if m.lastAccountSignedIn and not signedIn
        m.signedOutGateMode = "landing"
        resetViewerPresentation()
    end if
    state = m.top.runtimeState
    if not signedIn and state <> invalid and Type(state) = "roAssociativeArray"
        authMode = LCase(safeRuntimeLabel(state.authMode, "", 32))
        if Left(authMode, 5) = "local" and state.localAuthHasSession = true then m.signedOutGateMode = "local"
    end if
    m.lastAccountSignedIn = signedIn
    m.lastViewerPublished = viewerPublished
    if viewerPublished then m.lastPublishedViewerGeneration = viewerGeneration
    serverPickerWasWaiting = m.route = "server-selection" and m.serverPickerWaitingForList
    focusedRoute = ""
    if m.focusArea = "rail"
        focusedItem = railItemAt(m.focusedRailIndex)
        if focusedItem <> invalid and focusedItem.route <> invalid then focusedRoute = focusedItem.route
    end if
    refreshRuntimeLibraries()
    reconcileRuntimeNavigation(focusedRoute)
    clampServerSelectionFocus()
    if serverPickerWasWaiting and serverSelectionListReady()
        focusSelectedServer()
        m.serverPickerWaitingForList = false
    else if m.route = "server-selection" and not serverSelectionListReady()
        m.serverPickerWaitingForList = true
    end if
    reconcileContentFocus()
    clampRouteActionFocus()
    renderScene()
end sub

sub resetViewerPresentation()
    ' Route stacks, playback labels, focus coordinates, and overlays belong to
    ' one published viewer. Never carry them through sign-out, server/profile
    ' replacement, or a direct generation change.
    PorticoNavigationResetViewer(m.navigationStore, m.navigationStore.viewerEpoch, "home")
    PorticoSceneSyncNavigationAliases()
    m.routeFocusedAction = 0
    m.railExpanded = false
    m.focusArea = "routeActions"
    homeIndex = railIndexForRoute("home")
    if homeIndex < 0 then homeIndex = 0
    m.selectedRailIndex = homeIndex
    m.focusedRailIndex = homeIndex
    m.focusBeforeRail = "routeActions"
    m.homeFocusedRowId = ""
    m.homeFocusedItemIds = {}
    m.detailMoreOpen = false
    m.homeCustomizeOpen = false
    m.detailSeasonOpen = false
    m.watchWithFriendsOpen = false
    m.feedbackOpen = false
    m.globalNoticeFocused = false
    m.globalNoticePreviousFocus = ""
    m.playbackIdentity = {title: "", meta: ""}
    if m.playerScreen <> invalid
        m.playerScreen.privateContent = invalid
        m.playerScreen.watchGroupState = invalid
        m.playerScreen.watchSyncDirective = invalid
    end if
    resetDetailSecondaryFocus()
end sub

sub renderScene()
    if m.contract = invalid then return
    m.profileGateVisible = false

    showAuthGate = not PorticoSceneVisualFixtureEnabled() and not accountIsSignedIn()
    if showAuthGate
        hideGlobalEngagementSurfaces()
        showLocalAuth = m.signedOutGateMode = "local"
        if showLocalAuth
            m.localAuthScreen = PorticoSceneEnsureOverlaySurface("local-auth")
        else
            m.authGate = PorticoSceneEnsureOverlaySurface("auth-gate")
        end if
        m.homeCustomizeOpen = false
        PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
        m.detailSeasonOpen = false
        PorticoSceneSetVisible(m.detailSeasonOverlay, false)
        m.watchWithFriendsOpen = false
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
        m.detailMoreOpen = false
        PorticoSceneSetVisible(m.detailMoreScreen, false)
        m.content.visible = false
        m.railLayer.visible = false
        PorticoSceneSetVisible(m.serverSelectionScreen, false)
        PorticoSceneSetVisible(m.profileSelectionScreen, false)
        PorticoSceneSetVisible(m.stateScreen, false)
        ' Keep both signed-out surfaces hidden until their model has rendered. Showing
        ' a surface before assigning viewState exposes a partially populated frame on
        ' slower Roku hardware during launch.
        PorticoSceneSetVisible(m.authGate, false)
        PorticoSceneSetVisible(m.localAuthScreen, false)
        PorticoSceneSetVisible(m.playerScreen, false)
        if showLocalAuth
            m.localAuthScreen.viewState = m.top.runtimeState
            m.localAuthScreen.visible = true
            m.top.page = "local-auth"
            m.localAuthScreen.setFocus(true)
        else
            m.authGate.viewState = PorticoSignedOutGateModel(m.top.runtimeState, m.signedOutGateMode)
            m.authGate.visible = true
            m.top.page = "auth-gate"
            m.authGate.setFocus(true)
        end if
        return
    end if

    PorticoSceneSetVisible(m.authGate, false)
    PorticoSceneSetVisible(m.localAuthScreen, false)
    PorticoSceneSetVisible(m.profileSelectionScreen, false)
    viewerActive = PorticoSceneVisualFixtureEnabled() or activeViewerPublished()
    if not viewerActive
        hideGlobalEngagementSurfaces()
        PorticoSceneReleaseInactiveRouteSurfaces("")
        m.homeCustomizeOpen = false
        PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
        m.detailSeasonOpen = false
        PorticoSceneSetVisible(m.detailSeasonOverlay, false)
        m.watchWithFriendsOpen = false
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
        m.detailMoreOpen = false
        PorticoSceneSetVisible(m.detailMoreScreen, false)
        PorticoSceneSetVisible(m.playerScreen, false)
        m.content.visible = false
        m.railLayer.visible = false
        PorticoSceneSetVisible(m.serverSelectionScreen, false)
        PorticoSceneSetVisible(m.homeScreen, false)
        PorticoSceneSetVisible(m.detailScreen, false)
        PorticoSceneSetVisible(m.searchScreen, false)
        PorticoSceneSetVisible(m.personScreen, false)
        PorticoSceneSetVisible(m.libraryScreen, false)
        PorticoSceneSetVisible(m.savedScreen, false)
        PorticoSceneSetVisible(m.channelsScreen, false)
        PorticoSceneSetVisible(m.profileScreen, false)
        PorticoSceneSetVisible(m.settingsScreen, false)
        PorticoSceneSetVisible(m.stateScreen, false)
        profiles = []
        state = m.top.runtimeState
        if state <> invalid and Type(state) = "roAssociativeArray" and state.profileDirectory <> invalid and GetInterface(state.profileDirectory, "ifArray") <> invalid then profiles = state.profileDirectory
        selectedServerId = runtimeValue("selectedServerId", "")
        if m.route = "server-selection" or selectedServerId = ""
            m.serverSelectionScreen = PorticoSceneEnsureOverlaySurface("server-selection")
            currentDestination = PorticoNavigationCurrent(m.navigationStore)
            if currentDestination = invalid or currentDestination.route <> "server-selection" then PorticoNavigationTransition(m.navigationStore, "server-selection", invalid, "replace", m.navigationStore.viewerEpoch, m.navigationStore.routeEpoch)
            PorticoSceneSyncNavigationAliases()
            if m.focusArea <> "serverList" and m.focusArea <> "serverActions" and m.focusArea <> "serverClose"
                if serverSelectionListReady() and runtimeServers().Count() > 0
                    m.focusArea = "serverList"
                else
                    m.focusArea = "serverActions"
                end if
            end if
            m.serverSelectionScreen.viewState = {
                model: serverSelectionModel(),
                focusArea: m.focusArea,
                focusedIndex: m.serverFocusedIndex,
                offset: m.serverListOffset,
                focusedAction: m.routeFocusedAction
            }
            m.serverSelectionScreen.visible = true
            m.top.page = "server-selection"
            m.serverSelectionScreen.setFocus(true)
        else if profiles.Count() > 0
            m.profileSelectionScreen = PorticoSceneEnsureOverlaySurface("profile-selection")
            generation = 0
            status = "loading"
            errorMessageId = ""
            if state <> invalid and Type(state) = "roAssociativeArray"
                generation = PorticoSceneSafeInteger(state.viewerGeneration, 0)
                status = safeRuntimeLabel(state.profileDirectoryStatus, "loading", 40)
                errorMessageId = safeRuntimeLabel(state.viewerTransitionReason, "", 120)
            end if
            m.profileSelectionScreen.viewState = {profiles: profiles, viewerGeneration: generation, status: status, errorMessageId: errorMessageId}
            m.profileSelectionScreen.visible = true
            m.top.page = "profile-selection"
            m.profileSelectionScreen.setFocus(true)
        else
            m.profileGateVisible = true
            PorticoSceneReleaseClosedOverlays()
            PorticoSceneEnsureBaseNodes()
            m.content.visible = true
            m.content.translation = [PorticoSceneContentOrigin(), 0]
            PorticoSceneSetVisible(m.homeScreen, false)
            PorticoSceneSetVisible(m.detailScreen, false)
            PorticoSceneSetVisible(m.searchScreen, false)
            PorticoSceneSetVisible(m.personScreen, false)
            PorticoSceneSetVisible(m.libraryScreen, false)
            PorticoSceneSetVisible(m.savedScreen, false)
            PorticoSceneSetVisible(m.channelsScreen, false)
            PorticoSceneSetVisible(m.profileScreen, false)
            PorticoSceneSetVisible(m.settingsScreen, false)
            PorticoSceneSetVisible(m.serverSelectionScreen, false)
            m.stateScreen.visible = true
            m.focusArea = "routeActions"
            m.stateScreen.viewState = {model: profileGateStateModel(), focusedAction: m.routeFocusedAction}
            m.top.page = "profile-state"
            m.top.setFocus(true)
        end if
        return
    end if

    ' A profile switch is a transactional overlay over the currently published
    ' viewer. Keep the cached shell and player state intact behind the chooser;
    ' only a successfully proven replacement assertion may fence that viewer.
    if runtimeValue("profileSelectionOverlay", false) = true
        m.profileSelectionScreen = PorticoSceneEnsureOverlaySurface("profile-selection")
        state = m.top.runtimeState
        profiles = []
        generation = 0
        status = "loading"
        errorMessageId = ""
        if state <> invalid and Type(state) = "roAssociativeArray"
            if state.profileDirectory <> invalid and GetInterface(state.profileDirectory, "ifArray") <> invalid then profiles = state.profileDirectory
            generation = PorticoSceneSafeInteger(state.viewerGeneration, 0)
            status = safeRuntimeLabel(state.profileDirectoryStatus, "loading", 40)
            errorMessageId = safeRuntimeLabel(state.viewerTransitionReason, "", 120)
        end if
        m.profileSelectionScreen.viewState = {profiles: profiles, viewerGeneration: generation, status: status, errorMessageId: errorMessageId}
        m.profileSelectionScreen.visible = true
        m.railLayer.visible = false
        ' The playback task and position remain live; hide only its visual node so
        ' the later SceneGraph player layer cannot cover the profile chooser.
        PorticoSceneSetVisible(m.playerScreen, false)
        m.top.page = "profile-selection"
        m.profileSelectionScreen.setFocus(true)
        return
    end if
    showPlayer = m.route = "player"
    if showPlayer
        m.playerScreen = PorticoSceneEnsureOverlaySurface("player")
    end if
    PorticoSceneEnsureRouteSurface(m.route)
    PorticoSceneReleaseInactiveRouteSurfaces(m.route)
    if m.playerScreen <> invalid then m.playerScreen.watchGroupState = activeWatchWithFriendsViewState()
    PorticoSceneSetVisible(m.playerScreen, showPlayer)
    if showPlayer
        m.detailSeasonOpen = false
        PorticoSceneSetVisible(m.detailSeasonOverlay, false)
        m.detailMoreOpen = false
        PorticoSceneSetVisible(m.detailMoreScreen, false)
        m.content.visible = false
        m.railLayer.visible = false
        PorticoSceneSetVisible(m.serverSelectionScreen, false)
        m.playerScreen.viewState = activePlaybackModel()
        m.top.page = "player"
        m.playerScreen.setFocus(true)
        renderGlobalImportantNotice()
        PorticoSceneReleaseClosedOverlays()
        return
    end if

    m.content.visible = true
    settingsModalOpen = false
    if m.settingsScreen <> invalid then settingsModalOpen = m.settingsScreen.modalOpen = true
    m.railLayer.visible = not m.detailMoreOpen and not m.homeCustomizeOpen and not m.detailSeasonOpen and not m.watchWithFriendsOpen and not m.feedbackOpen and not m.globalNoticeFocused and not settingsModalOpen
    m.top.setFocus(true)

    contentShift = 0
    if m.railExpanded then contentShift = m.contract.rail.expandedContentTranslation
    m.content.translation = [PorticoSceneContentOrigin() + contentShift, 0]

    homeModel = activeHomeModel()
    detailModel = activeDetailModel()
    showVisualHome = m.route = "home" and (homeModel <> invalid or homeShouldReserveContent())
    showVisualDetail = m.route = "detail" and detailModel <> invalid
    showSearch = m.route = "search" and not PorticoSceneVisualFixtureEnabled()
    showPerson = m.route = "person" and not PorticoSceneVisualFixtureEnabled()
    showLibrary = (m.route = "library" or Left(m.route, 8) = "library/") and not PorticoSceneVisualFixtureEnabled()
    showSaved = m.route = "saved" and not PorticoSceneVisualFixtureEnabled()
    showChannels = m.route = "channels" and not PorticoSceneVisualFixtureEnabled()
    showProfile = m.route = "profile" and not PorticoSceneVisualFixtureEnabled()
    showSettings = m.route = "settings" and not PorticoSceneVisualFixtureEnabled()
    showServerSelection = m.route = "server-selection" and not PorticoSceneVisualFixtureEnabled()
    if showServerSelection then m.serverSelectionScreen = PorticoSceneEnsureOverlaySurface("server-selection")
    showState = not showVisualHome and not showVisualDetail and not showSearch and not showPerson and not showLibrary and not showSaved and not showChannels and not showProfile and not showSettings and not showServerSelection
    if showServerSelection then showState = true
    PorticoSceneSetVisible(m.homeScreen, showVisualHome)
    PorticoSceneSetVisible(m.detailScreen, showVisualDetail)
    PorticoSceneSetVisible(m.searchScreen, showSearch)
    PorticoSceneSetVisible(m.personScreen, showPerson)
    PorticoSceneSetVisible(m.libraryScreen, showLibrary)
    PorticoSceneSetVisible(m.savedScreen, showSaved)
    PorticoSceneSetVisible(m.channelsScreen, showChannels)
    PorticoSceneSetVisible(m.profileScreen, showProfile)
    PorticoSceneSetVisible(m.settingsScreen, showSettings)
    PorticoSceneSetVisible(m.serverSelectionScreen, showServerSelection)
    PorticoSceneSetVisible(m.stateScreen, showState)

    if showVisualHome
        if homeModel = invalid then homeModel = reservedHomeModel()
        m.homeScreen.model = homeModel
        m.homeScreen.focusArea = m.focusArea
        m.homeScreen.focusedAction = m.homeFocusedAction
        m.homeScreen.focusedRow = m.homeFocusedRow
        m.homeScreen.focusedIndices = copySceneIntegerArray(m.homeFocusedIndices)
        m.homeScreen.heroIndex = m.homeHeroIndex
    else if showVisualDetail
        m.detailScreen.model = detailModel
        m.detailScreen.focusArea = m.focusArea
        m.detailScreen.focusedAction = m.detailFocusedAction
        m.detailScreen.focusedEpisode = m.focusedEpisode
        m.detailScreen.focusedPerson = m.detailFocusedPerson
        m.detailScreen.focusedPersonResult = m.detailFocusedPersonResult
        m.detailScreen.focusedRelationshipRow = m.detailFocusedRelationshipRow
        m.detailScreen.focusedRelationshipItem = m.detailFocusedRelationshipItem
        m.detailScreen.factsOpen = m.detailFactsOpen
    else if showSearch
        m.searchScreen.viewState = activeSearchViewState()
    else if showPerson
        m.personScreen.viewState = activePersonViewState()
    else if showLibrary
        m.libraryScreen.viewState = activeLibraryViewState()
    else if showSaved
        m.savedScreen.viewState = activeSavedViewState()
    else if showChannels
        m.channelsScreen.viewState = activeChannelsViewState()
    else if showProfile
        m.profileScreen.viewState = {runtime: m.top.runtimeState, focused: m.focusArea = "profile"}
    else if showSettings
        m.settingsScreen.viewState = {runtime: m.top.runtimeState, focused: m.focusArea = "settings"}
    else if showServerSelection
        m.serverSelectionScreen.viewState = {
            model: serverSelectionModel(),
            focusArea: m.focusArea,
            focusedIndex: m.serverFocusedIndex,
            offset: m.serverListOffset,
            focusedAction: m.routeFocusedAction
        }
    else
        m.stateScreen.viewState = {
            model: routeStateModel(m.route),
            focusedAction: m.routeFocusedAction
        }
    end if

    if m.route = "home" and activeHomeModel() <> invalid then rememberHomeFocusIdentity(activeHomeModel())

    focusedIndex = -1
    if m.focusArea = "rail" then focusedIndex = m.focusedRailIndex
    m.rail.viewState = {
        model: railModel(),
        expanded: m.railExpanded,
        focusedIndex: focusedIndex,
        selectedIndex: m.selectedRailIndex
    }
    m.top.page = m.route
    if m.feedbackOpen
        m.globalFeedbackOverlay = PorticoSceneEnsureOverlaySurface("feedback")
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
        PorticoSceneSetVisible(m.detailSeasonOverlay, false)
        PorticoSceneSetVisible(m.detailMoreScreen, false)
        PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
        engagement = activeEngagementViewState()
        feedbackCapabilities = invalid
        feedbackStatus = "idle"
        feedbackReceipt = invalid
        if engagement <> invalid
            feedbackCapabilities = engagement.feedbackCapabilities
            feedbackStatus = safeRuntimeLabel(engagement.feedbackStatus, "idle", 24)
            feedbackReceipt = engagement.feedbackReceipt
        end if
        m.globalFeedbackOverlay.viewState = {
            open: true,
            feedbackCapabilities: feedbackCapabilities,
            feedbackStatus: feedbackStatus,
            feedbackReceipt: feedbackReceipt,
            initialKind: m.feedbackInitialKind,
            context: m.feedbackContext
        }
        m.globalFeedbackOverlay.visible = true
        m.globalFeedbackOverlay.setFocus(true)
    else if m.watchWithFriendsOpen
        m.watchWithFriendsOverlay = PorticoSceneEnsureOverlaySurface("watch-with-friends")
        watchState = activeWatchWithFriendsViewState()
        if watchState <> invalid and watchState.group <> invalid
            m.watchWithFriendsOpen = false
            PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
            focusActiveRoute()
        else
            PorticoSceneSetVisible(m.detailMoreScreen, false)
            PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
            m.watchWithFriendsOverlay.context = m.watchWithFriendsContext
            m.watchWithFriendsOverlay.viewState = watchState
            m.watchWithFriendsOverlay.visible = true
            m.watchWithFriendsOverlay.setFocus(true)
        end if
    else if m.detailSeasonOpen
        m.detailSeasonOverlay = PorticoSceneEnsureOverlaySurface("detail-season")
        PorticoSceneSetVisible(m.globalFeedbackOverlay, false)
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
        PorticoSceneSetVisible(m.detailMoreScreen, false)
        PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
        if detailModel = invalid or detailModel.seasons = invalid or GetInterface(detailModel.seasons, "ifArray") = invalid or detailModel.seasons.Count() = 0
            m.detailSeasonOpen = false
            PorticoSceneSetVisible(m.detailSeasonOverlay, false)
            focusActiveRoute()
        else
            m.detailSeasonOverlay.viewState = {seasons: detailModel.seasons, selectedSeasonId: detailModel.selectedSeasonId}
            m.detailSeasonOverlay.visible = true
            m.detailSeasonOverlay.setFocus(true)
        end if
    else if m.detailMoreOpen
        m.detailMoreScreen = PorticoSceneEnsureOverlaySurface("detail-more")
        PorticoSceneSetVisible(m.globalFeedbackOverlay, false)
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
        PorticoSceneSetVisible(m.detailSeasonOverlay, false)
        m.detailMoreScreen.visible = true
        m.detailMoreScreen.viewState = {open: true, model: detailModel}
        m.detailMoreScreen.setFocus(true)
    else
        PorticoSceneSetVisible(m.globalFeedbackOverlay, false)
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
        PorticoSceneSetVisible(m.detailSeasonOverlay, false)
        PorticoSceneSetVisible(m.detailMoreScreen, false)
        if m.homeCustomizeOpen
            m.homeCustomizeOverlay = PorticoSceneEnsureOverlaySurface("home-customize")
            customization = invalid
            if homeModel <> invalid then customization = homeModel.homeCustomization
            if customization = invalid
                m.homeCustomizeOpen = false
                PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
                focusActiveRoute()
            else
                expectedRevision = -1
                revisions = state.preferenceRevisions
                if revisions <> invalid and Type(revisions) = "roAssociativeArray" then expectedRevision = PorticoSceneSafeInteger(revisions.profileServer, -1)
                m.homeCustomizeOverlay.viewState = {rows: customization.availableRows, rowOrder: customization.rowOrder, hiddenRowIds: customization.hiddenRowIds, expectedRevision: expectedRevision}
                m.homeCustomizeOverlay.visible = true
                m.homeCustomizeOverlay.setFocus(true)
            end if
        else
            PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
            focusActiveRoute()
        end if
    end if
    renderGlobalImportantNotice()
    PorticoSceneReleaseClosedOverlays()
end sub

function activeEngagementViewState() as dynamic
    state = m.top.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" then return invalid
    value = state.engagementViewState
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    return value
end function

sub hideGlobalEngagementSurfaces()
    m.feedbackOpen = false
    m.feedbackInitialKind = "general"
    m.feedbackContext = {}
    PorticoSceneSetVisible(m.globalFeedbackOverlay, false)
    if m.globalFeedbackOverlay <> invalid then m.globalFeedbackOverlay.viewState = invalid
    m.globalNoticeFocused = false
    if m.globalImportantNotice <> invalid
        m.globalImportantNotice.focused = false
        m.globalImportantNotice.visible = false
        m.globalImportantNotice.viewState = invalid
    end if
    m.globalNoticePreviousFocus = ""
    m.lastFocusedNoticeKey = ""
    m.pendingDismissNoticeKey = ""
end sub

sub renderGlobalImportantNotice()
    if not accountIsSignedIn() or not (PorticoSceneVisualFixtureEnabled() or activeViewerPublished())
        m.globalNoticeFocused = false
        PorticoSceneSetVisible(m.globalImportantNotice, false)
        if m.globalImportantNotice <> invalid
            m.globalImportantNotice.focused = false
            m.globalImportantNotice.viewState = invalid
        end if
        m.globalNoticePreviousFocus = ""
        return
    end if
    engagement = activeEngagementViewState()
    notice = invalid
    revision = 0
    if engagement <> invalid
        revision = PorticoSceneSafeInteger(engagement.notificationRevision, 0)
        if engagement.importantNotice <> invalid and Type(engagement.importantNotice) = "roAssociativeArray"
            notice = ParseJson(FormatJson(engagement.importantNotice))
            notice.revision = revision
        end if
    end if
    if notice = invalid
        runtime = m.top.runtimeState
        if runtime <> invalid and Type(runtime) = "roAssociativeArray" and runtime.savedMutationError <> invalid and Type(runtime.savedMutationError) = "roAssociativeArray"
            notice = ParseJson(FormatJson(runtime.savedMutationError))
            notice.dismissKind = "dismiss-saved-mutation-error"
            revision = PorticoSceneSafeInteger(notice.revision, 0)
        end if
    end if
    if notice = invalid
        m.globalNoticeFocused = false
        PorticoSceneSetVisible(m.globalImportantNotice, false)
        if m.globalImportantNotice <> invalid
            m.globalImportantNotice.focused = false
            m.globalImportantNotice.viewState = invalid
        end if
        m.pendingDismissNoticeKey = ""
        m.globalNoticePreviousFocus = ""
        return
    end if
    noticeId = safeRuntimeLabel(notice.id, "", 128)
    noticeKey = noticeId + ":" + revision.ToStr()
    if noticeId = "" or noticeKey = m.pendingDismissNoticeKey
        m.globalNoticeFocused = false
        PorticoSceneSetVisible(m.globalImportantNotice, false)
        if m.globalImportantNotice <> invalid
            m.globalImportantNotice.focused = false
            m.globalImportantNotice.viewState = invalid
        end if
        m.globalNoticePreviousFocus = ""
        return
    end if
    m.globalImportantNotice = PorticoSceneEnsureOverlaySurface("important-notice")
    m.globalImportantNotice.viewState = notice
    m.globalImportantNotice.visible = true
    if noticeKey <> m.lastFocusedNoticeKey
        m.lastFocusedNoticeKey = noticeKey
    end if
    m.globalImportantNotice.focused = m.globalNoticeFocused
    if m.globalNoticeFocused then m.globalImportantNotice.setFocus(true)
end sub

sub focusGlobalImportantNotice()
    if not PorticoSceneIsVisible(m.globalImportantNotice) then return
    m.globalNoticePreviousFocus = m.focusArea
    m.globalNoticeFocused = true
    m.globalImportantNotice.focused = true
    m.globalImportantNotice.setFocus(true)
end sub

sub restoreFocusAfterGlobalNotice()
    m.globalNoticeFocused = false
    m.globalImportantNotice.focused = false
    if m.globalNoticePreviousFocus <> "" then m.focusArea = m.globalNoticePreviousFocus
    m.globalNoticePreviousFocus = ""
    focusActiveRoute()
end sub

function activeWatchWithFriendsViewState() as dynamic
    state = m.top.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" then return invalid
    value = state.watchWithFriendsViewState
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    return value
end function

function activeViewerPublished() as boolean
    state = m.top.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" then return false
    return LCase(safeRuntimeLabel(state.viewerStatus, "unavailable", 40)) = "active" and state.viewerAcceptingWrites = true
end function

function profileGateStateModel() as object
    state = m.top.runtimeState
    status = "loading"
    messageId = "auth.profile-selection-required"
    if state <> invalid and Type(state) = "roAssociativeArray"
        status = LCase(safeRuntimeLabel(state.profileDirectoryStatus, "loading", 40))
        requested = safeRuntimeLabel(state.viewerTransitionReason, "", 120)
        if requested <> "" then messageId = requested
    end if
    problem = status = "error" or status = "profile-error" or status = "unavailable"
    if (status = "error" or status = "profile-error") and requested = "" then messageId = "auth.profile-selection-failed"
    copy = PorticoProductLanguageMessage(m.productLanguage, messageId, "auth.profile-selection-failed", {})
    retry = PorticoProductLanguageMessage(m.productLanguage, "action.retry", "action.retry", {})
    back = PorticoProductLanguageMessage(m.productLanguage, "action.back", "action.back", {})
    retryLabel = retry.text
    backLabel = back.text
    if retryLabel = "" then retryLabel = "Try Again"
    if backLabel = "" then backLabel = "Back"
    actions = [
        {id: "retry-profile-directory", label: retryLabel, iconId: "action.retry", width: 190},
        {id: "open-server-selection", label: backLabel, iconId: "navigation.back", width: 190}
    ]
    label = "LOADING PROFILES"
    tone = "account"
    if problem
        label = "PROFILE UNAVAILABLE"
        tone = "danger"
    end if
    return {status: label, title: copy.title, body: copy.body, detail: "", statusTone: tone, actions: actions}
end function

function PorticoSceneSafeInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    valueType = LCase(Type(value))
    if valueType = "integer" or valueType = "roint" or valueType = "longinteger" or valueType = "rolonginteger" then return Int(value)
    return fallback
end function

function PorticoSceneDisplayMode() as string
    deviceInfo = CreateObject("roDeviceInfo")
    reported = ""
    if deviceInfo <> invalid then reported = LCase(PorticoHttpScalarString(deviceInfo.GetDisplayMode(), ""))
    if Instr(1, reported, "720") > 0 or reported = "hd" then return "hd"
    return "fhd"
end function

function PorticoSceneApplyGeometry(contract as dynamic) as object
    fallback = {
        mode: "fhd",
        displayWidth: 1920,
        displayHeight: 1080,
        designWidth: 1920,
        designHeight: 1080,
        scale: 1.0,
        safeZoneDesign: {left: 72, top: 54, right: 72, bottom: 54},
        safeZonePixels: {left: 72, top: 54, right: 72, bottom: 54}
    }
    if contract = invalid or Type(contract) <> "roAssociativeArray" or contract.layout = invalid or Type(contract.layout) <> "roAssociativeArray" then return fallback
    layout = contract.layout
    design = layout.designCanvas
    modes = layout.displayModes
    if design = invalid or Type(design) <> "roAssociativeArray" or modes = invalid or Type(modes) <> "roAssociativeArray" then return fallback
    designWidth = PorticoSceneSafeInteger(design.width, 1920)
    designHeight = PorticoSceneSafeInteger(design.height, 1080)
    modeName = PorticoSceneDisplayMode()
    selected = modes[modeName]
    if selected = invalid or Type(selected) <> "roAssociativeArray" then
        modeName = "fhd"
        selected = modes[modeName]
    end if
    if selected = invalid or Type(selected) <> "roAssociativeArray" then return fallback
    displayWidth = PorticoSceneSafeInteger(selected.width, designWidth)
    displayHeight = PorticoSceneSafeInteger(selected.height, designHeight)
    scale = displayWidth / designWidth
    heightScale = displayHeight / designHeight
    if heightScale < scale then scale = heightScale
    if scale <= 0 then return fallback
    safeSource = selected.safeZone
    if safeSource = invalid or Type(safeSource) <> "roAssociativeArray" then safeSource = {left: 0, top: 0, right: 0, bottom: 0}
    safeDesign = {
        left: PorticoSceneSafeInteger(safeSource.left, 0),
        top: PorticoSceneSafeInteger(safeSource.top, 0),
        right: PorticoSceneSafeInteger(safeSource.right, 0),
        bottom: PorticoSceneSafeInteger(safeSource.bottom, 0)
    }
    safePixels = {
        left: Int(safeDesign.left * scale),
        top: Int(safeDesign.top * scale),
        right: Int(safeDesign.right * scale),
        bottom: Int(safeDesign.bottom * scale)
    }
    if m.designRoot <> invalid
        m.designRoot.scale = [scale, scale]
        m.designRoot.translation = [Int((displayWidth - (designWidth * scale)) / 2), Int((displayHeight - (designHeight * scale)) / 2)]
    end if
    if m.projector <> invalid
        m.projector.width = designWidth
        m.projector.height = designHeight
    end if
    return {
        mode: modeName,
        displayWidth: displayWidth,
        displayHeight: displayHeight,
        designWidth: designWidth,
        designHeight: designHeight,
        scale: scale,
        safeZoneDesign: safeDesign,
        safeZonePixels: safePixels
    }
end function

function PorticoSceneContentOrigin() as integer
    origin = PorticoSceneSafeInteger(m.contract.rail.contentX, 136)
    if m.layout <> invalid and m.layout.safeZoneDesign <> invalid and m.layout.safeZoneDesign.left > origin then origin = m.layout.safeZoneDesign.left
    return origin
end function

function activeSearchViewState() as object
    state = m.top.runtimeState
    if state <> invalid and Type(state) = "roAssociativeArray" and state.searchViewState <> invalid and Type(state.searchViewState) = "roAssociativeArray" then return state.searchViewState
    return {status: "idle", query: "", queryRevision: 0, groups: []}
end function

function activePersonViewState() as object
    state = m.top.runtimeState
    if state <> invalid and Type(state) = "roAssociativeArray" and state.personViewState <> invalid and Type(state.personViewState) = "roAssociativeArray" then return state.personViewState
    return {status: "loading", personId: "", name: "", roles: [], image: "", items: [], hasMore: false, messageId: "media.detail-loading"}
end function

function activeLibraryViewState() as object
    state = m.top.runtimeState
    if state <> invalid and Type(state) = "roAssociativeArray" and state.libraryViewState <> invalid and Type(state.libraryViewState) = "roAssociativeArray" then return state.libraryViewState
    return {
        status: "loading",
        libraryName: routeTitle(m.route),
        serverName: runtimeValue("selectedServerName", "Portico Server"),
        presentation: "grid",
        tabs: [],
        actions: [],
        items: [],
        hasMore: false
    }
end function

function activeSavedViewState() as object
    state = m.top.runtimeState
    if state <> invalid and Type(state) = "roAssociativeArray" and state.savedViewState <> invalid and Type(state.savedViewState) = "roAssociativeArray"
        viewState = ParseJson(FormatJson(state.savedViewState))
        if state.savedMutationError <> invalid then viewState.mutationError = state.savedMutationError
        return viewState
    end if
    return {
        status: "loading",
        libraryName: "Saved",
        serverName: runtimeValue("selectedServerName", "Portico Server"),
        presentation: "grid",
        tabs: [],
        actions: [],
        items: [],
        hasMore: false
    }
end function

function activePlaybackModel() as object
    state = m.top.runtimeState
    if state <> invalid and Type(state) = "roAssociativeArray" and state.playbackViewState <> invalid and Type(state.playbackViewState) = "roAssociativeArray"
        model = state.playbackViewState
        if model.identity = invalid then model.identity = m.playbackIdentity
        return model
    end if
    return {
        playbackStatus: "preparing",
        playbackErrorCode: "",
        playbackGeneration: 0,
        sourceGeneration: 0,
        identity: m.playbackIdentity
    }
end function

function activeChannelsViewState() as object
    state = m.top.runtimeState
    if state <> invalid and Type(state) = "roAssociativeArray" and state.channelsViewState <> invalid and Type(state.channelsViewState) = "roAssociativeArray" then return state.channelsViewState
    return {
        status: "idle",
        serverName: runtimeValue("selectedServerName", "Portico Server"),
        sourceName: "",
        selectedTab: "guide",
        tabs: [
            {id: "guide", label: "Guide", selected: true},
            {id: "channels", label: "Channels", selected: false},
            {id: "dvr", label: "DVR", selected: false}
        ]
    }
end function

sub focusActiveRoute()
    if m.railExpanded
        m.top.setFocus(true)
    else if m.route = "player"
        m.playerScreen = PorticoSceneEnsureOverlaySurface("player")
        if m.playerScreen <> invalid then m.playerScreen.setFocus(true)
    else if m.route = "search"
        m.searchScreen = PorticoSceneEnsureRouteSurface("search")
        if m.searchScreen <> invalid then m.searchScreen.setFocus(true)
    else if m.route = "person"
        m.personScreen = PorticoSceneEnsureRouteSurface("person")
        if m.personScreen <> invalid then m.personScreen.setFocus(true)
    else if m.route = "library" or Left(m.route, 8) = "library/"
        m.libraryScreen = PorticoSceneEnsureRouteSurface("library")
        if m.libraryScreen <> invalid then m.libraryScreen.setFocus(true)
    else if m.route = "saved"
        m.savedScreen = PorticoSceneEnsureRouteSurface("saved")
        if m.savedScreen <> invalid then m.savedScreen.setFocus(true)
    else if m.route = "channels"
        m.channelsScreen = PorticoSceneEnsureRouteSurface("channels")
        if m.channelsScreen <> invalid then m.channelsScreen.setFocus(true)
    else if m.route = "profile"
        m.profileScreen = PorticoSceneEnsureRouteSurface("profile")
        if m.profileScreen <> invalid then m.profileScreen.setFocus(true)
    else if m.route = "settings"
        m.settingsScreen = PorticoSceneEnsureRouteSurface("settings")
        if m.settingsScreen <> invalid then m.settingsScreen.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

sub authGateActivationChanged()
    action = m.authGate.activation
    if action = invalid or Type(action) <> "roAssociativeArray" or action.kind = invalid then return
    kind = action.kind.ToStr()
    if kind = "start-account-setup"
        m.signedOutGateMode = "account"
        emitActivation("start-account-setup", "auth-gate")
    else if kind = "sign-in-account"
        m.signedOutGateMode = "account"
        emitForwardedActivation(action)
    else if kind = "start-local-auth"
        m.signedOutGateMode = "local"
        emitActivation("start-local-auth", "auth-gate")
    else if kind = "back-auth-landing"
        m.signedOutGateMode = "landing"
        emitActivation("pause-account-setup", "auth-gate")
    end if
    renderScene()
end sub

sub profileSelectionActivationChanged()
    action = m.profileSelectionScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    emitForwardedActivation(action)
    if kind = "cancel-profile-selection" and runtimeValue("profileSelectionOverlay", false) <> true then replaceWithServerSelection()
    renderScene()
end sub

sub localAuthActivationChanged()
    action = m.localAuthScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "local-back"
        m.signedOutGateMode = "landing"
    end if
    emitForwardedActivation(action)
    renderScene()
end sub

sub searchActivationChanged()
    action = m.searchScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "open-detail"
        openDetailFromBrowse(action.targetId)
    else if kind = "play-live"
        openPlayback("play-live", action.targetId, action.title, action.meta)
    else if kind = "select-person"
        emitForwardedActivation(action)
        pushRoute("person", -1, "search")
    else
        emitForwardedActivation(action)
    end if
    renderScene()
end sub

sub personActivationChanged()
    action = m.personScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "open-detail"
        openDetailFromBrowse(action.targetId)
    else
        emitForwardedActivation(action)
    end if
    renderScene()
end sub

sub libraryActivationChanged()
    action = m.libraryScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "open-detail"
        openDetailFromBrowse(action.targetId)
    else if kind = "open-server-selection"
        emitForwardedActivation(action)
        openInternalRoute("server-selection")
    else
        emitForwardedActivation(action)
    end if
    renderScene()
end sub

sub savedActivationChanged()
    action = m.savedScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "open-detail"
        openDetailFromBrowse(action.targetId)
    else if kind = "open-server-selection"
        emitForwardedActivation(action)
        openInternalRoute("server-selection")
    else
        emitForwardedActivation(action)
    end if
    renderScene()
end sub

sub detailMoreActivationChanged()
    action = m.detailMoreScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    emitForwardedActivation(action)
    if kind = "close-detail-more"
        m.detailMoreOpen = false
    end if
    renderScene()
end sub

sub homeCustomizeActivationChanged()
    action = m.homeCustomizeOverlay.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "save-home-customization" then emitForwardedActivation(action)
    m.homeCustomizeOpen = false
    PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
    focusActiveRoute()
    renderScene()
end sub

sub watchWithFriendsActionChanged()
    action = m.watchWithFriendsOverlay.action
    if not validChildActivation(action) then return
    PorticoScenePublishActivation({
        kind: "watch-with-friends-overlay-action",
        overlayAction: action
    })
    if LCase(action.kind.ToStr()) = "close"
        m.watchWithFriendsOpen = false
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
        focusActiveRoute()
    end if
    renderScene()
end sub

sub detailSeasonActivationChanged()
    action = m.detailSeasonOverlay.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "select-detail-season"
        model = activeDetailModel()
        selectedId = ""
        status = ""
        if model <> invalid
            selectedId = safeRuntimeLabel(model.selectedSeasonId, "", 128)
            status = LCase(safeRuntimeLabel(model.episodesStatus, "", 24))
        end if
        if safeRuntimeLabel(action.targetId, "", 128) = selectedId and (status = "error" or status = "offline" or status = "partial")
            emitActivation("retry-detail-episodes", selectedId)
        else
            emitForwardedActivation(action)
        end if
        m.focusedEpisode = 0
    end if
    m.detailSeasonOpen = false
    PorticoSceneSetVisible(m.detailSeasonOverlay, false)
    focusActiveRoute()
    renderScene()
end sub

sub playerEventChanged()
    action = m.playerScreen.playerEvent
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "watch-load"
        forwarded = {}
        for each key in action
            forwarded[key] = action[key]
        end for
        forwarded.title = m.watchWithFriendsContext.mediaTitle
        forwarded.meta = ""
        emitForwardedActivation(forwarded)
        if m.route <> "player" then pushRoute("player", -1, m.focusArea)
        titleValue = m.watchWithFriendsContext.mediaTitle
        m.playbackIdentity = {title: titleValue, meta: ""}
        PorticoSceneSyncNavigationAliases()
        m.focusArea = "player"
        m.railExpanded = false
        m.watchWithFriendsOpen = false
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
    else if kind <> "exit-browsing"
        emitForwardedActivation(action)
    end if
    if (kind = "stop" or kind = "exit-browsing") and action.exitRequested = true
        if not navigateBack()
            selectPrimaryRoute("home", railIndexForRoute("home"))
        end if
    end if
    renderScene()
end sub

sub channelsActivationChanged()
    action = m.channelsScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "play-live" or kind = "play-dvr" or kind = "play-library-channel"
        openPlayback(kind, action.targetId, action.title, action.meta)
    else
        emitForwardedActivation(action)
    end if
    renderScene()
end sub

sub profileActivationChanged()
    action = m.profileScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "open-settings"
        emitForwardedActivation(action)
        if historyReturnsTo("settings")
            navigateBack()
        else
            pushRoute("settings", railIndexForRoute("settings"), "profile")
        end if
    else if kind = "open-server-selection"
        emitForwardedActivation(action)
        openInternalRoute("server-selection")
    else if kind = "open-connection"
        emitForwardedActivation(action)
        openInternalRoute("connection")
    else if kind = "sign-out-account"
        emitSignOutActivation("profile")
    else
        emitForwardedActivation(action)
    end if
    renderScene()
end sub

sub settingsActivationChanged()
    action = m.settingsScreen.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "open-profile"
        emitForwardedActivation(action)
        if historyReturnsTo("profile")
            navigateBack()
        else
            pushRoute("profile", railIndexForRoute("profile"), "settings")
        end if
    else if kind = "open-server-selection"
        emitForwardedActivation(action)
        openInternalRoute("server-selection")
    else if kind = "open-connection"
        emitForwardedActivation(action)
        openInternalRoute("connection")
    else if kind = "sign-out-account"
        emitSignOutActivation("settings")
    else
        emitForwardedActivation(action)
    end if
    renderScene()
end sub

sub settingsModalChanged()
    renderScene()
end sub

sub globalFeedbackActivationChanged()
    action = m.globalFeedbackOverlay.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "close-feedback"
        m.feedbackOpen = false
        PorticoSceneSetVisible(m.globalFeedbackOverlay, false)
        focusActiveRoute()
    else if kind = "submit-feedback"
        emitForwardedActivation(action)
    end if
    renderScene()
end sub

sub globalImportantNoticeActivationChanged()
    action = m.globalImportantNotice.activation
    if not validChildActivation(action) then return
    kind = LCase(action.kind.ToStr())
    if kind = "dismiss-saved-mutation-error"
        emitForwardedActivation(action)
        restoreFocusAfterGlobalNotice()
        renderScene()
        return
    end if
    if kind <> "dismiss-notification" then return
    noticeId = safeRuntimeLabel(action.notificationId, "", 128)
    revision = PorticoSceneSafeInteger(action.expectedRevision, 0)
    if noticeId = "" then return
    m.pendingDismissNoticeKey = noticeId + ":" + revision.ToStr()
    emitForwardedActivation(action)
    restoreFocusAfterGlobalNotice()
    renderScene()
end sub

sub emitSignOutActivation(page as string)
    kind = "sign-out-account"
    state = m.top.runtimeState
    if state <> invalid and Type(state) = "roAssociativeArray" and LCase(safeRuntimeLabel(state.authMode, "", 32)) = "local" then kind = "sign-out-local"
    emitActivation(kind, page)
end sub

function validChildActivation(action as dynamic) as boolean
    if action = invalid or Type(action) <> "roAssociativeArray" then return false
    if action.kind = invalid then return false
    if PorticoHttpSafeIdentifier(action.kind, "") = "" then return false
    return PorticoSceneDispatchSpec(action.kind) <> invalid
end function

function PorticoSceneDispatchSpec(kind as dynamic) as dynamic
    normalized = LCase(safeRuntimeLabel(kind, "", 64))
    if normalized = "" then return invalid
    table = {
        "route": {targetRequired: true, requiredField: "route"},
        "route-fallback": {targetRequired: false},
        "start-account-setup": {targetRequired: false},
        "start-local-auth": {targetRequired: false},
        "pause-account-setup": {targetRequired: false},
        "back-auth-landing": {targetRequired: false},
        "sign-in-account": {targetRequired: false},
        "local-discover": {targetRequired: false},
        "local-manual-address": {targetRequired: false, requiredField: "address"},
        "local-select-server": {targetRequired: false, requiredField: "serverKey"},
        "local-confirm-trust": {targetRequired: false},
        "local-submit-credentials": {targetRequired: false, requiredField: "sealedCredentials"},
        "local-retry-session": {targetRequired: false},
        "local-back": {targetRequired: false},
        "select-profile": {targetRequired: false, requiredField: "profileId"},
        "open-detail": {targetRequired: true},
        "play": {targetRequired: true},
        "play-live": {targetRequired: true},
        "play-dvr": {targetRequired: true},
        "play-library-channel": {targetRequired: true},
        "play.from-beginning": {targetRequired: true},
        "watch-load": {targetRequired: true},
        "watch-control": {targetRequired: false},
        "watch-seek-trickplay": {targetRequired: false},
        "watch-settings": {targetRequired: false},
        "watch-leave": {targetRequired: false},
        "watch-end": {targetRequired: false},
        "player-state": {targetRequired: false},
        "seek": {targetRequired: false},
        "stop": {targetRequired: false},
        "completed": {targetRequired: false},
        "source-error": {targetRequired: false},
        "renew-grant": {targetRequired: false},
        "trickplay-dismiss": {targetRequired: false},
        "skip-segment": {targetRequired: false},
        "dismiss-segment": {targetRequired: false},
        "play-now": {targetRequired: false},
        "cancel-autoplay": {targetRequired: false},
        "confirm-still-watching": {targetRequired: false},
        "replay": {targetRequired: false},
        "previous": {targetRequired: false},
        "next": {targetRequired: false},
        "set-playback-preference": {targetRequired: false},
        "set-speed": {targetRequired: false},
        "set-sleep-timer": {targetRequired: false},
        "select-subtitle": {targetRequired: false},
        "select-audio": {targetRequired: false},
        "select-quality": {targetRequired: false},
        "select-person": {targetRequired: true},
        "retry-person": {targetRequired: true},
        "load-more-person": {targetRequired: true},
        "retry-detail-episodes": {targetRequired: true},
        "load-more-detail-episodes": {targetRequired: true},
        "load-more-home-row": {targetRequired: true},
        "load-more": {targetRequired: true},
        "refresh-home": {targetRequired: false},
        "refresh-servers": {targetRequired: false},
        "open-profile": {targetRequired: false},
        "select-server": {targetRequired: true},
        "saved-toggle": {targetRequired: true},
        "favorite-toggle": {targetRequired: true},
        "watched-toggle": {targetRequired: true},
        "watch-with-friends-refresh": {targetRequired: false},
        "watch-with-friends.start": {targetRequired: true},
        "open-server-selection": {targetRequired: false},
        "open-settings": {targetRequired: false},
        "open-connection": {targetRequired: false},
        "sign-out-account": {targetRequired: false},
        "sign-out-local": {targetRequired: false},
        "switch-profile": {targetRequired: false},
        "retry-profile-directory": {targetRequired: false},
        "cancel-profile-selection": {targetRequired: false},
        "exit-channel": {targetRequired: false},
        "save-home-customization": {targetRequired: false},
        "cancel-home-customization": {targetRequired: false},
        "submit-feedback": {targetRequired: false},
        "dismiss-notification": {targetRequired: false},
        "dismiss-saved-mutation-error": {targetRequired: false},
        "close-feedback": {targetRequired: false},
        "close-detail-more": {targetRequired: false},
        "set-detail-rating": {targetRequired: true},
        "add-detail-target": {targetRequired: true},
        "detail-queue": {targetRequired: true},
        "open-detail-targets": {targetRequired: true},
        "set-detail-reaction": {targetRequired: true},
        "create-detail-target": {targetRequired: true},
        "select-detail-season": {targetRequired: true},
        "close-detail-seasons": {targetRequired: false},
        "preferences-changed": {targetRequired: false},
        "close-saved-resource": {targetRequired: true},
        "select-saved-tab": {targetRequired: true},
        "select-saved-resource": {targetRequired: true},
        "load-more-saved": {targetRequired: true},
        "retry-saved": {targetRequired: false},
        "open-saved": {targetRequired: true},
        "select-tab": {targetRequired: false},
        "select-facet": {targetRequired: false},
        "select-resource": {targetRequired: true},
        "select-library": {targetRequired: true},
        "toggle-sort-direction": {targetRequired: false},
        "retry-library": {targetRequired: false},
        "apply-library-filters": {targetRequired: false},
        "cancel-library-filters": {targetRequired: false},
        "update-library-filter-draft": {targetRequired: false},
        "alphabet-seek": {targetRequired: false},
        "save-library-view": {targetRequired: false},
        "launch-saved-view": {targetRequired: true},
        "set-guide-query": {targetRequired: false},
        "set-guide-day": {targetRequired: false},
        "shift-guide-window": {targetRequired: false},
        "set-guide-filter": {targetRequired: true},
        "set-guide-group": {targetRequired: true},
        "cycle-guide-filter": {targetRequired: false},
        "cycle-guide-group": {targetRequired: false},
        "open-guide-search": {targetRequired: false},
        "open-guide-program": {targetRequired: true},
        "page-channels": {targetRequired: false},
        "select-channel-tab": {targetRequired: false},
        "select-source": {targetRequired: true},
        "more-sources": {targetRequired: true},
        "select-library-channel": {targetRequired: true},
        "select-program": {targetRequired: false},
        "record-program": {targetRequired: false},
        "record-series": {targetRequired: false},
        "cancel-dvr-recording": {targetRequired: false},
        "delete-dvr-recording": {targetRequired: false},
        "select-dvr-section": {targetRequired: false},
        "toggle-dvr-rule": {targetRequired: false},
        "delete-dvr-rule": {targetRequired: false},
        "toggle-recording-details": {targetRequired: false},
        "retry-channels": {targetRequired: false},
        "retry-search": {targetRequired: false},
        "submit-search": {targetRequired: false},
        "select-search-group": {targetRequired: true},
        "select-recent-search": {targetRequired: false},
        "cycle-search-sort": {targetRequired: false},
        "toggle-search-direction": {targetRequired: false},
        "clear-search-history": {targetRequired: false},
        "retry-preferences": {targetRequired: false},
        "set-automatic-profile": {targetRequired: false},
        "set-viewer-preference": {targetRequired: false},
        "clear-watch-history": {targetRequired: false},
        "open-account-security": {targetRequired: false},
        "close-account-security": {targetRequired: false},
        "close": {targetRequired: false},
        "leave-group": {targetRequired: false},
        "end-group": {targetRequired: false},
        "create-group": {targetRequired: false},
        "join-group": {targetRequired: false},
        "watch-with-friends-overlay-action": {targetRequired: false, requiredField: "overlayAction"}
    }
    if table[normalized] <> invalid then return table[normalized]
    if m.contract <> invalid and m.contract.mediaActions <> invalid and GetInterface(m.contract.mediaActions, "ifArray") <> invalid
        for each action in m.contract.mediaActions
            if action <> invalid and Type(action) = "roAssociativeArray" and LCase(safeRuntimeLabel(action.id, "", 64)) = normalized then return {targetRequired: false}
        end for
    end if
    return invalid
end function

function PorticoSceneValidateDispatch(action as dynamic) as boolean
    if action = invalid or Type(action) <> "roAssociativeArray" then return false
    kind = LCase(safeRuntimeLabel(action.kind, "", 64))
    spec = PorticoSceneDispatchSpec(kind)
    if spec = invalid then return false
    target = safeRuntimeLabel(action.targetId, "", 256)
    if spec.targetRequired = true and target = "" then return false
    requiredField = safeRuntimeLabel(spec.requiredField, "", 64)
    if requiredField <> "" and action[requiredField] = invalid then return false
    if action.viewerGeneration <> invalid
        generation = PorticoSceneSafeInteger(action.viewerGeneration, 0)
        if generation < 1 or generation <> PorticoSceneCurrentViewerGeneration() then return false
    end if
    if action.lifecycleGeneration <> invalid and PorticoSceneSafeInteger(action.lifecycleGeneration, 0) <> m.lifecycleGeneration then return false
    for each key in action
        if PorticoScenePrivateDispatchKey(key) then return false
        if key = "targetId" and Len(target) > 256 then return false
    end for
    if action.Count() > 16 then return false
    return true
end function

function PorticoScenePublishActivation(action as object) as boolean
    if not PorticoSceneValidateDispatch(action) then return false
    m.activationSequence = m.activationSequence + 1
    action.sequence = m.activationSequence
    action.page = m.page
    action.viewerGeneration = PorticoSceneCurrentViewerGeneration()
    action.lifecycleGeneration = m.lifecycleGeneration
    m.top.activation = action
    if m.activationTransactions.active <> invalid
        transaction = m.activationTransactions.active
        if PorticoActivationMarkCommitting(m.activationTransactions, transaction, transaction.viewerEpoch, transaction.routeEpoch) then PorticoActivationCommit(m.activationTransactions, transaction, transaction.viewerEpoch, transaction.routeEpoch)
    end if
    return true
end function

sub emitForwardedActivation(action as object)
    if not validChildActivation(action) then return
    forwarded = {kind: action.kind.ToStr()}
    for each key in action
        if key <> "sequence" and key <> "page" then forwarded[key] = action[key]
    end for
    PorticoScenePublishActivation(forwarded)
end sub

function activeHomeModel() as dynamic
    if PorticoSceneVisualFixtureEnabled() then return m.contract.home
    state = m.top.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" or state.homeModel = invalid then return invalid
    status = LCase(runtimeValue("homeStatus", "idle"))
    if status <> "ready" and status <> "stale" and status <> "refreshing" then return invalid
    model = state.homeModel
    if Type(model) <> "roAssociativeArray" or model.rows = invalid or GetInterface(model.rows, "ifArray") = invalid or model.rows.count() = 0 then return invalid
    return model
end function

function activeDetailModel() as dynamic
    if PorticoSceneVisualFixtureEnabled() then return m.contract.detail
    state = m.top.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" or state.detailModel = invalid then return invalid
    status = LCase(runtimeValue("detailStatus", "idle"))
    if status <> "ready" and status <> "stale" and status <> "refreshing" then return invalid
    if Type(state.detailModel) <> "roAssociativeArray" then return invalid
    return detailModelWithAvailableFeedback(state.detailModel)
end function

function detailModelWithAvailableFeedback(model as object) as object
    reportAllowed = feedbackKindAvailable("media")
    qualityAllowed = feedbackKindAvailable("quality")
    if reportAllowed and qualityAllowed then return model
    actions = sceneArray(model.uiActions)
    requiresCopy = false
    for each action in actions
        if (action = "feedback.report-problem" and not reportAllowed) or (action = "feedback.request-higher-quality" and not qualityAllowed) then requiresCopy = true
    end for
    if not requiresCopy then return model
    filtered = ParseJson(FormatJson(model))
    filtered.uiActions = []
    for each action in actions
        if action = "feedback.report-problem"
            if reportAllowed then filtered.uiActions.Push(action)
        else if action = "feedback.request-higher-quality"
            if qualityAllowed then filtered.uiActions.Push(action)
        else
            filtered.uiActions.Push(action)
        end if
    end for
    return filtered
end function

function feedbackKindAvailable(expected as string) as boolean
    engagement = activeEngagementViewState()
    if engagement = invalid or engagement.feedbackCapabilities = invalid or Type(engagement.feedbackCapabilities) <> "roAssociativeArray" then return false
    capabilities = engagement.feedbackCapabilities
    if capabilities.enabled <> true or capabilities.allowedKinds = invalid or GetInterface(capabilities.allowedKinds, "ifArray") = invalid then return false
    for each rawKind in capabilities.allowedKinds
        if LCase(safeRuntimeLabel(rawKind, "", 24)) = expected then return true
    end for
    return false
end function

sub reconcileContentFocus()
    if m.route = "home"
        model = activeHomeModel()
        syncHomeFocusedIndices(model)
        if model = invalid
            if m.focusArea = "homeActions" or m.focusArea = "homeRows" then m.focusArea = "routeActions"
        else if m.focusArea = "routeActions"
            if homeActionIds(model).count() > 0 and model.hero <> invalid
                m.focusArea = "homeActions"
            else
                firstRow = firstHomeRowIndex(model)
                if firstRow >= 0
                    m.homeFocusedRow = firstRow
                    m.focusArea = "homeRows"
                end if
            end if
        end if
        actionCount = homeActionIds(model).count()
        if actionCount > 0 and m.homeFocusedAction >= actionCount then m.homeFocusedAction = actionCount - 1
        if m.homeFocusedAction < 0 then m.homeFocusedAction = 0
        if m.focusArea = "homeRows" and homeRowItems(m.homeFocusedRow).count() = 0
            m.homeFocusedRow = firstHomeRowIndex(model)
        end if
    else if m.route = "detail"
        model = activeDetailModel()
        if model = invalid
            if Left(m.focusArea, 6) = "detail" then m.focusArea = "routeActions"
        else if m.focusArea = "routeActions"
            if detailActionIds(model).count() > 0
                m.focusArea = "detailActions"
            else
                m.focusArea = firstDetailContentArea(model)
            end if
        end if
        actionCount = detailActionIds(model).count()
        if actionCount > 0 and m.detailFocusedAction >= actionCount then m.detailFocusedAction = actionCount - 1
        if m.detailFocusedAction < 0 then m.detailFocusedAction = 0
        episodes = detailEpisodes(model)
        if episodes.count() = 0
            m.focusedEpisode = 0
        else if m.focusedEpisode >= episodes.count()
            m.focusedEpisode = episodes.count() - 1
        end if
        people = detailPeople(model)
        if people.count() = 0
            m.detailFocusedPerson = 0
        else if m.detailFocusedPerson >= people.count()
            m.detailFocusedPerson = people.count() - 1
        end if
        personResults = detailPersonResults(model)
        if personResults.count() = 0
            m.detailFocusedPersonResult = 0
        else if m.detailFocusedPersonResult >= personResults.count()
            m.detailFocusedPersonResult = personResults.count() - 1
        end if
        relationships = detailRelationships(model)
        if relationships.count() = 0
            m.detailFocusedRelationshipRow = 0
            m.detailFocusedRelationshipItem = 0
        else
            if m.detailFocusedRelationshipRow >= relationships.count() then m.detailFocusedRelationshipRow = relationships.count() - 1
            relationshipItems = sceneArray(relationships[m.detailFocusedRelationshipRow].items)
            if relationshipItems.count() = 0
                m.detailFocusedRelationshipItem = 0
            else if m.detailFocusedRelationshipItem >= relationshipItems.count()
                m.detailFocusedRelationshipItem = relationshipItems.count() - 1
            end if
        end if
    end if
end sub

function railModel() as object
    return {
        primaryItems: m.contract.railPrimaryItems,
        libraryItems: m.libraryItems,
        bottomItems: m.contract.railBottomItems
    }
end function

sub refreshRuntimeLibraries()
    m.libraryItems = []
    state = m.top.runtimeState
    if state = invalid or state.navigationSnapshotVerified <> true or state.libraryItems = invalid then return

    for each sourceItem in state.libraryItems
        if m.libraryItems.count() >= 4 then exit for
        if type(sourceItem) = "roAssociativeArray" and sourceItem.id <> invalid
            id = sourceItem.id.ToStr()
            label = invalid
            if sourceItem.label <> invalid then label = sourceItem.label
            if label = invalid and sourceItem.name <> invalid then label = sourceItem.name
            if id <> "" and label <> invalid and label.ToStr() <> "" and not containsLibraryId(m.libraryItems, id)
                m.libraryItems.push({
                    id: id,
                    route: "library/" + id,
                    label: label.ToStr(),
                    iconId: runtimeLibraryIcon(sourceItem)
                })
            end if
        end if
    end for
end sub

function containsLibraryId(items as object, id as string) as boolean
    for each item in items
        if item.id = id then return true
    end for
    return false
end function

function runtimeLibraryIcon(item as object) as string
    kind = ""
    if item.kind <> invalid then kind = LCase(item.kind.ToStr())
    if kind = "movie" or kind = "movies" then return "media.movie"
    if kind = "tv" or kind = "shows" or kind = "anime" then return "media.live-tv"
    if kind = "music" then return "media.music"
    if kind = "audiobook" or kind = "audiobooks" then return "media.audiobook"
    return "library.collection"
end function

sub reconcileRuntimeNavigation(previousFocusedRoute as string)
    if Left(m.route, 8) = "library/" and railIndexForRoute(m.route) < 0
        PorticoNavigationTransition(m.navigationStore, "library", invalid, "replace", m.navigationStore.viewerEpoch, m.navigationStore.routeEpoch)
        PorticoSceneSyncNavigationAliases()
        if m.focusArea <> "rail" then m.focusArea = "routeActions"
        m.routeFocusedAction = 0
    end if

    selectedIndex = railIndexForRoute(m.route)
    if selectedIndex >= 0 then m.selectedRailIndex = selectedIndex

    if m.focusArea = "rail"
        focusedIndex = railIndexForRoute(previousFocusedRoute)
        if focusedIndex < 0 then focusedIndex = m.selectedRailIndex
        if focusedIndex < 0 then focusedIndex = 0
        maximum = railItemCount() - 1
        if focusedIndex > maximum then focusedIndex = maximum
        m.focusedRailIndex = focusedIndex
    end if
end sub

function routeTitle(route as string) as string
    if route = "home" then return "Home"
    if route = "detail" then return "Media"
    if route = "search" then return "Search"
    if route = "person" then return "Person"
    if route = "library" then return "Library"
    if route = "channels" then return "Channels"
    if route = "saved" then return "Saved"
    if route = "profile" then return "Portico Account"
    if route = "settings" then return "Settings"
    if route = "server-selection" then return "Choose a server"
    if route = "connection" then return "Connection"

    index = railIndexForRoute(route)
    item = railItemAt(index)
    if item <> invalid then return item.label
    return "Library"
end function

function runtimeValue(key as string, fallback as string) as string
    state = m.top.runtimeState
    if state <> invalid and state[key] <> invalid and state[key].ToStr() <> "" then return state[key].ToStr()
    return fallback
end function

function accountIsSignedIn() as boolean
    accountStatus = runtimeValue("accountStatus", "signed-out")
    return accountStatus = "signed-in" or accountStatus = "refreshing" or accountStatus = "hosted-unavailable"
end function

function serverIsConnected() as boolean
    return runtimeValue("serverStatus", "not-connected") = "online"
end function

function serverSelectionListReady() as boolean
    if not accountIsSignedIn() then return false
    status = runtimeValue("serverListStatus", "unknown")
    if status <> "ready" and status <> "stale" and status <> "unknown" then return false
    return runtimeServers().count() > 0
end function

function serverSelectionModel() as object
    selectedName = runtimeValue("selectedServerName", "")
    selectedId = runtimeValue("selectedServerId", "")
    accountDetail = "No server selected"
    if selectedId <> "" and selectedName <> ""
        connectionLabel = "Unavailable"
        serverStatus = runtimeValue("serverStatus", "not-connected")
        if serverStatus = "online"
            connectionLabel = "Connected"
        else if serverStatus = "connecting"
            connectionLabel = "Connecting"
        else if serverStatus = "selected"
            connectionLabel = "Selected"
        end if
        accountDetail = selectedName + "  ·  " + connectionLabel
    end if
    servers = []
    if serverSelectionListReady() then servers = runtimeServers()
    return {
        accountDisplayName: runtimeValue("accountDisplayName", "Portico Account"),
        accountDetail: accountDetail,
        servers: servers,
        catalogState: serverSelectionCatalogState(),
        actions: serverSelectionActions()
    }
end function

function serverSelectionCatalogState() as dynamic
    if serverSelectionListReady() then return invalid

    serverListStatus = runtimeValue("serverListStatus", "unknown")
    hostedStatus = runtimeValue("hostedStatus", "unknown")
    if not accountIsSignedIn()
        return {
            id: "signed-out",
            status: "SIGN IN TO PORTICO",
            statusTone: "account",
            body: "Sign in to see the servers shared with your account."
        }
    else if serverListStatus = "loading" or serverListStatus = "unknown"
        return {
            id: "loading",
            status: "LOADING SERVERS",
            statusTone: "account",
            body: ""
        }
    else if serverListStatus = "denied"
        return {
            id: "denied",
            status: "ACCESS DENIED",
            statusTone: "danger",
            body: "This Portico Account can't access the server list."
        }
    else if serverListStatus = "incompatible" or hostedStatus = "incompatible"
        return {
            id: "incompatible",
            status: "UPDATE REQUIRED",
            statusTone: "danger",
            body: "Portico needs to be updated before your servers can load."
        }
    else if serverListStatus = "offline" or hostedStatus = "offline" or hostedStatus = "throttled"
        return {
            id: "offline",
            status: "SERVERS UNAVAILABLE",
            statusTone: "warning",
            body: "Check your internet connection and try again."
        }
    end if

    return {
        id: "empty",
        status: "NO SERVERS",
        statusTone: "warning",
        body: "No servers are shared with this Portico Account."
    }
end function

function serverSelectionActions() as object
    actions = []
    catalogState = serverSelectionCatalogState()
    showRefresh = accountIsSignedIn()
    if catalogState <> invalid and catalogState.id = "loading" then showRefresh = false
    if showRefresh
        actions.push({id: "refresh-servers", kind: "action", name: "Refresh", iconId: "action.retry", selected: false})
    end if
    actions.push({id: "open-profile", kind: "action", name: "Account", iconId: "account.user", selected: false})
    return actions
end function

function serverSelectionActionCount() as integer
    return serverSelectionActions().count()
end function

function runtimeServers() as object
    result = []
    state = m.top.runtimeState
    if state = invalid or state.availableServers = invalid then return result
    if GetInterface(state.availableServers, "ifArray") = invalid then return result
    selectedId = runtimeValue("selectedServerId", "")
    listIsStale = runtimeValue("serverListStatus", "unknown") = "stale"

    for each source in state.availableServers
        if result.count() >= 500 then exit for
        if Type(source) = "roAssociativeArray" and source.id <> invalid and source.name <> invalid
            id = safeServerId(source.id)
            name = safeRuntimeLabel(source.name, "Portico Server", 80)
            if id <> "" and name <> ""
                authMode = LCase(safeRuntimeLabel(source.preferredAuthMode, "portico", 24))
                if authMode <> "local" then authMode = "portico"
                availability = LCase(safeRuntimeLabel(source.availabilityState, "unknown", 40))
                remoteAccessEnabled = source.remoteAccessEnabled = true
                detail = "Portico Account"
                availabilityLabel = "Checking"
                availabilityTone = "account"
                if authMode = "local" then detail = "Sign in with this server"
                if listIsStale
                    availabilityLabel = "Not checked"
                    availabilityTone = "neutral"
                else if authMode = "local"
                    availabilityLabel = "Server Only Authentication"
                else if not remoteAccessEnabled or availability = "remote_access_disabled"
                    detail = "Remote Access is off"
                    availabilityLabel = "Local network only"
                    availabilityTone = "warning"
                else if availability = "reported_online"
                    availabilityLabel = "Online"
                    availabilityTone = "healthy"
                else if availability = "offline"
                    availabilityLabel = "Offline"
                    availabilityTone = "warning"
                else
                    availabilityLabel = "Status unavailable"
                    availabilityTone = "neutral"
                end if
                result.push({
                    id: id,
                    name: name,
                    detail: detail,
                    availabilityLabel: availabilityLabel,
                    availabilityTone: availabilityTone,
                    selected: id = selectedId
                })
            end if
        end if
    end for
    return result
end function

function safeServerId(value as dynamic) as string
    if value = invalid then return ""
    normalized = value.ToStr().Trim()
    if Len(normalized) < 1 or Len(normalized) > 128 then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for position = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, position, 1)) = 0 then return ""
    end for
    return normalized
end function

function safeRuntimeLabel(value as dynamic, fallback as string, maximum as integer) as string
    normalized = fallback
    if value <> invalid then normalized = value.ToStr()
    normalized = normalized.Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if normalized = "" then normalized = fallback
    if Len(normalized) > maximum then normalized = Left(normalized, maximum)
    return normalized
end function

function routeStateModel(route as string) as object
    title = routeTitle(route)
    accountStatus = runtimeValue("accountStatus", "signed-out")
    hostedStatus = runtimeValue("hostedStatus", "unknown")
    serverStatus = runtimeValue("serverStatus", "not-connected")
    serverName = runtimeValue("selectedServerName", "your server")

    status = "SERVER OFFLINE"
    tone = "warning"
    body = "Connect to a Portico Server to browse your media."
    detail = ""
    actions = [{id: "open-connection", label: "Connection", iconId: "navigation.settings", width: 214}]

    if serverStatus = "online"
        status = "CONNECTED"
        tone = "healthy"
        body = "Connected to " + serverName + "."
    else if serverStatus = "connecting"
        status = "CONNECTING"
        tone = "account"
        body = "Portico is connecting to " + serverName + "."
    else if serverStatus = "none" or serverStatus = "not-connected"
        status = "NO SERVER SELECTED"
        body = "Choose a Portico Server to browse your media."
        actions = [{id: "open-server-selection", label: "Choose Server", iconId: "navigation.library", width: 226}]
    else if serverStatus = "identity-mismatch" or serverStatus = "incompatible" or serverStatus = "permission-removed"
        status = "CONNECTION BLOCKED"
        tone = "danger"
        body = "Portico couldn't safely connect to " + serverName + "."
        actions = [{id: "open-connection", label: "Connection", iconId: "navigation.settings", width: 214}]
    end if

    if route = "home" and not PorticoSceneVisualFixtureEnabled()
        homeStatus = LCase(runtimeValue("homeStatus", "idle"))
        if serverStatus = "online" and (homeStatus = "idle" or homeStatus = "loading")
            status = "LOADING HOME"
            tone = "account"
            body = "Loading your media."
            actions = []
        else if serverStatus = "online" and homeStatus = "ready"
            status = "NOTHING TO WATCH YET"
            tone = "account"
            body = "This server has no visible media yet."
            actions = [{id: "refresh-home", label: "Refresh Home", iconId: "action.retry", width: 230}]
        else if homeStatus = "permission-removed"
            status = "HOME UNAVAILABLE"
            tone = "danger"
            body = "Your account no longer has access to this media."
            actions = [{id: "open-connection", label: "Connection", iconId: "navigation.settings", width: 214}]
        else if homeStatus = "incompatible" or homeStatus = "unavailable"
            status = "UPDATE REQUIRED"
            tone = "danger"
            body = "This server can't provide a compatible Home screen."
            actions = [{id: "open-connection", label: "Connection", iconId: "navigation.settings", width: 214}]
        else if serverStatus = "online"
            status = "HOME COULDN'T LOAD"
            tone = "warning"
            body = "Portico couldn't load Home from this server."
            actions = [{id: "refresh-home", label: "Try Again", iconId: "action.retry", width: 190}]
        end if
        return {route: route, title: title, status: status, statusTone: tone, body: body, detail: detail, actions: actions}
    else if route = "detail" and not PorticoSceneVisualFixtureEnabled()
        detailStatus = LCase(runtimeValue("detailStatus", "idle"))
        if detailStatus = "loading" or detailStatus = "refreshing"
            status = "LOADING MEDIA"
            tone = "account"
            body = "Loading this item."
            actions = []
        else if detailStatus = "not-found"
            status = "MEDIA NOT FOUND"
            tone = "warning"
            body = "This item is no longer available."
            actions = []
        else if detailStatus = "permission-removed"
            status = "MEDIA UNAVAILABLE"
            tone = "danger"
            body = "Your account no longer has access to this item."
            actions = []
        else if detailStatus = "incompatible" or detailStatus = "unavailable"
            status = "UPDATE REQUIRED"
            tone = "danger"
            body = "This item can't be displayed by this version of Portico."
            actions = []
        else if serverStatus = "online" and runtimeValue("detailMediaId", "") <> ""
            status = "MEDIA COULDN'T LOAD"
            tone = "warning"
            body = "Portico couldn't load this item."
            actions = [{id: "retry-detail", label: "Try Again", iconId: "action.retry", width: 190}]
        end if
        return {route: route, title: title, status: status, statusTone: tone, body: body, detail: detail, actions: actions}
    end if

    if route = "search"
        if serverIsConnected()
            body = "Connected to " + serverName + "."
        else
            body = "Connect to a Portico Server to search your media."
        end if
    else if route = "library"
        if serverIsConnected()
            body = "Connected to " + serverName + "."
        else
            body = "Connect to a Portico Server to view your libraries."
        end if
    else if Left(route, 8) = "library/"
        if serverIsConnected()
            body = title + " is connected to " + serverName + "."
        else
            body = title + " is unavailable while " + serverName + " is offline."
        end if
    else if route = "channels"
        if serverIsConnected()
            body = "Connected to " + serverName + "."
        else
            body = "Connect to a Portico Server to watch live TV and view the guide."
        end if
    else if route = "saved"
        if serverIsConnected()
            body = "Connected to " + serverName + "."
        else
            body = "Connect to a Portico Server to refresh your saved media."
        end if
    else if route = "profile"
        tone = "account"
        detail = ""
        status = "SIGNED IN"
        displayName = runtimeValue("accountDisplayName", "Your Portico Account")
        body = displayName + " is signed in."
        if accountStatus = "hosted-unavailable"
            if hostedStatus = "incompatible"
                detail = "Portico needs to be updated before account details can refresh."
            else
                detail = "Some account details may be out of date until Portico reconnects."
            end if
        end if
        actions = [
            {id: "open-server-selection", label: "Servers", iconId: "navigation.library", width: 190},
            {id: "sign-out-account", label: "Sign Out", iconId: "account.sign-out", width: 176}
        ]
    else if route = "settings"
        status = "SETTINGS"
        tone = "account"
        body = "Manage your Portico Account, servers, and connection."
        detail = ""
        actions = [
            {id: "open-profile", label: "Account", iconId: "account.user", width: 190},
            {id: "open-server-selection", label: "Servers", iconId: "navigation.library", width: 190},
            {id: "open-connection", label: "Connection", iconId: "navigation.settings", width: 214}
        ]
    else if route = "server-selection"
        tone = "warning"
        detail = ""
        serverListStatus = runtimeValue("serverListStatus", "unknown")
        actions = [
            {id: "refresh-servers", label: "Refresh", iconId: "action.refresh", width: 190},
            {id: "open-profile", label: "Account", iconId: "account.user", width: 190}
        ]
        if serverListStatus = "loading"
            status = "LOADING SERVERS"
            tone = "account"
            body = "Loading your servers."
            actions = [{id: "open-profile", label: "Account", iconId: "account.user", width: 190}]
        else if serverListStatus = "denied"
            status = "ACCESS DENIED"
            tone = "danger"
            body = "This Portico Account can't access the server list."
        else if serverListStatus = "incompatible" or hostedStatus = "incompatible"
            status = "UPDATE REQUIRED"
            tone = "danger"
            body = "Portico needs to be updated before your servers can load."
        else if serverListStatus = "offline"
            status = "SERVERS UNAVAILABLE"
            body = "Your servers couldn't be loaded."
        else if hostedStatus = "offline" or hostedStatus = "throttled"
            status = "SERVERS UNAVAILABLE"
            body = "Portico couldn't load your servers."
        else if serverListStatus = "ready" and runtimeServers().count() = 0
            status = "NO SERVERS"
            body = "No servers are shared with this Portico Account."
        else
            status = "CHOOSE A SERVER"
            tone = "account"
            body = "Choose where you want to watch."
        end if
    else if route = "connection"
        actions = [
            {id: "open-server-selection", label: "Choose Server", iconId: "navigation.library", width: 226},
            {id: "open-profile", label: "Account", iconId: "account.user", width: 190}
        ]
        if serverStatus = "offline" and runtimeValue("selectedServerId", "") <> ""
            retryKind = "retry-server"
            authMode = LCase(runtimeValue("authMode", ""))
            if Left(authMode, 5) = "local" then retryKind = "local-retry-session"
            actions = [
                {id: retryKind, label: "Try Again", iconId: "action.retry", width: 190},
                {id: "open-server-selection", label: "Choose Server", iconId: "navigation.library", width: 226},
                {id: "open-profile", label: "Account", iconId: "account.user", width: 190}
            ]
        end if
        if serverStatus = "online"
            status = "CONNECTED"
            tone = "healthy"
            body = "Connected to " + serverName + "."
            detail = ""
        else if serverStatus = "connecting"
            status = "CONNECTING"
            tone = "account"
            body = "Portico is connecting to " + serverName + "."
            detail = ""
        else if serverStatus = "selected"
            status = "SERVER SELECTED"
            tone = "account"
            body = serverName
            detail = ""
        else if serverStatus = "identity-mismatch" or serverStatus = "incompatible" or serverStatus = "permission-removed"
            status = "CONNECTION BLOCKED"
            tone = "danger"
            body = "Portico couldn't safely connect to " + serverName + "."
            detail = "Choose another server or review the connection."
        else if serverStatus = "none" or serverStatus = "not-connected"
            status = "NO SERVER SELECTED"
            tone = "warning"
            body = "Choose a Portico Server to start watching."
            detail = ""
        else
            status = "SERVER OFFLINE"
            tone = "warning"
            body = "Portico couldn't connect to " + serverName + "."
            detail = "Check that your server is running and on the same network, or choose another server."
        end if
    end if

    return {route: route, title: title, status: status, statusTone: tone, body: body, detail: detail, actions: actions}
end function

function routeActionCount() as integer
    model = routeStateModel(m.route)
    if model.actions = invalid then return 0
    return model.actions.count()
end function

function activeRouteActionCount() as integer
    if m.route = "server-selection" then return serverSelectionActionCount()
    return routeActionCount()
end function

sub clampRouteActionFocus()
    if m.focusArea <> "routeActions" then return
    count = activeRouteActionCount()
    if count <= 0
        m.routeFocusedAction = 0
    else if m.routeFocusedAction >= count
        m.routeFocusedAction = count - 1
    end if
end sub

sub clampServerSelectionFocus()
    servers = runtimeServers()
    if not serverSelectionListReady()
        m.serverFocusedIndex = 0
        m.serverListOffset = 0
        if m.route = "server-selection" and m.focusArea <> "serverClose" then m.focusArea = "serverActions"
        actionCount = serverSelectionActionCount()
        if actionCount <= 0
            m.routeFocusedAction = 0
        else if m.routeFocusedAction >= actionCount
            m.routeFocusedAction = actionCount - 1
        end if
        return
    end if
    if m.serverFocusedIndex < 0 then m.serverFocusedIndex = 0
    if m.serverFocusedIndex >= servers.count() then m.serverFocusedIndex = servers.count() - 1
    if m.serverListOffset < 0 then m.serverListOffset = 0
    maximumOffset = servers.count() - 6
    if maximumOffset < 0 then maximumOffset = 0
    if m.serverListOffset > maximumOffset then m.serverListOffset = maximumOffset
    if m.serverFocusedIndex < m.serverListOffset then m.serverListOffset = m.serverFocusedIndex
    if m.serverFocusedIndex >= m.serverListOffset + 6 then m.serverListOffset = m.serverFocusedIndex - 5
end sub

sub focusSelectedServer()
    servers = runtimeServers()
    if servers.count() = 0 then return
    selectedIndex = 0
    for index = 0 to servers.count() - 1
        if servers[index].selected = true
            selectedIndex = index
            exit for
        end if
    end for
    m.serverFocusedIndex = selectedIndex
    m.focusArea = "serverList"
    clampServerSelectionFocus()
end sub

function railItemCount() as integer
    return m.contract.railPrimaryItems.count() + m.libraryItems.count() + m.contract.railBottomItems.count()
end function

function railItemAt(flatIndex as integer) as object
    if flatIndex < 0 then return invalid
    sections = [m.contract.railPrimaryItems, m.libraryItems, m.contract.railBottomItems]
    remaining = flatIndex
    for each section in sections
        if remaining < section.count() then return section[remaining]
        remaining = remaining - section.count()
    end for
    return invalid
end function

function railIndexForRoute(route as string) as integer
    if route = "" then return -1
    for index = 0 to railItemCount() - 1
        item = railItemAt(index)
        if item <> invalid and item.route = route then return index
    end for
    return -1
end function

function isTransientRoute(route as string) as boolean
    return route = "search" or route = "profile" or route = "settings"
end function

function copySceneIntegerArray(source as dynamic) as object
    result = []
    if source = invalid or GetInterface(source, "ifArray") = invalid then return result
    for each value in source
        result.push(value)
    end for
    return result
end function

function copySceneStringMap(source as dynamic) as object
    result = {}
    if source = invalid or Type(source) <> "roAssociativeArray" then return result
    for each key in source
        result[key] = safeRuntimeLabel(source[key], "", 256)
    end for
    return result
end function

function captureRouteSnapshot(focusOverride as dynamic) as object
    focusValue = m.focusArea
    if focusOverride <> invalid then focusValue = focusOverride.ToStr()
    return {
        route: m.route,
        page: m.page,
        selectedRailIndex: m.selectedRailIndex,
        focusArea: focusValue,
        routeFocusedAction: m.routeFocusedAction,
        homeFocusedAction: m.homeFocusedAction,
        homeFocusedRow: m.homeFocusedRow,
        homeFocusedIndices: copySceneIntegerArray(m.homeFocusedIndices),
        homeFocusedRowId: m.homeFocusedRowId,
        homeFocusedItemIds: copySceneStringMap(m.homeFocusedItemIds),
        homeHeroIndex: m.homeHeroIndex,
        detailFocusedAction: m.detailFocusedAction,
        focusedEpisode: m.focusedEpisode,
        detailFocusedPerson: m.detailFocusedPerson,
        detailFocusedPersonResult: m.detailFocusedPersonResult,
        detailFocusedRelationshipRow: m.detailFocusedRelationshipRow,
        detailFocusedRelationshipItem: m.detailFocusedRelationshipItem,
        detailFactsOpen: m.detailFactsOpen,
        serverFocusedIndex: m.serverFocusedIndex,
        serverListOffset: m.serverListOffset
    }
end function

sub restoreRouteSnapshot(snapshot as object)
    destination = PorticoNavigationCurrent(m.navigationStore)
    if destination = invalid then return
    route = destination.route
    if Left(route, 8) = "library/" and railIndexForRoute(route) < 0 then route = "library"
    if route <> destination.route then PorticoNavigationTransition(m.navigationStore, route, invalid, "replace", m.navigationStore.viewerEpoch, m.navigationStore.routeEpoch)
    PorticoSceneSyncNavigationAliases()
    m.focusArea = snapshot.focusArea
    m.routeFocusedAction = snapshot.routeFocusedAction
    m.homeFocusedAction = snapshot.homeFocusedAction
    m.homeFocusedRow = snapshot.homeFocusedRow
    m.homeFocusedIndices = copySceneIntegerArray(snapshot.homeFocusedIndices)
    if snapshot.homeFocusedRowId <> invalid then m.homeFocusedRowId = safeRuntimeLabel(snapshot.homeFocusedRowId, "", 256)
    if snapshot.homeFocusedItemIds <> invalid then m.homeFocusedItemIds = copySceneStringMap(snapshot.homeFocusedItemIds)
    m.homeHeroIndex = snapshot.homeHeroIndex
    m.detailFocusedAction = snapshot.detailFocusedAction
    m.focusedEpisode = snapshot.focusedEpisode
    if snapshot.detailFocusedPerson <> invalid then m.detailFocusedPerson = snapshot.detailFocusedPerson
    if snapshot.detailFocusedPersonResult <> invalid then m.detailFocusedPersonResult = snapshot.detailFocusedPersonResult
    if snapshot.detailFocusedRelationshipRow <> invalid then m.detailFocusedRelationshipRow = snapshot.detailFocusedRelationshipRow
    if snapshot.detailFocusedRelationshipItem <> invalid then m.detailFocusedRelationshipItem = snapshot.detailFocusedRelationshipItem
    if snapshot.detailFactsOpen <> invalid then m.detailFactsOpen = snapshot.detailFactsOpen
    if snapshot.serverFocusedIndex <> invalid then m.serverFocusedIndex = snapshot.serverFocusedIndex
    if snapshot.serverListOffset <> invalid then m.serverListOffset = snapshot.serverListOffset
    m.railExpanded = false
    routeIndex = railIndexForRoute(route)
    if routeIndex >= 0
        m.selectedRailIndex = routeIndex
    else
        m.selectedRailIndex = snapshot.selectedRailIndex
    end if
end sub

sub selectPrimaryRoute(route as string, railIndex as integer)
    m.detailMoreOpen = false
    m.homeCustomizeOpen = false
    PorticoNavigationTransition(m.navigationStore, route, invalid, "primary", m.navigationStore.viewerEpoch, m.navigationStore.routeEpoch)
    PorticoSceneSyncNavigationAliases()
    m.selectedRailIndex = railIndex
    m.railExpanded = false
    m.routeFocusedAction = 0
    if route = "server-selection"
        m.serverFocusedIndex = 0
        m.serverListOffset = 0
    end if
    if route = "search"
        m.focusArea = "search"
    else if route = "person"
        m.focusArea = "person"
    else if route = "library" or Left(route, 8) = "library/"
        m.focusArea = "library"
    else if route = "saved"
        m.focusArea = "saved"
    else if route = "channels"
        m.focusArea = "channels"
    else if route = "profile"
        m.focusArea = "profile"
    else if route = "settings"
        m.focusArea = "settings"
    else if route = "home" and PorticoSceneVisualFixtureEnabled()
        m.focusArea = "homeActions"
    else
        m.focusArea = "routeActions"
    end if
    reconcileContentFocus()
end sub

sub pushRoute(route as string, railIndex as integer, focusOverride as dynamic)
    m.detailMoreOpen = false
    m.homeCustomizeOpen = false
    m.navigationStore.current.snapshot = captureRouteSnapshot(focusOverride)
    PorticoNavigationTransition(m.navigationStore, route, invalid, "push", m.navigationStore.viewerEpoch, m.navigationStore.routeEpoch)
    PorticoSceneSyncNavigationAliases()
    if railIndex >= 0 then m.selectedRailIndex = railIndex
    m.railExpanded = false
    if route = "search"
        m.focusArea = "search"
    else if route = "person"
        m.focusArea = "person"
    else if route = "library" or Left(route, 8) = "library/"
        m.focusArea = "library"
    else if route = "saved"
        m.focusArea = "saved"
    else if route = "channels"
        m.focusArea = "channels"
    else if route = "profile"
        m.focusArea = "profile"
    else if route = "settings"
        m.focusArea = "settings"
    else if route = "player"
        m.focusArea = "player"
    else
        m.focusArea = "routeActions"
    end if
    m.routeFocusedAction = 0
end sub

sub openInternalRoute(route as string)
    pushRoute(route, -1, m.focusArea)
    if route = "server-selection"
        m.serverPickerWaitingForList = not serverSelectionListReady()
        if serverSelectionListReady()
            focusSelectedServer()
        else
            m.focusArea = "serverActions"
            m.routeFocusedAction = 0
        end if
    end if
end sub

sub replaceWithServerSelection()
    ' Profile selection is a gate, not a pushed product route. Cancelling it
    ' replaces the gate with server selection so Back cannot reopen a stale,
    ' already-cancelled profile transaction.
    selectPrimaryRoute("server-selection", m.selectedRailIndex)
    m.serverPickerWaitingForList = not serverSelectionListReady()
    if serverSelectionListReady()
        focusSelectedServer()
    else
        m.focusArea = "serverActions"
        m.routeFocusedAction = 0
    end if
end sub

function historyReturnsTo(route as string) as boolean
    if m.navigationStore.history.count() = 0 then return false
    destination = m.navigationStore.history[m.navigationStore.history.count() - 1]
    return destination.route = route
end function

function navigateBack() as boolean
    destination = PorticoNavigationBack(m.navigationStore)
    if destination = invalid or destination.snapshot = invalid then return false
    PorticoSceneSyncNavigationAliases()
    restoreRouteSnapshot(destination.snapshot)
    return true
end function

function homeHeroModel() as dynamic
    model = activeHomeModel()
    if model = invalid then return invalid
    heroModel = model.hero
    rows = homeRows(model)
    if m.homeFocusedRow >= 0 and m.homeFocusedRow < rows.count() and m.homeFocusedRow < m.homeFocusedIndices.count()
        items = sceneArray(rows[m.homeFocusedRow].items)
        itemIndex = m.homeFocusedIndices[m.homeFocusedRow]
        if itemIndex >= 0 and itemIndex < items.count() and items[itemIndex].hero <> invalid then heroModel = items[itemIndex].hero
    end if
    return heroModel
end function

function homeRowItems(rowIndex as integer) as object
    model = activeHomeModel()
    if model = invalid then return []
    rows = homeRows(model)
    if rowIndex >= 0 and rowIndex < rows.count() then return sceneArray(rows[rowIndex].items)
    return []
end function

function homeRows(model as dynamic) as object
    result = []
    if model = invalid or Type(model) <> "roAssociativeArray" then return result
    if model.rows <> invalid and GetInterface(model.rows, "ifArray") <> invalid
        for each row in model.rows
            if result.count() >= 32 then exit for
            if row <> invalid and Type(row) = "roAssociativeArray" and sceneArray(row.items).count() > 0 then result.push(row)
        end for
    end if
    if result.count() = 0
        continueItems = sceneArray(model.continueWatching)
        recentItems = sceneArray(model.recentlyAdded)
        if continueItems.count() > 0 then result.push({id: "continue", title: "Continue Watching", items: continueItems, hasMore: false})
        if recentItems.count() > 0 then result.push({id: "recent", title: "Recently Added", items: recentItems, hasMore: false})
    end if
    return result
end function

function sceneArray(value as dynamic) as object
    if value <> invalid and GetInterface(value, "ifArray") <> invalid then return value
    return []
end function

sub syncHomeFocusedIndices(model as dynamic)
    rows = homeRows(model)
    previous = m.homeFocusedIndices
    nextIndices = []
    for index = 0 to rows.count() - 1
        focused = 0
        if previous <> invalid and GetInterface(previous, "ifArray") <> invalid and index < previous.count() then focused = previous[index]
        items = sceneArray(rows[index].items)
        rowId = sceneStableId(rows[index])
        rememberedItemId = ""
        if rowId <> "" and m.homeFocusedItemIds[rowId] <> invalid then rememberedItemId = m.homeFocusedItemIds[rowId]
        if rememberedItemId <> ""
            rememberedIndex = sceneIndexByStableId(items, rememberedItemId)
            if rememberedIndex >= 0 then focused = rememberedIndex
        end if
        if focused < 0 then focused = 0
        if items.count() > 0 and focused >= items.count() then focused = items.count() - 1
        nextIndices.push(focused)
    end for
    m.homeFocusedIndices = nextIndices
    if rows.count() = 0
        m.homeFocusedRow = 0
    else
        rememberedRowIndex = sceneIndexByStableId(rows, m.homeFocusedRowId)
        if rememberedRowIndex >= 0 then m.homeFocusedRow = rememberedRowIndex
        if m.homeFocusedRow < 0 then m.homeFocusedRow = 0
        if m.homeFocusedRow >= rows.count() then m.homeFocusedRow = rows.count() - 1
    end if
end sub

sub rememberHomeFocusIdentity(model as dynamic)
    rows = homeRows(model)
    if m.homeFocusedRow >= 0 and m.homeFocusedRow < rows.count()
        m.homeFocusedRowId = sceneStableId(rows[m.homeFocusedRow])
    end if
    for rowIndex = 0 to rows.count() - 1
        if rowIndex >= m.homeFocusedIndices.count() then exit for
        rowId = sceneStableId(rows[rowIndex])
        items = sceneArray(rows[rowIndex].items)
        itemIndex = m.homeFocusedIndices[rowIndex]
        if rowId <> "" and itemIndex >= 0 and itemIndex < items.count()
            itemId = sceneStableId(items[itemIndex])
            if itemId <> "" then m.homeFocusedItemIds[rowId] = itemId
        end if
    end for
end sub

function sceneStableId(value as dynamic) as string
    if value = invalid or Type(value) <> "roAssociativeArray" or value.id = invalid then return ""
    return safeRuntimeLabel(value.id, "", 256)
end function

function sceneIndexByStableId(values as dynamic, expected as string) as integer
    if expected = "" or values = invalid or GetInterface(values, "ifArray") = invalid then return -1
    for index = 0 to values.count() - 1
        if sceneStableId(values[index]) = expected then return index
    end for
    return -1
end function

function homeShouldReserveContent() as boolean
    if PorticoSceneVisualFixtureEnabled() then return false
    if runtimeValue("serverStatus", "not-connected") <> "online" then return false
    status = LCase(runtimeValue("homeStatus", "idle"))
    return status = "idle" or status = "loading"
end function

function reservedHomeModel() as object
    return {
        availabilityStatus: "current",
        rows: [
            {id: "reserved-home-0", title: "", items: [], required: true, loadStatus: "restoring", hasMore: false},
            {id: "reserved-home-1", title: "", items: [], required: true, loadStatus: "restoring", hasMore: false}
        ]
    }
end function

function firstHomeRowIndex(model as dynamic) as integer
    rows = homeRows(model)
    if rows.count() > 0 then return 0
    return -1
end function

function nextHomeRowIndex(current as integer) as integer
    rows = homeRows(activeHomeModel())
    for index = current + 1 to rows.count() - 1
        if sceneArray(rows[index].items).count() > 0 then return index
    end for
    return current
end function

function previousHomeRowIndex(current as integer) as integer
    rows = homeRows(activeHomeModel())
    index = current - 1
    while index >= 0
        if sceneArray(rows[index].items).count() > 0 then return index
        index = index - 1
    end while
    return current
end function

function homeActionIds(model as dynamic) as object
    hero = homeHeroModel()
    if model = invalid or hero = invalid then return []
    if hero.uiActions = invalid or GetInterface(hero.uiActions, "ifArray") = invalid then return []
    return safeSceneActionIds(hero.uiActions, {play: true, "saved-toggle": true, "open-detail": true, "favorite-toggle": true})
end function

function detailActionIds(model as dynamic) as object
    if model = invalid then return []
    if model.uiActions = invalid or GetInterface(model.uiActions, "ifArray") = invalid then return []
    return safeSceneActionIds(model.uiActions, {play: true, "play.from-beginning": true, "saved-toggle": true, "favorite-toggle": true, "watched-toggle": true, "watch-with-friends.start": true, "feedback.report-problem": true, "feedback.request-higher-quality": true, more: true}, 9)
end function

function safeSceneActionIds(source as object, allowed as object, maximum = 4 as integer) as object
    result = []
    seen = {}
    for each rawAction in source
        action = LCase(safeRuntimeLabel(rawAction, "", 48))
        if allowed[action] = true and seen[action] <> true
            seen[action] = true
            result.push(action)
        end if
        if result.count() >= maximum then exit for
    end for
    return result
end function

function detailEpisodes(model as dynamic) as object
    if model <> invalid and model.episodes <> invalid and GetInterface(model.episodes, "ifArray") <> invalid then return model.episodes
    return []
end function

function detailPeople(model as dynamic) as object
    if model <> invalid and model.people <> invalid and GetInterface(model.people, "ifArray") <> invalid then return model.people
    return []
end function

function detailPersonResults(model as dynamic) as object
    if model <> invalid and model.personResults <> invalid and GetInterface(model.personResults, "ifArray") <> invalid then return model.personResults
    return []
end function

function detailRelationships(model as dynamic) as object
    if model <> invalid and model.relationships <> invalid and GetInterface(model.relationships, "ifArray") <> invalid then return model.relationships
    return []
end function

function detailContentAreas(model as dynamic) as object
    result = []
    if model = invalid then return result
    if model.seasons <> invalid and GetInterface(model.seasons, "ifArray") <> invalid and model.seasons.Count() > 0 then result.push("detailSeason")
    if detailEpisodes(model).count() > 0 then result.push("detailEpisodes")
    if detailPeople(model).count() > 0 then result.push("detailPeople")
    selectedPersonName = safeRuntimeLabel(model.selectedPersonName, "", 100)
    personStatus = LCase(safeRuntimeLabel(model.personStatus, "idle", 24))
    if selectedPersonName <> "" and (detailPersonResults(model).count() > 0 or personStatus = "error" or personStatus = "offline") then result.push("detailPersonResults")
    relationships = detailRelationships(model)
    for rowIndex = 0 to relationships.count() - 1
        if sceneArray(relationships[rowIndex].items).count() > 0 then result.push("detailRelationship" + rowIndex.ToStr())
    end for
    result.push("detailFacts")
    return result
end function

function firstDetailContentArea(model as dynamic) as string
    areas = detailContentAreas(model)
    if areas.count() > 0 then return areas[0]
    return "detailBody"
end function

function detailFocusSequence(model as dynamic) as object
    result = []
    if detailActionIds(model).count() > 0 then result.push("detailActions")
    for each area in detailContentAreas(model)
        result.push(area)
    end for
    if result.count() = 0 then result.push("detailBody")
    return result
end function

function detailFocusAreaOffset(area as string, direction as integer) as string
    sequence = detailFocusSequence(activeDetailModel())
    currentIndex = -1
    for index = 0 to sequence.count() - 1
        if sequence[index] = area then currentIndex = index
    end for
    if currentIndex < 0 then return sequence[0]
    nextIndex = currentIndex + direction
    if nextIndex < 0 then nextIndex = 0
    if nextIndex >= sequence.count() then nextIndex = sequence.count() - 1
    return sequence[nextIndex]
end function

function detailRelationshipRowFromArea(area as string) as integer
    prefix = "detailRelationship"
    if Left(area, Len(prefix)) <> prefix then return -1
    return Int(Val(Mid(area, Len(prefix) + 1)))
end function

sub moveDetailHorizontal(direction as integer)
    model = activeDetailModel()
    if model = invalid then return
    if m.focusArea = "detailActions"
        count = detailActionIds(model).count()
        if direction < 0 and m.detailFocusedAction > 0
            m.detailFocusedAction = m.detailFocusedAction - 1
        else if direction > 0 and m.detailFocusedAction < count - 1
            m.detailFocusedAction = m.detailFocusedAction + 1
        else if direction < 0
            enterRail()
        end if
    else if m.focusArea = "detailEpisodes"
        previous = m.focusedEpisode
        m.focusedEpisode = sceneMoveIndex(m.focusedEpisode, detailEpisodes(model).count(), direction)
        if direction > 0 and previous = detailEpisodes(model).count() - 1 and model.episodesHasMore = true then emitActivation("load-more-detail-episodes", safeRuntimeLabel(model.selectedSeasonId, "", 128))
        if direction < 0 and previous = 0 then enterRail()
    else if m.focusArea = "detailSeason"
        if direction < 0 then enterRail()
    else if m.focusArea = "detailPeople"
        previous = m.detailFocusedPerson
        m.detailFocusedPerson = sceneMoveIndex(m.detailFocusedPerson, detailPeople(model).count(), direction)
        if direction < 0 and previous = 0 then enterRail()
    else if m.focusArea = "detailPersonResults"
        previous = m.detailFocusedPersonResult
        m.detailFocusedPersonResult = sceneMoveIndex(m.detailFocusedPersonResult, detailPersonResults(model).count(), direction)
        if direction < 0 and previous = 0 then enterRail()
    else if Left(m.focusArea, 18) = "detailRelationship"
        rowIndex = detailRelationshipRowFromArea(m.focusArea)
        relationships = detailRelationships(model)
        if rowIndex >= 0 and rowIndex < relationships.count()
            previous = m.detailFocusedRelationshipItem
            m.detailFocusedRelationshipRow = rowIndex
            m.detailFocusedRelationshipItem = sceneMoveIndex(m.detailFocusedRelationshipItem, sceneArray(relationships[rowIndex].items).count(), direction)
            if direction < 0 and previous = 0 then enterRail()
        end if
    else if direction < 0
        enterRail()
    end if
end sub

function sceneMoveIndex(current as integer, count as integer, direction as integer) as integer
    if count <= 0 then return 0
    nextIndex = current + direction
    if nextIndex < 0 then nextIndex = 0
    if nextIndex >= count then nextIndex = count - 1
    return nextIndex
end function

sub moveDetailVertical(direction as integer)
    m.focusArea = detailFocusAreaOffset(m.focusArea, direction)
    rowIndex = detailRelationshipRowFromArea(m.focusArea)
    if rowIndex >= 0 then m.detailFocusedRelationshipRow = rowIndex
end sub

sub emitActivation(kind as string, targetId as dynamic)
    targetValue = ""
    if targetId <> invalid then targetValue = targetId.ToStr()
    PorticoScenePublishActivation({
        kind: kind,
        targetId: targetValue
    })
end sub

sub emitPlaybackActivation(kind as string, targetId as dynamic, title as dynamic, meta as dynamic, startSeconds = invalid as dynamic)
    targetValue = ""
    if targetId <> invalid then targetValue = targetId.ToStr()
    titleValue = ""
    if title <> invalid then titleValue = title.ToStr()
    metaValue = ""
    if meta <> invalid then metaValue = meta.ToStr()
    activation = {
        kind: kind,
        targetId: targetValue,
        title: titleValue,
        meta: metaValue
    }
    if startSeconds <> invalid then activation.startSeconds = startSeconds
    PorticoScenePublishActivation(activation)
end sub

sub enterRail()
    PorticoSceneRefreshFocusGraph()
    boundaryTarget = PorticoScreenAuthorityMoveBoundary(m.screenAuthority, "left", PorticoSceneSemanticFocusId())
    if boundaryTarget = "" then return
    m.focusBeforeRail = m.focusArea
    priorSemanticId = PorticoSceneSemanticFocusId()
    m.railExpanded = true
    m.focusedRailIndex = m.selectedRailIndex
    m.focusArea = "rail"
    PorticoFocusRemember(m.focusMemory, m.route, priorSemanticId, m.navigationStore.viewerEpoch)
    PorticoRailOpen(m.railController, m.focusBeforeRail, false)
    PorticoFocusTraceRecord(m.focusTrace, "rail-open", m.navigationStore.routeEpoch, "navigation.rail")
    m.top.setFocus(true)
end sub

sub leaveRail()
    PorticoSceneRefreshFocusGraph()
    boundaryTarget = PorticoScreenAuthorityMoveBoundary(m.screenAuthority, "right", PorticoSceneSemanticFocusId())
    if boundaryTarget = "" then return
    m.railExpanded = false
    restored = PorticoRailClose(m.railController)
    if restored <> "" then m.focusBeforeRail = restored
    m.focusArea = m.focusBeforeRail
    recalledSemanticId = PorticoFocusRecall(m.focusMemory, m.route, m.navigationStore.viewerEpoch)
    if recalledSemanticId <> "" then PorticoFocusTraceRecord(m.focusTrace, "restore", m.navigationStore.routeEpoch, recalledSemanticId)
    focusActiveRoute()
end sub

sub openDetailFromHome()
    pushRoute("detail", -1, m.focusArea)
    m.focusArea = "routeActions"
    m.detailFocusedAction = 0
    m.focusedEpisode = 0
    resetDetailSecondaryFocus()
end sub

sub openDetailFromBrowse(targetId as dynamic)
    id = ""
    if targetId <> invalid then id = targetId.ToStr()
    if id = "" then return
    emitActivation("open-detail", id)
    pushRoute("detail", -1, m.focusArea)
    m.focusArea = "routeActions"
    m.detailFocusedAction = 0
    m.focusedEpisode = 0
    resetDetailSecondaryFocus()
end sub

sub resetDetailSecondaryFocus()
    m.detailFocusedPerson = 0
    m.detailFocusedPersonResult = 0
    m.detailFocusedRelationshipRow = 0
    m.detailFocusedRelationshipItem = 0
    m.detailFactsOpen = false
    m.detailMoreOpen = false
end sub

sub openPlayback(kind as string, targetId as dynamic, title as dynamic, meta as dynamic)
    id = ""
    if targetId <> invalid then id = targetId.ToStr()
    if id = "" then return
    titleValue = ""
    if title <> invalid then titleValue = title.ToStr()
    metaValue = ""
    if meta <> invalid then metaValue = meta.ToStr()
    m.playbackIdentity = {title: titleValue, meta: metaValue}
    pushRoute("player", -1, m.focusArea)
    m.focusArea = "player"
    m.railExpanded = false
    m.detailMoreOpen = false
    emitPlaybackActivation(kind, id, titleValue, metaValue)
end sub

sub openGlobalFeedback(initialKind as string, mediaId as dynamic)
    if not feedbackKindAvailable(initialKind) then return
    id = safeRuntimeLabel(mediaId, "", 128)
    m.feedbackInitialKind = initialKind
    m.feedbackContext = {}
    if id <> "" then m.feedbackContext.mediaId = id
    PorticoSceneRememberOverlayInvoker()
    m.feedbackOpen = true
end sub

sub activateRail()
    item = railItemAt(m.focusedRailIndex)
    if item = invalid then return
    route = item.route
    if route = invalid then route = item.id
    if not PorticoScenePublishActivation({
        kind: "route",
        targetId: item.id,
        route: route
    }) then return
    m.top.routeRequested = route
    PorticoRailSelect(m.railController, "route." + route)

    if route = m.route
        leaveRail()
    else if isTransientRoute(route)
        pushRoute(route, m.focusedRailIndex, m.focusBeforeRail)
    else
        selectPrimaryRoute(route, m.focusedRailIndex)
    end if
end sub

sub activateRouteAction()
    if m.route = "server-selection"
        m.focusArea = "serverActions"
        activateServerSelectionAction()
        return
    end if
    model = routeStateModel(m.route)
    if m.profileGateVisible then model = profileGateStateModel()
    if model.actions = invalid or m.routeFocusedAction < 0 or m.routeFocusedAction >= model.actions.count() then return
    action = model.actions[m.routeFocusedAction]
    if action.id = "open-settings"
        emitActivation(action.id, m.route)
        pushRoute("settings", railIndexForRoute("settings"), m.focusArea)
    else if action.id = "back-profile"
        emitActivation(action.id, m.route)
        navigateBack()
    else if action.id = "open-profile"
        emitActivation(action.id, m.route)
        if historyReturnsTo("profile")
            navigateBack()
        else
            pushRoute("profile", railIndexForRoute("profile"), m.focusArea)
        end if
    else if action.id = "open-server-selection"
        emitActivation(action.id, m.route)
        openInternalRoute("server-selection")
    else if action.id = "open-connection"
        emitActivation(action.id, m.route)
        openInternalRoute("connection")
    else if action.id = "refresh-home"
        emitActivation("refresh-home", "home")
    else if action.id = "retry-detail"
        emitActivation("open-detail", runtimeValue("detailMediaId", ""))
    else
        emitActivation(action.id, m.route)
    end if
end sub

sub activateServerSelectionAction()
    actions = serverSelectionActions()
    if m.routeFocusedAction < 0 or m.routeFocusedAction >= actions.count() then return
    action = actions[m.routeFocusedAction]
    if action.id = "refresh-servers"
        emitActivation("refresh-servers", "server-selection")
    else if action.id = "open-profile"
        emitActivation("open-profile", "server-selection")
        if historyReturnsTo("profile")
            navigateBack()
        else
            pushRoute("profile", railIndexForRoute("profile"), m.focusArea)
        end if
    end if
end sub

sub activateSelectedServer()
    servers = runtimeServers()
    if m.serverFocusedIndex < 0 or m.serverFocusedIndex >= servers.count() then return
    server = servers[m.serverFocusedIndex]
    emitActivation("select-server", server.id)
    openInternalRoute("connection")
end sub

sub activateHomeAction()
    hero = homeHeroModel()
    if hero = invalid then return
    actionIds = homeActionIds(activeHomeModel())
    if m.homeFocusedAction < 0 or m.homeFocusedAction >= actionIds.count() then return
    action = actionIds[m.homeFocusedAction]
    targetId = hero.id
    if action = "play"
        if hero.playbackMediaId <> invalid then targetId = hero.playbackMediaId
        playbackActivation = "play"
        if LCase(safeRuntimeLabel(hero.playbackKind, "vod", 16)) = "live" then playbackActivation = "play-live"
        openPlayback(playbackActivation, targetId, hero.title, hero.meta)
    else if action = "saved-toggle"
        emitActivation("saved-toggle", targetId)
    else if action = "open-detail"
        emitActivation("open-detail", targetId)
        openDetailFromHome()
    else if action = "favorite-toggle"
        emitActivation("favorite-toggle", targetId)
    end if
end sub

sub activateHomeCard()
    items = homeRowItems(m.homeFocusedRow)
    itemIndex = m.homeFocusedIndices[m.homeFocusedRow]
    if itemIndex < 0 or itemIndex >= items.count() then return
    item = items[itemIndex]
    emitActivation("open-detail", item.id)
    openDetailFromHome()
end sub

sub activateDetailAction()
    model = activeDetailModel()
    if model = invalid then return
    actionIds = detailActionIds(model)
    if m.detailFocusedAction < 0 or m.detailFocusedAction >= actionIds.count() then return
    action = actionIds[m.detailFocusedAction]
    targetId = model.id
    if action = "play"
        if model.playbackMediaId <> invalid then targetId = model.playbackMediaId
        playbackActivation = "play"
        if LCase(safeRuntimeLabel(model.playbackKind, "vod", 16)) = "live" then playbackActivation = "play-live"
        openPlayback(playbackActivation, targetId, model.title, model.meta)
    else if action = "play.from-beginning"
        if model.playbackMediaId <> invalid then targetId = model.playbackMediaId
        titleValue = safeRuntimeLabel(model.title, "", 180)
        metaValue = safeRuntimeLabel(model.meta, "", 180)
        m.playbackIdentity = {title: titleValue, meta: metaValue}
        pushRoute("player", -1, m.focusArea)
        m.focusArea = "player"
        m.railExpanded = false
        m.detailMoreOpen = false
        emitPlaybackActivation("play", targetId, titleValue, metaValue, 0)
    else if action = "saved-toggle"
        emitActivation("saved-toggle", targetId)
    else if action = "favorite-toggle"
        emitActivation("favorite-toggle", targetId)
    else if action = "watched-toggle"
        emitActivation("watched-toggle", targetId)
    else if action = "watch-with-friends.start"
        PorticoSceneRememberOverlayInvoker()
        m.watchWithFriendsContext = {mediaId: targetId, mediaTitle: safeRuntimeLabel(model.title, "", 180)}
        m.watchWithFriendsOpen = true
        emitActivation("watch-with-friends-refresh", targetId)
    else if action = "feedback.report-problem"
        openGlobalFeedback("media", targetId)
    else if action = "feedback.request-higher-quality"
        openGlobalFeedback("quality", targetId)
    else if action = "more"
        PorticoSceneRememberOverlayInvoker()
        m.detailMoreOpen = true
    end if
end sub

sub activateEpisode()
    episodes = detailEpisodes(activeDetailModel())
    if m.focusedEpisode < 0 or m.focusedEpisode >= episodes.count() then return
    openDetailFromBrowse(episodes[m.focusedEpisode].id)
end sub

sub activateDetailFocusedContent()
    model = activeDetailModel()
    if model = invalid then return
    if m.focusArea = "detailEpisodes"
        activateEpisode()
    else if m.focusArea = "detailSeason"
        PorticoSceneRememberOverlayInvoker()
        m.detailSeasonOpen = true
    else if m.focusArea = "detailPeople"
        people = detailPeople(model)
        if m.detailFocusedPerson < 0 or m.detailFocusedPerson >= people.count() then return
        person = people[m.detailFocusedPerson]
        emitForwardedActivation({kind: "select-person", targetId: person.id, personName: person.name})
    else if m.focusArea = "detailPersonResults"
        items = detailPersonResults(model)
        if items.count() > 0 and m.detailFocusedPersonResult >= 0 and m.detailFocusedPersonResult < items.count()
            openDetailFromBrowse(items[m.detailFocusedPersonResult].id)
        else
            status = LCase(safeRuntimeLabel(model.personStatus, "idle", 24))
            if status = "error" or status = "offline" then emitActivation("retry-person", model.selectedPersonId)
        end if
    else if Left(m.focusArea, 18) = "detailRelationship"
        rowIndex = detailRelationshipRowFromArea(m.focusArea)
        relationships = detailRelationships(model)
        if rowIndex < 0 or rowIndex >= relationships.count() then return
        items = sceneArray(relationships[rowIndex].items)
        if m.detailFocusedRelationshipItem >= 0 and m.detailFocusedRelationshipItem < items.count() then openDetailFromBrowse(items[m.detailFocusedRelationshipItem].id)
    else if m.focusArea = "detailFacts"
        m.detailFactsOpen = not m.detailFactsOpen
    end if
end sub

function PorticoSceneSemanticFocusId() as string
    if m.focusArea = "rail"
        railItem = railItemAt(m.focusedRailIndex)
        if railItem <> invalid then return "rail." + safeRuntimeLabel(railItem.id, railItem.route, 192)
        return "rail.unavailable"
    end if
    if m.route = "home"
        if m.homeScreen <> invalid and m.homeScreen.focusSemanticId <> "" then return m.homeScreen.focusSemanticId
        return "home.unavailable"
    end if
    if m.route = "detail"
        if m.detailScreen <> invalid and m.detailScreen.focusSemanticId <> "" then return m.detailScreen.focusSemanticId
        return "detail.unavailable"
    end if
    if m.focusArea = "serverList"
        servers = runtimeServers()
        if m.serverFocusedIndex >= 0 and m.serverFocusedIndex < servers.Count() then return "server.item." + safeRuntimeLabel(servers[m.serverFocusedIndex].id, "unknown", 128)
        return "server.item.unavailable"
    end if
    if m.focusArea = "routeActions" or m.focusArea = "serverActions"
        model = routeStateModel(m.route)
        if m.route = "server-selection" then model = {actions: serverSelectionActions()}
        if model <> invalid and model.actions <> invalid and m.routeFocusedAction >= 0 and m.routeFocusedAction < model.actions.Count() then return m.route + ".action." + safeRuntimeLabel(model.actions[m.routeFocusedAction].id, "unknown", 128)
        return m.route + ".action.unavailable"
    end if
    return m.route + ".focus." + m.focusArea
end function

function PorticoSceneActiveBackOverlayId() as string
    if m.feedbackOpen then return "feedback"
    if m.watchWithFriendsOpen then return "watch-with-friends"
    if m.detailSeasonOpen then return "detail-season"
    if m.detailMoreOpen then return "detail-more"
    if m.homeCustomizeOpen then return "home-customize"
    return ""
end function

sub PorticoSceneRememberOverlayInvoker()
    m.overlayInvokerFocusId = PorticoSceneSemanticFocusId()
    PorticoFocusRemember(m.focusMemory, m.route + ".overlay-invoker", m.overlayInvokerFocusId, m.navigationStore.viewerEpoch)
    PorticoFocusTraceRecord(m.focusTrace, "modal-open", m.navigationStore.routeEpoch, m.overlayInvokerFocusId)
end sub

sub PorticoSceneCloseBackOverlay(overlayId as string)
    if overlayId = "feedback"
        m.feedbackOpen = false
        PorticoSceneSetVisible(m.globalFeedbackOverlay, false)
    else if overlayId = "watch-with-friends"
        m.watchWithFriendsOpen = false
        PorticoSceneSetVisible(m.watchWithFriendsOverlay, false)
    else if overlayId = "detail-season"
        m.detailSeasonOpen = false
        PorticoSceneSetVisible(m.detailSeasonOverlay, false)
    else if overlayId = "detail-more"
        m.detailMoreOpen = false
        PorticoSceneSetVisible(m.detailMoreScreen, false)
    else if overlayId = "home-customize"
        m.homeCustomizeOpen = false
        PorticoSceneSetVisible(m.homeCustomizeOverlay, false)
    end if
    restoredId = m.overlayInvokerFocusId
    if restoredId = "" then restoredId = PorticoFocusRecall(m.focusMemory, m.route + ".overlay-invoker", m.navigationStore.viewerEpoch)
    if restoredId <> "" then PorticoFocusTraceRecord(m.focusTrace, "modal-close", m.navigationStore.routeEpoch, restoredId)
    m.overlayInvokerFocusId = ""
    focusActiveRoute()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        if key = "OK" then PorticoActivationRelease(m.activationTransactions)
        return false
    end if

    PorticoSceneRefreshFocusGraph()

    if key = "OK"
        PorticoFocusContainerReplace(m.sceneFocusContainer, [PorticoSceneSemanticFocusId()])
        transaction = PorticoActivationBegin(m.activationTransactions, PorticoFocusContainerCurrent(m.sceneFocusContainer), "ok", m.navigationStore.viewerEpoch, m.navigationStore.routeEpoch)
        if transaction = invalid then return true
        PorticoFocusTraceRecord(m.focusTrace, "activate", m.navigationStore.routeEpoch, transaction.semanticId)
    end if

    if m.profileGateVisible
        model = profileGateStateModel()
        if key = "back"
            emitActivation("cancel-profile-selection", "profile-state")
            replaceWithServerSelection()
        else if key = "left" and m.routeFocusedAction > 0
            m.routeFocusedAction = m.routeFocusedAction - 1
        else if key = "right" and model.actions <> invalid and m.routeFocusedAction + 1 < model.actions.Count()
            m.routeFocusedAction = m.routeFocusedAction + 1
        else if key = "OK"
            activateRouteAction()
        end if
        renderScene()
        return true
    end if

    if m.globalNoticeFocused
        if key = "back"
            restoreFocusAfterGlobalNotice()
            renderScene()
        end if
        return true
    end if

    settingsModalOpen = false
    if m.settingsScreen <> invalid then settingsModalOpen = m.settingsScreen.modalOpen = true
    if key = "options" and PorticoSceneIsVisible(m.globalImportantNotice) and not m.feedbackOpen and not m.watchWithFriendsOpen and not m.detailSeasonOpen and not m.detailMoreOpen and not m.homeCustomizeOpen and not settingsModalOpen
        focusGlobalImportantNotice()
        renderScene()
        return true
    end if

    if key = "options" and m.route = "home" and activeHomeModel() <> invalid
        customization = activeHomeModel().homeCustomization
        if customization <> invalid
            PorticoSceneRememberOverlayInvoker()
            m.homeCustomizeOpen = true
            renderScene()
            return true
        end if
    end if

    if key = "back"
        if not accountIsSignedIn()
            emitActivation("exit-channel", "root-back")
            return true
        end if
        decision = PorticoBackResolve(m.backCoordinator, {
            overlayId: PorticoSceneActiveBackOverlayId(),
            panelId: "",
            hasHistory: m.navigationStore.history.Count() > 0,
            railExpanded: m.railExpanded,
            railOpenedByRootBack: m.railController.openedByRootBack
        })
        if decision.kind = "close-overlay"
            PorticoSceneCloseBackOverlay(decision.targetId)
        else if decision.kind = "route-back"
            navigateBack()
        else if decision.kind = "open-rail"
            m.focusBeforeRail = m.focusArea
            m.railExpanded = true
            m.focusedRailIndex = m.selectedRailIndex
            m.focusArea = "rail"
            PorticoRailOpen(m.railController, m.focusBeforeRail, true)
            PorticoFocusTraceRecord(m.focusTrace, "root-back-rail", m.navigationStore.routeEpoch, "navigation.rail")
        else if decision.kind = "close-rail"
            leaveRail()
        else if decision.kind = "exit-channel"
            emitActivation("exit-channel", "root-back")
        end if
        renderScene()
        return true
    end if

    if key = "left"
        if m.focusArea = "rail"
            return true
        else if m.focusArea = "serverList"
            return true
        else if m.focusArea = "serverClose"
            return true
        else if m.focusArea = "serverActions"
            if m.routeFocusedAction > 0
                m.routeFocusedAction = m.routeFocusedAction - 1
            end if
        else if m.focusArea = "routeActions"
            if m.routeFocusedAction > 0
                m.routeFocusedAction = m.routeFocusedAction - 1
            else
                enterRail()
            end if
        else if m.focusArea = "homeActions"
            if m.homeFocusedAction > 0
                m.homeFocusedAction = m.homeFocusedAction - 1
            else
                enterRail()
            end if
        else if m.focusArea = "homeRows"
            rowIndex = m.homeFocusedRow
            if m.homeFocusedIndices[rowIndex] > 0
                m.homeFocusedIndices[rowIndex] = m.homeFocusedIndices[rowIndex] - 1
                m.homeHeroIndex = m.homeFocusedIndices[rowIndex]
            else
                enterRail()
            end if
        else if Left(m.focusArea, 6) = "detail"
            moveDetailHorizontal(-1)
        else if m.focusArea = "search" or m.focusArea = "library" or m.focusArea = "saved" or m.focusArea = "channels" or m.focusArea = "profile" or m.focusArea = "settings"
            enterRail()
        end if
        renderScene()
        return true
    end if

    if key = "right"
        if m.focusArea = "rail"
            leaveRail()
        else if m.focusArea = "serverList"
            return true
        else if m.focusArea = "serverClose"
            return true
        else if m.focusArea = "serverActions"
            actionCount = serverSelectionActionCount()
            if m.routeFocusedAction < actionCount - 1 then m.routeFocusedAction = m.routeFocusedAction + 1
        else if m.focusArea = "routeActions"
            count = activeRouteActionCount()
            if m.routeFocusedAction < count - 1 then m.routeFocusedAction = m.routeFocusedAction + 1
        else if m.focusArea = "homeActions"
            actionCount = homeActionIds(activeHomeModel()).count()
            if m.homeFocusedAction < actionCount - 1 then m.homeFocusedAction = m.homeFocusedAction + 1
        else if m.focusArea = "homeRows"
            rowIndex = m.homeFocusedRow
            items = homeRowItems(rowIndex)
            if m.homeFocusedIndices[rowIndex] < items.count() - 1
                m.homeFocusedIndices[rowIndex] = m.homeFocusedIndices[rowIndex] + 1
                m.homeHeroIndex = m.homeFocusedIndices[rowIndex]
            else
                rows = homeRows(activeHomeModel())
                if rowIndex >= 0 and rowIndex < rows.count() and rows[rowIndex].hasMore = true
                    emitActivation("load-more-home-row", rows[rowIndex].id)
                end if
            end if
        else if Left(m.focusArea, 6) = "detail"
            moveDetailHorizontal(1)
        end if
        renderScene()
        return true
    end if

    if key = "down"
        if m.focusArea = "rail"
            if m.focusedRailIndex < railItemCount() - 1 then m.focusedRailIndex = m.focusedRailIndex + 1
        else if m.focusArea = "serverClose"
            if runtimeServers().count() > 0
                m.focusArea = "serverList"
            else
                m.focusArea = "serverActions"
                m.routeFocusedAction = 0
            end if
        else if m.focusArea = "serverList"
            servers = runtimeServers()
            if m.serverFocusedIndex < servers.count() - 1
                m.serverFocusedIndex = m.serverFocusedIndex + 1
                clampServerSelectionFocus()
            else
                m.focusArea = "serverActions"
                m.routeFocusedAction = 0
            end if
        else if m.focusArea = "serverActions"
            return true
        else if m.focusArea = "routeActions"
            return true
        else if m.focusArea = "homeActions"
            firstRow = firstHomeRowIndex(activeHomeModel())
            if firstRow >= 0
                m.focusArea = "homeRows"
                m.homeFocusedRow = firstRow
                m.homeHeroIndex = m.homeFocusedIndices[firstRow]
            end if
        else if m.focusArea = "homeRows"
            nextRow = nextHomeRowIndex(m.homeFocusedRow)
            m.homeFocusedRow = nextRow
        else if Left(m.focusArea, 6) = "detail"
            moveDetailVertical(1)
        end if
        renderScene()
        return true
    end if

    if key = "up"
        if m.focusArea = "rail"
            if m.focusedRailIndex > 0 then m.focusedRailIndex = m.focusedRailIndex - 1
        else if m.focusArea = "serverClose"
            return true
        else if m.focusArea = "serverList"
            if m.serverFocusedIndex > 0
                m.serverFocusedIndex = m.serverFocusedIndex - 1
                clampServerSelectionFocus()
            else
                m.focusArea = "serverClose"
            end if
        else if m.focusArea = "serverActions"
            if serverSelectionListReady() and runtimeServers().count() > 0
                m.focusArea = "serverList"
            else
                m.focusArea = "serverClose"
            end if
        else if m.focusArea = "routeActions"
            if m.route = "server-selection"
                if serverSelectionListReady()
                    m.focusArea = "serverList"
                else
                    m.focusArea = "serverClose"
                end if
            end if
            return true
        else if m.focusArea = "homeRows"
            previousRow = previousHomeRowIndex(m.homeFocusedRow)
            if previousRow <> m.homeFocusedRow
                m.homeFocusedRow = previousRow
                m.homeHeroIndex = m.homeFocusedIndices[previousRow]
            else if homeActionIds(activeHomeModel()).count() > 0 and homeHeroModel() <> invalid
                m.focusArea = "homeActions"
            end if
        else if Left(m.focusArea, 6) = "detail"
            moveDetailVertical(-1)
        end if
        renderScene()
        return true
    end if

    if key = "OK"
        if m.focusArea = "rail"
            activateRail()
        else if m.focusArea = "serverClose"
            navigateBack()
        else if m.focusArea = "serverList"
            activateSelectedServer()
        else if m.focusArea = "serverActions"
            activateServerSelectionAction()
        else if m.focusArea = "routeActions"
            activateRouteAction()
        else if m.focusArea = "homeActions"
            activateHomeAction()
        else if m.focusArea = "homeRows"
            activateHomeCard()
        else if m.focusArea = "detailActions"
            activateDetailAction()
        else if Left(m.focusArea, 6) = "detail"
            activateDetailFocusedContent()
        end if
        renderScene()
        return true
    end if

    return false
end function
