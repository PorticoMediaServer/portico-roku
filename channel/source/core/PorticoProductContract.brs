function PorticoProductContractLoad() as object
    loaded = PorticoCoreReadGeneratedDocument("pkg:/data/generated/product-contract.v1.json", 524288)
    if not loaded.ok then return loaded
    checked = PorticoProductContractValidateGenerated(loaded.value)
    if not checked.ok then return { ok: false, code: checked.code, value: invalid }
    return { ok: true, code: "", value: loaded.value }
end function

' Sole packaged discovery source. Callers cannot supply or override a revision:
' both the generated contract and its manifest entry are validated here.
function PorticoProductContractDiscoveryEnvelope() as object
    contractResult = PorticoProductContractLoad()
    if not contractResult.ok then return {ok: false, code: contractResult.code, productContractRevision: ""}
    manifestResult = PorticoCoreReadGeneratedDocument("pkg:/data/generated/manifest.v1.json", 32768)
    if not manifestResult.ok then return {ok: false, code: manifestResult.code, productContractRevision: ""}
    manifest = manifestResult.value
    if not PorticoCoreGeneratedEnvelope(manifest).ok or not PorticoCoreIsArray(manifest.artifacts)
        return {ok: false, code: "invalid_generated_manifest", productContractRevision: ""}
    end if
    artifact = invalid
    for each candidate in manifest.artifacts
        if PorticoCoreIsAssociativeArray(candidate) and candidate.name = "product-contract.v1.json" then artifact = candidate
    end for
    if artifact = invalid then return {ok: false, code: "product_contract_manifest_missing", productContractRevision: ""}
    encoded = ReadAsciiFile("pkg:/data/generated/product-contract.v1.json")
    if encoded = "" or not PorticoCoreIsNumber(artifact.bytes) or artifact.bytes <> Len(encoded)
        return {ok: false, code: "product_contract_manifest_size_mismatch", productContractRevision: ""}
    end if
    digest = CreateObject("roEVPDigest")
    bytes = CreateObject("roByteArray")
    if digest = invalid or bytes = invalid or not digest.Setup("sha256")
        return {ok: false, code: "product_contract_digest_unavailable", productContractRevision: ""}
    end if
    bytes.FromAsciiString(encoded)
    encoded = ""
    digest.Process(bytes)
    bytes.Clear()
    hashBytes = digest.Final()
    if hashBytes = invalid then return {ok: false, code: "product_contract_digest_unavailable", productContractRevision: ""}
    actualHash = LCase(hashBytes.ToHexString())
    hashBytes.Clear()
    expectedHash = LCase(PorticoCoreSafeText(artifact.sha256, 64))
    if Len(expectedHash) <> 64 or actualHash <> expectedHash
        return {ok: false, code: "product_contract_manifest_hash_mismatch", productContractRevision: ""}
    end if
    contract = contractResult.value.contract
    return {
        ok: true, code: "", productContractRevision: contract.semanticIdentity.digest,
        apiVersion: contract.apiVersion, languageRevision: contract.language.revision
    }
end function

function PorticoProductContractValidateGenerated(document as dynamic) as object
    envelope = PorticoCoreGeneratedEnvelope(document)
    if not envelope.ok then return envelope
    if not PorticoCoreIsAssociativeArray(document.rokuPolicy) then return { ok: false, code: "invalid_roku_product_policy" }
    if document.snapshotRole <> "build-time-validation-and-conformance-only" then return { ok: false, code: "invalid_product_contract_snapshot_role" }
    if document.rokuPolicy.platform <> "roku" or document.rokuPolicy.deviceClass <> "television" or document.rokuPolicy.unknownActions <> "hide"
        return { ok: false, code: "incompatible_roku_product_policy" }
    end if
    if not PorticoCoreIsArray(document.rokuPolicy.consumerActionAllowlist) or not PorticoCoreIsArray(document.rokuPolicy.forbiddenActionGroups) or not PorticoCoreIsArray(document.rokuPolicy.forbiddenActionIds)
        return { ok: false, code: "invalid_roku_product_policy" }
    end if
    checked = PorticoProductContractValidate(document.contract)
    if not checked.ok then return checked
    actionIds = PorticoProductContractIdentifierSet(document.contract.mediaActions, "id", 128, 120)
    if actionIds = invalid then return {ok: false, code: "invalid_roku_product_policy"}
    if not PorticoProductContractStringArrayValid(document.rokuPolicy.consumerActionAllowlist, 128, 120, true, actionIds, false) then return {ok: false, code: "invalid_roku_product_policy"}
    if not PorticoProductContractStringArrayValid(document.rokuPolicy.forbiddenActionIds, 128, 120, true, actionIds, false) then return {ok: false, code: "invalid_roku_product_policy"}
    groups = {playback: true, saved: true, state: true, administration: true, feedback: true}
    if not PorticoProductContractStringArrayValid(document.rokuPolicy.forbiddenActionGroups, 16, 40, true, groups, false) then return {ok: false, code: "invalid_roku_product_policy"}
    return { ok: true, code: "" }
end function

function PorticoProductContractValidateLive(contract as dynamic) as object
    ' The packaged contract is a drift/conformance snapshot. Feature projection
    ' must pass the contract fetched from /api/product-contract through here.
    return PorticoProductContractValidate(contract)
end function

