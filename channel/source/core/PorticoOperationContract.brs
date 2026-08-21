function PorticoOperationContractLoad() as object
    loaded = PorticoCoreReadGeneratedDocument("pkg:/data/generated/operations.v1.json", 262144)
    if not loaded.ok then return loaded
    checked = PorticoOperationContractValidate(loaded.value)
    if not checked.ok then return { ok: false, code: checked.code, value: invalid }
    return { ok: true, code: "", value: loaded.value }
end function

function PorticoOperationContractValidate(document as dynamic) as object
    envelope = PorticoCoreGeneratedEnvelope(document)
    if not envelope.ok then return envelope
    if not PorticoCoreIsArray(document.operations) then return { ok: false, code: "invalid_operation_contract" }
    if document.operations.Count() < 1 or document.operations.Count() > 600 then return { ok: false, code: "operation_contract_out_of_bounds" }
    return { ok: true, code: "" }
end function

function PorticoOperationContractFind(document as dynamic, service as string, operationId as dynamic) as dynamic
    if not PorticoOperationContractValidate(document).ok then return invalid
    if service <> "server" and service <> "hosted" then return invalid
    identifier = PorticoCoreSafeIdentifier(operationId, 160)
    if identifier = "" then return invalid
    for each operation in document.operations
        if PorticoCoreIsAssociativeArray(operation) and operation.service = service and operation.operationId = identifier
            if PorticoOperationContractRecordAllowed(operation) then return operation
            return invalid
        end if
    end for
    return invalid
end function

function PorticoOperationContractRecordAllowed(operation as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(operation) then return false
    if operation.service = "server"
        if operation.audience <> "viewer" then return false
        if operation.auth <> "session" and operation.auth <> "public" and operation.auth <> "media-grant-or-session" then return false
        if not PorticoCoreArrayContains(operation.surfaces, "television") then return false
    else if operation.service = "hosted"
        if operation.audience <> "television-client" then return false
        if operation.auth <> "public" and operation.auth <> "scoped_secret" and operation.auth <> "hosted_account" and operation.auth <> "mixed_scoped_dispatcher" then return false
    else
        return false
    end if
    method = PorticoCoreSafeText(operation.method, 10)
    if method <> "GET" and method <> "POST" and method <> "PUT" and method <> "PATCH" and method <> "DELETE" and method <> "HEAD" then return false
    path = PorticoCoreSafeText(operation.path, 512)
    if Left(path, 1) <> "/" or Instr(1, path, "..") > 0 or Instr(1, path, "\\") > 0 or Instr(1, path, "?") > 0 or Instr(1, path, "#") > 0 then return false
    return true
end function

function PorticoOperationContractResolvePath(document as dynamic, service as string, operationId as dynamic, inputs as dynamic) as object
    operation = PorticoOperationContractFind(document, service, operationId)
    if operation = invalid then return { ok: false, code: "operation_not_allowed", path: "", method: "" }
    path = operation.path
    safeInputs = inputs
    if not PorticoCoreIsAssociativeArray(safeInputs) then safeInputs = {}
    start = Instr(1, path, "{")
    replacements = 0
    while start > 0
        finish = Instr(start + 1, path, "}")
        if finish = 0 then return { ok: false, code: "invalid_operation_template", path: "", method: "" }
        name = Mid(path, start + 1, finish - start - 1)
        if PorticoCoreSafeIdentifier(name, 80) <> name then return { ok: false, code: "invalid_operation_template", path: "", method: "" }
        value = PorticoCoreSafeText(safeInputs[name], 240)
        if value = "" then return { ok: false, code: "operation_input_required", path: "", method: "" }
        transfer = CreateObject("roUrlTransfer")
        if transfer = invalid then return { ok: false, code: "url_encoding_unavailable", path: "", method: "" }
        encoded = transfer.Escape(value)
        if encoded = "" then return { ok: false, code: "operation_input_invalid", path: "", method: "" }
        path = Left(path, start - 1) + encoded + Mid(path, finish + 1)
        replacements = replacements + 1
        if replacements > 16 or Len(path) > 1024 then return { ok: false, code: "operation_path_out_of_bounds", path: "", method: "" }
        start = Instr(1, path, "{")
    end while
    if Instr(1, path, "}") > 0 or Left(path, 1) <> "/" then return { ok: false, code: "invalid_operation_template", path: "", method: "" }
    return { ok: true, code: "", path: path, method: operation.method, operationId: operation.operationId, service: service }
end function
