function PorticoHttpLimits() as object
    return {
        defaultTimeoutMs: 15000,
        minimumTimeoutMs: 1000,
        maximumTimeoutMs: 30000,
        pollIntervalMs: 100,
        maximumUrlLength: 4096,
        maximumBodyBytes: 1048576,
        maximumResponseBytes: 2097152,
        maximumArtworkBytes: 4194304,
        maximumHeaderCount: 50,
        maximumHeaderNameLength: 128,
        maximumHeaderValueLength: 8192,
        maximumIdentifierLength: 200,
        maximumSafeMessageLength: 1000
    }
end function

function PorticoHttpSupportedMethods() as object
    return {
        GET: true,
        HEAD: true,
        POST: true,
        PUT: true,
        PATCH: true,
        DELETE: true
    }
end function

function PorticoHttpClassifyStatus(status as integer) as object
    if status >= 200 and status <= 299
        return PorticoHttpClassification("success", false, "none")
    else if status = 400
        return PorticoHttpClassification("bad_request", false, "none")
    else if status = 401
        return PorticoHttpClassification("authentication_required", false, "refresh_once")
    else if status = 403
        return PorticoHttpClassification("forbidden", false, "none")
    else if status = 409
        return PorticoHttpClassification("conflict", false, "reload_authoritative_state")
    else if status = 422
        return PorticoHttpClassification("unprocessable", false, "remove_unsupported_option")
    else if status = 429
        return PorticoHttpClassification("throttled", true, "honor_retry_after")
    else if status >= 500 and status <= 599
        return PorticoHttpClassification("server_error", true, "retry_with_budget")
    else if status >= 400 and status <= 499
        return PorticoHttpClassification("client_error", false, "none")
    else if status >= 300 and status <= 399
        return PorticoHttpClassification("redirect_error", false, "none")
    end if

    return PorticoHttpClassification("protocol_error", false, "none")
end function

function PorticoHttpClassifyFailure(kind as string) as object
    normalized = LCase(kind.Trim())
    if normalized = "timeout"
        return PorticoHttpClassification("timeout", true, "retry_with_budget")
    else if normalized = "cancelled"
        return PorticoHttpClassification("cancelled", false, "none")
    else if normalized = "transport"
        return PorticoHttpClassification("transport_error", true, "retry_with_budget")
    else if normalized = "parse"
        return PorticoHttpClassification("parse_error", false, "none")
    else if normalized = "request"
        return PorticoHttpClassification("request_error", false, "none")
    end if

    return PorticoHttpClassification("unknown_error", false, "none")
end function

function PorticoHttpClassification(classification as string, retryable as boolean, recommendedAction as string) as object
    authAction = "none"
    if recommendedAction = "refresh_once" then authAction = "refresh_once"
    return {
        classification: classification,
        retryable: retryable,
        recommendedAction: recommendedAction,
        authAction: authAction,
        refreshEligible: recommendedAction = "refresh_once"
    }
end function

function PorticoHttpFallbackProblemCode(classification as string) as string
    codes = {
        bad_request: "bad_request",
        authentication_required: "authentication_required",
        forbidden: "forbidden",
        conflict: "conflict",
        unprocessable: "unprocessable_request",
        throttled: "rate_limited",
        server_error: "server_error",
        client_error: "request_failed",
        redirect_error: "unexpected_redirect",
        protocol_error: "protocol_error",
        timeout: "request_timeout",
        cancelled: "request_cancelled",
        transport_error: "network_unavailable",
        parse_error: "invalid_response",
        request_error: "invalid_request",
        unknown_error: "request_failed"
    }
    if codes[classification] <> invalid then return codes[classification]
    return "request_failed"
end function

function PorticoHttpFallbackMessage(classification as string) as string
    messages = {
        bad_request: "The request could not be completed.",
        authentication_required: "Sign-in is required to continue.",
        forbidden: "This account does not have access to that action.",
        conflict: "This item changed. Reload it and try again.",
        unprocessable: "That option is not available for this item.",
        throttled: "Too many requests were made. Try again shortly.",
        server_error: "The server could not complete the request.",
        client_error: "The request could not be completed.",
        redirect_error: "The server returned an unexpected redirect.",
        protocol_error: "The server returned an unexpected response.",
        timeout: "The request took too long. Try again.",
        cancelled: "The request was cancelled.",
        transport_error: "The service could not be reached.",
        parse_error: "The server returned an invalid response.",
        request_error: "The request is not valid.",
        unknown_error: "The request could not be completed."
    }
    if messages[classification] <> invalid then return messages[classification]
    return "The request could not be completed."
end function