function PorticoProductContractValidate(contract as dynamic) as object
    if not PorticoCoreIsAssociativeArray(contract) then return { ok: false, code: "invalid_product_contract" }
    if not PorticoProductContractKeysAllowed(contract, {apiVersion: true, actionRevision: true, semanticIdentity: true, language: true, libraryKinds: true, entityKinds: true, entitySemantics: true, artworkRoles: true, browseFields: true, browseSorts: true, browseOperators: true, presentationFields: true, queryLimits: true, search: true, mediaActions: true, serverCapabilities: true, eventTransports: true, longPoll: true, applicationEvents: true}, 19) then return {ok: false, code: "invalid_product_contract"}
    if contract.apiVersion <> "v1" or contract.actionRevision <> "v1" then return { ok: false, code: "incompatible_product_contract" }
    if not PorticoProductContractSemanticIdentityValid(contract.semanticIdentity) then return {ok: false, code: "incompatible_product_contract_semantics"}
    if not PorticoProductContractLanguageValid(contract.language) then return {ok: false, code: "incompatible_product_language_reference"}

    if not PorticoProductContractStringArrayValid(contract.entityKinds, 128, 80, true, invalid, true) then return {ok: false, code: "invalid_product_contract_entity_kinds"}
    if not PorticoProductContractStringArrayValid(contract.presentationFields, 128, 80, true, invalid, false) then return {ok: false, code: "invalid_product_contract_presentation_fields"}
    if not PorticoProductContractStringArrayValid(contract.serverCapabilities, 256, 120, true, invalid, false) then return {ok: false, code: "invalid_product_contract_capabilities"}
    if not PorticoProductContractValidateEventTransports(contract.eventTransports) then return {ok: false, code: "invalid_product_contract_event_transport"}
    if not PorticoProductContractValidateLongPoll(contract.longPoll) then return {ok: false, code: "invalid_product_contract_long_poll"}
    if not PorticoProductContractValidateApplicationEvents(contract.applicationEvents) then return {ok: false, code: "invalid_product_contract_application_events"}
    entityKinds = PorticoProductContractStringSet(contract.entityKinds)
    presentationFields = PorticoProductContractStringSet(contract.presentationFields)
    if entityKinds = invalid or presentationFields = invalid then return {ok: false, code: "invalid_product_contract"}

    artworkRoles = PorticoProductContractValidateArtworkRoles(contract.artworkRoles)
    if not artworkRoles.ok then return artworkRoles
    operators = PorticoProductContractValidateOperators(contract.browseOperators)
    if not operators.ok then return operators
    sorts = PorticoProductContractValidateBrowseSorts(contract.browseSorts, entityKinds)
    if not sorts.ok then return sorts
    fields = PorticoProductContractValidateBrowseFields(contract.browseFields, entityKinds, operators.typesById)
    if not fields.ok then return fields
    semantics = PorticoProductContractValidateEntitySemantics(contract.entitySemantics, entityKinds, artworkRoles.ids)
    if not semantics.ok then return semantics
    libraries = PorticoProductContractValidateLibraryKinds(contract.libraryKinds, entityKinds, presentationFields, sorts.ids)
    if not libraries.ok then return libraries
    limits = PorticoProductContractValidateQueryLimits(contract.queryLimits)
    if not limits.ok then return limits
    search = PorticoProductContractValidateSearch(contract.search, entityKinds)
    if not search.ok then return search
    actions = PorticoProductContractValidateMediaActions(contract.mediaActions)
    if not actions.ok then return actions
    return { ok: true, code: "" }
end function

