sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    lifecycle = PorticoLifecycleController(args)
    input = CreateObject("roInput")
    if input <> invalid then input.SetMessagePort(port)

    scene = screen.CreateScene("PorticoScene")
    initialAuthMode = PorticoMainInitialAuthMode()
    #if visual_fixture
    scene.visualContract = ParseJson(ReadAsciiFile("pkg:/data/visual-contract.json"))
    #else
    scene.visualContract = ParseJson(ReadAsciiFile("pkg:/data/runtime-ui-contract.json"))
    #end if
    scene.runtimeState = {
        authMode: initialAuthMode,
        accountStatus: "signed-out",
        hostedStatus: "unknown",
        serverListStatus: "signed-out",
        availableServers: [],
        serverStatus: "not-connected",
        selectedServerId: "",
        selectedServerName: "Portico Server",
        viewerStatus: "unavailable",
        viewerGeneration: 1,
        viewerAcceptingWrites: false,
        viewerTransitionReason: "startup",
        profileDirectoryStatus: "idle",
        profileDirectory: [],
        profileSelectionOverlay: false,
        selectedProfileId: "",
        selectedProfileName: "",
        preferencesStatus: "idle",
        preferenceRevisions: {},
        productContractStatus: "idle",
        productContractRevision: "",
        productLanguageRevision: "v1",
        navigationSnapshotVerified: false,
        libraryItems: [],
        homeStatus: "idle",
        detailStatus: "idle",
        detailMediaId: "",
        searchViewState: {status: "idle", query: "", queryRevision: 0, groups: []},
        libraryViewState: invalid,
        savedViewState: invalid,
        savedMutationError: invalid,
        channelsViewState: invalid,
        playbackViewState: invalid,
        watchWithFriendsViewState: invalid,
        engagementViewState: invalid
    }
    viewerRuntime = PorticoViewerRuntimeController(scene)
    PorticoMainMergeRuntimeState(scene, PorticoViewerRuntimeControllerInitialState(viewerRuntime))
    ' Start rendering before long-lived background controllers are initialized.
    ' Their component types are registered by the non-visual Scene anchors.
    screen.Show()
    scene.ObserveField("activation", port)
    scene.ObserveField("externalRequestAcknowledgement", port)
    scene.ObserveField("accountRefreshRequested", port)
    accountAuthorization = PorticoDeviceAuthorizationController(scene, port)
    PorticoDeviceAuthorizationCommand(accountAuthorization, "start-account-setup")
    localAuth = PorticoLocalAuthController(scene, port)
    serverCatalog = PorticoServerCatalogController(scene, port)
    serverConnection = PorticoServerConnectionController(scene, port)
    ' Discovery domains start envelope-bound. Before an exact viewer scope is
    ' active their commands fail closed and their legacy projections are ignored.
    content = PorticoContentController(scene, port, viewerRuntime)
    search = PorticoSearchController(scene, port, viewerRuntime)
    library = PorticoLibraryController(scene, port, viewerRuntime)
    saved = PorticoSavedController(scene, port, viewerRuntime)
    liveTv = PorticoLiveTvController(scene, port, viewerRuntime)
    playback = PorticoPlaybackController(port, viewerRuntime)
    watchWithFriends = PorticoWatchWithFriendsController(port, viewerRuntime)
    engagement = PorticoEngagementController(port, viewerRuntime)
    m.porticoWatchWithFriendsController = watchWithFriends
    m.porticoEngagementController = engagement
    applicationEvents = PorticoApplicationEventsController(port, viewerRuntime)
    playbackEvents = PorticoPlaybackEventsController(port, viewerRuntime)
    m.porticoApplicationEventsController = applicationEvents
    m.porticoPlaybackEventsController = playbackEvents
    ' Realtime invalidations are retained for inactive destinations instead of
    ' waking every discovery Task. The active surface reconciles immediately;
    ' a hidden surface performs one latest-wins refresh when it becomes active.
    m.porticoPendingInvalidations = {}
    m.porticoPlaybackPresentationSequence = 0
    profiles = PorticoProfileController(scene, port)
    viewerPreferences = PorticoViewerPreferencesController(scene, port)
    PorticoLocalAuthViewerStateChanged(localAuth, viewerRuntime.runtime.generationSequence)
    if not PorticoMainUsesLocalAuth(scene.runtimeState)
        PorticoServerCatalogAccountStateChanged(serverCatalog, scene.runtimeState)
        PorticoServerConnectionAccountStateChanged(serverConnection, scene.runtimeState)
    end if
    ' Send restore last because Task command fields are latest-value mailboxes.
    PorticoServerConnectionInitialize(serverConnection, viewerRuntime.runtime.generationSequence)
    PorticoMainReconcileViewerFoundation(viewerRuntime, profiles, viewerPreferences, localAuth, serverConnection, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
    PorticoMainSynchronizeViewerDomains(viewerRuntime, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
    PorticoMainSynchronizeApplicationEvents(viewerRuntime, scene, applicationEvents)
    PorticoMainSynchronizePlaybackEvents(viewerRuntime, scene, playbackEvents)
    PorticoMainRetryApplicationEventReset(applicationEvents, viewerRuntime, scene, content, search, library, saved, liveTv, profiles, viewerPreferences)
    PorticoLifecycleReconcile(lifecycle, scene)
    PorticoLifecycleUpdateBeacons(lifecycle, scene, invalid)
    while true
        message = wait(200, port)
        if type(message) = "roSGScreenEvent" and message.IsScreenClosed()
            PorticoLifecycleRememberPage(lifecycle, scene.page, scene.runtimeState)
            PorticoWatchWithFriendsTransitionFence(watchWithFriends)
            if watchWithFriends.task <> invalid then watchWithFriends.task.control = "STOP"
            PorticoEngagementCancel(engagement)
            if engagement.task <> invalid then engagement.task.control = "STOP"
            PorticoApplicationEventsTransitionFence(applicationEvents)
            if applicationEvents.task <> invalid then applicationEvents.task.control = "STOP"
            PorticoPlaybackEventsCancel(playbackEvents)
            if playbackEvents.task <> invalid then playbackEvents.task.control = "STOP"
            PorticoPlaybackShutdown(playback, port, 3500)
            return
        end if
        if type(message) = "roInputEvent" and message.IsInput()
            PorticoLifecycleAcceptInput(lifecycle, message.GetInfo())
            PorticoLifecycleReconcile(lifecycle, scene)
            PorticoLifecycleUpdateBeacons(lifecycle, scene, invalid)
        end if
        if type(message) = "roSGNodeEvent"
            field = message.GetField()
            if field = "externalRequestAcknowledgement"
                ' Scene publishes this only after validating and consuming the
                ' external request. Gate deliveries are valid before viewer
                ' publication; keep their acknowledgement separate from the
                ' ordinary activation path.
                PorticoLifecycleAcknowledgeDispatch(lifecycle, message.GetData())
                PorticoLifecycleReconcile(lifecycle, scene)
                PorticoLifecycleUpdateBeacons(lifecycle, scene, invalid)
            else if field = "activation"
                activationData = message.GetData()
                if activationData <> invalid and Type(activationData) = "roAssociativeArray"
                    if LCase(PorticoHttpScalarString(activationData.kind, "")) = "exit-channel"
                        screen.Close()
                    end if
                    PorticoLifecycleRememberActivation(lifecycle, activationData, scene.runtimeState)
                    PorticoMainBeginAuthoritySwitch(activationData, viewerRuntime, profiles, viewerPreferences, localAuth, serverConnection, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                    PorticoLocalAuthHandleActivation(localAuth, activationData)
                    PorticoMainApplyAuthActivation(scene, activationData)
                    PorticoProfileControllerHandleActivation(profiles, activationData)
                    PorticoViewerPreferencesControllerHandleActivation(viewerPreferences, activationData)
                    localActivation = PorticoProfileControllerTakeLocalActivation(profiles)
                    if localActivation <> invalid then PorticoServerConnectionActivateLocalProfile(serverConnection, localActivation)
                    if LCase(PorticoHttpScalarString(activationData.kind, "")) = "retry-profile-directory"
                        if profiles.context = invalid or profiles.context.authority = "local" then PorticoMainReconnect(scene, localAuth, serverConnection)
                    end if
                    if LCase(PorticoHttpScalarString(activationData.kind, "")) = "save-home-customization" and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                        expectedRevision = PorticoHttpInteger(activationData.expectedRevision, -1)
                        changes = {home: {rowOrder: activationData.rowOrder, hiddenRowIds: activationData.hiddenRowIds}}
                        PorticoViewerPreferencesControllerPatch(viewerPreferences, "profile-server", expectedRevision, changes)
                    end if
                end if
                PorticoDeviceAuthorizationHandleActivation(accountAuthorization, activationData)
                if not PorticoMainUsesLocalAuth(scene.runtimeState)
                    PorticoServerCatalogHandleActivation(serverCatalog, activationData)
                    PorticoServerConnectionHandleActivation(serverConnection, activationData, scene.runtimeState)
                end if
                if PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                    PorticoContentHandleActivation(content, activationData)
                    PorticoSearchHandleActivation(search, activationData)
                    PorticoLibraryHandleActivation(library, activationData)
                    PorticoSavedHandleActivation(saved, activationData)
                    PorticoLiveTvHandleActivation(liveTv, activationData)
                end if
                if activationData <> invalid and Type(activationData) = "roAssociativeArray" and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                    activationKind = LCase(PorticoHttpScalarString(activationData.kind, ""))
                    playbackPlayerResult = PorticoPlaybackHandlePlayerEvent(playback, activationData)
                    PorticoWatchWithFriendsHandlePlayerEvent(watchWithFriends, activationData)
                    if playbackPlayerResult.watchLoad <> invalid
                        watchLoad = playbackPlayerResult.watchLoad
                        PorticoPlaybackSetIdentity(playback, {
                            title: PorticoHttpScalarString(activationData.title, ""),
                            meta: PorticoHttpScalarString(activationData.meta, "")
                        })
                        PorticoMainMergeRuntimeState(scene, {
                            playbackViewState: {
                                playbackStatus: "preparing",
                                playbackErrorCode: "",
                                playbackGeneration: 0,
                                sourceGeneration: 0,
                                identity: PorticoPlaybackIdentity(playback)
                            }
                        })
                        PorticoPlaybackStartTargetCommand(playback, PorticoHttpScalarString(scene.runtimeState.selectedServerId, ""), "vod", watchLoad.targetId, watchLoad.positionSeconds)
                    end if
                    if activationKind = "route"
                        requestedRoute = PorticoHttpScalarString(activationData.route, "")
                        if requestedRoute = "library"
                            PorticoLibraryOpen(library, "")
                        else if Left(requestedRoute, 8) = "library/"
                            PorticoLibraryOpen(library, Mid(requestedRoute, 9))
                        end if
                    else if activationKind = "play" or PorticoLiveTvPlaybackTarget(activationData) <> invalid
                        targetKind = "vod"
                        targetId = PorticoHttpScalarString(activationData.targetId, "")
                        channelTarget = PorticoLiveTvPlaybackTarget(activationData)
                        if channelTarget <> invalid
                            targetKind = channelTarget.targetKind
                            targetId = channelTarget.targetId
                        end if
                        PorticoPlaybackSetIdentity(playback, {
                            title: PorticoHttpScalarString(activationData.title, ""),
                            meta: PorticoHttpScalarString(activationData.meta, "")
                        })
                        PorticoMainMergeRuntimeState(scene, {
                            playbackViewState: {
                                playbackStatus: "preparing",
                                playbackErrorCode: "",
                                playbackGeneration: 0,
                                sourceGeneration: 0,
                                identity: PorticoPlaybackIdentity(playback)
                            }
                        })
                        startSeconds = invalid
                        if activationData.startSeconds <> invalid then startSeconds = PorticoHttpInteger(activationData.startSeconds, 0)
                        PorticoPlaybackStartTargetCommand(playback, PorticoHttpScalarString(scene.runtimeState.selectedServerId, ""), targetKind, targetId, startSeconds)
                    else if activationKind = "preferences-changed"
                        PorticoPlaybackPreferencesChangedCommand(playback)
                    else if activationKind = "watch-with-friends-refresh"
                        PorticoWatchWithFriendsRefreshCommand(watchWithFriends)
                    else if activationKind = "watch-with-friends-overlay-action"
                        PorticoWatchWithFriendsHandleOverlayAction(watchWithFriends, activationData.overlayAction)
                    else if activationKind = "dismiss-notification"
                        PorticoEngagementDismissNotice(engagement, activationData.notificationId, activationData.expectedRevision)
                    else if activationKind = "submit-feedback"
                        PorticoEngagementSubmitFeedback(engagement, activationData.feedbackKind, activationData.category, activationData)
                    end if
                end if
                PorticoLifecycleReconcile(lifecycle, scene)
                PorticoLifecycleUpdateBeacons(lifecycle, scene, activationData)
            else if field = "accountRefreshRequested"
                if message.GetData() = true and not PorticoMainUsesLocalAuth(scene.runtimeState) then PorticoDeviceAuthorizationRequestRefresh(accountAuthorization)
            else if field = "projection" or field = "projectionEnvelope" or field = "contentNode"
                sourceNode = message.GetRoSGNode()
                if sourceNode <> invalid and localAuth.task <> invalid and sourceNode.IsSameNode(localAuth.task)
                    PorticoLocalAuthHandleNodeEvent(localAuth, message)
                    PorticoMainReconcileViewerFoundation(viewerRuntime, profiles, viewerPreferences, localAuth, serverConnection, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                    localHandoff = PorticoLocalAuthTakeProfileHandoff(localAuth)
                    if localHandoff <> invalid
                        PorticoProfileControllerAdoptLocalHandoff(profiles, localHandoff)
                        localActivation = PorticoProfileControllerTakeLocalActivation(profiles)
                        if localActivation <> invalid then PorticoServerConnectionActivateLocalProfile(serverConnection, localActivation)
                    end if
                    PorticoMainSynchronizeViewerDomains(viewerRuntime, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                else if sourceNode <> invalid and accountAuthorization.task <> invalid and sourceNode.IsSameNode(accountAuthorization.task) and not PorticoMainUsesLocalAuth(scene.runtimeState)
                    PorticoDeviceAuthorizationHandleNodeEvent(accountAuthorization, message)
                    PorticoMainApplyAccountAuthMode(scene)
                    if not PorticoMainUsesLocalAuth(scene.runtimeState)
                        PorticoServerCatalogAccountStateChanged(serverCatalog, scene.runtimeState)
                        PorticoServerConnectionAccountStateChanged(serverConnection, scene.runtimeState)
                        PorticoMainPrepareHostedContext(viewerRuntime, serverConnection, scene.runtimeState)
                    end if
                    PorticoMainReconcileViewerFoundation(viewerRuntime, profiles, viewerPreferences, localAuth, serverConnection, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                    PorticoMainSynchronizeViewerDomains(viewerRuntime, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                else if sourceNode <> invalid and serverCatalog.task <> invalid and sourceNode.IsSameNode(serverCatalog.task) and not PorticoMainUsesLocalAuth(scene.runtimeState)
                    PorticoServerCatalogHandleNodeEvent(serverCatalog, message)
                    PorticoServerConnectionAccountStateChanged(serverConnection, scene.runtimeState)
                    PorticoMainPrepareHostedContext(viewerRuntime, serverConnection, scene.runtimeState)
                    PorticoMainReconcileViewerFoundation(viewerRuntime, profiles, viewerPreferences, localAuth, serverConnection, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                    PorticoMainSynchronizeViewerDomains(viewerRuntime, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                else if sourceNode <> invalid and serverConnection.task <> invalid and sourceNode.IsSameNode(serverConnection.task)
                    if PorticoServerConnectionHandleNodeEvent(serverConnection, message) and not PorticoMainUsesLocalAuth(scene.runtimeState)
                        PorticoDeviceAuthorizationRequestRefresh(accountAuthorization)
                    end if
                    PorticoMainFenceServerAuthorityLoss(viewerRuntime, profiles, viewerPreferences, localAuth, serverConnection, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                    PorticoMainReconcileViewerFoundation(viewerRuntime, profiles, viewerPreferences, localAuth, serverConnection, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                    PorticoMainAdvanceViewerAssertion(viewerRuntime, serverConnection, profiles, viewerPreferences, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                    PorticoMainSynchronizeViewerDomains(viewerRuntime, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                else if sourceNode <> invalid and profiles.task <> invalid and sourceNode.IsSameNode(profiles.task)
                    profileResult = PorticoProfileControllerHandleProjection(profiles, message)
                    if profileResult.activationRequired = true
                        hostedActivation = PorticoProfileControllerTakeHandoff(profiles)
                        if hostedActivation <> invalid then PorticoServerConnectionActivateHostedProfile(serverConnection, hostedActivation)
                    end if
                else if sourceNode <> invalid and viewerPreferences.task <> invalid and sourceNode.IsSameNode(viewerPreferences.task)
                    preferenceResult = PorticoViewerPreferencesControllerHandleProjection(viewerPreferences, message, viewerRuntime)
                    if preferenceResult.accepted = true
                        if scene.runtimeState.viewerPreferences <> invalid then PorticoPlaybackViewerPreferencesChanged(playback, {values: scene.runtimeState.viewerPreferences})
                        PorticoMainSynchronizeViewerDomains(viewerRuntime, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
                    end if
                else if sourceNode <> invalid and content.task <> invalid and sourceNode.IsSameNode(content.task)
                    if field = "projectionEnvelope" and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                        contentReconnectRequired = PorticoContentHandleNodeEvent(content, message, viewerRuntime)
                        PorticoSavedSynchronizeContentInvalidation(saved, scene.runtimeState)
                        PorticoLibrarySynchronizeContentInvalidation(library, scene.runtimeState)
                        if contentReconnectRequired
                            PorticoMainReconnect(scene, localAuth, serverConnection)
                        end if
                    end if
                else if sourceNode <> invalid and search.task <> invalid and sourceNode.IsSameNode(search.task)
                    if field = "projectionEnvelope" and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                        if PorticoSearchHandleNodeEvent(search, message, viewerRuntime)
                            PorticoMainReconnect(scene, localAuth, serverConnection)
                        end if
                    end if
                else if sourceNode <> invalid and library.task <> invalid and sourceNode.IsSameNode(library.task)
                    if field = "projectionEnvelope" and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                        if PorticoLibraryHandleNodeEvent(library, message, viewerRuntime)
                            PorticoMainReconnect(scene, localAuth, serverConnection)
                        end if
                    end if
                else if sourceNode <> invalid and saved.task <> invalid and sourceNode.IsSameNode(saved.task)
                    if field = "projectionEnvelope" and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                        previousResolutionToken = PorticoMainSavedResolutionToken(scene.runtimeState)
                        savedReconnectRequired = PorticoSavedHandleNodeEvent(saved, message, viewerRuntime)
                        nextResolutionToken = PorticoMainSavedResolutionToken(scene.runtimeState)
                        if nextResolutionToken <> "" and nextResolutionToken <> previousResolutionToken
                            ' Reconstruct from the already accepted runtime projection.
                            ' Never propagate the Task's raw, pre-scope-check envelope.
                            acceptedSavedProjection = {savedMutationResult: scene.runtimeState.savedMutationResolution}
                            PorticoContentSynchronizeSavedMutation(content, scene.runtimeState, acceptedSavedProjection)
                            PorticoSearchSynchronizeSavedMutation(search, scene.runtimeState, acceptedSavedProjection)
                            PorticoLibrarySynchronizeSavedMutation(library, scene.runtimeState, acceptedSavedProjection)
                        end if
                        if savedReconnectRequired
                            PorticoMainReconnect(scene, localAuth, serverConnection)
                        end if
                    end if
                else if sourceNode <> invalid and liveTv.task <> invalid and sourceNode.IsSameNode(liveTv.task) and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                    liveTvReconnectRequired = PorticoLiveTvHandleNodeEvent(liveTv, message, viewerRuntime)
                    PorticoLibrarySynchronizeDvrInvalidation(library, scene.runtimeState)
                    if liveTvReconnectRequired
                        PorticoMainReconnect(scene, localAuth, serverConnection)
                    end if
                else if sourceNode <> invalid and playback.task <> invalid and sourceNode.IsSameNode(playback.task) and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                    playbackResult = PorticoPlaybackHandleNodeEvent(playback, message)
                    if playbackResult.privateEventStateChanged = true and playbackResult.privateEventState <> invalid
                        eventState = playbackResult.privateEventState
                        if eventState.active
                            PorticoPlaybackEventsSetActiveSession(playbackEvents, eventState.sessionId, eventState.playbackGeneration)
                        else if playbackEvents.activePlaybackGeneration > 0 and eventState.playbackGeneration = playbackEvents.activePlaybackGeneration
                            PorticoPlaybackEventsClearActiveSession(playbackEvents, eventState.playbackGeneration)
                        end if
                    end if
                    if playbackResult.privateContentChanged = true
                        playerNode = scene.FindNode("playerScreen")
                        if playerNode <> invalid then playerNode.privateContent = playbackResult.privateContent
                    end if
                    if playbackResult.reconnectRequired
                        PorticoMainReconnect(scene, localAuth, serverConnection)
                    end if
                    if playbackResult.projection <> invalid
                        PorticoContentSynchronizePlayback(content, playbackResult.projection)
                        playbackResult.projection.identity = PorticoPlaybackIdentity(playback)
                        PorticoMainMergeRuntimeState(scene, {playbackViewState: playbackResult.projection})
                    end if
                else if sourceNode <> invalid and watchWithFriends.task <> invalid and sourceNode.IsSameNode(watchWithFriends.task) and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                    watchResult = PorticoWatchWithFriendsHandleNodeEvent(watchWithFriends, message)
                    if watchResult.projection <> invalid
                        watchProjection = watchResult.projection
                        playerNode = scene.FindNode("playerScreen")
                        if playerNode <> invalid
                            playerNode.watchGroupState = watchProjection
                            playerNode.watchSyncDirective = watchProjection.syncDirective
                        end if
                        if watchWithFriends.lastPublishedAuthority = invalid or watchWithFriends.lastPublishedAuthority <> watchProjection.authority
                            watchWithFriends.lastPublishedAuthority = watchProjection.authority
                            PorticoPlaybackWatchAuthorityChanged(playback, watchProjection.authority)
                        end if
                        PorticoMainMergeRuntimeState(scene, {watchWithFriendsViewState: watchProjection})
                    end if
                else if sourceNode <> invalid and engagement.task <> invalid and sourceNode.IsSameNode(engagement.task) and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                    engagementResult = PorticoEngagementHandleNodeEvent(engagement, message)
                    if engagementResult.projection <> invalid then PorticoMainMergeRuntimeState(scene, {engagementViewState: engagementResult.projection})
                else if sourceNode <> invalid and applicationEvents.task <> invalid and sourceNode.IsSameNode(applicationEvents.task) and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                    applicationEventResult = PorticoApplicationEventsHandleNodeEvent(applicationEvents, message)
                    if applicationEventResult.directive <> invalid
                        dispatched = PorticoMainDispatchApplicationEventDirective(applicationEventResult.directive, viewerRuntime, scene, content, search, library, saved, liveTv, profiles, viewerPreferences)
                        if dispatched and applicationEventResult.directive.kind = "reset-domains"
                            if PorticoApplicationEventsAcknowledgeReset(applicationEvents, applicationEventResult.directive.ackToken) then applicationEvents.projection.directive = invalid
                        else if not dispatched and applicationEventResult.directive.kind = "reset-domains"
                            applicationEvents.nextResetDispatchAt = PorticoMainEpochSeconds() + 2
                        end if
                    end if
                else if sourceNode <> invalid and playbackEvents.task <> invalid and sourceNode.IsSameNode(playbackEvents.task) and PorticoViewerRuntimeAccepting(viewerRuntime.runtime)
                    playbackEventResult = PorticoPlaybackEventsHandleNodeEvent(playbackEvents, message)
                    if playbackEventResult.directive <> invalid
                        if PorticoMainDispatchPlaybackEventDirective(playbackEventResult.directive, playbackEvents, playback, scene)
                            PorticoPlaybackEventsAcknowledgeDirective(playbackEvents, playbackEventResult.directive.ackToken)
                        end if
                    end if
                end if
                PorticoLifecycleReconcile(lifecycle, scene)
                PorticoLifecycleUpdateBeacons(lifecycle, scene, invalid)
            end if
        end if
        PorticoMainSynchronizeApplicationEvents(viewerRuntime, scene, applicationEvents)
        PorticoMainSynchronizePlaybackEvents(viewerRuntime, scene, playbackEvents)
        PorticoMainRetryApplicationEventReset(applicationEvents, viewerRuntime, scene, content, search, library, saved, liveTv, profiles, viewerPreferences)
        PorticoMainFlushActiveInvalidations(viewerRuntime, scene, content, search, library, saved, liveTv, profiles, viewerPreferences)
    end while
end sub

sub PorticoMainRetryApplicationEventReset(applicationEvents as object, viewerController as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, profiles as object, viewerPreferences as object)
    if applicationEvents = invalid or applicationEvents.projection = invalid or Type(applicationEvents.projection) <> "roAssociativeArray" then return
    directive = applicationEvents.projection.directive
    if directive = invalid or Type(directive) <> "roAssociativeArray" or directive.kind <> "reset-domains" then return
    now = PorticoMainEpochSeconds()
    if applicationEvents.nextResetDispatchAt <> invalid and now < applicationEvents.nextResetDispatchAt then return
    if PorticoMainDispatchApplicationEventDirective(directive, viewerController, scene, content, search, library, saved, liveTv, profiles, viewerPreferences)
        if PorticoApplicationEventsAcknowledgeReset(applicationEvents, directive.ackToken) then applicationEvents.projection.directive = invalid
    else
        applicationEvents.nextResetDispatchAt = now + 2
    end if
end sub

function PorticoMainEpochSeconds() as integer
    now = CreateObject("roDateTime")
    if now = invalid then return 0
    return now.AsSeconds()
end function

sub PorticoMainSynchronizeApplicationEvents(viewerController as object, scene as object, applicationEvents as object)
    if PorticoViewerRuntimeAccepting(viewerController.runtime)
        PorticoApplicationEventsViewerStateChanged(applicationEvents, scene.runtimeState)
    else
        PorticoMainFenceConstrainedEventOwners()
    end if
end sub

sub PorticoMainSynchronizePlaybackEvents(viewerController as object, scene as object, playbackEvents as object)
    if PorticoViewerRuntimeAccepting(viewerController.runtime)
        PorticoPlaybackEventsViewerStateChanged(playbackEvents, scene.runtimeState, scene.runtimeState.eventCapabilities)
    else
        PorticoPlaybackEventsCancel(playbackEvents)
    end if
end sub

function PorticoMainDispatchPlaybackEventDirective(directive as dynamic, playbackEvents as object, playback as object, scene as object) as boolean
    if directive = invalid or Type(directive) <> "roAssociativeArray" or playback = invalid or playback.task = invalid then return false
    kind = LCase(PorticoCoreSafeIdentifier(directive.kind, 16))
    generation = PorticoViewerScopePositiveInteger(directive.playbackGeneration)
    sessionCommand = generation > 0
    if sessionCommand
        if generation <> playbackEvents.activePlaybackGeneration or playbackEvents.activeSessionId = "" then return false
    else if kind <> "load"
        return false
    end if
    if kind = "load"
        mediaId = PorticoViewerScopeOpaqueId(directive.mediaId, 128)
        serverId = PorticoViewerScopeOpaqueId(scene.runtimeState.selectedServerId, 128)
        if mediaId = "" or serverId = "" then return false
        startSeconds = invalid
        if directive.positionSeconds <> invalid then startSeconds = PorticoHttpInteger(directive.positionSeconds, 0)
        if not PorticoPlaybackStartTargetCommand(playback, serverId, "vod", mediaId, startSeconds) then return false
        PorticoPlaybackSetIdentity(playback, {title: "", meta: ""})
        PorticoMainMergeRuntimeState(scene, {
            playbackViewState: {
                playbackStatus: "preparing",
                playbackErrorCode: "",
                playbackGeneration: 0,
                sourceGeneration: 0,
                identity: PorticoPlaybackIdentity(playback)
            }
        })
        m.porticoPlaybackPresentationSequence = PorticoHttpInteger(m.porticoPlaybackPresentationSequence, 0) + 1
        scene.playbackPresentationCommand = {
            sequence: m.porticoPlaybackPresentationSequence,
            kind: "open-player",
            viewerGeneration: PorticoViewerScopePositiveInteger(scene.runtimeState.viewerGeneration),
            identity: PorticoPlaybackIdentity(playback)
        }
        return true
    end if
    if kind = "stop"
        return PorticoPlaybackRemoteStopCommand(playback, generation, directive.message)
    end if
    if kind = "next"
        return PorticoPlaybackRemoteNextCommand(playback, generation)
    end if
    player = scene.FindNode("playerScreen")
    if player = invalid then return false
    if kind = "play" or kind = "pause"
        player.remotePlaybackDirective = {kind: kind, playbackGeneration: generation, sequence: directive.sequence}
        return true
    end if
    if kind = "seek"
        position = PorticoHttpInteger(directive.positionSeconds, -1)
        if position < 0 then return false
        paused = true
        playbackState = scene.runtimeState.playbackViewState
        if playbackState <> invalid and Type(playbackState) = "roAssociativeArray" then paused = LCase(PorticoCoreSafeIdentifier(playbackState.playbackStatus, 24)) <> "playing"
        player.remotePlaybackDirective = {kind: "seek", playbackGeneration: generation, sequence: directive.sequence, positionSeconds: position, paused: paused}
        return true
    end if
    if kind = "previous"
        paused = true
        playbackState = scene.runtimeState.playbackViewState
        if playbackState <> invalid and Type(playbackState) = "roAssociativeArray" then paused = LCase(PorticoCoreSafeIdentifier(playbackState.playbackStatus, 24)) <> "playing"
        return PorticoPlaybackRemotePreviousCommand(playback, generation)
    end if
    return false
end function

sub PorticoMainFenceConstrainedEventOwners()
    ' Deferred work is generation-owned. Never carry an invalidation from one
    ' account/profile/server authority into the next viewer generation.
    m.porticoPendingInvalidations = {}
    if m.porticoApplicationEventsController <> invalid then PorticoApplicationEventsTransitionFence(m.porticoApplicationEventsController)
    if m.porticoPlaybackEventsController <> invalid then PorticoPlaybackEventsCancel(m.porticoPlaybackEventsController)
    if m.porticoWatchWithFriendsController <> invalid then PorticoWatchWithFriendsTransitionFence(m.porticoWatchWithFriendsController)
    if m.porticoEngagementController <> invalid then PorticoEngagementCancel(m.porticoEngagementController)
end sub

function PorticoMainDispatchApplicationEventDirective(directive as dynamic, viewerController as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, profiles as object, viewerPreferences as object) as boolean
    if directive = invalid or Type(directive) <> "roAssociativeArray" or not PorticoViewerRuntimeAccepting(viewerController.runtime) then return false
    state = scene.runtimeState
    contractRevision = PorticoViewerScopeOpaqueId(PorticoRokuQueryContractRevision(), 128)
    productRevision = PorticoViewerScopeOpaqueId(state.productContractRevision, 128)
    activeDomains = []
    for each domain in directive.domains
        if PorticoMainInvalidationDomainActive(scene, domain)
            activeDomains.Push(domain)
        else
            if m.porticoPendingInvalidations = invalid or Type(m.porticoPendingInvalidations) <> "roAssociativeArray" then m.porticoPendingInvalidations = {}
            m.porticoPendingInvalidations[domain] = true
        end if
    end for
    refreshHome = false
    refreshDetail = false
    for each domain in activeDomains
        if domain = "home" then refreshHome = true
        if domain = "detail" then refreshDetail = true
    end for
    if refreshHome or refreshDetail
        contentCommand = {kind: "quiet-refresh-content", refreshHome: refreshHome}
        if refreshDetail then contentCommand.detailMediaId = PorticoViewerScopeOpaqueId(state.detailMediaId, 128)
        if contractRevision = "" or not PorticoContentViewerCommand(content, viewerController, contractRevision, contentCommand) then return false
    end if
    for each domain in activeDomains
        issued = true
        if domain = "home" or domain = "detail"
            issued = true
        else if domain = "search"
            searchState = state.searchViewState
            if searchState <> invalid and Type(searchState) = "roAssociativeArray"
                query = PorticoCoreSafeText(searchState.query, 200)
                if Len(query.Trim()) >= 2 then issued = contractRevision <> "" and PorticoSearchViewerCommand(search, viewerController, contractRevision, {kind: "quiet-refresh-search", query: query, queryRevision: PorticoHttpInteger(searchState.queryRevision, 0)})
            end if
        else if domain = "library"
            issued = contractRevision <> "" and PorticoLibraryViewerCommand(library, viewerController, contractRevision, {kind: "quiet-refresh-library"})
        else if domain = "saved"
            issued = contractRevision <> "" and PorticoSavedViewerCommand(saved, viewerController, contractRevision, {kind: "quiet-refresh-saved"})
        else if domain = "channels"
            issued = productRevision <> "" and PorticoLiveTvViewerCommand(liveTv, viewerController, productRevision, {kind: "quiet-refresh-channels"})
        else if domain = "settings"
            issued = PorticoViewerPreferencesControllerHandleActivation(viewerPreferences, {kind: "quiet-retry-preferences"})
        else if domain = "profile"
            ' Profile identity is governed by generation-bound auth revision and
            ' transactional selection. A generic data invalidation must never
            ' reopen/fence the chooser over an otherwise valid active viewer.
            issued = true
        else
            issued = false
        end if
        if not issued then return false
    end for
    return true
end function

function PorticoMainInvalidationDomainActive(scene as object, domain as string) as boolean
    if scene = invalid then return false
    page = LCase(PorticoHttpScalarString(scene.page, ""))
    if domain = "home" then return page = "home"
    if domain = "detail" then return page = "detail" or page = "person"
    if domain = "search" then return page = "search"
    if domain = "library" then return page = "library" or Left(page, 8) = "library/"
    if domain = "saved" then return page = "saved"
    if domain = "channels" then return page = "channels"
    if domain = "settings" then return page = "settings"
    if domain = "profile" then return page = "profile" or page = "profile-selection"
    return false
end function

sub PorticoMainFlushActiveInvalidations(viewerController as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, profiles as object, viewerPreferences as object)
    if m.porticoPendingInvalidations = invalid or Type(m.porticoPendingInvalidations) <> "roAssociativeArray" or not PorticoViewerRuntimeAccepting(viewerController.runtime) then return
    domains = []
    for each domain in ["home", "detail", "search", "library", "saved", "channels", "settings", "profile"]
        if m.porticoPendingInvalidations[domain] = true and PorticoMainInvalidationDomainActive(scene, domain)
            domains.Push(domain)
            m.porticoPendingInvalidations.Delete(domain)
        end if
    end for
    if domains.Count() = 0 then return
    directive = {version: 1, kind: "invalidate-domains", sequence: 1, domains: domains, resourceIds: []}
    if not PorticoMainDispatchApplicationEventDirective(directive, viewerController, scene, content, search, library, saved, liveTv, profiles, viewerPreferences)
        for each domain in domains
            m.porticoPendingInvalidations[domain] = true
        end for
    end if
end sub

sub PorticoMainFenceServerAuthorityLoss(viewerController as object, profileController as object, preferencesController as object, localAuth as object, serverConnection as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, playback as object, watchWithFriends as object, engagement as object)
    status = LCase(PorticoHttpScalarString(scene.runtimeState.serverStatus, "not-connected"))
    authorityLost = status = "identity-mismatch" or status = "permission-removed" or status = "not-connected" or status = "incompatible"
    if not authorityLost then return
    if PorticoViewerRuntimeAccepting(viewerController.runtime)
        PorticoMainFenceDiscoveryOwners(viewerController, scene, content, search, library, saved, liveTv)
        PorticoPlaybackTransitionFence(playback)
        PorticoMainFenceConstrainedEventOwners()
        PorticoWatchWithFriendsTransitionFence(watchWithFriends)
        PorticoEngagementCancel(engagement)
        watchWithFriends.lastPublishedAuthority = "independent"
        PorticoViewerRuntimeControllerFence(viewerController, "server-authority-lost")
    else if viewerController.runtime.transition <> invalid
        PorticoViewerRuntimeControllerRejectTransition(viewerController, viewerController.runtime.transition.id, "server-authority-lost")
    end if
    profileController.context = invalid
    profileController.contextKey = ""
    profileController.directory = invalid
    profileController.pendingProfileId = ""
    profileController.handoffId = ""
    profileController.localHandoffId = ""
    profileController.localActivation = invalid
    localAuth.bootstrapContext = invalid
    localAuth.profileHandoff = invalid
    failureMessageId = PorticoHttpScalarString(scene.runtimeState.serverMessageId, "problem.request-failed")
    PorticoMainMergeRuntimeState(scene, {
        profileDirectoryStatus: "error",
        profileDirectory: [],
        viewerStatus: "unavailable",
        viewerAcceptingWrites: false,
        viewerTransitionReason: failureMessageId
    })
    PorticoViewerPreferencesControllerCancel(preferencesController)
    PorticoServerConnectionClearRestoredContext(serverConnection)
    PorticoMainClearPendingAssertion(viewerController)
end sub

function PorticoMainSavedResolutionToken(state as dynamic) as string
    if state = invalid or Type(state) <> "roAssociativeArray" then return ""
    value = state.savedMutationResolution
    if value = invalid or Type(value) <> "roAssociativeArray" then return ""
    return PorticoProfilesSafeId(value.token)
end function

sub PorticoMainAdvanceViewerAssertion(viewerController as object, serverConnection as object, profileController as object, preferencesController as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, playback as object, watchWithFriends as object, engagement as object)
    existingTransition = viewerController.runtime.transition
    restoreContext = PorticoServerConnectionRestoredContext(serverConnection)
    selectionReady = profileController.context <> invalid and PorticoProfilesSafeId(profileController.pendingProfileId) <> ""
    if existingTransition = invalid and not selectionReady and restoreContext = invalid then return
    assertion = PorticoServerConnectionTakeScopeAssertion(serverConnection)
    scope = PorticoViewerScopeNormalize(assertion)
    if scope = invalid then return

    transition = viewerController.runtime.transition
    if transition = invalid
        if selectionReady
            context = profileController.context
            expectedProfileId = PorticoProfilesSafeId(profileController.pendingProfileId)
            expected = {
                authority: context.authority, accountId: context.accountId, serverId: context.serverId,
                installationId: context.installationId, profileId: expectedProfileId, restored: false
            }
            profile = PorticoProfilesFind(profileController.directory, expectedProfileId)
            if profile <> invalid then expected.profileName = profile.name
        else
            expected = restoreContext
        end if
        if expected = invalid or scope.authority <> expected.authority or scope.accountId <> expected.accountId or scope.serverId <> expected.serverId or scope.profileId <> expected.profileId
            PorticoServerConnectionFenceViewer(serverConnection, viewerController.runtime.generationSequence)
            PorticoMainMergeRuntimeState(scene, {viewerStatus: "unavailable", viewerAcceptingWrites: false, viewerTransitionReason: "scope_assertion_mismatch"})
            return
        end if

        tasksReady = PorticoMainFenceDiscoveryOwners(viewerController, scene, content, search, library, saved, liveTv)
        playbackReady = PorticoPlaybackTransitionFence(playback)
        PorticoMainFenceConstrainedEventOwners()
        watchReady = PorticoWatchWithFriendsTransitionFence(watchWithFriends)
        engagementReady = PorticoEngagementCancel(engagement)
        watchWithFriends.lastPublishedAuthority = "independent"

        started = PorticoViewerRuntimeControllerStartTransition(viewerController, scope, "activating-profile", ["tasks", "playback", "watch-with-friends", "engagement", "presentation"])
        if not started.ok then return
        viewerController.pendingAssertionTransitionId = started.transitionId
        viewerController.pendingAssertionContext = expected
        viewerController.pendingProfileProjection = invalid
        if expected.profileName <> invalid then viewerController.pendingProfileProjection = {name: expected.profileName}

        PorticoMainMergeRuntimeState(scene, {
            playbackViewState: invalid,
            watchWithFriendsViewState: invalid,
            notificationsViewState: invalid,
            engagementViewState: invalid
        })
        taskAck = PorticoViewerRuntimeControllerAcknowledge(viewerController, started.transitionId, "tasks", tasksReady)
        playbackAck = PorticoViewerRuntimeControllerAcknowledge(viewerController, started.transitionId, "playback", playbackReady)
        watchAck = PorticoViewerRuntimeControllerAcknowledge(viewerController, started.transitionId, "watch-with-friends", watchReady)
        engagementAck = PorticoViewerRuntimeControllerAcknowledge(viewerController, started.transitionId, "engagement", engagementReady)
        presentationAck = PorticoViewerRuntimeControllerAcknowledge(viewerController, started.transitionId, "presentation", true)
        if not taskAck.ok or not playbackAck.ok or not watchAck.ok or not engagementAck.ok or not presentationAck.ok
            PorticoViewerRuntimeControllerRejectTransition(viewerController, started.transitionId, "transition_teardown_failed")
            PorticoServerConnectionFenceViewer(serverConnection, viewerController.runtime.generationSequence)
            PorticoMainClearPendingAssertion(viewerController)
            return
        end if

        ' The first assertion proved identity at the fenced profile-selection
        ' generation. Restore once at the transition generation so the one-shot
        ' final /auth/me assertion exactly matches the candidate being published.
        PorticoServerConnectionInitialize(serverConnection, started.candidateScope.viewerGeneration)
        return
    end if

    transitionId = PorticoHttpInteger(viewerController.pendingAssertionTransitionId, 0)
    if transitionId < 1 or transition.id <> transitionId then return
    expected = viewerController.pendingAssertionContext
    if expected = invalid or Type(expected) <> "roAssociativeArray" or scope.authority <> expected.authority or scope.accountId <> expected.accountId or scope.serverId <> expected.serverId or scope.profileId <> expected.profileId or not PorticoViewerScopeEquals(scope, transition.candidateScope)
        PorticoViewerRuntimeControllerRejectTransition(viewerController, transitionId, "scope_assertion_mismatch")
        PorticoServerConnectionFenceViewer(serverConnection, viewerController.runtime.generationSequence)
        PorticoMainClearPendingAssertion(viewerController)
        return
    end if

    published = PorticoViewerRuntimeControllerPublish(viewerController, transitionId, scope, scope, viewerController.pendingProfileProjection)
    if published.ok
        profileController.stagingOverActive = false
        profileController.context = {authority: expected.authority, accountId: expected.accountId, serverId: expected.serverId, installationId: expected.installationId}
        profileController.contextKey = PorticoProfileControllerContextKey(profileController.context)
        profileController.viewerGeneration = published.activeScope.viewerGeneration
        profileController.handoffId = ""
        profileController.localHandoffId = ""
        profileController.pendingProfileId = ""
        profileController.localActivation = invalid
        if expected.restored = true
            profileController.directory = invalid
            PorticoMainMergeRuntimeState(scene, {profileDirectoryStatus: "idle", profileDirectory: []})
        end if
        publicPatch = {selectedServerId: published.activeScope.serverId, profileSelectionOverlay: false}
        if published.activeScope.authority = "local"
            publicPatch.authMode = "local"
            publicPatch.accountStatus = "signed-in"
        end if
        PorticoMainMergeRuntimeState(scene, publicPatch)
        preferencesOnline = LCase(PorticoHttpScalarString(scene.runtimeState.serverStatus, "offline")) = "online"
        PorticoViewerPreferencesControllerActivate(preferencesController, published.activeScope, expected.installationId, preferencesOnline)
        PorticoServerConnectionClearRestoredContext(serverConnection)
    end if
    PorticoMainClearPendingAssertion(viewerController)
end sub

sub PorticoMainBeginAuthoritySwitch(activation as object, viewerController as object, profileController as object, preferencesController as object, localAuth as object, serverConnection as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, playback as object, watchWithFriends as object, engagement as object)
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    authoritySwitch = kind = "start-local-auth" or kind = "start-account-setup" or kind = "sign-in-account"
    credentialExit = kind = "sign-out-account" or kind = "sign-out-local" or kind = "local-back" or kind = "back-auth-landing"
    hostedServerSwitch = kind = "select-server" and not PorticoMainUsesLocalAuth(scene.runtimeState)
    profileCancel = kind = "cancel-profile-selection"
    profileSwitch = kind = "switch-profile"
    if profileSwitch
        PorticoMainSwitchProfile(viewerController, profileController, preferencesController, localAuth, serverConnection, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
        return
    end if
    if not authoritySwitch and not credentialExit and not hostedServerSwitch and not profileCancel then return
    profileController.pendingProfileId = ""
    profileController.handoffId = ""
    profileController.localHandoffId = ""
    profileController.localActivation = invalid
    if profileCancel
        if PorticoViewerRuntimeAccepting(viewerController.runtime)
            profileController.stagingOverActive = false
            PorticoMainMergeRuntimeState(scene, {
                profileDirectoryStatus: "idle",
                profileDirectory: [],
                profileSelectionOverlay: false,
                viewerStatus: "active",
                viewerAcceptingWrites: true,
                viewerTransitionReason: ""
            })
            PorticoMainClearPendingAssertion(viewerController)
            return
        else if viewerController.runtime.transition <> invalid
            PorticoViewerRuntimeControllerRejectTransition(viewerController, viewerController.runtime.transition.id, "profile-selection-cancelled")
        end if
        PorticoServerConnectionFenceViewer(serverConnection, viewerController.runtime.generationSequence)
        PorticoViewerPreferencesControllerCancel(preferencesController)
        PorticoMainClearPendingAssertion(viewerController)
        return
    end if
    switchedGeneration = viewerController.runtime.generationSequence
    if PorticoViewerRuntimeAccepting(viewerController.runtime)
        PorticoMainFenceDiscoveryOwners(viewerController, scene, content, search, library, saved, liveTv)
        PorticoPlaybackTransitionFence(playback)
        PorticoMainFenceConstrainedEventOwners()
        PorticoWatchWithFriendsTransitionFence(watchWithFriends)
        PorticoEngagementCancel(engagement)
        watchWithFriends.lastPublishedAuthority = "independent"
        fenced = PorticoViewerRuntimeControllerFence(viewerController, "authority-switch")
        if fenced.ok
            switchedGeneration = fenced.generation
            PorticoServerConnectionFenceViewer(serverConnection, fenced.generation)
            PorticoMainFinishPreferencesAuthority(preferencesController, credentialExit)
        end if
    else if viewerController.runtime.transition <> invalid
        transitionId = viewerController.runtime.transition.id
        PorticoViewerRuntimeControllerRejectTransition(viewerController, transitionId, "viewer-switch-interrupted")
        PorticoServerConnectionFenceViewer(serverConnection, viewerController.runtime.generationSequence)
        PorticoMainFinishPreferencesAuthority(preferencesController, credentialExit)
        PorticoMainClearPendingAssertion(viewerController)
        switchedGeneration = viewerController.runtime.generationSequence
    else
        fenced = PorticoViewerRuntimeControllerFence(viewerController, "explicit-viewer-switch")
        if fenced.ok then switchedGeneration = fenced.generation
        PorticoServerConnectionFenceViewer(serverConnection, switchedGeneration)
        PorticoMainFinishPreferencesAuthority(preferencesController, credentialExit)
    end if
    profileController.context = invalid
    profileController.contextKey = ""
    profileController.directory = invalid
    profileController.stagingOverActive = false
    profileController.viewerGeneration = switchedGeneration
    PorticoMainMergeRuntimeState(scene, {profileDirectoryStatus: "idle", profileDirectory: []})
    if authoritySwitch or credentialExit then PorticoLocalAuthViewerStateChanged(localAuth, viewerController.runtime.generationSequence)
    if hostedServerSwitch then viewerController.preparedHostedContextKey = ""
end sub

sub PorticoMainSwitchProfile(viewerController as object, profileController as object, preferencesController as object, localAuth as object, serverConnection as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, playback as object, watchWithFriends as object, engagement as object)
    if not PorticoViewerRuntimeAccepting(viewerController.runtime) then return
    bootstrapContext = PorticoMainPrivateBootstrapContext(localAuth, serverConnection, scene.runtimeState)
    if bootstrapContext = invalid then return

    ' Plex-style switching is staged over the active viewer. The current profile,
    ' cached shell and playback remain authoritative until the candidate has a
    ' verified route, identity, profile scope, content bootstrap and durable
    ' credential commit. PorticoMainAdvanceViewerAssertion performs the only
    ' fence, immediately before the already-proven candidate is published.
    serverConnection.pendingScopeAssertion = invalid
    serverConnection.restoreContext = invalid
    PorticoMainClearPendingAssertion(viewerController)
    profileController.context = bootstrapContext
    profileController.contextKey = PorticoProfileControllerContextKey(bootstrapContext)
    profileController.directory = invalid
    profileController.decisionAppliedGeneration = viewerController.runtime.activeScope.viewerGeneration
    profileController.forceAskGeneration = viewerController.runtime.activeScope.viewerGeneration
    profileController.pendingProfileId = ""
    profileController.handoffId = ""
    profileController.localHandoffId = ""
    profileController.localActivation = invalid
    profileController.stagingOverActive = true
    profileController.viewerGeneration = viewerController.runtime.activeScope.viewerGeneration
    PorticoMainMergeRuntimeState(scene, {
        profileDirectoryStatus: "loading",
        profileDirectory: [],
        profileSelectionOverlay: true,
        viewerStatus: "active",
        viewerAcceptingWrites: true,
        viewerTransitionReason: "profile-selection-required"
    })
    if bootstrapContext.authority = "hosted"
        PorticoProfileControllerCommand(profileController, "viewer-state", {
            signedIn: true,
            authority: bootstrapContext.authority,
            accountId: bootstrapContext.accountId,
            serverId: bootstrapContext.serverId,
            installationId: bootstrapContext.installationId
        })
    else
        PorticoLocalAuthPrepareProfileSwitch(localAuth, profileController.viewerGeneration)
    end if
end sub

sub PorticoMainFinishPreferencesAuthority(preferencesController as object, signedOut as boolean)
    if signedOut
        PorticoViewerPreferencesControllerSignOut(preferencesController)
    else
        PorticoViewerPreferencesControllerCancel(preferencesController)
    end if
end sub

function PorticoMainFenceDiscoveryOwners(viewerController as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object) as boolean
    PorticoMainClearPrivatePlayer(scene)
    tasksPresent = content <> invalid and content.task <> invalid and search <> invalid and search.task <> invalid and library <> invalid and library.task <> invalid and saved <> invalid and saved.task <> invalid and liveTv <> invalid and liveTv.task <> invalid
    if not tasksPresent then return false
    fencedState = PorticoMainFencedDomainState(scene.runtimeState)
    PorticoLiveTvServerStateChanged(liveTv, fencedState)
    if not PorticoViewerRuntimeAccepting(viewerController.runtime) then return true
    revision = PorticoRokuQueryContractRevision()
    contentReady = PorticoContentViewerCommand(content, viewerController, revision, {kind: "server-state", selectedServerId: viewerController.runtime.activeScope.serverId, serverStatus: "not-connected"})
    searchReady = PorticoSearchViewerCommand(search, viewerController, revision, {kind: "server-state", selectedServerId: viewerController.runtime.activeScope.serverId, serverStatus: "not-connected"})
    libraryReady = PorticoLibraryViewerCommand(library, viewerController, revision, {kind: "server-state", selectedServerId: viewerController.runtime.activeScope.serverId, selectedServerName: "Portico Server", serverStatus: "not-connected"})
    savedReady = PorticoSavedViewerCommand(saved, viewerController, revision, {kind: "server-state", selectedServerId: viewerController.runtime.activeScope.serverId, selectedServerName: "Portico Server", serverStatus: "not-connected"})
    return contentReady and searchReady and libraryReady and savedReady
end function

sub PorticoMainClearPrivatePlayer(scene as object)
    if scene = invalid then return
    player = scene.FindNode("playerScreen")
    if player = invalid then return
    player.privateContent = invalid
    player.watchGroupState = invalid
    player.watchSyncDirective = invalid
end sub

sub PorticoMainClearPendingAssertion(viewerController as object)
    viewerController.pendingAssertionTransitionId = 0
    viewerController.pendingAssertionContext = invalid
    viewerController.pendingProfileProjection = invalid
end sub

function PorticoMainInitialAuthMode() as string
    ' Credential restoration belongs to the credential-owning Tasks. Main starts
    ' neutral and reacts only to their bounded public lifecycle projections.
    return "none"
end function

function PorticoMainUsesLocalAuth(state as dynamic) as boolean
    if state = invalid or Type(state) <> "roAssociativeArray" then return false
    return Left(LCase(PorticoHttpScalarString(state.authMode, "")), 5) = "local"
end function

sub PorticoMainApplyAuthActivation(scene as object, activation as object)
    kind = LCase(PorticoHttpScalarString(activation.kind, ""))
    if kind = "start-local-auth"
        PorticoMainMergeRuntimeState(scene, {authMode: "local-pending"})
    else if kind = "start-account-setup"
        PorticoMainMergeRuntimeState(scene, {authMode: "account-pending"})
    else if kind = "back-auth-landing" or kind = "local-back" or kind = "pause-account-setup"
        if not PorticoMainAccountSignedIn(scene.runtimeState) then PorticoMainMergeRuntimeState(scene, {authMode: "none"})
    end if
end sub

sub PorticoMainApplyAccountAuthMode(scene as object)
    state = scene.runtimeState
    if state = invalid or Type(state) <> "roAssociativeArray" then return
    status = LCase(PorticoHttpScalarString(state.accountStatus, "signed-out"))
    if status = "signed-in" or status = "refreshing" or status = "hosted-unavailable"
        PorticoMainMergeRuntimeState(scene, {authMode: "portico-account"})
    else if LCase(PorticoHttpScalarString(state.authMode, "")) = "portico-account"
        PorticoMainMergeRuntimeState(scene, {authMode: "none"})
    end if
end sub

function PorticoMainAccountSignedIn(state as dynamic) as boolean
    if state = invalid or Type(state) <> "roAssociativeArray" then return false
    status = LCase(PorticoHttpScalarString(state.accountStatus, "signed-out"))
    return status = "signed-in" or status = "refreshing" or status = "hosted-unavailable"
end function

sub PorticoMainReconnect(scene as object, localAuth as object, serverConnection as object)
    viewerActive = false
    if scene.runtimeState <> invalid and Type(scene.runtimeState) = "roAssociativeArray"
        viewerActive = LCase(PorticoHttpScalarString(scene.runtimeState.viewerStatus, "")) = "active" and scene.runtimeState.viewerAcceptingWrites = true
    end if
    if viewerActive
        PorticoServerConnectionCommand(serverConnection, "retry-server", "", "")
    else if PorticoMainUsesLocalAuth(scene.runtimeState)
        PorticoLocalAuthBridgeCommand(localAuth, "retry-session", invalid)
    else
        PorticoServerConnectionCommand(serverConnection, "retry-server", "", "")
    end if
end sub

sub PorticoMainMergeRuntimeState(scene as object, fields as object)
    current = scene.runtimeState
    nextState = {}
    if current <> invalid and Type(current) = "roAssociativeArray"
        for each key in current
            nextState[key] = current[key]
        end for
    end if
    for each key in fields
        nextState[key] = fields[key]
    end for
    scene.runtimeState = nextState
end sub

sub PorticoMainReconcileViewerFoundation(viewerController as object, profileController as object, preferencesController as object, localAuth as object, serverConnection as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, playback as object, watchWithFriends as object, engagement as object)
    bootstrapContext = PorticoMainPrivateBootstrapContext(localAuth, serverConnection, scene.runtimeState)
    serverStatus = LCase(PorticoHttpScalarString(scene.runtimeState.serverStatus, "not-connected"))
    nativeSessionUsable = serverStatus = "online" or serverStatus = "offline" or serverStatus = "connecting"
    if bootstrapContext = invalid and PorticoViewerRuntimeAccepting(viewerController.runtime) and (PorticoMainAccountSignedIn(scene.runtimeState) or nativeSessionUsable) and profileController.context <> invalid
        bootstrapContext = {
            authority: profileController.context.authority,
            accountId: profileController.context.accountId,
            serverId: profileController.context.serverId,
            installationId: profileController.context.installationId,
            provenByCredentialTask: true
        }
    end if
    if bootstrapContext <> invalid and bootstrapContext.authority = "local" and PorticoProfilesSafeId(scene.runtimeState.selectedServerId) = ""
        PorticoMainMergeRuntimeState(scene, {
            selectedServerId: bootstrapContext.serverId,
            selectedServerName: PorticoHttpScalarString(scene.runtimeState.selectedLocalServerName, "Portico Server"),
            serverListStatus: "ready"
        })
    end if
    teardownReady = PorticoMainPrepareProfileContextChange(viewerController, profileController, bootstrapContext, scene, content, search, library, saved, liveTv, playback, watchWithFriends, engagement)
    if not teardownReady then return
    result = PorticoProfileControllerSynchronize(profileController, viewerController, bootstrapContext, teardownReady)
    if result.changed and not result.available then PorticoViewerPreferencesControllerCancel(preferencesController)
    if bootstrapContext = invalid and PorticoProfilesSafeId(scene.runtimeState.selectedServerId) <> ""
        PorticoMainMergeRuntimeState(scene, {
            profileDirectoryStatus: "unavailable",
            profileDirectory: [],
            viewerStatus: "unavailable",
            viewerAcceptingWrites: false,
            viewerTransitionReason: "auth.device-session-required"
        })
    end if
end sub

function PorticoMainPrepareProfileContextChange(viewerController as object, profileController as object, bootstrapContext as dynamic, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, playback as object, watchWithFriends as object, engagement as object) as boolean
    nextKey = PorticoProfileControllerContextKey(PorticoProfileBootstrapContext(bootstrapContext))
    teardownKey = nextKey
    if teardownKey = "" then teardownKey = "none"
    if profileController.contextTeardownBlockedKey <> "" and teardownKey <> profileController.contextTeardownBlockedKey then profileController.contextTeardownBlockedKey = ""
    if teardownKey = profileController.contextTeardownBlockedKey then return false
    if nextKey = profileController.contextKey then return true

    alreadyExternallyFenced = not PorticoViewerRuntimeAccepting(viewerController.runtime) and viewerController.runtime.transition = invalid and viewerController.runtime.generationSequence > profileController.viewerGeneration
    needsTeardown = PorticoViewerRuntimeAccepting(viewerController.runtime) or viewerController.runtime.transition <> invalid or (profileController.contextKey <> "" and not alreadyExternallyFenced)
    if not needsTeardown then return true

    discoveryReady = PorticoMainFenceDiscoveryOwners(viewerController, scene, content, search, library, saved, liveTv)
    playbackReady = PorticoPlaybackTransitionFence(playback)
    PorticoMainFenceConstrainedEventOwners()
    watchReady = PorticoWatchWithFriendsTransitionFence(watchWithFriends)
    engagementReady = PorticoEngagementCancel(engagement)
    watchWithFriends.lastPublishedAuthority = "independent"
    if discoveryReady and playbackReady and watchReady and engagementReady
        profileController.contextTeardownBlockedKey = ""
        return true
    end if

    profileController.contextTeardownBlockedKey = teardownKey
    PorticoMainClearPrivatePlayer(scene)
    PorticoViewerRuntimeControllerFence(viewerController, "profile-context-teardown-failed")
    PorticoMainMergeRuntimeState(scene, {
        viewerStatus: "unavailable",
        viewerAcceptingWrites: false,
        viewerTransitionReason: "profile-context-teardown-failed"
    })
    return false
end function

function PorticoMainPrivateBootstrapContext(localAuth as object, serverConnection as object, state as dynamic) as dynamic
    if state = invalid or Type(state) <> "roAssociativeArray" then return invalid
    source = invalid
    if PorticoMainUsesLocalAuth(state)
        if localAuth <> invalid and Type(localAuth) = "roAssociativeArray" and localAuth.bootstrapContext <> invalid then source = localAuth.bootstrapContext
    else
        if serverConnection <> invalid and Type(serverConnection) = "roAssociativeArray" and serverConnection.bootstrapContext <> invalid then source = serverConnection.bootstrapContext
    end if
    context = PorticoProfileBootstrapContext(source)
    if context = invalid then return invalid
    if PorticoMainUsesLocalAuth(state) and context.authority <> "local" then return invalid
    if not PorticoMainUsesLocalAuth(state) and context.authority <> "hosted" then return invalid
    expectedServerId = PorticoProfilesSafeId(state.selectedServerId)
    if context.authority = "local"
        localServerId = PorticoProfilesSafeId(state.selectedLocalServerId)
        if localServerId <> "" then expectedServerId = localServerId
    end if
    if expectedServerId <> "" and context.serverId <> expectedServerId then return invalid
    if context.authority = "hosted" and expectedServerId = "" then return invalid
    return context
end function

sub PorticoMainPrepareHostedContext(viewerController as object, serverConnection as object, state as dynamic)
    if PorticoMainUsesLocalAuth(state) then return
    if not PorticoMainAccountSignedIn(state) then return
    serverId = PorticoProfilesSafeId(state.selectedServerId)
    if serverId = "" then return
    generation = viewerController.runtime.generationSequence
    key = serverId + "|" + generation.ToStr()
    if viewerController.preparedHostedContextKey = key then return
    viewerController.preparedHostedContextKey = key
    PorticoServerConnectionPrepareHostedContext(serverConnection, serverId, generation)
end sub

sub PorticoMainSynchronizeViewerDomains(viewerController as object, scene as object, content as object, search as object, library as object, saved as object, liveTv as object, playback as object, watchWithFriends as object, engagement as object)
    accepting = PorticoViewerRuntimeAccepting(viewerController.runtime)
    generation = viewerController.runtime.generationSequence
    if accepting
        viewerController.legacyDomainsFencedGeneration = -1
        domainState = scene.runtimeState
        contractRevision = PorticoViewerScopeOpaqueId(PorticoRokuQueryContractRevision(), 128)
        if contractRevision <> ""
            PorticoContentViewerStateChanged(content, viewerController, contractRevision, domainState)
            PorticoSearchViewerStateChanged(search, viewerController, contractRevision, domainState)
            PorticoLibraryViewerStateChanged(library, viewerController, contractRevision, domainState)
            PorticoSavedViewerStateChanged(saved, viewerController, contractRevision, domainState)
        end if
        PorticoPlaybackViewerStateChanged(playback, viewerController, domainState)
        eventCapabilities = domainState.eventCapabilities
        PorticoWatchWithFriendsViewerStateChanged(watchWithFriends, domainState, eventCapabilities)
        PorticoEngagementViewerStateChanged(engagement, domainState, eventCapabilities)
        productContractRevision = PorticoViewerScopeOpaqueId(domainState.productContractRevision, 128)
        if productContractRevision <> "" then PorticoLiveTvViewerStateChanged(liveTv, viewerController, productContractRevision, domainState)
    else
        if viewerController.legacyDomainsFencedGeneration = generation then return
        viewerController.legacyDomainsFencedGeneration = generation
        domainState = PorticoMainFencedDomainState(scene.runtimeState)
        PorticoMainClearPrivatePlayer(scene)
    end if
    if not accepting then PorticoLiveTvServerStateChanged(liveTv, domainState)
end sub

function PorticoMainFencedDomainState(state as dynamic) as object
    result = {}
    if state <> invalid and Type(state) = "roAssociativeArray"
        for each key in state
            result[key] = state[key]
        end for
    end if
    result.selectedServerId = ""
    result.serverStatus = "not-connected"
    result.navigationSnapshotVerified = false
    result.libraryItems = []
    return result
end function
