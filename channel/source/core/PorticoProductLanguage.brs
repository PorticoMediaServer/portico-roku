function PorticoProductLanguageLoad() as object
    loaded = PorticoCoreReadGeneratedDocument("pkg:/data/generated/product-language.v1.json", 524288)
    if not loaded.ok then return loaded
    checked = PorticoProductLanguageValidate(loaded.value)
    if not checked.ok then return { ok: false, code: checked.code, value: invalid }
    icons = PorticoIconResolverLoad()
    loaded.value.iconManifest = invalid
    if icons.ok then loaded.value.iconManifest = icons.value
    return { ok: true, code: "", value: loaded.value }
end function

function PorticoProductLanguageValidate(document as dynamic) as object
    envelope = PorticoCoreGeneratedEnvelope(document)
    if not envelope.ok then return envelope
    catalog = document.catalog
    if not PorticoCoreIsAssociativeArray(catalog) then return { ok: false, code: "invalid_product_language" }
    if catalog.revision <> "v1" or catalog.locale <> "en-US" or catalog.fallbackLocale <> "en-US" or catalog.iconFamily <> "lucide"
        return { ok: false, code: "incompatible_product_language" }
    end if
    if not PorticoCoreIsAssociativeArray(catalog.messages) or not PorticoCoreIsAssociativeArray(catalog.icons)
        return { ok: false, code: "invalid_product_language" }
    end if
    if not PorticoCoreIsAssociativeArray(document.problemCodeMessages) or not PorticoCoreIsAssociativeArray(document.rokuIconAssets) or not PorticoCoreIsArray(document.allowedParameters)
        return { ok: false, code: "invalid_product_language" }
    end if
    if catalog.messages.Count() < 1 or catalog.messages.Count() > 2500 or catalog.icons.Count() < 1 or catalog.icons.Count() > 256
        return { ok: false, code: "product_language_out_of_bounds" }
    end if
    return { ok: true, code: "" }
end function

function PorticoProductLanguageKnownMessageId(document as dynamic, value as dynamic) as string
    if not PorticoProductLanguageValidate(document).ok then return ""
    identifier = PorticoCoreSafeIdentifier(value, 120)
    if identifier = "" or document.catalog.messages[identifier] = invalid then return ""
    return identifier
end function

function PorticoProductLanguageKnownIconId(document as dynamic, value as dynamic) as string
    if not PorticoProductLanguageValidate(document).ok then return ""
    identifier = PorticoCoreSafeIdentifier(value, 120)
    if identifier = "" or document.catalog.icons[identifier] = invalid then return ""
    return identifier
end function

function PorticoProductLanguageInterpolate(document as object, template as dynamic, variables as dynamic) as string
    result = PorticoCoreSafeText(template, 2048)
    if result = "" or not PorticoCoreIsAssociativeArray(variables) then return result
    for each rawName in document.allowedParameters
        name = PorticoCoreSafeIdentifier(rawName, 60)
        if name <> "" and variables[name] <> invalid
            replacement = PorticoCoreSafeText(variables[name], 120)
            result = result.Replace("{" + name + "}", replacement)
            if Len(result) > 2048 then result = Left(result, 2048)
        end if
    end for
    return result
end function

function PorticoProductLanguageIconUri(document as dynamic, iconId as dynamic) as string
    if document = invalid or document.iconManifest = invalid then return ""
    return PorticoIconResolverUri(document.iconManifest, iconId, "default")
end function

