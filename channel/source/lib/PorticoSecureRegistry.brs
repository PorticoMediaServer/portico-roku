function PorticoSecureRegistryVersion() as integer
    return 1
end function

function PorticoSecureRegistryMaximumCiphertextLength() as integer
    ' The largest durable caches are bounded, normalized projections. Four MiB
    ' of base64 ciphertext leaves substantial forward-compatible headroom while
    ' preventing corrupt channel-local registry data from driving an unbounded
    ' decode/decrypt allocation.
    return 4194304
end function

function PorticoSecureRegistrySection(recordType as string) as dynamic
    if recordType <> "pending-account-authorization" and recordType <> "account-credentials" and recordType <> "account-refresh-rotation" and recordType <> "account-server-catalog" and recordType <> "server-session" and recordType <> "pending-server-session" and recordType <> "server-refresh-rotation" and recordType <> "local-auth-trust" and recordType <> "profile-launch" and recordType <> "pending-deep-link" and recordType <> "profile-selection-handoff" and recordType <> "playback-mutation" and recordType <> "navigation" and recordType <> "content-cache" and recordType <> "library-cache" and recordType <> "saved-cache" and recordType <> "channels-cache" then return invalid
    return CreateObject("roRegistrySection", "portico.secure." + recordType + ".v1")
end function

function PorticoSecureRegistryRotationKey() as string
    deviceInfo = CreateObject("roDeviceInfo")
    if deviceInfo = invalid then return ""
    first = deviceInfo.GetRandomUUID()
    second = deviceInfo.GetRandomUUID()
    if first = invalid or second = invalid then return ""
    key = first.ToStr().Replace("-", "") + second.ToStr().Replace("-", "")
    if Len(key) < 43 or Len(key) > 128 then return ""
    return key
end function

function PorticoSecureRegistryRead(recordType as string) as object
    section = PorticoSecureRegistrySection(recordType)
    if section = invalid then return { ok: false, code: "storage_unavailable", payload: invalid, generation: 0 }

    consumingRaw = section.Read("consumingGeneration")
    if consumingRaw <> invalid and consumingRaw.ToStr().Trim() <> ""
        return { ok: false, code: "consumption_interrupted", payload: invalid, generation: 0 }
    end if

    committedRaw = section.Read("committedGeneration")
    if committedRaw = invalid or committedRaw.Trim() = ""
        return { ok: true, code: "not_found", payload: invalid, generation: 0 }
    end if

    generation = Int(Val(committedRaw))
    if generation < 1 then return { ok: false, code: "invalid_commit_marker", payload: invalid, generation: 0 }
    schemaRaw = section.Read("schemaVersion")
    if schemaRaw = invalid or Int(Val(schemaRaw)) <> PorticoSecureRegistryVersion() then return { ok: false, code: "invalid_schema_marker", payload: invalid, generation: generation }
    encoded = section.Read("generation." + generation.ToStr())
    if encoded = invalid or encoded = "" then return { ok: false, code: "committed_generation_missing", payload: invalid, generation: generation }

    envelope = PorticoSecureRegistryDecrypt(encoded)
    if envelope = invalid or Type(envelope) <> "roAssociativeArray"
        return { ok: false, code: "credential_decryption_failed", payload: invalid, generation: generation }
    end if
    if envelope.version <> PorticoSecureRegistryVersion() or envelope.generation <> generation or envelope.recordType <> recordType
        return { ok: false, code: "credential_envelope_invalid", payload: invalid, generation: generation }
    end if
    if envelope.payload = invalid or Type(envelope.payload) <> "roAssociativeArray"
        return { ok: false, code: "credential_payload_invalid", payload: invalid, generation: generation }
    end if
    return { ok: true, code: "ok", payload: envelope.payload, generation: generation }
end function

function PorticoSecureRegistryCommit(recordType as string, payload as dynamic) as object
    if payload = invalid or Type(payload) <> "roAssociativeArray"
        return { ok: false, code: "credential_payload_invalid", generation: 0 }
    end if
    section = PorticoSecureRegistrySection(recordType)
    if section = invalid then return { ok: false, code: "storage_unavailable", generation: 0 }

    consumingRaw = section.Read("consumingGeneration")
    if consumingRaw <> invalid and consumingRaw.ToStr().Trim() <> ""
        return { ok: false, code: "consumption_interrupted", generation: 0 }
    end if
    committedRaw = section.Read("committedGeneration")
    committedGeneration = 0
    if committedRaw <> invalid and committedRaw.ToStr().Trim() <> ""
        committedGeneration = Int(Val(committedRaw))
        if committedGeneration < 1 then return { ok: false, code: "invalid_commit_marker", generation: 0 }
        schemaRaw = section.Read("schemaVersion")
        if schemaRaw = invalid or Int(Val(schemaRaw)) <> PorticoSecureRegistryVersion() then return { ok: false, code: "invalid_schema_marker", generation: committedGeneration }
    end if
    nextGeneration = committedGeneration + 1

    envelope = {
        version: PorticoSecureRegistryVersion(),
        generation: nextGeneration,
        recordType: recordType,
        payload: payload
    }
    encrypted = PorticoSecureRegistryEncrypt(envelope)
    if encrypted = "" then return { ok: false, code: "credential_encryption_failed", generation: committedGeneration }

    nextKey = "generation." + nextGeneration.ToStr()
    if not section.Write(nextKey, encrypted) then return { ok: false, code: "generation_write_failed", generation: committedGeneration }
    if not section.Flush() then return { ok: false, code: "generation_flush_failed", generation: committedGeneration }

    if not section.Write("schemaVersion", PorticoSecureRegistryVersion().ToStr())
        return { ok: false, code: "version_write_failed", generation: committedGeneration }
    end if
    if not section.Write("committedGeneration", nextGeneration.ToStr())
        return { ok: false, code: "commit_marker_write_failed", generation: committedGeneration }
    end if
    if not section.Flush() then return { ok: false, code: "commit_marker_flush_failed", generation: committedGeneration }

    if committedGeneration > 0 and committedGeneration <> nextGeneration
        section.Delete("generation." + committedGeneration.ToStr())
        section.Flush()
    end if
    return { ok: true, code: "ok", generation: nextGeneration }
