sub init()
    m.title = m.top.findNode("title")
    m.section = m.top.findNode("section")
    m.privacy = m.top.findNode("privacy")
    m.status = m.top.findNode("status")
    m.kindButtons = [m.top.findNode("kind0"), m.top.findNode("kind1"), m.top.findNode("kind2"), m.top.findNode("kind3")]
    m.categoryButtons = []
    for index = 0 to 6
        m.categoryButtons.Push(m.top.findNode("category" + index.ToStr()))
    end for
    m.send = m.top.findNode("send")
    m.cancel = m.top.findNode("cancel")
    m.title.font = PorticoFont("700", 40)
    m.title.color = "#F4F7FA"
    m.section.font = PorticoFont("600", 19)
    m.section.color = "#C7D0D8"
    m.privacy.font = PorticoFont("400", 16)
    m.privacy.color = "#8F9BA6"
    m.status.font = PorticoFont("500", 17)
    m.status.color = "#70BCE8"
    language = PorticoProductLanguageLoad()
    m.language = invalid
    if language.ok then m.language = language.value
    m.allowedKinds = []
    m.kind = "general"
    m.categories = ["other"]
    m.category = "other"
    m.area = "kind"
    m.kindFocus = 0
    m.categoryFocus = 0
    m.actionFocus = 0
    m.sequence = 0
    m.context = {}
    m.top.focusable = true
    applyViewState()
end sub

sub applyViewState()
    state = m.top.viewState
    open = state <> invalid and Type(state) = "roAssociativeArray" and state.open = true
    m.top.visible = open
    if not open then return
    m.context = {}
    if state.context <> invalid and Type(state.context) = "roAssociativeArray"
        mediaId = PorticoFeedbackId(state.context.mediaId)
        sessionId = PorticoFeedbackId(state.context.playbackSessionId)
        if mediaId <> "" then m.context.mediaId = mediaId
        if sessionId <> "" then m.context.playbackSessionId = sessionId
    end if
    capabilities = state.feedbackCapabilities
    m.allowedKinds = []
    if capabilities <> invalid and Type(capabilities) = "roAssociativeArray" and capabilities.enabled = true and GetInterface(capabilities.allowedKinds, "ifArray") <> invalid
        for each raw in capabilities.allowedKinds
            kind = PorticoFeedbackKind(raw)
            if kind <> "" then m.allowedKinds.Push(kind)
        end for
    end if
    if m.allowedKinds.Count() = 0 then m.allowedKinds = ["general"]
    if not PorticoFeedbackContains(m.allowedKinds, m.kind)
        m.kind = m.allowedKinds[0]
        m.kindFocus = 0
    end if
    m.categories = PorticoFeedbackCategories(m.kind)
    if not PorticoFeedbackContains(m.categories, m.category) then m.category = m.categories[0]
    if m.categoryFocus >= m.categories.Count() then m.categoryFocus = 0
    if state.initialKind <> invalid
        requested = PorticoFeedbackKind(state.initialKind)
        if requested <> "" and PorticoFeedbackContains(m.allowedKinds, requested) and requested <> m.kind
            m.kind = requested
            m.categories = PorticoFeedbackCategories(m.kind)
            m.category = m.categories[0]
            m.categoryFocus = 0
            for index = 0 to m.allowedKinds.Count() - 1
                if m.allowedKinds[index] = requested then m.kindFocus = index
            end for
        end if
    end if
    PorticoFeedbackRender()
end sub

