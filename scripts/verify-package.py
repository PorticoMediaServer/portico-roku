#!/usr/bin/env python3
"""Validate the compiled sideload ZIP and write distributable build evidence."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import platform
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
archive = root / "build/portico-roku.zip"
with zipfile.ZipFile(archive) as package:
    names = package.namelist()
    files = {name for name in names if not name.endswith("/")}
    assert len(names) == len(set(names)), "Duplicate ZIP entries"
    assert package.testzip() is None, "ZIP CRC failure"
    assert {"manifest", "source/Main.brs", "components/MainScene.xml"} <= files, "Missing channel entry points"
    for name in files:
        path = PurePosixPath(name)
        assert not path.is_absolute() and ".." not in path.parts and "\\" not in name, f"Unsafe ZIP path: {name}"
        assert not {"test", "tests", "node_modules", ".git"}.intersection(path.parts), f"Build-only file: {name}"
        assert name in {"manifest", "LICENSE", "THIRD_PARTY_NOTICES.txt"} or path.parts[0] in {"source", "components", "images", "fonts", "locale", "licenses"}, f"Unexpected ZIP file: {name}"
        assert path.suffix.lower() not in {".bs", ".ts", ".map", ".pkg"} and not path.name.startswith("."), f"Non-runtime file: {name}"
    manifest = package.read("manifest").decode("utf-8")
    for field in ("title", "major_version", "minor_version", "build_version"):
        assert re.search(rf"^{field}=.+$", manifest, re.M), f"Missing manifest field: {field}"
    version = json.loads((root / "package.json").read_text())["version"]
    assert re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version), "Expected numeric X.Y.Z version"
    fields = dict(re.findall(r"^(major_version|minor_version|build_version)=([0-9]+)$", manifest, re.M))
    assert tuple(int(fields[key]) for key in ("major_version", "minor_version", "build_version")) == tuple(map(int, version.split("."))), "Manifest/package version mismatch"
    ref = os.environ.get("GITHUB_REF", "")
    if ref.startswith("refs/tags/"):
        assert ref == f"refs/tags/v{version}", "Tag/package version mismatch"
    for notice in ("LICENSE", "THIRD_PARTY_NOTICES.txt", "licenses/Manrope-OFL.txt", "licenses/Lucide-LICENSE.txt", "licenses/BrighterScript-MIT.txt"):
        assert notice in files and package.read(notice) == (root / notice).read_bytes(), f"Missing or changed license: {notice}"
    for asset in re.findall(r"pkg:/([^\s]+)", manifest):
        assert asset in files, f"Missing manifest asset: {asset}"
    xml_count = 0
    for name in sorted(files):
        if not name.endswith(".xml"):
            continue
        tree = ET.fromstring(package.read(name))
        if name.startswith("components/"):
            xml_count += 1
            for script in tree.iter("script"):
                uri = script.get("uri", "")
                if uri.startswith("pkg:/"):
                    assert uri[5:] in files, f"Missing script in {name}: {uri}"
    assert any(name.startswith("fonts/") for name in files), "Missing fonts"
    assert any(name.startswith("locale/") for name in files), "Missing translations"

payload = archive.read_bytes()
digest = hashlib.sha256(payload).hexdigest()
archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n")
lock = json.loads((root / "package-lock.json").read_text())
assert lock["version"] == lock["packages"][""]["version"] == version, "Lockfile/package version mismatch"
metadata = {
    "version": version,
    "tag": os.environ.get("GITHUB_REF_NAME") if os.environ.get("GITHUB_REF_TYPE") == "tag" else None,
    "format": "unsigned-roku-sideload-zip",
    "repository": os.environ.get("GITHUB_REPOSITORY", "PorticoMediaServer/portico-roku"),
    "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
    "runUrl": f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}" if "GITHUB_RUN_ID" in os.environ else None,
    "npm": subprocess.check_output(["npm", "--version"], text=True).strip(),
    "python": platform.python_version(),
    "packageLockSha256": hashlib.sha256((root / "package-lock.json").read_bytes()).hexdigest(),
    "node": subprocess.check_output(["node", "--version"], text=True).strip(),
    "tools": {name: lock["packages"][f"node_modules/{name}"]["version"] for name in ("brighterscript", "@rokucommunity/brs", "roku-deploy")},
    "artifact": {"file": archive.name, "sha256": digest, "bytes": len(payload), "files": len(files), "components": xml_count},
    "signed": False,
    "hardwareValidated": False,
}
(root / "build/metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
print(f"Verified {len(files)} channel files and {xml_count} component XML files; SHA-256 {digest}")
