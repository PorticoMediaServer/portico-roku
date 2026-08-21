sub init()
    m.top.functionName = "PorticoExecuteHttpRequest"
end sub

sub PorticoExecuteHttpRequest()
    request = PorticoHttpNormalizeRequest(m.top.request)
    validation = PorticoHttpValidateRequest(request)
    if not validation.ok
        classification = PorticoHttpClassifyFailure("request")
        result = PorticoHttpBaseResult(request, classification)
        result.problem = {
            type: "about:blank",
            title: "Invalid request",
            status: 0,
            code: validation.code,
            detail: validation.message,
            instance: "",
            requestId: request.requestId
        }
        PorticoHttpPublishResult(result)
        return
    end if

    if m.top.cancelRequested
        PorticoHttpPublishResult(PorticoHttpFailureResult(request, "cancelled", 0))
        return
    end if

    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    if port = invalid or transfer = invalid
        PorticoHttpPublishResult(PorticoHttpFailureResult(request, "transport", 0))
        return
    end if

    transfer.SetMessagePort(port)
    transfer.SetUrl(request.url)
    transfer.SetRequest(request.method)
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)

    if Left(LCase(request.url), 8) = "https://"
        certificatesConfigured = transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        peerVerificationEnabled = transfer.EnablePeerVerification(true)
        hostVerificationEnabled = transfer.EnableHostVerification(true)
        if not certificatesConfigured or not peerVerificationEnabled or not hostVerificationEnabled
            PorticoHttpPublishResult(PorticoHttpFailureResult(request, "transport", 0))
            return
        end if
    end if

    headersAdded = true
    for each headerName in request.headers
        if not transfer.AddHeader(headerName, request.headers[headerName]) then headersAdded = false
    end for
    if not headersAdded
        PorticoHttpPublishResult(PorticoHttpFailureResult(request, "request", 0))
        return
    end if

    issued = PorticoHttpIssueTransfer(transfer, request.method, request.body, request.responsePath)
    if not issued
        PorticoHttpPublishResult(PorticoHttpFailureResult(request, "transport", 0))
        return
    end if

    timer = CreateObject("roTimespan")
    timer.Mark()
    transferIdentity = transfer.GetIdentity()
    limits = PorticoHttpLimits()

    while true
        if m.top.cancelRequested
            transfer.AsyncCancel()
            PorticoHttpDeleteResponseFile(request)
            PorticoHttpPublishResult(PorticoHttpFailureResult(request, "cancelled", 0))
            return
        end if

        elapsedMs = timer.TotalMilliseconds()
        if elapsedMs >= request.timeoutMs
            transfer.AsyncCancel()
            PorticoHttpDeleteResponseFile(request)
            result = PorticoHttpFailureResult(request, "timeout", 0)
            result.elapsedMs = elapsedMs
            PorticoHttpPublishResult(result)
            return
        end if

        remainingMs = request.timeoutMs - elapsedMs
        waitMs = limits.pollIntervalMs
        if remainingMs < waitMs then waitMs = remainingMs
        if waitMs < 1 then waitMs = 1
        message = Wait(waitMs, port)

        if message <> invalid and Type(message) = "roUrlEvent" and message.GetSourceIdentity() = transferIdentity
            result = PorticoHttpResultFromEvent(request, message)
            result.elapsedMs = timer.TotalMilliseconds()
            PorticoHttpPublishResult(result)
            return
        end if
    end while
end sub

function PorticoHttpIssueTransfer(transfer as object, method as string, body as string, responsePath as string) as boolean
    if method = "HEAD" then return transfer.AsyncHead()
    if body <> "" or method = "POST" or method = "PUT" or method = "PATCH"
        return transfer.AsyncPostFromString(body)
    end if
    if responsePath = "" then return transfer.AsyncGetToString()
    return transfer.AsyncGetToFile(responsePath)
end function

function PorticoHttpResultFromEvent(request as object, event as object) as object
    status = event.GetResponseCode()
    if status < 0
        result = PorticoHttpFailureResult(request, "transport", status)
        result.transportCode = status
        return result
    end if

    classification = PorticoHttpClassifyStatus(status)
    result = PorticoHttpBaseResult(request, classification)
    result.status = status
    result.responseHeaders = PorticoHttpResponseHeaders(event.GetResponseHeadersArray())
    result.retryAfterSeconds = PorticoHttpRetryAfterSeconds(result.responseHeaders)

    budget = PorticoHttpResponseBudget(result.responseHeaders)
    if not budget.ok then return PorticoHttpResponseTooLarge(result, request, status)
    bodyResult = PorticoHttpReadResponseBody(request, event, budget)
    if not bodyResult.ok then return PorticoHttpResponseTooLarge(result, request, status)
    body = bodyResult.body
    shouldParseJson = request.expectJson or PorticoHttpIsJsonContentType(result.responseHeaders)
    parsed = { ok: true, empty: true, value: invalid }
    if shouldParseJson then parsed = PorticoHttpParseJson(body)

    if classification.classification = "success"
        if shouldParseJson and not parsed.ok
            parseClassification = PorticoHttpClassifyFailure("parse")
            result.ok = false
            result.classification = parseClassification.classification
            result.retryable = parseClassification.retryable
            result.recommendedAction = parseClassification.recommendedAction
            result.authAction = parseClassification.authAction
            result.refreshEligible = parseClassification.refreshEligible
            result.problem = {
                type: "about:blank",
                title: "Invalid response",
                status: status,
                code: PorticoHttpFallbackProblemCode(parseClassification.classification),
                detail: PorticoHttpFallbackMessage(parseClassification.classification),
                instance: "",
                requestId: request.requestId
            }
        else
            result.ok = true
            if shouldParseJson
                result.data = parsed.value
            else
                result.data = body
            end if
        end if
    else
        problemPayload = invalid
        if parsed.ok then problemPayload = parsed.value
        result.bodyParseError = shouldParseJson and not parsed.ok
        result.problem = PorticoHttpNormalizeProblem(status, problemPayload, result.responseHeaders, request.requestId, result.classification)
    end if

    result.diagnostic = PorticoHttpDiagnostic(result)
    return result
