function PorticoIconResolverLoad() as object
    raw = ReadAsciiFile("pkg:/data/generated/roku-icons.v1.json")
    if raw = invalid or raw = "" then return {ok: false, code: "icon_manifest_missing", value: invalid}
    document = ParseJson(raw)
    if document = invalid or Type(document) <> "roAssociativeArray" then return {ok: false, code: "icon_manifest_invalid", value: invalid}
    if document.schemaVersion <> 1 or document.registryVersion = invalid then return {ok: false, code: "icon_manifest_incompatible", value: invalid}
    if document.semanticToMaster = invalid or Type(document.semanticToMaster) <> "roAssociativeArray" then return {ok: false, code: "icon_manifest_invalid", value: invalid}
    if document.masters = invalid or Type(document.masters) <> "roAssociativeArray" then return {ok: false, code: "icon_manifest_invalid", value: invalid}
    return {ok: true, code: "", value: document}
end function

function PorticoIconResolverUri(manifest as dynamic, semanticId as dynamic, state = "default" as string) as string
    if manifest = invalid or Type(manifest) <> "roAssociativeArray" then return PorticoIconResolverUnavailable(manifest)
    if semanticId = invalid then return PorticoIconResolverUnavailable(manifest)
    identifier = LCase(semanticId.ToStr().Trim())
    if identifier = "" or Len(identifier) > 120 then return PorticoIconResolverUnavailable(manifest)
    master = manifest.semanticToMaster[identifier]
    if master = invalid then return PorticoIconResolverUnavailable(manifest)
    safeState = LCase(state.Trim())
    if safeState <> "default" and safeState <> "focused" and safeState <> "selected" and safeState <> "disabled" and safeState <> "rail" and safeState <> "dark-background" and safeState <> "destructive" then return PorticoIconResolverUnavailable(manifest)
    masterStates = manifest.masters[master]
    if masterStates = invalid then return PorticoIconResolverUnavailable(manifest)
    entry = masterStates[safeState]
    if entry = invalid or entry.path = invalid or entry.uri = invalid then return PorticoIconResolverUnavailable(manifest)
    path = entry.path.ToStr()
    if path = "" or Right(LCase(path), 4) <> ".png" or Instr(1, path, "..") > 0 or Instr(1, path, "/") > 0 or Instr(1, path, "\") > 0 then return PorticoIconResolverUnavailable(manifest)
    uri = entry.uri.ToStr()
    packageRoot = "pkg:" + "/images/icons/generated/"
    if Left(uri, Len(packageRoot)) <> packageRoot or Right(uri, Len(path)) <> path then return PorticoIconResolverUnavailable(manifest)
    return uri
end function

function PorticoIconResolverUnavailable(manifest as dynamic) as string
#if visual_fixture
    if manifest <> invalid and manifest.semanticToMaster <> invalid and manifest.semanticToMaster["status.icon-mapping-missing"] <> invalid
        master = manifest.semanticToMaster["status.icon-mapping-missing"]
        if manifest.masters[master] <> invalid and manifest.masters[master].destructive <> invalid
            return manifest.masters[master].destructive.uri
        end if
    end if
#endif
    return ""
end function

function PorticoIconResolverPackageUri(semanticId as string, state = "default" as string) as string
    loaded = PorticoIconResolverLoad()
    if not loaded.ok then return ""
    return PorticoIconResolverUri(loaded.value, semanticId, state)
end function
