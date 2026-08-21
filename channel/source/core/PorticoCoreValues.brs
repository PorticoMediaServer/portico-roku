function PorticoCoreIsAssociativeArray(value as dynamic) as boolean
    return value <> invalid and Type(value) = "roAssociativeArray"
end function

function PorticoCoreIsArray(value as dynamic) as boolean
    return value <> invalid and GetInterface(value, "ifArray") <> invalid
end function

function PorticoCoreIsString(value as dynamic) as boolean
    if value = invalid then return false
    valueType = Type(value)
    return valueType = "String" or valueType = "roString"
end function

function PorticoCoreIsNumber(value as dynamic) as boolean
    if value = invalid then return false
    valueType = Type(value)
    return valueType = "Integer" or valueType = "LongInteger" or valueType = "Float" or valueType = "Double" or valueType = "roInt" or valueType = "roLongInteger" or valueType = "roFloat" or valueType = "roDouble"
end function

function PorticoCoreScalarString(value as dynamic, fallback as string) as string
    if PorticoCoreIsString(value) then return value.ToStr()
    if PorticoCoreIsNumber(value) then return value.ToStr()
    if value <> invalid and (Type(value) = "Boolean" or Type(value) = "roBoolean")
        if value then return "true"
        return "false"
    end if
    return fallback
end function

function PorticoCoreSafeText(value as dynamic, maximumLength as integer) as string
    if maximumLength < 0 then return ""
    normalized = PorticoCoreScalarString(value, "")
    safe = ""
    for index = 1 to Len(normalized)
        character = Mid(normalized, index, 1)
        code = Asc(character)
        if code >= 32 and code <> 127 then safe = safe + character
        if Len(safe) >= maximumLength then exit for
    end for
    return safe.Trim()
end function

function PorticoCoreSafeIdentifier(value as dynamic, maximumLength as integer) as string
    normalized = PorticoCoreSafeText(value, maximumLength)
    if normalized = "" then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    for index = 1 to Len(normalized)
        if Instr(1, allowed, Mid(normalized, index, 1)) = 0 then return ""
    end for
    return normalized
end function

function PorticoCoreArrayContains(values as dynamic, expected as string) as boolean
    if not PorticoCoreIsArray(values) then return false
    for each value in values
        if PorticoCoreIsString(value) and value.ToStr() = expected then return true
    end for
    return false
end function

function PorticoCoreReadGeneratedDocument(path as string, maximumBytes as integer) as object
    if Left(path, 20) <> "pkg:/data/generated/" then return { ok: false, code: "generated_path_not_allowed", value: invalid }
    if Instr(1, path, "..") > 0 or Instr(1, path, "\\") > 0 or Instr(1, path, "?") > 0 or Instr(1, path, "#") > 0
        return { ok: false, code: "generated_path_not_allowed", value: invalid }
    end if
    if maximumBytes < 1 or maximumBytes > 1048576 then return { ok: false, code: "invalid_generated_limit", value: invalid }

    fileSystem = CreateObject("roFileSystem")
    if fileSystem = invalid then return { ok: false, code: "generated_storage_unavailable", value: invalid }
    metadata = fileSystem.Stat(path)
    if not PorticoCoreIsAssociativeArray(metadata) or metadata.type <> "file"
        return { ok: false, code: "generated_document_unavailable", value: invalid }
    end if
    if not PorticoCoreIsNumber(metadata.size) or metadata.size < 2 or metadata.size > maximumBytes
        return { ok: false, code: "generated_document_out_of_bounds", value: invalid }
    end if
    encoded = ReadAsciiFile(path)
    if encoded = "" or Len(encoded) > maximumBytes then return { ok: false, code: "generated_document_out_of_bounds", value: invalid }
    parsed = ParseJson(encoded)
    if not PorticoCoreIsAssociativeArray(parsed) then return { ok: false, code: "generated_document_invalid", value: invalid }
    return { ok: true, code: "", value: parsed }
end function

function PorticoCoreGeneratedEnvelope(document as dynamic) as object
    if not PorticoCoreIsAssociativeArray(document) then return { ok: false, code: "invalid_generated_envelope" }
    if document.schemaVersion <> 1 or document.generatorRevision <> 1 then return { ok: false, code: "unsupported_generated_envelope" }
    return { ok: true, code: "" }
end function

function PorticoCoreCloneStringArray(values as dynamic, maximumItems as integer, maximumLength as integer) as object
    result = []
    if not PorticoCoreIsArray(values) or maximumItems < 1 then return result
    for each value in values
        if result.Count() >= maximumItems then exit for
        normalized = PorticoCoreSafeText(value, maximumLength)
        if normalized <> "" then result.Push(normalized)
    end for
    return result
end function

function PorticoCoreSafeInteger(value as dynamic, fallback as integer, minimum as integer, maximum as integer) as integer
    if not PorticoCoreIsNumber(value) then return fallback
    normalized = Int(value)
    if normalized < minimum or normalized > maximum then return fallback
    return normalized
end function

