sub init()
    m.content = m.top.findNode("savedContent")
    m.notice = m.top.findNode("mutationNotice")
    m.content.observeField("activation", "contentActivationChanged")
    m.content.observeField("focusState", "contentFocusChanged")
    m.notice.observeField("activation", "noticeActivationChanged")
    m.sequence = 0
    m.selectedResourceId = ""
    m.noticeFocused = false
    m.lastNoticeId = ""
    m.contentFocusId = "saved.content"
    m.screenAuthority = PorticoScreenAuthorityCreate("saved")
    m.top.focusable = true
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid or Type(state) <> "roAssociativeArray" then return
    viewerEpoch = 0
    if state.viewerGeneration <> invalid then viewerEpoch = state.viewerGeneration
    PorticoScreenAuthorityFence(m.screenAuthority, viewerEpoch)
    m.selectedResourceId = ""
    if state.selectedResourceId <> invalid then m.selectedResourceId = state.selectedResourceId.ToStr()
    m.content.viewState = state
    noticeModel = invalid
    if state.mutationError <> invalid and Type(state.mutationError) = "roAssociativeArray"
        noticeModel = ParseJson(FormatJson(state.mutationError))
        noticeModel.dismissKind = "dismiss-saved-mutation-error"
    end if
    m.notice.viewState = noticeModel
    if noticeModel = invalid
        m.noticeFocused = false
        m.notice.visible = false
    else
        noticeId = ""
        if noticeModel.id <> invalid then noticeId = noticeModel.id.ToStr()
        if noticeId <> "" and noticeId <> m.lastNoticeId
            m.lastNoticeId = noticeId
            m.noticeFocused = true
            PorticoScreenAuthorityOpenModal(m.screenAuthority, m.contentFocusId)
        end if
        m.notice.focused = m.noticeFocused
        m.notice.visible = true
        if m.noticeFocused then m.notice.setFocus(true)
    end if
end sub

sub noticeActivationChanged()
    action = m.notice.activation
    if action = invalid or Type(action) <> "roAssociativeArray" or action.kind = invalid then return
    if LCase(action.kind.ToStr()) <> "dismiss-saved-mutation-error" then return
    m.noticeFocused = false
    m.notice.focused = false
    m.content.setFocus(true)
    restoredId = PorticoScreenAuthorityCloseModal(m.screenAuthority, m.contentFocusId)
    PorticoScreenAuthorityFocused(m.screenAuthority, restoredId)
    m.sequence = m.sequence + 1
    m.top.activation = {sequence: m.sequence, kind: "dismiss-saved-mutation-error"}
end sub

sub contentActivationChanged()
    activation = m.content.activation
    if activation = invalid or Type(activation) <> "roAssociativeArray" then return
    kind = LCase(activation.kind.ToStr())
    if kind = "select-tab" then kind = "select-saved-tab"
    if kind = "select-resource" then kind = "select-saved-resource"
    if kind = "load-more" then kind = "load-more-saved"
    if kind = "retry-library" then kind = "retry-saved"
    if kind = "clear-selection" then kind = "close-saved-resource"
    m.sequence = m.sequence + 1
    forwarded = { sequence: m.sequence, kind: kind }
    for each key in activation
        if key <> "sequence" and key <> "kind" then forwarded[key] = activation[key]
    end for
    if kind = "select-saved-resource"
        state = m.top.viewState
        if state <> invalid and state.items <> invalid and GetInterface(state.items, "ifArray") <> invalid
            for each item in state.items
                if item.id = forwarded.targetId then forwarded.title = item.title
            end for
        end if
    end if
    m.top.activation = forwarded
end sub

sub contentFocusChanged()
    m.top.focusState = m.content.focusState
    state = m.content.focusState
    if state <> invalid and Type(state) = "roAssociativeArray" and state.key <> invalid and state.key.ToStr() <> ""
        m.contentFocusId = state.key.ToStr()
        PorticoScreenAuthorityFocused(m.screenAuthority, m.contentFocusId)
    end if
end sub

sub focusChanged()
    if not m.top.hasFocus() then return
    if m.noticeFocused and m.notice.visible
        m.notice.setFocus(true)
    else
        m.content.setFocus(true)
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.noticeFocused
        if key = "back"
            m.noticeFocused = false
            m.notice.focused = false
            m.content.setFocus(true)
            restoredId = PorticoScreenAuthorityCloseModal(m.screenAuthority, m.contentFocusId)
            PorticoScreenAuthorityFocused(m.screenAuthority, restoredId)
        end if
        return true
    end if
    if key = "back" and m.selectedResourceId <> ""
        m.sequence = m.sequence + 1
        m.top.activation = { sequence: m.sequence, kind: "close-saved-resource", targetId: m.selectedResourceId }
        return true
    end if
    return false
end function
