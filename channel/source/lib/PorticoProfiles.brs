function PorticoProfilesSafeId(value as dynamic) as string
    if value = invalid then return ""
    result = value.ToStr().Replace(Chr(0), "").Trim()
    if Len(result) < 1 or Len(result) > 128 then return ""
    for index = 1 to Len(result)
        character = Mid(result, index, 1)
        code = Asc(character)
        if code < 32 or code = 127 then return ""
    end for
    return result
end function

function PorticoProfilesSafeText(value as dynamic, maximum as integer) as string
    if value = invalid then return ""
    result = value.ToStr().Replace(Chr(0), "").Replace(Chr(10), " ").Replace(Chr(13), " ").Replace(Chr(9), " ").Trim()
    if Len(result) > maximum then result = Left(result, maximum)
    return result
end function

function PorticoProfilesInteger(value as dynamic, fallback as integer) as integer
    if value = invalid then return fallback
    kind = LCase(Type(value))
    if kind = "integer" or kind = "roint" or kind = "longinteger" or kind = "rolonginteger" or kind = "float" or kind = "rofloat" or kind = "double" or kind = "rodouble" then return Int(value)
    return fallback
end function

function PorticoProfilesPolicy(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> "v1" then return invalid
    age = invalid
    if value.maximumAgeRating <> invalid
        age = PorticoProfilesInteger(value.maximumAgeRating, -1)
        if age < 0 or age > 21 then return invalid
    end if
    for each key in ["allowUnrated", "allowDownloads", "allowLiveTV", "allowDvr", "allowWatchWithFriends", "allowFeedback"]
        if Type(value[key]) <> "roBoolean" and Type(value[key]) <> "Boolean" then return invalid
    end for
    labels = []
    if value.blockedLabels = invalid or GetInterface(value.blockedLabels, "ifArray") = invalid or value.blockedLabels.Count() > 64 then return invalid
    seen = {}
    for each raw in value.blockedLabels
        label = PorticoProfilesSafeText(raw, 128)
        lookup = LCase(label)
        if label = "" or seen[lookup] = true then return invalid
        seen[lookup] = true
        labels.Push(label)
    end for
    return {
        version: "v1", maximumAgeRating: age, allowUnrated: value.allowUnrated = true,
        blockedLabels: labels, allowDownloads: value.allowDownloads = true,
        allowLiveTV: value.allowLiveTV = true, allowDvr: value.allowDvr = true,
        allowWatchWithFriends: value.allowWatchWithFriends = true, allowFeedback: value.allowFeedback = true
    }
end function

function PorticoProfilesProfile(value as dynamic) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    id = PorticoProfilesSafeId(value.id)
    name = PorticoProfilesSafeText(value.name, 80)
    policy = PorticoProfilesPolicy(value.policy)
    pinRevision = PorticoProfilesInteger(value.pinRevision, -1)
    sortOrder = PorticoProfilesInteger(value.sortOrder, -1)
    if id = "" or name = "" or policy = invalid or pinRevision < 0 or sortOrder < 0 then return invalid
    if (value.isPrimary = true) <> (value.isAccountAdmin = true) then return invalid
    avatar = invalid
    if value.avatar <> invalid and Type(value.avatar) = "roAssociativeArray"
        avatarKind = LCase(PorticoProfilesSafeText(value.avatar.kind, 16))
        reference = PorticoProfilesSafeText(value.avatar.reference, 512)
        if (avatarKind = "preset" or avatarKind = "custom") and reference <> "" then avatar = {kind: avatarKind, reference: reference}
    end if
    return {
        id: id, name: name, avatar: avatar, isPrimary: value.isPrimary = true,
        isAccountAdmin: value.isAccountAdmin = true, hasPIN: value.hasPIN = true,
        pinRevision: pinRevision, sortOrder: sortOrder, policy: policy
    }
end function

function PorticoProfilesDirectory(value as dynamic, authority as string, accountId as string, serverId as string) as dynamic
    if value = invalid or Type(value) <> "roAssociativeArray" then return invalid
    normalizedAuthority = LCase(authority)
    if normalizedAuthority <> "hosted" and normalizedAuthority <> "local" then return invalid
    expectedAccount = PorticoProfilesSafeId(accountId)
    expectedServer = PorticoProfilesSafeId(serverId)
    sourceAccount = PorticoProfilesSafeId(value.accountId)
    sourceServer = PorticoProfilesSafeId(value.serverId)
    if expectedAccount = "" or expectedServer = "" or sourceAccount <> expectedAccount then return invalid
    if sourceServer <> "" and sourceServer <> expectedServer then return invalid
    if value.profiles = invalid or GetInterface(value.profiles, "ifArray") = invalid or value.profiles.Count() < 1 or value.profiles.Count() > 8 then return invalid
    revision = PorticoProfilesInteger(value.revision, 0)
    if normalizedAuthority = "hosted" and revision < 1 then return invalid
    profiles = []
    ids = {}
    primaryCount = 0
    for each raw in value.profiles
        profile = PorticoProfilesProfile(raw)
        if profile = invalid or ids[profile.id] = true then return invalid
        ids[profile.id] = true
        if profile.isPrimary then primaryCount = primaryCount + 1
        profiles.Push(profile)
    end for
    if primaryCount <> 1 then return invalid
    profiles.SortBy("sortOrder")
    return {authority: normalizedAuthority, accountId: expectedAccount, serverId: expectedServer, revision: revision, profilesAllowed: value.profilesAllowed <> false, profiles: profiles}
end function

function PorticoProfilesFind(directory as dynamic, profileId as string) as dynamic
    if directory = invalid or directory.profiles = invalid then return invalid
    safeId = PorticoProfilesSafeId(profileId)
    for each profile in directory.profiles
        if profile.id = safeId then return profile
    end for
    return invalid
end function

function PorticoProfilesSelectionDecision(directory as dynamic, mode as string, lastProfileId as string, trust as dynamic) as object
    if directory = invalid or directory.profiles = invalid or directory.profiles.Count() = 0 then return {kind: "unavailable"}
    eligible = directory.profiles
    if directory.profilesAllowed = false
        for each profile in directory.profiles
            if profile.isPrimary then eligible = [profile]
        end for
    end if
    if eligible.Count() = 1
        if eligible[0].hasPIN then return {kind: "pin", profile: eligible[0]}
        return {kind: "open", profile: eligible[0]}
    end if
    if LCase(mode) = "last-used"
        remembered = PorticoProfilesFind(directory, lastProfileId)
        if remembered <> invalid and PorticoProfilesTrustMatches(trust, directory, remembered)
            return {kind: "open", profile: remembered}
        end if
    end if
    return {kind: "select", profiles: eligible}
end function

function PorticoProfilesTrustMatches(value as dynamic, directory as dynamic, profile as dynamic) as boolean
    if value = invalid or Type(value) <> "roAssociativeArray" or value.version <> "v1" or value.purpose <> "automatic-profile-selection" then return false
    if LCase(PorticoProfilesSafeText(value.authority, 16)) <> directory.authority then return false
    if PorticoProfilesSafeId(value.accountId) <> directory.accountId or PorticoProfilesSafeId(value.serverId) <> directory.serverId then return false
    if PorticoProfilesSafeId(value.profileId) <> profile.id then return false
    if PorticoProfilesInteger(value.pinRevision, -1) <> profile.pinRevision then return false
    token = PorticoProfilesSafeText(value.token, 4096)
    expiresAt = PorticoProfilesSafeText(value.expiresAt, 64)
    if token = "" or expiresAt = "" then return false
    timer = CreateObject("roTimespan")
    if timer = invalid then return false
    return timer.GetSecondsToISO8601Date(expiresAt) > 0
end function

function PorticoProfilesSafeProjection(directory as dynamic) as dynamic
    if directory = invalid then return invalid
    projected = []
    for each profile in directory.profiles
        item = {
            id: profile.id, name: profile.name,
            isPrimary: profile.isPrimary, isAccountAdmin: profile.isAccountAdmin,
            hasPIN: profile.hasPIN, pinRevision: profile.pinRevision, sortOrder: profile.sortOrder,
            capabilities: {
                liveTV: profile.policy.allowLiveTV, dvr: profile.policy.allowDvr,
                watchWithFriends: profile.policy.allowWatchWithFriends, feedback: profile.policy.allowFeedback
            }
        }
        projected.Push(item)
    end for
    return {revision: PorticoProfilesInteger(directory.revision, 0), profilesAllowed: directory.profilesAllowed, profiles: projected}
end function

function PorticoProfilesSafePin(value as dynamic) as string
    pin = PorticoProfilesSafeText(value, 4)
    if Len(pin) <> 4 then return ""
    for index = 1 to 4
        digit = Mid(pin, index, 1)
        if digit < "0" or digit > "9" then return ""
    end for
    return pin
end function

function PorticoProfilesSealPin(pinValue as dynamic, profileId as dynamic, viewerGeneration as dynamic) as string
    pin = PorticoProfilesSafePin(pinValue)
    id = PorticoProfilesSafeId(profileId)
    generation = PorticoProfilesInteger(viewerGeneration, 0)
    if pin = "" or id = "" or generation < 1 then return ""
    crypto = CreateObject("roDeviceCrypto")
    plaintext = CreateObject("roByteArray")
    if crypto = invalid or plaintext = invalid then return ""
    plaintext.FromAsciiString(FormatJson({version: 1, purpose: "profile-pin", profileId: id, viewerGeneration: generation, pin: pin}))
    pin = ""
    encrypted = crypto.Encrypt(plaintext, "channel")
    plaintext.Clear()
    if encrypted = invalid then return ""
    return encrypted.ToBase64String()
end function

function PorticoProfilesUnsealPin(sealedValue as dynamic, profileId as dynamic, viewerGeneration as dynamic) as string
    if sealedValue = invalid or Len(sealedValue.ToStr()) > 8192 then return ""
    sealedPin = PorticoProfilesSafeText(sealedValue, 8192)
    id = PorticoProfilesSafeId(profileId)
    generation = PorticoProfilesInteger(viewerGeneration, 0)
    if sealedPin = "" or id = "" or generation < 1 then return ""
    crypto = CreateObject("roDeviceCrypto")
    encrypted = CreateObject("roByteArray")
    if crypto = invalid or encrypted = invalid then return ""
    encrypted.FromBase64String(sealedPin)
    sealedPin = ""
    if encrypted.Count() = 0 then return ""
    plaintext = crypto.Decrypt(encrypted, "channel")
    encrypted.Clear()
    if plaintext = invalid then return ""
    payload = ParseJson(plaintext.ToAsciiString())
    plaintext.Clear()
    if payload = invalid or payload.version <> 1 or payload.purpose <> "profile-pin" then return ""
    if PorticoProfilesSafeId(payload.profileId) <> id or PorticoProfilesInteger(payload.viewerGeneration, 0) <> generation then return ""
    pin = PorticoProfilesSafePin(payload.pin)
    payload.pin = ""
    return pin
end function

function PorticoProfilesSelectionTransactionMaximumCiphertextLength() as integer
    return 4194304
end function

function PorticoProfilesSelectionTransactionWrite(transactionId as string, envelope as dynamic, authority as string, accountId as string, serverId as string, profileId as string, viewerGeneration as integer) as boolean
    id = PorticoProfilesSafeId(transactionId)
    normalizedAuthority = LCase(PorticoProfilesSafeText(authority, 16))
    safeAccountId = PorticoProfilesSafeId(accountId)
    safeServerId = PorticoProfilesSafeId(serverId)
    safeProfileId = PorticoProfilesSafeId(profileId)
    if id = "" or (normalizedAuthority <> "hosted" and normalizedAuthority <> "local") or safeAccountId = "" or safeServerId = "" or safeProfileId = "" or viewerGeneration < 1 then return false
    if envelope = invalid or Type(envelope) <> "roAssociativeArray" or envelope.version <> "v1" then return false
    payload = {
        version: 1, purpose: "profile-selection-handoff", transactionId: id,
        authority: normalizedAuthority, accountId: safeAccountId, serverId: safeServerId, profileId: safeProfileId,
        viewerGeneration: viewerGeneration,
        expiresAt: envelope.expiresAt, selectionEnvelope: envelope
    }
    committed = PorticoSecureRegistryCommit("profile-selection-handoff", payload)
    payload.selectionEnvelope = invalid
    return committed.ok
end function

function PorticoProfilesSelectionTransactionConsume(transactionId as string, authority as string, accountId as string, serverId as string, profileId as string, viewerGeneration as integer) as dynamic
    normalizedAuthority = LCase(PorticoProfilesSafeText(authority, 16))
    stored = PorticoSecureRegistryRead("profile-selection-handoff")
    if not stored.ok or stored.payload = invalid then return invalid
    if not PorticoProfilesSelectionTransactionMatches(stored.payload, transactionId, normalizedAuthority, accountId, serverId, profileId, viewerGeneration) then return invalid
    payloadResult = PorticoSecureRegistryConsume("profile-selection-handoff")
    if not payloadResult.ok or payloadResult.payload = invalid then return invalid
    payload = payloadResult.payload
    if not PorticoProfilesSelectionTransactionMatches(payload, transactionId, normalizedAuthority, accountId, serverId, profileId, viewerGeneration) then return invalid
    selectionEnvelope = payload.selectionEnvelope
    payload.selectionEnvelope = invalid
    return selectionEnvelope
end function

function PorticoProfilesSelectionTransactionMatches(payload as dynamic, transactionId as string, authority as string, accountId as string, serverId as string, profileId as string, viewerGeneration as integer) as boolean
    if payload = invalid or Type(payload) <> "roAssociativeArray" or payload.version <> 1 or payload.purpose <> "profile-selection-handoff" then return false
    if PorticoProfilesSafeId(payload.transactionId) <> PorticoProfilesSafeId(transactionId) then return false
    if payload.authority <> authority or PorticoProfilesSafeId(payload.accountId) <> PorticoProfilesSafeId(accountId) or PorticoProfilesSafeId(payload.serverId) <> PorticoProfilesSafeId(serverId) then return false
    if PorticoProfilesSafeId(payload.profileId) <> PorticoProfilesSafeId(profileId) then return false
    if PorticoProfilesInteger(payload.viewerGeneration, -1) <> viewerGeneration then return false
    if payload.selectionEnvelope = invalid or Type(payload.selectionEnvelope) <> "roAssociativeArray" then return false
    timer = CreateObject("roTimespan")
    if timer = invalid or timer.GetSecondsToISO8601Date(PorticoProfilesSafeText(payload.expiresAt, 64)) <= 0 then return false
    return true
end function

sub PorticoProfilesSelectionTransactionClear()
    PorticoSecureRegistryClear("profile-selection-handoff")
end sub