end function

function PorticoSecureRegistryConsume(recordType as string) as object
    section = PorticoSecureRegistrySection(recordType)
    if section = invalid then return { ok: false, code: "storage_unavailable", payload: invalid, generation: 0 }

    consumingRaw = section.Read("consumingGeneration")
    if consumingRaw <> invalid and consumingRaw.ToStr().Trim() <> ""
        return { ok: false, code: "consumption_interrupted", payload: invalid, generation: 0 }
    end if

    committedRaw = section.Read("committedGeneration")
    if committedRaw = invalid or committedRaw.ToStr().Trim() = ""
        return { ok: true, code: "not_found", payload: invalid, generation: 0 }
    end if
    generation = Int(Val(committedRaw))
    if generation < 1 then return { ok: false, code: "invalid_commit_marker", payload: invalid, generation: 0 }
    schemaRaw = section.Read("schemaVersion")
    if schemaRaw = invalid or Int(Val(schemaRaw)) <> PorticoSecureRegistryVersion()
        return { ok: false, code: "invalid_schema_marker", payload: invalid, generation: generation }
    end if

    encoded = section.Read("generation." + generation.ToStr())
    if encoded = invalid or encoded = "" then return { ok: false, code: "committed_generation_missing", payload: invalid, generation: generation }
    envelope = PorticoSecureRegistryDecrypt(encoded)
    if envelope = invalid or Type(envelope) <> "roAssociativeArray"
        return { ok: false, code: "credential_decryption_failed", payload: invalid, generation: generation }
    end if
    if envelope.version <> PorticoSecureRegistryVersion() or envelope.generation <> generation or envelope.recordType <> recordType
        return { ok: false, code: "credential_envelope_invalid", payload: invalid, generation: generation }
    end if
    if envelope.payload = invalid or Type(envelope.payload) <> "roAssociativeArray"
        return { ok: false, code: "credential_payload_invalid", payload: invalid, generation: generation }
    end if

    ' Mark the consumption before deleting the committed record. If a process
    ' dies after this flush, future reads and commits fail closed instead of
    ' replaying or silently replacing an ambiguous one-time handoff.
    if not section.Write("consumingGeneration", generation.ToStr()) then return { ok: false, code: "consume_marker_write_failed", payload: invalid, generation: generation }
    if not section.Flush() then return { ok: false, code: "consume_marker_flush_failed", payload: invalid, generation: generation }

    section.Delete("generation." + generation.ToStr())
    section.Delete("committedGeneration")
    section.Delete("schemaVersion")
    if not section.Flush() then return { ok: false, code: "consume_flush_failed", payload: invalid, generation: generation }

    section.Delete("consumingGeneration")
    if not section.Flush() then return { ok: false, code: "consume_marker_clear_failed", payload: invalid, generation: generation }
    return { ok: true, code: "ok", payload: envelope.payload, generation: generation }
end function

function PorticoSecureRegistryClear(recordType as string) as boolean
    section = PorticoSecureRegistrySection(recordType)
    if section = invalid then return false
    keys = section.GetKeyList()
    if keys <> invalid
        for each key in keys
            section.Delete(key)
        end for
    end if
    return section.Flush()
end function

function PorticoSecureRegistryEncrypt(envelope as object) as string
    crypto = CreateObject("roDeviceCrypto")
    plaintext = CreateObject("roByteArray")
    if crypto = invalid or plaintext = invalid then return ""
    plaintext.FromAsciiString(FormatJson(envelope))
    encrypted = crypto.Encrypt(plaintext, "channel")
    if encrypted = invalid then return ""
    encoded = encrypted.ToBase64String()
    if Len(encoded) < 8 or Len(encoded) > PorticoSecureRegistryMaximumCiphertextLength() then return ""
    return encoded
end function

function PorticoSecureRegistryDecrypt(encoded as string) as dynamic
    if Len(encoded) < 8 or Len(encoded) > PorticoSecureRegistryMaximumCiphertextLength() then return invalid
    crypto = CreateObject("roDeviceCrypto")
    encrypted = CreateObject("roByteArray")
    if crypto = invalid or encrypted = invalid then return invalid
    encrypted.FromBase64String(encoded)
    if encrypted.Count() = 0 then return invalid
    plaintext = crypto.Decrypt(encrypted, "channel")
    if plaintext = invalid then return invalid
    return ParseJson(plaintext.ToAsciiString())
end function

function PorticoInstallationId() as string
    section = CreateObject("roRegistrySection", "portico.installation.v1")
    if section <> invalid
        existing = section.Read("installationId")
        if existing <> invalid and Len(existing.Trim()) >= 8 then return existing.Trim()
    end if

    deviceInfo = CreateObject("roDeviceInfo")
    identifier = ""
    if deviceInfo <> invalid
        randomId = deviceInfo.GetRandomUUID()
        if randomId <> invalid and Len(randomId.Trim()) >= 8 then identifier = "roku-" + randomId.Trim()
    end if
    if identifier = "" then return ""

    if section <> invalid and section.Write("installationId", identifier) and section.Flush() then return identifier
    return ""
end function