sub PorticoFeedbackRender()
    state = m.top.viewState
    hasMedia = m.context.mediaId <> invalid
    if hasMedia
        m.title.text = PorticoFeedbackCopy("feedback.heading.report-media", "Report a problem")
    else
        m.title.text = PorticoFeedbackCopy("feedback.heading.message", "Message server owner")
    end if
    m.section.text = PorticoFeedbackCopy("feedback.what-happened", "What happened?")
    m.privacy.text = PorticoFeedbackCopy("feedback.privacy", "Only information related to this issue will be included.")
    status = ""
    feedbackStatus = ""
    if state <> invalid then feedbackStatus = LCase(PorticoCoreSafeText(state.feedbackStatus, 24))
    if feedbackStatus = "loading" then status = PorticoFeedbackCopy("state.loading", "Loading")
    if feedbackStatus = "sending" then status = PorticoFeedbackCopy("action.sending-message", "Sending")
    if feedbackStatus = "sent" then status = PorticoFeedbackCopy("feedback.sent", "Message sent")
    if feedbackStatus = "error" then status = PorticoFeedbackCopy("feedback.load-failed", "Unable to send message")
    m.status.text = status

    for index = 0 to m.kindButtons.Count() - 1
        button = m.kindButtons[index]
        button.visible = index < m.allowedKinds.Count()
        if index < m.allowedKinds.Count()
            kind = m.allowedKinds[index]
            button.model = {label: PorticoFeedbackCopy("feedback.kind." + kind, PorticoFeedbackTitleCase(kind)), iconId: "action.feedback", width: 194, primary: kind = m.kind}
            button.focused = m.area = "kind" and index = m.kindFocus
        end if
    end for
    for index = 0 to m.categoryButtons.Count() - 1
        button = m.categoryButtons[index]
        button.visible = index < m.categories.Count()
        if index < m.categories.Count()
            category = m.categories[index]
            button.model = {label: PorticoFeedbackCopy("feedback.category." + category, PorticoFeedbackTitleCase(category)), iconId: "navigation.disclosure", width: 840, primary: category = m.category}
            button.focused = m.area = "category" and index = m.categoryFocus
        end if
    end for
    sent = feedbackStatus = "sent"
    m.send.model = {label: PorticoFeedbackCopy("action.send-message", "Send message"), iconId: "action.confirm", width: 232, primary: true}
    if sent then m.send.model = {label: PorticoFeedbackCopy("action.done", "Done"), iconId: "action.confirm", width: 232, primary: true}
    m.send.focused = m.area = "actions" and m.actionFocus = 0
    m.cancel.model = {label: PorticoFeedbackCopy("action.close", "Close"), iconId: "action.close", width: 210}
    m.cancel.focused = m.area = "actions" and m.actionFocus = 1
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press or not m.top.visible then return false
    if key = "back"
        PorticoFeedbackEmit("close-feedback", {})
        return true
    end if
    if m.area = "kind"
        if key = "left" and m.kindFocus > 0 then m.kindFocus = m.kindFocus - 1
        if key = "right" and m.kindFocus < m.allowedKinds.Count() - 1 then m.kindFocus = m.kindFocus + 1
        if key = "down" then m.area = "category"
        if key = "OK"
            m.kind = m.allowedKinds[m.kindFocus]
            m.categories = PorticoFeedbackCategories(m.kind)
            m.categoryFocus = 0
            m.category = m.categories[0]
        end if
    else if m.area = "category"
        if key = "up"
            if m.categoryFocus > 0 then m.categoryFocus = m.categoryFocus - 1 else m.area = "kind"
        else if key = "down"
            if m.categoryFocus < m.categories.Count() - 1 then m.categoryFocus = m.categoryFocus + 1 else m.area = "actions"
        else if key = "OK"
            m.category = m.categories[m.categoryFocus]
        end if
    else
        if key = "left" then m.actionFocus = 0
        if key = "right" then m.actionFocus = 1
        if key = "up" then m.area = "category"
        if key = "OK"
            if m.actionFocus = 1
                PorticoFeedbackEmit("close-feedback", {})
            else
                state = m.top.viewState
                if state <> invalid and LCase(PorticoCoreSafeText(state.feedbackStatus, 24)) = "sent"
                    PorticoFeedbackEmit("close-feedback", {})
                else
                    fields = {feedbackKind: m.kind, category: m.category}
                    for each name in m.context
                        fields[name] = m.context[name]
                    end for
                    PorticoFeedbackEmit("submit-feedback", fields)
                end if
            end if
        end if
    end if
    PorticoFeedbackRender()
    return true
end function

sub PorticoFeedbackEmit(kind as string, fields as object)
    m.sequence = m.sequence + 1
    activation = {sequence: m.sequence, kind: kind}
    for each key in fields
        activation[key] = fields[key]
    end for
    m.top.activation = activation
end sub

function PorticoFeedbackCopy(messageId as string, fallback as string) as string
    if m.language = invalid then return fallback
    message = PorticoProductLanguageMessage(m.language, messageId, messageId, {})
    if message.ok
        text = PorticoCoreSafeText(message.text, 240)
        if text = "" then text = PorticoCoreSafeText(message.title, 240)
        if text = "" then text = PorticoCoreSafeText(message.body, 240)
        if text <> "" then return text
    end if
    return fallback
end function

function PorticoFeedbackKind(value as dynamic) as string
    kind = LCase(PorticoCoreSafeText(value, 24))
    if kind = "general" or kind = "playback" or kind = "media" or kind = "quality" then return kind
    return ""
end function

function PorticoFeedbackCategories(kind as string) as object
    if kind = "playback" then return ["wont-play", "buffering", "playback-stopped", "wrong-video", "wrong-audio", "wrong-subtitles", "other"]
    if kind = "media" then return ["incorrect-media-information", "wrong-video", "wrong-audio", "wrong-subtitles", "other"]
    if kind = "quality" then return ["higher-quality-request", "other"]
    return ["other"]
end function

function PorticoFeedbackContains(values as object, target as string) as boolean
    for each value in values
        if value = target then return true
    end for
    return false
end function

function PorticoFeedbackId(value as dynamic) as string
    if value = invalid then return ""
    result = value.ToStr().Trim()
    if Len(result) < 1 or Len(result) > 128 then return ""
    for position = 1 to Len(result)
        code = Asc(Mid(result, position, 1))
        if code < 32 or code = 127 then return ""
    end for
    return result
end function

function PorticoFeedbackTitleCase(value as string) as string
    words = value.Replace("-", " ").Tokenize(" ")
    result = ""
    for each word in words
        if word <> ""
            if result <> "" then result = result + " "
            result = result + UCase(Left(word, 1)) + Mid(word, 2)
        end if
    end for
    return result
end function
