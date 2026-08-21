function PorticoPlayerControllerCreate(video as object, rateResetTimer as object, trickplayHideTimer as object, chromeHideTimer as object) as object
    return {
        video: video,
        timers: {rateReset: rateResetTimer, trickplayHide: trickplayHideTimer, chromeHide: chromeHideTimer},
        model: invalid,
        privateContent: invalid,
        playbackGeneration: 0,
        sourceGeneration: 0,
        eventSequence: 0,
        completedGeneration: -1,
        stopEventEmitted: false,
        renewalRequestedSourceGeneration: -1,
        lastRemoteDirectiveSequence: 0,
        nativeState: "none",
        positionSeconds: 0,
        durationSeconds: 0,
        pendingInitialSeekSeconds: 0,
        sourceRecoveryAttempts: 0,
        pendingWatchLoadPaused: false,
        pendingWatchLoadMediaId: "",
        pauseAfterInitialStart: false,
        applyingWatchSync: false,
        activation: {key: "", intentId: "", playbackGeneration: 0, sourceGeneration: 0, phase: "idle"}
    }
end function

function PorticoPlayerControllerAccepts(controller as object, playbackGeneration as integer, sourceGeneration as integer) as boolean
    if playbackGeneration < controller.playbackGeneration then return false
    if playbackGeneration = controller.playbackGeneration and sourceGeneration < controller.sourceGeneration then return false
    return true
end function

function PorticoPlayerControllerBeginActivation(controller as object, key as string, intentId as string) as boolean
    transaction = controller.activation
    if transaction.phase <> "idle" then return false
    transaction.key = key
    transaction.intentId = intentId
    transaction.playbackGeneration = controller.playbackGeneration
    transaction.sourceGeneration = controller.sourceGeneration
    transaction.phase = "requested"
    return true
end function

function PorticoPlayerControllerCommitActivation(controller as object) as boolean
    transaction = controller.activation
    if transaction.phase <> "requested" then return false
    if transaction.playbackGeneration <> controller.playbackGeneration or transaction.sourceGeneration <> controller.sourceGeneration
        transaction.phase = "cancelled"
        return false
    end if
    transaction.phase = "committing"
    return true
end function

sub PorticoPlayerControllerCompleteActivation(controller as object)
    if controller.activation.phase = "committing" then controller.activation.phase = "committed"
end sub

sub PorticoPlayerControllerCancelActivation(controller as object)
    controller.activation.phase = "cancelled"
end sub

sub PorticoPlayerControllerResetActivation(controller as object)
    controller.activation = {key: "", intentId: "", playbackGeneration: controller.playbackGeneration, sourceGeneration: controller.sourceGeneration, phase: "idle"}
end sub

sub PorticoPlayerControllerReleaseActivation(controller as object, key as string)
    if controller.activation.key <> key then return
    PorticoPlayerControllerResetActivation(controller)
end sub

function PorticoPlayerControllerIsAudio(controller as object) as boolean
    if controller.model = invalid or controller.model.source = invalid then return false
    kind = LCase(controller.model.source.mediaType)
    return kind = "audiobook" or kind = "book" or kind = "track" or kind = "music" or kind = "audio"
end function