function PorticoProductLanguageMessage(document as dynamic, requestedId as dynamic, fallbackId as string, variables as dynamic) as object
    checked = PorticoProductLanguageValidate(document)
    if not checked.ok then return PorticoProductLanguageEmergencyMessage(checked.code)
    messageId = PorticoProductLanguageKnownMessageId(document, requestedId)
    if messageId = "" then messageId = PorticoProductLanguageKnownMessageId(document, fallbackId)
    if messageId = "" then return PorticoProductLanguageEmergencyMessage("product_language_message_unavailable")
    definition = document.catalog.messages[messageId]
    if not PorticoCoreIsAssociativeArray(definition) then return PorticoProductLanguageEmergencyMessage("product_language_message_invalid")

    tone = PorticoCoreSafeIdentifier(definition.tone, 20)
    if tone <> "success" and tone <> "warning" and tone <> "error" then tone = "neutral"
    iconId = PorticoProductLanguageKnownIconId(document, definition.icon)
    actions = []
    if PorticoCoreIsArray(definition.actions)
        for each rawActionId in definition.actions
            if actions.Count() >= 8 then exit for
            actionId = PorticoProductLanguageKnownMessageId(document, rawActionId)
            if Left(actionId, 7) = "action."
                actionDefinition = document.catalog.messages[actionId]
                if PorticoCoreIsAssociativeArray(actionDefinition)
                    label = PorticoProductLanguageInterpolate(document, actionDefinition.text, variables)
                    if label <> "" then actions.Push({ id: actionId, label: label })
                end if
            end if
        end for
    end if
    return {
        ok: true,
        code: "",
        id: messageId,
        title: PorticoProductLanguageInterpolate(document, definition.title, variables),
        body: PorticoProductLanguageInterpolate(document, definition.body, variables),
        text: PorticoProductLanguageInterpolate(document, definition.text, variables),
        iconId: iconId,
        iconUri: PorticoProductLanguageIconUri(document, iconId),
        tone: tone,
        actions: actions
    }
end function

function PorticoProductLanguageResolveProblem(document as dynamic, problem as dynamic, variables as dynamic) as object
    checked = PorticoProductLanguageValidate(document)
    if not checked.ok then return PorticoProductLanguageEmergencyMessage(checked.code)
    safeProblem = problem
    if not PorticoCoreIsAssociativeArray(safeProblem) then safeProblem = {}
    safeVariables = {}
    if PorticoCoreIsAssociativeArray(safeProblem.details)
        safeVariables.serverName = PorticoCoreSafeText(safeProblem.details.serverName, 120)
        safeVariables.profileName = PorticoCoreSafeText(safeProblem.details.profileName, 120)
        if PorticoCoreIsNumber(safeProblem.details.capacity) then safeVariables.capacity = safeProblem.details.capacity
        if PorticoCoreIsNumber(safeProblem.details.demand) then safeVariables.demand = safeProblem.details.demand
    end if
    if PorticoCoreIsAssociativeArray(variables)
        for each rawName in document.allowedParameters
            name = PorticoCoreSafeIdentifier(rawName, 60)
            if name <> "" and variables[name] <> invalid then safeVariables[name] = PorticoCoreSafeText(variables[name], 120)
        end for
    end if

    messageId = PorticoProductLanguageKnownMessageId(document, safeProblem.messageId)
    if messageId = ""
        code = PorticoCoreSafeIdentifier(safeProblem.code, 120)
        if code <> "" then messageId = PorticoProductLanguageKnownMessageId(document, document.problemCodeMessages[code])
    end if
    if messageId = ""
        status = PorticoCoreSafeInteger(safeProblem.status, 0, 0, 599)
        if status = 401
            ' A bare endpoint 401 is ambiguous (stale access token, deployment
            ' skew, or request policy). Only stable terminal problem codes above
            ' may tell the user their long-lived session expired.
            messageId = "problem.request-failed"
        else if status = 403
            messageId = "problem.forbidden"
        else if status = 404
            messageId = "problem.not-found"
        else if status = 408 or status = 504
            messageId = "problem.timeout"
        else if status = 429
            messageId = "problem.rate-limited"
        else if status = 502 or status = 503
            messageId = "problem.server-unavailable"
        else
            messageId = "problem.request-failed"
        end if
    end if
    return PorticoProductLanguageMessage(document, messageId, "problem.request-failed", safeVariables)
end function

function PorticoProductLanguageEmergencyMessage(code as string) as object
    return {
        ok: false,
        code: PorticoCoreSafeIdentifier(code, 80),
        id: "",
        title: "Portico couldn't complete this request",
        body: "Please try again.",
        text: "",
        iconId: "",
        iconUri: "",
        tone: "error",
        actions: []
    }
end function