' Product semantics are identified independently from build and endpoint API
' revisions. The System document and Product Contract must name the exact same
' immutable semantic payload before any contract-derived behavior is published.
function PorticoProductContractSemanticIdentityValid(value as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(value) then return false
    if not PorticoProductContractKeysAllowed(value, {id: true, revision: true, digestAlgorithm: true, digest: true}, 4) then return false
    if value.Count() <> 4 then return false
    if value.id <> "portico.product-contract" or value.revision <> "v2" or value.digestAlgorithm <> "sha256" then return false
    digest = PorticoProductContractRequiredText(value.digest, 64)
    if Len(digest) <> 64 or digest <> LCase(digest) then return false
    hexadecimal = {"0": true, "1": true, "2": true, "3": true, "4": true, "5": true, "6": true, "7": true, "8": true, "9": true, a: true, b: true, c: true, d: true, e: true, f: true}
    for index = 1 to 64
        if hexadecimal[Mid(digest, index, 1)] <> true then return false
    end for
    return true
end function

function PorticoProductContractSemanticIdentityEquals(left as dynamic, right as dynamic) as boolean
    if not PorticoProductContractSemanticIdentityValid(left) or not PorticoProductContractSemanticIdentityValid(right) then return false
    return left.id = right.id and left.revision = right.revision and left.digestAlgorithm = right.digestAlgorithm and left.digest = right.digest
end function

function PorticoProductContractSystemSupports(system as dynamic, contract as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(system) or system.apiVersion <> "v1" then return false
    compatibility = system.compatibility
    if not PorticoCoreIsAssociativeArray(compatibility) then return false
    if not PorticoProductContractIntegerInRange(compatibility.envelopeRevision, 2, 2) then return false
    protocol = compatibility.supportedClientProtocol
    if not PorticoCoreIsAssociativeArray(protocol) then return false
    if not PorticoProductContractIntegerInRange(protocol.minimum, 1, 1) then return false
    if not PorticoProductContractIntegerInRange(protocol.maximum, 1, 2147483647) then return false
    semanticDocuments = compatibility.semanticDocuments
    if not PorticoCoreIsAssociativeArray(semanticDocuments) then return false
    return PorticoProductContractSemanticIdentityEquals(semanticDocuments.productContract, contract.semanticIdentity)
end function

function PorticoProductContractValidateEventTransports(transports as dynamic) as boolean
    allowed = {sse: true, "long-poll": true}
    return PorticoProductContractStringArrayValid(transports, 2, 9, true, allowed, true)
end function

function PorticoProductContractValidateLongPoll(longPoll as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(longPoll) then return false
    if not PorticoProductContractKeysAllowed(longPoll, {defaultWaitSeconds: true, maximumWaitSeconds: true, maximumConcurrentStreams: true}, 3) then return false
    if longPoll.Count() <> 3 then return false
    if not PorticoProductContractIntegerInRange(longPoll.defaultWaitSeconds, 20, 20) then return false
    if not PorticoProductContractIntegerInRange(longPoll.maximumWaitSeconds, 25, 25) then return false
    return PorticoProductContractIntegerInRange(longPoll.maximumConcurrentStreams, 4, 4)
end function

function PorticoProductContractValidateApplicationEvents(value as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(value) then return false
    if not PorticoProductContractKeysAllowed(value, {revision: true, eventTypes: true, tags: true, authoritativeResetErrorCodes: true, longPollResetField: true}, 5) then return false
    if value.Count() <> 5 or value.revision <> "v1" or value.longPollResetField <> "resetRequired" then return false
    eventTypes = {"data.changed": true, "library.scan.completed": true}
    if not PorticoProductContractStringArrayValid(value.eventTypes, 2, 80, true, eventTypes, true) then return false
    if value.eventTypes.Count() <> 2 then return false
    if not PorticoProductContractStringArrayValid(value.tags, 64, 120, true, invalid, true) then return false
    resetCodes = {invalid_poll_cursor: true}
    if not PorticoProductContractStringArrayValid(value.authoritativeResetErrorCodes, 1, 80, true, resetCodes, true) then return false
    return value.authoritativeResetErrorCodes.Count() = 1
end function

function PorticoProductContractLanguageValid(value as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(value) then return false
    if not PorticoProductContractKeysAllowed(value, {revision: true, defaultLocale: true, supportedLocales: true, endpointTemplate: true, iconFamily: true}, 5) then return false
    if value.revision <> "v1" or value.iconFamily <> "lucide" or value.endpointTemplate <> "/api/product-language/{locale}" then return false
    locale = PorticoProductContractRequiredText(value.defaultLocale, 32)
    if locale = "" then return false
    if not PorticoProductContractStringArrayValid(value.supportedLocales, 16, 32, false, invalid, true) then return false
    return PorticoCoreArrayContains(value.supportedLocales, locale)
end function

function PorticoProductContractValidateArtworkRoles(values as dynamic) as object
    if not PorticoCoreIsArray(values) or values.Count() < 1 or values.Count() > 32 then return {ok: false, code: "invalid_product_contract_artwork_roles"}
    ids = {}
    for each role in values
        if not PorticoCoreIsAssociativeArray(role) then return {ok: false, code: "invalid_product_contract_artwork_role"}
        if not PorticoProductContractKeysAllowed(role, {id: true, aspectRatio: true, fit: true, purpose: true}, 4) then return {ok: false, code: "invalid_product_contract_artwork_role"}
        id = PorticoProductContractRequiredIdentifier(role.id, 80)
        if id = "" or ids[id] = true then return {ok: false, code: "invalid_product_contract_artwork_role"}
        if not PorticoCoreIsNumber(role.aspectRatio) or role.aspectRatio <= 0 or role.aspectRatio > 100 then return {ok: false, code: "invalid_product_contract_artwork_role"}
        if role.fit <> "cover" and role.fit <> "contain" then return {ok: false, code: "invalid_product_contract_artwork_role"}
        if PorticoProductContractRequiredText(role.purpose, 512) = "" then return {ok: false, code: "invalid_product_contract_artwork_role"}
        ids[id] = true
    end for
    return {ok: true, code: "", ids: ids}
end function

function PorticoProductContractValidateOperators(values as dynamic) as object
    if not PorticoCoreIsArray(values) or values.Count() < 1 or values.Count() > 32 then return {ok: false, code: "invalid_product_contract_operators"}
    allowedTypes = {boolean: true, "enum": true, number: true, string: true, date: true, duration: true, "identity-set": true, presence: true}
    ids = {}
    typesById = {}
    for each item in values
        if not PorticoCoreIsAssociativeArray(item) then return {ok: false, code: "invalid_product_contract_operator"}
        if not PorticoProductContractKeysAllowed(item, {id: true, valueTypes: true}, 2) then return {ok: false, code: "invalid_product_contract_operator"}
        id = PorticoProductContractRequiredIdentifier(item.id, 80)
        if id = "" or ids[id] = true then return {ok: false, code: "invalid_product_contract_operator"}
        if not PorticoProductContractStringArrayValid(item.valueTypes, 16, 32, true, allowedTypes, true) then return {ok: false, code: "invalid_product_contract_operator"}
        ids[id] = true
        typesById[id] = PorticoProductContractStringSet(item.valueTypes)
    end for
    return {ok: true, code: "", ids: ids, typesById: typesById}
end function

function PorticoProductContractValidateBrowseSorts(values as dynamic, entityKinds as object) as object
    if not PorticoCoreIsArray(values) or values.Count() < 1 or values.Count() > 64 then return {ok: false, code: "invalid_product_contract_sorts"}
    directions = {asc: true, desc: true}
    ids = {}
    for each item in values
        if not PorticoCoreIsAssociativeArray(item) then return {ok: false, code: "invalid_product_contract_sort"}
        if not PorticoProductContractKeysAllowed(item, {id: true, label: true, directions: true, defaultDirection: true, applicableKinds: true, expensive: true}, 6) then return {ok: false, code: "invalid_product_contract_sort"}
        id = PorticoProductContractRequiredIdentifier(item.id, 80)
        if id = "" or ids[id] = true or PorticoProductContractRequiredText(item.label, 120) = "" then return {ok: false, code: "invalid_product_contract_sort"}
        if not PorticoProductContractStringArrayValid(item.directions, 2, 4, true, directions, true) then return {ok: false, code: "invalid_product_contract_sort"}
        if not PorticoProductContractSetContains(directions, item.defaultDirection, 4, true) or not PorticoCoreArrayContains(item.directions, item.defaultDirection) then return {ok: false, code: "invalid_product_contract_sort"}
        if not PorticoProductContractBoolean(item.expensive) then return {ok: false, code: "invalid_product_contract_sort"}
        if item.applicableKinds <> invalid and not PorticoProductContractStringArrayValid(item.applicableKinds, 128, 80, true, entityKinds, false) then return {ok: false, code: "invalid_product_contract_sort"}
        ids[id] = true
    end for
    return {ok: true, code: "", ids: ids}
end function

function PorticoProductContractValidateBrowseFields(values as dynamic, entityKinds as object, operatorTypes as object) as object
    if not PorticoCoreIsArray(values) or values.Count() < 1 or values.Count() > 128 then return {ok: false, code: "invalid_product_contract_fields"}
    valueTypes = {boolean: true, "enum": true, number: true, string: true, date: true, duration: true, "identity-set": true}
    controls = {toggle: true, select: true, "number-range": true, "date-range": true, "facet-multi-select": true, text: true}
    complexities = {quick: true, standard: true, advanced: true}
    costs = {indexed: true, "indexed-join": true}
    ids = {}
    for each item in values
        if not PorticoCoreIsAssociativeArray(item) then return {ok: false, code: "invalid_product_contract_field"}
        if not PorticoProductContractKeysAllowed(item, {id: true, label: true, valueType: true, operators: true, applicableKinds: true, caseSensitive: true, allowedValues: true, facetSource: true, controlHint: true, complexity: true, cost: true}, 11) then return {ok: false, code: "invalid_product_contract_field"}
        id = PorticoProductContractRequiredIdentifier(item.id, 80)
        if id = "" or ids[id] = true or PorticoProductContractRequiredText(item.label, 120) = "" then return {ok: false, code: "invalid_product_contract_field"}
        if not PorticoProductContractSetContains(valueTypes, item.valueType, 32, true) or not PorticoProductContractSetContains(controls, item.controlHint, 32, true) or not PorticoProductContractSetContains(complexities, item.complexity, 32, true) or not PorticoProductContractSetContains(costs, item.cost, 32, true) then return {ok: false, code: "invalid_product_contract_field"}
        if not PorticoProductContractStringArrayValid(item.operators, 32, 80, true, operatorTypes, true) then return {ok: false, code: "invalid_product_contract_field"}
        for each operatorId in item.operators
            supportedTypes = operatorTypes[operatorId]
            if not PorticoCoreIsAssociativeArray(supportedTypes) or (supportedTypes[item.valueType] <> true and supportedTypes.presence <> true) then return {ok: false, code: "invalid_product_contract_field_operator"}
        end for
        if item.applicableKinds <> invalid and not PorticoProductContractStringArrayValid(item.applicableKinds, 128, 80, true, entityKinds, false) then return {ok: false, code: "invalid_product_contract_field"}
        if item.allowedValues <> invalid and not PorticoProductContractStringArrayValid(item.allowedValues, 128, 160, false, invalid, false) then return {ok: false, code: "invalid_product_contract_field"}
        if item.caseSensitive <> invalid and not PorticoProductContractBoolean(item.caseSensitive) then return {ok: false, code: "invalid_product_contract_field"}
        if item.facetSource <> invalid and not PorticoProductContractFacetSourceValid(item.facetSource) then return {ok: false, code: "invalid_product_contract_field"}
        ids[id] = true
    end for
    return {ok: true, code: "", ids: ids}
end function

function PorticoProductContractFacetSourceValid(value as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(value) then return false
    if not PorticoProductContractKeysAllowed(value, {endpointTemplate: true, filterField: true, filterPrefix: true, valueField: true, labelField: true, countField: true}, 6) then return false
    if not PorticoProductContractApiPathValid(value.endpointTemplate, 512) then return false
    if PorticoProductContractRequiredText(value.filterField, 80) = "" or PorticoProductContractRequiredText(value.filterPrefix, 120) = "" then return false
    if PorticoProductContractRequiredText(value.valueField, 80) = "" or PorticoProductContractRequiredText(value.labelField, 80) = "" or PorticoProductContractRequiredText(value.countField, 80) = "" then return false
    return true
end function

function PorticoProductContractValidateEntitySemantics(values as dynamic, entityKinds as object, artworkRoles as object) as object
    if not PorticoCoreIsArray(values) or values.Count() < 1 or values.Count() > 128 then return {ok: false, code: "invalid_product_contract_semantics"}
    destinations = {detail: true, children: true, "series-detail": true}
    ids = {}
    for each item in values
        if not PorticoCoreIsAssociativeArray(item) then return {ok: false, code: "invalid_product_contract_semantic"}
        if not PorticoProductContractKeysAllowed(item, {id: true, container: true, playable: true, parentKinds: true, childKinds: true, childOrder: true, defaultDestination: true, primaryArtworkRole: true}, 8) then return {ok: false, code: "invalid_product_contract_semantic"}
        id = PorticoProductContractRequiredIdentifier(item.id, 80)
        if id = "" or entityKinds[id] <> true or ids[id] = true then return {ok: false, code: "invalid_product_contract_semantic"}
        if not PorticoProductContractBoolean(item.container) or not PorticoProductContractBoolean(item.playable) then return {ok: false, code: "invalid_product_contract_semantic"}
        if not PorticoProductContractStringArrayValid(item.parentKinds, 128, 80, true, entityKinds, false) then return {ok: false, code: "invalid_product_contract_semantic"}
        if not PorticoProductContractStringArrayValid(item.childKinds, 128, 80, true, entityKinds, false) then return {ok: false, code: "invalid_product_contract_semantic"}
        if not PorticoProductContractStringArrayValid(item.childOrder, 32, 80, true, invalid, false) then return {ok: false, code: "invalid_product_contract_semantic"}
        if not PorticoProductContractSetContains(destinations, item.defaultDestination, 32, true) or not PorticoProductContractSetContains(artworkRoles, item.primaryArtworkRole, 80, true) then return {ok: false, code: "invalid_product_contract_semantic"}
        ids[id] = true
    end for
    if ids.Count() <> entityKinds.Count() then return {ok: false, code: "invalid_product_contract_semantic_coverage"}
    return {ok: true, code: "", ids: ids}
end function

function PorticoProductContractValidateLibraryKinds(values as dynamic, entityKinds as object, presentationFields as object, sortIds as object) as object
    if not PorticoCoreIsArray(values) or values.Count() < 1 or values.Count() > 32 then return {ok: false, code: "invalid_product_contract_libraries"}
    views = {shelves: true, grid: true, compact: true, list: true, table: true, facets: true, timeline: true}
    directions = {asc: true, desc: true}
    ids = {}
    for each library in values
        if not PorticoCoreIsAssociativeArray(library) then return {ok: false, code: "invalid_product_contract_library"}
        if not PorticoProductContractKeysAllowed(library, {id: true, label: true, description: true, pivots: true, sortOrder: true}, 5) then return {ok: false, code: "invalid_product_contract_library"}
        id = PorticoProductContractRequiredIdentifier(library.id, 80)
        if id = "" or ids[id] = true or PorticoProductContractRequiredText(library.label, 120) = "" or PorticoProductContractRequiredText(library.description, 512) = "" then return {ok: false, code: "invalid_product_contract_library"}
        if not PorticoProductContractIntegerInRange(library.sortOrder, 0, 100000) then return {ok: false, code: "invalid_product_contract_library"}
        if not PorticoCoreIsArray(library.pivots) or library.pivots.Count() < 1 or library.pivots.Count() > 32 then return {ok: false, code: "invalid_product_contract_library"}
        pivotIds = {}
        for each pivot in library.pivots
            if not PorticoCoreIsAssociativeArray(pivot) then return {ok: false, code: "invalid_product_contract_pivot"}
            if not PorticoProductContractKeysAllowed(pivot, {id: true, label: true, entityKinds: true, defaultView: true, supportedViews: true, defaultSort: true, browseSupported: true, endpointTemplate: true, presentationFields: true}, 9) then return {ok: false, code: "invalid_product_contract_pivot"}
            pivotId = PorticoProductContractRequiredIdentifier(pivot.id, 80)
            if pivotId = "" or pivotIds[pivotId] = true or PorticoProductContractRequiredText(pivot.label, 120) = "" then return {ok: false, code: "invalid_product_contract_pivot"}
            if not PorticoProductContractBoolean(pivot.browseSupported) or not PorticoProductContractApiPathValid(pivot.endpointTemplate, 512) then return {ok: false, code: "invalid_product_contract_pivot"}
            if not PorticoProductContractStringArrayValid(pivot.entityKinds, 32, 80, true, entityKinds, true) then return {ok: false, code: "invalid_product_contract_pivot"}
            if not PorticoProductContractStringArrayValid(pivot.presentationFields, 128, 80, true, presentationFields, false) then return {ok: false, code: "invalid_product_contract_pivot"}
            if not PorticoProductContractStringArrayValid(pivot.supportedViews, 8, 16, true, views, true) or not PorticoProductContractSetContains(views, pivot.defaultView, 16, true) or not PorticoCoreArrayContains(pivot.supportedViews, pivot.defaultView) then return {ok: false, code: "invalid_product_contract_pivot"}
            if not PorticoCoreIsArray(pivot.defaultSort) or pivot.defaultSort.Count() < 1 or pivot.defaultSort.Count() > 3 then return {ok: false, code: "invalid_product_contract_pivot"}
            seenSorts = {}
            for each sort in pivot.defaultSort
                if not PorticoCoreIsAssociativeArray(sort) then return {ok: false, code: "invalid_product_contract_pivot_sort"}
                if not PorticoProductContractKeysAllowed(sort, {field: true, direction: true}, 2) then return {ok: false, code: "invalid_product_contract_pivot_sort"}
                field = PorticoProductContractRequiredIdentifier(sort.field, 80)
                if field = "" or sortIds[field] <> true or seenSorts[field] = true or not PorticoProductContractSetContains(directions, sort.direction, 4, true) then return {ok: false, code: "invalid_product_contract_pivot_sort"}
                seenSorts[field] = true
            end for
            pivotIds[pivotId] = true
        end for
        ids[id] = true
    end for
    return {ok: true, code: "", ids: ids}
end function

function PorticoProductContractValidateQueryLimits(value as dynamic) as object
    if not PorticoCoreIsAssociativeArray(value) then return {ok: false, code: "invalid_product_contract_query_limits"}
    if not PorticoProductContractKeysAllowed(value, {maximumDepth: true, maximumClauses: true, maximumBytes: true, defaultLimit: true, maximumLimit: true, cursorTtlSeconds: true}, 6) then return {ok: false, code: "invalid_product_contract_query_limits"}
    if not PorticoProductContractIntegerInRange(value.maximumDepth, 1, 8) then return {ok: false, code: "invalid_product_contract_query_limits"}
    if not PorticoProductContractIntegerInRange(value.maximumClauses, 1, 100) then return {ok: false, code: "invalid_product_contract_query_limits"}
    if not PorticoProductContractIntegerInRange(value.maximumBytes, 1024, 65536) then return {ok: false, code: "invalid_product_contract_query_limits"}
    if not PorticoProductContractIntegerInRange(value.defaultLimit, 1, 200) or not PorticoProductContractIntegerInRange(value.maximumLimit, 1, 200) then return {ok: false, code: "invalid_product_contract_query_limits"}
    if value.defaultLimit > value.maximumLimit then return {ok: false, code: "invalid_product_contract_query_limits"}
    if not PorticoProductContractIntegerInRange(value.cursorTtlSeconds, 60, 86400) then return {ok: false, code: "invalid_product_contract_query_limits"}
    return {ok: true, code: ""}
end function

function PorticoProductContractValidateSearch(value as dynamic, entityKinds as object) as object
    if not PorticoCoreIsAssociativeArray(value) or value.revision <> "v1" or value.endpoint <> "/api/search" or value.facetMode <> "none" then return {ok: false, code: "invalid_product_contract_search"}
    if not PorticoProductContractKeysAllowed(value, {revision: true, endpoint: true, groupOrder: true, groups: true, sorts: true, filters: true, facetMode: true, limits: true, cursor: true, resultSemantics: true}, 10) then return {ok: false, code: "invalid_product_contract_search"}
    if not PorticoCoreIsArray(value.groups) or value.groups.Count() < 1 or value.groups.Count() > 32 then return {ok: false, code: "invalid_product_contract_search_groups"}
    if not PorticoCoreIsArray(value.sorts) or value.sorts.Count() < 1 or value.sorts.Count() > 16 then return {ok: false, code: "invalid_product_contract_search_sorts"}
    if not PorticoCoreIsArray(value.filters) or value.filters.Count() > 16 then return {ok: false, code: "invalid_product_contract_search_filters"}
    groupIds = {}
    for each group in value.groups
        if not PorticoCoreIsAssociativeArray(group) then return {ok: false, code: "invalid_product_contract_search_group"}
        if not PorticoProductContractKeysAllowed(group, {id: true, title: true, entityKind: true, resultKinds: true, supportsLibraryScope: true, sorts: true}, 6) then return {ok: false, code: "invalid_product_contract_search_group"}
        id = PorticoProductContractRequiredIdentifier(group.id, 80)
        if id = "" or groupIds[id] = true or PorticoProductContractRequiredText(group.title, 120) = "" then return {ok: false, code: "invalid_product_contract_search_group"}
        if not PorticoProductContractSetContains(entityKinds, group.entityKind, 80, true) or not PorticoProductContractBoolean(group.supportsLibraryScope) then return {ok: false, code: "invalid_product_contract_search_group"}
        if not PorticoProductContractStringArrayValid(group.resultKinds, 32, 80, false, invalid, true) then return {ok: false, code: "invalid_product_contract_search_group"}
        groupIds[id] = true
    end for
    if not PorticoProductContractStringArrayValid(value.groupOrder, 32, 80, true, groupIds, true) or value.groupOrder.Count() <> value.groups.Count() then return {ok: false, code: "invalid_product_contract_search_order"}

    directionIds = {asc: true, desc: true}
    sortIds = {}
    for each sort in value.sorts
        if not PorticoCoreIsAssociativeArray(sort) then return {ok: false, code: "invalid_product_contract_search_sort"}
        if not PorticoProductContractKeysAllowed(sort, {id: true, label: true, directions: true, defaultDirection: true, applicableGroups: true}, 5) then return {ok: false, code: "invalid_product_contract_search_sort"}
        id = PorticoProductContractRequiredIdentifier(sort.id, 80)
        if id = "" or sortIds[id] = true or PorticoProductContractRequiredText(sort.label, 120) = "" then return {ok: false, code: "invalid_product_contract_search_sort"}
        if not PorticoProductContractStringArrayValid(sort.directions, 2, 4, true, directionIds, true) or not PorticoCoreArrayContains(sort.directions, sort.defaultDirection) then return {ok: false, code: "invalid_product_contract_search_sort"}
        if not PorticoProductContractStringArrayValid(sort.applicableGroups, 32, 80, true, groupIds, true) then return {ok: false, code: "invalid_product_contract_search_sort"}
        sortIds[id] = true
    end for
    for each group in value.groups
        if not PorticoProductContractStringArrayValid(group.sorts, 16, 80, true, sortIds, true) then return {ok: false, code: "invalid_product_contract_search_group_sorts"}
        for each sortId in group.sorts
            if not PorticoProductContractSearchSortApplies(value.sorts, sortId, group.id) then return {ok: false, code: "invalid_product_contract_search_group_sorts"}
        end for
    end for

    filterIds = {}
    filterTypes = {"enum": true, identity: true}
    for each filter in value.filters
        if not PorticoCoreIsAssociativeArray(filter) then return {ok: false, code: "invalid_product_contract_search_filter"}
        if not PorticoProductContractKeysAllowed(filter, {id: true, label: true, valueType: true, multiple: true, allowedValues: true, source: true}, 6) then return {ok: false, code: "invalid_product_contract_search_filter"}
        id = PorticoProductContractRequiredIdentifier(filter.id, 80)
        if id = "" or filterIds[id] = true or PorticoProductContractRequiredText(filter.label, 120) = "" or not PorticoProductContractSetContains(filterTypes, filter.valueType, 16, true) or not PorticoProductContractBoolean(filter.multiple) then return {ok: false, code: "invalid_product_contract_search_filter"}
        if filter.allowedValues <> invalid and not PorticoProductContractStringArrayValid(filter.allowedValues, 128, 80, false, invalid, false) then return {ok: false, code: "invalid_product_contract_search_filter"}
        if filter.source <> invalid and not PorticoProductContractSearchSourceValid(filter.source) then return {ok: false, code: "invalid_product_contract_search_filter"}
        if filter.valueType = "enum" and not PorticoCoreIsArray(filter.allowedValues) then return {ok: false, code: "invalid_product_contract_search_filter"}
        if filter.valueType = "identity" and not PorticoCoreIsAssociativeArray(filter.source) then return {ok: false, code: "invalid_product_contract_search_filter"}
        filterIds[id] = true
    end for
    limits = PorticoProductContractValidateSearchLimits(value.limits, value.groups.Count())
    if not limits.ok then return limits
    if not PorticoProductContractSearchCursorValid(value.cursor) then return {ok: false, code: "invalid_product_contract_search_cursor"}
    if not PorticoProductContractSearchResultSemanticsValid(value.resultSemantics, entityKinds, value.groups) then return {ok: false, code: "invalid_product_contract_search_semantics"}
    return {ok: true, code: "", groupIds: groupIds, sortIds: sortIds}
end function

function PorticoProductContractValidateSearchLimits(value as dynamic, groupCount as integer) as object
    if not PorticoCoreIsAssociativeArray(value) then return {ok: false, code: "invalid_product_contract_search_limits"}
    if not PorticoProductContractKeysAllowed(value, {minimumQueryLength: true, maximumQueryLength: true, defaultGroupLimit: true, maximumGroupLimit: true, quickInitialGroupLimit: true, quickMaximumGroups: true, quickMaximumItemsPerGroup: true, fullDefaultGroupLimit: true}, 8) then return {ok: false, code: "invalid_product_contract_search_limits"}
    keys = ["minimumQueryLength", "maximumQueryLength", "defaultGroupLimit", "maximumGroupLimit", "quickInitialGroupLimit", "quickMaximumGroups", "quickMaximumItemsPerGroup", "fullDefaultGroupLimit"]
    for each key in keys
        if not PorticoProductContractIntegerInRange(value[key], 1, 500) then return {ok: false, code: "invalid_product_contract_search_limits"}
    end for
    if value.minimumQueryLength > value.maximumQueryLength or value.maximumQueryLength > 512 then return {ok: false, code: "invalid_product_contract_search_limits"}
    if value.defaultGroupLimit > value.maximumGroupLimit or value.fullDefaultGroupLimit > value.maximumGroupLimit or value.quickInitialGroupLimit > value.quickMaximumItemsPerGroup then return {ok: false, code: "invalid_product_contract_search_limits"}
    if value.quickMaximumGroups > groupCount then return {ok: false, code: "invalid_product_contract_search_limits"}
    return {ok: true, code: ""}
end function

function PorticoProductContractSearchCursorValid(value as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(value) then return false
    if not PorticoProductContractKeysAllowed(value, {mode: true, opaque: true, requiresSingleGroup: true, principalBound: true, scopeFields: true, ttlSeconds: true, expiredErrorCode: true, invalidErrorCode: true}, 8) then return false
    if value.mode <> "independent-group" or value.opaque <> true or value.requiresSingleGroup <> true or value.principalBound <> true then return false
    allowed = {query: true, group: true, libraryIds: true, sort: true, direction: true}
    if not PorticoProductContractStringArrayValid(value.scopeFields, 5, 32, true, allowed, false) then return false
    if not PorticoProductContractIntegerInRange(value.ttlSeconds, 60, 86400) then return false
    return value.expiredErrorCode = "cursor_expired" and value.invalidErrorCode = "invalid_cursor"
end function

function PorticoProductContractSearchResultSemanticsValid(value as dynamic, entityKinds as object, groups as object) as boolean
    if not PorticoCoreIsAssociativeArray(value) then return false
    if not PorticoProductContractKeysAllowed(value, {destinationSource: true, hierarchySource: true, artworkRoleSource: true, kindMappings: true}, 4) then return false
    if value.destinationSource <> "entitySemantics.defaultDestination" or value.hierarchySource <> "entitySemantics.parentKinds+childKinds+childOrder" or value.artworkRoleSource <> "entitySemantics.primaryArtworkRole" then return false
    if not PorticoCoreIsArray(value.kindMappings) or value.kindMappings.Count() < 1 or value.kindMappings.Count() > 128 then return false
    resultKinds = {}
    for each mapping in value.kindMappings
        if not PorticoCoreIsAssociativeArray(mapping) then return false
        if not PorticoProductContractKeysAllowed(mapping, {resultKind: true, entityKind: true}, 2) then return false
        resultKind = PorticoProductContractRequiredText(mapping.resultKind, 80)
        if resultKind = "" or resultKinds[resultKind] = true or not PorticoProductContractSetContains(entityKinds, mapping.entityKind, 80, true) then return false
        resultKinds[resultKind] = true
    end for
    for each group in groups
        for each resultKind in group.resultKinds
            if resultKinds[resultKind] <> true then return false
        end for
    end for
    return true
end function

function PorticoProductContractSearchSourceValid(value as dynamic) as boolean
    if not PorticoCoreIsAssociativeArray(value) or not PorticoProductContractApiPathValid(value.endpoint, 512) then return false
    if not PorticoProductContractKeysAllowed(value, {endpoint: true, valueField: true, labelField: true}, 3) then return false
    return PorticoProductContractRequiredText(value.valueField, 80) <> "" and PorticoProductContractRequiredText(value.labelField, 80) <> ""
end function

function PorticoProductContractSearchSortApplies(sorts as object, sortId as string, groupId as string) as boolean
    for each sort in sorts
        if sort.id = sortId then return PorticoCoreArrayContains(sort.applicableGroups, groupId)
    end for
    return false
end function

function PorticoProductContractValidateMediaActions(values as dynamic) as object
    if not PorticoCoreIsArray(values) or values.Count() < 1 or values.Count() > 128 then return {ok: false, code: "invalid_product_contract_actions"}
    groups = {playback: true, saved: true, state: true, administration: true, feedback: true}
    surfaces = {web: true, mobile: true, television: true, "web-admin": true}
    executions = {single: true, "per-item": true, selection: true}
    results = {json: true, job: true, "playback-session": true, "download-grant": true, flow: true}
    tones = {none: true, destructive: true}
    ids = {}
    for each action in values
        if not PorticoCoreIsAssociativeArray(action) then return {ok: false, code: "invalid_product_contract_action"}
        if not PorticoProductContractKeysAllowed(action, {id: true, mutating: true, bulkSupported: true, presentation: true, command: true, confirmation: true, invalidates: true}, 7) then return {ok: false, code: "invalid_product_contract_action"}
        id = PorticoProductContractRequiredIdentifier(action.id, 120)
        if id = "" or ids[id] = true or not PorticoProductContractBoolean(action.mutating) or not PorticoProductContractBoolean(action.bulkSupported) then return {ok: false, code: "invalid_product_contract_action"}
        if not PorticoCoreIsAssociativeArray(action.presentation) or not PorticoProductContractSetContains(groups, action.presentation.group, 40, true) then return {ok: false, code: "invalid_product_contract_action_presentation"}
        if not PorticoProductContractKeysAllowed(action.presentation, {labelMessageId: true, iconId: true, group: true, priority: true, surfaces: true}, 5) then return {ok: false, code: "invalid_product_contract_action_presentation"}
        if PorticoProductContractActionToken(action.presentation.labelMessageId) = "" or PorticoProductContractActionToken(action.presentation.iconId) = "" then return {ok: false, code: "invalid_product_contract_action_presentation"}
        if not PorticoProductContractIntegerInRange(action.presentation.priority, 0, 100) or not PorticoProductContractStringArrayValid(action.presentation.surfaces, 4, 16, true, surfaces, true) then return {ok: false, code: "invalid_product_contract_action_presentation"}
        if not PorticoCoreIsAssociativeArray(action.confirmation) or not PorticoProductContractBoolean(action.confirmation.required) or not PorticoProductContractSetContains(tones, action.confirmation.tone, 16, true) then return {ok: false, code: "invalid_product_contract_action_confirmation"}
        if not PorticoProductContractKeysAllowed(action.confirmation, {required: true, tone: true}, 2) then return {ok: false, code: "invalid_product_contract_action_confirmation"}
        if action.confirmation.required = true and action.confirmation.tone <> "destructive" then return {ok: false, code: "invalid_product_contract_action_confirmation"}
        if not PorticoProductContractStringArrayValid(action.invalidates, 32, 120, true, invalid, false) then return {ok: false, code: "invalid_product_contract_action"}
        command = action.command
        if not PorticoCoreIsAssociativeArray(command) or not PorticoProductContractSetContains(executions, command.execution, 16, true) or not PorticoProductContractSetContains(results, command.resultHandling, 32, true) then return {ok: false, code: "invalid_product_contract_action_command"}
        if not PorticoProductContractKeysAllowed(command, {kind: true, execution: true, method: true, pathTemplate: true, staticBody: true, requiredInputs: true, flowId: true, resultHandling: true}, 8) then return {ok: false, code: "invalid_product_contract_action_command"}
        if command.kind = "api"
            if not PorticoProductContractMethodAllowed(command.method) or not PorticoProductContractApiPathValid(command.pathTemplate, 512) then return {ok: false, code: "invalid_product_contract_action_command"}
            if command.requiredInputs <> invalid and not PorticoProductContractStringArrayValid(command.requiredInputs, 32, 80, true, invalid, false) then return {ok: false, code: "invalid_product_contract_action_command"}
            if command.staticBody <> invalid
                budget = {remaining: 64}
                if not PorticoProductContractStaticValueValid(command.staticBody, 0, budget) then return {ok: false, code: "invalid_product_contract_action_command"}
            end if
        else if command.kind = "client-flow"
            if PorticoProductContractRequiredIdentifier(command.flowId, 120) = "" or command.resultHandling <> "flow" then return {ok: false, code: "invalid_product_contract_action_command"}
        else
            return {ok: false, code: "invalid_product_contract_action_command"}
        end if
        ids[id] = true
    end for
    return {ok: true, code: "", ids: ids}
end function

function PorticoProductContractStaticValueValid(value as dynamic, depth as integer, budget as object) as boolean
    if depth > 3 or budget.remaining < 1 then return false
    budget.remaining = budget.remaining - 1
    if PorticoCoreIsString(value) then return Len(value.ToStr()) <= 512
    if PorticoCoreIsNumber(value) then return value >= -1000000000 and value <= 1000000000
    if PorticoProductContractBoolean(value) then return true
    if PorticoCoreIsArray(value)
        if value.Count() > 16 then return false
        for each item in value
            if not PorticoProductContractStaticValueValid(item, depth + 1, budget) then return false
        end for
        return true
    end if
    if PorticoCoreIsAssociativeArray(value)
        if value.Count() > 16 then return false
        for each key in value
            if PorticoProductContractRequiredIdentifier(key, 80) = "" or not PorticoProductContractStaticValueValid(value[key], depth + 1, budget) then return false
        end for
        return true
    end if
    return false
end function

function PorticoProductContractStringArrayValid(values as dynamic, maximumItems as integer, maximumLength as integer, identifierOnly as boolean, allowed as dynamic, requireItems as boolean) as boolean
    if not PorticoCoreIsArray(values) or values.Count() > maximumItems then return false
    if requireItems and values.Count() < 1 then return false
    seen = {}
    for each value in values
        if not PorticoCoreIsString(value) then return false
        text = PorticoProductContractRequiredText(value, maximumLength)
        if text = "" or Len(value.ToStr()) > maximumLength then return false
        if identifierOnly and PorticoCoreSafeIdentifier(text, maximumLength) <> text then return false
        if seen[text] = true then return false
        if allowed <> invalid and allowed[text] <> true then return false
        seen[text] = true
    end for
    return true
end function

function PorticoProductContractStringSet(values as dynamic) as dynamic
    if not PorticoCoreIsArray(values) then return invalid
    result = {}
    for each value in values
        if not PorticoCoreIsString(value) then return invalid
        result[value.ToStr()] = true
    end for
    return result
end function

function PorticoProductContractIdentifierSet(values as dynamic, field as string, maximumItems as integer, maximumLength as integer) as dynamic
    if not PorticoCoreIsArray(values) or values.Count() > maximumItems then return invalid
    result = {}
    for each value in values
        if not PorticoCoreIsAssociativeArray(value) then return invalid
        identifier = PorticoProductContractRequiredIdentifier(value[field], maximumLength)
        if identifier = "" or result[identifier] = true then return invalid
        result[identifier] = true
    end for
    return result
end function

function PorticoProductContractRequiredText(value as dynamic, maximumLength as integer) as string
    if not PorticoCoreIsString(value) then return ""
    raw = value.ToStr()
    if Len(raw) < 1 or Len(raw) > maximumLength then return ""
    normalized = PorticoCoreSafeText(raw, maximumLength)
    if normalized <> raw.Trim() then return ""
    return normalized
end function

function PorticoProductContractRequiredIdentifier(value as dynamic, maximumLength as integer) as string
    text = PorticoProductContractRequiredText(value, maximumLength)
    if text = "" or PorticoCoreSafeIdentifier(text, maximumLength) <> text then return ""
    return text
end function

function PorticoProductContractSetContains(values as dynamic, value as dynamic, maximumLength as integer, identifierOnly as boolean) as boolean
    if not PorticoCoreIsAssociativeArray(values) then return false
    text = PorticoProductContractRequiredText(value, maximumLength)
    if text = "" then return false
    if identifierOnly and PorticoCoreSafeIdentifier(text, maximumLength) <> text then return false
    return values[text] = true
end function

function PorticoProductContractKeysAllowed(value as dynamic, allowed as dynamic, maximumKeys as integer) as boolean
    if not PorticoCoreIsAssociativeArray(value) or not PorticoCoreIsAssociativeArray(allowed) then return false
    if value.Count() > maximumKeys then return false
    for each key in value
        if allowed[key] <> true then return false
    end for
    return true
end function

function PorticoProductContractBoolean(value as dynamic) as boolean
    if value = invalid then return false
    valueType = Type(value)
    return valueType = "Boolean" or valueType = "roBoolean"
end function

function PorticoProductContractIntegerInRange(value as dynamic, minimum as integer, maximum as integer) as boolean
    if not PorticoCoreIsNumber(value) then return false
    if value < minimum or value > maximum then return false
    integerValue = Int(value)
    return value = integerValue
end function

function PorticoProductContractApiPathValid(value as dynamic, maximumLength as integer) as boolean
    path = PorticoProductContractRequiredText(value, maximumLength)
    if path = "" or Left(path, 5) <> "/api/" then return false
    if Instr(1, path, "..") > 0 or Instr(1, path, "\\") > 0 or Instr(1, path, "#") > 0 then return false
    return true
end function

function PorticoProductContractActionToken(value as dynamic) as string
    token = PorticoProductContractRequiredText(value, 120)
    if Left(token, 7) <> "action." then return ""
    if PorticoCoreSafeIdentifier(token, 120) <> token then return ""
    return token
end function

function PorticoProductContractSupportsCapability(contract as dynamic, capability as dynamic) as boolean
    if not PorticoProductContractValidate(contract).ok then return false
    identifier = PorticoCoreSafeIdentifier(capability, 120)
    if identifier = "" then return false
    return PorticoCoreArrayContains(contract.serverCapabilities, identifier)
end function

function PorticoProductContractEntitySemantic(contract as dynamic, entityKind as dynamic) as dynamic
    if not PorticoProductContractValidate(contract).ok then return invalid
    identifier = PorticoCoreSafeIdentifier(entityKind, 80)
    if identifier = "" then return invalid
    for each semantic in contract.entitySemantics
        if PorticoCoreIsAssociativeArray(semantic) and semantic.id = identifier then return semantic
    end for
    return invalid
end function

function PorticoProductContractArtworkRole(contract as dynamic, roleId as dynamic) as dynamic
    if not PorticoProductContractValidate(contract).ok then return invalid
    identifier = PorticoCoreSafeIdentifier(roleId, 80)
    if identifier = "" then return invalid
    for each role in contract.artworkRoles
        if PorticoCoreIsAssociativeArray(role) and role.id = identifier then return role
    end for
    return invalid
end function

function PorticoProductContractConsumerActions(generated as dynamic, contract as dynamic, availableActionIds as dynamic, surface as string, language as dynamic) as object
    result = []
    if not PorticoProductContractValidateGenerated(generated).ok then return result
    if not PorticoProductContractValidate(contract).ok or not PorticoProductLanguageValidate(language).ok then return result
    if surface <> "television" then return result
    if not PorticoCoreIsArray(availableActionIds) then return result

    for each action in contract.mediaActions
        if result.Count() >= 64 then exit for
        if PorticoProductContractActionAllowed(generated, action, availableActionIds, surface, language)
            presentation = action.presentation
            message = PorticoProductLanguageMessage(language, presentation.labelMessageId, "", {})
            label = message.text
            if label = "" then label = message.title
            if message.ok and label <> ""
                result.Push({
                    id: action.id,
                    label: label,
                    labelMessageId: presentation.labelMessageId,
                    iconId: presentation.iconId,
                    iconUri: PorticoProductLanguageIconUri(language, presentation.iconId),
                    group: presentation.group,
                    priority: PorticoCoreSafeInteger(presentation.priority, 0, 0, 100),
                    mutating: action.mutating = true,
                    confirmation: action.confirmation,
                    command: action.command,
                    invalidates: PorticoCoreCloneStringArray(action.invalidates, 32, 120)
                })
            end if
        end if
    end for
    PorticoProductContractSortActions(result)
    return result
end function

function PorticoProductContractActionAllowed(generated as object, action as dynamic, availableActionIds as object, surface as string, language as object) as boolean
    if not PorticoCoreIsAssociativeArray(action) then return false
    actionId = PorticoCoreSafeIdentifier(action.id, 120)
    if actionId = "" or not PorticoCoreArrayContains(availableActionIds, actionId) then return false
    policy = generated.rokuPolicy
    if not PorticoCoreArrayContains(policy.consumerActionAllowlist, actionId) then return false
    if PorticoCoreArrayContains(policy.forbiddenActionIds, actionId) then return false
    if not PorticoCoreIsAssociativeArray(action.presentation) or PorticoCoreArrayContains(policy.forbiddenActionGroups, action.presentation.group) then return false
    if not PorticoCoreArrayContains(action.presentation.surfaces, surface) then return false
    if PorticoProductLanguageKnownMessageId(language, action.presentation.labelMessageId) = "" then return false
    if PorticoProductLanguageKnownIconId(language, action.presentation.iconId) = "" then return false
    if not PorticoCoreIsAssociativeArray(action.command) or not PorticoCoreIsAssociativeArray(action.confirmation) then return false
    if action.command.kind <> "api" and action.command.kind <> "client-flow" then return false
    if action.command.kind = "api"
        if not PorticoProductContractMethodAllowed(action.command.method) then return false
        pathTemplate = PorticoCoreSafeText(action.command.pathTemplate, 512)
        if Left(pathTemplate, 5) <> "/api/" or Instr(1, pathTemplate, "..") > 0 or Instr(1, pathTemplate, "\\") > 0 then return false
    else
        if PorticoCoreSafeIdentifier(action.command.flowId, 120) = "" then return false
    end if
    return true
end function

function PorticoProductContractMethodAllowed(value as dynamic) as boolean
    method = PorticoCoreSafeText(value, 10)
    return method = "GET" or method = "POST" or method = "PATCH" or method = "DELETE"
end function

sub PorticoProductContractSortActions(actions as object)
    if actions.Count() < 2 then return
    for index = 1 to actions.Count() - 1
        candidate = actions[index]
        cursor = index - 1
        while cursor >= 0 and candidate.priority > actions[cursor].priority
            actions[cursor + 1] = actions[cursor]
            cursor = cursor - 1
        end while
        actions[cursor + 1] = candidate
    end for
end sub