end function

function PorticoHttpReadResponseBody(request as object, event as object, budget as object) as object
    if request.method = "HEAD"
        PorticoHttpDeleteResponseFile(request)
        return {ok: true, body: ""}
    end if

    maximumBytes = budget.materializationLimit
    path = PorticoHttpScalarString(request.responsePath, "")
    if request.method = "GET" and path <> ""
        size = PorticoHttpFileSize(path)
        if size < 0 or size > maximumBytes
            PorticoHttpDeleteResponseFile(request)
            return {ok: false, body: ""}
        end if
        if budget.declaredLength <> invalid and size > budget.declaredLength
            PorticoHttpDeleteResponseFile(request)
            return {ok: false, body: ""}
        end if
        body = ReadAsciiFile(path)
        PorticoHttpDeleteResponseFile(request)
        if Len(body) > maximumBytes then return {ok: false, body: ""}
        return {ok: true, body: body}
    end if

    ' Mutation responses are returned by roUrlTransfer as an event string. If
    ' the peer did not provide a trustworthy fixed length, fail closed before
    ' calling GetString(); this avoids turning an unbounded/chunked response
    ' into a BrightScript string merely to measure it.
    if budget.trustedLength <> true then return {ok: false, body: ""}
    if budget.declaredLength = 0 then return {ok: true, body: ""}
    body = event.GetString()
    if Len(body) > maximumBytes then return {ok: false, body: ""}
    if budget.declaredLength <> invalid and Len(body) > budget.declaredLength then return {ok: false, body: ""}
    return {ok: true, body: body}
end function

function PorticoHttpResponseTooLarge(result as object, request as object, status as integer) as object
    PorticoHttpDeleteResponseFile(request)
    parseClassification = PorticoHttpClassifyFailure("parse")
    result.ok = false
    result.classification = parseClassification.classification
    result.retryable = parseClassification.retryable
    result.recommendedAction = parseClassification.recommendedAction
    result.authAction = parseClassification.authAction
    result.refreshEligible = parseClassification.refreshEligible
    result.problem = {
        type: "about:blank",
        title: "Invalid response",
        status: status,
        code: "response_too_large",
        detail: PorticoHttpFallbackMessage(parseClassification.classification),
        instance: "",
        requestId: request.requestId
    }
    result.diagnostic = PorticoHttpDiagnostic(result)
    return result
end function

sub PorticoHttpDeleteResponseFile(request as object)
    path = PorticoHttpScalarString(request.responsePath, "")
    if path <> "" then DeleteFile(path)
end sub

function PorticoHttpFailureResult(request as object, failureKind as string, transportCode as integer) as object
    PorticoHttpDeleteResponseFile(request)
    classification = PorticoHttpClassifyFailure(failureKind)
    result = PorticoHttpBaseResult(request, classification)
    result.transportCode = transportCode
    result.timedOut = classification.classification = "timeout"
    result.cancelled = classification.classification = "cancelled"
    result.problem = {
        type: "about:blank",
        title: "Request failed",
        status: 0,
        code: PorticoHttpFallbackProblemCode(classification.classification),
        detail: PorticoHttpFallbackMessage(classification.classification),
        instance: "",
        requestId: request.requestId
    }
    result.diagnostic = PorticoHttpDiagnostic(result)
    return result
end function

function PorticoHttpBaseResult(request as object, classification as object) as object
    return {
        ok: false,
        operationId: request.operationId,
        generationId: request.generationId,
        requestId: request.requestId,
        method: request.method,
        url: PorticoHttpRedactUrl(request.url),
        status: 0,
        classification: classification.classification,
        retryable: classification.retryable,
        recommendedAction: classification.recommendedAction,
        authAction: classification.authAction,
        refreshEligible: classification.refreshEligible,
        timedOut: false,
        cancelled: false,
        bodyParseError: false,
        retryAfterSeconds: invalid,
        transportCode: 0,
        elapsedMs: 0,
        responseHeaders: {},
        data: invalid,
        problem: invalid,
        diagnostic: ""
    }
end function

function PorticoHttpRetryAfterSeconds(headers as object) as dynamic
    value = PorticoHttpScalarString(headers["retry-after"], "").Trim()
    if value = "" then return invalid
    for position = 1 to Len(value)
        if Instr(1, "0123456789", Mid(value, position, 1)) = 0 then return invalid
    end for
    seconds = Int(Val(value))
    if seconds < 0 then return invalid
    if seconds > 86400 then seconds = 86400
    return seconds
end function

function PorticoHttpDiagnostic(result as object) as string
    return "http_result classification=" + result.classification + " status=" + result.status.ToStr() + " operation=" + result.operationId + " request=" + result.requestId
end function

sub PorticoHttpPublishResult(result as object)
    if result.diagnostic = "" then result.diagnostic = PorticoHttpDiagnostic(result)
    m.top.result = result
end sub
